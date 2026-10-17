#!/bin/sh
# Xcode build phases for the prepared libmpv runtime (LINEUP_MPV_RUNTIME, set
# in Runner/Configs/NativePlayer.xcconfig).
#
#   mpv_runtime.sh check   fail early with a clear message when it is missing
#   mpv_runtime.sh embed   copy its dylibs into Contents/Frameworks and sign
#                          them with the app's signing identity, and install
#                          its license/patch/provenance resources
set -eu

runtime="${LINEUP_MPV_RUNTIME:-}"
manifest_name='.lineup-mpv-runtime-manifest'
pending_manifest_name='.lineup-mpv-runtime-pending'
resource_name='LineupNativeRuntime'
resource_backup_name='.lineup-native-runtime-previous'

check() {
  if [ -z "$runtime" ] || [ ! -f "$runtime/include/mpv/client.h" ] ||
    [ ! -f "$runtime/lib/libmpv.2.dylib" ]; then
    echo "error: The libmpv runtime was not found at LINEUP_MPV_RUNTIME='$runtime'." >&2
    echo "error: Build or provision the macOS runtime (lib/ and include/mpv/), or point LINEUP_MPV_RUNTIME at one through the environment or Runner/Configs/NativePlayer.local.xcconfig. See docs/DEVELOPMENT.md." >&2
    exit 1
  fi
  check_resources
}

fail() {
  echo "error: $*" >&2
  exit 1
}

validate_resource_tree() {
  tree=$1
  [ -d "$tree" ] && [ ! -L "$tree" ] ||
    fail "The native runtime resource tree must be a real directory: $tree"
  invalid=$(find "$tree" ! -type d ! -type f -print) ||
    fail "Could not inspect native runtime resources: $tree"
  [ -z "$invalid" ] ||
    fail "Native runtime resources contain symlinks or special files: $tree"
}

check_resources() {
  validate_resource_tree "$runtime/licenses"
  validate_resource_tree "$runtime/patches"
  # Required files of the current prepared-runtime format. S2's builder owns
  # license classification, generated-notice coverage, and GPL verification.
  # Copy all additional files too; this is a presence check, not a legal audit.
  for required in \
    BUILD-INFO.txt \
    licenses/NOTICES-SUMMARY.txt \
    licenses/cereal/LICENSE \
    licenses/curl/COPYING \
    licenses/curl/NOTICES.txt \
    licenses/curl/inet_ntop-ISC.txt \
    licenses/curl/inet_pton-ISC.txt \
    licenses/dav1d/COPYING \
    licenses/dav1d/NOTICES.txt \
    licenses/fast_float/LICENSE-APACHE \
    licenses/fast_float/LICENSE-BOOST \
    licenses/fast_float/LICENSE-MIT \
    licenses/ffmpeg/COPYING.LGPLv2.1 \
    licenses/ffmpeg/IJG-NOTICE.txt \
    licenses/ffmpeg/LICENSE.md \
    licenses/ffmpeg/NOTICES.txt \
    licenses/freetype/BDF-README \
    licenses/freetype/FTL.TXT \
    licenses/freetype/LICENSE.TXT \
    licenses/freetype/NOTICES.txt \
    licenses/freetype/PCF-README \
    licenses/freetype/fthash-NOTICE.txt \
    licenses/fribidi/COPYING \
    licenses/fribidi/NOTICES.txt \
    licenses/glslang/LICENSE.txt \
    licenses/glslang/NOTICES.txt \
    licenses/harfbuzz/COPYING \
    licenses/harfbuzz/NOTICES.txt \
    licenses/harfbuzz/ms-use-COPYING \
    licenses/lcms2/LICENSE \
    licenses/lcms2/NOTICES.txt \
    licenses/libass/COPYING \
    licenses/libass/NOTICES.txt \
    licenses/libplacebo/LICENSE \
    licenses/libplacebo/NOTICES.txt \
    licenses/moltenvk/LICENSE \
    licenses/moltenvk/NOTICES.txt \
    licenses/mpv/Copyright \
    licenses/mpv/LICENSE.LGPL \
    licenses/mpv/NOTICES.txt \
    licenses/openssl/LICENSE.txt \
    licenses/openssl/NOTICES.txt \
    licenses/spirv-cross/Apache-2.0.txt \
    licenses/spirv-cross/LICENSE \
    licenses/spirv-cross/MIT.txt \
    licenses/spirv-headers/LICENSE \
    licenses/spirv-tools/LICENSE \
    licenses/vulkan-headers/Apache-2.0.txt \
    licenses/vulkan-headers/LICENSE.md \
    licenses/vulkan-headers/MIT.txt \
    patches/ffmpeg/0001-aarch64-do-not-build-GPL-licensed-AC-3-DSP-code.patch \
    patches/ffmpeg/0002-aarch64-do-not-build-GPL-licensed-CRC-assembly.patch \
    patches/mpv/0001-vulkan-mac-embed-into-host-CAMetalLayer-via-wid.patch; do
    [ -f "$runtime/$required" ] && [ ! -L "$runtime/$required" ] &&
      [ -s "$runtime/$required" ] ||
      fail "Missing or empty native runtime license/provenance input: $runtime/$required"
  done
}

