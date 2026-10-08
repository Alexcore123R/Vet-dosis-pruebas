-- M13: draft MXN pricing, scoped entitlements and standalone personal workspaces.
-- Apply once after M9-M11/payment references. No processor or charges activated.
begin;
create table public.subscription_plans(code text primary key,name text not null,monthly_cents bigint not null check(monthly_cents>=0),annual_cents bigint not null check(annual_cents>=0),patient_limit integer not null check(patient_limit>0),storage_bytes bigint not null check(storage_bytes>0),ai_daily integer not null check(ai_daily>=0),team boolean not null,version integer not null default 1,published boolean not null default false);
insert into public.subscription_plans values
 ('free','Gratis',0,0,50,262144000,5,false,1,false),
 ('individual','Individual',19900,199000,5000,2147483648,200,false,1,false),
 ('clinic','Clínica',79900,799000,50000,10737418240,1000,true,1,false);
create table public.account_workspaces(clinic_id uuid primary key references public.clinics(id),kind text not null check(kind in ('personal','clinic')),owner_id uuid references auth.users(id),created_at timestamptz not null default clock_timestamp(),check((kind='personal')=(owner_id is not null)));
create unique index personal_workspace_owner on public.account_workspaces(owner_id) where kind='personal';
insert into public.account_workspaces(clinic_id,kind) select id,'clinic' from public.clinics;
create table public.subscription_grants(id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),plan_code text not null references public.subscription_plans(code),source text not null check(source in ('subscription','beta','gift','reward','migration')),starts_at timestamptz not null,ends_at timestamptz not null,reference text not null unique,created_at timestamptz not null default clock_timestamp(),check(ends_at>starts_at));
create table public.subscription_revocations(id uuid primary key default gen_random_uuid(),grant_id uuid not null unique references public.subscription_grants(id),reason text not null check(length(btrim(reason)) between 5 and 1000),created_at timestamptz not null default clock_timestamp());
-- Existing clinics keep a documented 90-day migration grace, not a paid subscription.
insert into public.subscription_grants(clinic_id,plan_code,source,starts_at,ends_at,reference) select id,'clinic','migration',clock_timestamp(),clock_timestamp()+interval '90 days','migration:'||id::text from public.clinics;
create table public.subscription_requests(id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),requested_by uuid not null references auth.users(id),plan_code text not null references public.subscription_plans(code),period text not null check(period in ('monthly','annual')),price_cents bigint not null,plan_version integer not null,created_at timestamptz not null default clock_timestamp());
create table public.reward_credits(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),points integer not null check(points<>0),reference text not null unique,reason text not null,created_at timestamptz not null default clock_timestamp());
create table private.workspace_usage(clinic_id uuid primary key references public.clinics(id),bytes bigint not null default 0 check(bytes>=0));
revoke all on private.workspace_usage from public,anon,authenticated;
create function private.plan_for(p_clinic uuid) returns public.subscription_plans language sql stable security definer set search_path='' as $$
 select p from public.subscription_plans p where p.code=coalesce((select g.plan_code from public.subscription_grants g where g.clinic_id=$1 and g.starts_at<=clock_timestamp() and g.ends_at>clock_timestamp() and not exists(select 1 from public.subscription_revocations r where r.grant_id=g.id) order by (select storage_bytes from public.subscription_plans where code=g.plan_code) desc,g.created_at desc limit 1),'free');
$$;
revoke all on function private.plan_for(uuid) from public,anon,authenticated;
create function private.personal_clinic(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.account_workspaces where clinic_id=$1 and kind='personal');$$;
create function private.team_plan(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$select not private.personal_clinic($1) and (private.plan_for($1)).team;$$;
revoke all on function private.personal_clinic(uuid),private.team_plan(uuid) from public,anon,authenticated;
create function private.workspace_created() returns trigger language plpgsql security definer set search_path='' as $$begin insert into public.account_workspaces(clinic_id,kind) values(new.id,'clinic');insert into private.workspace_usage(clinic_id) values(new.id);return new;end$$;
create trigger workspace_created after insert on public.clinics for each row execute function private.workspace_created();
insert into private.workspace_usage(clinic_id) select id from public.clinics;
create function public.personal_workspace_create() returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':personal',0));
 select clinic_id into v_id from public.account_workspaces where owner_id=auth.uid() and kind='personal';if v_id is not null then return v_id;end if;
 v_id=public.create_clinic('Mi espacio personal');
 update public.account_workspaces set kind='personal',owner_id=auth.uid() where clinic_id=v_id;
 return v_id;
