"""Extended client compatibility trial, always rolled back; never a deployment bundle."""
from integration_bundle import bundle_sql, unwrap
from integration_preflight import ROOT

EXTRA_FILES = (
    '13Y_ai_key_rotation.sql',
    '14A_dashboard_sales_metrics.sql',
    '14B_support_attachment_validation.sql',
)


def client_rehearsal_sql(root=ROOT):
    base = bundle_sql(root=root)
    if not base.endswith('rollback;\n'):
        raise ValueError('Extended rehearsal requires a rollback-only base.')
    extras = '\n'.join('-- Compatibility trial: ' + name + '\n' + unwrap(
        (root / 'supabase/proposed' / name).read_text()) for name in EXTRA_FILES)
    return base.removesuffix('rollback;\n') + extras + '''
do $client_verify$
begin
 if to_regprocedure('public.ai_key_rotate_server(uuid,uuid,text,text)') is null
 then raise exception 'client_rotation_contract_missing';end if;
 if has_function_privilege('anon','public.ai_key_rotate_server(uuid,uuid,text,text)','execute')
 or has_function_privilege('authenticated','public.ai_key_rotate_server(uuid,uuid,text,text)','execute')
 then raise exception 'client_rotation_rpc_exposed';end if;
 if not has_function_privilege('service_role','public.ai_key_rotate_server(uuid,uuid,text,text)','execute')
 then raise exception 'client_rotation_service_missing';end if;
 if not exists(select 1 from private.beta_policy where not admissions_enabled and not enforcement_enabled)
 or not exists(select 1 from private.permission_policy where not enforcement_enabled and not migration_reviewed)
 then raise exception 'client_trial_changed_gate';end if;
end
$client_verify$;
rollback;
'''
