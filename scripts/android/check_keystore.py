"""Compare the actual DER certificate to the public expected fingerprint.
Only public certificate fingerprints are printed. No secret values or certificate stdout.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile


def certificate_fingerprint(path, alias, env):
    with tempfile.TemporaryDirectory(prefix='vetdosis-public-cert-') as directory:
        certificate = Path(directory) / 'certificate.der'
        result = subprocess.run(['keytool', '-exportcert', '-keystore', str(path),
            '-alias', alias, '-storepass:env', 'ANDROID_BETA_STORE_PASSWORD',
            '-file', str(certificate)], env=env, capture_output=True)
        if result.returncode:
            raise ValueError('No se pudo leer el certificado del keystore; no se mostrarán credenciales.')
        return hashlib.sha256(certificate.read_bytes()).hexdigest()


if __name__ == '__main__':
    actual = certificate_fingerprint(os.environ['ANDROID_BETA_KEYSTORE_PATH'],
                                     os.environ['ANDROID_BETA_KEY_ALIAS'], os.environ)
    expected = os.environ['ANDROID_BETA_CERT_SHA256'].replace(':', '').strip().lower()
    print('Certificado real del keystore (SHA-256 público):', actual)
    print('Huella pública configurada:', expected)
    if actual != expected:
        raise SystemExit('La huella configurada no coincide con el certificado de la llave. No cambiar la llave; revisar la huella pública.')
    print('Keystore y huella pública coinciden.')
