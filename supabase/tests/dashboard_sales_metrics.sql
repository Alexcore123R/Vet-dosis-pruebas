-- Minimal synthetic arithmetic fixture. No application data or permissions imported.
create schema private;
create table public.inventory_sales(id uuid,clinic_id uuid,shift_id uuid,created_at timestamptz,method text,total numeric,cost numeric,commission numeric);
create table public.inventory_sale_reversals(sale_id uuid,clinic_id uuid,shift_id uuid,created_at timestamptz);
create table public.inventory_cash_movements(clinic_id uuid,shift_id uuid,created_at timestamptz,kind text,amount numeric);
create function private.inv_totals(uuid,uuid,timestamptz,timestamptz) returns jsonb language sql as $$select '{}'::jsonb$$;
-- Use the exact argument names of the production signature for replacement.
drop function private.inv_totals(uuid,uuid,timestamptz,timestamptz);
create function private.inv_totals(clinic uuid,shift uuid,start_time timestamptz,end_time timestamptz) returns jsonb language sql as $$select '{}'::jsonb$$;
revoke all on function private.inv_totals(uuid,uuid,timestamptz,timestamptz) from public;
\i supabase/proposed/14A_dashboard_sales_metrics.sql
insert into inventory_sales values
 ('00000000-0000-0000-0000-000000000001','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',null,'2026-10-17 01:00Z','efectivo',20.20,8,0),
 ('00000000-0000-0000-0000-000000000002','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',null,'2026-10-17 02:00Z','tarjeta',40,10,0),
 ('00000000-0000-0000-0000-000000000003','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',null,'2026-10-16 23:00Z','efectivo',100,10,0),
 ('00000000-0000-0000-0000-000000000004','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',null,'2026-10-17 03:00Z','efectivo',9999,1,0);
insert into inventory_sale_reversals values
 ('00000000-0000-0000-0000-000000000002','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',null,'2026-10-17 05:00Z'),
 ('00000000-0000-0000-0000-000000000001','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',null,'2026-10-18 05:00Z');
do $$declare result jsonb;begin
 result=private.inv_totals('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',null,'2026-10-17 00:00Z','2026-10-18 00:00Z');
 if result->>'sale_count'<>'1' or (result->>'average_ticket')::numeric<>20.20 or (result->>'gross')::numeric<>20.20 then raise exception 'Wrong whole-sale metrics, clinic filter or reversal boundary';end if;
 result=private.inv_totals('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',null,'2026-10-19 00:00Z','2026-10-20 00:00Z');
 if result->>'sale_count'<>'0' or result->>'average_ticket' is not null then raise exception 'Empty period average must be NULL';end if;
 if exists(select 1 from pg_proc p, lateral aclexplode(p.proacl) a where p.oid='private.inv_totals(uuid,uuid,timestamptz,timestamptz)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE') then raise exception 'Replacement widened EXECUTE';end if;
end $$;
