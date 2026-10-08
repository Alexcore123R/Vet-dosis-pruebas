\set ON_ERROR_STOP on
begin;
insert into auth.users values
('00000000-0000-0000-0000-000000000061','admin61@example.test',now()),
('00000000-0000-0000-0000-000000000062','mvz62@example.test',now()),
('00000000-0000-0000-0000-000000000063','aux63@example.test',now()),
('00000000-0000-0000-0000-000000000064','outside64@example.test',now()),
('00000000-0000-0000-0000-000000000065','mvz65@example.test',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000061',true);
select public.create_clinic('Formas ficticias') as clinic \gset
select public.form_branding_save(:'clinic','{"header":"Membrete inicial sintético","include_logo":false}');
select public.create_clinic('Otra clínica ficticia') as other_clinic \gset
select set_config('test.clinic',:'clinic',true);
select set_config('test.other',:'other_clinic',true);
reset role;
insert into public.clinic_members(clinic_id,user_id,role) values
(:'clinic','00000000-0000-0000-0000-000000000062','mvz'),
(:'clinic','00000000-0000-0000-0000-000000000063','auxiliar'),
(:'clinic','00000000-0000-0000-0000-000000000065','mvz');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select id as base from public.form_template_versions where clinic_id is null and schema->>'type'='clinical_history' \gset
select set_config('test.base',:'base',true);
select set_config('test.schema',(select schema::text from public.form_template_versions where id=:'base'),true);
select public.form_template_save(:'clinic',null,null,:'base',current_setting('test.schema')::jsonb,true,'Revisión sintética',repeat('a',48))->>'id' as version \gset
select set_config('test.version',:'version',true);
select template_id as template from public.form_template_versions where id=:'version' \gset
select set_config('test.template',:'template',true);
select public.create_vet_patient(:'clinic','{"name":"Paciente sintético","species":"Ficticia","sex":"sin especificar"}','{"name":"Tutor sintético"}',repeat('b',48)) as patient \gset
select set_config('test.patient',:'patient',true);
select set_config('test.values',jsonb_build_object('mvz_name','MVZ sintético','mvz_license','FICTICIA','privacy_url','https://example.test/privacy','clinical_date',current_date::text,'reason','Caso sintético','subjective','Observación sintética','weight','4.250','fc','123','observed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,true);
select public.form_document_create(:'clinic',:'patient',:'version',current_setting('test.values')::jsonb,'{}',repeat('c',48))->>'id' as doc \gset
select set_config('test.doc',:'doc',true);
select public.form_document_prepare(:'doc',1,'[]','[[0.2,0.2],[0.7,0.7]]');
select content_hash as hash from public.form_documents where id=:'doc' \gset
set local role service_role;
select public.form_register_pdf(:'doc',2,:'hash',encode(convert_to('%PDF-CLINICAL-SYNTHETIC','UTF8'),'base64'),null,'iVBORw0KGgo=');
set local role authenticated;
select pdf_hash as pdfhash from public.form_documents where id=:'doc' \gset
select public.form_document_finalize(:'doc',2,:'pdfhash');
select public.form_document_finalize(:'doc',2,:'pdfhash');
select id as case_id from public.clinical_cases where document_id=:'doc' \gset
select set_config('test.case',:'case_id',true);
select set_config('test.pdf',:'pdfhash',true);
do $$begin
 if (select count(*) from public.vet_patient_events where form_document_id=current_setting('test.doc')::uuid)<>2 then raise exception 'Missing SOAP/weight or duplicate retry';end if;
 if (select count(*) from public.form_signatures where document_id=current_setting('test.doc')::uuid)<>1 then raise exception 'Clinical document required tutor signature';end if;
 if jsonb_array_length(public.clinical_case_snapshot(current_setting('test.case')::uuid)->'observations')<>2 then raise exception 'Typed observations missing';end if;
end $$;
-- Unassigned clinician and auxiliary cannot read case or linked clinical events.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000065',true);
do $$begin
 if exists(select 1 from public.clinical_cases) or exists(select 1 from public.vet_patient_events where form_document_id is not null) then raise exception 'Unassigned clinical leakage';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000063',true);
do $$begin
 begin perform public.clinical_case_snapshot(current_setting('test.case')::uuid);raise exception 'Aux accessed unassigned case';exception when raise_exception then if sqlerrm<>'clinical_access_denied' then raise;end if;end;
 begin perform public.form_document_finalize(current_setting('test.doc')::uuid,2,current_setting('test.pdf'));raise exception 'Aux finalized clinical record';exception when raise_exception then if sqlerrm<>'responsible_mvz_required' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select public.clinical_authorize(:'case_id','00000000-0000-0000-0000-000000000063','observaciones',to_char((clock_timestamp()+interval '1 hour') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('d',48)) as grant_id \gset
select set_config('test.grant',:'grant_id',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000063',true);
select set_config('test.measurement',jsonb_build_object('kind','fr','value','20.50','unit','rpm','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,true);
select public.clinical_observation_add(:'case_id',current_setting('test.measurement')::jsonb,repeat('e',48));
select public.clinical_observation_add(:'case_id',current_setting('test.measurement')::jsonb,repeat('e',48));
do $$begin
 if jsonb_array_length(public.clinical_case_snapshot(current_setting('test.case')::uuid)->'observations')<>3 then raise exception 'Observation retry duplicated';end if;
 if public.form_read_pdf(current_setting('test.doc')::uuid)->>'hash'<>current_setting('test.pdf') then raise exception 'Original PDF changed';end if;
 begin perform public.clinical_act_add(current_setting('test.case')::uuid,'cirugia','No autorizado',auth.uid(),to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('f',48));raise exception 'Aux performed ungranted surgery';exception when raise_exception then if sqlerrm<>'procedure_authorization_required' then raise;end if;end;
 begin perform public.clinical_authorization_revoke(current_setting('test.grant')::uuid,'No autorizado',repeat('f',48));raise exception 'Aux revoked';exception when raise_exception then if sqlerrm<>'responsible_mvz_required' then raise;end if;end;
 begin perform public.clinical_observation_add(current_setting('test.case')::uuid,jsonb_set(current_setting('test.measurement')::jsonb,'{unit}','"mg"'),repeat('f',48));raise exception 'Wrong unit accepted';exception when raise_exception then if sqlerrm<>'invalid_measurement' then raise;end if;end;
 begin update public.clinical_observations set value=0;raise exception 'Direct modification';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select id as original_weight from public.clinical_observations where case_id=:'case_id' and kind='weight' \gset
select public.clinical_observation_add(:'case_id',jsonb_build_object('kind','weight','value','4.5','unit','kg','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'replaces_id',:'original_weight','correction_reason','Corrección sintética de peso'),repeat('9',48));
do $$begin
 if (select count(*) from public.vet_patient_events where kind='weight')<>1 then raise exception 'Weight curve used corrected and superseded weights';end if;
 if (select payload->>'kg' from public.vet_patient_events where kind='weight')<>'4.5' then raise exception 'Weight correction missing';end if;
 if jsonb_array_length(public.clinical_case_snapshot(current_setting('test.case')::uuid)->'observations')<>4 then raise exception 'Original measurement was overwritten';end if;
 if public.form_read_pdf(current_setting('test.doc')::uuid)->>'hash'<>current_setting('test.pdf') then raise exception 'Correction changed signed PDF';end if;
end $$;
select public.clinical_authorization_revoke(:'grant_id','Fin de supervisión',repeat('f',48));
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000063',true);
do $$begin
 if exists(select 1 from public.clinical_cases) or exists(select 1 from public.vet_patient_events where form_document_id is not null) then raise exception 'Revoked case access persisted';end if;
 begin perform public.clinical_observation_add(current_setting('test.case')::uuid,current_setting('test.measurement')::jsonb,repeat('1',48));raise exception 'Revoked write';exception when raise_exception then if sqlerrm<>'procedure_authorization_required' then raise;end if;end;
end $$;
-- Surgical sheet reuses version engine and separates participants.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select id as surgery_base from public.form_template_versions where clinic_id is null and schema->>'type'='surgical_sheet' \gset
select public.form_template_save(:'clinic',null,null,:'surgery_base',(select schema from public.form_template_versions where id=:'surgery_base'),true,'Prueba sintética',repeat('2',48))->>'id' as surgery_version \gset
select set_config('test.surgery',:'surgery_version',true);
select set_config('test.surgery_values',jsonb_build_object('mvz_name','MVZ sintético','mvz_license','FICTICIA','privacy_url','https://example.test/privacy','clinical_date',current_date::text,'reason','Caso sintético','procedure','Procedimiento sintético','surgeon_id','00000000-0000-0000-0000-000000000062','anesthetist_id','00000000-0000-0000-0000-000000000065','asa','Captura manual','ekg','Interpretación manual')::text,true);
select public.form_document_create(:'clinic',:'patient',:'surgery_version',current_setting('test.surgery_values')::jsonb,'{}',repeat('3',48))->>'id' as surgical_doc \gset
select public.form_document_prepare(:'surgical_doc',1,'[]','[[0.2,0.2],[0.7,0.7]]');
select content_hash as surgery_hash from public.form_documents where id=:'surgical_doc' \gset
set local role service_role;
select public.form_register_pdf(:'surgical_doc',2,:'surgery_hash',encode(convert_to('%PDF-SURGICAL-SYNTHETIC','UTF8'),'base64'),null,'iVBORw0KGgo=');
set local role authenticated;
select public.form_document_finalize(:'surgical_doc',2,(select pdf_hash from public.form_documents where id=:'surgical_doc'));
select id as surgical_case from public.clinical_cases where document_id=:'surgical_doc' \gset
select set_config('test.surgical_case',:'surgical_case',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000065',true);
do $$begin
 if jsonb_array_length(public.clinical_case_snapshot(current_setting('test.surgical_case')::uuid)->'staff')<>3 then raise exception 'Staff roles merged';end if;
end $$;
-- Euthanasia is signed first; later fact and its correction do not change any signed data.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select id as euth_base from public.form_template_versions where clinic_id is null and schema->>'type'='euthanasia' \gset
select public.form_template_save(:'clinic',null,null,:'euth_base',(select schema from public.form_template_versions where id=:'euth_base'),true,'Prueba sintética',repeat('4',48))->>'id' as euth_version \gset
select public.form_document_create(:'clinic',:'patient',:'euth_version','{"mvz_name":"Ficticio","mvz_license":"FICTICIA","signer_name":"Tutor ficticio","signer_id":"FICTICIA","privacy_url":"https://example.test/privacy","procedure":"Ficticio","information":"Ficticio","clinical_reason":"Ficticio","prior_opinion":"Ficticio","method":"Ficticio","body_disposition":"Acuerdo ficticio","cost":"Ficticio"}','{}',repeat('5',48))->>'id' as euth_doc \gset
select set_config('test.euth_doc',:'euth_doc',true);
select public.form_document_prepare(:'euth_doc',1,'[[0.1,0.1],[0.8,0.8]]','[[0.2,0.2],[0.7,0.7]]');
select content_hash as euth_hash from public.form_documents where id=:'euth_doc' \gset
set local role service_role;
select public.form_register_pdf(:'euth_doc',2,:'euth_hash',encode(convert_to('%PDF-EUTH-SYNTHETIC','UTF8'),'base64'),'iVBORw0KGgo=','iVBORw0KGgo=');
set local role authenticated;
select public.form_document_finalize(:'euth_doc',2,(select pdf_hash from public.form_documents where id=:'euth_doc'));
select set_config('test.euth_frozen',(select to_jsonb(d)::text from public.form_documents d where id=:'euth_doc'),true);
select set_config('test.death',jsonb_build_object('result','no_confirmada','method','Método ficticio','findings','Hallazgos ficticios','observed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,true);
select public.clinical_death_add(:'euth_doc',current_setting('test.death')::jsonb,repeat('6',48)) as death_id \gset
select public.clinical_death_add(:'euth_doc',current_setting('test.death')::jsonb,repeat('6',48));
select public.clinical_death_add(:'euth_doc',current_setting('test.death')::jsonb||jsonb_build_object('replaces_id',:'death_id','correction_reason','Corrección sintética'),repeat('7',48));
do $$begin
 if jsonb_array_length(public.clinical_death_list(current_setting('test.euth_doc')::uuid))<>2 then raise exception 'Death retry/correction failure';end if;
 if (select to_jsonb(d) from public.form_documents d where id=current_setting('test.euth_doc')::uuid)<>current_setting('test.euth_frozen')::jsonb then raise exception 'Signed consent changed';end if;
 begin perform public.clinical_death_add(current_setting('test.euth_doc')::uuid,jsonb_set(current_setting('test.death')::jsonb,'{observed_at}','"2000-01-01T00:00:00Z"'),repeat('8',48));raise exception 'Death before consent';exception when raise_exception then if sqlerrm<>'post_consent_time_required' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000063',true);
do $$begin
 begin perform public.clinical_death_add(current_setting('test.euth_doc')::uuid,current_setting('test.death')::jsonb,repeat('8',48));raise exception 'Aux confirmed death';exception when raise_exception then if sqlerrm<>'responsible_mvz_required' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000064',true);
do $$begin
 begin perform public.clinical_cases_list(current_setting('test.other')::uuid,null);raise exception 'Cross clinic case';exception when raise_exception then if sqlerrm<>'clinical_role_required' then raise;end if;end;
 if exists(select 1 from public.clinical_death_records) then raise exception 'Cross clinic death leak';end if;
end $$;
reset role;
do $$begin
 begin update public.clinical_cases set reason='Mutated';raise exception 'Privileged case mutation';exception when raise_exception then if sqlerrm<>'clinical_record_is_immutable_append_correction' then raise;end if;end;
 begin update public.clinical_death_records set result='confirmada';raise exception 'Privileged death mutation';exception when raise_exception then if sqlerrm<>'clinical_record_is_immutable_append_correction' then raise;end if;end;
end $$;
rollback;
