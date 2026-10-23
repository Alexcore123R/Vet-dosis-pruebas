-- Synthetic fixture only: no bibliographic data and no patient records.
create role staging_reviewer_example nologin;
insert into vetdosis_reference_staging.import_batches
(batch_key,label,origin_filename,original_sha256)
values ('synthetic-review-batch','Synthetic Reference Batch','synthetic.xlsx',repeat('a',64));
insert into vetdosis_reference_staging.raw_intake_rows
(batch_id,row_key,source_filename,source_sheet,source_row,source_title,
 original_payload,row_sha256,review_state)
select id,'sample-row-2','synthetic.xlsx','Page1',2,'Synthetic Source',
 '{"species":null,"unit":null}'::jsonb,repeat('b',64),'pending'
from vetdosis_reference_staging.import_batches where batch_key='synthetic-review-batch';
do $assert$
begin
 if (select count(*) from vetdosis_reference_staging.raw_intake_rows r
 join vetdosis_reference_staging.import_batches b on r.batch_id=b.id
 where b.batch_key='synthetic-review-batch')<>1 then
   raise exception 'Synthetic raw row missing';
 end if;
 if has_table_privilege('anon','vetdosis_reference_staging.raw_intake_rows','SELECT')
    or has_table_privilege('authenticated','vetdosis_reference_staging.raw_intake_rows','SELECT')
    or not (select relrowsecurity from pg_class where oid='vetdosis_reference_staging.raw_intake_rows'::regclass)
 then
   raise exception 'Raw bibliographic data exposed to client';
 end if;
 if exists(select 1 from vetdosis_reference_staging.candidates) then
   raise exception 'Import incorrectly promoted raw values';
 end if;
end$assert$;
