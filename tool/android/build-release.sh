#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
flutter_bin="$(command -v flutter || true)"
if [[ -z "$flutter_bin" ]]; then
  echo 'Flutter 3.47.7 is required on PATH.' >&2
  exit 1
fi
if [[ ! -x "$root/android/gradlew" ]]; then
  echo 'Android Gradle wrapper is missing. Run flutter create --empty --platforms=android --no-overwrite .' >&2
  exit 1
fi

flutter_root="$(cd "$(dirname "$flutter_bin")/.." && pwd)"
version_line="$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+)\+([0-9]+)[[:space:]]*$/\1 \2/p' "$root/pubspec.yaml")"
if [[ -z "$version_line" ]]; then
  echo 'Could not read versionName/versionCode from pubspec.yaml.' >&2
  exit 1
fi
read -r version_name version_code <<< "$version_line"

report="$(mktemp "${TMPDIR:-/tmp}/lineup-android-release-dependencies.XXXXXX")"
cert_report="$(mktemp "${TMPDIR:-/tmp}/lineup-android-release-certificates.XXXXXX")"
cleanup() { rm -f "$report" "$cert_report"; }
trap cleanup EXIT

(
  cd "$root/android"
  ./gradlew :app:dependencies --configuration releaseRuntimeClasspath --no-daemon
) > "$report"

python3 "$root/tool/android/check-manifest.py" "$root/android/app/src/main/AndroidManifest.xml"

python3 "$root/tool/android/generate-licenses.py" --check \
  --dependency-report "$report" \
  --output "$root/android/app/src/main/assets" \
  --flutter-root "$flutter_root" \
  --flutter-version "$(flutter --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])')" \
  --license-cache "$root/build/android-license-cache"

"$root/tool/android/with-signing.sh" flutter build apk \
  --release --target-platform android-arm,android-arm64

apk="$root/build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "$apk" ]]; then
  echo "Release APK not found: $apk" >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1; then
  apk_sha256="$(shasum -a 256 "$apk" | awk '{print $1}')"
else
  apk_sha256="$(openssl dgst -sha256 "$apk" | awk '{print $NF}')"
fi
android_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
"$android_sdk/cmdline-tools/latest/bin/apkanalyzer" manifest print "$apk" | \
  python3 "$root/tool/android/check-manifest.py" -
apksigner="$(find "$android_sdk/build-tools" -maxdepth 2 -type f -name apksigner -print 2>/dev/null | sort -V | tail -n 1)"
if [[ -z "$apksigner" || ! -x "$apksigner" ]]; then
  echo "Android SDK apksigner is unavailable under $android_sdk/build-tools." >&2
  exit 1
fi
if ! "$apksigner" verify --print-certs "$apk" > "$cert_report" 2>&1; then
  echo "apksigner rejected the release APK: $apk" >&2
  exit 1
fi
cert_sha256="$(sed -nE 's/^[[:space:]]*Signer #1 certificate SHA-256 digest:[[:space:]]*([[:xdigit:]:]+)[[:space:]]*$/\1/p' "$cert_report" | head -n 1 | tr -d ':' | tr '[:lower:]' '[:upper:]')"
expected_cert_sha256='D67697201152AB71DD9D5820D06B128520242EE171117F923A4328F52894C6B8'
if [[ ! "$cert_sha256" =~ ^[[:xdigit:]]{64}$ || "$cert_sha256" != "$expected_cert_sha256" ]]; then
  echo 'Release APK signing certificate did not match the expected Lineup certificate.' >&2
  exit 1
fi
media3_version="$(sed -nE 's/.*media3-exoplayer:([^" ]+).*/\1/p' "$root/android/app/build.gradle.kts" | head -n 1)"
if [[ -z "$media3_version" ]]; then
  media3_version='not-integrated'
fi

echo "APK: $apk"
echo "APK SHA-256: $apk_sha256"
echo "versionName: $version_name"
echo "versionCode: $version_code"
echo "certificate SHA-256: $cert_sha256"
echo "Flutter: $(flutter --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])')"
echo "Media3: $media3_version"
