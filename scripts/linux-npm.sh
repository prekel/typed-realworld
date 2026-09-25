#!/usr/bin/env bash
set -euo pipefail

IFS=: read -r -a path_dirs <<< "${PATH:-}"
for bin_dir in "${path_dirs[@]}" "$HOME"/.local/share/zed/node/*/bin "$HOME"/.nvm/versions/node/*/bin; do
  case "$bin_dir" in
    /mnt/[a-zA-Z]/*) continue ;;
  esac

  if [[ -x "$bin_dir/node" && -x "$bin_dir/npm" ]]; then
    export PATH="$bin_dir:$PATH"
    exec "$bin_dir/npm" "$@"
  fi
done

printf 'Linux node and npm are required for the frontend build. Install them in WSL.\n' >&2
exit 1
