-- LOCAL CANDIDATE after 13H1. Individual authorization; no beta opening/deploy.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
alter table public.prescriptions drop constraint prescriptions_state_check;
alter table public.prescriptions add constraint prescriptions_state_check check(state in ('draft','awaiting_authorization','awaiting_review','ready','issued'));
alter table public.prescriptions
 add column consultation_attestation_id uuid references private.prescription_consultation_attestations(id),
 add column prepared_by uuid references auth.users(id),
 add column prepare_grant_id uuid references private.member_permission_grants(id),
 add column prepared_member_since timestamptz,
 add column authorized_by uuid references auth.users(id),
 add column authorized_at timestamptz,
 add column authorization_grant_id uuid references private.member_permission_grants(id),
 add column authorization_reference_id uuid,
 add column authorization_profile_version_id uuid references private.professional_profile_versions(id),
 add column issued_by uuid references auth.users(id);
alter table public.prescriptions add constraint prescription_attribution_metadata check(
 (consultation_attestation_id is null and prepared_by is null and prepare_grant_id is null and prepared_member_since is null and authorization_profile_version_id is null
 and authorized_by is null and authorized_at is null and authorization_grant_id is null and authorization_reference_id is null and issued_by is null)
 or (consultation_attestation_id is not null and prepared_by is not null and prepare_grant_id is not null and prepared_member_since is not null and authorization_profile_version_id is not null
 and ((authorized_by is null and authorized_at is null and authorization_grant_id is null and authorization_reference_id is null)
 or (authorized_by is not null and authorized_by=responsible_id and authorized_at is not null and authorization_grant_id is not null and authorization_reference_id is not null))
 and (issued_by is null or (state='issued' and authorized_by is not null and issued_by=authorized_by))));
-- Historical columns stay NULL. A captured license or old delegation is not authority.
create or replace function private.rx_permission(r public.prescriptions,scope text) returns void language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;begin
 select * into c from public.clinical_cases where id=r.case_id;
 if not found or not private.clinical_readable(c) or r.clinic_id is distinct from c.clinic_id or r.responsible_id is distinct from c.responsible_id
 or not private.clinical_professional_at(c.clinic_id,c.responsible_id,clock_timestamp()) then raise exception 'responsible_professional_required';end if;
 if scope='prepare' then perform private.medication_permission(c.clinic_id,'prescription.prepare');
 elsif scope='issue' then
  if auth.uid()<>c.responsible_id then raise exception 'individual_responsible_only';end if;
  perform private.medication_permission(c.clinic_id,'prescription.authorize');
 else raise exception 'unsupported_prescription_action';end if;
 if r.controlled and auth.uid()<>c.responsible_id then raise exception 'controlled_responsible_only';end if;
end$$;
create or replace function private.rx_readable(r public.prescriptions) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.clinical_cases c where c.id=r.case_id and c.clinic_id=r.clinic_id and c.patient_id=r.patient_id and private.clinical_readable(c))
 and (not r.controlled or (r.responsible_id=auth.uid() and private.clinical_professional_at(r.clinic_id,auth.uid(),clock_timestamp())));
$$;

