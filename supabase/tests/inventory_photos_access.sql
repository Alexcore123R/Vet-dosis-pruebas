begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000061',true);
select id as item,clinic_id as clinic,version as version from public.inventario where nombre='Producto sintético' \gset
select :'clinic'||'/'||:'item'||'/'||repeat('a',48)||'.jpg' as path \gset
insert into storage.objects(bucket_id,name) values('inventory-photos',:'path');
select public.inv_photo_attach(:'item',:'version',:'path');
select set_config('test.photo_path',:'path',true);
select set_config('test.photo_item',:'item',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000063',true);
do $$begin
 if (select count(*) from storage.objects)<>1 then raise exception 'Permitted reader cannot see product photo';end if;
 begin insert into storage.objects(bucket_id,name) values('inventory-photos',replace(current_setting('test.photo_path'),repeat('a',48),repeat('b',48)));raise exception 'Aux uploaded photo';exception when insufficient_privilege then null;end;
 begin update storage.objects set name=name||'changed';exception when insufficient_privilege then null;end;
 if exists(select 1 from storage.objects where name like '%changed') then raise exception 'Photo update policy bypassed';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000064',true);
do $$begin
 if exists(select 1 from storage.objects) then raise exception 'Foreign clinic photo leak';end if;
 begin perform public.inv_photo_attach(current_setting('test.photo_item')::uuid,1,current_setting('test.photo_path'));raise exception 'Foreign photo attached';exception when raise_exception then if sqlerrm<>'photo_scope_denied' then raise;end if;end;
end $$;
rollback;
