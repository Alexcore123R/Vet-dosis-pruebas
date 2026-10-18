-- Targeted bug fix: preserve the real audit_log.entity_id NOT NULL contract.
-- No grants or schema constraints changed. Existing function ACL is retained.
begin;
set local lock_timeout='5s';
do $$begin
 if not exists(select 1 from private.beta_policy where not admissions_enabled and not enforcement_enabled) then
  raise exception 'timezone_patch_requires_closed_test_beta';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.inv_settings(uuid,text)')
 and encode(sha256(convert_to(prosrc,'UTF8')),'hex') in ('79a28e6523fbaf6617516d13b1de447d89fab4a13596f3475d8d536a48c66c3c','b0b28dc11c34a52fa2a84d86af6a0740c3439d6fe2abc734f61651e591c2400c'))
 then raise exception 'timezone_patch_requires_reviewed_definition';end if;
end$$;
create or replace function public.inv_settings(p_clinic uuid,p_timezone text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.inventory_require(p_clinic,'inventory.manage',null,null,false);
 if not private.inventory_current(p_clinic,'inventory.manage') then raise exception 'inventory_admin_required';end if;
 if not exists(select 1 from pg_timezone_names where name=p_timezone) then raise exception 'timezone_required';end if;
 insert into public.inventory_clinic_settings values(p_clinic,p_timezone) on conflict(clinic_id) do update set timezone=excluded.timezone;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'inventory_timezone_changed',p_clinic::text);
end $$;
commit;
