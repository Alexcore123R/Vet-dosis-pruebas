-- Stage 2A: explicit grants and evidence. Does not activate replacement of legacy ACLs.
-- Apply once after M6, 09A/09B. No clinical data, grants or verifications are seeded.
begin;
create table private.permission_policy (
 singleton boolean primary key default true check(singleton),
 enforcement_enabled boolean not null default false,
 migration_reviewed boolean not null default false,
 check(not enforcement_enabled or migration_reviewed)
);
insert into private.permission_policy default values;
create table private.permission_catalog (
 code text primary key, label text not null, procedure_scoped boolean not null,
 requires_professional boolean not null, version integer not null default 1 check(version>0)
);
insert into private.permission_catalog(code,label,procedure_scoped,requires_professional) values
 ('patient.read','Consultar pacientes',false,false),('patient.write','Registrar pacientes',false,false),
 ('appointment.read','Consultar agenda',false,false),('appointment.manage','Gestionar agenda',false,false),
 ('hospital.read','Consultar hospitalización',false,false),('hospital.report','Registrar observaciones',false,false),
 ('hospital.schedule','Prescribir tareas de hospitalización',false,true),
 ('inventory.read','Consultar inventario',false,false),('inventory.adjust','Ajustar inventario',false,false),
 ('prescription.prepare','Preparar recetas',false,false),('prescription.authorize','Autorizar recetas',false,true),
 ('medication.report','Reportar aplicaciones',false,false),('medication.validate','Validar aplicaciones',false,true),
 ('controlled.dispense','Dispensar productos sujetos a receta o controlados',false,true),
 ('report.prepare','Preparar reportes',false,false),('report.issue','Emitir reportes profesionales',false,true),
 ('form.prepare','Preparar formatos',false,false),('form.authorize','Autorizar formatos profesionales',false,true),
 ('backup.export','Exportar respaldo de clínica',false,false),('backup.restore','Restaurar respaldo de clínica',false,false),
 ('workspace.manage','Administrar espacio',false,false),
 ('procedure.perform','Realizar procedimiento',true,false),
 ('drug.administer','Administrar medicamento',true,false),('vial.draw','Extraer de frasco',true,false);
create table private.member_job_labels (
 clinic_id uuid not null,user_id uuid not null,label text not null check(length(btrim(label))<=100),
 updated_by uuid not null references auth.users(id),updated_at timestamptz not null default clock_timestamp(),
 primary key(clinic_id,user_id),foreign key(clinic_id,user_id) references public.clinic_members(clinic_id,user_id) on delete cascade
);
create table private.procedure_types (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),
 name text not null check(length(btrim(name)) between 1 and 100),active boolean not null default true,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),unique(clinic_id,id)
);
create unique index permission_procedure_name on private.procedure_types(clinic_id,lower(btrim(name)));
create table private.professional_verifications (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),
 clinic_id uuid references public.clinics(id),profile_version_id uuid not null references private.professional_profile_versions(id),
 reviewer_id uuid not null references auth.users(id),reviewed_at timestamptz not null,
 evidence_hash text not null check(evidence_hash ~ '^[a-f0-9]{64}$'),
 evidence_reference text not null check(length(btrim(evidence_reference)) between 1 and 1000),
 valid_until timestamptz not null,recorded_at timestamptz not null default clock_timestamp(),
 origin text not null check(origin in ('platform_external','clinic_responsible')),
 check(user_id<>reviewer_id),check(valid_until>reviewed_at),
 check((origin='platform_external' and clinic_id is null) or (origin='clinic_responsible' and clinic_id is not null))
);
create table private.professional_revocations (
 verification_id uuid primary key references private.professional_verifications(id),
 revoked_by uuid not null references auth.users(id),revoked_at timestamptz not null default clock_timestamp(),
 reason text not null check(length(btrim(reason)) between 1 and 1000)
);
create table private.clinic_responsible_designations (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),
 user_id uuid not null references auth.users(id),member_since timestamptz not null,proposed_by uuid not null references auth.users(id),
 proposed_at timestamptz not null default clock_timestamp(),valid_until timestamptz not null,
 accepted_at timestamptz,revoked_at timestamptz,revoked_by uuid references auth.users(id)
);
create table private.member_permission_grants (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),
 user_id uuid not null references auth.users(id),member_since timestamptz not null,
 code text not null references private.permission_catalog(code),procedure_id uuid,
 granted_by uuid not null references auth.users(id),granted_at timestamptz not null default clock_timestamp(),
 valid_until timestamptz not null,reason text not null check(length(btrim(reason)) between 1 and 1000),
 foreign key(clinic_id,procedure_id) references private.procedure_types(clinic_id,id),check(valid_until>granted_at)
);
create table private.permission_revocations (
 grant_id uuid primary key references private.member_permission_grants(id),
 revoked_by uuid not null references auth.users(id),revoked_at timestamptz not null default clock_timestamp(),
 reason text not null check(length(btrim(reason)) between 1 and 1000)
);
create index permission_subject_scope on private.member_permission_grants(clinic_id,user_id,code,procedure_id);
create index verification_subject_scope on private.professional_verifications(user_id,clinic_id);
-- Private evidence never appears in clinical exports or client table access.
do $$declare t text;begin
 foreach t in array array['permission_policy','permission_catalog','member_job_labels','procedure_types','professional_verifications','professional_revocations','clinic_responsible_designations','member_permission_grants','permission_revocations'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated',t);
 end loop;
end$$;
create function private.permission_event(p_clinic uuid,p_action text,p_id uuid,p_details jsonb default '{}') returns void language sql security definer set search_path='' as $$
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),p_action,p_id::text,p_details);
$$;
create function private.permission_admin(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() and role='admin');
$$;
create function private.professional_current(p_clinic uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.clinic_members m where m.clinic_id=p_clinic and m.user_id=p_user)
 and exists(select 1 from private.professional_verifications v
 join private.professional_profile_versions reviewed on reviewed.id=v.profile_version_id
 join public.professional_profiles rp on rp.id=reviewed.profile_id and rp.user_id=v.user_id
 join public.professional_profiles current_profile on current_profile.clinic_id=p_clinic and current_profile.user_id=v.user_id
 join lateral (select cv.* from private.professional_profile_versions cv where cv.profile_id=current_profile.id order by cv.version desc limit 1) current_v on true
 where v.user_id=p_user and (v.clinic_id is null or v.clinic_id=p_clinic)
 and v.valid_until>statement_timestamp() and v.reviewed_at<=statement_timestamp()
 and length(btrim(current_v.license))>0 and current_v.license=reviewed.license and current_v.name=reviewed.name
 and not exists(select 1 from private.professional_revocations r where r.verification_id=v.id));
