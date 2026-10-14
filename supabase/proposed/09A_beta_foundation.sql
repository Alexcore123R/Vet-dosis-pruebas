-- PROPOSED / LOCAL ONLY. Not wired into the current application or its write paths.
-- Never treats this foundation as a complete beta gate. No destructive retention job.
begin;
create table private.platform_admins (
 user_id uuid primary key references auth.users(id), enabled boolean not null default true,
 created_at timestamptz not null default clock_timestamp()
);
create table private.beta_policy (
 id boolean primary key default true check(id), admissions_enabled boolean not null default false,
 duration_days integer not null default 60 check(duration_days=60),
 warning_days integer not null default 7 check(warning_days=7),
 sponsor_grace_days integer not null default 14 check(sponsor_grace_days=14),
 build_days integer not null default 90 check(build_days=90)
);
insert into private.beta_policy(id) values(true);
create table private.beta_email_approvals (
 email text primary key, enabled boolean not null, changed_by uuid not null references auth.users(id),
 changed_at timestamptz not null default clock_timestamp(), reason text not null check(length(btrim(reason)) between 5 and 1000)
);
create table private.beta_invites (
 id uuid primary key default gen_random_uuid(), email text not null, token_hash text not null unique,
 expires_at timestamptz not null, consumed_by uuid references auth.users(id), consumed_at timestamptz,
 revoked_at timestamptz, created_by uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),
 check((consumed_by is null)=(consumed_at is null))
);
create table private.beta_enrollments (
 user_id uuid primary key references auth.users(id), email text not null,
 starts_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null,
 revoked_at timestamptz, invite_id uuid references private.beta_invites(id),
 terms_version text not null, terms_hash text not null, accepted_at timestamptz not null,
 check(expires_at>starts_at)
);
create table private.beta_terms (
 version text primary key, content text not null, content_hash text not null,
 published boolean not null default false, published_at timestamptz
);
create table private.beta_audit (
 id uuid primary key default gen_random_uuid(), actor_id uuid references auth.users(id),
 action text not null, entity_id text not null, server_at timestamptz not null default clock_timestamp(),
 reason text
);
-- No table grants; no policies allowing direct client access, even for platform admins.
do $$declare t text;begin
 foreach t in array array['platform_admins','beta_policy','beta_email_approvals','beta_invites','beta_enrollments','beta_terms','beta_audit'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
 end loop;
end$$;
create function private.beta_normalize_email(value text) returns text language plpgsql immutable set search_path='' as $$
declare email text=lower(btrim(value));begin
 if email is null or length(email)>254 or email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'invalid_email';end if;
 -- Keep +tags and dots: provider-specific rewriting would conflate identities.
 return email;
end$$;
create function private.require_platform_admin() returns void language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or not exists(select 1 from private.platform_admins where user_id=auth.uid() and enabled)
 or coalesce(auth.jwt()->>'aal','')<>'aal2'
 or exists(select 1 from public.clinic_members where user_id=auth.uid()) then raise exception 'platform_admin_mfa_required';end if;
end$$;
create function public.platform_beta_set_email(p_email text,p_enabled boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare v_email text;begin
 perform private.require_platform_admin();v_email=private.beta_normalize_email(p_email);
 if p_reason is null or length(btrim(p_reason)) not between 5 and 1000 then raise exception 'reason_required';end if;
 insert into private.beta_email_approvals(email,enabled,changed_by,reason) values(v_email,p_enabled,auth.uid(),p_reason)
 on conflict(email) do update set enabled=excluded.enabled,changed_by=auth.uid(),changed_at=clock_timestamp(),reason=excluded.reason;
 insert into private.beta_audit(actor_id,action,entity_id,reason) values(auth.uid(),case when p_enabled then 'email_approved' else 'email_revoked' end,v_email,p_reason);
 -- Revocation removes access for already enrolled users too; it never deletes their records.
 if not p_enabled then update private.beta_enrollments set revoked_at=coalesce(revoked_at,clock_timestamp()) where beta_enrollments.email=v_email;end if;
end$$;
create function public.platform_beta_create_invite(p_email text,p_hours integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_email text;token text;created_id uuid;begin
 perform private.require_platform_admin();v_email=private.beta_normalize_email(p_email);
 if p_hours is null or p_hours<1 or p_hours>168 then raise exception 'invite_lifetime_invalid';end if;
 token=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 insert into private.beta_invites(email,token_hash,expires_at,created_by) values(v_email,encode(sha256(convert_to(token,'UTF8')),'hex'),clock_timestamp()+make_interval(hours=>p_hours),auth.uid()) returning id into created_id;
 insert into private.beta_audit(actor_id,action,entity_id) values(auth.uid(),'invite_created',created_id::text);
 -- Returned exactly once to the administrator. Do not log request responses or tokens.
 return jsonb_build_object('id',created_id,'token',token,'email',v_email);
end$$;
create function public.platform_beta_revoke_invite(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_platform_admin();
 if p_reason is null or length(btrim(p_reason)) not between 5 and 1000 then raise exception 'reason_required';end if;
 update private.beta_invites set revoked_at=coalesce(revoked_at,clock_timestamp()) where id=p_id;
 if not found then raise exception 'invite_not_found';end if;
 update private.beta_enrollments set revoked_at=coalesce(revoked_at,clock_timestamp()) where invite_id=p_id;
 insert into private.beta_audit(actor_id,action,entity_id,reason) values(auth.uid(),'invite_revoked',p_id::text,p_reason);
end$$;
create function public.platform_beta_list() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform private.require_platform_admin();
 return jsonb_build_object('approvals',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from private.beta_email_approvals a),
 'invites',(select coalesce(jsonb_agg(to_jsonb(i)-'token_hash'),'[]') from private.beta_invites i),
 'enrollments',(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from private.beta_enrollments e));
end$$;
-- Pure private decision primitive, for boundary tests and future gate integration.
-- Explicit revocation or enrollment expiry wins over sponsor grace; grace is not a renewed beta.
create function private.beta_state(p_at timestamptz,p_start timestamptz,p_end timestamptz,p_revoked timestamptz,p_sponsor_lost timestamptz,p_build_expires timestamptz) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('mode',case
 when p_revoked is not null then 'revoked'
 when p_start is null or p_end is null or p_at<p_start then 'not_enrolled'
 when p_at>=p_end or (p_build_expires is not null and p_at>=p_build_expires) then 'read_export'
 when p_sponsor_lost is not null and p_at>=p_sponsor_lost+interval '14 days' then 'read_export'
 when p_sponsor_lost is not null then 'sponsor_grace'
 else 'active' end,
 'expiry_warning',p_end is not null and p_at>=p_end-interval '7 days' and p_at<p_end);
$$;
-- Enrolment endpoint intentionally NOT provided in 09A: terms, grants and complete gate
-- coverage must be reviewed and tested before admissions can open. Default remains disabled.
revoke all on function private.beta_normalize_email(text),private.require_platform_admin(),private.beta_state(timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz) from public,anon,authenticated;
revoke all on function public.platform_beta_set_email(text,boolean,text),public.platform_beta_create_invite(text,integer),public.platform_beta_revoke_invite(uuid,text),public.platform_beta_list() from public,anon;
grant execute on function public.platform_beta_set_email(text,boolean,text),public.platform_beta_create_invite(text,integer),public.platform_beta_revoke_invite(uuid,text),public.platform_beta_list() to authenticated;
commit;
