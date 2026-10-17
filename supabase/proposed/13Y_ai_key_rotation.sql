-- LOCAL CANDIDATE ONLY. Apply only during coordinated beta rollout.
-- Rotates an existing encrypted credential without exposing plaintext.
begin;
create function public.ai_key_rotate_server(
 p_user uuid, p_connection uuid, p_cipher text, p_nonce text
) returns integer language plpgsql security definer set search_path='' as $$
declare v_version integer;
begin
 if not private.ai_key_allowed(p_connection,p_user,true) then
  raise exception 'key_management_denied';
 end if;
 if length(p_cipher) not between 20 and 8000 or length(p_nonce) not between 16 and 100 then
  raise exception 'cipher_required';
 end if;
 -- Lock the credential row, increment exactly once per successful rotation.
 update private.ai_credentials
 set ciphertext=p_cipher,nonce=p_nonce,key_version=key_version+1
 where connection_id=p_connection
 returning key_version into v_version;
 if not found then raise exception 'credential_missing';end if;
 return v_version;
end$$;
revoke all on function public.ai_key_rotate_server(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.ai_key_rotate_server(uuid,uuid,text,text) to service_role;

-- Capture the key version on transition to processing, holding a shared row lock
-- so a concurrent rotation cannot interleave before the claim commits.
alter table public.ai_requests add column credential_version integer;
create function private.ai_capture_credential_version() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.state='processing' and old.state='queued' then
  select k.key_version into new.credential_version
  from private.ai_credentials k
  where k.connection_id=new.connection_id
  for share;
  if new.credential_version is null then raise exception 'credential_missing';end if;
 end if;
 return new;
end$$;
create trigger ai_capture_credential_version
before update of state on public.ai_requests
for each row execute function private.ai_capture_credential_version();
revoke all on function private.ai_capture_credential_version() from public,anon,authenticated;

-- Re-check and lock the credential within the same transaction that stores the
-- generated answer. This closes the check-to-write rotation race.
create or replace function public.ai_finish_server(
 p_id uuid,p_user uuid,p_body text,p_success boolean
) returns void language plpgsql security definer set search_path='' as $$
declare r public.ai_requests;v_msg uuid;v_version integer;
begin
 select * into r from public.ai_requests where id=p_id and user_id=p_user for update;
 if not found or r.state not in ('queued','processing')
    or (p_success and r.state<>'processing') then
  raise exception 'request_not_processing';
 end if;
 if p_success then
  select k.key_version into v_version from private.ai_credentials k
  where k.connection_id=r.connection_id for share;
 end if;
 if not p_success
    or r.credential_version is null
    or v_version is distinct from r.credential_version
    or not private.ai_chat_allowed(r.chat_id,p_user)
    or not private.ai_key_allowed(r.connection_id,p_user)
    or exists(
      select 1 from private.ai_context_sources s
      left join public.ai_chats c on c.id=s.chat_id
      where s.request_id=r.id and
      (c.id is null or c.version<>s.policy_version
       or not private.ai_chat_allowed(c.id,p_user))
    ) then
  update public.ai_requests set state='failed' where id=r.id;
  return;
 end if;
 insert into public.ai_messages(clinic_id,chat_id,role,body,created_by)
 values(r.clinic_id,r.chat_id,'assistant',p_body,p_user) returning id into v_msg;
 update public.ai_requests set state='done',output_message_id=v_msg where id=r.id;
end$$;
commit;
