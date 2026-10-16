-- Synthetic template governance only. No patient signatures or clinical data.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('test.clinic',:'clinic',false);
select id as base,schema from public.form_template_versions where clinic_id is null and schema->>'type'='general' order by version desc limit 1 \gset
select set_config('test.base',:'base',false);
select set_config('test.schema',:'schema',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select pg_temp.assert_true(not(public.form_template_permissions(:'clinic')->>'can_edit')::boolean,'admin inherited template edit');
select pg_temp.expect_error($q$select public.form_templates_list(current_setting('test.clinic')::uuid)$q$,'explicit_template_read_required');
select pg_temp.assert_true((select count(*)=0 from public.form_template_versions),'base references leaked without permission');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','form.template.read',null,clock_timestamp()+interval '1 day','Synthetic template read');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','form.template.edit',null,clock_timestamp()+interval '1 day','Synthetic template edit') as edit_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.assert_true((public.form_template_permissions(:'clinic')->>'can_edit')::boolean,'visual stylist cannot edit with permission');
select pg_temp.assert_true(jsonb_array_length(public.form_templates_list(:'clinic'))>0,'reference templates missing');
select pg_temp.assert_true(public.form_template_preview_check(:'clinic',:'schema','{}'),'read-only preview denied');
select public.form_template_save(:'clinic',null,null,:'base',:'schema',false,'Synthetic pending template',repeat('1711',12))->>'template_id' as template \gset
select set_config('test.template',:'template',false);
select public.form_template_save(:'clinic',null,null,:'base',:'schema',false,'Synthetic pending template',repeat('1711',12));
select pg_temp.assert_true((select count(*)=1 from public.form_template_versions where template_id=:'template'),'duplicate template receipt');
select pg_temp.expect_error($q$select public.form_template_save(current_setting('test.clinic')::uuid,current_setting('test.template')::uuid,1,current_setting('test.base')::uuid,current_setting('test.schema')::jsonb,true,'Synthetic forged approval',repeat('1712',12))$q$,'explicit_permission_required');
select pg_temp.expect_error($q$select public.form_template_save(current_setting('test.clinic')::uuid,current_setting('test.template')::uuid,1,current_setting('test.base')::uuid,jsonb_set(current_setting('test.schema')::jsonb,'{fields}','[]'),false,'Synthetic removed locks',repeat('1713',12))$q$,'protected_field');
select pg_temp.expect_error($q$select public.form_branding_save(current_setting('test.clinic')::uuid,'{"header":"Synthetic"}')$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','form.template.read',null,clock_timestamp()+interval '1 day','Synthetic reviewer read');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','form.template.edit',null,clock_timestamp()+interval '1 day','Synthetic reviewer edit');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','form.template.approve',null,clock_timestamp()+interval '1 day','Synthetic reviewer approval') as approve_grant \gset
select pg_temp.expect_error($q$select public.permission_grant(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000170','form.template.approve',null,clock_timestamp()+interval '1 day','Synthetic unverified approval grant')$q$,'verified_professional_required');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','form.branding.manage',null,clock_timestamp()+interval '1 day','Synthetic branding');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.form_template_save(:'clinic',:'template',1,:'base',:'schema',true,'Synthetic reviewed template',repeat('1714',12))->>'id' as approved_version \gset
select pg_temp.assert_true((select approved and source_status='sin verificar' from public.form_template_versions where id=:'approved_version'),'template approval invented clinical verification');
select pg_temp.expect_error($q$select public.form_template_save(current_setting('test.clinic')::uuid,current_setting('test.template')::uuid,1,current_setting('test.base')::uuid,current_setting('test.schema')::jsonb,false,'Synthetic stale edit',repeat('1715',12))$q$,'template_version_conflict');
reset role;
select pg_temp.assert_true((select details->>'approval_grant_id'=:'approve_grant' and details->>'reviewer_id'='00000000-0000-0000-0000-000000000151' and details->>'profile_version_id' is not null from public.audit_log where entity_id=:'approved_version' and action='form_template_version_created'),'approval attribution missing');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.assert_true(not(public.form_template_permissions(:'clinic')->>'can_approve')::boolean,'unverified member approved template');
select pg_temp.expect_error($q$select public.form_template_save(current_setting('test.clinic')::uuid,current_setting('test.template')::uuid,2,current_setting('test.base')::uuid,current_setting('test.schema')::jsonb,true,'Synthetic forged second approval',repeat('1717',12))$q$,'explicit_permission_required');
select pg_temp.expect_error($q$update public.form_template_versions set source_status='verificada' where template_id=current_setting('test.template')::uuid$q$,'permission denied');
select public.form_branding_save(:'clinic','{"header":"Synthetic template letterhead","include_logo":false}');
select pg_temp.assert_true(public.form_branding(:'clinic')->>'header'='Synthetic template letterhead','brand grant ineffective');
-- Any edit creates a new pending version, it cannot retain prior approval.
select public.form_template_save(:'clinic',:'template',2,:'base',:'schema',false,'Synthetic later edit',repeat('1716',12));
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'edit_grant','Synthetic revocation');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.form_template_save(current_setting('test.clinic')::uuid,null,null,current_setting('test.base')::uuid,current_setting('test.schema')::jsonb,false,'Synthetic pending template',repeat('1711',12))$q$,'explicit_permission_required');
reset role;
-- Other clinics and logged-out callers cannot use global bases as an access path.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);set role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.form_template_versions),'other user read template schema');
select pg_temp.expect_error($q$select public.form_templates_list(current_setting('test.clinic')::uuid)$q$,'explicit_template_read_required');
select pg_temp.expect_error($q$select public.form_branding(current_setting('test.clinic')::uuid)$q$,'explicit_template_read_required');
reset role;
set role anon;
select pg_temp.expect_error($q$select public.form_template_permissions(current_setting('test.clinic')::uuid)$q$,'permission denied');
reset role;
