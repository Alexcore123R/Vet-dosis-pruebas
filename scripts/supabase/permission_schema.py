"""Install only dormant permission foundation in the fixed test project."""
import os
from pathlib import Path
from identity_schema import query

ROOT = Path(__file__).resolve().parents[2]
TABLES = ('permission_policy','permission_catalog','member_job_labels','procedure_types',
          'professional_verifications','professional_revocations',
          'clinic_responsible_designations','member_permission_grants','permission_revocations')
FUNCTIONS = ('permission_snapshot(uuid)','permission_set_job(uuid,uuid,text)',
             'permission_procedure_set(uuid,uuid,text,boolean)',
             'permission_grant(uuid,uuid,text,uuid,timestamp with time zone,text)',
             'permission_revoke(uuid,text)', 'permission_responsible_propose(uuid,uuid,timestamp with time zone)',
             'permission_responsible_respond(uuid,boolean)','permission_responsible_revoke(uuid)',
             'permission_professional_review(uuid,uuid,timestamp with time zone,text,text,timestamp with time zone)',
             'permission_professional_revoke(uuid,text)','permission_professional_snapshot(uuid)')
PREFLIGHT = """select
 to_regclass('public.professional_profiles') is not null and to_regclass('private.professional_profile_versions') is not null as prescribing_ready,
 to_regprocedure('private.beta_install_guards()') is not null as beta_ready,
 (select not admissions_enabled and not enforcement_enabled from private.beta_policy) as beta_closed,
 (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relkind='r' and c.relname in (""" + ','.join("'"+t+"'" for t in TABLES) + ")) as foundation_tables"


def validate_existing():
    signature_checks = ' and '.join("to_regprocedure('public."+f+"') is not null" for f in FUNCTIONS)
    state = query("select not enforcement_enabled and not migration_reviewed as dormant,"+signature_checks+" as api_ready from private.permission_policy")[0]
    if not state['dormant'] or not state['api_ready']:
        raise SystemExit('Modelo parcial o ya activado: requiere revisión, no se modifica.')
    print('Base de permisos instalada y desactivada; sin conversión automática de roles.')


def main():
    action = os.environ.get('PERMISSION_ACTION','inspect')
    if action not in ('inspect','apply'):
        raise SystemExit('Acción inválida.')
    state = query(PREFLIGHT)[0]
    print('Preflight de permisos:',state)
    if action == 'inspect':
        if state['foundation_tables'] == len(TABLES):
            validate_existing()
        return
    if os.environ.get('PERMISSION_CONFIRMATION') != 'PREPARAR_PERMISOS_SIN_ACTIVAR_BETA':
        raise SystemExit('Confirmación incorrecta.')
    if not all(state[k] for k in ('prescribing_ready','beta_ready','beta_closed')):
        raise SystemExit('Faltan dependencias o la beta no está cerrada; no se cambia el proyecto.')
    if state['foundation_tables'] not in (0,len(TABLES)):
        raise SystemExit('Modelo parcial: no se reejecuta ni sobrescribe.')
    if state['foundation_tables'] == 0:
        query((ROOT / 'supabase/proposed/11A_permission_foundation.sql').read_text())
    validate_existing()
    print('Sin datos clínicos, verificaciones ni concesiones creadas por el despliegue. No se abrieron admisiones.')


if __name__ == '__main__':
    main()
