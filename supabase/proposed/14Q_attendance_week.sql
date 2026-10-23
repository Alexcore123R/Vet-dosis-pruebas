-- Apply after 14P. Weekly punctuality uses server times and a clinic-defined start.
begin;
create table public.clinic_attendance_schedule (
 clinic_id uuid primary key references public.clinics(id),
 start_local time not null,
 weekdays integer[] not null check(cardinality(weekdays) between 1 and 7 and weekdays <@ array[1,2,3,4,5,6,7]),
 grace_minutes integer not null check(grace_minutes between 0 and 120),
 updated_at timestamptz not null default clock_timestamp(),
 updated_by uuid not null references auth.users(id)
);
alter table public.clinic_attendance_schedule enable row level security;
revoke all on public.clinic_attendance_schedule from public,anon,authenticated;
create index if not exists attendance_week_events on public.attendance_events(clinic_id,user_id,server_at desc) where direction='entrada';

create function public.att_schedule_save(p_clinic uuid,p_start time,p_weekdays integer[],p_grace integer)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 if not private.team_plan(p_clinic) then raise exception 'clinic_plan_required';end if;
 if p_start is null or p_weekdays is null or cardinality(p_weekdays) not between 1 and 7 or
    p_weekdays <> (select array_agg(distinct x order by x) from unnest(p_weekdays) x) or
    not p_weekdays <@ array[1,2,3,4,5,6,7] or p_grace not between 0 and 120 then
   raise exception 'invalid_attendance_schedule';
 end if;
 insert into public.clinic_attendance_schedule(clinic_id,start_local,weekdays,grace_minutes,updated_by)
 values(p_clinic,p_start,p_weekdays,p_grace,auth.uid())
 on conflict(clinic_id) do update set start_local=excluded.start_local,weekdays=excluded.weekdays,
  grace_minutes=excluded.grace_minutes,updated_at=clock_timestamp(),updated_by=auth.uid();
 insert into public.audit_log(clinic_id,actor_id,action,entity_id)
 values(p_clinic,auth.uid(),'attendance_schedule_updated',p_clinic::text);
end$$;
revoke all on function public.att_schedule_save(uuid,time,integer[],integer) from public,anon;
grant execute on function public.att_schedule_save(uuid,time,integer[],integer) to authenticated;

alter function public.att_qr(uuid) rename to att_qr_before_admin_only;
revoke all on function public.att_qr_before_admin_only(uuid) from public,anon,authenticated;
create function public.att_qr(p_clinic uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 return public.att_qr_before_admin_only(p_clinic);
end$$;
revoke all on function public.att_qr(uuid) from public,anon;
grant execute on function public.att_qr(uuid) to authenticated;

alter function public.att_dashboard(uuid) rename to att_dashboard_before_week;
revoke all on function public.att_dashboard_before_week(uuid) from public,anon,authenticated;
create function public.att_dashboard(p_clinic uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare snapshot jsonb;s public.clinic_attendance_schedule;zone text;week_start date;summary jsonb;is_admin boolean;
begin
 snapshot=public.att_dashboard_before_week(p_clinic);
 is_admin=private.has_clinic_role(p_clinic,array['admin']);
 select * into s from public.clinic_attendance_schedule where clinic_id=p_clinic;
 zone=private.inv_timezone(p_clinic);
 week_start=date_trunc('week',clock_timestamp() at time zone zone)::date;
 with first_entries as (
  select e.user_id,(coalesce(c.corrected_at,e.server_at) at time zone zone)::date as local_day,
   min((coalesce(c.corrected_at,e.server_at) at time zone zone)::time) as first_in
  from public.attendance_events e
  left join lateral (select corrected_at from public.attendance_corrections
    where event_id=e.id order by created_at desc,id desc limit 1) c on true
  where e.clinic_id=p_clinic and e.direction='entrada' and (is_admin or e.user_id=auth.uid())
   and e.server_at >= (week_start::timestamp at time zone zone) - interval '1 day'
   and e.server_at < ((week_start+7)::timestamp at time zone zone) + interval '1 day'
  group by e.user_id,(coalesce(c.corrected_at,e.server_at) at time zone zone)::date
 )
 select jsonb_build_object(
  'configured',s.clinic_id is not null,'week_start',week_start,
  'attended',count(*) filter(where local_day between week_start and week_start+6 and
   (s.clinic_id is null or extract(isodow from local_day)::integer=any(s.weekdays))),
  'on_time',case when s.clinic_id is null then null else count(*) filter(where
   local_day between week_start and week_start+6 and extract(isodow from local_day)::integer=any(s.weekdays)
   and first_in <= s.start_local + make_interval(mins=>s.grace_minutes)) end,
  'late',case when s.clinic_id is null then null else count(*) filter(where
   local_day between week_start and week_start+6 and extract(isodow from local_day)::integer=any(s.weekdays)
   and first_in > s.start_local + make_interval(mins=>s.grace_minutes)) end,
  'start_local',case when s.clinic_id is null then null else s.start_local::text end,
  'grace_minutes',s.grace_minutes)
 into summary from first_entries;
 return snapshot || jsonb_build_object('week_summary',summary,
  'schedule',case when s.clinic_id is null then null else jsonb_build_object(
   'start_local',s.start_local::text,'weekdays',s.weekdays,'grace_minutes',s.grace_minutes) end);
end$$;
revoke all on function public.att_dashboard(uuid) from public,anon;
grant execute on function public.att_dashboard(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
