# Windows Native Acceptance Plan

**Status:** Procedure defined; full exact-commit campaign not yet executed.

**Owner-observed surface smoke (reported 2026-08-23):** the Windows native
Player, Classic PiP/Overlay presentation, and fullscreen work at a surface
level on the owner's system. This is useful evidence that the architecture is
viable and these paths are implemented; the tested commit, machine/display,
package identity, media set, and transition results were not captured. The
deeper campaign below remains the support/release record, not an urgent
precondition for continuing product-completeness work.

**Target branch:** `flutter-mvp`

This is the authoritative physical-Windows campaign for native presentation,
libmpv playback, focus/input integration, and portable packaging. It is a
procedure, not proof. A result is valid only for the exact commit, machine,
display configuration, runtime identity, and observations recorded in its
report.

## Exit criteria

Windows native acceptance is complete only when:

- the pinned patched Flutter engine is active at runtime;
- real Plex video is visible beneath Flutter in Player, Classic Guide PiP, and
  Overlay Guide;
- replacement tuning leaves one current player with no stale audio, video,
  events, or presentation lease;
- mandatory SDR, HDR, track, windowing, focus, recovery, and lifecycle scenarios
  pass on physical hardware;
- the clean portable package launches and plays outside the developer tree;
- provenance, licenses, system requirements, manifests, and hashes are present;
- shared evidence contains no credential or unnecessary private-media data; and
- every unresolved failure is classified as a release blocker or a bounded,
  explicitly unsupported limitation.

A successful build, CI run, or widget test does not satisfy these criteria.

## Responsibilities and safety

The physical-machine operator supplies credentials, protected-profile PINs,
private media, visual/HDR judgments, and approval for fullscreen, high-DPI,
multi-monitor, gamepad, and disposable-VM testing. The operator makes the final
release-gate decision.

Codex or another execution agent may inspect source, run the exact pinned build
and test commands, guide observable scenarios, collect redacted facts, and
produce the report. It must not merge, publish packages, rotate credentials,
alter drivers, disable security controls, or make opportunistic product changes.
A source fix requires a separate authorized implementation task.

Safety rules:

- Prefer a dedicated Plex test profile and non-sensitive test media.
- Never paste Plex tokens, authorization headers, tokenized URLs, or
  credential-store output into transcripts, issues, commits, or chat.
- Inspect and redact every log, screenshot, recording, crash detail, and path
  before sharing it.
- Store local evidence below `build/native-acceptance/`; it must remain
  untracked and disposable.
- Test a missing `vulkan-1.dll` only in a disposable VM or snapshot. Never copy
  that DLL from another machine into the package.
- Stop immediately if credentials appear in output or an unintended UI surface.

## 1. Define local paths

Start in PowerShell 7.4 or newer (`pwsh`) with the exact Flutter and pinned
`depot_tools` environment from [Development](DEVELOPMENT.md). Edit only these
values:

```powershell
$Repo = 'C:\src\LineupDesktop'
$FlutterRoot = 'C:\src\flutter'
$MpvRoot = 'C:\local\lineup-mpv' # Must be new or empty.
$SdrSample = 'C:\test-media\sdr-sample.mp4'
```

The machine needs Visual Studio Build Tools 2022 with Desktop C++, ATL, Windows
SDK `10.0.22621.0`, Debugging Tools for Windows, 7-Zip, Git, PowerShell 7.4 or
newer, Python, `depot_tools`, and the exact Flutter checkout documented in
[Development](DEVELOPMENT.md).

## 2. Establish a clean, exact baseline

