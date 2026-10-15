"""Deploy only the reviewed additive identity schema to the fixed test project.

Credentials are read from the GitHub service environment, never CLI arguments.
The default is a read-only preflight. No credentials or response bodies are logged.
"""
import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.request

PROJECT = 'wtrelwtztkddfktrfdpb'
ENDPOINT = f'https://api.supabase.com/v1/projects/{PROJECT}/database/query'
PREFLIGHT = """select
 to_regclass('public.clinic_members') is not null as membership_ready,
 to_regclass('public.clinic_document_settings') is not null as branding_ready,
 to_regclass('storage.objects') is not null as storage_ready,
 to_regclass('public.account_identity') is not null as account_exists,
 to_regprocedure('public.account_identity_get()') is not null as account_get_exists,
 to_regprocedure('public.account_identity_save(integer,boolean)') is not null as account_save_exists,
 to_regprocedure('public.clinic_identity_get(uuid)') is not null as clinic_get_exists,
 exists(select 1 from storage.buckets where id='account-avatars') as bucket_exists"""


def query(sql):
    token = os.environ.get('SUPABASE_ACCESS_TOKEN', '').strip()
    if not token:
        raise SystemExit('Falta SUPABASE_ACCESS_TOKEN en los secretos de GitHub.')
    request = urllib.request.Request(
        ENDPOINT,
        data=json.dumps({'query': sql}).encode(),
        headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
        method='POST',
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise SystemExit(f'Supabase rechazó la operación administrativa (HTTP {error.code}). No se muestran credenciales ni respuesta privada.') from None
    except (urllib.error.URLError, TimeoutError):
        raise SystemExit('No se pudo confirmar la conexión administrativa. Revisar el estado antes de reintentar.') from None


def main():
    mode = os.environ.get('IDENTITY_ACTION', 'inspect')
    if mode not in ('inspect', 'apply'):
        raise SystemExit('Acción desconocida.')
    state = query(PREFLIGHT)[0]
    print('Proyecto de pruebas:', PROJECT)
    print('Preflight:', json.dumps(state, sort_keys=True))
    if mode == 'inspect':
        return
    if os.environ.get('IDENTITY_CONFIRMATION') != 'ACTIVAR_IDENTIDAD_EN_PRUEBAS':
        raise SystemExit('Falta la confirmación exacta del proyecto de pruebas.')
    if not all(state[name] for name in ('membership_ready', 'branding_ready', 'storage_ready')):
        raise SystemExit('Faltan dependencias; no se aplicó la migración.')
    identity_parts = ('account_exists', 'account_get_exists', 'account_save_exists', 'clinic_get_exists', 'bucket_exists')
    if any(state[name] for name in identity_parts):
        if all(state[name] for name in identity_parts):
            print('La identidad ya existe; no se repite ni sobrescribe su migración.')
            return
        raise SystemExit('Existe un esquema parcial: requiere revisión antes de aplicar cambios.')
    sql = (Path(__file__).resolve().parents[2] / 'supabase/proposed/10_identity.sql').read_text()
    query(sql)
    after = query(PREFLIGHT)[0]
    if not all(after[name] for name in identity_parts):
        raise SystemExit('Verificación incompleta; revisar el servidor antes de reintentar.')
    print('Identidad aplicada y objetos verificados; las pruebas con sesión real y Storage binario siguen pendientes.')


if __name__ == '__main__':
    main()
