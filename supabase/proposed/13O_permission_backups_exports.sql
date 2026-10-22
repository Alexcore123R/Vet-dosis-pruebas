-- Local candidate after 13N. Separates clinic and personal exports.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;

create function private.backup_clinic_authorized(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.clinic_members where clinic_id=$1 and user_id=auth.uid())
 and exists(select 1 from public.account_workspaces where clinic_id=$1 and kind='clinic')
 and private.permission_effective($1,auth.uid(),'backup.export') is not null
 and (private.permission_effective($1,auth.uid(),'workspace.manage') is not null or private.permission_responsible($1));
$$;
create function private.backup_personal_authorized(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.account_workspaces where clinic_id=$1 and kind='personal' and owner_id=auth.uid())
 and exists(select 1 from public.clinic_members where clinic_id=$1 and user_id=auth.uid());
$$;

-- Replace the original leaf in the existing snapshot decorator chain. Authorization
-- is capability based; the wrappers still add payments, AI and agenda records.
create or replace function private.clinic_snapshot_before_ai_plans(p_clinic uuid) returns text language plpgsql stable security definer set search_path='' as $$
declare result jsonb='{}';t text;rows jsonb;
begin
 if not private.backup_clinic_authorized(p_clinic) then raise exception 'backup_export_required';end if;
 foreach t in array array['professional_profiles','clinic_professional_authorizations','professional_delegations','prescriptions','prescription_items','medication_vials','medication_records','medication_vial_movements','medication_vial_reconciliations','controlled_drug_reviews','controlled_drug_reports','vet_owners','vet_patients','vet_patient_events','clinical_cases','case_staff_assignments','person_procedure_authorizations','clinical_observations','clinical_procedure_acts','clinical_death_records','hospital_stays','hospital_tasks','form_templates','form_template_versions','form_documents','clinic_document_settings','attendance_settings','attendance_consents','attendance_events','attendance_corrections','audit_log','inventory_clinic_settings','inventory_stock_movements','inventory_cash_shifts','inventory_sales','inventory_sale_lines','inventory_sale_reversals','inventory_cash_movements','inventory_order_drafts','inventory_order_approvals','inventory_vial_links','inventory_dispensing_limits','dose_personal_entries','inventory_delivery_grants','inventory_application_tariffs','inventory_application_charges','inventory_delivery_tickets','clinic_services','clinic_appointments','clinic_tasks','clinic_messages','clinic_suppliers','clinic_service_acts','inventario','lotes_inventario','clinic_members'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.%I x where clinic_id=$1',t) into rows using p_clinic;
  result=result||jsonb_build_object(t,rows);
 end loop;
 -- Preventive booklet v2 is applied as a later additive adaptation in some
 -- installations. Include its records whenever the tables exist so an export
 -- taken after that cutover preserves evidence, plans, retirements and links.
 foreach t in array array['preventive_evidence','preventive_plans','preventive_plan_retirements','preventive_appointment_links'] loop
  if to_regclass(format('public.%I',t)) is not null then
   execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.%I x where clinic_id=$1',t) into rows using p_clinic;
   result=result||jsonb_build_object(t,rows);
  end if;
 end loop;
 result=result||jsonb_build_object(
  'clinics',(select jsonb_agg(to_jsonb(c)) from public.clinics c where id=p_clinic),
  'professional_delegation_revocations',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.professional_delegation_revocations x join public.professional_delegations p on p.id=x.delegation_id where p.clinic_id=p_clinic),
  'person_procedure_revocations',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.person_procedure_revocations x join public.person_procedure_authorizations p on p.id=x.authorization_id where p.clinic_id=p_clinic),
  'inventory_delivery_revocations',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.inventory_delivery_revocations x join public.inventory_delivery_grants p on p.id=x.grant_id where p.clinic_id=p_clinic),
  'controlled_drug_report_items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.controlled_drug_report_items x join public.controlled_drug_reports p on p.id=x.report_id where p.clinic_id=p_clinic),
  'medication_product_versions',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.medication_product_versions x),
  'rx_regulatory_versions',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.rx_regulatory_versions x),
  'general_doses',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public."Fármacos" x),
  'form_signatures',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from public.form_signatures s join public.form_documents d on d.id=s.document_id where d.clinic_id=p_clinic),
  'form_artifacts',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from private.form_artifacts a join public.form_documents d on d.id=a.document_id where d.clinic_id=p_clinic),
  'rx_artifacts',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from private.rx_artifacts a where (a.kind='prescription' and exists(select 1 from public.prescriptions r where r.id=a.entity_id and r.clinic_id=p_clinic)) or (a.kind='report' and exists(select 1 from public.controlled_drug_reports r where r.id=a.entity_id and r.clinic_id=p_clinic))),
  'my_staff_medical_profile',(select coalesce(jsonb_agg(to_jsonb(m)),'[]') from public.staff_medical_profiles m where clinic_id=p_clinic and user_id=auth.uid()),
  'base_template_versions',(select coalesce(jsonb_agg(to_jsonb(v)),'[]') from public.form_template_versions v where clinic_id is null));
 return jsonb_build_object('format','vetdosis-operational-backup','version',1,'clinic_id',p_clinic,'exported_by',auth.uid(),'server_at',clock_timestamp(),'tables',result,
  'scope',jsonb_build_object('operational_records',true,'historical_pdf_artifacts',true,'inventory_photos','download_by_client','excluded',jsonb_build_array('auth credentials','invitation tokens','QR signing secrets','reusable professional signature profiles','other staff medical profiles','restore/migration tooling')))::text;
