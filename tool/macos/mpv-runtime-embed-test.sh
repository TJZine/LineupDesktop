#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
embed_script="$repo_root/macos/Runner/Scripts/mpv_runtime.sh"
accepted_runtime="${LINEUP_MPV_RUNTIME:-}"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/lineup-mpv-embed-test.XXXXXX")
app="$test_root/Lineup Desktop.app"
frameworks="$app/Contents/Frameworks"
resources="$app/Contents/Resources"
runtime_one="$test_root/runtime-one"
runtime_two="$test_root/runtime-two"
runtime_three="$test_root/runtime-three"
fake_bin="$test_root/bin"
codesign_log="$test_root/codesign.log"
manifest_name='.lineup-mpv-runtime-manifest'
pending_manifest_name='.lineup-mpv-runtime-pending'
owned_resources="$resources/LineupNativeRuntime"
resource_backup="$resources/.lineup-native-runtime-previous"
manifest="$resources/.lineup-mpv-runtime-manifest"
pending_manifest="$resources/.lineup-mpv-runtime-pending"
legacy_manifest="$frameworks/.lineup-mpv-runtime-manifest"
legacy_pending_manifest="$frameworks/.lineup-mpv-runtime-pending"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "Expected file: $1"
}

assert_missing() {
  [ ! -e "$1" ] && [ ! -L "$1" ] || fail "Expected path to be absent: $1"
}

assert_content() {
  assert_file "$1"
  actual=$(cat "$1")
  [ "$actual" = "$2" ] || fail "Unexpected content in $1: '$actual'"
}

assert_manifest_entry() {
  grep -F -x -- "$1" "$manifest" >/dev/null ||
    fail "Manifest is missing '$1'."
}

assert_pending_entry() {
  grep -F -x -- "$1" "$pending_manifest" >/dev/null ||
    fail "Pending manifest is missing '$1'."
}

assert_manifest_count() {
  actual=$(wc -l < "$manifest" | tr -d '[:space:]')
  [ "$actual" = "$1" ] || fail "Manifest has $actual entries; expected $1."
}

make_library() {
  printf '%s\n' "$2" > "$1"
}

make_resource_fixture() {
  fixture_runtime=$1
  fixture_label=$2
  for fixture_file in \
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
    mkdir -p "$fixture_runtime/$(dirname "$fixture_file")"
    printf '%s\n%s\n' "$fixture_label" "$fixture_file" > "$fixture_runtime/$fixture_file"
  done
  mkdir -p "$fixture_runtime/licenses/empty directory"
}

assert_resource_tree() {
  source_resources=$1
  embedded_resources=$2
  diff -qr "$source_resources/licenses" "$embedded_resources/licenses" >/dev/null ||
    fail 'Embedded license file set, directory hierarchy, or bytes differ.'
  diff -qr "$source_resources/patches" "$embedded_resources/patches" >/dev/null ||
    fail 'Embedded patch file set, directory hierarchy, or bytes differ.'
  cmp -s "$source_resources/BUILD-INFO.txt" "$embedded_resources/BUILD-INFO.txt" ||
    fail 'Embedded raw runtime provenance differs.'
  top_entries=$(find "$embedded_resources" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d '[:space:]')
  [ "$top_entries" = 3 ] || fail 'The owned resource tree contains unexpected files/dylibs.'
  bad_modes=$(find "$embedded_resources" \( -type d ! -perm 0755 \) -o \( -type f ! -perm 0644 \))
  [ -z "$bad_modes" ] || fail 'Bundled resource permissions are not readable across users.'
}

assert_no_resource_stage() {
  for abandoned in "$resources"/.lineup-native-runtime-stage.*; do
    [ ! -e "$abandoned" ] || fail 'A failed embed left a resource stage in the app.'
  done
}

make_runtime_one() {
  runtime_path=$1
  mkdir -p "$runtime_path/include/mpv" "$runtime_path/lib"
  printf '%s\n' '/* fixture mpv header */' > "$runtime_path/include/mpv/client.h"
  make_library "$runtime_path/lib/libmpv.2.dylib" 'runtime-one mpv'
  make_library "$runtime_path/lib/libavutil.61.dylib" 'runtime-one avutil'
  make_library "$runtime_path/lib/libMoltenVK.dylib" 'runtime-one MoltenVK'
  make_library "$runtime_path/lib/libremoved.1.dylib" 'runtime-one removed later'
  make_resource_fixture "$runtime_path" 'runtime-one resources'
  make_library "$runtime_path/licenses/removed-notice.txt" 'old optional notice'
}

