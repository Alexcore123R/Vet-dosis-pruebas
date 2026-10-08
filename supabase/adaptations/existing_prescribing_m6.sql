-- M6. Apply once after M2, M4, M5 and forms phases 1/2. No remote execution.
-- Legal/product references are empty until source-reviewed server publication.
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
create function public.rx_professional_authorize(p_clinic uuid,p_user uuid,p_enabled boolean,p_until timestamptz,p_reference text) returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;
begin
 if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=p_user and role in ('admin','mvz')) or p_until<=clock_timestamp() then raise exception 'professional_membership_required';end if;
 insert into public.clinic_professional_authorizations(clinic_id,user_id,enabled,valid_until,review_reference) values(p_clinic,p_user,p_enabled,p_until,p_reference) returning clinic_professional_authorizations.id into id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,null,'professional_authorization_server_reviewed',id);return id;
end $$;
create function public.rx_profiles(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'user_id',p.user_id,'version_id',(v->>'id'),'version',v->'version','name',(v->>'name'),'license',(v->>'license'),'registration',(v->>'registration'),'has_signature',v->'signature' is not null and v->'signature'<>'null','source_status','sin verificar','authorized',private.rx_professional(p.clinic_id,p.user_id))) from public.professional_profiles p cross join lateral (select private.rx_profile(p.id) as v) q where p.clinic_id=p_clinic and (p.user_id=auth.uid() or exists(select 1 from public.professional_delegations d where d.profile_id=p.id and d.recipient_id=auth.uid() and d.use_data and d.valid_until>clock_timestamp() and not exists(select 1 from public.professional_delegation_revocations x where x.delegation_id=d.id)))),'[]');
end $$;
create function public.rx_profile_save(p_clinic uuid,p_expected integer,p_name text,p_license text,p_registration text,p_signature jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.professional_profiles;v jsonb;id uuid;fp jsonb;
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'profile_role_required';end if;
 if coalesce(length(btrim(p_name)),0) not between 1 and 200 or length(coalesce(p_license,''))>200 or length(coalesce(p_registration,''))>200 then raise exception 'invalid_profile';end if;
 if p_signature is not null and p_signature<>'null'::jsonb and p_signature<>'{"keep":true}'::jsonb then perform private.form_validate_signature(p_signature);end if;
 fp=jsonb_build_object('kind','profile','expected',p_expected,'name',p_name,'license',p_license,'registration',p_registration,'signature',p_signature);
 id=private.vet_receipt(p_clinic,p_operation,fp);if id is not null then return id;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_clinic::text||auth.uid()::text,0));
 select * into p from public.professional_profiles where clinic_id=p_clinic and user_id=auth.uid() for update;
 if not found then insert into public.professional_profiles(clinic_id,user_id) values(p_clinic,auth.uid()) returning * into p;end if;
 v=private.rx_profile(p.id);if coalesce(((v->>'version'))::integer,0) is distinct from coalesce(p_expected,0) then raise exception 'profile_version_conflict';end if;
 insert into private.professional_profile_versions(profile_id,version,name,license,registration,signature,created_by) values(p.id,coalesce(((v->>'version'))::integer,0)+1,p_name,coalesce(p_license,''),coalesce(p_registration,''),case when p_signature='{"keep":true}'::jsonb then v->'signature' when p_signature='null'::jsonb then null else p_signature end,auth.uid()) returning professional_profile_versions.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'professional_profile_version_created',id);return id;
end $$;
create function public.rx_delegations(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('revoked',exists(select 1 from public.professional_delegation_revocations r where r.delegation_id=d.id))) from public.professional_delegations d where d.clinic_id=p_clinic and (d.created_by=auth.uid() or d.recipient_id=auth.uid())),'[]');
end $$;
create function public.rx_delegate(p_profile uuid,p_recipient uuid,p_case uuid,p_permissions jsonb,p_until text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.professional_profiles;id uuid;fp jsonb;k text;until_at timestamptz;
begin
 select * into p from public.professional_profiles where professional_profiles.id=p_profile for update;
 if not found or p.user_id<>auth.uid() or not private.rx_professional(p.clinic_id,auth.uid()) then raise exception 'profile_owner_professional_required';end if;
 if not exists(select 1 from public.clinic_members where clinic_id=p.clinic_id and user_id=p_recipient and role in ('mvz','auxiliar','admin')) or p_recipient=auth.uid() then raise exception 'recipient_in_clinic_required';end if;
 until_at=private.clinical_time(p_until);if until_at<=clock_timestamp() then raise exception 'future_expiry_required';end if;
 foreach k in array array['use_data','use_signature','prepare_ordinary','issue_ordinary','dispense_ordinary'] loop if jsonb_typeof(p_permissions->k) is distinct from 'boolean' then raise exception 'typed_permissions_required';end if;end loop;
 if (p_permissions->'prepare_ordinary'='true' or p_permissions->'issue_ordinary'='true' or p_permissions->'dispense_ordinary'='true') and (p_case is null or not exists(select 1 from public.clinical_cases c where c.id=p_case and c.clinic_id=p.clinic_id and c.responsible_id=auth.uid())) then raise exception 'responsible_case_required';end if;
 if p_case is not null and not exists(select 1 from public.clinical_cases c where c.id=p_case and c.clinic_id=p.clinic_id and private.rx_case(c)) then raise exception 'case_access_required';end if;
 fp=jsonb_build_object('kind','delegation','profile',p_profile,'recipient',p_recipient,'case',p_case,'permissions',p_permissions,'until',p_until);id=private.vet_receipt(p.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.professional_delegations(clinic_id,profile_id,recipient_id,case_id,use_data,use_signature,prepare_ordinary,issue_ordinary,dispense_ordinary,valid_until,created_by)
 values(p.clinic_id,p.id,p_recipient,p_case,((p_permissions->>'use_data'))::boolean,((p_permissions->>'use_signature'))::boolean,((p_permissions->>'prepare_ordinary'))::boolean,((p_permissions->>'issue_ordinary'))::boolean,((p_permissions->>'dispense_ordinary'))::boolean,until_at,auth.uid()) returning professional_delegations.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p.clinic_id,auth.uid(),'professional_delegation_granted',id);return id;
end $$;
create function public.rx_delegate_revoke(p_id uuid,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.professional_delegations;p public.professional_profiles;id uuid;fp jsonb;
begin
 select * into d from public.professional_delegations where professional_delegations.id=p_id;
 select * into p from public.professional_profiles where professional_profiles.id=d.profile_id for update;
 if not found or p.user_id<>auth.uid() or not private.has_clinic_role(p.clinic_id,array['admin','mvz','auxiliar']) then raise exception 'profile_owner_required';end if;
 fp=jsonb_build_object('kind','delegation_revoke','delegation',p_id,'reason',p_reason);id=private.vet_receipt(p.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.professional_delegation_revocations(delegation_id,reason,created_by) values(d.id,p_reason,auth.uid()) returning professional_delegation_revocations.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p.clinic_id,auth.uid(),'professional_delegation_revoked',id);return id;
end $$;
create function private.rx_items_check(items jsonb,delegated boolean) returns boolean language plpgsql security definer set search_path='' as $$
declare x jsonb;p public.medication_product_versions;controlled boolean=false;k text;
begin
 if jsonb_typeof(items) is distinct from 'array' then raise exception 'prescription_items_required';end if;
 if jsonb_array_length(items) not between 1 and 40 then raise exception 'prescription_items_required';end if;
 for x in select * from jsonb_array_elements(items) loop
  select * into p from public.medication_product_versions where id=((x->>'product_version_id'))::uuid;
  if not found then raise exception 'product_version_required';end if;
  perform private.rx_quantity((x->>'quantity'));
  if (x->>'unit') is distinct from p.unit then raise exception 'product_unit_mismatch';end if;
  foreach k in array array['route','interval','duration'] loop
   if jsonb_typeof(x->k) is distinct from 'string' or coalesce(length(btrim(x->>k)),0) not between 1 and 1000 then raise exception 'complete_instructions_required';end if;
  end loop;
  if x ? 'care' and (jsonb_typeof(x->'care') is distinct from 'string' or length((x->>'care'))>4000) then raise exception 'invalid_care';end if;
  if p.classification<>'no_controlado' or coalesce(p.quantified_prescription,true) then controlled=true;end if;
  if delegated and (not private.rx_product_verified(p) or p.classification<>'no_controlado' or p.quantified_prescription) then raise exception 'delegated_restricted_product_denied';end if;
 end loop;
 return controlled;
end $$;
create function private.rx_permission(r public.prescriptions,scope text) returns void language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;p public.professional_profiles;
begin
 select * into c from public.clinical_cases where id=r.case_id;
 if not private.rx_professional(r.clinic_id,r.responsible_id) or not private.rx_case(c) then raise exception 'responsible_professional_required';end if;
 if r.responsible_id=auth.uid() and private.rx_professional(r.clinic_id,auth.uid()) then return;end if;
 if r.controlled then raise exception 'controlled_responsible_only';end if;
 select * into p from public.professional_profiles where clinic_id=r.clinic_id and user_id=r.responsible_id;
 if p.id is null or not private.rx_delegated(p,scope,r.case_id) then raise exception 'ordinary_delegation_required';end if;
end $$;
create function private.rx_insert_items(r public.prescriptions,items jsonb) returns void language plpgsql security definer set search_path='' as $$
declare x jsonb;begin
 for x in select * from jsonb_array_elements(items) loop
 insert into public.prescription_items(clinic_id,prescription_id,product_version_id,quantity,unit,route,interval_text,duration_text,care)
 values(r.clinic_id,r.id,((x->>'product_version_id'))::uuid,private.rx_quantity((x->>'quantity')),(x->>'unit'),(x->>'route'),(x->>'interval'),(x->>'duration'),coalesce((x->>'care'),''));
 end loop;
end $$;
create function public.rx_create(p_case uuid,p_items jsonb,p_folio text,p_instructions text,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;r public.prescriptions;controlled boolean;id uuid;fp jsonb;
begin
 select * into c from public.clinical_cases where clinical_cases.id=p_case;
 if not found or not private.rx_case(c) then raise exception 'case_access_required';end if;
 controlled=private.rx_items_check(p_items,c.responsible_id<>auth.uid() or not private.rx_professional(c.clinic_id,auth.uid()));
 r.clinic_id=c.clinic_id;r.case_id=c.id;r.responsible_id=c.responsible_id;r.controlled=controlled;
 perform private.rx_permission(r,'prepare');
 if length(coalesce(p_folio,''))>200 or length(coalesce(p_instructions,''))>4000 then raise exception 'invalid_prescription_text';end if;
 fp=jsonb_build_object('kind','rx_create','case',p_case,'items',p_items,'folio',p_folio,'instructions',p_instructions);id=private.vet_receipt(c.clinic_id,p_operation,fp);
 if id is not null then select * into r from public.prescriptions where prescriptions.id=id;return to_jsonb(r);end if;
 insert into public.prescriptions(clinic_id,case_id,patient_id,responsible_id,created_by,controlled,official_folio,instructions)
 values(c.clinic_id,c.id,c.patient_id,c.responsible_id,auth.uid(),controlled,coalesce(p_folio,''),coalesce(p_instructions,'')) returning * into r;
 perform private.rx_insert_items(r,p_items);
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,r.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(c.clinic_id,auth.uid(),'prescription_draft_created',r.id);return to_jsonb(r);
end $$;
create function public.rx_save(p_id uuid,p_revision integer,p_items jsonb,p_folio text,p_instructions text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;v_controlled boolean;
begin
 select * into r from public.prescriptions where id=p_id for update;
 if not found or r.revision is distinct from p_revision or r.state<>'draft' then raise exception 'prescription_revision_conflict';end if;
 v_controlled=private.rx_items_check(p_items,r.responsible_id<>auth.uid() or not private.rx_professional(r.clinic_id,auth.uid()));
 r.controlled=v_controlled;perform private.rx_permission(r,'prepare');
 if length(coalesce(p_folio,''))>200 or length(coalesce(p_instructions,''))>4000 then raise exception 'invalid_prescription_text';end if;
 delete from public.prescription_items where prescription_id=r.id;perform private.rx_insert_items(r,p_items);
 update public.prescriptions set controlled=v_controlled,official_folio=coalesce(p_folio,''),instructions=coalesce(p_instructions,''),revision=revision+1 where id=r.id returning * into r;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(r.clinic_id,auth.uid(),'prescription_draft_changed',r.id);return to_jsonb(r);
end $$;
create function public.rx_list(p_clinic uuid,p_patient uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('patient_name',p.name) order by r.created_at desc) from public.prescriptions r join public.vet_patients p on p.id=r.patient_id where r.clinic_id=p_clinic and (p_patient is null or r.patient_id=p_patient) and private.rx_readable(r)),'[]');
end $$;
create function public.rx_snapshot(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.prescriptions;
begin
 select * into r from public.prescriptions where id=p_id;
 if not found or not private.rx_readable(r) then raise exception 'prescription_access_denied';end if;
 return to_jsonb(r)||jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('quantity',i.quantity::text,'product_name',p.name,'presentation',p.presentation,'classification',p.classification,'source_status',p.source_status)) from public.prescription_items i join public.medication_product_versions p on p.id=i.product_version_id where prescription_id=r.id),'[]'));
