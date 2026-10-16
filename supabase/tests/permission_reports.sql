-- Synthetic ledger only; no official or clinical source is asserted.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('test.clinic',:'clinic',false);
-- One validated application, one historical review without a grant, and one
-- pending application. All values below are synthetic test fixtures only.
insert into public.medication_product_versions(product_key,version,name,presentation,unit,classification,quantified_prescription,source,source_status)
 values('synthetic-report-only',1,'Synthetic report product','Synthetic only','ml','grupo_i',true,'{"reference":"SYNTHETIC TEST ONLY; NOT CLINICAL OR LEGAL"}','verificada') returning id as report_product \gset
insert into public.medication_records(id,clinic_id,case_id,patient_id,product_version_id,quantity,unit,route,procedure,performed_by,reported_by,responsible_id,observed_at,lot,content_hash)
 select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,clinic_id,id,patient_id,:'report_product',1,'ml','Synthetic route','cuidados',responsible_id,responsible_id,responsible_id,'2021-01-02T00:00:00Z','SYNTHETIC ONLY',repeat(n::text,10)
 from public.clinical_cases cross join generate_series(181,183) n where title='Synthetic medication case';
insert into public.controlled_drug_reviews(clinic_id,record_id,content_hash,decision,reason,validated_by,permission_grant_id)
 select clinic_id,id,content_hash,'validada','Synthetic only',responsible_id,case when id::text like '%181' then (select g.id from private.member_permission_grants g where g.clinic_id=medication_records.clinic_id and g.user_id=responsible_id and g.code='medication.validate' order by g.granted_at desc limit 1) end
 from public.medication_records where id in ('00000000-0000-0000-0000-000000000181','00000000-0000-0000-0000-000000000182');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select pg_temp.assert_true(public.rx_reports(:'clinic')='[]','admin inherited report access');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','report.prepare',null,clock_timestamp()+interval '1 day','Synthetic controlled ledger') as prep \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','report.prepare',null,clock_timestamp()+interval '1 day','Synthetic unverified preparer');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.assert_true(not(public.rx_report_permissions(:'clinic')->>'can_prepare')::boolean,'unverified preparer allowed controlled report');
