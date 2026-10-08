\set ON_ERROR_STOP on
begin;
insert into auth.users values
('00000000-0000-0000-0000-000000000021','admin21@example.test',now()),
('00000000-0000-0000-0000-000000000022','aux22@example.test',now()),
('00000000-0000-0000-0000-000000000023','recep23@example.test',now()),
('00000000-0000-0000-0000-000000000024','outside24@example.test',now()),
('00000000-0000-0000-0000-000000000025','stylist25@example.test',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000021',true);
select public.create_clinic('M4 ficticia') as clinic \gset
select public.create_clinic('M4 otra') as other_clinic \gset
select set_config('test.clinic',:'clinic',true);
select set_config('test.other_clinic',:'other_clinic',true);
reset role;
insert into public.clinic_members(clinic_id,user_id,role) values
(:'clinic','00000000-0000-0000-0000-000000000022','auxiliar'),
(:'clinic','00000000-0000-0000-0000-000000000023','recepcion'),
(:'clinic','00000000-0000-0000-0000-000000000025','estilista');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000021',true);
select set_config('test.patient_json','{"name":"Paciente ficticio","species":"Especie ficticia","sex":"sin especificar"}',true);
select public.create_vet_patient(:'clinic',current_setting('test.patient_json')::jsonb,'{"name":"Tutor ficticio","phone":"+520000000000"}',repeat('a',48)) as patient \gset
select set_config('test.patient',:'patient',true);
select public.add_vet_patient_event(:'clinic',:'patient','soap','{"date":"2026-01-01","reason":"Caso ficticio","species_template":"Ficticia","subjective":"Observación ficticia","objective":"","assessment":"","plan":""}',repeat('b',48)) as soap \gset
select public.add_vet_patient_event(:'clinic',:'patient','consent','{"date":"2026-01-01","procedure":"Caso ficticio","text":"Texto de prueba, no modelo legal","signer":"Tutor ficticio","accepted":true,"signature":[[0.1,0.2],[0.4,0.5],null]}',repeat('c',48)) as consent \gset
do $$ declare duplicate uuid;begin
 duplicate=public.create_vet_patient(current_setting('test.clinic')::uuid,current_setting('test.patient_json')::jsonb,'{"name":"Tutor ficticio","phone":"+520000000000"}',repeat('a',48));
 if duplicate<>current_setting('test.patient')::uuid or (select count(*) from public.vet_patients)<>1 or (select count(*) from public.vet_owners)<>1 then raise exception 'Creation receipt failed';end if;
 begin
  perform public.create_vet_patient(current_setting('test.clinic')::uuid,'{"name":"Changed","species":"Ficticia","sex":"hembra"}',null,repeat('a',48));
  raise exception 'Operation reused with different payload';
 exception when raise_exception then if sqlerrm<>'operation_payload_changed' then raise;end if;end;
 begin
  perform public.add_vet_patient_event(current_setting('test.other_clinic')::uuid,current_setting('test.patient')::uuid,'weight','{"date":"2026-01-01","kg":"1"}',repeat('d',48));
  raise exception 'Patient attached to other clinic';
 exception when raise_exception then if sqlerrm<>'patient_wrong_clinic' then raise;end if;end;
 begin
  perform public.add_vet_patient_event(current_setting('test.clinic')::uuid,current_setting('test.patient')::uuid,'weight','{"date":"2026-01-01","kg":"0"}',repeat('d',48));
  raise exception 'Zero weight accepted';
 exception when raise_exception then if sqlerrm<>'invalid_weight' then raise;end if;end;
 begin
  perform public.add_vet_patient_event(current_setting('test.clinic')::uuid,current_setting('test.patient')::uuid,'consent','{"date":"2026-01-01","procedure":"Caso","text":"Texto de prueba","signer":"Tutor","accepted":true,"signature":[[0.1,0.2],[0.1,0.2]]}',repeat('d',48));
  raise exception 'Point counted as signature';
 exception when raise_exception then if sqlerrm<>'consent_not_signed' then raise;end if;end;
 begin
  update public.vet_patient_events set payload='{}';raise exception 'Clinical history overwritten';
 exception when insufficient_privilege then null;end;
 if (select count(*) from public.audit_log where action='patient_event_created')<>2 then raise exception 'Clinical audit missing';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000022',true);
do $$ begin
 if (select count(*) from public.vet_owners)<>0 then raise exception 'Auxiliary read owner data';end if;
 if (select count(*) from public.vet_patient_events)<>1 then raise exception 'Auxiliary consent disclosure or missing SOAP';end if;
 begin
  perform public.add_vet_patient_event(current_setting('test.clinic')::uuid,current_setting('test.patient')::uuid,'soap','{}',repeat('d',48));
  raise exception 'Auxiliary wrote physician note';
 exception when raise_exception then if sqlerrm<>'clinical_role_required' then raise;end if;end;
end $$;
select public.add_vet_patient_event(:'clinic',:'patient','weight','{"date":"2026-01-01","kg":"1.5"}',repeat('d',48)) as weight \gset
select public.add_vet_patient_event(:'clinic',:'patient','weight','{"date":"2026-01-01","kg":"1.5"}',repeat('d',48)) as duplicate_weight \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000023',true);
do $$ begin
 if (select count(*) from public.vet_owners)<>1 or (select count(*) from public.vet_patients)<>1 then raise exception 'Reception demographics missing';end if;
 if (select count(*) from public.vet_patient_events)<>0 then raise exception 'Reception clinical disclosure';end if;
 begin
  perform public.add_vet_patient_event(current_setting('test.clinic')::uuid,current_setting('test.patient')::uuid,'weight','{"date":"2026-01-01","kg":"2"}',repeat('e',48));raise exception 'Reception wrote clinical data';
 exception when raise_exception then if sqlerrm<>'clinical_role_required' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000025',true);
do $$ begin
 if (select count(*) from public.vet_patients)<>1 or (select count(*) from public.vet_owners)<>0 or (select count(*) from public.vet_patient_events)<>0 then raise exception 'Stylist scope failed';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000024',true);
do $$ begin
 if (select count(*) from public.vet_patients)<>0 or (select count(*) from public.vet_owners)<>0 or (select count(*) from public.vet_patient_events)<>0 then raise exception 'Cross-clinic disclosure';end if;
 begin
  perform public.create_vet_patient(current_setting('test.clinic')::uuid,current_setting('test.patient_json')::jsonb,null,repeat('f',48));raise exception 'Outsider created patient';
 exception when raise_exception then if sqlerrm<>'patient_role_required' then raise;end if;end;
end $$;
reset role;
do $$begin
 if (select count(*) from public.vet_patient_events where kind='weight')<>1 then raise exception 'Repeated weight duplicated';end if;
 if not exists(select 1 from public."Fármacos" where "Fármaco"='PRUEBA-SIN-USO-CLINICO') then raise exception 'Existing catalog lost';end if;
end $$;
rollback;
select 'M4 RLS and idempotency tests passed' as result;
