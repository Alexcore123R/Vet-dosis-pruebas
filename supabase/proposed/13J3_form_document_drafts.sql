-- LOCAL CANDIDATE 13J3, after 13J2. Drafts/authorship only, not issuance.
-- No migration of old signatures, no clinical act, no tutor acceptance inferred.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
create table private.form_authorship_attestations (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,document_id uuid not null,
 draft_revision integer not null check(draft_revision>0),content_hash text not null check(content_hash~'^[0-9a-f]{64}$'),
 signer_id uuid not null references auth.users(id),signer_name text not null check(length(btrim(signer_name)) between 1 and 200 and signer_name!~'[[:cntrl:]]'),
 signature jsonb not null,member_since timestamptz not null,permission_grant_id uuid not null references private.member_permission_grants(id),
 signed_at timestamptz not null default clock_timestamp(),foreign key(clinic_id,document_id) references public.form_documents(clinic_id,id)
);
alter table private.form_authorship_attestations enable row level security;
revoke all on private.form_authorship_attestations from public,anon,authenticated,service_role;
create trigger permission_immutable before update or delete on private.form_authorship_attestations for each row execute function private.permission_immutable();
create function private.form_document_current(p_clinic uuid,p_user uuid,p_code text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.member_permission_grants where id=private.permission_effective(p_clinic,p_user,p_code) and valid_until>clock_timestamp());
$$;
create function private.form_document_reader(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.form_document_current(p_clinic,auth.uid(),'clinical.read') and private.form_document_current(p_clinic,auth.uid(),'patient.read');
$$;
create or replace function private.form_readable(d public.form_documents) returns boolean language sql stable security definer set search_path='' as $$
 select private.form_document_reader(d.clinic_id) and (
 (d.created_by=auth.uid() and private.form_document_current(d.clinic_id,auth.uid(),'form.prepare'))
 or (d.responsible_id=auth.uid() and private.form_document_current(d.clinic_id,auth.uid(),'form.authorize') and private.clinical_professional_at(d.clinic_id,auth.uid(),clock_timestamp()))
 or (d.state='signed' and exists(select 1 from public.clinical_cases c where c.document_id=d.id and private.clinical_readable(c))));
$$;
create function private.form_draft_content(d public.form_documents) returns text language sql stable security definer set search_path='' as $$
 select encode(sha256(convert_to(jsonb_build_object('document',d.id,'clinic',d.clinic_id,'patient',d.patient_id,'template',d.version_id,'responsible',d.responsible_id,'author',d.created_by,'values',d.values,'branding',d.branding,'snapshot',d.snapshot)::text,'UTF8')),'hex');
$$;
create function private.form_draft_current(d public.form_documents) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb=d.snapshot->'draft_authority';profile jsonb;begin
 if d.snapshot->>'document_flow_version' is distinct from '1' or d.state<>'draft' then raise exception 'attributed_draft_required';end if;
 if not exists(select 1 from public.clinic_members where clinic_id=d.clinic_id and user_id=d.created_by and created_at=(a->>'author_member_since')::timestamptz)
 or private.permission_effective(d.clinic_id,d.created_by,'form.prepare')::text is distinct from a->>'prepare_grant_id'
 or not private.form_document_current(d.clinic_id,d.created_by,'form.prepare')
 or not private.form_document_current(d.clinic_id,d.created_by,'patient.read') or not private.form_document_current(d.clinic_id,d.created_by,'clinical.read')
 then raise exception 'draft_author_authority_changed';end if;
 if not exists(select 1 from public.clinic_members where clinic_id=d.clinic_id and user_id=d.responsible_id and created_at=(a->>'responsible_member_since')::timestamptz)
 or private.permission_effective(d.clinic_id,d.responsible_id,'form.authorize')::text is distinct from a->>'responsible_selection_grant_id'
 or not private.form_document_current(d.clinic_id,d.responsible_id,'form.authorize')
 or not private.form_document_current(d.clinic_id,d.responsible_id,'patient.read') or not private.form_document_current(d.clinic_id,d.responsible_id,'clinical.read')
 or not private.clinical_professional_at(d.clinic_id,d.responsible_id,clock_timestamp()) then raise exception 'draft_responsible_authority_changed';end if;
 select private.rx_profile(id) into profile from public.professional_profiles where clinic_id=d.clinic_id and user_id=d.responsible_id;
 if profile->>'id' is distinct from a->>'responsible_profile_version_id' or d.values->>'mvz_name' is distinct from profile->>'name' or d.values->>'mvz_license' is distinct from profile->>'license' then raise exception 'draft_responsible_profile_changed';end if;
end$$;
create function private.form_draft_lock(p_id uuid) returns public.form_documents language plpgsql security definer set search_path='' as $$
declare d public.form_documents;person uuid;begin
 select * into d from public.form_documents where id=p_id;
 if not found then raise exception 'document_access_denied';end if;
 perform private.medication_lock(d.clinic_id);
 for person in select distinct x from unnest(array[auth.uid(),d.created_by,d.responsible_id]) x where x is not null order by x loop perform pg_advisory_xact_lock(hashtextextended(person::text,9061));end loop;
 select * into d from public.form_documents where id=p_id for update;
 if not private.form_readable(d) then raise exception 'document_access_denied';end if;
 perform private.form_draft_current(d);
 return d;
end$$;
create function private.form_authorship_for_draft(d public.form_documents,p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare a private.form_authorship_attestations;begin
 select * into a from private.form_authorship_attestations where id=p_id and document_id=d.id and clinic_id=d.clinic_id;
 if not found or a.signer_id<>d.created_by or a.draft_revision<>d.revision or a.content_hash<>private.form_draft_content(d) then raise exception 'document_authorship_stale';end if;
 perform private.form_draft_current(d);
 if private.permission_effective(d.clinic_id,a.signer_id,'form.prepare') is distinct from a.permission_grant_id
 or not exists(select 1 from public.clinic_members where clinic_id=d.clinic_id and user_id=a.signer_id and created_at=a.member_since) then raise exception 'document_authorship_authority_changed';end if;
 perform private.form_validate_signature(a.signature);
 return jsonb_build_object('scope','document_authorship','id',a.id,'user_id',a.signer_id,'name',a.signer_name,'signature',a.signature,'signed_at',a.signed_at,'content_hash',a.content_hash);
end$$;
create function private.form_draft_editable(d public.form_documents) returns boolean language plpgsql stable security definer set search_path='' as $$begin
 if d.created_by<>auth.uid() or not private.form_readable(d) then return false;end if;
 perform private.form_draft_current(d);return true;
exception when others then return false;
end$$;
create function private.form_document_safe(d public.form_documents) returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(d)||jsonb_build_object('snapshot',jsonb_build_object('schema',d.snapshot->'schema','patient',d.snapshot->'patient','owner',d.snapshot->'owner','clinic_name',d.snapshot->'clinic_name','clinical',d.snapshot->'clinical','document_flow_version',d.snapshot->'document_flow_version','can_edit',private.form_draft_editable(d)),
 'authorship',case when d.state='draft' then (select jsonb_build_object('id',a.id,'name',a.signer_name,'user_id',a.signer_id,'signed_at',a.signed_at,'scope','document_authorship') from private.form_authorship_attestations a where a.document_id=d.id and a.draft_revision=d.revision and a.content_hash=private.form_draft_content(d) and private.permission_effective(a.clinic_id,a.signer_id,'form.prepare')=a.permission_grant_id and private.form_document_current(a.clinic_id,a.signer_id,'form.prepare') and exists(select 1 from public.clinic_members m where m.clinic_id=a.clinic_id and m.user_id=a.signer_id and m.created_at=a.member_since) order by a.signed_at desc,a.id desc limit 1) end);
$$;
revoke all on function private.form_document_current(uuid,uuid,text),private.form_document_reader(uuid),private.form_draft_content(public.form_documents),private.form_draft_current(public.form_documents),private.form_draft_lock(uuid),private.form_authorship_for_draft(public.form_documents,uuid),private.form_document_safe(public.form_documents),private.form_draft_editable(public.form_documents) from public,anon,authenticated,service_role;
-- Only checked RPCs return document data; never raw signature vectors in lists.
revoke select on public.form_documents,public.form_signatures from authenticated;
grant select(id,clinic_id) on public.form_documents to authenticated;
drop policy form_signature_read on public.form_signatures;
create or replace function public.form_documents_list(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.form_document_reader(p_clinic) then raise exception 'document_read_required';end if;
 return coalesce((select jsonb_agg(private.form_document_safe(d) order by d.created_at desc,d.id) from public.form_documents d where d.clinic_id=p_clinic and private.form_readable(d)),'[]');
end$$;
create function public.form_document_workspace(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare readable boolean;prep boolean;begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'current_member_required';end if;
 readable=private.form_document_reader(p_clinic);prep=readable and private.form_document_current(p_clinic,auth.uid(),'form.prepare') and private.form_template_current(p_clinic,'form.template.read');
 return jsonb_build_object('schema_version',1,'mode','draft_authorship','can_read',readable,'can_prepare',prep,
 'approved_template_ids',case when prep then coalesce((select jsonb_agg(v.id) from public.form_template_versions v where v.clinic_id=p_clinic and v.approved and exists(select 1 from public.audit_log a where a.clinic_id=p_clinic and a.entity_id=v.id::text and a.action='form_template_version_created' and a.details->>'approval_grant_id' is not null and a.details->>'profile_version_id' is not null)),'[]') else '[]'::jsonb end,
 'responsibles',case when prep then coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'name',v->>'name','license',v->>'license') order by p.user_id)
 from public.professional_profiles p cross join lateral(select private.rx_profile(p.id) v) q where p.clinic_id=p_clinic and private.clinical_professional_at(p.clinic_id,p.user_id,clock_timestamp()) and private.form_document_current(p.clinic_id,p.user_id,'form.authorize') and private.form_document_current(p.clinic_id,p.user_id,'clinical.read') and private.form_document_current(p.clinic_id,p.user_id,'patient.read')),'[]') else '[]'::jsonb end);
