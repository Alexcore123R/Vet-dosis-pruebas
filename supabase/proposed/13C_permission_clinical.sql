-- LOCAL CANDIDATE 2B-3. Requires schema review and coordinated cutover before deployment.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
insert into private.permission_catalog(code,label,procedure_scoped,requires_professional) values
 ('clinical.read','Consultar expediente clínico',false,false),
 ('clinical.authorize','Configurar y autorizar actuaciones del caso',false,true);
create table private.clinical_scope_bindings (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,case_id uuid not null,
 scope text not null check(scope in ('observaciones','evaluacion','cirugia','anestesia','recuperacion','cuidados')),
 procedure_id uuid not null,professional_required boolean not null default true,
 source text not null check(length(btrim(source)) between 1 and 1000),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,case_id) references public.clinical_cases(clinic_id,id),
 foreign key(clinic_id,procedure_id) references private.procedure_types(clinic_id,id),
 check(scope='observaciones' or professional_required)
);
create table private.clinical_scope_revocations (
 binding_id uuid primary key references private.clinical_scope_bindings(id),
 revoked_by uuid not null references auth.users(id),revoked_at timestamptz not null default clock_timestamp(),
 reason text not null check(length(btrim(reason)) between 1 and 1000)
);
-- Historical case authorizations remain readable history, not new-model authority.
alter table public.person_procedure_authorizations
 add column authority_grant_id uuid references private.member_permission_grants(id),
 add column scope_binding_id uuid references private.clinical_scope_bindings(id);
do $$declare t text;begin
 foreach t in array array['clinical_scope_bindings','clinical_scope_revocations'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated',t);
 execute format('create trigger permission_immutable before update or delete on private.%I for each row execute function private.permission_immutable()',t);
 end loop;
end$$;
create function private.clinical_professional_at(p_clinic uuid,p_user uuid,p_at timestamptz) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.clinic_members m where m.clinic_id=p_clinic and m.user_id=p_user)
 and exists(select 1 from private.professional_verifications v
 join private.professional_profile_versions reviewed on reviewed.id=v.profile_version_id
 join public.professional_profiles rp on rp.id=reviewed.profile_id and rp.user_id=v.user_id
 join public.professional_profiles current_profile on current_profile.clinic_id=p_clinic and current_profile.user_id=v.user_id
 join lateral (select cv.* from private.professional_profile_versions cv where cv.profile_id=current_profile.id order by cv.version desc limit 1) current_v on true
 where v.user_id=p_user and (v.clinic_id is null or v.clinic_id=p_clinic)
 and v.valid_until>p_at and v.reviewed_at<=p_at
 and length(btrim(current_v.license))>0 and current_v.license=reviewed.license and current_v.name=reviewed.name
 and not exists(select 1 from private.professional_revocations r where r.verification_id=v.id));
$$;
create function private.clinical_identity_lock() returns trigger language plpgsql security definer set search_path='' as $$
declare person uuid;begin
 if tg_table_name='professional_verifications' then person=new.user_id;
 elsif tg_table_name='professional_revocations' then select user_id into person from private.professional_verifications where id=new.verification_id;
 else select user_id into person from public.professional_profiles where id=new.profile_id;end if;
 if person is null then raise exception 'professional_identity_required';end if;
 perform pg_advisory_xact_lock(hashtextextended(person::text,9061));return new;
end$$;
create trigger clinical_identity_lock before insert on private.professional_verifications for each row execute function private.clinical_identity_lock();
create trigger clinical_identity_lock before insert on private.professional_revocations for each row execute function private.clinical_identity_lock();
create trigger clinical_identity_lock before insert on private.professional_profile_versions for each row execute function private.clinical_identity_lock();
create or replace function private.clinical_readable(c public.clinical_cases) returns boolean language sql stable security definer set search_path='' as $$
 select private.permission_effective(c.clinic_id,auth.uid(),'clinical.read') is not null
 and private.permission_effective(c.clinic_id,auth.uid(),'patient.read') is not null
 and exists(select 1 from private.member_permission_grants g where g.id=private.permission_effective(c.clinic_id,auth.uid(),'clinical.read') and g.valid_until>clock_timestamp())
 and exists(select 1 from private.member_permission_grants g where g.id=private.permission_effective(c.clinic_id,auth.uid(),'patient.read') and g.valid_until>clock_timestamp());
