#!/bin/sh
# Xcode build phases for the prepared libmpv runtime (LINEUP_MPV_RUNTIME, set
# in Runner/Configs/NativePlayer.xcconfig).
#
#   mpv_runtime.sh check   fail early with a clear message when it is missing
#   mpv_runtime.sh embed   copy its dylibs into Contents/Frameworks and sign
#                          them with the app's signing identity
set -eu

runtime="${LINEUP_MPV_RUNTIME:-}"
manifest_name='.lineup-mpv-runtime-manifest'
pending_manifest_name='.lineup-mpv-runtime-pending'

check() {
  if [ -z "$runtime" ] || [ ! -f "$runtime/include/mpv/client.h" ] ||
    [ ! -f "$runtime/lib/libmpv.2.dylib" ]; then
    echo "error: The libmpv runtime was not found at LINEUP_MPV_RUNTIME='$runtime'." >&2
    echo "error: Build or provision the macOS runtime (lib/ and include/mpv/), or point LINEUP_MPV_RUNTIME at one through the environment or Runner/Configs/NativePlayer.local.xcconfig. See docs/DEVELOPMENT.md." >&2
    exit 1
  fi
}

fail() {
  echo "error: $*" >&2
  exit 1
}

validate_runtime_name() {
  name=$1
  case "$name" in
    ''|.|..|/*|*/*|*\\*|*[!A-Za-z0-9._-]*)
      fail "Invalid libmpv runtime manifest entry '$name'."
      ;;
  esac
  case "$name" in
    *.dylib) ;;
    *) fail "Invalid libmpv runtime manifest entry '$name'." ;;
  esac
}

is_numeric_version() {
  version=$1
  case "$version" in
    ''|.*|*.) return 1 ;;
    *[!0-9.]*) return 1 ;;
  esac
  old_ifs=$IFS
  IFS=.
  set -- $version
  IFS=$old_ifs
  [ "$#" -gt 0 ] || return 1
  for component in "$@"; do
    case "$component" in
      ''|*[!0-9]*) return 1 ;;
    esac
  done
  return 0
}

component_family() {
  name=$1
  stem=${name%.dylib}
  case "$stem" in
    *.*)
      family=${stem%%.*}
      version=${stem#"$family."}
      if is_numeric_version "$version"; then
        printf '%s\n' "$family"
      else
        printf '%s\n' "$stem"
      fi
      ;;
    *)
      printf '%s\n' "$stem"
      ;;
  esac
}

