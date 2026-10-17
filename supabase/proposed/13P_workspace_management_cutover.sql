-- Stage 2B.22: workspace management cutover after 13O.
-- Replaces visual admin authority in non-clinical management surfaces with explicit workspace.manage.
begin;

create or replace function private.workspace_management_authorized(p_clinic uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select p_user is not null
 and exists(select 1 from public.clinic_members m where m.clinic_id=p_clinic and m.user_id=p_user)
 and (
  exists(select 1 from public.account_workspaces w where w.clinic_id=p_clinic and w.kind='personal' and w.owner_id=p_user)
  or private.permission_effective(p_clinic,p_user,'workspace.manage') is not null
 );
$$;
revoke all on function private.workspace_management_authorized(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function public.workspace_management_status(p_clinic uuid)
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then
  raise exception 'current_member_required';
 end if;
 return private.workspace_management_authorized(p_clinic,auth.uid());
end$$;
revoke all on function public.workspace_management_status(uuid) from public,anon;
grant execute on function public.workspace_management_status(uuid) to authenticated;

create or replace function private.ai_key_allowed(p_connection uuid,p_user uuid,p_manage boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.ai_connections c
  where c.id=p_connection
   and (c.enabled or p_manage)
   and (
    (c.scope='personal' and c.owner_id=p_user)
    or (
     c.scope='clinic'
     and exists(select 1 from public.clinic_members m where m.clinic_id=c.clinic_id and m.user_id=p_user)
     and (not p_manage or private.workspace_management_authorized(c.clinic_id,p_user))
    )
   )
 );
$$;
revoke all on function private.ai_key_allowed(uuid,uuid,boolean) from public,anon,authenticated,service_role;

create or replace function public.ai_dashboard(p_clinic uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;
 return jsonb_build_object(
  'can_manage',private.workspace_management_authorized(p_clinic,auth.uid()),
  'connections',(select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('can_manage',private.ai_key_allowed(c.id,auth.uid(),true))),'[]') from public.ai_connections c where (c.owner_id=auth.uid() or c.clinic_id=p_clinic) and private.ai_key_allowed(c.id,auth.uid(),false)),
  'chats',(select coalesce(jsonb_agg(to_jsonb(c) order by created_at desc),'[]') from public.ai_chats c where c.clinic_id=p_clinic and private.ai_chat_allowed(c.id,auth.uid())),
  'daily_used',coalesce((select attempts from private.ai_daily_usage where clinic_id=p_clinic and day=(clock_timestamp() at time zone 'UTC')::date),0),
  'daily_limit',(private.plan_for(p_clinic)).ai_daily
 );
end$$;

create or replace function public.ai_key_store_server(
 p_user uuid,p_scope text,p_clinic uuid,p_provider text,p_cipher text,p_nonce text
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not exists(select 1 from auth.users where id=p_user and email_confirmed_at is not null) then raise exception 'verified_user_required';end if;
 if p_scope not in ('personal','clinic') then raise exception 'invalid_scope';end if;
 if p_scope='clinic' and not private.workspace_management_authorized(p_clinic,p_user) then raise exception 'workspace_manage_required';end if;
 if length(p_cipher) not between 20 and 8000 or length(p_nonce) not between 16 and 100 then raise exception 'cipher_required';end if;
 insert into public.ai_connections(provider,scope,owner_id,clinic_id,created_by)
 values(p_provider,p_scope,case when p_scope='personal' then p_user end,case when p_scope='clinic' then p_clinic end,p_user)
 returning id into v_id;
 insert into private.ai_credentials(connection_id,ciphertext,nonce) values(v_id,p_cipher,p_nonce);
 return v_id;
end$$;
revoke all on function public.ai_key_store_server(uuid,text,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.ai_key_store_server(uuid,text,uuid,text,text,text) to service_role;

create or replace function public.clinic_team_snapshot(target_clinic uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not private.workspace_management_authorized(target_clinic,auth.uid()) then raise exception 'workspace_manage_required';end if;
 return jsonb_build_object(
  'members',coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'email',u.email,'role',m.role) order by m.created_at,m.user_id)
    from public.clinic_members m join auth.users u on u.id=m.user_id where m.clinic_id=target_clinic),'[]'::jsonb),
  'invitations',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'email',i.email,'role',i.role,'expires_at',i.expires_at,'accepted_at',i.accepted_at,'revoked_at',i.revoked_at) order by i.created_at desc)
    from public.clinic_invitations i where i.clinic_id=target_clinic),'[]'::jsonb)
 );
end$$;