```powershell
$ErrorActionPreference = 'Stop'
Set-Location $Repo

if (git status --porcelain) {
  throw 'Worktree must be clean before switching or updating the branch.'
}

$ExpectedFlutter = [IO.Path]::GetFullPath((Join-Path $FlutterRoot 'bin\flutter.bat'))
$ActualFlutter = [IO.Path]::GetFullPath((Get-Command flutter).Source)
if ($ActualFlutter -ne $ExpectedFlutter) {
  throw "flutter resolves to $ActualFlutter instead of $ExpectedFlutter."
}

git fetch origin
git switch flutter-mvp
git merge --ff-only origin/flutter-mvp

if (git status --porcelain) {
  throw 'Worktree must be clean before native acceptance.'
}

$Head = (git rev-parse HEAD).Trim()
$EvidenceRoot = Join-Path $Repo "build\native-acceptance\$Head"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

$Head | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'commit.txt')
flutter --version | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'flutter-version.txt')
flutter doctor -v | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'flutter-doctor.txt')

[ordered]@{
  testedAt = (Get-Date).ToString('o')
  windows = (Get-CimInstance Win32_OperatingSystem).Caption
  windowsVersion = (Get-CimInstance Win32_OperatingSystem).Version
  cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name)
  gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion)
  displays = @(Get-CimInstance Win32_DesktopMonitor |
    Select-Object Name, ScreenWidth, ScreenHeight)
  vulkanLoaderPresent = Test-Path "$env:WINDIR\System32\vulkan-1.dll"
} | ConvertTo-Json -Depth 4 |
  Set-Content -LiteralPath (Join-Path $EvidenceRoot 'machine.json')
```

Record the physical monitor model, resolution and scaling per monitor, HDR
capability/state, input devices, observed Plex connection type, and whether the
run uses a developer build or portable package. Review generated files before
sharing them.

## 3. Run deterministic checks

```powershell
Set-Location $Repo
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test

if (git status --porcelain) {
  throw 'Repository checks changed the worktree; resolve that before acceptance.'
}
```

All commands must pass on `$Head`; a pass on another SHA is not evidence.

## 4. Verify the pinned runtime and patched engine

Follow the one-time engine-provisioning procedure in
[Development](DEVELOPMENT.md). Do not substitute a framework, engine, patch,
`depot_tools` revision, libmpv asset, or hash.

```powershell
Set-Location $Repo
if ((Test-Path -LiteralPath $MpvRoot) -and
    (Get-ChildItem -LiteralPath $MpvRoot -Force | Select-Object -First 1)) {
  throw 'Set $MpvRoot to a new or empty directory before preparation.'
}
& .\tool\windows\prepare-mpv.ps1 -Destination $MpvRoot
$env:LINEUP_MPV_ROOT = $MpvRoot

$Metadata = Import-PowerShellDataFile -LiteralPath `
  (Join-Path $Repo 'tool\windows\build-metadata.psd1')

if ((git -C $FlutterRoot rev-parse HEAD).Trim() -ne
    $Metadata.FlutterFrameworkRevision) {
  throw 'Flutter framework revision does not match repository metadata.'
}

$EngineVersion = Join-Path $FlutterRoot 'bin\internal\engine.version'
if ((Get-Content -Raw -LiteralPath $EngineVersion).Trim() -ne
    $Metadata.FlutterEngineRevision) {
  throw 'Flutter engine revision does not match repository metadata.'
}

$PatchPath = Join-Path $Repo $Metadata.FlutterEnginePatchPath
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $PatchPath).Hash -ne
    $Metadata.FlutterEnginePatchSha256) {
  throw 'Flutter engine patch hash does not match repository metadata.'
}

& git -C $FlutterRoot apply --reverse --check $PatchPath
if ($LASTEXITCODE) {
  throw 'The exact repository-owned Flutter engine patch is not applied.'
}

$EngineSource = Join-Path $FlutterRoot 'engine\src'
if (-not (Test-Path -LiteralPath $EngineSource)) {
  throw 'Flutter engine source is not provisioned.'
}
```

Build both local-engine configurations when they are not already current:

```powershell
Set-Location $EngineSource
python .\flutter\tools\gn --runtime-mode=debug
ninja -C out\host_debug
python .\flutter\tools\gn --runtime-mode=release
ninja -C out\host_release
```

## 5. Local SDR smoke test

Use a non-sensitive local SDR sample before signing in to Plex:

```powershell
Set-Location $Repo
flutter run -d windows `
  --local-engine=host_debug `
  --local-engine-host=host_debug `
  --local-engine-src-path=$EngineSource `
  --dart-entrypoint-args="--media=$SdrSample"
