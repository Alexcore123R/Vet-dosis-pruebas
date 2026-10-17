#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
container_name="vetdosis-integration-bundle-$$"
work_dir=$(mktemp -d)
docker run -d --name "$container_name" --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine >/dev/null
trap 'docker rm -f "$container_name" >/dev/null; rm -rf "$work_dir"' EXIT
ready=false
for attempt in {1..30};do
 if docker exec "$container_name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1;then ready=true;break;fi
 sleep 1
done
if [ "$ready" != true ];then echo 'PostgreSQL startup failed';exit 1;fi
# Only baseline migrations, never interleaved module test scripts.
for sql_file in supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_doses_m3.sql supabase/adaptations/existing_patients_m4.sql supabase/adaptations/existing_hospital_m5.sql supabase/adaptations/existing_forms_phase1.sql supabase/adaptations/existing_forms_phase2.sql supabase/adaptations/existing_prescribing_m6.sql supabase/adaptations/existing_inventory_m8.sql supabase/adaptations/existing_inventory_workflow_m8.sql supabase/adaptations/existing_operations_m9.sql supabase/adaptations/existing_attendance_m10.sql supabase/adaptations/existing_statistics_m11.sql supabase/adaptations/existing_payment_references.sql supabase/adaptations/existing_subscriptions_m13.sql supabase/adaptations/existing_ai_m12.sql supabase/tests/storage_fixture.sql supabase/adaptations/existing_inventory_photos_m8.sql supabase/adaptations/existing_plan_files_m13.sql supabase/adaptations/existing_ai_plan_export.sql supabase/adaptations/existing_support_m14.sql supabase/adaptations/existing_starter_ai_review.sql supabase/adaptations/existing_team_management.sql supabase/adaptations/existing_appointments_extension.sql supabase/adaptations/existing_membership_history.sql supabase/proposed/10_identity.sql supabase/proposed/09A_beta_foundation.sql supabase/proposed/09B_beta_gate.sql supabase/proposed/11A_permission_foundation.sql supabase/proposed/12A_terms_acceptances.sql supabase/proposed/12B_platform_professional_admin.sql supabase/proposed/12C_privacy_binding.sql;do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$sql_file" > "$work_dir/test.log" 2>&1 || { echo "FAILED: $sql_file";tail -c 6000 "$work_dir/test.log";exit 1; }
done
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
create function auth.jwt() returns jsonb language sql stable as $$select '{}'::jsonb$$;
insert into auth.users(id,email,email_confirmed_at) values('90000000-0000-0000-0000-000000000900','integration-synthetic@example.test',now());
insert into public.clinics(id,name,created_by) values('90000000-0000-0000-0000-000000000901','Synthetic integration sentinel','90000000-0000-0000-0000-000000000900');
insert into public.vet_patients(id,clinic_id,name,species,sex,created_by) values('90000000-0000-0000-0000-000000000902','90000000-0000-0000-0000-000000000901','Synthetic untouched patient','synthetic','sin especificar','90000000-0000-0000-0000-000000000900');
SQL
python3 scripts/supabase/integration_bundle.py --output "$work_dir/rehearse.sql"
python3 scripts/supabase/integration_bundle.py --commit --output "$work_dir/apply.sql"
# An error after several candidates must roll back those candidates too.
if python3 - <<'PY' | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/injected.log" 2>&1
import sys
sys.path.insert(0,'scripts/supabase')
from integration_bundle import bundle_sql
print(bundle_sql(commit=True).replace('-- Candidate: 13F_permission_medication.sql',
    'select 1/0; -- synthetic mid-bundle failure\n-- Candidate: 13F_permission_medication.sql'))
PY
then echo 'Injected failure incorrectly accepted';exit 1;fi
rg -q 'division by zero' "$work_dir/injected.log"
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if to_regclass('private.beta_integration_receipts') is not null
 or to_regprocedure('private.permission_patient_read(uuid)') is not null
 then raise exception 'failed_bundle_partially_committed';end if;
end$$;
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/rehearse.sql" > "$work_dir/test.log" 2>&1 || { tail -c 6000 "$work_dir/test.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if to_regclass('private.beta_integration_receipts') is not null or to_regclass('public.clinical_vital_sets') is not null then raise exception 'rehearsal_persisted_changes';end if;
end$$;
create function private.permission_patient_read(uuid) returns boolean language sql as $$select false$$;
SQL
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/apply.sql" > "$work_dir/partial.log" 2>&1;then echo 'Partial installation incorrectly accepted';exit 1;fi
rg -q 'integration_partial_or_already_applied_requires_review' "$work_dir/partial.log"
docker exec "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -c 'drop function private.permission_patient_read(uuid)' >/dev/null
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/apply.sql" > "$work_dir/test.log" 2>&1 || { tail -c 6000 "$work_dir/test.log";exit 1; }
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/apply.sql" > "$work_dir/repeat.log" 2>&1;then echo 'Repeated rollout incorrectly accepted';exit 1;fi
rg -q 'integration_partial_or_already_applied_requires_review' "$work_dir/repeat.log"
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if (select count(*) from private.beta_integration_receipts)<>1 then raise exception 'integration_receipt_missing_or_duplicated';end if;
 if (select name from public.vet_patients where id='90000000-0000-0000-0000-000000000902')<>'Synthetic untouched patient' then raise exception 'integration_changed_existing_patient';end if;
 if to_regclass('private.backup_restore_staging') is not null then raise exception 'integration_enabled_restoration';end if;
 if to_regprocedure('public.app_module_workspace(uuid)') is null or to_regprocedure('public.clinical_vitals_add(uuid,jsonb,text)') is null then raise exception 'integration_api_incomplete';end if;
end$$;
SQL
echo 'Atomic 23-candidate rollout passed: rollback, partial/repeat rejection, unchanged counts and final function fingerprints.'
