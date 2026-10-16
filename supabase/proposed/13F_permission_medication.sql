-- LOCAL CANDIDATE 13F. Do not deploy independently or activate beta.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
insert into private.permission_catalog(code,label,procedure_scoped,requires_professional) values
 ('vial.read','Consultar frascos y saldos',false,false),('vial.manage','Abrir y conciliar frascos',false,true);
alter table public.medication_records add column procedure_type_id uuid;
alter table public.medication_records add constraint medication_procedure_clinic foreign key(clinic_id,procedure_type_id) references private.procedure_types(clinic_id,id);
alter table public.medication_records add column scope_binding_id uuid references private.clinical_scope_bindings(id);
alter table public.medication_records add column report_grant_id uuid references private.member_permission_grants(id);
alter table public.medication_records add column administer_grant_id uuid references private.member_permission_grants(id);
alter table public.medication_records add column draw_grant_id uuid references private.member_permission_grants(id);
alter table public.medication_records add column correction_grant_id uuid references private.member_permission_grants(id);
alter table public.medication_records add constraint medication_authority_pair check(
 (procedure_type_id is null and scope_binding_id is null and report_grant_id is null and administer_grant_id is null and draw_grant_id is null and correction_grant_id is null)
 or (procedure_type_id is not null and scope_binding_id is not null and report_grant_id is not null and administer_grant_id is not null));
alter table public.controlled_drug_reviews add column permission_grant_id uuid references private.member_permission_grants(id);
-- Historical authority stays NULL; no automatic professional or role conversion.
create function private.medication_lock(p_clinic uuid) returns void language plpgsql security definer set search_path='' as $$begin
 perform 1 from public.clinics where id=p_clinic for update;
 perform pg_advisory_xact_lock(hashtextextended('rx-ledger-'||p_clinic::text,0));
end$$;
create function private.medication_case_lock(p_case uuid) returns public.clinical_cases language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;person uuid;begin
 select * into c from public.clinical_cases where id=p_case;
 if not found then raise exception 'case_access_required';end if;
 perform private.medication_lock(c.clinic_id);
 select * into c from public.clinical_cases where id=p_case for update;
 if not private.clinical_readable(c) then raise exception 'case_access_required';end if;
 for person in select distinct x from unnest(array[auth.uid(),c.responsible_id]) x order by x loop
 perform pg_advisory_xact_lock(hashtextextended(person::text,9061));end loop;
 if not private.clinical_professional_at(c.clinic_id,c.responsible_id,clock_timestamp()) then raise exception 'case_verified_responsible_required';end if;
 return c;
end$$;
create function private.medication_permission(p_clinic uuid,p_code text,p_procedure uuid default null,p_observed timestamptz default null) returns uuid language plpgsql security definer set search_path='' as $$
declare g uuid;begin
 g=private.hospital_order_permission(p_clinic,p_code,p_procedure,false);
 if p_observed is not null and not exists(select 1 from private.member_permission_grants where id=g and granted_at<=p_observed and valid_until>p_observed) then raise exception 'permission_not_valid_at_application';end if;
 return g;
