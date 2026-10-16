#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
# Restore synthetic evidence for a race; this is not a verification of a real user.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" <<'SQL'
insert into private.professional_verifications(id,user_id,profile_version_id,reviewer_id,reviewed_at,evidence_hash,evidence_reference,valid_until,origin)
select '00000000-0000-0000-0000-000000000120',p.user_id,v.id,'00000000-0000-0000-0000-000000000114',clock_timestamp(),repeat('b',64),'Synthetic concurrency evidence',clock_timestamp()+interval '1 day','platform_external'
from public.professional_profiles p join private.professional_profile_versions v on v.profile_id=p.id
where p.user_id='00000000-0000-0000-0000-000000000111' and v.version=1;
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoke.log" 2>&1 <<'SQL' &
begin;
insert into private.professional_revocations(verification_id,revoked_by,reason) values('00000000-0000-0000-0000-000000000120','00000000-0000-0000-0000-000000000114','Synthetic concurrent revocation');
select pg_advisory_xact_lock(771140);
select pg_sleep(2);
commit;
SQL
revoker_pid=$!
ready=false
for attempt in {1..30};do
 available=$(docker exec "$container_name" psql -U postgres -Atc 'select pg_try_advisory_lock(771140)')
 if [ "$available" = f ];then ready=true;break;fi
 sleep 0.1
done
if [ "$ready" != true ];then wait "$revoker_pid";echo 'Professional revocation coordination failed';exit 1;fi
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/action.log" 2>&1 <<'SQL'
select c.id as case_id,b.procedure_id as procedure from public.clinical_cases c join private.clinical_scope_bindings b on b.case_id=c.id where c.title='Synthetic case' and b.scope='observaciones' and not exists(select 1 from private.clinical_scope_revocations r where r.binding_id=b.id) \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',false);
set role authenticated;
select public.clinical_scope_bind(:'case_id','observaciones',:'procedure',true,'Synthetic concurrency source','Should be blocked');
SQL
then echo 'ERROR: waiting clinical authority survived professional revocation';exit 1;fi
wait "$revoker_pid" || { cat "$work_dir/revoke.log";exit 1; }
grep -Eq 'explicit_permission_required|verified_authority_required' "$work_dir/action.log" || { cat "$work_dir/action.log";exit 1; }
echo 'Clinical concurrency passed: professional revocation serializes with waiting clinical authority.'
