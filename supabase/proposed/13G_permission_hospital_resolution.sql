-- LOCAL CANDIDATE. Complete with the coordinated cutover; no standalone deployment.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
insert into private.permission_catalog(code,label,procedure_scoped,requires_professional) values
 ('hospital.discharge','Autorizar alta hospitalaria',false,true),
 ('medication.followup','Posponer aviso o reportar una dosis no aplicada',true,false);
alter table public.hospital_tasks add column resolution_kind text check(resolution_kind in ('not_given','discharge'));
alter table public.hospital_tasks add constraint hospital_resolution_not_application check(resolution_kind is null or
 (state='cancelled' and cancelled_by is not null and cancelled_at is not null and length(btrim(cancel_reason))>0 and performed_by is null and performed_at is null and medication_record_id is null));
create function private.hospital_pending(p_clinic uuid,p_stay uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'version',t.version,'kind',t.kind,'label',t.label,'instructions',t.instructions,'due_at',t.due_at) order by t.due_at,t.id),'[]') from public.hospital_tasks t where t.clinic_id=p_clinic and t.stay_id=p_stay and t.state='pending';
$$;
revoke all on function private.hospital_pending(uuid,uuid) from public,anon,authenticated;
create function public.hospital_medication_followup(p_clinic uuid,p_task uuid,p_version integer,p_action text,p_minutes integer,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare t public.hospital_tasks;s public.hospital_stays;g uuid;fp jsonb;event_id uuid;begin
 perform private.medication_lock(p_clinic);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 select * into t from public.hospital_tasks where clinic_id=p_clinic and id=p_task;
 if not found then raise exception 'task_not_found';end if;
 select * into s from public.hospital_stays where clinic_id=p_clinic and id=t.stay_id for update;
 select * into t from public.hospital_tasks where clinic_id=p_clinic and id=p_task for update;
 if t.kind<>'medicacion' or t.procedure_type_id is null or t.authority_grant_id is null or t.prescription_item_id is null or t.clinical_case_id is null then raise exception 'typed_medication_task_required';end if;
 if not exists(select 1 from public.prescription_items i join public.prescriptions r on r.id=i.prescription_id and r.clinic_id=i.clinic_id where i.id=t.prescription_item_id and i.clinic_id=p_clinic and r.patient_id=s.patient_id and r.case_id=t.clinical_case_id and r.state='issued') then raise exception 'typed_medication_task_required';end if;
 g=private.hospital_order_permission(p_clinic,'medication.followup',t.procedure_type_id,false);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 if p_action is null or p_action not in ('snooze','not_given') or coalesce(length(btrim(p_reason)),0) not between 1 and 500 then raise exception 'followup_action_and_reason_required';end if;
 fp=jsonb_build_object('kind','medication_followup','task',p_task,'version',p_version,'action',p_action,'minutes',p_minutes,'reason',p_reason);
 event_id=private.vet_receipt(p_clinic,p_operation,fp);if event_id is not null then return event_id;end if;
 if t.state='done' or t.medication_record_id is not null then raise exception 'task_already_confirmed';end if;
 if s.discharged_at is not null or t.state<>'pending' then raise exception 'task_closed_without_application';end if;
 if t.version is distinct from p_version then raise exception 'task_version_conflict';end if;
 if t.due_at>clock_timestamp() then raise exception 'task_not_due';end if;
 if p_action='snooze' then
  if p_minutes is null or p_minutes not between 1 and 30 then raise exception 'invalid_snooze';end if;
  if t.snooze_count>=3 then raise exception 'snooze_limit';end if;
  update public.hospital_tasks set snoozed_until=clock_timestamp()+make_interval(mins=>p_minutes),snooze_count=snooze_count+1,snooze_reason=btrim(p_reason),version=version+1 where id=t.id;
 else
  if p_minutes is not null then raise exception 'not_given_has_no_interval';end if;
  update public.hospital_tasks set state='cancelled',resolution_kind='not_given',cancelled_by=auth.uid(),cancelled_at=clock_timestamp(),cancel_reason=btrim(p_reason),snoozed_until=null,version=version+1 where id=t.id;
 end if;
 event_id=gen_random_uuid();
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'hospital_medication_'||p_action,t.id,jsonb_build_object('event_id',event_id,'permission_grant_id',g,'procedure_id',t.procedure_type_id,'previous_version',t.version,'version',t.version+1,'reason',p_reason,'minutes',p_minutes));
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,event_id);return event_id;
end$$;
create function public.hospital_discharge_preview(p_clinic uuid,p_stay uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.hospital_stays;pending jsonb;begin
 perform private.medication_lock(p_clinic);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 perform private.hospital_order_permission(p_clinic,'hospital.discharge',null,true);
 select * into s from public.hospital_stays where clinic_id=p_clinic and id=p_stay for update;
 if not found or s.discharged_at is not null then raise exception 'stay_inactive';end if;
 perform private.hospital_order_permission(p_clinic,'hospital.discharge',null,true);
 pending=private.hospital_pending(p_clinic,p_stay);
 return jsonb_build_object('stay_id',s.id,'version',s.version,'pending',pending,'pending_hash',encode(sha256(convert_to(pending::text,'UTF8')),'hex'));
end$$;
create function public.hospital_discharge_confirm(p_clinic uuid,p_stay uuid,p_version integer,p_pending_hash text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare s public.hospital_stays;g uuid;fp jsonb;receipt uuid;pending jsonb;at_time timestamptz;task_id uuid;begin
 perform private.medication_lock(p_clinic);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 g=private.hospital_order_permission(p_clinic,'hospital.discharge',null,true);
 if coalesce(length(btrim(p_reason)),0) not between 1 and 500 or p_pending_hash is null or p_pending_hash !~ '^[a-f0-9]{64}$' then raise exception 'reviewed_discharge_reason_required';end if;
 fp=jsonb_build_object('kind','reviewed_discharge','stay',p_stay,'version',p_version,'pending_hash',p_pending_hash,'reason',p_reason);
 receipt=private.vet_receipt(p_clinic,p_operation,fp);if receipt is not null then return receipt;end if;
 select * into s from public.hospital_stays where clinic_id=p_clinic and id=p_stay for update;
 if not found or s.discharged_at is not null then raise exception 'stay_inactive';end if;
 g=private.hospital_order_permission(p_clinic,'hospital.discharge',null,true);
 if s.version is distinct from p_version then raise exception 'hospital_version_conflict';end if;
 -- Lock also against a pre-cutover writer; the full cutover must remove all legacy routes.
 perform 1 from public.hospital_tasks where clinic_id=p_clinic and stay_id=p_stay order by id for update;
 g=private.hospital_order_permission(p_clinic,'hospital.discharge',null,true);
 pending=private.hospital_pending(p_clinic,p_stay);
 if encode(sha256(convert_to(pending::text,'UTF8')),'hex')<>p_pending_hash then raise exception 'discharge_preview_changed';end if;
 at_time=clock_timestamp();
 update public.hospital_stays set discharged_at=at_time,discharged_by=auth.uid(),discharge_reason=btrim(p_reason),version=version+1 where id=s.id;
 for task_id in update public.hospital_tasks set state='cancelled',resolution_kind='discharge',cancelled_by=auth.uid(),cancelled_at=at_time,cancel_reason='Alta: '||btrim(p_reason),snoozed_until=null,version=version+1 where clinic_id=p_clinic and stay_id=p_stay and state='pending' returning id loop
  insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'hospital_task_cancelled_by_discharge',task_id,jsonb_build_object('permission_grant_id',g,'stay_id',s.id,'reason',p_reason));
 end loop;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'hospital_discharged',s.id,jsonb_build_object('permission_grant_id',g,'pending_hash',p_pending_hash,'cancelled_count',jsonb_array_length(pending),'previous_version',s.version,'version',s.version+1));
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,s.id);return s.id;
end$$;
create or replace function public.hospital_discharge(p_clinic_id uuid,p_stay_id uuid,p_expected_version integer,p_reason text) returns void language plpgsql security definer set search_path='' as $$begin
 raise exception 'reviewed_discharge_required';
