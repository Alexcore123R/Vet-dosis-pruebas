"""Read-only account/clinic review. Prints metadata and counts, never records or secrets."""
import json
import uuid
from identity_schema import query


def identifier(value):
    return '"' + value.replace('"', '""') + '"'


def review(email):
    email = email.strip()
    if len(email) > 254 or '\n' in email or '@' not in email:
        raise SystemExit('Correo inválido para revisión.')
    literal = email.replace("'", "''")
    clinics = query(f"""select c.id,c.name,coalesce(w.kind,'clinic') as kind,
 c.created_by=u.id as is_owner,
 (select count(*) from public.clinic_members where clinic_id=c.id) as members
 from auth.users u join public.clinic_members m on m.user_id=u.id
 join public.clinics c on c.id=m.clinic_id
 left join public.account_workspaces w on w.clinic_id=c.id
 where lower(btrim(u.email))=lower(btrim('{literal}')) order by c.id""")
    columns = query("""select distinct n.nspname as schema,c.relname as table,a.attname as column
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
 where c.relkind='r' and n.nspname in ('public','private') and
 (a.attname='clinic_id' or exists(select 1 from pg_constraint f where f.contype='f'
 and f.conrelid=c.oid and f.confrelid='public.clinics'::regclass
 and cardinality(f.conkey)=1 and f.conkey[1]=a.attnum))
 order by n.nspname,c.relname,a.attname""")
    print('Revisión de clínicas vinculadas (solo lectura):', len(clinics))
    for clinic in clinics:
        scope = str(uuid.UUID(clinic['id']))
        selections = []
        for column in columns:
            name = column['schema'] + '.' + column['table']
            label = name.replace("'", "''")
            selections.append(f"select '{label}' as table_name,count(*) as rows from {identifier(column['schema'])}.{identifier(column['table'])} where {identifier(column['column'])}::text='{scope}'")
        counts = query(' union all '.join(selections)) if selections else []
        files = query(f"select count(*) as files from storage.objects where name like '{scope}/%'")[0]['files']
        report = dict(clinic, nonempty_tables=[row for row in counts if row['rows']], clinic_path_files=files)
        print('Resultado de revisión:', json.dumps(report, ensure_ascii=False, sort_keys=True))
    print('Revisión terminada. No se borró ni modificó ninguna cuenta, membresía o clínica.')