end$$;
create function public.form_document_draft_create(p_clinic uuid,p_patient uuid,p_version uuid,p_responsible uuid,p_values jsonb,p_branding jsonb,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.form_template_versions;p public.vet_patients;o public.vet_owners;d public.form_documents;profile jsonb;g uuid;person uuid;fp jsonb;receipt uuid;s jsonb;values_bound jsonb;begin
 perform private.medication_lock(p_clinic);
 for person in select distinct x from unnest(array[auth.uid(),p_responsible]) x where x is not null order by x loop perform pg_advisory_xact_lock(hashtextextended(person::text,9061));end loop;
 perform private.hospital_order_permission(p_clinic,'clinical.read',null,false);perform private.hospital_order_permission(p_clinic,'patient.read',null,false);
 perform private.hospital_order_permission(p_clinic,'form.template.read',null,false);g=private.hospital_order_permission(p_clinic,'form.prepare',null,false);
 if p_responsible is null or not private.clinical_professional_at(p_clinic,p_responsible,clock_timestamp()) or not private.form_document_current(p_clinic,p_responsible,'form.authorize') or not private.form_document_current(p_clinic,p_responsible,'clinical.read') or not private.form_document_current(p_clinic,p_responsible,'patient.read') then raise exception 'explicit_verified_responsible_required';end if;
 select private.rx_profile(id) into profile from public.professional_profiles where clinic_id=p_clinic and user_id=p_responsible;
 select * into v from public.form_template_versions where id=p_version and clinic_id=p_clinic and approved;
 if not found or not exists(select 1 from public.audit_log where clinic_id=p_clinic and entity_id=p_version::text and action='form_template_version_created' and details->>'approval_grant_id' is not null and details->>'profile_version_id' is not null) then raise exception 'reviewed_template_version_required';end if;
 values_bound=p_values||jsonb_build_object('mvz_name',profile->>'name','mvz_license',profile->>'license');
 perform private.form_validate_values(v.schema,values_bound,false);perform private.form_validate_brand(p_branding);
 fp=jsonb_build_object('kind','attributed_form_draft','patient',p_patient,'version',p_version,'responsible',p_responsible,'values',p_values,'branding',p_branding);
 receipt=private.vet_receipt(p_clinic,p_operation,fp);
 if receipt is not null then select * into d from public.form_documents where id=receipt;perform private.form_draft_current(d);return private.form_document_safe(d);end if;
 select * into p from public.vet_patients where id=p_patient and clinic_id=p_clinic;
 if not found or (p.owner_id is null and v.schema->>'type' not in ('clinical_history','surgical_sheet','surgical_risk')) then raise exception 'patient_and_owner_required';end if;
 select * into o from public.vet_owners where id=p.owner_id and clinic_id=p_clinic;
 s=jsonb_build_object('schema',v.schema,'template_version',v.version,'patient',jsonb_build_object('id',p.id,'name',p.name,'species',p.species,'breed',p.breed,'sex',p.sex),'owner',jsonb_build_object('id',o.id,'name',coalesce(o.name,'Sin propietario registrado')),'clinical',v.schema->>'type' in ('clinical_history','surgical_sheet','surgical_risk'),'responsible_id',p_responsible,'clinic_name',(select name from public.clinics where id=p_clinic),'document_flow_version',1,
 'draft_authority',jsonb_build_object('prepare_grant_id',g,'author_member_since',(select created_at from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()),'responsible_member_since',(select created_at from public.clinic_members where clinic_id=p_clinic and user_id=p_responsible),'responsible_profile_version_id',profile->>'id','responsible_selection_grant_id',private.permission_effective(p_clinic,p_responsible,'form.authorize')));
 insert into public.form_documents(clinic_id,patient_id,version_id,responsible_id,values,branding,snapshot,created_by) values(p_clinic,p_patient,p_version,p_responsible,values_bound,p_branding,s,auth.uid()) returning * into d;
 perform private.form_draft_current(d);
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,d.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'attributed_form_draft_created',d.id,jsonb_build_object('prepare_grant_id',g,'responsible_selected',p_responsible,'authorization_recorded',false));
 return private.form_document_safe(d);
