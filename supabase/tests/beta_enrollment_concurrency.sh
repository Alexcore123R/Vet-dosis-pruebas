#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
for attempt in 1 2;do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/$attempt.log" 2>&1 <<'SQL' &
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000016',true);
select set_config('request.headers','{"x-vetdosis-build":"100"}',true);
select public.beta_enroll('synthetic','synthetic-hash','SYNTHETIC-RACE-TOKEN');
select pg_sleep(0.5);
commit;
SQL
 if [ "$attempt" = 1 ];then first_pid=$!;else second_pid=$!;fi
done
wait "$first_pid" || { cat "$work_dir/1.log";exit 1; }
wait "$second_pid" || { cat "$work_dir/2.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if (select count(*) from private.beta_enrollments where user_id='00000000-0000-0000-0000-000000000016')<>1 then raise exception 'race_duplicate_enrollment';end if;
 if (select expires_at-starts_at<>interval '60 days' from private.beta_enrollments where user_id='00000000-0000-0000-0000-000000000016') then raise exception 'race_renewed_beta';end if;
 if (select count(*) from private.beta_invites where consumed_by='00000000-0000-0000-0000-000000000016')<>1 then raise exception 'race_reused_invite';end if;
end$$;
SQL
echo 'Inscripción concurrente: una matrícula, una invitación consumida y 60 días sin renovación.'
