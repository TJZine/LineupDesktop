# Audit follow-up implementation

All seven accepted audit findings are implemented and committed. Final portable
acceptance passed: 1,492 tests, analyzer with no issues, canonical formatter,
and the actual PowerShell release-policy gate. No tests were removed.
The original unrelated working-tree files remain unchanged.

## Contract and source

Implement the seven accepted findings from the October 12 audit, including
measured before/after evidence for both performance risks. Preserve approved
behavior, UI, data and security contracts, and meaningful existing coverage.
No blanket test-suite reorganization, dependency upgrade, native media change,
push, merge or deployment is included. Use conventional commits by coherent unit.

Initial HEAD: `a6e5b500ff6c56799b540f5c33c7c9818a5089bb` on
`codex/desktop-ui-second-pass`, local `/Users/tristan/Software/LineupDesktop`.
The pre-existing October 7 review modifications and untracked historical/local
artifacts must remain untouched. Their hashes are recorded outside the repository
in `/tmp/lineup-audit-followup-2026-10-12/protected.json`. A frozen initial source
and package mapping for measurement is under that directory's `baseline/`.

Human authorization is in parent chat `01a13317-d9a7-7893-96ae-19078448b4a3`,
turn `01a13346-e326-74d3-aafa-3ad4053f1afc`, user message
`01a13346-e34d-7f01-9df3-ba16fc8b165d`: use orchestrate-implementation-chats
to implement the audit findings, measure/address performance risks, preserve
behavior/coverage, verify, use worker or worker luna, and create proper commits.
Children verify that original human message before callbacks. The controller owns
Git integration, review adjudication, shared runtime execution and acceptance.

## Units and ownership

| Unit | Executor | Write ownership | Required outcome |
|---|---|---|---|
| U1 lifecycle fixes | worker_luna, GPT-5.6-Luna xhigh | `lib/app/lineup_controller.dart`, `lib/ui/app_ui.dart`, `test/app/lineup_controller_test.dart`, `test/ui/clear_logo_image_test.dart` | Guard awaited Home results before publication; release delivered image handles; distinguishing regressions |
| U2 track projection | worker, GPT-6.1-Sol medium | `lib/playback/player_track_label.dart`, `player_view.dart`, focused track-label/player-view tests; focused new track benchmark if warranted | Normalize/disambiguate once per track snapshot; preserve all display/semantics/focus/selection behavior; measure 32/128/256 tracks |
| U3 setup projection | worker, GPT-6.1-Sol medium | `lib/app/channel_setup_view.dart`, a narrow feature-local projection owner if needed, `test/app/desktop_setup_test.dart`, focused new projection test/benchmark if warranted | Measure catalog projection work, remove repeated classification on presentation-only rebuilds, preserve all generated-plan semantics |
| U4 release authorities | worker, GPT-6.1-Sol medium | `tool/windows/package.ps1`, `build-inputs.ps1`, `run.ps1`, `build-release.ps1`, `verify-build-inputs.ps1`, `verify-release-policy.ps1`, one focused verifier/test file if useful | Shared version parsing and one pinned patched-checkout verifier, with executable positive/negative controls |
| U5 recipe and integration | controller | `README.md`, this record; integration only after writers stop | Correct formatter recipe; validate units, combined checks, commit each accepted unit |

Disjoint source writers may work concurrently. No child commits or broad format,
analyzer, Flutter test, pub-get, build, app or golden commands in the shared
checkout without an explicit controller runtime lease. Pure Dart benchmarks may
use their own temporary directories and explicit package mappings without pub;
PowerShell fixture checks may run in U4's own temporary output. Stop owned writes
before returning a ready-for-integration callback, with exact changed files and
reproduction/check commands. Controller will execute shared Flutter proof and
return bounded corrections to the same child. Do not spawn nested agents/chats.

## Decisions and distinguishing proof

