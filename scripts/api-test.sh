#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
server=${SERVER_BIN:?SERVER_BIN is required}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/typed-realworld-api.XXXXXX")
port=${REALWORLD_TEST_PORT:-3100}
base="http://127.0.0.1:${port}"
trap '[[ -n ${server_pid:-} ]] && kill "$server_pid" 2>/dev/null || true; rm -rf -- "$tmp"' EXIT

REALWORLD_DATABASE_URL="sqlite3:$tmp/realworld.sqlite3" bash "$root/scripts/dbmate.sh" up
REALWORLD_DATABASE_URL="sqlite3:$tmp/realworld.sqlite3" \
REALWORLD_PORT="$port" \
REALWORLD_JWT_SECRET="hurl-contract-secret" \
"$server" >"$tmp/server.log" 2>&1 &
server_pid=$!

for _ in $(seq 1 50); do
  if curl --silent --fail "$base/api/tags" >/dev/null; then
    break
  fi
  sleep 0.1
done
if ! curl --silent --fail "$base/api/tags" >/dev/null; then
  cat "$tmp/server.log" >&2
  exit 1
fi
uid=$(date +%s)$$
"$root/scripts/hurl.sh" \
  --test \
  --jobs 1 \
  --variable "host=$base" \
  --variable "uid=$uid" \
  "$root"/test/hurl/official/*.hurl \
  "$root"/test/hurl/project/*.hurl
