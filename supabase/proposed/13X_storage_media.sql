-- Stage 2B.30: private Storage contracts for patient photos and clinical attachments.
-- LOCAL CANDIDATE ONLY. No remote bucket or policy deployment is performed here.
begin;

insert into private.permission_catalog(code,label,procedure_scoped,requires_professional)
values('clinical.attach','Adjuntar archivos al expediente clínico',false,false)
on conflict(code) do nothing;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values
 ('patient-photos','patient-photos',false,8000000,array['image/png','image/jpeg','image/webp']),
 ('clinical-attachments','clinical-attachments',false,20000000,array['image/png','image/jpeg','image/webp','application/pdf'])
on conflict(id) do update set
 public=false,
 file_size_limit=excluded.file_size_limit,
 allowed_mime_types=excluded.allowed_mime_types;

create function private.storage_safe_uuid(value text)
returns uuid language plpgsql immutable set search_path='' as $$
begin
 return value::uuid;
exception when others then
 return null;
end$$;

create function private.storage_patient_photo_allowed(p_name text,p_write boolean)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare
 parts text[];
 clinic uuid;
 patient uuid;
 grant_id uuid;
begin
 if auth.uid() is null then return false;end if;
 parts=string_to_array(p_name,'/');
 if array_length(parts,1)<>3 or parts[1]='' or parts[2]='' or parts[3] not in ('photo.png','photo.jpg','photo.jpeg','photo.webp') then return false;end if;
 clinic=private.storage_safe_uuid(parts[1]);
 patient=private.storage_safe_uuid(parts[2]);
 if clinic is null or patient is null or not exists(
  select 1 from public.vet_patients p where p.id=patient and p.clinic_id=clinic
 ) then return false;end if;
 grant_id=private.permission_effective(
  clinic,auth.uid(),case when p_write then 'patient.write' else 'patient.read' end
 );
 return grant_id is not null and exists(
  select 1 from private.member_permission_grants g
  where g.id=grant_id and g.valid_until>clock_timestamp()
 );
end$$;

create function private.storage_clinical_attachment_allowed(p_name text,p_write boolean)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare
 parts text[];
 clinic uuid;
 case_id uuid;
 object_name text;
 object_id uuid;
 c public.clinical_cases;
 grant_id uuid;
 extension text;
begin
 if auth.uid() is null then return false;end if;
 parts=string_to_array(p_name,'/');
 if array_length(parts,1)<>3 or parts[1]='' or parts[2]='' or parts[3]='' then return false;end if;
 clinic=private.storage_safe_uuid(parts[1]);
 case_id=private.storage_safe_uuid(parts[2]);
 object_name=parts[3];
 if clinic is null or case_id is null or object_name !~ '^[0-9a-fA-F-]{36}[.][A-Za-z0-9]+$' then return false;end if;
 object_id=private.storage_safe_uuid(split_part(object_name,'.',1));
 extension=lower(split_part(object_name,'.',2));
 if object_id is null or extension not in ('png','jpg','jpeg','webp','pdf') then return false;end if;
 select * into c from public.clinical_cases where id=case_id and clinic_id=clinic;
 if not found or not private.clinical_readable(c) then return false;end if;
 if not p_write then return true;end if;
 grant_id=private.permission_effective(clinic,auth.uid(),'clinical.attach');
 return grant_id is not null and exists(
  select 1 from private.member_permission_grants g
  where g.id=grant_id and g.valid_until>clock_timestamp()
 );
end$$;

revoke all on function private.storage_safe_uuid(text) from public,anon,authenticated,service_role;
revoke all on function private.storage_patient_photo_allowed(text,boolean),
 private.storage_clinical_attachment_allowed(text,boolean)
from public,anon,service_role;
grant execute on function private.storage_patient_photo_allowed(text,boolean),
 private.storage_clinical_attachment_allowed(text,boolean)
to authenticated;

create policy patient_photo_read on storage.objects
for select to authenticated
using(bucket_id='patient-photos' and private.storage_patient_photo_allowed(name,false));

create policy patient_photo_insert on storage.objects
for insert to authenticated
with check(bucket_id='patient-photos' and private.storage_patient_photo_allowed(name,true));

create policy patient_photo_update on storage.objects
for update to authenticated
using(bucket_id='patient-photos' and private.storage_patient_photo_allowed(name,true))
with check(bucket_id='patient-photos' and private.storage_patient_photo_allowed(name,true));

create policy patient_photo_delete on storage.objects
for delete to authenticated
using(bucket_id='patient-photos' and private.storage_patient_photo_allowed(name,true));

create policy clinical_attachment_read on storage.objects
for select to authenticated
using(bucket_id='clinical-attachments' and private.storage_clinical_attachment_allowed(name,false));

create policy clinical_attachment_insert on storage.objects
for insert to authenticated
with check(bucket_id='clinical-attachments' and private.storage_clinical_attachment_allowed(name,true));

create policy clinical_attachment_update on storage.objects
for update to authenticated
using(bucket_id='clinical-attachments' and private.storage_clinical_attachment_allowed(name,true))
with check(bucket_id='clinical-attachments' and private.storage_clinical_attachment_allowed(name,true));

create policy clinical_attachment_delete on storage.objects
for delete to authenticated
using(bucket_id='clinical-attachments' and private.storage_clinical_attachment_allowed(name,true));

notify pgrst,'reload schema';
commit;
