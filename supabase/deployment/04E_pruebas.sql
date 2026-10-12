-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Etapa 4, bloque 5/6.
-- Ejecutar en orden; no probar funciones M6 hasta completar todos los bloques.
begin;

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
-- Cierre provisional: ningún endpoint farmacológico nuevo habilitado al cliente.
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (p.proname like 'rx_%' or p.proname in ('form_professional_check','form_document_use_profile')) and n.nspname in ('public','private') loop execute 'revoke all on function '||f.signature||' from public,anon,authenticated';end loop;
end $$;

notify pgrst, 'reload schema';
commit;
select '04E COMPLETADO (5/6)' as resultado;
-- FIN COMPLETO 04E
