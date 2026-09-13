# Development

Lineup Desktop work normally moves through five activities in one session:

1. **Inspect** the current flow, its owners, tests, and platform constraints.
   Use `git show bfaee636748f2a0d442f3690b7ba5262d32ff17c:<path>` when the
   preserved Electron implementation is provenance evidence. The mutable
   `origin/electron-ui` branch is suitable only for non-evidentiary exploration.
   Use `git show origin/initial-build:<path>` for the later historical Flutter
   milestone only when that evidence is relevant.
2. **Decide** the responsibility owner, dependency direction, failure behavior,
   and proportionate proof before editing.
3. **Implement** the smallest cohesive change that meets current requirements.
   Delete displaced alternatives and keep commits coherent.
4. **Verify** with fresh, observed evidence matched to the risk.
5. **Self-review and close out** the complete diff, remaining platform limits,
   and whether independent review is specifically worthwhile.

These are not mandatory separate agents, sessions, tracked plans, Tiers, or
handoff formats. Independent review is optional and never launched
automatically. Recommend it for novel security boundaries, credential or data
loss risks, complex concurrency, native ABI/lifetime work, or Windows media and
presentation changes whose proof deserves a second specialist.

Read the relevant sections and affected owners first; broaden to callers, adjacent
contracts, or complete documents when invariants or behavior remain unclear.
Continue authorized implementation and repair failures caused by the change without
requesting approval at each step. Ask when investigation leaves a consequential
product, design, security, data-loss, or scope decision unresolved. Preserve existing
UI design approvals in `.interface-design/system.md`.

Reuse inspected verification results when the tested code, inputs, dependencies,
and relevant environment are unchanged. Rerun affected checks when edits or
integration invalidate them, and add proof for uncovered interactions. Nonbehavioral
edits need only the relevant structural or formatting check. Physical Windows
evidence requirements for native behavior and support claims remain unchanged.

## Architecture practice

Use a feature-oriented modular monolith. A feature owns its models, policies,
state, and UI where that improves cohesion. The application bootstrap is the
single composition root; dependencies point from that root into features and
are passed explicitly through constructors. Avoid repeated
`data/domain/presentation` ceremonies and generic `core` or `utils` dumping
grounds. Local widget state stays local. Adopt one state-management package only
when a concrete cross-feature asynchronous state graph shows a material
debugging, testing, or correctness advantage over Flutter/Dart built-ins.

Current requirements outrank hypothetical compatibility. Keep one owner per
responsibility and make cancellation/currentness explicit for asynchronous
work. Bound queues and caches whose inputs can grow.

Apply SOLID, DRY, KISS, and YAGNI as design judgment:

- Group behavior by shared invariants and reason to change. Split an independent
  policy or resource lifetime when that improves ownership; file length alone
  does not justify either splitting or accumulating responsibilities.
- Keep one authoritative implementation of each business rule, such as schedule
  resolution. Extract shared knowledge, not merely similar syntax whose callers
  may evolve independently.
- Keep interfaces small at real boundaries. Substitutes must preserve errors,
  ordering, and cleanup as well as successful results. Prefer composition and
  explicit collaborators; SOLID does not require an interface per class,
  inheritance, or speculative extension points.
- Prefer established repository and platform conventions. Judge simplicity by
  readability and total maintenance cost, not the fewest lines or files.
- Make scoped refactors and regression protection part of completing the change.
  YAGNI rules out speculative capability, not work that keeps current code safe
  to change. Remove obsolete paths replaced by the change; report concrete
  remaining debt with its consequence rather than adding vague future-proofing.

