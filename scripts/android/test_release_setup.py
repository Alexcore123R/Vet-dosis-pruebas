import base64
from pathlib import Path
import os
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

from prepare_ci import EPOCH, PACKAGE, prepare, version_code
from verify_apk import inspect_apk, certificate_fingerprints, stable_apksigner
from create_signing import create, run
from check_keystore import certificate_fingerprint, certificate_digests
import hashlib

ROOT = Path(__file__).resolve().parents[2]


class ReleaseSetupTest(unittest.TestCase):
    def test_counter_is_per_build_not_per_abi_and_does_not_reset_on_workflow_rename(self):
        self.assertEqual(version_code(EPOCH+100), 100)
        self.assertGreater(version_code(EPOCH+101), version_code(EPOCH+100))
        for timestamp in [EPOCH, EPOCH+2_100_000_001]:
            with self.assertRaises(ValueError):
                version_code(timestamp)

    def test_missing_signing_does_not_create_release_material(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = {'RUNNER_TEMP': tmp, 'GITHUB_ENV': str(Path(tmp)/'env')}
            with self.assertRaisesRegex(ValueError, 'Faltan'):
                prepare(env)
            self.assertEqual(list(Path(tmp).iterdir()), [])

    def test_prepare_uses_private_file_and_never_emits_key_or_password(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = {'RUNNER_TEMP': tmp, 'GITHUB_ENV': str(Path(tmp)/'env'),
                   'ANDROID_BETA_KEYSTORE_BASE64': base64.b64encode(b'fixture'*100).decode(),
                   'ANDROID_BETA_STORE_PASSWORD': 'synthetic-store',
                   'ANDROID_BETA_KEY_ALIAS': 'fixture', 'ANDROID_BETA_KEY_PASSWORD': 'synthetic-key',
                   'ANDROID_BETA_CERT_SHA256': 'a'*64}
            with patch('builtins.print') as printed, patch('prepare_ci.time.time', return_value=EPOCH+123):
                prepare(env)
            self.assertEqual((Path(tmp)/'vetdosis-beta.jks').stat().st_mode & 0o777, 0o600)
            self.assertIn('BETA_VERSION_CODE=123', Path(env['GITHUB_ENV']).read_text())
            output = str(printed.call_args_list)
            for name in ['ANDROID_BETA_KEYSTORE_BASE64','ANDROID_BETA_STORE_PASSWORD','ANDROID_BETA_KEY_PASSWORD']:
                self.assertNotIn(env[name], output)
            with self.assertRaises(FileExistsError):
                prepare(env)

    def test_android_manifest_and_extraction_exclude_private_data(self):
        android = '{http://schemas.android.com/apk/res/android}'
        manifest = ET.parse(ROOT/'android/app/src/main/AndroidManifest.xml').getroot()
        application = manifest.find('application')
        self.assertEqual(application.get(android+'allowBackup'), 'false')
        self.assertEqual(application.get(android+'dataExtractionRules'), '@xml/data_extraction_rules')
        data = manifest.find('.//data')
        self.assertEqual(data.get(android+'scheme'), PACKAGE)
        extraction = ET.parse(ROOT/'android/app/src/main/res/xml/data_extraction_rules.xml').getroot()
        for kind in ['cloud-backup','device-transfer']:
            domains = {e.attrib['domain'] for e in extraction.find(kind).findall('exclude')}
            self.assertTrue({'root','file','database','sharedpref','external','device_root'} <= domains)
        gradle = (ROOT/'android/app/build.gradle.kts').read_text()
        self.assertIn('applicationIdSuffix = ".beta"', gradle)
        self.assertNotIn('signingConfigs.getByName("debug")', gradle)

    def test_apk_verifier_rejects_unsigned_wrong_identity_and_wrong_certificate(self):
        with tempfile.TemporaryDirectory() as tmp:
            apk = Path(tmp)/'fixture.apk'; apk.write_bytes(b'fixture')
            cert = 'a'*64
            good_cert = subprocess.CompletedProcess([],0,stdout=f'Signer #1 certificate SHA-256 digest: {cert}',stderr='')
            good_badging = subprocess.CompletedProcess([],0,stdout=f"package: name='{PACKAGE}' versionCode='123'\nlaunchable-activity: name='io.github.alexcore123r.vetdosis.MainActivity'",stderr='')
            good_manifest = subprocess.CompletedProcess([],0,stdout='android:allowBackup(0x01010280)=(type 0x12)0x0',stderr='')
            with patch('verify_apk.subprocess.run', side_effect=[good_cert,good_badging,good_manifest]):
                self.assertEqual(inspect_apk(apk,123,cert,'aapt','apksigner')['version_code'],123)
            with patch('verify_apk.subprocess.run', return_value=subprocess.CompletedProcess([],1,stdout='',stderr='')):
                with self.assertRaises(ValueError): inspect_apk(apk,123,cert,'aapt','apksigner')
            with patch('verify_apk.subprocess.run', return_value=good_cert):
                with self.assertRaisesRegex(ValueError,'Firma'): inspect_apk(apk,123,'b'*64,'aapt','apksigner')
            with patch('verify_apk.subprocess.run', side_effect=[good_cert,good_badging]):
                with self.assertRaisesRegex(ValueError,'versionCode'): inspect_apk(apk,124,cert,'aapt','apksigner')
            bad_manifest = subprocess.CompletedProcess([],0,stdout='android:allowBackup(0x01010280)=(type 0x12)0xffffffff',stderr='')
            with patch('verify_apk.subprocess.run', side_effect=[good_cert,good_badging,bad_manifest]):
                with self.assertRaisesRegex(ValueError,'allowBackup'): inspect_apk(apk,123,cert,'aapt','apksigner')

    def test_android37_signer_label_and_public_key_digest_are_distinct(self):
        expected = 'a'*64
        output = f"V3.0 Signer: certificate SHA-256 digest: {expected}\nV3.0 Signer: public key SHA-256 digest: {'b'*64}\n"
        self.assertEqual(certificate_fingerprints(output), {expected})
        self.assertEqual(certificate_fingerprints(f"Signer #1 certificate SHA-256 digest: {expected}\n"), {expected})
        self.assertEqual(certificate_fingerprints('certificate SHA-256 digest: aaaa'), set())
        self.assertEqual(certificate_fingerprints(output + f"Signer #2 certificate SHA-256 digest: {'c'*64}\n"), {expected,'c'*64})

    def test_stable_sdk_is_selected_instead_of_rc(self):
        with tempfile.TemporaryDirectory() as tmp:
            for version in ['36.0.0','37.0.0','37.0.0-rc2','38.0.0-preview']:
                path = Path(tmp)/'build-tools'/version/'apksigner'
                path.parent.mkdir(parents=True);path.touch()
            self.assertEqual(stable_apksigner(tmp).parent.name,'37.0.0')

    def test_certificate_hash_ignores_jvm_console_warnings(self):
        with tempfile.TemporaryDirectory() as tmp:
            def export(command, **kwargs):
                Path(command[command.index('-file')+1]).write_bytes(b'synthetic-DER-certificate')
                return subprocess.CompletedProcess(command,0,stdout=b'JVM container warning',stderr=b'')
            with patch('check_keystore.subprocess.run', side_effect=export):
                actual = certificate_fingerprint(Path(tmp)/'fixture.jks','fixture',{})
            with patch('check_keystore.subprocess.run', side_effect=export):
                digests = certificate_digests(Path(tmp)/'fixture.jks','fixture',{})
            self.assertEqual(digests['SHA-1'], hashlib.sha1(b'synthetic-DER-certificate').hexdigest())
            self.assertEqual(digests['SHA-256'], actual)
            self.assertEqual(actual, hashlib.sha256(b'synthetic-DER-certificate').hexdigest())
            self.assertNotEqual(actual, hashlib.sha256(b'JVM container warningsynthetic-DER-certificate').hexdigest())

    def test_synthetic_key_recovery_roundtrip_and_no_accidental_replacement(self):
        # Temporary synthetic signing identity only. Never used to sign a distributed APK.
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)/'synthetic'
            with patch.dict(os.environ, {'GNUPGHOME': str(Path(tmp)/'gnupg')}):
                Path(os.environ['GNUPGHOME']).mkdir(mode=0o700)
                create(output, 'synthetic-backup-password-not-a-user-secret')
                encrypted = output/'vetdosis-beta.signing-backup.gpg'
                with self.assertRaises(RuntimeError):
                    run(['gpg','--batch','--pinentry-mode','loopback','--passphrase-fd','0','--decrypt',str(encrypted)],input=b'wrong-password\n')
                with self.assertRaises(ValueError):
                    create(output, 'synthetic-backup-password-not-a-user-secret')
                for file in output.iterdir(): self.assertEqual(file.stat().st_mode & 0o777,0o600)


if __name__ == '__main__':
    unittest.main()
