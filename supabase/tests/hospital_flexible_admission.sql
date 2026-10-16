-- Synthetic administrative cases only. No clinical findings or measurements required.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000130','flex-admin@example.test',now()),
 ('00000000-0000-0000-0000-000000000131','flex-manager@example.test',now()),
 ('00000000-0000-0000-0000-000000000132','flex-reader@example.test',now()),
 ('00000000-0000-0000-0000-000000000133','flex-other@example.test',now());
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000130',false);
select public.create_clinic('Synthetic flexible hospital A') as clinic \gset
select set_config('test.clinic',:'clinic',false);
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000000131','auxiliar'),(:'clinic','00000000-0000-0000-0000-000000000132','mvz');
insert into public.vet_patients(clinic_id,name,species,sex,created_by) values(:'clinic','Synthetic first','synthetic','sin especificar',auth.uid()) returning id as p1 \gset
insert into public.vet_patients(clinic_id,name,species,sex,created_by) values(:'clinic','Synthetic second','synthetic','sin especificar',auth.uid()) returning id as p2 \gset
select set_config('test.patient',:'p1',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_admit(current_setting('test.clinic')::uuid,current_setting('test.patient')::uuid,null,repeat('a',48))$q$,'explicit_permission_required');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000131','hospital.manage',null,now()+interval '1 day','Synthetic management') as manage \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000131','patient.read',null,now()+interval '1 day','Synthetic patient read');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000132','hospital.read',null,now()+interval '1 day','Synthetic reader');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000131',false);
set role authenticated;
select public.hospital_admit(:'clinic',:'p1','',repeat('b',48)) as stay1 \gset
select public.hospital_admit(:'clinic',:'p2',null,repeat('c',48)) as stay2 \gset
select public.hospital_admit(:'clinic',:'p1','',repeat('b',48)) as retry \gset
select pg_temp.assert_true(:'stay1'=:'retry','admission retry duplicated');
select set_config('test.stay',:'stay1',false);
select pg_temp.assert_true(not exists(select 1 from public.hospital_stays where clinic_id=current_setting('test.clinic')::uuid),'manage implicitly granted read');
select public.hospital_cage_set(:'clinic',:'stay1',1,'Box A','',repeat('d',48));
select public.hospital_cage_set(:'clinic',:'stay1',1,'Box A','',repeat('d',48));
select pg_temp.expect_error($q$select public.hospital_cage_set(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,1,null,'',repeat('e',48))$q$,'hospital_version_conflict');
select pg_temp.expect_error(format('select public.hospital_cage_set(%L,%L,1,'' box a '','''',repeat(''f'',48))',:'clinic',:'stay2'),'hospital_cage_occupied');
select public.hospital_cage_set(:'clinic',:'stay1',2,'   ',null,repeat('1',48));
select public.hospital_cage_set(:'clinic',:'stay2',1,'Box A','Synthetic move',repeat('2',48));
reset role;
select pg_temp.assert_true((select cage is null and version=3 from public.hospital_stays where id=:'stay1'),'missing cage not represented as NULL or wrong version');
select pg_temp.assert_true(not exists(select 1 from public.clinical_observations where clinic_id=:'clinic'),'admission invented observations');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000132',false);
set role authenticated;
select pg_temp.assert_true((public.hospital_snapshot(:'clinic')->'capabilities'->>'optional_cage')::boolean,'optional cage not advertised');
select pg_temp.assert_true(jsonb_array_length(public.hospital_cage_history(:'clinic',:'stay1'))=3,'history missing or duplicated');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.hospital_cage_history(:'clinic',:'stay1')) a where a->>'actor_id'<>'00000000-0000-0000-0000-000000000131' or a->>'at' is null),'history lost actor/time');
select pg_temp.expect_error($q$select public.hospital_cage_set(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,3,null,'',repeat('3',48))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000130',false);
set role authenticated;
select public.permission_revoke(:'manage','Synthetic revocation');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000131',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_cage_set(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,1,'Box A','',repeat('d',48))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000133',false);
select public.create_clinic('Synthetic flexible hospital B');
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_cage_history(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid)$q$,'explicit_permission_required');
reset role;
set role anon;
select pg_temp.expect_error('select public.hospital_cage_history(null,null)','permission denied');
reset role;
select pg_temp.assert_true(not(select migration_reviewed or enforcement_enabled from private.permission_policy),'global cut activated');
select pg_temp.assert_true(not(select admissions_enabled or enforcement_enabled from private.beta_policy),'beta opened');
