-- Export own chats only. A clinic admin does not acquire other users' private histories.
begin;
alter function private.clinic_snapshot(uuid) rename to clinic_snapshot_before_ai_plans;
revoke all on function private.clinic_snapshot_before_ai_plans(uuid) from public,anon,authenticated;
create function private.clinic_snapshot(p_clinic uuid) returns text language plpgsql stable security definer set search_path='' as $$declare s jsonb;begin
 s=private.clinic_snapshot_before_ai_plans(p_clinic)::jsonb;
 s=jsonb_set(s,'{tables,my_ai_chats}',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from public.ai_chats c where clinic_id=p_clinic and owner_id=auth.uid()));
 s=jsonb_set(s,'{tables,my_ai_messages}',(select coalesce(jsonb_agg(to_jsonb(m)),'[]') from public.ai_messages m join public.ai_chats c on c.id=m.chat_id where c.clinic_id=p_clinic and c.owner_id=auth.uid()));
 s=jsonb_set(s,'{tables,subscription_grants}',(select coalesce(jsonb_agg(to_jsonb(g)),'[]') from public.subscription_grants g where clinic_id=p_clinic));
 s=jsonb_set(s,'{tables,subscription_requests}',(select coalesce(jsonb_agg(to_jsonb(g)),'[]') from public.subscription_requests g where clinic_id=p_clinic));
 s=jsonb_set(s,'{tables,subscription_payments}',(select coalesce(jsonb_agg(to_jsonb(g)),'[]') from public.subscription_payments g where clinic_id=p_clinic));
 s=jsonb_set(s,'{tables,account_workspaces}',(select coalesce(jsonb_agg(to_jsonb(g)),'[]') from public.account_workspaces g where clinic_id=p_clinic));
 return s::text;
end$$;
revoke all on function private.clinic_snapshot(uuid) from public,anon,authenticated;
commit;
