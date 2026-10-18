"""Apply one hash-guarded timezone audit fix to the fixed closed test project."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from identity_schema import PROJECT, query
from integration_bundle import ROOT, unwrap


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply',action='store_true');args=parser.parse_args()
    source=(ROOT/'supabase/proposed/14C_inventory_timezone_audit.sql').read_text()
    function_body=re.findall(r'as \$\$(.*?)\$\$;',source,re.S|re.I)
    if len(function_body)!=1:raise SystemExit('Timezone patch fingerprint is ambiguous.')
    expected=hashlib.sha256(function_body[0].encode()).hexdigest()
    snapshot="select encode(sha256(convert_to(prosrc,'UTF8')),'hex') as sha from pg_proc where oid='public.inv_settings(uuid,text)'::regprocedure"
    before=query(snapshot)
    query('begin;\n'+unwrap(source)+('commit;\n' if args.apply else 'rollback;\n'))
    after=query(snapshot)
    if after!=([{'sha':expected}] if args.apply else before):raise SystemExit('Timezone patch verification incomplete; inspect before retry.')
    report={'project_ref':PROJECT,'applied':args.apply,'function':'public.inv_settings(uuid,text)',
            'definition_verified':True,'scope':'Audit entity ID supplied; no permissions or audit constraints relaxed.'}
    Path('timezone-fix-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
