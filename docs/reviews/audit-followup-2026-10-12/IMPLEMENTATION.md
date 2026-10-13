# Audit follow-up implementation

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
| U1 | `01a13349-ea89-7112-8310-b2f8a1879a1c` | Implementing; shared Flutter verification reserved to controller |
| U2 | `01a13349-f3f1-7852-8c10-4c48a698d031` | Measuring baseline and implementing |
| U3 | `01a13349-ff6d-76b1-aa3e-21552cb0522d` | Measuring baseline and implementing |
| U4 | `01a1334a-126e-7522-bbcb-9054fbe721bd` | Implementing; owns isolated PowerShell fixtures |

U5 README now uses the canonical Git-owned formatter. The preceding audit ran
both commands without writing files: canonical 99 files/zero differences/exit 0;
old whole-directory recipe 176 files/seven ignored historical probes/exit 1.
The recipe change requires documentation/diff checks, not product tests.
