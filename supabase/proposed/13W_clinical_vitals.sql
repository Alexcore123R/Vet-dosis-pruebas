-- Stage 2B.29: structured vital-sign snapshots inside an authorized clinical case.
-- Stores observed facts only. PAM is derived; reference ranges remain versioned catalog data.
begin;

create table public.clinical_vital_sets (
 id uuid primary key default gen_random_uuid(),
 clinic_id uuid not null,
 case_id uuid not null,
 observed_at timestamptz not null,
 performed_by uuid not null references auth.users(id),
 recorded_by uuid not null references auth.users(id),
 fc numeric(24,9),
 fr numeric(24,9),
 temperature numeric(24,9),
 tllc numeric(24,9),
 bp_systolic numeric(24,9),
 bp_diastolic numeric(24,9),
 mucosa_color text check(mucosa_color in ('rosadas','palidas','cianoticas','ictericas','congestivas')),
 mucosa_humidity text check(mucosa_humidity in ('humedas','pegajosas','secas')),
 reference_snapshot jsonb not null default '[]'::jsonb check(jsonb_typeof(reference_snapshot)='array'),
 notes text not null default '' check(length(notes)<=4000),
 created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,case_id) references public.clinical_cases(clinic_id,id),
 check(fc is null or fc>0),
 check(fr is null or fr>0),
 check(temperature is null or temperature>0),
 check(tllc is null or tllc>=0),
 check(bp_systolic is null or bp_systolic>0),
 check(bp_diastolic is null or bp_diastolic>0),
 check((bp_systolic is null)=(bp_diastolic is null)),
 check(
  fc is not null or fr is not null or temperature is not null or tllc is not null or
  bp_systolic is not null or mucosa_color is not null or mucosa_humidity is not null or
  length(btrim(notes))>0
 )
);
create index clinical_vital_sets_case on public.clinical_vital_sets(case_id,observed_at desc,created_at desc);
alter table public.clinical_vital_sets enable row level security;
revoke all on public.clinical_vital_sets from public,anon,authenticated,service_role;
create trigger clinical_vital_sets_immutable
 before update or delete on public.clinical_vital_sets
 for each row execute function private.clinical_immutable();

create function private.clinical_vital_json(v public.clinical_vital_sets)
returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(v)||jsonb_build_object(
  'fc',case when v.fc is null then null else v.fc::text end,
  'fr',case when v.fr is null then null else v.fr::text end,
  'temperature',case when v.temperature is null then null else v.temperature::text end,
  'tllc',case when v.tllc is null then null else v.tllc::text end,
  'bp_systolic',case when v.bp_systolic is null then null else v.bp_systolic::text end,
  'bp_diastolic',case when v.bp_diastolic is null then null else v.bp_diastolic::text end,
  'pam',case when v.bp_systolic is null then null else ((v.bp_systolic+2*v.bp_diastolic)/3)::text end
 );
$$;
revoke all on function private.clinical_vital_json(public.clinical_vital_sets) from public,anon,authenticated,service_role;

