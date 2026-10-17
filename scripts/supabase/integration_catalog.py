"""Compare catalog metadata with the isolated baseline; never exports row data."""
import argparse
import json
from pathlib import Path

from identity_schema import PROJECT, query
from integration_bundle import REQUIRED_FUNCTIONS, REQUIRED_RELATIONS, literal


def catalog_sql():
    relations = ','.join(literal(name) for name in REQUIRED_RELATIONS)
    functions = ','.join(literal(name) for name in REQUIRED_FUNCTIONS)
    return f"""select jsonb_build_object(
      'relations', (select jsonb_object_agg(name, jsonb_build_object(
        'present', to_regclass(name) is not null,
        'rls', (select relrowsecurity from pg_class where oid=to_regclass(name)),
        'security', jsonb_build_object(
          'force_rls',(select relforcerowsecurity from pg_class where oid=to_regclass(name)),
          'table_grants',(select jsonb_object_agg(role_name, jsonb_build_object(
            'select',has_table_privilege(role_name,to_regclass(name),'SELECT'),
            'insert',has_table_privilege(role_name,to_regclass(name),'INSERT'),
            'update',has_table_privilege(role_name,to_regclass(name),'UPDATE'),
            'delete',has_table_privilege(role_name,to_regclass(name),'DELETE')))
            from unnest(array['anon','authenticated','service_role']) role_name),
          'constraints',(select coalesce(jsonb_object_agg(c.conname,jsonb_build_object(
            'type',c.contype,'validated',c.convalidated,
            'definition_sha256',encode(sha256(convert_to(pg_get_constraintdef(c.oid,true),'UTF8')),'hex'))),'{{}}')
            from pg_constraint c where c.conrelid=to_regclass(name)),
          'policies',(select coalesce(jsonb_object_agg(p.polname,jsonb_build_object(
            'command',p.polcmd,'permissive',p.polpermissive,
            'roles',(select jsonb_agg(case when role_id=0 then 'PUBLIC' else role_id::regrole::text end order by role_id::regrole::text)
              from unnest(p.polroles) role_id),
            'using_sha256',encode(sha256(convert_to(coalesce(pg_get_expr(p.polqual,p.polrelid),''),'UTF8')),'hex'),
            'check_sha256',encode(sha256(convert_to(coalesce(pg_get_expr(p.polwithcheck,p.polrelid),''),'UTF8')),'hex'))),'{{}}')
            from pg_policy p where p.polrelid=to_regclass(name)),
          'triggers',(select coalesce(jsonb_object_agg(t.tgname,jsonb_build_object(
            'enabled',t.tgenabled,
            'definition_sha256',encode(sha256(convert_to(pg_get_triggerdef(t.oid,true),'UTF8')),'hex'))),'{{}}')
            from pg_trigger t where t.tgrelid=to_regclass(name) and not t.tgisinternal)),
        'columns', (select coalesce(jsonb_object_agg(a.attname, jsonb_build_object(
          'type',format_type(a.atttypid,a.atttypmod), 'not_null',a.attnotnull)), '{{}}'::jsonb)
          from pg_attribute a where a.attrelid=to_regclass(name)
            and a.attnum>0 and not a.attisdropped)))
        from unnest(array[{relations}]) name),
      'functions', (select jsonb_object_agg(name, jsonb_build_object(
        'present',to_regprocedure(name) is not null,
        'body_sha256',(select encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')
          from pg_proc p where p.oid=to_regprocedure(name)),
        'security_definer',(select p.prosecdef from pg_proc p where p.oid=to_regprocedure(name))))
        from unnest(array[{functions}]) name),
      'routines',(select coalesce(jsonb_object_agg(n.nspname||'.'||p.proname||'('||oidvectortypes(p.proargtypes)||')',
        jsonb_build_object('body_sha256',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex'),
          'security_definer',p.prosecdef,'return_type',pg_get_function_result(p.oid),
          'config_sha256',encode(sha256(convert_to(coalesce(p.proconfig::text,''),'UTF8')),'hex'),
          'execute_anon',has_function_privilege('anon',p.oid,'EXECUTE'),
          'execute_authenticated',has_function_privilege('authenticated',p.oid,'EXECUTE'),
          'execute_service_role',has_function_privilege('service_role',p.oid,'EXECUTE'))),'{{}}')
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname in ('public','private') and p.prokind='f'
          and not exists(select 1 from pg_depend d where d.classid='pg_proc'::regclass
            and d.objid=p.oid and d.deptype='e'))
    ) as catalog"""


