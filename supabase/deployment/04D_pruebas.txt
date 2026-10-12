-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Etapa 4, bloque 4/6.
-- Ejecutar en orden; no probar funciones M6 hasta completar todos los bloques.
begin;

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
-- Cierre provisional: ningún endpoint farmacológico nuevo habilitado al cliente.
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (p.proname like 'rx_%' or p.proname in ('form_professional_check','form_document_use_profile')) and n.nspname in ('public','private') loop execute 'revoke all on function '||f.signature||' from public,anon,authenticated';end loop;
end $$;

notify pgrst, 'reload schema';
commit;
select '04D COMPLETADO (4/6)' as resultado;
-- FIN COMPLETO 04D