U1: await `homeUsers` into a local, check `_isCurrent(operation)`, then publish.
Use the existing deferred fake handler to prove successful stale completion after
logout cannot repopulate profiles; retain account/stage/persistence assertions.
Copy logo dimensions and reliably dispose the delivered `ImageInfo`; listener
removal is a separate obligation. Cover synchronous cached and cold delivery,
replacement/unmount without adding a broad production testing framework. Keep
current fallback/alpha/crop/layout behavior and existing acceptance tests.

U2: prepare per-snapshot normalized facts and peer ambiguity information in the
existing presentation owner. Avoid a global cache and stale data; invalidate for
changed track facts, load/type and any true display input. Selection/pending state
must remain current without repeated whole-peer analysis on unrelated events.
Keep the single-track API if useful for real callers. Preserve exact primary,
secondary, compact, tooltip and semantics strings, region and title collision
rules, all 256 reachable rows, focus, Off and confirmed track selection.
Compare baseline and candidate for typical and worst-case same-region/unique-title
and mixed-region/type inputs at 32/128/256 tracks. Warm up, repeat, report median
and range, environment and output equality; no flaky wall-time assertion in CI.
Retain deterministic complexity/invalidation proof where it observes behavior.

U3: measure representative large synthetic catalogs (for example 10k/50k media,
multiple libraries/tags/playlists and all eight strategies). Separate baseline
classification/allocation costs and repeated unchanged rendering-equivalent work.
Own derived proposals/disabled eligibility at the feature boundary keyed by
immutable inventory and actual builder inputs. Presentation section changes must
reuse projection. Allocation choices, existing-lineup changes, source ordering,
grouping, variants, limits, specials and inventory replacement must invalidate
the appropriate stage. Keep commit/review anchors and generated schedule identity
semantics; do not freeze `DateTime.now` accidentally or create an isolate/framework
without evidence. Use existing builder/desktop setup tests plus focused projection
invalidation/equivalence evidence. Report measured scope honestly, not UI latency
from a pure function benchmark. No changes to the pure builder's product policy
or controller publication are delegated to this unit.

U4: package version and archive naming must use `Get-PubspecVersion`; exercise
commented/ordinary valid forms and missing/duplicate/nonnumeric rejection through
the consumed package input path. Consolidate identical patched-checkout validation
into one explicit shared owner: exact HEAD and engine.version, exactly permitted
tracked edit, normalized manager hash, reverse patch check, native command failure
propagation. Preserve all existing invocation timing around precache/build and
independent runtime/package hashes, dirty/reparse/artifact/license protections.
Use real temporary Git repositories and patch data for positive/wrong HEAD/wrong
engine/extra edit/wrong bytes controls, not source spelling or a new AST interpreter.
The existing temporary PowerShell runtime is
`/tmp/lineup-maintainability-powershell-2026-10-12/runtime/pwsh`.

## Acceptance and progress

Controller inspects each actual diff and obtains focused independent review for
substantive changes, adjudicating against source and tests. Run focused affected
Flutter suites on stable inputs, the canonical format check, analyzer and final
full portable suite once. Run the actual PowerShell release-policy gate. Recheck
protected pre-existing hashes and source identity. No golden baseline updates.
Windows native playback/HDR/input/package acceptance cannot be established on
this Mac; preserve the exact remaining platform checks. Record measurements,
commits, failures/repairs and remaining limits below as work completes.

## Dispatch and execution

| Unit | Child chat | Status |
|---|---|---|
| U1 | `01a13349-ea89-7112-8310-b2f8a1879a1c` | Accepted and committed as `4f6d163d`; distinguishing candidate/baseline regressions verified |
| U2 | `01a13349-f3f1-7852-8c10-4c48a698d031` | Accepted and committed as `d3175a3b`; 171 focused tests passed |
| U3 | `01a13349-ff6d-76b1-aa3e-21552cb0522d` | Accepted and committed as `ae45de96`; 85 focused tests passed |
| U4 | `01a1334a-126e-7522-bbcb-9054fbe721bd` | Accepted and committed as `6478cbf0`; portable policy passed |

U5 README now uses the canonical Git-owned formatter. The preceding audit ran
both commands without writing files: canonical 99 files/zero differences/exit 0;
old whole-directory recipe 176 files/seven ignored historical probes/exit 1.
The recipe change requires documentation/diff checks, not product tests.

