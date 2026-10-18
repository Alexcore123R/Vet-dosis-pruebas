"""Explicit, audited non-professional beta access for one verified clinic owner.

Default action rehearses with ROLLBACK. Uses existing grant RPC business rules;
no schema, professional evidence, procedures, roles or clinical records created.
The administrative executor acts on the clinic owner's explicit request. A second
append-only event records that automation origin separately from the authorizer.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
from identity_schema import PROJECT, query
from integration_bundle import literal

CODES = (
    'patient.read','patient.write','appointment.read','appointment.manage',
    'clinical.read','hospital.read','hospital.report','hospital.manage','vial.read',
    'inventory.read','inventory.adjust','inventory.manage','inventory.receive',
    'inventory.order.prepare','inventory.order.approve',
    'sales.collect','sales.read','sales.reverse','sales.reconcile','sales.manual','cash.move',
    'prescription.prepare','form.prepare','report.prepare','backup.export','workspace.manage',
    'form.template.read','form.template.edit','form.branding.manage',
)


def email(value):
    value=value.strip().lower()
    if len(value)>254 or '@' not in value or any(c in value for c in '\r\n\x00'):
        raise ValueError('Invalid account identifier.')
    return value


def inputs(clinic_email,platform_email,clinic_name):
    clinic_email=email(clinic_email);platform_email=email(platform_email)
    if clinic_email==platform_email:raise ValueError('Accounts must remain separate.')
    clinic_name=clinic_name.strip()
    if not 1<=len(clinic_name)<=120 or any(c in clinic_name for c in '\r\n\x00'):
        raise ValueError('Invalid clinic identifier.')
    return clinic_email,platform_email,clinic_name


def setup_sql(clinic_email,platform_email,clinic_name,*,commit=False,executor='local-test',run_id='local-test'):
    clinic_email,platform_email,clinic_name=inputs(clinic_email,platform_email,clinic_name)
    codes=','.join(literal(code) for code in CODES)
    origin=literal(json.dumps({'origin':'github_actions_administrative_setup',
        'executor':executor,'run_id':run_id,'owner_requested':True,'profile':'operational_beta_v2'}))
    return f"""begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtextextended('vetdosis-operational-beta-setup',0));
do $setup$
declare subject uuid;space uuid;reviewer uuid;matches integer;permission_code text;created integer=0;
 until_at timestamptz=statement_timestamp()+interval '60 days';
 verifications_before bigint;professional_before boolean;outside_before bigint;
 codes constant text[]=array[{codes}];
begin
 select count(*),(array_agg(id))[1] into matches,subject from auth.users where lower(btrim(email))={literal(clinic_email)};
 if matches<>1 then raise exception 'beta_setup_owner_not_unique';end if;
 select count(*),(array_agg(u.id))[1] into matches,reviewer
 from auth.users u join private.platform_admins p on p.user_id=u.id and p.enabled
 where lower(btrim(u.email))={literal(platform_email)};
 if matches<>1 or reviewer=subject or exists(select 1 from public.clinic_members where user_id=reviewer)
 or exists(select 1 from private.platform_admins where user_id=subject and enabled)
 then raise exception 'beta_setup_account_separation_required';end if;
 select count(*),(array_agg(c.id))[1] into matches,space
 from public.clinics c join public.clinic_members m on m.clinic_id=c.id and m.user_id=subject
 where lower(btrim(c.name))=lower({literal(clinic_name)}) and c.created_by=subject and m.role='admin'
 and not exists(select 1 from public.account_workspaces w where w.clinic_id=c.id and w.kind='personal');
 if matches<>1 then raise exception 'beta_setup_clinic_owner_not_unique';end if;
 perform 1 from public.clinics where id=space for update;
 if to_regclass('private.beta_integration_receipts') is null
 or not exists(select 1 from private.beta_policy where not admissions_enabled and not enforcement_enabled)
 or not exists(select 1 from private.permission_policy where not enforcement_enabled and not migration_reviewed)
 then raise exception 'beta_setup_requires_installed_closed_test_project';end if;
 if (select count(*) from private.permission_catalog where code=any(codes) and not requires_professional and not procedure_scoped)<>cardinality(codes)
 then raise exception 'beta_setup_catalog_scope_changed';end if;
 select count(*) into verifications_before from private.professional_verifications;
 select private.professional_current(space,subject) into professional_before;
 select count(*) into outside_before from private.member_permission_grants where clinic_id<>space or user_id<>subject;
 -- Administrative on-behalf-of context is transaction-local, never an Auth login.
 -- The additional audit event below identifies the actual administrative executor.
 perform set_config('request.jwt.claim.sub',subject::text,true);
 foreach permission_code in array codes loop
  if private.permission_effective(space,subject,permission_code) is null then
   perform public.permission_grant(space,subject,permission_code,null,until_at,
    'Prueba operativa con datos ficticios solicitada por la titular; configuración administrativa automatizada. Sin habilitación profesional.');
   created=created+1;
  end if;
 end loop;
 if exists(select 1 from unnest(codes) p where private.permission_effective(space,subject,p) is null)
 then raise exception 'beta_setup_effective_permissions_incomplete';end if;
 if (select count(*) from private.professional_verifications)<>verifications_before
 or private.professional_current(space,subject) is distinct from professional_before
 or (select count(*) from private.member_permission_grants where clinic_id<>space or user_id<>subject)<>outside_before
 then raise exception 'beta_setup_authority_or_other_scope_changed';end if;
 perform private.permission_event(space,'beta_operational_setup',space,
  {origin}::jsonb||jsonb_build_object('created',created,'codes',to_jsonb(codes),'new_grant_expiry',until_at));
