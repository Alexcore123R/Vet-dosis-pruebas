#!/usr/bin/env bash
set -euo pipefail
# Applies the full prerequisite chain, then tests clinic operations permissions.
# The unrelated backups/exports test is omitted because it requires a separate
# preventive_evidence fixture not used by this permission contract.
cd "$(dirname "$0")/../.."
container_name="vetdosis-workspace-manage-$$"
work_dir=$(mktemp -d)
docker run -d --name "$container_name" --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine >/dev/null
trap 'docker rm -f "$container_name" >/dev/null; rm -rf "$work_dir"' EXIT
ready=false
for attempt in {1..30};do
 if docker exec "$container_name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1;then ready=true;break;fi
 sleep 1
done
if [ "$ready" != true ];then echo 'PostgreSQL startup failed';exit 1;fi
# Exercise both upgrade paths: existing categories and a skipped 13B3.
category_migration=()
if [ "${SKIP_SERVICE_CATEGORIES:-0}" != "1" ]; then
 category_migration=(supabase/proposed/13B3_service_categories.sql)
fi
for sql_file in supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_doses_m3.sql supabase/adaptations/existing_patients_m4.sql supabase/adaptations/existing_hospital_m5.sql supabase/adaptations/existing_forms_phase1.sql supabase/adaptations/existing_forms_phase2.sql supabase/adaptations/existing_prescribing_m6.sql supabase/adaptations/existing_inventory_m8.sql supabase/adaptations/existing_inventory_workflow_m8.sql supabase/adaptations/existing_operations_m9.sql supabase/adaptations/existing_attendance_m10.sql supabase/adaptations/existing_statistics_m11.sql supabase/adaptations/existing_payment_references.sql supabase/adaptations/existing_subscriptions_m13.sql supabase/adaptations/existing_ai_m12.sql supabase/tests/storage_fixture.sql supabase/adaptations/existing_inventory_photos_m8.sql supabase/adaptations/existing_plan_files_m13.sql supabase/adaptations/existing_ai_plan_export.sql supabase/adaptations/existing_support_m14.sql supabase/adaptations/existing_starter_ai_review.sql supabase/adaptations/existing_team_management.sql supabase/adaptations/existing_appointments_extension.sql supabase/adaptations/existing_membership_history.sql supabase/proposed/09A_beta_foundation.sql supabase/tests/beta_foundation.sql supabase/proposed/09B_beta_gate.sql supabase/proposed/11A_permission_foundation.sql supabase/proposed/13A_permission_patient_registration.sql supabase/proposed/13B_permission_agenda.sql supabase/proposed/13C_permission_clinical.sql supabase/proposed/13D_hospital_flexible_admission.sql supabase/proposed/13E_permission_hospital_reviews.sql supabase/proposed/13F_permission_medication.sql supabase/tests/permission_medication.sql supabase/proposed/13G_permission_hospital_resolution.sql supabase/proposed/13H1_consultation_attestation.sql supabase/tests/consultation_attestation.sql supabase/proposed/13H2_prescription_individual.sql supabase/tests/prescription_individual.sql supabase/proposed/13H3_standing_prescriptions.sql supabase/tests/prescription_standing.sql supabase/proposed/13I1_permission_dispensing.sql supabase/tests/permission_dispensing.sql supabase/proposed/13I2_permission_inventory_cash.sql supabase/tests/permission_inventory_cash.sql supabase/proposed/13J1_permission_reports.sql supabase/tests/permission_reports.sql supabase/proposed/13J2_permission_form_templates.sql supabase/tests/permission_form_templates.sql supabase/proposed/13J3_form_document_drafts.sql supabase/tests/permission_form_document_drafts.sql supabase/proposed/13J4_form_individual_workflow.sql supabase/tests/form_individual_workflow.sql supabase/proposed/13K_clinical_screen_contract.sql supabase/tests/clinical_screen_contract.sql supabase/proposed/13L_independent_clinical_cases.sql supabase/tests/independent_clinical_cases.sql supabase/proposed/13M_death_attestation.sql supabase/tests/death_attestation.sql supabase/proposed/13N_module_navigation_dashboard.sql supabase/tests/module_navigation_dashboard.sql supabase/proposed/13O_permission_backups_exports.sql supabase/proposed/13P_workspace_management_cutover.sql supabase/tests/workspace_management_cutover.sql supabase/proposed/13B1_permission_clinic_operations.sql supabase/proposed/13B2_restore_module_navigation.sql "${category_migration[@]}" supabase/proposed/13B4_service_subcategories.sql supabase/proposed/13B4_service_subcategories.sql supabase/tests/permission_clinic_operations.sql "$@";do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$sql_file" > "$work_dir/test.log" 2>&1 || { echo "FAILED: $sql_file";tail -c 8000 "$work_dir/test.log";exit 1; }
done
echo 'Workspace management and clinic operations permissions passed.'
