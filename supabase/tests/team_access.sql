begin;
insert into auth.users values ('00000000-0000-0000-0000-000000000901','second@example.test',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000900',true);
do $$declare c uuid := '00000000-0000-0000-0000-000000000900'; j jsonb; begin
 j := public.clinic_team_snapshot(c);
 if jsonb_array_length(j->'members')<>1 or j::text like '%token_hash%' then raise exception 'unsafe_snapshot'; end if;
 begin
  perform public.remove_clinic_member(c,auth.uid());
  raise exception 'last_admin_deleted';
 exception when raise_exception then
  if sqlerrm <> 'last_admin_required' then raise; end if;
 end;
end $$;
reset role;
insert into public.clinic_members(clinic_id,user_id,role) values
('00000000-0000-0000-0000-000000000900','00000000-0000-0000-0000-000000000901','auxiliar');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000901',true);
do $$begin
 begin
  perform public.clinic_team_snapshot('00000000-0000-0000-0000-000000000900');
  raise exception 'non_admin_snapshot';
 exception when raise_exception then if sqlerrm <> 'admin_required' then raise; end if; end;
 begin
  perform public.remove_clinic_member('00000000-0000-0000-0000-000000000900',auth.uid());
  raise exception 'non_admin_remove';
 exception when raise_exception then if sqlerrm <> 'admin_required' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000900',true);
select public.remove_clinic_member('00000000-0000-0000-0000-000000000900','00000000-0000-0000-0000-000000000901');
do $$begin
 if (select count(*) from public.audit_log where action='member_removed')<>1 then raise exception 'missing_removal_audit'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000901',true);
do $$begin
 begin
  perform public.clinic_team_snapshot('00000000-0000-0000-0000-000000000900');
  raise exception 'removed_member_access';
 exception when raise_exception then if sqlerrm <> 'admin_required' then raise; end if; end;
end $$;
rollback;
