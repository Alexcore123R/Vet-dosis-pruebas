-- VetDosis Pro: ETAPA 1. Solo proyecto NUEVO de PRUEBAS wtrelwtztkddfktrfdpb.
-- No ejecutar en wycrgscbhybyjmatotkt ni en otra base con tablas existentes.
-- Prepara seis tablas vacías compatibles y aplica M2/equipo. No inserta usuarios ni datos clínicos.
-- Ejecutar completo una sola vez en SQL Editor. Un error revierte la transacción.
begin;
do $$ begin
 if exists(select 1 from information_schema.tables where table_schema='public' and table_type='BASE TABLE')
 then raise exception 'STOP: public contiene tablas; requiere revisar esquema antes de instalar'; end if;
end $$;
create table public."clinic_members" ("clinic_id" uuid not null, "user_id" uuid not null, "role" text default 'member'::text not null, "created_at" timestamp with time zone default now() not null);
alter table public."clinic_members" enable row level security;
create table public."clinics" ("id" uuid default gen_random_uuid() not null, "name" text not null, "created_by" uuid default auth.uid() not null, "created_at" timestamp with time zone default now() not null);
alter table public."clinics" enable row level security;
create table public."Fármacos personalizados" ("id" uuid default gen_random_uuid() not null, "user_id" uuid default auth.uid() not null, "Fármaco" text not null, "Categoría" text, "Especie" text not null, "Dosis mín. (por kg)" double precision, "Dosis máx. (por kg)" double precision, "Unidad" text, "Vía" text, "Frecuencia" text, "Notas / seguridad" text, "Clave (uso interno)" text, "Fuente de referencia" text, "created_at" timestamp with time zone default now() not null, "Marca comercial" text, "Concentración" numeric, "Presentación" text, "Laboratorio" text, "Unidad de concentración" text, "clinic_id" uuid);
alter table public."Fármacos personalizados" enable row level security;
create table public."Fármacos" ("Fármaco" text not null, "Categoría" text, "Especie" text not null, "Dosis mín. (por kg)" double precision, "Dosis máx. (por kg)" double precision, "Unidad" text, "Vía" text, "Frecuencia" text, "Notas / seguridad" text, "Clave (uso interno)" text, "Fuente de referencia" text);
alter table public."Fármacos" enable row level security;
create table public."inventario" ("id" uuid default gen_random_uuid() not null, "user_id" uuid default auth.uid() not null, "clinic_id" uuid, "nombre" text not null, "categoria" text default 'producto'::text not null, "presentacion" text, "stock" numeric default 0 not null, "stock_minimo" numeric default 0 not null, "precio_compra" numeric default 0 not null, "precio_venta" numeric default 0 not null, "caducidad" text, "proveedor" text, "codigo_barras" text, "imagen_url" text, "etiqueta_url" text, "notas" text, "created_at" timestamp with time zone default now() not null);
alter table public."inventario" enable row level security;
create table public."lotes_inventario" ("id" uuid default gen_random_uuid() not null, "user_id" uuid default auth.uid() not null, "clinic_id" uuid, "item_id" uuid not null, "lote" text, "caducidad" date, "cantidad" numeric default 0 not null, "costo_unitario" numeric default 0 not null, "notas" text, "created_at" timestamp with time zone default now() not null);
alter table public."lotes_inventario" enable row level security;
alter table public."clinic_members" add constraint "clinic_members_pkey" PRIMARY KEY (clinic_id, user_id);
alter table public."clinics" add constraint "clinics_pkey" PRIMARY KEY (id);
alter table public."Fármacos personalizados" add constraint "Fármacos personalizados_pkey" PRIMARY KEY (id);
alter table public."Fármacos" add constraint "Fármacos_pkey" PRIMARY KEY ("Fármaco", "Especie");
alter table public."inventario" add constraint "inventario_pkey" PRIMARY KEY (id);
alter table public."lotes_inventario" add constraint "lotes_inventario_pkey" PRIMARY KEY (id);
alter table public."clinic_members" add constraint "clinic_members_role_check" CHECK (role = ANY (ARRAY['admin'::text, 'editor'::text, 'member'::text]));
alter table public."clinics" add constraint "clinics_name_check" CHECK (btrim(name) <> ''::text);
alter table public."clinic_members" add constraint "clinic_members_clinic_id_fkey" FOREIGN KEY (clinic_id) REFERENCES clinics(id) ON DELETE CASCADE;
alter table public."clinic_members" add constraint "clinic_members_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public."clinics" add constraint "clinics_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public."Fármacos personalizados" add constraint "Fármacos personalizados_clinic_id_fkey" FOREIGN KEY (clinic_id) REFERENCES clinics(id) ON DELETE CASCADE;
alter table public."Fármacos personalizados" add constraint "Fármacos personalizados_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public."lotes_inventario" add constraint "lotes_inventario_item_id_fkey" FOREIGN KEY (item_id) REFERENCES inventario(id) ON DELETE CASCADE;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;
-- Abort before any schema change if old roles need an explicit decision.
lock table public.clinic_members in share row exclusive mode;
do $$ begin
 if exists(select 1 from public.clinic_members
   where role not in ('admin','mvz','auxiliar','recepcion','estilista'))
 then raise exception 'legacy_roles_require_explicit_mapping'; end if;
 if exists(select 1 from public.clinics c where not exists(
   select 1 from public.clinic_members m where m.clinic_id=c.id and m.role='admin'))
 then raise exception 'clinic_without_admin_requires_review'; end if;
