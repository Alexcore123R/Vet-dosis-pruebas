"""Compare the actual DER certificate to the public expected fingerprint.
Only public certificate fingerprints are printed. No secret values or certificate stdout.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile


def certificate_digests(path, alias, env):
    with tempfile.TemporaryDirectory(prefix='vetdosis-public-cert-') as directory:
        certificate = Path(directory) / 'certificate.der'
        result = subprocess.run(['keytool', '-exportcert', '-keystore', str(path),
            '-alias', alias, '-storepass:env', 'ANDROID_BETA_STORE_PASSWORD',
            '-file', str(certificate)], env=env, capture_output=True)
        if result.returncode:
            raise ValueError('No se pudo leer el certificado del keystore; no se mostrarán credenciales.')
        der = certificate.read_bytes()
        return {'SHA-1': hashlib.sha1(der).hexdigest(), 'SHA-256': hashlib.sha256(der).hexdigest()}


def certificate_fingerprint(path, alias, env):
    return certificate_digests(path, alias, env)['SHA-256']


if __name__ == '__main__':
    digests = certificate_digests(os.environ['ANDROID_BETA_KEYSTORE_PATH'],
                                  os.environ['ANDROID_BETA_KEY_ALIAS'], os.environ)
    actual = digests['SHA-256']
    for algorithm, digest in digests.items():
        formatted = ':'.join(digest[i:i+2].upper() for i in range(0, len(digest), 2))
        print(f'{algorithm}: {formatted}')
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            summary.write('### Huellas públicas del certificado beta\n\n')
            for algorithm, digest in digests.items():
                summary.write(f'- {algorithm}: `{digest}`\n')
    expected = os.environ['ANDROID_BETA_CERT_SHA256'].replace(':', '').strip().lower()
    print('Certificado real del keystore (SHA-256 público):', actual)
    print('Huella pública configurada:', expected)
    if actual != expected:
        raise SystemExit('La huella configurada no coincide con el certificado de la llave. No cambiar la llave; revisar la huella pública.')
    print('Keystore y huella pública coinciden.')
