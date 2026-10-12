-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Después de etapas 1-6.
-- Ejecutar 07A hasta 07E en orden. No activa cobros ni proveedores IA.
begin;

-- existing_ai_m12.sql

create table private.ai_daily_usage(clinic_id uuid not null references public.clinics(id),day date not null,attempts integer not null default 0,primary key(clinic_id,day));
revoke all on private.ai_daily_usage from public,anon,authenticated;
create table private.ai_context_sources(request_id uuid not null,chat_id uuid not null,policy_version integer not null,primary key(request_id,chat_id));
revoke all on private.ai_context_sources from public,anon,authenticated;
create table public.ai_connections(id uuid primary key default gen_random_uuid(),provider text not null check(provider in ('openai','google','anthropic')),scope text not null check(scope in ('personal','clinic')),owner_id uuid references auth.users(id),clinic_id uuid references public.clinics(id),enabled boolean not null default true,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),check((scope='personal' and owner_id is not null and clinic_id is null) or (scope='clinic' and clinic_id is not null and owner_id is null)));
create table private.ai_credentials(connection_id uuid primary key references public.ai_connections(id),ciphertext text not null,nonce text not null,key_version integer not null default 1);
create table public.ai_chats(id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),owner_id uuid not null references auth.users(id),title text not null check(length(btrim(title)) between 1 and 150),visibility text not null default 'private' check(visibility in ('private','clinic')),context_mode text not null default 'none' check(context_mode in ('none','personal','clinic')),audience text[] not null default '{}',version integer not null default 1,created_at timestamptz not null default clock_timestamp(),unique(clinic_id,id),check(context_mode<>'clinic' or visibility='clinic'));
create table public.ai_messages(id uuid primary key default gen_random_uuid(),clinic_id uuid not null,chat_id uuid not null,role text not null check(role in ('user','assistant')),body text not null check(length(body) between 1 and 30000),created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),foreign key(clinic_id,chat_id) references public.ai_chats(clinic_id,id));
create table public.ai_requests(id uuid primary key default gen_random_uuid(),clinic_id uuid not null,chat_id uuid not null,user_id uuid not null references auth.users(id),connection_id uuid not null references public.ai_connections(id),model text not null check(length(model) between 1 and 150),operation text not null,personal_context boolean not null,team_context boolean not null,state text not null default 'queued' check(state in ('queued','processing','done','failed')),input_message_id uuid not null references public.ai_messages(id),output_message_id uuid references public.ai_messages(id),created_at timestamptz not null default clock_timestamp(),unique(user_id,operation),foreign key(clinic_id,chat_id) references public.ai_chats(clinic_id,id));
revoke all on private.ai_credentials from public,anon,authenticated;
create function private.ai_key_allowed(p_connection uuid,p_user uuid,p_manage boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.ai_connections c where c.id=$1 and (c.enabled or $3) and ((c.scope='personal' and c.owner_id=$2) or (c.scope='clinic' and exists(select 1 from public.clinic_members m where m.clinic_id=c.clinic_id and m.user_id=$2 and (not $3 or m.role='admin')))));
$$;
create function private.ai_chat_allowed(p_chat uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.ai_chats c join public.clinic_members m on m.clinic_id=c.clinic_id and m.user_id=$2 where c.id=$1 and (c.owner_id=$2 or (c.visibility='clinic' and m.role=any(c.audience))));$$;
revoke all on function private.ai_key_allowed(uuid,uuid,boolean),private.ai_chat_allowed(uuid,uuid) from public,anon,authenticated;
create function public.ai_dashboard(p_clinic uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;
 return jsonb_build_object('connections',(select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('can_manage',private.ai_key_allowed(c.id,auth.uid(),true))),'[]') from public.ai_connections c where (c.owner_id=auth.uid() or c.clinic_id=p_clinic) and private.ai_key_allowed(c.id,auth.uid(),false)),
 'chats',(select coalesce(jsonb_agg(to_jsonb(c) order by created_at desc),'[]') from public.ai_chats c where c.clinic_id=p_clinic and private.ai_chat_allowed(c.id,auth.uid())),
 'daily_used',coalesce((select attempts from private.ai_daily_usage where clinic_id=p_clinic and day=(clock_timestamp() at time zone 'UTC')::date),0),'daily_limit',(private.plan_for(p_clinic)).ai_daily);