make_runtime_two() {
  runtime_path=$1
  mkdir -p "$runtime_path/include/mpv" "$runtime_path/lib"
  printf '%s\n' '/* fixture mpv header */' > "$runtime_path/include/mpv/client.h"
  make_library "$runtime_path/lib/libmpv.2.dylib" 'runtime-two mpv'
  make_library "$runtime_path/lib/libavutil.62.dylib" 'runtime-two avutil replacement'
  make_library "$runtime_path/lib/libMoltenVK.dylib" 'runtime-two MoltenVK'
  make_library "$runtime_path/lib/libadded.1.dylib" 'runtime-two added component'
  make_resource_fixture "$runtime_path" 'runtime-two resources'
  mkdir -p "$runtime_path/licenses/extra notices"
  make_library "$runtime_path/licenses/extra notices/added.txt" 'new optional notice'
}

make_runtime_three() {
  runtime_path=$1
  mkdir -p "$runtime_path/include/mpv" "$runtime_path/lib"
  printf '%s\n' '/* fixture mpv header */' > "$runtime_path/include/mpv/client.h"
  make_library "$runtime_path/lib/libmpv.2.dylib" 'runtime-three mpv'
  make_library "$runtime_path/lib/libavutil.63.dylib" 'runtime-three avutil replacement'
  make_library "$runtime_path/lib/libMoltenVK.dylib" 'runtime-three MoltenVK'
  make_resource_fixture "$runtime_path" 'runtime-three resources'
}

run_embed() {
  LINEUP_MPV_RUNTIME=$1 \
    TARGET_BUILD_DIR="$test_root" \
    FRAMEWORKS_FOLDER_PATH='Lineup Desktop.app/Contents/Frameworks' \
    UNLOCALIZED_RESOURCES_FOLDER_PATH='Lineup Desktop.app/Contents/Resources' \
    LC_ALL=C \
    PATH="$fake_bin:$PATH" \
    CODESIGN_LOG="$codesign_log" \
    "$embed_script" embed
}

mkdir -p "$frameworks" "$resources" "$fake_bin"
make_library "$resources/unrelated-resource.txt" 'unrelated resource'
cat > "$fake_bin/codesign" <<'FAKE_CODESIGN'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$CODESIGN_LOG"
if [ "${FAKE_CODESIGN_FAIL:-NO}" = YES ]; then
  exit 23
fi
FAKE_CODESIGN
chmod +x "$fake_bin/codesign"
cat > "$fake_bin/mv" <<'FAKE_MV'
#!/bin/sh
set -eu
if [ "${1:-}" = '-f' ]; then
  source_path=${2:-}
else
  source_path=${1:-}
fi
case "$(basename "$source_path")" in
  .lineup-native-runtime-stage.*)
    if [ "${FAKE_RESOURCE_PUBLISH_FAIL:-NO}" = YES ]; then exit 49; fi ;;
  .lineup-native-runtime-previous)
    if [ "${FAKE_RESOURCE_ROLLBACK_FAIL:-NO}" = YES ]; then exit 50; fi ;;
esac
if [ -n "${FAKE_MV_FAIL_NAME:-}" ] &&
  [ "$(basename "$source_path")" = "$FAKE_MV_FAIL_NAME" ]; then
  exit 47
fi
exec /bin/mv "$@"
FAKE_MV
chmod +x "$fake_bin/mv"
cat > "$fake_bin/cp" <<'FAKE_CP'
#!/bin/sh
set -eu
for argument do destination_path=$argument; done
/bin/cp "$@"
case "$destination_path" in
  */.lineup-native-runtime-stage.*/licenses)
    if [ "${FAKE_RESOURCE_COPY_FAIL:-NO}" = YES ]; then exit 48; fi
    if [ "${FAKE_RESOURCE_COPY_TRUNCATE:-NO}" = YES ]; then
      : > "$destination_path/mpv/NOTICES.txt"
    fi ;;
esac
FAKE_CP
chmod +x "$fake_bin/cp"

if LINEUP_MPV_RUNTIME="$test_root/missing-runtime" "$embed_script" check 2>/dev/null; then
  fail 'A missing runtime unexpectedly passed the early check.'
fi

make_runtime_one "$runtime_one"
make_runtime_two "$runtime_two"
make_runtime_three "$runtime_three"

