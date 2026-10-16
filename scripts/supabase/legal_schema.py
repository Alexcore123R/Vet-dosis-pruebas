"""Prepare consent history and platform revocation; import only an unpublished draft."""
import hashlib
import json
import os
from pathlib import Path
import re
from identity_schema import query

ROOT = Path(__file__).resolve().parents[2]
PREFLIGHT = """select
 to_regprocedure('private.beta_install_guards()') is not null as beta_ready,
 to_regprocedure('public.permission_professional_revoke(uuid,text)') is not null as permissions_ready,
 (select not admissions_enabled and not enforcement_enabled from private.beta_policy) as beta_closed,
 to_regclass('public.terms_acceptances') is not null as acceptance_table,
 to_regprocedure('public.beta_accept_terms(text,text)') is not null as acceptance_rpc,
 to_regprocedure('public.platform_beta_professional_list()') is not null as platform_list,
 to_regprocedure('public.platform_beta_professional_revoke(uuid,text)') is not null as platform_revoke"""


def literal(value):
    return "'"+value.replace("'", "''")+"'"


def load_draft():
    data=json.loads((ROOT / 'docs/legal/terms-v1-drive.json').read_text())
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,63}',data['version']):
        raise ValueError('Identificador de versión inválido.')
    heading=re.search(r'^Versión\s+([^\s(]+)', data['content'], re.MULTILINE)
    if data['state']!='draft' or not heading or heading.group(1)!=data['version']:
        raise ValueError('La versión del manifiesto debe coincidir con el encabezado del texto fuente.')
    if not data['source_url'].startswith('https://docs.google.com/document/d/'):
        raise ValueError('Referencia de origen no reconocida.')
    data['hash']=hashlib.sha256(data['content'].encode('utf-8')).hexdigest()
    return data


def draft_sql(data):
    version=literal(data['version'])
    metadata=json.dumps({k:data[k] for k in ('source_url','source_modified_at','hash')},ensure_ascii=False)
    return f"""do $$begin
 if exists(select 1 from private.beta_terms where version={version} and published) then raise exception 'published_terms_cannot_be_replaced_by_draft';end if;
 end$$;
 with changed as (
 insert into private.beta_terms(version,content,content_hash,published) values({version},{literal(data['content'])},{literal(data['hash'])},false)
 on conflict(version) do update set content=excluded.content,content_hash=excluded.content_hash
 where not beta_terms.published and (beta_terms.content,beta_terms.content_hash) is distinct from (excluded.content,excluded.content_hash)
 returning version)
 insert into private.beta_audit(action,entity_id,reason) select 'terms_draft_imported',version,{literal(metadata)} from changed;
 """


def main():
    action=os.environ.get('LEGAL_ACTION','inspect')
    if action not in ('inspect','prepare'):
        raise SystemExit('Acción inválida; este operador no publica textos ni abre beta.')
    state=query(PREFLIGHT)[0]
    print('Estado de consentimientos y plataforma:',state)
    if action=='inspect':
        return
    if os.environ.get('LEGAL_CONFIRMATION')!='PREPARAR_TERMINOS_SIN_PUBLICAR':
        raise SystemExit('Falta confirmación de preparación sin publicación.')
    if not all(state[k] for k in ('beta_ready','permissions_ready','beta_closed')):
        raise SystemExit('Faltan dependencias o la beta no está cerrada. Sin cambios.')
    if state['acceptance_table']!=state['acceptance_rpc'] or state['platform_list']!=state['platform_revoke']:
        raise SystemExit('Estado parcial: revisar antes de aplicar.')
    parts=[]
    if not state['acceptance_table']:
        parts.append((ROOT/'supabase/proposed/12A_terms_acceptances.sql').read_text())
    if not state['platform_list']:
        parts.append((ROOT/'supabase/proposed/12B_platform_professional_admin.sql').read_text())
    statements=[p.replace('begin;\n','',1).removesuffix('commit;\n') for p in parts]
    data=load_draft()
    query("begin;\nset local standard_conforming_strings=on;\n"+'\n'.join(statements)+draft_sql(data)+"\ncommit;")
    check=query(f"""select
 (select not admissions_enabled and not enforcement_enabled from private.beta_policy) as beta_closed,
 exists(select 1 from private.beta_terms where version={literal(data['version'])} and content_hash={literal(data['hash'])} and content_hash=encode(sha256(convert_to(content,'UTF8')),'hex') and not published) as exact_draft_unpublished,
 to_regprocedure('public.beta_accept_terms(text,text)') is not null as acceptance_ready,
 to_regprocedure('public.platform_beta_professional_revoke(uuid,text)') is not null as platform_revocation_ready""")[0]
    if not all(check.values()):
        raise SystemExit('Verificación incompleta: revisar el estado antes de continuar.')
    print('Preparación verificada:',check)
    print('Términos versión',data['version'],'importados como BORRADOR. Sin publicación, apertura, aceptación ficticia ni renovación de beta.')


if __name__=='__main__':
    main()