create function public.clinical_vitals_add(
 p_case uuid,
 p_data jsonb,
 p_operation text
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 c public.clinical_cases;
 v public.clinical_vital_sets;
 fp jsonb;
 existing_id uuid;
 performer uuid;
 observed timestamptz;
 field text;
 n numeric;
 fc_n numeric;fr_n numeric;temp_n numeric;tllc_n numeric;sbp_n numeric;dbp_n numeric;
 color text;humidity text;note text;refs jsonb;
begin
 select * into c from public.clinical_cases where id=p_case for update;
 if not found then raise exception 'clinical_access_denied';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or
    exists(select 1 from jsonb_object_keys(p_data) k where k not in (
     'observed_at','performed_by','fc','fr','temperature','tllc',
     'bp_systolic','bp_diastolic','mucosa_color','mucosa_humidity','reference_snapshot','notes'
    )) then
  raise exception 'invalid_vital_set';
 end if;

 begin performer=(p_data->>'performed_by')::uuid;exception when others then raise exception 'invalid_vital_set';end;
 observed=private.clinical_time(p_data->>'observed_at');
 perform private.clinical_write_check(c,'observaciones',performer,observed);

 foreach field in array array['fc','fr','temperature','tllc','bp_systolic','bp_diastolic'] loop
  if p_data ? field and p_data->field<>'null'::jsonb then
   if jsonb_typeof(p_data->field)<>'string' or p_data->>field !~ '^[0-9]{1,12}([.][0-9]{1,9})?$' then
    raise exception 'invalid_vital_set';
   end if;
   n=(p_data->>field)::numeric;
   if (field in ('fc','fr','temperature','bp_systolic','bp_diastolic') and n<=0) or
      (field='tllc' and n<0) then
    raise exception 'invalid_vital_set';
   end if;
  end if;
 end loop;

 fc_n=nullif(p_data->>'fc','')::numeric;
 fr_n=nullif(p_data->>'fr','')::numeric;
 temp_n=nullif(p_data->>'temperature','')::numeric;
 tllc_n=nullif(p_data->>'tllc','')::numeric;
 sbp_n=nullif(p_data->>'bp_systolic','')::numeric;
 dbp_n=nullif(p_data->>'bp_diastolic','')::numeric;
 if (sbp_n is null) is distinct from (dbp_n is null) then raise exception 'paired_blood_pressure_required';end if;

 color=nullif(p_data->>'mucosa_color','');
 if color is not null and color not in ('rosadas','palidas','cianoticas','ictericas','congestivas') then raise exception 'invalid_vital_set';end if;
 humidity=nullif(p_data->>'mucosa_humidity','');
 if humidity is not null and humidity not in ('humedas','pegajosas','secas') then raise exception 'invalid_vital_set';end if;
 if p_data ? 'reference_snapshot' then
  refs=p_data->'reference_snapshot';
  if jsonb_typeof(refs)<>'array' or jsonb_array_length(refs)>6 or exists(
   select 1 from jsonb_array_elements(refs) r
   where jsonb_typeof(r)<>'object'
      or exists(select 1 from jsonb_object_keys(r) k where k not in (
       'catalog_version','reference_id','species','parameter','unit','min','max',
       'source','reviewed_at','state'
      ))
      or not (r ?& array[
       'catalog_version','reference_id','species','parameter','unit','min','max',
       'source','reviewed_at','state'
      ])
      or r->>'state' not in ('below','within','above')
      or r->>'parameter' not in ('fc','fr','temperature','tllc','bp_systolic','bp_diastolic')
      or r->>'min' !~ '^[0-9]{1,12}([.][0-9]{1,9})?$'
      or r->>'max' !~ '^[0-9]{1,12}([.][0-9]{1,9})?$'
      or (r->>'min')::numeric>(r->>'max')::numeric
      or length(r->>'source')=0
      or length(r->>'catalog_version')=0
      or length(r->>'reference_id')=0
  ) then
   raise exception 'invalid_vital_reference_snapshot';
  end if;
 else
  refs='[]'::jsonb;
 end if;
 if p_data ? 'notes' and jsonb_typeof(p_data->'notes')<>'string' then raise exception 'invalid_vital_set';end if;
 note=coalesce(p_data->>'notes','');
 if length(note)>4000 then raise exception 'invalid_vital_set';end if;
 if fc_n is null and fr_n is null and temp_n is null and tllc_n is null and sbp_n is null and color is null and humidity is null and btrim(note)='' then
  raise exception 'empty_vital_set';
 end if;

 fp=jsonb_build_object('kind','clinical_vitals','case',p_case,'data',p_data);
 existing_id=private.vet_receipt(c.clinic_id,p_operation,fp);
 if existing_id is not null then
  select * into v from public.clinical_vital_sets where id=existing_id and clinic_id=c.clinic_id and case_id=c.id;
  if not found then raise exception 'clinical_vital_receipt_invalid';end if;
  return private.clinical_vital_json(v);
 end if;

 insert into public.clinical_vital_sets(
  clinic_id,case_id,observed_at,performed_by,recorded_by,
  fc,fr,temperature,tllc,bp_systolic,bp_diastolic,mucosa_color,mucosa_humidity,reference_snapshot,notes
 ) values(
  c.clinic_id,c.id,observed,performer,auth.uid(),
  fc_n,fr_n,temp_n,tllc_n,sbp_n,dbp_n,color,humidity,refs,note
 ) returning * into v;

 insert into private.vet_operation_receipts
 values(auth.uid(),c.clinic_id,p_operation,fp,v.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(c.clinic_id,auth.uid(),'clinical_vitals_recorded',v.id,
  jsonb_build_object('case_id',c.id,'patient_id',c.patient_id,'performed_by',performer,'observed_at',observed));

 return private.clinical_vital_json(v);
end$$;

create or replace function public.clinical_cases_list(p_clinic uuid,p_patient uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.form_document_reader(p_clinic) then raise exception 'clinical_access_denied';end if;
 return coalesce((
  select jsonb_agg(
   to_jsonb(c)||jsonb_build_object(
    'patient_name',p.name,'patient_species',p.species,'patient_breed',p.breed,
    'patient_sex',p.sex,'patient_birth_date',p.birth_date
   ) order by c.created_at desc
  )
  from public.clinical_cases c
  join public.vet_patients p on p.id=c.patient_id and p.clinic_id=c.clinic_id
  where c.clinic_id=p_clinic and (p_patient is null or c.patient_id=p_patient)
   and private.clinical_readable(c)
 ),'[]'::jsonb);
end$$;

create or replace function public.clinical_case_snapshot(p_case uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.clinical_cases;p public.vet_patients;
begin
 select * into c from public.clinical_cases where id=p_case;
 if not found or not private.clinical_readable(c) then raise exception 'clinical_access_denied';end if;
 select * into p from public.vet_patients where id=c.patient_id and clinic_id=c.clinic_id;
 return jsonb_build_object(
  'case',to_jsonb(c)||jsonb_build_object(
   'patient_name',p.name,'patient_species',p.species,'patient_breed',p.breed,
   'patient_sex',p.sex,'patient_birth_date',p.birth_date
  ),
  'staff',coalesce((select jsonb_agg(to_jsonb(s)) from public.case_staff_assignments s where case_id=c.id),'[]'),
  'observations',coalesce((select jsonb_agg(to_jsonb(o)||jsonb_build_object('value',o.value::text) order by o.observed_at,o.created_at) from public.clinical_observations o where case_id=c.id),'[]'),
  'vitals',coalesce((select jsonb_agg(private.clinical_vital_json(v) order by v.observed_at,v.created_at) from public.clinical_vital_sets v where v.case_id=c.id),'[]'),
  'acts',coalesce((select jsonb_agg(to_jsonb(a) order by a.observed_at,a.created_at) from public.clinical_procedure_acts a where case_id=c.id),'[]'),
  'authorizations',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('revoked',(select to_jsonb(r) from public.person_procedure_revocations r where r.authorization_id=a.id))) from public.person_procedure_authorizations a where case_id=c.id),'[]')
 );
end$$;

revoke all on function public.clinical_vitals_add(uuid,jsonb,text) from public,anon;
grant execute on function public.clinical_vitals_add(uuid,jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;

      or r->>'max' !~ '^[0-9]{1,12}([.][0-9]{1,9})? note=coalesce(p_data->>'notes','');
 if length(note)>4000 then raise exception 'invalid_vital_set';end if;
 if fc_n is null and fr_n is null and temp_n is null and tllc_n is null and sbp_n is null and color is null and humidity is null and btrim(note)='' then
  raise exception 'empty_vital_set';
 end if;

 fp=jsonb_build_object('kind','clinical_vitals','case',p_case,'data',p_data);
 existing_id=private.vet_receipt(c.clinic_id,p_operation,fp);
 if existing_id is not null then
  select * into v from public.clinical_vital_sets where id=existing_id and clinic_id=c.clinic_id and case_id=c.id;
  if not found then raise exception 'clinical_vital_receipt_invalid';end if;
  return private.clinical_vital_json(v);
 end if;

 insert into public.clinical_vital_sets(
  clinic_id,case_id,observed_at,performed_by,recorded_by,
  fc,fr,temperature,tllc,bp_systolic,bp_diastolic,mucosa_color,mucosa_humidity,notes
 ) values(
  c.clinic_id,c.id,observed,performer,auth.uid(),
  fc_n,fr_n,temp_n,tllc_n,sbp_n,dbp_n,color,humidity,note
 ) returning * into v;

 insert into private.vet_operation_receipts
 values(auth.uid(),c.clinic_id,p_operation,fp,v.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(c.clinic_id,auth.uid(),'clinical_vitals_recorded',v.id,
  jsonb_build_object('case_id',c.id,'patient_id',c.patient_id,'performed_by',performer,'observed_at',observed));

 return private.clinical_vital_json(v);
end$$;

create or replace function public.clinical_cases_list(p_clinic uuid,p_patient uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.form_document_reader(p_clinic) then raise exception 'clinical_access_denied';end if;
 return coalesce((
  select jsonb_agg(
   to_jsonb(c)||jsonb_build_object(
    'patient_name',p.name,'patient_species',p.species,'patient_breed',p.breed,
    'patient_sex',p.sex,'patient_birth_date',p.birth_date
   ) order by c.created_at desc
  )
  from public.clinical_cases c
  join public.vet_patients p on p.id=c.patient_id and p.clinic_id=c.clinic_id
  where c.clinic_id=p_clinic and (p_patient is null or c.patient_id=p_patient)
   and private.clinical_readable(c)
 ),'[]'::jsonb);
end$$;

create or replace function public.clinical_case_snapshot(p_case uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.clinical_cases;p public.vet_patients;
begin
 select * into c from public.clinical_cases where id=p_case;
 if not found or not private.clinical_readable(c) then raise exception 'clinical_access_denied';end if;
 select * into p from public.vet_patients where id=c.patient_id and clinic_id=c.clinic_id;
 return jsonb_build_object(
  'case',to_jsonb(c)||jsonb_build_object(
   'patient_name',p.name,'patient_species',p.species,'patient_breed',p.breed,
   'patient_sex',p.sex,'patient_birth_date',p.birth_date
  ),
  'staff',coalesce((select jsonb_agg(to_jsonb(s)) from public.case_staff_assignments s where case_id=c.id),'[]'),
  'observations',coalesce((select jsonb_agg(to_jsonb(o)||jsonb_build_object('value',o.value::text) order by o.observed_at,o.created_at) from public.clinical_observations o where case_id=c.id),'[]'),
  'vitals',coalesce((select jsonb_agg(private.clinical_vital_json(v) order by v.observed_at,v.created_at) from public.clinical_vital_sets v where v.case_id=c.id),'[]'),
  'acts',coalesce((select jsonb_agg(to_jsonb(a) order by a.observed_at,a.created_at) from public.clinical_procedure_acts a where case_id=c.id),'[]'),
  'authorizations',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('revoked',(select to_jsonb(r) from public.person_procedure_revocations r where r.authorization_id=a.id))) from public.person_procedure_authorizations a where case_id=c.id),'[]')
 );
end$$;

revoke all on function public.clinical_vitals_add(uuid,jsonb,text) from public,anon;
grant execute on function public.clinical_vitals_add(uuid,jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;

      or (r->>'min')::numeric>(r->>'max')::numeric
      or length(r->>'source')=0
      or length(r->>'catalog_version')=0
      or length(r->>'reference_id')=0
  ) then
   raise exception 'invalid_vital_reference_snapshot';
  end if;
 else
  refs='[]'::jsonb;
 end if;
 if p_data ? 'notes' and jsonb_typeof(p_data->'notes')<>'string' then raise exception 'invalid_vital_set';end if;
 note=coalesce(p_data->>'notes','');
 if length(note)>4000 then raise exception 'invalid_vital_set';end if;
 if fc_n is null and fr_n is null and temp_n is null and tllc_n is null and sbp_n is null and color is null and humidity is null and btrim(note)='' then
  raise exception 'empty_vital_set';
 end if;

 fp=jsonb_build_object('kind','clinical_vitals','case',p_case,'data',p_data);
 existing_id=private.vet_receipt(c.clinic_id,p_operation,fp);
 if existing_id is not null then
  select * into v from public.clinical_vital_sets where id=existing_id and clinic_id=c.clinic_id and case_id=c.id;
  if not found then raise exception 'clinical_vital_receipt_invalid';end if;
  return private.clinical_vital_json(v);
 end if;

 insert into public.clinical_vital_sets(
  clinic_id,case_id,observed_at,performed_by,recorded_by,
  fc,fr,temperature,tllc,bp_systolic,bp_diastolic,mucosa_color,mucosa_humidity,notes
 ) values(
  c.clinic_id,c.id,observed,performer,auth.uid(),
  fc_n,fr_n,temp_n,tllc_n,sbp_n,dbp_n,color,humidity,note
 ) returning * into v;

 insert into private.vet_operation_receipts
 values(auth.uid(),c.clinic_id,p_operation,fp,v.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(c.clinic_id,auth.uid(),'clinical_vitals_recorded',v.id,
  jsonb_build_object('case_id',c.id,'patient_id',c.patient_id,'performed_by',performer,'observed_at',observed));

 return private.clinical_vital_json(v);
end$$;

create or replace function public.clinical_cases_list(p_clinic uuid,p_patient uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.form_document_reader(p_clinic) then raise exception 'clinical_access_denied';end if;
 return coalesce((
  select jsonb_agg(
   to_jsonb(c)||jsonb_build_object(
    'patient_name',p.name,'patient_species',p.species,'patient_breed',p.breed,
    'patient_sex',p.sex,'patient_birth_date',p.birth_date
   ) order by c.created_at desc
  )
  from public.clinical_cases c
  join public.vet_patients p on p.id=c.patient_id and p.clinic_id=c.clinic_id
  where c.clinic_id=p_clinic and (p_patient is null or c.patient_id=p_patient)
   and private.clinical_readable(c)
 ),'[]'::jsonb);
end$$;

create or replace function public.clinical_case_snapshot(p_case uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.clinical_cases;p public.vet_patients;
begin
 select * into c from public.clinical_cases where id=p_case;
 if not found or not private.clinical_readable(c) then raise exception 'clinical_access_denied';end if;
 select * into p from public.vet_patients where id=c.patient_id and clinic_id=c.clinic_id;
 return jsonb_build_object(
  'case',to_jsonb(c)||jsonb_build_object(
   'patient_name',p.name,'patient_species',p.species,'patient_breed',p.breed,
   'patient_sex',p.sex,'patient_birth_date',p.birth_date
  ),
  'staff',coalesce((select jsonb_agg(to_jsonb(s)) from public.case_staff_assignments s where case_id=c.id),'[]'),
  'observations',coalesce((select jsonb_agg(to_jsonb(o)||jsonb_build_object('value',o.value::text) order by o.observed_at,o.created_at) from public.clinical_observations o where case_id=c.id),'[]'),
  'vitals',coalesce((select jsonb_agg(private.clinical_vital_json(v) order by v.observed_at,v.created_at) from public.clinical_vital_sets v where v.case_id=c.id),'[]'),
  'acts',coalesce((select jsonb_agg(to_jsonb(a) order by a.observed_at,a.created_at) from public.clinical_procedure_acts a where case_id=c.id),'[]'),
  'authorizations',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('revoked',(select to_jsonb(r) from public.person_procedure_revocations r where r.authorization_id=a.id))) from public.person_procedure_authorizations a where case_id=c.id),'[]')
 );
end$$;

revoke all on function public.clinical_vitals_add(uuid,jsonb,text) from public,anon;
grant execute on function public.clinical_vitals_add(uuid,jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;
