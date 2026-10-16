-- Version shown = version accepted; no legal text published or beta flags changed.
begin;
create unique index beta_terms_version_hash on private.beta_terms(version,content_hash);
create table public.terms_acceptances (
 user_id uuid not null references auth.users(id),terms_version text not null,terms_hash text not null,
 accepted_at timestamptz not null default clock_timestamp(),
 origin text not null check(origin in ('explicit','beta_enrollment_migration')),
 primary key(user_id,terms_version),foreign key(terms_version,terms_hash) references private.beta_terms(version,content_hash)
);
alter table public.terms_acceptances enable row level security;
revoke all on public.terms_acceptances from public,anon,authenticated;
grant select on public.terms_acceptances to authenticated;
create policy own_terms_acceptances on public.terms_acceptances for select to authenticated using(user_id=auth.uid());
-- Preserve only proven historical acceptances; unresolved legacy text requires review.
do $$begin
 if exists(select 1 from private.beta_enrollments e where not exists(select 1 from private.beta_terms t where t.version=e.terms_version and t.content_hash=e.terms_hash and t.published and t.content_hash=encode(sha256(convert_to(t.content,'UTF8')),'hex'))) then
 raise exception 'legacy_terms_acceptances_require_review';end if;
end$$;
insert into public.terms_acceptances(user_id,terms_version,terms_hash,accepted_at,origin)
select user_id,terms_version,terms_hash,accepted_at,'beta_enrollment_migration' from private.beta_enrollments;
create trigger immutable_terms_acceptance before update or delete on public.terms_acceptances for each row execute function private.beta_immutable();
create function private.beta_latest_terms() returns private.beta_terms language sql stable security definer set search_path='' as $$
 select t from private.beta_terms t where t.published order by t.published_at desc,t.version desc limit 1;
$$;
create function private.beta_terms_pending() returns boolean language sql stable security definer set search_path='' as $$
 select (select enforcement_enabled from private.beta_policy) and exists(select 1 from private.beta_enrollments where user_id=auth.uid())
 and exists(select 1 from private.beta_terms t where t.version=(private.beta_latest_terms()).version
 and not exists(select 1 from public.terms_acceptances a where a.user_id=auth.uid() and a.terms_version=t.version and a.terms_hash=t.content_hash));
$$;
create function private.beta_record_acceptance(p_version text,p_hash text) returns void language plpgsql security definer set search_path='' as $$
declare t private.beta_terms;begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 -- Publishers lock the same table. A publication cannot race the final validation.
 lock table private.beta_terms in share mode;
 select * into t from private.beta_latest_terms();
 if t.version is null or t.version is distinct from p_version or t.content_hash is distinct from p_hash or t.content_hash<>encode(sha256(convert_to(t.content,'UTF8')),'hex') then raise exception 'beta_terms_changed';end if;
 insert into public.terms_acceptances(user_id,terms_version,terms_hash,origin) values(auth.uid(),t.version,t.content_hash,'explicit') on conflict(user_id,terms_version) do nothing;
 if found then insert into private.beta_audit(actor_id,action,entity_id) values(auth.uid(),'terms_accepted',t.version);end if;
end$$;
create function public.beta_accept_terms(p_terms text,p_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare e private.beta_enrollments;begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,9021));
 select * into e from private.beta_enrollments where user_id=auth.uid() for update;
 if e.user_id is null then raise exception 'beta_enrollment_required';end if;
 if e.revoked_at is not null then raise exception 'beta_access_revoked';end if;
 if not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null and lower(btrim(email))=e.email) then raise exception 'verified_enrollment_email_required';end if;
 perform private.beta_record_acceptance(p_terms,p_hash);
 return jsonb_build_object('version',p_terms,'accepted',true,'expires_at',e.expires_at);
end$$;
create or replace function public.beta_enroll(p_terms text,p_hash text,p_token text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_email text;t private.beta_terms;i private.beta_invites;at_time timestamptz=clock_timestamp();begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 if not (select admissions_enabled from private.beta_policy) then raise exception 'beta_admissions_closed';end if;
 -- Serialize by user first; retries do not extend access or consume another invitation.
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,9021));
 if exists(select 1 from private.beta_enrollments where user_id=auth.uid()) then perform public.beta_accept_terms(p_terms,p_hash);return private.beta_mode();end if;
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
 perform private.beta_record_acceptance(p_terms,p_hash);
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
 select jsonb_build_object('version',version,'content',content,'hash',content_hash) into terms from private.beta_terms where published order by published_at desc,version desc limit 1;
 return status||jsonb_build_object('admissions_enabled',(select admissions_enabled from private.beta_policy),'terms',terms,'terms_acceptance_required',private.beta_terms_pending());