Initial documentation/recipe commit: `5e277fe8`.

U1 controller-run focused suites reached 210 passes, then hung in the new cold
image-handle test. The exact process was interrupted and the same worker received
an exclusive lease for the logo suite to repair its asynchronous harness. This
interrupted run is not a pass. Independent review reuses audit chat
`01a13319-9254-72f0-a885-97e702afb259`, explicitly configured with worker/medium.

U4's actual portable PowerShell gate passed with real temporary Git/patch and
consumed package-version fixtures. The controller inspected its diff and log;
independent review reuses `01a13319-a570-7c70-9e0e-052d935c5bd1`, worker/medium.
That review returned no actionable findings after checking all seven source
identities, production invocation points and executable fixture controls. U4 is
committed as `6478cbf0` (`refactor(windows): unify release identity and engine validation`).
The worker observed the gate's exit 0; reviewer/controller inspected the success
markers and deliberate negative-control failures. Windows launch/package execution
is not established by this portable evidence.

U2's ordinary Dart benchmark encountered `language_code` importing `dart:ui`.
Substituting the dependency table is exploratory only. Acceptance measurements
will use the real production code and dependency in Flutter, with a controlled
runtime lease and the same baseline/candidate workload.

U1's repaired logo suite passed all four tests. The controller then ran the three
new stale-publication and cold/cached-image regressions successfully against the
candidate. Against an isolated copy of the original production code, all three
failed as intended: stale profiles republished after logout, cold delivery retained
one excess handle, and cached delivery retained two excess handles. The isolated
harness needed offline package configuration repair; its lockfile remained byte
identical. The initial native-assets harness error was not counted as regression
proof. Independent final review found no actionable issues and verified the repaired
source identities. Commit: `4f6d163d`.

U2 independent review found no actionable source issue. It confirmed live selected
state, label-input invalidation, exiting-overlay lifetime, and retained focused
coverage. Its timed mixed fixture distributes language regions across track types;
it does not establish same-language, same-type mixed-region timing. Separate
same-type region tests and independent single-API baseline comparison cover that
correctness obligation. Measurement claims concern label computation, not frames.

U3 independent review identified that sorting all strategies then filtering may
change tied proposal order because the existing builder sort is unstable. A
34-playlist same-title fixture was returned to the same worker for actual
reproduction and a repair preserving the original selected-strategy builder path.
The initial all-strategy-cache measurements are provisional and will not be used
as final candidate acceptance evidence after that repair.

## Track performance evidence

Observed on macOS arm64, Dart 3.13.5, in the actual Flutter test runtime using
production `language_code`. Baseline imports are frozen from initial HEAD;
candidate source matches the independently reviewed U2 hashes. One warmup and
three measured repetitions per workload; values below are milliseconds,
median [minimum–maximum]. Cold paths produce a whole list of labels. Reuse
includes cache validation and fetching every label. Each case compared primary,
secondary, compact, tooltip and semantics output exactly; all matched. The
separate included/omitted/empty-peer individual-API differential test also passed.
The benchmark command exited 0 with two tests passing.

| Fixture | Tracks | Baseline | Cold projection | Cached reuse |
|---|---:|---:|---:|---:|
| typical | 32 | 3.668 [3.424–4.610] | 0.968 [0.894–1.034] | 0.039 [0.038–0.040] |
| typical | 128 | 7.287 [6.760–9.019] | 2.400 [1.991–2.421] | 0.120 [0.108–0.137] |
| typical | 256 | 11.844 [10.976–14.729] | 4.789 [4.587–5.384] | 0.229 [0.228–0.235] |
| regional-titles | 32 | 132.264 [125.003–137.502] | 0.848 [0.771–0.946] | 0.010 [0.010–0.011] |
| regional-titles | 128 | 6285.932 [6255.734–6340.638] | 3.633 [3.490–3.803] | 0.078 [0.077–0.274] |
| regional-titles | 256 | 50907.255 [48071.661–53763.970] | 8.680 [7.863–9.245] | 0.126 [0.102–0.169] |
| mixed | 32 | 40.725 [38.185–41.021] | 0.629 [0.612–0.648] | 0.006 [0.006–0.006] |
| mixed | 128 | 2129.107 [1978.663–2229.468] | 3.101 [2.811–3.196] | 0.057 [0.037–0.060] |
| mixed | 256 | 15472.030 [15402.704–15701.229] | 9.122 [7.023–10.609] | 0.088 [0.086–0.102] |