# Build products may live below a symlinked system temporary directory, but
# nothing inside TARGET_BUILD_DIR may redirect the bundle destination outside it.
validate_bundle_path() {
  relative=$1
  current=$TARGET_BUILD_DIR
  [ -d "$current" ] || fail "The target build directory is unavailable: $current"
  while [ -n "$relative" ]; do
    case "$relative" in
      */*) component=${relative%%/*}; relative=${relative#*/} ;;
      *) component=$relative; relative='' ;;
    esac
    case "$component" in
      ''|.|..) fail "Invalid app bundle directory component: $component" ;;
    esac
    current="$current/$component"
    [ ! -L "$current" ] || fail "An app bundle directory must not be a symlink: $current"
    if [ -e "$current" ]; then
      [ -d "$current" ] || fail "An app bundle directory is not a directory: $current"
    fi
  done
}

prepare_resource_destination() {
  resource_destination="$resources_destination/$resource_name"
  resource_backup="$resources_destination/$resource_backup_name"
  for tree in "$resource_destination" "$resource_backup"; do
    if [ -e "$tree" ] || [ -L "$tree" ]; then
      validate_resource_tree "$tree"
    fi
  done
  # Recover an interrupted rename before staging the next complete tree. If a
  # new tree was already installed, only its obsolete backup remains to clean.
  if [ -d "$resource_backup" ]; then
    if [ -d "$resource_destination" ]; then
      rm -rf "$resource_backup"
    else
      resource_rollback_needed=1
      mv -f "$resource_backup" "$resource_destination"
      resource_rollback_needed=0
    fi
  fi
}

stage_resources() {
  # A killed build may leave an unpublished stage. These reserved directories
  # are owned by this phase and must not become stale signed app resources.
  for abandoned in "$resources_destination"/.lineup-native-runtime-stage.*; do
    if [ -e "$abandoned" ] || [ -L "$abandoned" ]; then
      validate_resource_tree "$abandoned"
      find "$abandoned" -type d -exec chmod u+w '{}' +
      rm -rf "$abandoned"
    fi
  done
  resource_stage=$(mktemp -d "$resources_destination/.lineup-native-runtime-stage.XXXXXX")
  cp -RP "$runtime/licenses" "$resource_stage/licenses"
  cp -RP "$runtime/patches" "$resource_stage/patches"
  cp -P "$runtime/BUILD-INFO.txt" "$resource_stage/BUILD-INFO.txt"
  validate_resource_tree "$resource_stage"
  # A tool reporting success must still have copied the entire selected input.
  diff -qr "$runtime/licenses" "$resource_stage/licenses" >/dev/null ||
    fail "The staged native runtime licenses differ from their source."
  diff -qr "$runtime/patches" "$resource_stage/patches" >/dev/null ||
    fail "The staged native runtime patches differ from their source."
  cmp -s "$runtime/BUILD-INFO.txt" "$resource_stage/BUILD-INFO.txt" ||
    fail "The staged native runtime provenance differs from its source."
  # mktemp's private root and source permission bits must not make bundled
  # public license texts unreadable to another user installing/running the app.
  find "$resource_stage" -type d -exec chmod 755 '{}' +
  find "$resource_stage" -type f -exec chmod 644 '{}' +
}

