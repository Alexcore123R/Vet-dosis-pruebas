-- Synthetic extension of the medication fixture. No real clinical records.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as case_id,patient_id as patient from public.clinical_cases where title='Synthetic medication case' \gset
select id as product from public.medication_product_versions where product_key='synthetic-permission-liquid' \gset
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-0000-0000-000000000170','synthetic-consultation@example.test',now());
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000000170','auxiliar');
insert into public.prescriptions(clinic_id,case_id,patient_id,responsible_id,created_by)
 values(:'clinic',:'case_id',:'patient','00000000-0000-0000-0000-000000000151','00000000-0000-0000-0000-000000000152') returning id as draft \gset
insert into public.prescription_items(clinic_id,prescription_id,product_version_id,quantity,unit,route,interval_text,duration_text)
 values(:'clinic',:'draft',:'product',1,'ml','Synthetic route','Synthetic interval','Synthetic duration');
select set_config('test.draft',:'draft',false);
select set_config('test.signature','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','clinical.read',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','patient.read',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','prescription.prepare',null,now()+interval '1 day','Synthetic');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);
set role authenticated;
select pg_temp.expect_error($q$select public.rx_consultation_sign(current_setting('test.draft')::uuid,1,'Synthetic signer',current_setting('test.signature')::jsonb,true,repeat('a1',24))$q$,'explicit_permission_required');
select pg_temp.expect_error('select * from private.prescription_consultation_attestations','permission denied');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','prescription.prepare',null,now()+interval '1 day','Synthetic') as signer_grant \gset
-- Admin label is not clinical access.
select pg_temp.expect_error($q$select public.rx_consultation_sign(current_setting('test.draft')::uuid,1,'Synthetic signer',current_setting('test.signature')::jsonb,true,repeat('a1',24))$q$,'case_access_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);
set role authenticated;
select pg_temp.expect_error($q$select public.rx_consultation_sign(current_setting('test.draft')::uuid,1,'Synthetic signer',current_setting('test.signature')::jsonb,false,repeat('a1',24))$q$,'consultation_confirmation_required');
select pg_temp.expect_error($q$select public.rx_consultation_sign(current_setting('test.draft')::uuid,1,'   ',current_setting('test.signature')::jsonb,true,repeat('a1',24))$q$,'consultation_name_required');
select pg_temp.expect_error($q$select public.rx_consultation_sign(current_setting('test.draft')::uuid,1,'Synthetic signer','null',true,repeat('a1',24))$q$,'invalid_signature');
select pg_temp.expect_error($q$select public.rx_consultation_sign(current_setting('test.draft')::uuid,1,'Synthetic signer','[[0.1,0.1],[0.1,0.1]]',true,repeat('a1',24))$q$,'signature_required');
select public.rx_consultation_sign(:'draft',1,'Synthetic consultation signer',current_setting('test.signature')::jsonb,true,repeat('a1',24)) as attestation \gset
select public.rx_consultation_sign(:'draft',1,'Synthetic consultation signer',current_setting('test.signature')::jsonb,true,repeat('a1',24)) as retry \gset
select pg_temp.assert_true(:'attestation'=:'retry','signature retry duplicated');
select pg_temp.expect_error($q$select public.rx_consultation_sign(current_setting('test.draft')::uuid,1,'Different signer name',current_setting('test.signature')::jsonb,true,repeat('a1',24))$q$,'operation_payload_changed');
reset role;
select pg_temp.assert_true((select count(*)=1 from private.prescription_consultation_attestations where prescription_id=:'draft'),'signature duplicated');
select pg_temp.assert_true((select signer_id='00000000-0000-0000-0000-000000000170' and permission_grant_id=:'signer_grant' and signed_at<=clock_timestamp() from private.prescription_consultation_attestations where id=:'attestation'),'signer or server authority lost');
select pg_temp.assert_true(not private.clinical_professional_at(:'clinic','00000000-0000-0000-0000-000000000170',clock_timestamp()),'signature promoted a person to professional');
select pg_temp.assert_true((select state='draft' and snapshot is null and pdf_hash is null from public.prescriptions where id=:'draft'),'signature issued or authorized a prescription');
select pg_temp.assert_true((select private.rx_consultation_for_draft(r,:'attestation')->>'name'='Synthetic consultation signer' from public.prescriptions r where id=:'draft'),'attestation cannot prepare own content');
select set_config('test.attestation',:'attestation',false);
select pg_temp.expect_error($q$update private.prescription_consultation_attestations set signer_name='Replacement' where id=current_setting('test.attestation')::uuid$q$,'append_only_permission_record');
update public.prescriptions set instructions='Changed after signature' where id=:'draft';
select pg_temp.expect_error($q$select private.rx_consultation_for_draft(r,current_setting('test.attestation')::uuid) from public.prescriptions r where id=current_setting('test.draft')::uuid$q$,'consultation_signature_stale');
update public.prescriptions set instructions='',revision=2 where id=:'draft';
select pg_temp.expect_error($q$select private.rx_consultation_for_draft(r,current_setting('test.attestation')::uuid) from public.prescriptions r where id=current_setting('test.draft')::uuid$q$,'consultation_signature_stale');
update public.prescriptions set revision=1,controlled=true where id=:'draft';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);
set role authenticated;
select pg_temp.expect_error($q$select public.rx_consultation_sign(current_setting('test.draft')::uuid,1,'Synthetic signer',current_setting('test.signature')::jsonb,true,repeat('b1',24))$q$,'controlled_responsible_only');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);
set role authenticated;
select public.rx_consultation_sign(:'draft',1,'Synthetic responsible signer',current_setting('test.signature')::jsonb,true,repeat('b1',24));
reset role;
update public.prescriptions set controlled=false where id=:'draft';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);
set role authenticated;
select pg_temp.expect_error($q$select public.rx_consultation_sign(current_setting('test.draft')::uuid,1,'Other clinic signer',current_setting('test.signature')::jsonb,true,repeat('c1',24))$q$,'case_access_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);
set role authenticated;
select public.permission_revoke(:'signer_grant','Synthetic revocation');
reset role;
select pg_temp.expect_error($q$select private.rx_consultation_for_draft(r,current_setting('test.attestation')::uuid) from public.prescriptions r where id=current_setting('test.draft')::uuid$q$,'consultation_signer_authority_changed');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);
set role authenticated;
select pg_temp.expect_error($q$select public.rx_consultation_sign(current_setting('test.draft')::uuid,1,'Synthetic consultation signer',current_setting('test.signature')::jsonb,true,repeat('a1',24))$q$,'explicit_permission_required');
reset role;
select pg_temp.assert_true(not has_function_privilege('anon','public.rx_consultation_sign(uuid,integer,text,jsonb,boolean,text)','execute'),'anon can sign');
select pg_temp.assert_true(not has_table_privilege('authenticated','private.prescription_consultation_attestations','select'),'signature table exposed');
