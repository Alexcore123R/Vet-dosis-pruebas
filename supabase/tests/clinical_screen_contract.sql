-- Synthetic access/metadata only; no clinical recommendations.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as case_id,patient_id,document_id from public.clinical_cases where title='Synthetic medication case' \gset
select set_config('test.clinic',:'clinic',false);select set_config('test.case',:'case_id',false);
select count(*) as cases_before from public.clinical_cases \gset
select count(*) as observations_before from public.clinical_observations \gset
-- A signed linked document is separate from the case's legacy original.
insert into public.form_documents(clinic_id,patient_id,version_id,responsible_id,state,revision,values,branding,snapshot,created_by,accepted_at)
 select clinic_id,patient_id,version_id,responsible_id,'signed',1,values,branding,snapshot||jsonb_build_object('attention_assignment',jsonb_build_object('case_id',:'case_id','actor_id','00000000-0000-0000-0000-000000000152')),created_by,clock_timestamp() from public.form_documents where version_id=(select id from public.form_template_versions where reason='Synthetic separately attributed clinical template') returning id as linked \gset
select set_config('test.linked',:'linked',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select pg_temp.assert_true(public.clinical_workspace(:'clinic')->>'can_read'='false','visual admin obtained clinical read');
select pg_temp.assert_true(public.clinical_workspace(:'clinic')->'members'='[]'::jsonb,'visual admin obtained staff choices');
select pg_temp.expect_error($q$select public.clinical_workspace(current_setting('test.clinic')::uuid,current_setting('test.case')::uuid)$q$,'clinical_access_denied');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.assert_true((public.clinical_workspace(:'clinic',:'case_id')->'actions'->>'bind')::boolean,'responsible cannot configure existing scope');
select pg_temp.assert_true((public.clinical_workspace(:'clinic',:'case_id')->'actions'->>'authorize')::boolean,'responsible cannot authorize');
select pg_temp.assert_true(not(public.clinical_workspace(:'clinic',:'case_id')->'actions'->>'observe')::boolean,'responsible gained implicit own procedure authority');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.clinical_workspace(:'clinic',:'case_id')->'documents') d where d->>'id'=:'linked' and d->>'state'='signed' and d->>'is_original'='false'),'separate signed linked document missing');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.clinical_workspace(:'clinic',:'case_id')->'documents') d where d->>'id'=:'document_id'),'unsigned original offered as signed PDF');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',false);set role authenticated;
select pg_temp.assert_true(public.clinical_workspace(:'clinic',:'case_id')->'act_scopes' ? 'evaluacion','explicit evaluation omitted');
select pg_temp.assert_true(not(public.clinical_workspace(:'clinic',:'case_id')->'actions'->>'authorize')::boolean,'case performer gained authorization permission');
select pg_temp.assert_true(public.clinical_workspace(:'clinic',:'case_id')->'members'='[]'::jsonb,'performer obtained management choices');
reset role;
-- A nonprofessional visual stylist is read-only until explicit observation grants.
select id as binding_procedure from private.procedure_types where clinic_id=:'clinic' and active order by id limit 1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.assert_true(public.clinical_workspace(:'clinic',:'case_id')->'act_scopes'='[]'::jsonb,'job label obtained procedures');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_procedure_set(:'clinic',null,'Synthetic screen measurements',true) as observation_type \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','procedure.perform',:'observation_type',clock_timestamp()+interval '1 day','Synthetic measurement permission') as observation_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.clinical_scope_bind(:'case_id','observaciones',:'observation_type',false,'Synthetic observation policy','Synthetic screen binding');
select public.clinical_authorize(:'case_id','00000000-0000-0000-0000-000000000170','observaciones',to_char(clock_timestamp()+interval '1 day','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('2011',12));reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.assert_true((public.clinical_workspace(:'clinic',:'case_id')->'actions'->>'observe')::boolean,'visual stylist explicit observation grant ignored');
select pg_temp.assert_true(not(public.clinical_workspace(:'clinic',:'case_id')->'actions'->>'correct')::boolean,'observer gained responsible correction');
select pg_temp.assert_true(not(public.clinical_workspace(:'clinic',:'case_id')->'actions'->>'bind')::boolean,'observer gained procedure mapping');
select pg_temp.expect_error($q$select public.clinical_observation_add(current_setting('test.case')::uuid,jsonb_build_object('kind','fc','unit','lpm','value','1','performed_by','00000000-0000-0000-0000-000000000151','observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),repeat('2012',12))$q$,'own_act_only');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'observation_grant','Synthetic immediate revocation');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.assert_true(not(public.clinical_workspace(:'clinic',:'case_id')->'actions'->>'observe')::boolean,'revoked action remained enabled');reset role;
-- Lost professional habilitation hides authorizing actions; no role fallback.
begin;
insert into private.professional_revocations(verification_id,revoked_by,reason) select id,'00000000-0000-0000-0000-000000000154','Synthetic screen revoke' from private.professional_verifications where user_id='00000000-0000-0000-0000-000000000151' and not exists(select 1 from private.professional_revocations r where r.verification_id=private.professional_verifications.id);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.assert_true(not(public.clinical_workspace(:'clinic',:'case_id')->'actions'->>'authorize')::boolean,'revoked professional still authorized');rollback;
set role anon;select pg_temp.expect_error($q$select public.clinical_workspace(current_setting('test.clinic')::uuid)$q$,'permission denied');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);set role authenticated;
select pg_temp.expect_error($q$select public.clinical_workspace(current_setting('test.clinic')::uuid,current_setting('test.case')::uuid)$q$,'clinical_access_denied');reset role;
select pg_temp.assert_true((select count(*)=:cases_before from public.clinical_cases),'contract published case');
select pg_temp.assert_true((select count(*)=:observations_before from public.clinical_observations),'contract inserted measurement');
