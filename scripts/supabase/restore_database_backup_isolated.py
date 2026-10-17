"""Restore an existing encrypted archive only into a disposable networkless container."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time
import os
import uuid

from encrypted_database_backup import gpg_process, validate_passphrase
from identity_schema import PROJECT

IMAGE = 'supabase/postgres:17.11.0.004'
ROLES = ('anon','authenticated','service_role','authenticator','supabase_admin',
         'supabase_auth_admin','supabase_storage_admin','supabase_functions_admin',
         'supabase_replication_admin','supabase_read_only_user','dashboard_user','pgbouncer',
         'pgsodium_keyholder','pgsodium_keyiduser','pgsodium_keymaker')


def archive_path(directory, manifest):
    name = manifest.get('file')
    if (manifest.get('project_ref') != PROJECT or not isinstance(name, str)
            or Path(name).name != name or not name.endswith('.dump.gpg')):
        raise ValueError('Archive manifest does not identify the fixed test project.')
    for field in ('encrypted_sha256','plaintext_sha256'):
        if not isinstance(manifest.get(field),str) or not re.fullmatch('[0-9a-f]{64}',manifest[field]):
            raise ValueError('Invalid archive checksum metadata.')
    return directory / name


def restore_error_classes(text):
    # Never print raw restore stderr: it can include SQL and application values.
    patterns = {'extension_unavailable': 'is not available',
                'dependent_object_missing': 'does not exist', 'object_already_exists': 'already exists',
                'permission_denied': 'permission denied', 'unsupported_parameter': 'unrecognized configuration parameter',
                'extension_version_missing': 'has no installation script', 'syntax_error': 'syntax error'}
    return sorted(name for name,fragment in patterns.items() if fragment in text.lower()) or ['unclassified_restore_failure']


def missing_managed_role(text):
    match=re.search(r'role "([^"]+)" does not exist',text)
    if match and re.fullmatch(r'(?:supabase_[a-z_]+|pgsodium_[a-z_]+)',match[1]):
        return match[1]
    return None


def run_restore(directory, passphrase, output, trial=False, client_extras=False):
    validate_passphrase(passphrase)
    manifest=json.loads((directory/'manifest.json').read_text())
    archive=archive_path(directory,manifest)
    checksum=hashlib.sha256()
    with archive.open('rb') as source:
        while chunk:=source.read(1024*1024): checksum.update(chunk)
    if checksum.hexdigest()!=manifest['encrypted_sha256']:
        raise ValueError('Encrypted artifact checksum mismatch.')
    name='vetdosis-real-restore-'+uuid.uuid4().hex[:12]
    report={'project_ref':PROJECT,'source_file':archive.name,
            'checked_at_utc':datetime.now(timezone.utc).isoformat(),
            'archive_restore_succeeded':False,'service_recovery_verified':False,
            'migration_rehearsal_passed':False,'active_database_modified':False,
            'scope':'Disposable networkless restore of the existing logical database archive. '
                    'Global role identity/ownership, platform secrets and Storage binaries are not restored.'}
    try:
        with tempfile.TemporaryDirectory(prefix='vetdosis-real-restore-') as temporary, tempfile.TemporaryFile() as errors, tempfile.TemporaryFile() as plaintext:
            home=Path(temporary)/'gpg';home.mkdir(mode=0o700)
            try:
                with gpg_process(home,passphrase,['--decrypt',str(archive)],stdout=plaintext,stderr=errors) as decryptor:
                    if decryptor.wait()!=0: raise ValueError('Backup could not be authenticated/decrypted.')
            finally:
                subprocess.run(['gpgconf','--homedir',str(home),'--kill','gpg-agent'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            plaintext.seek(0);checksum=hashlib.sha256()
            while chunk:=plaintext.read(1024*1024): checksum.update(chunk)
            if checksum.hexdigest()!=manifest['plaintext_sha256']:
                raise ValueError('Plaintext backup checksum mismatch.')
            report['decryption_integrity_verified']=True
            subprocess.run(['docker','run','-d','--name',name,'--network','none',
                            '-e','POSTGRES_PASSWORD=synthetic-isolated-restore-only',
                            '-e','POSTGRES_HOST_AUTH_METHOD=trust',IMAGE,
                            'postgres','-D','/etc/postgresql','-c','cron.launch_active_jobs=off',
                            '-c','cron.database_name=restored_backup'],
                           stdout=subprocess.DEVNULL,stderr=errors,check=True)
            network=subprocess.check_output(['docker','inspect',name,'--format','{{.HostConfig.NetworkMode}}'],text=True).strip()
            if network!='none': raise RuntimeError('Restore container must have no network.')
            ready=False
            for _ in range(90):
                if subprocess.run(['docker','exec',name,'pg_isready','-h','127.0.0.1','-U','postgres'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:
                    ready=True;break
                time.sleep(1)
            if not ready:
                report['failure_stage']='isolated_database_startup';return report
            admin=None
            for candidate in ('supabase_admin','postgres'):
                probe=subprocess.run(['docker','exec',name,'psql','-w','-h','127.0.0.1','-U',candidate,
                                      '-d','postgres','-At','-c','select rolsuper from pg_roles where rolname=current_user'],
                                     stdout=subprocess.PIPE,stderr=errors)
                if probe.returncode==0 and probe.stdout.strip()==b't':
                    admin=candidate;break
            if admin is None:
                report['failure_stage']='isolated_superuser_unavailable';return report
            report['isolated_superuser_verified']=True
            setup=''.join("do $$begin if not exists(select 1 from pg_roles where rolname='"+role+"') then create role "+role+" nologin;end if;end$$;\n" for role in ROLES)
            setup+='create database restored_backup template template0;\n'
            result=subprocess.run(['docker','exec','-i',name,'psql','-w','-h','127.0.0.1','-U',admin,'-d','postgres','-v','ON_ERROR_STOP=1'],
                                  input=setup.encode(),stdout=subprocess.DEVNULL,stderr=errors)
            if result.returncode:
                report['failure_stage']='isolated_role_setup';return report
            for attempt in range(6):
                plaintext.seek(0)
                errors.seek(0);errors.truncate()
                result=subprocess.run(['docker','exec','-i',name,'pg_restore','-w','-h','127.0.0.1','-U',admin,'--no-owner',
                                       '--exit-on-error','--dbname','restored_backup'],
                                      stdin=plaintext,stdout=subprocess.DEVNULL,stderr=errors)
                if result.returncode==0: break
                errors.seek(0);diagnostic=errors.read().decode(errors='replace')
                missing=missing_managed_role(diagnostic)
                if missing is None or attempt==5:
                    report.update(failure_stage='archive_restore',error_classes=restore_error_classes(diagnostic))
                    return report
                # Only known managed-role identifiers, without passwords or login.
                # Restart from a clean local DB; never continue a partial restore.
                setup='create role "'+missing+'" nologin;\ndrop database restored_backup with (force);\ncreate database restored_backup template template0;\n'
                retry=subprocess.run(['docker','exec','-i',name,'psql','-w','-h','127.0.0.1','-U',admin,'-d','postgres','-v','ON_ERROR_STOP=1'],
                                     input=setup.encode(),stdout=subprocess.DEVNULL,stderr=errors)
                if retry.returncode:
                    report['failure_stage']='isolated_managed_role_setup';return report
                report['additional_placeholder_roles']=report.get('additional_placeholder_roles',0)+1
            report['archive_restore_succeeded']=True
            report['network_mode']='none'
            counts_sql="""select json_build_object(
              'patients',(select count(*) from public.vet_patients),
              'owners',(select count(*) from public.vet_owners),
              'medication',(select count(*) from public.medication_records),
              'storage_objects_metadata',(select count(*) from storage.objects),
              'application_tables',(select count(*) from pg_tables where schemaname in ('public','private'))
            )"""
            result=subprocess.run(['docker','exec','-i',name,'psql','-w','-h','127.0.0.1','-U',admin,'-d','restored_backup','-At','-v','ON_ERROR_STOP=1'],
                                  input=counts_sql.encode(),stdout=subprocess.PIPE,stderr=errors)
            if result.returncode: report['verification_queries_passed']=False;return report
            report['restored_counts']=json.loads(result.stdout)
            report['verification_queries_passed']=True
            if trial:
                from integration_bundle import bundle_sql
                sql = bundle_sql()
                if client_extras:
                    from integration_client_rehearsal import client_rehearsal_sql, EXTRA_FILES
                    sql = client_rehearsal_sql()
                    report['client_compatibility_candidates'] = list(EXTRA_FILES)
                result=subprocess.run(['docker','exec','-i',name,'psql','-w','-h','127.0.0.1','-U',admin,'-d','restored_backup','-v','ON_ERROR_STOP=1'],
                                      input=sql.encode(),stdout=subprocess.DEVNULL,stderr=errors)
                report['migration_rehearsal_passed']=result.returncode==0
                report['migration_rehearsal_mode']=('23 candidates + client extras' if client_extras else '23 candidates') + ', ROLLBACK, isolated copy only'
            return report
    finally:
        subprocess.run(['docker','rm','-f','-v',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        output.write_text(json.dumps(report,indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact-dir',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--trial-migrations',action='store_true')
    parser.add_argument('--trial-client-extras',action='store_true')
    args=parser.parse_args()
    if args.trial_client_extras and not args.trial_migrations:
        parser.error('Client extras require --trial-migrations.')
    if os.environ.get('SUPABASE_TEST_DB_URL'):
        raise SystemExit('Do not provide a live database connection to this isolated restore job.')
    try:
        report=run_restore(args.artifact_dir,os.environ.get('SUPABASE_TEST_BACKUP_PASSPHRASE',''),args.output,args.trial_migrations,args.trial_client_extras)
    except (ValueError,RuntimeError,OSError,subprocess.SubprocessError):
        raise SystemExit('Isolated restore failed safely; no private diagnostics are logged.') from None
    print(json.dumps(report,indent=2))
    if not report.get('archive_restore_succeeded') or not report.get('verification_queries_passed'):
        raise SystemExit('The real archive is not yet certified as restorable in this isolated environment.')
    if args.trial_migrations and not report.get('migration_rehearsal_passed'):
        raise SystemExit('The isolated migration trial did not pass. The active server was not changed.')


if __name__=='__main__':
    main()
