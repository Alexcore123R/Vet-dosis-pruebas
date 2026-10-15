-- Privileged one-off operation, never a public RPC. Caller supplies reviewed literals.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $conversion$
declare
 target_clinic uuid=__CLINIC_ID__;
 target_email text=__ACCOUNT_EMAIL__;
 target_name text=__CLINIC_NAME__;
 target_user uuid;
 t record;
 rows_found bigint;
 old_audit jsonb;
begin
 select id into target_user from auth.users where lower(btrim(email))=lower(btrim(target_email)) and email_confirmed_at is not null for update;
 if target_user is null then raise exception 'confirmed_account_required';end if;
 if not exists(select 1 from public.clinics where id=target_clinic) then
  if exists(select 1 from private.platform_admins where user_id=target_user and enabled) and not exists(select 1 from public.clinic_members where user_id=target_user) then return;end if;
  raise exception 'reviewed_clinic_not_found';
 end if;
 -- Serialize the review and deletion, including legacy tables without a clinic FK.
 lock table public.clinics in share row exclusive mode;
 for t in select distinct n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped where c.relkind='r' and n.nspname in ('public','private') and (a.attname='clinic_id' or exists(select 1 from pg_constraint f where f.contype='f' and f.conrelid=c.oid and f.confrelid='public.clinics'::regclass and cardinality(f.conkey)=1 and f.conkey[1]=a.attnum)) order by n.nspname,c.relname loop
  execute format('lock table %I.%I in share row exclusive mode',t.nspname,t.relname);
 end loop;
 lock table storage.objects in share mode;
 if not exists(select 1 from public.clinics where id=target_clinic and name=target_name and created_by=target_user) then raise exception 'reviewed_clinic_identity_changed';end if;
 if (select count(*) from public.clinic_members where user_id=target_user)<>1 or (select count(*) from public.clinic_members where clinic_id=target_clinic)<>1 or not exists(select 1 from public.clinic_members where clinic_id=target_clinic and user_id=target_user and role='admin') then raise exception 'reviewed_membership_changed';end if;
 if not exists(select 1 from public.account_workspaces where clinic_id=target_clinic and kind='clinic' and owner_id is null) then raise exception 'reviewed_workspace_changed';end if;
 if not exists(select 1 from private.workspace_usage where clinic_id=target_clinic and bytes=0) then raise exception 'workspace_has_storage_usage';end if;
 if exists(select 1 from storage.objects where name like target_clinic::text||'/%') then raise exception 'clinic_has_files';end if;
 for t in select distinct n.nspname,c.relname,a.attname from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped where c.relkind='r' and n.nspname in ('public','private') and (a.attname='clinic_id' or exists(select 1 from pg_constraint f where f.contype='f' and f.conrelid=c.oid and f.confrelid='public.clinics'::regclass and cardinality(f.conkey)=1 and f.conkey[1]=a.attnum)) order by n.nspname,c.relname,a.attname loop
  execute format('select count(*) from %I.%I where %I::text=$1',t.nspname,t.relname,t.attname) into rows_found using target_clinic::text;
  if t.nspname='public' and t.relname='audit_log' then
   if rows_found<>2 or exists(select 1 from public.audit_log where clinic_id=target_clinic and (action not in ('clinic_created','member_joined') or actor_id is distinct from target_user)) then raise exception 'reviewed_audit_changed';end if;
  elsif (t.nspname,t.relname) in (('public','clinic_members'),('public','account_workspaces'),('private','workspace_usage')) then
   if rows_found<>1 then raise exception 'reviewed_configuration_changed';end if;
  elsif rows_found<>0 then
   raise exception 'clinic_no_longer_empty';
  end if;
 end loop;
 select jsonb_agg(to_jsonb(a) order by a.id) into old_audit from public.audit_log a where clinic_id=target_clinic;
 -- FK-dependent bookkeeping is the only explicit data removal besides the clinic.
 delete from private.workspace_usage where clinic_id=target_clinic;
 delete from public.account_workspaces where clinic_id=target_clinic;
 -- The legacy last-admin trigger also rejects parent CASCADE deletes. It is
 -- disabled only under this transaction's exclusive table lock and restored before commit.
 alter table public.clinic_members disable trigger prevent_last_clinic_admin_removal;
 delete from public.clinics where id=target_clinic;
 alter table public.clinic_members enable trigger prevent_last_clinic_admin_removal;
 if exists(select 1 from public.clinic_members where user_id=target_user) then raise exception 'account_still_has_memberships';end if;
 if not private.beta_bootstrap_admin(target_email) then raise exception 'platform_bootstrap_failed';end if;
 insert into private.beta_audit(action,entity_id,reason) values('empty_clinic_converted_to_platform',target_clinic::text,jsonb_build_object('clinic_name',target_name,'preserved_creation_audit',old_audit,'authorization','Owner approved deleting this exact empty clinic and retaining the account')::text);
 if not exists(select 1 from pg_trigger where tgrelid='public.clinic_members'::regclass and tgname='prevent_last_clinic_admin_removal' and tgenabled='O') then raise exception 'membership_protection_not_restored';end if;
end
$conversion$;
commit;