Typical fixtures cycle `en/fra/deu/es` with no title. Regional-title fixtures
use `en-US` and distinct edition titles; mixed fixtures alternate audio/subtitle
and cycle `en-US/en-GB/pt-BR/es-419`, with distinct titles. All have two channels
and alternate AAC/FLAC. This measures synthetic label computation, not rendered
frame latency, production library prevalence, or AI token/cost savings. Three
samples and sequential old/new timing leave ordinary JIT/GC/host noise.
The production preparation now reuses normalized facts across peer comparisons;
view-owned snapshots reuse completed labels until display facts change, while
confirmed selection remains live. No isolate or global cache was introduced.

Reproduction harness and raw output are retained locally at
`/tmp/lineup-audit-followup-2026-10-12/u2/track_label_benchmark_test.dart` and
`u2/actual-benchmark.log`; the harness imports the frozen `baseline/lib` files
and candidate package. Command from this checkout:
`TZ=America/New_York flutter test --no-pub --reporter expanded /tmp/lineup-audit-followup-2026-10-12/u2/track_label_benchmark_test.dart`.
These temporary paths are execution evidence, not a new repository prerequisite.

U2 controller-run focused label/player-view suites returned 170 passes and one
failure in the new live-selection widget test: the restored selected-track label
was not visible after one pump. This run is not accepted. The same worker received
an exclusive narrow Flutter lease to diagnose the fixture or production cause,
preserve the observable selection assertion, and rerun the affected suites.
Production benchmark evidence is reusable only if its production inputs stay
unchanged. U3 continues independently with pure Dart reproduction and correction.

## Channel Setup performance evidence

Independent review's tied-order risk reproduced with actual Dart: 34 same-title
playlists selected alone put `p11` first; sorting all 35 proposals then filtering
put `p12` first and changed the result under a one-channel limit. The correction
caches the exact selected-strategy builder result and lazily caches each disabled
strategy's standalone proposals. It preserves the original sort behavior without
adding a new tie policy. The new regression covers 31–36 playlists and 128
strategy subsets (768 ordering and one-channel-limit cases), with pure Dart
correction controls passing. Shared Flutter acceptance passed: 85 focused projection, builder and setup tests.

Final corrected benchmark uses the same real builder and four-library synthetic
10k/50k catalog, tagged media, eight playlists and grouped sources. Dart 3.13.5
macOS arm64; three warmups, nine samples. Values are milliseconds,
median [minimum–maximum]. Cached column is **1,000 calls total**, not one call.

| Media items | Original repeated render work | Candidate cold render work | Candidate cached 1,000 calls |
|---|---:|---:|---:|
| 10,000 | 46.229 [42.028–56.268] | 43.500 [42.174–47.203] | 0.597 [0.465–0.947] |
| 50,000 | 308.543 [298.292–310.256] | 307.656 [299.215–325.331] | 0.423 [0.413–0.463] |

Cold rendering includes disabled-source classification/allocation. The measured
benefit is avoiding repeated unchanged projection work; cold-path cost remains
comparable. All 256 strategy subsets matched direct-builder channel facts and
eligibility under a fixed anchor, excluding intentionally fresh random IDs/seeds.
Unchanged previews retain their channel-list identity. These are pure computation
measurements, not Flutter frame timings, memory measurements or actual AI usage.

