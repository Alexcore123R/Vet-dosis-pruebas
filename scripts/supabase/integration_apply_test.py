"""Install the reviewed initial module contract only in the fixed, closed test project."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from identity_schema import PROJECT, query
from integration_bundle import bundle_sql, unwrap, literal
from integration_preflight import ROOT
from integration_remote_rehearsal import snapshot

PATCHES = {
    '14A_dashboard_sales_metrics.sql':'private.inv_totals(uuid,uuid,timestamptz,timestamptz)',
    '14B_support_attachment_validation.sql':'public.support_attachment_finish(uuid,text)',
}


def rollout_sql(commit=False):
    sql=bundle_sql().removesuffix('rollback;\n')
    checks=[]
    for name,signature in PATCHES.items():
        source=(ROOT/'supabase/proposed'/name).read_text()
        body=re.findall(r'as \$\$(.*?)\$\$;',source,re.S|re.I)
        if len(body)!=1:raise ValueError('Patch fingerprint is ambiguous.')
        digest=hashlib.sha256(body[0].encode()).hexdigest()
        checks.append("if not exists(select 1 from pg_proc where oid="+literal(signature)+"::regprocedure and encode(sha256(convert_to(prosrc,'UTF8')),'hex')="+literal(digest)+") then raise exception 'client_patch_hash_mismatch';end if;")
        sql+='\n-- Client patch: '+name+'\n'+unwrap(source)
    sql+='\ndo $patch_verify$ begin\n'+'\n'.join(checks)+'\nend $patch_verify$;\n'
    return sql+('commit;\n' if commit else 'rollback;\n')


def install(read=query):
    before=snapshot(read)
    if any(before.get(key) is not False for key in ('receipt','module_contract','rotation')):
        raise ValueError('Partial or existing rollout requires inspection; no automatic retry.')
    if before.get('beta_closed') is not True or before.get('permissions_dormant') is not True:
        raise ValueError('The test project must remain closed and dormant.')
    sql=rollout_sql(commit=True)
    read(sql)
    after=snapshot(read)
    for key in ('patients','owners','medication','grants','verifications','beta_closed','permissions_dormant'):
        if after.get(key)!=before.get(key):raise ValueError('Post-install invariants differ; inspect, do not retry.')
    if after.get('receipt') is not True or after.get('module_contract') is not True or after.get('rotation') is not False:
        raise ValueError('Post-install contract verification incomplete; do not retry.')
    return {'project_ref':PROJECT,'initial_module_contract_installed':True,
            'clinical_and_authority_counts_unchanged':True,'beta_closed':True,
            'permission_policy_dormant':True,'client_patches':list(PATCHES),
            'sql_sha256':hashlib.sha256(sql.encode()).hexdigest(),
            'ai_rotation_installed':False,'admissions_opened':False,
            'scope':'Schema only. Explicit per-person grants and real-session HTTP checks still required.'}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    if not args.apply:
        query(rollout_sql())
        print('Initial contract and patches rehearsed with ROLLBACK only.')
        return
    report=install()
    Path('initial-module-install.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
