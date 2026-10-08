-- M10: signed 45-second admin QR; location used only on check-in.
begin;
create table private.attendance_secrets(clinic_id uuid primary key references public.clinics(id),secret bytea not null default extensions.gen_random_bytes(32));
revoke all on private.attendance_secrets from public,anon,authenticated;
create table public.attendance_settings(clinic_id uuid primary key references public.clinics(id),latitude double precision not null check(latitude between -90 and 90),longitude double precision not null check(longitude between -180 and 180),radius_m integer not null check(radius_m between 10 and 5000),max_accuracy_m integer not null check(max_accuracy_m between 5 and 200),privacy_notice text not null check(length(privacy_notice) between 10 and 10000),version integer not null default 1);
create table public.attendance_consents(clinic_id uuid not null,user_id uuid not null,settings_version integer not null,consented_at timestamptz not null default clock_timestamp(),primary key(clinic_id,user_id),foreign key(clinic_id,user_id) references public.clinic_members(clinic_id,user_id));
create table public.attendance_events(id uuid primary key default gen_random_uuid(),clinic_id uuid not null,user_id uuid not null,direction text not null check(direction in ('entrada','salida')),server_at timestamptz not null default clock_timestamp(),distance_m double precision not null,accuracy_m double precision not null,qr_bucket bigint not null,unique(clinic_id,user_id,qr_bucket),foreign key(clinic_id,user_id) references public.clinic_members(clinic_id,user_id));
create table public.attendance_corrections(id uuid primary key default gen_random_uuid(),clinic_id uuid not null,event_id uuid not null references public.attendance_events(id),corrected_at timestamptz not null,reason text not null check(length(btrim(reason)) between 5 and 1000),created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp());
create trigger attendance_immutable before update or delete on public.attendance_events for each row execute function private.inv_history_guard();
create trigger attendance_correction_immutable before update or delete on public.attendance_corrections for each row execute function private.inv_history_guard();
do $$declare t text;begin foreach t in array array['attendance_settings','attendance_consents','attendance_events','attendance_corrections'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);end loop;end$$;
create function public.att_settings_save(p_clinic uuid,p_data jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 insert into public.attendance_settings(clinic_id,latitude,longitude,radius_m,max_accuracy_m,privacy_notice) values(p_clinic,(p_data->>'latitude')::float8,(p_data->>'longitude')::float8,(p_data->>'radius_m')::int,(p_data->>'max_accuracy_m')::int,p_data->>'privacy_notice') on conflict(clinic_id) do update set latitude=excluded.latitude,longitude=excluded.longitude,radius_m=excluded.radius_m,max_accuracy_m=excluded.max_accuracy_m,privacy_notice=excluded.privacy_notice,version=public.attendance_settings.version+1;
 insert into private.attendance_secrets(clinic_id) values(p_clinic) on conflict do nothing;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'attendance_settings_updated',p_clinic::text);