# This is a pre-manifest bundle. It includes current names with old contents,
# numeric aliases that migration may remove, and unrelated bundle contents.
make_library "$frameworks/libmpv.2.dylib" 'old mpv contents'
make_library "$frameworks/libavutil.61.dylib" 'old avutil contents'
make_library "$frameworks/libMoltenVK.dylib" 'old MoltenVK contents'
make_library "$frameworks/libmpv.1.dylib" 'old mpv alias'
make_library "$frameworks/libavutil.61.1.102.dylib" 'old avutil alias'
make_library "$frameworks/libMoltenVK.0.dylib" 'old MoltenVK alias'
make_library "$frameworks/libunrelated.dylib" 'unrelated dylib'
make_library "$frameworks/libunrelated.7.dylib" 'unrelated numeric dylib'
make_library "$frameworks/libfoo-bar.1.dylib" 'unrelated hyphenated dylib'
mkdir -p "$frameworks/Unrelated.framework/Versions/A"
make_library "$frameworks/Unrelated.framework/Versions/A/Unrelated" 'unrelated framework'
make_library "$frameworks/plugin.bundle" 'unrelated plugin file'

unset CODE_SIGNING_ALLOWED ENABLE_HARDENED_RUNTIME EXPANDED_CODE_SIGN_IDENTITY FAKE_CODESIGN_FAIL
ENABLE_HARDENED_RUNTIME=YES run_embed "$runtime_one"

assert_content "$frameworks/libmpv.2.dylib" 'runtime-one mpv'
assert_content "$frameworks/libavutil.61.dylib" 'runtime-one avutil'
assert_content "$frameworks/libMoltenVK.dylib" 'runtime-one MoltenVK'
assert_content "$frameworks/libremoved.1.dylib" 'runtime-one removed later'
assert_resource_tree "$runtime_one" "$owned_resources"
assert_content "$resources/unrelated-resource.txt" 'unrelated resource'
assert_missing "$frameworks/libmpv.1.dylib"
assert_missing "$frameworks/libavutil.61.1.102.dylib"
assert_missing "$frameworks/libMoltenVK.0.dylib"
assert_content "$frameworks/libunrelated.dylib" 'unrelated dylib'
assert_content "$frameworks/libunrelated.7.dylib" 'unrelated numeric dylib'
assert_content "$frameworks/libfoo-bar.1.dylib" 'unrelated hyphenated dylib'
assert_content "$frameworks/Unrelated.framework/Versions/A/Unrelated" 'unrelated framework'
assert_content "$frameworks/plugin.bundle" 'unrelated plugin file'
assert_file "$manifest"
assert_manifest_count 4
assert_manifest_entry 'libmpv.2.dylib'
assert_manifest_entry 'libavutil.61.dylib'
assert_manifest_entry 'libMoltenVK.dylib'
assert_manifest_entry 'libremoved.1.dylib'
if grep -E '[/[:space:]]' "$manifest" >/dev/null; then
  fail 'Manifest contains a path or whitespace.'
fi
sign_count=$(wc -l < "$codesign_log" | tr -d '[:space:]')
[ "$sign_count" = 4 ] || fail "Expected four ad hoc signing calls; got $sign_count."
grep -F -- '--sign - --options runtime --timestamp=none' "$codesign_log" >/dev/null ||
  fail 'Ad hoc hardened signing did not use --timestamp=none and --options runtime.'

# A valid pre-Resources manifest pair is migrated only after the active
# Resources manifest has been published successfully.
printf '%s\n' libmpv.2.dylib libavutil.61.dylib libMoltenVK.dylib libremoved.1.dylib > "$legacy_manifest"
printf '%s\n' libmpv.2.dylib libavutil.61.dylib libMoltenVK.dylib libremoved.1.dylib > "$legacy_pending_manifest"
CODE_SIGNING_ALLOWED=NO run_embed "$runtime_one"
assert_missing "$legacy_manifest"
assert_missing "$legacy_pending_manifest"
assert_file "$manifest"
assert_missing "$pending_manifest"

# A later runtime adds a component and renames another. A signing failure must
# leave the completed A state untouched, with no B orphan for a later C retry.
cp "$manifest" "$test_root/manifest-a"
: > "$codesign_log"
if CODE_SIGNING_ALLOWED=YES EXPANDED_CODE_SIGN_IDENTITY=TEAMID \
  FAKE_CODESIGN_FAIL=YES run_embed "$runtime_two"; then
  fail 'A staged codesign failure unexpectedly returned success.'
