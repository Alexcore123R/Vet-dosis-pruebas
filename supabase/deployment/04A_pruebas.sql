-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Etapa 4, bloque 1/6.
-- Ejecutar en orden; no probar funciones M6 hasta completar todos los bloques.
begin;

create table public.professional_profiles (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),
 user_id uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),unique(clinic_id,user_id),unique(clinic_id,id)
);
create table private.professional_profile_versions (
 id uuid primary key default gen_random_uuid(),profile_id uuid not null references public.professional_profiles(id),version integer not null,
 name text not null check(length(btrim(name)) between 1 and 200),license text not null default '',registration text not null default '',
 signature jsonb,source_status text not null default 'sin verificar' check(source_status='sin verificar'),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),unique(profile_id,version)
);
create table public.clinic_professional_authorizations (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,user_id uuid not null references auth.users(id),
 enabled boolean not null,valid_until timestamptz not null,review_reference text not null check(length(btrim(review_reference)) between 1 and 1000),
 created_at timestamptz not null default clock_timestamp(),foreign key(clinic_id) references public.clinics(id)
);
create table public.professional_delegations (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,profile_id uuid not null,recipient_id uuid not null references auth.users(id),
 case_id uuid,use_data boolean not null,use_signature boolean not null,prepare_ordinary boolean not null,issue_ordinary boolean not null,
 dispense_ordinary boolean not null,valid_until timestamptz not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,profile_id) references public.professional_profiles(clinic_id,id),foreign key(clinic_id,case_id) references public.clinical_cases(clinic_id,id)
);
create table public.professional_delegation_revocations (
 id uuid primary key default gen_random_uuid(),delegation_id uuid not null unique references public.professional_delegations(id),
 reason text not null check(length(btrim(reason)) between 1 and 1000),created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp()
);
create table public.medication_product_versions (
 id uuid primary key default gen_random_uuid(),product_key text not null,version integer not null,
 name text not null,presentation text not null,unit text not null check(unit in ('ml','mg','g','tableta','capsula')),
 concentration text,classification text not null check(classification in ('desconocida','no_controlado','grupo_i','restringido')),
 quantified_prescription boolean,source jsonb not null,source_status text not null check(source_status in ('verificada','sin verificar')),
 source_valid_until timestamptz,created_at timestamptz not null default clock_timestamp(),unique(product_key,version),
 check(source_status<>'verificada' or (classification<>'desconocida' and quantified_prescription is not null and coalesce(length(btrim((source->>'reference'))),0)>0))
);
create table public.rx_regulatory_versions (
 id uuid primary key default gen_random_uuid(),kind text not null check(kind in ('controlled_prescription','controlled_report')),
 version integer not null,source jsonb not null,source_status text not null check(source_status in ('verificada','sin verificar')),
 valid_until timestamptz,required_fields text[] not null,created_at timestamptz not null default clock_timestamp(),unique(kind,version),
 check(source_status<>'verificada' or coalesce(length(btrim((source->>'reference'))),0)>0)
);
create table public.prescriptions (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,case_id uuid not null,patient_id uuid not null,
 responsible_id uuid not null references auth.users(id),created_by uuid not null references auth.users(id),
 state text not null default 'draft' check(state in ('draft','awaiting_review','ready','issued')),revision integer not null default 1,
 controlled boolean not null default false,official_folio text not null default '',instructions text not null default '',
 profile_id uuid,delegation_id uuid references public.professional_delegations(id),use_shared_signature boolean not null default false,
 regulatory_version_id uuid references public.rx_regulatory_versions(id),snapshot jsonb,content_hash text,pdf_hash text,prepared_at timestamptz,issued_at timestamptz,
 created_at timestamptz not null default clock_timestamp(),unique(clinic_id,id),
 foreign key(clinic_id,case_id) references public.clinical_cases(clinic_id,id),foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id),
 foreign key(clinic_id,profile_id) references public.professional_profiles(clinic_id,id)
);
create table public.prescription_items (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,prescription_id uuid not null,product_version_id uuid not null references public.medication_product_versions(id),
 quantity numeric(24,9) not null check(quantity>0),unit text not null,route text not null,interval_text text not null,duration_text text not null,care text not null default '',
 foreign key(clinic_id,prescription_id) references public.prescriptions(clinic_id,id)
);
create table public.medication_vials (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),product_version_id uuid not null references public.medication_product_versions(id),
 inventory_id uuid references public.inventario(id),inventory_lot_id uuid references public.lotes_inventario(id),lot text not null,
 initial_volume numeric(24,9) not null check(initial_volume>0),unit text not null check(unit='ml'),responsible_id uuid not null references auth.users(id),
 opened_at timestamptz not null,created_at timestamptz not null default clock_timestamp(),unique(clinic_id,id)
);
create table public.medication_records (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,case_id uuid not null,patient_id uuid not null,
 product_version_id uuid not null references public.medication_product_versions(id),prescription_id uuid,
 hospital_task_id uuid,vial_id uuid,quantity numeric(24,9) not null check(quantity>0),unit text not null,route text not null,procedure text not null,
 performed_by uuid not null references auth.users(id),reported_by uuid not null references auth.users(id),responsible_id uuid not null references auth.users(id),
 observed_at timestamptz not null,reported_at timestamptz not null default clock_timestamp(),lot text not null,
 replaces_id uuid unique references public.medication_records(id),correction_reason text,incidence text not null default '',content_hash text not null,
 foreign key(clinic_id,case_id) references public.clinical_cases(clinic_id,id),foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id),
 foreign key(clinic_id,prescription_id) references public.prescriptions(clinic_id,id),foreign key(clinic_id,vial_id) references public.medication_vials(clinic_id,id),
 unique(clinic_id,id),unique(hospital_task_id)
);
create table public.medication_vial_movements (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,vial_id uuid not null,record_id uuid unique,
 delta numeric(24,9) not null,reason text not null,created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,vial_id) references public.medication_vials(clinic_id,id),foreign key(clinic_id,record_id) references public.medication_records(clinic_id,id)
);
create table public.medication_vial_reconciliations (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,vial_id uuid not null unique,
 expected numeric(24,9) not null,measured numeric(24,9) not null check(measured>=0),difference numeric(24,9) not null,
 reason text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,vial_id) references public.medication_vials(clinic_id,id)
);
create table public.controlled_drug_reviews (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,record_id uuid not null,content_hash text not null,
 decision text not null check(decision in ('validada','requiere_correccion')),reason text not null,validated_by uuid not null references auth.users(id),
 validated_at timestamptz not null default clock_timestamp(),foreign key(clinic_id,record_id) references public.medication_records(clinic_id,id)
);
create table public.controlled_drug_reports (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),responsible_id uuid not null references auth.users(id),
 starts_at timestamptz not null,ends_at timestamptz not null,cutoff timestamptz not null default clock_timestamp(),
 official boolean not null,complete boolean not null,regulatory_version_id uuid references public.rx_regulatory_versions(id),
 pending_ids uuid[] not null,snapshot jsonb not null,content_hash text not null,pdf_hash text,state text not null default 'awaiting_review' check(state in ('awaiting_review','ready','issued')),
 issued_at timestamptz,created_at timestamptz not null default clock_timestamp(),unique(clinic_id,id)
);
create table public.controlled_drug_report_items (
 id uuid primary key default gen_random_uuid(),report_id uuid not null references public.controlled_drug_reports(id),record_id uuid not null references public.medication_records(id),
 review_id uuid not null references public.controlled_drug_reviews(id),unique(report_id,record_id)
);
create table private.rx_artifacts (
 kind text not null check(kind in ('prescription','report')),entity_id uuid not null,revision integer not null,
 content_hash text not null,pdf bytea not null,pdf_hash text not null,signature_png bytea not null,
 created_at timestamptz not null default clock_timestamp(),primary key(kind,entity_id)
);
alter table public.hospital_tasks add column medication_record_id uuid references public.medication_records(id);
create function private.rx_professional(clinic uuid,person uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.clinic_members m where m.clinic_id=$1 and m.user_id=$2 and m.role in ('admin','mvz')) and
 coalesce((select a.enabled and a.valid_until>clock_timestamp() from public.clinic_professional_authorizations a where a.clinic_id=$1 and a.user_id=$2 order by a.created_at desc,a.id desc limit 1),false);
