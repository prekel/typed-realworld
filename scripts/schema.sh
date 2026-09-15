#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
case ${1:-} in
  update|check) action=$1 ;;
  *) printf 'Usage: schema.sh update|check\n' >&2; exit 2 ;;
esac
schema_tmp=$(mktemp -d "${TMPDIR:-/tmp}/typed-realworld-schema.XXXXXX")
trap 'rm -rf -- "$schema_tmp"' EXIT
schema_url="sqlite3:$schema_tmp/schema.sqlite3"
# Always rebuild a disposable database; never introspect the developer's data.
REALWORLD_DATABASE_URL="$schema_url" bash "$project_root/scripts/dbmate.sh" up >&2
opam exec -- dune exec --root "$project_root" tools/schema_snapshot.exe -- "$schema_url" \
  > "$schema_tmp/schema.json"

if [[ $action == check ]]; then
  if ! diff -u "$project_root/db/schema.json" "$schema_tmp/schema.json"; then
    printf 'Schema snapshot is stale. Run make schema and review db/schema.json.\n' >&2
    exit 1
  fi
  printf 'Schema snapshot matches migrations.\n'
else
  # Keep the previous snapshot intact if migration, introspection or codegen fails.
  if ! cmp -s "$schema_tmp/schema.json" "$project_root/db/schema.json"; then
    cp -- "$schema_tmp/schema.json" "$project_root/db/schema.json"
  fi
  printf 'Updated db/schema.json.\n'
fi
