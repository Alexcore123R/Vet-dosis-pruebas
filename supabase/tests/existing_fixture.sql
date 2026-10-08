-- Local fixture reconstructed from exported metadata. No real records.
create role service_role nologin bypassrls;
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
CREATE OR REPLACE FUNCTION public.create_clinic(p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'name required';
  end if;

  insert into public.clinics (name, created_by) values (trim(p_name), auth.uid())
    returning id into v_id;

  insert into public.clinic_members (clinic_id, user_id, role) values (v_id, auth.uid(), 'admin')
    on conflict (clinic_id, user_id) do update set role = 'admin';

  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.has_clinic_role(p_clinic_id uuid, p_roles text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.clinic_members AS cm
    WHERE cm.clinic_id = p_clinic_id
      AND cm.user_id = (SELECT auth.uid())
      AND cm.role = ANY (p_roles)
  );
$function$
;
CREATE OR REPLACE FUNCTION public.is_clinic_member(p_clinic_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.clinic_members AS cm
    WHERE cm.clinic_id = p_clinic_id
      AND cm.user_id = (SELECT auth.uid())
  );
$function$
;
CREATE OR REPLACE FUNCTION public.prevent_last_clinic_admin_removal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_has_other_admin boolean;
BEGIN
  IF OLD.role = 'admin' THEN
    PERFORM 1
    FROM public.clinics AS c
    WHERE c.id = OLD.clinic_id
    FOR UPDATE;

    SELECT EXISTS (
      SELECT 1
      FROM public.clinic_members AS cm
      WHERE cm.clinic_id = OLD.clinic_id
        AND cm.role = 'admin'
        AND cm.user_id <> OLD.user_id
    ) INTO v_has_other_admin;

    IF NOT v_has_other_admin THEN
      RAISE EXCEPTION 'A clinic must retain at least one admin';
    END IF;
  END IF;

  RETURN OLD;
END;
$function$
;
CREATE TRIGGER prevent_last_clinic_admin_removal BEFORE DELETE ON clinic_members FOR EACH ROW EXECUTE FUNCTION prevent_last_clinic_admin_removal();
create policy "Admins can remove members and members can leave" on public."clinic_members" as PERMISSIVE for DELETE to "authenticated" using ((has_clinic_role(clinic_id, ARRAY['admin'::text]) OR ((user_id = ( SELECT auth.uid() AS uid)) AND (role <> 'admin'::text))));
create policy "Admins can change clinic member roles" on public."clinic_members" as PERMISSIVE for UPDATE to "authenticated" using (has_clinic_role(clinic_id, ARRAY['admin'::text])) with check (has_clinic_role(clinic_id, ARRAY['admin'::text]));
create policy "Members can view their clinic roster" on public."clinic_members" as PERMISSIVE for SELECT to "authenticated" using (is_clinic_member(clinic_id));
create policy "Admins can add clinic members" on public."clinic_members" as PERMISSIVE for INSERT to "authenticated" with check (has_clinic_role(clinic_id, ARRAY['admin'::text]));
create policy "Clinic admins can rename clinics" on public."clinics" as PERMISSIVE for UPDATE to "authenticated" using (has_clinic_role(id, ARRAY['admin'::text])) with check (has_clinic_role(id, ARRAY['admin'::text]));
create policy "Clinic members can read their clinics" on public."clinics" as PERMISSIVE for SELECT to "authenticated" using (is_clinic_member(id));
create policy "Owners or clinic editors can delete drugs" on public."Fármacos personalizados" as PERMISSIVE for DELETE to "authenticated" using ((((clinic_id IS NULL) AND (user_id = ( SELECT auth.uid() AS uid))) OR ((clinic_id IS NOT NULL) AND has_clinic_role(clinic_id, ARRAY['admin'::text, 'editor'::text]))));
create policy "Owners or clinic editors can update drugs" on public."Fármacos personalizados" as PERMISSIVE for UPDATE to "authenticated" using ((((clinic_id IS NULL) AND (user_id = ( SELECT auth.uid() AS uid))) OR ((clinic_id IS NOT NULL) AND has_clinic_role(clinic_id, ARRAY['admin'::text, 'editor'::text])))) with check ((((clinic_id IS NULL) AND (user_id = ( SELECT auth.uid() AS uid))) OR ((clinic_id IS NOT NULL) AND has_clinic_role(clinic_id, ARRAY['admin'::text, 'editor'::text]))));
create policy "Users can read personal or clinic drugs" on public."Fármacos personalizados" as PERMISSIVE for SELECT to "authenticated" using ((((clinic_id IS NULL) AND (user_id = ( SELECT auth.uid() AS uid))) OR ((clinic_id IS NOT NULL) AND is_clinic_member(clinic_id))));
create policy "Users can add personal or clinic drugs" on public."Fármacos personalizados" as PERMISSIVE for INSERT to "authenticated" with check (((user_id = ( SELECT auth.uid() AS uid)) AND ((clinic_id IS NULL) OR has_clinic_role(clinic_id, ARRAY['admin'::text, 'editor'::text]))));
create policy "Authenticated users can read Fármacos" on public."Fármacos" as PERMISSIVE for SELECT to "authenticated" using (true);
create policy "inventario_delete" on public."inventario" as PERMISSIVE for DELETE to "authenticated" using ((((clinic_id IS NULL) AND (user_id = ( SELECT auth.uid() AS uid))) OR ((clinic_id IS NOT NULL) AND has_clinic_role(clinic_id, ARRAY['admin'::text, 'editor'::text]))));
create policy "inventario_update" on public."inventario" as PERMISSIVE for UPDATE to "authenticated" using ((((clinic_id IS NULL) AND (user_id = ( SELECT auth.uid() AS uid))) OR ((clinic_id IS NOT NULL) AND has_clinic_role(clinic_id, ARRAY['admin'::text, 'editor'::text])))) with check ((((clinic_id IS NULL) AND (user_id = ( SELECT auth.uid() AS uid))) OR ((clinic_id IS NOT NULL) AND has_clinic_role(clinic_id, ARRAY['admin'::text, 'editor'::text]))));
create policy "inventario_select" on public."inventario" as PERMISSIVE for SELECT to "authenticated" using ((((clinic_id IS NULL) AND (user_id = ( SELECT auth.uid() AS uid))) OR ((clinic_id IS NOT NULL) AND is_clinic_member(clinic_id))));
create policy "inventario_insert" on public."inventario" as PERMISSIVE for INSERT to "authenticated" with check (((user_id = ( SELECT auth.uid() AS uid)) AND ((clinic_id IS NULL) OR has_clinic_role(clinic_id, ARRAY['admin'::text, 'editor'::text]))));
create policy "lotes_inventario_delete" on public."lotes_inventario" as PERMISSIVE for DELETE to "authenticated" using ((((clinic_id IS NULL) AND (user_id = ( SELECT auth.uid() AS uid))) OR ((clinic_id IS NOT NULL) AND has_clinic_role(clinic_id, ARRAY['admin'::text, 'editor'::text]))));
create policy "lotes_inventario_update" on public."lotes_inventario" as PERMISSIVE for UPDATE to "authenticated" using ((((clinic_id IS NULL) AND (user_id = ( SELECT auth.uid() AS uid))) OR ((clinic_id IS NOT NULL) AND has_clinic_role(clinic_id, ARRAY['admin'::text, 'editor'::text])))) with check ((((clinic_id IS NULL) AND (user_id = ( SELECT auth.uid() AS uid))) OR ((clinic_id IS NOT NULL) AND has_clinic_role(clinic_id, ARRAY['admin'::text, 'editor'::text]))));
create policy "lotes_inventario_select" on public."lotes_inventario" as PERMISSIVE for SELECT to "authenticated" using ((((clinic_id IS NULL) AND (user_id = ( SELECT auth.uid() AS uid))) OR ((clinic_id IS NOT NULL) AND is_clinic_member(clinic_id))));
create policy "lotes_inventario_insert" on public."lotes_inventario" as PERMISSIVE for INSERT to "authenticated" with check (((user_id = ( SELECT auth.uid() AS uid)) AND ((clinic_id IS NULL) OR has_clinic_role(clinic_id, ARRAY['admin'::text, 'editor'::text]))));
grant DELETE on public."inventario" to "anon";
grant INSERT on public."inventario" to "anon";
grant REFERENCES on public."inventario" to "anon";
grant SELECT on public."inventario" to "anon";
grant TRIGGER on public."inventario" to "anon";
grant TRUNCATE on public."inventario" to "anon";
grant UPDATE on public."inventario" to "anon";
grant DELETE on public."lotes_inventario" to "anon";
grant INSERT on public."lotes_inventario" to "anon";
grant REFERENCES on public."lotes_inventario" to "anon";
grant SELECT on public."lotes_inventario" to "anon";
grant TRIGGER on public."lotes_inventario" to "anon";
grant TRUNCATE on public."lotes_inventario" to "anon";
grant UPDATE on public."lotes_inventario" to "anon";
grant DELETE on public."clinic_members" to "authenticated";
grant INSERT on public."clinic_members" to "authenticated";
grant SELECT on public."clinic_members" to "authenticated";
grant SELECT on public."clinics" to "authenticated";
grant DELETE on public."Fármacos personalizados" to "authenticated";
grant INSERT on public."Fármacos personalizados" to "authenticated";
grant SELECT on public."Fármacos personalizados" to "authenticated";
grant UPDATE on public."Fármacos personalizados" to "authenticated";
grant SELECT on public."Fármacos" to "authenticated";
grant DELETE on public."inventario" to "authenticated";
grant INSERT on public."inventario" to "authenticated";
grant REFERENCES on public."inventario" to "authenticated";
grant SELECT on public."inventario" to "authenticated";
grant TRIGGER on public."inventario" to "authenticated";
grant TRUNCATE on public."inventario" to "authenticated";
grant UPDATE on public."inventario" to "authenticated";
grant DELETE on public."lotes_inventario" to "authenticated";
grant INSERT on public."lotes_inventario" to "authenticated";
grant REFERENCES on public."lotes_inventario" to "authenticated";
grant SELECT on public."lotes_inventario" to "authenticated";
grant TRIGGER on public."lotes_inventario" to "authenticated";
grant TRUNCATE on public."lotes_inventario" to "authenticated";
grant UPDATE on public."lotes_inventario" to "authenticated";
grant SELECT on public."Fármacos" to "service_role";
grant DELETE on public."inventario" to "service_role";
grant INSERT on public."inventario" to "service_role";
grant REFERENCES on public."inventario" to "service_role";
grant SELECT on public."inventario" to "service_role";
grant TRIGGER on public."inventario" to "service_role";
grant TRUNCATE on public."inventario" to "service_role";
grant UPDATE on public."inventario" to "service_role";
grant DELETE on public."lotes_inventario" to "service_role";
grant INSERT on public."lotes_inventario" to "service_role";
grant REFERENCES on public."lotes_inventario" to "service_role";
grant SELECT on public."lotes_inventario" to "service_role";
grant TRIGGER on public."lotes_inventario" to "service_role";
grant TRUNCATE on public."lotes_inventario" to "service_role";
grant UPDATE on public."lotes_inventario" to "service_role";
grant UPDATE ("role") on public."clinic_members" to "authenticated";
grant UPDATE ("name") on public."clinics" to "authenticated";-- Synthetic preservation fixtures; deliberately no clinical doses.
insert into auth.users values ('00000000-0000-0000-0000-000000000900','fixture@example.test',now());
insert into public.clinics(id,name,created_by) values
 ('00000000-0000-0000-0000-000000000900','Clínica fixture','00000000-0000-0000-0000-000000000900');
insert into public.clinic_members(clinic_id,user_id,role) values
 ('00000000-0000-0000-0000-000000000900','00000000-0000-0000-0000-000000000900','admin');
insert into public."Fármacos"("Fármaco","Especie") values ('PRUEBA-SIN-USO-CLINICO','fixture');
insert into public.inventario(id,user_id,clinic_id,nombre) values
 ('00000000-0000-0000-0000-000000000900','00000000-0000-0000-0000-000000000900',
  '00000000-0000-0000-0000-000000000900','Producto fixture');
