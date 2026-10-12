-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Etapa 4, bloque 2/6.
-- Ejecutar en orden; no probar funciones M6 hasta completar todos los bloques.
begin;

create function public.rx_professional_authorize(p_clinic uuid,p_user uuid,p_enabled boolean,p_until timestamptz,p_reference text) returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;
begin
 if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=p_user and role in ('admin','mvz')) or p_until<=clock_timestamp() then raise exception 'professional_membership_required';end if;
 insert into public.clinic_professional_authorizations(clinic_id,user_id,enabled,valid_until,review_reference) values(p_clinic,p_user,p_enabled,p_until,p_reference) returning clinic_professional_authorizations.id into id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,null,'professional_authorization_server_reviewed',id);return id;
end $$;
create function public.rx_profiles(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'user_id',p.user_id,'version_id',(v->>'id'),'version',v->'version','name',(v->>'name'),'license',(v->>'license'),'registration',(v->>'registration'),'has_signature',v->'signature' is not null and v->'signature'<>'null','source_status','sin verificar','authorized',private.rx_professional(p.clinic_id,p.user_id))) from public.professional_profiles p cross join lateral (select private.rx_profile(p.id) as v) q where p.clinic_id=p_clinic and (p.user_id=auth.uid() or exists(select 1 from public.professional_delegations d where d.profile_id=p.id and d.recipient_id=auth.uid() and d.use_data and d.valid_until>clock_timestamp() and not exists(select 1 from public.professional_delegation_revocations x where x.delegation_id=d.id)))),'[]');
end $$;
create function public.rx_profile_save(p_clinic uuid,p_expected integer,p_name text,p_license text,p_registration text,p_signature jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.professional_profiles;v jsonb;id uuid;fp jsonb;
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'profile_role_required';end if;
 if coalesce(length(btrim(p_name)),0) not between 1 and 200 or length(coalesce(p_license,''))>200 or length(coalesce(p_registration,''))>200 then raise exception 'invalid_profile';end if;
 if p_signature is not null and p_signature<>'null'::jsonb and p_signature<>'{"keep":true}'::jsonb then perform private.form_validate_signature(p_signature);end if;
 fp=jsonb_build_object('kind','profile','expected',p_expected,'name',p_name,'license',p_license,'registration',p_registration,'signature',p_signature);
 id=private.vet_receipt(p_clinic,p_operation,fp);if id is not null then return id;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_clinic::text||auth.uid()::text,0));
 select * into p from public.professional_profiles where clinic_id=p_clinic and user_id=auth.uid() for update;
 if not found then insert into public.professional_profiles(clinic_id,user_id) values(p_clinic,auth.uid()) returning * into p;end if;
 v=private.rx_profile(p.id);if coalesce(((v->>'version'))::integer,0) is distinct from coalesce(p_expected,0) then raise exception 'profile_version_conflict';end if;
 insert into private.professional_profile_versions(profile_id,version,name,license,registration,signature,created_by) values(p.id,coalesce(((v->>'version'))::integer,0)+1,p_name,coalesce(p_license,''),coalesce(p_registration,''),case when p_signature='{"keep":true}'::jsonb then v->'signature' when p_signature='null'::jsonb then null else p_signature end,auth.uid()) returning professional_profile_versions.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'professional_profile_version_created',id);return id;
