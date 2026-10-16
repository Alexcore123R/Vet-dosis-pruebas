-- Local candidate after 13L. No deployment or historical authority conversion.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy) or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
insert into private.permission_catalog(code,label,procedure_scoped,requires_professional) values('clinical.death.record','Constatar muerte: responsable habilitado',true,true);
create table private.death_attestations(
 record_id uuid primary key references public.clinical_death_records(id),actor_id uuid not null references auth.users(id),
 signer_name text not null,signature jsonb not null,record_grant uuid not null references private.member_permission_grants(id),perform_grant uuid not null references private.member_permission_grants(id),
 procedure_id uuid not null references private.procedure_types(id),profile_version_id uuid not null references private.professional_profile_versions(id),input_hash text not null,created_at timestamptz not null default clock_timestamp());
alter table private.death_attestations enable row level security;
revoke all on private.death_attestations from public,anon,authenticated,service_role;
create trigger immutable before update or delete on private.death_attestations for each row execute function private.permission_immutable();
create function private.death_readable(d public.form_documents) returns boolean language sql stable security definer set search_path='' as $$
 select d.state='signed' and d.snapshot->'schema'->>'type'='euthanasia' and private.form_readable(d);
$$;
revoke all on function private.death_readable(public.form_documents) from public,anon,authenticated,service_role;
grant execute on function private.death_readable(public.form_documents) to authenticated;
drop policy death_read on public.clinical_death_records;
create policy death_read on public.clinical_death_records for select to authenticated using(exists(select 1 from public.form_documents d where d.id=consent_id and private.death_readable(d)));
create or replace function public.clinical_death_list(p_consent uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.form_documents;begin
 select * into d from public.form_documents where id=p_consent;
 if not found or private.death_readable(d) is distinct from true then raise exception 'signed_euthanasia_access_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('signer_name',a.signer_name,'attested',a.record_id is not null) order by r.created_at) from public.clinical_death_records r left join private.death_attestations a on a.record_id=r.id where r.consent_id=d.id),'[]');
end$$;
create function public.clinical_death_workspace(p_consent uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.form_documents;ps jsonb='[]';begin
 select * into d from public.form_documents where id=p_consent;
 if not found or private.death_readable(d) is distinct from true then raise exception 'signed_euthanasia_access_required';end if;
 if d.responsible_id=auth.uid() and private.clinical_professional_at(d.clinic_id,auth.uid(),clock_timestamp()) and public.beta_access_check(false,d.clinic_id)->>'mode' in ('internal','active','sponsor_grace') then
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name) order by p.name),'[]') into ps from private.procedure_types p where p.clinic_id=d.clinic_id and p.active
 and exists(select 1 from private.member_permission_grants where id=private.permission_effective(d.clinic_id,auth.uid(),'clinical.death.record',p.id) and valid_until>clock_timestamp())
 and exists(select 1 from private.member_permission_grants where id=private.permission_effective(d.clinic_id,auth.uid(),'procedure.perform',p.id) and valid_until>clock_timestamp());
 end if;
 return jsonb_build_object('version',1,'consent_id',d.id,'can_record',jsonb_array_length(ps)>0,'procedures',ps,'records',public.clinical_death_list(d.id));
