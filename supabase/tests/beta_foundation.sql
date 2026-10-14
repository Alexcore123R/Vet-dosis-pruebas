-- Synthetic accounts only. Local harness creates auth.jwt; never apply test fixtures remotely.
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000001','platform@example.test',now()),
 ('00000000-0000-0000-0000-000000000002','clinical@example.test',now());
insert into private.platform_admins(user_id) values('00000000-0000-0000-0000-000000000001');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
set role authenticated;
do $$begin
 begin perform public.platform_beta_list();raise exception 'test_mfa_bypass';exception when others then if sqlerrm<>'platform_admin_mfa_required' then raise;end if;end;
end$$;
reset role;
select set_config('request.jwt.claims','{"aal":"aal2"}',false);
set role authenticated;
select public.platform_beta_set_email(' Alice+Beta@Example.Test ',true,'Synthetic approval');
do $$declare result jsonb;begin
 result=public.platform_beta_list();
 if result->'approvals'->0->>'email'<>'alice+beta@example.test' then raise exception 'normalization_failed';end if;
 if result::text like '%token_hash%' then raise exception 'hash_leak';end if;
 begin perform 1 from private.platform_admins;raise exception 'direct_table_read';exception when insufficient_privilege then null;end;
end$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
set role authenticated;
do $$begin
 begin perform public.platform_beta_set_email('self@example.test',true,'Self approval');raise exception 'test_self_approval';exception when others then if sqlerrm<>'platform_admin_mfa_required' then raise;end if;end;
end$$;
reset role;
set role anon;
do $$begin
 begin perform public.platform_beta_list();raise exception 'test_anon_access';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$declare at_time timestamptz='2026-10-14T12:00:00Z';state jsonb;begin
 if (select admissions_enabled from private.beta_policy) then raise exception 'admissions_open';end if;
 if private.beta_normalize_email(' A.B+1@Example.Test ')<>'a.b+1@example.test' then raise exception 'provider_rewrite';end if;
 begin perform private.beta_normalize_email('a b@example.test');raise exception 'accepted_invalid_email';exception when others then if sqlerrm<>'invalid_email' then raise;end if;end;
 state=private.beta_state(at_time,at_time-interval '60 days',at_time,null,null,null);
 if state->>'mode'<>'read_export' then raise exception 'expiry_boundary';end if;
 state=private.beta_state(at_time,at_time-interval '53 days',at_time+interval '7 days',null,null,null);
 if state->>'expiry_warning'<>'true' then raise exception 'warning_boundary';end if;
 state=private.beta_state(at_time,at_time-interval '10 days',at_time+interval '50 days',null,at_time-interval '14 days',null);
 if state->>'mode'<>'read_export' then raise exception 'grace_boundary';end if;
 state=private.beta_state(at_time,at_time-interval '10 days',at_time+interval '50 days',null,at_time-interval '13 days',null);
 if state->>'mode'<>'sponsor_grace' then raise exception 'grace_active';end if;
 state=private.beta_state(at_time,at_time-interval '60 days',at_time,null,at_time,null);
 if state->>'mode'<>'read_export' then raise exception 'sponsor_renewed_beta';end if;
 state=private.beta_state(at_time,at_time-interval '10 days',at_time+interval '50 days',null,null,at_time);
 if state->>'mode'<>'read_export' then raise exception 'build_expiry';end if;
 state=private.beta_state(at_time,at_time-interval '10 days',at_time+interval '50 days',at_time,null,null);
 if state->>'mode'<>'revoked' then raise exception 'revocation_precedence';end if;
end$$;
-- Administrator invite operations never expose hashes or restore revoked enrollment.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
set role authenticated;
do $$declare invite jsonb;listed jsonb;begin
 invite=public.platform_beta_create_invite(' Invited+1@Example.Test ',24);
 if length(invite->>'token')<>64 then raise exception 'token_entropy_shape';end if;
 listed=public.platform_beta_list();
 if listed::text like '%'||(invite->>'token')||'%' or listed::text like '%token_hash%' then raise exception 'invite_secret_leaked';end if;
 perform public.platform_beta_revoke_invite((invite->>'id')::uuid,'Synthetic revocation');
 listed=public.platform_beta_list();
 if listed->'invites'->0->>'revoked_at' is null then raise exception 'invite_not_revoked';end if;
end$$;
reset role;
insert into private.beta_enrollments(user_id,email,starts_at,expires_at,terms_version,terms_hash,accepted_at) values
 ('00000000-0000-0000-0000-000000000002','alice+beta@example.test',clock_timestamp(),clock_timestamp()+interval '60 days','synthetic','synthetic-hash',clock_timestamp());
set role authenticated;
select public.platform_beta_set_email(' ALICE+Beta@Example.Test ',false,'Synthetic revoke enrollment');
select public.platform_beta_set_email(' ALICE+Beta@Example.Test ',true,'Synthetic reapprove email');
reset role;
do $$begin
 if (select revoked_at from private.beta_enrollments where user_id='00000000-0000-0000-0000-000000000002') is null then raise exception 'email_reapprove_restored_access';end if;
end$$;
-- A platform account that also has clinic membership is rejected, even at aal2.
insert into public.clinics(id,name,created_by) values('00000000-0000-0000-0000-000000000100','Synthetic clinic','00000000-0000-0000-0000-000000000001');
insert into public.clinic_members(clinic_id,user_id,role) values('00000000-0000-0000-0000-000000000100','00000000-0000-0000-0000-000000000001','admin');
set role authenticated;
do $$begin
 begin perform public.platform_beta_list();raise exception 'test_shared_admin_account';exception when others then if sqlerrm<>'platform_admin_mfa_required' then raise;end if;end;
end$$;
reset role;
