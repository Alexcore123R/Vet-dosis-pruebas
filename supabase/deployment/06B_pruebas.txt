-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb, después de etapas 1-5.
-- Ejecutar 06A, 06B y 06C en orden. Sin datos de ejemplo ni conexiones bancarias.
-- M11: server-scoped operational export and statistics. No Drive credentials/secrets.
begin;
create function public.clinic_statistics(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tz text;begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 select timezone into tz from public.inventory_clinic_settings where clinic_id=p_clinic;tz=coalesce(tz,'America/Mexico_City');
 return jsonb_build_object('timezone',tz,'sales',(with months as (select generate_series(date_trunc('month',now() at time zone tz)-interval '11 months',date_trunc('month',now() at time zone tz),interval '1 month') m),flows as (
 select s.created_at at time zone tz at,s.total amount from public.inventory_sales s where s.clinic_id=p_clinic
 union all select r.created_at at time zone tz,-s.total from public.inventory_sale_reversals r join public.inventory_sales s on s.id=r.sale_id where r.clinic_id=p_clinic)
 select jsonb_agg(jsonb_build_object('month',to_char(m,'YYYY-MM'),'amount',amount::text) order by m) from (select m,coalesce(sum(f.amount),0) amount from months left join flows f on f.at>=m and f.at<m+interval '1 month' group by m) x),
 'species',(select coalesce(jsonb_agg(jsonb_build_object('species',species,'count',n)),'[]') from (select species,count(*) n from public.clinic_appointments where clinic_id=p_clinic and state<>'cancelado' and starts_at>=(date_trunc('month',now() at time zone tz) at time zone tz) and starts_at<((date_trunc('month',now() at time zone tz)+interval '1 month') at time zone tz) group by species) x),
 'low_stock',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',nombre,'stock',stock::text,'minimum',stock_minimo::text)),'[]') from public.inventario where clinic_id=p_clinic and active and m8_enabled and stock<=stock_minimo));
end$$;
create function private.clinic_snapshot(p_clinic uuid) returns text language plpgsql stable security definer set search_path='' as $$
declare result jsonb='{}';t text;rows jsonb;
begin
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() and role='admin';
 if not found then raise exception 'admin_required';end if;
 foreach t in array array['professional_profiles','clinic_professional_authorizations','professional_delegations','prescriptions','prescription_items','medication_vials','medication_records','medication_vial_movements','medication_vial_reconciliations','controlled_drug_reviews','controlled_drug_reports','vet_owners','vet_patients','vet_patient_events','clinical_cases','case_staff_assignments','person_procedure_authorizations','clinical_observations','clinical_procedure_acts','clinical_death_records','hospital_stays','hospital_tasks','form_templates','form_template_versions','form_documents','clinic_document_settings','attendance_settings','attendance_consents','attendance_events','attendance_corrections','audit_log','inventory_clinic_settings','inventory_stock_movements','inventory_cash_shifts','inventory_sales','inventory_sale_lines','inventory_sale_reversals','inventory_cash_movements','inventory_order_drafts','inventory_order_approvals','inventory_vial_links','inventory_dispensing_limits','dose_personal_entries','inventory_delivery_grants','inventory_application_tariffs','inventory_application_charges','inventory_delivery_tickets','clinic_services','clinic_appointments','clinic_tasks','clinic_messages','clinic_suppliers','clinic_service_acts','inventario','lotes_inventario','clinic_members'] loop
 execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.%I x where clinic_id=$1',t) into rows using p_clinic;
 result=result||jsonb_build_object(t,rows);
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
 'my_staff_medical_profile',(select coalesce(jsonb_agg(to_jsonb(m)),'[]') from public.staff_medical_profiles m where clinic_id=p_clinic and user_id=auth.uid()));
 -- Source catalogs and base templates, referenced across clinics, are non-personal.
 result=result||jsonb_build_object('base_template_versions',(select coalesce(jsonb_agg(to_jsonb(v)),'[]') from public.form_template_versions v where clinic_id is null));

 return jsonb_build_object('format','vetdosis-operational-backup','version',1,'clinic_id',p_clinic,'exported_by',auth.uid(),'server_at',clock_timestamp(),'tables',result,
 'scope',jsonb_build_object('operational_records',true,'historical_pdf_artifacts',true,'inventory_photos','download_by_client','excluded',jsonb_build_array('auth credentials','invitation tokens','QR signing secrets','reusable professional signature profiles','other staff medical profiles','restore/migration tooling')))::text;
end$$;
revoke all on function private.clinic_snapshot(uuid) from public,anon,authenticated;
create function public.clinic_export(p_clinic uuid) returns text language plpgsql security definer set search_path='' as $$
declare result text;
begin
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() and role='admin' for share;
 if not found then raise exception 'admin_required';end if;
 select private.clinic_snapshot(p_clinic) into result;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'operational_backup_exported',p_clinic::text);
 return result;
end$$;
revoke all on function public.clinic_statistics(uuid),public.clinic_export(uuid) from public,anon;
grant execute on function public.clinic_statistics(uuid),public.clinic_export(uuid) to authenticated;
commit;

notify pgrst, 'reload schema';
select '06B COMPLETADO: estadisticas y exportacion' as resultado;
-- FIN COMPLETO 06B