end$$;
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
  if task.state<>'pending' or stay.discharged_at is not null or task.resolution_kind is not null then raise exception 'task_closed_without_application';end if;
  if coalesce(p_data->>'hospital_task_version','') !~ '^[1-9][0-9]{0,8}$' then raise exception 'hospital_task_version_required';end if;
  if task.version<>(p_data->>'hospital_task_version')::integer then raise exception 'task_version_conflict';end if;
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
create or replace function public.rx_hospital(p_case uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.clinical_cases;begin
 select * into c from public.clinical_cases where id=p_case;
 if not found or not private.clinical_readable(c) or private.permission_effective(c.clinic_id,auth.uid(),'hospital.read') is null then raise exception 'case_hospital_access_required';end if;
 return jsonb_build_object('stays',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'cage',s.cage)),'[]') from public.hospital_stays s where s.clinic_id=c.clinic_id and s.patient_id=c.patient_id and s.discharged_at is null),
 'tasks',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'version',t.version,'label',t.label,'due_at',t.due_at,'prescription_item_id',t.prescription_item_id,'procedure_type_id',t.procedure_type_id)),'[]') from public.hospital_tasks t join public.hospital_stays s on s.id=t.stay_id and s.clinic_id=t.clinic_id where t.clinic_id=c.clinic_id and s.patient_id=c.patient_id and t.kind='medicacion' and t.prescription_item_id is not null and t.procedure_type_id is not null and t.authority_grant_id is not null and t.clinical_case_id=c.id and t.medication_record_id is null and s.discharged_at is null and t.state='pending'));
