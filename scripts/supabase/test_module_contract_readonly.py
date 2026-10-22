import unittest
from unittest.mock import Mock

from module_contract_readonly import candidate_body, summarize, SQL


class ModuleContractAuditTests(unittest.TestCase):
    N = "begin\n return jsonb_build_object('patients',true);\nend"
    O = "begin\n return jsonb_build_object('patients',true,'statistics',true,'backup',true);\nend"

    def test_extract_bodies(self):
        sql = ("create or replace function public.app_module_workspace(p_clinic uuid) "
               "returns jsonb language plpgsql stable security definer set search_path='' "
               "as $$begin return null;end$$;")
        self.assertEqual(candidate_body(sql),"begin return null;end")

    def test_remote_exact_candidate(self):
        read=Mock(return_value=[{'source':self.O,'security_definer':True,
             'volatility':'s','anon_execute':False,'authenticated_execute':True}])
        report,diff=summarize(read,sources={'13N':self.N,'13O':self.O})
        self.assertEqual(read.call_args.args[0],SQL)
        self.assertTrue(SQL.lstrip().lower().startswith('select'))
        self.assertEqual(report['verdict'],'exact_13O')
        self.assertEqual(diff,'')
        self.assertFalse(report['deploy_ready'])

    def test_drift_is_not_approved(self):
        read=Mock(return_value=[{'source':self.N,'security_definer':True,
             'volatility':'s','anon_execute':False,'authenticated_execute':True}])
        report,diff=summarize(read,sources={'13N':self.N,'13O':self.O})
        self.assertEqual(report['verdict'],'exact_13N')
        self.assertEqual(report['module_tokens_missing'],['backup','statistics'])
        self.assertIn('candidate_13O',diff)

    def test_missing(self):
        report,diff=summarize(Mock(return_value=[]),sources={'13N':self.N,'13O':self.O})
        self.assertFalse(report['function_present'])
        self.assertFalse(report['deploy_ready'])

    def test_unexpected_catalog(self):
        with self.assertRaises(ValueError):
            summarize(Mock(return_value=[{'source':'a'},{'source':'b'}]),
                      sources={'13N':self.N,'13O':self.O})


if __name__ == '__main__':
    unittest.main()
