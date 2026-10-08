-- Phase 1. Apply once after M2 and M4. Prepared locally; no remote execution.
-- No role changes: pasante is auxiliar. No controlled prescribing/reporting here.
begin;
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

commit;
