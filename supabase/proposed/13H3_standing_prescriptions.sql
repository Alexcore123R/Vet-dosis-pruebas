-- LOCAL CANDIDATE after 13H2. Ordinary prescriptions, explicit existing case.
-- No deployment, no uncontrolled professional/operational permission conversion.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
alter table public.professional_delegations
 add column document_type text,
 add column authority_grant_id uuid references private.member_permission_grants(id),
 add column recipient_prepare_grant_id uuid references private.member_permission_grants(id),
 add column grantor_member_since timestamptz,
 add column recipient_member_since timestamptz,
 add column profile_version_id uuid references private.professional_profile_versions(id),
 add constraint typed_standing_metadata check(
 (document_type is null and authority_grant_id is null and recipient_prepare_grant_id is null and grantor_member_since is null and recipient_member_since is null and profile_version_id is null)
 or (document_type is not null and document_type='ordinary_prescription' and case_id is not null and authority_grant_id is not null and recipient_prepare_grant_id is not null and grantor_member_since is not null and recipient_member_since is not null and profile_version_id is not null and not use_signature and not dispense_ordinary));
alter table public.prescriptions add column authorization_mode text check(authorization_mode in ('individual','standing'));
alter table public.prescriptions drop constraint prescription_attribution_metadata;
alter table public.prescriptions add constraint prescription_attribution_metadata check(
 (consultation_attestation_id is null and prepared_by is null and prepare_grant_id is null and prepared_member_since is null and authorization_profile_version_id is null
 and authorized_by is null and authorized_at is null and authorization_grant_id is null and authorization_reference_id is null and issued_by is null and authorization_mode is null)
 or (consultation_attestation_id is not null and prepared_by is not null and prepare_grant_id is not null and prepared_member_since is not null and authorization_profile_version_id is not null
 and ((authorized_by is null and authorized_at is null and authorization_grant_id is null and authorization_reference_id is null and authorization_mode is null)
 or (authorized_by is not null and authorized_by=responsible_id and authorized_at is not null and authorization_grant_id is not null and authorization_reference_id is not null))
 and (authorization_mode is distinct from 'standing' or (delegation_id is not null and not controlled and authorized_by is not null))
 and (issued_by is null or (state='issued' and authorized_by is not null and ((coalesce(authorization_mode,'individual')='individual' and issued_by=authorized_by) or (authorization_mode='standing' and issued_by=prepared_by))))));
