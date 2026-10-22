-- Proposed: public, read-only preview of the latest *published* legal documents.
-- Requires 12A + 12C. Does not publish drafts, record consent, or open admissions.
begin;

create or replace function public.beta_registration_legal()
returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'terms', jsonb_build_object(
      'version',t.version,'hash',t.content_hash,'content',t.content
    ),
    'privacy', jsonb_build_object(
      'version',n.version,'hash',n.content_hash,'content',n.content
    )
  )
  from (
    select version,content_hash,content,privacy_version
    from private.beta_terms
    where published
    order by published_at desc,version desc
    limit 1
  ) t
  join private.beta_privacy_notices n
    on n.version=t.privacy_version
   and n.published
   and n.content_hash=encode(sha256(convert_to(n.content,'UTF8')),'hex')
  where t.content_hash=encode(sha256(convert_to(t.content,'UTF8')),'hex');
$$;
-- Narrow pre-request exception: only this exact, read-only published-text RPC.
-- Every other request still uses the installed beta gate unchanged.
create or replace function public.beta_request_guard()
returns void language plpgsql stable security definer set search_path='' as $legal_guard$
begin
  if current_setting('request.path',true)='/rpc/beta_registration_legal' then
    return;
  end if;
  perform private.beta_request_guard();
end$legal_guard$;
revoke all on function public.beta_registration_legal() from public;
grant execute on function public.beta_registration_legal() to anon,authenticated;
commit;
notify pgrst,'reload schema';
