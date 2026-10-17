"""Read backup availability from the fixed test service; never downloads backups."""
import argparse
import json
import os
from pathlib import Path
import urllib.error
import urllib.request

from identity_schema import PROJECT

ENDPOINT = f'https://api.supabase.com/v1/projects/{PROJECT}/database/backups'


def summarize(payload):
    if not isinstance(payload, dict) or not isinstance(payload.get('backups'), list):
        raise ValueError('Incomplete backup inventory response.')
    backups = []
    for item in payload['backups']:
        if not isinstance(item, dict):
            raise ValueError('Invalid backup metadata.')
        # Only documented metadata: no paths, signed URLs, credentials or row data.
        entry = {}
        for field in ('status', 'inserted_at'):
            value = item.get(field)
            if value is not None:
                if not isinstance(value, str) or len(value) > 100:
                    raise ValueError('Invalid backup status metadata.')
                entry[field] = value
        backups.append(entry)
    return {'project_ref': PROJECT, 'read_only': True, 'inventory_confirmed': True,
            'available_entries': len(backups), 'backups': backups,
            'pitr_enabled': payload.get('pitr_enabled') is True,
            'walg_enabled': payload.get('walg_enabled') is True,
            'restore_verified': False, 'deploy_ready': False,
            'scope': 'Availability only. No backup created, downloaded or restored; '
                     'Storage binary recovery is not established by database backup metadata.'}


def inspect(opener=urllib.request.urlopen):
    token = os.environ.get('SUPABASE_ACCESS_TOKEN', '').strip()
    if not token:
        raise SystemExit('Missing service secret SUPABASE_ACCESS_TOKEN.')
    request = urllib.request.Request(ENDPOINT, headers={'Authorization': f'Bearer {token}'}, method='GET')
    try:
        with opener(request, timeout=60) as response:
            return summarize(json.load(response))
    except urllib.error.HTTPError as error:
        # No private API response bodies or request headers in logs.
        return {'project_ref': PROJECT, 'read_only': True, 'inventory_confirmed': False,
                'http_status': error.code, 'restore_verified': False, 'deploy_ready': False}
    except (urllib.error.URLError, TimeoutError):
        raise SystemExit('Backup inventory connection could not be confirmed.') from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = inspect()
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