fi
unset FAKE_CODESIGN_FAIL
cmp -s "$test_root/manifest-a" "$manifest" ||
  fail 'Completed manifest advanced after a staged signing failure.'
assert_missing "$pending_manifest"
assert_content "$frameworks/libavutil.61.dylib" 'runtime-one avutil'
assert_missing "$frameworks/libavutil.62.dylib"
assert_missing "$frameworks/libadded.1.dylib"
assert_content "$frameworks/libunrelated.7.dylib" 'unrelated numeric dylib'

# B publishes its new names, then fails on the final current name. C must use
# the pending ownership record to remove both B-only files before completing.
: > "$codesign_log"
if CODE_SIGNING_ALLOWED=NO FAKE_MV_FAIL_NAME=libmpv.2.dylib \
  run_embed "$runtime_two"; then
  fail 'A partial final-install failure unexpectedly returned success.'
fi
unset FAKE_MV_FAIL_NAME
cmp -s "$test_root/manifest-a" "$manifest" ||
  fail 'Completed manifest advanced after a partial final-install failure.'
assert_file "$pending_manifest"
assert_pending_entry 'libadded.1.dylib'
assert_pending_entry 'libavutil.62.dylib'
assert_pending_entry 'libmpv.2.dylib'
assert_content "$frameworks/libadded.1.dylib" 'runtime-two added component'
assert_content "$frameworks/libavutil.62.dylib" 'runtime-two avutil replacement'

# C recovers directly from A. The changed B component and superseded version
# must not survive, while current C files and unrelated contents do.
: > "$codesign_log"
CODE_SIGNING_ALLOWED=YES EXPANDED_CODE_SIGN_IDENTITY=TEAMID \
  ENABLE_HARDENED_RUNTIME=NO run_embed "$runtime_three"
assert_missing "$frameworks/libavutil.61.dylib"
assert_missing "$frameworks/libremoved.1.dylib"
assert_missing "$frameworks/libavutil.62.dylib"
assert_missing "$frameworks/libadded.1.dylib"
assert_content "$frameworks/libmpv.2.dylib" 'runtime-three mpv'
assert_content "$frameworks/libMoltenVK.dylib" 'runtime-three MoltenVK'
assert_content "$frameworks/libavutil.63.dylib" 'runtime-three avutil replacement'
assert_content "$frameworks/libunrelated.7.dylib" 'unrelated numeric dylib'
assert_content "$frameworks/libfoo-bar.1.dylib" 'unrelated hyphenated dylib'
assert_manifest_count 3
assert_manifest_entry 'libavutil.63.dylib'
assert_missing "$pending_manifest"
sign_count=$(wc -l < "$codesign_log" | tr -d '[:space:]')
[ "$sign_count" = 3 ] || fail "Expected three C signing calls; got $sign_count."
grep -F -- '--sign TEAMID --timestamp ' "$codesign_log" >/dev/null ||
  fail 'Real-identity signing did not request a secure timestamp.'
if grep -F -- '--timestamp=none' "$codesign_log" >/dev/null; then
  fail 'Real-identity signing incorrectly disabled the timestamp.'
fi

# B is also used to prove the no-signing path and the manifest cleanup of C.
: > "$codesign_log"
CODE_SIGNING_ALLOWED=YES EXPANDED_CODE_SIGN_IDENTITY=TEAMID \
  ENABLE_HARDENED_RUNTIME=NO run_embed "$runtime_two"
assert_missing "$frameworks/libavutil.63.dylib"
assert_content "$frameworks/libavutil.62.dylib" 'runtime-two avutil replacement'
assert_content "$frameworks/libadded.1.dylib" 'runtime-two added component'
assert_manifest_count 4
assert_missing "$pending_manifest"
sign_count=$(wc -l < "$codesign_log" | tr -d '[:space:]')
[ "$sign_count" = 4 ] || fail "Expected four B signing calls; got $sign_count."
grep -F -- '--sign TEAMID --timestamp ' "$codesign_log" >/dev/null ||
  fail 'B real-identity signing did not request a secure timestamp.'

# CODE_SIGNING_ALLOWED=NO must retain the copy/manifest behavior without
# invoking codesign at all.
: > "$codesign_log"
CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"
[ ! -s "$codesign_log" ] || fail 'codesign ran while CODE_SIGNING_ALLOWED=NO.'

