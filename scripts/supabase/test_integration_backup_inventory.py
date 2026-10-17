import io
import json
import os
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError

from integration_backup_inventory import ENDPOINT, inspect, summarize


class BackupInventoryTests(unittest.TestCase):
    def test_inventory_never_claims_verified_restore_or_exports_unknown_fields(self):
        report = summarize({'backups': [{'status': 'COMPLETED', 'inserted_at': '2026-10-17',
                                        'signed_url': 'must-not-export', 'password': 'must-not-export'}],
                            'pitr_enabled': True})
        self.assertEqual(report['available_entries'], 1)
        self.assertNotIn('must-not-export', json.dumps(report))
        self.assertFalse(report['restore_verified'])
        self.assertFalse(report['deploy_ready'])

    def test_only_get_fixed_test_endpoint(self):
        opener = Mock(return_value=io.StringIO('{"backups":[]}'))
        with patch.dict(os.environ, {'SUPABASE_ACCESS_TOKEN': 'synthetic'}):
            inspect(opener)
        request = opener.call_args.args[0]
        self.assertEqual(request.full_url, ENDPOINT)
        self.assertEqual(request.method, 'GET')

    def test_forbidden_response_is_not_logged_or_counted_as_backup(self):
        opener = Mock(side_effect=HTTPError(ENDPOINT, 403, 'private-body', {}, None))
        with patch.dict(os.environ, {'SUPABASE_ACCESS_TOKEN': 'synthetic'}):
            report = inspect(opener)
        self.assertFalse(report['inventory_confirmed'])
        self.assertEqual(report['http_status'], 403)
        self.assertNotIn('private-body', json.dumps(report))

    def test_malformed_or_missing_inventory_is_rejected(self):
        for payload in ({}, {'backups': None}, {'backups': [None]}):
            with self.assertRaises(ValueError):
                summarize(payload)


if __name__ == '__main__':
    unittest.main()
