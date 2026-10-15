-- Beta gate, additive. Requires 09A, M2, and Storage. Admissions/enforcement stay OFF.
begin;
alter table private.beta_policy add column enforcement_enabled boolean not null default false;
create table private.beta_builds (
 version_code bigint primary key check(version_code>0), channel text not null default 'beta' check(channel='beta'),
 released_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz generated always as ((released_at at time zone 'UTC' + interval '90 days') at time zone 'UTC') stored,
 published_by uuid references auth.users(id)
);
create table private.beta_release_policy(id boolean primary key default true check(id),minimum_build bigint not null default 1);
insert into private.beta_release_policy(id) values(true);
create table private.beta_session_builds(session_id uuid primary key,user_id uuid not null references auth.users(id),version_code bigint not null references private.beta_builds(version_code));
create table private.beta_workspace_grants(clinic_id uuid primary key references public.clinics(id),sponsor_id uuid not null references auth.users(id),accepted_at timestamptz not null default clock_timestamp());
create table private.beta_sponsor_events(id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),sponsor_id uuid not null references auth.users(id),lost_at timestamptz not null,closed_at timestamptz);
create unique index beta_one_open_sponsor_loss on private.beta_sponsor_events(clinic_id) where closed_at is null;
create function private.beta_immutable() returns trigger language plpgsql set search_path='' as $$begin raise exception 'beta_version_is_immutable';end$$;
create trigger beta_build_immutable before update or delete on private.beta_builds for each row execute function private.beta_immutable();
create trigger beta_terms_immutable before update or delete on private.beta_terms for each row when(old.published) execute function private.beta_immutable();
do $$declare t text;begin
 foreach t in array array['beta_builds','beta_release_policy','beta_session_builds','beta_workspace_grants','beta_sponsor_events'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
 end loop;
end$$;
create function private.beta_mode(p_build bigint default null,p_clinic uuid default null,p_require_member boolean default true) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare e private.beta_enrollments;b private.beta_builds;g private.beta_workspace_grants;lost timestamptz;result jsonb;v_build bigint=p_build;sponsor private.beta_enrollments;at_time timestamptz=clock_timestamp();
begin
 if auth.uid() is null then return jsonb_build_object('mode','signed_out');end if;
 if not (select enforcement_enabled from private.beta_policy) then return jsonb_build_object('mode','internal','enforcement',false);end if;
 select * into e from private.beta_enrollments where user_id=auth.uid();
 if e.user_id is null then return jsonb_build_object('mode','not_enrolled','enforcement',true);end if;
 if v_build is null then
  begin v_build=nullif(coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb->>'x-vetdosis-build','')::bigint;exception when others then v_build=null;end;
  if v_build is null then select version_code into v_build from private.beta_session_builds where session_id=nullif(auth.jwt()->>'session_id','')::uuid and user_id=auth.uid();end if;
 end if;
 select * into b from private.beta_builds where version_code=v_build and channel='beta';
 result=private.beta_state(at_time,e.starts_at,e.expires_at,e.revoked_at,null,b.expires_at)||jsonb_build_object('enforcement',true,'server_at',at_time,'expires_at',e.expires_at,'build_expires_at',b.expires_at);
 if result->>'mode' in ('revoked','not_enrolled') then return result;end if;
 if b.version_code is null or b.released_at>at_time or v_build<(select minimum_build from private.beta_release_policy) then return result||jsonb_build_object('mode','read_export','update_required',true);end if;
 if at_time>=b.expires_at then result=result||jsonb_build_object('update_required',true);end if;
 if p_clinic is null then return result;end if;
 if p_require_member and not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then return jsonb_build_object('mode','denied');end if;
 select * into g from private.beta_workspace_grants where clinic_id=p_clinic;
 if g.clinic_id is null then return result||jsonb_build_object('mode',case when result->>'mode'='active' then 'sponsor_required' else result->>'mode' end);end if;
 select * into sponsor from private.beta_enrollments where user_id=g.sponsor_id;
 select lost_at into lost from private.beta_sponsor_events where clinic_id=p_clinic and closed_at is null;
 if sponsor.revoked_at is not null then lost=least(lost,sponsor.revoked_at);end if;
 if sponsor.expires_at<=at_time then lost=least(lost,sponsor.expires_at);end if;
 if sponsor.user_id is null then return result||jsonb_build_object('mode','sponsor_required');end if;
 if lost is not null and result->>'mode'='active' then
  result=result||jsonb_build_object('mode',case when at_time>=lost+interval '14 days' then 'read_export' else 'sponsor_grace' end,'sponsor_grace_until',lost+interval '14 days');
 end if;
 return result;
end$$;
create function public.beta_status(p_build bigint,p_clinic uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
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
 return status||jsonb_build_object('admissions_enabled',(select admissions_enabled from private.beta_policy),'terms',terms);
end$$;
create function public.beta_enroll(p_terms text,p_hash text,p_token text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_email text;t private.beta_terms;i private.beta_invites;at_time timestamptz=clock_timestamp();begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 if not (select admissions_enabled from private.beta_policy) then raise exception 'beta_admissions_closed';end if;
 -- Serialize by user first; retries do not extend access or consume another invitation.
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,9021));
 if exists(select 1 from private.beta_enrollments where user_id=auth.uid()) then return private.beta_mode();end if;
 select private.beta_normalize_email(u.email) into v_email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
 if v_email is null then raise exception 'verified_email_required';end if;
 select * into t from private.beta_terms where version=p_terms and content_hash=p_hash and published;
 if t.version is null or t.version<>(select version from private.beta_terms where published order by published_at desc,version desc limit 1) then raise exception 'beta_terms_changed';end if;
 if exists(select 1 from private.beta_email_approvals a where a.email=v_email and not enabled) then raise exception 'beta_email_revoked';end if;
 if not exists(select 1 from private.beta_email_approvals a where a.email=v_email and enabled) then
  select * into i from private.beta_invites where token_hash=encode(sha256(convert_to(coalesce(p_token,''),'UTF8')),'hex') for update;
  if i.id is null or i.email<>v_email or i.revoked_at is not null or i.consumed_at is not null or i.expires_at<=at_time then raise exception 'beta_invite_invalid';end if;
  update private.beta_invites set consumed_by=auth.uid(),consumed_at=at_time where id=i.id;
 end if;
 insert into private.beta_enrollments(user_id,email,starts_at,expires_at,invite_id,terms_version,terms_hash,accepted_at) values(auth.uid(),v_email,at_time,at_time+interval '60 days',i.id,t.version,t.content_hash,at_time);
 insert into private.beta_audit(actor_id,action,entity_id) values(auth.uid(),'enrolled',auth.uid()::text);
 return private.beta_mode();
end$$;
create function public.beta_sponsor_accept(p_clinic uuid) returns void language plpgsql security definer set search_path='' as $$
declare state jsonb;begin
 state=private.beta_mode();
 if state->>'mode' not in ('active','internal') or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() and role='admin') then raise exception 'beta_sponsor_denied';end if;
 insert into private.beta_workspace_grants(clinic_id,sponsor_id) values(p_clinic,auth.uid()) on conflict(clinic_id) do update set sponsor_id=excluded.sponsor_id,accepted_at=clock_timestamp();
 update private.beta_sponsor_events set closed_at=clock_timestamp() where clinic_id=p_clinic and closed_at is null;
 insert into private.beta_audit(actor_id,action,entity_id) values(auth.uid(),'sponsor_accepted',p_clinic::text);