end$$;

create or replace function public.clinic_export(p_clinic uuid) returns text language plpgsql security definer set search_path='' as $$
declare result text;
begin
 perform public.beta_access_check(false,p_clinic);
 if not private.backup_clinic_authorized(p_clinic) then raise exception 'backup_export_required';end if;
 result=private.clinic_snapshot(p_clinic);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'operational_backup_exported','clinic:'||p_clinic::text);
 return result;
end$$;

create function public.personal_export(p_clinic uuid) returns text language plpgsql security definer set search_path='' as $$
declare result jsonb;profile_ids uuid[];
begin
 perform public.beta_access_check(false,p_clinic);
 if not private.backup_personal_authorized(p_clinic) then raise exception 'personal_owner_required';end if;
 select coalesce(array_agg(id),'{}') into profile_ids from public.professional_profiles where clinic_id=p_clinic and user_id=auth.uid();
 result=jsonb_build_object(
  'dose_personal_entries',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.dose_personal_entries x where clinic_id=p_clinic and user_id=auth.uid()),
  'form_templates',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.form_templates x where clinic_id=p_clinic and created_by=auth.uid()),
  'form_template_versions',(select coalesce(jsonb_agg(to_jsonb(v)),'[]') from public.form_template_versions v where v.clinic_id=p_clinic and v.created_by=auth.uid() and exists(select 1 from public.form_templates t where t.id=v.template_id and t.created_by=auth.uid())),
  'professional_profiles',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.professional_profiles x where clinic_id=p_clinic and user_id=auth.uid()),
  'professional_profile_versions',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from private.professional_profile_versions x where profile_id=any(profile_ids)));
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'operational_backup_exported','personal:'||p_clinic::text);
 return jsonb_build_object('format','vetdosis-personal-backup','version',1,'clinic_id',p_clinic,'exported_by',auth.uid(),'server_at',clock_timestamp(),'tables',result,
  'scope',jsonb_build_object('personal_only',true,'clinical_records',false,'excluded',jsonb_build_array('patients','owners','clinical records','hospitalization','document signatures','clinic emergency cards','other accounts','credentials','restore/migration tooling')))::text;
end$$;

