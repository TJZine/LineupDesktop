# Code-quality Windows validation handoff

Status: **F merged for testing; Windows validation and physical acceptance pending.
The full code-quality plan is not complete.**

## Candidate and authorization

Pull `origin/codex/code-quality-2026-10`. This contains all portable packages and
F, merged at `4f3b144a7989a0ba9f0096bf88bb265dd817bf7f` from candidate
`040e4a64bdc667bae9673d61a39a8d15261959c3`, over portable closeout
`952f321accfdc7b2e640f63938506023ba0acd75`. Later handoff/status-only commits
may follow that merge: record the **actual full pulled HEAD** as the tested
candidate and keep it fixed throughout the run. Do not test only the old F branch.

The human maintainer explicitly authorized this merge and branch push to enable
Windows testing (parent turn `01a140ff-2a77-7653-bb41-0da87984c434`, message
`01a140ff-2aab-79c1-825d-586b4d78550c`). This overrides the earlier unmerged-F
route, not its required tests. No main merge, PR, deployment/publication, default
branch change, unrelated deletion, persisted/wire format change, committed golden
update, macOS media implementation or additional product feature is authorized.

Read repository `AGENTS.md`, `.agents/project.md`, the code-quality plan's
Windows-testing override, §7.F and §10, `TRACES.md` T4, and `FINAL_REVIEW.md`
before execution. Current setup and safety authorities:

- [Development](../../DEVELOPMENT.md), especially patched-engine provisioning,
  current test tiers, development launcher and Windows timezone instructions.
- [Native acceptance](../../windows-native-validation.md), including operator
  approvals, privacy, exact-artifact identity and physical scenario procedures.
- [Open obligations](../../open-obligations.md), including W1–W12 and H's
  unexecuted PowerShell assertion. Older review findings are attributed history.
- [Execution record](EXECUTION.md), including retained proof and review outcomes.

## Preserve local work and select the branch

Inspect the existing Windows checkout first; never reset, clean, overwrite or
discard unrelated edits. Close any running Lineup instance normally. From the
repository root in PowerShell 7.4+, inspect before updating:

```powershell
git status --short --branch
git branch --show-current
git fetch origin codex/code-quality-2026-10
```

If the local task branch already exists and is suitable, use:

```powershell
git switch codex/code-quality-2026-10
git pull --ff-only origin codex/code-quality-2026-10
```

If it does not exist, use instead:

```powershell
git switch --track -c codex/code-quality-2026-10 origin/codex/code-quality-2026-10
```

Stop and reconcile local divergence or dirty work without destructive commands.
Confirm the merge is present and record the exact candidate:

```powershell
git merge-base --is-ancestor 4f3b144a7989a0ba9f0096bf88bb265dd817bf7f HEAD
if ($LASTEXITCODE -ne 0) { throw 'Windows-testing merge is missing.' }
$candidate = (git rev-parse HEAD).Trim()
git status --short --branch
New-Item -ItemType Directory -Force build/native-acceptance/code-quality | Out-Null
$candidate | Set-Content build/native-acceptance/code-quality/candidate.txt
```

Keep evidence under ignored `build/native-acceptance/`. The release build requires
a clean tracked tree and no non-ignored untracked files. Do not update the
checkout or let another agent/build mutate shared inputs during validation.

## Provision and identify the runtime

Use the current `tool/flutter_version.json` and
`tool/windows/build-metadata.psd1`; do not upgrade dependencies or substitute a
different engine/runtime. The inspected pin is Flutter 3.47.7, framework
`abaf9c523780a608bd46686fd5e53740a07077f8`, Dart 3.13.5.

Application prerequisites are Windows x64, MSVC 2022 Desktop C++, application
Windows SDK 10.0.26100.0 or newer, CMake, PowerShell 7.4+, prepared pinned libmpv,
and the Vulkan loader required by that runtime. Patched-engine provisioning has
its own pinned SDK 10.0.22621.0, ATL, Python and depot_tools requirements; follow
Development exactly. Existing patched outputs may be reused only after their
source, applied patch and metadata match the current pin.

Set `LINEUP_MPV_ROOT` to the existing verified prepared runtime, and
`LINEUP_ENGINE_SOURCE` to the matching Flutter `engine/src` directory. Select
that Flutter checkout's `bin` on PATH. Provision fresh destinations when inputs
changed; do not overwrite older runtimes. These machine-specific values are not
provided by the repository. Run:

```powershell
dart tool/check_toolchain.dart
flutter --version
flutter doctor -v
Get-TimeZone
```