$$;
create function private.clinical_binding(p_case uuid,p_scope text) returns private.clinical_scope_bindings language sql stable security definer set search_path='' as $$
 select b from private.clinical_scope_bindings b where case_id=p_case and scope=p_scope
 and not exists(select 1 from private.clinical_scope_revocations r where r.binding_id=b.id)
 order by created_at desc,id desc limit 1;
$$;
create function private.clinical_permission_context(c public.clinical_cases,p_scope text,p_person uuid,p_observed timestamptz) returns jsonb language plpgsql security definer set search_path='' as $$
declare b private.clinical_scope_bindings;g uuid;begin
 perform pg_advisory_xact_lock(hashtextextended(p_person::text,9061));
 b=private.clinical_binding(c.id,p_scope);
 if b.id is null then raise exception 'clinical_scope_mapping_required';end if;
 g=private.permission_effective(c.clinic_id,p_person,'procedure.perform',b.procedure_id);
 if g is null or not exists(select 1 from private.member_permission_grants where member_permission_grants.id=g and granted_at<=p_observed and valid_until>clock_timestamp() and valid_until>p_observed)
 or b.created_at>p_observed then raise exception 'explicit_procedure_permission_required';end if;
 if b.professional_required and not (private.clinical_professional_at(c.clinic_id,p_person,clock_timestamp()) and private.clinical_professional_at(c.clinic_id,p_person,p_observed)) then raise exception 'verified_professional_required';end if;
 if not exists(select 1 from public.person_procedure_authorizations a where a.case_id=c.id and a.clinic_id=c.clinic_id and a.person_id=p_person and a.scope=p_scope and a.scope_binding_id=b.id and a.authority_grant_id is not null
 and a.created_at<=p_observed and a.valid_until>p_observed and a.valid_until>clock_timestamp()
 and not exists(select 1 from public.person_procedure_revocations r where r.authorization_id=a.id)) then raise exception 'case_authorization_required';end if;
 return jsonb_build_object('binding_id',b.id,'procedure_id',b.procedure_id,'permission_grant_id',g);
end$$;
create or replace function private.clinical_eligible(c public.clinical_cases,person uuid,scope text,at_time timestamptz) returns boolean language plpgsql stable security definer set search_path='' as $$
declare b private.clinical_scope_bindings;begin
 b=private.clinical_binding(c.id,scope);
 return b.id is not null and b.created_at<=at_time
 and private.permission_effective(c.clinic_id,person,'procedure.perform',b.procedure_id) is not null
 and (not b.professional_required or (private.clinical_professional_at(c.clinic_id,person,clock_timestamp()) and private.clinical_professional_at(c.clinic_id,person,at_time)))
 and exists(select 1 from private.member_permission_grants g where g.id=private.permission_effective(c.clinic_id,person,'procedure.perform',b.procedure_id) and g.granted_at<=at_time and g.valid_until>clock_timestamp() and g.valid_until>at_time)
 and exists(select 1 from public.person_procedure_authorizations a where a.case_id=c.id and a.person_id=person and a.scope=$3 and a.scope_binding_id=b.id and a.authority_grant_id is not null and a.created_at<=at_time and a.valid_until>at_time and a.valid_until>statement_timestamp() and not exists(select 1 from public.person_procedure_revocations r where r.authorization_id=a.id));
end$$;
create or replace function private.clinical_write_check(c public.clinical_cases,scope text,performer uuid,observed timestamptz) returns void language plpgsql security definer set search_path='' as $$begin
 if performer is distinct from auth.uid() then raise exception 'own_act_only';end if;
 if not private.clinical_readable(c) then raise exception 'clinical_access_denied';end if;
 if observed is null or observed>clock_timestamp() or (observed at time zone 'UTC')::date<c.clinical_date then raise exception 'invalid_observation_time';end if;
 perform private.clinical_permission_context(c,scope,performer,observed);
end$$;
create function private.clinical_authority_require(c public.clinical_cases) returns uuid language plpgsql security definer set search_path='' as $$
declare g uuid;begin
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,9061));
 g=private.permission_require(c.clinic_id,'clinical.authorize');
 if not exists(select 1 from private.member_permission_grants where member_permission_grants.id=g and valid_until>clock_timestamp()) or not private.clinical_professional_at(c.clinic_id,auth.uid(),clock_timestamp()) then raise exception 'verified_authority_required';end if;
 return g;
