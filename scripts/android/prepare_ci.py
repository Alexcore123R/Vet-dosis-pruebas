"""Prepare beta release identity. Never print credentials or key bytes."""
import base64
import os
from pathlib import Path
import time

EPOCH = 1577836800  # Fixed 2020-01-01 UTC; never move/reset to reuse version codes.
PACKAGE = 'io.github.alexcore123r.vetdosis.beta'


def version_code(timestamp):
    value = int(timestamp) - EPOCH
    if not 1 <= value <= 2_100_000_000:
        raise ValueError('Fecha de compilación fuera del rango de versionCode.')
    return value


def prepare(env):
    required = ['ANDROID_BETA_KEYSTORE_BASE64', 'ANDROID_BETA_STORE_PASSWORD',
                'ANDROID_BETA_KEY_ALIAS', 'ANDROID_BETA_KEY_PASSWORD',
                'ANDROID_BETA_CERT_SHA256']
    missing = [name for name in required if not env.get(name, '').strip()]
    if missing:
        raise ValueError('Faltan secretos/huella de firma: ' + ', '.join(missing))
    certificate = env['ANDROID_BETA_CERT_SHA256'].replace(':', '').lower().strip()
    if len(certificate) != 64 or any(c not in '0123456789abcdef' for c in certificate):
        raise ValueError('Huella pública de certificado inválida.')
    try:
        key = base64.b64decode(env['ANDROID_BETA_KEYSTORE_BASE64'], validate=True)
    except Exception:
        raise ValueError('Keystore base64 inválido.') from None
    if len(key) < 256:
        raise ValueError('Keystore incompleto.')
    runner = Path(env['RUNNER_TEMP'])
    path = runner / 'vetdosis-beta.jks'
    with path.open('xb') as handle:
        os.chmod(path, 0o600)
        handle.write(key)
    timestamp = time.time()
    code = version_code(timestamp)
    with Path(env['GITHUB_ENV']).open('a') as handle:
        handle.write(f'ANDROID_BETA_KEYSTORE_PATH={path}\nBETA_VERSION_CODE={code}\n')
    print(f'Beta {PACKAGE} · versionCode {code}; firma preparada sin mostrar credenciales.')


if __name__ == '__main__':
    try:
        prepare(os.environ)
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(str(error)) from None