create function private.rx_attributed_current(r public.prescriptions,p_authorized boolean) returns void language plpgsql security definer set search_path='' as $$
declare a private.prescription_consultation_attestations;draft public.prescriptions;consultation jsonb;profile jsonb;begin
 select * into a from private.prescription_consultation_attestations where id=r.consultation_attestation_id and prescription_id=r.id;
 if not found or r.prepared_by is null then raise exception 'attributed_prescription_required';end if;
 if not exists(select 1 from public.clinical_cases c where c.id=r.case_id and c.clinic_id=r.clinic_id and c.patient_id=r.patient_id and c.responsible_id=r.responsible_id) then raise exception 'prescription_case_mismatch';end if;
 draft=r;draft.state='draft';draft.revision=a.draft_revision;
 consultation=private.rx_consultation_for_draft(draft,a.id);
 if r.snapshot->'prescription_identity'->'consultation' is distinct from consultation then raise exception 'consultation_signature_mismatch';end if;
 if not exists(select 1 from public.clinic_members m where m.clinic_id=r.clinic_id and m.user_id=r.prepared_by and m.created_at=r.prepared_member_since)
 or private.permission_effective(r.clinic_id,r.prepared_by,'prescription.prepare') is distinct from r.prepare_grant_id
 or not exists(select 1 from private.member_permission_grants where id=r.prepare_grant_id and valid_until>clock_timestamp()) then raise exception 'preparer_authority_changed';end if;
 profile=private.rx_profile(r.profile_id);
 if (profile->>'id')::uuid is distinct from r.authorization_profile_version_id
 or not exists(select 1 from public.professional_profiles p where p.id=r.profile_id and p.clinic_id=r.clinic_id and p.user_id=r.responsible_id)
 or not private.clinical_professional_at(r.clinic_id,r.responsible_id,clock_timestamp()) then raise exception 'responsible_profile_changed';end if;
 if p_authorized and (r.authorized_by is distinct from r.responsible_id or r.authorized_at is null or r.authorization_reference_id is null
 or private.permission_effective(r.clinic_id,r.responsible_id,'prescription.authorize') is distinct from r.authorization_grant_id
 or not exists(select 1 from private.member_permission_grants where id=r.authorization_grant_id and valid_until>clock_timestamp())) then raise exception 'prescription_authorization_changed';end if;
 if p_authorized and r.controlled and r.regulatory_version_id is distinct from (private.rx_regulation('controlled_prescription')).id then raise exception 'prescription_regulation_changed';end if;
end$$;

create function public.rx_consultations(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.prescriptions;begin
 select * into r from public.prescriptions where id=p_id;
 if not found or not private.rx_readable(r) then raise exception 'prescription_access_denied';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'user_id',a.signer_id,'name',a.signer_name,'signed_at',a.signed_at) order by a.signed_at desc)
 from private.prescription_consultation_attestations a where a.prescription_id=r.id and r.state='draft' and a.draft_revision=r.revision and a.content_hash=private.rx_consultation_content(r)
 and private.permission_effective(a.clinic_id,a.signer_id,'prescription.prepare')=a.permission_grant_id
 and exists(select 1 from private.member_permission_grants where id=a.permission_grant_id and valid_until>clock_timestamp())),'[]');
end$$;

