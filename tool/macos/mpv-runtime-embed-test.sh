#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
embed_script="$repo_root/macos/Runner/Scripts/mpv_runtime.sh"
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

make_runtime_one() {
  runtime_path=$1
  mkdir -p "$runtime_path/include/mpv" "$runtime_path/lib"
  printf '%s\n' '/* fixture mpv header */' > "$runtime_path/include/mpv/client.h"
  make_library "$runtime_path/lib/libmpv.2.dylib" 'runtime-one mpv'
  make_library "$runtime_path/lib/libavutil.61.dylib" 'runtime-one avutil'
  make_library "$runtime_path/lib/libMoltenVK.dylib" 'runtime-one MoltenVK'
  make_library "$runtime_path/lib/libremoved.1.dylib" 'runtime-one removed later'
}

make_runtime_two() {
  runtime_path=$1
  mkdir -p "$runtime_path/include/mpv" "$runtime_path/lib"
  printf '%s\n' '/* fixture mpv header */' > "$runtime_path/include/mpv/client.h"
  make_library "$runtime_path/lib/libmpv.2.dylib" 'runtime-two mpv'
  make_library "$runtime_path/lib/libavutil.62.dylib" 'runtime-two avutil replacement'
  make_library "$runtime_path/lib/libMoltenVK.dylib" 'runtime-two MoltenVK'
  make_library "$runtime_path/lib/libadded.1.dylib" 'runtime-two added component'
}

make_runtime_three() {
  runtime_path=$1
  mkdir -p "$runtime_path/include/mpv" "$runtime_path/lib"
  printf '%s\n' '/* fixture mpv header */' > "$runtime_path/include/mpv/client.h"
  make_library "$runtime_path/lib/libmpv.2.dylib" 'runtime-three mpv'
  make_library "$runtime_path/lib/libavutil.63.dylib" 'runtime-three avutil replacement'
  make_library "$runtime_path/lib/libMoltenVK.dylib" 'runtime-three MoltenVK'
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

mkdir -p "$frameworks" "$fake_bin"
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
if [ -n "${FAKE_MV_FAIL_NAME:-}" ] &&
  [ "$(basename "$source_path")" = "$FAKE_MV_FAIL_NAME" ]; then
  exit 47
fi
exec /bin/mv "$@"
FAKE_MV
chmod +x "$fake_bin/mv"

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

echo 'mpv runtime embedding integration test passed'