end$$;
create or replace function public.rx_operational_permissions(p_clinic uuid,p_case uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.clinical_cases;professional boolean;begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'clinic_membership_required';end if;
 professional=private.professional_current(p_clinic,auth.uid());
 if p_case is not null then
  select * into c from public.clinical_cases where id=p_case and clinic_id=p_clinic;
  if not found or not private.clinical_readable(c) then raise exception 'case_access_required';end if;
 end if;
 return jsonb_build_object('schema_version',1,'task_versions',true,'typed_medication_schedule',true,
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
create function private.medication_task_actionable(t public.hospital_tasks) returns boolean language sql stable security definer set search_path='' as $$
 select t.state='pending' and t.kind='medicacion' and t.prescription_item_id is not null and t.procedure_type_id is not null and t.authority_grant_id is not null
 and private.permission_effective(t.clinic_id,auth.uid(),'medication.report') is not null
 and private.permission_effective(t.clinic_id,auth.uid(),'drug.administer',t.procedure_type_id) is not null
 and exists(select 1 from public.clinical_cases c join private.clinical_scope_bindings b on b.case_id=c.id and b.procedure_id=t.procedure_type_id
 where c.id=t.clinical_case_id and c.clinic_id=t.clinic_id and private.clinical_readable(c) and b.scope<>'observaciones'
 and not exists(select 1 from private.clinical_scope_revocations r where r.binding_id=b.id)
 and private.clinical_eligible(c,auth.uid(),b.scope,clock_timestamp()));
$$;
revoke all on function private.medication_task_actionable(public.hospital_tasks) from public,anon,authenticated;
alter function public.hospital_snapshot(uuid) set schema private;
alter function private.hospital_snapshot(uuid) rename to hospital_snapshot_before_resolution;
revoke all on function private.hospital_snapshot_before_resolution(uuid) from public,anon,authenticated;
create function public.hospital_snapshot(p_clinic_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare b jsonb;begin
 b=private.hospital_snapshot_before_resolution(p_clinic_id);
 return b||jsonb_build_object('capabilities',(b->'capabilities')||jsonb_build_object('reviewed_discharge',true,'medication_followup',true),
 'permissions',(b->'permissions')||jsonb_build_object('hospital.discharge',private.professional_current(p_clinic_id,auth.uid()) and private.permission_effective(p_clinic_id,auth.uid(),'hospital.discharge') is not null),
 'tasks',(select coalesce(jsonb_agg(j||jsonb_build_object('actions',(j->'actions')||case when t.kind='medicacion' then jsonb_build_object(
 'perform',private.medication_task_actionable(t),
 'snooze',t.state='pending' and t.prescription_item_id is not null and t.procedure_type_id is not null and t.authority_grant_id is not null and private.permission_effective(p_clinic_id,auth.uid(),'medication.followup',t.procedure_type_id) is not null,
 'not_given',t.state='pending' and t.prescription_item_id is not null and t.procedure_type_id is not null and t.authority_grant_id is not null and private.permission_effective(p_clinic_id,auth.uid(),'medication.followup',t.procedure_type_id) is not null) else '{}'::jsonb end) order by t.due_at,t.id),'[]')
 from jsonb_array_elements(b->'tasks') j join public.hospital_tasks t on t.id=(j->>'id')::uuid and t.clinic_id=p_clinic_id));
end$$;
revoke all on function public.hospital_snapshot(uuid),public.hospital_medication_followup(uuid,uuid,integer,text,integer,text,text),public.hospital_discharge_preview(uuid,uuid),public.hospital_discharge_confirm(uuid,uuid,integer,text,text,text) from public,anon;
grant execute on function public.hospital_snapshot(uuid),public.hospital_medication_followup(uuid,uuid,integer,text,integer,text,text),public.hospital_discharge_preview(uuid,uuid),public.hospital_discharge_confirm(uuid,uuid,integer,text,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