end$$;
create or replace function public.beta_access_check(p_write boolean default false,p_clinic uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$declare status jsonb;begin
 status=private.beta_mode(null,p_clinic);
 if status->>'mode' not in ('internal','active','sponsor_grace','read_export') then raise exception 'beta_access_denied';end if;
 if p_write and status->>'mode'='read_export' then raise exception 'beta_read_export_only';end if;
 if p_write and private.beta_terms_pending() then raise exception 'terms_acceptance_required';end if;
 return status;
end$$;
create or replace function private.beta_request_guard() returns void language plpgsql stable security definer set search_path='' as $$
declare path text=current_setting('request.path',true);begin
 if not(select enforcement_enabled from private.beta_policy) then return;end if;
 if auth.uid() is null and auth.jwt()->>'role'='service_role' then return;end if;
 if path in ('/rpc/beta_status','/rpc/beta_enroll','/rpc/beta_accept_terms','/rpc/beta_sponsor_accept','/rpc/beta_access_check') or path like '/rpc/platform_beta_%' then return;end if;
 perform public.beta_access_check(false);
end$$;

-- Acceptance is a security/legal action, allowed in read/export mode; its own RPC checks
-- identity, enrollment and exact text. It never extends the trial or re-enables writes.
create or replace function private.beta_write_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare item jsonb;scope uuid;state jsonb;begin
 if not (select enforcement_enabled from private.beta_policy) then if tg_op='DELETE' then return old;end if;return new;end if;
 -- Trusted service jobs remain server-only. A security-definer RPC does not change the request role GUC.
 if auth.uid() is null and (coalesce(auth.jwt()->>'role','')='service_role' or current_setting('role',true) in ('none','postgres','service_role')) then if tg_op='DELETE' then return old;end if;return new;end if;
 item=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 if tg_table_schema='public' and tg_table_name='audit_log' and item->>'action'='operational_backup_exported' and item->>'actor_id'=auth.uid()::text then perform public.beta_access_check(false);return new;end if;
 -- Narrow legal-consent exception; direct client INSERT remains revoked.
 if tg_table_schema='public' and tg_table_name='terms_acceptances' and tg_op='INSERT'
 and item->>'user_id'=auth.uid()::text and item->>'origin'='explicit'
 and exists(select 1 from private.beta_terms t where t.version=item->>'terms_version' and t.content_hash=item->>'terms_hash' and t.published and t.version=(private.beta_latest_terms()).version)
 then return new;end if;
 state=public.beta_access_check(true);
 begin scope=nullif(item->>'clinic_id','')::uuid;exception when invalid_text_representation then scope=null;end;
 if tg_table_schema='public' and tg_table_name='clinics' then scope=(item->>'id')::uuid;end if;
 if tg_table_schema='storage' and item->>'bucket_id'='inventory-photos' then begin scope=split_part(item->>'name','/',1)::uuid;exception when others then scope=null;end;end if;
 if scope is not null and tg_table_name not in ('audit_log','workspace_usage') then
  -- Clinic creation and its creator's initial admin membership are a bounded bootstrap;
  -- recording clinic data subsequently requires explicit sponsor acceptance.
  if not(tg_op='INSERT' and ((tg_table_name='clinics' and item->>'created_by'=auth.uid()::text) or (tg_table_name='clinic_members' and item->>'user_id'=auth.uid()::text and item->>'role'='admin' and exists(select 1 from public.clinics where id=scope and created_by=auth.uid())))) then
   state=private.beta_mode(null,scope,not(tg_table_name='clinic_members' and tg_op='INSERT'));
   if state->>'mode' not in ('active','sponsor_grace','internal') then raise exception 'beta_workspace_read_only';end if;
  end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end$$;
select private.beta_install_guards();
revoke all on function private.beta_latest_terms(),private.beta_terms_pending(),private.beta_record_acceptance(text,text) from public,anon,authenticated;
revoke all on function public.beta_accept_terms(text,text) from public,anon;
grant execute on function public.beta_accept_terms(text,text) to authenticated;
notify pgrst,'reload schema';
commit;
