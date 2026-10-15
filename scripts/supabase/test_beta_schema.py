import contextlib
import io
import os
import unittest
from unittest.mock import patch
import beta_schema as beta


class ClosedBetaDeployment(unittest.TestCase):
    def state(self, **updates):
        state = dict(foundation=False, gate=False, storage_ready=True, rest_role=True, rest_hook=None)
        state.update(updates)
        return state

    def test_inspection_never_changes_policy(self):
        with patch.dict(os.environ, {'BETA_ACTION':'inspect'}), patch.object(beta,'query',return_value=[self.state()]) as query, contextlib.redirect_stdout(io.StringIO()):
            beta.main()
            self.assertEqual(query.call_count,1)

    def test_existing_hook_is_not_overwritten(self):
        with patch.dict(os.environ, {'BETA_ACTION':'prepare','BETA_CONFIRMATION':'PREPARAR_BETA_CERRADA'}), patch.object(beta,'query',return_value=[self.state(rest_hook='pgrst.db_pre_request=public.other_hook')]) as query, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit): beta.main()
            self.assertEqual(query.call_count,1)

    def test_prepare_keeps_admissions_closed_and_atomic(self):
        with patch.dict(os.environ, {'BETA_ACTION':'prepare','BETA_CONFIRMATION':'PREPARAR_BETA_CERRADA','BETA_ADMIN_EMAIL':''}), patch.object(beta,'query',side_effect=[[self.state()],[],[],[{'admissions_enabled':False,'enforcement_enabled':False}]]) as query, contextlib.redirect_stdout(io.StringIO()):
            beta.main()
            sql=query.call_args_list[1].args[0]
            self.assertTrue(sql.startswith('begin;'))
            self.assertTrue(sql.endswith('commit;'))
            self.assertIn('create table private.platform_admins',sql)
            self.assertIn('create table private.beta_builds',sql)
            self.assertNotIn('admissions_enabled=true',sql)


    def test_membership_blocks_admin_bootstrap_without_removing_it(self):
        states = [[self.state(foundation=True,gate=True)], [], [{'admissions_enabled':False,'enforcement_enabled':False}], [{'registered':True,'confirmed':True,'has_membership':True}]]
        with patch.dict(os.environ, {'BETA_ACTION':'prepare','BETA_CONFIRMATION':'PREPARAR_BETA_CERRADA','BETA_ADMIN_EMAIL':'synthetic@example.test'}), patch.object(beta,'query',side_effect=states) as query, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(SystemExit,'No se alteraron membresías'):
                beta.main()
            self.assertEqual(query.call_count,4)
            self.assertFalse(any('select private.beta_bootstrap_admin' in call.args[0] for call in query.call_args_list))

    def test_confirmed_separate_account_can_be_bootstrapped(self):
        states = [[self.state(foundation=True,gate=True)], [], [{'admissions_enabled':False,'enforcement_enabled':False}], [{'registered':True,'confirmed':True,'has_membership':False}], [{'ready':True}]]
        with patch.dict(os.environ, {'BETA_ACTION':'prepare','BETA_CONFIRMATION':'PREPARAR_BETA_CERRADA','BETA_ADMIN_EMAIL':'synthetic@example.test'}), patch.object(beta,'query',side_effect=states) as query, contextlib.redirect_stdout(io.StringIO()):
            beta.main()
            self.assertEqual(query.call_count,5)
            self.assertIn('select private.beta_bootstrap_admin',query.call_args.args[0])


if __name__=='__main__': unittest.main()