# Current-name symlinks are unlinked before final moves; real directories are
# rejected before any final move. Both cases must not write outside Frameworks.
outside_sentinel="$test_root/outside-sentinel"
make_library "$outside_sentinel" 'outside sentinel'
outside_directory="$test_root/outside-directory"
mkdir -p "$outside_directory"
make_library "$outside_directory/sentinel" 'outside directory sentinel'
rm -f "$frameworks/libmpv.2.dylib"
ln -s "$outside_directory" "$frameworks/libmpv.2.dylib"
CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"
assert_content "$frameworks/libmpv.2.dylib" 'runtime-two mpv'
[ ! -L "$frameworks/libmpv.2.dylib" ] || fail 'Directory symlink was retained.'
assert_content "$outside_directory/sentinel" 'outside directory sentinel'
assert_missing "$outside_directory/libmpv.2.dylib"

rm -f "$frameworks/libmpv.2.dylib"
mkdir "$frameworks/libmpv.2.dylib"
cp "$manifest" "$test_root/manifest-before-directory"
if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"; then
  fail 'A current-name directory was accepted as a dylib destination.'
fi
cmp -s "$test_root/manifest-before-directory" "$manifest" ||
  fail 'Completed manifest advanced after the directory rejection.'
[ -f "$pending_manifest" ] || fail 'Directory rejection lost pending ownership.'
[ -d "$frameworks/libmpv.2.dylib" ] || fail 'Current-name directory was removed.'
assert_content "$outside_sentinel" 'outside sentinel'
assert_missing "$outside_directory/libmpv.2.dylib"
rmdir "$frameworks/libmpv.2.dylib"
CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"

outside_file="$test_root/outside-file"
make_library "$outside_file" 'outside file'
rm -f "$frameworks/libmpv.2.dylib"
ln -s "$outside_file" "$frameworks/libmpv.2.dylib"
CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"
assert_content "$frameworks/libmpv.2.dylib" 'runtime-two mpv'
[ ! -L "$frameworks/libmpv.2.dylib" ] || fail 'File symlink was retained.'
assert_content "$outside_file" 'outside file'

# Manifest entries are validated before any cleanup or copy. Exercise absolute,
# parent, nested, and symlink inputs while protecting an outside sentinel.
make_library "$frameworks/libstale.1.dylib" 'must remain after invalid manifest'
for invalid_entry in '/outside-sentinel' '../outside-sentinel' 'nested/libstale.1.dylib'; do
  printf '%s\n' "$invalid_entry" > "$manifest"
  if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"; then
    fail "Invalid manifest entry was accepted: $invalid_entry"
  fi
  assert_content "$outside_sentinel" 'outside sentinel'
  assert_content "$frameworks/libstale.1.dylib" 'must remain after invalid manifest'
done
rm -f "$manifest"
ln -s "$outside_sentinel" "$manifest"
if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"; then
  fail 'A symlinked completed manifest was accepted.'
fi
assert_content "$outside_sentinel" 'outside sentinel'
assert_content "$frameworks/libstale.1.dylib" 'must remain after invalid manifest'
rm -f "$manifest"
CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"

for invalid_entry in '/outside-sentinel' '../outside-sentinel' 'nested/libstale.1.dylib'; do
  printf '%s\n' "$invalid_entry" > "$pending_manifest"
  if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"; then
    fail "Invalid pending manifest entry was accepted: $invalid_entry"
  fi
  assert_content "$outside_sentinel" 'outside sentinel'
  assert_content "$frameworks/libstale.1.dylib" 'must remain after invalid manifest'
  rm -f "$pending_manifest"
done
ln -s "$outside_sentinel" "$pending_manifest"
if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"; then
  fail 'A symlinked pending manifest was accepted.'
fi
assert_content "$outside_sentinel" 'outside sentinel'
rm -f "$pending_manifest"

printf '%s\n' '../outside-sentinel' > "$legacy_manifest"
if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"; then
  fail 'An invalid legacy completed manifest was accepted.'
fi
assert_content "$outside_sentinel" 'outside sentinel'
rm -f "$legacy_manifest"
ln -s "$outside_sentinel" "$legacy_pending_manifest"
if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"; then
  fail 'A symlinked legacy pending manifest was accepted.'
fi
assert_content "$outside_sentinel" 'outside sentinel'
rm -f "$legacy_pending_manifest"

