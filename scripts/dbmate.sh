#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=$(<"$project_root/scripts/dbmate-version")
binary=${DBMATE_BIN:-"$project_root/.tools/bin/dbmate"}
if [[ ! -x "$binary" ]]; then
  printf 'dbmate is missing. Run make tools or set DBMATE_BIN to an absolute executable path.\n' >&2
  exit 1
fi
if [[ $("$binary" --version) != "dbmate version $version" ]]; then
  printf 'Expected dbmate %s. Run make tools.\n' "$version" >&2
  exit 1
fi

export REALWORLD_DATABASE_URL=${REALWORLD_DATABASE_URL:-sqlite3:realworld.sqlite3}
export DBMATE_STRICT=true
case "$REALWORLD_DATABASE_URL" in
  sqlite:*|sqlite3:*) ;;
  *) printf 'Only SQLite migrations are implemented; PostgreSQL support is planned.\n' >&2; exit 1 ;;
esac
# A single configuration source shared with the application. Do not implicitly
# load .env or let DBMATE_* variables redirect the schema history or dialect.
cd -- "$project_root"
exec "$binary" --env-file /dev/null --env REALWORLD_DATABASE_URL --driver sqlite \
  --migrations-dir "$project_root/db/migrations/sqlite" \
  --migrations-table schema_migrations --no-dump-schema "$@"
