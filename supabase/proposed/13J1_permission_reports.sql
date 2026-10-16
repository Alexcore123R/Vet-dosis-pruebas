-- LOCAL CANDIDATE 13J1, after 13I2. No remote deployment or beta activation.
-- Current scope: the responsible professional's controlled-drug ledger, not
-- a general production/official report. No automatic grants or conversions.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
create function private.report_current(p_clinic uuid,p_user uuid,p_code text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.member_permission_grants where id=private.permission_effective(p_clinic,p_user,p_code) and valid_until>clock_timestamp());
$$;
create function private.report_readable(r public.controlled_drug_reports) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid()=r.responsible_id and private.clinical_professional_at(r.clinic_id,auth.uid(),clock_timestamp())
 and private.report_current(r.clinic_id,auth.uid(),'clinical.read') and private.report_current(r.clinic_id,auth.uid(),'patient.read')
 and (private.report_current(r.clinic_id,auth.uid(),'report.prepare') or private.report_current(r.clinic_id,auth.uid(),'report.issue'));
$$;
create function private.report_prepared_current(r public.controlled_drug_reports) returns void language plpgsql security definer set search_path='' as $$
declare authority jsonb=r.snapshot->'report_authority';profile jsonb;begin
 if authority->>'version' is distinct from '1' then raise exception 'attributed_report_required';end if;
 if not private.clinical_professional_at(r.clinic_id,r.responsible_id,clock_timestamp())
 or not private.report_current(r.clinic_id,r.responsible_id,'clinical.read') or not private.report_current(r.clinic_id,r.responsible_id,'patient.read')
 or private.permission_effective(r.clinic_id,r.responsible_id,'report.prepare')::text is distinct from authority->>'prepare_grant_id'
 or not private.report_current(r.clinic_id,r.responsible_id,'report.prepare')
 or not exists(select 1 from public.clinic_members where clinic_id=r.clinic_id and user_id=r.responsible_id and created_at=(authority->>'member_since')::timestamptz)
 then raise exception 'report_authority_changed';end if;
 select private.rx_profile(id) into profile from public.professional_profiles where clinic_id=r.clinic_id and user_id=r.responsible_id;
 if profile->>'id' is distinct from authority->>'profile_version_id' or profile-'signature' is distinct from r.snapshot->'profile'
 or profile->'signature' is distinct from r.snapshot->'mvz_signature' then raise exception 'report_profile_changed';end if;
 if r.official then raise exception 'reference_reports_only';end if;
 if encode(sha256(convert_to(r.snapshot::text,'UTF8')),'hex') is distinct from r.content_hash then raise exception 'report_content_changed';end if;