end$$;
create function public.ai_chat_create(p_clinic uuid,p_title text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$declare fp jsonb;v_id uuid;begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;
 fp=jsonb_build_object('kind','ai_chat','title',p_title);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.ai_chats(clinic_id,owner_id,title) values(p_clinic,auth.uid(),p_title) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);return v_id;
end$$;
create function public.ai_chat_policy(p_id uuid,p_version integer,p_visibility text,p_context text,p_audience text[]) returns void language plpgsql security definer set search_path='' as $$declare c public.ai_chats;begin
 select * into c from public.ai_chats where id=p_id for update;
 if not found or c.owner_id<>auth.uid() or not private.has_clinic_role(c.clinic_id) then raise exception 'owner_required';end if;
 if p_version<>c.version then raise exception 'version_conflict';end if;
 if p_visibility='clinic' then
 if not private.team_plan(c.clinic_id) then raise exception 'clinic_plan_required';end if;
 if coalesce(cardinality(p_audience),0)=0 or not p_audience<@array['admin','mvz','auxiliar','recepcion','estilista'] then raise exception 'audience_required';end if;
 end if;
 update public.ai_chats set visibility=p_visibility,context_mode=p_context,audience=case when p_visibility='private' then '{}' else p_audience end,version=version+1 where id=p_id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(c.clinic_id,auth.uid(),'ai_policy_changed',c.id::text,jsonb_build_object('visibility',p_visibility,'context',p_context));
