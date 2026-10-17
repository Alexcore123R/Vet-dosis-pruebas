import unittest
from integration_client_rehearsal import client_rehearsal_sql, EXTRA_FILES


class ClientRehearsalTests(unittest.TestCase):
    def test_all_candidates_remain_in_one_rollback_only_transaction(self):
        sql = client_rehearsal_sql()
        self.assertEqual(sql.count('\nbegin;\n'), 1)
        self.assertNotIn('\ncommit;', sql)
        self.assertTrue(sql.endswith('rollback;\n'))
        self.assertEqual(sql.count('-- Candidate:'), 23)
        for name in EXTRA_FILES:
            self.assertIn('-- Compatibility trial: ' + name, sql)
        self.assertIn('client_rotation_rpc_exposed', sql)
        self.assertIn('client_trial_changed_gate', sql)


if __name__ == '__main__':
    unittest.main()
