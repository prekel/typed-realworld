#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
binary="$root/.tools/bin/hurl"
if [[ -x $binary ]] \
   && LD_LIBRARY_PATH="$root/.tools${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
      "$binary" --version >/dev/null 2>&1; then
  exit 0
fi

version=$(<"$root/scripts/hurl-version")
case "$(uname -s):$(uname -m)" in
  Linux:x86_64) target=x86_64-unknown-linux-gnu; checksum=cac7c4670d69444db120edb21fe06c97ba8c80dcc52279957c8dd18f05fb0c06 ;;
  *) printf 'Hurl %s is only bootstrapped for Linux x86_64 by this script.\n' "$version" >&2; exit 1 ;;
esac

archive="hurl-${version}-${target}.tar.gz"
url="https://github.com/Orange-OpenSource/hurl/releases/download/${version}/${archive}"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/typed-realworld-hurl.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
curl --fail --location --silent --show-error --output "$tmp/$archive" "$url"
printf '%s  %s\n' "$checksum" "$tmp/$archive" | sha256sum --check --status
mkdir -p "$root/.tools/bin" "$tmp/unpack"
tar -xzf "$tmp/$archive" -C "$tmp/unpack" --strip-components=1
install -m 755 "$tmp/unpack/bin/hurl" "$root/.tools/bin/hurl"
if ! "$root/.tools/bin/hurl" --version >/dev/null 2>&1; then
  compatibility=$(find /usr/lib /lib -name 'libxml2.so.*' -type f 2>/dev/null | sort | tail -n 1 || true)
  if [[ -n $compatibility ]]; then
    ln -sfn "$compatibility" "$root/.tools/libxml2.so.2"
  fi
fi
LD_LIBRARY_PATH="$root/.tools${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$root/.tools/bin/hurl" --version >/dev/null