end $$;
create function public.rx_delegations(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('revoked',exists(select 1 from public.professional_delegation_revocations r where r.delegation_id=d.id))) from public.professional_delegations d where d.clinic_id=p_clinic and (d.created_by=auth.uid() or d.recipient_id=auth.uid())),'[]');
end $$;
create function public.rx_delegate(p_profile uuid,p_recipient uuid,p_case uuid,p_permissions jsonb,p_until text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.professional_profiles;id uuid;fp jsonb;k text;until_at timestamptz;
begin
 select * into p from public.professional_profiles where professional_profiles.id=p_profile for update;
 if not found or p.user_id<>auth.uid() or not private.rx_professional(p.clinic_id,auth.uid()) then raise exception 'profile_owner_professional_required';end if;
 if not exists(select 1 from public.clinic_members where clinic_id=p.clinic_id and user_id=p_recipient and role in ('mvz','auxiliar','admin')) or p_recipient=auth.uid() then raise exception 'recipient_in_clinic_required';end if;
 until_at=private.clinical_time(p_until);if until_at<=clock_timestamp() then raise exception 'future_expiry_required';end if;
 foreach k in array array['use_data','use_signature','prepare_ordinary','issue_ordinary','dispense_ordinary'] loop if jsonb_typeof(p_permissions->k) is distinct from 'boolean' then raise exception 'typed_permissions_required';end if;end loop;
 if (p_permissions->'prepare_ordinary'='true' or p_permissions->'issue_ordinary'='true' or p_permissions->'dispense_ordinary'='true') and (p_case is null or not exists(select 1 from public.clinical_cases c where c.id=p_case and c.clinic_id=p.clinic_id and c.responsible_id=auth.uid())) then raise exception 'responsible_case_required';end if;
 if p_case is not null and not exists(select 1 from public.clinical_cases c where c.id=p_case and c.clinic_id=p.clinic_id and private.rx_case(c)) then raise exception 'case_access_required';end if;
 fp=jsonb_build_object('kind','delegation','profile',p_profile,'recipient',p_recipient,'case',p_case,'permissions',p_permissions,'until',p_until);id=private.vet_receipt(p.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.professional_delegations(clinic_id,profile_id,recipient_id,case_id,use_data,use_signature,prepare_ordinary,issue_ordinary,dispense_ordinary,valid_until,created_by)
 values(p.clinic_id,p.id,p_recipient,p_case,((p_permissions->>'use_data'))::boolean,((p_permissions->>'use_signature'))::boolean,((p_permissions->>'prepare_ordinary'))::boolean,((p_permissions->>'issue_ordinary'))::boolean,((p_permissions->>'dispense_ordinary'))::boolean,until_at,auth.uid()) returning professional_delegations.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p.clinic_id,auth.uid(),'professional_delegation_granted',id);return id;
end $$;
create function public.rx_delegate_revoke(p_id uuid,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.professional_delegations;p public.professional_profiles;id uuid;fp jsonb;
begin
 select * into d from public.professional_delegations where professional_delegations.id=p_id;
 select * into p from public.professional_profiles where professional_profiles.id=d.profile_id for update;
 if not found or p.user_id<>auth.uid() or not private.has_clinic_role(p.clinic_id,array['admin','mvz','auxiliar']) then raise exception 'profile_owner_required';end if;
 fp=jsonb_build_object('kind','delegation_revoke','delegation',p_id,'reason',p_reason);id=private.vet_receipt(p.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.professional_delegation_revocations(delegation_id,reason,created_by) values(d.id,p_reason,auth.uid()) returning professional_delegation_revocations.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p.clinic_id,auth.uid(),'professional_delegation_revoked',id);return id;
end $$;
create function private.rx_items_check(items jsonb,delegated boolean) returns boolean language plpgsql security definer set search_path='' as $$
declare x jsonb;p public.medication_product_versions;controlled boolean=false;k text;
begin
 if jsonb_typeof(items) is distinct from 'array' then raise exception 'prescription_items_required';end if;
 if jsonb_array_length(items) not between 1 and 40 then raise exception 'prescription_items_required';end if;
 for x in select * from jsonb_array_elements(items) loop
  select * into p from public.medication_product_versions where id=((x->>'product_version_id'))::uuid;
  if not found then raise exception 'product_version_required';end if;
  perform private.rx_quantity((x->>'quantity'));
  if (x->>'unit') is distinct from p.unit then raise exception 'product_unit_mismatch';end if;
  foreach k in array array['route','interval','duration'] loop
   if jsonb_typeof(x->k) is distinct from 'string' or coalesce(length(btrim(x->>k)),0) not between 1 and 1000 then raise exception 'complete_instructions_required';end if;
  end loop;
  if x ? 'care' and (jsonb_typeof(x->'care') is distinct from 'string' or length((x->>'care'))>4000) then raise exception 'invalid_care';end if;
  if p.classification<>'no_controlado' or coalesce(p.quantified_prescription,true) then controlled=true;end if;
  if delegated and (not private.rx_product_verified(p) or p.classification<>'no_controlado' or p.quantified_prescription) then raise exception 'delegated_restricted_product_denied';end if;
 end loop;
 return controlled;
end $$;
create function private.rx_permission(r public.prescriptions,scope text) returns void language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;p public.professional_profiles;
begin
 select * into c from public.clinical_cases where id=r.case_id;
 if not private.rx_professional(r.clinic_id,r.responsible_id) or not private.rx_case(c) then raise exception 'responsible_professional_required';end if;
 if r.responsible_id=auth.uid() and private.rx_professional(r.clinic_id,auth.uid()) then return;end if;
 if r.controlled then raise exception 'controlled_responsible_only';end if;
 select * into p from public.professional_profiles where clinic_id=r.clinic_id and user_id=r.responsible_id;
 if p.id is null or not private.rx_delegated(p,scope,r.case_id) then raise exception 'ordinary_delegation_required';end if;
end $$;
create function private.rx_insert_items(r public.prescriptions,items jsonb) returns void language plpgsql security definer set search_path='' as $$
declare x jsonb;begin
 for x in select * from jsonb_array_elements(items) loop
 insert into public.prescription_items(clinic_id,prescription_id,product_version_id,quantity,unit,route,interval_text,duration_text,care)
 values(r.clinic_id,r.id,((x->>'product_version_id'))::uuid,private.rx_quantity((x->>'quantity')),(x->>'unit'),(x->>'route'),(x->>'interval'),(x->>'duration'),coalesce((x->>'care'),''));
 end loop;
end $$;
create function public.rx_create(p_case uuid,p_items jsonb,p_folio text,p_instructions text,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;r public.prescriptions;controlled boolean;id uuid;fp jsonb;
begin
 select * into c from public.clinical_cases where clinical_cases.id=p_case;
 if not found or not private.rx_case(c) then raise exception 'case_access_required';end if;
 controlled=private.rx_items_check(p_items,c.responsible_id<>auth.uid() or not private.rx_professional(c.clinic_id,auth.uid()));
 r.clinic_id=c.clinic_id;r.case_id=c.id;r.responsible_id=c.responsible_id;r.controlled=controlled;
 perform private.rx_permission(r,'prepare');
 if length(coalesce(p_folio,''))>200 or length(coalesce(p_instructions,''))>4000 then raise exception 'invalid_prescription_text';end if;
 fp=jsonb_build_object('kind','rx_create','case',p_case,'items',p_items,'folio',p_folio,'instructions',p_instructions);id=private.vet_receipt(c.clinic_id,p_operation,fp);
 if id is not null then select * into r from public.prescriptions where prescriptions.id=id;return to_jsonb(r);end if;
 insert into public.prescriptions(clinic_id,case_id,patient_id,responsible_id,created_by,controlled,official_folio,instructions)
 values(c.clinic_id,c.id,c.patient_id,c.responsible_id,auth.uid(),controlled,coalesce(p_folio,''),coalesce(p_instructions,'')) returning * into r;
 perform private.rx_insert_items(r,p_items);
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,r.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(c.clinic_id,auth.uid(),'prescription_draft_created',r.id);return to_jsonb(r);
end $$;
create function public.rx_save(p_id uuid,p_revision integer,p_items jsonb,p_folio text,p_instructions text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;v_controlled boolean;
begin
 select * into r from public.prescriptions where id=p_id for update;
 if not found or r.revision is distinct from p_revision or r.state<>'draft' then raise exception 'prescription_revision_conflict';end if;
 v_controlled=private.rx_items_check(p_items,r.responsible_id<>auth.uid() or not private.rx_professional(r.clinic_id,auth.uid()));
 r.controlled=v_controlled;perform private.rx_permission(r,'prepare');
 if length(coalesce(p_folio,''))>200 or length(coalesce(p_instructions,''))>4000 then raise exception 'invalid_prescription_text';end if;
 delete from public.prescription_items where prescription_id=r.id;perform private.rx_insert_items(r,p_items);
 update public.prescriptions set controlled=v_controlled,official_folio=coalesce(p_folio,''),instructions=coalesce(p_instructions,''),revision=revision+1 where id=r.id returning * into r;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(r.clinic_id,auth.uid(),'prescription_draft_changed',r.id);return to_jsonb(r);
end $$;
create function public.rx_list(p_clinic uuid,p_patient uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('patient_name',p.name) order by r.created_at desc) from public.prescriptions r join public.vet_patients p on p.id=r.patient_id where r.clinic_id=p_clinic and (p_patient is null or r.patient_id=p_patient) and private.rx_readable(r)),'[]');
end $$;
create function public.rx_snapshot(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.prescriptions;
begin
 select * into r from public.prescriptions where id=p_id;
 if not found or not private.rx_readable(r) then raise exception 'prescription_access_denied';end if;
 return to_jsonb(r)||jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('quantity',i.quantity::text,'product_name',p.name,'presentation',p.presentation,'classification',p.classification,'source_status',p.source_status)) from public.prescription_items i join public.medication_product_versions p on p.id=i.product_version_id where prescription_id=r.id),'[]'));
