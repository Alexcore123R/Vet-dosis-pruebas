#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
container_name="vetdosis-encrypted-backup-$$"
docker run -d --name "$container_name" --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine >/dev/null
trap 'docker rm -f "$container_name" >/dev/null' EXIT
ready=false
for attempt in {1..30};do
 if docker exec "$container_name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1;then ready=true;break;fi
 sleep 1
done
if [ "$ready" != true ];then echo 'PostgreSQL startup failed';exit 1;fi
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
create table public.synthetic_sample(id integer primary key, amount numeric, note text);
insert into public.synthetic_sample values(1,12.75,'dato ficticio'),(2,null,null);
alter table public.synthetic_sample enable row level security;
create policy synthetic_read on public.synthetic_sample for select using(true);
create function public.synthetic_total() returns numeric language sql as $$select sum(amount) from public.synthetic_sample$$;
create database synthetic_restored;
SQL
python3 - "$container_name" <<'PY'
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
sys.path.insert(0,'scripts/supabase')
from encrypted_database_backup import encrypt_and_check, gpg_process

container=sys.argv[1]
phrase='synthetic-only-test-passphrase-not-a-real-secret'
with tempfile.TemporaryDirectory(prefix='vetdosis-synthetic-backup-') as directory:
    target=Path(directory)/'synthetic.dump.gpg'
    dump=subprocess.Popen(['docker','exec',container,'pg_dump','-U','postgres','--format=custom','--no-owner','postgres'],stdout=subprocess.PIPE)
    try:
        result=encrypt_and_check(dump.stdout,target,phrase,
            ['docker','exec','-i',container,'pg_restore','--list'])
        assert dump.wait()==0
    finally:
        dump.stdout.close()
        if dump.poll() is None:
            dump.kill();dump.wait()
    assert result['decryption_integrity_verified'] and result['pg_restore_archive_readable']
    assert not result['full_database_restore_verified']
    # The verification flags must not confuse archive readability with a full restore.
    # Perform that full round trip here only against synthetic isolated data.
    home=Path(directory)/'verify-gpg';home.mkdir(mode=0o700)
    try:
        with tempfile.TemporaryFile() as errors, tempfile.TemporaryFile() as plaintext:
            with gpg_process(home,phrase,['--decrypt',str(target)],stdout=plaintext,stderr=errors) as decryptor:
                assert decryptor.wait()==0
            plaintext.seek(0)
            subprocess.run(['docker','exec','-i',container,'pg_restore','-U','postgres','--exit-on-error','--dbname','synthetic_restored'],
                           stdin=plaintext,stdout=subprocess.DEVNULL,check=True)
        restored=subprocess.check_output(['docker','exec',container,'psql','-U','postgres','-d','synthetic_restored','-At','-c',
            "select (select count(*)=2 and count(amount)=1 from public.synthetic_sample) and public.synthetic_total()=12.75 "
            "and (select relrowsecurity from pg_class where oid='public.synthetic_sample'::regclass) "
            "and exists(select 1 from pg_policy where polrelid='public.synthetic_sample'::regclass and polname='synthetic_read')"],text=True).strip()
        assert restored=='t', 'Synthetic data/functions/RLS/policies did not survive restoration'
        with tempfile.TemporaryFile() as errors:
            with gpg_process(home,'different-synthetic-passphrase',['--decrypt',str(target)],
                             stdout=subprocess.DEVNULL,stderr=errors) as wrong:
                assert wrong.wait()!=0, 'Wrong passphrase accepted'
        damaged=Path(directory)/'damaged.dump.gpg'
        ciphertext=bytearray(target.read_bytes());ciphertext[-30]^=1;damaged.write_bytes(ciphertext)
        with tempfile.TemporaryFile() as errors:
            with gpg_process(home,phrase,['--decrypt',str(damaged)],stdout=subprocess.DEVNULL,stderr=errors) as corrupt:
                assert corrupt.wait()!=0, 'Corrupted ciphertext accepted'
        try:
            encrypt_and_check(io.BytesIO(b''),Path(directory)/'empty.gpg',phrase,['false'])
            raise AssertionError('Empty export accepted')
        except RuntimeError:
            assert not (Path(directory)/'empty.gpg').exists()
    finally:
        subprocess.run(['gpgconf','--homedir',str(home),'--kill','gpg-agent'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
print('Synthetic encrypted backup: restored data/functions/RLS/policies; rejected wrong key, corruption and empty dump. No remote connection.')
PY
