-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Después de etapas 1-6.
-- Ejecutar 07A hasta 07E en orden. No activa cobros ni proveedores IA.
begin;

-- existing_starter_ai_review.sql

alter table public.ai_connections drop constraint ai_connections_provider_check;
alter table public.ai_connections add constraint ai_connections_provider_check check(provider in('openai','google','anthropic','zai'));
create table private.starter_ai_config(id boolean primary key default true check(id),enabled boolean not null default false,provider text not null default 'google' check(provider in('google','zai')),model text not null default 'gemini-2.5-flash',per_user_daily integer not null default 5 check(per_user_daily between 1 and 20),global_daily integer not null default 100 check(global_daily between 1 and 1000),check((provider='google' and model in('gemini-2.5-flash','gemini-2.5-flash-lite'))or(provider='zai' and model in('glm-4.5-flash','glm-4.7-flash'))));
insert into private.starter_ai_config(id)values(true);
create table private.starter_ai_user_usage(user_id uuid not null references auth.users(id),day date not null,attempts integer not null default 0,primary key(user_id,day));
create table private.starter_ai_global_usage(day date primary key,attempts integer not null default 0);
create table private.starter_ai_requests(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),clinic_id uuid not null references public.clinics(id),chat_id uuid references public.ai_chats(id) on delete set null,topic text not null,provider text not null,model text not null,operation text not null,state text not null default 'queued' check(state in('queued','processing','done','failed')),created_at timestamptz not null default clock_timestamp(),unique(user_id,operation));
revoke all on private.starter_ai_config,private.starter_ai_user_usage,private.starter_ai_global_usage,private.starter_ai_requests from public,anon,authenticated;
create function public.starter_ai_status(p_clinic uuid)returns jsonb language plpgsql security definer set search_path='' as $$declare cfg private.starter_ai_config;begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;select * into cfg from private.starter_ai_config where id=true;
 return jsonb_build_object('enabled',cfg.enabled,'provider',cfg.provider,'model',cfg.model,'limit',cfg.per_user_daily,'used',coalesce((select attempts from private.starter_ai_user_usage where user_id=auth.uid() and day=(clock_timestamp() at time zone 'UTC')::date),0));end $$;
create function public.starter_ai_prepare(p_clinic uuid,p_topic text,p_operation text)returns jsonb language plpgsql security definer set search_path='' as $$declare cfg private.starter_ai_config;r private.starter_ai_requests;v_chat uuid;day_utc date=(clock_timestamp()at time zone 'UTC')::date;begin
 if not private.has_clinic_role(p_clinic) or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'verified_member_required';end if;
 if p_topic is null or p_topic not in('getting_started','permissions','payments','notifications','report_problem','privacy') or p_operation is null or length(p_operation) not between 16 and 100 then raise exception 'invalid_help_topic';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,715));
 select * into r from private.starter_ai_requests where user_id=auth.uid() and operation=p_operation;
 if found then if r.clinic_id<>p_clinic or r.topic<>p_topic then raise exception 'operation_content_changed';end if;
 if r.state in('queued','processing') and r.created_at<clock_timestamp()-interval '2 minutes' then update private.starter_ai_requests set state='failed' where id=r.id returning * into r;end if;
 return jsonb_build_object('id',r.id,'state',r.state,'chat',r.chat_id);end if;
 select * into cfg from private.starter_ai_config where id=true;if not cfg.enabled then raise exception 'starter_ai_disabled';end if;
 insert into private.starter_ai_global_usage(day)values(day_utc)on conflict do nothing;perform 1 from private.starter_ai_global_usage where day=day_utc for update;
 insert into private.starter_ai_user_usage(user_id,day)values(auth.uid(),day_utc)on conflict do nothing;
 if(select attempts from private.starter_ai_global_usage where day=day_utc)>=cfg.global_daily or(select attempts from private.starter_ai_user_usage where user_id=auth.uid() and day=day_utc)>=cfg.per_user_daily then raise exception 'starter_ai_daily_limit';end if;
 update private.starter_ai_global_usage set attempts=attempts+1 where day=day_utc;update private.starter_ai_user_usage set attempts=attempts+1 where user_id=auth.uid() and day=day_utc;
 insert into public.ai_chats(clinic_id,owner_id,title)values(p_clinic,auth.uid(),'Ayuda incluida · '||(case p_topic when 'getting_started' then 'Primeros pasos' when 'permissions' then 'Roles y permisos' when 'payments' then 'Planes, ventas y caja' when 'notifications' then 'Avisos y notificaciones' when 'report_problem' then 'Reportar un problema' when 'privacy' then 'Privacidad y contexto' end))returning id into v_chat;
 insert into public.ai_messages(clinic_id,chat_id,role,body,created_by)values(p_clinic,v_chat,'user','Ayuda de uso de la app: '||(case p_topic when 'getting_started' then 'Primeros pasos' when 'permissions' then 'Roles y permisos' when 'payments' then 'Planes, ventas y caja' when 'notifications' then 'Avisos y notificaciones' when 'report_problem' then 'Reportar un problema' when 'privacy' then 'Privacidad y contexto' end),auth.uid());
 insert into private.starter_ai_requests(user_id,clinic_id,chat_id,topic,provider,model,operation)values(auth.uid(),p_clinic,v_chat,p_topic,cfg.provider,cfg.model,p_operation)returning * into r;
 return jsonb_build_object('id',r.id,'state',r.state,'chat',v_chat);end $$;
