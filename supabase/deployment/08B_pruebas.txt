-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Después de etapas 1-7.
-- Ejecutar 08A y después 08B. Conserva registros existentes.
-- Apply once after M10 and existing_appointments_extension.sql.
-- Historic records reference account/clinic identity, not an active membership.
begin;
do $$declare t text; col text; fk record; begin
 foreach t in array array['clinic_appointments','clinic_tasks','staff_medical_profiles','clinic_service_acts','attendance_consents','attendance_events'] loop
 col := case when t in ('clinic_appointments','clinic_service_acts') then 'professional_id' when t='clinic_tasks' then 'assigned_to' else 'user_id' end;
 for fk in select conname from pg_catalog.pg_constraint where conrelid=to_regclass('public.'||t) and confrelid='public.clinic_members'::regclass and contype='f' loop
 execute format('alter table public.%I drop constraint %I',t,fk.conname);
 end loop;
 execute format('alter table public.%I add constraint %I foreign key(clinic_id) references public.clinics(id)',t,t||'_history_clinic');
 execute format('alter table public.%I add constraint %I foreign key(%I) references auth.users(id)',t,t||'_history_user',col);
 end loop;
end $$;
create or replace function public.ops_medical(p_clinic uuid,p_details jsonb default null,p_consent boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for share;
 if not found then raise exception 'access_denied';end if;
 if p_details is not null then
 if not p_consent then raise exception 'consent_required';end if;
 if p_details='{}'::jsonb then delete from public.staff_medical_profiles where clinic_id=p_clinic and user_id=auth.uid();
 else insert into public.staff_medical_profiles(clinic_id,user_id,details) values(p_clinic,auth.uid(),p_details) on conflict(clinic_id,user_id) do update set details=excluded.details,updated_at=clock_timestamp();end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'staff_medical_updated',auth.uid()::text);
 end if;
 return (select coalesce(jsonb_agg(to_jsonb(m)),'[]') from public.staff_medical_profiles m where clinic_id=p_clinic and (user_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin'])));
end$$;
create or replace function public.att_consent(p_clinic uuid,p_version integer,p_accept boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for share;
 if not found then raise exception 'access_denied';end if;
 perform 1 from public.attendance_settings where clinic_id=p_clinic and version=p_version for share;
 if not found then raise exception 'version_conflict';end if;
 if p_accept then insert into public.attendance_consents(clinic_id,user_id,settings_version) values(p_clinic,auth.uid(),p_version) on conflict(clinic_id,user_id) do update set settings_version=excluded.settings_version,consented_at=clock_timestamp();
 else delete from public.attendance_consents where clinic_id=p_clinic and user_id=auth.uid();end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'attendance_consent',auth.uid()::text,jsonb_build_object('accepted',p_accept,'version',p_version));
end$$;
-- RPCs still check current clinic membership for each new operation.
commit;

notify pgrst, 'reload schema';
select '08B COMPLETADO: historial conservado al retirar integrantes' as resultado;
-- FIN COMPLETO 08B
