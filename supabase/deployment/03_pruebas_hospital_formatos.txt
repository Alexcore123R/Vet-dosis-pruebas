-- ETAPA 3: solo proyecto de pruebas wtrelwtztkddfktrfdpb, después de etapas 1 y 2.
-- Hospitalización, plantillas y hojas clínicas. Sin pacientes, dosis o firmas reales.
begin;

-- existing_hospital_m5.sql

create table public.hospital_stays (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,patient_id uuid not null,
 cage text not null check(length(btrim(cage)) between 1 and 80),
 admitted_at timestamptz not null default now(),admitted_by uuid not null references auth.users(id),
 discharged_at timestamptz,discharged_by uuid references auth.users(id),discharge_reason text,
 version integer not null default 1,unique(clinic_id,id),
 foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id)
);
create unique index hospital_cage_occupied on public.hospital_stays(clinic_id,lower(btrim(cage))) where discharged_at is null;
create unique index hospital_patient_admitted on public.hospital_stays(clinic_id,patient_id) where discharged_at is null;
create table public.hospital_tasks (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,stay_id uuid not null,
 kind text not null check(kind in ('medicacion','revision')),
 label text not null check(length(btrim(label)) between 1 and 300),
 instructions text not null check(length(btrim(instructions)) between 1 and 4000),
 due_at timestamptz not null,escalation_minutes integer not null check(escalation_minutes between 1 and 120),
 state text not null default 'pending' check(state in ('pending','done','cancelled')),
 version integer not null default 1,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 performed_by uuid references auth.users(id),performed_at timestamptz,
 snoozed_until timestamptz,snooze_count integer not null default 0 check(snooze_count between 0 and 3),snooze_reason text,
 cancelled_by uuid references auth.users(id),cancelled_at timestamptz,cancel_reason text,
 foreign key(clinic_id,stay_id) references public.hospital_stays(clinic_id,id)
);
create index hospital_tasks_sheet on public.hospital_tasks(clinic_id,stay_id,due_at);
revoke all on public.hospital_stays,public.hospital_tasks from public,anon,authenticated;
grant select on public.hospital_stays,public.hospital_tasks to authenticated;
alter table public.hospital_stays enable row level security;
alter table public.hospital_tasks enable row level security;
create policy hospital_stay_read on public.hospital_stays for select to authenticated using(private.has_clinic_role(clinic_id,array['admin','mvz','auxiliar']));
create policy hospital_task_read on public.hospital_tasks for select to authenticated using(private.has_clinic_role(clinic_id,array['admin','mvz','auxiliar']));
create function public.hospital_snapshot(p_clinic_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic_id,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return jsonb_build_object('stays',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('vet_patients',jsonb_build_object('name',p.name,'species',p.species)) order by s.cage) from public.hospital_stays s join public.vet_patients p on p.id=s.patient_id and p.clinic_id=s.clinic_id where s.clinic_id=p_clinic_id and s.discharged_at is null),'[]'::jsonb),
 'tasks',coalesce((select jsonb_agg(to_jsonb(t) order by t.due_at) from public.hospital_tasks t join public.hospital_stays s on s.id=t.stay_id and s.clinic_id=t.clinic_id where t.clinic_id=p_clinic_id and s.discharged_at is null),'[]'::jsonb));
end $$;
create function public.hospital_admit(p_clinic_id uuid,p_patient_id uuid,p_cage text,p_operation_id text)
returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;fp jsonb;
begin
 if not private.has_clinic_role(p_clinic_id,array['admin','mvz']) then raise exception 'physician_required';end if;
 fp=jsonb_build_object('kind','hospital_admit','patient',p_patient_id,'cage',p_cage);
 id=private.vet_receipt(p_clinic_id,p_operation_id,fp);if id is not null then return id;end if;
 if p_cage is null or length(btrim(p_cage)) not between 1 and 80 then raise exception 'invalid_cage';end if;
 if not exists(select 1 from public.vet_patients where clinic_id=p_clinic_id and vet_patients.id=p_patient_id) then raise exception 'patient_wrong_clinic';end if;
 insert into public.hospital_stays(clinic_id,patient_id,cage,admitted_by) values(p_clinic_id,p_patient_id,btrim(p_cage),auth.uid()) returning hospital_stays.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic_id,p_operation_id,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic_id,auth.uid(),'hospital_admitted',id);
 return id;