end$$;
create function private.beta_sponsor_lost() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='DELETE' or new.role<>'admin' then
  insert into private.beta_sponsor_events(clinic_id,sponsor_id,lost_at) select clinic_id,sponsor_id,clock_timestamp() from private.beta_workspace_grants where clinic_id=old.clinic_id and sponsor_id=old.user_id on conflict(clinic_id) where closed_at is null do nothing;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end$$;
create trigger beta_sponsor_membership_loss after delete or update of role on public.clinic_members for each row execute function private.beta_sponsor_lost();
create function public.beta_access_check(p_write boolean default false,p_clinic uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$declare status jsonb;begin
 status=private.beta_mode(null,p_clinic);
 if status->>'mode' not in ('internal','active','sponsor_grace','read_export') then raise exception 'beta_access_denied';end if;
 if p_write and status->>'mode'='read_export' then raise exception 'beta_read_export_only';end if;
 return status;
end$$;
create function private.beta_read_allowed() returns boolean language sql stable security definer set search_path='' as $$select not(select enforcement_enabled from private.beta_policy) or private.beta_mode()->>'mode' in ('active','sponsor_grace','read_export')$$;
create function private.beta_write_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare item jsonb;scope uuid;state jsonb;begin
 if not (select enforcement_enabled from private.beta_policy) then if tg_op='DELETE' then return old;end if;return new;end if;
 -- Trusted service jobs remain server-only. A security-definer RPC does not change the request role GUC.
 if auth.uid() is null and (coalesce(auth.jwt()->>'role','')='service_role' or current_setting('role',true) in ('none','postgres','service_role')) then if tg_op='DELETE' then return old;end if;return new;end if;
 item=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 if tg_table_schema='public' and tg_table_name='audit_log' and item->>'action'='operational_backup_exported' and item->>'actor_id'=auth.uid()::text then perform public.beta_access_check(false);return new;end if;
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
-- Platform identity is enrolled out-of-app and can never join a clinic.
create function private.beta_separate_platform_account() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from private.platform_admins where user_id=new.user_id and enabled) then raise exception 'platform_account_must_be_separate';end if;return new;
end$$;
create trigger beta_platform_separation before insert or update on public.clinic_members for each row execute function private.beta_separate_platform_account();
create function private.beta_bootstrap_admin(p_email text) returns boolean language plpgsql security definer set search_path='' as $$declare target uuid;begin
 select id into target from auth.users where lower(btrim(email))=private.beta_normalize_email(p_email) and email_confirmed_at is not null;
 if target is null then return false;end if;
 if exists(select 1 from public.clinic_members where user_id=target) then raise exception 'platform_account_must_be_separate';end if;
 insert into private.platform_admins(user_id) values(target) on conflict(user_id) do nothing;
 insert into private.beta_audit(action,entity_id) values('platform_admin_bootstrap',target::text);
 return true;