# Resource A->B replacement must remove stale files, copy optional/nested
# files and empty directories, and preserve unrelated resource/framework siblings.
CODE_SIGNING_ALLOWED=NO run_embed "$runtime_one"
assert_resource_tree "$runtime_one" "$owned_resources"
CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"
assert_resource_tree "$runtime_two" "$owned_resources"
assert_missing "$owned_resources/licenses/removed-notice.txt"
assert_content "$owned_resources/licenses/extra notices/added.txt" 'new optional notice'
assert_content "$resources/unrelated-resource.txt" 'unrelated resource'
assert_content "$frameworks/libunrelated.7.dylib" 'unrelated numeric dylib'

# Missing/empty essential inputs fail before changing the completed resources.
for missing in BUILD-INFO.txt licenses/NOTICES-SUMMARY.txt licenses/mpv/LICENSE.LGPL \
  licenses/mpv/NOTICES.txt patches/mpv/0001-vulkan-mac-embed-into-host-CAMetalLayer-via-wid.patch; do
  mv "$runtime_one/$missing" "$test_root/missing-input"
  if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_one"; then
    fail "A missing resource input was accepted: $missing"
  fi
  mv "$test_root/missing-input" "$runtime_one/$missing"
  assert_resource_tree "$runtime_two" "$owned_resources"
done
cp "$runtime_one/licenses/mpv/NOTICES.txt" "$test_root/notices-input"
: > "$runtime_one/licenses/mpv/NOTICES.txt"
if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_one"; then
  fail 'An empty required notice was accepted.'
fi
cp "$test_root/notices-input" "$runtime_one/licenses/mpv/NOTICES.txt"
assert_resource_tree "$runtime_two" "$owned_resources"

# Reject source links/special files, including optional files and whole trees.
ln -s "$outside_sentinel" "$runtime_one/licenses/escape-link"
if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_one"; then fail 'A source symlink was accepted.'; fi
rm "$runtime_one/licenses/escape-link"
mkfifo "$runtime_one/patches/special-file"
if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_one"; then fail 'A source FIFO was accepted.'; fi
rm "$runtime_one/patches/special-file"
mv "$runtime_one/licenses" "$runtime_one/licenses-real"
ln -s "$runtime_one/licenses-real" "$runtime_one/licenses"
if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_one"; then fail 'A linked source tree was accepted.'; fi
rm "$runtime_one/licenses"
mv "$runtime_one/licenses-real" "$runtime_one/licenses"
assert_content "$outside_sentinel" 'outside sentinel'
assert_resource_tree "$runtime_two" "$owned_resources"

# Copy failure and a false-success truncation both retain the old full tree.
for copy_failure in exit truncated; do
  if [ "$copy_failure" = exit ]; then
    if CODE_SIGNING_ALLOWED=NO FAKE_RESOURCE_COPY_FAIL=YES run_embed "$runtime_one"; then
      fail 'A controlled resource copy failure returned success.'
    fi
  else
    if CODE_SIGNING_ALLOWED=NO FAKE_RESOURCE_COPY_TRUNCATE=YES run_embed "$runtime_one"; then
      fail 'A silently truncated resource copy returned success.'
    fi
  fi
  unset FAKE_RESOURCE_COPY_FAIL FAKE_RESOURCE_COPY_TRUNCATE
  assert_resource_tree "$runtime_two" "$owned_resources"
  assert_no_resource_stage
done

# The old directory is rolled back if publication fails; retry installs A.
if CODE_SIGNING_ALLOWED=NO FAKE_RESOURCE_PUBLISH_FAIL=YES run_embed "$runtime_one"; then
  fail 'A controlled resource publication failure returned success.'
fi
unset FAKE_RESOURCE_PUBLISH_FAIL
assert_resource_tree "$runtime_two" "$owned_resources"
assert_missing "$resource_backup"
assert_no_resource_stage
CODE_SIGNING_ALLOWED=NO run_embed "$runtime_one"
assert_resource_tree "$runtime_one" "$owned_resources"

# If rollback itself is unavailable, keep the previous complete tree in the
# reserved backup; the next successful embed must recover and replace it.
if CODE_SIGNING_ALLOWED=NO FAKE_RESOURCE_PUBLISH_FAIL=YES FAKE_RESOURCE_ROLLBACK_FAIL=YES \
  run_embed "$runtime_two"; then fail 'A resource rollback failure returned success.'; fi
