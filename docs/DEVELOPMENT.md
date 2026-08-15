# Development

Lineup Desktop work normally moves through five activities in one session:

1. **Inspect** the current flow, its owners, tests, and platform constraints.
   Use `git show origin/initial-build:<path>` only when historical behavior is
   relevant.
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

## Quality and safety

- Test pure policies and public seams. Add widget/integration/manual proof when
  behavior depends on focus, accessibility, rendering, lifecycle, or native
  platform integration. Do not use brittle tests merely to increase coverage.
- Evaluate each dependency for current need, activity, license, desktop support,
  transitive cost, debuggability, and standard-library alternatives. Record
  material license obligations before shipping bundled native libraries.
- Never commit Plex credentials, authorization headers, tokenized media URLs,
  private media metadata, or unredacted diagnostics. Redact at the owner before
  values cross logging, UI, or export boundaries.
- Keep scheduling deterministic and pure. Cancel or reject stale network and
  playback results. Avoid blocking the UI isolate; measure before optimizing,
  then isolate CPU-heavy work and bound large guide/channel workloads.
- Use coherent conventional commits. Keep generated platform scaffolding with
  the feature that requires it, and do not mix unrelated cleanup.

## Commands

Flutter SDK `3.47.0` (revision
`4cf24164269a5ebf0c16a028a00727d0e77bbb05`, Dart `3.13.0`) is the reproducible
toolchain for macOS, Windows, and CI.

On macOS, install Xcode and its command-line tools on macOS 12 or newer, then
select the exact Flutter checkout rather than a different SDK already on PATH:

```sh
git clone https://github.com/flutter/flutter.git /path/to/flutter
git -C /path/to/flutter checkout 4cf24164269a5ebf0c16a028a00727d0e77bbb05
export PATH=/path/to/flutter/bin:$PATH
flutter doctor -v
flutter config --enable-macos-desktop
```

Resolve any Xcode/macOS warnings reported by `flutter doctor` before running
the repository commands. The application currently targets macOS 12.0.

```sh
dart format .
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter run -d macos
flutter build macos
flutter build windows # run on Windows
```

## Windows native player

The Windows player requires Visual Studio Build Tools 2022 with Desktop C++,
ATL, Windows SDK `10.0.22621.0`, Debugging Tools for Windows, and 7-Zip with
`7z.exe` on PATH. The pinned Flutter SDK is also the source checkout for the
owned engine patch:

```powershell
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git C:\path\to\depot_tools
git clone https://github.com/flutter/flutter.git C:\path\to\flutter
git -C C:\path\to\flutter checkout 4cf24164269a5ebf0c16a028a00727d0e77bbb05

$env:PATH = 'C:\path\to\depot_tools;C:\path\to\flutter\bin;' + $env:PATH
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

The patch must be applied to the exact revisions recorded in
`tool/flutter_engine/README.md`. Before configuring the application, prepare
the ignored x86-64 LGPL libmpv directory and set the required build variable:

```powershell
Set-Location C:\path\to\LineupDesktop
$mpvRoot = 'C:\local\lineup-mpv'
& .\tool\windows\prepare-mpv.ps1 -Destination $mpvRoot
$env:LINEUP_MPV_ROOT = $mpvRoot
```

Then select the resulting engine explicitly—do not replace Flutter's SDK
cache:

```powershell
$engineSource = 'C:\path\to\flutter\engine\src'
flutter run -d windows `
  --local-engine=host_debug `
  --local-engine-host=host_debug `
  --local-engine-src-path=$engineSource `
  --dart-entrypoint-args='--media=C:\path\to\sdr-sample.mp4'

flutter build windows `
  --local-engine=host_release `
  --local-engine-host=host_release `
  --local-engine-src-path=$engineSource
```

The preparation script verifies the archive SHA-256, generates an MSVC import
library from the DLL exports, and writes the runtime provenance record CMake
requires.

The preparation script pins and verifies zhongfly's x86-64 LGPL build from
release `2026-08-13-7b8915bc1d`. The asset is
`mpv-dev-lgpl-x86_64-20260813-git-7b8915bc1d.7z`, SHA-256
`13723530C3A719577A27EA19E0127175CE6A047071F8D988ADC1B0DD400B3D18`.
It contains mpv `v0.41.0-923-g7b8915bc1` configured with `-Dgpl=false`, FFmpeg
`N-126123-g8b4fad11a` configured without GPL components, and libplacebo
`v7.371.0` (`v7.360.0-111-g22ee762-dirty`). CMake verifies the archive identity,
header, DLL, redistribution marker, and locally generated MSVC import library
before linking.
See `docs/windows-runtime.md` for provenance and redistribution obligations.
The selected DLL also imports the Khronos Vulkan loader even when Lineup uses
D3D11 output, so test and package machines need a current GPU driver or Vulkan
Runtime that provides `vulkan-1.dll`.

CI runs on Windows Server 2022, bootstraps gclient from the pinned Flutter
checkout's official `engine/scripts/standard.gclient`, verifies that config's
blob plus the exact framework, engine, and patched source revisions, builds
`host_release`, and compiles the Windows application against that local engine.
It does not execute the application, so the runtime marker and DirectComposition
presentation still need Windows acceptance evidence.