$$;
create function private.rx_profile(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(v) from private.professional_profile_versions v where v.profile_id=p_id order by v.version desc limit 1;
$$;
create function private.rx_delegated(p public.professional_profiles,scope text,caseid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.professional_delegations d where d.profile_id=p.id and d.recipient_id=auth.uid() and d.valid_until>clock_timestamp() and
 (d.case_id is null or d.case_id=$3) and not exists(select 1 from public.professional_delegation_revocations r where r.delegation_id=d.id) and
 case $2 when 'data' then d.use_data when 'signature' then d.use_signature when 'prepare' then d.prepare_ordinary when 'issue' then d.issue_ordinary else false end);
$$;
create function private.rx_case(c public.clinical_cases) returns boolean language sql stable security definer set search_path='' as $$
 select private.clinical_readable(c) and exists(select 1 from public.clinic_members where clinic_id=c.clinic_id and user_id=auth.uid() and role in ('admin','mvz','auxiliar'));
$$;
create function private.rx_readable(r public.prescriptions) returns boolean language sql stable security definer set search_path='' as $$
 select private.has_clinic_role(r.clinic_id,array['admin']) or (r.responsible_id=auth.uid() and private.rx_professional(r.clinic_id,auth.uid())) or
 (not r.controlled and r.created_by=auth.uid() and exists(select 1 from public.clinical_cases c where c.id=r.case_id and private.rx_case(c)));
$$;
create function private.rx_quantity(s text) returns numeric language plpgsql immutable set search_path='' as $$
begin if s is null or s !~ '^\d{1,12}(\.\d{1,9})?$' or s::numeric<=0 then raise exception 'positive_exact_quantity_required';end if;return s::numeric;end $$;
create function private.rx_product_verified(p public.medication_product_versions) returns boolean language sql stable set search_path='' as $$
 select p.source_status='verificada' and p.classification<>'desconocida' and p.quantified_prescription is not null and (p.source_valid_until is null or p.source_valid_until>clock_timestamp()) and
 p.version=(select max(v.version) from public.medication_product_versions v where v.product_key=p.product_key);
$$;
create function private.rx_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_table_name='prescriptions' then if old.state='issued' then raise exception 'issued_prescription_is_immutable';end if;return new;end if;
 if tg_table_name='controlled_drug_reports' then if old.state='issued' then raise exception 'issued_report_is_immutable';end if;return new;end if;
 if tg_table_name='prescription_items' then if exists(select 1 from public.prescriptions where id=old.prescription_id and state<>'draft') then raise exception 'prescription_items_frozen';end if;if tg_op='DELETE' then return old;end if;return new;end if;
 if tg_table_name='rx_artifacts' then
  if exists(select 1 from public.prescriptions where id=old.entity_id and state='issued') or exists(select 1 from public.controlled_drug_reports where id=old.entity_id and state='issued') then raise exception 'issued_pdf_is_immutable';end if;
  if tg_op='DELETE' then return old;end if;return new;
 end if;
 raise exception 'rx_history_is_immutable';
end $$;
-- No direct writes or reads of signature vectors/profile versions/artifacts.
revoke all on private.professional_profile_versions,private.rx_artifacts from public,anon,authenticated;
create trigger immutable before update or delete on private.professional_profile_versions for each row execute function private.rx_guard();
create trigger immutable before update or delete on private.rx_artifacts for each row execute function private.rx_guard();
do $$declare t text;begin
 foreach t in array array['professional_profiles','clinic_professional_authorizations','professional_delegations','professional_delegation_revocations','medication_product_versions','rx_regulatory_versions','prescriptions','prescription_items','medication_vials','medication_records','medication_vial_movements','medication_vial_reconciliations','controlled_drug_reviews','controlled_drug_reports','controlled_drug_report_items'] loop
  execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);
  execute format('create trigger immutable before update or delete on public.%I for each row execute function private.rx_guard()',t);
 end loop;
