-- LOCAL CANDIDATE 13H1, after 13G. Attribution primitive only, NOT full Rx cutover.
-- No deployment, no automatic historic signatures, no clinical permission grant.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
create table private.prescription_consultation_attestations (
 id uuid primary key default gen_random_uuid(),
 clinic_id uuid not null, prescription_id uuid not null,
 draft_revision integer not null check(draft_revision>0), content_hash text not null check(content_hash~'^[0-9a-f]{64}$'),
 signer_id uuid not null references auth.users(id), signer_name text not null check(length(btrim(signer_name)) between 1 and 200 and signer_name!~'[[:cntrl:]]'),
 signature jsonb not null, member_since timestamptz not null,
 permission_grant_id uuid not null references private.member_permission_grants(id),
 signed_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,prescription_id) references public.prescriptions(clinic_id,id)
);
alter table private.prescription_consultation_attestations enable row level security;
revoke all on private.prescription_consultation_attestations from public,anon,authenticated;
create trigger permission_immutable before update or delete on private.prescription_consultation_attestations
 for each row execute function private.permission_immutable();

create function private.rx_consultation_content(r public.prescriptions) returns text
language sql stable security definer set search_path='' as $$
 select encode(sha256(convert_to(jsonb_build_object(
  'clinic',r.clinic_id,'case',r.case_id,'patient',r.patient_id,'responsible',r.responsible_id,
  'controlled',r.controlled,'folio',r.official_folio,'instructions',r.instructions,
  'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.id) from public.prescription_items i where i.prescription_id=r.id),'[]'::jsonb)
 )::text,'UTF8')),'hex');
$$;

create function public.rx_consultation_sign(p_id uuid,p_revision integer,p_name text,p_signature jsonb,p_confirmed boolean,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;c public.clinical_cases;g uuid;member_at timestamptz;fp jsonb;result_id uuid;content text;
begin
 select * into r from public.prescriptions where id=p_id;
 if not found then raise exception 'prescription_access_denied';end if;
 c=private.medication_case_lock(r.case_id);
 select * into r from public.prescriptions where id=p_id for update;
 g=private.medication_permission(c.clinic_id,'prescription.prepare');
 if r.clinic_id is distinct from c.clinic_id or r.patient_id is distinct from c.patient_id or r.responsible_id is distinct from c.responsible_id then raise exception 'prescription_case_mismatch';end if;
 if not private.clinical_professional_at(c.clinic_id,c.responsible_id,clock_timestamp()) then raise exception 'case_verified_responsible_required';end if;
 if r.state<>'draft' or r.revision is distinct from p_revision then raise exception 'prescription_revision_conflict';end if;
 if p_confirmed is distinct from true then raise exception 'consultation_confirmation_required';end if;
 if coalesce(length(btrim(p_name)),0) not between 1 and 200 or p_name~'[[:cntrl:]]' then raise exception 'consultation_name_required';end if;
 perform private.form_validate_signature(p_signature);
 -- No signer parameter: a preparer cannot attest on someone else's behalf.
 select created_at into member_at from public.clinic_members where clinic_id=c.clinic_id and user_id=auth.uid();
 if member_at is null then raise exception 'current_member_required';end if;
 if r.controlled and (auth.uid()<>c.responsible_id or not private.clinical_professional_at(c.clinic_id,auth.uid(),clock_timestamp())) then raise exception 'controlled_responsible_only';end if;
 content=private.rx_consultation_content(r);
 fp=jsonb_build_object('kind','consultation_signature','prescription',r.id,'revision',p_revision,'name',btrim(p_name),'signature',p_signature,'content_hash',content,'confirmed',true);
 result_id=private.vet_receipt(c.clinic_id,p_operation,fp);
 if result_id is not null then return result_id;end if;
 insert into private.prescription_consultation_attestations(clinic_id,prescription_id,draft_revision,content_hash,signer_id,signer_name,signature,member_since,permission_grant_id)
 values(c.clinic_id,r.id,r.revision,content,auth.uid(),btrim(p_name),p_signature,member_at,g) returning id into result_id;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,result_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(c.clinic_id,auth.uid(),'consultation_signature_attested',r.id,jsonb_build_object('attestation_id',result_id,'draft_revision',r.revision,'content_hash',content,'permission_grant_id',g));
 return result_id;
end$$;

-- For the future prepare RPC. The caller must explicitly select the attestation;
-- do not infer who consulted from created_by or the last arbitrary signature.
create function private.rx_consultation_for_draft(r public.prescriptions,p_attestation uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a private.prescription_consultation_attestations;
begin
 select * into a from private.prescription_consultation_attestations where id=p_attestation and prescription_id=r.id and clinic_id=r.clinic_id;
 if not found then raise exception 'consultation_signature_required';end if;
 if r.state<>'draft' or a.draft_revision<>r.revision or a.content_hash<>private.rx_consultation_content(r) then raise exception 'consultation_signature_stale';end if;
 if not exists(select 1 from public.clinic_members m where m.clinic_id=a.clinic_id and m.user_id=a.signer_id and m.created_at=a.member_since)
 or private.permission_effective(a.clinic_id,a.signer_id,'prescription.prepare') is distinct from a.permission_grant_id
 or not exists(select 1 from private.member_permission_grants g where g.id=a.permission_grant_id and g.valid_until>clock_timestamp()) then raise exception 'consultation_signer_authority_changed';end if;
 if r.controlled and (a.signer_id<>r.responsible_id or not private.clinical_professional_at(r.clinic_id,a.signer_id,clock_timestamp())) then raise exception 'controlled_responsible_only';end if;
 perform private.form_validate_signature(a.signature);
 return jsonb_build_object('user_id',a.signer_id,'name',a.signer_name,'signature',a.signature,'attestation_id',a.id,'signed_at',to_char(a.signed_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
end$$;

revoke all on function private.rx_consultation_content(public.prescriptions),private.rx_consultation_for_draft(public.prescriptions,uuid),public.rx_consultation_sign(uuid,integer,text,jsonb,boolean,text) from public,anon,authenticated;
grant execute on function public.rx_consultation_sign(uuid,integer,text,jsonb,boolean,text) to authenticated;
-- Deliberately does not replace rx_prepare/finalize yet. Their remaining legacy
-- authority and PDF generation must be migrated together before any beta cutover.
commit;