end$$;
revoke all on function private.report_current(uuid,uuid,text),private.report_readable(public.controlled_drug_reports),private.report_prepared_current(public.controlled_drug_reports) from public,anon,authenticated;
-- Raw tables expose no snapshots/signature vectors. Scope lookup by Edge uses
-- a minimal column grant; all report contents go through checked RPCs.
revoke select on public.controlled_drug_reports,public.controlled_drug_report_items from authenticated;
grant select(id,clinic_id) on public.controlled_drug_reports to authenticated;
drop policy rx_report_read on public.controlled_drug_reports;
drop policy rx_report_items_read on public.controlled_drug_report_items;
create policy rx_report_read on public.controlled_drug_reports for select to authenticated using(private.report_readable(controlled_drug_reports));
grant execute on function private.report_readable(public.controlled_drug_reports) to authenticated;
create or replace function public.rx_report_create(p_clinic uuid,p_start text,p_end text,p_official boolean,p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_report_id uuid;fp jsonb;starts timestamptz;ends timestamptz;cutoff_at timestamptz;profile jsonb;items jsonb;pending uuid[];rows jsonb;s jsonb;r public.controlled_drug_reports;schema jsonb;authority jsonb;
begin
 perform private.medication_lock(p_clinic);
 perform private.hospital_order_permission(p_clinic,'clinical.read',null,false);
 perform private.hospital_order_permission(p_clinic,'patient.read',null,false);
 perform private.hospital_order_permission(p_clinic,'report.prepare',null,true);
 if p_official is distinct from false then raise exception 'reference_reports_only';end if;
 starts=private.clinical_time(p_start);ends=private.clinical_time(p_end);
 if starts>=ends or ends>clock_timestamp() or p_official is null then raise exception 'closed_report_period_required';end if;
 fp=jsonb_build_object('kind','controlled_report','start',p_start,'end',p_end,'official',p_official);v_report_id=private.vet_receipt(p_clinic,p_operation,fp);if v_report_id is not null then select * into r from public.controlled_drug_reports where controlled_drug_reports.id=v_report_id;perform private.report_prepared_current(r);return to_jsonb(r)-'snapshot';end if;
 perform pg_advisory_xact_lock(hashtextextended('rx-ledger-'||p_clinic::text,0));cutoff_at=clock_timestamp();
 profile=private.rx_profile((select professional_profiles.id from public.professional_profiles where clinic_id=p_clinic and user_id=auth.uid()));
 if profile is null or coalesce((profile->>'license'),'')='' then raise exception 'professional_profile_required';end if;
 perform private.form_validate_signature(profile->'signature');
 with current_records as (
  select m.*,p.name,p.presentation,p.source_status,p.source_valid_until,p.classification,p.quantified_prescription from public.medication_records m join public.medication_product_versions p on p.id=m.product_version_id
  where m.clinic_id=p_clinic and m.responsible_id=auth.uid() and m.observed_at>=starts and m.observed_at<ends and m.reported_at<=cutoff_at
  and (p.classification<>'no_controlado' or coalesce(p.quantified_prescription,true))
  and not exists(select 1 from public.medication_records n where n.replaces_id=m.id and n.reported_at<=cutoff_at)
 ),decisions as (
  select m.*,v.id as review_id,v.decision,v.validated_by,v.validated_at,v.permission_grant_id as review_permission_grant_id from current_records m left join lateral (select * from public.controlled_drug_reviews d where d.record_id=m.id and d.content_hash=m.content_hash and d.validated_at<=cutoff_at order by d.validated_at desc,d.id desc limit 1) v on true
 )
 select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('quantity',d.quantity::text,'patient_name',(select name from public.vet_patients where vet_patients.id=d.patient_id),'official_folio',(select official_folio from public.prescriptions where prescriptions.id=d.prescription_id))) filter(where decision='validada' and incidence='' and source_status='verificada' and (source_valid_until is null or source_valid_until>cutoff_at) and review_permission_grant_id is not null),'[]'),
 coalesce(array_agg(d.id) filter(where decision is distinct from 'validada' or incidence<>'' or source_status<>'verificada' or source_valid_until<=cutoff_at or review_permission_grant_id is null),'{}') into items,pending from decisions d;
 v_report_id=gen_random_uuid();
 select coalesce(jsonb_agg(jsonb_build_array((x->>'patient_name'),(x->>'name'),(x->>'lot'),(x->>'quantity')||' '||(x->>'unit'),(x->>'route'),(x->>'observed_at'),(x->>'performed_by'),(x->>'validated_by'),coalesce((x->>'official_folio'),'Sin folio vinculado'))),'[]') into rows from jsonb_array_elements(items) x;
 schema=jsonb_build_object('type','controlled_report','title','Registro de control · basado en Anexo 5, no oficial',
 'fields',jsonb_build_array(jsonb_build_object('id','period','type','text','label','Periodo UTC (fin excluyente)'),jsonb_build_object('id','state','type','text','label','Estado del corte'),jsonb_build_object('id','pending','type','text','label','Registros pendientes / incidencias'),jsonb_build_object('id','records','type','table','label','Únicamente aplicaciones validadas al corte','columns',jsonb_build_array('Paciente','Producto','Lote','Cantidad','Vía','Hora observada','Aplicó','Validó','Folio vinculado'))),'clauses',jsonb_build_array(jsonb_build_object('text','Este corte es inmutable. Validaciones o correcciones posteriores requieren otro reporte. No se crean folios ni se infieren requisitos oficiales.')));
 s=jsonb_build_object('clinical',true,'schema',schema,'document_id',v_report_id,'template_version',1,'prepared_at',cutoff_at,'branding',private.rx_branding(p_clinic),'profile',profile-'signature','mvz_signature',profile->'signature','entries',items,'pending_ids',to_jsonb(pending),'values',jsonb_build_object('period',p_start||' — '||p_end,'state',case when cardinality(pending)=0 then 'Completo al corte' else 'INCOMPLETO: hay pendientes o incidencias' end,'pending',cardinality(pending)::text||' · '||array_to_string(pending,', '),'records',rows,'mvz_name',(profile->>'name'),'mvz_license',(profile->>'license')));
 authority=jsonb_build_object('version',1,'prepare_grant_id',private.permission_effective(p_clinic,auth.uid(),'report.prepare'),'profile_version_id',profile->>'id','member_since',(select created_at from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()));
 s=s||jsonb_build_object('report_authority',authority);
 insert into public.controlled_drug_reports(id,clinic_id,responsible_id,starts_at,ends_at,cutoff,official,complete,regulatory_version_id,pending_ids,snapshot,content_hash)
 values(v_report_id,p_clinic,auth.uid(),starts,ends,cutoff_at,p_official,cardinality(pending)=0,null,pending,s,encode(sha256(convert_to(s::text,'UTF8')),'hex')) returning * into r;
 insert into public.controlled_drug_report_items(report_id,record_id,review_id) select r.id,((x->>'id'))::uuid,((x->>'review_id'))::uuid from jsonb_array_elements(items) x;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,r.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'controlled_report_cutoff_prepared',r.id);return to_jsonb(r)-'snapshot';
end $$;