end $$;
create policy rx_profile_read on public.professional_profiles for select to authenticated using(user_id=auth.uid() and private.has_clinic_role(clinic_id,array['admin','mvz','auxiliar']));
create policy rx_auth_read on public.clinic_professional_authorizations for select to authenticated using(user_id=auth.uid() and private.has_clinic_role(clinic_id,array['admin','mvz','auxiliar']));
create policy rx_delegation_read on public.professional_delegations for select to authenticated using((recipient_id=auth.uid() or created_by=auth.uid()) and private.has_clinic_role(clinic_id,array['admin','mvz','auxiliar']));
create policy rx_revocation_read on public.professional_delegation_revocations for select to authenticated using(exists(select 1 from public.professional_delegations d where d.id=delegation_id and (d.recipient_id=auth.uid() or d.created_by=auth.uid())));
create policy rx_catalog_read on public.medication_product_versions for select to authenticated using(auth.uid() is not null);
create policy rx_rules_read on public.rx_regulatory_versions for select to authenticated using(auth.uid() is not null);
create policy rx_read on public.prescriptions for select to authenticated using(private.rx_readable(prescriptions));
create policy rx_items_read on public.prescription_items for select to authenticated using(exists(select 1 from public.prescriptions r where r.id=prescription_id and private.rx_readable(r)));
create policy rx_vial_read on public.medication_vials for select to authenticated using(private.has_clinic_role(clinic_id,array['admin','mvz','auxiliar']));
create policy rx_record_read on public.medication_records for select to authenticated using(exists(select 1 from public.clinical_cases c where c.id=case_id and private.rx_case(c)));
create policy rx_movement_read on public.medication_vial_movements for select to authenticated using(exists(select 1 from public.medication_records r join public.clinical_cases c on c.id=r.case_id where r.id=record_id and private.rx_case(c)));
create policy rx_reconciliation_read on public.medication_vial_reconciliations for select to authenticated using(private.has_clinic_role(clinic_id,array['admin','mvz','auxiliar']));
create policy rx_review_read on public.controlled_drug_reviews for select to authenticated using(exists(select 1 from public.medication_records r join public.clinical_cases c on c.id=r.case_id where r.id=record_id and private.rx_case(c)));
create policy rx_report_read on public.controlled_drug_reports for select to authenticated using(private.has_clinic_role(clinic_id,array['admin']) or (responsible_id=auth.uid() and private.rx_professional(clinic_id,auth.uid())));
create policy rx_report_items_read on public.controlled_drug_report_items for select to authenticated using(exists(select 1 from public.controlled_drug_reports r where r.id=report_id and (private.has_clinic_role(r.clinic_id,array['admin']) or (r.responsible_id=auth.uid() and private.rx_professional(r.clinic_id,auth.uid())))));
-- Cierre provisional: ningún endpoint farmacológico nuevo habilitado al cliente.
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (p.proname like 'rx_%' or p.proname in ('form_professional_check','form_document_use_profile')) and n.nspname in ('public','private') loop execute 'revoke all on function '||f.signature||' from public,anon,authenticated';end loop;
end $$;

notify pgrst, 'reload schema';
commit;
select '04A COMPLETADO (1/6)' as resultado;
-- FIN COMPLETO 04A
