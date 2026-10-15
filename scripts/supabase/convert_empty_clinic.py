"""Execute the owner-approved empty clinic conversion on the fixed test project."""
import os
from pathlib import Path
import uuid
from identity_schema import query


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def statement(email, clinic_id, clinic_name):
    scope = str(uuid.UUID(clinic_id))
    if not email or len(email)>254 or '@' not in email or '\n' in email:
        raise ValueError('Correo inválido.')
    if not clinic_name or len(clinic_name)>120 or '\n' in clinic_name:
        raise ValueError('Nombre de clínica inválido.')
    sql = Path(__file__).with_suffix('.sql').read_text()
    return sql.replace('__CLINIC_ID__',literal(scope)+'::uuid').replace('__ACCOUNT_EMAIL__',literal(email)).replace('__CLINIC_NAME__',literal(clinic_name))


def main():
    if os.environ.get('CONVERSION_CONFIRMATION')!='ELIMINAR_SOLO_CLINICA_VACIA_Y_CONSERVAR_CUENTA':
        raise SystemExit('Falta la confirmación de la conversión revisada.')
    email=os.environ['CONVERSION_EMAIL']
    scope=str(uuid.UUID(os.environ['CONVERSION_CLINIC_ID']))
    query(statement(email,scope,os.environ['CONVERSION_CLINIC_NAME']))
    check=query(f"""select
 not exists(select 1 from public.clinics where id='{scope}'::uuid) as clinic_removed,
 exists(select 1 from auth.users where lower(btrim(email))=lower(btrim({literal(email)})) and email_confirmed_at is not null) as confirmed_account_preserved,
 exists(select 1 from private.platform_admins p join auth.users u on u.id=p.user_id where lower(btrim(u.email))=lower(btrim({literal(email)})) and p.enabled) as platform_enabled,
 not exists(select 1 from public.clinic_members m join auth.users u on u.id=m.user_id where lower(btrim(u.email))=lower(btrim({literal(email)}))) as no_clinic_memberships,
 exists(select 1 from pg_trigger where tgrelid='public.clinic_members'::regclass and tgname='prevent_last_clinic_admin_removal' and tgenabled='O') as membership_protection_enabled""")[0]
    if not all(check.values()):
        raise SystemExit('Verificación incompleta: revisar el estado, sin repetir acciones destructivas.')
    print('Conversión verificada:',check)
    print('Cuenta conservada y plataforma habilitada. El panel sigue exigiendo 2FA; no se abrieron admisiones beta.')


if __name__=='__main__': main()
