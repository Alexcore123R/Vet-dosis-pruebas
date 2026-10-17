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
rollback;