unset FAKE_RESOURCE_PUBLISH_FAIL FAKE_RESOURCE_ROLLBACK_FAIL
assert_missing "$owned_resources"
assert_resource_tree "$runtime_one" "$resource_backup"
assert_no_resource_stage
CODE_SIGNING_ALLOWED=NO run_embed "$runtime_one"
assert_resource_tree "$runtime_one" "$owned_resources"
assert_missing "$resource_backup"

# Recover both possible interrupted-publication states without stale notices.
mv "$owned_resources" "$resource_backup"
CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"
assert_resource_tree "$runtime_two" "$owned_resources"
assert_missing "$resource_backup"
cp -R "$owned_resources" "$resource_backup"
CODE_SIGNING_ALLOWED=NO run_embed "$runtime_one"
assert_resource_tree "$runtime_one" "$owned_resources"
assert_missing "$resource_backup"
mkdir "$resources/.lineup-native-runtime-stage.interrupted"
make_library "$resources/.lineup-native-runtime-stage.interrupted/partial-notice" 'abandoned stage'
CODE_SIGNING_ALLOWED=NO run_embed "$runtime_one"
assert_resource_tree "$runtime_one" "$owned_resources"
assert_no_resource_stage

# Refuse destination root/ancestor links or traversal before outside writes.
mv "$owned_resources" "$test_root/owned-resources-save"
ln -s "$outside_directory" "$owned_resources"
if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"; then fail 'A linked owned destination was accepted.'; fi
[ -L "$owned_resources" ] || fail 'Rejected owned-destination link was changed.'
rm "$owned_resources"
mv "$test_root/owned-resources-save" "$owned_resources"
ln -s "$outside_directory" "$resource_backup"
if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"; then fail 'A linked backup destination was accepted.'; fi
rm "$resource_backup"
mv "$resources" "$test_root/resources-save"
ln -s "$outside_directory" "$resources"
if CODE_SIGNING_ALLOWED=NO run_embed "$runtime_two"; then fail 'A linked Resources directory was accepted.'; fi
rm "$resources"
mv "$test_root/resources-save" "$resources"
ln -s "$outside_directory" "$test_root/Outside.app"
if LINEUP_MPV_RUNTIME="$runtime_two" TARGET_BUILD_DIR="$test_root" \
  FRAMEWORKS_FOLDER_PATH='Outside.app/Contents/Frameworks' CODE_SIGNING_ALLOWED=NO \
  "$embed_script" embed; then fail 'A linked app ancestor was accepted.'; fi
if LINEUP_MPV_RUNTIME="$runtime_two" TARGET_BUILD_DIR="$test_root" \
  FRAMEWORKS_FOLDER_PATH='../Outside.app/Contents/Frameworks' CODE_SIGNING_ALLOWED=NO \
  "$embed_script" embed; then fail 'A traversing bundle path was accepted.'; fi
if LINEUP_MPV_RUNTIME="$runtime_two" TARGET_BUILD_DIR="$test_root" \
  FRAMEWORKS_FOLDER_PATH='Lineup Desktop.app/Contents/Frameworks' \
  UNLOCALIZED_RESOURCES_FOLDER_PATH="$outside_directory" CODE_SIGNING_ALLOWED=NO \
  "$embed_script" embed; then fail 'An outside resource destination was accepted.'; fi
assert_content "$outside_directory/sentinel" 'outside directory sentinel'
assert_missing "$outside_directory/LineupNativeRuntime"
assert_missing "$outside_directory/Contents"
assert_resource_tree "$runtime_one" "$owned_resources"
assert_content "$resources/unrelated-resource.txt" 'unrelated resource'

# Use a real Mach-O app and dylib to prove that Resources bookkeeping does not
# invalidate an ad-hoc app signature, and that the old Frameworks location is
# the failure this test would catch.
command -v cc >/dev/null || fail 'A C compiler is required for Mach-O signing proof.'
[ -x /usr/bin/codesign ] || fail 'macOS codesign is required for signing proof.'
mach_root="$test_root/mach-app-root"
mach_app="$mach_root/Fixture.app"
mach_frameworks="$mach_app/Contents/Frameworks"
mach_resources="$mach_app/Contents/Resources"
mach_runtime="$test_root/mach-runtime"
mkdir -p "$mach_app/Contents/MacOS" "$mach_frameworks" "$mach_resources" \
  "$mach_runtime/include/mpv" "$mach_runtime/lib"
