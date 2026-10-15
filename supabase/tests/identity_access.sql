begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('10000000-0000-0000-0000-000000000001','a@example.test',now()),
 ('10000000-0000-0000-0000-000000000002','b@example.test',now()),
 ('10000000-0000-0000-0000-000000000003','c@example.test',now());
insert into public.clinics(id,name,created_by) values
 ('20000000-0000-0000-0000-000000000001','Clínica A','10000000-0000-0000-0000-000000000001'),
 ('20000000-0000-0000-0000-000000000002','Clínica B','10000000-0000-0000-0000-000000000002');
insert into public.clinic_members(clinic_id,user_id,role) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','admin'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','admin'),
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','recepcion');
set local role anon;
do $$begin
 begin perform public.account_identity_get();raise exception 'anon_allowed';exception when insufficient_privilege then null;end;
 begin perform public.clinic_identity_get('20000000-0000-0000-0000-000000000001');raise exception 'anon_clinic_allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select public.account_identity_save(2,false);
do $$begin
 if public.account_identity_get()->>'icon'<>'2' then raise exception 'icon_not_saved';end if;
 begin perform public.account_identity_save(5,false);raise exception 'bad_icon_allowed';exception when raise_exception then if sqlerrm<>'invalid_identity' then raise;end if;end;
 begin perform public.account_identity_save(2,true);raise exception 'missing_photo_allowed';exception when raise_exception then if sqlerrm<>'avatar_upload_required' then raise;end if;end;
 begin insert into public.account_identity(user_id,icon) values(auth.uid(),3);raise exception 'direct_write_allowed';exception when insufficient_privilege then null;end;
end $$;
insert into storage.objects(bucket_id,name) values('account-avatars',auth.uid()::text||'/avatar.png');
select public.account_identity_save(2,true);
do $$begin
 begin insert into storage.objects(bucket_id,name) values('account-avatars','10000000-0000-0000-0000-000000000002/avatar.png');raise exception 'foreign_upload_allowed';exception when insufficient_privilege then null;end;
 begin insert into storage.objects(bucket_id,name) values('account-avatars',auth.uid()::text||'/another.png');raise exception 'extra_upload_allowed';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
do $$begin
 if exists(select 1 from public.account_identity) then raise exception 'other_account_visible';end if;
 if exists(select 1 from storage.objects where bucket_id='account-avatars') then raise exception 'other_avatar_visible';end if;
 if public.account_identity_get()->>'icon'<>'0' then raise exception 'other_icon_visible';end if;
 delete from storage.objects where bucket_id='account-avatars';
 if found then raise exception 'foreign_avatar_deleted';end if;
 update storage.objects set name=auth.uid()::text||'/avatar.png' where bucket_id='account-avatars';
 if found then raise exception 'foreign_avatar_updated';end if;
 begin perform public.clinic_identity_get('20000000-0000-0000-0000-000000000001');raise exception 'foreign_clinic_visible';exception when raise_exception then if sqlerrm<>'clinic_membership_required' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
do $$declare brand jsonb;begin
 brand:=public.clinic_identity_get('20000000-0000-0000-0000-000000000001');
 if brand->>'name'<>'Clínica A' or (select count(*) from jsonb_object_keys(brand))<>5 then raise exception 'identity_projection_invalid';end if;
 begin perform public.form_branding('20000000-0000-0000-0000-000000000001');raise exception 'clinical_access_expanded';exception when raise_exception then if sqlerrm<>'clinical_role_required' then raise;end if;end;
 begin perform public.form_branding_save('20000000-0000-0000-0000-000000000001','{}');raise exception 'branding_write_expanded';exception when raise_exception then if sqlerrm<>'clinic_admin_required' then raise;end if;end;
end $$;
reset role;
delete from public.clinic_members where user_id='10000000-0000-0000-0000-000000000003';
set local role authenticated;
do $$begin
 begin perform public.clinic_identity_get('20000000-0000-0000-0000-000000000001');raise exception 'revoked_member_visible';exception when raise_exception then if sqlerrm<>'clinic_membership_required' then raise;end if;end;
end $$;
reset role;
do $$begin
 if not exists(select 1 from storage.buckets where id='account-avatars' and public=false and file_size_limit=500000 and allowed_mime_types=array['image/png']) then raise exception 'bucket_unbounded';end if;
end $$;
rollback;
