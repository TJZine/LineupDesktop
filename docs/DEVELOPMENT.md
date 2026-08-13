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
ATL, Windows SDK `10.0.22621.0`, and Debugging Tools for Windows. The pinned
Flutter SDK is also the source checkout for the owned engine patch:

```powershell
$env:PATH = 'C:\path\to\depot_tools;C:\path\to\flutter\bin;' + $env:PATH
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = '0'
$env:GYP_MSVS_OVERRIDE_PATH = 'C:\path\to\VisualStudio2022BuildTools'
$env:WINDOWSSDKDIR = 'C:\Program Files (x86)\Windows Kits\10'

Set-Location C:\path\to\flutter
gclient sync --no-history
git apply --unidiff-zero C:\path\to\LineupDesktop\tool\flutter_engine\0001-windows-direct-composition.patch

Set-Location engine\src
python .\flutter\tools\gn --runtime-mode=debug
ninja -C out\host_debug
python .\flutter\tools\gn --runtime-mode=release
ninja -C out\host_release
```

The patch must be applied to the exact revisions recorded in
`tool/flutter_engine/README.md`; run `git apply --check` first on a fresh
checkout using `--unidiff-zero`. Select the resulting engine explicitly—do not replace Flutter's SDK
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

Set `LINEUP_MPV_ROOT` to an uncommitted x86-64 libmpv development directory
containing `include\mpv\client.h`, `libmpv-2.dll`, and an MSVC-compatible
`libmpv.lib`. Shinchiro development archives contain a GNU import library; for
local development, generate the MSVC import library from the DLL exports with
Visual Studio's `lib.exe`. Do not commit or redistribute the DLL, import
library, or generated app bundle until the exact mpv/FFmpeg configuration,
source offer, notices, license obligations, and packaging policy are approved.

The development build used for this foundation is Shinchiro's official GitHub
release `20260421`, asset
`mpv-dev-x86_64-20260421-git-5921fe5.7z`, SHA-256
`9DCDA280322CFEC168D42F5AFA1A58691311E6AAF81B8A0DFDDFA97A6209A5FA`.
It reports mpv `v0.41.0-524-g5921fe50b`, FFmpeg
`N-124056-gc92304f8c`, and libplacebo
`v7.360.0-16-g409c9a8-dirty`. The upstream build does not pass
`-Dgpl=false`, so treat it as mpv's default GPLv2-or-later configuration. It is
acceptable for ignored local development here, not an approved redistributable
Lineup dependency.