end
$setup$;
"""+('commit;\n' if commit else 'rollback;\n')


def state_sql(clinic_email,clinic_name):
    return f"""select jsonb_build_object(
 'scope_count',count(*),
 'professional_current',coalesce(bool_or(private.professional_current(m.clinic_id,u.id)),false),
 'effective_codes',coalesce((select jsonb_agg(pc.code order by pc.code) from private.permission_catalog pc
 where pc.code=any(array[{','.join(literal(c) for c in CODES)}]) and exists(
 select 1 from auth.users x join public.clinic_members mm on mm.user_id=x.id join public.clinics cc on cc.id=mm.clinic_id
 where lower(btrim(x.email))={literal(email(clinic_email))} and lower(btrim(cc.name))=lower({literal(clinic_name.strip())})
 and private.permission_effective(mm.clinic_id,x.id,pc.code) is not null)),'[]'::jsonb)) as state
 from auth.users u join public.clinic_members m on m.user_id=u.id join public.clinics c on c.id=m.clinic_id
 where lower(btrim(u.email))={literal(email(clinic_email))} and lower(btrim(c.name))=lower({literal(clinic_name.strip())})"""


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply',action='store_true');args=parser.parse_args()
    owner,platform,clinic=inputs(os.environ.get('CLINIC_EMAIL',''),os.environ.get('PLATFORM_EMAIL',''),os.environ.get('CLINIC_NAME',''))
    before=query(state_sql(owner,clinic))[0]['state']
    sql=setup_sql(owner,platform,clinic,commit=args.apply,
        executor=os.environ.get('GITHUB_ACTOR','unknown'),run_id=os.environ.get('GITHUB_RUN_ID','unknown'))
    query(sql)
    after=query(state_sql(owner,clinic))[0]['state']
    if args.apply:
        if after['scope_count']!=1 or set(after['effective_codes'])!=set(CODES) or after['professional_current']!=before['professional_current']:
            raise SystemExit('Post-setup check incomplete. Inspect before any retry.')
    elif after!=before:raise SystemExit('Rehearsal rollback check differs.')
    report={'project_ref':PROJECT,'applied':args.apply,'profile':'operational_beta_v2',
            'scope_count':after['scope_count'],'effective_codes':after['effective_codes'],
            'professional_current':after['professional_current'],'professional_authority_changed':False,
            'new_grants_valid_days':60,'existing_grants_extended':False,
            'sql_sha256':hashlib.sha256(sql.encode()).hexdigest(),
            'scope':'One clinic owner, non-professional unscoped permissions only. No admission, clinical data or verification changes.'}
    Path('beta-operational-access.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