grant select(authorization_mode) on public.prescriptions to authenticated;
create table private.rx_standing_acceptances (
 delegation_id uuid primary key references public.professional_delegations(id),
 recipient_id uuid not null references auth.users(id),accepted_at timestamptz not null default clock_timestamp()
);
create table private.rx_standing_events (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,prescription_id uuid not null,
 delegation_id uuid not null references public.professional_delegations(id),
 recipient_id uuid not null references auth.users(id),responsible_id uuid not null references auth.users(id),
 content_hash text not null,pdf_hash text not null,created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,prescription_id) references public.prescriptions(clinic_id,id),unique(prescription_id)
);
create table private.rx_standing_reviews (
 event_id uuid primary key references private.rx_standing_events(id),reviewed_by uuid not null references auth.users(id),
 reviewed_at timestamptz not null default clock_timestamp(),note text not null check(length(note)<=1000)
);
do $$declare t text;begin
 foreach t in array array['rx_standing_acceptances','rx_standing_events','rx_standing_reviews'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated',t);
 execute format('create trigger immutable before update or delete on private.%I for each row execute function private.permission_immutable()',t);
 end loop;
end$$;

create function private.rx_standing_valid(d public.professional_delegations,p_accepted boolean default true) returns boolean language sql stable security definer set search_path='' as $$
 select d.document_type='ordinary_prescription' and d.case_id is not null and d.created_by<>d.recipient_id and d.valid_until>clock_timestamp()
 and not d.use_signature and not d.dispense_ordinary and d.use_data and d.prepare_ordinary and d.issue_ordinary
 and exists(select 1 from public.clinical_cases c where c.id=d.case_id and c.clinic_id=d.clinic_id and c.responsible_id=d.created_by)
 and exists(select 1 from public.professional_profiles p where p.id=d.profile_id and p.clinic_id=d.clinic_id and p.user_id=d.created_by and (private.rx_profile(p.id)->>'id')::uuid=d.profile_version_id)
 and private.clinical_professional_at(d.clinic_id,d.created_by,clock_timestamp())
 and exists(select 1 from public.clinic_members where clinic_id=d.clinic_id and user_id=d.created_by and created_at=d.grantor_member_since)
 and exists(select 1 from public.clinic_members where clinic_id=d.clinic_id and user_id=d.recipient_id and created_at=d.recipient_member_since)
 and private.permission_effective(d.clinic_id,d.created_by,'prescription.authorize')=d.authority_grant_id
 and private.permission_effective(d.clinic_id,d.recipient_id,'prescription.prepare')=d.recipient_prepare_grant_id
 and exists(select 1 from private.member_permission_grants where id=d.authority_grant_id and valid_until>clock_timestamp())
 and exists(select 1 from private.member_permission_grants where id=d.recipient_prepare_grant_id and valid_until>clock_timestamp())
 and private.permission_effective(d.clinic_id,d.recipient_id,'clinical.read') is not null and private.permission_effective(d.clinic_id,d.recipient_id,'patient.read') is not null
 and not exists(select 1 from public.professional_delegation_revocations where delegation_id=d.id)
 and (not p_accepted or exists(select 1 from private.rx_standing_acceptances where delegation_id=d.id and recipient_id=d.recipient_id));
$$;
create function public.rx_standing_offer(p_case uuid,p_recipient uuid,p_until text,p_confirmed boolean,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;g uuid;rg uuid;p public.professional_profiles;v jsonb;issuer_epoch timestamptz;recipient_epoch timestamptz;expiry timestamptz;fp jsonb;result uuid;begin
 c=private.medication_case_lock(p_case);
 g=private.medication_permission(c.clinic_id,'prescription.authorize');
 if c.responsible_id<>auth.uid() or p_confirmed is distinct from true then raise exception 'responsible_explicit_authorization_required';end if;
 if p_recipient is null or p_recipient=auth.uid() then raise exception 'different_recipient_required';end if;
 select created_at into issuer_epoch from public.clinic_members where clinic_id=c.clinic_id and user_id=auth.uid();
 select created_at into recipient_epoch from public.clinic_members where clinic_id=c.clinic_id and user_id=p_recipient;
 rg=private.permission_effective(c.clinic_id,p_recipient,'prescription.prepare');
 if recipient_epoch is null or rg is null or private.permission_effective(c.clinic_id,p_recipient,'patient.read') is null or private.permission_effective(c.clinic_id,p_recipient,'clinical.read') is null then raise exception 'recipient_preparation_permissions_required';end if;
 expiry=private.clinical_time(p_until);
 if expiry<=clock_timestamp() or not exists(select 1 from private.member_permission_grants where id=g and valid_until>=expiry)
 or not exists(select 1 from private.member_permission_grants where id=rg and valid_until>=expiry) then raise exception 'standing_expiry_outside_permissions';end if;
 select * into p from public.professional_profiles where clinic_id=c.clinic_id and user_id=auth.uid();v=private.rx_profile(p.id);
 fp=jsonb_build_object('kind','standing_offer','case',p_case,'recipient',p_recipient,'until',p_until,'confirmed',true);
 result=private.vet_receipt(c.clinic_id,p_operation,fp);if result is not null then return result;end if;
 insert into public.professional_delegations(clinic_id,profile_id,recipient_id,case_id,use_data,use_signature,prepare_ordinary,issue_ordinary,dispense_ordinary,valid_until,created_by,
 document_type,authority_grant_id,recipient_prepare_grant_id,grantor_member_since,recipient_member_since,profile_version_id)
 values(c.clinic_id,p.id,p_recipient,c.id,true,false,true,true,false,expiry,auth.uid(),'ordinary_prescription',g,rg,issuer_epoch,recipient_epoch,(v->>'id')::uuid) returning id into result;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,result);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(c.clinic_id,auth.uid(),'ordinary_standing_authorization_offered',result,jsonb_build_object('case_id',c.id,'recipient_id',p_recipient,'valid_until',expiry,'authority_grant_id',g));return result;
end$$;
create function public.rx_standing_accept(p_id uuid,p_confirmed boolean,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.professional_delegations;c public.clinical_cases;fp jsonb;result uuid;inserted integer;begin
 select * into d from public.professional_delegations where id=p_id;
 if not found or d.recipient_id is distinct from auth.uid() then raise exception 'standing_recipient_only';end if;
 c=private.medication_case_lock(d.case_id);
 if p_confirmed is distinct from true then raise exception 'standing_acceptance_required';end if;
 if private.rx_standing_valid(d,false) is distinct from true then raise exception 'standing_authorization_unavailable';end if;
 fp=jsonb_build_object('kind','standing_acceptance','delegation',p_id,'confirmed',true);
 result=private.vet_receipt(d.clinic_id,p_operation,fp);if result is not null then return result;end if;
 insert into private.rx_standing_acceptances(delegation_id,recipient_id) values(d.id,auth.uid()) on conflict do nothing;
 get diagnostics inserted = row_count;
 insert into private.vet_operation_receipts values(auth.uid(),d.clinic_id,p_operation,fp,d.id);
 if inserted=1 then insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(d.clinic_id,auth.uid(),'ordinary_standing_authorization_accepted',d.id);end if;return d.id;
end$$;

alter function private.rx_permission(public.prescriptions,text) rename to rx_permission_before_standing;
revoke all on function private.rx_permission_before_standing(public.prescriptions,text) from public,anon,authenticated;
create function private.rx_permission(r public.prescriptions,scope text) returns void language plpgsql security definer set search_path='' as $$
declare d public.professional_delegations;begin
 if scope='issue' and r.authorization_mode='standing' then
  select * into d from public.professional_delegations where id=r.delegation_id;
  if r.controlled or r.prepared_by is distinct from auth.uid() or d.recipient_id is distinct from auth.uid() then raise exception 'standing_recipient_only';end if;
  if d.case_id is distinct from r.case_id or private.rx_standing_valid(d) is distinct from true then raise exception 'standing_authorization_unavailable';end if;
  perform private.medication_permission(r.clinic_id,'prescription.prepare');
 else perform private.rx_permission_before_standing(r,scope);end if;
end$$;
alter function private.rx_attributed_current(public.prescriptions,boolean) rename to rx_attributed_before_standing;
revoke all on function private.rx_attributed_before_standing(public.prescriptions,boolean) from public,anon,authenticated;
create function private.rx_attributed_current(r public.prescriptions,p_authorized boolean) returns void language plpgsql security definer set search_path='' as $$
declare d public.professional_delegations;begin
 perform private.rx_attributed_before_standing(r,p_authorized);
 if r.authorization_mode='standing' then
  select * into d from public.professional_delegations where id=r.delegation_id;
  if r.controlled or d.case_id is distinct from r.case_id or d.recipient_id is distinct from r.prepared_by or private.rx_standing_valid(d) is distinct from true
  or r.authorization_reference_id is distinct from d.id or r.authorization_grant_id is distinct from d.authority_grant_id or r.authorization_profile_version_id is distinct from d.profile_version_id then raise exception 'standing_authorization_unavailable';end if;
 end if;
end$$;
create function public.rx_prepare_standing(p_id uuid,p_revision integer,p_attestation uuid,p_preparer_name text,p_delegation uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;c public.clinical_cases;d public.professional_delegations;s jsonb;t timestamptz;begin
 select * into r from public.prescriptions where id=p_id;
 if not found then raise exception 'prescription_access_denied';end if;
 c=private.medication_case_lock(r.case_id);
 select * into d from public.professional_delegations where id=p_delegation;
 if r.controlled then raise exception 'controlled_responsible_only';end if;
 if d.recipient_id is distinct from auth.uid() or d.case_id is distinct from r.case_id or private.rx_standing_valid(d) is distinct from true then raise exception 'standing_authorization_unavailable';end if;
 perform public.rx_prepare_attributed(p_id,p_revision,p_attestation,p_preparer_name);
 select * into r from public.prescriptions where id=p_id for update;
 perform private.rx_products_ready(r);
 if r.authorization_profile_version_id is distinct from d.profile_version_id then raise exception 'responsible_profile_changed';end if;
 t=clock_timestamp();s=jsonb_set(r.snapshot,'{prepared_at}',to_jsonb(to_char(t at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
 s=jsonb_set(s,'{prescription_identity,authorization}',jsonb_build_object('mode','standing','actor_id',d.created_by,'authorized_at',to_char(d.created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
 'reference_id',d.id,'valid_until',to_char(d.valid_until at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'document_type',d.document_type,'case_id',d.case_id));
 update public.prescriptions set state='awaiting_review',authorization_mode='standing',delegation_id=d.id,authorized_by=d.created_by,authorized_at=d.created_at,authorization_grant_id=d.authority_grant_id,
 authorization_reference_id=d.id,snapshot=s,content_hash=encode(sha256(convert_to(s::text,'UTF8')),'hex') where id=r.id returning * into r;
 perform private.rx_attributed_current(r,true);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(r.clinic_id,auth.uid(),'prescription_prepared_under_standing_authorization',r.id,jsonb_build_object('delegation_id',d.id,'authority_grant_id',d.authority_grant_id));
 return to_jsonb(r)-'snapshot';
end$$;

create or replace function private.rx_prepared_permission(r public.prescriptions) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.rx_readable(r) then raise exception 'prescription_access_denied';end if;
 if r.state='awaiting_authorization' then raise exception 'individual_authorization_required';end if;
 perform private.rx_attributed_current(r,true);
 if auth.uid()=r.responsible_id then perform private.medication_permission(r.clinic_id,'prescription.authorize');
 elsif auth.uid()=r.prepared_by then perform private.rx_permission(r,'prepare');
 else raise exception 'prepared_prescription_access_denied';end if;
end$$;
alter function public.rx_finalize(uuid,integer,text) set schema private;
alter function private.rx_finalize(uuid,integer,text) rename to rx_finalize_before_standing;
revoke all on function private.rx_finalize_before_standing(uuid,integer,text) from public,anon,authenticated;
create function public.rx_finalize(p_id uuid,p_revision integer,p_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare before_row public.prescriptions;r public.prescriptions;result jsonb;begin
 select * into before_row from public.prescriptions where id=p_id;
 result=private.rx_finalize_before_standing(p_id,p_revision,p_hash);
 select * into r from public.prescriptions where id=p_id;
 if r.authorization_mode='standing' and before_row.state<>'issued' then
  insert into private.rx_standing_events(clinic_id,prescription_id,delegation_id,recipient_id,responsible_id,content_hash,pdf_hash)
  values(r.clinic_id,r.id,r.delegation_id,r.issued_by,r.responsible_id,r.content_hash,r.pdf_hash) on conflict(prescription_id) do nothing;
 end if;
 return result;
end$$;
create function public.rx_standing_resume(p_clinic uuid,p_reason text,p_operation text) returns integer language plpgsql security definer set search_path='' as $$
declare d public.professional_delegations;fp jsonb;receipt uuid;result integer=0;begin
 perform private.medication_lock(p_clinic);
 if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'current_member_required';end if;
 if coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'revocation_reason_required';end if;
 fp=jsonb_build_object('kind','standing_resume','reason',btrim(p_reason));receipt=private.vet_receipt(p_clinic,p_operation,fp);
 if receipt is not null then return (select (details->>'count')::integer from public.audit_log where action='ordinary_standing_authorizations_resumed' and details->>'receipt'=receipt::text);end if;
 for d in select * from public.professional_delegations where clinic_id=p_clinic and created_by=auth.uid() and document_type='ordinary_prescription' and not exists(select 1 from public.professional_delegation_revocations where delegation_id=professional_delegations.id) loop
 insert into public.professional_delegation_revocations(delegation_id,reason,created_by) values(d.id,btrim(p_reason),auth.uid());result=result+1;end loop;
 receipt=gen_random_uuid();insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,receipt);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'ordinary_standing_authorizations_resumed',receipt,jsonb_build_object('receipt',receipt,'count',result,'reason',btrim(p_reason)));return result;
end$$;

create function public.rx_standing_review(p_event uuid,p_content_hash text,p_pdf_hash text,p_confirmed boolean,p_note text) returns uuid language plpgsql security definer set search_path='' as $$
declare e private.rx_standing_events;r public.prescriptions;c public.clinical_cases;existing private.rx_standing_reviews;begin
 select * into e from private.rx_standing_events where id=p_event;
 if not found or e.responsible_id is distinct from auth.uid() then raise exception 'responsible_review_only';end if;
 select * into r from public.prescriptions where id=e.prescription_id;c=private.medication_case_lock(r.case_id);
 perform private.medication_permission(e.clinic_id,'prescription.authorize');
 if not private.clinical_professional_at(e.clinic_id,auth.uid(),clock_timestamp()) then raise exception 'responsible_professional_required';end if;
 if p_confirmed is distinct from true or length(coalesce(p_note,''))>1000 then raise exception 'post_review_confirmation_required';end if;
 if r.state<>'issued' or r.content_hash is distinct from p_content_hash or r.pdf_hash is distinct from p_pdf_hash or e.content_hash is distinct from p_content_hash or e.pdf_hash is distinct from p_pdf_hash then raise exception 'reviewed_prescription_mismatch';end if;
 select * into existing from private.rx_standing_reviews where event_id=e.id;
 if found then
  if existing.note is distinct from coalesce(p_note,'') then raise exception 'post_review_already_recorded';end if;return e.id;
 end if;
 insert into private.rx_standing_reviews(event_id,reviewed_by,note) values(e.id,auth.uid(),coalesce(p_note,''));
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(e.clinic_id,auth.uid(),'standing_prescription_reviewed_after_issuance',r.id,jsonb_build_object('event_id',e.id,'content_hash',p_content_hash,'pdf_hash',p_pdf_hash));return e.id;
end$$;

create function public.rx_standing_workspace(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare can_authorize boolean;begin
 if private.permission_effective(p_clinic,auth.uid(),'clinical.read') is null or private.permission_effective(p_clinic,auth.uid(),'patient.read') is null then raise exception 'case_access_required';end if;
 can_authorize=private.clinical_professional_at(p_clinic,auth.uid(),clock_timestamp()) and private.permission_effective(p_clinic,auth.uid(),'prescription.authorize') is not null;
 return jsonb_build_object('members',case when can_authorize then coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'label',coalesce(nullif(private.rx_profile(p.id)->>'name',''),u.email,m.user_id::text))) from public.clinic_members m join auth.users u on u.id=m.user_id left join public.professional_profiles p on p.clinic_id=m.clinic_id and p.user_id=m.user_id
 where m.clinic_id=p_clinic and m.user_id<>auth.uid() and private.permission_effective(p_clinic,m.user_id,'prescription.prepare') is not null and private.permission_effective(p_clinic,m.user_id,'clinical.read') is not null and private.permission_effective(p_clinic,m.user_id,'patient.read') is not null),'[]') else '[]'::jsonb end,
 'offers',coalesce((select jsonb_agg((to_jsonb(d))||jsonb_build_object('accepted',exists(select 1 from private.rx_standing_acceptances where delegation_id=d.id),'active',coalesce(private.rx_standing_valid(d),false),'available',coalesce(private.rx_standing_valid(d,false),false),'revoked',exists(select 1 from public.professional_delegation_revocations where delegation_id=d.id))) from public.professional_delegations d where d.clinic_id=p_clinic and d.document_type='ordinary_prescription' and (d.created_by=auth.uid() or d.recipient_id=auth.uid())),'[]'),
 'events',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object('patient_name',p.name,'reviewed',v.event_id is not null,'reviewed_at',v.reviewed_at) order by e.created_at desc) from private.rx_standing_events e join public.prescriptions r on r.id=e.prescription_id join public.vet_patients p on p.id=r.patient_id left join private.rx_standing_reviews v on v.event_id=e.id where e.clinic_id=p_clinic and e.responsible_id=auth.uid() and private.rx_readable(r)),'[]'));
end$$;

alter function public.rx_prescription_permissions(uuid) set schema private;
alter function private.rx_prescription_permissions(uuid) rename to rx_permissions_before_standing;
revoke all on function private.rx_permissions_before_standing(uuid) from public,anon,authenticated;
create function public.rx_prescription_permissions(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare base jsonb;rows jsonb;begin
 base=private.rx_permissions_before_standing(p_clinic);
 select coalesce(jsonb_agg(a.value||jsonb_build_object('prepare_standing',not r.controlled and r.state='draft' and (base->>'can_prepare')::boolean and exists(select 1 from public.professional_delegations d where d.case_id=r.case_id and d.recipient_id=auth.uid() and private.rx_standing_valid(d)),
 'issue',case when r.authorization_mode='standing' then r.state in ('awaiting_review','ready') and r.prepared_by=auth.uid() and exists(select 1 from public.professional_delegations d where d.id=r.delegation_id and private.rx_standing_valid(d)) else (a.value->>'issue')::boolean end)),'[]') into rows
 from jsonb_array_elements(base->'recipes') a(value) join public.prescriptions r on r.id=(a.value->>'id')::uuid;
 return base||jsonb_build_object('mode','individual_standing','standing_version',1,'recipes',rows);
end$$;
revoke all on function private.rx_standing_valid(public.professional_delegations,boolean),private.rx_permission(public.prescriptions,text),private.rx_attributed_current(public.prescriptions,boolean),public.rx_standing_offer(uuid,uuid,text,boolean,text),public.rx_standing_accept(uuid,boolean,text),public.rx_prepare_standing(uuid,integer,uuid,text,uuid),public.rx_finalize(uuid,integer,text),public.rx_standing_resume(uuid,text,text),public.rx_standing_review(uuid,text,text,boolean,text),public.rx_standing_workspace(uuid),public.rx_prescription_permissions(uuid) from public,anon,authenticated;
grant execute on function public.rx_standing_offer(uuid,uuid,text,boolean,text),public.rx_standing_accept(uuid,boolean,text),public.rx_prepare_standing(uuid,integer,uuid,text,uuid),public.rx_finalize(uuid,integer,text),public.rx_standing_resume(uuid,text,text),public.rx_standing_review(uuid,text,text,boolean,text),public.rx_standing_workspace(uuid),public.rx_prescription_permissions(uuid) to authenticated;
create or replace function public.rx_return_to_draft(p_id uuid,p_revision integer,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.prescriptions;c public.clinical_cases;begin
 select * into r from public.prescriptions where id=p_id;
 if not found then raise exception 'prescription_access_denied';end if;
 c=private.medication_case_lock(r.case_id);
 select * into r from public.prescriptions where id=p_id for update;
 if auth.uid()=r.responsible_id then perform private.medication_permission(r.clinic_id,'prescription.authorize');
 elsif auth.uid()=r.prepared_by then perform private.rx_permission(r,'prepare');
 else raise exception 'prepared_prescription_access_denied';end if;
 if r.revision is distinct from p_revision or r.state not in ('awaiting_authorization','awaiting_review','ready') then raise exception 'prescription_revision_conflict';end if;
 if coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'prescription_correction_reason_required';end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(r.clinic_id,auth.uid(),'prescription_returned_to_draft',r.id,jsonb_build_object('reason',btrim(p_reason),'previous_revision',r.revision,'previous_content_hash',r.content_hash,'authorization_reference_id',r.authorization_reference_id));
 delete from private.rx_artifacts where kind='prescription' and entity_id=r.id;
 update public.prescriptions set authorization_mode=null,state='draft',revision=revision+1,snapshot=null,content_hash=null,pdf_hash=null,profile_id=null,delegation_id=null,use_shared_signature=false,regulatory_version_id=null,consultation_attestation_id=null,
 prepared_by=null,prepared_member_since=null,prepare_grant_id=null,prepared_at=null,authorized_by=null,authorized_at=null,authorization_grant_id=null,authorization_reference_id=null,authorization_profile_version_id=null where id=r.id returning * into r;
 return to_jsonb(r)-'snapshot';
end$$;

select private.beta_install_guards();
commit;
