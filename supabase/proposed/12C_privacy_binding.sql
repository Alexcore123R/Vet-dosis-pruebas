-- PROPOSED: review schema before remote application. Does not publish or open beta.
begin;
do $$begin
 if not (select not admissions_enabled and not enforcement_enabled from private.beta_policy) then raise exception 'beta_must_be_closed';end if;
end$$;
create table private.beta_privacy_notices (
 version text primary key,content text not null,content_hash text not null,
 published boolean not null default false,published_at timestamptz,
 unique(version,content_hash),
 check(content_hash=encode(sha256(convert_to(content,'UTF8')),'hex')),
 check(not published or published_at is not null)
);
alter table private.beta_privacy_notices enable row level security;
revoke all on private.beta_privacy_notices from public,anon,authenticated;
create trigger immutable_published_privacy before update or delete on private.beta_privacy_notices
 for each row when(old.published) execute function private.beta_immutable();
alter table private.beta_terms add column privacy_version text references private.beta_privacy_notices(version);
alter table public.terms_acceptances
 add column privacy_version text,
 add column privacy_hash text,
 add constraint privacy_pair check((privacy_version is null)=(privacy_hash is null)),
 add constraint accepted_privacy foreign key(privacy_version,privacy_hash) references private.beta_privacy_notices(version,content_hash);
-- New columns on historical acceptances stay NULL; no consent is fabricated.
create function private.beta_validate_privacy_binding() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.published and new.privacy_version is not null and not exists(select 1 from private.beta_privacy_notices where version=new.privacy_version and published) then raise exception 'published_privacy_required';end if;
 return new;
end$$;
create trigger published_terms_privacy before insert or update on private.beta_terms for each row execute function private.beta_validate_privacy_binding();
drop function public.beta_enroll(text,text,text);
drop function public.beta_accept_terms(text,text);
drop function private.beta_record_acceptance(text,text);
create function private.beta_record_acceptance(p_version text,p_hash text,p_privacy_version text default null,p_privacy_hash text default null) returns void language plpgsql security definer set search_path='' as $$
declare t private.beta_terms;n private.beta_privacy_notices;begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 -- Publishers lock the same table. A publication cannot race the final validation.
 lock table private.beta_terms in share mode;
 select * into t from private.beta_latest_terms();
 if t.version is null or t.version is distinct from p_version or t.content_hash is distinct from p_hash or t.content_hash<>encode(sha256(convert_to(t.content,'UTF8')),'hex') then raise exception 'beta_terms_changed';end if;
 if t.privacy_version is not null then
  lock table private.beta_privacy_notices in share mode;
  select * into n from private.beta_privacy_notices where version=t.privacy_version and published;
  if n.version is null or n.version is distinct from p_privacy_version or n.content_hash is distinct from p_privacy_hash
  or n.content_hash<>encode(sha256(convert_to(n.content,'UTF8')),'hex') then raise exception 'beta_privacy_changed';end if;
 elsif p_privacy_version is not null or p_privacy_hash is not null then raise exception 'beta_privacy_changed';end if;
 insert into public.terms_acceptances(user_id,terms_version,terms_hash,origin,privacy_version,privacy_hash) values(auth.uid(),t.version,t.content_hash,'explicit',n.version,n.content_hash) on conflict(user_id,terms_version) do nothing;
 if found then insert into private.beta_audit(actor_id,action,entity_id) values(auth.uid(),'terms_accepted',t.version);end if;
end$$;
create function public.beta_accept_terms(p_terms text,p_hash text,p_privacy_version text default null,p_privacy_hash text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare e private.beta_enrollments;begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,9021));
 select * into e from private.beta_enrollments where user_id=auth.uid() for update;
 if e.user_id is null then raise exception 'beta_enrollment_required';end if;
 if e.revoked_at is not null then raise exception 'beta_access_revoked';end if;
 if not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null and lower(btrim(email))=e.email) then raise exception 'verified_enrollment_email_required';end if;
 perform private.beta_record_acceptance(p_terms,p_hash,p_privacy_version,p_privacy_hash);
 return jsonb_build_object('version',p_terms,'accepted',true,'expires_at',e.expires_at);
