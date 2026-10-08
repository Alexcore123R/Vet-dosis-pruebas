\set ON_ERROR_STOP on
begin;
insert into auth.users values
('00000000-0000-0000-0000-000000000031','admin31@example.test',now()),
('00000000-0000-0000-0000-000000000032','aux32@example.test',now()),
('00000000-0000-0000-0000-000000000033','mvz33@example.test',now()),
('00000000-0000-0000-0000-000000000034','recep34@example.test',now()),
('00000000-0000-0000-0000-000000000035','outside35@example.test',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000031',true);
select public.create_clinic('Hospital ficticio') as clinic \gset
select public.create_clinic('Otra clínica ficticia') as other_clinic \gset
select set_config('test.clinic',:'clinic',true);
select set_config('test.other_clinic',:'other_clinic',true);
select public.create_vet_patient(:'clinic','{"name":"Paciente ficticio","species":"Especie ficticia","sex":"sin especificar"}',null,repeat('a',48)) as patient \gset
select public.create_vet_patient(:'clinic','{"name":"Otro ficticio","species":"Especie ficticia","sex":"sin especificar"}',null,repeat('b',48)) as patient_two \gset
select set_config('test.patient',:'patient',true);
select set_config('test.patient_two',:'patient_two',true);
reset role;
insert into public.clinic_members(clinic_id,user_id,role) values
(:'clinic','00000000-0000-0000-0000-000000000032','auxiliar'),
(:'clinic','00000000-0000-0000-0000-000000000033','mvz'),
(:'clinic','00000000-0000-0000-0000-000000000034','recepcion');
set local role authenticated;
select public.hospital_admit(:'clinic',:'patient','Jaula 1',repeat('c',48)) as stay \gset
select set_config('test.stay',:'stay',true);
do $$ declare id uuid;begin
 id=public.hospital_admit(current_setting('test.clinic')::uuid,current_setting('test.patient')::uuid,'Jaula 1',repeat('c',48));
 if id<>current_setting('test.stay')::uuid or (select count(*) from public.hospital_stays)<>1 then raise exception 'Admission duplicated';end if;
 begin
  perform public.hospital_admit(current_setting('test.clinic')::uuid,current_setting('test.patient_two')::uuid,'  JAULA 1  ',repeat('d',48));raise exception 'Occupied cage allowed';
 exception when unique_violation then null;end;
 begin
  perform public.hospital_admit(current_setting('test.other_clinic')::uuid,current_setting('test.patient')::uuid,'Box',repeat('d',48));raise exception 'Cross-clinic admission allowed';
 exception when raise_exception then if sqlerrm<>'patient_wrong_clinic' then raise;end if;end;
end $$;
select set_config('test.times',jsonb_build_array(to_char((now()+interval '1 hour') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),to_char((now()+interval '2 hours') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,true);
select public.hospital_prescribe(:'clinic',:'stay','medicacion','Caso aritmético ficticio','No usar clínicamente',current_setting('test.times')::jsonb,10,repeat('e',48)) as task \gset
select set_config('test.task',:'task',true);
do $$ begin
 perform public.hospital_prescribe(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,'medicacion','Caso aritmético ficticio','No usar clínicamente',current_setting('test.times')::jsonb,10,repeat('e',48));
 if (select count(*) from public.hospital_tasks)<>2 then raise exception 'Prescription duplicated';end if;
 begin
  perform public.hospital_prescribe(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,'revision','Ficticio','No clínico','["2020-01-01T00:00:00Z"]',10,repeat('f',48));raise exception 'Past order accepted';
 exception when raise_exception then if sqlerrm<>'past_order_time' then raise;end if;end;
 begin
  perform public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.task')::uuid,1,'perform');raise exception 'Early administration accepted';
 exception when raise_exception then if sqlerrm<>'task_not_due' then raise;end if;end;
 begin
  update public.hospital_tasks set performed_by=auth.uid(),state='done';raise exception 'Direct administration forged';
 exception when insufficient_privilege then null;end;
 if jsonb_array_length(public.hospital_snapshot(current_setting('test.clinic')::uuid)->'tasks')<>2 then raise exception 'Snapshot missing tasks';end if;
end $$;
-- Local fixture advances a single task's due time; no external records touched.
reset role;
update public.hospital_tasks set due_at=now()-interval '2 minutes' where id=:'task';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000032',true);
do $$ begin
 begin
  perform public.hospital_prescribe(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,'revision','Ficticio','No clínico',current_setting('test.times')::jsonb,10,repeat('f',48));raise exception 'Auxiliary prescribed';
 exception when raise_exception then if sqlerrm<>'physician_required' then raise;end if;end;
 begin
  perform public.hospital_discharge(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,1,'Ficticio');raise exception 'Auxiliary discharged';
 exception when raise_exception then if sqlerrm<>'physician_required' then raise;end if;end;
end $$;
select public.hospital_task_action(:'clinic',:'task',1,'snooze',5,'Razón ficticia');
do $$ begin
 if (select due_at from public.hospital_tasks where id=current_setting('test.task')::uuid)<>now()-interval '2 minutes' then raise exception 'Snooze changed medical schedule';end if;
 if (select state from public.hospital_tasks where id=current_setting('test.task')::uuid)<>'pending' then raise exception 'Snooze administered';end if;
 begin
  perform public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.task')::uuid,1,'perform');raise exception 'Stale version accepted';
 exception when raise_exception then if sqlerrm<>'version_conflict' then raise;end if;end;
end $$;
select public.hospital_task_action(:'clinic',:'task',2,'snooze',5,'Razón ficticia');
select public.hospital_task_action(:'clinic',:'task',3,'snooze',5,'Razón ficticia');
do $$ begin
 begin
  perform public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.task')::uuid,4,'snooze',5,'Razón ficticia');raise exception 'Unlimited snooze';
 exception when raise_exception then if sqlerrm<>'snooze_limit' then raise;end if;end;
end $$;
select public.hospital_task_action(:'clinic',:'task',4,'perform');
select public.hospital_task_action(:'clinic',:'task',4,'perform');
do $$begin
 if (select performed_by from public.hospital_tasks where id=current_setting('test.task')::uuid)<>auth.uid() or (select performed_at from public.hospital_tasks where id=current_setting('test.task')::uuid)<>now() then raise exception 'Actor or server time incorrect';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000033',true);
do $$begin
 begin
  perform public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.task')::uuid,4,'perform');raise exception 'Another user double-administered';
 exception when raise_exception then if sqlerrm<>'task_not_pending' then raise;end if;end;
end $$;
select public.hospital_discharge(:'clinic',:'stay',1,'Alta ficticia');
do $$begin
 if (select count(*) from public.hospital_tasks where state='cancelled')<>1 or (select count(*) from public.hospital_tasks where state='done')<>1 then raise exception 'Discharge lost administrations or kept pending tasks';end if;
 if jsonb_array_length(public.hospital_snapshot(current_setting('test.clinic')::uuid)->'stays')<>0 then raise exception 'Discharged stay still active';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000031',true);
do $$begin
 if (select count(*) from public.audit_log where action='hospital_task_perform')<>1 then raise exception 'Administration audit duplicated';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000034',true);
do $$begin
 if (select count(*) from public.hospital_stays)<>0 or (select count(*) from public.hospital_tasks)<>0 then raise exception 'Reception disclosure';end if;
 begin
  perform public.hospital_snapshot(current_setting('test.clinic')::uuid);raise exception 'Reception snapshot leaked';
 exception when raise_exception then if sqlerrm<>'clinical_role_required' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000035',true);
do $$begin
 if (select count(*) from public.hospital_stays)<>0 or (select count(*) from public.hospital_tasks)<>0 then raise exception 'Other clinic disclosure';end if;
 begin
  perform public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.task')::uuid,5,'perform');raise exception 'Outsider performed';
 exception when raise_exception then if sqlerrm<>'clinical_role_required' then raise;end if;end;
end $$;
rollback;
select 'M5 permissions, scheduling and confirmation tests passed' as result;
