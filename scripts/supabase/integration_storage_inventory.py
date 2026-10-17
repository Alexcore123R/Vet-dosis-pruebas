"""Aggregate Storage inventory only: no object paths, owners, URLs or row data."""
import argparse
import json
from pathlib import Path
import re

from identity_schema import PROJECT, query

SQL = """select
 (select count(*) from storage.buckets) as buckets,
 count(*) as objects,
 coalesce(sum(case when metadata->>'size' ~ '^[0-9]{1,20}$'
                   then (metadata->>'size')::numeric else 0 end),0) as known_bytes,
 count(*) filter (where metadata->>'size' is null
    or metadata->>'size' !~ '^[0-9]{1,20}$') as unknown_size_objects
 from storage.objects"""


def inspect(read=query):
    rows = read(SQL)
    if len(rows) != 1 or set(rows[0]) != {'buckets','objects','known_bytes','unknown_size_objects'}:
        raise ValueError('Incomplete Storage aggregate inventory.')
    values = {}
    for key,value in rows[0].items():
        if type(value) is int and value>=0:
            values[key]=value
        elif isinstance(value,str) and re.fullmatch('[0-9]{1,30}',value):
            # PostgreSQL bigint/numeric may arrive as exact decimal strings.
            values[key]=int(value)
        else:
            raise ValueError('Invalid Storage aggregate inventory.')
    return {'project_ref': PROJECT, 'read_only': True, **values,
            'binary_backup_created': False,
            'scope': 'Aggregate live inventory, not the database backup snapshot. No file contents or paths exported.'}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    report=inspect()
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':
    main()
