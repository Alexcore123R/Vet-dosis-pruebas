"""Build a reviewable atomic SQL bundle; does not connect to any server."""
import argparse
import hashlib
import json
from pathlib import Path
import re

from integration_preflight import BETA_FILES, MARKERS, ROOT, expected_markers, local_plan

REQUIRED_RELATIONS = (
    'public.clinic_members', 'public.account_workspaces',
    'public.vet_owners', 'public.vet_patients', 'public.vet_patient_events',
    'public.clinical_cases', 'public.clinical_observations',
    'public.hospital_stays', 'public.hospital_tasks',
    'public.professional_profiles', 'private.professional_profile_versions',
    'public.prescriptions', 'public.prescription_items',
    'public.medication_records', 'public.medication_vials',
    'public.form_documents', 'public.form_templates',
    'public.form_template_versions', 'private.form_artifacts', 'private.rx_artifacts',
    'public.inventario', 'public.lotes_inventario', 'public.inventory_stock_movements',
    'public.staff_display_names', 'public.clinic_appointments',
    'public.payment_transactions', 'public.ai_connections',
    'public.account_identity', 'public.terms_acceptances',
    'private.beta_policy', 'private.permission_policy',
    'private.beta_privacy_notices', 'storage.objects',
)
REQUIRED_FUNCTIONS = (
    'private.clinic_snapshot_before_ai_plans(uuid)',
    'private.permission_effective(uuid,uuid,text,uuid)',
    'private.beta_install_guards()', 'private.require_platform_admin()',
)


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def unwrap(text):
    """Only unwrap the single outer transaction; reject trailing SQL fragments."""
    if (len(re.findall(r'^begin;\s*$', text, re.I | re.M)) != 1
            or len(re.findall(r'^commit;\s*$', text, re.I | re.M)) != 1):
        raise ValueError('Each candidate must contain one outer BEGIN/COMMIT.')
    match = re.fullmatch(
        r'(?P<comments>(?:[ \t]*--[^\n]*\n|[ \t]*\n)*)begin;\s*'
        r'(?P<body>.*?)\ncommit;\s*', text, re.I | re.S)
    if not match:
        raise ValueError('Unexpected content outside candidate transaction.')
    return match['comments'] + match['body'] + '\n'


def bundle_sql(*, commit=False, root=ROOT):
    plan = local_plan(root)
    plan_hash = hashlib.sha256(json.dumps(plan, sort_keys=True).encode()).hexdigest()
    required_relations = ','.join(literal(x) for x in REQUIRED_RELATIONS)
    required_functions = ','.join(literal(x) for x in REQUIRED_FUNCTIONS)
    new_functions = ','.join(literal(x) for x in MARKERS if x != 'public.clinic_statistics')
    guard = f"""-- Fixed test-project rollout candidate. Review before execution.
-- No admissions, grants, verifications, clinical seed data or restoration.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('vetdosis-beta-integration',0));
do $guard$
declare missing text;
begin
 select string_agg(name,', ') into missing from unnest(array[{required_relations}]) name
 where to_regclass(name) is null;
 if missing is not null then raise exception 'integration_missing_relations: %',missing;end if;
 select string_agg(name,', ') into missing from unnest(array[{required_functions}]) name
 where to_regprocedure(name) is null;
 if missing is not null then raise exception 'integration_missing_functions: %',missing;end if;
 perform 1 from private.beta_policy for update;
 if not exists(select 1 from private.beta_policy where not admissions_enabled and not enforcement_enabled)
 or not exists(select 1 from private.permission_policy where not enforcement_enabled and not migration_reviewed)
 then raise exception 'integration_requires_closed_dormant_policies';end if;
 if to_regclass('private.beta_integration_receipts') is not null
 or to_regprocedure('private.permission_patient_read(uuid)') is not null
 or exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname||'.'||p.proname=any(array[{new_functions}]))
 then raise exception 'integration_partial_or_already_applied_requires_review';end if;
end
$guard$;
create table private.beta_integration_receipts(
 plan_sha256 text primary key, candidate_files jsonb not null,
 applied_at timestamptz not null default clock_timestamp()
);
alter table private.beta_integration_receipts enable row level security;
revoke all on private.beta_integration_receipts from public,anon,authenticated,service_role;
create temporary table integration_before_counts on commit drop as
 select (select count(*) from public.vet_patients) as patients,
        (select count(*) from public.vet_owners) as owners,
        (select count(*) from public.medication_records) as medication,
        (select count(*) from private.member_permission_grants) as grants,
        (select count(*) from private.professional_verifications) as verifications;
"""
    body = '\n'.join('-- Candidate: ' + name + '\n' + unwrap(
        (root / 'supabase/proposed' / name).read_text()) for name in BETA_FILES)
    checks = []
    for marker, sha in expected_markers(root).items():
        schema, name = marker.split('.')
        checks.append(
            "if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace "
            f"where n.nspname={literal(schema)} and p.proname={literal(name)} "
            f"and encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')={literal(sha)}) "
            f"then raise exception 'integration_function_mismatch: {marker}';end if;")
    postcheck = """
do $verify$
begin
 if exists(select 1 from integration_before_counts b where
 b.patients<>(select count(*) from public.vet_patients) or
 b.owners<>(select count(*) from public.vet_owners) or
 b.medication<>(select count(*) from public.medication_records) or
 b.grants<>(select count(*) from private.member_permission_grants) or
 b.verifications<>(select count(*) from private.professional_verifications))
 then raise exception 'integration_changed_clinical_or_authority_counts';end if;
 if not exists(select 1 from private.beta_policy where not admissions_enabled and not enforcement_enabled)
 or not exists(select 1 from private.permission_policy where not enforcement_enabled and not migration_reviewed)
 then raise exception 'integration_changed_policy';end if;
""" + '\n'.join(checks) + "\nend\n$verify$;\n"
    receipt = (
        'insert into private.beta_integration_receipts(plan_sha256,candidate_files) values('
        + literal(plan_hash) + ',' + literal(json.dumps(plan)) + '::jsonb);\n')
    return guard + body + postcheck + receipt + ('commit;\n' if commit else 'rollback;\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--commit', action='store_true',
                        help='Generate COMMIT variant; default rehearsal ends in ROLLBACK.')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    args.output.write_text(bundle_sql(commit=args.commit))
    print('Generated atomic bundle:', 'COMMIT' if args.commit else 'ROLLBACK',
          '·', len(BETA_FILES), 'candidates · no remote connection')


if __name__ == '__main__':
    main()
