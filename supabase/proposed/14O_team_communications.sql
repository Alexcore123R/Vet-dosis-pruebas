-- Apply after 14N. Private messages are only exposed through the member-scoped RPC.
begin;
create table public.clinic_private_messages (
 id uuid primary key default gen_random_uuid(),
 clinic_id uuid not null references public.clinics(id),
 author_id uuid not null,
 recipient_id uuid not null,
 body text not null check (length(btrim(body)) between 1 and 2000),
 created_at timestamptz not null default clock_timestamp(),
 foreign key (clinic_id,author_id) references public.clinic_members(clinic_id,user_id),
 foreign key (clinic_id,recipient_id) references public.clinic_members(clinic_id,user_id),
 check (author_id <> recipient_id)
);
create index clinic_private_messages_inbox on public.clinic_private_messages(clinic_id,recipient_id,created_at desc);
create index clinic_private_messages_outbox on public.clinic_private_messages(clinic_id,author_id,created_at desc);
alter table public.clinic_private_messages enable row level security;
revoke all on public.clinic_private_messages from public,anon,authenticated;

alter function public.ops_write(uuid,text,jsonb,text) rename to ops_write_before_team_communications;
revoke all on function public.ops_write_before_team_communications(uuid,text,jsonb,text) from public,anon,authenticated;
create function public.ops_write(p_clinic uuid,p_action text,p_data jsonb,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_recipient uuid;fp jsonb;
begin
 if p_action <> 'private_message' then
  return public.ops_write_before_team_communications(p_clinic,p_action,p_data,p_operation);
 end if;
 if auth.uid() is null or not private.team_plan(p_clinic) or
    not (private.ops_permission_active(p_clinic,'team.read') or private.ops_permission_active(p_clinic,'team.manage')) then
  raise exception 'team_access_required';
 end if;
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for share;
 if not found then raise exception 'access_denied';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>3000 then raise exception 'invalid_data';end if;
 v_recipient=(p_data->>'recipient_id')::uuid;
 if v_recipient=auth.uid() or length(btrim(coalesce(p_data->>'body',''))) not between 1 and 2000 then raise exception 'invalid_message';end if;
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=v_recipient for share;
 if not found then raise exception 'recipient_not_in_clinic';end if;
 fp=jsonb_build_object('kind','ops','action',p_action,'data',p_data);
 v_id=private.vet_receipt(p_clinic,p_operation,fp);
 if v_id is not null then return v_id;end if;
 insert into public.clinic_private_messages(clinic_id,author_id,recipient_id,body)
 values(p_clinic,auth.uid(),v_recipient,btrim(p_data->>'body')) returning id into v_id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id)
 values(p_clinic,auth.uid(),'ops_private_message',v_id::text);
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 return v_id;
end$$;
revoke all on function public.ops_write(uuid,text,jsonb,text) from public,anon;
grant execute on function public.ops_write(uuid,text,jsonb,text) to authenticated;

alter function public.ops_dashboard(uuid) rename to ops_dashboard_before_team_communications;
revoke all on function public.ops_dashboard_before_team_communications(uuid) from public,anon,authenticated;
create function public.ops_dashboard(p_clinic uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare snapshot jsonb;enabled boolean;
begin
 snapshot=public.ops_dashboard_before_team_communications(p_clinic);
 enabled=coalesce((snapshot->'sections'->>'messages')::boolean,false);
 return snapshot || jsonb_build_object(
  'sections',(snapshot->'sections') || jsonb_build_object('notices',enabled,'private_messages',enabled),
  'private_messages',case when enabled then coalesce((
    select jsonb_agg(to_jsonb(m) order by m.created_at desc)
    from (select id,clinic_id,author_id,recipient_id,body,created_at
      from public.clinic_private_messages
      where clinic_id=p_clinic and (author_id=auth.uid() or recipient_id=auth.uid())
      order by created_at desc limit 100) m
   ),'[]'::jsonb) else '[]'::jsonb end
 );
end$$;
revoke all on function public.ops_dashboard(uuid) from public,anon;
grant execute on function public.ops_dashboard(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
