-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Después de etapas 1-6.
-- Ejecutar 07A hasta 07E en orden. No activa cobros ni proveedores IA.
begin;

-- existing_support_m14.sql

create table private.support_operators(user_id uuid primary key references auth.users(id),enabled boolean not null default true);
revoke all on private.support_operators from public,anon,authenticated;
create function public.support_operator_enabled() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from private.support_operators where user_id=auth.uid() and enabled) $$;
revoke all on function public.support_operator_enabled() from public,anon;grant execute on function public.support_operator_enabled() to authenticated;
create table public.support_tickets(id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),owner_id uuid not null references auth.users(id),category text not null check(category in ('error','payment','question','suggestion')),title text not null check(length(title) between 3 and 150),body text not null check(length(body) between 10 and 12000),status text not null default 'waiting_human' check(status in ('waiting_human','in_progress','awaiting_user','resolved')),operation text not null,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(owner_id,operation));
create table public.support_messages(id uuid primary key default gen_random_uuid(),ticket_id uuid not null references public.support_tickets(id),sender text not null check(sender in ('user','human')),body text not null check(length(body) between 1 and 12000),operation text not null,created_at timestamptz not null default now(),unique(ticket_id,operation));
create table public.support_attachments(id uuid primary key default gen_random_uuid(),ticket_id uuid not null references public.support_tickets(id),name text not null check(length(name) between 1 and 200),path text not null unique,mime text not null,size bigint not null check(size between 1 and 5242880),ready boolean not null default false,created_at timestamptz not null default now());
alter table public.support_tickets enable row level security;alter table public.support_messages enable row level security;alter table public.support_attachments enable row level security;
revoke all on public.support_tickets,public.support_messages,public.support_attachments from public,anon,authenticated;
create function private.support_access(p_ticket uuid) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.support_tickets t where t.id=p_ticket and t.owner_id=auth.uid() and private.has_clinic_role(t.clinic_id)) $$;
create function public.support_create(p_clinic uuid,p_category text,p_title text,p_body text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$declare t public.support_tickets;begin
 if not private.has_clinic_role(p_clinic) or auth.uid() is null or length(p_operation) not between 16 and 100 then raise exception 'support_denied';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,714));
 select * into t from public.support_tickets where owner_id=auth.uid() and operation=p_operation;
 if found then if t.clinic_id<>p_clinic or t.category<>p_category or t.title<>p_title or t.body<>p_body then raise exception 'operation_conflict';end if;return t.id;end if;
 if (select count(*) from public.support_tickets where owner_id=auth.uid() and created_at>now()-interval '1 day')>=20 then raise exception 'support_daily_limit';end if;
 insert into public.support_tickets(clinic_id,owner_id,category,title,body,operation) values(p_clinic,auth.uid(),p_category,p_title,p_body,p_operation) returning id into t.id;return t.id;end $$;
