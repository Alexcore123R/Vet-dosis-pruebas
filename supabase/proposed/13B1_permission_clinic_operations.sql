-- Stage 2B-2.1. Clinic operations permissions.
-- Apply after 13N_module_navigation_dashboard.sql and 13P_workspace_management_cutover.sql.
-- Grants are intentionally not seeded.
begin;
do $$begin
 if to_regprocedure('public.ops_write(uuid,text,jsonb,text)') is null
   or to_regprocedure('public.ops_dashboard(uuid)') is null
   or to_regprocedure('private.permission_effective(uuid,uuid,text,uuid)') is null
   or to_regprocedure('private.module_current(uuid,text[])') is null
   or to_regprocedure('public.app_module_workspace(uuid)') is null then
  raise exception 'permission_agenda_contract_required';
 end if;
end$$;

insert into private.permission_catalog(code,label,procedure_scoped,requires_professional) values
 ('service.read','Consultar catálogo y precios de servicios',false,false),
 ('service.manage','Crear y editar servicios de la clínica',false,false),
 ('supplier.read','Consultar proveedores de la clínica',false,false),
 ('supplier.manage','Agregar proveedores de la clínica',false,false),
 ('team.read','Consultar tareas y mensajes del equipo',false,false),
 ('team.manage','Crear tareas y publicar mensajes del equipo',false,false),
 ('service.act.read','Consultar servicios realizados y sus importes',false,false),
 ('service.act.record','Registrar un servicio realizado',false,false)
on conflict(code) do update set label=excluded.label,procedure_scoped=false,requires_professional=false;

create function private.ops_permission_active(p_clinic uuid,p_code text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from private.member_permission_grants g
  where g.id=private.permission_effective(p_clinic,auth.uid(),p_code)
    and g.valid_until>clock_timestamp()
 );
$$;
revoke all on function private.ops_permission_active(uuid,text) from public,anon,authenticated,service_role;

