import unittest

from encrypted_database_backup import configuration_status, connection_environment, export_error_code, trusted_ca_bundle, validate_passphrase
from identity_schema import PROJECT


class EncryptedBackupTests(unittest.TestCase):
    def test_pinned_vendor_ca_is_combined_with_system_roots_and_removed(self):
        with trusted_ca_bundle() as bundle:
            self.assertGreaterEqual(bundle.read_bytes().count(b'BEGIN CERTIFICATE'), 2)
            path = bundle
        self.assertFalse(path.exists())

    def test_diagnostics_only_return_fixed_codes_not_private_connection_text(self):
        self.assertEqual(export_error_code('private-host: certificate verify failed'),
                         'database_tls_verification_failed')
        self.assertEqual(export_error_code('password authentication failed: synthetic-secret'),
                         'database_authentication_failed')
        self.assertEqual(export_error_code('synthetic-secret unknown problem'),
                         'database_export_unclassified_failure')

    def test_configuration_check_never_returns_credentials_or_claims_a_backup(self):
        report = configuration_status({})
        self.assertFalse(report['configuration_valid'])
        report = configuration_status({
            'SUPABASE_TEST_DB_URL': f'postgresql://postgres:synthetic@db.{PROJECT}.supabase.co:5432/postgres',
            'SUPABASE_TEST_BACKUP_PASSPHRASE': 'synthetic-only-backup-passphrase'})
        self.assertTrue(report['configuration_valid'])
        self.assertFalse(report['backup_created'])
        self.assertNotIn('synthetic', str(report))

    def test_fixed_direct_project_and_ssl_are_required(self):
        env = connection_environment(f'postgresql://postgres:synthetic%40password@db.{PROJECT}.supabase.co:5432/postgres')
        self.assertEqual(env['PGPASSWORD'], 'synthetic@password')
        self.assertEqual(env['PGSSLMODE'], 'verify-full')
        self.assertIn('read_only=on', env['PGOPTIONS'])

    def test_session_pooler_is_bound_to_project_username(self):
        env = connection_environment(f'postgresql://postgres.{PROJECT}:synthetic@aws-0-example.pooler.supabase.com:5432/postgres')
        self.assertEqual(env['PGUSER'], f'postgres.{PROJECT}')

    def test_foreign_projects_and_transaction_pooler_fail_closed(self):
        urls = [
            'postgresql://postgres:synthetic@db.other.supabase.co:5432/postgres',
            'postgresql://postgres.other:synthetic@aws-0-example.pooler.supabase.com:5432/postgres',
            f'postgresql://postgres.{PROJECT}:synthetic@aws-0-example.pooler.supabase.com:6543/postgres',
            f'postgresql://postgres:synthetic@db.{PROJECT}.supabase.co:5432/other',
            f'postgresql://postgres:synthetic@db.{PROJECT}.supabase.co:5432/postgres?options=unsafe',
        ]
        for url in urls:
            with self.subTest(url=url), self.assertRaises(ValueError) as error:
                connection_environment(url)
            self.assertNotIn('synthetic', str(error.exception))

    def test_passphrase_cannot_be_empty_short_or_multiline(self):
        for phrase in ('', 'short', 'synthetic-example-password\nextra'):
            with self.assertRaises(ValueError):
                validate_passphrase(phrase)


if __name__ == '__main__':
    unittest.main()