select pg_temp.expect_error($q$select public.rx_report_create(current_setting('test.clinic')::uuid,'2020-01-01T00:00:00Z','2020-02-01T00:00:00Z',false,repeat('1610',12))$q$,'verified_professional_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
reset role;
select pv.version,pv.name,pv.license from public.professional_profiles p join lateral (select * from private.professional_profile_versions where profile_id=p.id order by version desc limit 1) pv on true where p.clinic_id=:'clinic' and p.user_id='00000000-0000-0000-0000-000000000151' \gset
set role authenticated;
select public.rx_profile_save(:'clinic',:version,:'name',:'license','','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',repeat('1619',12));
select public.rx_report_create(:'clinic','2021-01-01T00:00:00Z','2021-02-01T00:00:00Z',false,repeat('1618',12))->>'id' as content_report \gset
select pg_temp.assert_true(jsonb_array_length(public.rx_pdf_snapshot('report',:'content_report')->'snapshot'->'entries')=1,'unvalidated or legacy review entered report');
select pg_temp.assert_true(jsonb_array_length(public.rx_pdf_snapshot('report',:'content_report')->'snapshot'->'pending_ids')=2,'pending records disappeared');
select public.rx_report_create(:'clinic','2020-01-01T00:00:00Z','2020-02-01T00:00:00Z',false,repeat('1611',12))->>'id' as report \gset
select set_config('test.report',:'report',false);
select pg_temp.assert_true(not (public.rx_reports(:'clinic')->0 ? 'snapshot'),'list leaked signature snapshot');
select pg_temp.expect_error($q$select snapshot from public.controlled_drug_reports$q$,'permission denied');
select pg_temp.expect_error($q$select * from public.controlled_drug_report_items$q$,'permission denied');
select pg_temp.expect_error($q$select public.rx_report_export(current_setting('test.report')::uuid)$q$,'issued_report_access_required');
select pg_temp.expect_error($q$select public.rx_report_create(current_setting('test.clinic')::uuid,'2020-01-01T00:00:00Z','2020-02-01T00:00:00Z',true,repeat('1612',12))$q$,'reference_reports_only');
select pg_temp.assert_true(position('basado en Anexo 5, no oficial' in public.rx_pdf_snapshot('report',:'report')->'snapshot'->'schema'->>'title')>0,'report official claim');
select pg_temp.expect_error($q$select public.rx_report_finalize(current_setting('test.report')::uuid,'wrong')$q$,'explicit_permission_required');
reset role;
-- Registration is service-only and rechecks frozen authority after render.
select encode(sha256(convert_to('%PDF-SYNTHETIC-REPORT','UTF8')),'hex') as pdf_hash \gset
select content_hash from public.controlled_drug_reports where id=:'report' \gset
set role service_role;
select public.rx_pdf_register('report',:'report',1,:'content_hash',encode(convert_to('%PDF-SYNTHETIC-REPORT','UTF8'),'base64'),encode(decode('89504e470d0a1a0a','hex'),'base64'));
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','report.issue',null,clock_timestamp()+interval '1 day','Synthetic ledger issue') as issue \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_report_finalize(:'report',:'pdf_hash');
select public.rx_report_finalize(:'report',:'pdf_hash');
select pg_temp.assert_true(not (public.rx_report_export(:'report')->'snapshot' ? 'mvz_signature'),'export leaked signature');
reset role;
select pg_temp.assert_true((select count(*)=1 from public.audit_log where entity_id=:'report' and action='controlled_report_signed'),'duplicate report emission');
-- Pending report cannot survive a changed prepare grant, even with fresh grants.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_report_create(:'clinic','2020-02-01T00:00:00Z','2020-03-01T00:00:00Z',false,repeat('1613',12))->>'id' as pending \gset
select set_config('test.pending',:'pending',false);
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'prep','Synthetic revocation');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','report.prepare',null,clock_timestamp()+interval '1 day','Synthetic replacement') as replacement \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_pdf_snapshot('report',current_setting('test.pending')::uuid)$q$,'report_authority_changed');
select pg_temp.expect_error($q$select public.rx_report_create(current_setting('test.clinic')::uuid,'2020-02-01T00:00:00Z','2020-03-01T00:00:00Z',false,repeat('1613',12))$q$,'report_authority_changed');
-- Issued historical artifact stays readable through current read authority.
select pg_temp.assert_true(public.rx_pdf_read('report',:'report')->>'hash'=:'pdf_hash','issued artifact was rewritten/lost');
reset role;
set role service_role;
select pg_temp.expect_error($q$select public.rx_pdf_register('report',current_setting('test.pending')::uuid,1,'x','x','x')$q$,'report_authority_changed');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_report_export(current_setting('test.report')::uuid)$q$,'issued_report_access_required');
reset role;
set role anon;
select pg_temp.expect_error($q$select public.rx_reports(current_setting('test.clinic')::uuid)$q$,'permission denied');
select pg_temp.expect_error($q$select public.rx_pdf_register('report',current_setting('test.pending')::uuid,1,'x','x','x')$q$,'permission denied');
reset role;

begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_report_create(:'clinic','2020-05-01T00:00:00Z','2020-06-01T00:00:00Z',false,repeat('1617',12))->>'id' as profile_report \gset
select set_config('test.profile_report',:'profile_report',true);
reset role;
select pv.version,pv.name,pv.license from public.professional_profiles p join lateral (select * from private.professional_profile_versions where profile_id=p.id order by version desc limit 1) pv on true where p.clinic_id=:'clinic' and p.user_id='00000000-0000-0000-0000-000000000151' \gset
set role authenticated;
select public.rx_profile_save(:'clinic',:version,:'name',:'license','','[[0.2,0.3],[0.4,0.6],[0.8,0.7],null]',repeat('1616',12));
select pg_temp.expect_error($q$select public.rx_pdf_snapshot('report',current_setting('test.profile_report')::uuid)$q$,'report_profile_changed');
select pg_temp.assert_true(public.rx_pdf_read('report',:'report')->>'hash'=:'pdf_hash','issued PDF changed after signature update');
rollback;
begin;
select id as read_grant from private.member_permission_grants where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000151' and code='clinical.read' order by granted_at desc limit 1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'read_grant','Synthetic read revocation');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.assert_true(public.rx_reports(:'clinic')='[]','revoked clinical reader retained list');
select pg_temp.expect_error($q$select public.rx_report_export(current_setting('test.report')::uuid)$q$,'issued_report_access_required');
rollback;

reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_reports(current_setting('test.clinic')::uuid)$q$,'current_member_required');
select pg_temp.expect_error($q$select public.rx_report_export(current_setting('test.report')::uuid)$q$,'issued_report_access_required');
reset role;