-- Recipe branding has already been authorized by the caller's Rx permissions;
-- do not reintroduce role-based form access through this shared dependency.
create function private.rx_branding(p_clinic uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce((select branding from public.clinic_document_settings where clinic_id=p_clinic order by created_at desc,id desc limit 1),
 jsonb_build_object('header',(select name from public.clinics where id=p_clinic),'include_logo',false));
$$;
revoke all on function private.rx_branding(uuid) from public,anon,authenticated;

create function public.rx_prepare_attributed(p_id uuid,p_revision integer,p_attestation uuid,p_preparer_name text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;c public.clinical_cases;consultation jsonb;profile jsonb;p public.professional_profiles;patient public.vet_patients;owner public.vet_owners;s jsonb;rows jsonb;g uuid;member_at timestamptz;preparer text;begin
 select * into r from public.prescriptions where id=p_id;
 if not found then raise exception 'prescription_access_denied';end if;
 c=private.medication_case_lock(r.case_id);
 select * into r from public.prescriptions where id=p_id for update;
 perform private.rx_permission(r,'prepare');g=private.medication_permission(r.clinic_id,'prescription.prepare');
 if r.state<>'draft' or r.revision is distinct from p_revision then raise exception 'prescription_revision_conflict';end if;
 consultation=private.rx_consultation_for_draft(r,p_attestation);
 preparer=case when consultation->>'user_id'=auth.uid()::text then consultation->>'name' else btrim(p_preparer_name) end;
 if coalesce(length(preparer),0) not between 1 and 200 or preparer~'[[:cntrl:]]' then raise exception 'preparer_name_required';end if;
 select created_at into member_at from public.clinic_members where clinic_id=r.clinic_id and user_id=auth.uid();
 select * into p from public.professional_profiles where clinic_id=r.clinic_id and user_id=r.responsible_id;
 profile=private.rx_profile(p.id);
 if profile is null or coalesce(profile->>'license','')='' then raise exception 'professional_profile_required';end if;
 if consultation->>'user_id'=r.responsible_id::text and consultation->>'name' is distinct from profile->>'name' then raise exception 'consultation_profile_name_mismatch';end if;
 if auth.uid()=r.responsible_id and preparer is distinct from profile->>'name' then raise exception 'preparer_profile_name_mismatch';end if;
 select * into patient from public.vet_patients where id=r.patient_id;
 select * into owner from public.vet_owners where id=patient.owner_id;
 if owner.id is null then raise exception 'patient_owner_required';end if;
 select coalesce(jsonb_agg(jsonb_build_array(pv.name||' · '||pv.presentation,i.quantity::text||' '||i.unit,i.route,i.interval_text,i.duration_text,i.care) order by i.id),'[]') into rows
 from public.prescription_items i join public.medication_product_versions pv on pv.id=i.product_version_id where i.prescription_id=r.id;
 s=jsonb_build_object('clinical',true,'schema',jsonb_build_object('type','prescription','title',case when r.controlled then 'Receta controlada · folio capturado' else 'Receta médica veterinaria' end,'fields',jsonb_build_array(
 jsonb_build_object('id','patient','type','binding','label','Paciente'),jsonb_build_object('id','owner','type','binding','label','Propietario registrado'),
 jsonb_build_object('id','folio','type','text','label','Folio capturado (no generado por la app)'),jsonb_build_object('id','products','type','table','label','Indicaciones capturadas','columns',jsonb_build_array('Producto / presentación','Cantidad','Vía','Intervalo','Duración','Cuidados')),
 jsonb_build_object('id','instructions','type','text','label','Indicaciones adicionales')),'clauses',jsonb_build_array()),
 'document_id',r.id,'case_id',r.case_id,'template_version',2,'clinic_name',(select name from public.clinics where id=r.clinic_id),'branding',private.rx_branding(r.clinic_id),
 'patient',jsonb_build_object('name',patient.name,'species',patient.species),'owner',jsonb_build_object('name',owner.name),'profile',profile-'signature',
 'prescription_identity_version',1,'prescription_identity',jsonb_build_object('controlled',r.controlled,'consultation',consultation,'prepared_by',jsonb_build_object('user_id',auth.uid(),'name',preparer),
 'responsible',jsonb_build_object('user_id',r.responsible_id,'name',profile->>'name','license',profile->>'license','profile_version_id',profile->>'id')),
 'values',jsonb_build_object('folio',r.official_folio,'products',rows,'instructions',r.instructions));
 update public.prescriptions set state='awaiting_authorization',revision=revision+1,consultation_attestation_id=p_attestation,prepared_by=auth.uid(),prepare_grant_id=g,prepared_member_since=member_at,
 profile_id=p.id,delegation_id=null,use_shared_signature=false,regulatory_version_id=null,authorization_profile_version_id=(profile->>'id')::uuid,snapshot=s,prepared_at=clock_timestamp(),content_hash=encode(sha256(convert_to(s::text,'UTF8')),'hex') where id=r.id returning * into r;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(r.clinic_id,auth.uid(),'prescription_prepared_awaiting_authorization',r.id,jsonb_build_object('attestation_id',p_attestation,'prepare_grant_id',g,'revision',r.revision));
 return (to_jsonb(r)-'snapshot');
end$$;

create function public.rx_authorize_individual(p_id uuid,p_revision integer,p_confirmed boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;c public.clinical_cases;g uuid;s jsonb;t timestamptz;ref uuid=gen_random_uuid();begin
 select * into r from public.prescriptions where id=p_id;
 if not found then raise exception 'prescription_access_denied';end if;
 c=private.medication_case_lock(r.case_id);
 select * into r from public.prescriptions where id=p_id for update;
 perform private.rx_permission(r,'issue');g=private.medication_permission(r.clinic_id,'prescription.authorize');
 if p_confirmed is distinct from true then raise exception 'individual_authorization_confirmation_required';end if;
 if r.state<>'awaiting_authorization' or r.revision is distinct from p_revision then raise exception 'prescription_revision_conflict';end if;
 perform private.rx_attributed_current(r,false);perform private.rx_emit_check(r);
 t=clock_timestamp();s=r.snapshot;
 s=jsonb_set(s,'{prepared_at}',to_jsonb(to_char(t at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
 s=jsonb_set(s,'{prescription_identity,authorization}',jsonb_build_object('mode','individual','actor_id',auth.uid(),'authorized_at',to_char(t at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'reference_id',ref));
 update public.prescriptions set state='awaiting_review',revision=revision+1,authorized_by=auth.uid(),authorized_at=t,authorization_grant_id=g,authorization_reference_id=ref,regulatory_version_id=case when r.controlled then (private.rx_regulation('controlled_prescription')).id end,
 snapshot=s,content_hash=encode(sha256(convert_to(s::text,'UTF8')),'hex') where id=r.id returning * into r;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(r.clinic_id,auth.uid(),'prescription_individually_authorized',r.id,jsonb_build_object('authorization_reference_id',ref,'authorization_grant_id',g,'revision',r.revision));
 return to_jsonb(r)-'snapshot';
end$$;

create or replace function private.rx_prepared_permission(r public.prescriptions) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.rx_readable(r) then raise exception 'prescription_access_denied';end if;
 if r.state='awaiting_authorization' then raise exception 'individual_authorization_required';end if;
 perform private.rx_attributed_current(r,true);
 if auth.uid()=r.responsible_id then perform private.rx_permission(r,'issue');
 elsif auth.uid()=r.prepared_by then perform private.rx_permission(r,'prepare');
 else raise exception 'prepared_prescription_access_denied';end if;
end$$;
create or replace function public.rx_prepare(p_id uuid,p_revision integer,p_profile uuid,p_shared_signature boolean,p_signature jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 raise exception 'attributed_prescription_preparation_required';end$$;
create function public.rx_return_to_draft(p_id uuid,p_revision integer,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;c public.clinical_cases;begin
 select * into r from public.prescriptions where id=p_id;
 if not found then raise exception 'prescription_access_denied';end if;
 c=private.medication_case_lock(r.case_id);
 select * into r from public.prescriptions where id=p_id for update;
 if auth.uid()=r.responsible_id then perform private.rx_permission(r,'issue');
 elsif auth.uid()=r.prepared_by then perform private.rx_permission(r,'prepare');
 else raise exception 'prepared_prescription_access_denied';end if;
 if r.revision is distinct from p_revision or r.state not in ('awaiting_authorization','awaiting_review','ready') then raise exception 'prescription_revision_conflict';end if;
 if coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'prescription_correction_reason_required';end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(r.clinic_id,auth.uid(),'prescription_returned_to_draft',r.id,jsonb_build_object('reason',btrim(p_reason),'previous_revision',r.revision,'previous_content_hash',r.content_hash,'authorization_reference_id',r.authorization_reference_id));
 delete from private.rx_artifacts where kind='prescription' and entity_id=r.id;
 update public.prescriptions set state='draft',revision=revision+1,snapshot=null,content_hash=null,pdf_hash=null,profile_id=null,delegation_id=null,use_shared_signature=false,regulatory_version_id=null,consultation_attestation_id=null,
 prepared_by=null,prepared_member_since=null,prepare_grant_id=null,prepared_at=null,authorized_by=null,authorized_at=null,authorization_grant_id=null,authorization_reference_id=null,authorization_profile_version_id=null where id=r.id returning * into r;
 return to_jsonb(r)-'snapshot';
end$$;
create or replace function public.rx_finalize(p_id uuid,p_revision integer,p_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;c public.clinical_cases;begin
 select * into r from public.prescriptions where id=p_id;
 if not found then raise exception 'prescription_access_denied';end if;
 c=private.medication_case_lock(r.case_id);
 select * into r from public.prescriptions where id=p_id for update;
 perform private.rx_permission(r,'issue');perform private.rx_attributed_current(r,true);perform private.rx_emit_check(r);
 if r.revision is distinct from p_revision or r.pdf_hash is distinct from p_hash or p_hash is null then raise exception 'reviewed_prescription_mismatch';end if;
 if r.state='issued' then return to_jsonb(r)-'snapshot';end if;
 if r.state<>'ready' or not exists(select 1 from private.rx_artifacts a where a.kind='prescription' and a.entity_id=r.id and a.revision=r.revision and a.pdf_hash=p_hash and encode(sha256(a.pdf),'hex')=p_hash) then raise exception 'reviewed_pdf_required';end if;
 update public.prescriptions set state='issued',issued_at=clock_timestamp(),issued_by=auth.uid() where id=r.id returning * into r;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(r.clinic_id,auth.uid(),'prescription_issued',r.id,jsonb_build_object('prepared_by',r.prepared_by,'authorized_by',r.authorized_by,'authorization_reference_id',r.authorization_reference_id,'pdf_hash',p_hash));
 return to_jsonb(r)-'snapshot';
end$$;

-- Signing/preparing does not resurrect the old shared-signature or dispensing grants.
create or replace function public.rx_delegate(p_profile uuid,p_recipient uuid,p_case uuid,p_permissions jsonb,p_until text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$begin
 raise exception 'typed_standing_authorization_not_available';end$$;
revoke all on function private.rx_attributed_current(public.prescriptions,boolean),public.rx_consultations(uuid),public.rx_prepare_attributed(uuid,integer,uuid,text),public.rx_authorize_individual(uuid,integer,boolean),public.rx_return_to_draft(uuid,integer,text) from public,anon,authenticated;
grant execute on function public.rx_consultations(uuid),public.rx_prepare_attributed(uuid,integer,uuid,text),public.rx_authorize_individual(uuid,integer,boolean),public.rx_return_to_draft(uuid,integer,text) to authenticated;
create or replace function public.rx_create(p_case uuid,p_items jsonb,p_folio text,p_instructions text,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;r public.prescriptions;controlled boolean;id uuid;fp jsonb;
begin
 c=private.medication_case_lock(p_case);
 controlled=private.rx_items_check(p_items,c.responsible_id<>auth.uid() or not private.clinical_professional_at(c.clinic_id,auth.uid(),clock_timestamp()));
 r.clinic_id=c.clinic_id;r.case_id=c.id;r.responsible_id=c.responsible_id;r.controlled=controlled;
 perform private.rx_permission(r,'prepare');
 if length(coalesce(p_folio,''))>200 or length(coalesce(p_instructions,''))>4000 then raise exception 'invalid_prescription_text';end if;
 fp=jsonb_build_object('kind','rx_create','case',p_case,'items',p_items,'folio',p_folio,'instructions',p_instructions);id=private.vet_receipt(c.clinic_id,p_operation,fp);
 if id is not null then select * into r from public.prescriptions where prescriptions.id=id;return to_jsonb(r)-'snapshot';end if;
 insert into public.prescriptions(clinic_id,case_id,patient_id,responsible_id,created_by,controlled,official_folio,instructions)
 values(c.clinic_id,c.id,c.patient_id,c.responsible_id,auth.uid(),controlled,coalesce(p_folio,''),coalesce(p_instructions,'')) returning * into r;
 perform private.rx_insert_items(r,p_items);
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,r.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(c.clinic_id,auth.uid(),'prescription_draft_created',r.id);return to_jsonb(r)-'snapshot';
end $$;
create or replace function public.rx_save(p_id uuid,p_revision integer,p_items jsonb,p_folio text,p_instructions text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;c public.clinical_cases;v_controlled boolean;
begin
 select * into r from public.prescriptions where id=p_id;
 if not found then raise exception 'prescription_access_denied';end if;
 c=private.medication_case_lock(r.case_id);
 select * into r from public.prescriptions where id=p_id for update;
 if not found or r.revision is distinct from p_revision or r.state<>'draft' then raise exception 'prescription_revision_conflict';end if;
 v_controlled=private.rx_items_check(p_items,r.responsible_id<>auth.uid() or not private.clinical_professional_at(r.clinic_id,auth.uid(),clock_timestamp()));
 r.controlled=v_controlled;perform private.rx_permission(r,'prepare');
 if length(coalesce(p_folio,''))>200 or length(coalesce(p_instructions,''))>4000 then raise exception 'invalid_prescription_text';end if;
 delete from public.prescription_items where prescription_id=r.id;perform private.rx_insert_items(r,p_items);
 update public.prescriptions set controlled=v_controlled,official_folio=coalesce(p_folio,''),instructions=coalesce(p_instructions,''),revision=revision+1 where id=r.id returning * into r;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(r.clinic_id,auth.uid(),'prescription_draft_changed',r.id);return to_jsonb(r)-'snapshot';
end $$;
create or replace function private.rx_products_ready(r public.prescriptions) returns void language plpgsql security definer set search_path='' as $$
declare i public.prescription_items;p public.medication_product_versions;rule public.rx_regulatory_versions;k text;
begin
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
create or replace function private.rx_emit_check(r public.prescriptions) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.rx_permission(r,'issue');perform private.rx_products_ready(r);
end$$;

create or replace function public.rx_profiles(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if private.permission_effective(p_clinic,auth.uid(),'clinical.read') is null or private.permission_effective(p_clinic,auth.uid(),'patient.read') is null then raise exception 'case_access_required';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'user_id',p.user_id,'version_id',v->>'id','version',v->'version','name',v->>'name','license',v->>'license','registration',v->>'registration','has_signature',v->'signature' is not null and v->'signature'<>'null'::jsonb,'source_status','sin verificar','authorized',private.clinical_professional_at(p.clinic_id,p.user_id,clock_timestamp())))
 from public.professional_profiles p cross join lateral(select private.rx_profile(p.id) v) q where p.clinic_id=p_clinic and (p.user_id=auth.uid() or exists(select 1 from public.clinical_cases c where c.clinic_id=p_clinic and c.responsible_id=p.user_id and private.clinical_readable(c)))),'[]');
end$$;
create or replace function public.rx_delegations(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if private.permission_effective(p_clinic,auth.uid(),'clinical.read') is null or private.permission_effective(p_clinic,auth.uid(),'patient.read') is null then raise exception 'case_access_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('revoked',exists(select 1 from public.professional_delegation_revocations v where v.delegation_id=d.id),'effective_in_new_workflow',false)) from public.professional_delegations d where d.clinic_id=p_clinic and (d.created_by=auth.uid() or d.recipient_id=auth.uid())),'[]');
end$$;
create or replace function public.rx_list(p_clinic uuid,p_patient uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if private.permission_effective(p_clinic,auth.uid(),'clinical.read') is null or private.permission_effective(p_clinic,auth.uid(),'patient.read') is null then raise exception 'case_access_required';end if;
 return coalesce((select jsonb_agg((to_jsonb(r)-'snapshot')||jsonb_build_object('patient_name',p.name) order by r.created_at desc) from public.prescriptions r join public.vet_patients p on p.id=r.patient_id
 where r.clinic_id=p_clinic and (p_patient is null or r.patient_id=p_patient) and private.rx_readable(r)),'[]');
end$$;
create or replace function public.rx_snapshot(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.prescriptions;begin
 select * into r from public.prescriptions where id=p_id;
 if not found or not private.rx_readable(r) then raise exception 'prescription_access_denied';end if;
 return (to_jsonb(r)-'snapshot')||jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('product_name',p.name,'presentation',p.presentation,'classification',p.classification,'source_status',p.source_status) order by i.id) from public.prescription_items i join public.medication_product_versions p on p.id=i.product_version_id where i.prescription_id=r.id),'[]'));
end$$;
-- Keep signatures out of direct table/list/detail reads. Authorized PDF RPCs
-- still deliver the server-owned snapshot to the renderer under their guards.
revoke select on public.prescriptions from authenticated;
revoke select(snapshot) on public.prescriptions from authenticated;
do $$declare cols text;begin
 select string_agg(quote_ident(column_name),',') into cols from information_schema.columns where table_schema='public' and table_name='prescriptions' and column_name<>'snapshot';
 execute 'grant select ('||cols||') on public.prescriptions to authenticated';
end$$;

create function public.rx_prescription_permissions(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare prep boolean;authorize boolean;begin
 if private.permission_effective(p_clinic,auth.uid(),'clinical.read') is null or private.permission_effective(p_clinic,auth.uid(),'patient.read') is null then raise exception 'case_access_required';end if;
 prep=private.permission_effective(p_clinic,auth.uid(),'prescription.prepare') is not null
 and exists(select 1 from private.member_permission_grants where id=private.permission_effective(p_clinic,auth.uid(),'prescription.prepare') and valid_until>clock_timestamp());
 authorize=private.permission_effective(p_clinic,auth.uid(),'prescription.authorize') is not null and private.clinical_professional_at(p_clinic,auth.uid(),clock_timestamp())
 and exists(select 1 from private.member_permission_grants where id=private.permission_effective(p_clinic,auth.uid(),'prescription.authorize') and valid_until>clock_timestamp());
 return jsonb_build_object('schema_version',1,'mode','individual','can_prepare',prep,'can_authorize',authorize,'recipes',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'revision',r.revision,
 'sign',r.state='draft' and prep,'prepare',r.state='draft' and prep,'edit',r.state='draft' and prep,
 'authorize',r.state='awaiting_authorization' and authorize and r.responsible_id=auth.uid(),
 'correct',r.state in ('awaiting_authorization','awaiting_review','ready') and ((prep and r.prepared_by=auth.uid()) or (authorize and r.responsible_id=auth.uid())),
 'issue',r.state in ('awaiting_review','ready') and authorize and r.responsible_id=auth.uid())) from public.prescriptions r where r.clinic_id=p_clinic and private.rx_readable(r)),'[]'));
end$$;

-- Recheck authority after rendering and lock in the same order as clinical
-- writes. The old register body remains service-only behind this wrapper.
alter function public.rx_pdf_register(text,uuid,integer,text,text,text) set schema private;
alter function private.rx_pdf_register(text,uuid,integer,text,text,text) rename to rx_pdf_register_before_attribution;
revoke all on function private.rx_pdf_register_before_attribution(text,uuid,integer,text,text,text) from public,anon,authenticated,service_role;
create function public.rx_pdf_register(p_kind text,p_id uuid,p_revision integer,p_content_hash text,p_pdf text,p_signature text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;begin
 if p_kind='prescription' then
  select * into r from public.prescriptions where id=p_id;
  if not found then raise exception 'prescription_access_denied';end if;
  perform private.medication_lock(r.clinic_id);
  perform pg_advisory_xact_lock(hashtextextended(r.responsible_id::text,9061));
  select * into r from public.prescriptions where id=p_id for update;
  perform private.rx_attributed_current(r,true);perform private.rx_products_ready(r);
 end if;
 return private.rx_pdf_register_before_attribution(p_kind,p_id,p_revision,p_content_hash,p_pdf,p_signature);
end$$;
revoke all on function public.rx_pdf_register(text,uuid,integer,text,text,text),private.rx_products_ready(public.prescriptions),public.rx_prescription_permissions(uuid) from public,anon,authenticated;
grant execute on function public.rx_pdf_register(text,uuid,integer,text,text,text) to service_role;
grant execute on function public.rx_prescription_permissions(uuid) to authenticated;
create or replace function public.rx_profile_save(p_clinic uuid,p_expected integer,p_name text,p_license text,p_registration text,p_signature jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.professional_profiles;v jsonb;id uuid;fp jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'current_member_required';end if;
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
create or replace function public.rx_delegate_revoke(p_id uuid,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.professional_delegations;p public.professional_profiles;id uuid;fp jsonb;
begin
 select * into d from public.professional_delegations where professional_delegations.id=p_id;
 if not found then raise exception 'profile_owner_required';end if;
 perform private.medication_lock(d.clinic_id);
 select * into p from public.professional_profiles where professional_profiles.id=d.profile_id;
 if not found or p.user_id<>auth.uid() or not exists(select 1 from public.clinic_members where clinic_id=p.clinic_id and user_id=auth.uid()) then raise exception 'profile_owner_required';end if;
 if coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'revocation_reason_required';end if;
 fp=jsonb_build_object('kind','delegation_revoke','delegation',p_id,'reason',p_reason);id=private.vet_receipt(p.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.professional_delegation_revocations(delegation_id,reason,created_by) values(d.id,p_reason,auth.uid()) returning professional_delegation_revocations.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p.clinic_id,auth.uid(),'professional_delegation_revoked',id);return id;
end $$;
select private.beta_install_guards();
commit;
