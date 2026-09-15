#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ ! ${NAME:-} =~ ^[a-z][a-z0-9_]*$ ]]; then
  printf 'Usage: make migration NAME=add_bio (lowercase letters, digits, underscores).\n' >&2
  exit 2
fi
exec bash "$project_root/scripts/dbmate.sh" new "$NAME"
