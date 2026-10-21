-- Apply after 14K and the clinic operations permissions (13B1).
-- Weekly routines are materialized as ordinary clinic_tasks, preserving history.
begin;
alter table public.clinic_tasks add column if not exists scheduled_on date;
alter table public.clinic_tasks add column if not exists estimated_minutes integer not null default 15 check(estimated_minutes between 1 and 480);
alter table public.clinic_tasks add column if not exists area text not null default '' check(length(area)<=150);
alter table public.clinic_tasks add column if not exists instructions text not null default '' check(length(instructions)<=2000);
alter table public.clinic_tasks add column if not exists routine_id uuid;
alter table public.clinic_tasks add column if not exists planning_version integer not null default 1;
create unique index if not exists clinic_task_routine_day on public.clinic_tasks(clinic_id,routine_id,scheduled_on) where routine_id is not null;
create index if not exists clinic_task_week on public.clinic_tasks(clinic_id,scheduled_on);
create table if not exists public.clinic_productivity_profiles (
 clinic_id uuid primary key references public.clinics(id),
 details jsonb not null default '{}' check(jsonb_typeof(details)='object' and octet_length(details::text)<=16000),
 updated_by uuid not null references auth.users(id),updated_at timestamptz not null default clock_timestamp()
);
create table if not exists public.clinic_task_routines (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),
 title text not null check(length(btrim(title)) between 1 and 150),area text not null default '' check(length(area)<=150),
 instructions text not null default '' check(length(instructions)<=2000),
 weekdays integer[] not null check(cardinality(weekdays) between 1 and 7 and weekdays <@ array[0,1,2,3,4,5,6]),
 assignees uuid[] not null default '{}',estimated_minutes integer not null check(estimated_minutes between 1 and 480),
 active boolean not null default true,version integer not null default 1,created_by uuid not null references auth.users(id)
);
create table if not exists public.clinic_week_plans (
 clinic_id uuid not null references public.clinics(id),week_start date not null,
 body text not null check(length(body)<=12000),updated_by uuid not null references auth.users(id),
 updated_at timestamptz not null default clock_timestamp(),primary key(clinic_id,week_start)
);
do $$declare t text;begin
 foreach t in array array['clinic_productivity_profiles','clinic_task_routines','clinic_week_plans'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
end$$;
create or replace function public.ops_productivity_read(p_clinic uuid,p_week date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_manage boolean;v_read boolean;
begin
 v_manage=private.ops_permission_active(p_clinic,'team.manage');
 v_read=private.ops_permission_active(p_clinic,'team.read');
 if not (v_manage or v_read) or not private.team_plan(p_clinic) then raise exception 'team_access_required';end if;
 if p_week is null or extract(isodow from p_week)<>1 then raise exception 'monday_required';end if;
 return jsonb_build_object('can_manage',v_manage,'can_profile',v_manage and private.has_clinic_role(p_clinic,array['admin']),
 'profile',case when v_manage then coalesce((select details from public.clinic_productivity_profiles where clinic_id=p_clinic),'{}') else '{}'::jsonb end,
 'plan',case when v_manage then coalesce((select body from public.clinic_week_plans where clinic_id=p_clinic and week_start=p_week),'') else '' end,
 'routines',case when v_manage then coalesce((select jsonb_agg(to_jsonb(r) order by r.title) from public.clinic_task_routines r where r.clinic_id=p_clinic and r.active),'[]') else '[]'::jsonb end,
 'members',coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'name',coalesce(n.name,'Integrante del equipo'))) from public.clinic_members m left join public.staff_display_names n using(clinic_id,user_id) where m.clinic_id=p_clinic),'[]'),
 'tasks',coalesce((select jsonb_agg(to_jsonb(t) order by t.scheduled_on,t.created_at) from public.clinic_tasks t where t.clinic_id=p_clinic and t.scheduled_on between p_week and p_week+6 and (v_manage or t.assigned_to=auth.uid() or t.assigned_to is null)),'[]'));
end$$;
revoke all on function public.ops_productivity_read(uuid,date) from public,anon;
grant execute on function public.ops_productivity_read(uuid,date) to authenticated;

