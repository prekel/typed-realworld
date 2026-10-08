#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
case ${1:-} in
  update|check) action=$1 ;;
  *) printf 'Usage: frontend-types.sh update|check\n' >&2; exit 2 ;;
esac

cd "$project_root/frontend"
if [[ $action == update ]]; then
  bash ../scripts/linux-npm.sh run generate:api
  exit 0
fi

types_tmp=$(mktemp -d "${TMPDIR:-/tmp}/typed-realworld-frontend-types.XXXXXX")
trap 'rm -rf -- "$types_tmp"' EXIT
bash ../scripts/linux-npm.sh run generate:api -- --output "$types_tmp/api"
if ! diff -ru "$project_root/frontend/src/generated/api" "$types_tmp/api"; then
  printf 'Generated TypeScript client is stale. Run make frontend-types and review frontend/src/generated/api.\n' >&2
  exit 1
fi
printf 'Generated TypeScript client matches OpenAPI.\n'
