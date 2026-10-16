-- Synthetic boundary fixture; not a real consent or clinical finding.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
insert into public.form_documents(clinic_id,patient_id,version_id,responsible_id,state,values,branding,snapshot,created_by,accepted_at)
select clinic_id,patient_id,version_id,'00000000-0000-0000-0000-000000000151','signed','{}','{}','{"schema":{"type":"euthanasia"}}','00000000-0000-0000-0000-000000000170',clock_timestamp()-interval '1 minute' from public.form_documents where clinic_id=:'clinic' limit 1 returning id as consent \gset
select set_config('test.consent',:'consent',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.assert_true(not (public.clinical_death_workspace(:'consent')->>'can_record')::boolean,'role granted death permission');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_procedure_set(:'clinic',null,'Synthetic death ascertainment',true) as procedure \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','clinical.death.record',:'procedure',clock_timestamp()+interval '1 day','Synthetic explicit death permission') as death_grant \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','procedure.perform',:'procedure',clock_timestamp()+interval '1 day','Synthetic explicit procedure');reset role;
select set_config('test.data',jsonb_build_object('procedure_id',:'procedure','result','no_confirmada','method','Synthetic method','findings','Synthetic findings','observed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'signer_name','Synthetic actual observer','signature','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]'::jsonb,'confirmed',true)::text,false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.assert_true((public.clinical_death_workspace(:'consent')->>'can_record')::boolean,'explicit authority not available');
select pg_temp.expect_error($q$select public.clinical_death_add(current_setting('test.consent')::uuid,current_setting('test.data')::jsonb-'result',repeat('2211',12))$q$,'required_death_field');
select pg_temp.expect_error($q$select public.clinical_death_add(current_setting('test.consent')::uuid,current_setting('test.data')::jsonb||'{"confirmed":false}',repeat('2211',12))$q$,'own_attestation_required');
select public.clinical_death_add(:'consent',current_setting('test.data')::jsonb,repeat('2211',12)) as record \gset
select pg_temp.assert_true(public.clinical_death_add(:'consent',current_setting('test.data')::jsonb,repeat('2211',12))=:'record','duplicate retry');
select pg_temp.assert_true(public.clinical_death_list(:'consent')->0->>'signer_name'='Synthetic actual observer','actual name absent');
select pg_temp.assert_true(not (public.clinical_death_list(:'consent')->0 ? 'signature'),'raw signature exposed');
select pg_temp.expect_error($q$select public.clinical_death_add(current_setting('test.consent')::uuid,current_setting('test.data')::jsonb||'{"findings":"Changed"}',repeat('2211',12))$q$,'operation_payload_changed');
select public.clinical_death_add(:'consent',current_setting('test.data')::jsonb||jsonb_build_object('replaces_id',:'record','correction_reason','Synthetic correction','findings','Corrected synthetic findings'),repeat('2212',12));
select pg_temp.assert_true(jsonb_array_length(public.clinical_death_list(:'consent'))=2,'correction erased original');

select pg_temp.expect_error($q$select * from private.death_attestations$q$,'permission denied');reset role;
select pg_temp.assert_true((select record_grant=:'death_grant' from private.death_attestations where record_id=:'record'),'grant trace absent');
select pg_temp.assert_true((select snapshot='{"schema":{"type":"euthanasia"}}'::jsonb from public.form_documents where id=:'consent'),'signed consent mutated');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);set role authenticated;
select pg_temp.expect_error($q$select public.clinical_death_workspace(current_setting('test.consent')::uuid)$q$,'signed_euthanasia_access_required');reset role;
set role anon;
select pg_temp.expect_error($q$select public.clinical_death_list(current_setting('test.consent')::uuid)$q$,'permission denied');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'death_grant','Synthetic revoke');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.expect_error($q$select public.clinical_death_add(current_setting('test.consent')::uuid,current_setting('test.data')::jsonb,repeat('2211',12))$q$,'explicit_permission_required');reset role;
