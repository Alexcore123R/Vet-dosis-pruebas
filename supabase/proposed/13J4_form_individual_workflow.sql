-- LOCAL CANDIDATE 13J4, after 13J3. No deployment/beta activation.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy) or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
alter table public.form_documents drop constraint form_documents_state_check;
alter table public.form_documents add constraint form_documents_state_check check(state in ('draft','awaiting_authorization','awaiting_tutor','awaiting_review','ready','signed'));
insert into private.permission_catalog(code,label,procedure_scoped,requires_professional) values('form.issue','Emitir documento con autorización individual vigente',false,false);
-- New reference versions only. Existing clinic approvals and signed documents
-- are never rewritten or silently reapproved.
create function private.form_attribution_clause() returns text language sql immutable set search_path='' as $$
 select 'Registro clínico de la atención indicada, con elaboración y autorización identificadas por separado. No sustituye la autorización del tutor. Los campos sin captura permanecen pendientes; no representan hallazgos normales. Las actuaciones posteriores se anexan al expediente sin alterar este documento.'::text;
$$;
insert into public.form_template_versions(template_id,clinic_id,version,base_version_id,schema,source_status,reason)
 select v.template_id,null,v.version+1,v.id,jsonb_set(v.schema,'{clauses}',(select jsonb_agg(case when c->>'id'='clinical_scope' then jsonb_set(c,'{text}',to_jsonb(private.form_attribution_clause())) else c end order by n) from jsonb_array_elements(v.schema->'clauses') with ordinality x(c,n))), 'sin verificar','13J4: atribución separada; requiere nueva revisión de la clínica'
 from public.form_template_versions v where v.clinic_id is null and v.schema->>'type' in ('clinical_history','surgical_sheet','surgical_risk') and not exists(select 1 from public.form_template_versions newer where newer.template_id=v.template_id and newer.version>v.version);
revoke all on function private.form_attribution_clause() from public,anon,authenticated,service_role;
create table private.form_flow_events(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,document_id uuid not null,revision integer not null,
 kind text not null check(kind in ('attention','request','authorization','tutor','issuance')),
 content_hash text not null,actor_id uuid not null references auth.users(id),grant_id uuid not null references private.member_permission_grants(id),member_since timestamptz not null,
 payload jsonb not null,created_at timestamptz not null default clock_timestamp(),foreign key(clinic_id,document_id) references public.form_documents(clinic_id,id));
create table private.form_flow_artifacts(
 document_id uuid not null references public.form_documents(id),revision integer not null,kind text not null check(kind in ('preview','final')),
 content_hash text not null,pdf bytea not null,pdf_hash text not null,created_at timestamptz not null default clock_timestamp(),primary key(document_id,revision,kind));
alter table private.form_flow_events enable row level security;
alter table private.form_flow_artifacts enable row level security;
revoke all on private.form_flow_events,private.form_flow_artifacts from public,anon,authenticated,service_role;
create trigger immutable before update or delete on private.form_flow_events for each row execute function private.permission_immutable();
create trigger immutable before update or delete on private.form_flow_artifacts for each row execute function private.permission_immutable();
create function private.form_base_snapshot(d public.form_documents) returns jsonb language sql immutable set search_path='' as $$
 select d.snapshot-array['document_id','values','branding','prepared_at','form_identity','form_identity_version','form_preview','flow_request_id','flow_authorization_id','flow_tutor_id','staff_labels'];
$$;
create or replace function private.form_draft_content(d public.form_documents) returns text language sql stable security definer set search_path='' as $$
 select encode(sha256(convert_to(jsonb_build_object('document',d.id,'clinic',d.clinic_id,'patient',d.patient_id,'template',d.version_id,'responsible',d.responsible_id,'author',d.created_by,'values',d.values,'branding',d.branding,'snapshot',private.form_base_snapshot(d))::text,'UTF8')),'hex');
