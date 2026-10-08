-- Optional file quotas AFTER M13 and inventory photo Storage adaptation.
begin;
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
commit;
