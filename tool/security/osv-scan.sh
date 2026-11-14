#!/usr/bin/env bash
# Ordinary OSV-Scanner with verified upstream release bytes. Never runs builds.
set -euo pipefail
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64)
    asset=osv-scanner_linux_amd64
    expected=fb7dab19a8bd9bbe5c3189f09d4b7ee1820c9553a23bac202648a56efd2f6ee8
    ;;
  Darwin/arm64)
    asset=osv-scanner_darwin_arm64
    expected=b22c02877a811c8f78956e8643efa554932b7378f590d13f8e97d4e9448a29f3
    ;;
  *) echo 'Unsupported scanner host. Use a supported host or record a manual advisory review.' >&2; exit 2 ;;
esac
scan_tools=$(mktemp -d)
trap 'rm -rf "$scan_tools"' EXIT
curl --fail --location --retry 3 "https://github.com/google/osv-scanner/releases/download/v2.7.1/$asset" -o "$scan_tools/osv-scanner"
actual=$(shasum -a 256 "$scan_tools/osv-scanner")
if [[ "${actual%% *}" != "$expected" ]]; then
  echo 'OSV-Scanner release digest mismatch.' >&2
  exit 2
fi
chmod +x "$scan_tools/osv-scanner"
"$scan_tools/osv-scanner" --version
python3 "$(dirname "$0")/scanner-fixture-test.py" "$scan_tools/osv-scanner"
"$scan_tools/osv-scanner" scan source "$@"
