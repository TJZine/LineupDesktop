#!/bin/sh
# Xcode build phases for the prepared libmpv runtime (LINEUP_MPV_RUNTIME, set
# in Runner/Configs/NativePlayer.xcconfig).
#
#   mpv_runtime.sh check   fail early with a clear message when it is missing
#   mpv_runtime.sh embed   copy its dylibs into Contents/Frameworks and sign
#                          them with the app's signing identity
set -eu

runtime="${LINEUP_MPV_RUNTIME:-}"

check() {
  if [ -z "$runtime" ] || [ ! -f "$runtime/include/mpv/client.h" ] ||
    [ ! -f "$runtime/lib/libmpv.2.dylib" ]; then
    echo "error: The libmpv runtime was not found at LINEUP_MPV_RUNTIME='$runtime'." >&2
    echo "error: Build or provision the macOS runtime (lib/ and include/mpv/), or point LINEUP_MPV_RUNTIME at one through the environment or Runner/Configs/NativePlayer.local.xcconfig. See docs/DEVELOPMENT.md." >&2
    exit 1
  fi
}

embed() {
  check
  destination="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
  mkdir -p "$destination"
  for library in "$runtime"/lib/*.dylib; do
    name=$(basename "$library")
    rm -f "$destination/$name"
    cp -L "$library" "$destination/$name"
    chmod u+w "$destination/$name"
    if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]; then
      identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
      [ -n "$identity" ] || identity="-"
      if [ "${ENABLE_HARDENED_RUNTIME:-NO}" = "YES" ]; then
        codesign --force --sign "$identity" --options runtime --timestamp=none \
          "$destination/$name"
      else
        codesign --force --sign "$identity" --timestamp=none "$destination/$name"
      fi
    fi
  done
}

case "${1:-}" in
  check) check ;;
  embed) embed ;;
  *)
    echo "usage: $0 check|embed" >&2
    exit 2
    ;;
esac
