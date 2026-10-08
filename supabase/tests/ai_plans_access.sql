\set ON_ERROR_STOP on
begin;
insert into auth.users values ('00000000-0000-0000-0000-000000000091','admin91@example.test',now()),('00000000-0000-0000-0000-000000000092','mvz92@example.test',now()),('00000000-0000-0000-0000-000000000093','aux93@example.test',now()),('00000000-0000-0000-0000-000000000094','outside94@example.test',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000091',true);
select public.create_clinic('AI planes ficticios') as clinic \gset
select set_config('test.ai_clinic',:'clinic',true);
reset role;
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000000092','mvz'),(:'clinic','00000000-0000-0000-0000-000000000093','auxiliar');
set local role service_role;
select public.plan_grant_server(:'clinic','clinic','beta',now()-interval '1 minute',now()+interval '2 days','beta-fixture');
select public.ai_key_store_server('00000000-0000-0000-0000-000000000092','personal',null,'openai',repeat('cipher-fixture',4),repeat('nonce',5)) as connection \gset
select set_config('test.ai_key',:'connection',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',true);
select public.personal_workspace_create() as personal \gset
select set_config('test.personal',:'personal',true);
select public.personal_workspace_create() as same_personal \gset
select public.ai_chat_create(:'clinic','Privado excluido',repeat('a1',24)) as excluded \gset
select public.ai_chat_create(:'clinic','Personal permitido',repeat('a2',24)) as personal_chat \gset
select public.ai_chat_policy(:'personal_chat',1,'private','personal','{}');
select public.ai_chat_create(:'clinic','Compartido solo MVZ',repeat('a3',24)) as shared \gset
select public.ai_chat_policy(:'shared',1,'clinic','clinic',array['mvz']);
select public.ai_chat_create(:'clinic','Chat actual',repeat('a4',24)) as current_chat \gset
select set_config('test.chat',:'current_chat',true);select set_config('test.excluded',:'excluded',true);select set_config('test.shared',:'shared',true);
reset role;
insert into public.ai_messages(clinic_id,chat_id,role,body,created_by) values(:'clinic',:'excluded','user','NO COMPARTIR EXCLUIDO','00000000-0000-0000-0000-000000000092'),(:'clinic',:'personal_chat','user','CONTEXTO PERSONAL PERMITIDO','00000000-0000-0000-0000-000000000092'),(:'clinic',:'shared','user','CONTEXTO PARA MVZ','00000000-0000-0000-0000-000000000092');
set local role authenticated;
select public.ai_prepare(:'current_chat',:'connection','modelo-ficticio','Pregunta ficticia',repeat('a5',24),true,true)->>'id' as request \gset
select set_config('test.ai_request',:'request',true);
select public.ai_prepare(:'current_chat',:'connection','modelo-ficticio','Pregunta ficticia',repeat('a5',24),true,true);
do $$begin
 if public.ai_dashboard(current_setting('test.ai_clinic')::uuid)::text like '%cipher-fixture%' then raise exception 'ciphertext in client dashboard';end if;
 begin perform public.plan_grant_server(current_setting('test.personal')::uuid,'individual','gift',now(),now()+interval '1 year','forged');raise exception 'user forged plan';exception when insufficient_privilege then null;end;
 begin perform public.ai_key_get_server(auth.uid(),current_setting('test.ai_key')::uuid);raise exception 'user reads key';exception when insufficient_privilege then null;end;
 begin perform public.create_clinic_invitation(current_setting('test.personal')::uuid,'fake@example.test','auxiliar');raise exception 'personal workspace invited members';exception when others then if sqlerrm<>'clinic_plan_required' then raise;end if;end;
 begin perform public.ops_write(current_setting('test.personal')::uuid,'message','{"category":"general","body":"No equipo"}',repeat('a6',24));raise exception 'personal team chat';exception when others then if sqlerrm<>'clinic_plan_required' then raise;end if;end;
end$$;
set local role service_role;
select set_config('test.ai_snapshot',public.ai_claim_server(:'request','00000000-0000-0000-0000-000000000092')::text,true);
do $$begin
 if current_setting('test.ai_snapshot') like '%NO COMPARTIR EXCLUIDO%' then raise exception 'excluded chat entered prompt';end if;
 if current_setting('test.ai_snapshot') not like '%CONTEXTO PERSONAL PERMITIDO%' or current_setting('test.ai_snapshot') not like '%CONTEXTO PARA MVZ%' then raise exception 'authorized context missing';end if;
 begin perform public.ai_claim_server(current_setting('test.ai_request')::uuid,'00000000-0000-0000-0000-000000000092');raise exception 'double model call';exception when others then if sqlerrm<>'request_already_claimed' then raise;end if;end;
end$$;
select public.ai_finish_server(:'request','00000000-0000-0000-0000-000000000092','Respuesta ficticia sin verificar',true);
set local role authenticated;
select public.ai_chat_policy(:'shared',2,'private','none','{}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000091',true);
do $$begin
 begin perform public.ai_messages_read(current_setting('test.shared')::uuid);raise exception 'admin reads owner private chat';exception when others then if sqlerrm<>'access_denied' then raise;end if;end;
 begin perform public.ai_chat_policy(current_setting('test.shared')::uuid,3,'clinic','clinic',array['admin']);raise exception 'admin overrides private policy';exception when others then if sqlerrm<>'owner_required' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000093',true);
do $$begin
 begin perform public.ai_messages_read(current_setting('test.excluded')::uuid);raise exception 'aux reads private chat';exception when others then if sqlerrm<>'access_denied' then raise;end if;end;
end$$;
-- Free limits; direct trusted fixture insertion also encounters the server quota.
reset role;
insert into public.vet_patients(clinic_id,name,species,sex,created_by) select :'personal','Ficticio '||n,'Especie ficticia','sin especificar','00000000-0000-0000-0000-000000000092' from generate_series(1,50) n;
do $$begin
 begin insert into public.vet_patients(clinic_id,name,species,sex,created_by) values(current_setting('test.personal')::uuid,'Límite excedido','Especie ficticia','sin especificar','00000000-0000-0000-0000-000000000092');raise exception 'free patient cap bypassed';exception when others then if sqlerrm<>'patient_plan_limit' then raise;end if;end;
 begin insert into public.clinic_members(clinic_id,user_id,role) values(current_setting('test.personal')::uuid,'00000000-0000-0000-0000-000000000093','auxiliar');raise exception 'personal access shared';exception when others then if sqlerrm<>'personal_workspace_cannot_share' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',true);
-- Daily cap survives deletion; original role/membership does not change with plan.
select public.ai_chat_create(:'personal','Cuota IA ficticia',repeat('b8',24)) as quota_chat \gset
select set_config('test.quota_chat',:'quota_chat',true);
do $$declare n integer;request uuid;begin
 for n in 1..5 loop
 request=(public.ai_prepare(current_setting('test.quota_chat')::uuid,current_setting('test.ai_key')::uuid,'modelo-ficticio','Mensaje '||n,lpad(n::text,48,'c'),false,false)->>'id')::uuid;
 perform public.ai_claim_server(request,'00000000-0000-0000-0000-000000000092');perform public.ai_finish_server(request,'00000000-0000-0000-0000-000000000092','',false);
 end loop;
 begin perform public.ai_prepare(current_setting('test.quota_chat')::uuid,current_setting('test.ai_key')::uuid,'modelo-ficticio','Excedido',repeat('b9',24),false,false);raise exception 'free daily cap bypassed';exception when others then if sqlerrm<>'ai_daily_limit' then raise;end if;end;
 perform public.ai_chat_delete(current_setting('test.quota_chat')::uuid);
 if public.ai_dashboard(current_setting('test.personal')::uuid)->>'daily_used'<>'5' then raise exception 'deleted quota reset';end if;
end$$;
-- Conservative 4MB photo reservation is enforced under the same serialized budget.
insert into public.inventario(clinic_id,nombre,m8_enabled,created_at) values(:'personal','Producto ficticio para cuota',true,now()) returning id as quota_product \gset
select set_config('test.quota_product',:'quota_product',true);
select set_config('test.original_usage',(select bytes::text from private.workspace_usage where clinic_id=:'personal'),true);
update private.workspace_usage set bytes=(select storage_bytes-1 from public.subscription_plans where code='free') where clinic_id=:'personal';
do $$begin
 begin insert into storage.objects(bucket_id,name) values('inventory-photos',current_setting('test.personal')||'/'||current_setting('test.quota_product')||'/'||repeat('a',48)||'.png');raise exception 'storage quota bypassed';exception when others then if sqlerrm<>'storage_plan_limit' then raise;end if;end;
end$$;
update private.workspace_usage set bytes=current_setting('test.original_usage')::bigint where clinic_id=:'personal';

-- Requests do not activate paid benefits; draft pricing cannot start checkout.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',true);
select public.plan_request(:'personal','individual','monthly',repeat('b1',24)) as plan_request \gset
select set_config('test.plan_request',:'plan_request',true);
do $$begin
 if public.plan_dashboard(current_setting('test.personal')::uuid)->'effective'->>'code'<>'free' then raise exception 'interest activated paid plan';end if;
 begin perform public.billing_request_read(current_setting('test.plan_request')::uuid);raise exception 'draft price checkout enabled';exception when others then if sqlerrm<>'pricing_not_published' then raise;end if;end;
end$$;
-- Operator publishes inside isolated fixture only; a confirmed invoice grants exactly once.
reset role;
update public.subscription_plans set published=true where code='individual';
set local role service_role;
select public.reward_credit_server('00000000-0000-0000-0000-000000000092',1000,'reward-fixture','Prueba aislada');
reset role;
update private.reward_policy set enabled=true;
set local role authenticated;
select public.reward_redeem(:'personal',repeat('b2',24));
select public.reward_redeem(:'personal',repeat('b2',24));
do $$begin
 if public.plan_dashboard(current_setting('test.personal')::uuid)->'effective'->>'code'<>'individual' then raise exception 'paid benefit missing';end if;
 if public.plan_dashboard(current_setting('test.personal')::uuid)->>'reward_points'<>'0' then raise exception 'reward redeemed twice';end if;
end$$;
set local role service_role;
select public.billing_invoice_server(:'plan_request','invoice-fixture','subscription-fixture','event-fixture',19900,'mxn',now(),now()+interval '1 month');
select public.billing_invoice_server(:'plan_request','invoice-fixture','subscription-fixture','event-fixture',19900,'mxn',now(),now()+interval '1 month');
set local role authenticated;
-- Deleting chats never resets daily provider usage.
select public.ai_chat_delete(:'current_chat');
do $$begin if public.ai_dashboard(current_setting('test.ai_clinic')::uuid)->>'daily_used'<>'1' then raise exception 'chat delete reset rate limit';end if;end$$;
select public.ai_chat_policy(:'personal_chat',2,'private','personal','{}');
select public.ai_chat_create(:'clinic','Solicitud pendiente',repeat('bb',24)) as inflight \gset
select public.ai_prepare(:'inflight',:'connection','modelo-ficticio','Pregunta con contexto',repeat('bc',24),true,false)->>'id' as inflight_request \gset
set local role service_role;
select public.ai_claim_server(:'inflight_request','00000000-0000-0000-0000-000000000092');
set local role authenticated;
select public.ai_chat_policy(:'personal_chat',3,'private','none','{}');
set local role service_role;
select public.ai_finish_server(:'inflight_request','00000000-0000-0000-0000-000000000092','No debe verse esta respuesta',true);
set local role authenticated;
select set_config('test.inflight',:'inflight',true);
do $$begin if public.ai_messages_read(current_setting('test.inflight')::uuid)::text like '%No debe verse%' then raise exception 'revoked context leaked in answer';end if;end$$;

select public.ai_connection_disable(:'connection');
set local role service_role;
do $$begin
 begin perform public.ai_key_get_server('00000000-0000-0000-0000-000000000092',current_setting('test.ai_key')::uuid);raise exception 'revoked key readable';exception when others then if sqlerrm<>'key_access_denied' then raise;end if;end;
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000094',true);
do $$begin
 begin perform public.plan_dashboard(current_setting('test.ai_clinic')::uuid);raise exception 'outside plan read';exception when others then if sqlerrm<>'access_denied' then raise;end if;end;
 begin perform public.ai_dashboard(current_setting('test.ai_clinic')::uuid);raise exception 'outside AI read';exception when others then if sqlerrm<>'access_denied' then raise;end if;end;
end$$;
rollback;
