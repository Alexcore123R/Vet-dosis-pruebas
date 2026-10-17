\set ON_ERROR_STOP on
begin;
insert into auth.users values('00000000-0000-0000-0000-000000000081','s81@example.test',now()),('00000000-0000-0000-0000-000000000082','s82@example.test',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select public.create_clinic('Support ficticio') as clinic \gset
select public.support_create(:'clinic','error','Fallo ficticio','Descripción ficticia sin datos reales',repeat('a',24)) as ticket \gset
select set_config('test.support_ticket',:'ticket',true);
select set_config('test.support_clinic',:'clinic',true);
reset role;
insert into public.support_attachments(ticket_id,name,path,mime,size,ready,created_at)
values(:'ticket','stale.txt','00000000-0000-0000-0000-000000000081/'||:'ticket'||'/stale.txt','text/plain',10,false,clock_timestamp()-interval '2 hours');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
do $begin
 if public.support_create(current_setting('test.support_clinic')::uuid,'error','Fallo ficticio','Descripción ficticia sin datos reales',repeat('a',24))<>current_setting('test.support_ticket')::uuid then raise exception 'not_idempotent';end if;
 begin perform public.support_reply_server(current_setting('test.support_ticket')::uuid,'Respuesta','resolved','reply');raise exception 'client_replied';exception when insufficient_privilege then null;end;
end $$;
select public.support_attachment_reserve(:'ticket','prueba.txt','text/plain',20,repeat('b',24),'txt') as path \gset
do $begin
 if exists(select 1 from public.support_attachments where ticket_id=current_setting('test.support_ticket')::uuid and path like '%/stale.txt') then raise exception 'stale_attachment_reservation_not_cleaned';end if;
end $;
insert into storage.objects(bucket_id,name)values('support-files',:'path');
select public.support_attachment_finish(:'ticket',:'path');
reset role;
insert into public.clinic_members(clinic_id,user_id,role)values(:'clinic','00000000-0000-0000-0000-000000000082','admin');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
do $$begin
 if public.support_list(current_setting('test.support_clinic')::uuid)<>'[]'::jsonb then raise exception 'admin_read_private';end if;
 begin perform public.support_operator_queue();raise exception 'clinical_admin_became_operator';exception when raise_exception then if sqlerrm<>'support_operator_denied' then raise;end if;end;
 begin perform public.support_detail(current_setting('test.support_ticket')::uuid);raise exception 'private_read';exception when raise_exception then if sqlerrm<>'support_denied' then raise;end if;end;
 if exists(select 1 from storage.objects where bucket_id='support-files')then raise exception 'private_file';end if;
end $$;
set local role service_role;
select public.support_reply_server(:'ticket','Respuesta ficticia','resolved',repeat('r',24));
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
do $$declare d jsonb;begin
 d=public.support_detail(current_setting('test.support_ticket')::uuid);
 if d->'ticket'->>'status'<>'resolved' or jsonb_array_length(d->'messages')<>1 or jsonb_array_length(d->'attachments')<>1 then raise exception 'support_detail';end if;
end $$;
select public.support_message(:'ticket','Necesito otro detalle',repeat('c',24));
select public.support_message(:'ticket','Necesito otro detalle',repeat('c',24));
do $$declare d jsonb;begin d=public.support_detail(current_setting('test.support_ticket')::uuid);if jsonb_array_length(d->'messages')<>2 or d->'ticket'->>'status'<>'waiting_human' then raise exception 'message_idempotency';end if;end $$;
reset role;
insert into private.support_operators(user_id)values('00000000-0000-0000-0000-000000000082');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
select public.support_operator_detail(:'ticket');
select public.support_operator_reply(:'ticket','Atención por operador asignado','resolved',repeat('x',24));
do $$begin if not exists(select 1 from storage.objects where bucket_id='support-files')then raise exception 'operator_file_access';end if;end $$;
reset role;
do $$begin if not exists(select 1 from private.support_operator_audit where operator_id='00000000-0000-0000-0000-000000000082' and action='reply')then raise exception 'operator_audit';end if;end $$;
rollback;
