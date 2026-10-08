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
reset role;
-- Published synthetic sources are only test fixtures, never application clinical data.
insert into public.medication_product_versions(id,product_key,version,name,presentation,unit,classification,quantified_prescription,source,source_status) values
 ('10000000-0000-0000-0000-000000000001','SYNTHETIC-ORDINARY',1,'Producto ficticio ordinario','Presentación ficticia','ml','no_controlado',false,'{"reference":"SYNTHETIC-NOT-CLINICAL"}','verificada'),
 ('10000000-0000-0000-0000-000000000002','SYNTHETIC-CONTROLLED',1,'Producto ficticio controlado','Presentación ficticia','ml','grupo_i',true,'{"reference":"SYNTHETIC-NOT-CLINICAL"}','verificada'),
 ('10000000-0000-0000-0000-000000000003','SYNTHETIC-UNKNOWN',1,'Producto ficticio sin clasificar','Presentación ficticia','ml','desconocida',null,'{}','sin verificar');
insert into public.rx_regulatory_versions(kind,version,source,source_status,required_fields) values
 ('controlled_prescription',1,'{"reference":"SYNTHETIC-NOT-LEGAL"}','verificada',array['folio','patient','owner','mvz_name','mvz_license','signature']),
 ('controlled_report',1,'{"reference":"SYNTHETIC-NOT-LEGAL"}','verificada',array['patient','product','lot','quantity','unit','observed_at','performed_by','validated_by']);