```

Required observations: no engine-marker/libmpv error; visible video and audible
audio; play/pause and seeking; correct OSD stacking and focus; resilient resize,
minimize/restore, maximize, and fullscreen; and no retained
`lineup_desktop.exe` process after exit. Failure blocks the Plex campaign.

## 6. Plex end-to-end campaign

Launch without a local-media argument:

```powershell
Set-Location $Repo
flutter run -d windows `
  --local-engine=host_debug `
  --local-engine-host=host_debug `
  --local-engine-src-path=$EngineSource
```

Classify every row as **Pass**, **Fail — blocker**, **Fail — non-blocking**, or
**Blocked/not run**.

| Area | Mandatory scenarios and observations | Result |
| --- | --- | --- |
| Startup | Branded startup; no stock-engine fallback or native-init error | |
| Plex auth | PIN/QR success, expiration replacement, cancellation, protected-profile rejection/retry | |
| Server/state | Direct/relay description is truthful; retry/switch/clear works; relaunch is profile-scoped; logout stops playback and clears scope | |
| Authenticated redirects | Using a dedicated test credential and controlled endpoints, an authenticated HTTPS response redirects first to a different HTTPS origin and then, in a separate run, to HTTP; neither redirect target receives a request or token, and no credential appears in output | |
| Channels | Initial Builder review/apply is atomic; custom create/edit/delete validates and confirms destructive action; representative large lineup remains responsive | |
| Classic Guide | Focused/selected/tuned/airing identities remain distinct; time/paging/filter/now behavior works; real video occupies only the PiP aperture | |
| Overlay Guide | Real video remains beneath legible, interactive Flutter artwork, text, focus, and schedule | |
| Continuity | Player -> Guide -> Player preserves one session and restores focus | |
| Replacement tune | Guide and mini-Guide replacement leave no stale audio/frame/event, duplicate player, or retained lease | |
| OSD/transport | Verify default classic-TV OSD (transport hidden and Player-local pause/play/seek/stop/media shortcuts blocked), retained channel/tuning/tracks/sleep/menu/fullscreen input, then enable DVR playback controls and verify transport UI plus those shortcuts; include reveal/auto-hide | |
| Tracks | Audio selection matches output; subtitles select, render, and disable without hiding Flutter controls | |
| Input | Keyboard contracts pass; available remote/gamepad maps predictably and leaves every core control reachable | |
| Fullscreen/window | Enter/exit, continuous resize, minimize/restore, maximize/restore, route changes, and repeated stop/relaunch preserve geometry, focus, stacking, and lifetime | |
| Multi-monitor/DPI | Moving between monitors and changing scaling updates physical geometry with no second native window | |

Test at minimum `800x600`, `1280x720`, `1360x840`, `1600x900`, and
`1920x1080`, plus a 4K/high-DPI regime and 200% scaling when available.

For the authenticated-redirect row, use a dedicated Plex-compatible test
server or reverse proxy and credential. Configure the selected media response
to return, in separate runs, a redirect to a distinct HTTPS origin and a
redirect to an HTTP origin. Confirm the authenticated source endpoint was
reached but each redirect target's request count remains zero. Do not enable
header logging or place the credential in a command line, environment variable,
report, or screenshot. Repeat the scenarios from the portable package in
section 8.

## 7. Media acceptance matrix

Use only authorized media. Record Plex connection path, container, codecs,
resolution, frame rate, bit depth, dynamic range, audio, subtitles,
direct-play/transcode behavior, and observed native telemetry.