end$$;
create or replace function public.clinical_death_add(p_consent uuid,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.form_documents;id uuid;fp jsonb;t timestamptz;k text;previous uuid;g uuid;pg uuid;profile jsonb;
begin
 select * into d from public.form_documents where form_documents.id=p_consent;
 if not found then raise exception 'signed_euthanasia_access_required';end if;
 perform private.medication_lock(d.clinic_id);
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,9061));
 select * into d from public.form_documents where form_documents.id=p_consent for update;
 if private.death_readable(d) is distinct from true then raise exception 'signed_euthanasia_access_required';end if;
 if d.responsible_id is distinct from auth.uid() then raise exception 'responsible_mvz_required';end if;
 perform public.beta_access_check(true,d.clinic_id);
 g=private.hospital_order_permission(d.clinic_id,'clinical.death.record',(p_data->>'procedure_id')::uuid,true);
 pg=private.hospital_order_permission(d.clinic_id,'procedure.perform',(p_data->>'procedure_id')::uuid,true);
 if not exists(select 1 from private.procedure_types where procedure_types.id=(p_data->>'procedure_id')::uuid and clinic_id=d.clinic_id and active) then raise exception 'active_procedure_required';end if;
 if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'own_attestation_required';end if;
 perform private.form_validate_signature(p_data->'signature');
 if jsonb_typeof(p_data->'signer_name') is distinct from 'string' or length(btrim(p_data->>'signer_name')) not between 1 and 200 then raise exception 'own_name_required';end if;
 if exists(select 1 from jsonb_object_keys(p_data) as keys(field) where keys.field not in ('procedure_id','confirmed','signature','signer_name','result','method','findings','observed_at','body_disposition','cost','notes','correction_reason','replaces_id')) then raise exception 'invalid_death_field';end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'invalid_death_record';end if;
 foreach k in array array['result','method','findings','observed_at'] loop
  if jsonb_typeof(p_data->k) is distinct from 'string' or length(btrim(p_data->>k)) not between 1 and 4000 then raise exception 'required_death_field';end if;
 end loop;
 foreach k in array array['body_disposition','cost','notes','correction_reason'] loop
  if p_data ? k and (jsonb_typeof(p_data->k) is distinct from 'string' or length(p_data->>k)>4000) then raise exception 'invalid_death_field';end if;
 end loop;
 t=private.clinical_time(p_data->>'observed_at');if d.accepted_at is null or t<d.accepted_at or t>clock_timestamp() then raise exception 'post_consent_time_required';end if;
 perform private.medication_permission(d.clinic_id,'clinical.death.record',(p_data->>'procedure_id')::uuid,t);
 perform private.medication_permission(d.clinic_id,'procedure.perform',(p_data->>'procedure_id')::uuid,t);
 if not private.clinical_professional_at(d.clinic_id,auth.uid(),t) then raise exception 'verified_professional_required';end if;
 previous=nullif(p_data->>'replaces_id','')::uuid;
 if previous is not null and (coalesce(length(btrim(p_data->>'correction_reason')),0)=0 or not exists(select 1 from public.clinical_death_records where clinical_death_records.id=previous and consent_id=d.id)) then raise exception 'correction_reference_required';end if;
 fp=jsonb_build_object('kind','death_record','consent',p_consent,'data',p_data);id=private.vet_receipt(d.clinic_id,p_operation,fp);if id is not null then return id;end if;
 insert into public.clinical_death_records(clinic_id,patient_id,consent_id,result,method,findings,observed_at,body_disposition,cost,notes,recorded_by,replaces_id,correction_reason)
 values(d.clinic_id,d.patient_id,d.id,p_data->>'result',p_data->>'method',p_data->>'findings',t,coalesce(p_data->>'body_disposition',''),coalesce(p_data->>'cost',''),coalesce(p_data->>'notes',''),auth.uid(),previous,p_data->>'correction_reason') returning clinical_death_records.id into id;
 select private.rx_profile(professional_profiles.id) into profile from public.professional_profiles where clinic_id=d.clinic_id and user_id=auth.uid();
 insert into private.death_attestations(record_id,actor_id,signer_name,signature,record_grant,perform_grant,procedure_id,profile_version_id,input_hash)
 values(id,auth.uid(),btrim(p_data->>'signer_name'),p_data->'signature',g,pg,(p_data->>'procedure_id')::uuid,(profile->>'id')::uuid,encode(sha256(convert_to(p_data::text,'UTF8')),'hex'));
 insert into private.vet_operation_receipts values(auth.uid(),d.clinic_id,p_operation,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(d.clinic_id,auth.uid(),'clinical_death_record_added',id);return id;
end $$;
revoke all on function public.clinical_death_add(uuid,jsonb,text),public.clinical_death_list(uuid),public.clinical_death_workspace(uuid) from public,anon,authenticated,service_role;
grant execute on function public.clinical_death_add(uuid,jsonb,text),public.clinical_death_list(uuid),public.clinical_death_workspace(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
