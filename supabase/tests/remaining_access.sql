-- Synthetic M9/M10/M11 permission and accounting checks. No remote writes.
\set ON_ERROR_STOP on
begin;
insert into auth.users values('00000000-0000-0000-0000-000000000081','admin81@example.test',now()),('00000000-0000-0000-0000-000000000082','reception82@example.test',now()),('00000000-0000-0000-0000-000000000083','groomer83@example.test',now()),('00000000-0000-0000-0000-000000000084','outside84@example.test',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select public.create_clinic('Módulos restantes ficticios') as clinic \gset
select set_config('test.rest_clinic',:'clinic',true);
reset role;
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000000082','recepcion'),(:'clinic','00000000-0000-0000-0000-000000000083','estilista');
set local role authenticated;
select public.ops_write(:'clinic','service','{"name":"Servicio ficticio","price":"123.45","commission_kind":"porcentaje","commission_value":"12.50"}',repeat('91',24)) as service \gset
select public.ops_write(:'clinic','service',jsonb_build_object('id',:'service','version',1,'name','Servicio actualizado','price','200.00','commission_kind','bono','commission_value','10.00'),repeat('92',24));
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
select public.ops_write(:'clinic','appointment',jsonb_build_object('patient_name','Animal ficticio','species','Especie ficticia','kind','estetica','professional_id','00000000-0000-0000-0000-000000000083','starts_at',now()+interval '1 day','ends_at',now()+interval '1 day 1 hour'),repeat('93',24)) as appt \gset
select set_config('test.rest_appt',:'appt',true);
do $$begin
 begin perform public.ops_write(current_setting('test.rest_clinic')::uuid,'appointment',jsonb_build_object('patient_name','Otra cita','species','Especie ficticia','kind','estetica','professional_id','00000000-0000-0000-0000-000000000083','starts_at',now()+interval '1 day','ends_at',now()+interval '1 day 1 hour'),repeat('94',24));raise exception 'overlap accepted';exception when others then if sqlerrm<>'appointment_overlap' then raise;end if;end;
 begin perform public.ops_write(current_setting('test.rest_clinic')::uuid,'service','{"name":"Unauthorized","price":"100","commission_kind":"bono","commission_value":"1"}',repeat('95',24));raise exception 'nonadmin service edit accepted';exception when others then if sqlerrm<>'admin_required' then raise;end if;end;
 begin perform public.ops_medical(current_setting('test.rest_clinic')::uuid,'{"allergies":"Ficticio"}',false);raise exception 'unconsented medical data';exception when others then if sqlerrm<>'consent_required' then raise;end if;end;
end$$;
select public.ops_medical(:'clinic','{"allergies":"Dato ficticio privado"}',true);
select public.ops_write(:'clinic','task','{"title":"Pendiente ficticio","assigned_to":"00000000-0000-0000-0000-000000000083","priority":"media"}',repeat('96',24)) as task \gset
select public.ops_write(:'clinic','message','{"category":"turno","body":"Mensaje ficticio"}',repeat('97',24));
select public.ops_write(:'clinic','service_act',jsonb_build_object('service_id',:'service','professional_id','00000000-0000-0000-0000-000000000083','appointment_id',:'appt'),repeat('98',24)) as act \gset
-- Same network operation is exactly-once.
select public.ops_write(:'clinic','service_act',jsonb_build_object('service_id',:'service','professional_id','00000000-0000-0000-0000-000000000083','appointment_id',:'appt'),repeat('98',24));
select public.inv_shift_open(:'clinic','0',repeat('99',24)) as shift \gset
select public.inv_sale_post(:'shift','efectivo',jsonb_build_array(jsonb_build_object('kind','servicio','service_act_id',:'act','quantity','1','price','200.00')),'200.00',repeat('a1',24));
select set_config('test.rest_act',:'act',true);select set_config('test.rest_shift',:'shift',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000083',true);
do $$begin
 if jsonb_array_length(public.ops_medical(current_setting('test.rest_clinic')::uuid))<>0 then raise exception 'groomer saw coworker health data';end if;
 if jsonb_array_length(public.ops_dashboard(current_setting('test.rest_clinic')::uuid)->'tasks')<>1 then raise exception 'assigned task invisible';end if;
 begin perform public.clinic_export(current_setting('test.rest_clinic')::uuid);raise exception 'nonadmin backup allowed';exception when others then if sqlerrm<>'admin_required' then raise;end if;end;
 begin perform public.att_qr(current_setting('test.rest_clinic')::uuid);raise exception 'nonadmin QR allowed';exception when others then if sqlerrm<>'admin_required' then raise;end if;end;
end$$;
select public.ops_write(:'clinic','appointment_state',jsonb_build_object('id',:'appt','version',1,'state','en_atencion'),repeat('a2',24));
select public.ops_write(:'clinic','task_complete',jsonb_build_object('id',:'task'),repeat('a3',24));
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select public.ops_write(:'clinic','appointment',jsonb_build_object('patient_name','Cita futura ficticia','species','No incluir este mes','kind','estetica','professional_id','00000000-0000-0000-0000-000000000083','starts_at',now()+interval '2 months','ends_at',now()+interval '2 months 1 hour'),repeat('b3',24));
select public.att_settings_save(:'clinic','{"latitude":19.4,"longitude":-99.1,"radius_m":100,"max_accuracy_m":50,"privacy_notice":"Aviso ficticio para prueba local de asistencia."}');
select public.att_qr(:'clinic')->>'token' as token \gset
select set_config('test.rest_token',:'token',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
select public.att_consent(:'clinic',1,true);
-- Fetch/scan in same transaction; test server controls expiry rather than sleeping.
select public.att_scan(:'clinic',:'token',19.4,-99.1,5,repeat('a4',24)) as event \gset
select public.att_scan(:'clinic',:'token',19.4,-99.1,5,repeat('a4',24));
select set_config('test.rest_event',:'event',true);
do $$declare parts text[];begin
 if jsonb_array_length(public.att_dashboard(current_setting('test.rest_clinic')::uuid)->'events')<>1 then raise exception 'retry duplicated checado';end if;
 begin perform public.att_scan(current_setting('test.rest_clinic')::uuid,current_setting('test.rest_token'),0,0,5,repeat('a5',24));raise exception 'outside radius allowed';exception when others then if sqlerrm<>'outside_radius' then raise;end if;end;
 begin perform public.att_scan(current_setting('test.rest_clinic')::uuid,current_setting('test.rest_token'),19.4,-99.1,500,repeat('a6',24));raise exception 'bad accuracy allowed';exception when others then if sqlerrm<>'invalid_location' then raise;end if;end;
 parts=string_to_array(current_setting('test.rest_token'),':');parts[5]='1';
 begin perform public.att_scan(current_setting('test.rest_clinic')::uuid,array_to_string(parts,':'),19.4,-99.1,5,repeat('a7',24));raise exception 'expired QR allowed';exception when others then if sqlerrm<>'expired_qr' then raise;end if;end;
 parts=string_to_array(current_setting('test.rest_token'),':');parts[6]=repeat('0',64);
 begin perform public.att_scan(current_setting('test.rest_clinic')::uuid,array_to_string(parts,':'),19.4,-99.1,5,repeat('a8',24));raise exception 'forged QR allowed';exception when others then if sqlerrm<>'invalid_qr' then raise;end if;end;
 begin perform public.att_correct(current_setting('test.rest_clinic')::uuid,current_setting('test.rest_event')::uuid,now(),'Corrección ficticia',repeat('a9',24));raise exception 'nonadmin correction';exception when others then if sqlerrm<>'admin_required' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select public.att_correct(:'clinic',:'event',now()-interval '5 minutes','Corrección ficticia',repeat('b1',24));
select public.ops_write(:'clinic','service',jsonb_build_object('id',:'service','version',2,'name','Otro precio','price','300.00','commission_kind','porcentaje','commission_value','50'),repeat('b2',24));
do $$declare backup jsonb;dash jsonb;begin
 dash=public.ops_dashboard(current_setting('test.rest_clinic')::uuid);
 if (dash->'acts'->0->>'price')::numeric<>200 or (dash->'acts'->0->>'commission')::numeric<>10 or jsonb_array_length(dash->'acts')<>1 then raise exception 'service commission history overwritten or duplicate';end if;
 if (public.inv_shift_snapshot(current_setting('test.rest_shift')::uuid)->'totals'->>'commission')::numeric<>10 then raise exception 'service commission not in shift';end if;
 if jsonb_array_length(public.ops_medical(current_setting('test.rest_clinic')::uuid))<>1 then raise exception 'admin cannot see consented staff profile';end if;
 backup=public.clinic_export(current_setting('test.rest_clinic')::uuid)::jsonb;
 if jsonb_array_length(backup->'tables'->'my_staff_medical_profile')<>0 then raise exception 'backup copied employee medical profile';end if;
 if jsonb_array_length(backup->'tables'->'clinic_members')<>3 then raise exception 'backup leaked other clinic';end if;
 if not (backup->'tables' ? 'attendance_events') then raise exception 'attendance missing in backup';end if;
 if (public.clinic_statistics(current_setting('test.rest_clinic')::uuid)->'sales'->11->>'amount')::numeric<>200 then raise exception 'monthly sales wrong';end if;
 if exists(select 1 from jsonb_array_elements(public.clinic_statistics(current_setting('test.rest_clinic')::uuid)->'species') x where x->>'species'='No incluir este mes') then raise exception 'future appointment counted this month';end if;
 begin update public.attendance_events set direction='salida' where id=current_setting('test.rest_event')::uuid;raise exception 'direct checado edit';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$begin if exists(select 1 from private.vet_operation_receipts where clinic_id=current_setting('test.rest_clinic')::uuid and fingerprint->>'kind'='attendance_scan' and (fingerprint ?| array['lat','lon','latitude','longitude'])) then raise exception 'coordinates retained in retry ledger';end if;end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000084',true);
do $$begin
 begin perform public.ops_dashboard(current_setting('test.rest_clinic')::uuid);raise exception 'outside ops read';exception when others then if sqlerrm<>'access_denied' then raise;end if;end;
 begin perform public.att_dashboard(current_setting('test.rest_clinic')::uuid);raise exception 'outside checado read';exception when others then if sqlerrm<>'access_denied' then raise;end if;end;
end$$;
rollback;
