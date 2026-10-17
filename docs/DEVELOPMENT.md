# Development

This document owns Lineup's toolchain, commands, build prerequisites, and
evidence boundaries. Start at [AGENTS.md](../AGENTS.md) for agent workflow and
the [project profile](../.agents/project.md) for task-specific routing. The
shared skills own general implementation, design, review, and verification
procedures; they do not require separate agents or sessions for each activity.

Read the affected owner and relevant document sections; expand when a material
question remains. Independent investigation, checks, and implementation may
run in parallel when their contracts, ownership, worktrees or shared-tree
write scopes, and runtime resources permit it. The controller owns Git
integration and ensures checks observe a stable source state. Historical UI
campaign handoffs do not prescribe model choices or review batches for new work.

Use the task or PR's resolved target and base. For Electron provenance only,
use `git show bfaee636748f2a0d442f3690b7ba5262d32ff17c:<path>`; the historical
`initial-build` milestone is relevant only to an explicitly identified older
observation. Neither historical branch is a compatibility target.

## Architecture practice

[Architecture](architecture.md#accepted-ownership) owns the current
Flutter/Dart and native responsibilities. Use the shared `design-code` skill
when an unresolved domain or architecture decision warrants it. The project
profile maps the affected owners and obligations; a coherent redesign may
replace current private structure while preserving or explicitly migrating
those obligations. Existing files, queues, and abstractions are not permanent
design constraints merely because they already exist.

Preserve still-approved [UI decisions](../.interface-design/system.md) unless
the current task authorizes changing them. Workflow maintenance alone does not
approve a new visual direction or a platform migration.

## Quality and safety

Use the shared `verify-code` procedure and
[project-specific verification selection](../.agents/project.md#verification-selection)
to choose evidence. Coverage remains a local diagnostic, not a percentage gate.
Existing risk-matched checks are reused until changed code, fixtures,
dependencies, build settings, or relevant environment invalidate them.

Preserve the credential, diagnostic, cancellation, and persistence contracts in
[Architecture](architecture.md). Producers emit fixed safe messages and
normalized facts; do not put tokens, tokenized URLs, raw exceptions, native
messages, headers, or private media data in shared evidence. Redaction remains
defense in depth. Native dependency changes retain their provenance, license,
and redistribution obligations.

## Verification by task

Choose the affected checks below using the
[evidence identity and reuse rules](../.agents/project.md#native-evidence-and-reuse).
Native behavior and support claims require the relevant physical Windows
evidence with its actual tested identity. Missing Windows evidence does not
block unrelated portable work; report the specific unverified scenario.

| Task or evidence | Prerequisites and checks | What the result establishes |
| --- | --- | --- |
| Documentation only | `git diff --check`; check changed links, examples, and claims against their owners | Structural and source consistency; no new product or platform evidence |
| Dart policy, models, async work | Pinned Flutter SDK; focused tests plus the relevant full format/analyze/test checks below | Deterministic contracts; no Xcode application build or Windows engine provisioning required |
| Flutter layout, focus, semantics | Relevant widget tests at representative sizes; macOS for the required alpha suite and optional local visual checks below | Flutter composition and input/semantics contracts; physical Windows input, AT, and video layering remain separate |
| Persistence or credentials | Controller/store/transport failure, rollback, scope-isolation, and secret-flow tests named in [Architecture](architecture.md#changing-asynchronous-and-persisted-state) | Deterministic recovery/currentness; OS credential storage and physical filesystem behavior need platform observation |
| macOS development app and player | Xcode, the libmpv runtime (`LINEUP_MPV_RUNTIME`), and macOS setup below; `flutter build macos`, the `RunnerTests` XCTests, and the real-protocol harness as relevant | Build, conversion/rect contract, and protocol-flow evidence; visual layering, HDR output, and fullscreen need a physical observation on a visible display |
| Windows package policy | PowerShell 7.4+ on a portable host; `pwsh -File ./tool/windows/verify-release-policy.ps1` | Script parsing, repository-derived release inputs, production launch/exit contracts with fixture platform executables, and pinned policy inputs; no native Windows or package execution proof |
| Native player contract / C++ integration | Dart adapter/coordinator tests, lifetime/currentness inspection, Windows C++ toolchain and prepared libmpv; `flutter build windows` | Contract and stock-engine compile/link proof; not a runnable or packageable Lineup player |
| Patched engine / portable package | Full Windows provisioning below; release wrapper and [package acceptance](windows-native-validation.md#8-portable-package-acceptance) | Artifact-bound build/package checks; launch, media, HDR, layering, fullscreen, input, and support claims require [physical Windows acceptance](windows-native-validation.md) |

### Current test tiers and gaps

`test/` contains Dart policy, boundary, widget, and public-seam integration
tests using `flutter_test`. The product-spine test uses fake Plex/native
boundaries; `test_driver/ui_harness.dart` is a synthetic development composition
root. Neither is an automated real-app E2E harness with checked artifacts;
that harness is currently absent, and CI does not launch the app. Select
additional evidence by the changed obligation and credible failure, using the
shared verification procedure and existing owners in the project profile.
Building a new harness requires an actual task need; these synthetic checks
do not establish physical media, platform input, or package behavior.

`flutter analyze` includes `test/`, `tool/visual/`, and `test_driver/` under the
same analyzer configuration as `lib/`. There is no coverage-percentage floor;
`TZ=America/New_York flutter test --coverage` is available for local diagnosis.
Optional visual suites run explicitly as described below. Native runtime and
hardware proof follows [physical Windows acceptance](windows-native-validation.md).

Windows CI explicitly builds and runs `track_list_encoder_test`,
`native_playback_state_test`, `display_dynamic_range_test`, and
`display_guardian_test` after the stock-engine application build, using the
prepared pinned libmpv runtime and Flutter-generated inputs. These targets
remain excluded from the default application build. CTest runs serially, rejects
an empty selection, and allows 30 seconds per suite except the guardian's
60-second process-fixture budget. These contracts do not require a live Flutter
engine or physical HDR changes; they do not establish media or presentation
acceptance.

The assertion-based `track_list_encoder_test` exercises the real encoder,
not the app. It is defined with the shared player core in
`native/player_core/`, which the Windows runner build includes. After
configuring the Windows build with the prerequisites below, run:

```powershell
cmake --build .\build\windows\x64 --config Release --target track_list_encoder_test
ctest --test-dir .\build\windows\x64 -C Release -R '^track_list_encoder$' --output-on-failure --timeout 30
```

Additional targets cover native correlation and shutdown:

- `native_playback_state_test` exercises the actual worker-owned correlation
  state, including replacement, redirects, retirement, and observed idle.
- `player_core_contract_test` drives the shared core's parser, command queue,
  bounds, event projection and eviction, token header, and worker lifecycle
  through fake libmpv operations. It needs mpv headers but not libmpv.
- `encodable_value_conversion_test` checks the Windows adapter's conversion
  between Flutter codec values and the core's neutral values, including
  unchanged event bytes.
- `native_player_contract_test` drives the Windows adapter, codec, parser, command queue,
  load-to-state handoff, event projection, and real libmpv worker through a
  bounded HWND/message pump. Test-local DLL responses make selected load
  command/query outcomes deterministic; lifecycle scenarios use the real DLL.
- `runner_lifecycle_test` uses the actual `FlutterWindow`, engine, and messenger
  against installed candidate assets. A retained blank-widget Dart entry point
  avoids opening user state or credentials through the application bootstrap.

All are `EXCLUDE_FROM_ALL`; CI explicitly selects `native_playback_state_test`,
`player_core_contract_test`, and `encodable_value_conversion_test`. These tests
do not require a live engine or the patched engine:

```powershell
cmake --build .\build\windows\x64 --config Release --target player_core_contract_test encodable_value_conversion_test
ctest --test-dir .\build\windows\x64 -C Release -R '^(player_core_contract|encodable_value_conversion)$' --output-on-failure --timeout 45
```

The player-contract and
runner-lifecycle targets remain explicit local checks. Build/install the
candidate with the pinned patched engine and prepared libmpv first for those
checks, then build the targets and run their CTests:

```powershell
cmake --build .\build\windows\x64 --config Release --target native_playback_state_test native_player_contract_test runner_lifecycle_test
ctest --test-dir .\build\windows\x64 -C Release -R '^(native_playback_state|native_player_contract|runner_lifecycle)$' --output-on-failure --timeout 60
```

Record the exact candidate commit, installed asset identity, prepared/copied DLL
hashes, and patched-engine identity. The runner test's data path is the built
application's installed `data` directory. Stock-engine compilation does not
provide the runner test's required composition marker. Keep encoder and
authenticated-reference checks as distinct obligations.

The shared player core and its encoder, state, and contract tests are portable.
On macOS with Homebrew mpv headers (`/opt/homebrew/include` by default, or set
`-DLINEUP_MPV_INCLUDE_DIR=<dir>`):

```sh
cmake -S native/player_core -B build/player_core
cmake --build build/player_core
ctest --test-dir build/player_core --output-on-failure
```

Portable core proof does not compile or execute the Windows adapter/runner.
Blank-widget runner proof does not establish physical media, HDR, composition,
input, or package acceptance. Queue pressure preferentially removes property
events; an all-non-property saturated queue can evict an old acknowledgment,
so existing timeout/retry behavior remains necessary. Use the affected
[physical acceptance](windows-native-validation.md) scenarios for rapid tune
replacement, track confirmation, stop/retry, disposal/recreation, and window
close while work is pending.

The gated `authenticated_reference_test` target compiles the production native
player and drives its existing method channel against the exact prepared DLL.
It is `EXCLUDE_FROM_ALL`, with no CI gate change. Python 3, an FFmpeg executable
with the `libx264` encoder and DASH muxer, and OpenSSL are required. Put them on
PATH before running CTest; Python is resolved when the test runs, so ordinary
application configuration and builds do not require it. The runner also recognizes
Git for Windows' bundled OpenSSL. `LINEUP_MPV_ROOT` must be the prepared pinned runtime.
No Python packages or system trust-store changes are needed.

```powershell
cmake --build .\build\windows\x64 --config Release --target authenticated_reference_test
ctest --test-dir .\build\windows\x64 -C Release -R '^authenticated_reference$' --repeat until-fail:3 --verbose --timeout 180
```

The test verifies both prepared and copied DLL hashes, creates authenticated
loopback HTTPS fixtures and a temporary CA, and leaves TLS verification enabled.
Test-local forwarding around libmpv creation/initialization supplies only the CA
and null audio/video outputs; the production option list and authenticated
`loadfile` command are reused directly. The hidden window and supplied engine
marker allow the channel boundary to run without a live Flutter engine. This
does not validate presentation, hardware, real Plex playback, or packaging.
Option-rejection injection exercises fail-closed initialization, and an
untrusted-CA control verifies TLS refusal. All subprocesses, native observation
waits, socket operations and server joins are bounded; an overall 150-second
runner deadline leaves cleanup time before CTest's 180-second timeout.
Only normalized request counts, token-presence booleans and playback outcomes
are emitted. Servers, media, keys and certificates are removed after each run.
The [dated reference mitigation record](libmpv-authenticated-reference-investigation.md#2026-10-03-mitigation-disable-reference-following)
records the before/after evidence and source-audit limits. To reproduce the
negative comparison locally, remove only the two reference-hardening options,
rebuild the same test target, observe containment failure, then restore them and
rebuild. Do not distribute or commit that unhardened configuration.

The CI-selected `display_dynamic_range_test` uses fake
DisplayConfig/guardian/clock inputs, including failed-admission report and
shutdown checks.
`display_guardian_test` retains protocol/pipe fixtures and also launches real
Win32 predecessor, guardian and successor processes against isolated journals
and controlled display effects. Event barriers pause recovery before gate
acquisition and observe blocked production admission. Cases cover both desired
states, original HDR, timeout, multiple retained targets, clean disarm, helper
loss, failed/unknown recovery, late-write liability, external changes, stale
guardian identities, abandoned gates, corruption and unmutated orphan cleanup.
Its negative control bypasses admission to demonstrate premature original
capture; it does not reproduce the complete wrong-restoration chain.
The process fixture exercises production admission, display worker and guardian
recovery, with a controlled successor guardian link and a test protocol client.
It does not test the production `WindowsGuardianLink` launcher or `wWinMain`
window-focus path. Neither target changes Windows HDR or establishes physical
display behavior. After configuration, build the affected targets explicitly:

```powershell
cmake --build .\build\windows\x64 --config Release --target display_dynamic_range_test display_guardian_test native_player_contract_test runner_lifecycle_test
ctest --test-dir .\build\windows\x64 -C Release -R '^(display_dynamic_range|display_guardian|native_player_contract|runner_lifecycle)$' --output-on-failure --timeout 60
```

Install the pinned patched-engine candidate and prepared runtime before
runner-lifecycle execution as described above. The guardian CTest has a
60-second budget for process startup and its deliberately unresolved admission
cases. Synchronous Windows display/storage calls have no general OS timeout
guarantee; explicit coordination waits are bounded and run on native workers.
Unknown or failed recovery after helper loss intentionally retains its journal
record and disables successor matching; restarting does not erase that liability.
Power loss, OS crash and interrupted shutdown remain physical limits.

To include the separate encoder/authenticated-reference obligations:

```powershell
cmake --build .\build\windows\x64 --config Release --target track_list_encoder_test authenticated_reference_test display_dynamic_range_test display_guardian_test
ctest --test-dir .\build\windows\x64 -C Release --output-on-failure --timeout 180
```

The encoder/authenticated targets depend on Flutter-generated native inputs;
serialize these builds with Flutter checks and other shared-build writers.
The authenticated target retains the FFmpeg, OpenSSL, Python and pinned-runtime
prerequisites above. See the [HDR plan's evidence](fullscreen-hdr-implementation-plan.md#evidence)
for the controller and guardian contracts covered by their fake tests.

## Portable commands

Run `dart tool/check_toolchain.dart` before repository checks; it verifies that
the Flutter SDK on PATH matches `tool/flutter_version.json`. That configuration
is the canonical version/revision authority; use it when the pin changes.

Flutter SDK `3.47.7` (revision
`abaf9c523780a608bd46686fd5e53740a07077f8`, Dart `3.13.5`) is the reproducible
toolchain for macOS, Windows, and CI.

Select the exact Flutter checkout rather than a different SDK already on PATH:

```sh
git clone https://github.com/flutter/flutter.git /path/to/flutter
git -C /path/to/flutter checkout abaf9c523780a608bd46686fd5e53740a07077f8
export PATH=/path/to/flutter/bin:$PATH
flutter doctor -v
```

```sh
flutter pub get
dart tool/format.dart --check
flutter analyze
TZ=America/New_York flutter test
```

From PowerShell on macOS or Linux, use:

```powershell
$env:TZ = 'America/New_York'
flutter test
```

The [formatter](../tool/format.dart) uses tracked and non-ignored untracked Dart
files from Git, including new source in `lib`, `test`, `tool`, and `test_driver`.
Ignored build output and deleted files are excluded. `--check` reports formatting
differences without writing files; use `dart tool/format.dart` to format all these
inputs or `dart format <changed-paths>` to format an edit. Git and the selected
Dart SDK must be available; run from within the checkout.

The timezone above is canonical for localized schedule goldens on POSIX hosts.
On Windows, use the machine's configured Eastern Standard Time with the process
`TZ` variable unset:

```powershell
Remove-Item Env:TZ -ErrorAction SilentlyContinue
flutter test
```

The Windows Dart 3.13.5 runtime can interpret `TZ=America/New_York` as an
incorrect base offset while retaining Windows' Eastern timezone name/DST shift;
the October 11 HDR verification observed offsets 0/+1 instead of -5/-4.
The explicit POSIX-style plan command is still reported separately when requested.
Check effective local offsets; do not infer correctness from the timezone name.
If the machine is not configured for Eastern time, report that prerequisite
or have its operator configure it before claiming canonical schedule evidence.
The
full suite on Linux/Windows excludes the required alpha suite marked
`@TestOn('mac-os')`; the optional visual checks are outside the default `test/`
tree. A portable pass there is not macOS visual evidence. Run the required
macOS alpha checks when the Guide surface needs pixel verification:

```sh
TZ=America/New_York flutter test test/app/guide_opacity_test.dart
```

The named Guide Eastern-DST prerequisite test in
[`test/guide/guide_controller_test.dart`](../test/guide/guide_controller_test.dart)
must execute and pass when the machine's effective local offsets match its
Eastern cases. It explicitly skips incompatible offsets so another host does
not turn a portability limitation into a false failure; that skip is
portability evidence only, not a timezone-independent suite result. The
Windows OS timezone with process `TZ` unset governs the canonical Windows
result; `TZ=America/New_York` cannot establish it.

The five screenshot goldens are optional local visual-review checks outside the
default `test/` tree. They use Flutter's default exact comparator and remain
useful for intentional visual changes; run them explicitly when reviewing a
surface:

```sh
TZ=America/New_York flutter test tool/visual/ui_acceptance_golden_test.dart
TZ=America/New_York flutter test tool/visual/guide_sparse_golden_test.dart
```

To intentionally replace one of these local baselines after reviewing the
real-widget render, use `--update-goldens` on that explicit command:

```sh
TZ=America/New_York flutter test --update-goldens tool/visual/ui_acceptance_golden_test.dart
TZ=America/New_York flutter test --update-goldens tool/visual/guide_sparse_golden_test.dart
```

The equivalent required-alpha command from PowerShell on macOS is:

```powershell
$env:TZ = 'America/New_York'
flutter test test/app/guide_opacity_test.dart
```

The required alpha suite loads fonts from the pinned Flutter SDK, runs with
`TZ=America/New_York`, remains macOS-only, and performs exact pixel-alpha
checks: the no-playback Guide must be opaque, while Classic PiP transparency
must remain inside its native aperture. The two optional local suites load the
same pinned fonts and retain exactly five representative 1920×1080 snapshots:
rich and reference-free Guide, OSD, Now Playing, and Ember & Steel Appearance.
They are not run by default `flutter test` or required CI. The optional checks
use exact comparison, so inspect intentional visual changes before using
`--update-goldens`.

Inspect intentional golden changes from the real widgets. Preserve
[approved UI decisions](../.interface-design/system.md), including the protected
Player layouts and separate approval for structural proposals.

## macOS development app

For macOS application builds/runs, install Xcode and its command-line tools on
macOS 12 or newer. Resolve relevant Xcode/macOS warnings from `flutter doctor`;
those application prerequisites do not gate unrelated Dart checks. The
application currently targets macOS 12.0 on Apple silicon (arm64 only).
macOS is not yet a release platform; the port plan is
[macos-port-plan.md](macos-port-plan.md). The macOS player implements
[the protocol](native-player-protocol.md) with the Objective-C++ adapter in
`macos/Runner/NativePlayer/` on the shared core in `native/player_core/`.

### libmpv runtime

The Runner links the prepared LGPL libmpv runtime (the S2 build with the
`CAMetalLayer` `--wid` embedding patch) and embeds its `lib/*.dylib` files into
`Contents/Frameworks`, signed with the app's identity. The runtime location
is the single build setting `LINEUP_MPV_RUNTIME`, defined in
`macos/Runner/Configs/NativePlayer.xcconfig`. It defaults to
`build/macos-runtime/dist/arm64` in the repository. The build fails early, with
a message naming the path, when `include/mpv/client.h` or `lib/libmpv.2.dylib`
is missing. To use a runtime elsewhere, either set it in the environment of
the build:

```sh
LINEUP_MPV_RUNTIME=/path/to/macos-runtime/arm64 flutter build macos
```

or write `LINEUP_MPV_RUNTIME = /path/to/macos-runtime/arm64` in the untracked
`macos/Runner/Configs/NativePlayer.local.xcconfig`, which takes precedence over
the environment. Runtime provisioning, pinning, and App Store signing are
package R1 of the port plan.

```sh
flutter config --enable-macos-desktop
flutter run -d macos
flutter build macos
```

### Native unit tests

`macos/RunnerTests` holds unhosted XCTests for the Foundation/`Value`
conversion and the video rectangle rules. They need an application build
first (for the generated Flutter configuration) and the runtime setting:

```sh
flutter build macos --debug
cd macos
xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination 'platform=macOS' -only-testing:RunnerTests
```

### Real-protocol harness

`test_driver/macos_native_harness.dart` is the synthetic `ui_harness.dart`
composition with the real `MethodChannelNativePlayer` and local media. The app
is sandboxed, so it can read media only inside its container. Copy test media
there and pass absolute paths separated by `|`:

```sh
media="$HOME/Library/Containers/com.tjzine.lineupDesktop/Data/tmp/lineup-media"
mkdir -p "$media" && cp sdr.mp4 hdr10.mp4 "$media/"
flutter build macos --debug -t test_driver/macos_native_harness.dart \
  "--dart-define=LINEUP_HARNESS_MEDIA=$media/sdr.mp4|$media/hdr10.mp4" \
  --dart-define=LINEUP_HARNESS_EXERCISE=true
LINEUP_PRESENTATION_LOG=1 \
  "build/macos/Build/Products/Debug/Lineup Desktop.app/Contents/MacOS/Lineup Desktop"
```

Channel N plays media N modulo the list. With `LINEUP_HARNESS_EXERCISE=true`
the harness loads each file in turn through the real player, with seek,
volume, track selection, fullscreen, and video rectangle changes on the
first, then stops. It prints every call outcome, state, telemetry change, and
display report with a `[harness]` prefix, and never prints media paths.
`LINEUP_PRESENTATION_LOG=1` makes the adapter log the video layer's color
space, EDR, EDR metadata, drawable size, visibility, and the screen's EDR
headroom whenever they change. Neither is evidence of visual correctness.
HDR judgments need a physical observation on an unlocked, visible display.

## Windows native player

### Application compile check

Use the pinned Flutter SDK, Git, PowerShell 7.4+ (`pwsh`), Visual Studio Build
Tools 2022 with Desktop C++ and a Windows SDK, and 7-Zip.

Windows application builds require SDK **10.0.26100.0 or newer**; CMake rejects
an older selected SDK with a configure error. The shared DisplayConfig API
translation unit enables newer declarations locally, with runtime capability
detection preserving Windows 10 execution. The patched engine's separately
pinned SDK below is unchanged.

Prepare the ignored x86-64 LGPL libmpv directory before configuring the application:

```powershell
Set-Location C:\path\to\LineupDesktop
$mpvRoot = 'C:\local\lineup-mpv-20261002-3186d369f9' # New or empty directory.
& .\tool\windows\prepare-mpv.ps1 -Destination $mpvRoot
$env:LINEUP_MPV_ROOT = $mpvRoot
flutter build windows
```

This is only a compile/link integration check against Flutter's stock cached
engine. It is not a runnable Lineup player or a packageable release because
native initialization requires the repository-patched DirectComposition engine.

The preparation script verifies the archive, generates an MSVC import library,
and writes the provenance record required by CMake. Acquisition pins and
integrity checks live in the build scripts and CMake; see
[Windows Runtime Provenance](windows-runtime.md) for the asset identity,
component versions, licenses, and redistribution obligations. Runnable test and
package machines also need a GPU driver or Vulkan Runtime providing
`vulkan-1.dll`, even though Lineup selects D3D11 output.

When the pinned runtime changes, provision it into a fresh unique destination;
do not reuse or overwrite an older prepared directory. Rebuild the Lineup
application against the new runtime. When the pinned Flutter SDK or engine
changes, reprovision its patched `host_debug` and `host_release` outputs
before launching or packaging; the older SDK outputs cannot be reused.

### Patched engine provisioning

Only engine builds and runnable player/package work require the full engine
toolchain: the application prerequisites above plus Python 3, pinned
`depot_tools`, Visual Studio ATL, Windows SDK `10.0.22621.0`, and Debugging Tools
for Windows. The pinned Flutter checkout is also the engine source checkout.
Use [build metadata](../tool/windows/build-metadata.psd1) for exact identities:

```powershell
$metadata = Import-PowerShellDataFile C:\path\to\LineupDesktop\tool\windows\build-metadata.psd1
git clone --depth 1 --no-checkout https://chromium.googlesource.com/chromium/tools/depot_tools.git C:\path\to\depot_tools
git -C C:\path\to\depot_tools fetch --depth 1 origin $metadata.DepotToolsRevision
git -C C:\path\to\depot_tools checkout --detach $metadata.DepotToolsRevision
if ((git -C C:\path\to\depot_tools rev-parse HEAD).Trim() -ne $metadata.DepotToolsRevision) { throw 'depot_tools revision mismatch.' }
git clone https://github.com/flutter/flutter.git C:\path\to\flutter
git -C C:\path\to\flutter checkout $metadata.FlutterFrameworkRevision
if (
  (git -C C:\path\to\flutter rev-parse HEAD).Trim() -ne
  $metadata.FlutterFrameworkRevision
) {
  throw 'Flutter framework revision mismatch.'
}

$env:PATH = 'C:\path\to\depot_tools;C:\path\to\flutter\bin;' + $env:PATH
$env:DEPOT_TOOLS_UPDATE = '0'
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = '0'
$env:GYP_MSVS_OVERRIDE_PATH = 'C:\path\to\VisualStudio2022BuildTools'
$env:WINDOWSSDKDIR = 'C:\Program Files (x86)\Windows Kits\10'

Set-Location C:\path\to\flutter
Copy-Item .\engine\scripts\standard.gclient .\.gclient
gclient sync --no-history
C:\path\to\LineupDesktop\tool\flutter_engine\apply.ps1 -FlutterRoot (Get-Location)

Set-Location engine\src
python .\flutter\tools\gn --runtime-mode=debug
ninja -C out\host_debug
python .\flutter\tools\gn --runtime-mode=release
ninja -C out\host_release
```

See the [engine patch contract](../tool/flutter_engine/README.md) for source
validation and provenance. Reuse provisioned outputs only while their inputs
remain current. Select the resulting engine explicitly; do not replace a stock
Flutter SDK cache.

### Development launcher

Only one Lineup instance runs per Windows user session. A second application
launch, including a second `flutter run`, brings the existing window forward and
exits successfully; its arguments (including `--media`) are ignored. Close the
existing app normally before launching a different development candidate.
Guardian mode dispatch occurs before instance enforcement and initializes no
Flutter engine or window.

After the one-time prerequisites and patched `host_debug` setup above, the
small PowerShell launcher reuses those exact local-engine outputs. Configure
the two machine-specific paths once as user environment values, and set them
in the current session as well:

```powershell
$engineSource = 'C:\path\to\flutter\engine\src'
$mpvRoot = 'C:\local\lineup-mpv-20261002-3186d369f9'
[Environment]::SetEnvironmentVariable('LINEUP_ENGINE_SOURCE', $engineSource, 'User')
[Environment]::SetEnvironmentVariable('LINEUP_MPV_ROOT', $mpvRoot, 'User')
$env:LINEUP_ENGINE_SOURCE = $engineSource
$env:LINEUP_MPV_ROOT = $mpvRoot
```

Then run the normal Plex onboarding/application entry point:

```powershell
Set-Location C:\path\to\LineupDesktop
pwsh -File .\tool\windows\run.ps1
```

The script also works from another caller directory when given its full path:

```powershell
pwsh -File 'C:\path\to\LineupDesktop\tool\windows\run.ps1'
```

For the existing local-media entry point, pass an existing file explicitly:

```powershell
pwsh -File .\tool\windows\run.ps1 -MediaPath 'C:\path\to\sdr-sample.mp4'
```

The launcher validates Windows, the required paths, the pinned Flutter
framework/engine revisions, the repository patch and applied manager source,
and the prepared libmpv inputs. It requires `engine\src\out\host_debug\build.ninja`
and runs incremental Ninja before `flutter run`, so changed patched-engine
source is not silently stale. It does not run GN, provision engine sources,
apply the patch, or use an arbitrary `flutter` on `PATH`; missing provisioning
is a setup error with a link back to the commands above. If the pinned
Flutter checkout lacks its Windows SDK cache, the launcher runs that
checkout's `bin\flutter.bat precache --windows` once; it never changes a
different SDK cache. Uncommitted Lineup application edits are allowed for
development, while the release wrapper below still requires a clean checkout.

Update the saved paths after moving or reprovisioning the Flutter engine or
libmpv directory. The launcher restores the caller's current directory and
`LINEUP_MPV_ROOT` value when it exits.

### Portable package

After the one-time prerequisites, patched `host_release` setup, and a clean
Lineup checkout (no tracked changes or non-ignored untracked files), build and
package the portable application:

```powershell
Set-Location C:\path\to\LineupDesktop
$env:LINEUP_MPV_ROOT = 'C:\local\lineup-mpv-20261002-3186d369f9'
.\tool\windows\build-release.ps1 -EngineSource 'C:\path\to\flutter\engine\src'
.\tool\windows\package.ps1
```

The default archive is
`build/package/LineupDesktop-<version>-windows-x64.zip` (for example,
`LineupDesktop-0.1.0-1-windows-x64.zip`). If that destination or archive
already exists, choose a unique destination below `build/package`:

```powershell
.\tool\windows\package.ps1 -Destination 'build/package/LineupDesktop-0.1.0-1-windows-x64-rerun'
```

Review and deliberately move or remove an old package yourself when that is
intended; the package script never silently overwrites or deletes an existing
destination. The resulting archive contains a complete portable folder.
Extract the entire folder and run `lineup_desktop.exe`; keep its adjacent DLLs
and `data` directory together. The package also includes provenance, licenses,
system requirements, and a manifest. This is a private portable build flow,
not an installer or a public-release claim; launch, media, and hardware
acceptance still require the physical-Windows procedure in
[Windows Native Acceptance](windows-native-validation.md).

The release wrapper validates the clean Lineup checkout, exact framework and
engine revisions, and exact patched manager source, refreshes the configured
`host_release` engine with Ninja, and selects that output for Flutter. After
Flutter succeeds, it writes
`LINEUP-BUILD-PROVENANCE.json` beside the executable with hashes for every
build input copied into the portable package. `tool/windows/package.ps1`
requires that marker, rechecks it against the clean current commit and pinned
engine metadata, and rejects stale markers or modified build artifacts.

## CI evidence

[The workflow](../.github/workflows/ci.yml) runs portable Dart verification on
Linux, the required macOS alpha suite and an application build on macOS, portable
PowerShell release-policy validation, and focused widget tests plus a
stock-engine C++/CMake application build on Windows Server 2022 followed by
the existing encoder, playback-state, display-controller, and guardian CTests.
The native suites use real contract assertions and controlled fixtures; the
guardian includes Win32 subprocess coverage. The player-contract,
runner-lifecycle, and authenticated-reference CTests remain separate explicit
checks and are not selected by CI.

The expensive patched-engine/package job is conditional on engine and direct
package-policy inputs selected by `release-inputs`. Ordinary `lib/` or
`windows/` source edits alone do not select it. Manual workflow dispatch and an
unavailable comparison baseline also select the full job. When selected, it
verifies the pinned source/configuration/patch, builds `host_release`, invokes
the release wrapper, and exercises artifact/provenance/license/package rejection
checks. Inspect which jobs actually ran before describing a green CI result.
CI does not launch the application; runtime markers and native presentation
still require physical Windows acceptance.
