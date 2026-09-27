#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
pg_bindir=$(pg_config --bindir)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/typed-realworld-postgres.XXXXXX")
pg_port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')

cleanup() {
  "$pg_bindir/pg_ctl" -D "$tmp/data" -m immediate stop >/dev/null 2>&1 || true
  python3 -c 'import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$tmp"
}
trap cleanup EXIT

"$pg_bindir/initdb" -D "$tmp/data" --encoding=UTF8 --locale=C \
  --auth-local=trust --auth-host=trust --no-instructions --no-sync >/dev/null
"$pg_bindir/pg_ctl" -D "$tmp/data" \
  -o "-c listen_addresses=127.0.0.1 -k $tmp -p $pg_port" \
  -l "$tmp/server.log" -w start >/dev/null

server_version=$("$pg_bindir/psql" -h 127.0.0.1 -p "$pg_port" -U "$(id -un)" \
  -d postgres -Atqc 'SHOW server_version_num')
if [[ "$server_version" -lt 180000 || "$server_version" -ge 190000 ]]; then
  printf 'PostgreSQL 18 is required, got %s.\n' "$server_version" >&2
  exit 1
fi

"$pg_bindir/createdb" -h 127.0.0.1 -p "$pg_port" typed_realworld_repository_test
"$pg_bindir/createdb" -h 127.0.0.1 -p "$pg_port" typed_realworld_api_test
repository_url="postgresql://$(id -un)@127.0.0.1:$pg_port/typed_realworld_repository_test?sslmode=disable"
api_url="postgresql://$(id -un)@127.0.0.1:$pg_port/typed_realworld_api_test?sslmode=disable"
REALWORLD_DATABASE_URL="$repository_url" bash "$root/scripts/dbmate.sh" up
opam exec -- dune exec --root "$root" test/repository_integration_test.exe -- "$repository_url"
SERVER_BIN="$root/_build/default/bin/realworld_server_postgres.exe" \
REALWORLD_TEST_DATABASE_URL="$api_url" \
bash "$root/scripts/api-test.sh"

printf 'PostgreSQL repository and API tests passed.\n'
