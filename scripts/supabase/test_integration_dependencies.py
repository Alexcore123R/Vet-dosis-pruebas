import unittest
from unittest.mock import Mock

from integration_bundle import REQUIRED_FUNCTIONS, REQUIRED_RELATIONS
from integration_dependencies import inspect_dependencies


class DependencyTests(unittest.TestCase):
    def test_prerequisites_only_use_catalog_and_do_not_certify_rollout(self):
        read = Mock(return_value=[{
            'relations': dict.fromkeys(REQUIRED_RELATIONS, True),
            'functions': dict.fromkeys(REQUIRED_FUNCTIONS, True),
        }])
        report = inspect_dependencies(read)
        self.assertTrue(report['prerequisites_present'])
        self.assertFalse(report['deploy_ready'])
        self.assertTrue(read.call_args.args[0].lstrip().startswith('select'))
        self.assertEqual(read.call_count, 1)

    def test_missing_baseline_is_named(self):
        relations = dict.fromkeys(REQUIRED_RELATIONS, True)
        relations['public.account_identity'] = False
        report = inspect_dependencies(Mock(return_value=[{
            'relations': relations, 'functions': dict.fromkeys(REQUIRED_FUNCTIONS, True),
        }]))
        self.assertFalse(report['prerequisites_present'])
        self.assertEqual(report['missing'], ['public.account_identity'])

    def test_incomplete_catalog_fails_instead_of_claiming_ready(self):
        with self.assertRaises(ValueError):
            inspect_dependencies(Mock(return_value=[{'relations': {}, 'functions': {}}]))


if __name__ == '__main__':
    unittest.main()
