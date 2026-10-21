\set ON_ERROR_STOP on
-- Synthetic staging tests: no patient data, no real reference range.
begin;
create role vetdosis_ref_reader nologin;
do $$
declare
  source_id uuid;
  batch_id uuid;
  candidate_id uuid;
  failed boolean;
begin
  if has_schema_privilege('vetdosis_ref_reader','vetdosis_reference_staging','USAGE') then
    raise exception 'Staging schema exposed to client role';
  end if;
  if has_table_privilege('vetdosis_ref_reader','vetdosis_reference_staging.candidates','SELECT') then
    raise exception 'Staging candidates readable by client role';
  end if;
  if exists (
    select 1 from pg_policies
    where schemaname='vetdosis_reference_staging'
  ) then raise exception 'Unexpected row policy on private staging'; end if;

  insert into vetdosis_reference_staging.sources (source_key,title,source_type)
  values('synthetic-book','Synthetic book for tests','book')
  returning id into source_id;
  insert into vetdosis_reference_staging.import_batches (batch_key,label)
  values('synthetic-lot','Synthetic isolated batch')
  returning id into batch_id;

  insert into vetdosis_reference_staging.candidates (
    batch_id,source_id,row_key,category,species_label,parameter_label,source_locator,
    raw_value,value_kind,value_min,value_max,unit_original
  ) values (
    batch_id,source_id,'r1','physiology','Synthetic species','Synthetic parameter','p. 1',
    '0.0–1.0','interval',0,1,'test-unit'
  ) returning id into candidate_id;
  if not exists (
    select 1 from vetdosis_reference_staging.candidates
    where id=candidate_id and review_state='pending' and value_min=0
  ) then raise exception 'Candidate not stored as pending, preserving zero'; end if;

  failed := false;
  begin
    insert into vetdosis_reference_staging.candidates (
      batch_id,source_id,row_key,category,species_label,parameter_label,source_locator,
      raw_value,value_kind,value_min,value_max
    ) values(batch_id,source_id,'r1','laboratory','Synthetic species','Parameter','p. 2','1','point',1,null);
  exception when unique_violation then failed:=true; end;
  if not failed then raise exception 'Same batch/row duplicated'; end if;

  failed := false;
  begin
    insert into vetdosis_reference_staging.candidates (
      batch_id,source_id,row_key,category,species_label,parameter_label,source_locator,
      raw_value,value_kind,value_min,value_max
    ) values(batch_id,source_id,'r2','laboratory','Synthetic species','Parameter','p. 2','5-1','interval',5,1);
  exception when check_violation then failed:=true; end;
  if not failed then raise exception 'Inverted interval accepted'; end if;

  failed := false;
  begin
    insert into vetdosis_reference_staging.candidates (
      batch_id,source_id,row_key,category,species_label,parameter_label,source_locator,
      raw_value,value_kind,value_min,review_state
    ) values(batch_id,source_id,'r3','laboratory','Synthetic species','Parameter','p. 3','2','point',2,'approved');
  exception when check_violation then failed:=true; end;
  if not failed then raise exception 'Unreviewed reference allowed as approved'; end if;

  insert into vetdosis_reference_staging.candidates (
    batch_id,source_id,row_key,category,species_label,parameter_label,source_locator,
    raw_value,value_kind,review_state
  ) values(batch_id,source_id,'r4','laboratory','Synthetic species','Unparsed unit','image p. 4',
    'unknown symbol','unparsed','conflict');
end $$;
rollback;
select 'Reference staging tests passed (rolled back)' as result;
