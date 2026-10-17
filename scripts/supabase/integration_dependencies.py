"""Read-only prerequisite inventory for the atomic test rollout."""
import argparse
import json
from pathlib import Path

from identity_schema import PROJECT, query
from integration_bundle import REQUIRED_FUNCTIONS, REQUIRED_RELATIONS, literal


def inspect_dependencies(read=query):
    relations = ','.join('(' + literal(x) + ')' for x in REQUIRED_RELATIONS)
    functions = ','.join('(' + literal(x) + ')' for x in REQUIRED_FUNCTIONS)
    sql = f"""select
      (select jsonb_object_agg(name,to_regclass(name) is not null)
       from (values {relations}) r(name)) as relations,
      (select jsonb_object_agg(name,to_regprocedure(name) is not null)
       from (values {functions}) f(name)) as functions"""
    rows = read(sql)
    if len(rows) != 1:
        raise ValueError('Incomplete dependency inventory.')
    result = rows[0]
    for key, expected in (('relations', REQUIRED_RELATIONS), ('functions', REQUIRED_FUNCTIONS)):
        if (not isinstance(result.get(key), dict) or set(result[key]) != set(expected)
                or any(type(v) is not bool for v in result[key].values())):
            raise ValueError('Invalid dependency response: ' + key)
    missing = [k for group in ('relations', 'functions') for k, exists in result[group].items()
               if not exists]
    return {'project_ref': PROJECT, 'read_only': True,
            'prerequisites_present': not missing, 'missing': missing,
            'objects': result, 'deploy_ready': False,
            'scope': 'Object presence only. Definitions, data compatibility and rollback rehearsal still require review.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    report = inspect_dependencies()
    text = json.dumps(report, ensure_ascii=False, indent=2)
    args.output.write_text(text + '\n')
    print(text)


if __name__ == '__main__':
    main()