end$$;
create function public.ai_messages_read(p_chat uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if not private.ai_chat_allowed(p_chat,auth.uid()) then raise exception 'access_denied';end if;
 return (select coalesce(jsonb_agg(to_jsonb(m) order by created_at,id),'[]') from public.ai_messages m where chat_id=p_chat);
end$$;
create function public.ai_chat_delete(p_chat uuid) returns void language plpgsql security definer set search_path='' as $$declare c public.ai_chats;begin
 select * into c from public.ai_chats where id=p_chat for update;
 if not found or c.owner_id<>auth.uid() or not private.has_clinic_role(c.clinic_id) then raise exception 'owner_required';end if;
 if exists(select 1 from public.ai_requests where chat_id=p_chat and state in ('queued','processing')) then raise exception 'chat_in_progress';end if;
 delete from private.ai_context_sources where request_id in (select id from public.ai_requests where chat_id=p_chat);delete from public.ai_requests where chat_id=p_chat;delete from public.ai_messages where chat_id=p_chat;delete from public.ai_chats where id=p_chat;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(c.clinic_id,auth.uid(),'ai_chat_deleted',p_chat::text);
end$$;
create function public.ai_connection_disable(p_id uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.ai_key_allowed(p_id,auth.uid(),true) then raise exception 'owner_required';end if;
 update public.ai_connections set enabled=false where id=p_id;delete from private.ai_credentials where connection_id=p_id;
end$$;
create function public.ai_prepare(p_chat uuid,p_connection uuid,p_model text,p_message text,p_operation text,p_personal boolean,p_team boolean) returns jsonb language plpgsql security definer set search_path='' as $$declare c public.ai_chats;r public.ai_requests;v_msg uuid;plan public.subscription_plans;begin
 select * into c from public.ai_chats where id=p_chat for update;
 if not found or c.owner_id<>auth.uid() or not private.has_clinic_role(c.clinic_id) then raise exception 'owner_required';end if;
 if not private.ai_key_allowed(p_connection,auth.uid()) or exists(select 1 from public.ai_connections where id=p_connection and clinic_id is not null and clinic_id<>c.clinic_id) then raise exception 'key_access_denied';end if;
 if p_team and not private.team_plan(c.clinic_id) then raise exception 'clinic_plan_required';end if;
 select * into r from public.ai_requests where user_id=auth.uid() and operation=p_operation;
 if found then
 if r.chat_id<>p_chat or r.connection_id<>p_connection or r.model<>p_model or r.personal_context<>p_personal or r.team_context<>p_team or (select body from public.ai_messages where id=r.input_message_id)<>p_message then raise exception 'operation_content_changed';end if;
 return jsonb_build_object('id',r.id,'state',r.state);end if;
 if length(p_message) not between 1 and 12000 or length(p_operation) not between 16 and 100 then raise exception 'invalid_message';end if;
 if exists(select 1 from public.ai_requests where chat_id=p_chat and state in ('queued','processing')) then raise exception 'chat_in_progress';end if;
 perform 1 from private.workspace_usage where clinic_id=c.clinic_id for update;plan=private.plan_for(c.clinic_id);
 insert into private.ai_daily_usage(clinic_id,day) values(c.clinic_id,(clock_timestamp() at time zone 'UTC')::date) on conflict do nothing;
 if (select attempts from private.ai_daily_usage where clinic_id=c.clinic_id and day=(clock_timestamp() at time zone 'UTC')::date)>=plan.ai_daily then raise exception 'ai_daily_limit';end if;
 update private.ai_daily_usage set attempts=attempts+1 where clinic_id=c.clinic_id and day=(clock_timestamp() at time zone 'UTC')::date;
 insert into public.ai_messages(clinic_id,chat_id,role,body,created_by) values(c.clinic_id,c.id,'user',p_message,auth.uid()) returning id into v_msg;
 insert into public.ai_requests(clinic_id,chat_id,user_id,connection_id,model,operation,personal_context,team_context,input_message_id) values(c.clinic_id,c.id,auth.uid(),p_connection,p_model,p_operation,p_personal,p_team,v_msg) returning * into r;
 return jsonb_build_object('id',r.id,'state',r.state);
end$$;
-- Gateway-only storage of AES-GCM ciphertext.
create function public.ai_key_store_server(p_user uuid,p_scope text,p_clinic uuid,p_provider text,p_cipher text,p_nonce text) returns uuid language plpgsql security definer set search_path='' as $$declare v_id uuid;begin
 if not exists(select 1 from auth.users where id=p_user and email_confirmed_at is not null) then raise exception 'verified_user_required';end if;
 if p_scope='clinic' and not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=p_user and role='admin') then raise exception 'admin_required';end if;
 if length(p_cipher) not between 20 and 8000 or length(p_nonce) not between 16 and 100 then raise exception 'cipher_required';end if;
 insert into public.ai_connections(provider,scope,owner_id,clinic_id,created_by) values(p_provider,p_scope,case when p_scope='personal' then p_user end,case when p_scope='clinic' then p_clinic end,p_user) returning id into v_id;
 insert into private.ai_credentials(connection_id,ciphertext,nonce) values(v_id,p_cipher,p_nonce);return v_id;
end$$;
create function public.ai_key_get_server(p_user uuid,p_connection uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if not private.ai_key_allowed(p_connection,p_user) then raise exception 'key_access_denied';end if;
 return (select to_jsonb(k)||jsonb_build_object('provider',c.provider,'scope',c.scope,'owner_id',c.owner_id,'clinic_id',c.clinic_id) from private.ai_credentials k join public.ai_connections c on c.id=k.connection_id where c.id=p_connection);
end$$;
create function public.ai_claim_server(p_id uuid,p_user uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare r public.ai_requests;ctx jsonb;history jsonb;begin
 select * into r from public.ai_requests where id=p_id and user_id=p_user for update;
 if not found or r.state<>'queued' then raise exception 'request_already_claimed';end if;
 if not private.ai_chat_allowed(r.chat_id,p_user) or not private.ai_key_allowed(r.connection_id,p_user) then raise exception 'access_denied';end if;
 if r.team_context and not private.team_plan(r.clinic_id) then raise exception 'clinic_plan_required';end if;
 -- Re-read policies now. No context supplied by the client or cached from an old permission.
 select coalesce(jsonb_agg(jsonb_build_object('chat_id',c.id,'role',m.role,'body',left(m.body,2000)) order by m.created_at),'[]') into ctx from (select * from public.ai_chats where clinic_id=r.clinic_id and id<>r.chat_id and private.ai_chat_allowed(id,p_user) and ((r.personal_context and owner_id=p_user and context_mode in ('personal','clinic')) or (r.team_context and visibility='clinic' and context_mode='clinic')) order by created_at desc limit 5) c join lateral (select * from public.ai_messages where chat_id=c.id order by created_at desc limit 4) m on true;
 select coalesce(jsonb_agg(jsonb_build_object('role',m.role,'body',left(m.body,12000)) order by m.created_at,m.id),'[]') into history from (select * from public.ai_messages where chat_id=r.chat_id order by created_at desc,id desc limit 12) m;
 insert into private.ai_context_sources(request_id,chat_id,policy_version) select distinct r.id,c.id,c.version from jsonb_array_elements(ctx) e join public.ai_chats c on c.id=(e->>'chat_id')::uuid;
 update public.ai_requests set state='processing' where id=r.id;
 return jsonb_build_object('request',to_jsonb(r),'context',ctx,'history',history,'key',public.ai_key_get_server(p_user,r.connection_id));
end$$;
create function public.ai_finish_server(p_id uuid,p_user uuid,p_body text,p_success boolean) returns void language plpgsql security definer set search_path='' as $$declare r public.ai_requests;v_msg uuid;begin
 select * into r from public.ai_requests where id=p_id and user_id=p_user for update;
 if not found or r.state not in ('queued','processing') or (p_success and r.state<>'processing') then raise exception 'request_not_processing';end if;
 if not p_success or not private.ai_chat_allowed(r.chat_id,p_user) or not private.ai_key_allowed(r.connection_id,p_user) or exists(select 1 from private.ai_context_sources s left join public.ai_chats c on c.id=s.chat_id where s.request_id=r.id and (c.id is null or c.version<>s.policy_version or not private.ai_chat_allowed(c.id,p_user))) then update public.ai_requests set state='failed' where id=r.id;return;end if;
 insert into public.ai_messages(clinic_id,chat_id,role,body,created_by) values(r.clinic_id,r.chat_id,'assistant',p_body,p_user) returning id into v_msg;
 update public.ai_requests set state='done',output_message_id=v_msg where id=r.id;
end$$;
create trigger ai_chat_budget after insert or update or delete on public.ai_chats for each row execute function private.plan_record_budget();
create trigger ai_message_budget after insert or update or delete on public.ai_messages for each row execute function private.plan_record_budget();
do $$declare t text;begin foreach t in array array['ai_connections','ai_chats','ai_messages','ai_requests'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);end loop;end$$;
revoke all on function public.ai_key_store_server(uuid,text,uuid,text,text,text),public.ai_key_get_server(uuid,uuid),public.ai_claim_server(uuid,uuid),public.ai_finish_server(uuid,uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.ai_key_store_server(uuid,text,uuid,text,text,text),public.ai_key_get_server(uuid,uuid),public.ai_claim_server(uuid,uuid),public.ai_finish_server(uuid,uuid,text,boolean) to service_role;
revoke all on function public.ai_dashboard(uuid),public.ai_chat_create(uuid,text,text),public.ai_chat_policy(uuid,integer,text,text,text[]),public.ai_messages_read(uuid),public.ai_chat_delete(uuid),public.ai_connection_disable(uuid),public.ai_prepare(uuid,uuid,text,text,text,boolean,boolean) from public,anon;
grant execute on function public.ai_dashboard(uuid),public.ai_chat_create(uuid,text,text),public.ai_chat_policy(uuid,integer,text,text,text[]),public.ai_messages_read(uuid),public.ai_chat_delete(uuid),public.ai_connection_disable(uuid),public.ai_prepare(uuid,uuid,text,text,text,boolean,boolean) to authenticated;

create function public.ai_request_abandon(p_chat uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from public.ai_chats where id=p_chat and owner_id=auth.uid()) or not private.ai_chat_allowed(p_chat,auth.uid()) then raise exception 'owner_required';end if;
 update public.ai_requests set state='failed' where chat_id=p_chat and user_id=auth.uid() and state in ('queued','processing') and created_at<clock_timestamp()-interval '2 minutes';
 if not found then raise exception 'no_stale_request';end if;
end$$;
revoke all on function public.ai_request_abandon(uuid) from public,anon;grant execute on function public.ai_request_abandon(uuid) to authenticated;


notify pgrst, 'reload schema';
commit;
select '07B COMPLETADO: IA y chats' as resultado;
-- FIN COMPLETO 07B
