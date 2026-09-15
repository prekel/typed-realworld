#!/usr/bin/env bash
set -euo pipefail

build_root=$(cd -- "$1" && pwd)
test_binary=$(cd -- "$(dirname -- "$2")" && pwd)/$(basename -- "$2")
snapshot_binary=$(cd -- "$(dirname -- "$3")" && pwd)/$(basename -- "$3")
binary=${DBMATE_BIN:?Run make tools, then make test.}
version=$(<"$build_root/scripts/dbmate-version")
[[ $("$binary" --version) == "dbmate version $version" ]]
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/typed-realworld-migrations.XXXXXX")
trap 'rm -rf -- "$test_tmp"' EXIT

dbmate() {
  local directory=$1
  shift
  "$binary" --env-file /dev/null --env REALWORLD_DATABASE_URL --driver sqlite \
    --migrations-dir "$directory" --migrations-table schema_migrations --no-dump-schema "$@"
}
export REALWORLD_DATABASE_URL="sqlite3:$test_tmp/upgrade.sqlite3"
mkdir -- "$test_tmp/previous" "$test_tmp/failing"
cp -- "$build_root/db/migrations/sqlite/20260913000100_create_users.sql" "$test_tmp/previous/"
dbmate "$test_tmp/previous" up --strict
"$test_binary" seed "$REALWORLD_DATABASE_URL"
dbmate "$build_root/db/migrations/sqlite" up --strict
"$test_binary" verify "$REALWORLD_DATABASE_URL"
"$snapshot_binary" "$REALWORLD_DATABASE_URL" > "$test_tmp/upgraded.json"
diff -u "$build_root/db/schema.json" "$test_tmp/upgraded.json"

# Re-running does not change the schema or lose the seeded user.
dbmate "$build_root/db/migrations/sqlite" up --strict
dbmate "$build_root/db/migrations/sqlite" status --exit-code
"$test_binary" check-user "$REALWORLD_DATABASE_URL"
"$snapshot_binary" "$REALWORLD_DATABASE_URL" > "$test_tmp/repeated.json"
cmp "$test_tmp/upgraded.json" "$test_tmp/repeated.json"

# An unsuccessful migration must roll back both DDL and its history entry.
cp -- "$build_root"/db/migrations/sqlite/*.sql "$test_tmp/failing/"
cp -- "$build_root/test/fixtures/20260913000300_failing_migration.sql" "$test_tmp/failing/"
if dbmate "$test_tmp/failing" up --strict > "$test_tmp/failure.log" 2>&1; then
  printf 'Broken migration unexpectedly succeeded.\n' >&2
  exit 1
fi
"$snapshot_binary" "$REALWORLD_DATABASE_URL" > "$test_tmp/failed.json"
cmp "$test_tmp/upgraded.json" "$test_tmp/failed.json"
if dbmate "$test_tmp/failing" status --exit-code > "$test_tmp/status.log"; then
  printf 'Failed migration was incorrectly recorded as applied.\n' >&2
  exit 1
fi
"$test_binary" check-user "$REALWORLD_DATABASE_URL"

# A fresh database must have exactly the same application schema as an upgrade.
export REALWORLD_DATABASE_URL="sqlite3:$test_tmp/fresh.sqlite3"
dbmate "$build_root/db/migrations/sqlite" up --strict
"$snapshot_binary" "$REALWORLD_DATABASE_URL" > "$test_tmp/fresh.json"
cmp "$test_tmp/upgraded.json" "$test_tmp/fresh.json"
printf 'Migration, upgrade, rollback, snapshot and generated-query tests passed.\n'
