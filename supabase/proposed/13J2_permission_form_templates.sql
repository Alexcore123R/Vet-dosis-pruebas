-- LOCAL CANDIDATE 13J2: template governance only, after 13J1.
-- Does not cut over patient documents, delegate signatures or open beta.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
insert into private.permission_catalog(code,label,procedure_scoped,requires_professional) values
 ('form.template.read','Consultar plantillas y membrete',false,false),
 ('form.template.edit','Editar plantillas en versiones nuevas',false,false),
 ('form.template.approve','Aprobar contenido de plantillas',false,true),
 ('form.branding.manage','Editar membrete de formatos',false,false);
-- No grants, no role-to-professional conversion, no clinical verification.
create function private.form_template_current(p_clinic uuid,p_code text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.member_permission_grants where id=private.permission_effective(p_clinic,auth.uid(),p_code) and valid_until>clock_timestamp());
$$;
create function private.form_template_readable(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$
 select case when p_clinic is null then exists(select 1 from public.clinic_members m where m.user_id=auth.uid() and private.form_template_current(m.clinic_id,'form.template.read'))
 else private.form_template_current(p_clinic,'form.template.read') end;
$$;
create function private.form_template_require(p_clinic uuid,p_code text,p_professional boolean default false) returns uuid language plpgsql security definer set search_path='' as $$begin
 return private.hospital_order_permission(p_clinic,p_code,null,p_professional);
end$$;
revoke all on function private.form_template_current(uuid,text),private.form_template_readable(uuid),private.form_template_require(uuid,text,boolean) from public,anon,authenticated;
grant execute on function private.form_template_readable(uuid) to authenticated;
drop policy form_template_read on public.form_templates;
drop policy form_version_read on public.form_template_versions;
drop policy form_settings_read on public.clinic_document_settings;
create policy form_template_read on public.form_templates for select to authenticated using(private.form_template_readable(clinic_id));
create policy form_version_read on public.form_template_versions for select to authenticated using(private.form_template_readable(clinic_id));
create policy form_settings_read on public.clinic_document_settings for select to authenticated using(private.form_template_readable(clinic_id));
create or replace function public.form_templates_list(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.form_template_current(p_clinic,'form.template.read') then raise exception 'explicit_template_read_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(v) order by v.template_id,v.version) from public.form_template_versions v where (v.clinic_id is null or v.clinic_id=p_clinic) and v.version=(select max(v2.version) from public.form_template_versions v2 where v2.template_id=v.template_id)),'[]');
end$$;
create or replace function public.form_template_save(p_clinic uuid,p_template uuid,p_expected integer,p_base uuid,p_schema jsonb,p_approved boolean,p_reason text,p_operation text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.form_templates;v public.form_template_versions;current_v public.form_template_versions;receipt_id uuid;fp jsonb;edit_grant uuid;approve_grant uuid;base public.form_template_versions;
begin
 perform private.medication_lock(p_clinic);
 perform private.form_template_require(p_clinic,'form.template.read');
 edit_grant=private.form_template_require(p_clinic,'form.template.edit');
 if p_approved then approve_grant=private.form_template_require(p_clinic,'form.template.approve',true);end if;
 if coalesce(length(btrim(p_reason)),0) not between 1 and 500 or p_approved is null then raise exception 'reason_required';end if;
 perform private.form_validate_schema(p_schema);
 fp=jsonb_build_object('kind','form_template','template',p_template,'expected',p_expected,'base',p_base,'schema',p_schema,'approved',p_approved,'reason',p_reason);
 receipt_id=private.vet_receipt(p_clinic,p_operation,fp);
 if receipt_id is not null then select * into v from public.form_template_versions where form_template_versions.id=receipt_id;return to_jsonb(v);end if;
 if p_base is not null then
  select * into base from public.form_template_versions where form_template_versions.id=p_base and clinic_id is null;
  if not found or base.schema->>'type'<>p_schema->>'type' then raise exception 'invalid_base';end if;
  if not (p_schema->'fields') @> (select coalesce(jsonb_agg(value),'[]') from jsonb_array_elements(base.schema->'fields') where value->'locked'='true'::jsonb) or not (p_schema->'clauses') @> (select coalesce(jsonb_agg(value),'[]') from jsonb_array_elements(base.schema->'clauses') where value->'locked'='true'::jsonb) then raise exception 'protected_field_changed';end if;
 end if;
 if p_template is null then
  insert into public.form_templates(clinic_id,responsible_id,created_by) values(p_clinic,auth.uid(),auth.uid()) returning * into t;
 else
  select * into t from public.form_templates where form_templates.id=p_template and clinic_id=p_clinic for update;
  if not found then raise exception 'template_not_in_clinic';end if;
  select * into current_v from public.form_template_versions where template_id=t.id order by version desc limit 1;
  if p_expected is distinct from current_v.version then raise exception 'template_version_conflict';end if;
  if p_schema->>'type'<>current_v.schema->>'type' or p_base is distinct from current_v.base_version_id then raise exception 'template_origin_changed';end if;
  if not (p_schema->'fields') @> (select coalesce(jsonb_agg(value),'[]') from jsonb_array_elements(current_v.schema->'fields') where value->'locked'='true'::jsonb) or not (p_schema->'clauses') @> (select coalesce(jsonb_agg(value),'[]') from jsonb_array_elements(current_v.schema->'clauses') where value->'locked'='true'::jsonb) then raise exception 'protected_field_changed';end if;
 end if;
 -- Recheck real time after legacy row waits and validation.
 perform private.form_template_require(p_clinic,'form.template.read');
 edit_grant=private.form_template_require(p_clinic,'form.template.edit');
 if p_approved then approve_grant=private.form_template_require(p_clinic,'form.template.approve',true);end if;
 insert into public.form_template_versions(template_id,clinic_id,responsible_id,version,base_version_id,schema,approved,reason,created_by)
 values(t.id,p_clinic,t.responsible_id,coalesce(current_v.version,0)+1,p_base,p_schema,p_approved,p_reason,auth.uid()) returning * into v;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'form_template_version_created',v.id,jsonb_build_object('template',t.id,'version',v.version,'approved',v.approved,'reason',p_reason,'edit_grant_id',edit_grant,'approval_grant_id',approve_grant,'reviewer_id',case when p_approved then auth.uid() end,'profile_version_id',case when p_approved then (select private.rx_profile(p.id)->>'id' from public.professional_profiles p where p.clinic_id=p_clinic and p.user_id=auth.uid()) end));
 return to_jsonb(v);
end $$;

create or replace function public.form_template_preview_check(p_clinic uuid,p_schema jsonb,p_branding jsonb) returns boolean language plpgsql security definer set search_path='' as $$begin
 perform private.medication_lock(p_clinic);
 perform private.form_template_require(p_clinic,'form.template.read');
 perform private.form_validate_schema(p_schema);perform private.form_validate_brand(p_branding);return true;
end$$;
create or replace function public.form_branding(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.form_template_current(p_clinic,'form.template.read') then raise exception 'explicit_template_read_required';end if;
 return private.rx_branding(p_clinic);
end$$;
create or replace function public.form_branding_save(p_clinic uuid,p_branding jsonb) returns void language plpgsql security definer set search_path='' as $$
declare id uuid;g uuid;begin
 perform private.medication_lock(p_clinic);
 perform private.form_template_require(p_clinic,'form.template.read');
 g=private.form_template_require(p_clinic,'form.branding.manage');
 perform private.form_validate_brand(p_branding);
 insert into public.clinic_document_settings(clinic_id,branding,created_by) values(p_clinic,p_branding,auth.uid()) returning clinic_document_settings.id into id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'form_branding_version_created',id,jsonb_build_object('permission_grant_id',g));
end$$;
create function public.form_template_permissions(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare readable boolean;begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'current_member_required';end if;
 readable=private.form_template_current(p_clinic,'form.template.read');
 return jsonb_build_object('schema_version',1,'mode','templates_only','can_read',readable,
 'can_edit',readable and private.form_template_current(p_clinic,'form.template.edit'),
 'can_approve',readable and private.form_template_current(p_clinic,'form.template.edit') and private.form_template_current(p_clinic,'form.template.approve') and private.clinical_professional_at(p_clinic,auth.uid(),clock_timestamp()),
 'can_brand',readable and private.form_template_current(p_clinic,'form.branding.manage'));
end$$;
revoke all on function public.form_template_permissions(uuid) from public,anon,authenticated;
grant execute on function public.form_template_permissions(uuid) to authenticated;
commit;
