"""Actual SDK verification with temporary synthetic keys; never a distributable app."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile
from verify_apk import certificate_fingerprints, stable_apksigner


class ApkSignerIntegrationTest(unittest.TestCase):
    def test_real_sdk_certificate_matches_exported_der(self):
        paths = os.environ.get('APK_SIGNER_TEST_JARS', '')
        if paths:
            jars = [Path(value) for value in paths.split(os.pathsep)]
        elif os.environ.get('ANDROID_HOME'):
            jars = [stable_apksigner(os.environ['ANDROID_HOME']).parent/'lib'/'apksigner.jar']
        else:
            self.skipTest('Android SDK not installed; synthetic APK integration runs in Android CI.')
        def run(args, env):
            result = subprocess.run(args, env=env, capture_output=True)
            if result.returncode:
                self.fail('Synthetic SDK integration tool failed; no key output logged.')
            return result.stdout
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            env = {**os.environ, 'SYNTHETIC_APK_TEST_PASSWORD': 'temporary-test-not-a-user-secret'}
            run(['keytool','-genkeypair','-keystore',str(root/'fixture.jks'),'-storetype','JKS',
                 '-alias','fixture','-keyalg','RSA','-keysize','2048','-dname','CN=Synthetic SDK Test',
                 '-storepass:env','SYNTHETIC_APK_TEST_PASSWORD','-keypass:env','SYNTHETIC_APK_TEST_PASSWORD',
                 '-validity','1'],env)
            run(['keytool','-exportcert','-keystore',str(root/'fixture.jks'),'-alias','fixture',
                 '-storepass:env','SYNTHETIC_APK_TEST_PASSWORD','-file',str(root/'certificate.der')],env)
            expected = hashlib.sha256((root/'certificate.der').read_bytes()).hexdigest()
            # Explicit minSdk lets apksigner verify this non-installable ZIP fixture.
            with zipfile.ZipFile(root/'unsigned.apk','w') as archive:
                archive.writestr('AndroidManifest.xml','Synthetic verification fixture, not an application')
            for i, jar in enumerate(jars):
                signed = root/f'signed-{i}.apk'
                run(['java','-jar',str(jar),'sign','--min-sdk-version','24','--ks',str(root/'fixture.jks'),
                     '--ks-key-alias','fixture','--ks-pass','env:SYNTHETIC_APK_TEST_PASSWORD',
                     '--key-pass','env:SYNTHETIC_APK_TEST_PASSWORD','--out',str(signed),str(root/'unsigned.apk')],env)
                output = run(['java','-jar',str(jar),'verify','--min-sdk-version','24','--verbose','--print-certs',str(signed)],env).decode()
                self.assertEqual(certificate_fingerprints(output),{expected})