end $$;
alter table public.clinic_members drop constraint clinic_members_role_check;
alter table public.clinic_members add constraint clinic_members_role_check
 check (role in ('admin','mvz','auxiliar','recepcion','estilista'));
alter table public.clinic_members alter column role drop default;
create table public.clinic_invitations (
 id uuid primary key default gen_random_uuid(),
 clinic_id uuid not null references public.clinics(id) on delete cascade,
 email text not null check (email = lower(btrim(email)) and position('@' in email) > 1),
 role text not null check (role in ('admin','mvz','auxiliar','recepcion','estilista')),
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
create index vd_membership_user on public.clinic_members(user_id);
create index audit_clinic_time on public.audit_log(clinic_id, occurred_at desc);

create function private.has_clinic_role(target uuid, allowed text[] default null)
returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.clinic_members m
 where m.clinic_id = target and m.user_id = auth.uid()
 and (allowed is null or m.role = any(allowed)));
$$;
revoke all on function private.has_clinic_role(uuid, text[]) from public;
grant execute on function private.has_clinic_role(uuid, text[]) to authenticated;

alter table public.clinics enable row level security;
alter table public.clinic_members enable row level security;
alter table public.clinic_invitations enable row level security;
alter table public.audit_log enable row level security;
revoke update (role) on public.clinic_members from anon, authenticated;
revoke update (name) on public.clinics from anon, authenticated;
-- RLS does not protect TRUNCATE; client roles do not need these privileges.
revoke truncate, references, trigger on public.inventario, public.lotes_inventario from public, anon, authenticated;
revoke all on public.clinics, public.clinic_members, public.clinic_invitations, public.audit_log from anon, authenticated;
grant update (name) on public.clinics to authenticated;
grant select on public.clinics, public.clinic_members, public.audit_log to authenticated;
grant select (id, clinic_id, email, role, created_at, expires_at, accepted_at, revoked_at)
 on public.clinic_invitations to authenticated;
create policy invitations_read on public.clinic_invitations for select to authenticated
 using (private.has_clinic_role(clinic_id, array['admin']::text[]));
create policy vd_clinics_read on public.clinics for select to authenticated
 using (private.has_clinic_role(id));
create policy vd_memberships_read on public.clinic_members for select to authenticated
 using (user_id = auth.uid() or private.has_clinic_role(clinic_id, array['admin']::text[]));
create policy audit_read on public.audit_log for select to authenticated
 using (private.has_clinic_role(clinic_id, array['admin']::text[]));
-- No client writes to role, invitations or audit tables. Only bounded RPCs.

create function private.audit_membership() returns trigger
 language plpgsql security definer set search_path = '' as $$
begin
 insert into public.audit_log(clinic_id, actor_id, action, entity_id, details)
 values (new.clinic_id, auth.uid(), case when tg_op = 'INSERT' then 'member_joined' else 'role_changed' end,
 new.user_id::text, jsonb_build_object('role',new.role));
 return new;
end; $$;
create trigger membership_audit after insert or update of role on public.clinic_members
 for each row execute function private.audit_membership();
revoke all on function private.audit_membership() from public;

create or replace function public.create_clinic(p_name text) returns uuid
 language plpgsql security definer set search_path = '' as $$
declare new_id uuid;
begin
 if auth.uid() is null then raise exception 'authentication_required'; end if;
 if not exists(select 1 from auth.users where id = auth.uid() and email_confirmed_at is not null)
 then raise exception 'verified_email_required'; end if;
 if p_name is null or char_length(btrim(p_name)) not between 2 and 120 then raise exception 'invalid_clinic_name'; end if;
 insert into public.clinics(name,created_by) values (btrim(p_name),auth.uid()) returning id into new_id;
 insert into public.clinic_members(clinic_id,user_id,role) values(new_id,auth.uid(),'admin');
 insert into public.audit_log(clinic_id,actor_id,action,entity_id)
 values(new_id,auth.uid(),'clinic_created',new_id::text);
 return new_id;
end; $$;