create or replace function public.create_clinic_invitation(target_clinic uuid,invite_email text,invite_role text)
returns text language plpgsql security definer set search_path='' as $$
declare token text;invite_id uuid;
begin
 if not private.workspace_management_authorized(target_clinic,auth.uid()) then raise exception 'workspace_manage_required';end if;
 if not private.team_plan(target_clinic) then raise exception 'clinic_plan_required';end if;
 token=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.clinic_invitations(clinic_id,email,role,token_hash,created_by)
 values(target_clinic,lower(btrim(invite_email)),invite_role,encode(extensions.digest(token,'sha256'),'hex'),auth.uid())
 returning id into invite_id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(target_clinic,auth.uid(),'invitation_created',invite_id::text,jsonb_build_object('role',invite_role));
 return token;
end$$;

create or replace function public.revoke_clinic_invitation(invitation_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
 select clinic_id into target from public.clinic_invitations where id=invitation_id;
 if target is null or not private.workspace_management_authorized(target,auth.uid()) then raise exception 'workspace_manage_required';end if;
 update public.clinic_invitations set revoked_at=clock_timestamp() where id=invitation_id and accepted_at is null;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(target,auth.uid(),'invitation_revoked',invitation_id::text);
end$$;

create or replace function public.remove_clinic_member(target_clinic uuid,target_user uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.clinics where id=target_clinic for update;
 if not private.workspace_management_authorized(target_clinic,auth.uid()) then raise exception 'workspace_manage_required';end if;
 delete from public.clinic_members where clinic_id=target_clinic and user_id=target_user;
 if not found then raise exception 'member_not_found';end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(target_clinic,auth.uid(),'member_removed',target_user::text);
end$$;

create or replace function public.set_clinic_member_role(target_clinic uuid,target_user uuid,new_role text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.clinics where id=target_clinic for update;
 if not private.workspace_management_authorized(target_clinic,auth.uid()) then raise exception 'workspace_manage_required';end if;
 update public.clinic_members set role=new_role where clinic_id=target_clinic and user_id=target_user;
 if not found then raise exception 'member_not_found';end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(target_clinic,auth.uid(),'member_role_changed',target_user::text,jsonb_build_object('role',new_role));
end$$;

create or replace function public.att_settings_save(p_clinic uuid,p_data jsonb) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.workspace_management_authorized(p_clinic,auth.uid()) then raise exception 'workspace_manage_required';end if;
 if not private.team_plan(p_clinic) then raise exception 'clinic_plan_required';end if;
 insert into public.attendance_settings(clinic_id,latitude,longitude,radius_m,max_accuracy_m,privacy_notice)
 values(p_clinic,(p_data->>'latitude')::float8,(p_data->>'longitude')::float8,(p_data->>'radius_m')::int,(p_data->>'max_accuracy_m')::int,p_data->>'privacy_notice')
 on conflict(clinic_id) do update set latitude=excluded.latitude,longitude=excluded.longitude,radius_m=excluded.radius_m,max_accuracy_m=excluded.max_accuracy_m,privacy_notice=excluded.privacy_notice,version=public.attendance_settings.version+1;
 insert into private.attendance_secrets(clinic_id) values(p_clinic) on conflict do nothing;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'attendance_settings_updated',p_clinic::text);
end$$;

create or replace function public.att_dashboard(p_clinic uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare manager boolean;
begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;
 manager=private.workspace_management_authorized(p_clinic,auth.uid());
 return jsonb_build_object(
  'can_manage',manager,
  'settings',(select to_jsonb(s) from public.attendance_settings s where clinic_id=p_clinic),
  'consented',exists(select 1 from public.attendance_consents c join public.attendance_settings s using(clinic_id) where c.clinic_id=p_clinic and c.user_id=auth.uid() and c.settings_version=s.version),
  'events',(select coalesce(jsonb_agg(to_jsonb(e)||jsonb_build_object('effective_at',coalesce((select c.corrected_at from public.attendance_corrections c where c.event_id=e.id order by c.created_at desc,c.id desc limit 1),e.server_at)) order by server_at desc),'[]') from public.attendance_events e where clinic_id=p_clinic and (user_id=auth.uid() or manager)),
  'corrections',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from public.attendance_corrections c join public.attendance_events e on e.id=c.event_id where e.clinic_id=p_clinic and (e.user_id=auth.uid() or manager))
 );
end$$;

create or replace function public.att_qr(p_clinic uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare bucket bigint;payload text;secret bytea;
begin
 if not private.workspace_management_authorized(p_clinic,auth.uid()) then raise exception 'workspace_manage_required';end if;
 select s.secret into secret from private.attendance_secrets s where clinic_id=p_clinic;
 if secret is null then raise exception 'attendance_settings_required';end if;
 bucket=floor(extract(epoch from clock_timestamp())/45);
 payload='vetdosis-att:1:'||p_clinic::text||':'||auth.uid()::text||':'||bucket::text;
 return jsonb_build_object('token',payload||':'||encode(extensions.hmac(payload,encode(secret,'hex'),'sha256'),'hex'),'expires_at',to_timestamp((bucket+1)*45),'server_at',clock_timestamp());
end$$;

create or replace function public.att_scan(p_clinic uuid,p_token text,p_latitude double precision,p_longitude double precision,p_accuracy double precision,p_operation text) returns uuid
language plpgsql security definer set search_path='' as $$
declare parts text[];payload text;s public.attendance_settings;v_secret bytea;v_id uuid;dist double precision;v_direction text;fp jsonb;bucket bigint;
begin
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for update;
 if not found then raise exception 'access_denied';end if;
 if not private.team_plan(p_clinic) then raise exception 'clinic_plan_required';end if;
 fp=jsonb_build_object('kind','attendance_scan','token_hash',encode(extensions.digest(p_token,'sha256'),'hex'));v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 parts=string_to_array(p_token,':');
 if cardinality(parts)<>6 or parts[1]<>'vetdosis-att' or parts[2]<>'1' or parts[3]<>p_clinic::text then raise exception 'invalid_qr';end if;
 if not private.workspace_management_authorized(p_clinic,parts[4]::uuid) then raise exception 'invalid_qr';end if;
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

create or replace function public.att_correct(p_clinic uuid,p_event uuid,p_at timestamptz,p_reason text,p_operation text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid;fp jsonb;
begin
 if not private.workspace_management_authorized(p_clinic,auth.uid()) then raise exception 'workspace_manage_required';end if;
 perform 1 from public.attendance_events where id=p_event and clinic_id=p_clinic for update;
 if not found then raise exception 'access_denied';end if;
 if p_at is null or p_at>clock_timestamp()+interval '1 day' then raise exception 'invalid_correction';end if;
 fp=jsonb_build_object('kind','attendance_correction','event',p_event,'at',p_at,'reason',p_reason);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.attendance_corrections(clinic_id,event_id,corrected_at,reason,created_by) values(p_clinic,p_event,p_at,p_reason,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'attendance_corrected',v_id::text);
 return v_id;
end$$;

create or replace function public.plan_dashboard(p_clinic uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.subscription_plans;manager boolean;
begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;
 manager=private.workspace_management_authorized(p_clinic,auth.uid());
 p=private.plan_for(p_clinic);
 return jsonb_build_object(
  'can_manage',manager,
  'workspace',(select to_jsonb(w) from public.account_workspaces w where clinic_id=p_clinic),
  'effective',to_jsonb(p),
  'plans',(select jsonb_agg(to_jsonb(x) order by monthly_cents) from public.subscription_plans x),
  'grants',(select coalesce(jsonb_agg(to_jsonb(g)||jsonb_build_object('revoked',exists(select 1 from public.subscription_revocations r where r.grant_id=g.id))),'[]') from public.subscription_grants g where clinic_id=p_clinic),
  'requests',(select coalesce(jsonb_agg(to_jsonb(r) order by created_at desc),'[]') from public.subscription_requests r where clinic_id=p_clinic and (requested_by=auth.uid() or manager)),
  'usage_bytes',(select bytes::text from private.workspace_usage where clinic_id=p_clinic),
  'patients',(select count(*) from public.vet_patients where clinic_id=p_clinic),
  'reward_points',(select coalesce(sum(points),0)::text from public.reward_credits where user_id=auth.uid()),
  'billing_enabled',exists(select 1 from public.subscription_plans where published and code<>'free'),
  'reward_enabled',coalesce((select enabled from private.reward_policy where id=true),false)
 );
end$$;

create or replace function public.plan_request(p_clinic uuid,p_code text,p_period text,p_operation text) returns uuid
language plpgsql security definer set search_path='' as $$
declare p public.subscription_plans;v_id uuid;fp jsonb;
begin
 if not private.workspace_management_authorized(p_clinic,auth.uid()) then raise exception 'workspace_manage_required';end if;
 select * into p from public.subscription_plans where code=p_code and code<>'free';if not found then raise exception 'invalid_plan';end if;
 if private.personal_clinic(p_clinic)<>(p_code='individual') then raise exception 'plan_workspace_mismatch';end if;
 if p_period not in ('monthly','annual') then raise exception 'invalid_period';end if;
 fp=jsonb_build_object('kind','plan_request','code',p_code,'period',p_period,'version',p.version);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.subscription_requests(clinic_id,requested_by,plan_code,period,price_cents,plan_version)
 values(p_clinic,auth.uid(),p_code,p_period,case when p_period='annual' then p.annual_cents else p.monthly_cents end,p.version)
 returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 return v_id;
end$$;

create or replace function public.billing_request_read(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r public.subscription_requests;
begin
 select * into r from public.subscription_requests where id=p_id;
 if not found or r.requested_by<>auth.uid() or not private.workspace_management_authorized(r.clinic_id,auth.uid()) then raise exception 'owner_required';end if;
 if not exists(select 1 from public.subscription_plans where code=r.plan_code and published) then raise exception 'pricing_not_published';end if;
 if exists(select 1 from public.subscription_grants g where g.clinic_id=r.clinic_id and source='subscription' and ends_at>clock_timestamp() and not exists(select 1 from public.subscription_revocations x where x.grant_id=g.id)) then raise exception 'subscription_already_active_manage_provider';end if;
 return to_jsonb(r)||jsonb_build_object('trial_until',(select max(ends_at) from public.subscription_grants g where g.clinic_id=r.clinic_id and g.plan_code=r.plan_code and source<>'subscription' and ends_at>clock_timestamp() and not exists(select 1 from public.subscription_revocations x where x.grant_id=g.id)));
end$$;

create or replace function public.reward_redeem(p_clinic uuid,p_operation text) returns uuid
language plpgsql security definer set search_path='' as $$
declare policy private.reward_policy;v_id uuid;fp jsonb;code text;benefit_start timestamptz;
begin
 if not private.workspace_management_authorized(p_clinic,auth.uid()) then raise exception 'workspace_manage_required';end if;
 select * into policy from private.reward_policy where id=true;if not policy.enabled then raise exception 'reward_program_not_active';end if;
 fp=jsonb_build_object('kind','reward_redeem','points',policy.points,'days',policy.days);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':rewards',0));
 if (select coalesce(sum(points),0) from public.reward_credits where user_id=auth.uid())<policy.points then raise exception 'insufficient_reward_points';end if;
 if exists(select 1 from public.subscription_grants g where g.clinic_id=p_clinic and g.source='subscription' and g.ends_at>clock_timestamp() and not exists(select 1 from public.subscription_revocations r where r.grant_id=g.id)) then raise exception 'active_subscription_rewards_pending';end if;
 code=case when private.personal_clinic(p_clinic) then 'individual' else 'clinic' end;
 select greatest(clock_timestamp(),coalesce(max(ends_at),clock_timestamp())) into benefit_start from public.subscription_grants g where g.clinic_id=p_clinic and plan_code=code and not exists(select 1 from public.subscription_revocations r where r.grant_id=g.id);
 insert into public.reward_credits(user_id,points,reference,reason) values(auth.uid(),-policy.points,'redeem:'||auth.uid()::text||':'||p_operation,'Canje de beneficio temporal');
 insert into public.subscription_grants(clinic_id,plan_code,source,starts_at,ends_at,reference) values(p_clinic,code,'reward',benefit_start,benefit_start+make_interval(days=>policy.days),'redeem:'||auth.uid()::text||':'||p_operation) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 return v_id;
end$$;

create or replace function public.plan_payment_history(p_clinic uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not private.workspace_management_authorized(p_clinic,auth.uid()) then raise exception 'payment_history_denied';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'amount_cents',amount_cents,'currency',currency,'provider',provider,'period_start',period_start,'period_end',period_end) order by period_start desc) from public.subscription_payments where clinic_id=p_clinic),'[]');
end$$;

revoke all on function public.clinic_team_snapshot(uuid),public.create_clinic_invitation(uuid,text,text),public.revoke_clinic_invitation(uuid),public.remove_clinic_member(uuid,uuid),public.set_clinic_member_role(uuid,uuid),public.att_settings_save(uuid,jsonb),public.att_dashboard(uuid),public.att_qr(uuid),public.att_scan(uuid,text,double precision,double precision,double precision,text),public.att_correct(uuid,uuid,timestamptz,text,text),public.plan_dashboard(uuid),public.plan_request(uuid,text,text,text),public.billing_request_read(uuid),public.reward_redeem(uuid,text),public.plan_payment_history(uuid) from public,anon;
grant execute on function public.clinic_team_snapshot(uuid),public.create_clinic_invitation(uuid,text,text),public.revoke_clinic_invitation(uuid),public.remove_clinic_member(uuid,uuid),public.set_clinic_member_role(uuid,uuid),public.att_settings_save(uuid,jsonb),public.att_dashboard(uuid),public.att_qr(uuid),public.att_scan(uuid,text,double precision,double precision,double precision,text),public.att_correct(uuid,uuid,timestamptz,text,text),public.plan_dashboard(uuid),public.plan_request(uuid,text,text,text),public.billing_request_read(uuid),public.reward_redeem(uuid,text),public.plan_payment_history(uuid) to authenticated;

notify pgrst,'reload schema';
commit;
