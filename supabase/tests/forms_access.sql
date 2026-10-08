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
select id as base from public.form_template_versions where clinic_id is null and schema->>'type'='euthanasia' \gset
select set_config('test.base',:'base',true);
select set_config('test.schema',(select schema::text from public.form_template_versions where id=:'base'),true);
select public.form_template_save(:'clinic',null,null,:'base',current_setting('test.schema')::jsonb,true,'Revisión sintética',repeat('a',48))->>'id' as version \gset
select set_config('test.version',:'version',true);
select template_id as template from public.form_template_versions where id=:'version' \gset
select set_config('test.template',:'template',true);
select public.create_vet_patient(:'clinic','{"name":"Paciente sintético","species":"Ficticia","sex":"sin especificar"}','{"name":"Tutor sintético"}',repeat('b',48)) as patient \gset
select set_config('test.patient',:'patient',true);
select set_config('test.values','{"mvz_name":"MVZ ficticio","mvz_license":"CEDULA-FICTICIA","signer_name":"Tutor ficticio","signer_id":"IDENTIFICACION-FICTICIA","privacy_url":"https://example.test/privacidad","procedure":"Procedimiento ficticio sin uso clínico","information":"Información sintética","clinical_reason":"Motivo ficticio","prior_opinion":"Concepto ficticio","method":"Método ficticio sin fármacos","body_disposition":"Acuerdo ficticio","cost":"Costo ficticio"}',true);
select public.form_document_create(:'clinic',:'patient',:'version',current_setting('test.values')::jsonb,'{"header":"Clínica ficticia"}',repeat('c',48))->>'id' as doc \gset
select set_config('test.doc',:'doc',true);
select public.form_document_assign(:'doc','00000000-0000-0000-0000-000000000063');
-- Aux can fill assigned draft; cannot edit templates, prepare, sign, or access artifacts.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000063',true);
select public.form_document_save(:'doc',2,current_setting('test.values')::jsonb,'{"header":"Clínica ficticia"}');
do $$ begin
 if (select count(*) from public.vet_owners)<>0 then raise exception 'Aux owner access broadened';end if;
 begin perform public.form_branding_save(current_setting('test.clinic')::uuid,'{}');raise exception 'Aux changed branding';exception when raise_exception then if sqlerrm<>'clinic_admin_required' then raise;end if;end;
 if jsonb_array_length(public.form_documents_list(current_setting('test.clinic')::uuid))<>1 then raise exception 'Assigned draft not available';end if;
 begin perform public.form_document_prepare(current_setting('test.doc')::uuid,3,'[[0.1,0.1],[0.8,0.8]]','[[0.1,0.1],[0.8,0.8]]');raise exception 'Aux prepared signatures';exception when raise_exception then if sqlerrm<>'responsible_mvz_required' then raise;end if;end;
 begin perform public.form_template_save(current_setting('test.clinic')::uuid,null,null,null,current_setting('test.schema')::jsonb,true,'Unauthorized',repeat('d',48));raise exception 'Aux edited template';exception when raise_exception then if sqlerrm<>'template_editor_required' then raise;end if;end;
 begin perform public.form_read_pdf(current_setting('test.doc')::uuid);raise exception 'Aux artifact access';exception when raise_exception then if sqlerrm<>'document_access_denied' then raise;end if;end;
 begin perform public.form_register_pdf(current_setting('test.doc')::uuid,3,'bad','bad','bad','bad');raise exception 'User registered artifact';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
do $$ declare s jsonb;begin
 s=current_setting('test.schema')::jsonb;
 s=jsonb_set(s,'{fields,0,label}','"Altered protected animal field"');
 begin perform public.form_template_save(current_setting('test.clinic')::uuid,null,null,null,s,true,'Alteración',repeat('d',48));raise exception 'Protected field changed';exception when raise_exception then if sqlerrm<>'protected_field_changed' then raise;end if;end;
 begin perform public.form_document_finalize(current_setting('test.doc')::uuid,3,'fake');raise exception 'Signed before PDF';exception when raise_exception then if sqlerrm<>'reviewed_pdf_mismatch' then raise;end if;end;
 begin perform public.form_document_prepare(current_setting('test.doc')::uuid,3,'[[0.1,0.1],null,[0.8,0.8]]','[[0.1,0.1],[0.8,0.8]]');raise exception 'Disconnected points accepted';exception when raise_exception then if sqlerrm<>'signature_required' then raise;end if;end;
 begin perform public.form_document_prepare(current_setting('test.doc')::uuid,3,'[[0.1,0.1],[0.1,0.1]]','[[0.1,0.1],[0.8,0.8]]');raise exception 'Point signature accepted';exception when raise_exception then if sqlerrm<>'signature_required' then raise;end if;end;
