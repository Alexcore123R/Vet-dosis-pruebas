-- Optional M8 photo storage, AFTER M8. Supabase Storage required.
begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('inventory-photos','inventory-photos',false,4194304,array['image/jpeg','image/png']);
create function private.inv_photo_allowed(p_path text,p_write boolean) returns boolean language plpgsql stable security definer set search_path='' as $$
declare clinic uuid;item uuid;
begin
 if p_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{48}\.(jpg|png)$' then return false;end if;
 begin clinic=split_part(p_path,'/',1)::uuid;item=split_part(p_path,'/',2)::uuid;exception when invalid_text_representation then return false;end;
 return exists(select 1 from public.inventario where id=item and clinic_id=clinic and m8_enabled) and case when p_write then private.has_clinic_role(clinic,array['admin']) else private.inv_access(clinic) end;
end $$;
revoke all on function private.inv_photo_allowed(text,boolean) from public,anon;grant execute on function private.inv_photo_allowed(text,boolean) to authenticated;
create policy inv_photo_read on storage.objects for select to authenticated using(bucket_id='inventory-photos' and private.inv_photo_allowed(name,false));
create policy inv_photo_insert on storage.objects for insert to authenticated with check(bucket_id='inventory-photos' and private.inv_photo_allowed(name,true));
-- No overwrite/delete policies; old files are not overwritten. Cleanup is a privileged maintenance operation.
create function public.inv_photo_attach(p_item uuid,p_version integer,p_path text) returns void language plpgsql security definer set search_path='' as $$
declare i public.inventario;
begin
 select * into i from public.inventario where id=p_item for update;
 if not found or not private.has_clinic_role(i.clinic_id,array['admin']) or not private.inv_photo_allowed(p_path,true) or split_part(p_path,'/',2)<>i.id::text then raise exception 'photo_scope_denied';end if;
 if i.version<>p_version then raise exception 'product_revision_conflict_or_legacy';end if;
 if not exists(select 1 from storage.objects where bucket_id='inventory-photos' and name=p_path) then raise exception 'photo_upload_required';end if;
 update public.inventario set photo_path=p_path,version=version+1 where id=i.id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(i.clinic_id,auth.uid(),'inventory_photo_attached',i.id);
end $$;
revoke all on function public.inv_photo_attach(uuid,integer,text) from public,anon;grant execute on function public.inv_photo_attach(uuid,integer,text) to authenticated;
commit;