create function public.create_clinic_invitation(target_clinic uuid, invite_email text, invite_role text)
returns text language plpgsql security definer set search_path = '' as $$
declare token text; invite_id uuid;
begin
 if not private.has_clinic_role(target_clinic,array['admin']::text[])
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
 insert into public.clinic_members(clinic_id,user_id,role)
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
 if not private.has_clinic_role(target,array['admin']::text[])
 then raise exception 'admin_required'; end if;
 update public.clinic_invitations set revoked_at = now() where id = invitation_id and accepted_at is null;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id)
 values(target,auth.uid(),'invitation_revoked',invitation_id::text);
end; $$;

revoke all on function public.create_clinic(text) from public;
revoke all on function public.create_clinic_invitation(uuid,text,text) from public;
revoke all on function public.accept_clinic_invitation(text) from public;
revoke all on function public.revoke_clinic_invitation(uuid) from public;
grant execute on function public.create_clinic(text) to authenticated;
grant execute on function public.create_clinic_invitation(uuid,text,text) to authenticated;
grant execute on function public.accept_clinic_invitation(text) to authenticated;
grant execute on function public.revoke_clinic_invitation(uuid) to authenticated;
-- Protect the last administrator on both deletion and role changes.
create or replace function public.prevent_last_clinic_admin_removal() returns trigger
 language plpgsql security definer set search_path = '' as $$
begin
 if tg_op = 'UPDATE' and (new.clinic_id <> old.clinic_id or new.user_id <> old.user_id)
 then raise exception 'membership_identity_is_immutable'; end if;
 if old.role = 'admin' and (tg_op = 'DELETE' or new.role <> 'admin') then
   perform 1 from public.clinics where id = old.clinic_id for update;
   if not exists(select 1 from public.clinic_members
     where clinic_id=old.clinic_id and role='admin' and user_id<>old.user_id)
   then raise exception 'last_admin_required'; end if;
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end; $$;
revoke all on function public.prevent_last_clinic_admin_removal() from public;
drop trigger if exists prevent_last_clinic_admin_removal on public.clinic_members;
create trigger prevent_last_clinic_admin_removal before delete or update on public.clinic_members
 for each row execute function public.prevent_last_clinic_admin_removal();

create function public.set_clinic_member_role(target_clinic uuid, target_user uuid, new_role text)
returns void language plpgsql security definer set search_path = '' as $$
begin
 perform 1 from public.clinics where id=target_clinic for update;
 if not private.has_clinic_role(target_clinic,array['admin']::text[])
 then raise exception 'admin_required'; end if;
 update public.clinic_members set role=new_role
 where clinic_id=target_clinic and user_id=target_user;
 if not found then raise exception 'member_not_found'; end if;
end; $$;
revoke all on function public.set_clinic_member_role(uuid,uuid,text) from public;
grant execute on function public.set_clinic_member_role(uuid,uuid,text) to authenticated;


create function public.clinic_team_snapshot(target_clinic uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(target_clinic,array['admin']::text[]) then raise exception 'admin_required'; end if;
 return jsonb_build_object(
 'members',coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'email',u.email,'role',m.role) order by m.created_at,m.user_id)
 from public.clinic_members m join auth.users u on u.id=m.user_id where m.clinic_id=target_clinic),'[]'::jsonb),
 'invitations',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'email',i.email,'role',i.role,'expires_at',i.expires_at,'accepted_at',i.accepted_at,'revoked_at',i.revoked_at) order by i.created_at desc)
 from public.clinic_invitations i where i.clinic_id=target_clinic),'[]'::jsonb));
end; $$;
create function public.remove_clinic_member(target_clinic uuid,target_user uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.clinics where id=target_clinic for update;
 if not private.has_clinic_role(target_clinic,array['admin']::text[]) then raise exception 'admin_required'; end if;
 delete from public.clinic_members where clinic_id=target_clinic and user_id=target_user;
 if not found then raise exception 'member_not_found'; end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id)
 values(target_clinic,auth.uid(),'member_removed',target_user::text);
 -- Existing trigger enforces last administrator.
end; $$;
revoke all on function public.clinic_team_snapshot(uuid) from public;
revoke all on function public.remove_clinic_member(uuid,uuid) from public;
grant execute on function public.clinic_team_snapshot(uuid) to authenticated;
grant execute on function public.remove_clinic_member(uuid,uuid) to authenticated;

-- No acceso cliente a las cuatro tablas de catálogo/inventario hasta sus adaptaciones posteriores.
revoke all on public."Fármacos", public."Fármacos personalizados", public.inventario, public.lotes_inventario from public, anon, authenticated;
notify pgrst, 'reload schema';
commit;
select 'ETAPA 1 COMPLETADA: base vacía y acceso M2/equipo instalados' as resultado;
