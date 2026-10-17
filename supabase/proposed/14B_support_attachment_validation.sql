-- Targeted replacement for the older deployed finalizer; no table/bucket recreation.
-- Existing ACL is preserved. Do not create this RPC on a missing installation.
begin;
do $$begin
 if to_regprocedure('public.support_attachment_finish(uuid,text)') is null then
  raise exception 'support_finalizer_dependency_required';
 end if;
end $$;
create or replace function public.support_attachment_finish(p_ticket uuid,p_path text) returns void language plpgsql security definer set search_path='' as $$begin
 if private.support_access(p_ticket) is distinct from true or not exists(
  select 1 from public.support_attachments a join storage.objects o on o.bucket_id='support-files' and o.name=a.path
  where a.ticket_id=p_ticket and a.path=p_path
   and o.metadata->>'mimetype'=a.mime
   and case when o.metadata->>'size' ~ '^[0-9]{1,20}$'
       then (o.metadata->>'size')::numeric=a.size else false end
 ) then raise exception 'support_attachment_denied';end if;
 update public.support_attachments set ready=true where ticket_id=p_ticket and path=p_path;
 if not found then raise exception 'support_attachment_denied';end if;end $$;
commit;