end$$;
create function private.vial_readable(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.permission_effective(p_clinic,auth.uid(),'vial.read') is not null;
$$;
revoke all on function private.medication_lock(uuid),private.medication_case_lock(uuid),private.medication_permission(uuid,text,uuid,timestamptz),private.vial_readable(uuid) from public,anon,authenticated;
grant execute on function private.vial_readable(uuid) to authenticated;
drop policy rx_vial_read on public.medication_vials;
drop policy rx_reconciliation_read on public.medication_vial_reconciliations;
create policy rx_vial_read on public.medication_vials for select to authenticated using(private.vial_readable(clinic_id));
create policy rx_reconciliation_read on public.medication_vial_reconciliations for select to authenticated using(private.vial_readable(clinic_id));
create or replace function public.rx_medication_report(p_case uuid,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;p public.medication_product_versions;v public.medication_vials;previous public.medication_records;v_record_id uuid;fp jsonb;n numeric;t timestamptz;performer uuid;vial uuid;balance numeric;delta numeric;incidence text='';lot text;task public.hospital_tasks;stay public.hospital_stays;prescription public.prescriptions;ctx jsonb;rg uuid;ag uuid;dg uuid;cg uuid;
begin
 c=private.medication_case_lock(p_case);
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'typed_medication_required';end if;
 select * into p from public.medication_product_versions where medication_product_versions.id=((p_data->>'product_version_id'))::uuid;
 if not found then raise exception 'product_version_required';end if;
 n=private.rx_quantity((p_data->>'quantity'));t=private.clinical_time((p_data->>'observed_at'));performer=((p_data->>'performed_by'))::uuid;
 if t>clock_timestamp() or (t at time zone 'UTC')::date<c.clinical_date then raise exception 'invalid_observation_time';end if;
 if (p_data->>'unit') is distinct from p.unit or coalesce(length(btrim((p_data->>'route'))),0) not between 1 and 200 or p_data->>'procedure' is null or (p_data->>'procedure') not in ('evaluacion','cirugia','anestesia','recuperacion','cuidados') then raise exception 'medication_fields_required';end if;
 if nullif(p_data->>'replaces_id','') is not null then
  select * into previous from public.medication_records where id=(p_data->>'replaces_id')::uuid and case_id=c.id for update;
  cg=private.medication_permission(c.clinic_id,'medication.validate');
  if previous.id is null or c.responsible_id<>auth.uid() or not private.clinical_professional_at(c.clinic_id,auth.uid(),clock_timestamp()) or coalesce(length(btrim(p_data->>'correction_reason')),0) not between 1 and 1000 then raise exception 'responsible_correction_required';end if;
  if previous.scope_binding_id is null then raise exception 'legacy_medication_reauthorization_required';end if;
  if previous.product_version_id<>p.id or previous.unit<>p.unit or previous.performed_by<>performer or previous.procedure is distinct from p_data->>'procedure' or previous.observed_at is distinct from t then raise exception 'correction_identity_changed';end if;
  ctx=jsonb_build_object('binding_id',previous.scope_binding_id,'procedure_id',previous.procedure_type_id);
  rg=previous.report_grant_id;ag=previous.administer_grant_id;dg=previous.draw_grant_id;
 else
  if performer is distinct from auth.uid() then raise exception 'own_act_only';end if;
  ctx=private.clinical_permission_context(c,p_data->>'procedure',performer,t);
  rg=private.medication_permission(c.clinic_id,'medication.report',null,t);
  ag=private.medication_permission(c.clinic_id,'drug.administer',(ctx->>'procedure_id')::uuid,t);
  if nullif(p_data->>'vial_id','') is not null then dg=private.medication_permission(c.clinic_id,'vial.draw',(ctx->>'procedure_id')::uuid,t);end if;
 end if;
 fp=jsonb_build_object('kind','medication','case',p_case,'data',p_data);v_record_id=private.vet_receipt(c.clinic_id,p_operation,fp);if v_record_id is not null then return v_record_id;end if;
 if previous.id is not null and exists(select 1 from public.medication_records where replaces_id=previous.id) then raise exception 'record_already_corrected';end if;
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
  if task.id is null or task.prescription_item_id is null or task.clinical_case_id is distinct from c.id or stay.patient_id<>c.patient_id or task.kind<>'medicacion' then raise exception 'matching_hospital_medication_task_required';end if;
  if task.procedure_type_id is null or task.authority_grant_id is null then raise exception 'legacy_medication_task_reauthorization_required';end if;
  if task.medication_record_id is not null or task.state='done' then raise exception 'task_already_confirmed';end if;
  if previous.id is not null then raise exception 'correction_task_must_not_reconfirm';end if;
  if task.procedure_type_id is not null and task.procedure_type_id is distinct from (ctx->>'procedure_id')::uuid then raise exception 'scheduled_procedure_mismatch';end if;
  if task.prescription_item_id is not null and (task.clinical_case_id<>c.id or not exists(select 1 from public.prescription_items where prescription_items.id=task.prescription_item_id and product_version_id=p.id)) then raise exception 'scheduled_product_case_mismatch';end if;
  if task.prescription_item_id is not null then
   if prescription.id is not null and prescription.id<>(select prescription_id from public.prescription_items where prescription_items.id=task.prescription_item_id) then raise exception 'scheduled_prescription_mismatch';end if;
   select * into prescription from public.prescriptions where prescriptions.id=(select prescription_id from public.prescription_items where prescription_items.id=task.prescription_item_id);
  end if;
  if task.due_at>t then incidence=incidence||' · Aplicación anterior a la hora programada';end if;
  if task.state='cancelled' or stay.discharged_at is not null then incidence=incidence||' · Tarea cancelada / estancia cerrada';end if;
 end if;
 insert into public.medication_records(clinic_id,case_id,patient_id,product_version_id,prescription_id,hospital_task_id,vial_id,quantity,unit,route,procedure,performed_by,reported_by,responsible_id,observed_at,lot,replaces_id,correction_reason,incidence,content_hash,procedure_type_id,scope_binding_id,report_grant_id,administer_grant_id,draw_grant_id,correction_grant_id)
 values(c.clinic_id,c.id,c.patient_id,p.id,prescription.id,task.id,vial,n,p.unit,(p_data->>'route'),(p_data->>'procedure'),performer,auth.uid(),c.responsible_id,t,lot,previous.id,(p_data->>'correction_reason'),incidence,encode(sha256(convert_to(fp::text,'UTF8')),'hex'),(ctx->>'procedure_id')::uuid,(ctx->>'binding_id')::uuid,rg,ag,dg,cg) returning medication_records.id into v_record_id;
 if vial is not null then insert into public.medication_vial_movements(clinic_id,vial_id,record_id,delta,kind,created_by,reason) values(c.clinic_id,vial,v_record_id,delta,case when previous.id is null then 'toma' else 'correccion' end,auth.uid(),case when previous.id is null then 'Toma reportada, no implica validación' else 'Rectificación contable de captura; no devolución física: '||(p_data->>'correction_reason') end);end if;
 if task.id is not null then update public.hospital_tasks set medication_record_id=v_record_id,
 state=case when state='pending' then 'done' else state end,
 performed_by=case when state='pending' then performer else performed_by end,
 performed_at=case when state='pending' then t else performed_at end,version=version+1 where hospital_tasks.id=task.id;end if;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,v_record_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(c.clinic_id,auth.uid(),'medication_application_reported_pending_review',v_record_id,jsonb_build_object('procedure_id',ctx->>'procedure_id','binding_id',ctx->>'binding_id','report_grant_id',rg,'administer_grant_id',ag,'draw_grant_id',dg,'correction_grant_id',cg));return v_record_id;
end $$;
create or replace function public.rx_medication_review(p_id uuid,p_hash text,p_decision text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.medication_records;c public.clinical_cases;id uuid;fp jsonb;g uuid;
begin
 select * into r from public.medication_records where medication_records.id=p_id;
 c=private.medication_case_lock(r.case_id);
 g=private.medication_permission(c.clinic_id,'medication.validate');
 if r.responsible_id<>auth.uid() or c.responsible_id<>auth.uid() or not private.clinical_professional_at(c.clinic_id,auth.uid(),clock_timestamp()) then raise exception 'responsible_verified_professional_required';end if;
 if r.report_grant_id is null then raise exception 'legacy_medication_reauthorization_required';end if;
 if p_decision is null or p_decision not in ('validada','requiere_correccion') or coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'review_decision_and_reason_required';end if;
 fp=jsonb_build_object('kind','medication_review','record',p_id,'hash',p_hash,'decision',p_decision,'reason',p_reason);id=private.vet_receipt(r.clinic_id,p_operation,fp);if id is not null then return id;end if;
 if r.content_hash is distinct from p_hash or exists(select 1 from public.medication_records where replaces_id=r.id) then raise exception 'exact_current_record_required';end if;
 if p_decision='validada' and r.incidence<>'' then raise exception 'unresolved_incidence_requires_correction';end if;
 insert into public.controlled_drug_reviews(clinic_id,record_id,content_hash,decision,reason,validated_by,permission_grant_id) values(r.clinic_id,r.id,r.content_hash,p_decision,p_reason,auth.uid(),g) returning controlled_drug_reviews.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),r.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(r.clinic_id,auth.uid(),'medication_record_reviewed',id,jsonb_build_object('permission_grant_id',g,'record_id',r.id,'content_hash',r.content_hash));return id;
end $$;
create or replace function public.rx_vial_open(p_clinic uuid,p_product uuid,p_lot text,p_volume text,p_opened text,p_inventory uuid,p_inventory_lot uuid,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.medication_product_versions;id uuid;fp jsonb;opened timestamptz;g uuid;
begin
 perform private.medication_lock(p_clinic);g=private.hospital_order_permission(p_clinic,'vial.manage',null,true);
 select * into p from public.medication_product_versions where medication_product_versions.id=p_product;
 if not found or p.unit<>'ml' then raise exception 'volume_product_required';end if;
 if coalesce(length(btrim(p_lot)),0) not between 1 and 200 then raise exception 'lot_required';end if;
 if p_inventory is not null and not exists(select 1 from public.inventario where inventario.id=p_inventory and clinic_id=p_clinic) then raise exception 'inventory_wrong_clinic';end if;
 if p_inventory_lot is not null and not exists(select 1 from public.lotes_inventario where lotes_inventario.id=p_inventory_lot and clinic_id=p_clinic and item_id=p_inventory and lote=p_lot) then raise exception 'lot_inventory_mismatch';end if;
 opened=private.clinical_time(p_opened);if opened>clock_timestamp() then raise exception 'future_opening';end if;
 fp=jsonb_build_object('kind','vial_open','product',p_product,'lot',p_lot,'volume',p_volume,'opened',p_opened,'inventory',p_inventory,'inventory_lot',p_inventory_lot);id=private.vet_receipt(p_clinic,p_operation,fp);if id is not null then return id;end if;
 insert into public.medication_vials(clinic_id,product_version_id,inventory_id,inventory_lot_id,lot,initial_volume,unit,responsible_id,opened_at) values(p_clinic,p_product,p_inventory,p_inventory_lot,p_lot,private.rx_quantity(p_volume),'ml',auth.uid(),opened) returning medication_vials.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'medication_vial_opened',id,jsonb_build_object('permission_grant_id',g));return id;
end $$;
create or replace function public.rx_vial_close(p_id uuid,p_measured text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v public.medication_vials;id uuid;fp jsonb;measured numeric;expected numeric;difference numeric;g uuid;
begin
 select clinic_id into v.clinic_id from public.medication_vials where medication_vials.id=p_id;
 perform private.medication_lock(v.clinic_id);g=private.hospital_order_permission(v.clinic_id,'vial.manage',null,true);
 select * into v from public.medication_vials where medication_vials.id=p_id for update;
 if not found or v.responsible_id<>auth.uid() then raise exception 'vial_responsible_required';end if;
 if p_measured is null or p_measured !~ '^\d{1,12}(\.\d{1,9})?$' then raise exception 'exact_measured_volume_required';end if;
 measured=p_measured::numeric;expected=private.rx_vial_balance(v.id);difference=measured-expected;
 if (difference<>0 or expected<0) and coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'discrepancy_mvZ_note_required';end if;
 fp=jsonb_build_object('kind','vial_close','vial',p_id,'measured',p_measured,'reason',p_reason);id=private.vet_receipt(v.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.medication_vial_reconciliations(clinic_id,vial_id,expected,measured,difference,reason,created_by) values(v.clinic_id,v.id,expected,measured,difference,coalesce(p_reason,''),auth.uid()) returning medication_vial_reconciliations.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),v.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(v.clinic_id,auth.uid(),'medication_vial_closed_with_reconciliation',id,jsonb_build_object('permission_grant_id',g));return id;
end $$;
create or replace function public.rx_vial_adjust(p_id uuid,p_kind text,p_delta text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v public.medication_vials;id uuid;fp jsonb;n numeric;g uuid;
begin
 select clinic_id into v.clinic_id from public.medication_vials where medication_vials.id=p_id;
 perform private.medication_lock(v.clinic_id);g=private.hospital_order_permission(v.clinic_id,'vial.manage',null,true);
 select * into v from public.medication_vials where medication_vials.id=p_id for update;
 if not found or v.responsible_id<>auth.uid() then raise exception 'vial_responsible_required';end if;
 if not exists(select 1 from public.medication_product_versions p where p.id=v.product_version_id and p.classification='no_controlado' and private.rx_product_verified(p)) then raise exception 'controlled_or_unverified_vial_adjustment_denied';end if;
 if exists(select 1 from public.medication_vial_reconciliations where vial_id=v.id) then raise exception 'closed_vial_adjustment_denied';end if;
 if p_delta is null or p_delta !~ '^-?\d{1,12}(\.\d{1,9})?$' or p_delta::numeric=0 or p_kind not in ('merma','devolucion','ajuste') or coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'exact_adjustment_and_reason_required';end if;
 n=p_delta::numeric;if (p_kind='merma' and n>=0) or (p_kind='devolucion' and n<=0) then raise exception 'movement_direction_mismatch';end if;
 fp=jsonb_build_object('kind','vial_adjust','vial',p_id,'movement',p_kind,'delta',p_delta,'reason',p_reason);id=private.vet_receipt(v.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.medication_vial_movements(clinic_id,vial_id,delta,reason,kind,created_by) values(v.clinic_id,v.id,n,p_reason,p_kind,auth.uid()) returning medication_vial_movements.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),v.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(v.clinic_id,auth.uid(),'medication_vial_adjustment_appended',id,jsonb_build_object('permission_grant_id',g));return id;
end $$;
create or replace function public.rx_medications(p_case uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.clinical_cases;
begin
 select * into c from public.clinical_cases where id=p_case;
 if not found or not private.clinical_readable(c) then raise exception 'case_access_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('quantity',r.quantity::text,'product_name',p.name,'presentation',p.presentation,'classification',p.classification,'source_status',p.source_status,'superseded',exists(select 1 from public.medication_records n where n.replaces_id=r.id),'review',(select to_jsonb(v) from public.controlled_drug_reviews v where v.record_id=r.id and v.content_hash=r.content_hash order by v.validated_at desc,v.id desc limit 1),'dose_reference',null,'can_correct',r.report_grant_id is not null and c.responsible_id=auth.uid() and private.professional_current(c.clinic_id,auth.uid()) and private.permission_effective(c.clinic_id,auth.uid(),'medication.validate') is not null) order by r.observed_at,r.reported_at) from public.medication_records r join public.medication_product_versions p on p.id=r.product_version_id where r.case_id=c.id),'[]');
end $$;
drop policy rx_record_read on public.medication_records;
drop policy rx_review_read on public.controlled_drug_reviews;
drop policy rx_movement_read on public.medication_vial_movements;
create policy rx_record_read on public.medication_records for select to authenticated using(exists(select 1 from public.clinical_cases c where c.id=case_id and private.clinical_readable(c)));
create policy rx_review_read on public.controlled_drug_reviews for select to authenticated using(exists(select 1 from public.medication_records r join public.clinical_cases c on c.id=r.case_id where r.id=record_id and private.clinical_readable(c)));
create policy rx_movement_read on public.medication_vial_movements for select to authenticated using(private.vial_readable(clinic_id) and (record_id is null or exists(select 1 from public.medication_records r join public.clinical_cases c on c.id=r.case_id where r.id=record_id and private.clinical_readable(c))));
create or replace function public.rx_vials(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.vial_readable(p_clinic) then raise exception 'explicit_permission_required';end if;
 return (select coalesce(jsonb_agg(to_jsonb(v)||jsonb_build_object('product_name',p.name,'balance',private.rx_vial_balance(v.id)::text,
 'can_manage',v.responsible_id=auth.uid() and private.professional_current(p_clinic,auth.uid()) and private.permission_effective(p_clinic,auth.uid(),'vial.manage') is not null,
 'can_adjust',v.responsible_id=auth.uid() and private.professional_current(p_clinic,auth.uid()) and private.permission_effective(p_clinic,auth.uid(),'vial.manage') is not null and p.classification='no_controlado' and private.rx_product_verified(p),
 'movements',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('delta',m.delta::text) order by m.created_at,m.id) from public.medication_vial_movements m where m.vial_id=v.id and (m.record_id is null or exists(select 1 from public.medication_records r join public.clinical_cases c on c.id=r.case_id where r.id=m.record_id and private.clinical_readable(c)))),'[]'),
 'closed',exists(select 1 from public.medication_vial_reconciliations where vial_id=v.id),
 'closure',(select to_jsonb(x) from public.medication_vial_reconciliations x where x.vial_id=v.id))) ,'[]') from public.medication_vials v join public.medication_product_versions p on p.id=v.product_version_id where v.clinic_id=p_clinic);
end$$;
create function public.rx_operational_permissions(p_clinic uuid,p_case uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.clinical_cases;professional boolean;begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'clinic_membership_required';end if;
 professional=private.professional_current(p_clinic,auth.uid());
 if p_case is not null then
  select * into c from public.clinical_cases where id=p_case and clinic_id=p_clinic;
  if not found or not private.clinical_readable(c) then raise exception 'case_access_required';end if;
 end if;
 return jsonb_build_object('schema_version',1,'typed_medication_schedule',true,
 'professional_current',professional,
 'vial.read',private.vial_readable(p_clinic),
 'vial.manage',professional and private.permission_effective(p_clinic,auth.uid(),'vial.manage') is not null,
 'medication.validate',p_case is not null and c.responsible_id=auth.uid() and professional and private.permission_effective(p_clinic,auth.uid(),'medication.validate') is not null,
 'hospital.read',private.permission_effective(p_clinic,auth.uid(),'hospital.read') is not null,
 'hospital.schedule',professional and private.permission_effective(p_clinic,auth.uid(),'hospital.schedule') is not null,
 'scopes',(select coalesce(jsonb_agg(jsonb_build_object('scope',b.scope,'procedure_id',b.procedure_id,
 'administer',private.clinical_eligible(c,auth.uid(),b.scope,clock_timestamp()) and private.permission_effective(p_clinic,auth.uid(),'medication.report') is not null and private.permission_effective(p_clinic,auth.uid(),'drug.administer',b.procedure_id) is not null,
 'draw',private.permission_effective(p_clinic,auth.uid(),'vial.draw',b.procedure_id) is not null) order by b.scope),'[]') from private.clinical_scope_bindings b where b.case_id=p_case and b.scope<>'observaciones' and not exists(select 1 from private.clinical_scope_revocations r where r.binding_id=b.id)));
end$$;
create or replace function public.rx_hospital(p_case uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.clinical_cases;begin
 select * into c from public.clinical_cases where id=p_case;
 if not found or not private.clinical_readable(c) or private.permission_effective(c.clinic_id,auth.uid(),'hospital.read') is null then raise exception 'case_hospital_access_required';end if;
 return jsonb_build_object('stays',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'cage',s.cage)),'[]') from public.hospital_stays s where s.clinic_id=c.clinic_id and s.patient_id=c.patient_id and s.discharged_at is null),
 'tasks',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',t.label,'due_at',t.due_at,'prescription_item_id',t.prescription_item_id,'procedure_type_id',t.procedure_type_id)),'[]') from public.hospital_tasks t join public.hospital_stays s on s.id=t.stay_id and s.clinic_id=t.clinic_id where t.clinic_id=c.clinic_id and s.patient_id=c.patient_id and t.kind='medicacion' and t.prescription_item_id is not null and t.procedure_type_id is not null and t.authority_grant_id is not null and t.clinical_case_id=c.id and t.medication_record_id is null and s.discharged_at is null and t.state='pending'));
end$$;
-- Old scheduling cannot silently choose scope or alert interval for the new permission model.
create or replace function public.rx_schedule(p_id uuid,p_item uuid,p_stay uuid,p_times jsonb,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$begin
 raise exception 'typed_medication_schedule_required';
end$$;
create function public.rx_schedule_typed(p_id uuid,p_item uuid,p_stay uuid,p_scope text,p_times jsonb,p_delay integer,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;i public.prescription_items;s public.hospital_stays;c public.clinical_cases;b private.clinical_scope_bindings;g uuid;fp jsonb;receipt uuid;x jsonb;t timestamptz;id uuid;ids jsonb='[]';begin
 select * into r from public.prescriptions where prescriptions.id=p_id;
 c=private.medication_case_lock(r.case_id);
 g=private.hospital_order_permission(c.clinic_id,'hospital.schedule',null,true);
 perform private.medication_permission(c.clinic_id,'hospital.read');
 if r.state<>'issued' or r.responsible_id<>auth.uid() or r.case_id<>c.id then raise exception 'issued_responsible_prescription_required';end if;
 b=private.clinical_binding(c.id,p_scope);
 if b.id is null or p_scope='observaciones' or not exists(select 1 from private.procedure_types pt where pt.id=b.procedure_id and clinic_id=c.clinic_id and active) then raise exception 'active_scope_mapping_required';end if;
 fp=jsonb_build_object('kind','rx_schedule_typed','prescription',p_id,'item',p_item,'stay',p_stay,'scope',p_scope,'times',p_times,'delay',p_delay);
 receipt=private.vet_receipt(c.clinic_id,p_operation,fp);if receipt is not null then return (select details->'tasks' from public.audit_log where entity_id=receipt::text and action='prescription_hospital_tasks_created');end if;
 select * into i from public.prescription_items where prescription_items.id=p_item and prescription_id=r.id;
 select * into s from public.hospital_stays where hospital_stays.id=p_stay and clinic_id=c.clinic_id and patient_id=c.patient_id for update;
 -- Recheck clock after stay locks held by a pre-cutover writer.
 g=private.hospital_order_permission(c.clinic_id,'hospital.schedule',null,true);
 if i.id is null or s.id is null or s.discharged_at is not null then raise exception 'matching_active_stay_required';end if;
 if p_delay is null or p_delay not between 1 and 120 then raise exception 'explicit_alert_delay_required';end if;
 if jsonb_typeof(p_times) is distinct from 'array' or jsonb_array_length(p_times) not between 1 and 48 then raise exception 'explicit_times_required';end if;
 for x in select * from jsonb_array_elements(p_times) loop
  t=private.clinical_time(x#>>'{}');if t<=clock_timestamp() then raise exception 'future_explicit_schedule_required';end if;
 end loop;
 if (select count(distinct (element.value#>>'{}')::timestamptz) from jsonb_array_elements(p_times) element(value))<>jsonb_array_length(p_times) then raise exception 'duplicate_times';end if;
 for x in select * from jsonb_array_elements(p_times) loop
  insert into public.hospital_tasks(clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by,prescription_item_id,clinical_case_id,procedure_type_id,authority_grant_id)
  values(c.clinic_id,s.id,'medicacion',(select left(name,300) from public.medication_product_versions mp where mp.id=i.product_version_id),i.quantity::text||' '||i.unit||' · '||i.route||' · '||i.interval_text||' · '||i.duration_text,private.clinical_time(x#>>'{}'),p_delay,auth.uid(),i.id,c.id,b.procedure_id,g) returning hospital_tasks.id into id;
  ids=ids||jsonb_build_array(id);
 end loop;
 receipt=gen_random_uuid();insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,receipt);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(c.clinic_id,auth.uid(),'prescription_hospital_tasks_created',receipt,jsonb_build_object('tasks',ids,'procedure_id',b.procedure_id,'binding_id',b.id,'permission_grant_id',g));return ids;
end$$;
revoke all on function public.rx_operational_permissions(uuid,uuid),public.rx_schedule_typed(uuid,uuid,uuid,text,jsonb,integer,text) from public,anon;
grant execute on function public.rx_operational_permissions(uuid,uuid),public.rx_schedule_typed(uuid,uuid,uuid,text,jsonb,integer,text) to authenticated;
notify pgrst,'reload schema';
commit;
