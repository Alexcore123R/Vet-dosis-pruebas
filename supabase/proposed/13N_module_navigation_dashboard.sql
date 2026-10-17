-- Local candidate after 13M. Capability projection only; no clinical data.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
create function private.module_current(p_clinic uuid,p_codes text[]) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from unnest(p_codes) code where private.permission_effective(p_clinic,auth.uid(),code) is not null);
$$;
create function public.app_module_workspace(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'current_member_required';end if;
 return jsonb_build_object('schema_version',1,'mode','explicit_modules','modules',jsonb_build_object(
  'patients',private.module_current(p_clinic,array['patient.read','patient.write']),
  'agenda',private.module_current(p_clinic,array['appointment.read','appointment.manage']),
  'hospital',private.module_current(p_clinic,array['hospital.read','hospital.manage','hospital.report','hospital.schedule','hospital.discharge']),
  'inventory',private.module_current(p_clinic,array['inventory.read','inventory.manage','inventory.receive','inventory.adjust','inventory.order.prepare','inventory.order.approve']),
  'sales',private.module_current(p_clinic,array['sales.collect','sales.read','sales.reverse','sales.reconcile','sales.manual','cash.move']),
  'prescriptions',private.module_current(p_clinic,array['prescription.prepare','prescription.authorize']),
  'forms',private.module_current(p_clinic,array['form.template.read','form.template.edit','form.template.approve','form.branding.manage','form.prepare','form.authorize','form.issue']),
  'clinical',private.module_current(p_clinic,array['clinical.read','clinical.authorize','clinical.case.prepare'])
 ),'summaries',jsonb_build_object(
  'patients',private.module_current(p_clinic,array['patient.read']),
  'agenda',private.module_current(p_clinic,array['appointment.read']),
  'hospital',private.module_current(p_clinic,array['hospital.read']),
  'inventory',private.module_current(p_clinic,array['inventory.read']),
  'sales',private.module_current(p_clinic,array['sales.read'])
 ));
end$$;
revoke all on function private.module_current(uuid,text[]),public.app_module_workspace(uuid) from public,anon,authenticated,service_role;
grant execute on function public.app_module_workspace(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
