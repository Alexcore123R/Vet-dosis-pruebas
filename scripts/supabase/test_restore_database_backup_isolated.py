from pathlib import Path
import unittest

from identity_schema import PROJECT
from restore_database_backup_isolated import archive_path, restore_error_classes


class RestoreBackupTests(unittest.TestCase):
    def manifest(self):
        return {'project_ref':PROJECT,'file':'synthetic.dump.gpg',
                'encrypted_sha256':'a'*64,'plaintext_sha256':'b'*64}

    def test_only_known_project_and_local_artifact_filename_are_accepted(self):
        manifest=self.manifest()
        self.assertEqual(archive_path(Path('/tmp/synthetic'),manifest),Path('/tmp/synthetic/synthetic.dump.gpg'))
        for value in ('../foreign.dump.gpg','/tmp/foreign.dump.gpg','plain.sql'):
            manifest['file']=value
            with self.assertRaises(ValueError): archive_path(Path('/tmp'),manifest)
        manifest=self.manifest();manifest['project_ref']='different-project'
        with self.assertRaises(ValueError): archive_path(Path('/tmp'),manifest)

    def test_absent_or_malformed_hashes_fail_before_decryption_or_restore(self):
        manifest=self.manifest();manifest['plaintext_sha256']='not-a-checksum'
        with self.assertRaises(ValueError): archive_path(Path('/tmp'),manifest)

    def test_private_restore_diagnostics_are_replaced_by_fixed_categories(self):
        self.assertEqual(restore_error_classes('ERROR: role "private name" does not exist'),['role_missing'])
        self.assertEqual(restore_error_classes('private clinical text'),['unclassified_restore_failure'])


if __name__=='__main__':
    unittest.main()