$$;
create function private.permission_responsible(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.professional_current(p_clinic,auth.uid()) and exists(select 1 from private.clinic_responsible_designations d
 where d.clinic_id=p_clinic and d.user_id=auth.uid() and exists(select 1 from public.clinic_members m where m.clinic_id=d.clinic_id and m.user_id=d.user_id and m.created_at=d.member_since) and d.accepted_at is not null and d.revoked_at is null and d.valid_until>statement_timestamp());
$$;
create function private.permission_effective(p_clinic uuid,p_user uuid,p_code text,p_procedure uuid default null) returns uuid language sql stable security definer set search_path='' as $$
 select g.id from private.member_permission_grants g
 join public.clinic_members m on m.clinic_id=g.clinic_id and m.user_id=g.user_id and m.created_at=g.member_since
 join private.permission_catalog c on c.code=g.code
 where g.clinic_id=p_clinic and g.user_id=p_user and g.code=p_code and g.valid_until>statement_timestamp()
 and ((not c.procedure_scoped and p_procedure is null and g.procedure_id is null)
 or (c.procedure_scoped and p_procedure is not null and g.procedure_id=p_procedure and exists(select 1 from private.procedure_types t where t.id=p_procedure and t.clinic_id=p_clinic and t.active)))
 and (not c.requires_professional or private.professional_current(p_clinic,p_user))
 and not exists(select 1 from private.permission_revocations r where r.grant_id=g.id)
 order by g.granted_at desc,g.id limit 1;
$$;
create function private.permission_require(p_clinic uuid,p_code text,p_procedure uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare g uuid;begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 g=private.permission_effective(p_clinic,auth.uid(),p_code,p_procedure);
 if g is null then raise exception 'explicit_permission_required';end if;return g;
end$$;
create function public.permission_snapshot(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare manager boolean;begin
 if not private.has_clinic_role(p_clinic) then raise exception 'membership_required';end if;
 manager=private.permission_admin(p_clinic);
 return jsonb_build_object('enforcement_enabled',(select enforcement_enabled from private.permission_policy),'can_manage',manager,
 'can_review',private.permission_responsible(p_clinic),
 'catalog',(select jsonb_agg(to_jsonb(c) order by code) from private.permission_catalog c),
 'procedures',coalesce((select jsonb_agg(to_jsonb(t) order by name) from private.procedure_types t where clinic_id=p_clinic),'[]'),
 'members',coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'email',u.email,'job_label',coalesce(l.label,''),
 'professional_current',private.professional_current(p_clinic,m.user_id))) from public.clinic_members m join auth.users u on u.id=m.user_id
 left join private.member_job_labels l on l.clinic_id=m.clinic_id and l.user_id=m.user_id
 where m.clinic_id=p_clinic and (manager or private.permission_responsible(p_clinic) or m.user_id=auth.uid())),'[]'),
 'grants',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'user_id',g.user_id,'code',g.code,'procedure_id',g.procedure_id,'granted_by',g.granted_by,'granted_at',g.granted_at,'valid_until',g.valid_until,'reason',g.reason,
 'effective',private.permission_effective(p_clinic,g.user_id,g.code,g.procedure_id)=g.id,'revoked',exists(select 1 from private.permission_revocations r where r.grant_id=g.id))) from private.member_permission_grants g where g.clinic_id=p_clinic and (manager or g.user_id=auth.uid())),'[]'),
 'responsible',coalesce((select jsonb_agg(to_jsonb(d)) from private.clinic_responsible_designations d where d.clinic_id=p_clinic and (manager or d.user_id=auth.uid())),'[]'));
