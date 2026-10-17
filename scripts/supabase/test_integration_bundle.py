import unittest

from integration_bundle import bundle_sql, unwrap


class BundleTests(unittest.TestCase):
    def test_default_is_one_transaction_ending_in_rollback(self):
        sql = bundle_sql()
        self.assertTrue(sql.endswith('rollback;\n'))
        self.assertEqual(sql.count('\nbegin;\n'), 1)
        self.assertNotIn('\ncommit;', sql)
        self.assertEqual(sql.count('-- Candidate:'), 23)
        self.assertIn('integration_partial_or_already_applied_requires_review', sql)
        self.assertIn('integration_changed_clinical_or_authority_counts', sql)

    def test_commit_is_explicit_and_only_changes_final_statement(self):
        self.assertEqual(bundle_sql(commit=True).removesuffix('commit;\n'),
                         bundle_sql().removesuffix('rollback;\n'))

    def test_trailing_duplicate_and_extra_transactions_are_rejected(self):
        for sql in ('begin;\nselect 1;\ncommit;\nstray sql;',
                    'begin;\nselect 1;\ncommit;\nbegin;\ncommit;\n'):
            with self.assertRaises(ValueError):
                unwrap(sql)


if __name__ == '__main__':
    unittest.main()
