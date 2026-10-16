"""Proposed privacy binding operator. Default read-only; never publishes or opens beta."""
import os
from legal_schema import ROOT, literal, load_draft, draft_sql
from identity_schema import query
import hashlib
import json
import re

PREFLIGHT = """select
 (select not admissions_enabled and not enforcement_enabled from private.beta_policy) as beta_closed,
 to_regclass('public.terms_acceptances') is not null as terms_ready,
 to_regclass('private.beta_privacy_notices') is not null as notice_table,
 exists(select 1 from information_schema.columns where table_schema='private' and table_name='beta_terms' and column_name='privacy_version') as terms_binding,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='terms_acceptances' and column_name='privacy_hash') as receipt_binding,
 to_regprocedure('public.beta_accept_terms(text,text,text,text)') is not null as accept_rpc,
 to_regprocedure('public.beta_enroll(text,text,text,text,text)') is not null as enroll_rpc"""


def load_privacy():
    data = json.loads((ROOT / 'docs/legal/privacy-v1-drive.json').read_text())
    heading = re.search(r'^Versión\s+([^\s(]+)', data['content'], re.MULTILINE)
    if (data['state'] != 'draft' or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,63}', data['version'])
        or not heading or heading.group(1) != data['version']
        or not data['source_url'].startswith('https://docs.google.com/document/d/')):
        raise ValueError('El aviso debe ser un borrador con versión y origen verificables.')
    data['hash'] = hashlib.sha256(data['content'].encode('utf-8')).hexdigest()
    return data


def binding_sql(terms, notice):
    version = literal(notice['version'])
    metadata = literal(json.dumps({k:notice[k] for k in ('source_url','source_revision','hash')}, ensure_ascii=False))
    return f"""do $$begin
 if exists(select 1 from private.beta_privacy_notices where version={version} and published) then raise exception 'published_privacy_cannot_be_replaced_by_draft';end if;
 end$$;
 insert into private.beta_privacy_notices(version,content,content_hash) values({version},{literal(notice['content'])},{literal(notice['hash'])})
 on conflict(version) do update set content=excluded.content,content_hash=excluded.content_hash where not beta_privacy_notices.published;
 {draft_sql(terms)}
 update private.beta_terms set privacy_version={version} where version={literal(terms['version'])} and not published;
 insert into private.beta_audit(action,entity_id,reason) values('privacy_draft_bound',{version},{metadata});
 """


def main():
    action = os.environ.get('PRIVACY_ACTION','inspect')
    if action not in ('inspect','prepare'):
        raise SystemExit('Acción inválida.')
    state = query(PREFLIGHT)[0]
    print('Estado de vinculación del aviso:', state)
    if action == 'inspect':
        return
    if os.environ.get('PRIVACY_CONFIRMATION') != 'PREPARAR_AVISO_SIN_PUBLICAR':
        raise SystemExit('Falta confirmación de la propuesta revisada.')
    if not state['beta_closed'] or not state['terms_ready']:
        raise SystemExit('Requiere términos instalados y beta cerrada.')
    installed = [state[k] for k in ('notice_table','terms_binding','receipt_binding','accept_rpc','enroll_rpc')]
    if any(installed) and not all(installed):
        raise SystemExit('Esquema parcial; revisar sin aplicar cambios.')
    terms,notice = load_draft(),load_privacy()
    migration = '' if all(installed) else (ROOT/'supabase/proposed/12C_privacy_binding.sql').read_text().removeprefix('-- PROPOSED: review schema before remote application. Does not publish or open beta.\n').removeprefix('begin;\n').removesuffix('commit;\n')
    query("""begin;
 select 1 from private.beta_policy for update;
 do $$begin if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy) then raise exception 'beta_must_be_closed';end if;end$$;
 """ + migration + '\nlock table private.beta_terms in share row exclusive mode;\nlock table private.beta_privacy_notices in share row exclusive mode;\n' + binding_sql(terms,notice) + '\ncommit;')
    checked = query(f"""select
 (select not admissions_enabled and not enforcement_enabled from private.beta_policy) as beta_closed,
 exists(select 1 from private.beta_terms t join private.beta_privacy_notices n on n.version=t.privacy_version
 where t.version={literal(terms['version'])} and n.version={literal(notice['version'])}
 and not t.published and not n.published
 and t.content_hash={literal(terms['hash'])} and n.content_hash={literal(notice['hash'])}
 and t.content_hash=encode(sha256(convert_to(t.content,'UTF8')),'hex')
 and n.content_hash=encode(sha256(convert_to(n.content,'UTF8')),'hex')) as exact_unpublished_binding""")[0]
    if not all(checked.values()):
        raise SystemExit('Verificación incompleta; revisar estado.')
    print('Borradores vinculados y verificados:', checked)
    print('Sin publicación, apertura, aceptaciones nuevas ni renovación de beta.')


if __name__ == '__main__':
    main()