end $$;
create function private.rx_regulation(kind text) returns public.rx_regulatory_versions language sql stable security definer set search_path='' as $$
 select r from public.rx_regulatory_versions r where r.kind=$1 order by r.version desc limit 1;
$$;
create function private.rx_emit_check(r public.prescriptions) returns void language plpgsql security definer set search_path='' as $$
declare i public.prescription_items;p public.medication_product_versions;rule public.rx_regulatory_versions;k text;
begin
 perform private.rx_permission(r,'issue');
 for i in select * from public.prescription_items where prescription_id=r.id loop
 select * into p from public.medication_product_versions where medication_product_versions.id=i.product_version_id;
 if not private.rx_product_verified(p) then raise exception 'verified_current_product_required';end if;
 end loop;
 if r.controlled then
  rule=private.rx_regulation('controlled_prescription');
  if rule.id is null or rule.source_status<>'verificada' or (rule.valid_until is not null and rule.valid_until<=clock_timestamp()) or r.official_folio='' then raise exception 'verified_controlled_format_and_captured_folio_required';end if;
  foreach k in array rule.required_fields loop
   if k not in ('folio','patient','owner','mvz_name','mvz_license','registration','products','instructions','signature') then raise exception 'unsupported_official_field';end if;
   if k='registration' and coalesce(r.snapshot->'profile'->>'registration','')='' then raise exception 'professional_registration_required';end if;
  end loop;
 end if;