end$$;
create function public.clinical_scope_bind(p_case uuid,p_scope text,p_procedure uuid,p_professional boolean,p_source text,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;old_binding private.clinical_scope_bindings;id uuid;g uuid;begin
 select * into c from public.clinical_cases where clinical_cases.id=p_case;
 perform 1 from public.clinics where clinics.id=c.clinic_id for update;
 perform 1 from public.clinical_cases where clinical_cases.id=p_case for update;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,9061));
 g=private.permission_require(c.clinic_id,'clinical.authorize');
 if not exists(select 1 from private.member_permission_grants where member_permission_grants.id=g and valid_until>clock_timestamp()) or not private.clinical_professional_at(c.clinic_id,auth.uid(),clock_timestamp()) then raise exception 'verified_authority_required';end if;
 if c.responsible_id is distinct from auth.uid() or not private.clinical_readable(c) then raise exception 'case_responsible_required';end if;
 if not exists(select 1 from private.procedure_types where procedure_types.id=p_procedure and clinic_id=c.clinic_id and active) then raise exception 'invalid_procedure_scope';end if;
 if p_professional is null then raise exception 'explicit_professional_policy_required';end if;
 if p_scope<>'observaciones' and not p_professional then raise exception 'professional_act_policy_required';end if;
 old_binding=private.clinical_binding(c.id,p_scope);
 if old_binding.id is not null and old_binding.procedure_id=p_procedure and old_binding.professional_required=p_professional and old_binding.source=btrim(p_source) then return old_binding.id;end if;
 if old_binding.id is not null then
 insert into private.clinical_scope_revocations(binding_id,revoked_by,reason) values(old_binding.id,auth.uid(),btrim(p_reason));end if;
 insert into private.clinical_scope_bindings(clinic_id,case_id,scope,procedure_id,professional_required,source,created_by)
 values(c.clinic_id,c.id,p_scope,p_procedure,p_professional,btrim(p_source),auth.uid()) returning clinical_scope_bindings.id into id;
 perform private.permission_event(c.clinic_id,'clinical_scope_bound',id,jsonb_build_object('case_id',c.id,'scope',p_scope,'permission_grant_id',g));
 return id;
end$$;
create or replace function public.clinical_cases_list(p_clinic uuid,p_patient uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform private.permission_require(p_clinic,'patient.read');perform private.permission_require(p_clinic,'clinical.read');
 return coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('patient_name',p.name) order by c.created_at desc) from public.clinical_cases c join public.vet_patients p on p.id=c.patient_id where c.clinic_id=p_clinic and (p_patient is null or c.patient_id=p_patient) and private.clinical_readable(c)),'[]');
end $$;
create or replace function public.clinical_case_snapshot(p_case uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.clinical_cases;
begin
 select * into c from public.clinical_cases where id=p_case;
 if not found or not private.clinical_readable(c) then raise exception 'clinical_access_denied';end if;
 return jsonb_build_object('case',to_jsonb(c)||jsonb_build_object('patient_name',(select name from public.vet_patients where id=c.patient_id)),
 'staff',coalesce((select jsonb_agg(to_jsonb(s)) from public.case_staff_assignments s where case_id=c.id),'[]'),
 'observations',coalesce((select jsonb_agg(to_jsonb(o)||jsonb_build_object('value',o.value::text) order by o.observed_at,o.created_at) from public.clinical_observations o where case_id=c.id),'[]'),
 'acts',coalesce((select jsonb_agg(to_jsonb(a) order by a.observed_at,a.created_at) from public.clinical_procedure_acts a where case_id=c.id),'[]'),
 'authorizations',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('revoked',(select to_jsonb(r) from public.person_procedure_revocations r where r.authorization_id=a.id))) from public.person_procedure_authorizations a where case_id=c.id),'[]'));
