-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Después de etapas 1-6.
-- Ejecutar 07A hasta 07E en orden. No activa cobros ni proveedores IA.
begin;

-- existing_inventory_photos_m8.sql

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


-- existing_plan_files_m13.sql

create function private.plan_artifact_budget() returns trigger language plpgsql security definer set search_path='' as $$declare scope uuid;item jsonb;delta bigint;used bigint;begin
 item=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 if tg_table_name='form_artifacts' then select clinic_id into scope from public.form_documents where id=(item->>'document_id')::uuid;
 elsif tg_table_name='rx_artifacts' then if item->>'kind'='prescription' then select clinic_id into scope from public.prescriptions where id=(item->>'entity_id')::uuid;else select clinic_id into scope from public.controlled_drug_reports where id=(item->>'entity_id')::uuid;end if;
 else select clinic_id into scope from public.professional_profiles where id=(item->>'profile_id')::uuid;end if;
 if scope is null then raise exception 'artifact_scope_required';end if;
 delta=case when tg_op='DELETE' then -octet_length(to_jsonb(old)::text) when tg_op='UPDATE' then octet_length(to_jsonb(new)::text)-octet_length(to_jsonb(old)::text) else octet_length(to_jsonb(new)::text) end;
 select bytes into used from private.workspace_usage where clinic_id=scope for update;
 if delta>0 and used+delta>(private.plan_for(scope)).storage_bytes then raise exception 'storage_plan_limit';end if;
 update private.workspace_usage set bytes=greatest(0,bytes+delta) where clinic_id=scope;
 if tg_op='DELETE' then return old;end if;return new;
end$$;
create trigger plan_artifact_budget after insert or update or delete on private.form_artifacts for each row execute function private.plan_artifact_budget();
create trigger plan_artifact_budget after insert or update or delete on private.rx_artifacts for each row execute function private.plan_artifact_budget();
create trigger plan_artifact_budget after insert or update or delete on private.professional_profile_versions for each row execute function private.plan_artifact_budget();
update private.workspace_usage u set bytes=bytes+(select coalesce(sum(octet_length(to_jsonb(a)::text)),0) from private.form_artifacts a join public.form_documents d on d.id=a.document_id where d.clinic_id=u.clinic_id)+(select coalesce(sum(octet_length(to_jsonb(a)::text)),0) from private.professional_profile_versions a join public.professional_profiles p on p.id=a.profile_id where p.clinic_id=u.clinic_id)+(select coalesce(sum(octet_length(to_jsonb(a)::text)),0) from private.rx_artifacts a where (a.kind='prescription' and exists(select 1 from public.prescriptions r where r.id=a.entity_id and r.clinic_id=u.clinic_id)) or (a.kind='report' and exists(select 1 from public.controlled_drug_reports r where r.id=a.entity_id and r.clinic_id=u.clinic_id)));
create function private.plan_photo_budget() returns trigger language plpgsql security definer set search_path='' as $$declare scope uuid;item jsonb;delta bigint;used bigint;begin
 item=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 if item->>'bucket_id'<>'inventory-photos' then if tg_op='DELETE' then return old;end if;return new;end if;
 scope=split_part(item->>'name','/',1)::uuid;
 if tg_op='UPDATE' then if old.name<>new.name or old.bucket_id<>new.bucket_id then raise exception 'photo_cannot_move';end if;return new;end if;
 delta=case when tg_op='DELETE' then -4194304 else 4194304 end;
 select bytes into used from private.workspace_usage where clinic_id=scope for update;
 if used is null then raise exception 'photo_scope_required';end if;
 if delta>0 and used+delta>(private.plan_for(scope)).storage_bytes then raise exception 'storage_plan_limit';end if;
 update private.workspace_usage set bytes=greatest(0,bytes+delta) where clinic_id=scope;
 if tg_op='DELETE' then return old;end if;return new;
end$$;
update private.workspace_usage u set bytes=bytes+(select count(*)*4194304 from storage.objects where bucket_id='inventory-photos' and split_part(name,'/',1)=u.clinic_id::text);
create trigger plan_photo_budget after insert or update or delete on storage.objects for each row execute function private.plan_photo_budget();
revoke all on function private.plan_artifact_budget(),private.plan_photo_budget() from public,anon,authenticated;


-- existing_ai_plan_export.sql

alter function private.clinic_snapshot(uuid) rename to clinic_snapshot_before_ai_plans;
revoke all on function private.clinic_snapshot_before_ai_plans(uuid) from public,anon,authenticated;
create function private.clinic_snapshot(p_clinic uuid) returns text language plpgsql stable security definer set search_path='' as $$declare s jsonb;begin
 s=private.clinic_snapshot_before_ai_plans(p_clinic)::jsonb;
 s=jsonb_set(s,'{tables,my_ai_chats}',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from public.ai_chats c where clinic_id=p_clinic and owner_id=auth.uid()));
 s=jsonb_set(s,'{tables,my_ai_messages}',(select coalesce(jsonb_agg(to_jsonb(m)),'[]') from public.ai_messages m join public.ai_chats c on c.id=m.chat_id where c.clinic_id=p_clinic and c.owner_id=auth.uid()));
 s=jsonb_set(s,'{tables,subscription_grants}',(select coalesce(jsonb_agg(to_jsonb(g)),'[]') from public.subscription_grants g where clinic_id=p_clinic));
 s=jsonb_set(s,'{tables,subscription_requests}',(select coalesce(jsonb_agg(to_jsonb(g)),'[]') from public.subscription_requests g where clinic_id=p_clinic));
 s=jsonb_set(s,'{tables,subscription_payments}',(select coalesce(jsonb_agg(to_jsonb(g)),'[]') from public.subscription_payments g where clinic_id=p_clinic));
 s=jsonb_set(s,'{tables,account_workspaces}',(select coalesce(jsonb_agg(to_jsonb(g)),'[]') from public.account_workspaces g where clinic_id=p_clinic));
 return s::text;
end$$;
revoke all on function private.clinic_snapshot(uuid) from public,anon,authenticated;

notify pgrst, 'reload schema';
commit;
select '07C COMPLETADO: archivos privados, cuotas y exportacion' as resultado;
-- FIN COMPLETO 07C