publish_resources() {
  if [ -d "$resource_destination" ]; then
    mv -f "$resource_destination" "$resource_backup"
    resource_rollback_needed=1
  fi
  mv -f "$resource_stage" "$resource_destination"
  resource_stage=''
  resource_rollback_needed=0
  if [ -d "$resource_backup" ]; then
    rm -rf "$resource_backup"
  fi
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
resource_stage=''
resource_backup=''
resource_destination=''
resource_rollback_needed=0
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
  # A failed publication keeps the old complete tree. If rollback itself is
  # interrupted/fails, retain the backup for prepare_resource_destination.
  if [ "${resource_rollback_needed:-0}" -eq 1 ] &&
    [ -n "${resource_backup:-}" ] && [ -d "$resource_backup" ] && [ ! -L "$resource_backup" ] &&
    [ ! -e "$resource_destination" ] && [ ! -L "$resource_destination" ]; then
    mv -f "$resource_backup" "$resource_destination" ||
      echo "error: Native runtime resource rollback failed; retry embedding to recover the retained backup." >&2
  fi
  if [ -n "${resource_stage:-}" ] && [ -d "$resource_stage" ]; then
    find "$resource_stage" -type d -exec chmod u+w '{}' + || :
    rm -rf "$resource_stage" || :
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
  case "$FRAMEWORKS_FOLDER_PATH" in
    *.app/Contents/Frameworks) ;;
    *) fail "The Frameworks destination must be inside an app's Contents directory." ;;
  esac
  validate_bundle_path "$FRAMEWORKS_FOLDER_PATH"
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

  bundle_contents=$(dirname "$destination")
  resources_folder_path="${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}"
  if [ -n "$resources_folder_path" ]; then
    case "$resources_folder_path" in
      /*) resources_destination="$resources_folder_path" ;;
      *) resources_destination="$TARGET_BUILD_DIR/$resources_folder_path" ;;
    esac
  else
    resources_destination="$bundle_contents/Resources"
  fi
  case "$resources_destination" in
    "$bundle_contents/Resources") ;;
    *) fail "The app resources destination is not the bundle Resources directory: $resources_destination" ;;
  esac
  [ ! -L "$resources_destination" ] ||
    fail "The app Resources destination must not be a symlink: $resources_destination"
  validate_bundle_path "$(dirname "$FRAMEWORKS_FOLDER_PATH")/Resources"
  mkdir -p "$resources_destination"
  prepare_resource_destination
  stage_resources

  manifest="$resources_destination/$manifest_name"
  pending_manifest="$resources_destination/$pending_manifest_name"
  legacy_manifest="$destination/$manifest_name"
  legacy_pending_manifest="$destination/$pending_manifest_name"
  read_manifest "$manifest"
  active_manifest_exists=$read_exists
  previous_entries=$read_entries
  read_manifest "$legacy_manifest"
  legacy_manifest_exists=$read_exists
  for entry in $read_entries; do
    if ! list_contains "$entry" "$previous_entries"; then
      previous_entries="${previous_entries}${entry} "
    fi
  done
  manifest_exists=0
  if [ "$active_manifest_exists" -eq 1 ] || [ "$legacy_manifest_exists" -eq 1 ]; then
    manifest_exists=1
  fi
  read_manifest "$pending_manifest"
  pending_entries=$read_entries
  active_pending_exists=$read_exists
  read_manifest "$legacy_pending_manifest"
  legacy_pending_exists=$read_exists
  for entry in $read_entries; do
    if ! list_contains "$entry" "$pending_entries"; then
      pending_entries="${pending_entries}${entry} "
    fi
  done
  pending_exists=0
  if [ "$active_pending_exists" -eq 1 ] || [ "$legacy_pending_exists" -eq 1 ]; then
    pending_exists=1
  fi

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
  rm -f "$legacy_manifest" "$legacy_pending_manifest"
  publish_resources
}

case "${1:-}" in
  check) check ;;
  embed) embed ;;
  *)
    echo "usage: $0 check|embed" >&2
    exit 2
    ;;
esac
