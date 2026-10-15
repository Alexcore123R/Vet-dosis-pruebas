"""Owner-operated setup. Credentials go only to local ignored files and GitHub Secrets.
Run in a trusted private computer/Codespace. Never paste generated files into chat.
"""
import base64
import getpass
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile


def run(command, *, env=None, input=None):
    result = subprocess.run(command, env=env, input=input, capture_output=True)
    if result.returncode:
        raise RuntimeError('Falló la herramienta de firma/cifrado; no se mostrará su salida sensible.')
    return result.stdout


def create(output, backup_password):
    if len(backup_password) < 16:
        raise ValueError('Usa una contraseña de respaldo de al menos 16 caracteres.')
    output = Path(output)
    output.mkdir(mode=0o700, parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise ValueError('La carpeta ya contiene archivos. No se reemplazará una firma existente.')
    os.chmod(output, 0o700)
    store = secrets.token_urlsafe(32)
    key = secrets.token_urlsafe(32)
    alias = 'vetdosis-beta'
    env = {**os.environ, 'VET_STORE': store, 'VET_KEY': key}
    with tempfile.TemporaryDirectory(prefix='vetdosis-signing-') as temporary:
        root = Path(temporary)
        keystore = root / 'beta.jks'
        run(['keytool', '-genkeypair', '-storetype', 'JKS', '-keystore', str(keystore),
             '-alias', alias, '-keyalg', 'RSA', '-keysize', '3072', '-validity', '10000',
             '-dname', 'CN=VetDosis Beta', '-storepass:env', 'VET_STORE',
             '-keypass:env', 'VET_KEY', '-noprompt'], env=env)
        cert = run(['keytool', '-exportcert', '-keystore', str(keystore), '-alias', alias,
                    '-storepass:env', 'VET_STORE'], env=env)
        fingerprint = hashlib.sha256(cert).hexdigest()
        values = {'ANDROID_BETA_KEYSTORE_BASE64': base64.b64encode(keystore.read_bytes()).decode(),
                  'ANDROID_BETA_STORE_PASSWORD': store, 'ANDROID_BETA_KEY_ALIAS': alias,
                  'ANDROID_BETA_KEY_PASSWORD': key, 'ANDROID_BETA_CERT_SHA256': fingerprint}
        payload = root / 'recovery.json'
        payload.write_text(json.dumps({'format': 'vetdosis-beta-signing-recovery-v1', 'secrets': values}))
        os.chmod(payload, 0o600)
        encrypted = output / 'vetdosis-beta.signing-backup.gpg'
        run(['gpg', '--batch', '--yes', '--pinentry-mode', 'loopback', '--passphrase-fd', '0',
             '--symmetric', '--cipher-algo', 'AES256', '--output', str(encrypted), str(payload)],
            input=(backup_password+'\n').encode())
        os.chmod(encrypted, 0o600)
        recovered = run(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase-fd', '0',
                         '--decrypt', str(encrypted)], input=(backup_password+'\n').encode())
        if json.loads(recovered) != json.loads(payload.read_bytes()):
            raise RuntimeError('El respaldo cifrado no pasó la comprobación.')
        # Separate local files make service-side setup possible without printing secrets.
        for name, value in values.items():
            target = output / (name+'.txt')
            target.write_text(value)
            os.chmod(target, 0o600)
    return fingerprint


if __name__ == '__main__':
    password = getpass.getpass('Contraseña de copia cifrada (guárdala fuera del chat): ')
    confirm = getpass.getpass('Repite la contraseña: ')
    if password != confirm:
        raise SystemExit('Las contraseñas no coinciden; no se creó una llave.')
    try:
        fingerprint = create('.signing', password)
    except (ValueError, RuntimeError, OSError) as error:
        raise SystemExit(str(error)) from None
    print('Copia cifrada creada y verificada en .signing; no compartas los archivos de secretos.')
    print('Huella pública SHA-256:', fingerprint)
