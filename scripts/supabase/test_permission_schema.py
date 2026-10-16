import os
import unittest
from unittest.mock import patch
import permission_schema as deployment


class PermissionDeploymentTests(unittest.TestCase):
    def run_main(self, state, action='apply', confirmation='PREPARAR_PERMISOS_SIN_ACTIVAR_BETA'):
        with patch.dict(os.environ, {'PERMISSION_ACTION':action,'PERMISSION_CONFIRMATION':confirmation}), patch.object(deployment, 'query',return_value=[state]) as query:
            with self.assertRaises(SystemExit):
                deployment.main()
            self.assertEqual(query.call_count,1)

    def test_confirmation_cannot_be_skipped(self):
        self.run_main({'foundation_tables':0}, confirmation='')

    def test_partial_model_is_not_overwritten(self):
        self.run_main({'prescribing_ready':True,'beta_ready':True,'beta_closed':True,'foundation_tables':2})

    def test_open_beta_is_not_modified(self):
        self.run_main({'prescribing_ready':True,'beta_ready':True,'beta_closed':False,'foundation_tables':0})

    def test_missing_dependency_is_not_modified(self):
        self.run_main({'prescribing_ready':False,'beta_ready':True,'beta_closed':True,'foundation_tables':0})

    def test_inspect_is_read_only(self):
        with patch.dict(os.environ, {'PERMISSION_ACTION':'inspect'}), patch.object(deployment,'query',return_value=[{'foundation_tables':0}]) as query:
            deployment.main()
            self.assertEqual(query.call_count,1)

    def test_completed_model_is_not_reapplied(self):
        state={'prescribing_ready':True,'beta_ready':True,'beta_closed':True,'foundation_tables':len(deployment.TABLES)}
        with patch.dict(os.environ, {'PERMISSION_ACTION':'apply','PERMISSION_CONFIRMATION':'PREPARAR_PERMISOS_SIN_ACTIVAR_BETA'}), patch.object(deployment,'query',side_effect=[[state],[{'dormant':True,'api_ready':True}]]) as query:
            deployment.main()
            self.assertEqual(query.call_count,2)
            self.assertFalse(any('create table' in call.args[0].lower() for call in query.call_args_list))
