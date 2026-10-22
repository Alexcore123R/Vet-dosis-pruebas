create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);
insert into public.vet_owners(clinic_id,name,phone,email,created_by) values(:'clinic','Synthetic authorized contact','+5215551112222','synthetic@example.test',auth.uid()) returning id as owner \gset
insert into public.vet_patients(clinic_id,name,species,sex,owner_id,created_by) values(:'clinic','Synthetic message patient','synthetic','sin especificar',:'owner',auth.uid()) returning id as patient \gset
insert into public.clinic_appointments(clinic_id,patient_id,patient_name,species,kind,professional_id,starts_at,ends_at,created_by) values(:'clinic',:'patient','Synthetic message patient','synthetic','consulta','00000000-0000-0000-0000-000000000151',now()+interval '1 day',now()+interval '1 day 1 hour',auth.uid()) returning id as appointment \gset
set role authenticated;
select public.permission_grant(:'clinic',auth.uid(),'appointment.read',null,now()+interval '1 day','Synthetic appointment read');
select public.permission_grant(:'clinic',auth.uid(),'patient.read',null,now()+interval '1 day','Synthetic patient read');
select public.permission_grant(:'clinic',auth.uid(),'patient.write',null,now()+interval '1 day','Synthetic consent recording');
select public.ops_service_contact_save(:'clinic',:'owner','appointment',true,false,'Synthetic written authorization');
select pg_temp.assert_true((public.ops_appointment_contact(:'clinic',:'appointment')->'preferences'->'appointment'->>'whatsapp_allowed')::boolean,'appointment consent not saved');
select pg_temp.assert_true(public.ops_appointment_contact(:'clinic',:'appointment')->'preferences'->'follow_up' is null,'reminder consent implied follow-up consent');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.ops_client_directory(:'clinic')) c where c->>'id'=:'owner' and (c->>'whatsapp_allowed')::boolean),'service consent implied marketing consent');
select public.ops_service_contact_save(:'clinic',:'owner','appointment',false,false,'Synthetic revocation');
select pg_temp.assert_true(not (public.ops_appointment_contact(:'clinic',:'appointment')->'preferences'->'appointment'->>'whatsapp_allowed')::boolean,'revoked consent still returned');
select pg_temp.expect_error(format('select public.ops_service_contact_save(%L,%L,%L,true,false,%L)',:'clinic',:'owner','follow_up',''),'contact_consent_source_required');
select public.ops_promotion_save(:'clinic','{"kind":"promocion","title":"Synthetic promotion","message":"Synthetic message","service_name":"Grooming","conditions":"Synthetic conditions","discount_percent":"10","starts_on":"2026-10-22","ends_on":"2026-10-31"}') as promotion \gset
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.ops_promotions(:'clinic')) p where p->>'id'=:'promotion' and p->>'conditions'='Synthetic conditions' and p->>'service_name'='Grooming'),'structured promotion fields not persisted');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000181','inventory.read',null,now()+interval '1 day','Synthetic stock-only analysis');
reset role;
insert into public.inventario(clinic_id,user_id,nombre,m8_enabled,m8_kind,stock_unit,stock_minimo,reorder_point) values(:'clinic','00000000-0000-0000-0000-000000000150','Synthetic insight product',true,'producto','unidad',5,6) returning id as item \gset
insert into public.lotes_inventario(clinic_id,user_id,item_id,lote,caducidad,cantidad,costo_unitario) values
(:'clinic','00000000-0000-0000-0000-000000000150',:'item','EXPIRED',current_date-1,20,1),
(:'clinic','00000000-0000-0000-0000-000000000150',:'item','SOON',current_date+10,2,1),
(:'clinic','00000000-0000-0000-0000-000000000150',:'item','FUTURE',current_date+200,2,1);
insert into public.inventory_cash_shifts(clinic_id,cashier_id,opening_cash,timezone,closed_at,counted_cash) values(:'clinic','00000000-0000-0000-0000-000000000150',0,'UTC',now(),0) returning id as shift \gset
insert into public.inventory_sales(clinic_id,shift_id,cashier_id,method,total,cost,commission,created_at) values(:'clinic',:'shift','00000000-0000-0000-0000-000000000150','efectivo',80,8,0,now()-interval '40 days') returning id as previous_sale \gset
insert into public.inventory_sales(clinic_id,shift_id,cashier_id,method,total,cost,commission,created_at) values(:'clinic',:'shift','00000000-0000-0000-0000-000000000150','efectivo',30,3,0,now()) returning id as current_sale \gset
insert into public.inventory_sale_lines(clinic_id,sale_id,kind,item_id,name,quantity,price,cost,total,metadata) values
(:'clinic',:'previous_sale','producto',:'item','Synthetic insight product',8,10,8,80,'{}'),(:'clinic',:'current_sale','producto',:'item','Synthetic insight product',3,10,3,30,'{}');
insert into public.inventory_sale_reversals(clinic_id,sale_id,shift_id,reason,created_by) values(:'clinic',:'previous_sale',:'shift','Synthetic reversal','00000000-0000-0000-0000-000000000150');
set role authenticated;
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.inv_ai_insights(:'clinic')->'products') p where p->>'id'=:'item' and (p->>'available')::numeric=4 and (p->>'low_stock')::boolean),'expired stock was available or shortage was missed');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.inv_ai_insights(:'clinic')->'lots') l where l->>'lot'='SOON' and (l->>'days')::integer between 9 and 11),'upcoming lot missing');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.inv_ai_insights(:'clinic')->'lots') l where l->>'lot'='FUTURE'),'lot outside 90-day window leaked');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.inv_ai_insights(:'clinic')->'sales') s where s->>'item_id'=:'item' and (s->>'current_quantity')::numeric=-5 and (s->>'previous_quantity')::numeric=8 and (s->>'current_amount')::numeric=-50),'sales periods or returns calculated incorrectly');
reset role;select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',false);set role authenticated;
select pg_temp.assert_true(public.inv_ai_insights(:'clinic')->'sales'='[]'::jsonb and not (public.inv_ai_insights(:'clinic')->>'sales_allowed')::boolean,'inventory-only user saw sales');
select pg_temp.expect_error(format('select public.ops_service_contact_save(%L,%L,%L,true,false,%L)',:'clinic',:'owner','appointment','Unauthorized write'),'explicit_permission_required');
reset role;set role anon;
select pg_temp.expect_error(format('select public.inv_ai_insights(%L)',:'clinic'),'permission denied');
reset role;
