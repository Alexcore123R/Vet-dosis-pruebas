"""Check denial of anonymous legal requests on the fixed test backend; log no keys/bodies."""
import base64
import json
import os
import urllib.error
import urllib.request


def main():
    key=os.environ.get('SUPABASE_TEST_PUBLISHABLE_KEY','').strip()
    if not key:
        raise SystemExit('Falta la clave pública de pruebas en el servicio.')
    if not key.startswith('sb_publishable_'):
        try:
            payload=key.split('.')[1]
            role=json.loads(base64.urlsafe_b64decode(payload+'='*(-len(payload)%4)))['role']
        except (IndexError,ValueError,KeyError):
            raise SystemExit('La clave configurada no tiene formato de cliente público.') from None
        if role!='anon':
            raise SystemExit('Se rechaza usar una credencial privilegiada en esta prueba.')
    probes=[
        ('rpc/beta_accept_terms',{'p_terms':'probe-unpublished','p_hash':'invalid','p_privacy_version':'probe-unpublished','p_privacy_hash':'invalid'}),
        ('rpc/beta_enroll',{'p_terms':'probe-unpublished','p_hash':'invalid','p_token':None,'p_privacy_version':'probe-unpublished','p_privacy_hash':'invalid'}),
        ('terms_acceptances?select=terms_version,privacy_version&limit=1',None),
    ]
    for path,data in probes:
        request=urllib.request.Request('https://wtrelwtztkddfktrfdpb.supabase.co/rest/v1/'+path,
            data=None if data is None else json.dumps(data).encode(),
            headers={'apikey':key,'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(request,timeout=20) as response:
                raise SystemExit('Acceso anon inesperadamente permitido: '+path.split('?')[0])
        except urllib.error.HTTPError as error:
            try:
                code=json.loads(error.read()).get('code')
            except ValueError:
                raise SystemExit('Respuesta no reconocida; revisar sin mostrar contenido.') from None
            if error.code not in (401,403) or code!='42501':
                raise SystemExit('Denegación no comprobada: HTTP '+str(error.code)) from None
            print(path.split('?')[0]+': anon rechazado por permisos (HTTP '+str(error.code)+', 42501).')
        except (urllib.error.URLError,TimeoutError):
            raise SystemExit('No se pudo comprobar el acceso anon por conexión.') from None
    print('Tres pruebas HTTP anon satisfactorias; sin inscripciones ni aceptaciones creadas.')


if __name__=='__main__':
    main()