end $$;
create function public.hospital_prescribe(p_clinic_id uuid,p_stay_id uuid,p_kind text,p_label text,p_instructions text,p_times jsonb,p_escalation_minutes integer,p_operation_id text)
returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;fp jsonb;stay public.hospital_stays;instant jsonb;due timestamptz;first_id uuid;
begin
 if not private.has_clinic_role(p_clinic_id,array['admin','mvz']) then raise exception 'physician_required';end if;
 fp=jsonb_build_object('kind','hospital_prescribe','stay',p_stay_id,'type',p_kind,'label',p_label,'instructions',p_instructions,'times',p_times,'escalation',p_escalation_minutes);
 id=private.vet_receipt(p_clinic_id,p_operation_id,fp);if id is not null then return id;end if;
 select * into stay from public.hospital_stays where clinic_id=p_clinic_id and hospital_stays.id=p_stay_id for update;
 if not found or stay.discharged_at is not null then raise exception 'stay_inactive';end if;
 if p_kind is null or p_kind not in ('medicacion','revision') or p_label is null or length(btrim(p_label)) not between 1 and 300 or p_instructions is null or length(btrim(p_instructions)) not between 1 and 4000 then raise exception 'invalid_order';end if;
 if p_escalation_minutes is null or p_escalation_minutes not between 1 and 120 then raise exception 'invalid_escalation';end if;
 if jsonb_typeof(p_times) is distinct from 'array' then raise exception 'invalid_times';end if;
 if jsonb_array_length(p_times) not between 1 and 200 then raise exception 'invalid_times';end if;
 for instant in select * from jsonb_array_elements(p_times) loop
  if jsonb_typeof(instant) is distinct from 'string' or (instant#>>'{}') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$' then raise exception 'invalid_instant';end if;
  due=(instant#>>'{}')::timestamptz;
  if due<=now() then raise exception 'past_order_time';end if;
 end loop;
 if (select count(distinct (x#>>'{}')::timestamptz) from jsonb_array_elements(p_times) x)<>jsonb_array_length(p_times) then raise exception 'duplicate_times';end if;
 for instant in select * from jsonb_array_elements(p_times) loop
  insert into public.hospital_tasks(clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by)
  values(p_clinic_id,p_stay_id,p_kind,btrim(p_label),btrim(p_instructions),(instant#>>'{}')::timestamptz,p_escalation_minutes,auth.uid()) returning hospital_tasks.id into id;
  first_id=coalesce(first_id,id);
  insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic_id,auth.uid(),'hospital_task_prescribed',id);
 end loop;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic_id,p_operation_id,fp,first_id);
 return first_id;
end $$;
create function public.hospital_task_action(p_clinic_id uuid,p_task_id uuid,p_expected_version integer,p_action text,p_minutes integer default null,p_reason text default null)
returns void language plpgsql security definer set search_path='' as $$
declare task public.hospital_tasks;stay public.hospital_stays;stay_id uuid;
begin
 if not private.has_clinic_role(p_clinic_id,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 if p_action is null or p_action not in ('perform','snooze','cancel') then raise exception 'invalid_action';end if;
 select t.stay_id into stay_id from public.hospital_tasks t where t.clinic_id=p_clinic_id and t.id=p_task_id;
 if stay_id is null then raise exception 'task_not_found';end if;
 -- All mutations lock the stay before tasks, including discharge.
 select * into stay from public.hospital_stays s where s.id=stay_id and s.clinic_id=p_clinic_id for update;
 select * into task from public.hospital_tasks t where t.id=p_task_id and t.clinic_id=p_clinic_id for update;
 if p_action='perform' and task.state='done' and task.performed_by=auth.uid() then return;end if;
 if stay.discharged_at is not null then raise exception 'stay_inactive';end if;
 if task.state<>'pending' then raise exception 'task_not_pending';end if;
 if p_expected_version is null or task.version<>p_expected_version then raise exception 'version_conflict';end if;
 if p_action='perform' then
  -- Scheduling does not authorize an early administration.
  if task.due_at>now() then raise exception 'task_not_due';end if;
  update public.hospital_tasks set state='done',performed_by=auth.uid(),performed_at=now(),version=version+1 where id=p_task_id;
 elsif p_action='snooze' then
  if task.due_at>now() then raise exception 'task_not_due';end if;
  if task.snooze_count>=3 then raise exception 'snooze_limit';end if;
  if p_minutes is null or p_minutes not between 1 and 30 or p_reason is null or length(btrim(p_reason)) not between 1 and 500 then raise exception 'invalid_snooze';end if;
  update public.hospital_tasks set snoozed_until=now()+make_interval(mins=>p_minutes),snooze_count=snooze_count+1,snooze_reason=btrim(p_reason),version=version+1 where id=p_task_id;
 else
  if not private.has_clinic_role(p_clinic_id,array['admin','mvz']) then raise exception 'physician_required';end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 500 then raise exception 'reason_required';end if;
  update public.hospital_tasks set state='cancelled',cancelled_by=auth.uid(),cancelled_at=now(),cancel_reason=btrim(p_reason),version=version+1 where id=p_task_id;
 end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic_id,auth.uid(),'hospital_task_'||p_action,p_task_id);
end $$;
create function public.hospital_discharge(p_clinic_id uuid,p_stay_id uuid,p_expected_version integer,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare stay public.hospital_stays;
begin
 if not private.has_clinic_role(p_clinic_id,array['admin','mvz']) then raise exception 'physician_required';end if;
 if p_reason is null or length(btrim(p_reason)) not between 1 and 500 then raise exception 'reason_required';end if;
 select * into stay from public.hospital_stays where clinic_id=p_clinic_id and id=p_stay_id for update;
 if not found or stay.discharged_at is not null then raise exception 'stay_inactive';end if;
 if p_expected_version is null or stay.version<>p_expected_version then raise exception 'version_conflict';end if;
 update public.hospital_stays set discharged_at=now(),discharged_by=auth.uid(),discharge_reason=btrim(p_reason),version=version+1 where id=p_stay_id;
 update public.hospital_tasks set state='cancelled',cancelled_by=auth.uid(),cancelled_at=now(),cancel_reason='Alta: '||btrim(p_reason),version=version+1 where stay_id=p_stay_id and clinic_id=p_clinic_id and state='pending';
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic_id,auth.uid(),'hospital_discharged',p_stay_id);
end $$;
revoke all on function public.hospital_snapshot(uuid),public.hospital_admit(uuid,uuid,text,text),public.hospital_prescribe(uuid,uuid,text,text,text,jsonb,integer,text),public.hospital_task_action(uuid,uuid,integer,text,integer,text),public.hospital_discharge(uuid,uuid,integer,text) from public,anon;
grant execute on function public.hospital_snapshot(uuid),public.hospital_admit(uuid,uuid,text,text),public.hospital_prescribe(uuid,uuid,text,text,text,jsonb,integer,text),public.hospital_task_action(uuid,uuid,integer,text,integer,text),public.hospital_discharge(uuid,uuid,integer,text) to authenticated;


-- existing_forms_phase1.sql

create table public.form_templates (
 id uuid primary key default gen_random_uuid(),clinic_id uuid references public.clinics(id),
 responsible_id uuid references auth.users(id),created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),unique(clinic_id,id)
);
create table public.form_template_versions (
 id uuid primary key default gen_random_uuid(),template_id uuid not null references public.form_templates(id),
 clinic_id uuid references public.clinics(id),responsible_id uuid references auth.users(id),
 version integer not null check(version>0),base_version_id uuid references public.form_template_versions(id),
 schema jsonb not null,approved boolean not null default false,
 source_status text not null default 'sin verificar' check(source_status in ('verificada','sin verificar')),
 reason text not null,created_by uuid references auth.users(id),created_at timestamptz not null default now(),
 unique(template_id,version),unique(clinic_id,id)
);
create table public.form_documents (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,patient_id uuid not null,
 version_id uuid not null,responsible_id uuid not null references auth.users(id),
 assigned_aux_id uuid references auth.users(id),state text not null default 'draft' check(state in ('draft','awaiting_review','ready','signed')),
 revision integer not null default 1,values jsonb not null,branding jsonb not null,snapshot jsonb not null,
 content_hash text,pdf_hash text,prepared_at timestamptz,accepted_at timestamptz,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(clinic_id,id),foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id),
 foreign key(clinic_id,version_id) references public.form_template_versions(clinic_id,id)
);
create table public.form_signatures (
 id uuid primary key default gen_random_uuid(),document_id uuid not null references public.form_documents(id),
 role text not null check(role in ('tutor','mvz')),name text not null,identification_number text not null,
 points jsonb not null,image bytea,image_hash text,captured_at timestamptz not null default now(),
 unique(document_id,role)
);
-- Binary artifacts are PRIVATE Postgres data in this phase, not publicly accessible Storage objects.
-- This permits an atomic PDF+hash registration. Limit 2 MB per PDF.
create table private.form_artifacts (
 document_id uuid primary key references public.form_documents(id),revision integer not null,
 content_hash text not null,pdf bytea not null,pdf_hash text not null,
 renderer_version text not null,created_at timestamptz not null default now()
);
create index form_docs_clinic on public.form_documents(clinic_id,created_at desc);
revoke all on public.form_templates,public.form_template_versions,public.form_documents,public.form_signatures from public,anon,authenticated;
revoke all on private.form_artifacts from public,anon,authenticated;
grant select on public.form_templates,public.form_template_versions,public.form_documents,public.form_signatures to authenticated;
alter table public.form_templates enable row level security;
alter table public.form_template_versions enable row level security;
alter table public.form_documents enable row level security;
alter table public.form_signatures enable row level security;
create function private.form_readable(d public.form_documents) returns boolean language sql stable security definer set search_path='' as $$
 select private.has_clinic_role(d.clinic_id,array['admin']) or
 (d.responsible_id=auth.uid() and private.has_clinic_role(d.clinic_id,array['mvz'])) or
 (d.assigned_aux_id=auth.uid() and d.state='draft' and private.has_clinic_role(d.clinic_id,array['auxiliar']));
$$;
revoke all on function private.form_readable(public.form_documents) from public;
grant execute on function private.form_readable(public.form_documents) to authenticated;
create policy form_template_read on public.form_templates for select to authenticated using(clinic_id is null or private.has_clinic_role(clinic_id,array['admin','mvz','auxiliar']));
create policy form_version_read on public.form_template_versions for select to authenticated using(clinic_id is null or private.has_clinic_role(clinic_id,array['admin','mvz','auxiliar']));
create policy form_document_read on public.form_documents for select to authenticated using(private.form_readable(form_documents));
create policy form_signature_read on public.form_signatures for select to authenticated using(exists(select 1 from public.form_documents d where d.id=document_id and (private.has_clinic_role(d.clinic_id,array['admin']) or (d.responsible_id=auth.uid() and private.has_clinic_role(d.clinic_id,array['mvz'])))));
create function private.form_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_table_name='form_template_versions' then raise exception 'version_is_immutable';end if;
 if tg_table_name='form_documents' then
  if old.state='signed' then raise exception 'signed_document_is_immutable';end if;
 end if;
 if tg_table_name in ('form_signatures','form_artifacts') then
  if exists(select 1 from public.form_documents where id=old.document_id and state='signed') then raise exception 'signed_artifact_is_immutable';end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
create trigger form_version_immutable before update or delete on public.form_template_versions for each row execute function private.form_guard();
create trigger form_document_immutable before update or delete on public.form_documents for each row execute function private.form_guard();
create trigger form_signature_immutable before update or delete on public.form_signatures for each row execute function private.form_guard();
create trigger form_artifact_immutable before update or delete on private.form_artifacts for each row execute function private.form_guard();

create function private.form_validate_schema(s jsonb) returns void language plpgsql set search_path='' as $$
declare f jsonb;c jsonb;ids text[]='{}';keys text[]='{}';k text;canonical jsonb;rev jsonb;
begin
 if jsonb_typeof(s) is distinct from 'object' or octet_length(s::text)>60000 or s->>'type' is null or s->>'type' not in ('general','surgery','euthanasia','early_discharge','hospital') or jsonb_typeof(s->'title') is distinct from 'string' or coalesce(length(btrim(s->>'title')),0) not between 1 and 200 then raise exception 'invalid_template';end if;
 if jsonb_typeof(s->'fields') is distinct from 'array' or jsonb_typeof(s->'clauses') is distinct from 'array' then raise exception 'invalid_template';end if;
 if jsonb_array_length(s->'fields')>80 or jsonb_array_length(s->'clauses')>40 then raise exception 'invalid_template';end if;
 for f in select * from jsonb_array_elements(s->'fields') loop
  if jsonb_typeof(f->'id') is distinct from 'string' or jsonb_typeof(f->'label') is distinct from 'string' or f->>'id' is null or f->>'id' !~ '^[a-z][a-z0-9_]{0,63}$' or f->>'id'=any(ids) or f->>'type' is null or f->>'type' not in ('text','date','checkbox','single','multiple','table','number','binding','signature') or coalesce(length(btrim(f->>'label')),0) not between 1 and 200 or jsonb_typeof(f->'required') is distinct from 'boolean' or jsonb_typeof(f->'locked') is distinct from 'boolean' then raise exception 'invalid_field';end if;
  ids=array_append(ids,f->>'id');
  if f->>'type' in ('single','multiple') then
   if jsonb_typeof(f->'options') is distinct from 'array' then raise exception 'invalid_options';end if;
   if jsonb_array_length(f->'options') not between 1 and 40 or exists(select 1 from jsonb_array_elements(f->'options') o where jsonb_typeof(o)<>'string' or length(btrim(o#>>'{}')) not between 1 and 200) or (select count(distinct o) from jsonb_array_elements(f->'options') o)<>jsonb_array_length(f->'options') then raise exception 'invalid_options';end if;
  end if;
  if f->>'type'='table' then
   if jsonb_typeof(f->'columns') is distinct from 'array' then raise exception 'invalid_columns';end if;
   if jsonb_array_length(f->'columns') not between 1 and 12 or exists(select 1 from jsonb_array_elements(f->'columns') o where jsonb_typeof(o)<>'string' or length(btrim(o#>>'{}')) not between 1 and 100) or (select count(distinct o) from jsonb_array_elements(f->'columns') o)<>jsonb_array_length(f->'columns') then raise exception 'invalid_columns';end if;
  end if;
 end loop;
 -- Mandatory definitions come from the installed base, not client-controlled flags.
 select b.schema into canonical from public.form_template_versions b
 where b.clinic_id is null and b.schema->>'type'=s->>'type'
 and (s->'fields') @> (select coalesce(jsonb_agg(value),'[]') from jsonb_array_elements(b.schema->'fields') where value->'locked'='true'::jsonb)
 and (s->'clauses') @> (select coalesce(jsonb_agg(value),'[]') from jsonb_array_elements(b.schema->'clauses') where value->'locked'='true'::jsonb)
 order by b.version desc limit 1;
 if canonical is null then raise exception 'protected_field_changed';end if;
 if canonical is not null then
  for f in select * from jsonb_array_elements(canonical->'fields') where (value->>'locked')::boolean loop
   if not exists(select 1 from jsonb_array_elements(s->'fields') n where n=f) then raise exception 'protected_field_changed';end if;
  end loop;
 end if;
 foreach k in array array['patient','owner','mvz_name','mvz_license','signer_name','signer_id','privacy_url','signature'] loop
  if not exists(select 1 from jsonb_array_elements(s->'fields') as item(value) where item.value->>'id'=k and item.value->'locked'='true'::jsonb and item.value->'required'='true'::jsonb) then raise exception 'protected_field_missing';end if;
 end loop;
 for c in select * from jsonb_array_elements(s->'clauses') loop
  if jsonb_typeof(c->'id') is distinct from 'string' or jsonb_typeof(c->'text') is distinct from 'string' or c->>'id' is null or c->>'id'=any(keys) or coalesce(length(btrim(c->>'text')),0) not between 1 and 12000 or jsonb_typeof(c->'locked') is distinct from 'boolean' or c->>'text' ~* '\mirrevocable\M' then raise exception 'invalid_clause';end if;
  keys=array_append(keys,c->>'id');
  if c->>'id'='revocation' and c->'locked'='true'::jsonb then rev=c;end if;
 end loop;
 if rev is null then raise exception 'revocation_required';end if;
 if canonical is not null and rev<>(select value from jsonb_array_elements(canonical->'clauses') where value->>'id'='revocation') then raise exception 'protected_clause_changed';end if;
 if s->>'type'='euthanasia' and not ids @> array['clinical_reason','prior_opinion','method','body_disposition','cost'] then raise exception 'euthanasia_fields_required';end if;
end $$;

create function private.form_validate_values(s jsonb,v jsonb,complete boolean) returns void language plpgsql set search_path='' as $$
declare f jsonb;x jsonb;k text;r jsonb;d date;
begin
 if jsonb_typeof(v) is distinct from 'object' or octet_length(v::text)>200000 then raise exception 'invalid_values';end if;
 for k,x in select * from jsonb_each(v) loop
  select value into f from jsonb_array_elements(s->'fields') where value->>'id'=k;
  if f is null or f->>'type' in ('binding','signature') then raise exception 'field_not_editable';end if;
  case f->>'type'
  when 'checkbox' then if jsonb_typeof(x)<>'boolean' then raise exception 'invalid_checkbox';end if;
  when 'multiple' then
   if jsonb_typeof(x)<>'array' then raise exception 'invalid_selection';end if;
   if exists(select 1 from jsonb_array_elements(x) a where not (f->'options') @> jsonb_build_array(a)) or (select count(distinct a) from jsonb_array_elements(x) a)<>jsonb_array_length(x) then raise exception 'invalid_selection';end if;
  when 'table' then
   if jsonb_typeof(x)<>'array' or jsonb_array_length(x)>100 then raise exception 'invalid_table';end if;
   for r in select * from jsonb_array_elements(x) loop
    if jsonb_typeof(r)<>'array' or jsonb_array_length(r)<>jsonb_array_length(f->'columns') then raise exception 'invalid_table';end if;
    if exists(select 1 from jsonb_array_elements(r) cell where jsonb_typeof(cell)<>'string' or length(cell#>>'{}')>1000) then raise exception 'invalid_table';end if;
   end loop;
  else
   if jsonb_typeof(x)<>'string' or length(x#>>'{}')>12000 then raise exception 'invalid_text';end if;
   if f->>'type'='single' and x#>>'{}'<>'' and not (f->'options') @> jsonb_build_array(x) then raise exception 'invalid_selection';end if;
   if f->>'type'='number' and x#>>'{}'<>'' and x#>>'{}' !~ '^-?\d{1,12}(\.\d{1,9})?$' then raise exception 'invalid_number';end if;
   if f->>'type'='date' and x#>>'{}'<>'' then
    if x#>>'{}' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid_date';end if;
    d=(x#>>'{}')::date;
   end if;
   if k='privacy_url' and x#>>'{}'<>'' and x#>>'{}' !~ '^https://[^ /]+(/.*)?$' then raise exception 'invalid_privacy_url';end if;
  end case;
 end loop;
 if complete then
  for f in select * from jsonb_array_elements(s->'fields') where value->'required'='true'::jsonb and value->>'type' not in ('binding','signature') loop
   x=v->(f->>'id');
   if x is null or x='null'::jsonb or x='false'::jsonb or x='[]'::jsonb or (jsonb_typeof(x)='string' and btrim(x#>>'{}')='') then raise exception 'required_field_missing';end if;
  end loop;
 end if;
end $$;
create function private.form_validate_brand(b jsonb) returns void language plpgsql set search_path='' as $$
begin
 if jsonb_typeof(b) is distinct from 'object' or octet_length(b::text)>400000 or exists(select 1 from jsonb_object_keys(b) k where k not in ('header','logo','include_logo')) then raise exception 'invalid_branding';end if;
 if b->'header' is not null and (jsonb_typeof(b->'header')<>'string' or length(b->>'header')>2000) then raise exception 'invalid_branding';end if;
 if b->'include_logo' is not null and jsonb_typeof(b->'include_logo')<>'boolean' then raise exception 'invalid_branding';end if;
 if b->'logo' is not null and jsonb_typeof(b->'logo')<>'string' then raise exception 'invalid_branding';end if;
end $$;
create function public.form_templates_list(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(v)) from public.form_template_versions v where (v.clinic_id is null or v.clinic_id=p_clinic) and v.version=(select max(v2.version) from public.form_template_versions v2 where v2.template_id=v.template_id)),'[]');
end $$;
create function public.form_template_save(p_clinic uuid,p_template uuid,p_expected integer,p_base uuid,p_schema jsonb,p_approved boolean,p_reason text,p_operation text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.form_templates;v public.form_template_versions;current_v public.form_template_versions;id uuid;fp jsonb;base public.form_template_versions;
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz']) then raise exception 'template_editor_required';end if;
 if coalesce(length(btrim(p_reason)),0) not between 1 and 500 or p_approved is null then raise exception 'reason_required';end if;
 perform private.form_validate_schema(p_schema);
 fp=jsonb_build_object('kind','form_template','template',p_template,'expected',p_expected,'base',p_base,'schema',p_schema,'approved',p_approved,'reason',p_reason);
 id=private.vet_receipt(p_clinic,p_operation,fp);
 if id is not null then select * into v from public.form_template_versions where form_template_versions.id=id;return to_jsonb(v);end if;
 if p_base is not null then
  select * into base from public.form_template_versions where form_template_versions.id=p_base and clinic_id is null;
  if not found or base.schema->>'type'<>p_schema->>'type' then raise exception 'invalid_base';end if;
  if not (p_schema->'fields') @> (select coalesce(jsonb_agg(value),'[]') from jsonb_array_elements(base.schema->'fields') where value->'locked'='true'::jsonb) or not (p_schema->'clauses') @> (select coalesce(jsonb_agg(value),'[]') from jsonb_array_elements(base.schema->'clauses') where value->'locked'='true'::jsonb) then raise exception 'protected_field_changed';end if;
 end if;
 if p_template is null then
  insert into public.form_templates(clinic_id,responsible_id,created_by) values(p_clinic,auth.uid(),auth.uid()) returning * into t;
 else
  select * into t from public.form_templates where form_templates.id=p_template and clinic_id=p_clinic for update;
  if not found then raise exception 'template_not_in_clinic';end if;
  if not private.has_clinic_role(p_clinic,array['admin']) and t.responsible_id<>auth.uid() then raise exception 'responsible_editor_required';end if;
  select * into current_v from public.form_template_versions where template_id=t.id order by version desc limit 1;
  if p_expected is distinct from current_v.version then raise exception 'template_version_conflict';end if;
  if p_schema->>'type'<>current_v.schema->>'type' or p_base is distinct from current_v.base_version_id then raise exception 'template_origin_changed';end if;
  if not (p_schema->'fields') @> (select coalesce(jsonb_agg(value),'[]') from jsonb_array_elements(current_v.schema->'fields') where value->'locked'='true'::jsonb) or not (p_schema->'clauses') @> (select coalesce(jsonb_agg(value),'[]') from jsonb_array_elements(current_v.schema->'clauses') where value->'locked'='true'::jsonb) then raise exception 'protected_field_changed';end if;
 end if;
 insert into public.form_template_versions(template_id,clinic_id,responsible_id,version,base_version_id,schema,approved,reason,created_by)
 values(t.id,p_clinic,t.responsible_id,coalesce(current_v.version,0)+1,p_base,p_schema,p_approved,p_reason,auth.uid()) returning * into v;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'form_template_version_created',v.id,jsonb_build_object('template',t.id,'version',v.version,'approved',v.approved,'reason',p_reason));
 return to_jsonb(v);
end $$;
create function public.form_documents_list(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc) from public.form_documents d where d.clinic_id=p_clinic and private.form_readable(d)),'[]');
end $$;
create function public.form_document_create(p_clinic uuid,p_patient uuid,p_version uuid,p_values jsonb,p_branding jsonb,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.form_template_versions;p public.vet_patients;o public.vet_owners;d public.form_documents;id uuid;fp jsonb;s jsonb;
begin
 if not private.has_clinic_role(p_clinic,array['mvz']) then raise exception 'responsible_mvz_required';end if;
 select * into v from public.form_template_versions where form_template_versions.id=p_version and clinic_id=p_clinic and approved;
 if not found then raise exception 'approved_clinic_template_required';end if;
 perform private.form_validate_values(v.schema,p_values,false);perform private.form_validate_brand(p_branding);
 fp=jsonb_build_object('kind','form_document','patient',p_patient,'version',p_version,'values',p_values,'branding',p_branding);
 id=private.vet_receipt(p_clinic,p_operation,fp);
 if id is not null then select * into d from public.form_documents where form_documents.id=id;return to_jsonb(d);end if;
 select * into p from public.vet_patients where vet_patients.id=p_patient and clinic_id=p_clinic;
 if not found or p.owner_id is null then raise exception 'patient_and_owner_required';end if;
 select * into o from public.vet_owners where vet_owners.id=p.owner_id and clinic_id=p_clinic;
 s=jsonb_build_object('schema',v.schema,'template_version',v.version,'patient',jsonb_build_object('id',p.id,'name',p.name,'species',p.species,'breed',p.breed,'sex',p.sex),'owner',jsonb_build_object('id',o.id,'name',o.name),'clinic_name',(select name from public.clinics where clinics.id=p_clinic));
 insert into public.form_documents(clinic_id,patient_id,version_id,responsible_id,values,branding,snapshot,created_by) values(p_clinic,p_patient,p_version,auth.uid(),p_values,p_branding,s,auth.uid()) returning * into d;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,d.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'form_document_draft_created',d.id);
 return to_jsonb(d);
end $$;
create function public.form_document_save(p_id uuid,p_revision integer,p_values jsonb,p_branding jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;
begin
 select * into d from public.form_documents where id=p_id for update;
 if not found or not private.form_readable(d) or d.state='signed' then raise exception 'document_not_editable';end if;
 if d.revision is distinct from p_revision then raise exception 'document_revision_conflict';end if;
 if d.responsible_id<>auth.uid() and not (d.assigned_aux_id=auth.uid() and d.state='draft') then raise exception 'responsible_or_assigned_required';end if;
 perform private.form_validate_values(d.snapshot->'schema',p_values,false);perform private.form_validate_brand(p_branding);
 delete from public.form_signatures where document_id=d.id;
 delete from private.form_artifacts where document_id=d.id;
 update public.form_documents set values=p_values,branding=p_branding,snapshot=snapshot-array['document_id','values','branding','prepared_at','tutor_signature','mvz_signature'],state='draft',revision=revision+1,content_hash=null,pdf_hash=null,prepared_at=null where id=d.id returning * into d;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(d.clinic_id,auth.uid(),'form_document_draft_changed',d.id,jsonb_build_object('revision',d.revision));return to_jsonb(d);
end $$;
create function private.form_validate_signature(points jsonb) returns void language plpgsql set search_path='' as $$
declare p jsonb;first_p jsonb;previous_p jsonb;moved boolean=false;drawn boolean=false;n integer=0;
begin
 if jsonb_typeof(points) is distinct from 'array' then raise exception 'invalid_signature';end if;
 if jsonb_array_length(points) not between 2 and 5000 then raise exception 'invalid_signature';end if;
 for p in select * from jsonb_array_elements(points) loop
  if p='null'::jsonb then previous_p=null;continue;end if;
  if jsonb_typeof(p)<>'array' or jsonb_array_length(p)<>2 or jsonb_typeof(p->0)<>'number' or jsonb_typeof(p->1)<>'number' then raise exception 'invalid_signature';end if;
  if (p->>0)::numeric not between 0 and 1 or (p->>1)::numeric not between 0 and 1 then raise exception 'invalid_signature';end if;
  if first_p is null then first_p=p;end if;
  if abs((p->>0)::numeric-(first_p->>0)::numeric)+abs((p->>1)::numeric-(first_p->>1)::numeric)>0.005 then moved=true;end if;
  if previous_p is not null and (abs((p->>0)::numeric-(previous_p->>0)::numeric)>1.0/599 or abs((p->>1)::numeric-(previous_p->>1)::numeric)>1.0/179) then drawn=true;end if;
  previous_p=p;n=n+1;
 end loop;
 if n<2 or not moved or not drawn then raise exception 'signature_required';end if;
end $$;
create function public.form_document_prepare(p_id uuid,p_revision integer,p_tutor_signature jsonb,p_mvz_signature jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;time timestamptz=clock_timestamp();s jsonb;
begin
 select * into d from public.form_documents where id=p_id for update;
 if not found or d.responsible_id<>auth.uid() or not private.has_clinic_role(d.clinic_id,array['mvz']) then raise exception 'responsible_mvz_required';end if;
 if d.state<>'draft' or d.revision is distinct from p_revision then raise exception 'document_revision_conflict';end if;
 perform private.form_validate_values(d.snapshot->'schema',d.values,true);
 perform private.form_validate_signature(p_tutor_signature);perform private.form_validate_signature(p_mvz_signature);
 s=d.snapshot||jsonb_build_object('document_id',d.id,'values',d.values,'branding',d.branding,'prepared_at',time,'tutor_signature',p_tutor_signature,'mvz_signature',p_mvz_signature);
 insert into public.form_signatures(document_id,role,name,identification_number,points,captured_at) values(d.id,'tutor',d.values->>'signer_name',d.values->>'signer_id',p_tutor_signature,time),(d.id,'mvz',d.values->>'mvz_name',d.values->>'mvz_license',p_mvz_signature,time);
 update public.form_documents set state='awaiting_review',revision=revision+1,snapshot=s,prepared_at=time,content_hash=encode(sha256(convert_to(s::text,'UTF8')),'hex') where id=d.id returning * into d;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(d.clinic_id,auth.uid(),'form_document_prepared_for_review',d.id);return to_jsonb(d);
end $$;
create function public.form_document_snapshot(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.form_documents;
begin
 select * into d from public.form_documents where id=p_id;
 if not found or not private.form_readable(d) or d.assigned_aux_id=auth.uid() then raise exception 'document_access_denied';end if;
 return to_jsonb(d);
end $$;
create function public.form_read_pdf(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.form_documents;a private.form_artifacts;
begin
 select * into d from public.form_documents where id=p_id;
 if not found or not private.form_readable(d) or d.assigned_aux_id=auth.uid() then raise exception 'document_access_denied';end if;
 select * into a from private.form_artifacts where document_id=p_id and revision=d.revision and content_hash=d.content_hash;
 if not found then return null;end if;
 return jsonb_build_object('pdf',encode(a.pdf,'base64'),'hash',a.pdf_hash);
end $$;
-- Only the trusted renderer can register artifacts; caller still needs a fresh authenticated read.
create function public.form_register_pdf(p_id uuid,p_revision integer,p_content_hash text,p_pdf text,p_tutor_png text,p_mvz_png text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;bytes bytea;t bytea;m bytea;hash text;a private.form_artifacts;
begin
 select * into d from public.form_documents where id=p_id for update;
 if not found or d.revision is distinct from p_revision or d.content_hash is distinct from p_content_hash then raise exception 'stale_pdf';end if;
 select * into a from private.form_artifacts where document_id=p_id;
 if found then return jsonb_build_object('pdf',encode(a.pdf,'base64'),'hash',a.pdf_hash);end if;
 if d.state<>'awaiting_review' then raise exception 'document_not_prepared';end if;
 if length(p_pdf)>2800000 or length(p_tutor_png)>300000 or length(p_mvz_png)>300000 then raise exception 'artifact_too_large';end if;
 bytes=decode(p_pdf,'base64');t=decode(p_tutor_png,'base64');m=decode(p_mvz_png,'base64');
 if octet_length(bytes) not between 5 and 2097152 or substring(bytes from 1 for 5)<>convert_to('%PDF-','UTF8') or substring(t from 1 for 8)<>decode('89504e470d0a1a0a','hex') or substring(m from 1 for 8)<>decode('89504e470d0a1a0a','hex') then raise exception 'invalid_artifact';end if;
 hash=encode(sha256(bytes),'hex');
 insert into private.form_artifacts values(p_id,d.revision,d.content_hash,bytes,hash,'vetdosis-pdf-1',clock_timestamp());
 update public.form_signatures set image=case role when 'tutor' then t else m end,image_hash=encode(sha256(case role when 'tutor' then t else m end),'hex') where document_id=p_id;
 update public.form_documents set state='ready',pdf_hash=hash where id=p_id;
 return jsonb_build_object('pdf',encode(bytes,'base64'),'hash',hash);
end $$;
create function public.form_document_finalize(p_id uuid,p_revision integer,p_pdf_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;
begin
 select * into d from public.form_documents where id=p_id for update;
 if not found or d.responsible_id<>auth.uid() or not private.has_clinic_role(d.clinic_id,array['mvz']) then raise exception 'responsible_mvz_required';end if;
 if d.revision is distinct from p_revision or d.pdf_hash is distinct from p_pdf_hash or p_pdf_hash is null then raise exception 'reviewed_pdf_mismatch';end if;
 if d.state='signed' then return to_jsonb(d);end if;
 if d.state<>'ready' or not exists(select 1 from private.form_artifacts a where a.document_id=d.id and a.revision=d.revision and a.content_hash=d.content_hash and a.pdf_hash=p_pdf_hash and encode(sha256(a.pdf),'hex')=p_pdf_hash) then raise exception 'pdf_not_ready';end if;
 update public.form_documents set state='signed',accepted_at=clock_timestamp() where id=d.id returning * into d;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(d.clinic_id,auth.uid(),'form_document_signed',d.id,jsonb_build_object('pdf_hash',p_pdf_hash,'version',d.version_id));
 return to_jsonb(d);
end $$;
create function public.form_document_assign(p_id uuid,p_aux uuid) returns void language plpgsql security definer set search_path='' as $$
declare d public.form_documents;
begin
 select * into d from public.form_documents where id=p_id for update;
 if not found or d.responsible_id<>auth.uid() or not private.has_clinic_role(d.clinic_id,array['mvz']) or d.state<>'draft' then raise exception 'responsible_mvz_required';end if;
 if p_aux is not null and not exists(select 1 from public.clinic_members where clinic_id=d.clinic_id and user_id=p_aux and role='auxiliar') then raise exception 'auxiliary_not_in_clinic';end if;
 update public.form_documents set assigned_aux_id=p_aux,revision=revision+1 where id=p_id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(d.clinic_id,auth.uid(),'form_document_assigned',d.id);
end $$;
create function public.form_template_preview_check(p_clinic uuid,p_schema jsonb,p_branding jsonb) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz']) then raise exception 'template_editor_required';end if;
 perform private.form_validate_schema(p_schema);perform private.form_validate_brand(p_branding);return true;
end $$;
create table public.clinic_document_settings (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),
 branding jsonb not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp()
);
revoke all on public.clinic_document_settings from public,anon,authenticated;
grant select on public.clinic_document_settings to authenticated;
alter table public.clinic_document_settings enable row level security;
create policy form_settings_read on public.clinic_document_settings for select to authenticated using(private.has_clinic_role(clinic_id,array['admin','mvz','auxiliar']));
create function private.form_settings_guard() returns trigger language plpgsql as $$begin raise exception 'setting_version_is_immutable';end $$;
create trigger form_settings_immutable before update or delete on public.clinic_document_settings for each row execute function private.form_settings_guard();
create function public.form_branding(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return coalesce((select branding from public.clinic_document_settings where clinic_id=p_clinic order by created_at desc,id desc limit 1),jsonb_build_object('header',(select name from public.clinics where id=p_clinic),'include_logo',false));
end $$;
create function public.form_branding_save(p_clinic uuid,p_branding jsonb) returns void language plpgsql security definer set search_path='' as $$
declare id uuid;
begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'clinic_admin_required';end if;
 perform private.form_validate_brand(p_branding);
 insert into public.clinic_document_settings(clinic_id,branding,created_by) values(p_clinic,p_branding,auth.uid()) returning clinic_document_settings.id into id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'form_branding_version_created',id);
end $$;
create function public.form_auxiliaries(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['mvz']) then raise exception 'responsible_mvz_required';end if;
 return coalesce((select jsonb_agg(user_id order by user_id) from public.clinic_members where clinic_id=p_clinic and role='auxiliar'),'[]');
end $$;
-- Explicit privileges: no global write endpoint for the mobile/web application.
do $$ declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname like 'form_%') or (n.nspname='private' and p.proname like 'form_%') loop
  execute 'revoke all on function '||f.signature||' from public,anon,authenticated';
 end loop;
end $$;
grant execute on function private.form_readable(public.form_documents) to authenticated;
grant execute on function public.form_branding(uuid),public.form_branding_save(uuid,jsonb),public.form_auxiliaries(uuid),public.form_template_preview_check(uuid,jsonb,jsonb),public.form_templates_list(uuid),public.form_template_save(uuid,uuid,integer,uuid,jsonb,boolean,text,text),public.form_documents_list(uuid),public.form_document_create(uuid,uuid,uuid,jsonb,jsonb,text),public.form_document_save(uuid,integer,jsonb,jsonb),public.form_document_prepare(uuid,integer,jsonb,jsonb),public.form_document_snapshot(uuid),public.form_read_pdf(uuid),public.form_document_finalize(uuid,integer,text),public.form_document_assign(uuid,uuid) to authenticated;
-- Supabase service_role exists remotely; isolated test harness adds this role explicitly.
grant execute on function public.form_register_pdf(uuid,integer,text,text,text,text) to service_role;

with t as (insert into public.form_templates default values returning id) insert into public.form_template_versions(template_id,version,schema,reason) select id,1,'{"type": "general", "title": "Consentimiento general", "fields": [{"id": "patient", "label": "Paciente", "type": "binding", "required": true, "locked": true}, {"id": "owner", "label": "Propietario registrado", "type": "binding", "required": true, "locked": true}, {"id": "mvz_name", "label": "Nombre del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "mvz_license", "label": "Cédula del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "signer_name", "label": "Nombre del firmante", "type": "text", "required": true, "locked": true}, {"id": "signer_id", "label": "Número de identificación del firmante (sin fotografía)", "type": "text", "required": true, "locked": true}, {"id": "privacy_url", "label": "Enlace al aviso de privacidad", "type": "text", "required": true, "locked": true}, {"id": "signature", "label": "Firmas del tutor y del MVZ", "type": "signature", "required": true, "locked": true}, {"id": "procedure", "label": "Procedimiento o alcance autorizado", "type": "text", "required": true, "locked": false}, {"id": "information", "label": "Información explicada y preguntas del tutor", "type": "text", "required": true, "locked": false}, {"id": "preop_instructions", "label": "Indicaciones de preparación indicadas por el MVZ", "type": "text", "required": false, "locked": false}, {"id": "aftercare", "label": "Indicaciones de recuperación", "type": "text", "required": false, "locked": false}, {"id": "teaching", "label": "Participación docente y supervisión (si corresponde)", "type": "text", "required": false, "locked": false}], "clauses": [{"id": "information", "text": "El MVZ responsable documentará el procedimiento propuesto, sus alternativas y los riesgos identificados para este paciente. El firmante puede formular preguntas antes de decidir. La clínica debe revisar este texto de referencia y adaptarlo a su práctica.", "locked": false}, {"id": "revocation", "text": "Puede comunicar al MVZ responsable su decisión de retirar esta autorización antes del procedimiento. Si el procedimiento ya está en curso, el MVZ explicará las medidas necesarias para atender al animal y registrará la decisión y su alcance.", "locked": true}]}'::jsonb,'Referencia original; requiere revisión de la clínica' from t;

with t as (insert into public.form_templates default values returning id) insert into public.form_template_versions(template_id,version,schema,reason) select id,1,'{"type": "surgery", "title": "Sedación, anestesia y cirugía", "fields": [{"id": "patient", "label": "Paciente", "type": "binding", "required": true, "locked": true}, {"id": "owner", "label": "Propietario registrado", "type": "binding", "required": true, "locked": true}, {"id": "mvz_name", "label": "Nombre del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "mvz_license", "label": "Cédula del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "signer_name", "label": "Nombre del firmante", "type": "text", "required": true, "locked": true}, {"id": "signer_id", "label": "Número de identificación del firmante (sin fotografía)", "type": "text", "required": true, "locked": true}, {"id": "privacy_url", "label": "Enlace al aviso de privacidad", "type": "text", "required": true, "locked": true}, {"id": "signature", "label": "Firmas del tutor y del MVZ", "type": "signature", "required": true, "locked": true}, {"id": "procedure", "label": "Procedimiento o alcance autorizado", "type": "text", "required": true, "locked": false}, {"id": "information", "label": "Información explicada y preguntas del tutor", "type": "text", "required": true, "locked": false}, {"id": "preop_instructions", "label": "Indicaciones de preparación indicadas por el MVZ", "type": "text", "required": false, "locked": false}, {"id": "aftercare", "label": "Indicaciones de recuperación", "type": "text", "required": false, "locked": false}, {"id": "teaching", "label": "Participación docente y supervisión (si corresponde)", "type": "text", "required": false, "locked": false}], "clauses": [{"id": "information", "text": "El MVZ responsable documentará el procedimiento propuesto, sus alternativas y los riesgos identificados para este paciente. El firmante puede formular preguntas antes de decidir. La clínica debe revisar este texto de referencia y adaptarlo a su práctica.", "locked": false}, {"id": "revocation", "text": "Puede comunicar al MVZ responsable su decisión de retirar esta autorización antes del procedimiento. Si el procedimiento ya está en curso, el MVZ explicará las medidas necesarias para atender al animal y registrará la decisión y su alcance.", "locked": true}]}'::jsonb,'Referencia original; requiere revisión de la clínica' from t;

with t as (insert into public.form_templates default values returning id) insert into public.form_template_versions(template_id,version,schema,reason) select id,1,'{"type": "euthanasia", "title": "Consentimiento de eutanasia", "fields": [{"id": "patient", "label": "Paciente", "type": "binding", "required": true, "locked": true}, {"id": "owner", "label": "Propietario registrado", "type": "binding", "required": true, "locked": true}, {"id": "mvz_name", "label": "Nombre del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "mvz_license", "label": "Cédula del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "signer_name", "label": "Nombre del firmante", "type": "text", "required": true, "locked": true}, {"id": "signer_id", "label": "Número de identificación del firmante (sin fotografía)", "type": "text", "required": true, "locked": true}, {"id": "privacy_url", "label": "Enlace al aviso de privacidad", "type": "text", "required": true, "locked": true}, {"id": "signature", "label": "Firmas del tutor y del MVZ", "type": "signature", "required": true, "locked": true}, {"id": "procedure", "label": "Procedimiento o alcance autorizado", "type": "text", "required": true, "locked": false}, {"id": "information", "label": "Información explicada y preguntas del tutor", "type": "text", "required": true, "locked": false}, {"id": "preop_instructions", "label": "Indicaciones de preparación indicadas por el MVZ", "type": "text", "required": false, "locked": false}, {"id": "aftercare", "label": "Indicaciones de recuperación", "type": "text", "required": false, "locked": false}, {"id": "teaching", "label": "Participación docente y supervisión (si corresponde)", "type": "text", "required": false, "locked": false}, {"id": "clinical_reason", "label": "Motivo clínico", "type": "text", "required": true, "locked": true}, {"id": "prior_opinion", "label": "Concepto previo del MVZ", "type": "text", "required": true, "locked": true}, {"id": "method", "label": "Método propuesto por el MVZ", "type": "text", "required": true, "locked": true}, {"id": "body_disposition", "label": "Disposición del cuerpo acordada", "type": "text", "required": true, "locked": true}, {"id": "cost", "label": "Costo y condiciones acordadas", "type": "text", "required": true, "locked": true}], "clauses": [{"id": "information", "text": "El MVZ responsable documentará el procedimiento propuesto, sus alternativas y los riesgos identificados para este paciente. El firmante puede formular preguntas antes de decidir. La clínica debe revisar este texto de referencia y adaptarlo a su práctica.", "locked": false}, {"id": "revocation", "text": "Puede comunicar al MVZ responsable su decisión de retirar esta autorización antes del procedimiento. Si el procedimiento ya está en curso, el MVZ explicará las medidas necesarias para atender al animal y registrará la decisión y su alcance.", "locked": true}]}'::jsonb,'Referencia original; requiere revisión de la clínica' from t;

with t as (insert into public.form_templates default values returning id) insert into public.form_template_versions(template_id,version,schema,reason) select id,1,'{"type": "early_discharge", "title": "Solicitud de alta anticipada", "fields": [{"id": "patient", "label": "Paciente", "type": "binding", "required": true, "locked": true}, {"id": "owner", "label": "Propietario registrado", "type": "binding", "required": true, "locked": true}, {"id": "mvz_name", "label": "Nombre del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "mvz_license", "label": "Cédula del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "signer_name", "label": "Nombre del firmante", "type": "text", "required": true, "locked": true}, {"id": "signer_id", "label": "Número de identificación del firmante (sin fotografía)", "type": "text", "required": true, "locked": true}, {"id": "privacy_url", "label": "Enlace al aviso de privacidad", "type": "text", "required": true, "locked": true}, {"id": "signature", "label": "Firmas del tutor y del MVZ", "type": "signature", "required": true, "locked": true}, {"id": "procedure", "label": "Procedimiento o alcance autorizado", "type": "text", "required": true, "locked": false}, {"id": "information", "label": "Información explicada y preguntas del tutor", "type": "text", "required": true, "locked": false}, {"id": "preop_instructions", "label": "Indicaciones de preparación indicadas por el MVZ", "type": "text", "required": false, "locked": false}, {"id": "aftercare", "label": "Indicaciones de recuperación", "type": "text", "required": false, "locked": false}, {"id": "teaching", "label": "Participación docente y supervisión (si corresponde)", "type": "text", "required": false, "locked": false}], "clauses": [{"id": "information", "text": "El MVZ responsable documentará el procedimiento propuesto, sus alternativas y los riesgos identificados para este paciente. El firmante puede formular preguntas antes de decidir. La clínica debe revisar este texto de referencia y adaptarlo a su práctica.", "locked": false}, {"id": "revocation", "text": "Puede comunicar al MVZ responsable su decisión de retirar esta autorización antes del procedimiento. Si el procedimiento ya está en curso, el MVZ explicará las medidas necesarias para atender al animal y registrará la decisión y su alcance.", "locked": true}]}'::jsonb,'Referencia original; requiere revisión de la clínica' from t;

with t as (insert into public.form_templates default values returning id) insert into public.form_template_versions(template_id,version,schema,reason) select id,1,'{"type": "hospital", "title": "Consentimiento de ingreso hospitalario", "fields": [{"id": "patient", "label": "Paciente", "type": "binding", "required": true, "locked": true}, {"id": "owner", "label": "Propietario registrado", "type": "binding", "required": true, "locked": true}, {"id": "mvz_name", "label": "Nombre del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "mvz_license", "label": "Cédula del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "signer_name", "label": "Nombre del firmante", "type": "text", "required": true, "locked": true}, {"id": "signer_id", "label": "Número de identificación del firmante (sin fotografía)", "type": "text", "required": true, "locked": true}, {"id": "privacy_url", "label": "Enlace al aviso de privacidad", "type": "text", "required": true, "locked": true}, {"id": "signature", "label": "Firmas del tutor y del MVZ", "type": "signature", "required": true, "locked": true}, {"id": "procedure", "label": "Procedimiento o alcance autorizado", "type": "text", "required": true, "locked": false}, {"id": "information", "label": "Información explicada y preguntas del tutor", "type": "text", "required": true, "locked": false}, {"id": "preop_instructions", "label": "Indicaciones de preparación indicadas por el MVZ", "type": "text", "required": false, "locked": false}, {"id": "aftercare", "label": "Indicaciones de recuperación", "type": "text", "required": false, "locked": false}, {"id": "teaching", "label": "Participación docente y supervisión (si corresponde)", "type": "text", "required": false, "locked": false}], "clauses": [{"id": "information", "text": "El MVZ responsable documentará el procedimiento propuesto, sus alternativas y los riesgos identificados para este paciente. El firmante puede formular preguntas antes de decidir. La clínica debe revisar este texto de referencia y adaptarlo a su práctica.", "locked": false}, {"id": "revocation", "text": "Puede comunicar al MVZ responsable su decisión de retirar esta autorización antes del procedimiento. Si el procedimiento ya está en curso, el MVZ explicará las medidas necesarias para atender al animal y registrará la decisión y su alcance.", "locked": true}]}'::jsonb,'Referencia original; requiere revisión de la clínica' from t;



-- existing_forms_phase2.sql

create table public.clinical_cases (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,patient_id uuid not null,
 document_id uuid not null unique,responsible_id uuid not null references auth.users(id),
 kind text not null check(kind in ('clinical_history','surgical_sheet','surgical_risk')),
 title text not null,reason text not null,procedure text,clinical_date date not null,
 asa text,ekg text,antecedents text,notes text,consent_id uuid,
 created_at timestamptz not null default clock_timestamp(),unique(clinic_id,id),
 foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id),
 foreign key(clinic_id,document_id) references public.form_documents(clinic_id,id),
 foreign key(clinic_id,consent_id) references public.form_documents(clinic_id,id)
);
create table public.case_staff_assignments (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,case_id uuid not null,
 person_id uuid not null references auth.users(id),role text not null check(role in ('responsable','cirujano','anestesista')),
 created_at timestamptz not null default clock_timestamp(),foreign key(clinic_id,case_id) references public.clinical_cases(clinic_id,id),unique(case_id,role)
);
create table public.person_procedure_authorizations (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,case_id uuid not null,
 person_id uuid not null references auth.users(id),scope text not null check(scope in ('observaciones','evaluacion','cirugia','anestesia','recuperacion','cuidados')),
 valid_until timestamptz not null,granted_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,case_id) references public.clinical_cases(clinic_id,id)
);
create table public.person_procedure_revocations (
 id uuid primary key default gen_random_uuid(),authorization_id uuid not null unique references public.person_procedure_authorizations(id),
 reason text not null check(length(btrim(reason)) between 1 and 1000),created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp()
);
create table public.clinical_observations (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,case_id uuid not null,
 kind text not null,value numeric(24,9) not null,unit text not null,observed_at timestamptz not null,
 performed_by uuid not null references auth.users(id),recorded_by uuid not null references auth.users(id),
 notes text not null default '',created_at timestamptz not null default clock_timestamp(),
 replaces_id uuid unique references public.clinical_observations(id),correction_reason text,
 foreign key(clinic_id,case_id) references public.clinical_cases(clinic_id,id)
);
create table public.clinical_procedure_acts (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,case_id uuid not null,
 scope text not null check(scope in ('evaluacion','cirugia','anestesia','recuperacion','cuidados')),
 notes text not null check(length(btrim(notes)) between 1 and 4000),observed_at timestamptz not null,
 performed_by uuid not null references auth.users(id),recorded_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,case_id) references public.clinical_cases(clinic_id,id)
);
create table public.clinical_death_records (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,patient_id uuid not null,consent_id uuid not null,
 result text not null check(result in ('confirmada','no_confirmada')),method text not null,findings text not null,
 observed_at timestamptz not null,body_disposition text not null default '',cost text not null default '',notes text not null default '',
 recorded_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 replaces_id uuid unique references public.clinical_death_records(id),correction_reason text,
 foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id),
 foreign key(clinic_id,consent_id) references public.form_documents(clinic_id,id)
);
alter table public.vet_patient_events add column clinical_observation_id uuid references public.clinical_observations(id);
alter table public.vet_patient_events add column form_document_id uuid references public.form_documents(id);
create unique index vet_event_form_unique on public.vet_patient_events(form_document_id,kind) where form_document_id is not null;
create function private.clinical_time(s text) returns timestamptz language plpgsql immutable set search_path='' as $$
declare t timestamptz;
begin
 if s is null or s !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$' then raise exception 'invalid_utc_time';end if;
 t=s::timestamptz;
 if to_char(t at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS')<>left(s,19) then raise exception 'invalid_utc_time';end if;
 return t;
end $$;
create function private.clinical_eligible(c public.clinical_cases,person uuid,scope text,at_time timestamptz) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.clinic_members m where m.clinic_id=c.clinic_id and m.user_id=person and m.role in ('mvz','auxiliar')) and (
 exists(select 1 from public.case_staff_assignments s where s.case_id=c.id and s.person_id=person and exists(select 1 from public.clinic_members m where m.clinic_id=c.clinic_id and m.user_id=person and m.role='mvz')) or
 exists(select 1 from public.person_procedure_authorizations a where a.case_id=c.id and a.person_id=person and a.scope=$3 and a.created_at<=at_time and a.valid_until>=at_time and not exists(select 1 from public.person_procedure_revocations r where r.authorization_id=a.id and r.created_at<=at_time)));
$$;
create function private.clinical_readable(c public.clinical_cases) returns boolean language sql stable security definer set search_path='' as $$
 select private.has_clinic_role(c.clinic_id,array['admin']) or
 exists(select 1 from public.case_staff_assignments s where s.case_id=c.id and s.person_id=auth.uid() and private.has_clinic_role(c.clinic_id,array['mvz'])) or
 exists(select 1 from public.person_procedure_authorizations a where a.case_id=c.id and a.person_id=auth.uid() and private.clinical_eligible(c,auth.uid(),a.scope,clock_timestamp()));
$$;
create function private.clinical_write_check(c public.clinical_cases,scope text,performer uuid,observed timestamptz) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.clinical_eligible(c,auth.uid(),scope,clock_timestamp()) or not private.clinical_eligible(c,performer,scope,observed) then raise exception 'procedure_authorization_required';end if;
 if observed is null or observed>clock_timestamp() or observed::date<c.clinical_date then raise exception 'invalid_observation_time';end if;
 -- An auxiliary reports their own act; no attribution to another clinician.
 if private.has_clinic_role(c.clinic_id,array['auxiliar']) and performer<>auth.uid() then raise exception 'own_application_only';end if;
end $$;
create function private.clinical_immutable() returns trigger language plpgsql set search_path='' as $$begin raise exception 'clinical_record_is_immutable_append_correction';end $$;
do $$ declare t text;begin
 foreach t in array array['clinical_cases','case_staff_assignments','person_procedure_authorizations','clinical_observations','clinical_procedure_acts'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create trigger immutable before update or delete on public.%I for each row execute function private.clinical_immutable()',t);
  if t='clinical_cases' then execute 'create policy clinical_read on public.clinical_cases for select to authenticated using(private.clinical_readable(clinical_cases))';
  else execute format('create policy clinical_read on public.%I for select to authenticated using(exists(select 1 from public.clinical_cases c where c.id=case_id and private.clinical_readable(c)))',t);end if;
 end loop;
 foreach t in array array['person_procedure_revocations','clinical_death_records'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create trigger immutable before update or delete on public.%I for each row execute function private.clinical_immutable()',t);
 end loop;
end $$;
create policy revocation_read on public.person_procedure_revocations for select to authenticated using(exists(select 1 from public.person_procedure_authorizations a join public.clinical_cases c on c.id=a.case_id where a.id=authorization_id and private.clinical_readable(c)));
create policy death_read on public.clinical_death_records for select to authenticated using(exists(select 1 from public.form_documents d where d.id=consent_id and private.form_readable(d)));
create or replace function private.form_readable(d public.form_documents) returns boolean language sql stable security definer set search_path='' as $$
 select private.has_clinic_role(d.clinic_id,array['admin']) or (d.responsible_id=auth.uid() and private.has_clinic_role(d.clinic_id,array['mvz'])) or
 (d.assigned_aux_id=auth.uid() and d.state='draft' and private.has_clinic_role(d.clinic_id,array['auxiliar'])) or
 (d.state='signed' and exists(select 1 from public.clinical_cases c where c.document_id=d.id and private.clinical_readable(c)));
$$;
drop policy vet_event_read on public.vet_patient_events;
create policy vet_event_read on public.vet_patient_events for select to authenticated using(
 case when form_document_id is not null then exists(select 1 from public.clinical_cases c where c.document_id=form_document_id and private.clinical_readable(c))
 else private.has_clinic_role(clinic_id,case when kind='consent' then array['admin','mvz'] else array['admin','mvz','auxiliar'] end) end);
create function public.form_clinical_staff(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'role',m.role,'label',coalesce(nullif(u.email,''),m.user_id::text))) from public.clinic_members m join auth.users u on u.id=m.user_id where m.clinic_id=p_clinic and m.role in ('mvz','auxiliar')),'[]');
end $$;
create function private.clinical_document_check(d public.form_documents) returns void language plpgsql security definer set search_path='' as $$
declare k text;v jsonb=d.values;ct text=d.snapshot->'schema'->>'type';p uuid;n numeric;
begin
 if ct not in ('clinical_history','surgical_sheet','surgical_risk') then return;end if;
 if coalesce(length(btrim(v->>'reason')),0) not between 1 and 300 then raise exception 'clinical_reason_required';end if;
 foreach k in array array['antecedents','subjective','objective','assessment','plan','asa','ekg','notes'] loop
  if length(coalesce(v->>k,''))>4000 then raise exception 'clinical_field_too_long';end if;
 end loop;
 if (v->>'clinical_date')::date>current_date then raise exception 'future_clinical_date';end if;
 if ct='clinical_history' and coalesce(btrim(v->>'subjective'),'')='' and coalesce(btrim(v->>'objective'),'')='' and coalesce(btrim(v->>'assessment'),'')='' and coalesce(btrim(v->>'plan'),'')='' then raise exception 'soap_required';end if;
 foreach k in array array['surgeon_id','anesthetist_id'] loop
  if coalesce(v->>k,'')<>'' then
   p=(v->>k)::uuid;
   if not exists(select 1 from public.clinic_members where clinic_id=d.clinic_id and user_id=p and role='mvz') then raise exception 'assigned_mvz_not_in_clinic';end if;
  end if;
 end loop;
 if coalesce(v->>'consent_id','')<>'' and not exists(select 1 from public.form_documents consent where consent.id=(v->>'consent_id')::uuid and consent.clinic_id=d.clinic_id and consent.patient_id=d.patient_id and consent.state='signed' and consent.snapshot->'schema'->>'type'='surgery' and private.form_readable(consent)) then raise exception 'matching_signed_surgery_consent_required';end if;
 foreach k in array array['weight','fc','fr','temperature','tllc','bp_systolic','bp_diastolic'] loop
  if coalesce(v->>k,'')<>'' then
   n=(v->>k)::numeric;
   if (k='weight' and n<=0) or (k<>'temperature' and n<0) then raise exception 'invalid_measurement';end if;
   if private.clinical_time(v->>'observed_at')>clock_timestamp() or private.clinical_time(v->>'observed_at')::date<>(v->>'clinical_date')::date then raise exception 'measurement_time_required';end if;
  end if;
 end loop;
end $$;
create function private.clinical_document_publish(d public.form_documents) returns void language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;v jsonb=d.values;k text;u text;ct text=d.snapshot->'schema'->>'type';observation_id uuid;
begin
 if ct not in ('clinical_history','surgical_sheet','surgical_risk') then return;end if;
 insert into public.clinical_cases(clinic_id,patient_id,document_id,responsible_id,kind,title,reason,procedure,clinical_date,asa,ekg,antecedents,notes,consent_id)
 values(d.clinic_id,d.patient_id,d.id,d.responsible_id,ct,d.snapshot->'schema'->>'title',v->>'reason',v->>'procedure',(v->>'clinical_date')::date,v->>'asa',v->>'ekg',v->>'antecedents',v->>'notes',nullif(v->>'consent_id','')::uuid) returning * into c;
 insert into public.case_staff_assignments(clinic_id,case_id,person_id,role) values(c.clinic_id,c.id,c.responsible_id,'responsable');
 if nullif(v->>'surgeon_id','') is not null then insert into public.case_staff_assignments(clinic_id,case_id,person_id,role) values(c.clinic_id,c.id,(v->>'surgeon_id')::uuid,'cirujano');end if;
 if nullif(v->>'anesthetist_id','') is not null then insert into public.case_staff_assignments(clinic_id,case_id,person_id,role) values(c.clinic_id,c.id,(v->>'anesthetist_id')::uuid,'anestesista');end if;
 if ct='clinical_history' then
  insert into public.vet_patient_events(clinic_id,patient_id,kind,payload,created_by,form_document_id) values(d.clinic_id,d.patient_id,'soap',jsonb_build_object('date',v->>'clinical_date','reason',v->>'reason','species_template',d.snapshot->'patient'->>'species','subjective',coalesce(v->>'subjective',''),'objective',coalesce(v->>'objective',''),'assessment',coalesce(v->>'assessment',''),'plan',coalesce(v->>'plan','')),d.responsible_id,d.id);
 end if;
 foreach k in array array['weight','fc','fr','temperature','tllc','bp_systolic','bp_diastolic'] loop
  if coalesce(v->>k,'')<>'' then
   u=case k when 'weight' then 'kg' when 'fc' then 'lpm' when 'fr' then 'rpm' when 'temperature' then '°C' when 'tllc' then 's' else 'mmHg' end;
   insert into public.clinical_observations(clinic_id,case_id,kind,value,unit,observed_at,performed_by,recorded_by) values(c.clinic_id,c.id,k,(v->>k)::numeric,u,private.clinical_time(v->>'observed_at'),d.responsible_id,d.responsible_id) returning id into observation_id;
   if k='weight' then insert into public.vet_patient_events(clinic_id,patient_id,kind,payload,created_by,form_document_id,clinical_observation_id) values(c.clinic_id,c.patient_id,'weight',jsonb_build_object('date',v->>'clinical_date','kg',v->>'weight'),d.responsible_id,d.id,observation_id);end if;
  end if;
 end loop;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(c.clinic_id,auth.uid(),'clinical_case_published',c.id);
end $$;


create or replace function private.form_validate_schema(s jsonb) returns void language plpgsql set search_path='' as $$
declare f jsonb;c jsonb;ids text[]='{}';keys text[]='{}';k text;canonical jsonb;rev jsonb;
begin
 if jsonb_typeof(s) is distinct from 'object' or octet_length(s::text)>60000 or s->>'type' is null or s->>'type' not in ('general','surgery','euthanasia','early_discharge','hospital','clinical_history','surgical_sheet','surgical_risk') or jsonb_typeof(s->'title') is distinct from 'string' or coalesce(length(btrim(s->>'title')),0) not between 1 and 200 then raise exception 'invalid_template';end if;
 if jsonb_typeof(s->'fields') is distinct from 'array' or jsonb_typeof(s->'clauses') is distinct from 'array' then raise exception 'invalid_template';end if;
 if jsonb_array_length(s->'fields')>80 or jsonb_array_length(s->'clauses')>40 then raise exception 'invalid_template';end if;
 for f in select * from jsonb_array_elements(s->'fields') loop
  if jsonb_typeof(f->'id') is distinct from 'string' or jsonb_typeof(f->'label') is distinct from 'string' or f->>'id' is null or f->>'id' !~ '^[a-z][a-z0-9_]{0,63}$' or f->>'id'=any(ids) or f->>'type' is null or f->>'type' not in ('text','date','checkbox','single','multiple','table','number','binding','signature','person','consent','instant') or coalesce(length(btrim(f->>'label')),0) not between 1 and 200 or jsonb_typeof(f->'required') is distinct from 'boolean' or jsonb_typeof(f->'locked') is distinct from 'boolean' then raise exception 'invalid_field';end if;
  ids=array_append(ids,f->>'id');
  if f->>'type' in ('single','multiple') then
   if jsonb_typeof(f->'options') is distinct from 'array' then raise exception 'invalid_options';end if;
   if jsonb_array_length(f->'options') not between 1 and 40 or exists(select 1 from jsonb_array_elements(f->'options') o where jsonb_typeof(o)<>'string' or length(btrim(o#>>'{}')) not between 1 and 200) or (select count(distinct o) from jsonb_array_elements(f->'options') o)<>jsonb_array_length(f->'options') then raise exception 'invalid_options';end if;
  end if;
  if f->>'type'='table' then
   if jsonb_typeof(f->'columns') is distinct from 'array' then raise exception 'invalid_columns';end if;
   if jsonb_array_length(f->'columns') not between 1 and 12 or exists(select 1 from jsonb_array_elements(f->'columns') o where jsonb_typeof(o)<>'string' or length(btrim(o#>>'{}')) not between 1 and 100) or (select count(distinct o) from jsonb_array_elements(f->'columns') o)<>jsonb_array_length(f->'columns') then raise exception 'invalid_columns';end if;
  end if;
 end loop;
 -- Mandatory definitions come from the installed base, not client-controlled flags.
 select b.schema into canonical from public.form_template_versions b
 where b.clinic_id is null and b.schema->>'type'=s->>'type'
 and (s->'fields') @> (select coalesce(jsonb_agg(value),'[]') from jsonb_array_elements(b.schema->'fields') where value->'locked'='true'::jsonb)
 and (s->'clauses') @> (select coalesce(jsonb_agg(value),'[]') from jsonb_array_elements(b.schema->'clauses') where value->'locked'='true'::jsonb)
 order by b.version desc limit 1;
 if canonical is null then raise exception 'protected_field_changed';end if;
 if canonical is not null then
  for f in select * from jsonb_array_elements(canonical->'fields') where (value->>'locked')::boolean loop
   if not exists(select 1 from jsonb_array_elements(s->'fields') n where n=f) then raise exception 'protected_field_changed';end if;
  end loop;
 end if;
 foreach k in array case when s->>'type' in ('clinical_history','surgical_sheet','surgical_risk') then array['patient','owner','mvz_name','mvz_license','privacy_url','signature'] else array['patient','owner','mvz_name','mvz_license','signer_name','signer_id','privacy_url','signature'] end loop
  if not exists(select 1 from jsonb_array_elements(s->'fields') as item(value) where item.value->>'id'=k and item.value->'locked'='true'::jsonb and item.value->'required'='true'::jsonb) then raise exception 'protected_field_missing';end if;
 end loop;
 for c in select * from jsonb_array_elements(s->'clauses') loop
  if jsonb_typeof(c->'id') is distinct from 'string' or jsonb_typeof(c->'text') is distinct from 'string' or c->>'id' is null or c->>'id'=any(keys) or coalesce(length(btrim(c->>'text')),0) not between 1 and 12000 or jsonb_typeof(c->'locked') is distinct from 'boolean' or c->>'text' ~* '\mirrevocable\M' then raise exception 'invalid_clause';end if;
  keys=array_append(keys,c->>'id');
  if c->>'id'='revocation' and c->'locked'='true'::jsonb then rev=c;end if;
 end loop;
 if s->>'type' not in ('clinical_history','surgical_sheet','surgical_risk') and rev is null then raise exception 'revocation_required';end if;
 if canonical is not null and rev<>(select value from jsonb_array_elements(canonical->'clauses') where value->>'id'='revocation') then raise exception 'protected_clause_changed';end if;
 if s->>'type'='euthanasia' and not ids @> array['clinical_reason','prior_opinion','method','body_disposition','cost'] then raise exception 'euthanasia_fields_required';end if;
end $$;

create or replace function private.form_validate_values(s jsonb,v jsonb,complete boolean) returns void language plpgsql set search_path='' as $$
declare f jsonb;x jsonb;k text;r jsonb;d date;
begin
 if jsonb_typeof(v) is distinct from 'object' or octet_length(v::text)>200000 then raise exception 'invalid_values';end if;
 for k,x in select * from jsonb_each(v) loop
  select value into f from jsonb_array_elements(s->'fields') where value->>'id'=k;
  if f is null or f->>'type' in ('binding','signature') then raise exception 'field_not_editable';end if;
  case f->>'type'
  when 'checkbox' then if jsonb_typeof(x)<>'boolean' then raise exception 'invalid_checkbox';end if;
  when 'multiple' then
   if jsonb_typeof(x)<>'array' then raise exception 'invalid_selection';end if;
   if exists(select 1 from jsonb_array_elements(x) a where not (f->'options') @> jsonb_build_array(a)) or (select count(distinct a) from jsonb_array_elements(x) a)<>jsonb_array_length(x) then raise exception 'invalid_selection';end if;
  when 'table' then
   if jsonb_typeof(x)<>'array' or jsonb_array_length(x)>100 then raise exception 'invalid_table';end if;
   for r in select * from jsonb_array_elements(x) loop
    if jsonb_typeof(r)<>'array' or jsonb_array_length(r)<>jsonb_array_length(f->'columns') then raise exception 'invalid_table';end if;
    if exists(select 1 from jsonb_array_elements(r) cell where jsonb_typeof(cell)<>'string' or length(cell#>>'{}')>1000) then raise exception 'invalid_table';end if;
   end loop;
  else
   if jsonb_typeof(x)<>'string' or length(x#>>'{}')>12000 then raise exception 'invalid_text';end if;
   if f->>'type'='single' and x#>>'{}'<>'' and not (f->'options') @> jsonb_build_array(x) then raise exception 'invalid_selection';end if;
   if f->>'type'='number' and x#>>'{}'<>'' and x#>>'{}' !~ '^-?\d{1,12}(\.\d{1,9})?$' then raise exception 'invalid_number';end if;
   if f->>'type'='date' and x#>>'{}'<>'' then
    if x#>>'{}' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid_date';end if;
    d=(x#>>'{}')::date;
   end if;
   if f->>'type' in ('person','consent') and x#>>'{}'<>'' and x#>>'{}' !~ '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' then raise exception 'invalid_reference';end if;
   if f->>'type'='instant' and x#>>'{}'<>'' then perform private.clinical_time(x#>>'{}');end if;
   if k='privacy_url' and x#>>'{}'<>'' and x#>>'{}' !~ '^https://[^ /]+(/.*)?$' then raise exception 'invalid_privacy_url';end if;
  end case;
 end loop;
 if complete then
  for f in select * from jsonb_array_elements(s->'fields') where value->'required'='true'::jsonb and value->>'type' not in ('binding','signature') loop
   x=v->(f->>'id');
   if x is null or x='null'::jsonb or x='false'::jsonb or x='[]'::jsonb or (jsonb_typeof(x)='string' and btrim(x#>>'{}')='') then raise exception 'required_field_missing';end if;
  end loop;
 end if;
end $$;

create or replace function public.form_document_create(p_clinic uuid,p_patient uuid,p_version uuid,p_values jsonb,p_branding jsonb,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.form_template_versions;p public.vet_patients;o public.vet_owners;d public.form_documents;id uuid;fp jsonb;s jsonb;
begin
 if not private.has_clinic_role(p_clinic,array['mvz']) then raise exception 'responsible_mvz_required';end if;
 select * into v from public.form_template_versions where form_template_versions.id=p_version and clinic_id=p_clinic and approved;
 if not found then raise exception 'approved_clinic_template_required';end if;
 perform private.form_validate_values(v.schema,p_values,false);perform private.form_validate_brand(p_branding);
 fp=jsonb_build_object('kind','form_document','patient',p_patient,'version',p_version,'values',p_values,'branding',p_branding);
 id=private.vet_receipt(p_clinic,p_operation,fp);
 if id is not null then select * into d from public.form_documents where form_documents.id=id;return to_jsonb(d);end if;
 select * into p from public.vet_patients where vet_patients.id=p_patient and clinic_id=p_clinic;
 if not found or (p.owner_id is null and v.schema->>'type' not in ('clinical_history','surgical_sheet','surgical_risk')) then raise exception 'patient_and_owner_required';end if;
 select * into o from public.vet_owners where vet_owners.id=p.owner_id and clinic_id=p_clinic;
 s=jsonb_build_object('schema',v.schema,'template_version',v.version,'patient',jsonb_build_object('id',p.id,'name',p.name,'species',p.species,'breed',p.breed,'sex',p.sex),'owner',jsonb_build_object('id',o.id,'name',coalesce(o.name,'Sin propietario registrado')),'clinical',v.schema->>'type' in ('clinical_history','surgical_sheet','surgical_risk'),'responsible_id',auth.uid(),'clinic_name',(select name from public.clinics where clinics.id=p_clinic));
 insert into public.form_documents(clinic_id,patient_id,version_id,responsible_id,values,branding,snapshot,created_by) values(p_clinic,p_patient,p_version,auth.uid(),p_values,p_branding,s,auth.uid()) returning * into d;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,d.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'form_document_draft_created',d.id);
 return to_jsonb(d);
end $$;

create or replace function public.form_document_prepare(p_id uuid,p_revision integer,p_tutor_signature jsonb,p_mvz_signature jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;time timestamptz=clock_timestamp();s jsonb;
begin
 select * into d from public.form_documents where id=p_id for update;
 if not found or d.responsible_id<>auth.uid() or not private.has_clinic_role(d.clinic_id,array['mvz']) then raise exception 'responsible_mvz_required';end if;
 if d.state<>'draft' or d.revision is distinct from p_revision then raise exception 'document_revision_conflict';end if;
 perform private.form_validate_values(d.snapshot->'schema',d.values,true);
 if not coalesce((d.snapshot->>'clinical')::boolean,false) then perform private.form_validate_signature(p_tutor_signature);end if;
 perform private.clinical_document_check(d);perform private.form_validate_signature(p_mvz_signature);
 s=d.snapshot||jsonb_build_object('staff_labels',(select coalesce(jsonb_object_agg(m.user_id::text,coalesce(nullif(u.email,''),m.user_id::text)),'{}') from public.clinic_members m join auth.users u on u.id=m.user_id where m.clinic_id=d.clinic_id and m.user_id in (nullif(d.values->>'surgeon_id','')::uuid,nullif(d.values->>'anesthetist_id','')::uuid)),'document_id',d.id,'values',d.values,'branding',d.branding,'prepared_at',time,'tutor_signature',p_tutor_signature,'mvz_signature',p_mvz_signature);
 insert into public.form_signatures(document_id,role,name,identification_number,points,captured_at) values(d.id,'mvz',d.values->>'mvz_name',d.values->>'mvz_license',p_mvz_signature,time);
 if not coalesce((d.snapshot->>'clinical')::boolean,false) then insert into public.form_signatures(document_id,role,name,identification_number,points,captured_at) values(d.id,'tutor',d.values->>'signer_name',d.values->>'signer_id',p_tutor_signature,time);end if;
 update public.form_documents set state='awaiting_review',revision=revision+1,snapshot=s,prepared_at=time,content_hash=encode(sha256(convert_to(s::text,'UTF8')),'hex') where id=d.id returning * into d;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(d.clinic_id,auth.uid(),'form_document_prepared_for_review',d.id);return to_jsonb(d);
end $$;

create or replace function public.form_register_pdf(p_id uuid,p_revision integer,p_content_hash text,p_pdf text,p_tutor_png text,p_mvz_png text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;bytes bytea;t bytea;m bytea;hash text;a private.form_artifacts;
begin
 select * into d from public.form_documents where id=p_id for update;
 if not found or d.revision is distinct from p_revision or d.content_hash is distinct from p_content_hash then raise exception 'stale_pdf';end if;
 select * into a from private.form_artifacts where document_id=p_id;
 if found then return jsonb_build_object('pdf',encode(a.pdf,'base64'),'hash',a.pdf_hash);end if;
 if d.state<>'awaiting_review' then raise exception 'document_not_prepared';end if;
 if p_pdf is null or p_mvz_png is null then raise exception 'invalid_artifact';end if;
 if length(p_pdf)>2800000 or length(p_tutor_png)>300000 or length(p_mvz_png)>300000 then raise exception 'artifact_too_large';end if;
 bytes=decode(p_pdf,'base64');t=decode(p_tutor_png,'base64');m=decode(p_mvz_png,'base64');
 if octet_length(bytes) not between 5 and 2097152 or substring(bytes from 1 for 5)<>convert_to('%PDF-','UTF8') or (not coalesce((d.snapshot->>'clinical')::boolean,false) and (t is null or substring(t from 1 for 8)<>decode('89504e470d0a1a0a','hex'))) or substring(m from 1 for 8)<>decode('89504e470d0a1a0a','hex') then raise exception 'invalid_artifact';end if;
 hash=encode(sha256(bytes),'hex');
 insert into private.form_artifacts values(p_id,d.revision,d.content_hash,bytes,hash,'vetdosis-pdf-1',clock_timestamp());
 update public.form_signatures set image=case role when 'tutor' then t else m end,image_hash=encode(sha256(case role when 'tutor' then t else m end),'hex') where document_id=p_id;
 update public.form_documents set state='ready',pdf_hash=hash where id=p_id;
 return jsonb_build_object('pdf',encode(bytes,'base64'),'hash',hash);
end $$;

create or replace function public.form_document_finalize(p_id uuid,p_revision integer,p_pdf_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.form_documents;
begin
 select * into d from public.form_documents where id=p_id for update;
 if not found or d.responsible_id<>auth.uid() or not private.has_clinic_role(d.clinic_id,array['mvz']) then raise exception 'responsible_mvz_required';end if;
 if d.revision is distinct from p_revision or d.pdf_hash is distinct from p_pdf_hash or p_pdf_hash is null then raise exception 'reviewed_pdf_mismatch';end if;
 if d.state='signed' then return to_jsonb(d);end if;
 if d.state<>'ready' or not exists(select 1 from private.form_artifacts a where a.document_id=d.id and a.revision=d.revision and a.content_hash=d.content_hash and a.pdf_hash=p_pdf_hash and encode(sha256(a.pdf),'hex')=p_pdf_hash) then raise exception 'pdf_not_ready';end if;
 perform private.clinical_document_check(d);
 update public.form_documents set state='signed',accepted_at=clock_timestamp() where id=d.id returning * into d;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(d.clinic_id,auth.uid(),'form_document_signed',d.id,jsonb_build_object('pdf_hash',p_pdf_hash,'version',d.version_id));
 perform private.clinical_document_publish(d);
 return to_jsonb(d);
end $$;

with t as (insert into public.form_templates default values returning id) insert into public.form_template_versions(template_id,version,schema,reason) select id,1,'{"type": "clinical_history", "title": "Historia clínica", "fields": [{"id": "patient", "label": "Paciente", "type": "binding", "required": true, "locked": true}, {"id": "owner", "label": "Propietario registrado", "type": "binding", "required": true, "locked": true}, {"id": "mvz_name", "label": "Nombre del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "mvz_license", "label": "Cédula del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "privacy_url", "label": "Enlace al aviso de privacidad", "type": "text", "required": true, "locked": true}, {"id": "signature", "label": "Firma del MVZ responsable", "type": "signature", "required": true, "locked": true}, {"id": "clinical_date", "label": "Fecha clínica", "type": "date", "required": true, "locked": true}, {"id": "reason", "label": "Motivo de atención", "type": "text", "required": true, "locked": true}, {"id": "antecedents", "label": "Antecedentes", "type": "text", "required": false, "locked": true}, {"id": "subjective", "label": "SOAP · Subjetivo", "type": "text", "required": false, "locked": true}, {"id": "objective", "label": "SOAP · Objetivo", "type": "text", "required": false, "locked": true}, {"id": "assessment", "label": "SOAP · Análisis", "type": "text", "required": false, "locked": true}, {"id": "plan", "label": "SOAP · Plan", "type": "text", "required": false, "locked": true}, {"id": "observed_at", "label": "Fecha y hora de las mediciones (UTC)", "type": "instant", "required": false, "locked": true}, {"id": "weight", "label": "Peso (kg)", "type": "number", "required": false, "locked": true}, {"id": "fc", "label": "Frecuencia cardíaca (lpm)", "type": "number", "required": false, "locked": true}, {"id": "fr", "label": "Frecuencia respiratoria (rpm)", "type": "number", "required": false, "locked": true}, {"id": "temperature", "label": "Temperatura (°C)", "type": "number", "required": false, "locked": true}, {"id": "tllc", "label": "TLLC (s)", "type": "number", "required": false, "locked": true}, {"id": "bp_systolic", "label": "Presión sistólica (mmHg)", "type": "number", "required": false, "locked": true}, {"id": "bp_diastolic", "label": "Presión diastólica (mmHg)", "type": "number", "required": false, "locked": true}], "clauses": [{"id": "clinical_scope", "text": "Registro clínico elaborado por el MVZ. No sustituye la autorización del tutor. Los campos sin captura permanecen pendientes; no representan hallazgos normales. Las actuaciones posteriores se anexan al expediente sin alterar este documento.", "locked": true}]}'::jsonb,'Estructura clínica original; requiere revisión de la clínica' from t;

with t as (insert into public.form_templates default values returning id) insert into public.form_template_versions(template_id,version,schema,reason) select id,1,'{"type": "surgical_sheet", "title": "Hoja quirúrgica y anestésica", "fields": [{"id": "patient", "label": "Paciente", "type": "binding", "required": true, "locked": true}, {"id": "owner", "label": "Propietario registrado", "type": "binding", "required": true, "locked": true}, {"id": "mvz_name", "label": "Nombre del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "mvz_license", "label": "Cédula del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "privacy_url", "label": "Enlace al aviso de privacidad", "type": "text", "required": true, "locked": true}, {"id": "signature", "label": "Firma del MVZ responsable", "type": "signature", "required": true, "locked": true}, {"id": "clinical_date", "label": "Fecha clínica", "type": "date", "required": true, "locked": true}, {"id": "reason", "label": "Motivo de atención", "type": "text", "required": true, "locked": true}, {"id": "procedure", "label": "Procedimiento", "type": "text", "required": true, "locked": true}, {"id": "surgeon_id", "label": "Cirujano", "type": "person", "required": true, "locked": true}, {"id": "anesthetist_id", "label": "Anestesista", "type": "person", "required": true, "locked": true}, {"id": "consent_id", "label": "Consentimiento quirúrgico firmado vinculado", "type": "consent", "required": false, "locked": true}, {"id": "asa", "label": "ASA: valoración capturada por el MVZ", "type": "text", "required": false, "locked": true}, {"id": "ekg", "label": "EKG: hallazgos e interpretación del MVZ", "type": "text", "required": false, "locked": true}, {"id": "notes", "label": "Observaciones clínicas", "type": "text", "required": false, "locked": true}, {"id": "observed_at", "label": "Fecha y hora de las mediciones (UTC)", "type": "instant", "required": false, "locked": true}, {"id": "weight", "label": "Peso (kg)", "type": "number", "required": false, "locked": true}, {"id": "fc", "label": "Frecuencia cardíaca (lpm)", "type": "number", "required": false, "locked": true}, {"id": "fr", "label": "Frecuencia respiratoria (rpm)", "type": "number", "required": false, "locked": true}, {"id": "temperature", "label": "Temperatura (°C)", "type": "number", "required": false, "locked": true}, {"id": "tllc", "label": "TLLC (s)", "type": "number", "required": false, "locked": true}, {"id": "bp_systolic", "label": "Presión sistólica (mmHg)", "type": "number", "required": false, "locked": true}, {"id": "bp_diastolic", "label": "Presión diastólica (mmHg)", "type": "number", "required": false, "locked": true}], "clauses": [{"id": "clinical_scope", "text": "Registro clínico elaborado por el MVZ. No sustituye la autorización del tutor. Los campos sin captura permanecen pendientes; no representan hallazgos normales. Las actuaciones posteriores se anexan al expediente sin alterar este documento.", "locked": true}]}'::jsonb,'Estructura clínica original; requiere revisión de la clínica' from t;

with t as (insert into public.form_templates default values returning id) insert into public.form_template_versions(template_id,version,schema,reason) select id,1,'{"type": "surgical_risk", "title": "Valoración prequirúrgica / ASA / EKG", "fields": [{"id": "patient", "label": "Paciente", "type": "binding", "required": true, "locked": true}, {"id": "owner", "label": "Propietario registrado", "type": "binding", "required": true, "locked": true}, {"id": "mvz_name", "label": "Nombre del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "mvz_license", "label": "Cédula del MVZ responsable", "type": "text", "required": true, "locked": true}, {"id": "privacy_url", "label": "Enlace al aviso de privacidad", "type": "text", "required": true, "locked": true}, {"id": "signature", "label": "Firma del MVZ responsable", "type": "signature", "required": true, "locked": true}, {"id": "clinical_date", "label": "Fecha clínica", "type": "date", "required": true, "locked": true}, {"id": "reason", "label": "Motivo de atención", "type": "text", "required": true, "locked": true}, {"id": "procedure", "label": "Procedimiento", "type": "text", "required": true, "locked": true}, {"id": "surgeon_id", "label": "Cirujano", "type": "person", "required": false, "locked": true}, {"id": "anesthetist_id", "label": "Anestesista", "type": "person", "required": false, "locked": true}, {"id": "consent_id", "label": "Consentimiento quirúrgico firmado vinculado", "type": "consent", "required": false, "locked": true}, {"id": "asa", "label": "ASA: valoración capturada por el MVZ", "type": "text", "required": false, "locked": true}, {"id": "ekg", "label": "EKG: hallazgos e interpretación del MVZ", "type": "text", "required": false, "locked": true}, {"id": "notes", "label": "Observaciones clínicas", "type": "text", "required": false, "locked": true}, {"id": "observed_at", "label": "Fecha y hora de las mediciones (UTC)", "type": "instant", "required": false, "locked": true}, {"id": "weight", "label": "Peso (kg)", "type": "number", "required": false, "locked": true}, {"id": "fc", "label": "Frecuencia cardíaca (lpm)", "type": "number", "required": false, "locked": true}, {"id": "fr", "label": "Frecuencia respiratoria (rpm)", "type": "number", "required": false, "locked": true}, {"id": "temperature", "label": "Temperatura (°C)", "type": "number", "required": false, "locked": true}, {"id": "tllc", "label": "TLLC (s)", "type": "number", "required": false, "locked": true}, {"id": "bp_systolic", "label": "Presión sistólica (mmHg)", "type": "number", "required": false, "locked": true}, {"id": "bp_diastolic", "label": "Presión diastólica (mmHg)", "type": "number", "required": false, "locked": true}], "clauses": [{"id": "clinical_scope", "text": "Registro clínico elaborado por el MVZ. No sustituye la autorización del tutor. Los campos sin captura permanecen pendientes; no representan hallazgos normales. Las actuaciones posteriores se anexan al expediente sin alterar este documento.", "locked": true}]}'::jsonb,'Estructura clínica original; requiere revisión de la clínica' from t;
create function public.clinical_cases_list(p_clinic uuid,p_patient uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('patient_name',p.name) order by c.created_at desc) from public.clinical_cases c join public.vet_patients p on p.id=c.patient_id where c.clinic_id=p_clinic and (p_patient is null or c.patient_id=p_patient) and private.clinical_readable(c)),'[]');
end $$;
create function public.clinical_case_snapshot(p_case uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
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
create function public.clinical_authorize(p_case uuid,p_person uuid,p_scope text,p_until text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;id uuid;fp jsonb;until_at timestamptz;
begin
 select * into c from public.clinical_cases where clinical_cases.id=p_case for update;
 if not found or c.responsible_id<>auth.uid() or not private.has_clinic_role(c.clinic_id,array['mvz']) then raise exception 'responsible_mvz_required';end if;
 until_at=private.clinical_time(p_until);
 if until_at<=clock_timestamp() or not exists(select 1 from public.clinic_members where clinic_id=c.clinic_id and user_id=p_person and role in ('mvz','auxiliar')) then raise exception 'invalid_authorization';end if;
 fp=jsonb_build_object('kind','clinical_grant','case',p_case,'person',p_person,'scope',p_scope,'until',p_until);id=private.vet_receipt(c.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.person_procedure_authorizations(clinic_id,case_id,person_id,scope,valid_until,granted_by) values(c.clinic_id,c.id,p_person,p_scope,until_at,auth.uid()) returning person_procedure_authorizations.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(c.clinic_id,auth.uid(),'clinical_procedure_authorized',id);return id;
end $$;
create function public.clinical_authorization_revoke(p_id uuid,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare a public.person_procedure_authorizations;c public.clinical_cases;id uuid;fp jsonb;
begin
 select * into a from public.person_procedure_authorizations where person_procedure_authorizations.id=p_id;
 select * into c from public.clinical_cases where clinical_cases.id=a.case_id for update;
 if not found or c.responsible_id<>auth.uid() or not private.has_clinic_role(c.clinic_id,array['mvz']) then raise exception 'responsible_mvz_required';end if;
 fp=jsonb_build_object('kind','clinical_revoke','grant',p_id,'reason',p_reason);id=private.vet_receipt(c.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.person_procedure_revocations(authorization_id,reason,created_by) values(p_id,p_reason,auth.uid()) returning person_procedure_revocations.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(c.clinic_id,auth.uid(),'clinical_procedure_revoked',id);return id;
end $$;
create function public.clinical_observation_add(p_case uuid,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;id uuid;fp jsonb;k text;u text;n numeric;t timestamptz;performer uuid;previous uuid;
begin
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
 if previous is not null and (c.responsible_id<>auth.uid() or not private.has_clinic_role(c.clinic_id,array['mvz']) or coalesce(length(btrim(p_data->>'correction_reason')),0) not between 1 and 1000 or not exists(select 1 from public.clinical_observations where clinical_observations.id=previous and case_id=c.id and kind=k)) then raise exception 'responsible_correction_required';end if;
 fp=jsonb_build_object('kind','clinical_observation','case',p_case,'data',p_data);id=private.vet_receipt(c.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.clinical_observations(clinic_id,case_id,kind,value,unit,observed_at,performed_by,recorded_by,notes,replaces_id,correction_reason) values(c.clinic_id,c.id,k,n,u,t,performer,auth.uid(),coalesce(p_data->>'notes',''),previous,p_data->>'correction_reason') returning clinical_observations.id into id;
 if k='weight' then insert into public.vet_patient_events(clinic_id,patient_id,kind,payload,created_by,clinical_case_id,clinical_observation_id) values(c.clinic_id,c.patient_id,'weight',jsonb_build_object('date',to_char(t at time zone 'UTC','YYYY-MM-DD'),'kg',p_data->>'value','clinical_case_id',c.id),auth.uid(),c.id,id);end if;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(c.clinic_id,auth.uid(),'clinical_observation_added',id);return id;
end $$;
create function public.clinical_act_add(p_case uuid,p_scope text,p_notes text,p_performer uuid,p_observed text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases;id uuid;fp jsonb;t timestamptz;
begin
 select * into c from public.clinical_cases where clinical_cases.id=p_case for update;
 if not found then raise exception 'clinical_access_denied';end if;
 t=private.clinical_time(p_observed);perform private.clinical_write_check(c,p_scope,p_performer,t);
 fp=jsonb_build_object('kind','clinical_act','case',p_case,'scope',p_scope,'notes',p_notes,'performer',p_performer,'observed',p_observed);id=private.vet_receipt(c.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.clinical_procedure_acts(clinic_id,case_id,scope,notes,observed_at,performed_by,recorded_by) values(c.clinic_id,c.id,p_scope,p_notes,t,p_performer,auth.uid()) returning clinical_procedure_acts.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(c.clinic_id,auth.uid(),'clinical_act_added',id);return id;
end $$;
create function public.clinical_death_list(p_consent uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.form_documents;
begin
 select * into d from public.form_documents where id=p_consent;
 if not found or d.state<>'signed' or d.snapshot->'schema'->>'type'<>'euthanasia' or not private.form_readable(d) then raise exception 'signed_euthanasia_access_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(r) order by created_at) from public.clinical_death_records r where consent_id=d.id),'[]');
end $$;
create function public.clinical_death_add(p_consent uuid,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.form_documents;id uuid;fp jsonb;t timestamptz;k text;previous uuid;
begin
 select * into d from public.form_documents where form_documents.id=p_consent for update;
 if not found or d.state<>'signed' or d.snapshot->'schema'->>'type'<>'euthanasia' or d.responsible_id<>auth.uid() or not private.has_clinic_role(d.clinic_id,array['mvz']) then raise exception 'responsible_mvz_required';end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'invalid_death_record';end if;
 foreach k in array array['result','method','findings','observed_at'] loop
  if jsonb_typeof(p_data->k) is distinct from 'string' or length(btrim(p_data->>k)) not between 1 and 4000 then raise exception 'required_death_field';end if;
 end loop;
 foreach k in array array['body_disposition','cost','notes','correction_reason'] loop
  if p_data ? k and (jsonb_typeof(p_data->k) is distinct from 'string' or length(p_data->>k)>4000) then raise exception 'invalid_death_field';end if;
 end loop;
 t=private.clinical_time(p_data->>'observed_at');if t<d.accepted_at or t>clock_timestamp() then raise exception 'post_consent_time_required';end if;
 previous=nullif(p_data->>'replaces_id','')::uuid;
 if previous is not null and (coalesce(length(btrim(p_data->>'correction_reason')),0)=0 or not exists(select 1 from public.clinical_death_records where clinical_death_records.id=previous and consent_id=d.id)) then raise exception 'correction_reference_required';end if;
 fp=jsonb_build_object('kind','death_record','consent',p_consent,'data',p_data);id=private.vet_receipt(d.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.clinical_death_records(clinic_id,patient_id,consent_id,result,method,findings,observed_at,body_disposition,cost,notes,recorded_by,replaces_id,correction_reason)
 values(d.clinic_id,d.patient_id,d.id,p_data->>'result',p_data->>'method',p_data->>'findings',t,coalesce(p_data->>'body_disposition',''),coalesce(p_data->>'cost',''),coalesce(p_data->>'notes',''),auth.uid(),previous,p_data->>'correction_reason') returning clinical_death_records.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),d.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(d.clinic_id,auth.uid(),'clinical_death_record_added',id);return id;
end $$;
-- Prevent source-linked M4 events from disclosing a restricted case.
alter table public.vet_patient_events add column clinical_case_id uuid references public.clinical_cases(id);
drop policy vet_event_read on public.vet_patient_events;
create policy vet_event_read on public.vet_patient_events for select to authenticated using(
 case when clinical_case_id is not null or form_document_id is not null then exists(select 1 from public.clinical_cases c where (c.id=clinical_case_id or c.document_id=form_document_id) and private.clinical_readable(c))
 else private.has_clinic_role(clinic_id,case when kind='consent' then array['admin','mvz'] else array['admin','mvz','auxiliar'] end) end);
create or replace function public.form_document_snapshot(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.form_documents;
begin
 select * into d from public.form_documents where id=p_id;
 if not found or not private.form_readable(d) or (d.assigned_aux_id=auth.uid() and d.state<>'signed') then raise exception 'document_access_denied';end if;
 return to_jsonb(d);
end $$;
create or replace function public.form_read_pdf(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.form_documents;a private.form_artifacts;
begin
 select * into d from public.form_documents where id=p_id;
 if not found or not private.form_readable(d) or (d.assigned_aux_id=auth.uid() and d.state<>'signed') then raise exception 'document_access_denied';end if;
 select * into a from private.form_artifacts where document_id=p_id and revision=d.revision and content_hash=d.content_hash;
 if not found then return null;end if;
 return jsonb_build_object('pdf',encode(a.pdf,'base64'),'hash',a.pdf_hash);
end $$;
create function private.clinical_current_observation(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select p_id is null or not exists(select 1 from public.clinical_observations where replaces_id=p_id);
$$;
drop policy vet_event_read on public.vet_patient_events;
create policy vet_event_read on public.vet_patient_events for select to authenticated using(
 private.clinical_current_observation(clinical_observation_id) and
 case when clinical_case_id is not null or form_document_id is not null then exists(select 1 from public.clinical_cases c where (c.id=clinical_case_id or c.document_id=form_document_id) and private.clinical_readable(c))
 else private.has_clinic_role(clinic_id,case when kind='consent' then array['admin','mvz'] else array['admin','mvz','auxiliar'] end) end);
-- Private helpers remain unavailable as RPCs.
do $$ declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname like 'clinical_%') or (n.nspname='private' and p.proname like 'clinical_%') or (n.nspname='public' and p.proname='form_clinical_staff') loop
 execute 'revoke all on function '||f.signature||' from public,anon,authenticated';
 end loop;
end $$;
grant execute on function private.clinical_current_observation(uuid) to authenticated;
grant execute on function private.clinical_readable(public.clinical_cases) to authenticated;
grant execute on function public.form_clinical_staff(uuid),public.clinical_cases_list(uuid,uuid),public.clinical_case_snapshot(uuid),public.clinical_authorize(uuid,uuid,text,text,text),public.clinical_authorization_revoke(uuid,text,text),public.clinical_observation_add(uuid,jsonb,text),public.clinical_act_add(uuid,text,text,uuid,text,text),public.clinical_death_list(uuid),public.clinical_death_add(uuid,jsonb,text) to authenticated;

notify pgrst, 'reload schema';
commit;
select 'ETAPA 3 COMPLETADA: hospitalizacion y formatos' as resultado;