create or replace function public.ops_productivity_write(p_clinic uuid,p_action text,p_data jsonb,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_manage boolean;v_id uuid;fp jsonb;r public.clinic_task_routines%rowtype;d date;w date;who uuid;profile jsonb;days jsonb;capacity integer;
begin
 v_manage=private.ops_permission_active(p_clinic,'team.manage');
 if not private.team_plan(p_clinic) or not (v_manage or (p_action='complete' and private.ops_permission_active(p_clinic,'team.read'))) then raise exception 'team_access_required';end if;
 perform private.permission_require(p_clinic,case when v_manage then 'team.manage' else 'team.read' end);
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>20000 then raise exception 'invalid_data';end if;
 fp=jsonb_build_object('kind','productivity','action',p_action,'data',p_data);
 v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 if p_action='profile' then
  if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
  if jsonb_typeof(p_data->'availability') is distinct from 'object' then raise exception 'availability_required';end if;
  for who,days in select key::uuid,value from jsonb_each(p_data->'availability') loop
   if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=who) or jsonb_typeof(days) is distinct from 'array' or jsonb_array_length(days)>7 then raise exception 'invalid_availability';end if;
   if exists(select 1 from jsonb_array_elements_text(days) x where x::integer not between 0 and 6) then raise exception 'invalid_weekday';end if;
  end loop;
  capacity=coalesce(nullif(p_data->>'daily_minutes','')::integer,60);
  if capacity not between 1 and 480 then raise exception 'invalid_capacity';end if;
  insert into public.clinic_productivity_profiles(clinic_id,details,updated_by) values(p_clinic,p_data,auth.uid())
  on conflict(clinic_id) do update set details=excluded.details,updated_by=auth.uid(),updated_at=clock_timestamp();
  v_id=p_clinic;
 elsif p_action='routine' then
  if exists(select 1 from jsonb_array_elements_text(p_data->'assignees') x where not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=x::uuid)) then raise exception 'assignee_wrong_clinic';end if;
  v_id=nullif(p_data->>'id','')::uuid;
  if v_id is null then
   insert into public.clinic_task_routines(clinic_id,title,area,instructions,weekdays,assignees,estimated_minutes,created_by)
   values(p_clinic,btrim(p_data->>'title'),coalesce(p_data->>'area',''),coalesce(p_data->>'instructions',''),array(select x::integer from jsonb_array_elements_text(p_data->'weekdays') x),array(select x::uuid from jsonb_array_elements_text(p_data->'assignees') x),(p_data->>'estimated_minutes')::integer,auth.uid()) returning id into v_id;
  else
   update public.clinic_task_routines set title=btrim(p_data->>'title'),area=coalesce(p_data->>'area',''),instructions=coalesce(p_data->>'instructions',''),weekdays=array(select x::integer from jsonb_array_elements_text(p_data->'weekdays') x),assignees=array(select x::uuid from jsonb_array_elements_text(p_data->'assignees') x),estimated_minutes=(p_data->>'estimated_minutes')::integer,version=version+1
   where clinic_id=p_clinic and id=v_id and active and version=(p_data->>'version')::integer;
   if not found then raise exception 'routine_changed_refresh';end if;
  end if;
 elsif p_action='archive' then
  v_id=(p_data->>'id')::uuid;
  update public.clinic_task_routines set active=false,version=version+1 where clinic_id=p_clinic and id=v_id and version=(p_data->>'version')::integer;
  if not found then raise exception 'routine_changed_refresh';end if;
 elsif p_action='generate' then
  w=(p_data->>'week')::date;
  if w is null or extract(isodow from w)<>1 then raise exception 'monday_required';end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('planning:'||p_clinic::text,0));
  select details into profile from public.clinic_productivity_profiles where clinic_id=p_clinic;
  capacity=coalesce((profile->>'daily_minutes')::integer,60);
  for d in select generate_series(w::timestamp,(w+6)::timestamp,'1 day')::date loop
   for r in select * from public.clinic_task_routines where clinic_id=p_clinic and active and (extract(isodow from d)::integer-1)=any(weekdays) order by estimated_minutes desc,id loop
    if exists(select 1 from public.clinic_tasks where clinic_id=p_clinic and routine_id=r.id and scheduled_on=d) then continue;end if;
    who=null;
    select member.user_id into who from unnest(r.assignees) with ordinality a(user_id,ord)
    join public.clinic_members member on member.clinic_id=p_clinic and member.user_id=a.user_id
    where (profile->'availability'->(a.user_id::text) is null or (profile->'availability'->(a.user_id::text)) @> to_jsonb(array[extract(isodow from d)::integer-1]))
    and coalesce((select sum(t.estimated_minutes) from public.clinic_tasks t where t.clinic_id=p_clinic and t.assigned_to=a.user_id and t.scheduled_on=d),0)+r.estimated_minutes<=capacity
    order by coalesce((select sum(t.estimated_minutes) from public.clinic_tasks t where t.clinic_id=p_clinic and t.assigned_to=a.user_id and t.scheduled_on between w and w+6),0),mod(a.ord+(w-date '2020-01-06')/7, greatest(cardinality(r.assignees),1)) limit 1;
    insert into public.clinic_tasks(clinic_id,title,assigned_to,priority,created_by,scheduled_on,area,instructions,estimated_minutes,routine_id)
    values(p_clinic,r.title,who,'media',auth.uid(),d,r.area,r.instructions,r.estimated_minutes,r.id);
   end loop;
  end loop;
  v_id=p_clinic;
 elsif p_action='task' then
  v_id=nullif(p_data->>'id','')::uuid;who=nullif(p_data->>'assigned_to','')::uuid;
  if who is not null and not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=who) then raise exception 'assignee_wrong_clinic';end if;
  if nullif(p_data->>'scheduled_on','') is null then raise exception 'task_date_required';end if;
  if v_id is null then
   insert into public.clinic_tasks(clinic_id,title,assigned_to,priority,created_by,scheduled_on,area,instructions,estimated_minutes)
   values(p_clinic,btrim(p_data->>'title'),who,coalesce(p_data->>'priority','media'),auth.uid(),(p_data->>'scheduled_on')::date,coalesce(p_data->>'area',''),coalesce(p_data->>'instructions',''),(p_data->>'estimated_minutes')::integer) returning id into v_id;
  else
   update public.clinic_tasks set title=btrim(p_data->>'title'),assigned_to=who,scheduled_on=(p_data->>'scheduled_on')::date,area=coalesce(p_data->>'area',''),instructions=coalesce(p_data->>'instructions',''),estimated_minutes=(p_data->>'estimated_minutes')::integer,planning_version=planning_version+1
   where clinic_id=p_clinic and id=v_id and completed_at is null and planning_version=(p_data->>'planning_version')::integer;
   if not found then raise exception 'task_changed_refresh';end if;
  end if;
 elsif p_action='complete' then
  v_id=(p_data->>'id')::uuid;
  update public.clinic_tasks set completed_at=clock_timestamp(),completed_by=auth.uid(),planning_version=planning_version+1
  where clinic_id=p_clinic and id=v_id and completed_at is null and (v_manage or assigned_to=auth.uid() or assigned_to is null);
  if not found then raise exception 'task_unavailable';end if;
 elsif p_action='plan' then
  w=(p_data->>'week')::date;
  if w is null or extract(isodow from w)<>1 then raise exception 'monday_required';end if;
  insert into public.clinic_week_plans(clinic_id,week_start,body,updated_by) values(p_clinic,w,p_data->>'body',auth.uid())
  on conflict(clinic_id,week_start) do update set body=excluded.body,updated_by=auth.uid(),updated_at=clock_timestamp();v_id=p_clinic;
 else raise exception 'unknown_productivity_action';end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'productivity_'||p_action,v_id::text);
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 return v_id;
end$$;
revoke all on function public.ops_productivity_write(uuid,text,jsonb,text) from public,anon;
grant execute on function public.ops_productivity_write(uuid,text,jsonb,text) to authenticated;
select private.beta_install_guards();
commit;
notify pgrst, 'reload schema';
