\set ON_ERROR_STOP on
begin;
insert into auth.users values
('00000000-0000-0000-0000-000000000001','admin@example.test',now()),
('00000000-0000-0000-0000-000000000002','aux@example.test',now()),
('00000000-0000-0000-0000-000000000003','outsider@example.test',now()),
('00000000-0000-0000-0000-000000000004','pending@example.test',null);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select public.create_clinic('Clínica Uno') as clinic_one \gset
select public.create_clinic('Clínica Dos') as clinic_two \gset
select public.create_clinic_invitation(:'clinic_one','aux@example.test','auxiliar') as invite \gset
select set_config('test.clinic_one',:'clinic_one',true);
select set_config('test.invite',:'invite',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
do $$ begin
 if (select count(*) from public.clinics) <> 0 then raise exception 'Cross-clinic disclosure'; end if;
 if (select count(*) from public.clinic_memberships) <> 0 then raise exception 'Membership disclosure'; end if;
 if (select count(*) from public.audit_log) <> 0 then raise exception 'Audit disclosure'; end if;
 begin
  perform public.accept_clinic_invitation(current_setting('test.invite'));
  raise exception 'Wrong email invitation accepted';
 exception when raise_exception then
  if sqlerrm <> 'invalid_invitation' then raise; end if;
 end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',true);
do $$ begin
 begin
  perform public.create_clinic('Unverified clinic');
  raise exception 'Unverified account created clinic';
 exception when raise_exception then
  if sqlerrm <> 'verified_email_required' then raise; end if;
 end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select public.accept_clinic_invitation(:'invite');
do $$ begin
 if (select count(*) from public.clinics) <> 1 then raise exception 'Clinic isolation failed'; end if;
 if (select count(*) from public.clinic_memberships) <> 1 then raise exception 'Membership isolation failed'; end if;
 if (select role from public.clinic_memberships) <> 'auxiliar' then raise exception 'Role not from invitation'; end if;
 if (select count(*) from public.audit_log) <> 0 then raise exception 'Auxiliary read audit'; end if;
 begin
  update public.clinic_memberships set role = 'admin';
  raise exception 'Client promoted role';
 exception when insufficient_privilege then null; end;
 begin
  delete from public.audit_log;
  raise exception 'Client erased audit';
 exception when insufficient_privilege then null; end;
 begin
  perform public.create_clinic_invitation(current_setting('test.clinic_one')::uuid,'outsider@example.test','admin');
  raise exception 'Auxiliary invited admin';
 exception when raise_exception then
  if sqlerrm <> 'admin_required' then raise; end if;
 end;
 begin
  perform public.accept_clinic_invitation(current_setting('test.invite'));
  raise exception 'Invitation reused';
 exception when raise_exception then
  if sqlerrm <> 'invalid_invitation' then raise; end if;
 end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
do $$ begin
 if (select count(*) from public.clinic_memberships) <> 3 then raise exception 'Admin cannot read members'; end if;
 if (select count(*) from public.audit_log) <> 7 then raise exception 'Audit incomplete'; end if;
end $$;
-- Admin can see safe invite metadata, never raw token hashes.
do $$ begin
 if (select count(id) from public.clinic_invitations) <> 1 then raise exception 'Admin cannot see invite metadata'; end if;
 begin
  perform token_hash from public.clinic_invitations;
  raise exception 'Client read token hash';
 exception when insufficient_privilege then null; end;
end $$;
select public.create_clinic_invitation(:'clinic_one','outsider@example.test','mvz') as revoked_token \gset
select id as revoked_id from public.clinic_invitations where email = 'outsider@example.test' \gset
select public.revoke_clinic_invitation(:'revoked_id');
select set_config('test.revoked',:'revoked_token',true);
select public.create_clinic_invitation(:'clinic_one','outsider@example.test','mvz') as expired_token \gset
select set_config('test.expired',:'expired_token',true);
reset role;
update public.clinic_invitations set expires_at = now() - interval '1 minute'
 where token_hash = encode(extensions.digest(:'expired_token','sha256'),'hex');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
do $$ begin
 if (select count(id) from public.clinic_invitations) <> 0 then raise exception 'Invite metadata disclosure'; end if;
 begin
  perform public.accept_clinic_invitation(current_setting('test.revoked'));
  raise exception 'Revoked invite accepted';
 exception when raise_exception then
  if sqlerrm <> 'invalid_invitation' then raise; end if;
 end;
 begin
  perform public.accept_clinic_invitation(current_setting('test.expired'));
  raise exception 'Expired invite accepted';
 exception when raise_exception then
  if sqlerrm <> 'invalid_invitation' then raise; end if;
 end;
end $$;
set local role anon;
do $$ begin
 begin
  perform count(*) from public.clinics;
  raise exception 'Anonymous clinic access';
 exception when insufficient_privilege then null; end;
 begin
  perform public.create_clinic('Anonymous clinic');
  raise exception 'Anonymous RPC access';
 exception when insufficient_privilege then null; end;
end $$;
rollback;
\echo 'PASS: clínica, roles, invitaciones y auditoría.'