| ID | Minimum case | Required observation | Result |
| --- | --- | --- | --- |
| SDR-1 | H.264 8-bit 1080p SDR | Video/audio, seek, replacement tune, and fullscreen work | |
| SDR-2 | HEVC 10-bit SDR when available | Correct presentation without false HDR labeling | |
| HDR-1 | HEVC HDR10 on HDR display | Correct HDR/SDR state; no washed-out/crushed image; stable overlays/fullscreen | |
| DV-1 | Dolby Vision Profile 8 or DV with HDR fallback | Record actual fallback/output; infer nothing from metadata alone | |
| AUDIO-1 | Multiple audio tracks | Track selection corresponds to audible output | |
| AUDIO-2 | TrueHD and DTS/DTS-HD samples | Decode through libmpv to the system-selected output, normally PCM, without requiring passthrough; record actual channels/output telemetry | |
| SUB-1 | SRT and ASS/SSA text subtitles, embedded and Plex-managed external when available | Select, render styled/plain text, disable, and compose correctly | |
| SUB-2 | PGS and VobSub/image subtitles when available | Select, render, disable, and compose correctly, or receive an explicit classification | |
| OPEN-1 | Representative MP4/MKV/MPEG-TS and H.264/HEVC/AV1/MPEG-2/VC-1 inputs available to the operator | Original stream reaches libmpv without an application allowlist; record any actual demux/decode limitation rather than assuming universal support | |
| REMOTE-1 | Remote direct Plex stream | Start, seek, recover, and replace under realistic latency | |
| RELAY-1 | Plex Relay when intentionally available | Connection is labeled truthfully; performance is not generalized | |

The target is Plex-HTPC-like breadth through pinned libmpv/FFmpeg, including
native subtitle tracks and decode-to-PCM for lossless/surround audio. This does
not require browser codec allowlists, subtitle burn-in modes, or audio
passthrough. No finite matrix establishes “all formats”; preserve wording tied
to the pinned runtime and exact representative evidence.

## 8. Portable package acceptance

From a clean worktree and configured `host_release` engine build directory:

```powershell
Set-Location $Repo
$env:LINEUP_MPV_ROOT = $MpvRoot

& .\tool\windows\build-release.ps1 -EngineSource $EngineSource

$PackageDestination = "build\package\LineupDesktop-$($Head.Substring(0, 12))-windows-x64"
$PackageDirectory = Join-Path $Repo $PackageDestination
$PackageArchive = "$PackageDirectory.zip"
if ((Test-Path -LiteralPath $PackageDirectory) -or
    (Test-Path -LiteralPath $PackageArchive)) {
  throw 'Choose a new package destination or review and remove prior output.'
}

& .\tool\windows\package.ps1 -Destination $PackageDestination
Get-FileHash -Algorithm SHA256 -LiteralPath $PackageArchive |
  Format-List | Out-String |
  Set-Content -LiteralPath (Join-Path $EvidenceRoot 'package-sha256.txt')
```

Confirm:

- package creation reports no dirty-tree, runtime-hash, provenance, license, or
  forbidden-file failure;
- the archive contains the executable, required adjacent DLLs, `data`, licenses,
  `BUILD-INFO.txt`, `BUILD-PROVENANCE.json`, `SYSTEM-REQUIREMENTS.txt`,
  and `PACKAGE-MANIFEST.sha256`;
- `BUILD-INFO.txt` records `$Head` and `source-dirty=false`;
- `BUILD-PROVENANCE.json` records the same source commit, pinned framework,
  engine, patch, and hashes for the packaged build inputs;
- no debug/import artifacts, `dartjni.dll`, tokens, credentials, or private
  media are present;
- archive/package hashes are recorded;
- the authenticated cross-origin and HTTPS-to-HTTP redirect scenarios pass
  against this exact package without either redirect target receiving a request
  or token;
- mandatory SDR/Plex/Guide scenarios pass outside the developer tree; and
- the same package works in a clean Windows user profile or disposable system.

Test loader-absent behavior only in a disposable VM/snapshot. Record the actual
failure and guidance, install the proper GPU driver/runtime, and prove the same
package then launches.

## 9. Failure capture and classification

Before changing source for black/hidden/stale video or stacking failure, record:

- whether audio continues;
- Player, Classic PiP, or Overlay Guide;
- client size, monitor, resolution, scaling, fullscreen/window state, and the
  transition that preceded failure;
- intended logical and observed physical video rectangles when available;
- native-child visibility, clipping, and stacking, plus Flutter aperture
  opacity;
