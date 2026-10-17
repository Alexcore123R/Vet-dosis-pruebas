"""Encrypted pg_dump for the fixed test project. No restore into a remote database."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
from urllib.parse import parse_qs, unquote, urlsplit

from identity_schema import PROJECT

IMAGE = 'postgres:17-alpine'


def connection_environment(url):
    try:
        parsed = urlsplit(url)
        host, port = parsed.hostname or '', parsed.port or 5432
        user = unquote(parsed.username or '')
        password = unquote(parsed.password or '')
        direct = host == f'db.{PROJECT}.supabase.co' and user == 'postgres'
        pool = (host.endswith('.pooler.supabase.com') and user == f'postgres.{PROJECT}')
        if (parsed.scheme not in ('postgres', 'postgresql') or not (direct or pool)
                or port != 5432 or parsed.path != '/postgres' or parsed.fragment
                or set(parse_qs(parsed.query)) - {'sslmode'} or not password):
            raise ValueError
    except ValueError:
        raise ValueError('Use the fixed test project direct or session-pooler PostgreSQL URL on port 5432.') from None
    return {'PGHOST': host, 'PGPORT': str(port), 'PGUSER': user,
            'PGPASSWORD': password, 'PGDATABASE': 'postgres',
            'PGSSLMODE': 'verify-full', 'PGSSLROOTCERT': 'system',
            'PGCONNECT_TIMEOUT': '20',
            'PGOPTIONS': '-c default_transaction_read_only=on',
            'PGAPPNAME': 'vetdosis-encrypted-test-backup'}


def validate_passphrase(passphrase):
    if len(passphrase) < 20 or len(passphrase) > 1000 or '\n' in passphrase or '\r' in passphrase:
        raise ValueError('Backup passphrase must have 20–1000 characters and no newlines.')


def configuration_status(environment):
    url = environment.get('SUPABASE_TEST_DB_URL', '')
    phrase = environment.get('SUPABASE_TEST_BACKUP_PASSPHRASE', '')
    valid = False
    if url and phrase:
        try:
            connection_environment(url)
            validate_passphrase(phrase)
            valid = True
        except ValueError:
            pass
    return {'database_secret_present': bool(url), 'backup_passphrase_present': bool(phrase),
            'configuration_valid': valid, 'backup_created': False}


@contextmanager
def gpg_process(home, passphrase, arguments, **kwargs):
    read_fd, write_fd = os.pipe()
    process = None
    try:
        # Separate FD: the archive is stdin, and neither argv nor logs contain the passphrase.
        os.write(write_fd, passphrase.encode() + b'\n')
        os.close(write_fd)
        write_fd = -1
        command = ['gpg', '--no-options', '--homedir', str(home), '--batch', '--yes',
                   '--pinentry-mode', 'loopback', '--no-symkey-cache',
                   '--passphrase-fd', str(read_fd), *arguments]
        process = subprocess.Popen(command, pass_fds=(read_fd,), **kwargs)
        os.close(read_fd)
        read_fd = -1
        yield process
    finally:
        for descriptor in (read_fd, write_fd):
            if descriptor >= 0:
                os.close(descriptor)
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()


def encrypt_and_check(source, target, passphrase, archive_check):
    """Consume a dump stream; verify full decrypted hash and archive readability."""
    validate_passphrase(passphrase)
    original = hashlib.sha256()
    restored = hashlib.sha256()
    plaintext_bytes = 0
    target = Path(target)
    if target.exists():
        raise ValueError('Backup target already exists; no file overwritten.')
    with tempfile.TemporaryDirectory(prefix='vetdosis-backup-') as temporary:
        home = Path(temporary) / 'gpg'
        home.mkdir(mode=0o700)
        try:
            with tempfile.TemporaryFile() as errors:
                with gpg_process(home, passphrase,
                                 ['--symmetric', '--cipher-algo', 'AES256', '--s2k-mode', '3',
                                  '--s2k-count', '65011712', '--compress-algo', 'none',
                                  '--output', str(target)],
                                 stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=errors) as encryptor:
                    while chunk := source.read(1024 * 1024):
                        original.update(chunk)
                        plaintext_bytes += len(chunk)
                        encryptor.stdin.write(chunk)
                    encryptor.stdin.close()
                    if encryptor.wait() != 0 or plaintext_bytes == 0:
                        raise RuntimeError('Encrypted backup could not be created.')
                os.chmod(target, 0o600)
                # Unlinked temporary file is never uploaded; it closes on every exit path.
                with tempfile.TemporaryFile() as plaintext:
                    with gpg_process(home, passphrase, ['--decrypt', str(target)],
                                     stdout=subprocess.PIPE, stderr=errors) as decryptor:
                        while chunk := decryptor.stdout.read(1024 * 1024):
                            restored.update(chunk)
                            plaintext.write(chunk)
                        if decryptor.wait() != 0:
                            raise RuntimeError('Encrypted backup integrity verification failed.')
                    if restored.digest() != original.digest():
                        raise RuntimeError('Decrypted backup differs from the original dump.')
                    plaintext.seek(0)
                    check = subprocess.run(archive_check, stdin=plaintext,
                                           stdout=subprocess.DEVNULL, stderr=errors)
                    if check.returncode != 0:
                        raise RuntimeError('PostgreSQL could not read the decrypted archive.')
        except BaseException:
            target.unlink(missing_ok=True)
            raise
        finally:
            subprocess.run(['gpgconf', '--homedir', str(home), '--kill', 'gpg-agent'],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    encrypted = hashlib.sha256()
    with target.open('rb') as file:
        while chunk := file.read(1024 * 1024):
            encrypted.update(chunk)
    return {'encrypted_sha256': encrypted.hexdigest(), 'plaintext_sha256': original.hexdigest(),
            'encrypted_bytes': target.stat().st_size, 'plaintext_bytes': plaintext_bytes,
            'decryption_integrity_verified': True, 'pg_restore_archive_readable': True,
            'full_database_restore_verified': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--check-config', action='store_true')
    args = parser.parse_args()
    if args.check_config:
        print(json.dumps(configuration_status(os.environ), indent=2))
        return
    if args.output_dir is None:
        parser.error('--output-dir is required to create the encrypted backup')
    url = os.environ.get('SUPABASE_TEST_DB_URL', '')
    passphrase = os.environ.get('SUPABASE_TEST_BACKUP_PASSPHRASE', '')
    if not url or not passphrase:
        raise SystemExit('Configure SUPABASE_TEST_DB_URL and SUPABASE_TEST_BACKUP_PASSPHRASE in GitHub Actions secrets. Never send them in chat.')
    try:
        connection = connection_environment(url)
        validate_passphrase(passphrase)
        args.output_dir.mkdir(parents=True, exist_ok=False, mode=0o700)
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        target = args.output_dir / f'vetdosis-test-{stamp}.dump.gpg'
        # pg_dump uses a consistent snapshot and a read-only connection. Credentials
        # are inherited environment variables, never command-line URLs.
        command = ['docker', 'run', '--rm', '--network', 'host', '--read-only',
                   '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges']
        for key in connection:
            command += ['-e', key]
        command += [IMAGE, 'pg_dump', '--format=custom', '--no-owner', '--no-password',
                    '--lock-wait-timeout=10000']
        env = {key: value for key, value in os.environ.items()
               if key not in ('SUPABASE_TEST_DB_URL', 'SUPABASE_TEST_BACKUP_PASSPHRASE')}
        env.update(connection)
        with tempfile.TemporaryFile() as errors:
            dump = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=errors)
            try:
                evidence = encrypt_and_check(dump.stdout, target, passphrase,
                    ['docker', 'run', '--rm', '-i', '--network', 'none', IMAGE, 'pg_restore', '--list'])
                if dump.wait() != 0:
                    target.unlink(missing_ok=True)
                    raise RuntimeError('Database export failed; no backup published.')
            finally:
                dump.stdout.close()
                if dump.poll() is None:
                    dump.kill()
                    dump.wait()
        manifest = {'project_ref': PROJECT, 'created_at_utc': stamp, 'format': 'pg_dump custom + OpenPGP AES256',
                    'file': target.name, **evidence,
                    'scope': 'Database schemas/data/ACLs exported by pg_dump, without original ownership. '
                             'Cluster roles, platform configuration, Edge secrets and Storage binary files are not included.'}
        (args.output_dir / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        print('Encrypted database backup created; complete decryption hash and archive readability verified. Full restore and Storage binary recovery remain pending.')
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError):
        # No DB/GPG errors containing connection details or row contents in CI logs.
        raise SystemExit('Backup failed safely. No plaintext or credentials are logged; verify service secrets, connectivity and PostgreSQL version before retrying.') from None


if __name__ == '__main__':
    main()
