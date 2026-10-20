-- Additive read-only endpoint. Requires permission foundation, M4/M5/M8/M9.
-- Review remote schema before deployment. No historical 01-08 scripts are rerun.
begin;
create function public.patient_activity_snapshot(p_clinic uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tz text; d date; start_at timestamptz; end_at timestamptz;
  can_hospital boolean; can_appointments boolean; rows jsonb;
begin
  perform private.permission_require(p_clinic,'patient.read');
  can_hospital := private.permission_effective(p_clinic,auth.uid(),'hospital.read') is not null;
  can_appointments := private.permission_effective(p_clinic,auth.uid(),'appointment.read') is not null;
  select coalesce(s.timezone,'America/Mexico_City') into tz
    from public.inventory_clinic_settings s where s.clinic_id=p_clinic;
  tz := coalesce(tz,'America/Mexico_City');
  d := (statement_timestamp() at time zone tz)::date;
  start_at := d::timestamp at time zone tz;
  end_at := (d+1)::timestamp at time zone tz;
  select coalesce(jsonb_agg(x.payload order by x.sort_at,x.record_id),'[]'::jsonb)
  into rows from (
    select s.admitted_at sort_at,s.id record_id,jsonb_build_object(
      'patient_id',s.patient_id,'record_id',s.id,'kind','hospitalized',
      'detail','Estancia activa · Jaula: '||coalesce(nullif(btrim(s.cage),''),'Sin asignar'),
      'local_time',to_char(s.admitted_at at time zone tz,'YYYY-MM-DD HH24:MI'),
      'responsible','') payload
    from public.hospital_stays s
    join public.vet_patients p on p.clinic_id=s.clinic_id and p.id=s.patient_id
    where s.clinic_id=p_clinic and can_hospital and s.discharged_at is null
    union all
    select a.starts_at,a.id,jsonb_build_object(
      'patient_id',a.patient_id,'record_id',a.id,
      'kind',case when a.state='listo' then 'ready'
        when a.kind='consulta' then 'consultation' else 'service' end,
      'detail',case a.kind when 'consulta' then 'Consulta' else 'Estética' end||
        case when a.starts_at<start_at then ' · Pendiente de día anterior' else '' end||
        case when nullif(btrim(a.notes),'') is null then '' else ' · '||a.notes end,
      'local_time',to_char(a.starts_at at time zone tz,'YYYY-MM-DD HH24:MI'),
      'responsible',coalesce(n.name,''))
    from public.clinic_appointments a
    join public.vet_patients p on p.clinic_id=a.clinic_id and p.id=a.patient_id
    left join public.staff_display_names n on n.clinic_id=a.clinic_id and n.user_id=a.professional_id
    where a.clinic_id=p_clinic and can_appointments
      and a.starts_at<end_at and a.state in ('en_atencion','listo')
  ) x;
  return jsonb_build_object('schema_version',1,'clinic_id',p_clinic,
    'day',d,'timezone',tz,'server_time',statement_timestamp(),
    'hospital_allowed',can_hospital,'appointments_allowed',can_appointments,'items',rows);
end $$;
revoke all on function public.patient_activity_snapshot(uuid) from public,anon;
grant execute on function public.patient_activity_snapshot(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
