-- Synthetic AI credential rotation tests; no provider calls or real secrets.
\set ON_ERROR_STOP on
begin;
insert into public.ai_connections(provider,scope,owner_id,created_by)
values('openai','personal','00000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000111')
returning id as conn \gset
insert into private.ai_credentials(connection_id,ciphertext,nonce)
values(:'conn','synthetic-ciphertext-0001','synthetic-nonce-0001');
select set_config('test.ai_connection', :'conn', true);
select (key_version=1)::int as initial_ok from private.ai_credentials where connection_id=:'conn';
do $$
declare v_conn uuid=current_setting('test.ai_connection')::uuid;
begin
 if public.ai_key_rotate_server('00000000-0000-0000-0000-000000000111',v_conn,
 'synthetic-ciphertext-0002','synthetic-nonce-0002')<>2 then
  raise exception 'rotation did not increment to 2';
 end if;
 if (select key_version from private.ai_credentials where connection_id=v_conn)<>2 then
  raise exception 'old version still current';
 end if;
 begin
  perform public.ai_key_rotate_server('00000000-0000-0000-0000-000000000113',v_conn,
  'synthetic-ciphertext-0003','synthetic-nonce-0003');
  raise exception 'unauthorized rotation succeeded';
 exception when others then
  if sqlerrm<>'key_management_denied' then raise;end if;
 end;
 if (select key_version from private.ai_credentials where connection_id=v_conn)<>2 then
  raise exception 'rejected rotation changed version';
 end if;
end$$;

-- Claim a synthetic request at version 2, then rotate to version 3.
-- Finishing its response must not insert an assistant message.
select id as clinic from public.clinics where name='Synthetic clinical permission A' \gset
insert into public.ai_chats(clinic_id,owner_id,title)
values(:'clinic','00000000-0000-0000-0000-000000000111','Synthetic rotation in progress')
returning id as chat \gset
insert into public.ai_messages(clinic_id,chat_id,role,body,created_by)
values(:'clinic',:'chat','user','synthetic pending request','00000000-0000-0000-0000-000000000111')
returning id as msg \gset
insert into public.ai_requests(
 clinic_id,chat_id,user_id,connection_id,model,operation,
 personal_context,team_context,input_message_id
) values (
 :'clinic',:'chat','00000000-0000-0000-0000-000000000111',:'conn',
 'synthetic-model','synthetic-operation-rotation-001',false,false,:'msg'
) returning id as request \gset
select set_config('test.ai_request',:'request',true);
select set_config('test.ai_chat',:'chat',true);
update public.ai_requests set state='processing' where id=:'request';
do $
declare v_request uuid=current_setting('test.ai_request')::uuid;
begin
 if (select credential_version from public.ai_requests where id=v_request)<>2 then
  raise exception 'claim did not snapshot credential version';
 end if;
 perform public.ai_key_rotate_server(
 '00000000-0000-0000-0000-000000000111',
 current_setting('test.ai_connection')::uuid,
 'synthetic-ciphertext-0004','synthetic-nonce-0004'
 );
 perform public.ai_finish_server(
 v_request,'00000000-0000-0000-0000-000000000111',
 'stale synthetic assistant answer',true
 );
 if (select state from public.ai_requests where id=v_request)<>'failed' then
  raise exception 'stale AI request was accepted';
 end if;
 if exists(select 1 from public.ai_messages
           where chat_id=current_setting('test.ai_chat')::uuid
           and role='assistant') then
  raise exception 'stale assistant reply was saved';
 end if;
end$;
rollback;
