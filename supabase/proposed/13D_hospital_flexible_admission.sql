-- LOCAL CANDIDATE: flexible administrative admission, not medication cutover.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
insert into private.permission_catalog(code,label,procedure_scoped,requires_professional) values('hospital.manage','Gestionar ingreso y ubicación hospitalaria',false,false);
alter table public.hospital_stays alter column cage drop not null;
alter table public.hospital_stays drop constraint hospital_stays_cage_check;
alter table public.hospital_stays add constraint hospital_stays_cage_check check(cage is null or length(btrim(cage)) between 1 and 80);
-- Existing unique index already allows multiple NULLs and still excludes occupied named cages.
create function private.hospital_permission(p_clinic uuid,p_code text) returns uuid language plpgsql security definer set search_path='' as $$
declare g uuid;begin
 g=private.permission_require(p_clinic,p_code);
 if not exists(select 1 from private.member_permission_grants where id=g and valid_until>clock_timestamp()) then raise exception 'explicit_permission_required';end if;
 return g;
end$$;
create function private.hospital_readable(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.permission_effective(p_clinic,auth.uid(),'hospital.read') is not null;
$$;
revoke all on function private.hospital_permission(uuid,text),private.hospital_readable(uuid) from public,anon,authenticated;
grant execute on function private.hospital_readable(uuid) to authenticated;
drop policy hospital_stay_read on public.hospital_stays;
drop policy hospital_task_read on public.hospital_tasks;
create policy hospital_stay_read on public.hospital_stays for select to authenticated using(private.hospital_readable(clinic_id));
create policy hospital_task_read on public.hospital_tasks for select to authenticated using(private.hospital_readable(clinic_id));
create or replace function public.hospital_snapshot(p_clinic_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.hospital_readable(p_clinic_id) then raise exception 'explicit_permission_required';end if;
 return jsonb_build_object('capabilities',jsonb_build_object('optional_cage',true,'cage_changes',true),
 'permissions',jsonb_build_object('hospital.manage',private.permission_effective(p_clinic_id,auth.uid(),'hospital.manage') is not null,'patient.read',private.permission_effective(p_clinic_id,auth.uid(),'patient.read') is not null),
 'stays',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('vet_patients',jsonb_build_object('name',p.name,'species',p.species)) order by s.cage nulls last) from public.hospital_stays s join public.vet_patients p on p.id=s.patient_id and p.clinic_id=s.clinic_id where s.clinic_id=p_clinic_id and s.discharged_at is null),'[]'::jsonb),
 'tasks',coalesce((select jsonb_agg(to_jsonb(t) order by t.due_at) from public.hospital_tasks t join public.hospital_stays s on s.id=t.stay_id and s.clinic_id=t.clinic_id where t.clinic_id=p_clinic_id and s.discharged_at is null),'[]'::jsonb));
end$$;
create or replace function public.hospital_admit(p_clinic_id uuid,p_patient_id uuid,p_cage text,p_operation_id text) returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;g uuid;fp jsonb;cage_label text=nullif(btrim(p_cage),'');begin
 perform 1 from public.clinics where clinics.id=p_clinic_id for update;
 g=private.hospital_permission(p_clinic_id,'hospital.manage');
 perform private.hospital_permission(p_clinic_id,'patient.read');
 fp=jsonb_build_object('kind','hospital_admit','patient',p_patient_id,'cage',p_cage);
 id=private.vet_receipt(p_clinic_id,p_operation_id,fp);if id is not null then return id;end if;
 if cage_label is not null and length(cage_label)>80 then raise exception 'invalid_cage';end if;
 if not exists(select 1 from public.vet_patients p where p.clinic_id=p_clinic_id and p.id=p_patient_id) then raise exception 'patient_wrong_clinic';end if;
 insert into public.hospital_stays(clinic_id,patient_id,cage,admitted_by) values(p_clinic_id,p_patient_id,cage_label,auth.uid()) returning hospital_stays.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic_id,p_operation_id,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic_id,auth.uid(),'hospital_admitted',id,jsonb_build_object('cage',cage_label,'permission_grant_id',g));
 return id;
end$$;
create function public.hospital_cage_set(p_clinic_id uuid,p_stay_id uuid,p_version integer,p_cage text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare s public.hospital_stays;id uuid;g uuid;fp jsonb;cage_label text=nullif(btrim(p_cage),'');begin
 perform 1 from public.clinics where clinics.id=p_clinic_id for update;
 g=private.hospital_permission(p_clinic_id,'hospital.manage');
 fp=jsonb_build_object('kind','hospital_cage','stay',p_stay_id,'version',p_version,'cage',p_cage,'reason',p_reason);
 id=private.vet_receipt(p_clinic_id,p_operation,fp);if id is not null then return id;end if;
 select * into s from public.hospital_stays where hospital_stays.id=p_stay_id and clinic_id=p_clinic_id for update;
 if not found then raise exception 'hospital_stay_not_found';end if;
 if s.discharged_at is not null then raise exception 'hospital_stay_closed';end if;
 if s.version is distinct from p_version then raise exception 'hospital_version_conflict';end if;
 if (cage_label is not null and length(cage_label)>80) or length(coalesce(p_reason,''))>1000 then raise exception 'invalid_cage';end if;
 if cage_label is distinct from s.cage then
 update public.hospital_stays set cage=cage_label,version=version+1 where hospital_stays.id=s.id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic_id,auth.uid(),'hospital_cage_changed',s.id,jsonb_build_object('from',s.cage,'to',cage_label,'previous_version',s.version,'version',s.version+1,'reason',nullif(btrim(p_reason),''),'permission_grant_id',g));
 end if;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic_id,p_operation,fp,s.id);return s.id;
end$$;
create function public.hospital_cage_history(p_clinic_id uuid,p_stay_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.hospital_readable(p_clinic_id) then raise exception 'explicit_permission_required';end if;
 if not exists(select 1 from public.hospital_stays where clinic_id=p_clinic_id and id=p_stay_id) then raise exception 'hospital_stay_not_found';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('actor_id',a.actor_id,'at',a.occurred_at,'action',a.action,'details',a.details) order by a.occurred_at,a.id),'[]') from public.audit_log a where a.clinic_id=p_clinic_id and a.entity_id=p_stay_id::text and a.action in ('hospital_admitted','hospital_cage_changed'));
end$$;
revoke all on function public.hospital_cage_set(uuid,uuid,integer,text,text,text),public.hospital_cage_history(uuid,uuid) from public,anon;
grant execute on function public.hospital_cage_set(uuid,uuid,integer,text,text,text),public.hospital_cage_history(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
