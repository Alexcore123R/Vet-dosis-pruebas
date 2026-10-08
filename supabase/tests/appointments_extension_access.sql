-- Local synthetic agenda/history regression. No clinical doses.
begin;
insert into auth.users values
('00000000-0000-0000-0000-000000000951','agenda-admin@example.test',now()),
('00000000-0000-0000-0000-000000000952','agenda-aux@example.test',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000951',true);
select public.create_clinic('Agenda prueba local') as c \gset
select public.create_clinic('Otra clínica agenda') as other \gset
select set_config('test.agenda_c',:'c',true);
select public.ops_write(:'c','display_name','{"name":"MVZ ficticio","user_id":"00000000-0000-0000-0000-000000000952"}',repeat('ed',24));
reset role;
insert into public.clinic_members(clinic_id,user_id,role) values(:'c','00000000-0000-0000-0000-000000000952','auxiliar');
insert into public.vet_patients(id,clinic_id,name,species,sex,created_by) values
('00000000-0000-0000-0000-000000000951',:'c','Paciente agenda ficticio','Especie de prueba','sin especificar','00000000-0000-0000-0000-000000000951'),
('00000000-0000-0000-0000-000000000952',:'other','Paciente de otra clínica','Especie de prueba','sin especificar','00000000-0000-0000-0000-000000000951');
set local role authenticated;
do $$declare result jsonb;begin
 result=public.ops_patient_search(current_setting('test.agenda_c')::uuid,'agenda');
 if jsonb_array_length(result)<>1 or (result->0) ? 'owner_id' or (result->0) ? 'events' then raise exception 'search_disclosure';end if;
 begin
 perform public.ops_write(current_setting('test.agenda_c')::uuid,'appointment',jsonb_build_object('patient_id','00000000-0000-0000-0000-000000000952','kind','consulta','professional_id',auth.uid(),'starts_at',now()+interval '1 day','ends_at',now()+interval '1 day 1 hour'),repeat('f1',24));
 raise exception 'foreign_patient_accepted';
 exception when others then if sqlerrm<>'patient_wrong_clinic' then raise;end if;end;
end $$;
select public.ops_write(:'c','appointment',jsonb_build_object('patient_id','00000000-0000-0000-0000-000000000951','patient_name','Incorrecto','species','Incorrecta','kind','consulta','professional_id','00000000-0000-0000-0000-000000000952','starts_at',now()+interval '1 day','ends_at',now()+interval '1 day 1 hour'),repeat('f2',24)) as appt \gset
select set_config('test.agenda_appt',:'appt',true);
select public.ops_write(:'c','appointment',jsonb_build_object('patient_name','Otra cita','species','Prueba','kind','consulta','professional_id','00000000-0000-0000-0000-000000000952','starts_at',now()+interval '2 days','ends_at',now()+interval '2 days 1 hour'),repeat('f3',24));
select public.ops_write(:'c','service','{"name":"Servicio agenda ficticio","price":"10.00","commission_kind":"bono","commission_value":"0.00"}',repeat('f4',24)) as service \gset
select set_config('test.agenda_service',:'service',true);
select public.ops_write(:'c','service_act',jsonb_build_object('service_id',:'service','professional_id','00000000-0000-0000-0000-000000000952','appointment_id',:'appt'),repeat('f5',24));
do $$begin
 begin
 perform public.ops_write(current_setting('test.agenda_c')::uuid,'appointment_reschedule',jsonb_build_object('id',current_setting('test.agenda_appt'),'version',1,'reason','Cambio local','starts_at',now()+interval '2 days','ends_at',now()+interval '2 days 1 hour'),repeat('f6',24));raise exception 'reschedule_overlap_accepted';
 exception when others then if sqlerrm<>'appointment_overlap' then raise;end if;end;
 begin
 perform public.ops_write(current_setting('test.agenda_c')::uuid,'appointment_state',jsonb_build_object('id',current_setting('test.agenda_appt'),'version',1,'state','cancelado'),repeat('f7',24));raise exception 'cancel_missing_reason';
 exception when others then if sqlerrm<>'appointment_reason_required' then raise;end if;end;
end $$;
select public.ops_write(:'c','appointment_reschedule',jsonb_build_object('id',:'appt','version',1,'reason','Cambio solicitado','starts_at',now()+interval '3 days','ends_at',now()+interval '3 days 1 hour'),repeat('f8',24));
select public.ops_write(:'c','appointment_reschedule',jsonb_build_object('id',:'appt','version',1,'reason','Cambio solicitado','starts_at',now()+interval '3 days','ends_at',now()+interval '3 days 1 hour'),repeat('f8',24));
do $$begin
 begin
 perform public.ops_write(current_setting('test.agenda_c')::uuid,'appointment_state',jsonb_build_object('id',current_setting('test.agenda_appt'),'version',1,'state','cancelado','reason','Motivo válido'),repeat('f9',24));raise exception 'stale_version_accepted';
 exception when others then if sqlerrm<>'version_conflict' then raise;end if;end;
end $$;
select public.ops_write(:'c','appointment_state',jsonb_build_object('id',:'appt','version',2,'state','cancelado','reason','Cancelación solicitada'),repeat('fa',24));
reset role;
do $$declare a public.clinic_appointments;begin
 select * into a from public.clinic_appointments where id=current_setting('test.agenda_appt')::uuid;
 if a.patient_id<>'00000000-0000-0000-0000-000000000951' or a.patient_name<>'Paciente agenda ficticio' or a.species<>'Especie de prueba' or a.version<>3 then raise exception 'patient_snapshot_or_version_wrong';end if;
 if (select count(*) from public.audit_log where action='appointment_rescheduled' and entity_id=a.id::text)<>1 then raise exception 'reschedule_retry_not_idempotent';end if;
end $$;
insert into public.attendance_events(clinic_id,user_id,direction,server_at,distance_m,accuracy_m,qr_bucket) values(:'c','00000000-0000-0000-0000-000000000952','entrada',now(),0,1,1);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000952',true);
select public.ops_write(:'c','display_name','{"name":"Auxiliar ficticio"}',repeat('ee',24));
select public.ops_medical(:'c','{"emergency":"Contacto ficticio"}',true);
do $$begin
 begin perform public.ops_patient_search((select id from public.clinics where name='Otra clínica agenda'),'Paciente');raise exception 'foreign_search_allowed';
 exception when others then if sqlerrm<>'access_denied' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000951',true);
select public.remove_clinic_member(:'c','00000000-0000-0000-0000-000000000952');
do $$begin
 if jsonb_array_length(public.ops_dashboard(current_setting('test.agenda_c')::uuid)->'people')<>2 then raise exception 'staff_names_lost';end if;
 if jsonb_array_length((public.clinic_export(current_setting('test.agenda_c')::uuid)::jsonb)->'tables'->'staff_display_names')<>2 then raise exception 'staff_names_missing_from_backup';end if;
 if jsonb_array_length(public.ops_dashboard(current_setting('test.agenda_c')::uuid)->'appointments')<>2 then raise exception 'history_lost';end if;
 begin perform public.ops_write(current_setting('test.agenda_c')::uuid,'service_act',jsonb_build_object('service_id',current_setting('test.agenda_service'),'professional_id','00000000-0000-0000-0000-000000000952'),repeat('fb',24));raise exception 'removed_professional_accepted';
 exception when others then if sqlerrm<>'invalid_professional' then raise;end if;end;
end $$;
reset role;
do $$begin
 if not exists(select 1 from public.clinic_service_acts where clinic_id=current_setting('test.agenda_c')::uuid) or
 not exists(select 1 from public.attendance_events where clinic_id=current_setting('test.agenda_c')::uuid) or
 not exists(select 1 from public.staff_medical_profiles where clinic_id=current_setting('test.agenda_c')::uuid) then raise exception 'historic_data_deleted';end if;
end $$;
rollback;
