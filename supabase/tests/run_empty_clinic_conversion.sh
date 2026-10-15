#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
container_name="vetdosis-empty-clinic-$$"
work_dir=$(mktemp -d)
docker run -d --name "$container_name" --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine >/dev/null
trap 'docker rm -f "$container_name" >/dev/null; rm -rf "$work_dir"' EXIT
ready=false
for attempt in $(seq 1 30);do
 if docker exec "$container_name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1;then ready=true;break;fi
 sleep 1
done
if [ "$ready" != true ];then echo 'Postgres startup failed';exit 1;fi
for sql_file in supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/tests/storage_fixture.sql supabase/proposed/09A_beta_foundation.sql supabase/tests/beta_foundation.sql supabase/tests/empty_clinic_fixture.sql supabase/proposed/09B_beta_gate.sql;do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$sql_file" > "$work_dir/setup.log" 2>&1 || { cat "$work_dir/setup.log";exit 1; }
done
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-0000-0000-000000000021','conversion@example.test',now()),('00000000-0000-0000-0000-000000000022','keep@example.test',now());
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000021',false);
select public.create_clinic('Empty synthetic') as clinic \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000022',false);
select public.create_clinic('Keep synthetic') as other \gset
insert into public.account_workspaces(clinic_id,kind) values(:'clinic','clinic'),(:'other','clinic');
insert into private.workspace_usage(clinic_id) values(:'clinic'),(:'other');
insert into public.inventario(clinic_id,user_id,nombre) values(:'clinic','00000000-0000-0000-0000-000000000021','Synthetic guard record');
SQL
clinic_id=$(docker exec "$container_name" psql -U postgres -Atc "select id from public.clinics where name='Empty synthetic'")
PYTHONPATH=scripts/supabase python3 - "$clinic_id" "$work_dir/convert.sql" <<'PY'
import sys
from convert_empty_clinic import statement
from pathlib import Path
Path(sys.argv[2]).write_text(statement('conversion@example.test',sys.argv[1],'Empty synthetic'))
PY
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/convert.sql" > "$work_dir/blocked.log" 2>&1;then echo 'ERROR: nonempty clinic conversion succeeded';exit 1;fi
rg 'clinic_no_longer_empty' "$work_dir/blocked.log" >/dev/null
# A rejected conversion must roll back bookkeeping changes and preserve the account.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if (select count(*) from public.clinics where name='Empty synthetic')<>1 then raise exception 'failed_conversion_deleted_clinic';end if;
 if (select count(*) from public.inventario where nombre='Synthetic guard record')<>1 then raise exception 'failed_conversion_deleted_data';end if;
 if exists(select 1 from private.platform_admins where user_id='00000000-0000-0000-0000-000000000021') then raise exception 'failed_conversion_promoted';end if;
end$$;
delete from public.inventario where nombre='Synthetic guard record';
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/convert.sql"
# Retry is idempotent; it must not create a second conversion or remove another clinic.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/convert.sql"
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if exists(select 1 from public.clinics where name='Empty synthetic') then raise exception 'clinic_not_removed';end if;
 if not exists(select 1 from public.clinics where name='Keep synthetic') then raise exception 'other_clinic_removed';end if;
 if not exists(select 1 from auth.users where id='00000000-0000-0000-0000-000000000021') then raise exception 'account_removed';end if;
 if not exists(select 1 from private.platform_admins where user_id='00000000-0000-0000-0000-000000000021' and enabled) then raise exception 'platform_not_enabled';end if;
 if exists(select 1 from public.clinic_members where user_id='00000000-0000-0000-0000-000000000021') then raise exception 'membership_remains';end if;
 if (select count(*) from private.beta_audit where action='empty_clinic_converted_to_platform')<>1 then raise exception 'duplicate_conversion';end if;
 if (select jsonb_array_length(reason::jsonb->'preserved_creation_audit') from private.beta_audit where action='empty_clinic_converted_to_platform')<>2 then raise exception 'creation_audit_lost';end if;
 begin delete from public.clinic_members where user_id='00000000-0000-0000-0000-000000000022';raise exception 'last_admin_guard_disabled';exception when raise_exception then if sqlerrm<>'last_admin_required' then raise;end if;end;
end$$;
SQL
echo 'Empty clinic conversion: nonempty blocked, account and other clinic preserved, audit retained, retry safe, last-admin protection restored.'
