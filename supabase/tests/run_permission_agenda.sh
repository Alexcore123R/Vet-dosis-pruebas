#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
container_name="vetdosis-agenda-permissions-$$"
work_dir=$(mktemp -d)
docker run -d --name "$container_name" --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine >/dev/null
trap 'docker rm -f "$container_name" >/dev/null; rm -rf "$work_dir"' EXIT
ready=false
for attempt in {1..30};do
 if docker exec "$container_name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1;then ready=true;break;fi
 sleep 1
done
if [ "$ready" != true ];then echo 'PostgreSQL startup failed';exit 1;fi
for sql_file in supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_doses_m3.sql supabase/adaptations/existing_patients_m4.sql supabase/adaptations/existing_hospital_m5.sql supabase/adaptations/existing_forms_phase1.sql supabase/adaptations/existing_forms_phase2.sql supabase/adaptations/existing_prescribing_m6.sql supabase/adaptations/existing_inventory_m8.sql supabase/adaptations/existing_inventory_workflow_m8.sql supabase/adaptations/existing_operations_m9.sql supabase/adaptations/existing_attendance_m10.sql supabase/adaptations/existing_statistics_m11.sql supabase/adaptations/existing_payment_references.sql supabase/adaptations/existing_subscriptions_m13.sql supabase/adaptations/existing_ai_m12.sql supabase/tests/storage_fixture.sql supabase/adaptations/existing_inventory_photos_m8.sql supabase/adaptations/existing_plan_files_m13.sql supabase/adaptations/existing_ai_plan_export.sql supabase/adaptations/existing_support_m14.sql supabase/adaptations/existing_starter_ai_review.sql supabase/adaptations/existing_team_management.sql supabase/adaptations/existing_appointments_extension.sql supabase/adaptations/existing_membership_history.sql supabase/proposed/09A_beta_foundation.sql supabase/tests/beta_foundation.sql supabase/proposed/09B_beta_gate.sql supabase/proposed/11A_permission_foundation.sql supabase/proposed/13A_permission_patient_registration.sql supabase/proposed/13B_permission_agenda.sql supabase/tests/permission_agenda.sql;do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$sql_file" > "$work_dir/test.log" 2>&1 || { echo "FAILED: $sql_file";cat "$work_dir/test.log";exit 1; }
done
bash supabase/tests/permission_agenda_concurrency.sh "$container_name"
echo 'Agenda permissions passed: explicit read/manage, patient linkage, aggregate isolation, plan wrapper retained and legacy bypass blocked.'
