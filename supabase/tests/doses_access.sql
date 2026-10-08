\set ON_ERROR_STOP on
begin;
insert into auth.users values
('00000000-0000-0000-0000-000000000011','admin11@example.test',now()),
('00000000-0000-0000-0000-000000000012','mvz12@example.test',now()),
('00000000-0000-0000-0000-000000000013','mvz13@example.test',now()),
('00000000-0000-0000-0000-000000000014','outside14@example.test',now()),
('00000000-0000-0000-0000-000000000015','recep15@example.test',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000011',true);
select public.create_clinic('M3 ficticia') as clinic \gset
select set_config('test.clinic',:'clinic',true);
reset role;
insert into public.clinic_members(clinic_id,user_id,role) values
(:'clinic','00000000-0000-0000-0000-000000000012','mvz'),
(:'clinic','00000000-0000-0000-0000-000000000013','mvz'),
(:'clinic','00000000-0000-0000-0000-000000000015','recepcion');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000012',true);
select set_config('test.payload','{"id":"fiction","farmaco":"Ficticio","especie":"Ficticia","min":"1","max":"2","unidad_dosis":"mg/kg","via":"ficticia","intervalo":"ficticio","estado":"sin verificar","fuente":null,"presentaciones":[{"id":"p","nombre_comercial":"Ficticia","concentracion":"10","unidad_concentracion":"mg/ml","estado":"sin verificar","fuente":null}],"contraindicaciones":[]}',true);
select public.create_personal_dose(:'clinic',current_setting('test.payload')::jsonb,true) as pending \gset
select public.create_personal_dose(:'clinic',current_setting('test.payload')::jsonb,false) as personal \gset
select set_config('test.pending',:'pending',true);
do $$ begin
 begin
  perform public.review_personal_dose(current_setting('test.pending')::uuid,true);
  raise exception 'MVZ self-approved';
 exception when raise_exception then if sqlerrm<>'admin_required' then raise; end if; end;
 begin
  perform public.create_personal_dose(current_setting('test.clinic')::uuid,jsonb_set(current_setting('test.payload')::jsonb,'{max}','"0"'),false);
  raise exception 'Invalid range accepted';
 exception when raise_exception then if sqlerrm<>'invalid_range' then raise; end if; end;
 begin
  update public.dose_personal_entries set state='approved';
  raise exception 'Direct state update accepted';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000013',true);
do $$ begin if (select count(*) from public.dose_personal_entries)<>0 then raise exception 'Unapproved doses leaked'; end if; end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000011',true);
select public.review_personal_dose(:'pending',true);
do $$ begin
 if (select count(*) from public.audit_log where action='dose_approved')<>1 then raise exception 'Approval not audited'; end if;
 if (select count(*) from public."Fármacos" where "Fármaco"='PRUEBA-SIN-USO-CLINICO')<>1 then raise exception 'General catalog modified'; end if;
 begin
  perform public.review_personal_dose(current_setting('test.pending')::uuid,false);
  raise exception 'Reviewed entry modified';
 exception when raise_exception then if sqlerrm<>'not_pending' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000013',true);
do $$ begin if (select count(*) from public.dose_personal_entries)<>1 then raise exception 'Approved dose not visible'; end if; end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000014',true);
do $$ begin
 if (select count(*) from public.dose_personal_entries)<>0 then raise exception 'Cross-clinic dose disclosure'; end if;
 begin
  perform public.review_personal_dose(current_setting('test.pending')::uuid,true);
  raise exception 'Outsider review accepted';
 exception when raise_exception then if sqlerrm<>'admin_required' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000015',true);
do $$ begin
 if (select count(*) from public.dose_personal_entries)<>0 then raise exception 'Reception clinical access'; end if;
 begin
  perform public.create_personal_dose(current_setting('test.clinic')::uuid,current_setting('test.payload')::jsonb,false);
  raise exception 'Reception dose creation';
 exception when raise_exception then if sqlerrm<>'clinical_role_required' then raise; end if; end;
end $$;
rollback;
select 'M3 RLS tests passed' as result;