end $$;
select public.form_document_prepare(:'doc',3,'[[0.1,0.1],[0.8,0.8]]','[[0.2,0.2],[0.7,0.7]]');
select content_hash as hash from public.form_documents where id=:'doc' \gset
select set_config('test.content',:'hash',true);
-- Synthetic bytes test DB invariants; renderer tests separately exercise real PDFs and PNGs.
set local role service_role;
select public.form_register_pdf(:'doc',4,:'hash',encode(convert_to('%PDF-SYNTHETIC-ONLY','UTF8'),'base64'),'iVBORw0KGgo=','iVBORw0KGgo=');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select pdf_hash as pdfhash from public.form_documents where id=:'doc' \gset
select set_config('test.pdfhash',:'pdfhash',true);
select public.form_document_finalize(:'doc',4,:'pdfhash');
select public.form_document_finalize(:'doc',4,:'pdfhash');
-- A later GLOBAL base cannot rewrite or invalidate an older clinic copy.
reset role;
insert into public.form_template_versions(template_id,version,schema,reason)
select template_id,2,jsonb_set(schema,'{clauses,1,text}','"Nuevo texto global de revocación ficticio para prueba"'),'Nueva referencia global sintética'
from public.form_template_versions where id=:'base';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
-- Edits to version and patient do not mutate the exact signed snapshot or binary.
select public.form_template_save(:'clinic',:'template',1,:'base',jsonb_set(current_setting('test.schema')::jsonb,'{title}','"Nueva versión sintética"'),true,'Nueva revisión',repeat('d',48));
select public.form_template_save(:'clinic',:'template',2,:'base',current_setting('test.schema')::jsonb,true,'Restauración',repeat('e',48));
do $$ declare d public.form_documents;s public.form_signatures;begin
 select * into d from public.form_documents where id=current_setting('test.doc')::uuid;
 if d.version_id<>current_setting('test.version')::uuid or d.snapshot->'schema'->>'title'='Nueva versión sintética' or d.accepted_at is null or d.prepared_at is null or d.pdf_hash<>current_setting('test.pdfhash') then raise exception 'Signed snapshot changed';end if;
 if public.form_read_pdf(d.id)->>'hash'<>current_setting('test.pdfhash') then raise exception 'Artifact changed';end if;
 if (select count(*) from public.form_signatures where document_id=d.id)<>2 then raise exception 'Signatures missing';end if;
 begin perform public.form_document_save(d.id,4,current_setting('test.values')::jsonb,'{}');raise exception 'Signed draft edited';exception when raise_exception then if sqlerrm<>'document_not_editable' then raise;end if;end;
 begin update public.form_documents set state='draft' where id=d.id;raise exception 'Direct write accepted';exception when insufficient_privilege then null;end;
 begin update public.form_template_versions set schema='{}' where id=current_setting('test.version')::uuid;raise exception 'Version direct write accepted';exception when insufficient_privilege then null;end;
end $$;
-- Other physician and outsider cannot read the document/signatures.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000065',true);
do $$begin
 if (select count(*) from public.form_documents)<>0 or (select count(*) from public.form_signatures)<>0 then raise exception 'Other MVZ read case';end if;
 begin perform public.form_document_finalize(current_setting('test.doc')::uuid,4,current_setting('test.pdfhash'));raise exception 'Other MVZ signed';exception when raise_exception then if sqlerrm<>'responsible_mvz_required' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000063',true);
do $$begin if (select count(*) from public.form_documents)<>0 or (select count(*) from public.form_signatures)<>0 then raise exception 'Aux read prepared/signed document';end if;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000064',true);
do $$begin
 if (select count(*) from public.form_documents)<>0 or (select count(*) from public.form_signatures)<>0 then raise exception 'Cross clinic disclosure';end if;
 begin perform public.form_templates_list(current_setting('test.clinic')::uuid);raise exception 'Outside clinic list';exception when raise_exception then if sqlerrm<>'clinical_role_required' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000061',true);
do $$begin
 if (select count(*) from public.audit_log where action='form_document_signed')<>1 then raise exception 'Signing retry duplicated audit';end if;
 begin perform public.form_document_create(current_setting('test.clinic')::uuid,current_setting('test.patient')::uuid,current_setting('test.version')::uuid,current_setting('test.values')::jsonb,'{}',repeat('f',48));raise exception 'Admin implicitly physician';exception when raise_exception then if sqlerrm<>'responsible_mvz_required' then raise;end if;end;
end $$;
reset role;
-- Triggers also stop a service/owner mistake on signed rows (TRUNCATE is never granted to clients).
do $$begin
 begin update public.form_documents set values='{}' where id=current_setting('test.doc')::uuid;raise exception 'Owner changed signed row';exception when raise_exception then if sqlerrm<>'signed_document_is_immutable' then raise;end if;end;
 begin delete from public.form_signatures where document_id=current_setting('test.doc')::uuid;raise exception 'Signature deleted';exception when raise_exception then if sqlerrm<>'signed_artifact_is_immutable' then raise;end if;end;
 begin update private.form_artifacts set pdf=convert_to('changed','UTF8') where document_id=current_setting('test.doc')::uuid;raise exception 'PDF overwritten';exception when raise_exception then if sqlerrm<>'signed_artifact_is_immutable' then raise;end if;end;
 begin update public.form_template_versions set reason='changed' where id=current_setting('test.version')::uuid;raise exception 'Historical template overwritten';exception when raise_exception then if sqlerrm<>'version_is_immutable' then raise;end if;end;
end $$;
rollback;
