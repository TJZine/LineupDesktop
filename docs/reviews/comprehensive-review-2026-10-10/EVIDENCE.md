# Evidence ledger — general review complete

Source and initial dirty-state hashes: INPUT_IDENTITY.json. Host/toolchain: ENVIRONMENT.json. Scope and human authorization: historical CENSUS.md, available in [Git history](../../README.md#historical-material-in-git). No finding is accepted solely from a reviewer opinion.

## Commands

All commands run from /Users/tristan/Software/LineupDesktop. Portable checks use pinned Flutter 3.47.6 framework 5fc346839b5d0eef006ed8404392afb4dfae428d, Dart 3.13.5. Full tests explicitly use TZ=America/New_York. Logs live under build/review-probes/2026-10-10-4fb77580/orchestrator-run/ (verified ignored before writing); ignored logs/probes do not travel with Git.

| ID | Command | Result / limits |
|---|---|---|
| E-001 | git status, rev-parse, branch; tracked SHA-256 census | Actual current checkout identified; two historical report modifications preserved. |
| E-002 | git ls-files, direct rg/files/line-count census | 424 tracked files; no index dependency. |
| E-003 | dart format --output=none --set-exit-if-changed . | Initial sandbox attempt could not write SDK engine stamp. Authorized escalation retry exit 0: 160 files, zero changes, 4.18 s. format-rerun.log. No formatting writes to source. |
| E-004 | flutter analyze --no-pub | Exit 0; No issues found; 1.9 s. analyze.log. |
| E-005 | TZ=America/New_York flutter test --no-pub | Exit 0: 1,364 tests passed in 95 s. Required Guide alpha file included in the full run; no separate duplicate alpha run. test.log. |
| E-006 | pwsh -File ./tool/windows/verify-release-policy.ps1 | Not run: PowerShell absent on PATH. Source inspection is not a substitute for its parser/execution. |
| E-007 | tracked-input hash recheck after format/analyze and during full suite | No tracked input changed from initial fingerprints. |

## Controller direct source/history inspections

- Bootstrap: main.dart and lineup_app.dart composition, --media parsing, unsupported macOS backend, startup Future.wait, native initialization/restore and disposal ownership. CLI is one media argument, not a server API.
- ScheduleWorker entire owner and existing test suite: spawn/send/exit error handling, controller reuse and disposal. Startup cancellation is now confirmed F-004 after E-008 and B calibration. Normal build control plus immediate/microtask/timer disposal permutations exercise the actual worker; no production algorithm was copied.
- Release policy source: PowerShell parser checks plus executable launcher path/argument checks; source grep alone does not prove whole release behavior. CI includes portable gate, macOS alpha/build, Windows widget/stock compile, policy job and conditional patched engine/package. No CI execution result inferred.
- Engine patch source: opt-in environment, clears marker, requests ANGLE DirectComposition, sets exact marker only after EGL success; static inspection only.
- Historical diffs read: 204e0648 controller transaction serialization; 3fc568d9 unique quarantine directory; 37416c1e abortable requests; 5598005e per-server PMS credential; 7dd76763 complete library pagination; 85aa6452 custom-preserving builder allocation; 7287db1c stable revision cache; 51900b52 bounded native stop; 9534b282 nested picker origin; 6b874f35 event-stable OSD/cursor timing; 02330deb semantic track activation; 4d2470c5 fatal playlist sibling abort; d816b53b artifact-bound provenance; d6fff072 reject later error in positive reference controls; 91b66b7e live-join EOF progress and cd2c08f6 continuation presentation readiness. These diffs explain seeds, not present defects.
- Authoritative current Windows requirements read: windows-native-validation, windows-runtime, windows-collaborative-acceptance-handoff. Existing smoke is dated and lacks exact candidate/runtime identity; no current physical pass claimed. Authenticated-reference, transcoding and HDR records remain scoped to their actual evidence.

## Historical disposition boundaries

October 7 report is frozen at 0382c131713174d9f8bced9d5b942855a99a6414; local edits include October 8 execution updates and must remain untouched. Current source includes later fixes. Scheduled continuation is implemented October 10; automatic fullscreen HDR and Plex transcoding are still plans. Known native buffering projection gap (old F15) is existing deferred work pending physical observation, not a new discovery. General review does not execute Prompt 2 or make system/account changes.

## Focused evidence and adjudication

All executions below are controller-owned, on the same pinned source/toolchain and TZ=America/New_York. Probes were written only after git check-ignore confirmed their ignored destination. Source/recipes and SHA-256 are preserved in [PROBES.md](PROBES.md); ignored logs do not travel with Git. Detailed reviewer evidence is preserved in the historical REVIEWER_A–E.md and CALIBRATION_A/C/E.md packets in Git. Reviewer agreement alone is not evidence.

Let SDK be /Users/tristan/.cache/lineup-flutter/3.47.6/flutter/bin/flutter and RUN be build/review-probes/2026-10-10-4fb77580/orchestrator-run. Each command below expands these paths, from repository root. Logs contain synthetic values only.

| ID | Exact command form / record | Result, controls, limitations |
|---|---|---|
| E-008 | TZ=America/New_York SDK test --no-pub RUN/worker_disposal_probe_test.dart | Initial worker-probe.log exit 1: const fixture compilation error, not product evidence. Corrected worker-probe-rerun.log exit 1: normal build passes, trial 152 Timer.run disposal does not settle within 1 s. Stronger worker-probe-5sec.log exit 1, 5 s: trial 131 does not settle. Complete source path proves missing settlement; race is nondeterministic. No permanent Guide hang claim. |
| E-009/E-010 | TZ=America/New_York SDK test --no-pub RUN/pin_recovery_probe_test.dart RUN/duration_probe_test.dart | pin-duration-probes.log exit 1: duration characterization (3) and no-saved-server PIN control pass; saved-server recovery expectation fails. Initial PIN fixture mounted onboarding alone; superseded by real-shell E-009 below. Numeric evidence remains valid. |
| E-009 control refinement | TZ=America/New_York SDK test --no-pub RUN/pin_recovery_probe_test.dart | pin-recovery-controls.log exit 1: adds successful Escape recovery control. Standalone onboarding phase is superseded by integrated shell below. |
| E-009/E-011 final | TZ=America/New_York SDK test --no-pub RUN/guide_input_probe_test.dart RUN/pin_recovery_probe_test.dart | guide-and-shell-pin.log exit 1: +1/-4 in 3 s. No-saved-server control passes; real-shell saved-server failure keeps PIN; Enter/Space menu expectations fail with tune callback; schedule completion trims search. Escape recovery passes before retained-PIN assertion fails. |
| E-012 setup attempt | TZ=America/New_York SDK test --no-pub RUN/multipart_probe_test.dart | multipart-probe.log exit 1: both cases fail before reaching part two because wall-clock join did not model intended start. Fixture problem, not a defect; replaced with existing frozen continuation fixture. |
| E-012 final | TZ=America/New_York SDK test --no-pub RUN/multipart_probe_test.dart RUN/pending_eof_probe_test.dart | playback-probes.log exit 1: +2/-2, under 1 s displayed. Complete timing control: loads 2→2, part 2, seek 40. Incomplete timing: loads 2→3, part 1, seek 40. Postcommit EOF control loads=2; synthetic precommit EOF loads=1 and ended intent retained. Former confirms F-007 owner logic; latter is only sequence susceptibility, CAND-009 remains HYPOTHESIS. |
| E-013 | Current source/contract traces, native and release owner reads | F-006: native ended producer, stopped/error-only harness terminal, no subsequent stop rescue. F-008: ancestry walker stops at packageRoot; build above omitted; build-release mutates marker/output before descendant inspection. No PowerShell/native execution. |
| E-014 | Five original reports + A/C/E followup packets and B independent worker calibration | PIN narrowed to precommit server failure; Guide/worker/duration/harness/multipart retained; path risk lowered to S3 LIKELY; EOF held as hypothesis. C independently challenged credential/publication no-findings, with documented compensation limit. All terminal work collected. |
| E-015 | Final tracked SHA-256/package-config/HEAD/branch reconciliation, artifact link/ID/source checks | See FINAL_IDENTITY.json and artifact verification record below. Product inputs and pre-existing tracked dirty reports unchanged. |

Intermediate preparatory attempts are explicitly not additional defect observations or successful acceptance. Passing duration characterization is not a passing requirement test. Green baseline and targeted failing probes are compatible because the existing suite omits these combinations.

## Primary API/platform evidence

- Pinned Flutter source in packages/flutter/lib/src/material/ink_well.dart, material/dropdown.dart and widgets/app.dart was inspected by C/A for Focus→Shortcuts activation ordering. [Flutter focus](https://docs.flutter.dev/ui/interactivity/focus) and [default shortcuts](https://api.flutter.dev/flutter/widgets/WidgetsApp/defaultShortcuts.html) support the propagation contract.
- [Widget.key](https://api.flutter.dev/flutter/widgets/Widget/key.html) and [State.mounted](https://api.flutter.dev/flutter/widgets/State/mounted.html) support keyed PIN child replacement and retired callbacks.
- [TextEditingController](https://api.flutter.dev/flutter/widgets/TextEditingController-class.html) supports programmatic editing-value updates; no observed IME claim.
- Dart 3.13.5 [ReceivePort.close](https://api.dart.dev/dart-isolate/ReceivePort/close.html), [Future.then](https://api.dart.dev/dart-async/Future/then.html), [DateTime](https://api.dart.dev/dart-core/DateTime-class.html) support readiness/projection reasoning; real pinned-runtime probes establish exact numeric behavior.
- [MethodChannel](https://api.flutter.dev/flutter/services/MethodChannel-class.html), [Completer](https://api.dart.dev/dart-async/Completer/Completer.html), [microtasks](https://api.dart.dev/dart-async/scheduleMicrotask.html) do not prove actual cross-direction Windows event/reply ordering.
- [Pinned mpv API](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/include/mpv/client.h#L1413) distinguishes EOF/external Stop and readiness.
- [Microsoft junction documentation](https://learn.microsoft.com/en-us/windows/win32/fileio/hard-links-and-junctions) supports directory redirection. The intended repository physical boundary and observed Windows outcome remain gated.

## Deliberately unexecuted

PowerShell policy (executable absent), Windows native CTests/build/package/engine, physical GPU/media/HDR/audio/composition/input/storage/credential behavior and live Plex account/scale are W-001–W-013. Optional visual goldens lacked a concrete review question and were not run. No new E2E framework was built. No CI job was inferred from definitions. No real credentials, private media or diagnostics were inspected.


## Final artifact verification

E-015: All 424 tracked SHA-256 values match initial inputs, including the two pre-existing dirty October 7 reports. HEAD/branch and resolved package config remain unchanged. All 117 local Markdown links resolve. F-001–F-008, P-001–P-007 and W-001–W-013 are unique and cross-reference valid IDs. git diff --check exits 0. New non-ignored output is confined to this review directory; disposable probes/logs remain under the verified ignored run directory. All reviewer and independent calibration reports are collected. No implementation or Windows execution was started.
