-- Candidate migration: broader appointment lookup and additional appointment kinds.
-- Review with the existing permission cutover before deployment.
begin;
alter table public.clinic_appointments
  drop constraint if exists clinic_appointments_kind_check;
alter table public.clinic_appointments
  add constraint clinic_appointments_kind_check
  check (kind in ('consulta','seguimiento','estetica','cirugia','analisis','hospital_visita','vacunacion','entrega','otro'));

create or replace function public.ops_patient_search(p_clinic uuid,p_query text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare q text:=lower(btrim(p_query)); can_clinical boolean;
begin
  perform private.permission_require(p_clinic,'patient.read');
  if q is null or char_length(q) not between 1 and 120 then raise exception 'patient_search_required'; end if;
  can_clinical:=private.permission_effective(p_clinic,auth.uid(),'clinical.read') is not null;
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'name',p.name,'species',p.species,
    'owner_name',o.name,'owner_phone',o.phone,
    'clinical_match',can_clinical and exists(select 1 from public.vet_patient_events e where e.clinic_id=p_clinic and e.patient_id=p.id and lower(coalesce(e.payload->>'notes','')) like '%'||q||'%')
  ) order by p.name,p.id),'[]') from public.vet_patients p
  left join public.vet_owners o on o.clinic_id=p.clinic_id and o.id=p.owner_id
  where p.clinic_id=p_clinic and (
    lower(p.name) like '%'||q||'%' or lower(p.species) like '%'||q||'%'
    or lower(coalesce(o.name,'')) like '%'||q||'%' or lower(coalesce(o.phone,'')) like '%'||q||'%'
    or (can_clinical and exists(select 1 from public.vet_patient_events e where e.clinic_id=p_clinic and e.patient_id=p.id and lower(coalesce(e.payload->>'notes','')) like '%'||q||'%'))
  ) limit 50);
end$$;
notify pgrst,'reload schema';
commit;
