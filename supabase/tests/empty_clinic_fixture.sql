-- Isolated test only, minimal M13 bookkeeping matching real FKs.
create table public.account_workspaces(clinic_id uuid primary key references public.clinics(id),kind text not null,owner_id uuid references auth.users(id));
create table private.workspace_usage(clinic_id uuid primary key references public.clinics(id),bytes bigint not null default 0);
