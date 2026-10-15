import contextlib
import io
import os
import unittest
from unittest.mock import patch
import identity_schema as deploy


class DeploymentGuards(unittest.TestCase):
    def state(self, **updates):
        state = dict.fromkeys(('membership_ready', 'branding_ready', 'storage_ready'), True)
        state.update(dict.fromkeys(('account_exists', 'account_get_exists', 'account_save_exists', 'clinic_get_exists', 'bucket_exists'), False))
        state.update(updates)
        return state

    def run_mode(self, state, confirmation='ACTIVAR_IDENTIDAD_EN_PRUEBAS', mode='apply'):
        with patch.dict(os.environ, {'IDENTITY_ACTION': mode, 'IDENTITY_CONFIRMATION': confirmation}), patch.object(deploy, 'query', return_value=[state]) as query, contextlib.redirect_stdout(io.StringIO()):
            try:
                deploy.main()
            except SystemExit:
                pass
            # Every refusal/inspection case below must issue only the read-only preflight.
            self.assertEqual(query.call_count, 1)
            self.assertEqual(query.call_args.args, (deploy.PREFLIGHT,))

    def test_preflight_never_writes(self):
        self.run_mode(self.state(), mode='inspect')

    def test_missing_confirmation_never_writes(self):
        self.run_mode(self.state(), confirmation='otro proyecto')

    def test_missing_dependency_never_writes(self):
        self.run_mode(self.state(storage_ready=False))

    def test_partial_schema_never_overwrites(self):
        self.run_mode(self.state(account_exists=True))

    def test_existing_schema_never_repeats_migration(self):
        state = self.state()
        self.run_mode({key: True for key in state})

    def test_apply_sends_only_fixed_reviewed_migration(self):
        before = self.state()
        after = dict.fromkeys(before, True)
        with patch.dict(os.environ, {'IDENTITY_ACTION': 'apply', 'IDENTITY_CONFIRMATION': 'ACTIVAR_IDENTIDAD_EN_PRUEBAS'}), patch.object(deploy, 'query', side_effect=[[before], [], [after]]) as query, contextlib.redirect_stdout(io.StringIO()):
            deploy.main()
            self.assertEqual(query.call_count, 3)
            self.assertIn('create table public.account_identity', query.call_args_list[1].args[0])
            self.assertNotIn('09A_beta_foundation', query.call_args_list[1].args[0])


if __name__ == '__main__':
    unittest.main()