create function public.backup_workspace(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare kind text;
begin
 perform public.beta_access_check(false,p_clinic);
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'current_member_required';end if;
 select workspace_kind.kind into kind from public.account_workspaces workspace_kind where clinic_id=p_clinic;
 return jsonb_build_object('schema_version',1,'mode','explicit_backup','workspace_kind',kind,
  'exports',jsonb_build_object('clinic',private.backup_clinic_authorized(p_clinic),'personal',private.backup_personal_authorized(p_clinic)),
  'statistics',private.permission_effective(p_clinic,auth.uid(),'sales.read') is not null);
end$$;

create or replace function public.clinic_statistics(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tz text;begin
 perform public.beta_access_check(false,p_clinic);
 if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) or private.permission_effective(p_clinic,auth.uid(),'sales.read') is null then raise exception 'sales_read_required';end if;
 select timezone into tz from public.inventory_clinic_settings where clinic_id=p_clinic;tz=coalesce(tz,'America/Mexico_City');
 return jsonb_build_object('timezone',tz,'sales',(with months as (select generate_series(date_trunc('month',now() at time zone tz)-interval '11 months',date_trunc('month',now() at time zone tz),interval '1 month') m),flows as (
  select s.created_at at time zone tz at,s.total amount from public.inventory_sales s where s.clinic_id=p_clinic
  union all select r.created_at at time zone tz,-s.total from public.inventory_sale_reversals r join public.inventory_sales s on s.id=r.sale_id where r.clinic_id=p_clinic)
  select jsonb_agg(jsonb_build_object('month',to_char(m,'YYYY-MM'),'amount',amount::text) order by m) from (select m,coalesce(sum(f.amount),0) amount from months left join flows f on f.at>=m and f.at<m+interval '1 month' group by m) x),
  'species',case when private.permission_effective(p_clinic,auth.uid(),'appointment.read') is not null then (select coalesce(jsonb_agg(jsonb_build_object('species',species,'count',n)),'[]') from (select species,count(*) n from public.clinic_appointments where clinic_id=p_clinic and state<>'cancelado' and starts_at>=(date_trunc('month',now() at time zone tz) at time zone tz) and starts_at<((date_trunc('month',now() at time zone tz)+interval '1 month') at time zone tz) group by species) x) else null end,
  'low_stock',case when private.permission_effective(p_clinic,auth.uid(),'inventory.read') is not null then (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',nombre,'stock',stock::text,'minimum',stock_minimo::text)),'[]') from public.inventario where clinic_id=p_clinic and active and m8_enabled and stock<=stock_minimo) else null end);
end$$;

create or replace function public.app_module_workspace(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'current_member_required';end if;
 return jsonb_build_object('schema_version',1,'mode','explicit_modules','modules',jsonb_build_object(
  'patients',private.module_current(p_clinic,array['patient.read','patient.write']),'agenda',private.module_current(p_clinic,array['appointment.read','appointment.manage']),
  'hospital',private.module_current(p_clinic,array['hospital.read','hospital.manage','hospital.report','hospital.schedule','hospital.discharge']),
  'inventory',private.module_current(p_clinic,array['inventory.read','inventory.manage','inventory.receive','inventory.adjust','inventory.order.prepare','inventory.order.approve']),
  'sales',private.module_current(p_clinic,array['sales.collect','sales.read','sales.reverse','sales.reconcile','sales.manual','cash.move']),
  'prescriptions',private.module_current(p_clinic,array['prescription.prepare','prescription.authorize']),
  'forms',private.module_current(p_clinic,array['form.template.read','form.template.edit','form.template.approve','form.branding.manage','form.prepare','form.authorize','form.issue']),
  'clinical',private.module_current(p_clinic,array['clinical.read','clinical.authorize','clinical.case.prepare']),
  'statistics',private.module_current(p_clinic,array['sales.read']),
  'backup',private.backup_clinic_authorized(p_clinic) or private.backup_personal_authorized(p_clinic)),
  'summaries',jsonb_build_object('patients',private.module_current(p_clinic,array['patient.read']),'agenda',private.module_current(p_clinic,array['appointment.read']),'hospital',private.module_current(p_clinic,array['hospital.read']),'inventory',private.module_current(p_clinic,array['inventory.read']),'sales',private.module_current(p_clinic,array['sales.read'])));
end$$;

revoke all on function private.backup_clinic_authorized(uuid),private.backup_personal_authorized(uuid),private.clinic_snapshot_before_ai_plans(uuid),public.clinic_export(uuid),public.personal_export(uuid),public.backup_workspace(uuid),public.clinic_statistics(uuid),public.app_module_workspace(uuid) from public,anon,authenticated,service_role;
grant execute on function public.clinic_export(uuid),public.personal_export(uuid),public.backup_workspace(uuid),public.clinic_statistics(uuid),public.app_module_workspace(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