-- Explicit section grants are the write authority for the clinic catalog.
-- This keeps the earlier role-based compatibility writer from rejecting a
-- staff member who was deliberately granted service.manage or supplier.manage.
create function private.ops_catalog_write(p_clinic uuid,p_action text,p_data jsonb,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_grant uuid;v_id uuid;fp jsonb;
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 v_grant=private.permission_require(p_clinic,case p_action when 'service' then 'service.manage' when 'supplier' then 'supplier.manage' else null end);
 perform 1 from public.clinics where id=p_clinic for update;
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for share;
 if not found then raise exception 'access_denied';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>20000 then raise exception 'invalid_data';end if;
 fp=jsonb_build_object('kind','ops','action',p_action,'data',p_data);
 v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 if p_action='service' then
  v_id=nullif(p_data->>'id','')::uuid;
  if v_id is null then
   insert into public.clinic_services(clinic_id,name,price,commission_kind,commission_value)
   values(p_clinic,btrim(p_data->>'name'),private.inv_money(p_data->>'price'),p_data->>'commission_kind',private.inv_money(p_data->>'commission_value')) returning id into v_id;
  else
   update public.clinic_services set name=btrim(p_data->>'name'),price=private.inv_money(p_data->>'price'),commission_kind=p_data->>'commission_kind',commission_value=private.inv_money(p_data->>'commission_value'),version=version+1,updated_at=clock_timestamp()
   where id=v_id and clinic_id=p_clinic and version=(p_data->>'version')::int;
   if not found then raise exception 'version_conflict';end if;
  end if;
 elsif p_action='supplier' then
  insert into public.clinic_suppliers(clinic_id,name,phone,notes,created_by)
  values(p_clinic,btrim(p_data->>'name'),coalesce(p_data->>'phone',''),coalesce(p_data->>'notes',''),auth.uid()) returning id into v_id;
 else raise exception 'unknown_operation';end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(p_clinic,auth.uid(),'ops_'||p_action,v_id::text,jsonb_build_object('permission_grant_id',v_grant));
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 return v_id;
end$$;
revoke all on function private.ops_catalog_write(uuid,text,jsonb,text) from public,anon,authenticated,service_role;

-- Keep the agenda permission wrapper and the pre-existing plan checks behind a
-- private callable boundary. The new public entry point adds section permissions.
alter function public.ops_write(uuid,text,jsonb,text) rename to ops_write_before_clinic_operations;
revoke all on function public.ops_write_before_clinic_operations(uuid,text,jsonb,text) from public,anon,authenticated;
create function public.ops_write(p_clinic uuid,p_action text,p_data jsonb,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare code text;
begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'access_denied';end if;
 code=case p_action
  when 'service' then 'service.manage'
  when 'supplier' then 'supplier.manage'
  when 'task' then 'team.manage'
  when 'task_complete' then 'team.manage'
  when 'message' then 'team.manage'
  when 'service_act' then 'service.act.record'
  else null end;
 if code is not null and not private.ops_permission_active(p_clinic,code) then raise exception 'explicit_permission_required';end if;
 if code is not null then perform private.permission_require(p_clinic,code);end if;
 if p_action in ('service','supplier') then return private.ops_catalog_write(p_clinic,p_action,p_data,p_operation);end if;
 return public.ops_write_before_clinic_operations(p_clinic,p_action,p_data,p_operation);
end$$;
revoke all on function public.ops_write(uuid,text,jsonb,text) from public,anon;
grant execute on function public.ops_write(uuid,text,jsonb,text) to authenticated;

alter function public.ops_dashboard(uuid) rename to ops_dashboard_before_clinic_operations;
revoke all on function public.ops_dashboard_before_clinic_operations(uuid) from public,anon,authenticated;
create function public.ops_dashboard(p_clinic uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
 can_appointment_read boolean; can_appointment_manage boolean; can_patient boolean;
 can_service_read boolean; can_service_manage boolean; can_supplier_read boolean; can_supplier_manage boolean;
 can_team_read boolean; can_team_manage boolean; can_act_read boolean; can_act_record boolean; team_available boolean;
begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'access_denied';end if;
 can_appointment_read=private.ops_permission_active(p_clinic,'appointment.read');
 can_appointment_manage=private.ops_permission_active(p_clinic,'appointment.manage');
 can_patient=private.ops_permission_active(p_clinic,'patient.read');
 can_service_read=private.ops_permission_active(p_clinic,'service.read');
 can_service_manage=private.ops_permission_active(p_clinic,'service.manage');
 can_supplier_read=private.ops_permission_active(p_clinic,'supplier.read');
 can_supplier_manage=private.ops_permission_active(p_clinic,'supplier.manage');
 can_team_read=private.ops_permission_active(p_clinic,'team.read');
 can_team_manage=private.ops_permission_active(p_clinic,'team.manage');
 can_act_read=private.ops_permission_active(p_clinic,'service.act.read');
 can_act_record=private.ops_permission_active(p_clinic,'service.act.record');
 team_available=private.team_plan(p_clinic);
 return jsonb_build_object(
  'permissions',jsonb_build_object(
   'appointment.read',can_appointment_read,'appointment.manage',can_appointment_manage,'patient.read',can_patient,
   'service.read',can_service_read,'service.manage',can_service_manage,
   'supplier.read',can_supplier_read,'supplier.manage',can_supplier_manage,
   'team.read',can_team_read,'team.manage',can_team_manage,
   'service.act.read',can_act_read,'service.act.record',can_act_record),
  'sections',jsonb_build_object(
   'appointments',can_appointment_read or can_appointment_manage,
   'services',can_service_read or can_service_manage,
   'tasks',(can_team_read or can_team_manage) and team_available,
   'messages',(can_team_read or can_team_manage) and team_available,
   'suppliers',can_supplier_read or can_supplier_manage,
   'acts',can_act_read or can_act_record),
  'section_reasons',jsonb_build_object(
   'appointments',case when not(can_appointment_read or can_appointment_manage) then 'permission_required' end,
   'services',case when not(can_service_read or can_service_manage) then 'permission_required' end,
   'tasks',case when (can_team_read or can_team_manage) and not team_available then 'clinic_plan_required' when not(can_team_read or can_team_manage) then 'permission_required' end,
   'messages',case when (can_team_read or can_team_manage) and not team_available then 'clinic_plan_required' when not(can_team_read or can_team_manage) then 'permission_required' end,
   'suppliers',case when not(can_supplier_read or can_supplier_manage) then 'permission_required' end,
   'acts',case when not(can_act_read or can_act_record) then 'permission_required' end),
  'members',(select coalesce(jsonb_agg(jsonb_build_object('user_id',m.user_id,'role','member','display_name',n.name)),'[]')
    from public.clinic_members m left join public.staff_display_names n using(clinic_id,user_id)
    where m.clinic_id=p_clinic and (can_appointment_read or can_appointment_manage or can_team_read or can_team_manage or can_act_read or can_act_record)),
  'people',(select coalesce(jsonb_agg(jsonb_build_object('user_id',n.user_id,'display_name',n.name)),'[]')
    from public.staff_display_names n where n.clinic_id=p_clinic and (can_appointment_read or can_appointment_manage or can_team_read or can_team_manage or can_act_read or can_act_record or n.user_id=auth.uid())),
  'appointments',(select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('patient_id',case when can_patient then a.patient_id else null end) order by a.starts_at),'[]')
    from public.clinic_appointments a where a.clinic_id=p_clinic and can_appointment_read and a.starts_at>clock_timestamp()-interval '90 days'),
  'services',(select case when can_service_read or can_service_manage then coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('price',s.price::text,'commission_value',s.commission_value::text) order by s.name),'[]')
    when can_act_record then coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'active',s.active) order by s.name),'[]') else '[]'::jsonb end from public.clinic_services s where s.clinic_id=p_clinic and s.active),
  'tasks',(select case when team_available and (can_team_read or can_team_manage) then coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc),'[]') else '[]'::jsonb end
    from public.clinic_tasks t where t.clinic_id=p_clinic and (t.assigned_to is null or t.assigned_to=auth.uid() or t.created_by=auth.uid() or private.has_clinic_role(p_clinic,array['admin']))),
  'messages',(select case when team_available and (can_team_read or can_team_manage) then coalesce(jsonb_agg(to_jsonb(m) order by m.created_at),'[]') else '[]'::jsonb end
    from (select * from public.clinic_messages where clinic_id=p_clinic order by created_at desc limit 100) m),
  'suppliers',(select case when can_supplier_read or can_supplier_manage then coalesce(jsonb_agg(to_jsonb(s) order by s.name),'[]') else '[]'::jsonb end
    from public.clinic_suppliers s where s.clinic_id=p_clinic),
  'acts',(select case when can_act_read or can_act_record then coalesce(
      jsonb_agg(
       to_jsonb(a)||jsonb_build_object(
        'price',a.price::text,'commission',a.commission::text,
        'paid',exists(select 1 from public.inventory_sale_lines l
          where l.service_act_id=a.id and not exists(
           select 1 from public.inventory_sale_reversals r where r.sale_id=l.sale_id
          ))
       ) order by a.created_at desc
      ),'[]'
     ) else '[]'::jsonb end
    from public.clinic_service_acts a where a.clinic_id=p_clinic and (can_act_read or a.professional_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin','recepcion']))));
end$$;
revoke all on function public.ops_dashboard(uuid) from public,anon;
grant execute on function public.ops_dashboard(uuid) to authenticated;

-- The existing navigation contract has one operations module. Its visibility
-- reflects any explicit operations grant, while each section still checks its own grant.
create or replace function public.app_module_workspace(p_clinic uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'current_member_required';end if;
 return jsonb_build_object('schema_version',1,'mode','explicit_modules','modules',jsonb_build_object(
  'patients',private.module_current(p_clinic,array['patient.read','patient.write']),
  'agenda',private.module_current(p_clinic,array['appointment.read','appointment.manage','service.read','service.manage','supplier.read','supplier.manage','team.read','team.manage','service.act.read','service.act.record']),
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
revoke all on function public.app_module_workspace(uuid) from public,anon;
grant execute on function public.app_module_workspace(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
