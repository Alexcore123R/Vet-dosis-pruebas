-- Apply after 14D. Payroll periods are immutable snapshots; no commission history is erased.
begin;
create table if not exists public.clinic_commission_schedule (
 clinic_id uuid primary key references public.clinics(id),
 cadence text not null check(cadence in ('diario','semanal','quincenal','mensual')),
 pay_day integer not null check(pay_day between 1 and 31),
 period_start timestamptz not null,
 next_pay_on date not null,
 updated_by uuid not null references auth.users(id),
 updated_at timestamptz not null default clock_timestamp()
);
create table if not exists public.clinic_commission_payments (
 id uuid primary key default gen_random_uuid(),
 clinic_id uuid not null references public.clinics(id),
 professional_id uuid not null,
 period_start timestamptz not null,
 period_end timestamptz not null,
 scheduled_on date not null,
 amount numeric(18,2) not null check(amount>=0),
 recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),
 unique(clinic_id,professional_id,period_start,period_end),
 foreign key(clinic_id,professional_id) references public.clinic_members(clinic_id,user_id)
);
create index if not exists clinic_commission_payments_staff on public.clinic_commission_payments(clinic_id,professional_id,recorded_at desc);
alter table public.clinic_commission_schedule enable row level security;
alter table public.clinic_commission_payments enable row level security;
revoke all on public.clinic_commission_schedule,public.clinic_commission_payments from public,anon,authenticated;

create or replace function public.commission_schedule_save(p_clinic uuid,p_cadence text,p_next_pay_on date)
returns void language plpgsql security definer set search_path='' as $$
declare old public.clinic_commission_schedule;begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 if p_cadence not in ('diario','semanal','quincenal','mensual') or p_next_pay_on <= (clock_timestamp() at time zone private.inv_timezone(p_clinic))::date then raise exception 'invalid_schedule';end if;
 if (p_next_pay_on::timestamp at time zone private.inv_timezone(p_clinic))<=clock_timestamp() then raise exception 'invalid_schedule';end if;
 select * into old from public.clinic_commission_schedule where clinic_id=p_clinic for update;
 if found then
  if (p_next_pay_on::timestamp at time zone private.inv_timezone(p_clinic))<=old.period_start then raise exception 'invalid_schedule';end if;
  update public.clinic_commission_schedule set cadence=p_cadence,pay_day=extract(day from p_next_pay_on)::integer,next_pay_on=p_next_pay_on,updated_by=auth.uid(),updated_at=clock_timestamp() where clinic_id=p_clinic;
 else
  insert into public.clinic_commission_schedule(clinic_id,cadence,pay_day,period_start,next_pay_on,updated_by)
  values(p_clinic,p_cadence,extract(day from p_next_pay_on)::integer,clock_timestamp(),p_next_pay_on,auth.uid());
 end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(p_clinic,auth.uid(),'commission_schedule_saved',p_clinic::text,jsonb_build_object('cadence',p_cadence,'next_pay_on',p_next_pay_on));
end$$;

