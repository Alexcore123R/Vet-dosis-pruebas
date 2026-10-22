"""Audit ONLY public.app_module_workspace in the fixed Supabase TEST project.

Read-only catalog query; never touches patients, creates users, enables permissions,
applies SQL, or writes any data. Do not treat lexical similarity as SQL equivalence.
"""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re

from identity_schema import PROJECT, query

ROOT = Path(__file__).resolve().parents[2]
CANDIDATES = {
    '13N': ROOT / 'supabase/proposed/13N_module_navigation_dashboard.sql',
    '13O': ROOT / 'supabase/proposed/13O_permission_backups_exports.sql',
}
SQL = """select
 p.prosrc as source,
 p.prosecdef as security_definer,
 p.provolatile as volatility,
 has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
 has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
 encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') as source_sha256
from pg_proc p
where p.oid=to_regprocedure('public.app_module_workspace(uuid)')"""


def candidate_body(source):
    pattern = (r'create\s+(?:or\s+replace\s+)?function\s+'
               r'public\.app_module_workspace\s*\([^)]*\)\s+'
               r'returns\s+jsonb\b.*?\bas\s+\$\$(.*?)\$\$\s*;')
    matches = re.findall(pattern, source, re.I | re.S)
    if len(matches) != 1:
        raise ValueError('Expected exactly one candidate body.')
    return matches[0]


def summarize(read=query, sources=None):
    data = read(SQL)
    if not isinstance(data, list) or len(data) > 1:
        raise ValueError('Unexpected catalog result.')
    if not data:
        return {'project_ref': PROJECT, 'read_only': True, 'function_present': False,
                'verdict': 'missing', 'deploy_ready': False}, ''
    current = data[0]
    if not isinstance(current.get('source'), str):
        raise ValueError('Missing function definition.')
    if sources is None:
        sources = {key: candidate_body(path.read_text()) for key,path in CANDIDATES.items()}
    body = current['source']
    identical = [key for key,source in sources.items() if source == body]
    expected = sources['13O']
    # Approximation used only as a clue, never as proof of semantic equality.
    maybe_formatting = bool(not identical and re.sub(r'\s+', '',body)==re.sub(r'\s+','',expected))
    verdict = ('exact_'+identical[-1] if identical
               else 'possibly_formatting_only_not_verified' if maybe_formatting
               else 'different_definition_requires_review')
    def tokens(t):
        return sorted(set(re.findall(r"'(patients|agenda|hospital|inventory|sales|prescriptions|forms|clinical|statistics|backup)'",t)))
    delta = ''.join(difflib.unified_diff(
        expected.splitlines(keepends=True),body.splitlines(keepends=True),
        fromfile='candidate_13O',tofile='remote_function',n=2))
    metadata = {
        'project_ref':PROJECT, 'read_only':True, 'function_present':True,
        'verdict': verdict,
        'sha256_remote':hashlib.sha256(body.encode()).hexdigest(),
        'sha256_13O': hashlib.sha256(expected.encode()).hexdigest(),
        'sha256_13N': hashlib.sha256(sources['13N'].encode()).hexdigest(),
        'remote_module_tokens':tokens(body), 'candidate_13O_tokens':tokens(expected),
        'module_tokens_missing':sorted(set(tokens(expected))-set(tokens(body))),
        'module_tokens_extra':sorted(set(tokens(body))-set(tokens(expected))),
        'security_definer':current['security_definer'],
        'volatility':current['volatility'],
        'execute_anon':current['anon_execute'],
        'execute_authenticated':current['authenticated_execute'],
        'changed_lines_unified_diff':len(delta.splitlines()),
        'deploy_ready':False,
        'limitations':[
            'Hash, source text and token comparisons are NOT equivalent to authorization tests.',
            'Do not replace the remote function without reviewing the exact difference and permissions.',
            'The remaining P0 requires real authenticated multi-account/multi-clinic HTTP checks.',
        ]
    }
    return metadata, delta


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--diff-output',type=Path,required=True)
    args=parser.parse_args()
    report,delta=summarize()
    args.output.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    # SQL source code only. Keep raw function definitions off console logs.
    args.diff_output.write_text(delta or 'No source differences.\n')
    print(json.dumps(report,indent=2,ensure_ascii=False))
    if report.get('execute_anon') is True or report.get('security_definer') is not True:
        raise SystemExit('Function has an unexpected security surface.')


if __name__ == '__main__':
    main()
