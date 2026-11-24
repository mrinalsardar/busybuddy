#!/usr/bin/env bash
# Runs inside the `setup` service. Idempotent: applied migrations are recorded and skipped.
set -euo pipefail

echo "waiting for Auth to create its schema"
for _ in $(seq 1 120); do
  [ "$(psql -tAc "select to_regclass('auth.users') is not null")" = t ] && break
  sleep 1
done
[ "$(psql -tAc "select to_regclass('auth.users') is not null")" = t ] \
  || { echo "auth.users never appeared; check 'docker compose logs auth'" >&2; exit 1; }

psql -v ON_ERROR_STOP=1 -q -c "create schema if not exists dev; create table if not exists dev.applied_migration (name text primary key, applied_at timestamptz not null default now())"
for f in /migrations/*.sql; do
  name=$(basename "$f")
  if [ "$(psql -tAc "select count(*) from dev.applied_migration where name = '$name'")" = 0 ]; then
    echo "applying $name"
    psql -v ON_ERROR_STOP=1 -q --single-transaction -f "$f" -c "insert into dev.applied_migration (name) values ('$name')"
  fi
done

# Separate commands on purpose: one multi-statement `psql -c` is a single
# transaction, and `create database` cannot run inside one.
psql -v ON_ERROR_STOP=1 -q -c "do \$\$ begin if not exists (select from pg_roles where rolname = 'powersync_role') then create role powersync_role with replication bypassrls login password 'psync'; end if; end \$\$"
psql -v ON_ERROR_STOP=1 -q -c "grant select on all tables in schema public to powersync_role"
if [ "$(psql -tAc "select count(*) from pg_database where datname = 'powersync_storage'")" = 0 ]; then
  psql -v ON_ERROR_STOP=1 -q -c "create database powersync_storage"
fi
echo "setup done"
