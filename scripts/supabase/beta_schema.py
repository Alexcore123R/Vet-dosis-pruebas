"""Prepare the beta gate on the fixed test project, without enabling admissions."""
import os
from pathlib import Path
from identity_schema import query
from review_platform_clinic import review

ROOT = Path(__file__).resolve().parents[2]
PREFLIGHT = """select to_regclass('private.beta_policy') is not null as foundation,
 to_regclass('private.beta_builds') is not null as gate,
 to_regclass('storage.objects') is not null as storage_ready,
 exists(select 1 from pg_roles where rolname='authenticator') as rest_role,
 (select string_agg(v,',') from pg_roles r cross join lateral unnest(r.rolconfig) v where r.rolname='authenticator' and v like 'pgrst.db_pre_request=%') as rest_hook"""


def main():
    mode = os.environ.get('BETA_ACTION', 'inspect')
    if mode not in ('inspect', 'prepare'):
        raise SystemExit('Acción desconocida; no se abre la beta mediante este flujo.')
    state = query(PREFLIGHT)[0]
    print('Estado del proyecto de pruebas:', state)
    if mode == 'inspect':
        email = os.environ.get('BETA_ADMIN_EMAIL', '').strip()
        if email:
            review(email)
        return
    if os.environ.get('BETA_CONFIRMATION') != 'PREPARAR_BETA_CERRADA':
        raise SystemExit('Confirmación incorrecta.')
    if not state['storage_ready'] or not state['rest_role']:
        raise SystemExit('Faltan Storage o el rol REST.')
    hook = state['rest_hook']
    if hook and hook != 'pgrst.db_pre_request=public.beta_request_guard':
        raise SystemExit('Existe otro hook REST; requiere revisión para no sobrescribirlo.')
    if state['gate'] and not state['foundation']:
        raise SystemExit('Esquema beta parcial; no se sobrescribe.')
    scripts = []
    if not state['foundation']:
        scripts.append((ROOT / 'supabase/proposed/09A_beta_foundation.sql').read_text())
    if not state['gate']:
        scripts.append((ROOT / 'supabase/proposed/09B_beta_gate.sql').read_text())
    if scripts:
        # One atomic transaction; a failure rolls back both additions.
        joined = '\n'.join(s.replace('begin;\n', '', 1).removesuffix('commit;\n') for s in scripts)
        query('begin;\n' + joined + '\ncommit;')
    # Register a dormant hook only; its first instruction returns while enforcement is off.
    query("alter role authenticator set pgrst.db_pre_request='public.beta_request_guard'; notify pgrst,'reload config';")
    result = query('select admissions_enabled,enforcement_enabled from private.beta_policy')[0]
    print('Beta preparada. Política actual:', result)
    email = os.environ.get('BETA_ADMIN_EMAIL', '').strip()
    if email:
        if len(email) > 254 or '\n' in email or '@' not in email:
            raise SystemExit('Correo de administración inválido.')
        literal = email.replace("'", "''")
        account = query(f"""select
 exists(select 1 from auth.users where lower(btrim(email))=lower(btrim('{literal}'))) as registered,
 exists(select 1 from auth.users where lower(btrim(email))=lower(btrim('{literal}')) and email_confirmed_at is not null) as confirmed,
 exists(select 1 from public.clinic_members m join auth.users u on u.id=m.user_id where lower(btrim(u.email))=lower(btrim('{literal}'))) as has_membership,
 exists(select 1 from public.clinic_members m join auth.users u on u.id=m.user_id join public.account_workspaces w on w.clinic_id=m.clinic_id where lower(btrim(u.email))=lower(btrim('{literal}')) and w.kind='personal') as has_personal_space,
 exists(select 1 from public.clinic_members m join auth.users u on u.id=m.user_id left join public.account_workspaces w on w.clinic_id=m.clinic_id where lower(btrim(u.email))=lower(btrim('{literal}')) and coalesce(w.kind,'clinic')<>'personal') as has_clinic_space,
 exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace join pg_proc p on p.oid=t.tgfoid where n.nspname='auth' and c.relname='users' and not t.tgisinternal and (p.prosrc ilike '%clinic%' or p.prosrc ilike '%workspace%')) as automatic_workspace_trigger""")[0]
        print('Comprobación de cuenta separada:', account)
        if account['has_membership']:
            raise SystemExit('La cuenta pertenece a un espacio personal o clínica. No se alteraron membresías; se requiere una cuenta de plataforma separada.')
        if not account['confirmed']:
            print('Administración de plataforma: pendiente de registrar y confirmar la cuenta separada')
            return
        enrolled = query(f"select private.beta_bootstrap_admin('{literal}') as ready")[0]['ready']
        print('Administración de plataforma:', 'cuenta confirmada preparada; exige MFA' if enrolled else 'pendiente de registrar y confirmar la cuenta separada')


if __name__ == '__main__':
    main()
