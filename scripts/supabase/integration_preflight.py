"""Read-only inventory for the fixed beta test backend. Never applies migrations."""
import argparse
import hashlib
import json
from pathlib import Path
import re

from identity_schema import PROJECT, query

ROOT = Path(__file__).resolve().parents[2]
# Explicit order; restoration is deliberately excluded from the initial beta.
BETA_FILES = (
    '13A_permission_patient_registration.sql',
    '13B_permission_agenda.sql',
    '13C_permission_clinical.sql',
    '13D_hospital_flexible_admission.sql',
    '13E_permission_hospital_reviews.sql',
    '13F_permission_medication.sql',
    '13G_permission_hospital_resolution.sql',
    '13H1_consultation_attestation.sql',
    '13H2_prescription_individual.sql',
    '13H3_standing_prescriptions.sql',
    '13I1_permission_dispensing.sql',
    '13I2_permission_inventory_cash.sql',
    '13J1_permission_reports.sql',
    '13J2_permission_form_templates.sql',
    '13J3_form_document_drafts.sql',
    '13J4_form_individual_workflow.sql',
    '13K_clinical_screen_contract.sql',
    '13L_independent_clinical_cases.sql',
    '13M_death_attestation.sql',
    '13N_module_navigation_dashboard.sql',
    '13O_permission_backups_exports.sql',
    '13P_workspace_management_cutover.sql',
    '13W_clinical_vitals.sql',
)
MARKERS = (
    'public.app_module_workspace', 'public.backup_workspace',
    'public.clinic_statistics', 'public.workspace_management_status',
    'public.rx_prescription_permissions', 'public.rx_standing_workspace',
    'public.inv_management_permissions', 'public.form_document_workspace',
    'public.clinical_workspace', 'public.clinical_death_workspace',
    'public.clinical_vitals_add',
)
CATALOG_SQL = """select
 (select jsonb_object_agg(label, to_regclass(relation_name) is not null)
  from (values
   ('beta_policy','private.beta_policy'),
   ('permission_policy','private.permission_policy'),
   ('members','public.clinic_members'),
   ('account_identity','public.account_identity'),
   ('clinical_vitals','public.clinical_vital_sets'),
   ('restore_stage','private.backup_restore_staging')
  ) required(label,relation_name)) as relations,
 (select coalesce(jsonb_agg(jsonb_build_object('name',n.nspname||'.'||p.proname,
   'signature',pg_get_function_identity_arguments(p.oid),
   'source_sha256',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex'))),'[]'::jsonb)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (
    'app_module_workspace','backup_workspace','clinic_statistics',
    'workspace_management_status','rx_prescription_permissions',
    'rx_standing_workspace','inv_management_permissions',
    'form_document_workspace','clinical_workspace','clinical_death_workspace',
    'clinical_vitals_add')) as functions,
 (select coalesce(jsonb_agg(v),'[]'::jsonb) from pg_roles r
  cross join lateral unnest(r.rolconfig) v
  where r.rolname='authenticator' and v like 'pgrst.db_pre_request=%') as hooks"""
POLICY_SQL = {
    'beta_policy': 'select admissions_enabled,enforcement_enabled from private.beta_policy',
    'permission_policy': 'select enforcement_enabled,migration_reviewed from private.permission_policy',
}


def local_plan(root=ROOT):
    return [
        {'order': i + 1, 'file': 'supabase/proposed/' + name,
         'sha256': hashlib.sha256((root / 'supabase/proposed' / name).read_bytes()).hexdigest()}
        for i, name in enumerate(BETA_FILES)
    ]


def expected_markers(root=ROOT):
    """Fingerprint only named, dollar-quoted function bodies; not proof of ACLs."""
    result = {}
    for name in BETA_FILES:
        text = (root / 'supabase/proposed' / name).read_text()
        for marker in MARKERS:
            pattern = (r'create\s+(?:or\s+replace\s+)?function\s+' + re.escape(marker)
                       + r'\s*\([^;]*?\bas\s+(\$[A-Za-z_]*\$)(.*?)\1\s*;')
            for match in re.finditer(pattern, text, re.I | re.S):
                result[marker] = hashlib.sha256(match.group(2).encode()).hexdigest()
    if set(result) != set(MARKERS):
        raise ValueError('No se identificaron todos los cuerpos de función candidatos.')
    return result


def inspect_remote(read=query, root=ROOT):
    rows = read(CATALOG_SQL)
    if len(rows) != 1 or not isinstance(rows[0].get('relations'), dict):
        raise ValueError('Respuesta de catálogo incompleta.')
    catalog = rows[0]
    expected = expected_markers(root)
    checks = {}
    for marker, expected_sha in expected.items():
        candidates = [f for f in catalog.get('functions', []) if f['name'] == marker]
        checks[marker] = {
            'status': ('missing' if not candidates else
                       'body_matches_candidate' if any(
                           f['source_sha256'] == expected_sha for f in candidates)
                       else 'different_definition_requires_review'),
            'overloads_found': len(candidates),
        }
    policies = {}
    for table, sql in POLICY_SQL.items():
        if catalog['relations'].get(table) is True:
            state = read(sql)
            if len(state) != 1:
                raise ValueError('Estado de política incompleto: ' + table)
            policies[table] = state[0]
    return {
        'project_ref': PROJECT, 'read_only': True, 'deploy_ready': False,
        'relations': catalog['relations'], 'policies': policies,
        'rest_hooks': catalog.get('hooks', []), 'function_checks': checks,
        'candidate_order': local_plan(root),
        'limits': [
            'Presence and body hashes do not prove privileges, triggers or complete migration state.',
            'Do not reapply candidates to a partial installation automatically.',
            'Restoration, offline capture and automatic beta admission are excluded.',
            'Auth, Storage and Edge tests with real sessions are still required.',
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local-plan', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = ({'read_only': True, 'deploy_ready': False,
               'candidate_order': local_plan(),
               'expected_markers': expected_markers()}
              if args.local_plan else inspect_remote())
    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(text + '\n')
    print(text)


if __name__ == '__main__':
    main()
