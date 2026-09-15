#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=$(<"$project_root/scripts/dbmate-version")
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    asset=dbmate-linux-amd64
    checksum=5f1371fdf2d2798f089832ca73ac42d02694f8e07ed11523ca25a79a1fa9364c ;;
  Linux-aarch64|Linux-arm64)
    asset=dbmate-linux-arm64
    checksum=657d0ba57cc965f71e79b1dc532aaa21ea72cd9a541e995b3969f88b9053c3ea ;;
  Darwin-x86_64)
    asset=dbmate-macos-amd64
    checksum=58e134d2568ab5cc1f08f4471561c99ff374b1645c8acde982a4b75673355674 ;;
  Darwin-arm64)
    asset=dbmate-macos-arm64
    checksum=70ccca3263c0f50bfa201ce32f051dd576ef6c8c8b3930c3cb99e6ce2bb2ce6d ;;
  *) printf 'Unsupported platform. Install dbmate %s and set DBMATE_BIN.\n' "$version" >&2; exit 1 ;;
esac

destination="$project_root/.tools/bin/dbmate"
if [[ -x "$destination" ]] && [[ $("$destination" --version) == "dbmate version $version" ]]; then
  "$destination" --version
  exit 0
fi
mkdir -p -- "$project_root/.tools/bin"
download=$(mktemp "$project_root/.tools/bin/dbmate.download.XXXXXX")
trap 'rm -f -- "$download"' EXIT
curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
  "https://github.com/amacneil/dbmate/releases/download/v$version/$asset" -o "$download"
if command -v sha256sum >/dev/null; then
  printf '%s  %s\n' "$checksum" "$download" | sha256sum --check --status
else
  printf '%s  %s\n' "$checksum" "$download" | shasum -a 256 --check --status
fi
chmod 755 "$download"
mv -- "$download" "$destination"
"$destination" --version
