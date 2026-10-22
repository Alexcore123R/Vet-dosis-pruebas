-- Apply after 14M (requires weekly planning from 14L).
-- Reviewed tasks and their source plan commit together; AI never writes directly.
begin;
create table if not exists public.clinic_week_plan_batches (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),
 week_start date not null,content_hash text not null check(length(content_hash)=64),
 plan_body text not null check(length(plan_body) between 1 and 12000),
 tasks jsonb not null check(jsonb_typeof(tasks)='array' and octet_length(tasks::text)<=60000),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(clinic_id,week_start,content_hash)
);
alter table public.clinic_week_plan_batches enable row level security;
revoke all on public.clinic_week_plan_batches from public,anon,authenticated;
alter table public.clinic_tasks add column if not exists plan_batch_id uuid references public.clinic_week_plan_batches(id);
alter table public.clinic_tasks add column if not exists plan_item integer;
create unique index if not exists clinic_task_plan_item on public.clinic_tasks(clinic_id,plan_batch_id,plan_item) where plan_batch_id is not null;

create or replace function public.ops_week_plan_commit(p_clinic uuid,p_week date,p_expected_body text,p_body text,p_tasks jsonb,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;fp jsonb;row jsonb;normalized jsonb='[]';v_hash text;v_current text;profile jsonb;
 who uuid;d date;minutes integer;capacity integer;v_title text;v_area text;v_note text;v_priority text;n integer=0;
begin
 if not private.team_plan(p_clinic) or not private.ops_permission_active(p_clinic,'team.manage') then raise exception 'team_manage_required';end if;
 perform private.permission_require(p_clinic,'team.manage');
 if p_week is null or extract(isodow from p_week)<>1 then raise exception 'monday_required';end if;
 if p_body is null or length(btrim(p_body)) not between 1 and 12000 or coalesce(length(p_expected_body),0)>12000 then raise exception 'plan_body_invalid';end if;
 if jsonb_typeof(p_tasks) is distinct from 'array' or jsonb_array_length(p_tasks) not between 1 and 40 or octet_length(p_tasks::text)>60000 then raise exception 'reviewed_tasks_required';end if;
 fp=jsonb_build_object('kind','week_plan_commit','week',p_week,'expected',p_expected_body,'body',p_body,'tasks',p_tasks);
 v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 for row in select value from jsonb_array_elements(p_tasks) loop
  if jsonb_typeof(row) is distinct from 'object' then raise exception 'task_fields_invalid';end if;
  if exists(select 1 from jsonb_object_keys(row) k where k not in ('title','area','instructions','scheduled_on','assigned_to','estimated_minutes','priority')) then raise exception 'task_fields_invalid';end if;
  v_title=btrim(coalesce(row->>'title',''));v_area=btrim(coalesce(row->>'area',''));v_note=btrim(coalesce(row->>'instructions',''));v_priority=coalesce(row->>'priority','media');
  if length(v_title) not between 1 and 150 or length(v_area)>150 or length(v_note)>2000 or v_priority not in ('baja','media','urgente') or coalesce(row->>'estimated_minutes','') !~ '^[0-9]{1,3}$' then raise exception 'task_fields_invalid';end if;
  minutes=(row->>'estimated_minutes')::integer;d=(row->>'scheduled_on')::date;who=nullif(row->>'assigned_to','')::uuid;
  if minutes not between 1 and 480 or d is null or d<p_week or d>p_week+6 then raise exception 'task_week_or_duration_invalid';end if;
  normalized=normalized||jsonb_build_array(jsonb_build_object('title',v_title,'area',v_area,'instructions',v_note,'priority',v_priority,'estimated_minutes',minutes,'scheduled_on',d,'assigned_to',who));
 end loop;
 select jsonb_agg(value order by value->>'scheduled_on',value->>'title',value->>'assigned_to',value::text) into normalized from jsonb_array_elements(normalized);
 v_hash=encode(sha256(convert_to(jsonb_build_object('body',btrim(p_body),'tasks',normalized)::text,'UTF8')),'hex');
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('planning:'||p_clinic::text,0));
 select id into v_id from public.clinic_week_plan_batches where clinic_id=p_clinic and week_start=p_week and content_hash=v_hash;
 if found then
  insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);return v_id;
 end if;
 -- Create/lock the plan row before checking for edits made in another session.
 insert into public.clinic_week_plans(clinic_id,week_start,body,updated_by) values(p_clinic,p_week,'',auth.uid()) on conflict(clinic_id,week_start) do nothing;
 select body into v_current from public.clinic_week_plans where clinic_id=p_clinic and week_start=p_week for update;
 if v_current is distinct from coalesce(p_expected_body,'') then raise exception 'week_plan_changed_refresh';end if;
 select details into profile from public.clinic_productivity_profiles where clinic_id=p_clinic for share;
 capacity=coalesce((profile->>'daily_minutes')::integer,60);
 insert into public.clinic_week_plan_batches(clinic_id,week_start,content_hash,plan_body,tasks,created_by)
 values(p_clinic,p_week,v_hash,btrim(p_body),normalized,auth.uid()) returning id into v_id;
 for row in select value from jsonb_array_elements(normalized) loop
  who=nullif(row->>'assigned_to','')::uuid;d=(row->>'scheduled_on')::date;minutes=(row->>'estimated_minutes')::integer;n=n+1;
  if who is not null then
   perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=who for share;
   if not found then raise exception 'assignee_wrong_clinic';end if;
   if profile->'availability'->who::text is not null and not (profile->'availability'->who::text @> to_jsonb(array[extract(isodow from d)::integer-1])) then raise exception 'assignee_unavailable';end if;
   if coalesce((select sum(estimated_minutes) from public.clinic_tasks where clinic_id=p_clinic and scheduled_on=d and assigned_to=who),0)+minutes>capacity then raise exception 'daily_task_capacity_exceeded';end if;
  end if;
  if exists(select 1 from public.clinic_tasks where clinic_id=p_clinic and scheduled_on=d and lower(btrim(title))=lower(row->>'title') and btrim(area)=row->>'area' and assigned_to is not distinct from who) then raise exception 'task_already_scheduled';end if;
  insert into public.clinic_tasks(clinic_id,title,area,instructions,priority,estimated_minutes,scheduled_on,assigned_to,created_by,plan_batch_id,plan_item)
  values(p_clinic,row->>'title',row->>'area',row->>'instructions',row->>'priority',minutes,d,who,auth.uid(),v_id,n);
 end loop;
 update public.clinic_week_plans set body=btrim(p_body),updated_by=auth.uid(),updated_at=clock_timestamp() where clinic_id=p_clinic and week_start=p_week;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'week_plan_tasks_commit',v_id::text,jsonb_build_object('week',p_week,'count',n));
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);return v_id;
end$$;
revoke all on function public.ops_week_plan_commit(uuid,date,text,text,jsonb,text) from public,anon;
grant execute on function public.ops_week_plan_commit(uuid,date,text,text,jsonb,text) to authenticated;
select private.beta_install_guards();
commit;
notify pgrst, 'reload schema';