end $$;
create function public.rx_prepare(p_id uuid,p_revision integer,p_profile uuid,p_shared_signature boolean,p_signature jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;p public.professional_profiles;v jsonb;a jsonb;d public.professional_delegations;signature jsonb;schema jsonb;rows jsonb;s jsonb;patient public.vet_patients;owner public.vet_owners;rule public.rx_regulatory_versions;
begin
 select * into r from public.prescriptions where id=p_id for update;
 if not found or r.revision is distinct from p_revision or r.state<>'draft' then raise exception 'prescription_revision_conflict';end if;
 perform private.rx_permission(r,'prepare');
 select * into p from public.professional_profiles where id=p_profile and clinic_id=r.clinic_id for update;
 if not found or not private.rx_professional(p.clinic_id,p.user_id) then raise exception 'authorized_profile_required';end if;
 if r.controlled and (p.user_id<>auth.uid() or auth.uid()<>r.responsible_id) then raise exception 'controlled_own_profile_required';end if;
 v=private.rx_profile(p.id);if coalesce((v->>'license'),'')='' then raise exception 'professional_license_required';end if;
 if p.user_id<>auth.uid() then
  select * into d from public.professional_delegations where profile_id=p.id and recipient_id=auth.uid() and (case_id is null or case_id=r.case_id) and use_data and (not p_shared_signature or use_signature) and valid_until>clock_timestamp() and not exists(select 1 from public.professional_delegation_revocations x where x.delegation_id=professional_delegations.id) order by created_at desc limit 1;
  if not found then raise exception 'data_signature_permission_required';end if;
 end if;
 a=private.rx_profile((select id from public.professional_profiles where clinic_id=r.clinic_id and user_id=auth.uid()));
 if a is null then raise exception 'issuer_profile_required';end if;
 if p_shared_signature then signature=v->'signature';
 else
  a=private.rx_profile((select id from public.professional_profiles where clinic_id=r.clinic_id and user_id=auth.uid()));
  if a is null then raise exception 'issuer_profile_required';end if;
  signature=case when p_signature is not null and p_signature<>'null'::jsonb then p_signature else a->'signature' end;
 end if;
 perform private.form_validate_signature(signature);
 select * into patient from public.vet_patients where id=r.patient_id;
 select * into owner from public.vet_owners where id=patient.owner_id;
 if owner.id is null then raise exception 'patient_owner_required';end if;
 r.profile_id=p.id;r.delegation_id=d.id;r.use_shared_signature=p_shared_signature;
 r.snapshot=jsonb_build_object('profile',v-'signature','issuer',coalesce(a,v)-'signature');
 perform private.rx_emit_check(r);rule=private.rx_regulation('controlled_prescription');
 select coalesce(jsonb_agg(jsonb_build_array(pv.name||' · '||pv.presentation,i.quantity::text||' '||i.unit,i.route,i.interval_text,i.duration_text,i.care) order by i.id),'[]') into rows from public.prescription_items i join public.medication_product_versions pv on pv.id=i.product_version_id where i.prescription_id=r.id;
 schema=jsonb_build_object('type','prescription','title',case when r.controlled then 'Receta controlada · folio capturado' else 'Receta médica veterinaria' end,'fields',jsonb_build_array(
 jsonb_build_object('id','patient','type','binding','label','Paciente'),jsonb_build_object('id','owner','type','binding','label','Propietario registrado'),jsonb_build_object('id','folio','type','text','label','Folio capturado por el MVZ (no generado por la app)'),
 jsonb_build_object('id','internal_id','type','text','label','Referencia interna del documento (no folio oficial)'),jsonb_build_object('id','issuer','type','text','label','Responsable del caso / usuario que emite'),
 jsonb_build_object('id','holder','type','text','label','Datos del profesional titular / estado de referencia'),jsonb_build_object('id','sharing','type','text','label','Identidad y firma utilizadas'),jsonb_build_object('id','products','type','table','label','Indicaciones capturadas por el responsable','columns',jsonb_build_array('Producto / presentación','Cantidad por administración','Vía','Intervalo','Duración','Cuidados')),
 jsonb_build_object('id','instructions','type','text','label','Indicaciones adicionales')),'clauses',jsonb_build_array(jsonb_build_object('text','La clínica es responsable de las indicaciones capturadas y de verificar los requisitos aplicables. La referencia interna no sustituye un folio oficial.')));
 s=jsonb_build_object('clinical',true,'schema',schema,'document_id',r.id,'template_version',1,'clinic_name',(select name from public.clinics where id=r.clinic_id),'patient',jsonb_build_object('name',patient.name,'species',patient.species),'owner',jsonb_build_object('name',owner.name),
 'branding',public.form_branding(r.clinic_id),'prepared_at',clock_timestamp(),'profile',v-'signature','issuer',coalesce(a,v)-'signature','delegation_id',d.id,'mvz_signature',signature,
 'signature_label',case when p_shared_signature then 'Firma del titular compartida con autorización' else 'Firma propia de quien emite' end,'values',jsonb_build_object('folio',r.official_folio,'internal_id',r.id,'issuer','Responsable: '||r.responsible_id::text||' · Emisor: '||auth.uid()::text,'holder',(v->>'name')||' · Cédula capturada: '||(v->>'license')||' · sin verificar','sharing',case when p_shared_signature then 'Firma del titular del perfil, con permiso vigente' else 'Firma propia de quien emite' end,'products',rows,'instructions',r.instructions,'mvz_name',case when p_shared_signature then (v->>'name') else (a->>'name') end,'mvz_license',case when p_shared_signature then (v->>'license') else (a->>'license') end));
 update public.prescriptions set state='awaiting_review',revision=revision+1,profile_id=p.id,delegation_id=d.id,use_shared_signature=p_shared_signature,regulatory_version_id=case when r.controlled then rule.id end,snapshot=s,prepared_at=clock_timestamp(),content_hash=encode(sha256(convert_to(s::text,'UTF8')),'hex') where id=r.id returning * into r;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(r.clinic_id,auth.uid(),'prescription_prepared_for_pdf_review',r.id);return to_jsonb(r);
end $$;
create function private.rx_prepared_permission(r public.prescriptions) returns void language plpgsql security definer set search_path='' as $$
declare p public.professional_profiles;d public.professional_delegations;
begin
 perform private.rx_emit_check(r);
 select * into p from public.professional_profiles where id=r.profile_id for update;
 if not private.rx_professional(r.clinic_id,p.user_id) then raise exception 'authorized_profile_required';end if;
 if p.user_id<>auth.uid() then
  select * into d from public.professional_delegations where id=r.delegation_id;
  if not found or d.recipient_id<>auth.uid() or d.valid_until<=clock_timestamp() or not d.use_data or (r.use_shared_signature and not d.use_signature) or exists(select 1 from public.professional_delegation_revocations where delegation_id=d.id) then raise exception 'delegation_revoked_or_expired';end if;
 end if;
end $$;
create function public.rx_finalize(p_id uuid,p_revision integer,p_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;
begin
 select * into r from public.prescriptions where id=p_id for update;
 if not found or not private.rx_readable(r) or r.revision is distinct from p_revision or r.pdf_hash is distinct from p_hash or p_hash is null then raise exception 'reviewed_prescription_mismatch';end if;
 if r.state='issued' then return to_jsonb(r);end if;
 perform private.rx_prepared_permission(r);
 if r.state<>'ready' or not exists(select 1 from private.rx_artifacts a where a.kind='prescription' and a.entity_id=r.id and a.revision=r.revision and a.pdf_hash=p_hash and encode(sha256(a.pdf),'hex')=p_hash) then raise exception 'reviewed_pdf_required';end if;
 update public.prescriptions set state='issued',issued_at=clock_timestamp() where id=r.id returning * into r;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(r.clinic_id,auth.uid(),'prescription_issued',r.id);return to_jsonb(r);
end $$;
create unique index rx_captured_folio_unique on public.prescriptions(clinic_id,responsible_id,official_folio) where state='issued' and controlled;
create function public.rx_vial_open(p_clinic uuid,p_product uuid,p_lot text,p_volume text,p_opened text,p_inventory uuid,p_inventory_lot uuid,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.medication_product_versions;id uuid;fp jsonb;opened timestamptz;
begin
 if not private.rx_professional(p_clinic,auth.uid()) then raise exception 'professional_required';end if;
 select * into p from public.medication_product_versions where medication_product_versions.id=p_product;
 if not found or p.unit<>'ml' then raise exception 'volume_product_required';end if;
 if coalesce(length(btrim(p_lot)),0) not between 1 and 200 then raise exception 'lot_required';end if;
 if p_inventory is not null and not exists(select 1 from public.inventario where inventario.id=p_inventory and clinic_id=p_clinic) then raise exception 'inventory_wrong_clinic';end if;
 if p_inventory_lot is not null and not exists(select 1 from public.lotes_inventario where lotes_inventario.id=p_inventory_lot and clinic_id=p_clinic and item_id=p_inventory and lote=p_lot) then raise exception 'lot_inventory_mismatch';end if;
 opened=private.clinical_time(p_opened);if opened>clock_timestamp() then raise exception 'future_opening';end if;
 fp=jsonb_build_object('kind','vial_open','product',p_product,'lot',p_lot,'volume',p_volume,'opened',p_opened,'inventory',p_inventory,'inventory_lot',p_inventory_lot);id=private.vet_receipt(p_clinic,p_operation,fp);if id is not null then return id;end if;
 insert into public.medication_vials(clinic_id,product_version_id,inventory_id,inventory_lot_id,lot,initial_volume,unit,responsible_id,opened_at) values(p_clinic,p_product,p_inventory,p_inventory_lot,p_lot,private.rx_quantity(p_volume),'ml',auth.uid(),opened) returning medication_vials.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'medication_vial_opened',id);return id;
end $$;
create function private.rx_vial_balance(p_id uuid) returns numeric language sql stable security definer set search_path='' as $$
 select v.initial_volume+coalesce((select sum(m.delta) from public.medication_vial_movements m where m.vial_id=v.id),0) from public.medication_vials v where v.id=$1;
$$;
create function public.rx_vials(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(v)||jsonb_build_object('product_name',p.name,'balance',private.rx_vial_balance(v.id)::text,'movements',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'kind',m.kind,'delta',m.delta::text,'reason',m.reason,'record_id',m.record_id,'created_by',m.created_by,'created_at',m.created_at) order by m.created_at) from public.medication_vial_movements m where m.vial_id=v.id and (v.responsible_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin']) or exists(select 1 from public.medication_records mr join public.clinical_cases cc on cc.id=mr.case_id where mr.id=m.record_id and private.rx_case(cc)))),'[]'),'closed',exists(select 1 from public.medication_vial_reconciliations where vial_id=v.id),'closure',(select to_jsonb(x) from public.medication_vial_reconciliations x where x.vial_id=v.id))) from public.medication_vials v join public.medication_product_versions p on p.id=v.product_version_id where v.clinic_id=p_clinic),'[]');
end $$;
create function public.rx_vial_close(p_id uuid,p_measured text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v public.medication_vials;id uuid;fp jsonb;measured numeric;expected numeric;difference numeric;
begin
 select * into v from public.medication_vials where medication_vials.id=p_id for update;
 if not found or v.responsible_id<>auth.uid() or not private.rx_professional(v.clinic_id,auth.uid()) then raise exception 'vial_responsible_required';end if;
 if p_measured is null or p_measured !~ '^\d{1,12}(\.\d{1,9})?$' then raise exception 'exact_measured_volume_required';end if;
 measured=p_measured::numeric;expected=private.rx_vial_balance(v.id);difference=measured-expected;
 if (difference<>0 or expected<0) and coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'discrepancy_mvZ_note_required';end if;
 fp=jsonb_build_object('kind','vial_close','vial',p_id,'measured',p_measured,'reason',p_reason);id=private.vet_receipt(v.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.medication_vial_reconciliations(clinic_id,vial_id,expected,measured,difference,reason,created_by) values(v.clinic_id,v.id,expected,measured,difference,coalesce(p_reason,''),auth.uid()) returning medication_vial_reconciliations.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),v.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(v.clinic_id,auth.uid(),'medication_vial_closed_with_reconciliation',id);return id;
end $$;
create function public.rx_medication_report(p_case uuid,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;p public.medication_product_versions;v public.medication_vials;previous public.medication_records;v_record_id uuid;fp jsonb;n numeric;t timestamptz;performer uuid;vial uuid;balance numeric;delta numeric;incidence text='';lot text;task public.hospital_tasks;stay public.hospital_stays;prescription public.prescriptions;
begin
 select * into c from public.clinical_cases where clinical_cases.id=p_case for update;
 if not found or not private.rx_case(c) or not private.rx_professional(c.clinic_id,c.responsible_id) then raise exception 'case_professional_required';end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'typed_medication_required';end if;
 select * into p from public.medication_product_versions where medication_product_versions.id=((p_data->>'product_version_id'))::uuid;
 if not found then raise exception 'product_version_required';end if;
 n=private.rx_quantity((p_data->>'quantity'));t=private.clinical_time((p_data->>'observed_at'));performer=((p_data->>'performed_by'))::uuid;
 if (p_data->>'unit') is distinct from p.unit or coalesce(length(btrim((p_data->>'route'))),0) not between 1 and 200 or (p_data->>'procedure') not in ('evaluacion','cirugia','anestesia','recuperacion','cuidados') then raise exception 'medication_fields_required';end if;
 perform private.clinical_write_check(c,(p_data->>'procedure'),performer,t);
 if not private.rx_professional(c.clinic_id,auth.uid()) and not private.has_clinic_role(c.clinic_id,array['auxiliar']) then raise exception 'professional_or_authorized_auxiliary_required';end if;
 perform pg_advisory_xact_lock(hashtextextended('rx-ledger-'||c.clinic_id::text,0));
 fp=jsonb_build_object('kind','medication','case',p_case,'data',p_data);v_record_id=private.vet_receipt(c.clinic_id,p_operation,fp);if v_record_id is not null then return v_record_id;end if;
 if nullif((p_data->>'replaces_id'),'') is not null then
  select * into previous from public.medication_records where medication_records.id=((p_data->>'replaces_id'))::uuid and case_id=c.id for update;
  if not found or c.responsible_id<>auth.uid() or not private.rx_professional(c.clinic_id,auth.uid()) or coalesce(length(btrim((p_data->>'correction_reason'))),0) not between 1 and 1000 then raise exception 'responsible_correction_required';end if;
  if previous.product_version_id<>p.id or previous.unit<>p.unit or previous.performed_by<>performer then raise exception 'correction_identity_changed';end if;
  if exists(select 1 from public.medication_records where replaces_id=previous.id) then raise exception 'record_already_corrected';end if;
 end if;
 vial=nullif((p_data->>'vial_id'),'')::uuid;
 if previous.id is not null and vial is distinct from previous.vial_id then raise exception 'correction_vial_changed';end if;
 lot=coalesce((p_data->>'lot'),'');
 if vial is not null then
  select * into v from public.medication_vials where medication_vials.id=vial and clinic_id=c.clinic_id for update;
  if not found or v.product_version_id<>p.id or p.unit<>'ml' then raise exception 'vial_product_unit_mismatch';end if;
  lot=v.lot;balance=private.rx_vial_balance(v.id);delta=coalesce(previous.quantity,0)-n;
  if t<v.opened_at then raise exception 'application_before_vial_opening';end if;
  if balance+delta<0 then incidence='Saldo registrado insuficiente; aplicación reportada para conciliación';end if;
  if exists(select 1 from public.medication_vial_reconciliations where vial_id=v.id) then incidence=incidence||' · Frasco cerrado: requiere revisión del MVZ';end if;
 end if;
 if coalesce(length(btrim(lot)),0) not between 1 and 200 then raise exception 'exact_lot_required';end if;
 if nullif((p_data->>'prescription_id'),'') is not null then
  select * into prescription from public.prescriptions where prescriptions.id=((p_data->>'prescription_id'))::uuid and clinic_id=c.clinic_id and patient_id=c.patient_id and state='issued';
  if not found or not exists(select 1 from public.prescription_items where prescription_id=prescription.id and product_version_id=p.id) then raise exception 'issued_matching_prescription_required';end if;
 end if;
 if nullif((p_data->>'hospital_task_id'),'') is not null then
  select * into task from public.hospital_tasks where hospital_tasks.id=((p_data->>'hospital_task_id'))::uuid and clinic_id=c.clinic_id for update;
  select * into stay from public.hospital_stays where hospital_stays.id=task.stay_id;
  if task.id is null or stay.patient_id<>c.patient_id or task.kind<>'medicacion' then raise exception 'matching_hospital_medication_task_required';end if;
  if task.prescription_item_id is not null and (task.clinical_case_id<>c.id or not exists(select 1 from public.prescription_items where prescription_items.id=task.prescription_item_id and product_version_id=p.id)) then raise exception 'scheduled_product_case_mismatch';end if;
  if task.prescription_item_id is not null then
   if prescription.id is not null and prescription.id<>(select prescription_id from public.prescription_items where prescription_items.id=task.prescription_item_id) then raise exception 'scheduled_prescription_mismatch';end if;
   select * into prescription from public.prescriptions where prescriptions.id=(select prescription_id from public.prescription_items where prescription_items.id=task.prescription_item_id);
  end if;
  if task.due_at>t then incidence=incidence||' · Aplicación anterior a la hora programada';end if;
  if task.state='cancelled' or stay.discharged_at is not null then incidence=incidence||' · Tarea cancelada / estancia cerrada';end if;
 end if;
 insert into public.medication_records(clinic_id,case_id,patient_id,product_version_id,prescription_id,hospital_task_id,vial_id,quantity,unit,route,procedure,performed_by,reported_by,responsible_id,observed_at,lot,replaces_id,correction_reason,incidence,content_hash)
 values(c.clinic_id,c.id,c.patient_id,p.id,prescription.id,task.id,vial,n,p.unit,(p_data->>'route'),(p_data->>'procedure'),performer,auth.uid(),c.responsible_id,t,lot,previous.id,(p_data->>'correction_reason'),incidence,encode(sha256(convert_to(fp::text,'UTF8')),'hex')) returning medication_records.id into v_record_id;
 if vial is not null then insert into public.medication_vial_movements(clinic_id,vial_id,record_id,delta,kind,created_by,reason) values(c.clinic_id,vial,v_record_id,delta,case when previous.id is null then 'toma' else 'correccion' end,auth.uid(),case when previous.id is null then 'Toma reportada, no implica validación' else 'Rectificación contable de captura; no devolución física: '||(p_data->>'correction_reason') end);end if;
 if task.id is not null then update public.hospital_tasks set medication_record_id=v_record_id,
 state=case when state='pending' then 'done' else state end,
 performed_by=case when state='pending' then performer else performed_by end,
 performed_at=case when state='pending' then t else performed_at end,version=version+1 where hospital_tasks.id=task.id;end if;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,v_record_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(c.clinic_id,auth.uid(),'medication_application_reported_pending_review',v_record_id);return v_record_id;
end $$;
create function public.rx_medications(p_case uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.clinical_cases;
begin
 select * into c from public.clinical_cases where id=p_case;
 if not found or not private.rx_case(c) then raise exception 'case_access_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('quantity',r.quantity::text,'product_name',p.name,'presentation',p.presentation,'classification',p.classification,'source_status',p.source_status,'superseded',exists(select 1 from public.medication_records n where n.replaces_id=r.id),'review',(select to_jsonb(v) from public.controlled_drug_reviews v where v.record_id=r.id and v.content_hash=r.content_hash order by v.validated_at desc,v.id desc limit 1),'dose_reference',null) order by r.observed_at,r.reported_at) from public.medication_records r join public.medication_product_versions p on p.id=r.product_version_id where r.case_id=c.id),'[]');
end $$;
create function public.rx_medication_review(p_id uuid,p_hash text,p_decision text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.medication_records;c public.clinical_cases;id uuid;fp jsonb;
begin
 select * into r from public.medication_records where medication_records.id=p_id;
 select * into c from public.clinical_cases where clinical_cases.id=r.case_id for update;
 if not found or r.responsible_id<>auth.uid() or not private.rx_professional(r.clinic_id,auth.uid()) then raise exception 'responsible_professional_only';end if;
 if r.content_hash is distinct from p_hash or exists(select 1 from public.medication_records where replaces_id=r.id) then raise exception 'exact_current_record_required';end if;
 if p_decision not in ('validada','requiere_correccion') or coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'review_decision_and_reason_required';end if;
 if p_decision='validada' and r.incidence<>'' then raise exception 'unresolved_incidence_requires_correction';end if;
 perform pg_advisory_xact_lock(hashtextextended('rx-ledger-'||r.clinic_id::text,0));
 fp=jsonb_build_object('kind','medication_review','record',p_id,'hash',p_hash,'decision',p_decision,'reason',p_reason);id=private.vet_receipt(r.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.controlled_drug_reviews(clinic_id,record_id,content_hash,decision,reason,validated_by) values(r.clinic_id,r.id,r.content_hash,p_decision,p_reason,auth.uid()) returning controlled_drug_reviews.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),r.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(r.clinic_id,auth.uid(),'medication_record_reviewed',id);return id;
end $$;
create function public.rx_report_create(p_clinic uuid,p_start text,p_end text,p_official boolean,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare id uuid;fp jsonb;starts timestamptz;ends timestamptz;cutoff_at timestamptz;rule public.rx_regulatory_versions;profile jsonb;items jsonb;pending uuid[];rows jsonb;s jsonb;r public.controlled_drug_reports;schema jsonb;k text;
begin
 if not private.rx_professional(p_clinic,auth.uid()) then raise exception 'responsible_professional_only';end if;
 starts=private.clinical_time(p_start);ends=private.clinical_time(p_end);
 if starts>=ends or ends>clock_timestamp() or p_official is null then raise exception 'closed_report_period_required';end if;
 fp=jsonb_build_object('kind','controlled_report','start',p_start,'end',p_end,'official',p_official);id=private.vet_receipt(p_clinic,p_operation,fp);if id is not null then select * into r from public.controlled_drug_reports where controlled_drug_reports.id=id;return to_jsonb(r);end if;
 perform pg_advisory_xact_lock(hashtextextended('rx-ledger-'||p_clinic::text,0));cutoff_at=clock_timestamp();
 profile=private.rx_profile((select professional_profiles.id from public.professional_profiles where clinic_id=p_clinic and user_id=auth.uid()));
 if profile is null or coalesce((profile->>'license'),'')='' then raise exception 'professional_profile_required';end if;
 perform private.form_validate_signature(profile->'signature');
 rule=private.rx_regulation('controlled_report');
 if p_official then
  if rule.id is null or rule.source_status<>'verificada' or (rule.valid_until is not null and rule.valid_until<=cutoff_at) then raise exception 'verified_official_report_format_required';end if;
  foreach k in array rule.required_fields loop if k not in ('patient','product','lot','quantity','unit','route','observed_at','performed_by','validated_by','official_folio') then raise exception 'unsupported_official_report_field';end if;end loop;
 end if;
 with current_records as (
  select m.*,p.name,p.presentation,p.source_status,p.classification,p.quantified_prescription from public.medication_records m join public.medication_product_versions p on p.id=m.product_version_id
  where m.clinic_id=p_clinic and m.responsible_id=auth.uid() and m.observed_at>=starts and m.observed_at<ends and m.reported_at<=cutoff_at
  and (p.classification<>'no_controlado' or coalesce(p.quantified_prescription,true))
  and not exists(select 1 from public.medication_records n where n.replaces_id=m.id and n.reported_at<=cutoff_at)
 ),decisions as (
  select m.*,v.id as review_id,v.decision,v.validated_by,v.validated_at from current_records m left join lateral (select * from public.controlled_drug_reviews d where d.record_id=m.id and d.content_hash=m.content_hash and d.validated_at<=cutoff_at order by d.validated_at desc,d.id desc limit 1) v on true
 )
 select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('quantity',d.quantity::text,'patient_name',(select name from public.vet_patients where vet_patients.id=d.patient_id),'official_folio',(select official_folio from public.prescriptions where prescriptions.id=d.prescription_id))) filter(where decision='validada' and incidence='' and source_status='verificada'),'[]'),
 coalesce(array_agg(d.id) filter(where decision is distinct from 'validada' or incidence<>'' or source_status<>'verificada'),'{}') into items,pending from decisions d;
 if p_official then
  foreach k in array rule.required_fields loop
   if exists(select 1 from jsonb_array_elements(items) e where coalesce(btrim(e->>(case k when 'patient' then 'patient_name' when 'product' then 'name' else k end)),'')='') then raise exception 'official_report_required_value_missing';end if;
  end loop;
 end if;
 id=gen_random_uuid();
 select coalesce(jsonb_agg(jsonb_build_array((x->>'patient_name'),(x->>'name'),(x->>'lot'),(x->>'quantity')||' '||(x->>'unit'),(x->>'route'),(x->>'observed_at'),(x->>'performed_by'),(x->>'validated_by'),coalesce((x->>'official_folio'),'Sin folio vinculado'))),'[]') into rows from jsonb_array_elements(items) x;
 schema=jsonb_build_object('type','controlled_report','title',case when p_official then 'Reporte de control · formato verificado' else 'Reporte de referencia · no oficial' end,
 'fields',jsonb_build_array(jsonb_build_object('id','period','type','text','label','Periodo UTC (fin excluyente)'),jsonb_build_object('id','state','type','text','label','Estado del corte'),jsonb_build_object('id','pending','type','text','label','Registros pendientes / incidencias'),jsonb_build_object('id','records','type','table','label','Únicamente aplicaciones validadas al corte','columns',jsonb_build_array('Paciente','Producto','Lote','Cantidad','Vía','Hora observada','Aplicó','Validó','Folio vinculado'))),'clauses',jsonb_build_array(jsonb_build_object('text','Este corte es inmutable. Validaciones o correcciones posteriores requieren otro reporte. No se crean folios ni se infieren requisitos oficiales.')));
 s=jsonb_build_object('clinical',true,'schema',schema,'document_id',id,'template_version',coalesce(rule.version,1),'prepared_at',cutoff_at,'branding',public.form_branding(p_clinic),'profile',profile-'signature','mvz_signature',profile->'signature','entries',items,'pending_ids',to_jsonb(pending),'values',jsonb_build_object('period',p_start||' — '||p_end,'state',case when cardinality(pending)=0 then 'Completo al corte' else 'INCOMPLETO: hay pendientes o incidencias' end,'pending',cardinality(pending)::text||' · '||array_to_string(pending,', '),'records',rows,'mvz_name',(profile->>'name'),'mvz_license',(profile->>'license')));
 insert into public.controlled_drug_reports(id,clinic_id,responsible_id,starts_at,ends_at,cutoff,official,complete,regulatory_version_id,pending_ids,snapshot,content_hash)
 values(id,p_clinic,auth.uid(),starts,ends,cutoff_at,p_official,cardinality(pending)=0,case when p_official then rule.id end,pending,s,encode(sha256(convert_to(s::text,'UTF8')),'hex')) returning * into r;
 insert into public.controlled_drug_report_items(report_id,record_id,review_id) select r.id,((x->>'id'))::uuid,((x->>'review_id'))::uuid from jsonb_array_elements(items) x;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,r.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'controlled_report_cutoff_prepared',r.id);return to_jsonb(r);
end $$;
create function public.rx_reports(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz']) then raise exception 'report_read_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(r) order by created_at desc) from public.controlled_drug_reports r where clinic_id=p_clinic and (private.has_clinic_role(p_clinic,array['admin']) or responsible_id=auth.uid())),'[]');
end $$;
create function public.rx_report_finalize(p_id uuid,p_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.controlled_drug_reports;
begin
 select * into r from public.controlled_drug_reports where id=p_id for update;
 if not found or r.responsible_id<>auth.uid() or not private.rx_professional(r.clinic_id,auth.uid()) then raise exception 'responsible_professional_only';end if;
 if r.pdf_hash is distinct from p_hash or p_hash is null then raise exception 'reviewed_report_mismatch';end if;
 if r.state='issued' then return to_jsonb(r);end if;
 if r.state<>'ready' or not exists(select 1 from private.rx_artifacts a where kind='report' and entity_id=r.id and pdf_hash=p_hash and encode(sha256(pdf),'hex')=p_hash) then raise exception 'reviewed_pdf_required';end if;
 update public.controlled_drug_reports set state='issued',issued_at=clock_timestamp() where id=r.id returning * into r;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(r.clinic_id,auth.uid(),'controlled_report_signed',r.id);return to_jsonb(r);
end $$;
create function public.rx_pdf_snapshot(p_kind text,p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;t public.controlled_drug_reports;
begin
 if p_kind='prescription' then
 select * into r from public.prescriptions where id=p_id;
 if not found or not private.rx_readable(r) then raise exception 'prescription_access_denied';end if;
 if r.state<>'issued' then perform private.rx_prepared_permission(r);end if;
 return jsonb_build_object('snapshot',r.snapshot,'content_hash',r.content_hash,'revision',r.revision,'state',r.state);
 elsif p_kind='report' then
 select * into t from public.controlled_drug_reports where id=p_id;
 if not found or not (private.has_clinic_role(t.clinic_id,array['admin']) or (t.responsible_id=auth.uid() and private.rx_professional(t.clinic_id,auth.uid()))) then raise exception 'report_access_denied';end if;
 if t.state<>'issued' and (t.responsible_id<>auth.uid() or not private.rx_professional(t.clinic_id,auth.uid())) then raise exception 'responsible_professional_only';end if;
 return jsonb_build_object('snapshot',t.snapshot,'content_hash',t.content_hash,'revision',1,'state',t.state);
 end if;
 raise exception 'invalid_pdf_kind';
end $$;
create function public.rx_pdf_read(p_kind text,p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s jsonb;a private.rx_artifacts;
begin
 s=public.rx_pdf_snapshot(p_kind,p_id);
 select * into a from private.rx_artifacts where kind=p_kind and entity_id=p_id and content_hash=(s->>'content_hash') and revision=((s->>'revision'))::integer;
 if not found then return null;end if;
 return jsonb_build_object('pdf',encode(a.pdf,'base64'),'hash',a.pdf_hash);
end $$;
create function public.rx_pdf_register(p_kind text,p_id uuid,p_revision integer,p_content_hash text,p_pdf text,p_signature text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;t public.controlled_drug_reports;bytes bytea;png bytea;hash text;a private.rx_artifacts;
begin
 if p_kind='prescription' then
 select * into r from public.prescriptions where id=p_id for update;
 if not found or r.revision is distinct from p_revision or r.content_hash is distinct from p_content_hash then raise exception 'stale_rx_pdf';end if;
 elsif p_kind='report' then
 select * into t from public.controlled_drug_reports where id=p_id for update;
 if not found or p_revision<>1 or t.content_hash is distinct from p_content_hash then raise exception 'stale_report_pdf';end if;
 else raise exception 'invalid_pdf_kind';end if;
 select * into a from private.rx_artifacts where kind=p_kind and entity_id=p_id;
 if found then return jsonb_build_object('pdf',encode(a.pdf,'base64'),'hash',a.pdf_hash);end if;
 if (p_kind='prescription' and r.state<>'awaiting_review') or (p_kind='report' and t.state<>'awaiting_review') then raise exception 'document_not_prepared';end if;
 if p_pdf is null or p_signature is null or length(p_pdf)>2800000 or length(p_signature)>300000 then raise exception 'invalid_rx_artifact';end if;
 bytes=decode(p_pdf,'base64');png=decode(p_signature,'base64');
 if octet_length(bytes) not between 5 and 2097152 or substring(bytes from 1 for 5)<>convert_to('%PDF-','UTF8') or substring(png from 1 for 8)<>decode('89504e470d0a1a0a','hex') then raise exception 'invalid_rx_artifact';end if;
 hash=encode(sha256(bytes),'hex');
 insert into private.rx_artifacts(kind,entity_id,revision,content_hash,pdf,pdf_hash,signature_png) values(p_kind,p_id,p_revision,p_content_hash,bytes,hash,png);
 if p_kind='prescription' then update public.prescriptions set state='ready',pdf_hash=hash where id=p_id;
 else update public.controlled_drug_reports set state='ready',pdf_hash=hash where id=p_id;end if;
 return jsonb_build_object('pdf',encode(bytes,'base64'),'hash',hash);
end $$;

-- Opening, scheduling and actual application are different operations.
alter table public.hospital_tasks add column prescription_item_id uuid references public.prescription_items(id);
alter table public.hospital_tasks add column clinical_case_id uuid references public.clinical_cases(id);
create function public.rx_schedule(p_id uuid,p_item uuid,p_stay uuid,p_times jsonb,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;i public.prescription_items;s public.hospital_stays;ids jsonb='[]';id uuid;receipt uuid;fp jsonb;x jsonb;t timestamptz;
begin
 select * into r from public.prescriptions where prescriptions.id=p_id;
 if not found or r.state<>'issued' or r.responsible_id<>auth.uid() or not private.rx_professional(r.clinic_id,auth.uid()) then raise exception 'issued_responsible_prescription_required';end if;
 select * into i from public.prescription_items where prescription_items.id=p_item and prescription_id=r.id;
 select * into s from public.hospital_stays where hospital_stays.id=p_stay and clinic_id=r.clinic_id and patient_id=r.patient_id for update;
 if i.id is null or s.id is null or s.discharged_at is not null then raise exception 'matching_active_stay_required';end if;
 if jsonb_typeof(p_times) is distinct from 'array' then raise exception 'explicit_times_required';end if;
 if jsonb_array_length(p_times) not between 1 and 48 then raise exception 'explicit_times_required';end if;
 fp=jsonb_build_object('kind','rx_schedule','prescription',p_id,'item',p_item,'stay',p_stay,'times',p_times);receipt=private.vet_receipt(r.clinic_id,p_operation,fp);
 if receipt is not null then return (select details->'tasks' from public.audit_log where entity_id=receipt and action='prescription_hospital_tasks_created');end if;
 for x in select * from jsonb_array_elements(p_times) loop
  t=private.clinical_time(x#>>'{}');
  if t<clock_timestamp()-interval '5 minutes' then raise exception 'future_explicit_schedule_required';end if;
  insert into public.hospital_tasks(clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by,prescription_item_id,clinical_case_id)
  values(r.clinic_id,s.id,'medicacion',(select left(name,300) from public.medication_product_versions where medication_product_versions.id=i.product_version_id),i.quantity::text||' '||i.unit||' · '||i.route||' · '||i.interval_text||' · '||i.duration_text,t,15,auth.uid(),i.id,r.case_id) returning hospital_tasks.id into id;
  ids=ids||jsonb_build_array(id);
 end loop;
 receipt=gen_random_uuid();insert into private.vet_operation_receipts values(auth.uid(),r.clinic_id,p_operation,fp,receipt);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(r.clinic_id,auth.uid(),'prescription_hospital_tasks_created',receipt,jsonb_build_object('tasks',ids));return ids;
end $$;
create or replace function public.hospital_task_action(p_clinic_id uuid,p_task_id uuid,p_expected_version integer,p_action text,p_minutes integer default null,p_reason text default null)
returns void language plpgsql security definer set search_path='' as $$
declare task public.hospital_tasks;stay public.hospital_stays;stay_id uuid;
begin
 if not private.has_clinic_role(p_clinic_id,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 if p_action is null or p_action not in ('perform','snooze','cancel') then raise exception 'invalid_action';end if;
 select t.stay_id into stay_id from public.hospital_tasks t where t.clinic_id=p_clinic_id and t.id=p_task_id;
 if stay_id is null then raise exception 'task_not_found';end if;
 -- All mutations lock the stay before tasks, including discharge.
 select * into stay from public.hospital_stays s where s.id=stay_id and s.clinic_id=p_clinic_id for update;
 select * into task from public.hospital_tasks t where t.id=p_task_id and t.clinic_id=p_clinic_id for update;
 if p_action='perform' and task.state='done' and task.performed_by=auth.uid() then return;end if;
 if stay.discharged_at is not null then raise exception 'stay_inactive';end if;
 if task.state<>'pending' then raise exception 'task_not_pending';end if;
 if p_expected_version is null or task.version<>p_expected_version then raise exception 'version_conflict';end if;
 if p_action='perform' then
  if task.prescription_item_id is not null then raise exception 'structured_medication_report_required';end if;
  -- Scheduling does not authorize an early administration.
  if task.due_at>now() then raise exception 'task_not_due';end if;
  update public.hospital_tasks set state='done',performed_by=auth.uid(),performed_at=now(),version=version+1 where id=p_task_id;
 elsif p_action='snooze' then
  if task.due_at>now() then raise exception 'task_not_due';end if;
  if task.snooze_count>=3 then raise exception 'snooze_limit';end if;
  if p_minutes is null or p_minutes not between 1 and 30 or p_reason is null or length(btrim(p_reason)) not between 1 and 500 then raise exception 'invalid_snooze';end if;
  update public.hospital_tasks set snoozed_until=now()+make_interval(mins=>p_minutes),snooze_count=snooze_count+1,snooze_reason=btrim(p_reason),version=version+1 where id=p_task_id;
 else
  if not private.has_clinic_role(p_clinic_id,array['admin','mvz']) then raise exception 'physician_required';end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 500 then raise exception 'reason_required';end if;
  update public.hospital_tasks set state='cancelled',cancelled_by=auth.uid(),cancelled_at=now(),cancel_reason=btrim(p_reason),version=version+1 where id=p_task_id;
 end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic_id,auth.uid(),'hospital_task_'||p_action,p_task_id);
end $$;
create or replace function public.form_document_create(p_clinic uuid,p_patient uuid,p_version uuid,p_values jsonb,p_branding jsonb,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.form_template_versions;p public.vet_patients;o public.vet_owners;d public.form_documents;id uuid;fp jsonb;s jsonb;
begin
 if not (private.has_clinic_role(p_clinic,array['mvz']) or private.rx_professional(p_clinic,auth.uid())) then raise exception 'responsible_mvz_required';end if;
 select * into v from public.form_template_versions where form_template_versions.id=p_version and clinic_id=p_clinic and approved;
 if not found then raise exception 'approved_clinic_template_required';end if;
 perform private.form_validate_values(v.schema,p_values,false);perform private.form_validate_brand(p_branding);
 fp=jsonb_build_object('kind','form_document','patient',p_patient,'version',p_version,'values',p_values,'branding',p_branding);
 id=private.vet_receipt(p_clinic,p_operation,fp);
 if id is not null then select * into d from public.form_documents where form_documents.id=id;return to_jsonb(d);end if;
 select * into p from public.vet_patients where vet_patients.id=p_patient and clinic_id=p_clinic;
 if not found or (p.owner_id is null and v.schema->>'type' not in ('clinical_history','surgical_sheet','surgical_risk')) then raise exception 'patient_and_owner_required';end if;
 select * into o from public.vet_owners where vet_owners.id=p.owner_id and clinic_id=p_clinic;
 s=jsonb_build_object('schema',v.schema,'template_version',v.version,'patient',jsonb_build_object('id',p.id,'name',p.name,'species',p.species,'breed',p.breed,'sex',p.sex),'owner',jsonb_build_object('id',o.id,'name',coalesce(o.name,'Sin propietario registrado')),'clinical',v.schema->>'type' in ('clinical_history','surgical_sheet','surgical_risk'),'responsible_id',auth.uid(),'clinic_name',(select name from public.clinics where clinics.id=p_clinic));
 insert into public.form_documents(clinic_id,patient_id,version_id,responsible_id,values,branding,snapshot,created_by) values(p_clinic,p_patient,p_version,auth.uid(),p_values,p_branding,s,auth.uid()) returning * into d;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,d.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'form_document_draft_created',d.id);
 return to_jsonb(d);
end $$;
create or replace function public.form_document_prepare(p_id uuid,p_revision integer,p_tutor_signature jsonb,p_mvz_signature jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;time timestamptz=clock_timestamp();s jsonb;profile jsonb;mvz_points jsonb;
begin
 select * into d from public.form_documents where id=p_id for update;
 if not found or d.responsible_id<>auth.uid() or not (private.has_clinic_role(d.clinic_id,array['mvz']) or private.rx_professional(d.clinic_id,auth.uid())) then raise exception 'responsible_mvz_required';end if;
 if d.state<>'draft' or d.revision is distinct from p_revision then raise exception 'document_revision_conflict';end if;
 perform private.form_validate_values(d.snapshot->'schema',d.values,true);
 if not coalesce((d.snapshot->>'clinical')::boolean,false) then perform private.form_validate_signature(p_tutor_signature);end if;
 perform private.clinical_document_check(d);profile=private.form_professional_check(d);
 mvz_points=p_mvz_signature;
 if profile is not null then
  if d.values->>'mvz_name' is distinct from profile->>'name' or d.values->>'mvz_license' is distinct from profile->>'license' then raise exception 'profile_changed_rebind_required';end if;
  if d.shared_professional_signature then mvz_points=profile->'signature';
  elsif mvz_points is null or mvz_points='[]'::jsonb then mvz_points=private.rx_profile((select id from public.professional_profiles where clinic_id=d.clinic_id and user_id=auth.uid()))->'signature';end if;
 end if;
 perform private.form_validate_signature(mvz_points);
 s=d.snapshot||jsonb_build_object('staff_labels',(select coalesce(jsonb_object_agg(m.user_id::text,coalesce(nullif(u.email,''),m.user_id::text)),'{}') from public.clinic_members m join auth.users u on u.id=m.user_id where m.clinic_id=d.clinic_id and m.user_id in (nullif(d.values->>'surgeon_id','')::uuid,nullif(d.values->>'anesthetist_id','')::uuid)),'document_id',d.id,'values',d.values,'branding',d.branding,'prepared_at',time,'tutor_signature',p_tutor_signature,'mvz_signature',mvz_points,'professional_profile_version',profile-'signature','professional_issuer_profile',private.rx_profile((select id from public.professional_profiles where clinic_id=d.clinic_id and user_id=auth.uid()))-'signature','professional_delegation_id',d.professional_delegation_id,'signature_label',case when d.shared_professional_signature then 'Firma del titular compartida con autorización' else 'Firma del MVZ responsable' end);
 insert into public.form_signatures(document_id,role,name,identification_number,points,captured_at) values(d.id,'mvz',d.values->>'mvz_name',d.values->>'mvz_license',mvz_points,time);
 if not coalesce((d.snapshot->>'clinical')::boolean,false) then insert into public.form_signatures(document_id,role,name,identification_number,points,captured_at) values(d.id,'tutor',d.values->>'signer_name',d.values->>'signer_id',p_tutor_signature,time);end if;
 update public.form_documents set state='awaiting_review',revision=revision+1,snapshot=s,prepared_at=time,content_hash=encode(sha256(convert_to(s::text,'UTF8')),'hex') where id=d.id returning * into d;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(d.clinic_id,auth.uid(),'form_document_prepared_for_review',d.id);return to_jsonb(d);
end $$;
create or replace function public.form_document_finalize(p_id uuid,p_revision integer,p_pdf_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;
begin
 select * into d from public.form_documents where id=p_id for update;
 if not found or d.responsible_id<>auth.uid() or not (private.has_clinic_role(d.clinic_id,array['mvz']) or private.rx_professional(d.clinic_id,auth.uid())) then raise exception 'responsible_mvz_required';end if;
 if d.revision is distinct from p_revision or d.pdf_hash is distinct from p_pdf_hash or p_pdf_hash is null then raise exception 'reviewed_pdf_mismatch';end if;
 if d.state='signed' then return to_jsonb(d);end if;
 if d.state<>'ready' or not exists(select 1 from private.form_artifacts a where a.document_id=d.id and a.revision=d.revision and a.content_hash=d.content_hash and a.pdf_hash=p_pdf_hash and encode(sha256(a.pdf),'hex')=p_pdf_hash) then raise exception 'pdf_not_ready';end if;
 perform private.form_professional_check(d);
 perform private.clinical_document_check(d);
 update public.form_documents set state='signed',accepted_at=clock_timestamp() where id=d.id returning * into d;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(d.clinic_id,auth.uid(),'form_document_signed',d.id,jsonb_build_object('pdf_hash',p_pdf_hash,'version',d.version_id));
 perform private.clinical_document_publish(d);
 return to_jsonb(d);
end $$;
create or replace function public.form_document_assign(p_id uuid,p_aux uuid) returns void language plpgsql security definer set search_path='' as $$
declare d public.form_documents;
begin
 select * into d from public.form_documents where id=p_id for update;
 if not found or d.responsible_id<>auth.uid() or not (private.has_clinic_role(d.clinic_id,array['mvz']) or private.rx_professional(d.clinic_id,auth.uid())) or d.state<>'draft' then raise exception 'responsible_mvz_required';end if;
 if p_aux is not null and not exists(select 1 from public.clinic_members where clinic_id=d.clinic_id and user_id=p_aux and role='auxiliar') then raise exception 'auxiliary_not_in_clinic';end if;
 update public.form_documents set assigned_aux_id=p_aux,revision=revision+1 where id=p_id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(d.clinic_id,auth.uid(),'form_document_assigned',d.id);
end $$;
create or replace function public.form_auxiliaries(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not (private.has_clinic_role(p_clinic,array['mvz']) or private.rx_professional(p_clinic,auth.uid())) then raise exception 'responsible_mvz_required';end if;
 return coalesce((select jsonb_agg(user_id order by user_id) from public.clinic_members where clinic_id=p_clinic and role='auxiliar'),'[]');
end $$;
create or replace function public.clinical_authorize(p_case uuid,p_person uuid,p_scope text,p_until text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;id uuid;fp jsonb;until_at timestamptz;
begin
 select * into c from public.clinical_cases where clinical_cases.id=p_case for update;
 if not found or c.responsible_id<>auth.uid() or not (private.has_clinic_role(c.clinic_id,array['mvz']) or private.rx_professional(c.clinic_id,auth.uid())) then raise exception 'responsible_mvz_required';end if;
 until_at=private.clinical_time(p_until);
 if until_at<=clock_timestamp() or not exists(select 1 from public.clinic_members where clinic_id=c.clinic_id and user_id=p_person and role in ('mvz','auxiliar')) then raise exception 'invalid_authorization';end if;
 fp=jsonb_build_object('kind','clinical_grant','case',p_case,'person',p_person,'scope',p_scope,'until',p_until);id=private.vet_receipt(c.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.person_procedure_authorizations(clinic_id,case_id,person_id,scope,valid_until,granted_by) values(c.clinic_id,c.id,p_person,p_scope,until_at,auth.uid()) returning person_procedure_authorizations.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(c.clinic_id,auth.uid(),'clinical_procedure_authorized',id);return id;
end $$;
create or replace function public.clinical_authorization_revoke(p_id uuid,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare a public.person_procedure_authorizations;c public.clinical_cases;id uuid;fp jsonb;
begin
 select * into a from public.person_procedure_authorizations where person_procedure_authorizations.id=p_id;
 select * into c from public.clinical_cases where clinical_cases.id=a.case_id for update;
 if not found or c.responsible_id<>auth.uid() or not (private.has_clinic_role(c.clinic_id,array['mvz']) or private.rx_professional(c.clinic_id,auth.uid())) then raise exception 'responsible_mvz_required';end if;
 fp=jsonb_build_object('kind','clinical_revoke','grant',p_id,'reason',p_reason);id=private.vet_receipt(c.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.person_procedure_revocations(authorization_id,reason,created_by) values(p_id,p_reason,auth.uid()) returning person_procedure_revocations.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(c.clinic_id,auth.uid(),'clinical_procedure_revoked',id);return id;
end $$;
create or replace function public.clinical_death_add(p_consent uuid,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.form_documents;id uuid;fp jsonb;t timestamptz;k text;previous uuid;
begin
 select * into d from public.form_documents where form_documents.id=p_consent for update;
 if not found or d.state<>'signed' or d.snapshot->'schema'->>'type'<>'euthanasia' or d.responsible_id<>auth.uid() or not (private.has_clinic_role(d.clinic_id,array['mvz']) or private.rx_professional(d.clinic_id,auth.uid())) then raise exception 'responsible_mvz_required';end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'invalid_death_record';end if;
 foreach k in array array['result','method','findings','observed_at'] loop
  if jsonb_typeof(p_data->k) is distinct from 'string' or length(btrim(p_data->>k)) not between 1 and 4000 then raise exception 'required_death_field';end if;
 end loop;
 foreach k in array array['body_disposition','cost','notes','correction_reason'] loop
  if p_data ? k and (jsonb_typeof(p_data->k) is distinct from 'string' or length(p_data->>k)>4000) then raise exception 'invalid_death_field';end if;
 end loop;
 t=private.clinical_time(p_data->>'observed_at');if t<d.accepted_at or t>clock_timestamp() then raise exception 'post_consent_time_required';end if;
 previous=nullif(p_data->>'replaces_id','')::uuid;
 if previous is not null and (coalesce(length(btrim(p_data->>'correction_reason')),0)=0 or not exists(select 1 from public.clinical_death_records where clinical_death_records.id=previous and consent_id=d.id)) then raise exception 'correction_reference_required';end if;
 fp=jsonb_build_object('kind','death_record','consent',p_consent,'data',p_data);id=private.vet_receipt(d.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.clinical_death_records(clinic_id,patient_id,consent_id,result,method,findings,observed_at,body_disposition,cost,notes,recorded_by,replaces_id,correction_reason)
 values(d.clinic_id,d.patient_id,d.id,p_data->>'result',p_data->>'method',p_data->>'findings',t,coalesce(p_data->>'body_disposition',''),coalesce(p_data->>'cost',''),coalesce(p_data->>'notes',''),auth.uid(),previous,p_data->>'correction_reason') returning clinical_death_records.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),d.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(d.clinic_id,auth.uid(),'clinical_death_record_added',id);return id;
end $$;
create or replace function private.clinical_eligible(c public.clinical_cases,person uuid,scope text,at_time timestamptz) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.clinic_members m where m.clinic_id=c.clinic_id and m.user_id=person and (m.role in ('mvz','auxiliar') or (m.role='admin' and private.rx_professional(c.clinic_id,person)))) and (
 exists(select 1 from public.case_staff_assignments s where s.case_id=c.id and s.person_id=person and exists(select 1 from public.clinic_members m where m.clinic_id=c.clinic_id and m.user_id=person and (m.role='mvz' or private.rx_professional(c.clinic_id,person)))) or
 exists(select 1 from public.person_procedure_authorizations a where a.case_id=c.id and a.person_id=person and a.scope=$3 and a.created_at<=at_time and a.valid_until>=at_time and not exists(select 1 from public.person_procedure_revocations r where r.authorization_id=a.id and r.created_at<=at_time)));
$$;

alter table public.form_documents add column professional_profile_id uuid references public.professional_profiles(id);
alter table public.form_documents add column professional_delegation_id uuid references public.professional_delegations(id);
alter table public.form_documents add column shared_professional_signature boolean not null default false;
create function private.form_professional_check(d public.form_documents) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.professional_profiles;v jsonb;g public.professional_delegations;
begin
 if d.professional_profile_id is null then return null;end if;
 select * into p from public.professional_profiles where id=d.professional_profile_id and clinic_id=d.clinic_id for update;
 if not found or not private.rx_professional(d.clinic_id,p.user_id) then raise exception 'authorized_profile_required';end if;
 if p.user_id<>auth.uid() then
  select * into g from public.professional_delegations where id=d.professional_delegation_id and profile_id=p.id and recipient_id=auth.uid() and case_id is null and use_data and (not d.shared_professional_signature or use_signature) and valid_until>clock_timestamp();
  if not found or exists(select 1 from public.professional_delegation_revocations where delegation_id=g.id) then raise exception 'delegation_revoked_or_expired';end if;
 end if;
 v=private.rx_profile(p.id);if coalesce(v->>'license','')='' then raise exception 'professional_license_required';end if;
 return v;
end $$;
create function public.form_document_use_profile(p_id uuid,p_revision integer,p_profile uuid,p_share boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;p public.professional_profiles;g public.professional_delegations;v jsonb;
begin
 select * into d from public.form_documents where id=p_id for update;
 if not found or d.state='signed' or d.revision is distinct from p_revision or d.responsible_id<>auth.uid() or not private.rx_professional(d.clinic_id,auth.uid()) then raise exception 'responsible_professional_only';end if;
 select * into p from public.professional_profiles where id=p_profile and clinic_id=d.clinic_id for update;
 if not found then raise exception 'profile_in_clinic_required';end if;
 if p.user_id<>auth.uid() then select * into g from public.professional_delegations where profile_id=p.id and recipient_id=auth.uid() and case_id is null and use_data and (not p_share or use_signature) and valid_until>clock_timestamp() and not exists(select 1 from public.professional_delegation_revocations r where r.delegation_id=professional_delegations.id) order by created_at desc limit 1;end if;
 d.professional_profile_id=p.id;d.professional_delegation_id=g.id;d.shared_professional_signature=p_share;v=private.form_professional_check(d);
 perform public.form_document_save(d.id,d.revision,d.values||jsonb_build_object('mvz_name',v->>'name','mvz_license',v->>'license'),d.branding);
 update public.form_documents set professional_profile_id=p.id,professional_delegation_id=g.id,shared_professional_signature=p_share,snapshot=snapshot||jsonb_build_object('professional_profile_id',p.id,'shared_professional_signature',p_share) where id=d.id returning * into d;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(d.clinic_id,auth.uid(),'form_professional_identity_bound',d.id);return to_jsonb(d);
end $$;

create function public.rx_hospital(p_case uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.clinical_cases;
begin
 select * into c from public.clinical_cases where id=p_case;
 if not found or not private.rx_case(c) then raise exception 'case_access_required';end if;
 return jsonb_build_object('stays',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'cage',s.cage)) from public.hospital_stays s where s.clinic_id=c.clinic_id and s.patient_id=c.patient_id and s.discharged_at is null),'[]'),
 'tasks',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'label',t.label,'due_at',t.due_at,'prescription_item_id',t.prescription_item_id)) from public.hospital_tasks t join public.hospital_stays s on s.id=t.stay_id where t.clinic_id=c.clinic_id and s.patient_id=c.patient_id and t.kind='medicacion' and t.medication_record_id is null and (t.clinical_case_id is null or t.clinical_case_id=c.id) and t.state='pending'),'[]'));
end $$;
create or replace function public.form_clinical_staff(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'role',m.role,'professional',private.rx_professional(m.clinic_id,m.user_id),'label',coalesce(nullif(u.email,''),m.user_id::text))) from public.clinic_members m join auth.users u on u.id=m.user_id where m.clinic_id=p_clinic and (m.role in ('mvz','auxiliar') or (m.role='admin' and private.rx_professional(m.clinic_id,m.user_id)))),'[]');
end $$;
create or replace function private.clinical_document_check(d public.form_documents) returns void language plpgsql security definer set search_path='' as $$
declare k text;v jsonb=d.values;ct text=d.snapshot->'schema'->>'type';p uuid;n numeric;
begin
 if ct not in ('clinical_history','surgical_sheet','surgical_risk') then return;end if;
 if coalesce(length(btrim(v->>'reason')),0) not between 1 and 300 then raise exception 'clinical_reason_required';end if;
 foreach k in array array['antecedents','subjective','objective','assessment','plan','asa','ekg','notes'] loop
  if length(coalesce(v->>k,''))>4000 then raise exception 'clinical_field_too_long';end if;
 end loop;
 if (v->>'clinical_date')::date>current_date then raise exception 'future_clinical_date';end if;
 if ct='clinical_history' and coalesce(btrim(v->>'subjective'),'')='' and coalesce(btrim(v->>'objective'),'')='' and coalesce(btrim(v->>'assessment'),'')='' and coalesce(btrim(v->>'plan'),'')='' then raise exception 'soap_required';end if;
 foreach k in array array['surgeon_id','anesthetist_id'] loop
  if coalesce(v->>k,'')<>'' then
   p=(v->>k)::uuid;
   if not exists(select 1 from public.clinic_members where clinic_id=d.clinic_id and user_id=p and (role='mvz' or private.rx_professional(d.clinic_id,p))) then raise exception 'assigned_mvz_not_in_clinic';end if;
  end if;
 end loop;
 if coalesce(v->>'consent_id','')<>'' and not exists(select 1 from public.form_documents consent where consent.id=(v->>'consent_id')::uuid and consent.clinic_id=d.clinic_id and consent.patient_id=d.patient_id and consent.state='signed' and consent.snapshot->'schema'->>'type'='surgery' and private.form_readable(consent)) then raise exception 'matching_signed_surgery_consent_required';end if;
 foreach k in array array['weight','fc','fr','temperature','tllc','bp_systolic','bp_diastolic'] loop
  if coalesce(v->>k,'')<>'' then
   n=(v->>k)::numeric;
   if (k='weight' and n<=0) or (k<>'temperature' and n<0) then raise exception 'invalid_measurement';end if;
   if private.clinical_time(v->>'observed_at')>clock_timestamp() or private.clinical_time(v->>'observed_at')::date<>(v->>'clinical_date')::date then raise exception 'measurement_time_required';end if;
  end if;
 end loop;
end $$;

alter table public.medication_vial_movements add column kind text not null default 'toma' check(kind in ('toma','correccion','merma','devolucion','ajuste'));
alter table public.medication_vial_movements add column created_by uuid references auth.users(id);
create function public.rx_vial_adjust(p_id uuid,p_kind text,p_delta text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v public.medication_vials;id uuid;fp jsonb;n numeric;
begin
 select clinic_id into v.clinic_id from public.medication_vials where medication_vials.id=p_id;
 perform pg_advisory_xact_lock(hashtextextended('rx-ledger-'||v.clinic_id::text,0));
 select * into v from public.medication_vials where medication_vials.id=p_id for update;
 if not found or v.responsible_id<>auth.uid() or not private.rx_professional(v.clinic_id,auth.uid()) then raise exception 'vial_responsible_required';end if;
 if exists(select 1 from public.medication_vial_reconciliations where vial_id=v.id) then raise exception 'closed_vial_adjustment_denied';end if;
 if p_delta is null or p_delta !~ '^-?\d{1,12}(\.\d{1,9})?$' or p_delta::numeric=0 or p_kind not in ('merma','devolucion','ajuste') or coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'exact_adjustment_and_reason_required';end if;
 n=p_delta::numeric;if (p_kind='merma' and n>=0) or (p_kind='devolucion' and n<=0) then raise exception 'movement_direction_mismatch';end if;
 fp=jsonb_build_object('kind','vial_adjust','vial',p_id,'movement',p_kind,'delta',p_delta,'reason',p_reason);id=private.vet_receipt(v.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.medication_vial_movements(clinic_id,vial_id,delta,reason,kind,created_by) values(v.clinic_id,v.id,n,p_reason,p_kind,auth.uid()) returning medication_vial_movements.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),v.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(v.clinic_id,auth.uid(),'medication_vial_adjustment_appended',id);return id;
end $$;
create unique index rx_profile_clinic_identity on public.professional_delegations(clinic_id,id);
create unique index rx_item_clinic_identity on public.prescription_items(clinic_id,id);
create unique index rx_hospital_task_identity on public.hospital_tasks(clinic_id,id);
alter table public.form_documents add constraint form_profile_same_clinic foreign key(clinic_id,professional_profile_id) references public.professional_profiles(clinic_id,id);
alter table public.form_documents add constraint form_delegation_same_clinic foreign key(clinic_id,professional_delegation_id) references public.professional_delegations(clinic_id,id);
alter table public.hospital_tasks add constraint hospital_record_same_clinic foreign key(clinic_id,medication_record_id) references public.medication_records(clinic_id,id);
alter table public.hospital_tasks add constraint hospital_rx_item_same_clinic foreign key(clinic_id,prescription_item_id) references public.prescription_items(clinic_id,id);
alter table public.medication_records add constraint medication_task_same_clinic foreign key(clinic_id,hospital_task_id) references public.hospital_tasks(clinic_id,id);
-- Patient/case timeline uses these same medication rows, never a second anesthetic drug list.
-- Client endpoints cannot grant professional status or publish regulatory references.
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (p.proname like 'rx_%' or p.proname in ('form_professional_check','form_document_use_profile')) and n.nspname in ('public','private') loop execute 'revoke all on function '||f.signature||' from public,anon,authenticated';end loop;
end $$;
grant execute on function private.rx_readable(public.prescriptions),private.rx_case(public.clinical_cases),private.rx_professional(uuid,uuid) to authenticated;
grant execute on function public.rx_professional_authorize(uuid,uuid,boolean,timestamptz,text),public.rx_pdf_register(text,uuid,integer,text,text,text) to service_role;
grant execute on function public.form_document_use_profile(uuid,integer,uuid,boolean),public.rx_profiles(uuid),public.rx_profile_save(uuid,integer,text,text,text,jsonb,text),public.rx_delegations(uuid),public.rx_delegate(uuid,uuid,uuid,jsonb,text,text),public.rx_delegate_revoke(uuid,text,text),
 public.rx_create(uuid,jsonb,text,text,text),public.rx_save(uuid,integer,jsonb,text,text),public.rx_list(uuid,uuid),public.rx_snapshot(uuid),public.rx_prepare(uuid,integer,uuid,boolean,jsonb),public.rx_finalize(uuid,integer,text),
 public.rx_vial_open(uuid,uuid,text,text,text,uuid,uuid,text),public.rx_vials(uuid),public.rx_vial_adjust(uuid,text,text,text,text),public.rx_vial_close(uuid,text,text,text),public.rx_medication_report(uuid,jsonb,text),public.rx_medications(uuid),public.rx_medication_review(uuid,text,text,text,text),
 public.rx_hospital(uuid),public.rx_schedule(uuid,uuid,uuid,jsonb,text),public.rx_report_create(uuid,text,text,boolean,text),public.rx_reports(uuid),public.rx_report_finalize(uuid,text),public.rx_pdf_snapshot(text,uuid),public.rx_pdf_read(text,uuid) to authenticated;
commit;
