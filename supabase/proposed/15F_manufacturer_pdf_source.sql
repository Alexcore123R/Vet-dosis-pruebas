-- Add exact source type for user-supplied manufacturer PDFs; additive records and unchanged public API.
begin;
alter table vetdosis_reference_staging.commercial_label_regimens
 drop constraint commercial_label_regimens_source_type_check;
alter table vetdosis_reference_staging.commercial_label_regimens
 add constraint commercial_label_regimens_source_type_check
 check(source_type in ('manufacturer_page','plm_technical_page','manufacturer_document'));
commit;