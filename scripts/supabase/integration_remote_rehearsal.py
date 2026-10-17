"""Fixed-project transaction trial. Always ROLLBACK; no apply mode exists."""
import json
from pathlib import Path
from identity_schema import PROJECT, query
from integration_client_rehearsal import client_rehearsal_sql

SNAPSHOT = """select jsonb_build_object(
 'receipt',to_regclass('private.beta_integration_receipts') is not null,
 'module_contract',to_regprocedure('public.app_module_workspace(uuid)') is not null,
 'rotation',to_regprocedure('public.ai_key_rotate_server(uuid,uuid,text,text)') is not null,
 'patients',(select count(*) from public.vet_patients),
 'owners',(select count(*) from public.vet_owners),
 'medication',(select count(*) from public.medication_records),
 'grants',(select count(*) from private.member_permission_grants),
 'verifications',(select count(*) from private.professional_verifications),
 'beta_closed',(select not admissions_enabled and not enforcement_enabled from private.beta_policy),
 'permissions_dormant',(select not enforcement_enabled and not migration_reviewed from private.permission_policy),
 'routines',(select jsonb_object_agg(p.oid::regprocedure::text,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex'))
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='public' and p.proname in ('support_attachment_finish','ai_finish_server'))
 or (n.nspname='private' and p.proname='inv_totals'))
) as state"""


def snapshot(read=query):
    rows = read(SNAPSHOT)
    if len(rows) != 1 or not isinstance(rows[0].get('state'), dict):
        raise ValueError('Incomplete rollback verification state.')
    return rows[0]['state']


def rehearse(read=query):
    before = snapshot(read)
    if any(before.get(key) is not False for key in ('receipt','module_contract','rotation')):
        raise ValueError('Existing or partial rollout requires review.')
    if before.get('beta_closed') is not True or before.get('permissions_dormant') is not True:
        raise ValueError('Trial requires closed, dormant test policies.')
    read(client_rehearsal_sql())
    after = snapshot(read)
    if after != before:
        raise ValueError('Rollback verification differs; inspect before any retry.')
    return {'project_ref':PROJECT,'server_rollback_trial_passed':True,
            'active_database_modified':False,'admissions_opened':False,
            'mode':'23 candidates + 3 client patches, ROLLBACK',
            'scope':'SQL compatibility only; no Auth HTTP, Storage transfer or Edge deployment verified.'}


def main():
    report = rehearse()
    Path('remote-rollback-trial.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()