Check exit codes and record actual OS timezone. `TZ` alone does not change Dart's
effective Windows timezone. Obtain operator agreement for any system timezone
change; follow Development when running canonical Eastern schedule tests.

## Build and run all four required F suites

First build/install the exact candidate with the pinned **patched release
engine** and prepared runtime. A stock `flutter build windows` result does not
satisfy the runner-lifecycle prerequisite or establish a usable player.

```powershell
pwsh -File .\tool\windows\build-release.ps1 -EngineSource $env:LINEUP_ENGINE_SOURCE
if ($LASTEXITCODE -ne 0) { throw 'Candidate release build failed.' }
cmake --build .\build\windows\x64 --config Release --target display_dynamic_range_test display_guardian_test native_player_contract_test runner_lifecycle_test
if ($LASTEXITCODE -ne 0) { throw 'Required native test build failed.' }
ctest --test-dir .\build\windows\x64 -C Release -N -R '^(display_dynamic_range|display_guardian|native_player_contract|runner_lifecycle)$'
ctest --test-dir .\build\windows\x64 -C Release -R '^(display_dynamic_range|display_guardian|native_player_contract|runner_lifecycle)$' --no-tests=error --output-on-failure --timeout 60
if ($LASTEXITCODE -ne 0) { throw 'Required native CTests failed.' }
```

Verify **four distinct tests are selected and pass**, with no skips, missing
targets or empty-selection pass. Serialize application builds, native target
builds, tests, Flutter checks, app instances and any shared generated outputs.
Retain build output, CTest `Testing/Temporary/LastTest.log`, per-suite results,
exit codes and durations in local evidence. Inspect/redact before sharing.

F's proof obligations include the compiled constexpr decision table and ordinal
assertions, live release L2/L3/L7 and failed Execute history, unchanged Reconcile
suspension, recovery return values/history edges, and the fixed 1,428-byte v1
journal fixture exercised through `display_guardian`. Source review alone has
not executed these assertions or parsed that fixture. Preserve live/durable
late-attempt distinctions, target/route identity, guardian/journal ownership,
command/load/stop/track correlation, bounded parsing and privacy. No format
migration or behavior correction outside accepted §2.2 is approved.

Run the existing PowerShell pin-consistency assertion from
`.github/workflows/ci.yml` as written; it was source-reviewed, not executed on
the macOS controller. Additional encoder, playback-state, authenticated-reference
and package-policy checks retain their separate obligations and prerequisites
in Development; these four F suites do not claim to cover them. Do not run an
unfiltered CTest set without provisioning all selected prerequisites.

## Physical acceptance and return contract

Only after all four required CTests pass, run the plan's W1–W12 scenarios with
the operator using the native-acceptance procedure. W4–W6 specifically cover
HDR hold/match/release, external HDR toggle and kill/restart restoration, and
display target changes. Keep each row PASS/FAIL/BLOCKED/NOT RUN separately;
unavailable hardware, media or Plex topology is a named limit, not a pass.
Obtain operator approval for disruptive fullscreen, display, crash or multi-monitor
steps. Do not automate system changes or expose credentials/private media.

Return a redacted report containing:

- Actual full candidate SHA, clean state before/after, exact commands, exit codes,
  selected test names/counts, durations, failures and local evidence paths.
- OS/build, actual timezone, MSVC/SDK/CMake versions; Flutter framework and Dart;
  patched-engine source/output identity and patch hash; prepared/copied libmpv
  hashes/provenance; installed executable, engine DLL and data/asset identities.
- Four F suite results and fixture execution, H assertion result, any additional
  checks actually run, and individual physical W1–W12 results with hardware,
  display/scaling and operator observations. No future-CI or simulated pass.
- Concrete failure/reproduction, suspected owner and smallest correction if
  necessary. Return consequential decisions to the controller. A repair changes
  the candidate and requires independent review plus affected retesting; do not
  silently fix, mark an old build green, rewrite proof, or commit golden updates.

The portable closeout at `476750d950744d6f22de99a170d4a6dfde4042d4` passed
format/analyze, 1,690 tests and a macOS release build. Those results are attributed
portable evidence, not Windows execution. F was independently source-reviewed
with no material finding. The merged composition and this handoff also passed
[independent review](IMPLEMENTATION_WINDOWS_HANDOFF_REVIEW.md). A fresh combined
portable gate at `32e68e4c44e831680ab661bc88a8d8dfd63e4104` passed the pin
check, format144/0changed, clean analysis and all 1,690 tests. Later status-only
commits do not change those inputs. **Merged, reviewed, compiled/tested and physically
accepted are separate statuses.** Keep F pending until observed Windows results
are reviewed and closure records updated; retain its recovery branch/worktree.
