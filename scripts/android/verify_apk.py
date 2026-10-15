"""Verify release signature, identity, version and backup flag before publishing."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from prepare_ci import PACKAGE


def certificate_fingerprints(output):
    # Android 36: "Signer #1 certificate ..."; Android 37: "V3.0 Signer: certificate ...".
    # Only certificate digests, never the distinct public-key digest. Require exact SHA-256.
    return {value.lower() for value in re.findall(
        r'^[^\r\n]*certificate SHA-256 digest:\s*([0-9a-fA-F]{64})[ \t]*$', output, re.MULTILINE)}


def stable_apksigner(sdk):
    tools = [p for p in (Path(sdk) / 'build-tools').glob('*/apksigner')
             if re.fullmatch(r'\d+\.\d+\.\d+', p.parent.name)]
    if not tools:
        raise ValueError('No hay herramientas Android estables para verificar la firma.')
    return max(tools, key=lambda p: tuple(int(v) for v in p.parent.name.split('.')))


def inspect_apk(apk, expected_code, expected_certificate, aapt, apksigner):
    def tool(*args):
        result = subprocess.run(args, capture_output=True, text=True)
        if result.returncode:
            raise ValueError('No se pudo verificar el APK; no se publicará.')
        return result.stdout
    certificate = tool(str(apksigner), 'verify', '--verbose', '--print-certs', str(apk))
    certificates = certificate_fingerprints(certificate)
    expected = expected_certificate.replace(':', '').strip().lower()
    if not certificates:
        raise ValueError('El verificador no reconoció una huella de certificado en la salida de apksigner.')
    if certificates != {expected}:
        raise ValueError('Firma diferente a la huella de beta esperada.')
    badging = tool(str(aapt), 'dump', 'badging', str(apk))
    match = re.search(r"package: name='([^']+)' versionCode='(\d+)'", badging)
    if not match or match[1] != PACKAGE or int(match[2]) != expected_code:
        raise ValueError('Identificador/versionCode inesperado.')
    manifest = tool(str(aapt), 'dump', 'xmltree', str(apk), 'AndroidManifest.xml')
    if not re.search(r'android:allowBackup\([^)]*\)=\(type 0x12\)0x0\b', manifest):
        raise ValueError('El APK no desactiva allowBackup explícitamente.')
    if 'io.github.alexcore123r.vetdosis.MainActivity' not in badging:
        raise ValueError('La actividad de arranque no corresponde al namespace.')
    return {'file': apk.name, 'package': PACKAGE, 'version_code': expected_code,
            'certificate_sha256': expected, 'sha256': hashlib.sha256(apk.read_bytes()).hexdigest()}


if __name__ == '__main__':
    apksigner = stable_apksigner(os.environ['ANDROID_HOME'])
    aapt = apksigner.parent / 'aapt'
    folder = Path('build/app/outputs/flutter-apk')
    apks = sorted(folder.glob('app-*-beta-release.apk'))
    if len(apks) != 2:
        raise SystemExit('Se esperaban exactamente dos APK beta firmados.')
    report = [inspect_apk(apk, int(os.environ['BETA_VERSION_CODE']),
                          os.environ['ANDROID_BETA_CERT_SHA256'], aapt, apksigner) for apk in apks]
    (folder / 'BUILD-INFO.json').write_text(json.dumps({'channel': 'beta',
        'supabase_project': 'wtrelwtztkddfktrfdpb', 'commit': os.environ['GITHUB_SHA'],
        'run_id': os.environ['GITHUB_RUN_ID'], 'apks': report}, indent=2))
    (folder / 'SHA256SUMS.txt').write_text(''.join(f"{p['sha256']}  {p['file']}\n" for p in report))
    print('Dos APK beta verificados: firma, identificador, versión y respaldo Android desactivado.')