end$$;
create function private.beta_publish_build(p_version bigint) returns void language plpgsql security definer set search_path='' as $$begin
 insert into private.beta_builds(version_code) values(p_version) on conflict(version_code) do nothing;
end$$;
revoke all on function private.beta_separate_platform_account(),private.beta_bootstrap_admin(text),private.beta_publish_build(bigint) from public,anon,authenticated;
-- PostgREST hook covers direct reads and every RPC, including SECURITY DEFINER reads.
create function private.beta_request_guard() returns void language plpgsql stable security definer set search_path='' as $$
declare path text=current_setting('request.path',true);begin
 if not(select enforcement_enabled from private.beta_policy) then return;end if;
 if auth.uid() is null and auth.jwt()->>'role'='service_role' then return;end if;
 if path in ('/rpc/beta_status','/rpc/beta_enroll','/rpc/beta_sponsor_accept','/rpc/beta_access_check') or path like '/rpc/platform_beta_%' then return;end if;
 perform public.beta_access_check(false);
end$$;
create function public.beta_request_guard() returns void language sql stable security definer set search_path='' as $$select private.beta_request_guard()$$;
revoke all on function public.beta_request_guard() from public;
grant execute on function public.beta_request_guard() to authenticated,anon;
-- Install table guards only on application tables, excluding extension-managed objects.
-- Future schema migrations must re-run this installer and the coverage check before release.
create function private.beta_install_guards() returns void language plpgsql security definer set search_path='' as $$declare t record;begin
 for t in select c.oid,n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and (n.nspname='public' or (n.nspname='private' and c.relname not like 'beta_%' and c.relname<>'platform_admins') or (n.nspname='storage' and c.relname='objects')) and not exists(select 1 from pg_depend d where d.objid=c.oid and d.deptype='e') loop
  execute format('drop trigger if exists beta_write_guard on %I.%I',t.nspname,t.relname);
  execute format('create trigger beta_write_guard before insert or update or delete on %I.%I for each row execute function private.beta_write_guard()',t.nspname,t.relname);
 end loop;
end$$;
select private.beta_install_guards();
create policy beta_storage_read on storage.objects as restrictive for select to authenticated using(private.beta_read_allowed());
-- Bootstrap hook registration is separate: do not change authenticator configuration
-- until the remote preflight confirms its existing hook is empty/compatible.
revoke all on function private.beta_mode(bigint,uuid,boolean),private.beta_immutable(),private.beta_sponsor_lost(),private.beta_write_guard(),private.beta_install_guards() from public,anon,authenticated;
revoke all on function private.beta_request_guard(),private.beta_read_allowed() from public;
grant execute on function private.beta_request_guard(),private.beta_read_allowed() to authenticated,anon;
revoke all on function public.beta_status(bigint,uuid),public.beta_enroll(text,text,text),public.beta_sponsor_accept(uuid),public.beta_access_check(boolean,uuid) from public,anon;
grant execute on function public.beta_status(bigint,uuid),public.beta_enroll(text,text,text),public.beta_sponsor_accept(uuid),public.beta_access_check(boolean,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
