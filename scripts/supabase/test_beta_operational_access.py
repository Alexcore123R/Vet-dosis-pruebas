import unittest
from beta_operational_access import CODES, inputs, setup_sql


class OperationalAccessTests(unittest.TestCase):
    def test_default_rolls_back_and_professional_or_procedure_rights_are_excluded(self):
        sql=setup_sql('owner@example.test','platform@example.test','Synthetic clinic')
        self.assertTrue(sql.endswith('rollback;\n'))
        self.assertNotIn('\ncommit;',sql)
        self.assertEqual(len(CODES),len(set(CODES)))
        for code in ('prescription.authorize','controlled.dispense','medication.validate','vial.manage','hospital.schedule','hospital.discharge','procedure.perform','drug.administer','vial.draw','backup.restore'):
            self.assertNotIn(code,CODES)
        self.assertIn('not requires_professional and not procedure_scoped',sql)
        self.assertIn('beta_setup_account_separation_required',sql)
        self.assertIn('github_actions_administrative_setup',sql)

    def test_values_are_normalized_quoted_and_same_account_is_rejected(self):
        self.assertEqual(inputs(' OWNER@example.test ','PLATFORM@example.test',' Clinic '),('owner@example.test','platform@example.test','Clinic'))
        sql=setup_sql("o'wner@example.test",'platform@example.test',"Clinic's name")
        self.assertIn("'o''wner@example.test'",sql)
        self.assertIn("'Clinic''s name'",sql)
        with self.assertRaises(ValueError):inputs('same@example.test','SAME@example.test','Clinic')
        with self.assertRaises(ValueError):inputs('a@example.test\nx','b@example.test','Clinic')


if __name__=='__main__':unittest.main()