create function public.support_list(p_clinic uuid) returns jsonb language sql stable security definer set search_path='' as $$ select coalesce(jsonb_agg(to_jsonb(t) order by t.updated_at desc),'[]') from (select * from public.support_tickets where clinic_id=p_clinic and owner_id=auth.uid() and private.has_clinic_role(p_clinic) order by updated_at desc limit 100)t $$;
create function public.support_detail(p_ticket uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.support_access(p_ticket) then raise exception 'support_denied';end if;
 return jsonb_build_object('ticket',(select to_jsonb(t) from public.support_tickets t where id=p_ticket),'messages',coalesce((select jsonb_agg(to_jsonb(m) order by created_at) from public.support_messages m where ticket_id=p_ticket),'[]'),'attachments',coalesce((select jsonb_agg(to_jsonb(a) order by created_at) from public.support_attachments a where ticket_id=p_ticket and ready),'[]'));end $$;
create function public.support_message(p_ticket uuid,p_body text,p_operation text) returns void language plpgsql security definer set search_path='' as $$declare old_body text;begin
 if not private.support_access(p_ticket) or length(p_operation) not between 16 and 100 then raise exception 'support_denied';end if;
 perform 1 from public.support_tickets where id=p_ticket for update;
 select body into old_body from public.support_messages where ticket_id=p_ticket and operation=p_operation;
 if found then if old_body<>p_body then raise exception 'operation_conflict';end if;return;end if;
 if(select count(*) from public.support_messages where ticket_id=p_ticket)>=200 then raise exception 'support_message_limit';end if;
 insert into public.support_messages(ticket_id,sender,body,operation) values(p_ticket,'user',p_body,p_operation);
 update public.support_tickets set status='waiting_human',updated_at=now() where id=p_ticket;end $$;
create function public.support_attachment_reserve(p_ticket uuid,p_name text,p_mime text,p_size bigint,p_token text,p_extension text) returns text language plpgsql security definer set search_path='' as $$declare v_path text;begin
 if not private.support_access(p_ticket) or p_token !~ '^[a-zA-Z0-9-]{16,100}$' or (p_mime,p_extension) not in (('image/jpeg','jpg'),('image/png','png'),('application/pdf','pdf'),('text/plain','txt')) then raise exception 'support_attachment_denied';end if;
 perform 1 from public.support_tickets where id=p_ticket for update;
 if(select count(*) from public.support_attachments where ticket_id=p_ticket)>=5 then raise exception 'support_attachment_limit';end if;
 v_path=auth.uid()::text||'/'||p_ticket::text||'/'||p_token||'.'||p_extension;
 insert into public.support_attachments(ticket_id,name,path,mime,size) values(p_ticket,p_name,v_path,p_mime,p_size);return v_path;end $$;
create function private.support_file_access(p_path text,p_write boolean) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.support_attachments a where a.path=p_path and (private.support_access(a.ticket_id) or (not p_write and public.support_operator_enabled())) and (not p_write or not a.ready)) $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)values('support-files','support-files',false,5242880,array['image/jpeg','image/png','application/pdf','text/plain']);
create policy support_file_read on storage.objects for select to authenticated using(bucket_id='support-files' and private.support_file_access(name,false));
create policy support_file_insert on storage.objects for insert to authenticated with check(bucket_id='support-files' and private.support_file_access(name,true));
create function public.support_attachment_finish(p_ticket uuid,p_path text) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.support_access(p_ticket) or not exists(
  select 1 from public.support_attachments a join storage.objects o on o.bucket_id='support-files' and o.name=a.path
  where a.ticket_id=p_ticket and a.path=p_path
   and o.metadata->>'mimetype'=a.mime
   and case when o.metadata->>'size' ~ '^[0-9]{1,20}$'
       then (o.metadata->>'size')::numeric=a.size else false end
 ) then raise exception 'support_attachment_denied';end if;
 update public.support_attachments set ready=true where ticket_id=p_ticket and path=p_path;
 if not found then raise exception 'support_attachment_denied';end if;end $$;
-- Human operator adapter: callable only from a trusted global support backend.
create function public.support_reply_server(p_ticket uuid,p_body text,p_status text,p_operation text) returns void language plpgsql security definer set search_path='' as $$declare old_body text;begin
 perform 1 from public.support_tickets where id=p_ticket for update;if not found then raise exception 'ticket_missing';end if;
 select body into old_body from public.support_messages where ticket_id=p_ticket and operation=p_operation;
 if found then if old_body<>p_body then raise exception 'operation_conflict';end if;return;end if;
 insert into public.support_messages(ticket_id,sender,body,operation)values(p_ticket,'human',p_body,p_operation);
 update public.support_tickets set status=p_status,updated_at=now() where id=p_ticket;end $$;
