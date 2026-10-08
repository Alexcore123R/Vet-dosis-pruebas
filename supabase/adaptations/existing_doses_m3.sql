-- Apply once, after existing_clinics_m2.sql. Preserves the general catalog.
begin;
create table public.dose_personal_entries (
 id uuid primary key default gen_random_uuid(),
 clinic_id uuid not null references public.clinics(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 payload jsonb not null,
 state text not null default 'personal' check (state in ('personal','pending','approved','rejected')),
 reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
alter table public.dose_personal_entries enable row level security;
revoke all on public.dose_personal_entries from anon, authenticated;
grant select on public.dose_personal_entries to authenticated;
create policy dose_personal_read on public.dose_personal_entries for select to authenticated using (
 public.has_clinic_role(clinic_id,array['admin','mvz']) and
 (user_id=auth.uid() or public.has_clinic_role(clinic_id,array['admin']) or state='approved')
);
-- The old shared table has no approval provenance: don't expose legacy entries
-- to the whole team. Preserve them for their author and clinic administrator.
do $$ declare p record; begin
 for p in select policyname from pg_policies where schemaname='public' and tablename='Fármacos personalizados' loop
  execute format('drop policy %I on public."Fármacos personalizados"',p.policyname);
 end loop;
end $$;
revoke insert, update, delete on public."Fármacos personalizados" from authenticated;
create policy legacy_dose_read on public."Fármacos personalizados" for select to authenticated using (
 (clinic_id is null and user_id=auth.uid()) or
 (public.has_clinic_role(clinic_id,array['admin','mvz']) and
  (user_id=auth.uid() or public.has_clinic_role(clinic_id,array['admin'])))
);
create function public.create_personal_dose(p_clinic_id uuid,p_payload jsonb,p_share boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; p jsonb; k text; value text; lo numeric; hi numeric;
begin
 if auth.uid() is null or not public.has_clinic_role(p_clinic_id,array['admin','mvz']) then raise exception 'clinical_role_required'; end if;
 if jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'invalid_dose'; end if;
 foreach k in array array['id','farmaco','especie','via','intervalo'] loop
  if jsonb_typeof(p_payload->k) is distinct from 'string' or length(btrim(p_payload->>k)) not between 1 and 300 then raise exception 'invalid_dose'; end if;
 end loop;
 if p_payload->>'unidad_dosis' is distinct from 'mg/kg' then raise exception 'invalid_units'; end if;
 foreach k in array array['min','max'] loop
  value=p_payload->>k;
  if jsonb_typeof(p_payload->k) is distinct from 'string' or value !~ '^\d{1,12}(\.\d{1,9})?$' or value::numeric<=0 then raise exception 'invalid_range'; end if;
 end loop;
 lo=(p_payload->>'min')::numeric; hi=(p_payload->>'max')::numeric;
 if lo>hi then raise exception 'invalid_range'; end if;
 if p_payload->>'estado' is null or p_payload->>'estado' not in ('verificada','sin verificar') then raise exception 'invalid_evidence'; end if;
 if p_payload->>'estado'='verificada' and (jsonb_typeof(p_payload->'fuente') is distinct from 'string' or btrim(p_payload->>'fuente')='') then raise exception 'invalid_evidence'; end if;
 if jsonb_typeof(p_payload->'presentaciones') is distinct from 'array' then raise exception 'missing_presentation'; end if;
 if jsonb_array_length(p_payload->'presentaciones')=0 then raise exception 'missing_presentation'; end if;
 for p in select * from jsonb_array_elements(p_payload->'presentaciones') loop
  foreach k in array array['id','nombre_comercial'] loop
   if jsonb_typeof(p->k) is distinct from 'string' or btrim(p->>k)='' then raise exception 'invalid_presentation'; end if;
  end loop;
  value=p->>'concentracion';
  if p->>'unidad_concentracion' is distinct from 'mg/ml' or jsonb_typeof(p->'concentracion') is distinct from 'string' or value !~ '^\d{1,12}(\.\d{1,9})?$' or value::numeric<=0 then raise exception 'invalid_concentration'; end if;
  if p->>'estado' is null or p->>'estado' not in ('verificada','sin verificar') or
    (p->>'estado'='verificada' and (jsonb_typeof(p->'fuente') is distinct from 'string' or btrim(p->>'fuente')='')) then raise exception 'invalid_evidence'; end if;
 end loop;
 if (select count(*) from jsonb_array_elements(p_payload->'presentaciones')) <>
    (select count(distinct x->>'id') from jsonb_array_elements(p_payload->'presentaciones') x) then raise exception 'duplicate_presentation'; end if;
 if jsonb_typeof(p_payload->'contraindicaciones') is distinct from 'array' then raise exception 'invalid_contraindications'; end if;
 for p in select * from jsonb_array_elements(p_payload->'contraindicaciones') loop
  if p->>'tipo' is null or p->>'tipo' not in ('especie','raza','condicion') or jsonb_typeof(p->'valor') is distinct from 'string' or btrim(p->>'valor')='' or jsonb_typeof(p->'nota') is distinct from 'string' or btrim(p->>'nota')='' then raise exception 'invalid_contraindications'; end if;
  if p->>'estado' is null or p->>'estado' not in ('verificada','sin verificar') or (p->>'estado'='verificada' and (jsonb_typeof(p->'fuente') is distinct from 'string' or btrim(p->>'fuente')='')) then raise exception 'invalid_evidence'; end if;
 end loop;
 -- No updates: revisions are new entries and require a new review.
 insert into public.dose_personal_entries(clinic_id,user_id,payload,state) values(p_clinic_id,auth.uid(),p_payload,case when p_share then 'pending' else 'personal' end) returning id into v_id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic_id,auth.uid(),'dose_created',v_id);
 return v_id;
end $$;
create function public.review_personal_dose(p_id uuid,p_approve boolean)
returns void language plpgsql security definer set search_path='' as $$
declare entry public.dose_personal_entries;
begin
 select * into entry from public.dose_personal_entries where id=p_id for update;
 if not found or not public.has_clinic_role(entry.clinic_id,array['admin']) then raise exception 'admin_required'; end if;
 if entry.state<>'pending' then raise exception 'not_pending'; end if;
 update public.dose_personal_entries set state=case when p_approve then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now() where id=p_id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(entry.clinic_id,auth.uid(),case when p_approve then 'dose_approved' else 'dose_rejected' end,p_id);
end $$;
revoke all on function public.create_personal_dose(uuid,jsonb,boolean),public.review_personal_dose(uuid,boolean) from public,anon;
grant execute on function public.create_personal_dose(uuid,jsonb,boolean),public.review_personal_dose(uuid,boolean) to authenticated;
commit;