printf '%s\n' '/* fixture mpv header */' > "$mach_runtime/include/mpv/client.h"
make_resource_fixture "$mach_runtime" 'Mach-O runtime resources'
printf '%s\n' 'int lineup_fixture_value(void) { return 7; }' > "$test_root/mach-lib.c"
cc -dynamiclib -Wl,-install_name,@rpath/libmpv.2.dylib \
  -o "$mach_runtime/lib/libmpv.2.dylib" "$test_root/mach-lib.c"
printf '%s\n' 'int main(void) { return 0; }' > "$test_root/mach-main.c"
cc -o "$mach_app/Contents/MacOS/Fixture" "$test_root/mach-main.c"
cat > "$mach_app/Contents/Info.plist" <<'MACH_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.example.lineup-embed-fixture</string>
<key>CFBundleExecutable</key><string>Fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
MACH_PLIST
printf '%s\n' libmpv.2.dylib > "$mach_frameworks/$manifest_name"
printf '%s\n' libmpv.2.dylib > "$mach_frameworks/$pending_manifest_name"
if /usr/bin/codesign --force --sign - --timestamp=none "$mach_app" \
  > "$mach_root/legacy-codesign.log" 2>&1; then
  if /usr/bin/codesign --force --sign - --timestamp=none "$mach_frameworks" \
    >> "$mach_root/legacy-codesign.log" 2>&1; then
    fail 'Legacy Frameworks bookkeeping unexpectedly passed code signing.'
  fi
fi

LINEUP_MPV_RUNTIME="$mach_runtime" \
  TARGET_BUILD_DIR="$mach_root" \
  FRAMEWORKS_FOLDER_PATH='Fixture.app/Contents/Frameworks' \
  UNLOCALIZED_RESOURCES_FOLDER_PATH='Fixture.app/Contents/Resources' \
  CODE_SIGNING_ALLOWED=YES EXPANDED_CODE_SIGN_IDENTITY='' \
  ENABLE_HARDENED_RUNTIME=NO PATH='/usr/bin:/bin:/usr/sbin:/sbin' \
  "$embed_script" embed
assert_resource_tree "$mach_runtime" "$mach_resources/LineupNativeRuntime"
assert_file "$mach_resources/$manifest_name"
assert_missing "$mach_resources/$pending_manifest_name"
assert_missing "$mach_frameworks/$manifest_name"
assert_missing "$mach_frameworks/$pending_manifest_name"
/usr/bin/codesign --verify --verbose=2 "$mach_frameworks/libmpv.2.dylib" \
  > "$mach_root/dylib-codesign.log" 2>&1
/usr/bin/codesign --force --sign - --timestamp=none "$mach_app" \
  > "$mach_root/app-codesign.log" 2>&1
/usr/bin/codesign --verify --deep --strict "$mach_app" \
  > "$mach_root/app-verify.log" 2>&1

# When supplied, also embed/sign the immutable accepted prepared runtime into
# this isolated Mach-O app. No app/Xcode/Flutter build output is touched.
if [ -n "$accepted_runtime" ]; then
  (cd "$accepted_runtime" && find lib licenses patches -type f -exec shasum -a 256 '{}' \; &&
    shasum -a 256 BUILD-INFO.txt) > "$test_root/accepted-before.sha256"
  LINEUP_MPV_RUNTIME="$accepted_runtime" TARGET_BUILD_DIR="$mach_root" \
    FRAMEWORKS_FOLDER_PATH='Fixture.app/Contents/Frameworks' \
    UNLOCALIZED_RESOURCES_FOLDER_PATH='Fixture.app/Contents/Resources' \
    CODE_SIGNING_ALLOWED=YES EXPANDED_CODE_SIGN_IDENTITY='' ENABLE_HARDENED_RUNTIME=NO \
    PATH='/usr/bin:/bin:/usr/sbin:/sbin' "$embed_script" embed
  assert_resource_tree "$accepted_runtime" "$mach_resources/LineupNativeRuntime"
  (cd "$accepted_runtime" && shasum -a 256 -c "$test_root/accepted-before.sha256") \
    > "$test_root/accepted-after.log"
  /usr/bin/codesign --force --sign - --timestamp=none "$mach_app" \
    > "$mach_root/accepted-codesign.log" 2>&1
  /usr/bin/codesign --verify --deep --strict "$mach_app" \
    > "$mach_root/accepted-verify.log" 2>&1
  echo 'accepted runtime resources match byte-for-byte; source hashes unchanged; ad-hoc app signature verified'
fi

echo 'mpv runtime embedding integration test passed'
