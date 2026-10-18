"""Reproduce beta write failures using synthetic values and rollback subtransactions.

A session-local pg_temp helper returns only controlled-probe diagnostics.
Successful write probes are deliberately rolled back before any result is returned.
No screenshots' patient/contact data are copied into this diagnostic.
"""
import json
import os
from pathlib import Path
from identity_schema import PROJECT, query
from integration_bundle import literal
from beta_operational_access import inputs


def diagnostic_sql(owner,platform,clinic):
    owner,platform,clinic=inputs(owner,platform,clinic)
    return f"""create or replace function pg_temp.vd_beta_write_probe() returns jsonb language plpgsql set search_path='' as $probe$
declare subject uuid;space uuid;matches integer;step integer;ok boolean;err_code text;err_message text;
 results jsonb='[]'::jsonb; op text;
begin
 select count(*),(array_agg(u.id))[1],(array_agg(c.id))[1] into matches,subject,space
 from auth.users u join public.clinic_members m on m.user_id=u.id join public.clinics c on c.id=m.clinic_id
 where lower(btrim(u.email))={literal(owner)} and lower(btrim(c.name))=lower({literal(clinic)}) and c.created_by=u.id;
 if matches<>1 then raise exception 'diagnostic_owner_scope_not_unique';end if;
 perform set_config('request.jwt.claim.sub',subject::text,true);
 for step in 1..3 loop
  ok=false;err_code=null;err_message=null;
  op=md5(random()::text)||substr(md5(random()::text),1,16);
  begin
   if step=1 then
    perform public.create_vet_patient(space,'{{"name":"DIAGNOSTICO TEMPORAL","species":"sintetica","sex":"hembra","birth_date":null}}'::jsonb,null,op);
   elsif step=2 then
    perform public.create_vet_patient(space,'{{"name":"DIAGNOSTICO TEMPORAL","species":"sintetica","sex":"hembra","birth_date":null}}'::jsonb,
      '{{"name":"TUTOR SINTETICO TEMPORAL","phone":"+520000000000","email":"probe@example.test","address":"Domicilio ficticio"}}'::jsonb,op);
   else
    perform public.inv_settings(space,'America/Mexico_City');
   end if;
   ok=true;
   raise sqlstate 'ZX001' using message='rollback_controlled_probe';
  exception when sqlstate 'ZX001' then null;
   when others then err_code=sqlstate;err_message=left(sqlerrm,220);
  end;
  results=results||jsonb_build_array(jsonb_build_object(
   'probe',case step when 1 then 'patient_without_owner' when 2 then 'patient_with_synthetic_owner' else 'clinic_timezone' end,
   'passed',ok,'sqlstate',err_code,'message',err_message));
 end loop;
 return jsonb_build_object('project_ref',{literal(PROJECT)},'probes',results,
  'patients_available',(select count(*) from public.vet_patients where clinic_id=space),
  'template_permissions',public.form_template_permissions(space),
  'templates_available',case when private.permission_effective(space,subject,'form.template.read') is not null
     then jsonb_array_length(public.form_templates_list(space)) else null end,
  'all_probe_writes_rolled_back',true,'scope','Administrative SQL context, not an Auth HTTP session. No clinical/contact rows retained.');
end $probe$;
select pg_temp.vd_beta_write_probe() as diagnostic;
"""


def main():
    rows=query(diagnostic_sql(os.environ.get('CLINIC_EMAIL',''),os.environ.get('PLATFORM_EMAIL',''),os.environ.get('CLINIC_NAME','')))
    if len(rows)!=1 or not isinstance(rows[0].get('diagnostic'),dict):
        raise SystemExit('Diagnostic response incomplete; no raw data printed.')
    report=rows[0]['diagnostic']
    Path('beta-write-diagnostic.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