def validate(catalog):
    if not isinstance(catalog, dict):
        raise ValueError('Invalid catalog response.')
    for group, expected in (('relations', REQUIRED_RELATIONS), ('functions', REQUIRED_FUNCTIONS)):
        entries = catalog.get(group)
        if not isinstance(entries, dict) or set(entries) != set(expected):
            raise ValueError('Incomplete catalog: ' + group)
        for entry in entries.values():
            if not isinstance(entry, dict) or type(entry.get('present')) is not bool:
                raise ValueError('Invalid presence metadata.')
    for entry in catalog['relations'].values():
        if not isinstance(entry.get('columns'), dict):
            raise ValueError('Invalid columns metadata.')
        for column in entry['columns'].values():
            if (not isinstance(column, dict) or not isinstance(column.get('type'), str)
                    or type(column.get('not_null')) is not bool):
                raise ValueError('Invalid column metadata.')
    return catalog


def compare(baseline, remote):
    validate(baseline)
    validate(remote)
    differences = []
    for name, expected in baseline['relations'].items():
        actual = remote['relations'][name]
        if not expected['present']:
            raise ValueError('Isolated baseline is missing ' + name)
        if not actual['present']:
            differences.append({'object': name, 'kind': 'missing_relation'})
            continue
        if expected['rls'] != actual['rls']:
            differences.append({'object': name, 'kind': 'rls_differs',
                                'expected': expected['rls'], 'actual': actual['rls']})
        if 'security' in expected:
            for category, expected_value in expected['security'].items():
                actual_value = actual.get('security', {}).get(category)
                if expected_value != actual_value:
                    differences.append({'object': name, 'kind': category + '_differs',
                                        'expected': expected_value, 'actual': actual_value})
        for column, definition in expected['columns'].items():
            if actual['columns'].get(column) != definition:
                differences.append({'object': name + '.' + column, 'kind': 'column_differs',
                                    'expected': definition, 'actual': actual['columns'].get(column)})
        for column in sorted(actual['columns'].keys() - expected['columns'].keys()):
            differences.append({'object': name + '.' + column, 'kind': 'additional_remote_column'})
    for name, expected in baseline['functions'].items():
        if not expected['present']:
            raise ValueError('Isolated baseline is missing ' + name)
        if expected != remote['functions'][name]:
            differences.append({'object': name, 'kind': 'function_metadata_differs',
                                'expected': expected, 'actual': remote['functions'][name]})
    if 'routines' in baseline:
        if not isinstance(remote.get('routines'), dict):
            raise ValueError('Missing routine security metadata.')
        for name in sorted(baseline['routines'].keys() | remote['routines'].keys()):
            if baseline['routines'].get(name) != remote['routines'].get(name):
                expected_routine = baseline['routines'].get(name)
                actual_routine = remote['routines'].get(name)
                differences.append({'object': name, 'kind': 'routine_security_differs',
                                    'expected': expected_routine, 'actual': actual_routine,
                                    'changed_fields': sorted(
                                        key for key in (expected_routine or {}).keys() | (actual_routine or {}).keys()
                                        if (expected_routine or {}).get(key) != (actual_routine or {}).get(key))})
    return {'project_ref': PROJECT, 'read_only': True, 'deploy_ready': False,
            'differences': differences, 'compared_relations': len(REQUIRED_RELATIONS),
            'compared_functions': len(REQUIRED_FUNCTIONS),
            'compared_baseline_routines': len(baseline.get('routines', {})),
            'scope': 'Catalog only: columns, RLS, table privileges, constraint/policy/trigger hashes '
                     'and routine hashes/security/execute privileges. No row data or full schema restore; '
                     'indexes, column grants, role inheritance and Storage binaries not certified.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sql', action='store_true')
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.sql:
        print(catalog_sql() + ';')
        return
    if args.baseline is None or args.output is None:
        parser.error('--baseline and --output are required for remote inspection')
    rows = query(catalog_sql())
    if len(rows) != 1 or set(rows[0]) != {'catalog'}:
        raise ValueError('Incomplete remote catalog response.')
    report = compare(json.loads(args.baseline.read_text()), rows[0]['catalog'])
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({**report, 'differences': report['differences'][:25],
                      'difference_index': [{'object': d['object'], 'kind': d['kind'],
                                            'changed_fields': d.get('changed_fields', []),
                                            **({'remote_body_sha256': d['actual']['body_sha256']}
                                               if 'body_sha256' in d.get('changed_fields', [])
                                               and d.get('actual') else {})}
                                           for d in report['differences']],
                      'total_differences': len(report['differences']),
                      'full_report_in_artifact': True}, indent=2))


if __name__ == '__main__':
    main()
