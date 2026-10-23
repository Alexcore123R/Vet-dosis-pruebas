-- Non-destructive de-duplication of manufacturer label transcriptions.
-- Keep all source transcriptions, but select only the canonical regimen in review.
begin;
alter table vetdosis_reference_staging.commercial_label_regimens
  add column if not exists duplicate_of_regimen_key text;
do $$
begin
  if not exists(
    select 1 from pg_constraint where conrelid='vetdosis_reference_staging.commercial_label_regimens'::regclass
    and conname='commercial_label_regimens_duplicate_fkey'
  ) then
    alter table vetdosis_reference_staging.commercial_label_regimens
    add constraint commercial_label_regimens_duplicate_fkey
    foreign key (product_url,duplicate_of_regimen_key)
    references vetdosis_reference_staging.commercial_label_regimens(product_url,regimen_key);
  end if;
end $$;
create or replace view vetdosis_reference_staging.commercial_label_regimens_reconciled
with (security_invoker=true)
as select product_url,regimen_key,formulation_label,species_label,indication_label,
label_dosing_type,label_instruction_summary,amount,amount_unit,per_weight_kg,
frequency_text,administration_route,source_url,source_type,source_checked_on,
review_state,cautions,created_at
from vetdosis_reference_staging.commercial_label_regimens
where duplicate_of_regimen_key is null;
revoke all on vetdosis_reference_staging.commercial_label_regimens_reconciled from public,anon,authenticated;
commit;