end$$;
create or replace function public.form_document_save(p_id uuid,p_revision integer,p_values jsonb,p_branding jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;profile jsonb;bound jsonb;begin
 d=private.form_draft_lock(p_id);
 if d.created_by<>auth.uid() then raise exception 'draft_author_only';end if;
 if d.revision is distinct from p_revision then raise exception 'document_revision_conflict';end if;
 select private.rx_profile(id) into profile from public.professional_profiles where clinic_id=d.clinic_id and user_id=d.responsible_id;
 bound=p_values||jsonb_build_object('mvz_name',profile->>'name','mvz_license',profile->>'license');
 perform private.form_validate_values(d.snapshot->'schema',bound,false);perform private.form_validate_brand(p_branding);
 perform private.form_draft_current(d);
 update public.form_documents set values=bound,branding=p_branding,revision=revision+1 where id=p_id returning * into d;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(d.clinic_id,auth.uid(),'attributed_form_draft_changed',d.id,jsonb_build_object('revision',d.revision,'signatures_invalidated',true));
 return private.form_document_safe(d);
end$$;
create function public.form_document_authorship_sign(p_id uuid,p_revision integer,p_name text,p_signature jsonb,p_confirmed boolean,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.form_documents;g uuid;fp jsonb;receipt uuid;content text;begin
 d=private.form_draft_lock(p_id);
 if d.created_by<>auth.uid() then raise exception 'draft_author_only';end if;
 if d.revision is distinct from p_revision then raise exception 'document_revision_conflict';end if;
 g=private.hospital_order_permission(d.clinic_id,'form.prepare',null,false);
 if p_confirmed is distinct from true then raise exception 'document_authorship_confirmation_required';end if;
 if coalesce(length(btrim(p_name)),0) not between 1 and 200 or p_name~'[[:cntrl:]]' then raise exception 'document_author_name_required';end if;
 perform private.form_validate_signature(p_signature);content=private.form_draft_content(d);
 fp=jsonb_build_object('kind','document_authorship','document',d.id,'revision',d.revision,'name',btrim(p_name),'signature',p_signature,'content_hash',content,'confirmed',true);
 receipt=private.vet_receipt(d.clinic_id,p_operation,fp);if receipt is not null then return receipt;end if;
 insert into private.form_authorship_attestations(clinic_id,document_id,draft_revision,content_hash,signer_id,signer_name,signature,member_since,permission_grant_id)
 values(d.clinic_id,d.id,d.revision,content,auth.uid(),btrim(p_name),p_signature,(select created_at from public.clinic_members where clinic_id=d.clinic_id and user_id=auth.uid()),g) returning id into receipt;
 insert into private.vet_operation_receipts values(auth.uid(),d.clinic_id,p_operation,fp,receipt);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(d.clinic_id,auth.uid(),'form_authorship_attested',d.id,jsonb_build_object('attestation_id',receipt,'scope','document_authorship','signer_name',btrim(p_name),'revision',d.revision,'content_hash',content,'permission_grant_id',g,'tutor_acceptance_recorded',false,'clinical_act_recorded',false));
 return receipt;
end$$;
-- Retire legacy mutation entrypoints as part of this local candidate. The next
-- phase must provide explicit authorization/PDF issuance before deployment.
create or replace function public.form_document_create(p_clinic uuid,p_patient uuid,p_version uuid,p_values jsonb,p_branding jsonb,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$begin raise exception 'explicit_form_responsible_required';end$$;
create or replace function public.form_document_prepare(p_id uuid,p_revision integer,p_tutor_signature jsonb,p_mvz_signature jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin raise exception 'attributed_form_authorization_required';end$$;
create or replace function public.form_document_finalize(p_id uuid,p_revision integer,p_pdf_hash text) returns jsonb language plpgsql security definer set search_path='' as $$begin raise exception 'attributed_form_authorization_required';end$$;
create or replace function public.form_document_use_profile(p_id uuid,p_revision integer,p_profile uuid,p_share boolean) returns jsonb language plpgsql security definer set search_path='' as $$begin raise exception 'shared_form_signature_closed';end$$;
create or replace function public.form_document_assign(p_id uuid,p_aux uuid) returns void language plpgsql security definer set search_path='' as $$begin raise exception 'explicit_document_assignment_required';end$$;
create or replace function public.form_document_snapshot(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.form_documents;begin
 select * into d from public.form_documents where id=p_id;
 if not found or not private.form_readable(d) or d.state<>'signed' then raise exception 'signed_document_access_required';end if;
 return to_jsonb(d);
end$$;
create or replace function public.form_read_pdf(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.form_documents;a private.form_artifacts;begin
 select * into d from public.form_documents where id=p_id;
 if not found or not private.form_readable(d) or d.state<>'signed' then raise exception 'signed_document_access_required';end if;
 select * into a from private.form_artifacts where document_id=d.id and revision=d.revision and content_hash=d.content_hash and pdf_hash=d.pdf_hash and encode(sha256(pdf),'hex')=d.pdf_hash;
 if not found then raise exception 'reviewed_pdf_required';end if;
 return jsonb_build_object('pdf',encode(a.pdf,'base64'),'hash',a.pdf_hash);
end$$;
create or replace function public.form_register_pdf(p_id uuid,p_revision integer,p_content_hash text,p_pdf text,p_tutor_png text,p_mvz_png text) returns jsonb language plpgsql security definer set search_path='' as $$begin raise exception 'attributed_form_authorization_required';end$$;
revoke all on function public.form_document_workspace(uuid),public.form_document_draft_create(uuid,uuid,uuid,uuid,jsonb,jsonb,text),public.form_document_authorship_sign(uuid,integer,text,jsonb,boolean,text) from public,anon,authenticated;
grant execute on function public.form_document_workspace(uuid),public.form_document_draft_create(uuid,uuid,uuid,uuid,jsonb,jsonb,text),public.form_document_authorship_sign(uuid,integer,text,jsonb,boolean,text) to authenticated;
commit;
