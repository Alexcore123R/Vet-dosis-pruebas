-- Additive M2 team UI endpoints. Run after existing_clinics_m2.sql.
begin;
create function public.clinic_team_snapshot(target_clinic uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(target_clinic,array['admin']::text[]) then raise exception 'admin_required'; end if;
 return jsonb_build_object(
 'members',coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'email',u.email,'role',m.role) order by m.created_at,m.user_id)
 from public.clinic_members m join auth.users u on u.id=m.user_id where m.clinic_id=target_clinic),'[]'::jsonb),
 'invitations',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'email',i.email,'role',i.role,'expires_at',i.expires_at,'accepted_at',i.accepted_at,'revoked_at',i.revoked_at) order by i.created_at desc)
 from public.clinic_invitations i where i.clinic_id=target_clinic),'[]'::jsonb));
end; $$;
create function public.remove_clinic_member(target_clinic uuid,target_user uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.clinics where id=target_clinic for update;
 if not private.has_clinic_role(target_clinic,array['admin']::text[]) then raise exception 'admin_required'; end if;
 delete from public.clinic_members where clinic_id=target_clinic and user_id=target_user;
 if not found then raise exception 'member_not_found'; end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id)
 values(target_clinic,auth.uid(),'member_removed',target_user::text);
 -- Existing trigger enforces last administrator.
end; $$;
revoke all on function public.clinic_team_snapshot(uuid) from public;
revoke all on function public.remove_clinic_member(uuid,uuid) from public;
grant execute on function public.clinic_team_snapshot(uuid) to authenticated;
grant execute on function public.remove_clinic_member(uuid,uuid) to authenticated;
commit;
