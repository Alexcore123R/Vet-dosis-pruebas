"""Emit synthetic SQL only for the isolated integration fixture, never a project."""
import sys
sys.path.insert(0,'scripts/supabase')
from beta_operational_access import setup_sql, CODES

print("""
insert into auth.users(id,email,email_confirmed_at) values
 ('90000000-0000-0000-0000-000000000903','operational-platform@example.test',now());
insert into private.platform_admins(user_id) values('90000000-0000-0000-0000-000000000903');
insert into public.clinic_members(clinic_id,user_id,role) values
 ('90000000-0000-0000-0000-000000000901','90000000-0000-0000-0000-000000000900','admin') on conflict do nothing;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000900',false);
create temporary table setup_original_counts as select
 (select count(*) from private.professional_verifications) professional,
 (select count(*) from private.member_permission_grants) grants;
""")
args=('integration-synthetic@example.test','operational-platform@example.test','Synthetic integration sentinel')
print(setup_sql(*args))
print("""do $$begin
 if (select count(*) from private.member_permission_grants)<>(select grants from setup_original_counts)
 then raise exception 'Operational rehearsal persisted grants';end if;
end$$;""")
print(setup_sql(*args,commit=True))
print('create temporary table initial_operational_grants as select id,code,valid_until from private.member_permission_grants;')
print(setup_sql(*args,commit=True))
print("""do $$declare modules jsonb;begin
 if exists(select id,code,valid_until from private.member_permission_grants except select * from initial_operational_grants)
 or exists(select * from initial_operational_grants except select id,code,valid_until from private.member_permission_grants)
 then raise exception 'Replay duplicated or extended grants';end if;
 if private.professional_current('90000000-0000-0000-0000-000000000901',auth.uid())
 or (select count(*) from private.professional_verifications)<>(select professional from setup_original_counts)
 then raise exception 'Operational profile conferred professional authority';end if;
 modules=public.app_module_workspace('90000000-0000-0000-0000-000000000901');
 if modules#>>'{modules,inventory}'<>'true' or modules#>>'{modules,statistics}'<>'true'
 or modules#>>'{summaries,sales}'<>'true' then raise exception 'Operational module contract incomplete';end if;
 if (select name from public.vet_patients where id='90000000-0000-0000-0000-000000000902')<>'Synthetic untouched patient'
 then raise exception 'Operational setup changed a patient';end if;
 begin
 perform public.permission_grant('90000000-0000-0000-0000-000000000901',auth.uid(),'prescription.authorize',null,now()+interval '1 day','Synthetic denial probe');
 raise exception 'Unverified owner received professional permission';
 exception when raise_exception then if sqlerrm<>'verified_professional_required' then raise;end if;end;
 if not exists(select 1 from public.audit_log where action='beta_operational_setup'
 and details->>'origin'='github_actions_administrative_setup')
 then raise exception 'Administrative executor provenance missing';end if;
end$$;""")
print(f"do $$begin if (select count(*) from private.member_permission_grants)<>{len(CODES)} then raise exception 'Wrong operational scope';end if;end$$;")

from diagnose_beta_writes import diagnostic_sql
print("create temporary table probe_counts as select (select count(*) from public.vet_patients) patients,(select count(*) from public.vet_owners) owners,(select count(*) from public.inventory_clinic_settings) settings;")
print(diagnostic_sql(*args))
print("""do $$declare r jsonb;begin
 r=pg_temp.vd_beta_write_probe();
 if r#>>'{probes,0,passed}'<>'true' or r#>>'{probes,1,passed}'<>'true'
 or r#>>'{probes,2,sqlstate}'<>'23502' then raise exception 'Timezone failure not reproduced';end if;
end$$;""")
print(open('supabase/proposed/14C_inventory_timezone_audit.sql').read())
print("""do $$declare r jsonb;begin
 r=pg_temp.vd_beta_write_probe();
 if exists(select 1 from jsonb_array_elements(r->'probes') p where p->>'passed'<>'true')
 then raise exception 'Controlled writes still fail after targeted fix';end if;
 if exists(select 1 from probe_counts where patients<>(select count(*) from public.vet_patients)
 or owners<>(select count(*) from public.vet_owners) or settings<>(select count(*) from public.inventory_clinic_settings))
 then raise exception 'Controlled diagnostic retained synthetic writes';end if;
end$$;""")
