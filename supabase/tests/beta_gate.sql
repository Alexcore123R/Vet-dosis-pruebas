-- No real people or clinical references. Execute only in the isolated harness.
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000011','person+1@example.test',now()),
 ('00000000-0000-0000-0000-000000000012','invited@example.test',now()),
 ('00000000-0000-0000-0000-000000000013','unverified@example.test',null);
insert into private.beta_terms(version,content,content_hash,published,published_at) values('synthetic','SYNTHETIC ONLY','synthetic-hash',true,now());
insert into private.beta_builds(version_code,released_at) values(100,clock_timestamp());
update private.beta_policy set enforcement_enabled=true,admissions_enabled=true;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000011',false);
select set_config('request.jwt.claims','{"session_id":"11111111-0000-0000-0000-000000000011"}',false);
select set_config('request.headers','{"x-vetdosis-build":"100"}',false);
insert into private.beta_email_approvals(email,enabled,changed_by,reason) values('person+1@example.test',true,'00000000-0000-0000-0000-000000000001','Synthetic approval');
set role authenticated;
do $$begin
 if public.beta_status(100)->>'mode'<>'not_enrolled' then raise exception 'unenrolled_access';end if;
 begin perform public.beta_access_check(true);raise exception 'unenrolled_write';exception when raise_exception then if sqlerrm<>'beta_access_denied' then raise;end if;end;
 begin perform public.beta_enroll('synthetic','bad-hash');raise exception 'accepted_changed_terms';exception when raise_exception then if sqlerrm<>'beta_terms_changed' then raise;end if;end;
end$$;
select public.beta_enroll('synthetic','synthetic-hash');
do $$declare start_time timestamptz;begin
 if public.beta_status(100)->>'mode'<>'active' then raise exception 'enrollment_not_active';end if;
 perform public.beta_enroll('synthetic','synthetic-hash');
 if public.beta_status(99)->>'mode'<>'read_export' then raise exception 'unknown_build_allowed';end if;
end$$;
select public.beta_status(100);
select public.create_clinic('Beta synthetic clinic') as clinic \gset
select set_config('test.beta_clinic',:'clinic',false);
select public.beta_sponsor_accept(:'clinic');
do $$begin
 if public.beta_status(100,current_setting('test.beta_clinic')::uuid)->>'mode'<>'active' then raise exception 'sponsor_not_active';end if;
end$$;
reset role;
-- Enrollment retries never extend the original 60 days.
do $$begin
 if (select expires_at-starts_at<>interval '60 days' from private.beta_enrollments where user_id='00000000-0000-0000-0000-000000000011') then raise exception 'duration_changed';end if;
end$$;
update private.beta_enrollments set expires_at=clock_timestamp()-interval '1 second',starts_at=clock_timestamp()-interval '60 days' where user_id='00000000-0000-0000-0000-000000000011';
set role authenticated;
do $$begin
 if public.beta_status(100)->>'mode'<>'read_export' then raise exception 'expired_not_readonly';end if;
 perform public.beta_access_check(false);
 begin perform public.create_clinic('MUST FAIL');raise exception 'expired_rpc_write';exception when raise_exception then if sqlerrm<>'beta_read_export_only' then raise;end if;end;
 begin insert into storage.objects(bucket_id,name) values('synthetic','photo');raise exception 'expired_storage_write';exception when raise_exception then if sqlerrm<>'beta_read_export_only' then raise;end if;end;
end$$;
reset role;
-- Hook denies reads by a revoked user even when an old SECURITY DEFINER endpoint is used.
update private.beta_enrollments set revoked_at=clock_timestamp() where user_id='00000000-0000-0000-0000-000000000011';
set role authenticated;
select set_config('request.path','/rpc/workspace_memberships',false);
do $$begin
 begin perform private.beta_request_guard();raise exception 'revoked_rpc_read';exception when raise_exception then if sqlerrm<>'beta_access_denied' then raise;end if;end;
end$$;
select set_config('request.path','/rpc/beta_status',false);
select private.beta_request_guard();
reset role;
-- No automatic expiry deletion and immutable publications.
do $$begin
 begin update private.beta_builds set released_at=now() where version_code=100;raise exception 'build_rejuvenated';exception when raise_exception then if sqlerrm<>'beta_version_is_immutable' then raise;end if;end;
 if not exists(select 1 from private.beta_enrollments where user_id='00000000-0000-0000-0000-000000000011') then raise exception 'expired_deleted';end if;
