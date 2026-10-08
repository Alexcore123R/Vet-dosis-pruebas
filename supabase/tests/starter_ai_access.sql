\set ON_ERROR_STOP on
begin;
insert into auth.users values('00000000-0000-0000-0000-000000000071','starter71@example.test',now()),('00000000-0000-0000-0000-000000000072','starter72@example.test',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000071',true);
select public.personal_workspace_create()as clinic \gset
select set_config('test.starter_clinic',:'clinic',true);
do $$begin
 if (public.starter_ai_status(current_setting('test.starter_clinic')::uuid)->>'enabled')::boolean then raise exception 'default_not_off';end if;
 begin perform public.starter_ai_prepare(current_setting('test.starter_clinic')::uuid,'getting_started',repeat('s',24));raise exception 'default_call_allowed';exception when raise_exception then if sqlerrm<>'starter_ai_disabled' then raise;end if;end;
 begin update private.starter_ai_config set enabled=true;raise exception 'client_enabled_platform_key';exception when insufficient_privilege then null;end;
end $$;
reset role;update private.starter_ai_config set enabled=true,per_user_daily=2,global_daily=2;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000071',true);
select public.starter_ai_prepare(:'clinic','getting_started',repeat('s',24)) as prepared \gset
select set_config('test.starter_request',(:'prepared'::jsonb->>'id'),true);
select set_config('test.starter_chat',(:'prepared'::jsonb->>'chat'),true);
select public.starter_ai_prepare(:'clinic','getting_started',repeat('s',24));
do $$begin
 if(public.starter_ai_status(current_setting('test.starter_clinic')::uuid)->>'used')::int<>1 then raise exception 'retry_consumed_twice';end if;
 begin perform public.starter_ai_prepare(current_setting('test.starter_clinic')::uuid,'Patient data can never be a topic',repeat('t',24));raise exception 'arbitrary_topic_allowed';exception when raise_exception then if sqlerrm<>'invalid_help_topic' then raise;end if;end;
 begin perform public.starter_ai_claim_server(current_setting('test.starter_request')::uuid,auth.uid());raise exception 'client_claimed';exception when insufficient_privilege then null;end;
end $$;
set local role service_role;
select public.starter_ai_claim_server(current_setting('test.starter_request')::uuid,'00000000-0000-0000-0000-000000000071');
select public.starter_ai_finish_server(current_setting('test.starter_request')::uuid,'00000000-0000-0000-0000-000000000071','Respuesta ficticia de ayuda',true);
set local role authenticated;
select public.ai_chat_delete(current_setting('test.starter_chat')::uuid);
select public.starter_ai_prepare(:'clinic','privacy',repeat('p',24))as second \gset
select set_config('test.starter_second',(:'second'::jsonb->>'id'),true);
do $$begin
 begin perform public.starter_ai_prepare(current_setting('test.starter_clinic')::uuid,'permissions',repeat('u',24));raise exception 'quota_reset_by_delete';exception when raise_exception then if sqlerrm<>'starter_ai_daily_limit' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000072',true);
do $$begin
 begin perform public.starter_ai_status(current_setting('test.starter_clinic')::uuid);raise exception 'other_space_read';exception when raise_exception then if sqlerrm<>'access_denied' then raise;end if;end;
end $$;
select public.personal_workspace_create()as other \gset
select set_config('test.starter_other',:'other',true);
do $$begin
 begin perform public.starter_ai_prepare(current_setting('test.starter_other')::uuid,'permissions',repeat('u',24));raise exception 'global_quota_bypassed';exception when raise_exception then if sqlerrm<>'starter_ai_daily_limit' then raise;end if;end;
end $$;
reset role;
update private.starter_ai_config set enabled=false;
set local role service_role;
do $$begin
 begin perform public.starter_ai_claim_server(current_setting('test.starter_second')::uuid,'00000000-0000-0000-0000-000000000071');raise exception 'disabled_service_claim';exception when raise_exception then if sqlerrm<>'access_denied' then raise;end if;end;
end $$;
rollback;