set local role service_role;
select public.rx_professional_authorize(:'clinic','00000000-0000-0000-0000-000000000062',true,clock_timestamp()+interval '1 day','SYNTHETIC-REVIEW');
select public.rx_professional_authorize(:'clinic','00000000-0000-0000-0000-000000000065',true,clock_timestamp()+interval '1 day','SYNTHETIC-REVIEW');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select public.rx_profile_save(:'clinic',0,'MVZ ficticio','FICTICIA','REGISTRO-FICTICIO','[[0.2,0.2],[0.7,0.7]]',repeat('d',48));
select id as profile from public.professional_profiles where user_id=auth.uid() \gset
select set_config('test.profile',:'profile',true);
select public.rx_profiles(:'clinic');
select public.clinical_authorize(:'case_id','00000000-0000-0000-0000-000000000063','cuidados',to_char((clock_timestamp()+interval '1 hour') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('e',48));
select public.rx_delegate(:'profile','00000000-0000-0000-0000-000000000063',:'case_id','{"use_data":true,"use_signature":true,"prepare_ordinary":true,"issue_ordinary":true,"dispense_ordinary":true}',to_char((clock_timestamp()+interval '1 hour') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('f',48)) as delegation \gset
select set_config('test.delegation',:'delegation',true);
select public.rx_vial_open(:'clinic','10000000-0000-0000-0000-000000000002','LOTE-SINTETICO','10',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),null,null,repeat('1',48)) as vial \gset
select set_config('test.vial',:'vial',true);
select set_config('test.ordinary_items','[{"product_version_id":"10000000-0000-0000-0000-000000000001","quantity":"0.50","unit":"ml","route":"Vía ficticia","interval":"Intervalo ficticio","duration":"Duración ficticia"}]',true);
select set_config('test.controlled_items','[{"product_version_id":"10000000-0000-0000-0000-000000000002","quantity":"0.50","unit":"ml","route":"Vía ficticia","interval":"Intervalo ficticio","duration":"Duración ficticia"}]',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000063',true);
select public.rx_profile_save(:'clinic',0,'Auxiliar ficticio','','','[[0.3,0.3],[0.8,0.8]]',repeat('2',48));
select public.rx_profiles(:'clinic');
do $$begin
 begin perform public.rx_professional_authorize(current_setting('test.clinic')::uuid,auth.uid(),true,clock_timestamp()+interval '1 day','Unauthorized');raise exception 'Self professional authorization';exception when insufficient_privilege then null;end;
 begin perform public.rx_create(current_setting('test.case')::uuid,current_setting('test.controlled_items')::jsonb,'FICTICIO','',repeat('3',48));raise exception 'Aux prepared controlled with shared signature';exception when raise_exception then if sqlerrm<>'delegated_restricted_product_denied' then raise;end if;end;
 begin perform public.rx_create(current_setting('test.case')::uuid,jsonb_set(current_setting('test.ordinary_items')::jsonb,'{0,product_version_id}','"10000000-0000-0000-0000-000000000003"'),'','',repeat('3',48));raise exception 'Aux prepared unknown product';exception when raise_exception then if sqlerrm<>'delegated_restricted_product_denied' then raise;end if;end;
end $$;
select public.rx_create(:'case_id',current_setting('test.ordinary_items')::jsonb,'','Cuidados ficticios',repeat('3',48))->>'id' as ordinary_rx \gset
select set_config('test.rx',:'ordinary_rx',true);
select public.rx_save(:'ordinary_rx',1,current_setting('test.ordinary_items')::jsonb,'','Cuidados ficticios editados');
select public.rx_prepare(:'ordinary_rx',2,:'profile',true,null);
select content_hash as rx_hash from public.prescriptions where id=:'ordinary_rx' \gset
set local role service_role;
select public.rx_pdf_register('prescription',:'ordinary_rx',3,:'rx_hash',encode(convert_to('%PDF-RX-SYNTHETIC','UTF8'),'base64'),'iVBORw0KGgo=');
set local role authenticated;
select pdf_hash as rx_pdfhash from public.prescriptions where id=:'ordinary_rx' \gset
select public.rx_finalize(:'ordinary_rx',3,:'rx_pdfhash');
select public.rx_finalize(:'ordinary_rx',3,:'rx_pdfhash');
select set_config('test.rx_pdf',:'rx_pdfhash',true);
select set_config('test.application',jsonb_build_object('product_version_id','10000000-0000-0000-0000-000000000002','quantity','1.25','unit','ml','route','Vía ficticia','procedure','cuidados','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'vial_id',current_setting('test.vial'))::text,true);
select public.rx_medication_report(:'case_id',current_setting('test.application')::jsonb,repeat('4',48)) as application \gset
select set_config('test.application_id',:'application',true);
select public.rx_medication_report(:'case_id',current_setting('test.application')::jsonb,repeat('4',48));
select content_hash as medication_hash from public.medication_records where id=:'application' \gset
select set_config('test.medication_hash',:'medication_hash',true);
do $$begin
 if (select initial_volume from public.medication_vials where id=current_setting('test.vial')::uuid)<>10 then raise exception 'Initial volume mutated';end if;
 if (public.rx_vials(current_setting('test.clinic')::uuid)->0->>'balance')::numeric<>8.75 then raise exception 'Pending application duplicate or no subtraction';end if;
 begin perform public.rx_medication_review(current_setting('test.application_id')::uuid,current_setting('test.medication_hash'),'validada','No autorizado',repeat('5',48));raise exception 'Aux validated';exception when raise_exception then if sqlerrm<>'responsible_professional_only' then raise;end if;end;
 begin perform public.rx_report_create(current_setting('test.clinic')::uuid,'2026-01-01T00:00:00Z','2026-01-02T00:00:00Z',true,repeat('5',48));raise exception 'Aux official report';exception when raise_exception then if sqlerrm<>'responsible_professional_only' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select public.rx_report_create(:'clinic',to_char(current_date,'YYYY-MM-DD')||'T00:00:00Z',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),false,repeat('5',48))->>'id' as pending_report \gset
select set_config('test.pending_report',:'pending_report',true);
do $$begin
 if (select complete from public.controlled_drug_reports where id=current_setting('test.pending_report')::uuid) then raise exception 'Pending report falsely complete';end if;
 if (select count(*) from public.controlled_drug_report_items where report_id=current_setting('test.pending_report')::uuid)<>0 then raise exception 'Unvalidated report item';end if;
end $$;
select public.rx_medication_review(:'application',:'medication_hash','validada','Revisión sintética',repeat('6',48));
do $$begin
 if (public.rx_vials(current_setting('test.clinic')::uuid)->0->>'balance')::numeric<>8.75 then raise exception 'Validation subtracted twice';end if;
 if (select complete from public.controlled_drug_reports where id=current_setting('test.pending_report')::uuid) then raise exception 'Later validation changed report';end if;
end $$;
select public.rx_report_create(:'clinic',to_char(current_date,'YYYY-MM-DD')||'T00:00:00Z',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),true,repeat('7',48))->>'id' as validated_report \gset
select set_config('test.validated_report',:'validated_report',true);
select content_hash as report_hash from public.controlled_drug_reports where id=:'validated_report' \gset
set local role service_role;
select public.rx_pdf_register('report',:'validated_report',1,:'report_hash',encode(convert_to('%PDF-REPORT-SYNTHETIC','UTF8'),'base64'),'iVBORw0KGgo=');
set local role authenticated;
select public.rx_report_finalize(:'validated_report',(select pdf_hash from public.controlled_drug_reports where id=:'validated_report'));
select set_config('test.report_frozen',(select to_jsonb(r)::text from public.controlled_drug_reports r where id=:'validated_report'),true);
select public.rx_medication_report(:'case_id',current_setting('test.application')::jsonb||jsonb_build_object('quantity','1.00','replaces_id',:'application','correction_reason','Rectificación sintética, no devolución física'),repeat('8',48)) as correction \gset
select set_config('test.correction',:'correction',true);
do $$begin
 if (public.rx_vials(current_setting('test.clinic')::uuid)->0->>'balance')::numeric<>9.00 then raise exception 'Correction did not preserve exact balance';end if;
 if (select to_jsonb(r) from public.controlled_drug_reports r where id=current_setting('test.validated_report')::uuid)<>current_setting('test.report_frozen')::jsonb then raise exception 'Correction modified issued report';end if;
 if (public.rx_medications(current_setting('test.case')::uuid)->1->'review') is distinct from 'null'::jsonb then raise exception 'Correction inherited validation';end if;
 begin perform public.rx_vial_close(current_setting('test.vial')::uuid,'8.5','',repeat('9',48));raise exception 'Discrepancy closure without note';exception when raise_exception then if sqlerrm<>'discrepancy_mvZ_note_required' then raise;end if;end;
end $$;
select public.rx_vial_close(:'vial','8.5','Discrepancia sintética conservada',repeat('9',48));
select public.rx_profile_save(:'clinic',1,'MVZ ficticio actualizado','FICTICIA-2','REGISTRO-FICTICIO','{"keep":true}',repeat('a1',24));
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000063',true);
select public.rx_create(:'case_id',current_setting('test.ordinary_items')::jsonb,'','Prueba revocación',repeat('d1',24))->>'id' as revoked_pending_rx \gset
select set_config('test.revoked_pending_rx',:'revoked_pending_rx',true);
select public.rx_prepare(:'revoked_pending_rx',1,:'profile',true,null);
select content_hash as revoked_hash from public.prescriptions where id=:'revoked_pending_rx' \gset
set local role service_role;
select public.rx_pdf_register('prescription',:'revoked_pending_rx',2,:'revoked_hash',encode(convert_to('%PDF-REVOKED-PENDING','UTF8'),'base64'),'iVBORw0KGgo=');
set local role authenticated;
select set_config('test.revoked_pdf',(select pdf_hash from public.prescriptions where id=:'revoked_pending_rx'),true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select public.rx_delegate_revoke(:'delegation','Revocación sintética',repeat('b1',24));
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000063',true);
do $$begin
 if public.rx_pdf_read('prescription',current_setting('test.rx')::uuid)->>'hash'<>current_setting('test.rx_pdf') then raise exception 'Profile/revocation changed historical prescription';end if;
 begin perform public.rx_finalize(current_setting('test.revoked_pending_rx')::uuid,2,current_setting('test.revoked_pdf'));raise exception 'Revoked prepared recipe issued';exception when raise_exception then if sqlerrm not in ('ordinary_delegation_required','delegation_revoked_or_expired') then raise;end if;end;
 begin perform public.rx_create(current_setting('test.case')::uuid,current_setting('test.ordinary_items')::jsonb,'','',repeat('c',48));raise exception 'Revoked ordinary delegation reused';exception when raise_exception then if sqlerrm<>'ordinary_delegation_required' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select public.rx_create(:'case_id',current_setting('test.controlled_items')::jsonb,'FOLIO-SINTETICO-MANUAL','Prueba controlada',repeat('e1',24))->>'id' as controlled_rx \gset
select public.rx_prepare(:'controlled_rx',1,:'profile',false,null);
select content_hash as controlled_hash from public.prescriptions where id=:'controlled_rx' \gset
set local role service_role;
select public.rx_pdf_register('prescription',:'controlled_rx',2,:'controlled_hash',encode(convert_to('%PDF-CONTROLLED-SYNTHETIC','UTF8'),'base64'),'iVBORw0KGgo=');
set local role authenticated;
select public.rx_finalize(:'controlled_rx',2,(select pdf_hash from public.prescriptions where id=:'controlled_rx'));
select id as controlled_item from public.prescription_items where prescription_id=:'controlled_rx' \gset
select public.hospital_admit(:'clinic',:'patient','Jaula sintética',repeat('f1',24)) as stay \gset
select public.rx_schedule(:'controlled_rx',:'controlled_item',:'stay',jsonb_build_array(to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),repeat('12',24));
select id as task from public.hospital_tasks where prescription_item_id=:'controlled_item' \gset
select set_config('test.structured_task',:'task',true);
do $$begin
 begin perform public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.structured_task')::uuid,1,'perform',null,null);raise exception 'Structured task bypassed medication ledger';exception when raise_exception then if sqlerrm<>'structured_medication_report_required' then raise;end if;end;
end $$;
select set_config('test.structured_application',jsonb_build_object('product_version_id','10000000-0000-0000-0000-000000000002','quantity','0.5','unit','ml','route','Vía ficticia','procedure','cuidados','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'lot','LOTE-SINTETICO','hospital_task_id',:'task')::text,true);
select public.rx_medication_report(:'case_id',current_setting('test.structured_application')::jsonb,repeat('13',24));
select public.rx_medication_report(:'case_id',current_setting('test.structured_application')::jsonb,repeat('13',24));
do $$begin
 if (select state from public.hospital_tasks where id=current_setting('test.structured_task')::uuid)<>'done' then raise exception 'Medication did not confirm task';end if;
 if (select count(*) from public.medication_records where hospital_task_id=current_setting('test.structured_task')::uuid)<>1 then raise exception 'Task duplicate medication';end if;
end $$;
-- Bind an existing clinical draft to a profile; version change does not invent identity.
select public.form_document_create(:'clinic',:'patient',:'version',current_setting('test.values')::jsonb,'{}',repeat('14',24))->>'id' as bound_doc \gset
select public.form_document_use_profile(:'bound_doc',1,:'profile',true);
select public.form_document_prepare(:'bound_doc',2,'[]','[]');
select content_hash as bound_hash from public.form_documents where id=:'bound_doc' \gset
set local role service_role;
select public.form_register_pdf(:'bound_doc',3,:'bound_hash',encode(convert_to('%PDF-PROFILE-BOUND','UTF8'),'base64'),null,'iVBORw0KGgo=');
set local role authenticated;
select public.form_document_finalize(:'bound_doc',3,(select pdf_hash from public.form_documents where id=:'bound_doc'));
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000061',true);
do $$begin
 begin perform public.rx_report_create(current_setting('test.clinic')::uuid,'2026-01-01T00:00:00Z','2026-01-02T00:00:00Z',true,repeat('c',48));raise exception 'Admin self-professional';exception when raise_exception then if sqlerrm<>'responsible_professional_only' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000065',true);
do $$begin
 begin perform public.rx_medication_review(current_setting('test.correction')::uuid,'fake','validada','Otro MVZ',repeat('c',48));raise exception 'Another MVZ validated responsible case';exception when raise_exception then if sqlerrm<>'responsible_professional_only' then raise;end if;end;
 if exists(select 1 from public.medication_records) then raise exception 'Unassigned MVZ medications leak';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000064',true);
do $$begin
 if exists(select 1 from public.prescriptions) or exists(select 1 from public.medication_vials) or exists(select 1 from public.controlled_drug_reports) then raise exception 'Cross clinic M6 leak';end if;
end $$;
reset role;
do $$begin
 begin update public.prescriptions set official_folio='Modified' where state='issued';raise exception 'Issued prescription changed';exception when raise_exception then if sqlerrm<>'issued_prescription_is_immutable' then raise;end if;end;
 begin update public.medication_records set quantity=0;raise exception 'Application modified';exception when raise_exception then if sqlerrm<>'rx_history_is_immutable' then raise;end if;end;
end $$;
rollback;
