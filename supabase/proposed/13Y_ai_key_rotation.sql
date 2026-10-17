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
commit;