end$$;
create or replace function public.beta_enroll(p_terms text,p_hash text,p_token text default null,p_privacy_version text default null,p_privacy_hash text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_email text;t private.beta_terms;i private.beta_invites;at_time timestamptz=clock_timestamp();begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 if not (select admissions_enabled from private.beta_policy) then raise exception 'beta_admissions_closed';end if;
 -- Serialize by user first; retries do not extend access or consume another invitation.
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,9021));
 if exists(select 1 from private.beta_enrollments where user_id=auth.uid()) then perform public.beta_accept_terms(p_terms,p_hash,p_privacy_version,p_privacy_hash);return private.beta_mode();end if;
 select private.beta_normalize_email(u.email) into v_email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
 if v_email is null then raise exception 'verified_email_required';end if;
 lock table private.beta_terms in share mode;
 select * into t from private.beta_terms where version=p_terms and content_hash=p_hash and published;
 if t.version is null or t.version<>(select version from private.beta_terms where published order by published_at desc,version desc limit 1) then raise exception 'beta_terms_changed';end if;
 if exists(select 1 from private.beta_email_approvals a where a.email=v_email and not enabled) then raise exception 'beta_email_revoked';end if;
 if not exists(select 1 from private.beta_email_approvals a where a.email=v_email and enabled) then
  select * into i from private.beta_invites where token_hash=encode(sha256(convert_to(coalesce(p_token,''),'UTF8')),'hex') for update;
  if i.id is null or i.email<>v_email or i.revoked_at is not null or i.consumed_at is not null or i.expires_at<=at_time then raise exception 'beta_invite_invalid';end if;
  update private.beta_invites set consumed_by=auth.uid(),consumed_at=at_time where id=i.id;
 end if;
 insert into private.beta_enrollments(user_id,email,starts_at,expires_at,invite_id,terms_version,terms_hash,accepted_at) values(auth.uid(),v_email,at_time,at_time+interval '60 days',i.id,t.version,t.content_hash,at_time);
 perform private.beta_record_acceptance(p_terms,p_hash,p_privacy_version,p_privacy_hash);
 insert into private.beta_audit(actor_id,action,entity_id) values(auth.uid(),'enrolled',auth.uid()::text);
 return private.beta_mode();
end$$;
create or replace function public.beta_status(p_build bigint,p_clinic uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare status jsonb;session uuid;terms jsonb;begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 if exists(select 1 from private.platform_admins where user_id=auth.uid() and enabled) and not exists(select 1 from public.clinic_members where user_id=auth.uid()) then
  return jsonb_build_object('mode','platform_admin','mfa_ready',auth.jwt()->>'aal'='aal2');
 end if;
 begin session=nullif(auth.jwt()->>'session_id','')::uuid;exception when invalid_text_representation then session=null;end;
 if session is not null and exists(select 1 from private.beta_builds where version_code=p_build) then
  insert into private.beta_session_builds values(session,auth.uid(),p_build) on conflict(session_id) do update set version_code=excluded.version_code where beta_session_builds.user_id=auth.uid();
 end if;
 status=private.beta_mode(p_build,p_clinic);
 select jsonb_build_object('version',version,'content',content,'hash',content_hash,'privacy',(select jsonb_build_object('version',n.version,'content',n.content,'hash',n.content_hash) from private.beta_privacy_notices n where n.version=beta_terms.privacy_version and n.published)) into terms from private.beta_terms where published order by published_at desc,version desc limit 1;
 return status||jsonb_build_object('admissions_enabled',(select admissions_enabled from private.beta_policy),'terms',terms,'terms_acceptance_required',private.beta_terms_pending());
end$$;

revoke all on function private.beta_record_acceptance(text,text,text,text),private.beta_validate_privacy_binding() from public,anon,authenticated;
revoke all on function public.beta_accept_terms(text,text,text,text),public.beta_enroll(text,text,text,text,text) from public,anon;
grant execute on function public.beta_accept_terms(text,text,text,text),public.beta_enroll(text,text,text,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
