"""Register a verified APK publication once. Never changes its original expiry."""
import os
from identity_schema import query

code = int(os.environ['BETA_VERSION_CODE'])
if not 1 <= code <= 2100000000:
    raise SystemExit('Versión fuera del rango aprobado.')
query(f'select private.beta_publish_build({code})')
print('Publicación beta registrada con hora de servidor y caducidad de 90 días.')
