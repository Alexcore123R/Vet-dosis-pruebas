-- Apply after 14J. Reward balances and an immutable grant/redemption ledger.
begin;
create table if not exists public.client_loyalty_balances (
 clinic_id uuid not null references public.clinics(id),
 owner_id uuid not null,
 promotion_id uuid not null references public.clinic_promotions(id),
 units integer not null default 0 check(units >= 0),
 primary key(clinic_id,owner_id,promotion_id),
 foreign key(clinic_id,owner_id) references public.vet_owners(clinic_id,id)
);
alter table public.client_loyalty_balances enable row level security;
revoke all on public.client_loyalty_balances from public,anon,authenticated;
create table if not exists public.client_loyalty_movements (
 id uuid primary key default gen_random_uuid(),
 clinic_id uuid not null references public.clinics(id),
 owner_id uuid not null,
 promotion_id uuid not null references public.clinic_promotions(id),
 action text not null check(action in ('grant','redeem')),
 units integer not null check(units between 1 and 100000),
 note text not null default '' check(length(note)<=500),
 operation_id text not null check(length(operation_id) between 16 and 100),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),
 unique(clinic_id,operation_id),
 foreign key(clinic_id,owner_id) references public.vet_owners(clinic_id,id)
);
create index if not exists client_loyalty_movements_owner_idx on public.client_loyalty_movements(clinic_id,owner_id,created_at desc);
alter table public.client_loyalty_movements enable row level security;
revoke all on public.client_loyalty_movements from public,anon,authenticated;

create or replace function public.ops_loyalty_account(p_clinic uuid,p_owner uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.permission_patient_read(p_clinic) then raise exception 'patient_read_required';end if;
 if not exists(select 1 from public.vet_owners where clinic_id=p_clinic and id=p_owner) then raise exception 'owner_wrong_clinic';end if;
 return jsonb_build_object(
  'balances',coalesce((select jsonb_agg(jsonb_build_object('promotion_id',b.promotion_id,'title',p.title,'units',b.units,'active',p.active) order by p.title)
   from public.client_loyalty_balances b join public.clinic_promotions p on p.id=b.promotion_id and p.clinic_id=b.clinic_id
   where b.clinic_id=p_clinic and b.owner_id=p_owner),'[]'::jsonb),
  'movements',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'promotion_id',m.promotion_id,'title',p.title,'action',m.action,'units',m.units,'note',m.note,'created_at',m.created_at,'created_by',m.created_by) order by m.created_at desc)
   from public.client_loyalty_movements m join public.clinic_promotions p on p.id=m.promotion_id and p.clinic_id=m.clinic_id
   where m.clinic_id=p_clinic and m.owner_id=p_owner),'[]'::jsonb));
end$$;
revoke all on function public.ops_loyalty_account(uuid,uuid) from public,anon;
grant execute on function public.ops_loyalty_account(uuid,uuid) to authenticated;

create or replace function public.ops_loyalty_record(p_clinic uuid,p_owner uuid,p_promotion uuid,p_action text,p_units integer,p_note text,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_previous public.client_loyalty_movements%rowtype;
begin
 perform private.permission_require(p_clinic,'patient.write');
 if p_action not in ('grant','redeem') or p_units is null or p_units not between 1 and 100000 or
    length(coalesce(p_note,''))>500 or length(coalesce(p_operation,'')) not between 16 and 100 then raise exception 'loyalty_fields_invalid';end if;
 if not exists(select 1 from public.vet_owners where clinic_id=p_clinic and id=p_owner) then raise exception 'owner_wrong_clinic';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_clinic::text||':'||p_operation,0));
 select * into v_previous from public.client_loyalty_movements where clinic_id=p_clinic and operation_id=p_operation;
 if found then
  if v_previous.owner_id<>p_owner or v_previous.promotion_id<>p_promotion or v_previous.action<>p_action or v_previous.units<>p_units or v_previous.note<>coalesce(p_note,'') then raise exception 'operation_payload_conflict';end if;
  return v_previous.id;
 end if;
 if not exists(select 1 from public.clinic_promotions where clinic_id=p_clinic and id=p_promotion and kind='recompensa' and (active or p_action='redeem')) then raise exception 'reward_unavailable';end if;
 insert into public.client_loyalty_balances(clinic_id,owner_id,promotion_id) values(p_clinic,p_owner,p_promotion)
 on conflict(clinic_id,owner_id,promotion_id) do nothing;
 if p_action='grant' then
  update public.client_loyalty_balances set units=units+p_units where clinic_id=p_clinic and owner_id=p_owner and promotion_id=p_promotion;
 else
  update public.client_loyalty_balances set units=units-p_units where clinic_id=p_clinic and owner_id=p_owner and promotion_id=p_promotion and units>=p_units;
  if not found then raise exception 'insufficient_reward_balance';end if;
 end if;
 insert into public.client_loyalty_movements(clinic_id,owner_id,promotion_id,action,units,note,operation_id,created_by)
 values(p_clinic,p_owner,p_promotion,p_action,p_units,coalesce(p_note,''),p_operation,auth.uid()) returning id into v_id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values
 (p_clinic,auth.uid(),'loyalty_'||p_action,v_id::text,jsonb_build_object('owner',p_owner,'promotion',p_promotion,'units',p_units));
 return v_id;
end$$;
revoke all on function public.ops_loyalty_record(uuid,uuid,uuid,text,integer,text,text) from public,anon;
grant execute on function public.ops_loyalty_record(uuid,uuid,uuid,text,integer,text,text) to authenticated;
commit;
notify pgrst, 'reload schema';
