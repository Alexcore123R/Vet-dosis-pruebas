#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
container_name="vetdosis-permissions-test-$$"
docker run -d --name "$container_name" --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine >/dev/null
trap 'docker rm -f "$container_name" >/dev/null' EXIT
ready=false
for attempt in {1..30}; do
  if docker exec "$container_name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [ "$ready" != true ]; then
  docker logs "$container_name"
  exit 1
fi
if [ "${1:-fresh}" = ai_plans ]; then
  sql_files=(supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_doses_m3.sql supabase/adaptations/existing_patients_m4.sql supabase/adaptations/existing_hospital_m5.sql supabase/adaptations/existing_forms_phase1.sql supabase/adaptations/existing_forms_phase2.sql supabase/adaptations/existing_prescribing_m6.sql supabase/adaptations/existing_inventory_m8.sql supabase/adaptations/existing_inventory_workflow_m8.sql supabase/adaptations/existing_operations_m9.sql supabase/adaptations/existing_attendance_m10.sql supabase/adaptations/existing_statistics_m11.sql supabase/adaptations/existing_payment_references.sql supabase/adaptations/existing_subscriptions_m13.sql supabase/adaptations/existing_ai_m12.sql supabase/tests/storage_fixture.sql supabase/adaptations/existing_inventory_photos_m8.sql supabase/adaptations/existing_plan_files_m13.sql supabase/adaptations/existing_ai_plan_export.sql supabase/adaptations/existing_support_m14.sql supabase/adaptations/existing_starter_ai_review.sql supabase/adaptations/existing_team_management.sql supabase/adaptations/existing_appointments_extension.sql supabase/adaptations/existing_membership_history.sql supabase/tests/appointments_extension_access.sql supabase/tests/ai_plans_access.sql supabase/proposed/14B_support_attachment_validation.sql supabase/tests/support_access.sql supabase/tests/starter_ai_access.sql)
elif [ "${1:-fresh}" = remaining ]; then
  sql_files=(supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_doses_m3.sql supabase/adaptations/existing_patients_m4.sql supabase/adaptations/existing_hospital_m5.sql supabase/adaptations/existing_forms_phase1.sql supabase/adaptations/existing_forms_phase2.sql supabase/adaptations/existing_prescribing_m6.sql supabase/adaptations/existing_inventory_m8.sql supabase/adaptations/existing_inventory_workflow_m8.sql supabase/adaptations/existing_operations_m9.sql supabase/adaptations/existing_attendance_m10.sql supabase/adaptations/existing_statistics_m11.sql supabase/adaptations/existing_payment_references.sql supabase/tests/prescribing_access.sql supabase/tests/inventory_access.sql supabase/tests/inventory_workflow_access.sql supabase/tests/remaining_access.sql supabase/tests/payment_access.sql)
elif [ "${1:-fresh}" = inventory ]; then
  sql_files=(supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_patients_m4.sql supabase/adaptations/existing_hospital_m5.sql supabase/adaptations/existing_forms_phase1.sql supabase/adaptations/existing_forms_phase2.sql supabase/adaptations/existing_prescribing_m6.sql supabase/adaptations/existing_inventory_m8.sql supabase/adaptations/existing_inventory_workflow_m8.sql supabase/tests/prescribing_access.sql supabase/tests/inventory_access.sql supabase/tests/inventory_workflow_access.sql supabase/tests/storage_fixture.sql supabase/adaptations/existing_inventory_photos_m8.sql supabase/tests/inventory_photos_access.sql)
elif [ "${1:-fresh}" = prescribing ]; then
  sql_files=(supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_patients_m4.sql supabase/adaptations/existing_hospital_m5.sql supabase/adaptations/existing_forms_phase1.sql supabase/adaptations/existing_forms_phase2.sql supabase/adaptations/existing_prescribing_m6.sql supabase/tests/prescribing_access.sql)
elif [ "${1:-fresh}" = clinical ]; then
  sql_files=(supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_patients_m4.sql supabase/adaptations/existing_forms_phase1.sql supabase/adaptations/existing_forms_phase2.sql supabase/tests/forms_access.sql supabase/tests/clinical_access.sql)
elif [ "${1:-fresh}" = forms ]; then
  sql_files=(supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_patients_m4.sql supabase/adaptations/existing_forms_phase1.sql supabase/tests/forms_access.sql)
elif [ "${1:-fresh}" = hospital ]; then
  sql_files=(supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_doses_m3.sql supabase/adaptations/existing_patients_m4.sql supabase/adaptations/existing_hospital_m5.sql supabase/tests/hospital_access.sql)
elif [ "${1:-fresh}" = patients ]; then
  sql_files=(supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_doses_m3.sql supabase/adaptations/existing_patients_m4.sql supabase/tests/patients_access.sql)
elif [ "${1:-fresh}" = doses ]; then
  sql_files=(supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_doses_m3.sql supabase/tests/doses_access.sql)
elif [ "${1:-fresh}" = existing ]; then
  sql_files=(supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_team_management.sql supabase/tests/existing_access.sql supabase/tests/team_access.sql)
else
  sql_files=(supabase/tests/bootstrap.sql supabase/migrations/202610060001_clinics_auth.sql supabase/tests/access.sql)
fi
for sql_file in "${sql_files[@]}"; do
  if [ "$sql_file" = supabase/tests/prescribing_access.sql ] || [ "$sql_file" = supabase/tests/remaining_access.sql ]; then
    sed 's/^rollback;$/commit;/' "$sql_file" | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1
  else
    docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$sql_file"
  fi
done

if [ "${1:-fresh}" = hospital ]; then
  bash supabase/tests/hospital_concurrency.sh "$container_name"
fi

if [ "${1:-fresh}" = prescribing ]; then
  bash supabase/tests/prescribing_concurrency.sh "$container_name"
fi

if [ "${1:-fresh}" = inventory ]; then
  bash supabase/tests/inventory_concurrency.sh "$container_name"
fi

if [ "${1:-fresh}" = remaining ];then
  bash supabase/tests/remaining_concurrency.sh "$container_name"
  bash supabase/tests/inventory_concurrency.sh "$container_name"
fi