create function public.starter_ai_claim_server(p_id uuid,p_user uuid)returns jsonb language plpgsql security definer set search_path='' as $$declare r private.starter_ai_requests;cfg private.starter_ai_config;begin
 select * into r from private.starter_ai_requests where id=p_id and user_id=p_user for update;if not found or r.state<>'queued' then raise exception 'request_already_claimed';end if;
 select * into cfg from private.starter_ai_config where id=true;
 if not cfg.enabled or cfg.provider<>r.provider or cfg.model<>r.model or r.chat_id is null or not private.ai_chat_allowed(r.chat_id,p_user) then raise exception 'access_denied';end if;
 update private.starter_ai_requests set state='processing' where id=r.id;
 return jsonb_build_object('provider',r.provider,'model',r.model,'topic',r.topic);end $$;
create function public.starter_ai_finish_server(p_id uuid,p_user uuid,p_body text,p_success boolean)returns void language plpgsql security definer set search_path='' as $$declare r private.starter_ai_requests;begin
 select * into r from private.starter_ai_requests where id=p_id and user_id=p_user for update;if not found or r.state not in('queued','processing') or(p_success and r.state<>'processing')then raise exception 'request_not_processing';end if;
 if not p_success or r.chat_id is null or not private.ai_chat_allowed(r.chat_id,p_user) or not(select enabled from private.starter_ai_config where id=true) then update private.starter_ai_requests set state='failed' where id=r.id;return;end if;
 if length(p_body) not between 1 and 12000 then raise exception 'invalid_help_output';end if;
 insert into public.ai_messages(clinic_id,chat_id,role,body,created_by)values(r.clinic_id,r.chat_id,'assistant',p_body,p_user);update private.starter_ai_requests set state='done' where id=r.id;end $$;
create function private.starter_chat_deleting()returns trigger language plpgsql security definer set search_path='' as $$begin update private.starter_ai_requests set state='failed' where chat_id=old.id and state in('queued','processing');return old;end $$;
revoke all on function private.starter_chat_deleting() from public,anon,authenticated;
create trigger starter_chat_deleting before delete on public.ai_chats for each row execute function private.starter_chat_deleting();
revoke all on function public.starter_ai_status(uuid),public.starter_ai_prepare(uuid,text,text),public.starter_ai_claim_server(uuid,uuid),public.starter_ai_finish_server(uuid,uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.starter_ai_status(uuid),public.starter_ai_prepare(uuid,text,text) to authenticated;
grant execute on function public.starter_ai_claim_server(uuid,uuid),public.starter_ai_finish_server(uuid,uuid,text,boolean) to service_role;

notify pgrst, 'reload schema';
commit;
select '07E COMPLETADO: ayuda IA inicial desactivada' as resultado;
-- FIN COMPLETO 07E
