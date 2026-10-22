-- Isolated endpoint contract fixture. Does not certify the remote RLS cutover.
create schema private;
create schema auth;
do $$begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon;end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated;end if;
end$$;
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create table private.test_grants(clinic_id uuid,user_id uuid,code text);
create function private.permission_effective(c uuid,u uuid,k text) returns uuid language sql stable as $$
 select clinic_id from private.test_grants where clinic_id=c and user_id=u and code=k limit 1 $$;
create function private.permission_require(c uuid,k text) returns uuid language plpgsql as $$begin
 if private.permission_effective(c,auth.uid(),k) is null then raise exception 'explicit_permission_required';end if;return c;end$$;
create table public.inventory_clinic_settings(clinic_id uuid,timezone text);
create table public.vet_patients(clinic_id uuid,id uuid);
create table public.hospital_stays(id uuid,clinic_id uuid,patient_id uuid,cage text,admitted_at timestamptz,discharged_at timestamptz);
create table public.staff_display_names(clinic_id uuid,user_id uuid,name text);
create table public.clinic_appointments(id uuid,clinic_id uuid,patient_id uuid,professional_id uuid,kind text,state text,starts_at timestamptz,notes text);
\ir ../adaptations/patient_activity_snapshot_v1.sql
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
insert into private.test_grants values
 ('10000000-0000-0000-0000-000000000001',auth.uid(),'patient.read'),
 ('10000000-0000-0000-0000-000000000001',auth.uid(),'hospital.read'),
 ('10000000-0000-0000-0000-000000000001',auth.uid(),'appointment.read');
insert into public.inventory_clinic_settings values ('10000000-0000-0000-0000-000000000001','Pacific/Kiritimati');
insert into public.vet_patients values
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002');
insert into public.hospital_stays values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','A',now()-interval '3 days',null),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','B',now(),null),
 ('30000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','C',now(),now());
insert into public.clinic_appointments
select gen_random_uuid(),'10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',auth.uid(),kind,state,now()-interval '2 days','Synthetic'
from (values ('consulta','en_atencion'),('estetica','en_atencion'),('estetica','listo'),('consulta','agendado'),('estetica','entregado'),('consulta','cancelado')) x(kind,state);
insert into public.clinic_appointments values
 (gen_random_uuid(),'10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',auth.uid(),'consulta','en_atencion',now()+interval '3 days','Future'),
 (gen_random_uuid(),'10000000-0000-0000-0000-000000000001',null,auth.uid(),'consulta','en_atencion',now(),'Unlinked');
set role authenticated;
do $$declare r jsonb;begin
 r=public.patient_activity_snapshot('10000000-0000-0000-0000-000000000001');
 if jsonb_array_length(r->'items')<>4 then raise exception 'wrong_active_rows';end if;
 if r->>'day'<>to_char(statement_timestamp() at time zone 'Pacific/Kiritimati','YYYY-MM-DD') then raise exception 'device_or_utc_day_used';end if;
 if (select count(distinct j->>'patient_id') from jsonb_array_elements(r->'items') j)<>1 then raise exception 'cross_clinic_or_unlinked';end if;
 begin
   perform public.patient_activity_snapshot('10000000-0000-0000-0000-000000000002');
   raise exception 'test_expected_denial';
 exception when raise_exception then if sqlerrm<>'explicit_permission_required' then raise;end if;end;
end$$;
reset role;
delete from private.test_grants where code='hospital.read';
set role authenticated;
do $$declare r jsonb;begin
 r=public.patient_activity_snapshot('10000000-0000-0000-0000-000000000001');
 if r->'hospital_allowed'<>'false'::jsonb or jsonb_array_length(r->'items')<>3 then raise exception 'revocation_leak';end if;
end$$;
reset role;
delete from private.test_grants where code='appointment.read';
set role authenticated;
do $$declare r jsonb;begin
 r=public.patient_activity_snapshot('10000000-0000-0000-0000-000000000001');
 if r->'appointments_allowed'<>'false'::jsonb or jsonb_array_length(r->'items')<>0 then raise exception 'appointment_revocation_leak';end if;
end$$;
reset role;
do $$begin
 if has_function_privilege('anon','public.patient_activity_snapshot(uuid)','execute') then raise exception 'anonymous_access';end if;
end$$;
