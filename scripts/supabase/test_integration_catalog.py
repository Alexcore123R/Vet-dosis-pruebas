import copy
import unittest

from integration_bundle import REQUIRED_FUNCTIONS, REQUIRED_RELATIONS
from integration_catalog import catalog_sql, compare


def baseline():
    return {
        'relations': {name: {'present': True, 'rls': True,
                            'columns': {'id': {'type': 'uuid', 'not_null': True}}}
                      for name in REQUIRED_RELATIONS},
        'functions': {name: {'present': True, 'body_sha256': 'synthetic', 'security_definer': True}
                      for name in REQUIRED_FUNCTIONS},
    }


class CatalogTests(unittest.TestCase):
    def test_matching_catalog_does_not_certify_deployment(self):
        report = compare(baseline(), baseline())
        self.assertEqual(report['differences'], [])
        self.assertFalse(report['deploy_ready'])
        self.assertTrue(report['read_only'])
        sql = catalog_sql().lower()
        self.assertTrue(sql.startswith('select'))
        self.assertNotIn('from public.vet_patients', sql)
        self.assertNotIn('pg_get_functiondef', sql)

    def test_type_nullability_and_hash_differences_are_visible(self):
        expected = baseline()
        remote = copy.deepcopy(expected)
        remote['relations'][REQUIRED_RELATIONS[0]]['columns']['id']['not_null'] = False
        remote['functions'][REQUIRED_FUNCTIONS[0]]['body_sha256'] = 'different'
        self.assertEqual([d['kind'] for d in compare(expected, remote)['differences']],
                         ['column_differs', 'function_metadata_differs'])

    def test_missing_and_additional_columns_are_not_silently_accepted(self):
        expected = baseline()
        remote = copy.deepcopy(expected)
        columns = remote['relations'][REQUIRED_RELATIONS[0]]['columns']
        columns.pop('id')
        columns['extra'] = {'type': 'text', 'not_null': False}
        self.assertEqual([d['kind'] for d in compare(expected, remote)['differences']],
                         ['column_differs', 'additional_remote_column'])
        remote['relations'].pop(REQUIRED_RELATIONS[0])
        with self.assertRaises(ValueError):
            compare(expected, remote)

    def test_policy_grant_and_routine_drift_cannot_be_hidden_by_matching_columns(self):
        expected = baseline()
        name = REQUIRED_RELATIONS[0]
        expected['relations'][name]['security'] = {
            'table_grants': {'anon': {'select': False}}, 'policies': {'example': 'hash'}}
        expected['routines'] = {'public.synthetic()': {'execute_anon': False}}
        remote = copy.deepcopy(expected)
        remote['relations'][name]['security']['table_grants']['anon']['select'] = True
        remote['routines']['public.synthetic()']['execute_anon'] = True
        kinds = [d['kind'] for d in compare(expected, remote)['differences']]
        self.assertEqual(kinds, ['table_grants_differs', 'routine_security_differs'])
        del remote['routines']
        with self.assertRaises(ValueError):
            compare(expected, remote)


if __name__ == '__main__':
    unittest.main()