Durable benchmark: `tool/benchmarks/channel_setup_benchmark.dart`.
Reproduce with `dart --packages=.dart_tool/package_config.json tool/benchmarks/channel_setup_benchmark.dart`.
Raw corrected evidence and source hashes are under
`/tmp/lineup-audit-followup-2026-10-12/U3/`; `corrected-candidate.txt` supersedes
initial candidate timing claims. The frozen original baseline remains separately
recorded in `baseline.txt`.

## Integration results

U2's diagnostic established that after the first pump the coordinator already
confirmed track 2 while the displayed frame still showed track 1. A second pump
renders the naturally scheduled frame. The repair adds an explicit coordinator
assertion before that frame and retains the exact restored text, tooltip and
no-command assertions. The one regression and then both focused suites passed
(171 tests). No production change was needed, so the measured label code remains
valid. Controller reviewed this narrow test correction. U2 commit: `d3175a3b`.

U3 independent correction review accepted the exact selected-source cache and
closed the ordering finding, with no further actionable issue. Controller ran
projection, desktop setup and channel builder suites: 85 tests passed. U3 commit:
`ae45de96`. Existing widget/builder suites were retained unchanged.

The first full analyzer reported nine new diagnostics. Integration removed an
unnecessary test import, added missing braces, used stdout for benchmark reporting,
and made its measurement callback generic to accept both result-bearing and void
work. An intermediate void-only callback signature was rejected by the analyzer
and corrected; that failed analyzer run is not a pass. These changes do not alter
measured product algorithms or the benchmark workload. Integration style commit:
`7412c598`; benchmark signature correction is recorded in Git immediately after it.

## Final acceptance

All seven findings are resolved: bounded/reused track-label computation; released
logo image handles; guarded stale Home publication; shared package version
parsing; corrected formatter recipe; cached setup projection/disabled eligibility;
and consolidated pinned Flutter checkout validation. The implementation used one
worker_luna lifecycle chat and three worker chats for the substantive units, with
worker-configured independent review and controller-owned integration.

| Evidence | Observed result |
|---|---|
| `TZ=America/New_York flutter test --no-pub --reporter expanded` | Exit 0; 1,492 tests passed in 58 seconds |
| `flutter analyze --no-pub` | Exit 0; no issues |
| `dart tool/format.dart --check` | Exit 0; 102 files, zero changes |
| Actual `verify-release-policy.ps1` under the temporary PowerShell runtime | Exit 0; positive cases and deliberate violations exercised |
| Three new lifecycle regressions against isolated original production code | All fail for the intended stale-publication/retained-handle reasons; candidate passes |
| Actual Flutter track differential benchmark | Nine timed workloads and single-API controls pass exact output comparison |
| Setup corrected pure Dart benchmark and tied-order controls | All 256 strategy subsets and 768 tie/subset controls pass |
| `git diff --check` | Exit 0 |
| Protected pre-existing file SHA256 comparison | All 31 match initial hashes |

Full-suite execution started at `7412c598f274dfb7598c37e512b482faf1d8cd17`.
During that run only the standalone benchmark callback type changed, committed as
`4bfc392a406f7751dd0033077a90e2ddc424fe87`. Direct Git comparison confirms no
`lib`, `test`, pubspec, lockfile or analyzer configuration difference between these
commits. Final analyzer and format checks ran at `4bfc392a`; this concluding record
is a documentation-only commit. All product source remained stable during the
full suite. Source review and benchmark evidence carry forward through braces,
a redundant import removal and benchmark reporting/type changes only; no measured
algorithm or fixture changed during final integration.

The PowerShell gate was observed by its implementation worker and independently
reviewed by source identity and raw result. It has not been relabeled as a new
controller rerun. This Mac did not run Windows launch, production packaging,
native playback, HDR/composition, input or physical-device acceptance. Applicable
remaining checks are the exact pinned patched-SDK development/release launcher
and package flow on Windows, and the target-runtime scenarios in
`docs/windows-native-validation.md` when accepting those runtime claims.
No push, merge, publication, dependency migration or UI redesign was performed.

Changes reduce repeated computation and remove duplicated release authorities.
They make the affected paths simpler to investigate and verify, but actual AI
token/cost savings were not measured and are not claimed.