list_contains() {
  needle=$1
  list=$2
  for item in $list; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

is_migration_alias() {
  name=$1
  list_contains "$name" "$current_entries" && return 1
  stem=${name%.dylib}
  for family in $current_families; do
    case "$stem" in
      "$family".*)
        version=${stem#"$family."}
        if is_numeric_version "$version"; then
          return 0
        fi
        ;;
    esac
  done
  return 1
}

sign_library() {
  library=$1
  [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ] && return 0

  identity=${EXPANDED_CODE_SIGN_IDENTITY:-}
  [ -n "$identity" ] || identity='-'
  if [ "$identity" = '-' ]; then
    timestamp='--timestamp=none'
  else
    timestamp='--timestamp'
  fi

  if [ "${ENABLE_HARDENED_RUNTIME:-NO}" = "YES" ]; then
    codesign --force --sign "$identity" --options runtime "$timestamp" "$library"
  else
    codesign --force --sign "$identity" "$timestamp" "$library"
  fi
}

read_manifest() {
  manifest_path=$1
  read_entries=''
  read_exists=0
  if [ -e "$manifest_path" ] || [ -L "$manifest_path" ]; then
    [ -f "$manifest_path" ] && [ ! -L "$manifest_path" ] ||
      fail "The libmpv runtime manifest is not a regular file: $manifest_path"
    read_exists=1
    while IFS= read -r entry || [ -n "$entry" ]; do
      validate_runtime_name "$entry"
      read_entries="${read_entries}${entry} "
    done < "$manifest_path"
  fi
}

write_manifest() {
  manifest_path=$1
  entries=$2
  write_tmp=$(mktemp "$manifest_path.XXXXXX")
  : > "$write_tmp"
  for entry in $entries; do
    printf '%s\n' "$entry" >> "$write_tmp"
  done
  mv -f "$write_tmp" "$manifest_path"
  write_tmp=''
}

stage=''
write_tmp=''
cleanup_embed_artifacts() {
  cleanup_status=$1
  if [ -n "${stage:-}" ] && [ -d "$stage" ]; then
    for staged in "$stage"/*.dylib; do
      [ -f "$staged" ] || continue
      rm -f "$staged" || :
    done
    rmdir "$stage" 2>/dev/null || :
  fi
  if [ -n "${write_tmp:-}" ]; then
    rm -f "$write_tmp" || :
  fi
  return "$cleanup_status"
}

prepare_destination_names() {
  for name in $current_entries; do
    target="$destination/$name"
    if [ -d "$target" ] && [ ! -L "$target" ]; then
      fail "The app Frameworks destination contains a directory for '$name'."
    fi
  done
  for name in $current_entries; do
    target="$destination/$name"
    if [ -L "$target" ]; then
      rm -f "$target"
    fi
  done
}

embed() {
  check
  destination="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
  [ ! -L "$destination" ] || fail "The app Frameworks destination must not be a symlink: $destination"
  mkdir -p "$destination"
  trap 'status=$?; cleanup_embed_artifacts "$status"; exit "$status"' EXIT

  current_entries=''
  current_families=''
  current_count=0
  for library in "$runtime"/lib/*.dylib; do
    [ -f "$library" ] || continue
    current_count=$((current_count + 1))
    name=$(basename "$library")
    validate_runtime_name "$name"
    current_entries="${current_entries}${name} "
    family=$(component_family "$name")
    if ! list_contains "$family" "$current_families"; then
      current_families="${current_families}${family} "
    fi
  done
  [ "$current_count" -gt 0 ] || fail "The libmpv runtime has no dylibs in '$runtime/lib'."

  manifest="$destination/$manifest_name"
  pending_manifest="$destination/$pending_manifest_name"
  read_manifest "$manifest"
  manifest_exists=$read_exists
  previous_entries=$read_entries
  read_manifest "$pending_manifest"
  pending_exists=$read_exists
  pending_entries=$read_entries

  # A pending manifest owns names that may have been published before a
  # previous install was interrupted. Validate both manifests above before
  # removing any of those names.
  if [ "$pending_exists" -eq 1 ]; then
    for entry in $pending_entries; do
      if ! list_contains "$entry" "$current_entries" &&
        { [ -e "$destination/$entry" ] || [ -L "$destination/$entry" ]; }; then
        rm -f "$destination/$entry"
      fi
    done
  fi

  stage=$(mktemp -d "${TMPDIR:-/tmp}/lineup-mpv-runtime.XXXXXX")
  for name in $current_entries; do
    library="$runtime/lib/$name"
    cp -L "$library" "$stage/$name"
    chmod u+w "$stage/$name"
    sign_library "$stage/$name"
  done

  # Ownership is recorded before any staged file is published. If a later
  # move or cleanup fails, a retry can remove names that are no longer current.
  write_manifest "$pending_manifest" "$current_entries"
  prepare_destination_names
  for name in $current_entries; do
    mv -f "$stage/$name" "$destination/$name"
  done

  if [ "$manifest_exists" -eq 1 ]; then
    for entry in $previous_entries; do
      if ! list_contains "$entry" "$current_entries" &&
        { [ -e "$destination/$entry" ] || [ -L "$destination/$entry" ]; }; then
        rm -f "$destination/$entry"
      fi
    done
  else
    # Pre-manifest bundles may contain old install-name aliases. Only remove
    # numeric aliases for families present in the current prepared runtime.
    for candidate in "$destination"/*.dylib; do
      [ -f "$candidate" ] || [ -L "$candidate" ] || continue
      name=$(basename "$candidate")
      if is_migration_alias "$name"; then
        rm -f "$candidate"
      fi
    done
  fi

  write_manifest "$manifest" "$current_entries"
  rm -f "$pending_manifest"
}

case "${1:-}" in
  check) check ;;
  embed) embed ;;
  *)
    echo "usage: $0 check|embed" >&2
    exit 2
    ;;
esac
