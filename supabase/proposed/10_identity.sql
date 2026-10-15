-- Additive identity migration. Requires M2, Forms phase 1 and Supabase Storage.
-- No clinical permissions change. Review before applying to the test project.
begin;
create table public.account_identity (
 user_id uuid primary key references auth.users(id) on delete cascade,
 icon integer not null default 0 check(icon between 0 and 4),
 photo_path text,
 updated_at timestamptz not null default now(),
 check(photo_path is null or photo_path=user_id::text||'/avatar.png')
);
alter table public.account_identity enable row level security;
revoke all on public.account_identity from public,anon,authenticated;
grant select on public.account_identity to authenticated;
create policy account_identity_owner on public.account_identity for select to authenticated using(user_id=auth.uid());
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('account-avatars','account-avatars',false,500000,array['image/png']);
create policy account_avatar_read on storage.objects for select to authenticated
 using(bucket_id='account-avatars' and name=auth.uid()::text||'/avatar.png');
create policy account_avatar_insert on storage.objects for insert to authenticated
 with check(bucket_id='account-avatars' and name=auth.uid()::text||'/avatar.png');
create policy account_avatar_update on storage.objects for update to authenticated
 using(bucket_id='account-avatars' and name=auth.uid()::text||'/avatar.png')
 with check(bucket_id='account-avatars' and name=auth.uid()::text||'/avatar.png');
create policy account_avatar_delete on storage.objects for delete to authenticated
 using(bucket_id='account-avatars' and name=auth.uid()::text||'/avatar.png');
create function public.account_identity_get() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 return coalesce((select jsonb_build_object('icon',icon,'photo_path',photo_path,'configured',true) from public.account_identity where user_id=auth.uid()),jsonb_build_object('icon',0,'photo_path',null,'configured',false));
end $$;
create function public.account_identity_save(p_icon integer,p_photo boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 if p_icon is null or p_icon not between 0 and 4 or p_photo is null then raise exception 'invalid_identity';end if;
 if p_photo and not exists(select 1 from storage.objects where bucket_id='account-avatars' and name=auth.uid()::text||'/avatar.png') then raise exception 'avatar_upload_required';end if;
 insert into public.account_identity(user_id,icon,photo_path) values(auth.uid(),p_icon,case when p_photo then auth.uid()::text||'/avatar.png' end)
 on conflict(user_id) do update set icon=excluded.icon,photo_path=excluded.photo_path,updated_at=now();
end $$;
create function public.clinic_identity_get(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare brand jsonb;
begin
 if not private.has_clinic_role(p_clinic) then raise exception 'clinic_membership_required';end if;
 select branding into brand from public.clinic_document_settings where clinic_id=p_clinic order by created_at desc,id desc limit 1;
 return jsonb_build_object('clinic_id',p_clinic,'name',(select name from public.clinics where id=p_clinic),'header',coalesce(brand->>'header',''),'logo',brand->>'logo','include_logo',coalesce((brand->>'include_logo')::boolean,false));
end $$;
revoke all on function public.account_identity_get(), public.account_identity_save(integer,boolean),public.clinic_identity_get(uuid) from public,anon;
grant execute on function public.account_identity_get(), public.account_identity_save(integer,boolean),public.clinic_identity_get(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
