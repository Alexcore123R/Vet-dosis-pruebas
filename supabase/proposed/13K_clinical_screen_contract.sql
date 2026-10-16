-- Local candidate after 13J4. Read contract only; no automatic case publication.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy) or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
create function public.clinical_workspace(p_clinic uuid,p_case uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.clinical_cases;readable boolean;writable boolean=false;authority boolean=false;observe boolean=false;scopes jsonb='[]';bindings jsonb='[]';documents jsonb='[]';begin
 readable=private.form_document_reader(p_clinic);
 if readable then writable=(public.beta_access_check(false,p_clinic)->>'mode') in ('internal','active','sponsor_grace');end if;
 if p_case is not null then
  select * into c from public.clinical_cases where id=p_case and clinic_id=p_clinic;
  if not found or not readable or not private.clinical_readable(c) then raise exception 'clinical_access_denied';end if;
  authority=writable and c.responsible_id=auth.uid() and private.form_document_current(p_clinic,auth.uid(),'clinical.authorize') and private.clinical_professional_at(p_clinic,auth.uid(),clock_timestamp());
  observe=writable and private.clinical_eligible(c,auth.uid(),'observaciones',clock_timestamp());
  select coalesce(jsonb_agg(s order by s),'[]') into scopes from unnest(array['evaluacion','cirugia','anestesia','recuperacion','cuidados']) s where writable and private.clinical_eligible(c,auth.uid(),s,clock_timestamp());
  select coalesce(jsonb_agg(jsonb_build_object('scope',b.scope,'procedure_id',b.procedure_id,'professional_required',b.professional_required,'source',b.source) order by b.scope),'[]') into bindings from private.clinical_scope_bindings b where b.case_id=c.id and b.id=(private.clinical_binding(c.id,b.scope)).id;
  select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'title',d.snapshot->'schema'->>'title','revision',d.revision,'state',d.state,'is_original',d.id=c.document_id) order by d.created_at desc,d.id),'[]') into documents from public.form_documents d where d.clinic_id=c.clinic_id and d.patient_id=c.patient_id and d.state='signed' and (d.id=c.document_id or d.id=c.consent_id or d.snapshot->'attention_assignment'->>'case_id'=c.id::text) and private.form_readable(d);
 end if;
 return jsonb_build_object('schema_version',1,'mode','explicit_clinical','clinic_id',p_clinic,'case_id',p_case,'can_read',readable,
 'actions',jsonb_build_object('observe',observe,'act',jsonb_array_length(scopes)>0,'correct',authority and observe,'authorize',authority,'revoke',authority,'bind',authority),
 'act_scopes',scopes,'bindings',bindings,'documents',documents,
 'members',case when authority then coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'label',coalesce(private.rx_profile(p.id)->>'name','Miembro '||left(m.user_id::text,8))) order by m.user_id) from public.clinic_members m left join public.professional_profiles p on p.clinic_id=m.clinic_id and p.user_id=m.user_id where m.clinic_id=p_clinic),'[]') else '[]'::jsonb end,
 'procedures',case when authority then coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name) order by t.name,t.id) from private.procedure_types t where t.clinic_id=p_clinic and t.active),'[]') else '[]'::jsonb end);
end$$;
revoke all on function public.clinical_workspace(uuid,uuid) from public,anon,authenticated;
grant execute on function public.clinical_workspace(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
