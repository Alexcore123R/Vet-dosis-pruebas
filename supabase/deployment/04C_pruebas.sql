-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Etapa 4, bloque 3/6.
-- Ejecutar en orden; no probar funciones M6 hasta completar todos los bloques.
begin;

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
-- Cierre provisional: ningún endpoint farmacológico nuevo habilitado al cliente.
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (p.proname like 'rx_%' or p.proname in ('form_professional_check','form_document_use_profile')) and n.nspname in ('public','private') loop execute 'revoke all on function '||f.signature||' from public,anon,authenticated';end loop;
end $$;

notify pgrst, 'reload schema';
commit;
select '04C COMPLETADO (3/6)' as resultado;
-- FIN COMPLETO 04C
