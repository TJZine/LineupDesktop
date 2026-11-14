#!/usr/bin/env bash
# Run only in a fresh full checkout of the reviewed commit, with no signing access.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
if [[ $# -ne 2 || ! "$1" =~ ^[0-9a-f]{40}$ || ! "$2" =~ ^https://github.com/[^/]+/[^/]+/actions/runs/[0-9]+$ ]]; then
  echo 'Usage: tool/android/build-release.sh <full-reviewed-commit> <CI-run-URL>' >&2
  exit 2
fi
reviewed_commit="$1"
ci_run="$2"
check_source() {
  actual_commit="$(git rev-parse HEAD)"
  source_status="$(git status --porcelain --untracked-files=all)"
  if [[ "$actual_commit" != "$reviewed_commit" || -n "$source_status" ]]; then
    echo 'Release requires the full reviewed commit and a completely clean checkout, including untracked inputs.' >&2
    exit 1
  fi
}
check_source
if [[ "$(git rev-parse --is-shallow-repository)" != false ||
      "$(git config --bool core.sparseCheckout || true)" == true ]]; then
  echo 'Release requires a full, non-shallow, non-sparse checkout.' >&2
  exit 1
fi
if [[ -e build || -e android/.gradle || -e android/app/build ]]; then
  echo 'Release requires a fresh checkout without prior Android build outputs or project caches.' >&2
  exit 1
fi
python3 tool/android/check-wrapper.py
dart tool/check_toolchain.dart
# A release never reuses the developer/CI Gradle dependency or build cache.
scratch="$(mktemp -d "${TMPDIR:-/tmp}/lineup-android-release.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
export GRADLE_USER_HOME="$scratch/gradle"
export GRADLE_OPTS="-Dorg.gradle.daemon=false"
flutter_bin="$(command -v flutter)"
flutter_root="$(cd "$(dirname "$flutter_bin")/.." && pwd)"
sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
build_tools="$sdk/build-tools/36.0.0"
analyzer="$sdk/cmdline-tools/latest/bin/apkanalyzer"
for executable in "$build_tools/zipalign" "$build_tools/apksigner" "$build_tools/aapt2" "$analyzer"; do
  [[ -x "$executable" ]] || { echo "Missing Android SDK tool: $executable" >&2; exit 1; }
done
flutter pub get --enforce-lockfile
python3 tool/android/check-manifest.py --release android/app/src/main/AndroidManifest.xml \
  --extraction-rules android/app/src/main/res/xml/data_extraction_rules.xml
python3 tool/android/check-harness-absence.py --source lib --source android/app/src
python3 tool/android/generate-licenses.py --check --gradle-project android \
  --output android/app/src/main/assets --flutter-root "$flutter_root" \
  --flutter-version "$(flutter --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])')"
(cd android && ./gradlew --init-script ../tool/android/build-environment.init.gradle \
  :lineupBuildEnvironment --no-daemon --no-build-cache --no-configuration-cache) \
  > "$scratch/build-environment.txt"
(cd android && ./gradlew :app:dependencies --configuration releaseRuntimeClasspath \
  --no-daemon --no-build-cache --no-configuration-cache) > "$scratch/runtime-dependencies.txt"
python3 tool/android/check-resolved-dependencies.py "$scratch/build-environment.txt" "$scratch/runtime-dependencies.txt"
flutter build apk --release --target-platform android-arm,android-arm64
apk="$root/build/app/outputs/flutter-apk/app-release.apk"
python3 tool/android/check-unsigned-apk.py "$apk"
mkdir -p build/android-release
aligned="$root/build/android-release/lineup-unsigned-aligned.apk"
"$build_tools/zipalign" -P 16 -f 4 "$apk" "$aligned"
"$build_tools/zipalign" -c -P 16 -v 4 "$aligned"
python3 tool/android/check-unsigned-apk.py "$aligned"
if "$build_tools/apksigner" verify "$aligned" > "$scratch/signature-check.txt" 2>&1; then
  echo 'Unsigned candidate unexpectedly verifies as signed.' >&2
  exit 1
fi
if ! grep -q '^DOES NOT VERIFY$' "$scratch/signature-check.txt"; then
  cat "$scratch/signature-check.txt" >&2
  echo 'apksigner failed without an unsigned-signature rejection.' >&2
  exit 1
fi
python3 tool/android/check-harness-absence.py --artifact "$aligned"
python3 tool/android/check-manifest.py --reject-entry-bytes \
  android/app/src/debug/res/raw/fixture_ca.crt "$aligned"
python3 tool/android/check-manifest.py --apk "$aligned" \
  --apkanalyzer "$analyzer" --aapt2 "$build_tools/aapt2"
check_source
cp "$scratch/build-environment.txt" "$scratch/runtime-dependencies.txt" \
  "$scratch/signature-check.txt" build/android-release/
{
  echo "Reviewed commit: $reviewed_commit"
  echo "CI run: $ci_run"
  git show -s --format='Source: %H %s' HEAD
  flutter --version
  java -version 2>&1
  (cd android && ./gradlew --version --no-daemon)
  "$build_tools/apksigner" version
  "$analyzer" manifest application-id "$aligned"
  "$analyzer" manifest version-name "$aligned"
  "$analyzer" manifest version-code "$aligned"
  echo 'Unsigned aligned APK SHA-256'
  shasum -a 256 "$aligned"
} | tee build/android-release/build-evidence.txt
(cd build/android-release && shasum -a 256 lineup-unsigned-aligned.apk > SHA256SUMS)
echo "Unsigned candidate: $aligned"
