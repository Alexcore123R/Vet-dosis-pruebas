-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Etapa 4, bloque 6/6.
-- Ejecutar en orden; no probar funciones M6 hasta completar todos los bloques.
begin;

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
notify pgrst, 'reload schema';
commit;
select '04F COMPLETADO (6/6)' as resultado;
-- FIN COMPLETO 04F
