#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
binary=${HURL_BIN:-"$root/.tools/bin/hurl"}
if [[ ! -x $binary ]]; then
  printf 'Hurl is missing. Run make hurl-tools.\n' >&2
  exit 1
fi
# Some rolling Linux distributions expose a newer libxml2 SONAME. A colocated
# compatibility library, if supplied by the developer, is intentionally scoped
# to this tool invocation.
tool_dir=$(cd -- "$(dirname -- "$binary")/.." && pwd)
if [[ -f $tool_dir/libxml2.so.2 ]]; then
  export LD_LIBRARY_PATH="$tool_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
exec "$binary" "$@"