end$$;
-- Buying benefits never grants role/professional authority. Personal scope has one member.
create function private.personal_members_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if private.personal_clinic(new.clinic_id) and not exists(select 1 from public.account_workspaces where clinic_id=new.clinic_id and owner_id=new.user_id) then raise exception 'personal_workspace_cannot_share';end if;return new;
end$$;
create trigger personal_members_guard before insert or update on public.clinic_members for each row execute function private.personal_members_guard();
alter function public.create_clinic_invitation(uuid,text,text) rename to create_clinic_invitation_before_plans;
revoke all on function public.create_clinic_invitation_before_plans(uuid,text,text) from public,anon,authenticated;
create function public.create_clinic_invitation(target_clinic uuid,invite_email text,invite_role text) returns text language plpgsql security definer set search_path='' as $$begin
 if not private.has_clinic_role(target_clinic,array['admin']) then raise exception 'admin_required';end if;
 if not private.team_plan(target_clinic) then raise exception 'clinic_plan_required';end if;
 return public.create_clinic_invitation_before_plans(target_clinic,invite_email,invite_role);
end$$;
-- Block personal team features on the server, not just in the menu.
alter function public.ops_write(uuid,text,jsonb,text) rename to ops_write_before_plans;
revoke all on function public.ops_write_before_plans(uuid,text,jsonb,text) from public,anon,authenticated;
create function public.ops_write(p_clinic uuid,p_action text,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;
 if p_action in ('task','task_complete','message') and not private.team_plan(p_clinic) then raise exception 'clinic_plan_required';end if;
 return public.ops_write_before_plans(p_clinic,p_action,p_data,p_operation);
end$$;
alter function public.att_settings_save(uuid,jsonb) rename to att_settings_save_before_plans;
revoke all on function public.att_settings_save_before_plans(uuid,jsonb) from public,anon,authenticated;
create function public.att_settings_save(p_clinic uuid,p_data jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 if not private.team_plan(p_clinic) then raise exception 'clinic_plan_required';end if;
 perform public.att_settings_save_before_plans(p_clinic,p_data);
end$$;
create function public.plan_dashboard(p_clinic uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare p public.subscription_plans;begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;p=private.plan_for(p_clinic);
 return jsonb_build_object('workspace',(select to_jsonb(w) from public.account_workspaces w where clinic_id=p_clinic),'effective',to_jsonb(p),'plans',(select jsonb_agg(to_jsonb(x) order by monthly_cents) from public.subscription_plans x),'grants',(select coalesce(jsonb_agg(to_jsonb(g)||jsonb_build_object('revoked',exists(select 1 from public.subscription_revocations r where r.grant_id=g.id))),'[]') from public.subscription_grants g where clinic_id=p_clinic),'requests',(select coalesce(jsonb_agg(to_jsonb(r) order by created_at desc),'[]') from public.subscription_requests r where clinic_id=p_clinic and (requested_by=auth.uid() or private.has_clinic_role(p_clinic,array['admin']))),'usage_bytes',(select bytes::text from private.workspace_usage where clinic_id=p_clinic),'patients',(select count(*) from public.vet_patients where clinic_id=p_clinic),'reward_points',(select coalesce(sum(points),0)::text from public.reward_credits where user_id=auth.uid()),'billing_enabled',exists(select 1 from public.subscription_plans where published and code<>'free'),'reward_enabled',coalesce((select enabled from private.reward_policy where id=true),false));
end$$;
create function public.plan_request(p_clinic uuid,p_code text,p_period text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$declare p public.subscription_plans;v_id uuid;fp jsonb;begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 select * into p from public.subscription_plans where code=p_code and code<>'free';if not found then raise exception 'invalid_plan';end if;
 if private.personal_clinic(p_clinic)<> (p_code='individual') then raise exception 'plan_workspace_mismatch';end if;
 if p_period not in ('monthly','annual') then raise exception 'invalid_period';end if;
 fp=jsonb_build_object('kind','plan_request','code',p_code,'period',p_period,'version',p.version);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.subscription_requests(clinic_id,requested_by,plan_code,period,price_cents,plan_version) values(p_clinic,auth.uid(),p_code,p_period,case when p_period='annual' then p.annual_cents else p.monthly_cents end,p.version) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);return v_id;
end$$;
-- Server-only admin/billing functions. A clinic admin is NOT a global operator.
create function public.plan_grant_server(p_clinic uuid,p_code text,p_source text,p_start timestamptz,p_end timestamptz,p_reference text) returns uuid language plpgsql security definer set search_path='' as $$declare v_id uuid;begin
 if p_source='subscription' then raise exception 'verified_payment_adapter_required';end if;
 if not exists(select 1 from public.account_workspaces where clinic_id=p_clinic and ((kind='personal' and p_code='individual') or (kind='clinic' and p_code='clinic'))) then raise exception 'plan_workspace_mismatch';end if;
 insert into public.subscription_grants(clinic_id,plan_code,source,starts_at,ends_at,reference) values(p_clinic,p_code,p_source,p_start,p_end,p_reference) on conflict(reference) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.subscription_grants where reference=p_reference and clinic_id=p_clinic and plan_code=p_code and source=p_source and starts_at=p_start and ends_at=p_end;if v_id is null then raise exception 'grant_reference_conflict';end if;end if;
 return v_id;
end$$;
create function public.plan_revoke_server(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$begin insert into public.subscription_revocations(grant_id,reason) values(p_id,p_reason);end$$;
create function public.reward_credit_server(p_user uuid,p_points integer,p_reference text,p_reason text) returns void language plpgsql security definer set search_path='' as $$begin insert into public.reward_credits(user_id,points,reference,reason) values(p_user,p_points,p_reference,p_reason);end$$;
-- Quotas are serialized per workspace; over-quota never deletes existing records.
create function private.plan_patient_guard() returns trigger language plpgsql security definer set search_path='' as $$declare p public.subscription_plans;begin
 perform 1 from private.workspace_usage where clinic_id=new.clinic_id for update;p=private.plan_for(new.clinic_id);
 if (select count(*) from public.vet_patients where clinic_id=new.clinic_id)>=p.patient_limit then raise exception 'patient_plan_limit';end if;return new;
end$$;
create trigger plan_patient_guard before insert on public.vet_patients for each row execute function private.plan_patient_guard();
-- Budget is conservative JSON size for records, plus 4MB reserved per inventory photo.
create function private.plan_record_budget() returns trigger language plpgsql security definer set search_path='' as $$declare scope uuid;delta bigint;used bigint;limit_bytes bigint;begin
 scope=case when tg_op='DELETE' then old.clinic_id else new.clinic_id end;
 delta=case when tg_op='DELETE' then -octet_length(to_jsonb(old)::text) when tg_op='UPDATE' then octet_length(to_jsonb(new)::text)-octet_length(to_jsonb(old)::text) else octet_length(to_jsonb(new)::text) end;
 select bytes into used from private.workspace_usage where clinic_id=scope for update;limit_bytes=(private.plan_for(scope)).storage_bytes;
 if delta>0 and used+delta>limit_bytes then raise exception 'storage_plan_limit';end if;
 update private.workspace_usage set bytes=greatest(0,bytes+delta) where clinic_id=scope;
 if tg_op='DELETE' then return old;end if;return new;
end$$;
do $$declare t text;begin
 foreach t in array array['vet_owners','vet_patients','vet_patient_events','clinical_cases','clinical_observations','clinical_procedure_acts','clinical_death_records','form_templates','form_template_versions','form_documents','clinic_document_settings','hospital_stays','hospital_tasks','prescriptions','prescription_items','medication_records','medication_vials','inventario','lotes_inventario','inventory_sales','inventory_sale_lines','inventory_stock_movements','clinic_appointments','clinic_services','clinic_messages','clinic_tasks','staff_medical_profiles'] loop
 execute format('update private.workspace_usage u set bytes=bytes+(select coalesce(sum(octet_length(to_jsonb(x)::text)),0) from public.%I x where x.clinic_id=u.clinic_id)',t);
 execute format('create trigger plan_record_budget after insert or update or delete on public.%I for each row execute function private.plan_record_budget()',t);
 end loop;end$$;
do $$declare t text;begin foreach t in array array['subscription_plans','account_workspaces','subscription_grants','subscription_revocations','subscription_requests','reward_credits'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);end loop;end$$;
revoke all on function public.plan_grant_server(uuid,text,text,timestamptz,timestamptz,text),public.plan_revoke_server(uuid,text),public.reward_credit_server(uuid,integer,text,text) from public,anon,authenticated;
grant execute on function public.plan_grant_server(uuid,text,text,timestamptz,timestamptz,text),public.plan_revoke_server(uuid,text),public.reward_credit_server(uuid,integer,text,text) to service_role;
revoke all on function public.personal_workspace_create(),public.plan_dashboard(uuid),public.plan_request(uuid,text,text,text),public.create_clinic_invitation(uuid,text,text),public.ops_write(uuid,text,jsonb,text),public.att_settings_save(uuid,jsonb) from public,anon;
grant execute on function public.personal_workspace_create(),public.plan_dashboard(uuid),public.plan_request(uuid,text,text,text),public.create_clinic_invitation(uuid,text,text),public.ops_write(uuid,text,jsonb,text),public.att_settings_save(uuid,jsonb) to authenticated;
revoke all on function private.workspace_created(),private.personal_members_guard(),private.plan_patient_guard(),private.plan_record_budget() from public,anon,authenticated;

create function public.workspace_memberships() returns jsonb language sql stable security definer set search_path='' as $$select coalesce(jsonb_agg(jsonb_build_object('clinic_id',m.clinic_id,'user_id',m.user_id,'role',m.role,'clinic_name',c.name,'workspace_kind',w.kind)),'[]') from public.clinic_members m join public.clinics c on c.id=m.clinic_id join public.account_workspaces w on w.clinic_id=m.clinic_id where m.user_id=auth.uid();$$;
revoke all on function public.workspace_memberships() from public,anon;grant execute on function public.workspace_memberships() to authenticated;
-- Prevent attendance use after a clinic grant expires.
alter function public.att_scan(uuid,text,double precision,double precision,double precision,text) rename to att_scan_before_plans;
revoke all on function public.att_scan_before_plans(uuid,text,double precision,double precision,double precision,text) from public,anon,authenticated;
create function public.att_scan(p_clinic uuid,p_token text,p_latitude double precision,p_longitude double precision,p_accuracy double precision,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$begin if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;if not private.team_plan(p_clinic) then raise exception 'clinic_plan_required';end if;return public.att_scan_before_plans(p_clinic,p_token,p_latitude,p_longitude,p_accuracy,p_operation);end$$;
revoke all on function public.att_scan(uuid,text,double precision,double precision,double precision,text) from public,anon;grant execute on function public.att_scan(uuid,text,double precision,double precision,double precision,text) to authenticated;

-- Confirmed recurring payment bridge: callable ONLY by the verified webhook service.
create table public.subscription_payments(id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),request_id uuid not null references public.subscription_requests(id),provider text not null check(provider='stripe'),invoice_id text not null unique,subscription_id text not null,event_id text not null unique,amount_cents bigint not null,currency text not null check(currency='mxn'),period_start timestamptz not null,period_end timestamptz not null,received_at timestamptz not null default clock_timestamp());
alter table public.subscription_payments enable row level security;revoke all on public.subscription_payments from public,anon,authenticated;
create function public.billing_request_read(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare r public.subscription_requests;begin select * into r from public.subscription_requests where id=p_id;if not found or r.requested_by<>auth.uid() or not private.has_clinic_role(r.clinic_id,array['admin']) then raise exception 'owner_required';end if;if not exists(select 1 from public.subscription_plans where code=r.plan_code and published) then raise exception 'pricing_not_published';end if;if exists(select 1 from public.subscription_grants g where g.clinic_id=r.clinic_id and source='subscription' and ends_at>clock_timestamp() and not exists(select 1 from public.subscription_revocations x where x.grant_id=g.id)) then raise exception 'subscription_already_active_manage_provider';end if;return to_jsonb(r)||jsonb_build_object('trial_until',(select max(ends_at) from public.subscription_grants g where g.clinic_id=r.clinic_id and g.plan_code=r.plan_code and source<>'subscription' and ends_at>clock_timestamp() and not exists(select 1 from public.subscription_revocations x where x.grant_id=g.id)));end$$;
create function public.billing_invoice_server(p_request uuid,p_invoice text,p_subscription text,p_event text,p_amount bigint,p_currency text,p_start timestamptz,p_end timestamptz) returns uuid language plpgsql security definer set search_path='' as $$declare r public.subscription_requests;v_id uuid;existing public.subscription_payments;begin
 select * into r from public.subscription_requests where id=p_request for update;
 if not found or r.price_cents<>p_amount or p_currency<>'mxn' or p_end<=p_start or p_end<=clock_timestamp() then raise exception 'invoice_mismatch';end if;
 if not exists(select 1 from public.subscription_plans where code=r.plan_code and published) then raise exception 'pricing_not_published';end if;
 select * into existing from public.subscription_payments where invoice_id=p_invoice or event_id=p_event;
 if found then if existing.request_id<>p_request or existing.amount_cents<>p_amount or existing.period_start<>p_start or existing.period_end<>p_end then raise exception 'invoice_reference_conflict';end if;return existing.id;end if;
 insert into public.subscription_payments(clinic_id,request_id,provider,invoice_id,subscription_id,event_id,amount_cents,currency,period_start,period_end) values(r.clinic_id,r.id,'stripe',p_invoice,p_subscription,p_event,p_amount,p_currency,p_start,p_end) returning id into v_id;
 insert into public.subscription_grants(clinic_id,plan_code,source,starts_at,ends_at,reference) values(r.clinic_id,r.plan_code,'subscription',p_start,p_end,'stripe:invoice:'||p_invoice);
 return v_id;
end$$;
revoke all on function public.billing_request_read(uuid) from public,anon;grant execute on function public.billing_request_read(uuid) to authenticated;
revoke all on function public.billing_invoice_server(uuid,text,text,text,bigint,text,timestamptz,timestamptz) from public,anon,authenticated;grant execute on function public.billing_invoice_server(uuid,text,text,text,bigint,text,timestamptz,timestamptz) to service_role;
create trigger subscription_grant_immutable before update or delete on public.subscription_grants for each row execute function private.inv_history_guard();
create trigger subscription_revocation_immutable before update or delete on public.subscription_revocations for each row execute function private.inv_history_guard();
create trigger subscription_request_immutable before update or delete on public.subscription_requests for each row execute function private.inv_history_guard();
create trigger reward_immutable before update or delete on public.reward_credits for each row execute function private.inv_history_guard();

create table private.reward_policy(id boolean primary key default true check(id),points integer not null default 1000 check(points>0),days integer not null default 30 check(days between 1 and 365),enabled boolean not null default false);
insert into private.reward_policy(id) values(true);revoke all on private.reward_policy from public,anon,authenticated;
create function public.reward_redeem(p_clinic uuid,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$declare policy private.reward_policy;v_id uuid;fp jsonb;code text;benefit_start timestamptz;begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 select * into policy from private.reward_policy where id=true;if not policy.enabled then raise exception 'reward_program_not_active';end if;
 fp=jsonb_build_object('kind','reward_redeem','points',policy.points,'days',policy.days);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':rewards',0));
 if (select coalesce(sum(points),0) from public.reward_credits where user_id=auth.uid())<policy.points then raise exception 'insufficient_reward_points';end if;
 if exists(select 1 from public.subscription_grants g where g.clinic_id=p_clinic and g.source='subscription' and g.ends_at>clock_timestamp() and not exists(select 1 from public.subscription_revocations r where r.grant_id=g.id)) then raise exception 'active_subscription_rewards_pending';end if;
 code=case when private.personal_clinic(p_clinic) then 'individual' else 'clinic' end;
 select greatest(clock_timestamp(),coalesce(max(ends_at),clock_timestamp())) into benefit_start from public.subscription_grants g where g.clinic_id=p_clinic and plan_code=code and not exists(select 1 from public.subscription_revocations r where r.grant_id=g.id);
 insert into public.reward_credits(user_id,points,reference,reason) values(auth.uid(),-policy.points,'redeem:'||auth.uid()::text||':'||p_operation,'Canje de beneficio temporal');
 insert into public.subscription_grants(clinic_id,plan_code,source,starts_at,ends_at,reference) values(p_clinic,code,'reward',benefit_start,benefit_start+make_interval(days=>policy.days),'redeem:'||auth.uid()::text||':'||p_operation) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);return v_id;
end$$;
revoke all on function public.reward_redeem(uuid,text) from public,anon;grant execute on function public.reward_redeem(uuid,text) to authenticated;

commit;