create or replace function public.commission_account(p_clinic uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cfg public.clinic_commission_schedule;is_admin boolean;begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;
 is_admin=private.has_clinic_role(p_clinic,array['admin']);
 select * into cfg from public.clinic_commission_schedule where clinic_id=p_clinic;
 return jsonb_build_object(
  'schedule',case when cfg.clinic_id is null then null else jsonb_build_object('cadence',cfg.cadence,'pay_day',cfg.pay_day,'period_start',cfg.period_start,'next_pay_on',cfg.next_pay_on) end,
  'accrued',coalesce((select jsonb_agg(jsonb_build_object('professional_id',m.user_id,'professional_name',coalesce(n.name,'Sin nombre'),'amount',(coalesce(e.amount,0)-coalesce(p.amount,0))::text))
    from public.clinic_members m
    left join public.staff_display_names n on n.clinic_id=m.clinic_id and n.user_id=m.user_id
    left join lateral (
      select sum(l.commission) amount from public.inventory_sale_lines l
      join public.inventory_sales s on s.id=l.sale_id and s.clinic_id=l.clinic_id
      where l.clinic_id=p_clinic and l.professional_id=m.user_id and l.commission>0
        and not exists(select 1 from public.inventory_sale_reversals r where r.sale_id=s.id)
    ) e on true
    left join lateral (
      select sum(x.amount) amount from public.clinic_commission_payments x
      where x.clinic_id=p_clinic and x.professional_id=m.user_id
    ) p on true
    where m.clinic_id=p_clinic and (is_admin or m.user_id=auth.uid())
      and (coalesce(e.amount,0)-coalesce(p.amount,0))<>0),'[]'::jsonb),
  'payments',coalesce((select jsonb_agg(jsonb_build_object('professional_id',p.professional_id,'professional_name',coalesce(n.name,'Sin nombre'),'amount',p.amount::text,'scheduled_on',p.scheduled_on,'recorded_at',p.recorded_at,'period_start',p.period_start,'period_end',p.period_end) order by p.recorded_at desc)
    from public.clinic_commission_payments p left join public.staff_display_names n on n.clinic_id=p.clinic_id and n.user_id=p.professional_id where p.clinic_id=p_clinic and (is_admin or p.professional_id=auth.uid())),'[]'::jsonb)
 );
end$$;

create or replace function public.commission_period_pay(p_clinic uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare cfg public.clinic_commission_schedule;v_batch uuid=gen_random_uuid();v_end timestamptz;v_next date;begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 select * into cfg from public.clinic_commission_schedule where clinic_id=p_clinic for update;
 if not found then raise exception 'schedule_required';end if;
 if (clock_timestamp() at time zone private.inv_timezone(p_clinic))::date<cfg.next_pay_on then raise exception 'payment_day_not_reached';end if;
 v_end=cfg.next_pay_on::timestamp at time zone private.inv_timezone(p_clinic);
 if v_end<=cfg.period_start then raise exception 'invalid_period';end if;
 insert into public.clinic_commission_payments(clinic_id,professional_id,period_start,period_end,scheduled_on,amount,recorded_by)
 select p_clinic,m.user_id,cfg.period_start,v_end,cfg.next_pay_on,
        greatest(0,coalesce(e.amount,0)-coalesce(p.amount,0)),auth.uid()
 from public.clinic_members m
 left join lateral (
   select sum(l.commission) amount from public.inventory_sale_lines l
   join public.inventory_sales s on s.id=l.sale_id and s.clinic_id=l.clinic_id
   where l.clinic_id=p_clinic and l.professional_id=m.user_id and l.commission>0
     and s.created_at<v_end
     and not exists(select 1 from public.inventory_sale_reversals r where r.sale_id=s.id)
 ) e on true
 left join lateral (
   select sum(x.amount) amount from public.clinic_commission_payments x
   where x.clinic_id=p_clinic and x.professional_id=m.user_id
 ) p on true
 where m.clinic_id=p_clinic and coalesce(e.amount,0)>coalesce(p.amount,0);
 v_next=case cfg.cadence
  when 'diario' then cfg.next_pay_on+1
  when 'semanal' then cfg.next_pay_on+7
  when 'quincenal' then cfg.next_pay_on+15
  else make_date(
   extract(year from cfg.next_pay_on+interval '1 month')::integer,
   extract(month from cfg.next_pay_on+interval '1 month')::integer,
   least(cfg.pay_day,extract(day from date_trunc('month',cfg.next_pay_on+interval '2 months')-interval '1 day')::integer)
  ) end;
 update public.clinic_commission_schedule set period_start=v_end,next_pay_on=v_next,updated_by=auth.uid(),updated_at=clock_timestamp() where clinic_id=p_clinic;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(p_clinic,auth.uid(),'commission_period_paid',v_batch::text,jsonb_build_object('period_start',cfg.period_start,'period_end',v_end,'scheduled_on',cfg.next_pay_on));
 return v_batch;
end$$;
revoke all on function public.commission_schedule_save(uuid,text,date),public.commission_account(uuid),public.commission_period_pay(uuid) from public,anon;
grant execute on function public.commission_schedule_save(uuid,text,date),public.commission_account(uuid),public.commission_period_pay(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