create or replace function public.rx_reports(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'current_member_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(r)-'snapshot' order by r.created_at desc,r.id) from public.controlled_drug_reports r where r.clinic_id=p_clinic and private.report_readable(r)),'[]');
end$$;
create function public.rx_report_export(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.controlled_drug_reports;begin
 select * into r from public.controlled_drug_reports where id=p_id;
 if not found or not private.report_readable(r) or r.state<>'issued' then raise exception 'issued_report_access_required';end if;
 -- CSV/XLSX require entries, never the signature vector or other raw snapshot.
 return to_jsonb(r)-'snapshot'||jsonb_build_object('snapshot',jsonb_build_object('entries',r.snapshot->'entries','values',r.snapshot->'values'));
end$$;
create or replace function public.rx_report_finalize(p_id uuid,p_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.controlled_drug_reports;g uuid;begin
 select * into r from public.controlled_drug_reports where id=p_id;
 if not found then raise exception 'report_access_denied';end if;
 perform private.medication_lock(r.clinic_id);
 perform pg_advisory_xact_lock(hashtextextended(r.responsible_id::text,9061));
 select * into r from public.controlled_drug_reports where id=p_id for update;
 if not private.report_readable(r) then raise exception 'report_access_denied';end if;
 g=private.hospital_order_permission(r.clinic_id,'report.issue',null,true);
 if r.pdf_hash is distinct from p_hash or p_hash is null then raise exception 'reviewed_report_mismatch';end if;
 if r.state='issued' then return to_jsonb(r)-'snapshot';end if;
 perform private.report_prepared_current(r);
 if r.state<>'ready' or not exists(select 1 from private.rx_artifacts a where kind='report' and entity_id=r.id and content_hash=r.content_hash and revision=1 and pdf_hash=p_hash and encode(sha256(pdf),'hex')=p_hash) then raise exception 'reviewed_pdf_required';end if;
 update public.controlled_drug_reports set state='issued',issued_at=clock_timestamp() where id=r.id returning * into r;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(r.clinic_id,auth.uid(),'controlled_report_signed',r.id,jsonb_build_object('permission_grant_id',g,'content_hash',r.content_hash,'pdf_hash',p_hash));
 return to_jsonb(r)-'snapshot';
end$$;
-- Preserve the attributed/standing prescription dispatcher unchanged.
alter function public.rx_pdf_snapshot(text,uuid) set schema private;
alter function private.rx_pdf_snapshot(text,uuid) rename to rx_pdf_snapshot_before_reports;
revoke all on function private.rx_pdf_snapshot_before_reports(text,uuid) from public,anon,authenticated,service_role;
create function public.rx_pdf_snapshot(p_kind text,p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.controlled_drug_reports;begin
 if p_kind<>'report' then return private.rx_pdf_snapshot_before_reports(p_kind,p_id);end if;
 select * into r from public.controlled_drug_reports where id=p_id;
 if not found or not private.report_readable(r) then raise exception 'report_access_denied';end if;
 if r.state<>'issued' then perform private.report_prepared_current(r);end if;
 return jsonb_build_object('snapshot',r.snapshot,'content_hash',r.content_hash,'revision',1,'state',r.state);
end$$;
alter function public.rx_pdf_register(text,uuid,integer,text,text,text) set schema private;
alter function private.rx_pdf_register(text,uuid,integer,text,text,text) rename to rx_pdf_register_before_reports;
revoke all on function private.rx_pdf_register_before_reports(text,uuid,integer,text,text,text) from public,anon,authenticated,service_role;
create function public.rx_pdf_register(p_kind text,p_id uuid,p_revision integer,p_content_hash text,p_pdf text,p_signature text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.controlled_drug_reports;begin
 if p_kind='report' then
  select * into r from public.controlled_drug_reports where id=p_id;
  if not found then raise exception 'report_access_denied';end if;
  perform private.medication_lock(r.clinic_id);
  perform pg_advisory_xact_lock(hashtextextended(r.responsible_id::text,9061));
  select * into r from public.controlled_drug_reports where id=p_id for update;
  perform private.report_prepared_current(r);
 end if;
 return private.rx_pdf_register_before_reports(p_kind,p_id,p_revision,p_content_hash,p_pdf,p_signature);
end$$;
create function public.rx_report_permissions(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare eligible boolean;begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'current_member_required';end if;
 eligible=private.clinical_professional_at(p_clinic,auth.uid(),clock_timestamp()) and private.report_current(p_clinic,auth.uid(),'clinical.read') and private.report_current(p_clinic,auth.uid(),'patient.read');
 return jsonb_build_object('schema_version',1,'mode','controlled_reference','can_prepare',eligible and private.report_current(p_clinic,auth.uid(),'report.prepare'),'can_issue',eligible and private.report_current(p_clinic,auth.uid(),'report.issue'));
end$$;
revoke all on function public.rx_pdf_register(text,uuid,integer,text,text,text),public.rx_pdf_snapshot(text,uuid),public.rx_report_export(uuid),public.rx_report_permissions(uuid) from public,anon,authenticated;
grant execute on function public.rx_pdf_register(text,uuid,integer,text,text,text) to service_role;
grant execute on function public.rx_pdf_snapshot(text,uuid),public.rx_report_export(uuid),public.rx_report_permissions(uuid) to authenticated;
commit;