end$$;
create function public.att_dashboard(p_clinic uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;
 return jsonb_build_object('settings',(select to_jsonb(s) from public.attendance_settings s where clinic_id=p_clinic),'consented',exists(select 1 from public.attendance_consents c join public.attendance_settings s using(clinic_id) where c.clinic_id=p_clinic and c.user_id=auth.uid() and c.settings_version=s.version),
 'events',(select coalesce(jsonb_agg(to_jsonb(e)||jsonb_build_object('effective_at',coalesce((select c.corrected_at from public.attendance_corrections c where c.event_id=e.id order by c.created_at desc,c.id desc limit 1),e.server_at)) order by server_at desc),'[]') from public.attendance_events e where clinic_id=p_clinic and (user_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin']))),
 'corrections',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from public.attendance_corrections c join public.attendance_events e on e.id=c.event_id where e.clinic_id=p_clinic and (e.user_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin']))));
end$$;
create function public.att_consent(p_clinic uuid,p_version integer,p_accept boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;
 perform 1 from public.attendance_settings where clinic_id=p_clinic and version=p_version for share;
 if not found then raise exception 'version_conflict';end if;
 if p_accept then insert into public.attendance_consents(clinic_id,user_id,settings_version) values(p_clinic,auth.uid(),p_version) on conflict(clinic_id,user_id) do update set settings_version=excluded.settings_version,consented_at=clock_timestamp();
 else delete from public.attendance_consents where clinic_id=p_clinic and user_id=auth.uid();end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'attendance_consent',auth.uid()::text,jsonb_build_object('accepted',p_accept,'version',p_version));
end$$;
create function public.att_qr(p_clinic uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare bucket bigint;payload text;secret bytea;
begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 select s.secret into secret from private.attendance_secrets s where clinic_id=p_clinic;
 if secret is null then raise exception 'attendance_settings_required';end if;
 bucket=floor(extract(epoch from clock_timestamp())/45);
 payload='vetdosis-att:1:'||p_clinic::text||':'||auth.uid()::text||':'||bucket::text;
 return jsonb_build_object('token',payload||':'||encode(extensions.hmac(payload,encode(secret,'hex'),'sha256'),'hex'),'expires_at',to_timestamp((bucket+1)*45),'server_at',clock_timestamp());
end$$;
create function public.att_scan(p_clinic uuid,p_token text,p_latitude double precision,p_longitude double precision,p_accuracy double precision,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare parts text[];payload text;s public.attendance_settings;v_secret bytea;v_id uuid;dist double precision;v_direction text;fp jsonb;bucket bigint;
begin
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for update;
 if not found then raise exception 'access_denied';end if;
 fp=jsonb_build_object('kind','attendance_scan','token_hash',encode(extensions.digest(p_token,'sha256'),'hex'));v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 parts=string_to_array(p_token,':');
 if cardinality(parts)<>6 or parts[1]<>'vetdosis-att' or parts[2]<>'1' or parts[3]<>p_clinic::text then raise exception 'invalid_qr';end if;
 if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=parts[4]::uuid and role='admin') then raise exception 'invalid_qr';end if;
 bucket=parts[5]::bigint;
 if bucket<>floor(extract(epoch from clock_timestamp())/45) then raise exception 'expired_qr';end if;
 select secret into v_secret from private.attendance_secrets where clinic_id=p_clinic;
 payload=array_to_string(parts[1:5],':');
 if v_secret is null or parts[6]<>encode(extensions.hmac(payload,encode(v_secret,'hex'),'sha256'),'hex') then raise exception 'invalid_qr';end if;
 select * into s from public.attendance_settings where clinic_id=p_clinic for share;
 if not found then raise exception 'attendance_settings_required';end if;
 if not exists(select 1 from public.attendance_consents where clinic_id=p_clinic and user_id=auth.uid() and settings_version=s.version) then raise exception 'consent_required';end if;
 if p_latitude is null or p_longitude is null or p_accuracy is null or not (p_latitude between -90 and 90 and p_longitude between -180 and 180 and p_accuracy between 0 and s.max_accuracy_m) then raise exception 'invalid_location';end if;
 dist=6371000*2*asin(sqrt(least(1,greatest(0,power(sin(radians(p_latitude-s.latitude)/2),2)+cos(radians(s.latitude))*cos(radians(p_latitude))*power(sin(radians(p_longitude-s.longitude)/2),2)))));
 if dist>s.radius_m then raise exception 'outside_radius';end if;
 select case when direction='entrada' then 'salida' else 'entrada' end into v_direction from public.attendance_events where clinic_id=p_clinic and user_id=auth.uid() order by server_at desc,id desc limit 1;
 insert into public.attendance_events(clinic_id,user_id,direction,distance_m,accuracy_m,qr_bucket) values(p_clinic,auth.uid(),coalesce(v_direction,'entrada'),dist,p_accuracy,bucket) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'attendance_scanned',v_id::text);
 return v_id;
end$$;
create function public.att_correct(p_clinic uuid,p_event uuid,p_at timestamptz,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;fp jsonb;
begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 perform 1 from public.attendance_events where id=p_event and clinic_id=p_clinic for update;
 if not found then raise exception 'access_denied';end if;
 if p_at is null or p_at>clock_timestamp()+interval '1 day' then raise exception 'invalid_correction';end if;
 fp=jsonb_build_object('kind','attendance_correction','event',p_event,'at',p_at,'reason',p_reason);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.attendance_corrections(clinic_id,event_id,corrected_at,reason,created_by) values(p_clinic,p_event,p_at,p_reason,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'attendance_corrected',v_id::text);
 return v_id;
end$$;
revoke all on function public.att_settings_save(uuid,jsonb),public.att_dashboard(uuid),public.att_consent(uuid,integer,boolean),public.att_qr(uuid),public.att_scan(uuid,text,double precision,double precision,double precision,text),public.att_correct(uuid,uuid,timestamptz,text,text) from public,anon;
grant execute on function public.att_settings_save(uuid,jsonb),public.att_dashboard(uuid),public.att_consent(uuid,integer,boolean),public.att_qr(uuid),public.att_scan(uuid,text,double precision,double precision,double precision,text),public.att_correct(uuid,uuid,timestamptz,text,text) to authenticated;
commit;
