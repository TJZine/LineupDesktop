#!/usr/bin/env bash
# Compatibility entry point for credential-free development builds.
set -euo pipefail
if [[ $# -eq 0 ]]; then
  echo 'Usage: tool/android/with-signing.sh <build-command> [arguments...]' >&2
  exit 2
fi
export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.daemon=false"
exec "$@"
