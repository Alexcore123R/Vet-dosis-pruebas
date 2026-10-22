-- Apply after 14O. Mentions are visible only within the same clinic.
begin;
alter table public.clinic_messages add column if not exists mentioned_user_ids uuid[] not null default '{}';
alter table public.clinic_tasks add column if not exists mentioned_user_ids uuid[] not null default '{}';
create index if not exists clinic_tasks_mentions_idx on public.clinic_tasks using gin(mentioned_user_ids);

alter function public.ops_write(uuid,text,jsonb,text) rename to ops_write_before_team_mentions;
revoke all on function public.ops_write_before_team_mentions(uuid,text,jsonb,text) from public,anon,authenticated;
create function public.ops_write(p_clinic uuid,p_action text,p_data jsonb,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare ids uuid[]='{}';v_id uuid;fp jsonb;
begin
 if p_action in ('task','message') and p_data ? 'mentioned_user_ids' then
  if jsonb_typeof(p_data->'mentioned_user_ids') <> 'array' or jsonb_array_length(p_data->'mentioned_user_ids') > 30 then
   raise exception 'invalid_mentions';
  end if;
  select coalesce(array_agg(distinct value::uuid),'{}'::uuid[]) into ids
  from jsonb_array_elements_text(p_data->'mentioned_user_ids') e(value);
  if exists(select 1 from unnest(ids) x where not exists(
    select 1 from public.clinic_members m where m.clinic_id=p_clinic and m.user_id=x
  )) then raise exception 'mentioned_member_not_in_clinic';end if;
 end if;
 if p_action='message' then
  if auth.uid() is null or not private.team_plan(p_clinic) or not private.ops_permission_active(p_clinic,'team.manage') then
   raise exception 'team_manage_required';
  end if;
  perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for share;
  if not found then raise exception 'access_denied';end if;
  if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>20000 then raise exception 'invalid_data';end if;
  fp=jsonb_build_object('kind','ops','action',p_action,'data',p_data);
  v_id=private.vet_receipt(p_clinic,p_operation,fp);
  if v_id is not null then return v_id;end if;
  insert into public.clinic_messages(clinic_id,category,body,author_id,mentioned_user_ids)
  values(p_clinic,p_data->>'category',btrim(p_data->>'body'),auth.uid(),ids) returning id into v_id;
  insert into public.audit_log(clinic_id,actor_id,action,entity_id)
  values(p_clinic,auth.uid(),'ops_message',v_id::text);
  insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
  return v_id;
 end if;
 v_id=public.ops_write_before_team_mentions(p_clinic,p_action,p_data,p_operation);
 if p_action='task' then
  update public.clinic_tasks set mentioned_user_ids=ids where id=v_id and clinic_id=p_clinic;
 end if;
 return v_id;
end$$;
revoke all on function public.ops_write(uuid,text,jsonb,text) from public,anon;
grant execute on function public.ops_write(uuid,text,jsonb,text) to authenticated;

alter function public.ops_dashboard(uuid) rename to ops_dashboard_before_team_mentions;
revoke all on function public.ops_dashboard_before_team_mentions(uuid) from public,anon,authenticated;
create function public.ops_dashboard(p_clinic uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare snapshot jsonb;
begin
 snapshot=public.ops_dashboard_before_team_mentions(p_clinic);
 if coalesce((snapshot->'sections'->>'tasks')::boolean,false) then
  snapshot=jsonb_set(snapshot,'{tasks}',coalesce((
   select jsonb_agg(to_jsonb(t) order by t.created_at desc)
   from public.clinic_tasks t where t.clinic_id=p_clinic and
   (t.assigned_to is null or t.assigned_to=auth.uid() or t.created_by=auth.uid() or
    auth.uid()=any(t.mentioned_user_ids) or private.has_clinic_role(p_clinic,array['admin']))
  ),'[]'::jsonb));
 end if;
 return snapshot;
end$$;
revoke all on function public.ops_dashboard(uuid) from public,anon;
grant execute on function public.ops_dashboard(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