end $$;
create function private.rx_regulation(kind text) returns public.rx_regulatory_versions language sql stable security definer set search_path='' as $$
 select r from public.rx_regulatory_versions r where r.kind=$1 order by r.version desc limit 1;
$$;
create function private.rx_emit_check(r public.prescriptions) returns void language plpgsql security definer set search_path='' as $$
declare i public.prescription_items;p public.medication_product_versions;rule public.rx_regulatory_versions;k text;
begin
 perform private.rx_permission(r,'issue');
 for i in select * from public.prescription_items where prescription_id=r.id loop
 select * into p from public.medication_product_versions where medication_product_versions.id=i.product_version_id;
 if not private.rx_product_verified(p) then raise exception 'verified_current_product_required';end if;
 end loop;
 if r.controlled then
  rule=private.rx_regulation('controlled_prescription');
  if rule.id is null or rule.source_status<>'verificada' or (rule.valid_until is not null and rule.valid_until<=clock_timestamp()) or r.official_folio='' then raise exception 'verified_controlled_format_and_captured_folio_required';end if;
  foreach k in array rule.required_fields loop
   if k not in ('folio','patient','owner','mvz_name','mvz_license','registration','products','instructions','signature') then raise exception 'unsupported_official_field';end if;
   if k='registration' and coalesce(r.snapshot->'profile'->>'registration','')='' then raise exception 'professional_registration_required';end if;
  end loop;
 end if;
end $$;
-- Cierre provisional: ningún endpoint farmacológico nuevo habilitado al cliente.
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (p.proname like 'rx_%' or p.proname in ('form_professional_check','form_document_use_profile')) and n.nspname in ('public','private') loop execute 'revoke all on function '||f.signature||' from public,anon,authenticated';end loop;
end $$;

notify pgrst, 'reload schema';
commit;
select '04B COMPLETADO (2/6)' as resultado;
-- FIN COMPLETO 04B
