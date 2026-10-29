#!/bin/bash
# Keep signing secrets out of command arguments, logs, and persistent daemons.
set +x
set -euo pipefail
if [[ $# -eq 0 ]]; then
  echo 'Usage: tool/android/with-signing.sh <build-command> [arguments...]' >&2
  exit 2
fi
export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.daemon=false"
if [[ ${LINEUP_ANDROID_SIGNING:-} == debug-key ]]; then
  unset LINEUP_ANDROID_KEYSTORE LINEUP_ANDROID_KEY_ALIAS LINEUP_ANDROID_KEY_PASSWORD
else
  export LINEUP_ANDROID_KEYSTORE="${LINEUP_ANDROID_KEYSTORE:-$HOME/.config/lineup-android/lineup-release.jks}"
  export LINEUP_ANDROID_KEY_ALIAS="${LINEUP_ANDROID_KEY_ALIAS:-lineup}"
  if [[ ! -f "$LINEUP_ANDROID_KEYSTORE" ]]; then
    echo 'Lineup signing keystore unavailable. See docs/android-runtime.md.' >&2
    exit 1
  fi
  if ! LINEUP_ANDROID_KEY_PASSWORD=$(security find-generic-password -a "$USER" -s lineup-android-release -w 2>/dev/null); then
    echo 'Lineup signing password unavailable in the login Keychain.' >&2
    exit 1
  fi
  if [[ -z "$LINEUP_ANDROID_KEY_PASSWORD" ]]; then
    echo 'Lineup signing password is empty.' >&2
    exit 1
  fi
  export LINEUP_ANDROID_KEY_PASSWORD
fi
exec "$@"