- synthetic channel/replacement/load-generation identifiers; and
- whether resize, route return, stop, or relaunch changes the symptom.

For crashes/hangs, record the Windows event entry, exception code, faulting
module, and minimal redacted reproduction. Do not commit a dump before review.

Treat these as release blockers unless stronger evidence proves otherwise:
stock-engine fallback; invisible real video in Player/PiP/Overlay; persistent
black frame; duplicate/stale playback or events; crash/deadlock/orphan/lifetime
corruption; secret or cross-profile leakage; unusable fullscreen/DPI/focus;
package failure on the supported baseline; incorrect provenance/licenses; or
materially incorrect HDR while the app claims HDR operation.

A limitation is non-blocking only when it is not claimed as supported, recovery
is clear, no security/data/lifetime risk exists, and a concrete revisit trigger
is recorded.

## Acceptance report template

Create `build/native-acceptance/<commit>/REPORT.md` locally. After redaction,
copy only the safe summary into the repository or pull request.

```markdown
# Windows Native Acceptance Report

- Commit, date/timezone, operator, build type:
- Windows, CPU, GPU/driver:
- Monitor(s), resolution, scaling, HDR state:
- Input devices:
- Flutter framework/engine and libmpv identity:
- Plex connection types:
- Package SHA-256:

## Summary

- Overall: Pass / Fail — blocker / Provisional
- Passed:
- Failed:
- Blocked/not run:

## Deterministic and build results

- flutter pub get / format / analyze / test:
- debug/release local-engine builds:
- package creation:

## Native observations

| Scenario | Result | Concise evidence |
| --- | --- | --- |
| Local SDR smoke | | |
| Plex authentication/recovery | | |
| Classic PiP / Overlay Guide | | |
| Replacement tune / lifecycle | | |
| Window / DPI / fullscreen | | |
| Input / focus | | |
| Media / HDR / tracks | | |
| Portable package | | |
| Authenticated redirect rejection | | |

## Blockers and remaining limitations

For each failure: reproduction, expected/actual, frequency, recovery,
security/data impact, and smallest evidence-backed owner. List unverified or
intentionally unsupported behavior without converting it into a support claim.

## Data review

Confirm all shared text and media were inspected and contain no tokens,
authorization headers, tokenized URLs, private paths, or unnecessary private
media metadata.
```

## Copy-ready Codex handoff

```text
You are working in TJZine/LineupDesktop on a physical Windows native-test
machine.

Required branch: flutter-mvp

Do not merge. Do not make product-code changes during acceptance unless a
separate implementation task explicitly authorizes them.

Read and follow AGENTS.md, docs/README.md, docs/DEVELOPMENT.md,
docs/architecture.md, docs/windows-runtime.md,
docs/windows-native-validation.md, and docs/guide-pip-composition-spec.md.

Fetch and fast-forward, report the actual HEAD, and require a clean worktree.
Use the exact repository-pinned Flutter framework, engine, DirectComposition
patch, depot_tools revision, and LGPL libmpv runtime. Substitute nothing.

Execute docs/windows-native-validation.md in order. Capture the redacted
machine/build baseline; run pub get, format, analyze, and all tests; verify and
build patched debug/release engines; run local SDR smoke; complete Plex,
channels, Guide/PiP/Overlay, Player, replacement, window/DPI/fullscreen,
focus/input, media/HDR/tracks, and lifecycle scenarios; build and validate the
portable package; then produce the exact-commit acceptance report.

The human supplies credentials, profile PINs, private media, visual/HDR
judgments, and approval for multi-monitor or disposable-VM tests. Never expose
or persist those secrets.

Classify every scenario as Pass, Fail — blocker, Fail — non-blocking, or
Blocked/not run. Compilation is not native evidence. On a blocker, preserve the
smallest reproducible evidence, identify the likely authoritative owner, and
avoid speculative architecture changes. Report changed files (ideally none),
commands and observed results, native evidence, blockers, remaining
limitations, and whether independent review is specifically recommended.
```
