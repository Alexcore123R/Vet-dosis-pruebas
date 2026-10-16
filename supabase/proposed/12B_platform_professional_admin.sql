-- Requires 11A and 12A. Administration is separate from clinical enrollment.
-- No first-MVZ verification endpoint is exposed.
begin;
create function public.platform_beta_professional_list() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform private.require_platform_admin();
 return coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'user_id',v.user_id,'email',u.email,
 'name',p.name,'license',p.license,'reviewer_id',v.reviewer_id,'reviewed_at',v.reviewed_at,
 'valid_until',v.valid_until,'evidence_hash',v.evidence_hash,'evidence_reference',v.evidence_reference,
 'revoked',exists(select 1 from private.professional_revocations r where r.verification_id=v.id)) order by v.recorded_at desc)
 from private.professional_verifications v join auth.users u on u.id=v.user_id
 join private.professional_profile_versions p on p.id=v.profile_version_id
 where v.clinic_id is null and v.origin='platform_external'),'[]');
end$$;
create function public.platform_beta_professional_revoke(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.require_platform_admin();
 perform 1 from private.professional_verifications where id=p_id and clinic_id is null and origin='platform_external' for update;
 if not found then raise exception 'global_verification_not_found';end if;
 perform public.permission_professional_revoke(p_id,p_reason);
end$$;
create or replace function private.beta_write_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare item jsonb;scope uuid;state jsonb;begin
 if not (select enforcement_enabled from private.beta_policy) then if tg_op='DELETE' then return old;end if;return new;end if;
 -- Trusted service jobs remain server-only. A security-definer RPC does not change the request role GUC.
 if auth.uid() is null and (coalesce(auth.jwt()->>'role','')='service_role' or current_setting('role',true) in ('none','postgres','service_role')) then if tg_op='DELETE' then return old;end if;return new;end if;
 item=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 if tg_table_schema='public' and tg_table_name='audit_log' and item->>'action'='operational_backup_exported' and item->>'actor_id'=auth.uid()::text then perform public.beta_access_check(false);return new;end if;
 -- Narrow legal-consent exception; direct client INSERT remains revoked.
 if tg_table_schema='public' and tg_table_name='terms_acceptances' and tg_op='INSERT'
 and item->>'user_id'=auth.uid()::text and item->>'origin'='explicit'
 and exists(select 1 from private.beta_terms t where t.version=item->>'terms_version' and t.content_hash=item->>'terms_hash' and t.published and t.version=(private.beta_latest_terms()).version)
 then return new;end if;
 -- A separate platform administrator is not a clinical beta participant.
 if tg_table_schema='private' and tg_table_name='professional_revocations' and tg_op='INSERT'
 and item->>'revoked_by'=auth.uid()::text and exists(select 1 from private.professional_verifications v where v.id=(item->>'verification_id')::uuid and v.clinic_id is null and v.origin='platform_external') then
 perform private.require_platform_admin();return new;end if;
 state=public.beta_access_check(true);
 begin scope=nullif(item->>'clinic_id','')::uuid;exception when invalid_text_representation then scope=null;end;
 if tg_table_schema='public' and tg_table_name='clinics' then scope=(item->>'id')::uuid;end if;
 if tg_table_schema='storage' and item->>'bucket_id'='inventory-photos' then begin scope=split_part(item->>'name','/',1)::uuid;exception when others then scope=null;end;end if;
 if scope is not null and tg_table_name not in ('audit_log','workspace_usage') then
  -- Clinic creation and its creator's initial admin membership are a bounded bootstrap;
  -- recording clinic data subsequently requires explicit sponsor acceptance.
  if not(tg_op='INSERT' and ((tg_table_name='clinics' and item->>'created_by'=auth.uid()::text) or (tg_table_name='clinic_members' and item->>'user_id'=auth.uid()::text and item->>'role'='admin' and exists(select 1 from public.clinics where id=scope and created_by=auth.uid())))) then
   state=private.beta_mode(null,scope,not(tg_table_name='clinic_members' and tg_op='INSERT'));
   if state->>'mode' not in ('active','sponsor_grace','internal') then raise exception 'beta_workspace_read_only';end if;
  end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end$$;

revoke all on function public.platform_beta_professional_list(),public.platform_beta_professional_revoke(uuid,text) from public,anon;
grant execute on function public.platform_beta_professional_list(),public.platform_beta_professional_revoke(uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;