end$$;
-- Single-use invitation, bound to a verified email; separation from professional authority.
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-0000-0000-000000000014','platform.gate@example.test',now()),('00000000-0000-0000-0000-000000000015','wrong.gate@example.test',now());
select private.beta_bootstrap_admin('platform.gate@example.test');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000014',false);
select set_config('request.jwt.claims','{"aal":"aal2"}',false);
set role authenticated;
select public.platform_beta_create_invite('invited@example.test',24)->>'token' as token \gset
select set_config('test.beta_invite',:'token',false);
do $$begin
 if public.beta_status(100)->>'mode'<>'platform_admin' then raise exception 'platform_mode_missing';end if;
end$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000013',false);
set role authenticated;
do $$begin
 begin perform public.beta_enroll('synthetic','synthetic-hash',current_setting('test.beta_invite'));raise exception 'unverified_allowed';exception when raise_exception then if sqlerrm<>'verified_email_required' then raise;end if;end;
end$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000015',false);
set role authenticated;
do $$begin
 begin perform public.beta_enroll('synthetic','synthetic-hash',current_setting('test.beta_invite'));raise exception 'wrong_email_allowed';exception when raise_exception then if sqlerrm<>'beta_invite_invalid' then raise;end if;end;
end$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000012',false);
set role authenticated;
select public.beta_enroll('synthetic','synthetic-hash',current_setting('test.beta_invite'));
select public.beta_enroll('synthetic','synthetic-hash',current_setting('test.beta_invite'));
reset role;
do $$begin
 if (select count(*) from private.beta_enrollments where user_id='00000000-0000-0000-0000-000000000012')<>1 then raise exception 'enrollment_duplicated';end if;
 if not exists(select 1 from private.beta_invites where consumed_by='00000000-0000-0000-0000-000000000012' and consumed_at is not null) then raise exception 'invite_not_consumed';end if;
 if exists(select 1 from public.clinic_members where user_id='00000000-0000-0000-0000-000000000012') then raise exception 'clinical_permission_created';end if;
end$$;
-- One grace window per loss, and expiry does not get renewed by a sponsor event.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000012',false);
select set_config('request.jwt.claims','{"session_id":"11111111-0000-0000-0000-000000000012"}',false);
select set_config('request.headers','{"x-vetdosis-build":"100"}',false);
select set_config('request.jwt.claim.sub','',false);
insert into public.clinic_members(clinic_id,user_id,role) values(current_setting('test.beta_clinic')::uuid,'00000000-0000-0000-0000-000000000012','admin');
insert into private.beta_sponsor_events(clinic_id,sponsor_id,lost_at) values(current_setting('test.beta_clinic')::uuid,'00000000-0000-0000-0000-000000000011',clock_timestamp()-interval '13 days');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000012',false);
set role authenticated;
do $$begin
 if public.beta_status(100,current_setting('test.beta_clinic')::uuid)->>'mode'<>'sponsor_grace' then raise exception 'grace_missing';end if;
end$$;
reset role;
update private.beta_sponsor_events set lost_at=clock_timestamp()-interval '14 days' where clinic_id=current_setting('test.beta_clinic')::uuid;
set role authenticated;
do $$begin
 if public.beta_status(100,current_setting('test.beta_clinic')::uuid)->>'mode'<>'read_export' then raise exception 'grace_not_expired';end if;
 begin perform public.beta_access_check(true,current_setting('test.beta_clinic')::uuid);raise exception 'expired_grace_write';exception when raise_exception then if sqlerrm<>'beta_read_export_only' then raise;end if;end;
end$$;
reset role;
-- Storage-style calls can resolve the accepted build from the authenticated session.
set role authenticated;
select public.beta_status(100);
select set_config('request.headers','{}',false);
do $$begin
 if public.beta_access_check(false)->>'mode'<>'active' then raise exception 'storage_session_build_missing';end if;
end$$;
reset role;
select set_config('request.jwt.claim.sub','',false);
insert into private.beta_builds(version_code,released_at) values(101,clock_timestamp()-interval '91 days');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000012',false);
set role authenticated;
do $$begin
 if public.beta_status(101)->>'mode'<>'read_export' then raise exception 'expired_build_allowed';end if;
end$$;
reset role;
select set_config('request.jwt.claim.sub','',false);
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-0000-0000-000000000016','race.gate@example.test',now());
insert into private.beta_invites(email,token_hash,expires_at,created_by) values('race.gate@example.test',encode(sha256(convert_to('SYNTHETIC-RACE-TOKEN','UTF8')),'hex'),clock_timestamp()+interval '1 day','00000000-0000-0000-0000-000000000014');
