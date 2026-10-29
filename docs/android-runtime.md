# Android TV runtime

Lineup's Android host targets Android TV / Google TV and Android-based Fire TV
(Fire OS), API 28 or later. The application ID is `com.tjzine.lineup`, with
launcher label **Lineup**. Vega OS, phones and tablets are outside this beta.
The private sideload APK contains `armeabi-v7a` and `arm64-v8a` only.

Flutter/Dart owns application policy, focus and interaction. `MainActivity` hosts
Flutter and installs one `lineup/platform` method handler; `PlatformChannel.kt`
dispatches platform operations. `openPlexLink` accepts no Dart URL: native code
opens the fixed public `https://plex.tv/link` address and reports whether a
browser opened. TVs without a browser retain the displayed PIN and QR code.
`moveTaskToBack` backgrounds the task without finishing it. Android does not
register the desktop `lineup/app_menu` handler.

The Dart composition root selects the existing native-player protocol on Android.
The Kotlin adapter uses Media3 for media/OS mechanisms while the shared Dart
coordinator retains playback and scheduling policy. Packages and bundled font
notices work offline, and Android native-runtime notices are generated into the
APK assets (see [Release packaging and runtime notices](#release-packaging-and-runtime-notices)). Android hides the Windows HDR-matching toggle and
exposes Settings during onboarding and the Licenses row under Support.

## Playback adapter

`MainActivity` composes native default-z-order video, a Media3 SubtitleView and
transparent surface-rendered Flutter. `player/NativePlayerAdapter.kt` owns these
passive views and the method channel; `NativePlayerController.kt` owns protocol
validation, bounded queues, correlation and lifecycle fencing. A fresh
`Media3Engine` belongs to each load. See the [Android protocol details](native-player-protocol.md#android-backend)
for failure mapping, telemetry, exact initial joins and display limitations.
There is one authoritative Dart application; no Android Plex, schedule,
persistence or navigation implementation exists beside it. Windows/macOS keep
their existing libmpv adapters and transport contracts.

Synthetic runtime tools live in [tool/android/fixtures](../tool/android/fixtures/README.md).
The CA public certificate and trust override are debug-only. Fixture keys stay
outside the repository. Profile and release do not trust that CA. Use an assigned
device and loopback-only adb reverse; never feed private media or credentials to
the fixture entrypoint. JVM tests establish protocol/encoding behavior and
extractor regressions, while emulator media checks establish actual Media3
control behavior on that emulator. Neither replaces physical Fire TV/HDR/audio
or final integrated acceptance. Temporal G6 remains unverified; proceeding with
D8 does not establish its one-display-frame transition bound.

## Toolchain and builds

Use the Flutter identity in [tool/flutter_version.json](../tool/flutter_version.json)
(currently 3.47.7). Android uses the stock Flutter engine; desktop engine patches
are unrelated. The generated host uses Gradle 9.3.1, Android Gradle Plugin 9.1.0,
Kotlin 2.4.0 and JDK 17. Compile/target SDK and NDK follow the pinned Flutter
SDK defaults (currently API 36 and NDK 28.2.13676358); minimum SDK is 28.
Install Android SDK platform-tools, platform 36 and build-tools 36.0.0, and the
NDK when required by the build. Current plugin/native-asset builds also require
SDK platform 35 and CMake 3.22.1. A Google TV API 36 arm64 AVD covers the modern
Back path; it cannot establish physical HDR, Dolby Vision or audio passthrough.

On the maintainer's Mac:

```sh
export PATH="$HOME/.cache/lineup-flutter/3.47.7/flutter/bin:$HOME/Library/Android/sdk/platform-tools:$PATH"
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
flutter pub get
# Dedicated Lineup signing key, for BOTH debug and release:
tool/android/with-signing.sh flutter build apk --debug --target-platform android-arm,android-arm64
```

The host explicitly filters native libraries to the two ARM ABIs, including
assets contributed by Dart native hooks. Its pinned-Flutter configuration keeps
Flutter from replacing that filter with the default ABI list.

The universal debug APK is `build/app/outputs/flutter-apk/app-debug.apk`.
Contributors and CI without the Lineup key can set
`LINEUP_ANDROID_SIGNING=debug-key` to build **debug only**, using Android's
standard debug key. Release packaging fails closed without the dedicated key;
there is no release debug-key fallback.

The signing wrapper reads the password from the macOS login Keychain service
`lineup-android-release` for the current user, exports it only to the build
process, and disables persistent Gradle daemons. It never prints the password
or puts it in command arguments. Do not enable shell/Gradle debug tracing around
signing. The keystore is outside Git at
`~/.config/lineup-android/lineup-release.jks`, alias `lineup`; `LINEUP_ANDROID_KEYSTORE`
and `LINEUP_ANDROID_KEY_ALIAS` can override those non-secret defaults.
**Back up the keystore securely.** Losing it prevents in-place updates and forces
an uninstall, deleting on-device lineups and sign-in.

## Release packaging and runtime notices

Run the release recipe from the repository root:

```sh
export PATH="$HOME/.cache/lineup-flutter/3.47.7/flutter/bin:$HOME/Library/Android/sdk/platform-tools:$PATH"
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export GRADLE_OPTS=-Dorg.gradle.project.android.builder.sdkDownload=false
tool/android/build-release.sh
```

The recipe resolves `releaseRuntimeClasspath`, requires Maven POM license
metadata for every external module, and checks the committed upstream license
text and dependency manifest under `android/app/src/main/assets/licenses/`.
Notice drift fails release preparation without rewriting tracked assets. After
an intentional dependency or Flutter SDK update, regenerate and commit the
notices before building:

```sh
python3 tool/android/generate-licenses.py --gradle-project android \
  --output android/app/src/main/assets \
  --flutter-root "$HOME/.cache/lineup-flutter/3.47.7/flutter" \
  --flutter-version 3.47.7 --license-cache build/android-license-cache
```

Add `--check` to verify the same graph without changing the asset tree; the
Android CI job runs this check too. Flutter engine
artifacts are the explicit exception: their Maven POMs omit license metadata,
so the generator embeds the exact `LICENSE` file from the selected Flutter SDK.
Unknown or incomplete metadata fails closed; the generator never assumes a
license from a group name or artifact type. The generated tree includes
`BUILD-INFO.txt`, `licenses/NOTICES-SUMMARY.txt`, `licenses/DEPENDENCIES.txt`,
each resolved component's complete fetched license document, and any
artifact-specific `NOTICE` entries plus referenced license terms found in the
actual cached JAR. It is served offline through the existing `lineup/platform`
license operations using opaque asset IDs and bounded UTF-8 reads. Android
ships no LGPL runtime or Sources-and-rebuilding group.

`build-release.sh` runs through `with-signing.sh`, builds the universal
`armeabi-v7a` plus `arm64-v8a` release APK, and prints the APK SHA-256,
versionName/versionCode, verified signing certificate fingerprint, Flutter
version and resolved Media3 version. It verifies the final APK with the
Android SDK `apksigner` and fails unless the expected Lineup certificate is
present. Source and packaged manifests must opt in to `OnBackInvokedCallback`
so Back works on API 33–35; the release script checks both using the SDK's
`apkanalyzer` for the APK. A missing Lineup key fails before release packaging;
`LINEUP_ANDROID_SIGNING=debug-key` is accepted only by the CI debug job and is
never a release fallback. The Android CI job uses pinned Flutter, the debug-key
mode, the ARM debug build, and `:app:testDebugUnitTest`; hosted CI execution is
separate from the maintainer's signed release and device acceptance.

## Install, launch and logs

Always select the assigned device explicitly. Replace `emulator-5554` with the
actual assigned serial; never assume the default device.

```sh
adb -s emulator-5554 install -r -d build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 shell am start -n com.tjzine.lineup/.MainActivity
adb -s emulator-5554 shell input keyevent KEYCODE_DPAD_DOWN
adb -s emulator-5554 shell input keyevent KEYCODE_DPAD_CENTER
```

After sign-in, update only with `adb -s <serial> install -r -d <apk>` using the
same Lineup key. `flutter install` uninstalls by default, and `flutter run` can
uninstall after an install failure, losing sign-in and lineups. Use those tools
only on disposable emulators.

For development media, Flutter 3.47.7 requires a **String ArrayList** extra
(`--esal`); `--esa` produces a `String[]` and crashes the embedding. Stop the
existing process first so the entrypoint runs again:

```sh
adb -s emulator-5554 shell am force-stop com.tjzine.lineup
adb -s emulator-5554 shell am start -n com.tjzine.lineup/.MainActivity --esal dart_entrypoint_args "'--media=https://localhost:8443/fixture.mp4?case=join&n=1'"
```

The nested quotes preserve `&` and `?` across the host/device shells. Escape any
commas in the URI as `\,`, because `--esal` splits on commas. This path is for
debug/profile synthetic media only; never pass credentials. Dart ignores
`--media=` in Android release builds. Desktop argument behavior is unchanged.

Capture diagnostics locally, then sanitize before sharing:

```sh
adb -s emulator-5554 logcat --pid="$(adb -s emulator-5554 shell pidof com.tjzine.lineup)" > /tmp/lineup-android-local.log
adb -s emulator-5554 shell dumpsys meminfo com.tjzine.lineup
adb -s emulator-5554 shell dumpsys gfxinfo com.tjzine.lineup
adb -s emulator-5554 exec-out screencap -p > /tmp/lineup-android.png
```

Raw logcat and dumps are private evidence. Never commit credentials, tokens,
server addresses, account names or media titles.

## Storage and backup

`FileAppStore` retains its existing application-support directory and format
version guard. `flutter_secure_storage` uses Android Keystore-backed RSA OAEP
key wrapping with AES-GCM storage, without biometric prompts. Explicit
`AndroidOptions(resetOnError: false)` surfaces Keystore errors instead of
silently erasing credentials. macOS options and Windows behavior are unchanged.

Backup is disabled with `allowBackup=false`, `fullBackupContent=false`, and
[data extraction rules](../android/app/src/main/res/xml/data_extraction_rules.xml)
that exclude every credential/device-protected domain from cloud backup and
device transfer. The rules complement `allowBackup` on API 31+, where some
manufacturers still permit device transfer with that flag alone. See the
[Android backup contract](https://developer.android.com/identity/data/autobackup).
The app permits HTTPS traffic only and requests no cleartext exception.

The runtime smoke entrypoint in
[test/persistence/android_credential_smoke.dart](../test/persistence/android_credential_smoke.dart)
uses synthetic values and checks real native secure storage plus saved state.
Run it **only on a fresh disposable emulator**, never a signed-in device:

```sh
tool/android/with-signing.sh flutter build apk --debug --target-platform android-arm,android-arm64 --target test/persistence/android_credential_smoke.dart
adb -s emulator-5554 install -r -d build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 shell am start -n com.tjzine.lineup/.MainActivity --esal dart_entrypoint_args "'write'"
# Observe U1_STORAGE_WRITE_PASS, force-stop, and install the same signed APK again.
adb -s emulator-5554 shell am force-stop com.tjzine.lineup
adb -s emulator-5554 install -r -d build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 shell am start -n com.tjzine.lineup/.MainActivity --esal dart_entrypoint_args "'verify-and-clear'"
# Observe U1_STORAGE_RESTART_UPGRADE_DELETE_PASS. Rebuild normal lib/main.dart.
```

## Support and acceptance limits

The primary physical target is the Fire TV Stick 4K Max (2nd generation,
AFTKRT), Fire OS 8 / API 30, with a 32-bit userland. An arm64 emulator does not
exercise its `armeabi-v7a` runtime. Record actual device/build identities with
results; installation support is not media or performance acceptance.

Direct Play is the beta media scope. Display-mode/HDR matching is unavailable;
unsupported audio cannot use an FFmpeg extension. Built-in ASS styling is
limited. The Studio manual editor and air check remain reachable but are not
TV-accepted. Physical playback, HDR/DV, passthrough, remote feel and viewing-
distance readability require their own device/human acceptance.

## Subtitle presentation and device captions

Flutter owns the appearance of ordinary text subtitles. Media3 decodes them and
reports bounded styled text segments through the load-scoped `subtitle-cues`
property; the native SubtitleView receives no ordinary text. SSA keeps authored
styling unless the viewer opts into Lineup styling. Bitmap cues remain native.
Both native kinds scale live; supported bitmap geometry also raises and clamps.
SSA's default text size compensates for letterboxing so its em size follows the
Lineup presentation rectangle. Native defaults are white with black outline,
transparent background and window, with embedded SSA styles/sizes enabled.

Device caption colors, edges, font scale and typeface come directly from
CaptioningManager through `lineup/device_captions`. Dart explicitly subscribes;
OS changes send `changed`, and cancel/activity cleanup removes the listener.
The style is read even when the OS captions switch is off. Fire OS backing of
these values still requires the physical-device check; emulator reads do not
prove that platform behavior.

The additive `subtitle-*` fixture corpus and focused generation command are
documented in [the fixture README](../tool/android/fixtures/README.md).
Routing/JVM tests establish bounds, span/alignment mapping, queue retention,
track rerouting, live transforms and view reset. Packaged emulator checks and
physical PGS/HDR/Fire OS acceptance remain separate evidence.

API 34 Android TV emulator validation confirms comparisons against all seven
specified Typeface families and live updates from the system Captions screen,
including style changes while its Display switch is off. This establishes the
Android OS channel; the Fire OS settings backing remains a physical check.
