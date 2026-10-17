import unittest
from integration_apply_test import rollout_sql, install


class InstallTests(unittest.TestCase):
    def test_rollback_default_and_fixed_reviewed_patch_subset(self):
        sql=rollout_sql()
        self.assertTrue(sql.endswith('rollback;\n'))
        self.assertNotIn('\ncommit;',sql)
        self.assertNotIn('-- Compatibility trial: 13Y',sql)
        self.assertNotIn('create function public.ai_key_rotate_server',sql)
        self.assertEqual(sql.count('-- Candidate:'),23)
        self.assertEqual(sql.count('-- Client patch:'),2)
        self.assertIn('client_patch_hash_mismatch',sql)
        self.assertEqual(sql.removesuffix('rollback;\n'),rollout_sql(True).removesuffix('commit;\n'))

    def test_partial_install_never_retried(self):
        calls=[]
        def read(sql):
            calls.append(sql)
            return [{'state':{'receipt':True}}]
        with self.assertRaises(ValueError):install(read)
        self.assertEqual(len(calls),1)


if __name__=='__main__':unittest.main()