revoke all on function private.support_access(uuid),private.support_file_access(text,boolean) from public,anon;
grant execute on function private.support_access(uuid),private.support_file_access(text,boolean) to authenticated;
revoke all on function public.support_create(uuid,text,text,text,text),public.support_list(uuid),public.support_detail(uuid),public.support_message(uuid,text,text),public.support_attachment_reserve(uuid,text,text,bigint,text,text),public.support_attachment_finish(uuid,text),public.support_reply_server(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.support_create(uuid,text,text,text,text),public.support_list(uuid),public.support_detail(uuid),public.support_message(uuid,text,text),public.support_attachment_reserve(uuid,text,text,bigint,text,text),public.support_attachment_finish(uuid,text) to authenticated;
grant execute on function public.support_reply_server(uuid,text,text,text) to service_role;
-- Global support backend must authenticate its human operator before using this service-only queue.
create function public.support_queue_server() returns jsonb language sql stable security definer set search_path='' as $$select coalesce(jsonb_agg(to_jsonb(t) order by t.updated_at),'[]') from(select * from public.support_tickets where status<>'resolved' order by updated_at limit 100)t $$;
create function public.support_detail_server(p_ticket uuid) returns jsonb language sql stable security definer set search_path='' as $$select jsonb_build_object('ticket',(select to_jsonb(t) from public.support_tickets t where id=p_ticket),'messages',coalesce((select jsonb_agg(to_jsonb(m) order by created_at) from public.support_messages m where ticket_id=p_ticket),'[]'),'attachments',coalesce((select jsonb_agg(to_jsonb(a) order by created_at) from public.support_attachments a where ticket_id=p_ticket and ready),'[]')) $$;
revoke all on function public.support_queue_server(),public.support_detail_server(uuid) from public,anon,authenticated;
grant execute on function public.support_queue_server(),public.support_detail_server(uuid) to service_role;
create table private.support_operator_audit(id uuid primary key default gen_random_uuid(),operator_id uuid not null references auth.users(id),ticket_id uuid not null references public.support_tickets(id),action text not null,operation text,created_at timestamptz not null default now());
revoke all on private.support_operator_audit from public,anon,authenticated;
create function public.support_operator_queue() returns jsonb language plpgsql security definer set search_path='' as $$begin if not public.support_operator_enabled() then raise exception 'support_operator_denied';end if;return public.support_queue_server();end $$;
create function public.support_operator_detail(p_ticket uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin if not public.support_operator_enabled() then raise exception 'support_operator_denied';end if;insert into private.support_operator_audit(operator_id,ticket_id,action)values(auth.uid(),p_ticket,'read');return public.support_detail_server(p_ticket);end $$;
create function public.support_operator_reply(p_ticket uuid,p_body text,p_status text,p_operation text) returns void language plpgsql security definer set search_path='' as $$begin if not public.support_operator_enabled() then raise exception 'support_operator_denied';end if;
 if length(p_operation) not between 16 and 100 then raise exception 'operation_invalid';end if;
 perform public.support_reply_server(p_ticket,p_body,p_status,'operator:'||auth.uid()::text||':'||p_operation);
 insert into private.support_operator_audit(operator_id,ticket_id,action,operation)values(auth.uid(),p_ticket,'reply',p_operation);end $$;
revoke all on function public.support_operator_queue(),public.support_operator_detail(uuid),public.support_operator_reply(uuid,text,text,text) from public,anon;
grant execute on function public.support_operator_queue(),public.support_operator_detail(uuid),public.support_operator_reply(uuid,text,text,text) to authenticated;
-- Payment receipts visible only to the workspace admin, without card/customer details.
create function public.plan_payment_history(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'payment_history_denied';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'amount_cents',amount_cents,'currency',currency,'provider',provider,'period_start',period_start,'period_end',period_end) order by period_start desc) from public.subscription_payments where clinic_id=p_clinic),'[]');end $$;
revoke all on function public.plan_payment_history(uuid) from public,anon;grant execute on function public.plan_payment_history(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
select '07D COMPLETADO: soporte' as resultado;
-- FIN COMPLETO 07D