$$;
create or replace function private.form_document_reader(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.beta_read_allowed() and private.form_document_current(p_clinic,auth.uid(),'clinical.read') and private.form_document_current(p_clinic,auth.uid(),'patient.read');
$$;
create or replace function private.form_readable(d public.form_documents) returns boolean language sql stable security definer set search_path='' as $$
 select private.form_document_reader(d.clinic_id) and (
 (d.created_by=auth.uid() and private.form_document_current(d.clinic_id,auth.uid(),'form.prepare'))
 or (d.responsible_id=auth.uid() and private.form_document_current(d.clinic_id,auth.uid(),'form.authorize') and private.clinical_professional_at(d.clinic_id,auth.uid(),clock_timestamp()))
 or (d.snapshot->'attention_assignment'->>'actor_id'=auth.uid()::text and private.form_document_current(d.clinic_id,auth.uid(),'form.prepare'))
 or (d.state='signed' and exists(select 1 from public.clinical_cases c where (c.id::text=d.snapshot->'attention_assignment'->>'case_id' or c.document_id=d.id) and c.clinic_id=d.clinic_id and c.patient_id=d.patient_id and private.clinical_readable(c))));
$$;
create function private.form_flow_lock(p_id uuid,p_service boolean default false,p_next_actor uuid default null,p_next_case uuid default null) returns public.form_documents language plpgsql security definer set search_path='' as $$
declare d public.form_documents;person uuid;begin
 select * into d from public.form_documents where id=p_id;if not found then raise exception 'document_access_denied';end if;
 perform private.medication_lock(d.clinic_id);
 select * into d from public.form_documents where id=p_id;
 perform 1 from public.clinical_cases where id=any(array[(d.snapshot->'attention_assignment'->>'case_id')::uuid,p_next_case]) order by id for update;
 for person in select distinct x from unnest(array[auth.uid(),d.created_by,d.responsible_id,(d.snapshot->'attention_assignment'->>'actor_id')::uuid,p_next_actor]) x where x is not null order by x loop perform pg_advisory_xact_lock(hashtextextended(person::text,9061));end loop;
 select * into d from public.form_documents where id=p_id for update;
 if not p_service then
  if not private.form_readable(d) then raise exception 'document_access_denied';end if;
  perform public.beta_access_check(true,d.clinic_id);
 end if;
 return d;
end$$;
create function private.form_attention_current(d public.form_documents,e private.form_flow_events) returns void language plpgsql stable security definer set search_path='' as $$
declare a jsonb=d.snapshot->'attention_assignment';c public.clinical_cases;b private.clinical_scope_bindings;begin
 if e.kind<>'attention' or e.document_id<>d.id or e.revision<>d.revision or e.content_hash<>private.form_draft_content(d) or e.actor_id::text is distinct from a->>'actor_id'
 or private.permission_effective(d.clinic_id,e.actor_id,'form.prepare') is distinct from e.grant_id or not private.form_document_current(d.clinic_id,e.actor_id,'form.prepare')
 or not private.form_document_current(d.clinic_id,e.actor_id,'clinical.read') or not private.form_document_current(d.clinic_id,e.actor_id,'patient.read')
 or not exists(select 1 from public.clinic_members where clinic_id=d.clinic_id and user_id=e.actor_id and created_at=e.member_since)
 or e.grant_id::text is distinct from a->>'prepare_grant_id' or e.member_since is distinct from (a->>'member_since')::timestamptz then raise exception 'attention_authority_changed';end if;
 if coalesce((d.snapshot->>'clinical')::boolean,false) then
  select * into c from public.clinical_cases where id=(a->>'case_id')::uuid and clinic_id=d.clinic_id and patient_id=d.patient_id and responsible_id=d.responsible_id;
  if not found then raise exception 'attention_case_mismatch';end if;
  b=private.clinical_binding(c.id,a->>'scope');
  if not private.clinical_eligible(c,e.actor_id,a->>'scope',(e.payload->>'observed_at')::timestamptz) or b.id::text is distinct from e.payload->'context'->>'binding_id'
  or private.permission_effective(d.clinic_id,e.actor_id,'procedure.perform',b.procedure_id)::text is distinct from e.payload->'context'->>'permission_grant_id'
  or not exists(select 1 from private.member_permission_grants where id=(e.payload->'context'->>'permission_grant_id')::uuid and valid_until>clock_timestamp())
  or not exists(select 1 from public.person_procedure_authorizations x where x.id=(e.payload->>'case_authorization_id')::uuid and x.case_id=c.id and x.person_id=e.actor_id and x.scope_binding_id=b.id and x.member_since=e.member_since and x.valid_until>clock_timestamp() and not exists(select 1 from public.person_procedure_revocations where authorization_id=x.id)) then raise exception 'attention_case_authority_changed';end if;
 elsif a->>'scope' is distinct from 'consent_explanation' or nullif(a->>'case_id','') is not null then raise exception 'consent_is_not_procedure_attestation';end if;
 perform private.form_validate_signature(e.payload->'signature');
end$$;
-- Validate only measurements actually supplied. This does not require SOAP,
-- observations, weight or a temperature and never publishes a clinical act.
create function private.form_clinical_values(d public.form_documents) returns void language plpgsql stable security definer set search_path='' as $$
declare k text;n numeric;c public.clinical_cases;p uuid;scope text;begin
 if not coalesce((d.snapshot->>'clinical')::boolean,false) then return;end if;
 if not (d.snapshot->'schema'->'clauses') @> jsonb_build_array(jsonb_build_object('id','clinical_scope','text',private.form_attribution_clause())) then raise exception 'clinical_template_attribution_review_required';end if;
 select * into c from public.clinical_cases where id=(d.snapshot->'attention_assignment'->>'case_id')::uuid and clinic_id=d.clinic_id and patient_id=d.patient_id and responsible_id=d.responsible_id;
 if not found or (d.values->>'clinical_date')::date>current_date then raise exception 'matching_clinical_date_required';end if;
 foreach k in array array['weight','fc','fr','pulse','temperature','tllc','bp_systolic','bp_diastolic'] loop
  if nullif(d.values->>k,'') is not null then
   n=(d.values->>k)::numeric;
   if (k='weight' and n<=0) or (k<>'temperature' and n<0) then raise exception 'invalid_measurement';end if;
   if private.clinical_time(d.values->>'observed_at')>clock_timestamp() or private.clinical_time(d.values->>'observed_at')::date is distinct from (d.values->>'clinical_date')::date then raise exception 'measurement_time_required';end if;
  end if;
 end loop;
 foreach k in array array['surgeon_id','anesthetist_id'] loop
  if nullif(d.values->>k,'') is not null then
   p=(d.values->>k)::uuid;scope=case k when 'surgeon_id' then 'cirugia' else 'anestesia' end;
   if not private.clinical_eligible(c,p,scope,clock_timestamp()) then raise exception 'team_procedure_authority_required';end if;
  end if;
 end loop;
 if nullif(d.values->>'consent_id','') is not null and not exists(select 1 from public.form_documents x where x.id=(d.values->>'consent_id')::uuid and x.clinic_id=d.clinic_id and x.patient_id=d.patient_id and x.state='signed' and x.snapshot->'schema'->>'type'='surgery') then raise exception 'matching_signed_surgery_consent_required';end if;
end$$;
create function private.form_review_current(d public.form_documents,p_authorized boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare base public.form_documents=d;r private.form_flow_events;a private.form_flow_events;v private.form_flow_events;author jsonb;profile jsonb;begin
 base.state='draft';base.snapshot=private.form_base_snapshot(d);perform private.form_draft_current(base);perform private.form_clinical_values(d);
 select * into r from private.form_flow_events where id=(d.snapshot->>'flow_request_id')::uuid and document_id=d.id and kind='request';
 if not found or r.revision<>d.revision or r.content_hash<>private.form_draft_content(d) or r.actor_id<>d.created_by then raise exception 'exact_form_review_request_required';end if;
 author=private.form_authorship_for_draft(base,(r.payload->>'authorship_id')::uuid);
 select * into a from private.form_flow_events where id=(r.payload->>'attention_id')::uuid;
 if not found then raise exception 'attention_signature_required';end if;perform private.form_attention_current(d,a);
 select private.rx_profile(id) into profile from public.professional_profiles where clinic_id=d.clinic_id and user_id=d.responsible_id;
 if author->>'user_id'=a.actor_id::text and author->>'name' is distinct from a.payload->>'name' then raise exception 'same_person_name_mismatch';end if;
 if (author->>'user_id'=d.responsible_id::text and author->>'name' is distinct from profile->>'name') or (a.actor_id=d.responsible_id and a.payload->>'name' is distinct from profile->>'name') then raise exception 'responsible_name_mismatch';end if;
 if p_authorized then
  select * into v from private.form_flow_events where id=(d.snapshot->>'flow_authorization_id')::uuid and kind='authorization' and document_id=d.id;
  if not found or v.actor_id<>d.responsible_id or v.revision<>d.revision or v.content_hash<>r.content_hash or v.payload->>'request_id'<>r.id::text or private.permission_effective(d.clinic_id,v.actor_id,'form.authorize') is distinct from v.grant_id or not private.form_document_current(d.clinic_id,v.actor_id,'form.authorize') or v.payload->>'profile_version_id' is distinct from profile->>'id' or not exists(select 1 from public.clinic_members where clinic_id=d.clinic_id and user_id=v.actor_id and created_at=v.member_since) then raise exception 'form_authorization_changed';end if;
 end if;
 return jsonb_build_object('author',author,'attention',to_jsonb(a),'request',to_jsonb(r),'authorization',case when p_authorized then to_jsonb(v) end,'profile',profile-'signature');
end$$;
create function private.form_event(d public.form_documents,p_kind text,p_grant uuid,p_payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;begin
 insert into private.form_flow_events(clinic_id,document_id,revision,kind,content_hash,actor_id,grant_id,member_since,payload) values(d.clinic_id,d.id,d.revision,p_kind,private.form_draft_content(d),auth.uid(),p_grant,(select created_at from public.clinic_members where clinic_id=d.clinic_id and user_id=auth.uid()),p_payload) returning id into v_id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(d.clinic_id,auth.uid(),'form_'||p_kind||'_recorded',d.id,jsonb_build_object('event_id',v_id,'revision',d.revision,'content_hash',private.form_draft_content(d),'permission_grant_id',p_grant));return v_id;
end$$;
create function public.form_attention_select(p_id uuid,p_revision integer,p_actor uuid,p_case uuid,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;c public.clinical_cases;scope text;g uuid;fp jsonb;v_id uuid;begin
 d=private.form_flow_lock(p_id,false,p_actor,p_case);
 if d.created_by<>auth.uid() or not private.form_document_current(d.clinic_id,auth.uid(),'form.prepare') then raise exception 'draft_author_only';end if;
 fp=jsonb_build_object('kind','form_attention_selection','document',p_id,'revision',p_revision,'actor',p_actor,'case',p_case);v_id=private.vet_receipt(d.clinic_id,p_operation,fp);if v_id is not null then return private.form_document_safe(d);end if;
 if d.revision is distinct from p_revision then raise exception 'document_revision_conflict';end if;
 if d.state<>'draft' then raise exception 'draft_required';end if;perform private.form_draft_current(d);
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text,9061));
 if not private.form_document_current(d.clinic_id,p_actor,'form.prepare') or not private.form_document_current(d.clinic_id,p_actor,'clinical.read') or not private.form_document_current(d.clinic_id,p_actor,'patient.read') then raise exception 'attention_member_permissions_required';end if;
 scope='consent_explanation';
 if coalesce((d.snapshot->>'clinical')::boolean,false) then
  scope=case when d.snapshot->'schema'->>'type'='surgical_sheet' then 'cirugia' else 'evaluacion' end;
  select * into c from public.clinical_cases where id=p_case and clinic_id=d.clinic_id and patient_id=d.patient_id and responsible_id=d.responsible_id;
  if not found or not private.clinical_eligible(c,p_actor,scope,clock_timestamp()) then raise exception 'eligible_matching_case_required';end if;
 elsif p_case is not null then raise exception 'consent_is_not_procedure_attestation';end if;
 update public.form_documents set revision=revision+1,snapshot=private.form_base_snapshot(d)||jsonb_build_object('attention_assignment',jsonb_build_object('actor_id',p_actor,'case_id',p_case,'scope',scope,'prepare_grant_id',private.permission_effective(d.clinic_id,p_actor,'form.prepare'),'member_since',(select created_at from public.clinic_members where clinic_id=d.clinic_id and user_id=p_actor))) where id=p_id returning * into d;
 insert into private.vet_operation_receipts values(auth.uid(),d.clinic_id,p_operation,fp,d.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(d.clinic_id,auth.uid(),'form_attention_selected',d.id,jsonb_build_object('actor_id',p_actor,'case_id',p_case,'revision',d.revision,'no_clinical_act_created',true));return private.form_document_safe(d);
end$$;
create function public.form_attention_sign(p_id uuid,p_revision integer,p_name text,p_signature jsonb,p_observed text,p_confirmed boolean,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.form_documents;c public.clinical_cases;ctx jsonb;case_auth uuid;g uuid;fp jsonb;v_id uuid;t timestamptz;begin
 d=private.form_flow_lock(p_id);
 if d.snapshot->'attention_assignment'->>'actor_id' is distinct from auth.uid()::text then raise exception 'actual_attention_signer_only';end if;
 g=private.hospital_order_permission(d.clinic_id,'form.prepare',null,false);if d.revision is distinct from p_revision or d.state<>'draft' then raise exception 'document_revision_conflict';end if;
 perform private.form_draft_current(d);
 if p_confirmed is distinct from true then raise exception 'attention_confirmation_required';end if;
 if coalesce(length(btrim(p_name)),0) not between 1 and 200 or p_name~'[[:cntrl:]]' then raise exception 'attention_name_required';end if;
 perform private.form_validate_signature(p_signature);t=private.clinical_time(p_observed);
 if t>clock_timestamp() or not exists(select 1 from private.member_permission_grants where id=g and granted_at<=t and valid_until>t) then raise exception 'attention_time_not_covered';end if;
 if coalesce((d.snapshot->>'clinical')::boolean,false) then
  select * into c from public.clinical_cases where id=(d.snapshot->'attention_assignment'->>'case_id')::uuid and clinic_id=d.clinic_id and patient_id=d.patient_id and responsible_id=d.responsible_id;
  if not found or t::date<c.clinical_date then raise exception 'attention_case_mismatch';end if;
  ctx=private.clinical_permission_context(c,d.snapshot->'attention_assignment'->>'scope',auth.uid(),t);
  select x.id into case_auth from public.person_procedure_authorizations x where x.case_id=c.id and x.person_id=auth.uid() and x.scope=d.snapshot->'attention_assignment'->>'scope' and x.scope_binding_id=(ctx->>'binding_id')::uuid and x.authority_grant_id is not null and x.created_at<=t and x.valid_until>t and x.valid_until>clock_timestamp() and x.member_since=(select created_at from public.clinic_members where clinic_id=d.clinic_id and user_id=auth.uid()) and not exists(select 1 from public.person_procedure_revocations where authorization_id=x.id) order by x.created_at desc,x.id desc limit 1;
  if case_auth is null then raise exception 'case_authorization_required';end if;
 elsif d.snapshot->'attention_assignment'->>'scope' is distinct from 'consent_explanation' then raise exception 'consent_is_not_procedure_attestation';end if;
 fp=jsonb_build_object('kind','form_attention_signature','document',p_id,'revision',p_revision,'name',btrim(p_name),'signature',p_signature,'observed_at',p_observed);v_id=private.vet_receipt(d.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 v_id=private.form_event(d,'attention',g,jsonb_build_object('name',btrim(p_name),'signature',p_signature,'observed_at',p_observed,'context',ctx,'case_authorization_id',case_auth,'scope',d.snapshot->'attention_assignment'->>'scope'));
 insert into private.vet_operation_receipts values(auth.uid(),d.clinic_id,p_operation,fp,v_id);return v_id;
end$$;
create function public.form_review_submit(p_id uuid,p_revision integer,p_authorship uuid,p_attention uuid,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;base public.form_documents;r uuid;g uuid;fp jsonb;receipt uuid;a private.form_flow_events;author jsonb;begin
 d=private.form_flow_lock(p_id);if d.created_by<>auth.uid() then raise exception 'draft_author_only';end if;g=private.hospital_order_permission(d.clinic_id,'form.prepare',null,false);
 if d.revision is distinct from p_revision then raise exception 'document_revision_conflict';end if;
 fp=jsonb_build_object('kind','form_review_submit','document',p_id,'revision',p_revision,'authorship',p_authorship,'attention',p_attention);receipt=private.vet_receipt(d.clinic_id,p_operation,fp);if receipt is not null then perform private.form_review_current(d,d.state<>'awaiting_authorization');return private.form_document_safe(d);end if;
 if d.state<>'draft' then raise exception 'draft_required';end if;
 perform private.form_validate_values(d.snapshot->'schema',d.values,true);author=private.form_authorship_for_draft(d,p_authorship);
 select * into a from private.form_flow_events where id=p_attention;if not found then raise exception 'attention_signature_required';end if;perform private.form_attention_current(d,a);
 r=private.form_event(d,'request',g,jsonb_build_object('authorship_id',p_authorship,'attention_id',p_attention));
 update public.form_documents set state='awaiting_authorization',snapshot=snapshot||jsonb_build_object('flow_request_id',r) where id=p_id returning * into d;
 perform private.form_review_current(d,false);
 insert into private.vet_operation_receipts values(auth.uid(),d.clinic_id,p_operation,fp,r);return private.form_document_safe(d);
end$$;
create function private.form_freeze_snapshot(d public.form_documents,p_preview boolean) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ctx jsonb;identity jsonb;t private.form_flow_events;v private.form_flow_events;s jsonb;begin
 ctx=private.form_review_current(d,true);
 identity=jsonb_build_object('author',ctx->'author','attention',jsonb_build_object('user_id',ctx->'attention'->>'actor_id','name',ctx->'attention'->'payload'->>'name','signature',ctx->'attention'->'payload'->'signature','scope',ctx->'attention'->'payload'->>'scope','case_id',d.snapshot->'attention_assignment'->'case_id','observed_at',ctx->'attention'->'payload'->>'observed_at','event_id',ctx->'attention'->>'id'),
 'responsible',jsonb_build_object('user_id',d.responsible_id,'name',ctx->'profile'->>'name','license',ctx->'profile'->>'license','profile_version_id',ctx->'profile'->>'id'),
 'authorization',jsonb_build_object('mode','individual','actor_id',d.responsible_id,'reference_id',ctx->'authorization'->>'id','authorized_at',ctx->'authorization'->>'created_at','request_hash',ctx->'request'->>'content_hash'),'tutor',null);
 if not p_preview and not coalesce((d.snapshot->>'clinical')::boolean,false) then
  select * into t from private.form_flow_events where id=(d.snapshot->>'flow_tutor_id')::uuid and kind='tutor' and document_id=d.id;
  if not found or t.revision<>d.revision or t.content_hash<>private.form_draft_content(d) or (t.payload->>'authorization_id') is distinct from (ctx->'authorization'->>'id') or t.payload->>'name' is distinct from d.values->>'signer_name' or t.payload->>'identification_number' is distinct from d.values->>'signer_id' then raise exception 'exact_tutor_acceptance_required';end if;
  if private.permission_effective(d.clinic_id,t.actor_id,'form.prepare') is distinct from t.grant_id or not private.form_document_current(d.clinic_id,t.actor_id,'form.prepare') or not exists(select 1 from public.clinic_members where clinic_id=d.clinic_id and user_id=t.actor_id and created_at=t.member_since) then raise exception 'tutor_capture_authority_changed';end if;
  perform private.form_validate_signature(t.payload->'signature');
  identity=jsonb_set(identity,'{tutor}',jsonb_build_object('name',t.payload->>'name','identification_number',t.payload->>'identification_number','signature',t.payload->'signature','captured_by',t.actor_id,'captured_at',t.created_at,'preview_hash',t.payload->>'preview_hash','reference_id',t.id));
 end if;
 s=private.form_base_snapshot(d)||jsonb_build_object('flow_request_id',d.snapshot->>'flow_request_id','flow_authorization_id',d.snapshot->>'flow_authorization_id','flow_tutor_id',d.snapshot->>'flow_tutor_id','document_id',d.id,'values',d.values,'branding',d.branding,'prepared_at',case when t.id is null then ctx->'authorization'->>'created_at' else to_jsonb(t.created_at)#>>'{}' end,'form_identity_version',1,'form_identity',identity,'form_preview',p_preview,'staff_labels',coalesce((select jsonb_object_agg(p.user_id::text,private.rx_profile(p.id)->>'name') from public.professional_profiles p where p.clinic_id=d.clinic_id and p.user_id::text in (d.values->>'surgeon_id',d.values->>'anesthetist_id')),'{}'));
 return s;
end$$;
create function public.form_authorize_individual(p_id uuid,p_revision integer,p_confirmed boolean,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;ctx jsonb;g uuid;v_id uuid;fp jsonb;s jsonb;begin
 d=private.form_flow_lock(p_id);if d.responsible_id<>auth.uid() then raise exception 'selected_responsible_only';end if;
 g=private.hospital_order_permission(d.clinic_id,'form.authorize',null,true);if d.revision is distinct from p_revision then raise exception 'document_revision_conflict';end if;
 if p_confirmed is distinct from true then raise exception 'individual_form_review_required';end if;
 ctx=private.form_review_current(d,false);
 fp=jsonb_build_object('kind','form_individual_authorization','document',p_id,'revision',p_revision,'request',ctx->'request'->>'id','confirmed',true);v_id=private.vet_receipt(d.clinic_id,p_operation,fp);if v_id is not null then perform private.form_review_current(d,true);return private.form_document_safe(d);end if;
 if d.state<>'awaiting_authorization' then raise exception 'form_awaiting_authorization_required';end if;
 v_id=private.form_event(d,'authorization',g,jsonb_build_object('request_id',ctx->'request'->>'id','profile_version_id',ctx->'profile'->>'id','act','individual_content_review','signature_borrowed',false));
 d.snapshot=d.snapshot||jsonb_build_object('flow_authorization_id',v_id);
 if coalesce((d.snapshot->>'clinical')::boolean,false) then
  s=private.form_freeze_snapshot(d,false);
  update public.form_documents set state='awaiting_review',snapshot=s,prepared_at=clock_timestamp(),content_hash=encode(sha256(convert_to(s::text,'UTF8')),'hex') where id=p_id returning * into d;
 else
  update public.form_documents set state='awaiting_tutor',snapshot=d.snapshot where id=p_id returning * into d;
 end if;
 insert into private.vet_operation_receipts values(auth.uid(),d.clinic_id,p_operation,fp,v_id);return private.form_document_safe(d);
end$$;
create function public.form_document_preview_snapshot(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.form_documents;s jsonb;begin
 select * into d from public.form_documents where id=p_id;
 if not found or not private.form_readable(d) or d.state<>'awaiting_tutor' then raise exception 'tutor_preview_access_required';end if;
 s=private.form_freeze_snapshot(d,true);
 return jsonb_build_object('id',d.id,'clinic_id',d.clinic_id,'state',d.state,'revision',d.revision,'snapshot',s,'content_hash',encode(sha256(convert_to(s::text,'UTF8')),'hex'));
end$$;
create function public.form_preview_read(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s jsonb;a private.form_flow_artifacts;begin
 s=public.form_document_preview_snapshot(p_id);
 select * into a from private.form_flow_artifacts where document_id=p_id and revision=(s->>'revision')::integer and kind='preview' and content_hash=s->>'content_hash' and encode(sha256(pdf),'hex')=pdf_hash;
 if not found then return null;end if;return jsonb_build_object('pdf',encode(a.pdf,'base64'),'hash',a.pdf_hash);
end$$;
create function public.form_preview_register(p_id uuid,p_revision integer,p_content_hash text,p_pdf text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;s jsonb;bytes bytea;a private.form_flow_artifacts;begin
 d=private.form_flow_lock(p_id,true);
 if d.revision is distinct from p_revision or d.state<>'awaiting_tutor' then raise exception 'preview_revision_conflict';end if;
 s=private.form_freeze_snapshot(d,true);
 if encode(sha256(convert_to(s::text,'UTF8')),'hex') is distinct from p_content_hash then raise exception 'preview_content_conflict';end if;
 if p_pdf is null or length(p_pdf)>2800000 then raise exception 'invalid_preview_pdf';end if;bytes=decode(p_pdf,'base64');
 if octet_length(bytes) not between 5 and 2097152 or substring(bytes from 1 for 5)<>convert_to('%PDF-','UTF8') then raise exception 'invalid_preview_pdf';end if;
 insert into private.form_flow_artifacts(document_id,revision,kind,content_hash,pdf,pdf_hash) values(d.id,d.revision,'preview',p_content_hash,bytes,encode(sha256(bytes),'hex')) on conflict do nothing;
 select * into a from private.form_flow_artifacts where document_id=d.id and revision=d.revision and kind='preview';
 if a.content_hash<>p_content_hash then raise exception 'preview_content_conflict';end if;return jsonb_build_object('pdf',encode(a.pdf,'base64'),'hash',a.pdf_hash);
end$$;
create function public.form_tutor_capture(p_id uuid,p_revision integer,p_preview_hash text,p_signature jsonb,p_confirmed boolean,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;g uuid;fp jsonb;v_id uuid;ctx jsonb;preview jsonb;s jsonb;begin
 d=private.form_flow_lock(p_id);
 if auth.uid()<>d.created_by and (d.snapshot->'attention_assignment'->>'actor_id') is distinct from auth.uid()::text then raise exception 'tutor_capture_member_required';end if;
 g=private.hospital_order_permission(d.clinic_id,'form.prepare',null,false);if d.revision is distinct from p_revision then raise exception 'document_revision_conflict';end if;
 if p_confirmed is distinct from true then raise exception 'real_tutor_review_and_signature_required';end if;
 ctx=private.form_review_current(d,true);perform private.form_validate_signature(p_signature);
 fp=jsonb_build_object('kind','real_tutor_signature','document',p_id,'revision',p_revision,'preview_hash',p_preview_hash,'signature',p_signature,'confirmed',true);v_id=private.vet_receipt(d.clinic_id,p_operation,fp);if v_id is not null then perform private.form_freeze_snapshot(d,false);return private.form_document_safe(d);end if;
 if d.state<>'awaiting_tutor' or coalesce((d.snapshot->>'clinical')::boolean,false) then raise exception 'consent_awaiting_tutor_required';end if;
 preview=public.form_preview_read(p_id);if preview is null or preview->>'hash' is distinct from p_preview_hash then raise exception 'reviewed_tutor_preview_required';end if;
 v_id=private.form_event(d,'tutor',g,jsonb_build_object('authorization_id',ctx->'authorization'->>'id','name',d.values->>'signer_name','identification_number',d.values->>'signer_id','signature',p_signature,'preview_hash',p_preview_hash,'act','tutor_signature_captured_in_person','not_delegated',true));
 d.snapshot=d.snapshot||jsonb_build_object('flow_tutor_id',v_id);s=private.form_freeze_snapshot(d,false);
 update public.form_documents set state='awaiting_review',snapshot=s,prepared_at=clock_timestamp(),content_hash=encode(sha256(convert_to(s::text,'UTF8')),'hex') where id=p_id returning * into d;
 insert into private.vet_operation_receipts values(auth.uid(),d.clinic_id,p_operation,fp,v_id);return private.form_document_safe(d);
end$$;
-- Preserve historical artifacts and expose signed scope without raw vectors.
create or replace function public.form_document_snapshot(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.form_documents;s jsonb;begin
 select * into d from public.form_documents where id=p_id;
 if not found or not private.form_readable(d) then raise exception 'document_access_denied';end if;
 if d.state='signed' then return private.form_document_safe(d);end if;
 if d.state not in ('awaiting_review','ready') then raise exception 'authorized_form_snapshot_required';end if;
 s=private.form_freeze_snapshot(d,false);
 if s is distinct from d.snapshot or encode(sha256(convert_to(s::text,'UTF8')),'hex') is distinct from d.content_hash then raise exception 'form_snapshot_changed';end if;
 return to_jsonb(d);
end$$;
create or replace function public.form_read_pdf(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.form_documents;a private.form_flow_artifacts;old private.form_artifacts;s jsonb;begin
 s=public.form_document_snapshot(p_id);select * into d from public.form_documents where id=p_id;
 select * into a from private.form_flow_artifacts where document_id=d.id and revision=d.revision and kind='final' and content_hash=d.content_hash and pdf_hash=d.pdf_hash and encode(sha256(pdf),'hex')=pdf_hash;
 if found then return jsonb_build_object('pdf',encode(a.pdf,'base64'),'hash',a.pdf_hash);end if;
 if d.state='awaiting_review' then return null;end if;
 if d.state='signed' then
  select * into old from private.form_artifacts where document_id=d.id and revision=d.revision and content_hash=d.content_hash and pdf_hash=d.pdf_hash and encode(sha256(pdf),'hex')=pdf_hash;
  if found then return jsonb_build_object('pdf',encode(old.pdf,'base64'),'hash',old.pdf_hash);end if;
 end if;raise exception 'reviewed_pdf_required';
end$$;
create or replace function public.form_register_pdf(p_id uuid,p_revision integer,p_content_hash text,p_pdf text,p_tutor_png text,p_mvz_png text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;s jsonb;a private.form_flow_artifacts;bytes bytea;begin
 d=private.form_flow_lock(p_id,true);
 if d.state not in ('awaiting_review','ready') or d.revision is distinct from p_revision then raise exception 'pdf_revision_conflict';end if;
 s=private.form_freeze_snapshot(d,false);
 if d.snapshot is distinct from s or d.content_hash is distinct from p_content_hash or encode(sha256(convert_to(s::text,'UTF8')),'hex')<>p_content_hash then raise exception 'form_snapshot_changed';end if;
 if p_pdf is null or length(p_pdf)>2800000 or p_mvz_png is null or length(p_mvz_png)>300000 then raise exception 'invalid_form_artifact';end if;
 bytes=decode(p_pdf,'base64');if octet_length(bytes) not between 5 and 2097152 or substring(bytes from 1 for 5)<>convert_to('%PDF-','UTF8') or substring(decode(p_mvz_png,'base64') from 1 for 8)<>decode('89504e470d0a1a0a','hex') then raise exception 'invalid_form_artifact';end if;
 if not coalesce((d.snapshot->>'clinical')::boolean,false) and (p_tutor_png is null or length(p_tutor_png)>300000 or substring(decode(p_tutor_png,'base64') from 1 for 8)<>decode('89504e470d0a1a0a','hex')) then raise exception 'tutor_signature_image_required';end if;
 insert into private.form_flow_artifacts(document_id,revision,kind,content_hash,pdf,pdf_hash) values(d.id,d.revision,'final',d.content_hash,bytes,encode(sha256(bytes),'hex')) on conflict do nothing;
 select * into a from private.form_flow_artifacts where document_id=d.id and revision=d.revision and kind='final';if a.content_hash<>d.content_hash then raise exception 'pdf_revision_conflict';end if;
 update public.form_documents set state='ready',pdf_hash=a.pdf_hash where id=d.id;
 return jsonb_build_object('pdf',encode(a.pdf,'base64'),'hash',a.pdf_hash);
end$$;
create or replace function public.form_document_finalize(p_id uuid,p_revision integer,p_pdf_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;g uuid;s jsonb;v_id uuid;begin
 d=private.form_flow_lock(p_id);g=private.hospital_order_permission(d.clinic_id,'form.issue',null,false);
 if auth.uid()<>d.created_by and auth.uid()<>d.responsible_id and (d.snapshot->'attention_assignment'->>'actor_id') is distinct from auth.uid()::text then raise exception 'document_issuer_relation_required';end if;
 if d.revision is distinct from p_revision or p_pdf_hash is null or d.pdf_hash is distinct from p_pdf_hash then raise exception 'reviewed_pdf_mismatch';end if;
 if d.state='signed' then return private.form_document_safe(d);end if;
 if d.state<>'ready' then raise exception 'reviewed_pdf_required';end if;
 s=private.form_freeze_snapshot(d,false);if s is distinct from d.snapshot then raise exception 'form_snapshot_changed';end if;
 if not exists(select 1 from private.form_flow_artifacts where document_id=d.id and revision=d.revision and kind='final' and content_hash=d.content_hash and pdf_hash=p_pdf_hash and encode(sha256(pdf),'hex')=p_pdf_hash) then raise exception 'reviewed_pdf_required';end if;
 v_id=private.form_event(d,'issuance',g,jsonb_build_object('pdf_hash',p_pdf_hash,'snapshot_hash',d.content_hash,'authorization_id',d.snapshot->>'flow_authorization_id','actual_attention_actor_id',d.snapshot->'attention_assignment'->>'actor_id'));
 update public.form_documents set state='signed',accepted_at=clock_timestamp() where id=d.id returning * into d;
 return private.form_document_safe(d);
end$$;
create function public.form_document_reopen(p_id uuid,p_revision integer,p_responsible uuid,p_reason text,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;g uuid;profile jsonb;s jsonb;fp jsonb;receipt uuid;begin
 d=private.form_flow_lock(p_id,false,p_responsible);
 if d.created_by<>auth.uid() then raise exception 'draft_author_only';end if;g=private.hospital_order_permission(d.clinic_id,'form.prepare',null,false);
 if coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'form_correction_reason_required';end if;
 if d.state='signed' then raise exception 'signed_document_is_immutable';end if;
 if not private.clinical_professional_at(d.clinic_id,p_responsible,clock_timestamp()) or not private.form_document_current(d.clinic_id,p_responsible,'form.authorize') or not private.form_document_current(d.clinic_id,p_responsible,'patient.read') or not private.form_document_current(d.clinic_id,p_responsible,'clinical.read') then raise exception 'explicit_verified_responsible_required';end if;
 select private.rx_profile(id) into profile from public.professional_profiles where clinic_id=d.clinic_id and user_id=p_responsible;
 fp=jsonb_build_object('kind','form_reopen','document',p_id,'revision',p_revision,'responsible',p_responsible,'reason',p_reason);receipt=private.vet_receipt(d.clinic_id,p_operation,fp);if receipt is not null then return private.form_document_safe(d);end if;
 if d.revision is distinct from p_revision then raise exception 'document_revision_conflict';end if;
 s=private.form_base_snapshot(d)-'attention_assignment';
 s=s||jsonb_build_object('responsible_id',p_responsible,'draft_authority',jsonb_build_object('prepare_grant_id',g,'author_member_since',(select created_at from public.clinic_members where clinic_id=d.clinic_id and user_id=auth.uid()),'responsible_member_since',(select created_at from public.clinic_members where clinic_id=d.clinic_id and user_id=p_responsible),'responsible_profile_version_id',profile->>'id','responsible_selection_grant_id',private.permission_effective(d.clinic_id,p_responsible,'form.authorize')));
 update public.form_documents set state='draft',revision=revision+1,responsible_id=p_responsible,values=values||jsonb_build_object('mvz_name',profile->>'name','mvz_license',profile->>'license'),snapshot=s,prepared_at=null,content_hash=null,pdf_hash=null,accepted_at=null where id=d.id returning * into d;
 insert into private.vet_operation_receipts values(auth.uid(),d.clinic_id,p_operation,fp,d.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(d.clinic_id,auth.uid(),'form_reopened_for_correction',d.id,jsonb_build_object('reason',p_reason,'revision',d.revision,'all_prior_signatures_invalidated',true));return private.form_document_safe(d);
end$$;
create function private.form_flow_capable(d public.form_documents,p_action text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare base public.form_documents=d;v private.form_flow_events;author_id uuid;attention_id uuid;c public.clinical_cases;begin
 if not private.form_readable(d) then return false;end if;
 if p_action='reopen' then return d.state<>'signed' and d.created_by=auth.uid() and private.form_document_current(d.clinic_id,auth.uid(),'form.prepare');end if;
 if p_action='reject' then return d.state in ('awaiting_authorization','awaiting_tutor','awaiting_review','ready') and d.responsible_id=auth.uid() and private.form_document_current(d.clinic_id,auth.uid(),'form.authorize') and private.clinical_professional_at(d.clinic_id,auth.uid(),clock_timestamp());end if;
 base.state='draft';base.snapshot=private.form_base_snapshot(d);perform private.form_draft_current(base);
 if p_action in ('edit','select') then return d.state='draft' and d.created_by=auth.uid();end if;
 if p_action='sign_attention' then
  if d.state<>'draft' or d.snapshot->'attention_assignment'->>'actor_id' is distinct from auth.uid()::text or not private.form_document_current(d.clinic_id,auth.uid(),'form.prepare') or private.permission_effective(d.clinic_id,auth.uid(),'form.prepare')::text is distinct from d.snapshot->'attention_assignment'->>'prepare_grant_id' then return false;end if;
  if coalesce((d.snapshot->>'clinical')::boolean,false) then select * into c from public.clinical_cases where id=(d.snapshot->'attention_assignment'->>'case_id')::uuid and patient_id=d.patient_id and clinic_id=d.clinic_id and responsible_id=d.responsible_id;return found and private.clinical_eligible(c,auth.uid(),d.snapshot->'attention_assignment'->>'scope',clock_timestamp());end if;
  return d.snapshot->'attention_assignment'->>'scope'='consent_explanation';
 end if;
 if p_action='submit' then
  if d.state<>'draft' or d.created_by<>auth.uid() then return false;end if;
  perform private.form_validate_values(d.snapshot->'schema',d.values,true);
  select id into author_id from private.form_authorship_attestations where document_id=d.id and draft_revision=d.revision and content_hash=private.form_draft_content(d) order by signed_at desc,id desc limit 1;
  if author_id is null then return false;end if;perform private.form_authorship_for_draft(base,author_id);
  select * into v from private.form_flow_events where document_id=d.id and revision=d.revision and content_hash=private.form_draft_content(d) and kind='attention' order by created_at desc,id desc limit 1;
  if not found then return false;end if;perform private.form_attention_current(d,v);return true;
 end if;
 if p_action='authorize' then
  perform private.form_review_current(d,false);return d.state='awaiting_authorization' and d.responsible_id=auth.uid() and private.form_document_current(d.clinic_id,auth.uid(),'form.authorize');
 end if;
 perform private.form_review_current(d,true);
 if p_action='preview' then return d.state='awaiting_tutor';end if;
 if p_action='capture_tutor' then return d.state='awaiting_tutor' and private.form_document_current(d.clinic_id,auth.uid(),'form.prepare') and (d.created_by=auth.uid() or d.snapshot->'attention_assignment'->>'actor_id'=auth.uid()::text);end if;
 if p_action='view_pdf' then return d.state in ('awaiting_review','ready');end if;
 if p_action='issue' then return d.state in ('awaiting_review','ready') and private.form_document_current(d.clinic_id,auth.uid(),'form.issue');end if;
 return false;
exception when others then return false;
end$$;
create function private.form_field_choices(d public.form_documents) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.clinical_cases;result jsonb='{}';k text;scope text;begin
 if not coalesce((d.snapshot->>'clinical')::boolean,false) then return result;end if;
 select * into c from public.clinical_cases where id=(d.snapshot->'attention_assignment'->>'case_id')::uuid and clinic_id=d.clinic_id and patient_id=d.patient_id and responsible_id=d.responsible_id;
 if not found then return result;end if;
 foreach k in array array['surgeon_id','anesthetist_id'] loop
  scope=case k when 'surgeon_id' then 'cirugia' else 'anestesia' end;
  result=result||jsonb_build_object(k,coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'label',private.rx_profile(p.id)->>'name') order by m.user_id) from public.clinic_members m join public.professional_profiles p on p.clinic_id=m.clinic_id and p.user_id=m.user_id where m.clinic_id=d.clinic_id and private.clinical_eligible(c,m.user_id,scope,clock_timestamp())),'[]'));
 end loop;
 result=result||jsonb_build_object('consent_id',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'label',x.snapshot->'schema'->>'title') order by x.created_at desc) from public.form_documents x where x.clinic_id=d.clinic_id and x.patient_id=d.patient_id and x.state='signed' and x.snapshot->'schema'->>'type'='surgery' and private.form_readable(x)),'[]'));
 return result;
end$$;
revoke all on function private.form_field_choices(public.form_documents) from public,anon,authenticated,service_role;
create function public.form_document_flow(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.form_documents;actions jsonb;author jsonb;attention jsonb;begin
 select * into d from public.form_documents where id=p_id;
 if not found or not private.form_readable(d) then raise exception 'document_access_denied';end if;
 select jsonb_object_agg(k,private.form_flow_capable(d,k)) into actions from unnest(array['edit','select','sign_attention','submit','authorize','preview','capture_tutor','view_pdf','issue','reopen','reject']) k;
 select jsonb_build_object('id',id,'name',signer_name,'user_id',signer_id,'signed_at',signed_at) into author from private.form_authorship_attestations where document_id=d.id and draft_revision=d.revision and content_hash=private.form_draft_content(d) order by signed_at desc,id desc limit 1;
 select jsonb_build_object('id',id,'name',payload->>'name','user_id',actor_id,'observed_at',payload->>'observed_at','scope',payload->>'scope') into attention from private.form_flow_events where document_id=d.id and revision=d.revision and content_hash=private.form_draft_content(d) and kind='attention' order by created_at desc,id desc limit 1;
 return jsonb_build_object('schema_version',1,'mode','individual_forms','document',private.form_document_safe(d),'actions',actions,'authorship',author,'attention',attention,'assignment',d.snapshot->'attention_assignment','field_choices',private.form_field_choices(d),
 'people',case when actions->>'select'='true' then coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'name',coalesce(private.rx_profile(p.id)->>'name','Miembro '||left(m.user_id::text,8))) order by m.user_id) from public.clinic_members m left join public.professional_profiles p on p.clinic_id=m.clinic_id and p.user_id=m.user_id where m.clinic_id=d.clinic_id and private.form_document_current(m.clinic_id,m.user_id,'form.prepare') and private.form_document_current(m.clinic_id,m.user_id,'clinical.read') and private.form_document_current(m.clinic_id,m.user_id,'patient.read')),'[]') else '[]'::jsonb end,
 'cases',case when actions->>'select'='true' and coalesce((d.snapshot->>'clinical')::boolean,false) then coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'title',c.title,'clinical_date',c.clinical_date) order by c.created_at desc) from public.clinical_cases c where c.clinic_id=d.clinic_id and c.patient_id=d.patient_id and c.responsible_id=d.responsible_id and private.clinical_readable(c)),'[]') else '[]'::jsonb end,
 'responsibles',public.form_document_workspace(d.clinic_id)->'responsibles');
end$$;
create function public.form_review_reject(p_id uuid,p_revision integer,p_reason text,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;g uuid;fp jsonb;receipt uuid;begin
 d=private.form_flow_lock(p_id);if d.responsible_id<>auth.uid() then raise exception 'selected_responsible_only';end if;
 g=private.hospital_order_permission(d.clinic_id,'form.authorize',null,true);
 if coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'form_correction_reason_required';end if;
 fp=jsonb_build_object('kind','form_review_reject','document',p_id,'revision',p_revision,'reason',p_reason);receipt=private.vet_receipt(d.clinic_id,p_operation,fp);if receipt is not null then return private.form_document_safe(d);end if;
 if d.revision is distinct from p_revision then raise exception 'document_revision_conflict';end if;
 if d.state not in ('awaiting_authorization','awaiting_tutor','awaiting_review','ready') then raise exception 'unissued_form_review_required';end if;
 update public.form_documents set state='draft',revision=revision+1,snapshot=private.form_base_snapshot(d),prepared_at=null,content_hash=null,pdf_hash=null where id=d.id returning * into d;
 insert into private.vet_operation_receipts values(auth.uid(),d.clinic_id,p_operation,fp,d.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(d.clinic_id,auth.uid(),'form_returned_for_correction',d.id,jsonb_build_object('reason',p_reason,'revision',d.revision,'grant_id',g));return private.form_document_safe(d);
end$$;
-- Retain the old implementation privately; the public contract explicitly
-- announces the new flow version. Older clients must fail closed.
alter function public.form_document_workspace(uuid) set schema private;
alter function private.form_document_workspace(uuid) rename to form_document_workspace_drafts;
revoke all on function private.form_document_workspace_drafts(uuid) from public,anon,authenticated,service_role;
create function public.form_document_workspace(p_clinic uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select w||jsonb_build_object('mode','individual_forms','flow_version',1,'approved_template_ids',coalesce((select jsonb_agg(v.id order by v.id) from public.form_template_versions v where (w->'approved_template_ids') ? v.id::text and (v.schema->>'type' not in ('clinical_history','surgical_sheet','surgical_risk') or (v.schema->'clauses') @> jsonb_build_array(jsonb_build_object('id','clinical_scope','text',private.form_attribution_clause())))),'[]')) from (select private.form_document_workspace_drafts(p_clinic) w) q;
$$;
-- Close the general legacy prepare/profile/assign routes. New RPCs use explicit
-- attestations; issuance never calls the old automatic clinical publisher.
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in ('form_clinical_values','form_base_snapshot','form_flow_lock','form_attention_current','form_review_current','form_event','form_freeze_snapshot','form_flow_capable') loop execute 'revoke all on function '||f.signature||' from public,anon,authenticated,service_role';end loop;
end$$;
revoke all on function public.form_document_workspace(uuid),public.form_attention_select(uuid,integer,uuid,uuid,text),public.form_attention_sign(uuid,integer,text,jsonb,text,boolean,text),public.form_review_submit(uuid,integer,uuid,uuid,text),public.form_authorize_individual(uuid,integer,boolean,text),public.form_document_preview_snapshot(uuid),public.form_preview_read(uuid),public.form_tutor_capture(uuid,integer,text,jsonb,boolean,text),public.form_document_flow(uuid),public.form_document_reopen(uuid,integer,uuid,text,text),public.form_review_reject(uuid,integer,text,text) from public,anon,authenticated;
grant execute on function public.form_document_workspace(uuid),public.form_attention_select(uuid,integer,uuid,uuid,text),public.form_attention_sign(uuid,integer,text,jsonb,text,boolean,text),public.form_review_submit(uuid,integer,uuid,uuid,text),public.form_authorize_individual(uuid,integer,boolean,text),public.form_document_preview_snapshot(uuid),public.form_preview_read(uuid),public.form_tutor_capture(uuid,integer,text,jsonb,boolean,text),public.form_document_flow(uuid),public.form_document_reopen(uuid,integer,uuid,text,text),public.form_review_reject(uuid,integer,text,text) to authenticated;
revoke all on function public.form_preview_register(uuid,integer,text,text),public.form_register_pdf(uuid,integer,text,text,text,text) from public,anon,authenticated;
grant execute on function public.form_preview_register(uuid,integer,text,text),public.form_register_pdf(uuid,integer,text,text,text,text) to service_role;
commit;
