-- Local candidate after 13K. Context registration is not an attended consultation.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy) or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
alter table public.clinical_cases alter column document_id drop not null;
insert into private.permission_catalog(code,label,procedure_scoped,requires_professional) values('clinical.case.prepare','Registrar contexto de caso sin atribuir atención',false,false);
create table private.clinical_case_intakes(
 case_id uuid primary key,clinic_id uuid not null references public.clinics(id),
 actor_id uuid not null references auth.users(id),member_since timestamptz not null,prepare_grant_id uuid not null references private.member_permission_grants(id),
 responsible_id uuid not null references auth.users(id),responsible_member_since timestamptz not null,responsible_grant_id uuid not null references private.member_permission_grants(id),responsible_profile_version_id uuid not null references private.professional_profile_versions(id),
 input_hash text not null,created_at timestamptz not null default clock_timestamp(),foreign key(clinic_id,case_id) references public.clinical_cases(clinic_id,id));
alter table private.clinical_case_intakes enable row level security;
revoke all on private.clinical_case_intakes from public,anon,authenticated,service_role;
create trigger immutable before update or delete on private.clinical_case_intakes for each row execute function private.permission_immutable();
create function private.clinical_case_responsible(p_clinic uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.form_document_current(p_clinic,p_user,'clinical.authorize') and private.form_document_current(p_clinic,p_user,'clinical.read') and private.form_document_current(p_clinic,p_user,'patient.read') and private.clinical_professional_at(p_clinic,p_user,clock_timestamp());
$$;
create function public.clinical_case_register(p_clinic uuid,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_patient uuid;v_responsible uuid;person uuid;g uuid;profile jsonb;d date;reason text;notes text;v_kind text;v_id uuid;fp jsonb;begin
 perform private.medication_lock(p_clinic);
 v_responsible=(p_data->>'responsible_id')::uuid;
 for person in select distinct x from unnest(array[auth.uid(),v_responsible]) x where x is not null order by x loop perform pg_advisory_xact_lock(hashtextextended(person::text,9061));end loop;
 if not private.form_document_reader(p_clinic) then raise exception 'clinical_access_denied';end if;
 perform public.beta_access_check(true,p_clinic);
 g=private.hospital_order_permission(p_clinic,'clinical.case.prepare',null,false);
 if not private.clinical_case_responsible(p_clinic,v_responsible) then raise exception 'explicit_verified_case_responsible_required';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or exists(select 1 from jsonb_object_keys(p_data) k where k not in ('patient_id','responsible_id','clinical_date','kind','reason','notes')) then raise exception 'case_context_fields_only';end if;
 if jsonb_typeof(p_data->'reason') is distinct from 'string' or jsonb_typeof(p_data->'kind') is distinct from 'string' or (p_data ? 'notes' and jsonb_typeof(p_data->'notes') is distinct from 'string') then raise exception 'invalid_case_context';end if;
 v_kind=p_data->>'kind';reason=btrim(p_data->>'reason');notes=coalesce(p_data->>'notes','');
 if v_kind not in ('clinical_history','surgical_sheet','surgical_risk') or coalesce(length(reason),0) not between 1 and 300 or length(notes)>4000 then raise exception 'invalid_case_context';end if;
 if coalesce(p_data->>'clinical_date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'explicit_clinical_date_required';end if;
 begin d=(p_data->>'clinical_date')::date;exception when others then raise exception 'invalid_clinical_date';end;
 if to_char(d,'YYYY-MM-DD') is distinct from p_data->>'clinical_date' or d>current_date then raise exception 'invalid_clinical_date';end if;
 v_patient=(p_data->>'patient_id')::uuid;
 if not exists(select 1 from public.vet_patients where id=v_patient and clinic_id=p_clinic) then raise exception 'matching_clinic_patient_required';end if;
 fp=jsonb_build_object('kind','clinical_case_context','data',p_data);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 select private.rx_profile(id) into profile from public.professional_profiles where clinic_id=p_clinic and user_id=v_responsible;
 insert into public.clinical_cases(clinic_id,patient_id,document_id,responsible_id,kind,title,reason,clinical_date,notes)
 values(p_clinic,v_patient,null,v_responsible,v_kind,left(reason,200),reason,d,notes) returning id into v_id;
 insert into private.clinical_case_intakes(case_id,clinic_id,actor_id,member_since,prepare_grant_id,responsible_id,responsible_member_since,responsible_grant_id,responsible_profile_version_id,input_hash)
 values(v_id,p_clinic,auth.uid(),(select created_at from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()),g,v_responsible,(select created_at from public.clinic_members where clinic_id=p_clinic and user_id=v_responsible),private.permission_effective(p_clinic,v_responsible,'clinical.authorize'),(profile->>'id')::uuid,encode(sha256(convert_to(p_data::text,'UTF8')),'hex'));
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'clinical_case_context_registered',v_id,jsonb_build_object('prepare_grant_id',g,'responsible_selected',v_responsible,'no_attention_or_authorization_created',true));
 return v_id;
end$$;
-- Make the existing signed-document projection safe for a nullable original.
alter function public.clinical_workspace(uuid,uuid) set schema private;
alter function private.clinical_workspace(uuid,uuid) rename to clinical_workspace_charts;
revoke all on function private.clinical_workspace_charts(uuid,uuid) from public,anon,authenticated,service_role;
create function public.clinical_workspace(p_clinic uuid,p_case uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare w jsonb;can_create boolean;docs jsonb;begin
 w=private.clinical_workspace_charts(p_clinic,p_case);
 can_create=(w->>'can_read')::boolean and private.form_document_current(p_clinic,auth.uid(),'clinical.case.prepare');
 if can_create then can_create=(public.beta_access_check(false,p_clinic)->>'mode') in ('internal','active','sponsor_grace');end if;
 select coalesce(jsonb_agg(d||jsonb_build_object('is_original',coalesce((d->>'is_original')::boolean,false))),'[]') into docs from jsonb_array_elements(w->'documents') d;
 return w||jsonb_build_object('registration_version',1,'actions',(w->'actions')||jsonb_build_object('create',can_create),'documents',docs,
 'patients',case when can_create and p_case is null then coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name) order by p.name,p.id) from public.vet_patients p where p.clinic_id=p_clinic),'[]') else '[]'::jsonb end,
 'responsibles',case when can_create and p_case is null then coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'name',private.rx_profile(p.id)->>'name','license',private.rx_profile(p.id)->>'license') order by p.user_id) from public.professional_profiles p where p.clinic_id=p_clinic and private.clinical_case_responsible(p_clinic,p.user_id)),'[]') else '[]'::jsonb end);
end$$;
revoke all on function private.clinical_case_responsible(uuid,uuid),public.clinical_case_register(uuid,jsonb,text),public.clinical_workspace(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.clinical_case_register(uuid,jsonb,text),public.clinical_workspace(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
