"""Read-only anonymous HTTP probes against the fixed test project. No response data logged."""
import json
import os
from pathlib import Path
import urllib.error
import urllib.request
from identity_schema import PROJECT

URL = f'https://{PROJECT}.supabase.co'
SENTINEL = '00000000-0000-0000-0000-000000000000'


def request(path, data=None):
    key=os.environ.get('SUPABASE_TEST_PUBLISHABLE_KEY','').strip()
    if not key:raise ValueError('Test publishable key is missing from the service environment.')
    req=urllib.request.Request(URL+path,
        data=json.dumps(data).encode() if data is not None else None,
        headers={'apikey':key,'Content-Type':'application/json'},
        method='POST' if data is not None else 'GET')
    try:
        with urllib.request.urlopen(req,timeout=30) as response:
            return response.status,json.load(response)
    except urllib.error.HTTPError as error:
        try:payload=json.load(error)
        except (ValueError,UnicodeDecodeError):payload={}
        return error.code,payload
    except (urllib.error.URLError,TimeoutError):
        raise ValueError('Anonymous probe connection failed.') from None


def probe(send=request):
    # Reject an invalid API key before interpreting any 401 as authorization evidence.
    status,_=send('/auth/v1/settings')
    if status!=200:raise ValueError('Public endpoint did not confirm the configured API key.')
    results=[]
    for rpc in ('app_module_workspace','ops_dashboard','inv_dashboard'):
        status,payload=send('/rest/v1/rpc/'+rpc,{'p_clinic':SENTINEL})
        code=payload.get('code') if isinstance(payload,dict) else None
        if status not in (401,403) or code not in ('42501','P0001'):
            raise ValueError('Anonymous RPC protection could not be confirmed: '+rpc)
        results.append({'rpc':rpc,'anonymous_denied':True,'http_status':status,'error_code':code})
    return {'project_ref':PROJECT,'read_only':True,'anonymous_rpc_probes':results,
            'scope':'Anonymous requests only. Does not certify authenticated cross-clinic isolation, Storage or Edge.'}


def main():
    report=probe()
    Path('anonymous-http-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
