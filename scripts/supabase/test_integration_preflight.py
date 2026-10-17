import unittest
from unittest.mock import Mock

import integration_preflight as preflight


class IntegrationPreflightTests(unittest.TestCase):
    def test_plan_is_ordered_and_excludes_restore(self):
        plan = preflight.local_plan()
        self.assertEqual(len(plan), 23)
        self.assertEqual(len({p['file'] for p in plan}), len(plan))
        self.assertFalse(any('restore' in p['file'] for p in plan))
        self.assertTrue(all(len(p['sha256']) == 64 for p in plan))
        self.assertEqual(len(preflight.expected_markers()), len(preflight.MARKERS))

    def test_missing_foundation_is_reported_without_querying_absent_tables(self):
        read = Mock(return_value=[{'relations': {}, 'functions': [], 'hooks': []}])
        report = preflight.inspect_remote(read)
        self.assertEqual(read.call_count, 1)
        self.assertTrue(report['read_only'])
        self.assertFalse(report['deploy_ready'])
        self.assertTrue(all(v['status'] == 'missing' for v in report['function_checks'].values()))

    def test_matching_body_does_not_certify_complete_deployment(self):
        expected = preflight.expected_markers()
        # Management API returns an array of rows for each SELECT.
        read = Mock(side_effect=[
            [{'relations': {'beta_policy': True, 'permission_policy': True},
              'functions': [{'name': n, 'source_sha256': h} for n, h in expected.items()],
              'hooks': []}],
            [{'admissions_enabled': False, 'enforcement_enabled': False}],
            [{'enforcement_enabled': False, 'migration_reviewed': False}],
        ])
        report = preflight.inspect_remote(read)
        self.assertFalse(report['deploy_ready'])
        self.assertTrue(all(v['status'] == 'body_matches_candidate'
                            for v in report['function_checks'].values()))
        self.assertTrue(all(c.args[0].lstrip().lower().startswith('select')
                            for c in read.call_args_list))

    def test_old_function_body_requires_review(self):
        read = Mock(return_value=[{'relations': {}, 'hooks': [], 'functions': [
            {'name': 'public.app_module_workspace', 'source_sha256': '0' * 64}]}])
        report = preflight.inspect_remote(read)
        self.assertEqual(report['function_checks']['public.app_module_workspace']['status'],
                         'different_definition_requires_review')


if __name__ == '__main__':
    unittest.main()