end $$;
create or replace function public.clinical_observation_add(p_case uuid,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;id uuid;fp jsonb;k text;u text;n numeric;t timestamptz;performer uuid;previous uuid;
begin
 select * into c from public.clinical_cases where clinical_cases.id=p_case;
 perform 1 from public.clinics where clinics.id=c.clinic_id for update;
 select * into c from public.clinical_cases where clinical_cases.id=p_case for update;
 if not found then raise exception 'clinical_access_denied';end if;
 k=p_data->>'kind';u=case k when 'weight' then 'kg' when 'fc' then 'lpm' when 'pulse' then 'lpm' when 'fr' then 'rpm' when 'temperature' then '°C' when 'tllc' then 's' when 'bp_systolic' then 'mmHg' when 'bp_diastolic' then 'mmHg' end;
 if p_data ? 'notes' and jsonb_typeof(p_data->'notes') is distinct from 'string' then raise exception 'invalid_measurement';end if;
 if p_data ? 'correction_reason' and jsonb_typeof(p_data->'correction_reason') is distinct from 'string' then raise exception 'invalid_measurement';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or u is null or p_data->>'unit' is distinct from u or jsonb_typeof(p_data->'value') is distinct from 'string' or p_data->>'value' !~ '^-?\d{1,12}(\.\d{1,9})?$' or length(coalesce(p_data->>'notes',''))>4000 then raise exception 'invalid_measurement';end if;
 n=(p_data->>'value')::numeric;if (k='weight' and n<=0) or (k<>'temperature' and n<0) then raise exception 'invalid_measurement';end if;
 performer=(p_data->>'performed_by')::uuid;t=private.clinical_time(p_data->>'observed_at');
 perform private.clinical_write_check(c,'observaciones',performer,t);
 previous=nullif(p_data->>'replaces_id','')::uuid;
 if previous is not null then perform private.clinical_authority_require(c);end if;
 if previous is not null and (c.responsible_id<>auth.uid() or not private.clinical_professional_at(c.clinic_id,auth.uid(),clock_timestamp()) or coalesce(length(btrim(p_data->>'correction_reason')),0) not between 1 and 1000 or not exists(select 1 from public.clinical_observations where clinical_observations.id=previous and case_id=c.id and kind=k)) then raise exception 'responsible_correction_required';end if;
 fp=jsonb_build_object('kind','clinical_observation','case',p_case,'data',p_data);id=private.vet_receipt(c.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.clinical_observations(clinic_id,case_id,kind,value,unit,observed_at,performed_by,recorded_by,notes,replaces_id,correction_reason) values(c.clinic_id,c.id,k,n,u,t,performer,auth.uid(),coalesce(p_data->>'notes',''),previous,p_data->>'correction_reason') returning clinical_observations.id into id;
 if k='weight' then insert into public.vet_patient_events(clinic_id,patient_id,kind,payload,created_by,clinical_case_id,clinical_observation_id) values(c.clinic_id,c.patient_id,'weight',jsonb_build_object('date',to_char(t at time zone 'UTC','YYYY-MM-DD'),'kg',p_data->>'value','clinical_case_id',c.id),auth.uid(),c.id,id);end if;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(c.clinic_id,auth.uid(),'clinical_observation_added',id,private.clinical_permission_context(c,'observaciones',performer,t));return id;
end $$;
create or replace function public.clinical_act_add(p_case uuid,p_scope text,p_notes text,p_performer uuid,p_observed text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;id uuid;fp jsonb;t timestamptz;
begin
 select * into c from public.clinical_cases where clinical_cases.id=p_case;
 perform 1 from public.clinics where clinics.id=c.clinic_id for update;
 select * into c from public.clinical_cases where clinical_cases.id=p_case for update;
 if not found then raise exception 'clinical_access_denied';end if;
 t=private.clinical_time(p_observed);perform private.clinical_write_check(c,p_scope,p_performer,t);
 fp=jsonb_build_object('kind','clinical_act','case',p_case,'scope',p_scope,'notes',p_notes,'performer',p_performer,'observed',p_observed);id=private.vet_receipt(c.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.clinical_procedure_acts(clinic_id,case_id,scope,notes,observed_at,performed_by,recorded_by) values(c.clinic_id,c.id,p_scope,p_notes,t,p_performer,auth.uid()) returning clinical_procedure_acts.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(c.clinic_id,auth.uid(),'clinical_act_added',id,private.clinical_permission_context(c,p_scope,p_performer,t));return id;
end $$;
create or replace function public.clinical_authorize(p_case uuid,p_person uuid,p_scope text,p_until text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare authority_id uuid;binding private.clinical_scope_bindings;c public.clinical_cases;id uuid;fp jsonb;until_at timestamptz;
begin
 select * into c from public.clinical_cases where clinical_cases.id=p_case;
 perform 1 from public.clinics where clinics.id=c.clinic_id for update;
 select * into c from public.clinical_cases where clinical_cases.id=p_case for update;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,9061));
 authority_id=private.clinical_authority_require(c);
 if c.responsible_id is distinct from auth.uid() or not private.clinical_professional_at(c.clinic_id,auth.uid(),clock_timestamp()) then raise exception 'responsible_mvz_required';end if;
 binding=private.clinical_binding(c.id,p_scope);
 if not private.clinical_readable(c) or binding.id is null then raise exception 'clinical_scope_mapping_required';end if;
 until_at=private.clinical_time(p_until);
 if until_at<=clock_timestamp() or not exists(select 1 from public.clinic_members where clinic_id=c.clinic_id and user_id=p_person) then raise exception 'invalid_authorization';end if;
 fp=jsonb_build_object('kind','clinical_grant','case',p_case,'person',p_person,'scope',p_scope,'until',p_until);id=private.vet_receipt(c.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.person_procedure_authorizations(clinic_id,case_id,person_id,scope,valid_until,granted_by,authority_grant_id,scope_binding_id) values(c.clinic_id,c.id,p_person,p_scope,until_at,auth.uid(),authority_id,binding.id) returning person_procedure_authorizations.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(c.clinic_id,auth.uid(),'clinical_procedure_authorized',id);return id;
end $$;
create or replace function public.clinical_authorization_revoke(p_id uuid,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare a public.person_procedure_authorizations;c public.clinical_cases;id uuid;fp jsonb;
begin
 select * into a from public.person_procedure_authorizations where person_procedure_authorizations.id=p_id;
 select * into c from public.clinical_cases where clinical_cases.id=a.case_id;
 perform 1 from public.clinics where clinics.id=c.clinic_id for update;
 select * into c from public.clinical_cases where clinical_cases.id=a.case_id for update;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,9061));
 perform private.clinical_authority_require(c);
 if c.responsible_id is distinct from auth.uid() or not private.clinical_professional_at(c.clinic_id,auth.uid(),clock_timestamp()) then raise exception 'responsible_mvz_required';end if;
 fp=jsonb_build_object('kind','clinical_revoke','grant',p_id,'reason',p_reason);id=private.vet_receipt(c.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.person_procedure_revocations(authorization_id,reason,created_by) values(p_id,p_reason,auth.uid()) returning person_procedure_revocations.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(c.clinic_id,auth.uid(),'clinical_procedure_revoked',id);return id;
end $$;
create function private.permission_clinical_read(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.permission_effective(p_clinic,auth.uid(),'clinical.read') is not null;
$$;
revoke all on function private.permission_clinical_read(uuid) from public,anon;
grant execute on function private.permission_clinical_read(uuid) to authenticated;

-- Old free-form patient events lack a structured procedure binding. No implicit conversion.
create or replace function public.add_vet_patient_event(p_clinic_id uuid,p_patient_id uuid,p_kind text,p_payload jsonb,p_operation_id text) returns uuid language plpgsql security definer set search_path='' as $$begin
 raise exception 'structured_clinical_record_required';
end$$;
drop policy vet_event_read on public.vet_patient_events;
create policy vet_event_read on public.vet_patient_events for select to authenticated using(
 private.clinical_current_observation(clinical_observation_id) and
 case when clinical_case_id is not null or form_document_id is not null then exists(select 1 from public.clinical_cases c where (c.id=clinical_case_id or c.document_id=form_document_id) and private.clinical_readable(c))
 else private.permission_patient_read(clinic_id) and private.permission_clinical_read(clinic_id) end);
-- RLS evaluation needs a narrow boolean wrapper, not EXECUTE on the generic evaluator.

revoke all on function private.clinical_authority_require(public.clinical_cases),private.clinical_identity_lock(),private.clinical_professional_at(uuid,uuid,timestamptz),private.clinical_binding(uuid,text),private.clinical_permission_context(public.clinical_cases,text,uuid,timestamptz),public.clinical_scope_bind(uuid,text,uuid,boolean,text,text) from public,anon,authenticated;
grant execute on function public.clinical_scope_bind(uuid,text,uuid,boolean,text,text) to authenticated;
select private.beta_install_guards();
notify pgrst,'reload schema';
commit;