end$$;
create function public.permission_set_job(p_clinic uuid,p_user uuid,p_label text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.clinics where id=p_clinic for update;
 if not private.permission_admin(p_clinic) then raise exception 'admin_required';end if;
 insert into private.member_job_labels(clinic_id,user_id,label,updated_by) values(p_clinic,p_user,btrim(p_label),auth.uid())
 on conflict(clinic_id,user_id) do update set label=excluded.label,updated_by=excluded.updated_by,updated_at=clock_timestamp();
 perform private.permission_event(p_clinic,'job_label_changed',p_user);
end$$;
create function public.permission_procedure_set(p_clinic uuid,p_id uuid,p_name text,p_active boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;begin
 perform 1 from public.clinics where id=p_clinic for update;
 if not private.permission_admin(p_clinic) then raise exception 'admin_required';end if;
 if p_id is null then
 insert into private.procedure_types(clinic_id,name,active,created_by) values(p_clinic,btrim(p_name),p_active,auth.uid()) returning id into result;
 else
 update private.procedure_types set name=btrim(p_name),active=p_active where id=p_id and clinic_id=p_clinic returning id into result;
 if result is null then raise exception 'procedure_not_found';end if;end if;
 perform private.permission_event(p_clinic,'procedure_type_changed',result);return result;
end$$;
create function public.permission_grant(p_clinic uuid,p_user uuid,p_code text,p_procedure uuid,p_until timestamptz,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare c private.permission_catalog;m public.clinic_members;result uuid;begin
 perform 1 from public.clinics where id=p_clinic for update;
 if not private.permission_admin(p_clinic) then raise exception 'admin_required';end if;
 select * into m from public.clinic_members where clinic_id=p_clinic and user_id=p_user for update;
 if not found then raise exception 'member_not_found';end if;
 select * into c from private.permission_catalog where code=p_code;
 if not found then raise exception 'unknown_permission';end if;
 if c.procedure_scoped<>(p_procedure is not null) then raise exception 'procedure_scope_required';end if;
 if p_procedure is not null and not exists(select 1 from private.procedure_types where id=p_procedure and clinic_id=p_clinic and active) then raise exception 'invalid_procedure_scope';end if;
 if c.requires_professional and not private.professional_current(p_clinic,p_user) then raise exception 'verified_professional_required';end if;
 if p_until is null or p_until<=clock_timestamp() then raise exception 'future_expiry_required';end if;
 if exists(select 1 from private.member_permission_grants g where g.clinic_id=p_clinic and g.user_id=p_user and g.member_since=m.created_at and g.code=p_code and g.procedure_id is not distinct from p_procedure and g.valid_until>clock_timestamp() and not exists(select 1 from private.permission_revocations r where r.grant_id=g.id)) then raise exception 'active_grant_already_exists';end if;
 insert into private.member_permission_grants(clinic_id,user_id,member_since,code,procedure_id,granted_by,valid_until,reason)
 values(p_clinic,p_user,m.created_at,p_code,p_procedure,auth.uid(),p_until,btrim(p_reason)) returning id into result;
 perform private.permission_event(p_clinic,'permission_granted',result,jsonb_build_object('code',p_code,'procedure_id',p_procedure));return result;
end$$;
create function public.permission_revoke(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare target uuid;begin
 select clinic_id into target from private.member_permission_grants where id=p_id;
 perform 1 from public.clinics where id=target for update;
 if not private.permission_admin(target) then raise exception 'admin_required';end if;
 insert into private.permission_revocations(grant_id,revoked_by,reason) values(p_id,auth.uid(),btrim(p_reason)) on conflict(grant_id) do nothing;
 if found then perform private.permission_event(target,'permission_revoked',p_id);end if;
end$$;
create function public.permission_responsible_propose(p_clinic uuid,p_user uuid,p_until timestamptz) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;begin
 perform 1 from public.clinics where id=p_clinic for update;
 if not private.permission_admin(p_clinic) then raise exception 'admin_required';end if;
 if not private.professional_current(p_clinic,p_user) then raise exception 'verified_professional_required';end if;
 if p_until is null or p_until<=clock_timestamp() then raise exception 'future_expiry_required';end if;
 update private.clinic_responsible_designations set revoked_at=clock_timestamp(),revoked_by=auth.uid() where clinic_id=p_clinic and revoked_at is null;
 insert into private.clinic_responsible_designations(clinic_id,user_id,member_since,proposed_by,valid_until) values(p_clinic,p_user,(select created_at from public.clinic_members where clinic_id=p_clinic and user_id=p_user),auth.uid(),p_until) returning id into result;
 perform private.permission_event(p_clinic,'responsible_proposed',result);return result;
end$$;
create function public.permission_responsible_respond(p_id uuid,p_accept boolean) returns void language plpgsql security definer set search_path='' as $$
declare d private.clinic_responsible_designations;begin
 select * into d from private.clinic_responsible_designations where id=p_id;
 perform 1 from public.clinics where id=d.clinic_id for update;
 select * into d from private.clinic_responsible_designations where id=p_id for update;
 if d.user_id is distinct from auth.uid() or not exists(select 1 from public.clinic_members m where m.clinic_id=d.clinic_id and m.user_id=d.user_id and m.created_at=d.member_since) or not private.professional_current(d.clinic_id,auth.uid()) or d.valid_until<=clock_timestamp() or d.revoked_at is not null then raise exception 'responsible_confirmation_required';end if;
 if p_accept is null then raise exception 'explicit_response_required';end if;
 if p_accept then update private.clinic_responsible_designations set accepted_at=coalesce(accepted_at,clock_timestamp()) where id=p_id;
 else update private.clinic_responsible_designations set revoked_at=clock_timestamp(),revoked_by=auth.uid() where id=p_id;end if;
 perform private.permission_event(d.clinic_id,case when p_accept then 'responsible_accepted' else 'responsible_declined' end,p_id);
end$$;
create function public.permission_responsible_revoke(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare target uuid;begin
 select clinic_id into target from private.clinic_responsible_designations where id=p_id;
 perform 1 from public.clinics where id=target for update;
 if not private.permission_admin(target) then raise exception 'admin_required';end if;
 update private.clinic_responsible_designations set revoked_at=clock_timestamp(),revoked_by=auth.uid() where id=p_id and revoked_at is null;
 if found then perform private.permission_event(target,'responsible_revoked',p_id);end if;
end$$;
-- First MVZ: privileged offline operation only, with explicit separate platform reviewer.
create function private.professional_record_external(p_version uuid,p_reviewer uuid,p_reviewed timestamptz,p_hash text,p_reference text,p_until timestamptz) returns uuid language plpgsql security definer set search_path='' as $$
declare subject uuid;result uuid;begin
 select p.user_id into subject from private.professional_profile_versions v join public.professional_profiles p on p.id=v.profile_id
 where v.id=p_version and length(btrim(v.license))>0 and not exists(select 1 from private.professional_profile_versions later where later.profile_id=v.profile_id and later.version>v.version);
 if subject is null then raise exception 'current_profile_with_license_required';end if;
 if subject=p_reviewer then raise exception 'self_review_forbidden';end if;
 if p_reviewed is null or p_reviewed>clock_timestamp() or p_until is null or p_until<=clock_timestamp() then raise exception 'invalid_review_dates';end if;
 if not exists(select 1 from private.platform_admins where user_id=p_reviewer and enabled) or exists(select 1 from public.clinic_members where user_id=p_reviewer) then raise exception 'separate_platform_reviewer_required';end if;
 insert into private.professional_verifications(user_id,profile_version_id,reviewer_id,reviewed_at,evidence_hash,evidence_reference,valid_until,origin)
 values(subject,p_version,p_reviewer,p_reviewed,p_hash,btrim(p_reference),p_until,'platform_external') returning id into result;
 insert into private.beta_audit(actor_id,action,entity_id) values(p_reviewer,'professional_external_review_recorded',result::text);return result;
end$$;
create function public.permission_professional_review(p_clinic uuid,p_version uuid,p_reviewed timestamptz,p_hash text,p_reference text,p_until timestamptz) returns uuid language plpgsql security definer set search_path='' as $$
declare subject uuid;result uuid;begin
 perform 1 from public.clinics where id=p_clinic for update;
 if not private.permission_responsible(p_clinic) then raise exception 'verified_responsible_required';end if;
 select p.user_id into subject from private.professional_profile_versions v join public.professional_profiles p on p.id=v.profile_id
 join public.clinic_members m on m.clinic_id=p.clinic_id and m.user_id=p.user_id
 where v.id=p_version and p.clinic_id=p_clinic and length(btrim(v.license))>0 and not exists(select 1 from private.professional_profile_versions later where later.profile_id=v.profile_id and later.version>v.version);
 if subject is null then raise exception 'current_profile_with_license_required';end if;
 if subject=auth.uid() then raise exception 'self_review_forbidden';end if;
 if p_reviewed is null or p_reviewed>clock_timestamp() or p_until is null or p_until<=clock_timestamp() then raise exception 'invalid_review_dates';end if;
 insert into private.professional_verifications(user_id,clinic_id,profile_version_id,reviewer_id,reviewed_at,evidence_hash,evidence_reference,valid_until,origin)
 values(subject,p_clinic,p_version,auth.uid(),p_reviewed,p_hash,btrim(p_reference),p_until,'clinic_responsible') returning id into result;
 perform private.permission_event(p_clinic,'professional_clinic_review_recorded',result);return result;
end$$;
create function public.permission_professional_revoke(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare v private.professional_verifications;begin
 select * into v from private.professional_verifications where id=p_id;
 if v.clinic_id is null then perform private.require_platform_admin();
 else
 perform 1 from public.clinics where id=v.clinic_id for update;
 if not private.permission_responsible(v.clinic_id) then raise exception 'verified_responsible_required';end if;end if;
 insert into private.professional_revocations(verification_id,revoked_by,reason) values(p_id,auth.uid(),btrim(p_reason)) on conflict(verification_id) do nothing;
 if found then
 if v.clinic_id is null then insert into private.beta_audit(actor_id,action,entity_id) values(auth.uid(),'professional_verification_revoked',p_id::text);
 else perform private.permission_event(v.clinic_id,'professional_verification_revoked',p_id);end if;end if;
end$$;
-- Metadata only. Evidence references/hashes restricted to reviewer and subject; no public URLs.
create function public.permission_professional_snapshot(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare manager boolean;begin
 if not private.has_clinic_role(p_clinic) then raise exception 'membership_required';end if;
 manager=private.permission_responsible(p_clinic);
 return jsonb_build_object('profiles',coalesce((select jsonb_agg(jsonb_build_object('user_id',p.user_id,'version_id',v.id,'name',v.name,'license',v.license))
 from public.professional_profiles p join lateral(select * from private.professional_profile_versions cv where cv.profile_id=p.id order by version desc limit 1) v on true
 where p.clinic_id=p_clinic and (manager or p.user_id=auth.uid())),'[]'),
 'verifications',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'user_id',v.user_id,'reviewer_id',v.reviewer_id,'reviewed_at',v.reviewed_at,'valid_until',v.valid_until,'origin',v.origin,
 'evidence_hash',v.evidence_hash,'evidence_reference',v.evidence_reference,'revoked',exists(select 1 from private.professional_revocations r where r.verification_id=v.id)))
 from private.professional_verifications v where (v.clinic_id=p_clinic or v.clinic_id is null) and (v.user_id=auth.uid() or (manager and v.clinic_id=p_clinic))),'[]'));
end$$;
-- Evidence and grants are append-only; changes use explicit revocation records.
create function private.permission_immutable() returns trigger language plpgsql set search_path='' as $$begin raise exception 'append_only_permission_record';end$$;
do $$declare t text;r record;begin
 foreach t in array array['professional_verifications','professional_revocations','member_permission_grants','permission_revocations'] loop
 execute format('create trigger permission_immutable before update or delete on private.%I for each row execute function private.permission_immutable()',t);
 end loop;
 for r in select p.oid::regprocedure as signature,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='public' and p.proname like 'permission_%') or (n.nspname='private' and (p.proname like 'permission_%' or p.proname in ('professional_current','professional_record_external'))) loop
 execute format('revoke all on function %s from public,anon,authenticated',r.signature);
 if r.nspname='public' then execute format('grant execute on function %s to authenticated',r.signature);end if;
 end loop;
end$$;
-- Integrate dormant beta guards for new private tables; no flag is enabled.
select private.beta_install_guards();
notify pgrst,'reload schema';
commit;