These interpretations use the maintainer's
[SOLID/DRY/KISS reference](https://scalastic.io/en/solid-dry-kiss/),
[Fowler's YAGNI clarification](https://martinfowler.com/bliki/Yagni.html), and
[Google's design/complexity review guidance](https://google.github.io/eng-practices/review/reviewer/looking-for.html).
They do not add a mandatory review pass or a new workflow.

## Quality and safety

- Test pure policies and public seams. Add widget/integration/manual proof when
  behavior depends on focus, accessibility, rendering, lifecycle, or native
  platform integration. Do not use brittle tests merely to increase coverage.
- Evaluate each dependency for current need, activity, license, desktop support,
  transitive cost, debuggability, and standard-library alternatives. Record
  material license obligations before shipping bundled native libraries.
- Never commit Plex credentials, authorization headers, tokenized media URLs,
  private media metadata, or unredacted diagnostics. Diagnostic producers use
  fixed messages and normalized structured facts; never log raw exceptions,
  native messages, headers, or playback descriptors. Redaction is defense in
  depth. Preserve the credential and diagnostic contracts in
  [Architecture](architecture.md#implemented-now).
- Keep scheduling deterministic and pure. Cancel or reject stale network and
  playback results. Avoid blocking the UI isolate; measure before optimizing,
  then isolate CPU-heavy work and bound large guide/channel workloads.
- Use coherent conventional commits. Keep generated platform scaffolding with
  the feature that requires it, and do not mix unrelated cleanup.

## Verification by task

Choose the affected checks below; reuse still-current results under the rule
above. Native behavior and support claims retain their exact-commit physical
Windows requirements. Missing Windows evidence does not block unrelated
portable work; report the specific unverified behavior and required scenario.

| Task or evidence | Prerequisites and checks | What the result establishes |
| --- | --- | --- |
| Documentation only | `git diff --check`; check changed links, examples, and claims against their owners | Structural and source consistency; no new product or platform evidence |
| Dart policy, models, async work | Pinned Flutter SDK; focused tests plus the relevant full format/analyze/test checks below | Deterministic contracts; no Xcode application build or Windows engine provisioning required |
| Flutter layout, focus, semantics | Relevant widget tests at representative sizes; macOS for the two golden suites below | Flutter composition and input/semantics contracts; physical Windows input, AT, and video layering remain separate |
| Persistence or credentials | Controller/store/transport failure, rollback, scope-isolation, and secret-flow tests named in [Architecture](architecture.md#changing-asynchronous-and-persisted-state) | Deterministic recovery/currentness; OS credential storage and physical filesystem behavior need platform observation |
| macOS development app | Xcode and macOS setup below; `flutter run -d macos` or `flutter build macos` as relevant | Development UI/runtime or build evidence; the macOS player explicitly reports unsupported playback |
| Windows package policy | PowerShell 7.4+ on a portable host; `pwsh -File ./tool/windows/verify-release-policy.ps1` | Script parsing and pinned policy inputs; no Windows runtime or package execution proof |
| Native player contract / C++ integration | Dart adapter/coordinator tests, lifetime/currentness inspection, Windows C++ toolchain and prepared libmpv; `flutter build windows` | Contract and stock-engine compile/link proof; not a runnable or packageable Lineup player |
| Patched engine / portable package | Full Windows provisioning below; release wrapper and [package acceptance](windows-native-validation.md#8-portable-package-acceptance) | Artifact-bound build/package checks; launch, media, HDR, layering, fullscreen, input, and support claims require [physical Windows acceptance](windows-native-validation.md) |

## Portable commands

Flutter SDK `3.47.2` (revision
`d3b14c876900e553bc736ca19295fc09e3853e8e`, Dart `3.13.2`) is the reproducible
toolchain for macOS, Windows, and CI.

Select the exact Flutter checkout rather than a different SDK already on PATH:

```sh
git clone https://github.com/flutter/flutter.git /path/to/flutter
git -C /path/to/flutter checkout d3b14c876900e553bc736ca19295fc09e3853e8e
export PATH=/path/to/flutter/bin:$PATH
flutter doctor -v
```

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
TZ=America/New_York flutter test
```

From PowerShell on macOS or Linux, use:

```powershell
$env:TZ = 'America/New_York'
flutter test
```

Use `dart format <changed-paths>` when formatting is needed. The timezone above
is canonical for localized schedule goldens. On Windows, Dart uses the Windows
system timezone; `$env:TZ` alone does not select it. Run the portable Windows
tests in the machine's configured timezone, or set the OS timezone to Eastern
Standard Time before treating localized schedule assertions as canonical. The
full suite on Linux/Windows excludes the two suites marked `@TestOn('mac-os')`;
a pass there is not golden evidence. Run these on macOS when the affected UI
needs pixel verification:

```sh
TZ=America/New_York flutter test test/app/ui_acceptance_golden_test.dart
TZ=America/New_York flutter test test/app/guide_sparse_golden_test.dart
```

The equivalent commands from PowerShell on macOS are:

```powershell
$env:TZ = 'America/New_York'
flutter test test/app/ui_acceptance_golden_test.dart
flutter test test/app/guide_sparse_golden_test.dart
```

Inspect intentional golden changes from the real widgets. Preserve
[approved UI decisions](../.interface-design/system.md), including the protected
Player layouts and separate approval for structural proposals.

## macOS development app

For macOS application builds/runs, install Xcode and its command-line tools on
macOS 12 or newer. Resolve relevant Xcode/macOS warnings from `flutter doctor`;
those application prerequisites do not gate unrelated Dart checks. The
application currently targets macOS 12.0.

```sh
flutter config --enable-macos-desktop
flutter run -d macos
flutter build macos
```

## Windows native player

### Application compile check

Use the pinned Flutter SDK, Git, PowerShell 7.4+ (`pwsh`), Visual Studio Build
Tools 2022 with Desktop C++ and a Windows SDK, and 7-Zip. Prepare the ignored
x86-64 LGPL libmpv directory before configuring the application:

```powershell
Set-Location C:\path\to\LineupDesktop
$mpvRoot = 'C:\local\lineup-mpv' # New or empty directory.
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

After the one-time prerequisites and patched `host_debug` setup above, the
small PowerShell launcher reuses those exact local-engine outputs. Configure
the two machine-specific paths once as user environment values, and set them
in the current session as well:

```powershell
$engineSource = 'C:\path\to\flutter\engine\src'
$mpvRoot = 'C:\local\lineup-mpv'
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
$env:LINEUP_MPV_ROOT = 'C:\local\lineup-mpv'
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
Linux, the two golden suites and an application build on macOS, portable
PowerShell release-policy validation, and focused widget tests plus a
stock-engine C++/CMake application build on Windows Server 2022.

The expensive patched-engine/package job is conditional on engine and direct
package-policy inputs selected by `release-inputs`. Ordinary `lib/` or
`windows/` source edits alone do not select it. Manual workflow dispatch and an
unavailable comparison baseline also select the full job. When selected, it
verifies the pinned source/configuration/patch, builds `host_release`, invokes
the release wrapper, and exercises artifact/provenance/license/package rejection
checks. Inspect which jobs actually ran before describing a green CI result.
CI does not launch the application; runtime markers and native presentation
still require physical Windows acceptance.
