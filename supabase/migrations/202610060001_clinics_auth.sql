-- M2: roles and clinic membership are authoritative on the server.
begin;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;
create type public.clinic_role as enum ('admin', 'mvz', 'auxiliar', 'recepcion', 'estilista');
create table public.clinics (
 id uuid primary key default gen_random_uuid(),
 name text not null check (char_length(btrim(name)) between 2 and 120),
 created_at timestamptz not null default now()
);
create table public.clinic_memberships (
 clinic_id uuid not null references public.clinics(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role public.clinic_role not null,
 created_at timestamptz not null default now(),
 primary key (clinic_id, user_id)
);
create table public.clinic_invitations (
 id uuid primary key default gen_random_uuid(),
 clinic_id uuid not null references public.clinics(id) on delete cascade,
 email text not null check (email = lower(btrim(email)) and position('@' in email) > 1),
 role public.clinic_role not null,
 token_hash text not null unique,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now() + interval '7 days',
 accepted_by uuid references auth.users(id),
 accepted_at timestamptz,
 revoked_at timestamptz
);
create table public.audit_log (
 id bigint generated always as identity primary key,
 clinic_id uuid not null references public.clinics(id) on delete cascade,
 actor_id uuid,
 action text not null,
 entity_id text not null,
 details jsonb not null default '{}'::jsonb,
 occurred_at timestamptz not null default now()
);
create index membership_user on public.clinic_memberships(user_id);
create index audit_clinic_time on public.audit_log(clinic_id, occurred_at desc);

create function private.has_clinic_role(target uuid, allowed public.clinic_role[] default null)
returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.clinic_memberships m
 where m.clinic_id = target and m.user_id = auth.uid()
 and (allowed is null or m.role = any(allowed)));
$$;
revoke all on function private.has_clinic_role(uuid, public.clinic_role[]) from public;
grant execute on function private.has_clinic_role(uuid, public.clinic_role[]) to authenticated;

alter table public.clinics enable row level security;
alter table public.clinic_memberships enable row level security;
alter table public.clinic_invitations enable row level security;
alter table public.audit_log enable row level security;
revoke all on public.clinics, public.clinic_memberships, public.clinic_invitations, public.audit_log from anon, authenticated;
grant select on public.clinics, public.clinic_memberships, public.audit_log to authenticated;
grant select (id, clinic_id, email, role, created_at, expires_at, accepted_at, revoked_at)
 on public.clinic_invitations to authenticated;
create policy invitations_read on public.clinic_invitations for select to authenticated
 using (private.has_clinic_role(clinic_id, array['admin']::public.clinic_role[]));
create policy clinics_read on public.clinics for select to authenticated
 using (private.has_clinic_role(id));
create policy memberships_read on public.clinic_memberships for select to authenticated
 using (user_id = auth.uid() or private.has_clinic_role(clinic_id, array['admin']::public.clinic_role[]));
create policy audit_read on public.audit_log for select to authenticated
 using (private.has_clinic_role(clinic_id, array['admin']::public.clinic_role[]));
-- No client writes to role, invitations or audit tables. Only bounded RPCs.

create function private.audit_membership() returns trigger
 language plpgsql security definer set search_path = '' as $$
begin
 insert into public.audit_log(clinic_id, actor_id, action, entity_id, details)
 values (new.clinic_id, auth.uid(), case when tg_op = 'INSERT' then 'member_joined' else 'role_changed' end,
 new.user_id::text, jsonb_build_object('role',new.role));
 return new;
end; $$;
create trigger membership_audit after insert or update of role on public.clinic_memberships
 for each row execute function private.audit_membership();
revoke all on function private.audit_membership() from public;

create function public.create_clinic(clinic_name text) returns uuid
 language plpgsql security definer set search_path = '' as $$
declare new_id uuid;
begin
 if auth.uid() is null then raise exception 'authentication_required'; end if;
 if not exists(select 1 from auth.users where id = auth.uid() and email_confirmed_at is not null)
 then raise exception 'verified_email_required'; end if;
 insert into public.clinics(name) values (btrim(clinic_name)) returning id into new_id;
 insert into public.clinic_memberships(clinic_id,user_id,role) values(new_id,auth.uid(),'admin');
 insert into public.audit_log(clinic_id,actor_id,action,entity_id)
 values(new_id,auth.uid(),'clinic_created',new_id::text);
 return new_id;
end; $$;

create function public.create_clinic_invitation(target_clinic uuid, invite_email text, invite_role public.clinic_role)
returns text language plpgsql security definer set search_path = '' as $$
declare token text; invite_id uuid;
begin
 if not private.has_clinic_role(target_clinic,array['admin']::public.clinic_role[])
 then raise exception 'admin_required'; end if;
 token := encode(extensions.gen_random_bytes(32),'hex');
 insert into public.clinic_invitations(clinic_id,email,role,token_hash,created_by)
 values(target_clinic,lower(btrim(invite_email)),invite_role,
 encode(extensions.digest(token,'sha256'),'hex'),auth.uid()) returning id into invite_id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(target_clinic,auth.uid(),'invitation_created',invite_id::text,jsonb_build_object('role',invite_role));
 return token;
end; $$;

create function public.accept_clinic_invitation(invite_token text) returns uuid
 language plpgsql security definer set search_path = '' as $$
declare invite public.clinic_invitations; user_email text;
begin
 if auth.uid() is null then raise exception 'authentication_required'; end if;
 select lower(email) into user_email from auth.users
 where id = auth.uid() and email_confirmed_at is not null;
 if user_email is null then raise exception 'verified_email_required'; end if;
 select * into invite from public.clinic_invitations
 where token_hash = encode(extensions.digest(btrim(invite_token),'sha256'),'hex') for update;
 if not found or invite.revoked_at is not null or invite.accepted_at is not null
 or invite.expires_at <= now() or invite.email <> user_email
 then raise exception 'invalid_invitation'; end if;
 insert into public.clinic_memberships(clinic_id,user_id,role)
 values(invite.clinic_id,auth.uid(),invite.role);
 update public.clinic_invitations set accepted_by = auth.uid(),accepted_at = now() where id = invite.id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id)
 values(invite.clinic_id,auth.uid(),'invitation_accepted',invite.id::text);
 return invite.clinic_id;
end; $$;

create function public.revoke_clinic_invitation(invitation_id uuid) returns void
 language plpgsql security definer set search_path = '' as $$
declare target uuid;
begin
 select clinic_id into target from public.clinic_invitations where id = invitation_id;
 if not private.has_clinic_role(target,array['admin']::public.clinic_role[])
 then raise exception 'admin_required'; end if;
 update public.clinic_invitations set revoked_at = now() where id = invitation_id and accepted_at is null;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id)
 values(target,auth.uid(),'invitation_revoked',invitation_id::text);
end; $$;

revoke all on function public.create_clinic(text) from public;
revoke all on function public.create_clinic_invitation(uuid,text,public.clinic_role) from public;
revoke all on function public.accept_clinic_invitation(text) from public;
revoke all on function public.revoke_clinic_invitation(uuid) from public;
grant execute on function public.create_clinic(text) to authenticated;
grant execute on function public.create_clinic_invitation(uuid,text,public.clinic_role) to authenticated;
grant execute on function public.accept_clinic_invitation(text) to authenticated;
grant execute on function public.revoke_clinic_invitation(uuid) to authenticated;
commit;
