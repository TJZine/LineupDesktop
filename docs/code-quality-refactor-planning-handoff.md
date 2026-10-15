# Lineup Desktop: code-quality assessment and planning handoff

Prepared October 15, 2026 for the maintainer to pass to an Opus 5.5 planning agent.

This is a detailed assessment and planning input. It records nine worthwhile
code-quality changes, their reasoning, current evidence, boundaries, migration
considerations, and verification obligations. It does not implement them or
claim that a replacement design has been validated. Proposed type and method
names below illustrate responsibilities; the planner should choose coherent
interfaces after tracing the relevant operations.

## 1. Original request and intended outcome

The maintainer's original request was:

> Any large refactor opportunities or code quality issues/things we can do to
> improve our repo to better align with pstack skills etc? not in workflow but
> actual code quality and best modern coding practices? utilize subagents to
> help where appropriate but ensure theyre tasks are scoped explicitely based
> on your insight and ideas

The follow-up requesting this document was:

> Please write me a detailed report alongside reasoning as well as what my
> original request was for me to pass to a planning agent (opus 5.5) to plan ALL
> of the changes you think are worthwhile and lead to a healthy codebase. this
> report needs to be detailed to save opus as much time as possible during the
> planning process

The intended outcome is a complete, evidence-led plan for the worthwhile
changes identified here. The focus is production code quality: responsibility,
domain modeling, asynchronous state, boundary validation, maintainability, and
appropriate verification. Workflow redesign, agent infrastructure, new product
features, visual redesign, dependency modernization, and platform migration were
not requested.

The assessment applied the shared `design-code`, `review-code`, and, for the
parser reproduction, `verify-code` guidance. No separate document named
`pstack` was identified or used as a technical authority. The operative
standards were cohesive ownership, small complete interfaces, explicit state
transitions, preserved behavior, and reduced caller coordination.

**Request to the planning agent:** plan all nine recommendations below. Include
the lower-priority improvements with appropriately small scope. Resolve the
remaining engineering choices; do not convert every illustrative class into a
mandatory abstraction. Where a narrower implementation achieves the stated
completion criteria, prefer it. If fresh source evidence invalidates a
recommendation, explain that explicitly rather than silently dropping it.

## 2. Source identity, investigation, and confidence

### Inspected state

- Repository: `LineupDesktop`.
- Checkout: `codex/desktop-ui-second-pass`.
- HEAD: `7afa3688bb58e6940871673d072cff77ee7ed5dc`.
- Assessment and handoff date: October 15, 2026.
- The assessment used the current working tree, including relevant uncommitted
  native changes. It was not a PR delta review or a comparison against `main`.
- Product source, tests, settings, dependencies, and existing documentation were
  not modified by the assessment. This handoff is the requested new document.

Pre-existing working-tree changes when the assessment was performed:

```text
 M .github/workflows/ci.yml
 M docs/DEVELOPMENT.md
 M docs/README.md
 M docs/architecture.md
 M docs/windows-runtime.md
 M pubspec.lock
 M tool/flutter_engine/0001-windows-direct-composition.patch
 M tool/flutter_engine/README.md
 M tool/windows/build-metadata.psd1
 M windows/runner/authenticated_reference_test.cpp
 M windows/runner/native_player.cpp
 M windows/runner/native_player_contract_test.cpp
?? docs/feature-opportunity-report.md
?? docs/feature-validation-findings.md
?? docs/opus-feature-research-request.md
```

The inspected native player/test diffs updated the required engine identity.
The CI, runtime, dependency, and separate feature-planning work is not owned by
this report. Recheck actual state before planning or editing; preserve these
changes and do not infer the target branch from its historical name.

### How the investigation was divided

The controller performed initial architecture/source reconnaissance, then gave
four read-only subagents explicit questions:

1. **Application transactions:** trace profile/server switching and
   channel/settings persistence; evaluate repeated commit bookkeeping and scan
   readiness ownership.
2. **Playback:** trace tune/replacement, track confirmation, stop/cleanup, and
   notification consumers; evaluate session ownership and publication coupling.
3. **Channel authoring:** trace draft, manual rundown, preview, review, and save;
   evaluate remaining domain logic in widgets after recent extractions.
4. **Native ownership:** inspect typed command/lifetime boundaries and display
   release/recovery; evaluate duplicated safety policy without assuming a native
   rewrite is necessary.

The controller investigated Plex parsing, resolution/scheduling starting points,
immutability and identity helpers, checked material agent findings against
source, and reproduced the parser issue using the actual parser.

### Evidence limits

- CQ-01 through CQ-08 are source-supported maintenance opportunities. No current
  user-visible failure was demonstrated for them.
- CQ-09 has a direct parser reproduction. The demonstrated outcome is a raw
  Dart type error; an application crash was not demonstrated.
- Existing relevant tests were inspected, not rerun during the assessment.
- No analyzer/full-suite result is claimed for this assessment.
- No Windows build, native CTest, packaged application, physical media, HDR,
  external display-change, or Windows input acceptance was performed.
- File length was used only to locate possible responsibility concentrations.
  It is not the justification for any recommendation.
- This was a focused architectural/code-quality assessment, not an exhaustive
  security, performance, supply-chain, or production-readiness audit.

Source line references describe the inspected state and may move. The symbols
and named behavioral tests are the more durable navigation aids.

## 3. Authorities and obligations the plan must carry forward

Read [AGENTS.md](../AGENTS.md) and the relevant sections of
[the project profile](../.agents/project.md). The most useful technical sources
are [architecture ownership and async/persistence contracts](architecture.md),
[development and verification](DEVELOPMENT.md),
[the approved interface system](../.interface-design/system.md), and
[physical Windows acceptance](windows-native-validation.md).

### Responsibility and platform constraints

- Flutter/Dart owns application policy, Plex coordination, channels, schedules,
  settings, navigation, focus, input, semantics, and visible interaction.
- C++ owns libmpv lifetime/commands, platform objects, display mechanisms, and
  native presentation. The native seam is justified by a real platform boundary.
- Windows is the native playback target. macOS is a development surface with
  explicitly unsupported native playback.
- Constructor injection and local state ownership are established strengths.
  Introduce a state-management dependency only for a demonstrated requirement.
- Approved Player/OSD/Now Playing and other visual decisions remain constraints.
  These refactors should preserve the product surface. A material departure
  needs its own design agreement and relevant real-Flutter evidence.

### Distinctions that must survive every refactor

| Distinction | Why it matters |
| --- | --- |
| Request currentness vs authorization lifetime vs committed content scope | Refreshing discovery does not necessarily invalidate active playback or a queued content mutation. Leaving and returning to the same identity must not revive old work. |
| Scheduled/current channel vs requested tune vs loaded program | Continuation, failed tune, rollback, live joining, and persisted selection have different authorities. |
| Requested track vs completed native command vs observed selection | Command acceptance is not proof that the requested track is active. |
| Native lifecycle generation vs load ID vs stop ID vs track request ID | Late events and acknowledgments must be rejected at the correct lifetime boundary. |
| Successful persistence vs runtime publication vs credential cleanup | Failed saves cannot look committed; credential cleanup has its own ordering and failure semantics. |
| Original display state vs attempted state vs verified state | A write may remain liable to complete late; an observation of the original state alone does not always prove safe resolution. |
| Plex media identity vs manual occurrence identity | Existing persisted manual programming can deliberately contain repeated media IDs with distinct snapshots/focus identities. |
| Explicitly off-air schedule vs failed/unavailable comparison | Repairability and authorization to save differ. |

The controller state-operation queue owns derive/snapshot/save/publication.
`FileAppStore`'s write queue only serializes file replacement. Credential writes
and logout cleanup retain separate ordering. Do not merge these into one
universal queue or cancellation token merely to reduce code.

Persisted decoding is strict. Keep compatible existing data valid, preserve
original bytes during recovery, and propagate migration/backup IO failures
correctly. These recommendations do not require a new persisted schema.

Keep credentials, token-bearing URLs, private media snapshots, raw exceptions,
and unredacted native diagnostics out of shared evidence.

## 4. Recommendation register

Priority describes expected engineering value, not an incident severity.
Scope/risk are qualitative judgments, not time estimates.

| ID | Recommendation | Priority | Likely scope / migration risk | Evidence |
| --- | --- | --- | --- | --- |
| CQ-01 | Cohesive scoped lineup state and explicit commit proposals | High; largest systemic benefit | Large / high | Repeated map assembly and manual save/publication protocol |
| CQ-02 | Scan state returns a validated subset commit candidate | Medium | Small–medium / medium | Controller reconstructs scan-owner invariants and reads rows directly |
| CQ-03 | Playback session owns active-program/load/recovery transitions | High | Large / high | Repeated nullable-tuple clearing and overlapping currentness checks |
| CQ-04 | Explicit playback reconciliation and deliberate observation state | High; useful bounded starting slice | Medium / medium–high | Notification performs policy and timer side effects; consumers filter independently |
| CQ-05 | Complete Studio draft ownership with a manual rundown model | High; strongest contained feature slice | Medium / medium | Widget owns domain edits, occurrences, undo, and snapshot reconciliation |
| CQ-06 | Explicit Air Check verification owner and outcomes | Medium–high | Medium / medium | Save authorization depends on rendering lifecycle and callback coordination |
| CQ-07 | Immutable setup-review snapshot and explicit review states | Medium; lower urgency | Small–medium / medium | Correlated plan/base/removal/phase/result fields and repeated derivation |
| CQ-08 | Shared native display-restoration classification | Medium; second wave | Small–medium first slice / high consequence | Live release and recovery separately encode safety decisions |
| CQ-09 | Consistent validation of optional Plex metadata shapes | High confidence; small correction | Small / low–medium | Reproduced `_TypeError` for malformed list-shaped metadata |

## 5. Detailed recommendations

### CQ-01 — Own committed selection/lineup state as one domain value

**Current mechanism and burden.**
[PersistedState](../lib/persistence/app_store.dart), starting at line 11,
contains separate selected-library, channel, and current-channel maps indexed
by profile/server. `LineupController.selectServer` reconstructs their related
values independently around lines 872–903. After saving, it manually retires
the old lifetime and publishes server, connection, credentials, libraries,
inventory, channels, current selection, stage, and generation around lines
904–934. Profile selection has a related protocol around line 747.

`_stateSnapshot`, around line 2268, copies and reconciles the nested maps with
separately held runtime values. Channel, scan, and settings changes participate
in the same commit owner but manually express their own derive/save/publish
steps and eligibility rules.

The issue is not that a controller is large. A new mutation or selection must
understand how related maps, runtime fields, save failure, cancellation controls,
and lifetime retirement fit together. That policy is easy to update partially.
Existing tests protect many cases, but the code still makes the implementer
coordinate the invariant.

**Recommended direction.** Model a scoped lineup value addressed by a
profile/server key. It should contain selected libraries, channels, and current
channel together, with meaningful lookup/replacement operations. Introduce
explicit selection proposals containing the candidate runtime publication and
persisted changes. Keep one application commit owner that derives from the
latest committed state inside the queue, persists, and publishes synchronously.

Named selection/content/settings operations should retain their distinct
eligibility. A generic callback-based transaction framework would hide the
important differences. Preserve independently ordered credential cleanup.

**Smallest credible implementation.** Keep `LineupController`; add private
proposal/value types and named publication functions, and scoped access/update
methods on `PersistedState`. A multi-controller architecture is not required.
The disk JSON can retain its current shape through boundary translation.

**Migration and deletion.**

1. Map the exact persist-before-retire behavior of one server selection.
2. Introduce its candidate value and publication operation while preserving the
   public controller API and serialized format.
3. Migrate profile selection, then applicable channel/scan state assembly.
4. Delete displaced nested-map copying and field-by-field publication policy.
5. Stop when callers express a meaningful operation without coordinating the
   internal map representation or commit sequence.

**Evidence to preserve.** In
[lineup_controller_test.dart](../test/app/lineup_controller_test.dart):
`cross-caller settings failure never becomes committed` (8008); the parameterized
selection-save tests starting around 8068; logout/in-flight commit tests around
8272; same-scope refresh with blocked delete/reorder/save around 8464; and queued
expected-base alias protection near the start of the file. Retain
[app_store_test.dart](../test/persistence/app_store_test.dart) compatibility,
failed-write, backup, and corruption/recovery coverage.

**Planning decisions.** Decide where the scoped value lives and how proposals
publish runtime state without moving credentials into ordinary UI state. Show
successful save, failed save, refresh-during-save, logout, and leave/return
traces. A wrapper around the existing maps without removing assembly policy
does not complete this recommendation.

### CQ-02 — Let scan state issue a validated commit candidate

**Current mechanism and burden.** The recent `_LibraryScanState` extraction
already owns attempts and retained readiness. However,
`LineupController._commitScannedLibraries`, around line 1030, checks readiness,
scope, selected IDs, and ready IDs itself; later rechecks identity inside the
state queue; reads `_scan.rows` to assemble media; and assigns scan status after
saving. The owner exposes mutable status/row-related state in
[library_scan_state.dart](../lib/app/library_scan_state.dart), starting at line 92.

The scan invariant therefore still spans both files. A caller needs to know
which readiness identity, content lifetime, and subset rows belong together.

**Recommended direction.** Have scan state produce an immutable selected-subset
candidate bound to its readiness identity and content lifetime. Illustrative
operations are `candidateFor(ids, lifetime)`, `isCurrent(candidate)`, and
`didCommit(candidate)`. The candidate carries the validated subset inventory
and relevant scan evidence. The application owner still decides whether required
channel sources are available, migrates schedules, persists, and publishes.

Keep request cancellation and HTTP abortion behavior intact. A readiness
candidate does not authorize an obsolete request to publish or make retained
evidence prove a source has disappeared.

**Migration and alternative.** Extend the current private class/`part`
arrangement first. Remove direct row/readiness/status coordination from the
commit path; a new public service or independent persistence queue is
unnecessary. Coordinate with CQ-01's commit proposal interface so scan state
does not acquire application transaction policy.

**Evidence to preserve.** Controller tests: returning to server A rejects old
readiness and late scan (around 952); exact subset persistence (1015); failed and
cancelled rescans preserve readiness (1038); cancellation/supersession (4711);
terminal restore failure (5105). Retain Plex IO cancellation tests because stale
result rejection alone does not prove connections are released.

**Completion criterion.** The controller can request, validate at commit time,
and commit a candidate without inspecting scan rows or rebuilding readiness
validity. Do not weaken lifetime checks to achieve this interface.

### CQ-03 — Give playback-session transitions a cohesive owner

**Current mechanism and burden.**
[PlayerCoordinator](../lib/playback/player_coordinator.dart) maintains active
playback authorization/request, active channel, loaded/resolving program,
native load, multipart durations, authorization recovery, and cleanup state
across many fields. In `_performTune`, approximately lines 729–820, the same
request/channel/program tuple is cleared in multiple branches, while generation
and identity checks surround native loading and persisted current-channel
publication. Multipart seek/recovery branches around line 1282 and retirement
around line 1952 coordinate related facts separately.

Local `_PlaybackLoad` and `_AuthorizationRecovery` objects are useful existing
steps. They do not yet make the active-session invariant authoritative in one
place. Adding a transition still requires understanding every clearing,
publication, supersession, and stop path.

**Recommended direction.** Keep `PlayerCoordinator` as the application/UI facade.
Group the active request, channel context, and program into one meaningful value
whose construction rules reflect actual transitional states. Give a session
owner explicit tune/load/seek/recovery/retirement operations and ownership of
their currentness/cleanup invariants. Keep persisted channel changes in the
controller's transaction boundary.

This is not a proposal for one enormous union containing overlays, sleep timer,
display state, transport, and every asynchronous operation. Independent
lifetimes must remain independent. Track confirmation could separately use an
operation value that contains its requested type/ID, timer, and correlation
identity instead of coordinating those fields by convention.

**Smallest credible first slice.** Introduce an active-program value and central
transition methods in the existing file. Extract a separate owner only if the
result hides meaningful coordination. Merely moving helpers to a new file would
leave the problem intact.

**Migration and deletion.** Sketch tune → native load → saved current-channel
commit → winning/superseded cleanup. Migrate that path, then multipart seek and
authorization recovery, then remaining retirement paths. Remove old parallel
fields/checks when the new owner expresses their invariant. Preserve facade
behavior so UI migration does not become a simultaneous redesign.

**Evidence to preserve.**
[player_coordinator_test.dart](../test/playback/player_coordinator_test.dart):
superseded tune cannot seek or replace the winning request (3726); replacement,
Stop, and scope invalidation coalesce preemption (around 4005); multipart and
part-transition authorization recovery (including around 5851); native stop
failure/timeouts; live-join EOF accounting; continuation readiness; current-
channel persistence failure; and two-stage track confirmation (2209).

**Planning decisions.** Define when a session is resolving, loaded, committed,
retiring, or failed without inventing exclusivity between facts that can
legitimately overlap. Show how a pending seek updates/reuses an in-flight part
load, and who owns stop liability after a failed or superseded operation.

### CQ-04 — Make playback reconciliation explicit and publication predictable

**Current mechanism and burden.** `PlayerCoordinator.notifyListeners`, around
line 285, invokes `_updateDisplaySession` and manages busy-indicator timers
before notifying. `DisplayMatching.updateSession`, around line 63 in
[display_matching.dart](../lib/playback/display_matching.dart), can send native
requests and finish/resume a hold. Display changes also call back into the
coordinator's notification entry point.

Consequently, a method conventionally understood as publishing state also
executes policy. Callers need to know this hidden responsibility. Observation
is also broad: `_eventVisibleFacts` coalesces coordinator publication, the shell
compares `_shellPlayerFacts` around line 98 in
[lineup_shell.dart](../lib/app/lineup_shell.dart), and `PlayerView._changed`
performs focus/transition bookkeeping and rebuilds around line 84 in
[player_view.dart](../lib/playback/player_view.dart).

**Recommended direction.** Establish explicitly named policy reconciliation
and busy-state transition operations. Ordinary notification should publish
state without initiating media/display commands or owning timer transitions.
Then define stable observation state for actual consumer needs: playback facts,
presentation facts, and diagnostics are candidates. Use narrow listenables only
where they remove duplicated consumer filtering or measured unnecessary work.

**Alternative and cost control.** Keep one notifier initially and name the
reconciliation boundary. Multiple notifiers, selectors, or a new state package
are not prerequisites. There is no measured frame-time regression in this
assessment; do not promise a performance improvement without measurement.

**Migration.** Trace cursor-only, progress-only, tune, fullscreen, route visibility,
and display-report events. Specify which operations reconcile policy and which
facts publish immediately. Preserve the callback ordering needed for HDR holds.
After moving side effects, migrate observation consumers only where the new
contract removes their bookkeeping. Coordinate with CQ-03 because both edit the
coordinator; avoid concurrent conflicting writers.

**Evidence to preserve.** Position publication remains bucketed at 250 ms while
seek/recovery coordinates stay exact (`player_coordinator_test.dart:1332`).
Retain HDR hold/session, OSD deadline, cursor/focus, Now Playing preservation,
Player widget, shell navigation, and native adapter tests as applicable. A
notification refactor must not reset OSD deadlines on repeated native facts.

**Completion criterion.** A reader can distinguish a state transition, policy
reconciliation, and publication from the method contract. Consumers obtain their
required state without duplicating a growing list of coordinator internals.

### CQ-05 — Complete Studio draft ownership with a manual rundown model

**Current mechanism and burden.**
[ChannelStudioDraft](../lib/app/channel_studio_draft.dart) already owns source
projection, dirty tracking, and schedule identity. The remaining manual rundown
lives in [ChannelStudioViewState](../lib/app/channel_studio_view.dart):

- `_ManualEntry`, occurrence counters, `_manualEntries`, and undo records around
  lines 35 and 126.
- Draft signature inputs around line 312.
- Add, batch-add, captured inventory fallback, and undo around line 2019.
- Several move/remove paths around line 2443.
- Fresh-inventory substitution for preview/save in `_manualItems`, around 2815.
- Copying every committed occurrence snapshot back into widget records after
  save, around 3033, before accepting the draft baseline.

The domain state is split between draft and widget. Every editing/save path must
preserve the relationship between retained snapshots, refreshed metadata,
repeated occurrences, undo, dirty identity, and baseline acceptance.

**Recommended direction.** Put a small manual-rundown owner under the draft. It
should own ordered occurrences and add/move/remove/undo operations, resolve
against current inventory, and reconcile saved snapshots. Return enough result
information for the view to choose the next focus target. Keep focus nodes,
scrolling, dialog state, browsing selection presentation, and accessibility
announcements in Flutter.

Keep occurrence identity distinct from media identity. Preserve existing
differences between single addition, batch selection deduplication, and repeated
persisted IDs. Do not impose one blanket deduplication rule as part of cleanup.

**Alternative.** Extracting a rundown widget alone improves navigation through
the source but leaves dirty/projection/save reconciliation shared. A domain
owner earns its cost by removing that coordination. It need not become a general
undo framework or reusable collection library.

**Migration and deletion.** Move record ownership and domain operations first;
adapt existing widget callbacks and stable keys; move inventory/saved-snapshot
reconciliation; remove widget mutation paths. Preserve tests through the
public behavior while moving pure ordering/identity cases to the domain seam
only when their proof is retained.

**Evidence to preserve.**
[channel_studio_view_test.dart](../test/app/channel_studio_view_test.dart):
inventory refresh permits clean revert (1505); selection metadata survives
inventory loss (2636); repeated persisted IDs retain occurrence focus/snapshots
(3002); save refreshes every retained snapshot (3379); conflict reload retires
occurrence focus ownership (3482). Keep
[channel_studio_draft_test.dart](../test/app/channel_studio_draft_test.dart)
projection/dirty/schedule tests. Domain tests cannot replace focus/semantics
observations.

**Completion criterion.** The widget sends editing intentions and consumes
results; it no longer maintains domain records or manually repairs their
baseline after save.

### CQ-06 — Give Air Check verification an explicit state owner

**Current mechanism and burden.**
[ChannelAirCheck](../lib/app/channel_air_check.dart) owns debounce, active/latest
pending requests, preview/error, original schedule and several parallel keys,
baseline failure/off-air state, and validity in its rendering `State`. Important
transitions begin around lines 126 and 211. `_reportValidity`, around line 396,
posts a frame callback to Studio. Studio separately checks the status snapshot
against its current draft/content generation around line 2966 and gates saving
around line 2988.

Save authorization therefore crosses a child widget lifecycle and a duplicated
parent validity handshake. The current checks are deliberate and tested; this
is an ownership burden, not a demonstrated stale-save bug.

There is also a timing handshake that must migrate with validity:
`ChannelStudioView.build` calls `_stageScheduleIdentity` around line 375;
the accepted validity callback calls `_commitScheduleIdentity` around line 494;
and Save requires both current validity and `scheduleIdentityCommitted` around
line 3012. `ChannelStudioDraft.stageScheduleIdentity` and
`commitScheduleIdentity`, around lines 277 and 283, stage one UTC anchor/seed,
then commit those exact previewed values while updating the dirty baseline.
Moving only the validity callback would leave part of save authorization tied
to rendering and could cause the verified schedule to differ from the saved one.

**Recommended direction.** A local Air Check session/controller should own the
verification lifecycle and expose revision-bound results. Model baseline
outcomes explicitly: loading, available, explicitly off-air, failed. Keep the
distinction between comparison readiness and current draft validity. Supply the
existing schedule loader and clock, and retain the bounded active/latest-pending
behavior and stale suppression.

Studio and the Air Check view should observe the same verification result. The
widget continues to own layout, artwork, synopsis expansion, and selection
presentation. Coordinate the draft identity and staged schedule-timing contract
with `ChannelStudioDraft`; do not create another scheduler or source resolver.
Use explicit draft-update/verification transitions to stage timing and commit
the exact verified candidate outside `build`. Preserve existing saved timing,
one-time fresh candidate creation, save-as-new candidate retirement, and the
current rules for retaining schedule version/transition metadata.

**Smaller alternative.** Replace correlated baseline fields with a sealed
outcome while retaining widget ownership. The preferred full extraction should
earn its cost by removing the parent/child status-and-timing handshake. If a
proposed extraction only relocates that handshake, choose the smaller model.

**Migration and evidence.** Transfer transitions intact before simplifying.
Retain [channel_air_check_test.dart](../test/app/channel_air_check_test.dart):
one active/latest pending (297); same-key recovery (329); generation/retry/
disposal rejection (354); stale visible preview (752); retry establishes original
comparison (1097); off-air original repair (1190); generation refresh order
(1224). Studio tests protect stale validity (3690), unavailable worker (4221),
failed baseline comparison (4251), and repairable off-air programming (4316).
Also retain the exact preview-anchor/seed persistence tests around 3579 and the
stale valid/retained-off-air identity tests around 3690 and 3760, plus all three
draft tests for pure projection, staged timing, and save-as-new/reload.

**Completion criterion.** The matching verification result and committed
schedule identity together authorize Save, including the exact anchor/seed that
was verified, independently of whether the preview widget has rendered another
frame. An unavailable or failed comparison remains distinguishable from explicit
no-content, and cannot silently become save permission.

### CQ-07 — Materialize setup review as an immutable snapshot

**Current mechanism and burden.**
[channel_setup_view.dart](../lib/app/channel_setup_view.dart), starting at line
43, combines an integer step, nullable plan, captured review base, mutable removal
choices, phase, and separately captured applied entries. `_prepareReview`
(around 2479), `_applyReview` (3249), and `_reviewEntries` (3475) coordinate these
fields and repeatedly derive final composition/differences.

The review is a meaningful domain snapshot, but its representation relies on
widget transition conventions and `_plan!`. This is a lower-priority improvement
because transitions are bounded and already covered.

**Recommended direction.** Introduce a review value containing the expected
base, freshly materialized plan, mode, removal choice, final composition, and
computed differences/counts. Updating removal choice can produce a new review
value. Use explicit review/applying/failed/completed state so required plan and
result data travels with its phase.

Continue calling existing `composeChannelPlan` and
`LineupController.applyReviewedChannelPlan` (around line 1496). The controller
remains the authority for queued expected-base comparison and persistence.
Keep configuration preview caching in `ChannelSetupProjection`; review must
materialize with a fresh anchor rather than commit a cached preview schedule.

**Migration and evidence.** Move review derivation, adapt prepare/apply/result
rendering, and remove synchronized field assignments and duplicate calculations.
Preserve stale-apply rematerialization and renewed removal confirmation. Retain
[desktop_setup_test.dart](../test/app/desktop_setup_test.dart) tests at 1029
(removal confirmation reset) and 1509 (stale apply refreshes review and requires
another apply), plus
[channel_setup_projection_test.dart](../test/app/channel_setup_projection_test.dart)
ordering/invalidation coverage and builder/controller apply tests.

**Completion criterion.** Review rendering and apply consume one explicit
review snapshot, while configuration preview, review materialization, and
persisted application retain their separate timing and authority.

### CQ-08 — Share native display-restoration classification

**Current mechanism and burden.** Normal release in
[display_dynamic_range.cpp](../windows/runner/display_dynamic_range.cpp),
`DisplayMatchingEngine::Release` around line 423, classifies unknown observation,
unresolved late attempt, original state, and external state before restoration
and guardian disarm. `IsOurState` around line 121 checks attempted/verified state.
Crash recovery independently classifies related histories in
[display_recovery.cpp](../windows/runner/display_recovery.cpp),
`RestoreDisplayOwnership` around line 246.

The live `Record`, around line 116 in
[display_dynamic_range.h](../windows/runner/display_dynamic_range.h), combines
ownership data with `owned`, `guardian_lost`, `unobserved_attempt`, guardian
presence, failure intent, and write revision. Start/write/reconcile/suspend/
release coordinate these fields. Changes to late-write safety require comparing
both paths and their different available history.

**Recommended first slice.** Extract a pure restoration classifier with explicit
inputs and outcomes such as unresolved, already original, external change, or
restore original. Use it in live release and recovery. Prove which history is
available to each caller; do not assume `unobserved_attempt` is interchangeable
with the recovery record's attempted/verified comparison in every state.

Keep side-effect execution separate: live release has queued-restart/guardian
sequencing; recovery has cross-process admission and journal identity fencing.
Preserve journal and guardian wire formats initially.

**Larger option, only if justified.** If the classifier exposes substantial
repeated transition bookkeeping, introduce a per-target ownership model with
record-attempt, observe-attempt, and protection-lost transitions. Keep session
eligibility and target remapping separate. Convert internal string states to
enums where this clarifies the touched model, translating to wire strings at
the boundary. A generic RAII or enum-conversion campaign would not resolve the
identified burden by itself.

**Migration and evidence.** Derive a transition/decision table from existing
tests, migrate both classifiers, and delete duplicate predicates. Preserve
[display_dynamic_range_test.cpp](../windows/runner/display_dynamic_range_test.cpp)
late/failed writes, external changes, restart inheritance, target loss/recovery,
and protection loss. Preserve
[display_guardian_test.cpp](../windows/runner/display_guardian_test.cpp)
`RestoreCases` around line 46 and process fixtures in
[display_admission_process_test.cpp](../windows/runner/display_admission_process_test.cpp).
Confirm actual target wiring: the process-fixture source does not imply a CTest
target of the same filename. Add only missing classification cases that exercise
distinct live/recovery histories.

Physical Windows validation remains necessary for HDR changes, external setting
changes, abnormal exit/restart, target remapping, and bounded close for a changed
candidate. Controlled native tests do not establish physical display behavior.

**Completion criterion.** Both execution paths obtain restoration classification
from one explicit policy, while retaining their own required sequencing and all
uncertain late-write liability. A new durable-state requirement would require an
explicit journal-version/migration decision.

### CQ-09 — Normalize malformed Plex metadata at the decoding boundary

**Reproduced mechanism.**
[plex_client.dart](../lib/plex/plex_client.dart), `parseMediaItem` around line
1576, directly casts `Media`/`Part` to nullable lists. `_tagNames` around line
1657 and `_castMembers` around 1677 cast optional metadata collections similarly.
These casts validate neither the list shape nor the intended failure contract.

A temporary script outside the repository imported the production parser and
used this input shape:

```dart
final base = <String, Object?>{
  'ratingKey': 'synthetic',
  'title': 'Synthetic',
  'type': 'movie',
  'duration': 1000,
};

parseMediaItem(base); // accepted
parseMediaItem({...base, 'Genre': 'unexpected'}); // _TypeError
parseMediaItem({...base, 'Role': <String, Object?>{}}); // _TypeError
parseMediaItem({...base, 'Media': 'unexpected'}); // _TypeError
```

The probe ran successfully with Dart 3.13.5 on `macos_arm64`, using the existing
`.dart_tool/package_config.json`. The `dart` executable resolved from the local
Flutter cache directory named `3.47.6`; this is a parser observation, not a claim
that the pinned Flutter 3.47.7 acceptance toolchain was selected. The temporary
script was removed automatically. No repository test file was added.

**Consequence.** `libraryItems` calls this parser for each row without per-row
recovery. The controller catches scan failures, so an app crash is not
established. The demonstrated defect is that malformed external optional
metadata escapes as an unclassified Dart type error and can fail the library
scan. Playlist scanning has its own catch/failure behavior; do not infer that
every caller crashes or has the same result.

**Recommended direction.** Establish consistent shape decoding at this actual
external boundary. Required identity/structure should fail with a typed, safe
`PlexException`. Optional descriptive enrichment should use deliberate fallback
where consistent with existing behavior. In particular, distinguish malformed
optional tags/cast from malformed media structure: dropping descriptive data and
retaining an unplayable item are different outcomes.

**Planning decisions.** Decide and document the field-category policy rather
than blanket-catching all errors. Preserve omitted-field behavior, ordered
parts, nullable durations, bounded cast, canonical artwork paths, numeric
tolerance already covered by tests, and useful strict validation. Do not catch
unrelated programming errors and disguise them as empty metadata.

**Migration and evidence.** Add focused malformed-shape cases to
[plex_parser_test.dart](../test/plex/plex_parser_test.dart), using the existing
real parser fixtures. Cover null/missing, wrong scalar/object/list shape, and
malformed elements where their behavior differs. Keep a valid control. Exercise
[plex_library_scan_test.dart](../test/plex/plex_library_scan_test.dart) and
[plex_transport_test.dart](../test/plex/plex_transport_test.dart) where needed to
show the public failure/fallback contract; transport mechanics are not being
rewritten. Remove unsafe casts at the relevant decoding points, without adding
a universal JSON schema framework.

**Completion criterion.** These inputs produce the intentional typed result or
failure, never an incidental cast error. Scan failure classification remains
safe and useful, and valid Plex responses retain existing semantics.

## 6. Recent improvements to preserve and avoid rediscovering

The repo has already completed a substantial maintainability campaign. Consult
[its execution record](reviews/maintainability-remediation-2026-10-12/EXECUTION.md)
for context and attributed evidence. Its old model roster or orchestration does
not govern a new plan.

| Commit | Relevant improvement / planning implication |
| --- | --- |
| `e3f36d00` | Settings serialization and committed mutation-scope separation. Keep transformations evaluated against committed state inside the queue. |
| `c7c393aa` | Persist selection before retiring active state. A pending/failed selection save must retain the old lifetime and its valid work. |
| `769b44fc` | Shared Plex page-envelope validation already exists. Library/playlist occurrence policies still differ intentionally. |
| `19416bc9` | Studio draft projection and facet matching are already extracted. CQ-05/CQ-06 address remaining ownership. |
| `a4d9a415` | Scan attempts and retained readiness already have an owner. CQ-02 completes a narrow boundary. |
| `69cedc0b` | Recursive immutable publication, frozen queued proposals, and constrained fixture scenarios. Do not restore mutable production state setters for test convenience. |
| `ae45de96` | Setup projection cache preserves source order and separates preview from fresh review materialization. |
| `ea4dce49` | Typed native commands and production lifecycle contract-test paths already exist. |
| `995a462d` | Position notification coalescing and visible-clock refresh already exist. CQ-04 must retain the contract. |
| `6b874f35` | Repeated playback facts preserve OSD deadlines. |
| `556dfa26`, `91b66b7e`, `cd2c08f6` | Scheduled continuation, live-join EOF accounting, and preservation ending at readiness are current behavior. |
| `60426a73`, `4ce152e1`, `13d711e0`, `eede9bb3` | HDR retry limits, restart ownership, same-target recovery, and predecessor fencing represent distinct real requirements. |

The existence of several fixes in a subsystem identifies reasoning complexity;
it does not prove that current code still has those defects.

## 7. Design directions considered but not justified

- **Blanket Riverpod/BLoC/provider migration:** no demonstrated cross-feature
  state-graph requirement. A new package would not automatically fix ownership.
- **Mechanical file splitting:** valid for navigation as a secondary benefit,
  insufficient as the goal of these changes.
- **One global epoch or cancellation abstraction:** would conflate validly
  different application/native lifetimes.
- **Replacing `NativePlayer` because it has one supported implementation:** the
  platform/trust/lifetime boundary remains real.
- **Wholesale native-player rewrite:** typed commands, playback-state correlation,
  and separate platform/mpv/display workers already address important complexity.
- **Queue rewrite based on acknowledgment eviction alone:** bounded event-queue
  saturation behavior is deliberate, tested, and paired with caller timeouts.
  No new pressure incident was established.
- **Blanket generated model/equality migration:** immutable-copy and canonical
  identity code deserves care, but this investigation did not establish enough
  independent benefit to prescribe a repo-wide code-generation dependency.
  Touch value semantics where a named package needs them.
- **New generic migration, undo, event-bus, command, or transaction frameworks:**
  prefer the concrete domain operations identified above.
- **Rewriting the deterministic scheduler or content resolver:** no material
  architectural defect was established there in this assessment. Preserve the
  one authoritative scheduling policy and measured off-interaction-path work.
- **Broad test pruning or new E2E infrastructure:** neither was justified here.
  Preserve distinct existing behavioral evidence; move or add tests only when
  the new boundary creates a meaningful proof need.

## 8. Related product/backlog work: reconcile without absorbing it

The separate [feature opportunity report](feature-opportunity-report.md),
[feature validation findings](feature-validation-findings.md), and
[Opus feature research request](opus-feature-research-request.md) discuss product
additions. They are context, not implementation scope for this handoff.

- Backup/restore would benefit from CQ-01's scoped state value, but CQ-01 should
  not introduce an export format or restore UX.
- Mixed-source authoring would benefit from clearer draft/rundown/verification
  ownership. Preserve existing mixed-source data without implementing an editor
  as part of these refactors.
- Last-channel recall would consume clearer playback-session transitions. Do
  not choose its success/history semantics implicitly in CQ-03.
- Preferred tracks and [Plex transcoding](plex-transcoding-implementation-plan.md)
  will touch track/session policy. Preserve the plan's current discovery/design
  gates and avoid a competing policy owner.

Existing review records also retain native buffering and other open acceptance
or policy items. The earlier October 7 report classified buffering as likely,
not physically established; later current source must be checked before relying
on that old classification. The October 10 records retain junction-policy and
native acceptance context. These were not revalidated by this assessment and
are not new accepted implementation packages here. The planner should identify
an actual dependency or collision if one exists, and preserve their status.

## 9. Package boundaries, dependencies, and suggested planning order

The following is sequencing advice, not a final implementation plan. The planner
should select coherent packages, exact interfaces, and actual write ownership.

| Potential package | Recommendations | Main integration concern |
| --- | --- | --- |
| Plex decoder correction | CQ-09 | Independent of the architectural work; avoid unrelated transport changes. |
| Studio manual rundown | CQ-05 | Preserve occurrence keys, widget focus, dirty identity, and saved snapshots. |
| Air Check verification | CQ-06 | Coordinate with Studio draft API; may follow CQ-05 or use an agreed stable seam. |
| Setup review value | CQ-07 | Reuse current builder/controller; overlaps the authoring domain but is a distinct view. |
| Scoped committed state | CQ-01 | One integration owner for controller/store; highest transaction migration risk. |
| Scan commit candidate | CQ-02 | Agree the CQ-01 commit interface; do not concurrently edit overlapping controller paths. |
| Explicit playback reconciliation | CQ-04 | Useful first playback slice; preserve display holds and publication semantics. |
| Playback session owner | CQ-03 | Coordinate with CQ-04; avoid concurrent coordinator writers. |
| Native restoration classifier | CQ-08 | Independent source area, but requires Windows native and physical acceptance resources. |

CQ-09 is the smallest confirmed correction. CQ-05 is the strongest contained
domain refactor. CQ-01 offers the largest systemic benefit. CQ-04 is a useful
entry to playback work before a larger lifecycle extraction. CQ-08 has a small
possible diff but high-consequence safety semantics; schedule it with access to
the required Windows evidence.

Parallel work is appropriate only after interfaces and write scopes are stable.
Plex decoding, setup review, and native classification can be independent of
controller work. Studio and playback packages have genuine shared-file/API
dependencies. A numbered plan does not require serial execution, and an agent
role name does not justify launching another agent. One controller should own
integration and final evidence.

## 10. Verification map for the implementation plan

Use [Development](DEVELOPMENT.md#portable-commands) as the live toolchain/command
authority. At report time it specifies Flutter 3.47.7, framework revision
`abaf9c523780a608bd46686fd5e53740a07077f8`, Dart 3.13.5. Do not select an
arbitrary SDK from PATH or overwrite the existing dependency/runtime upgrade.

For implementation, use focused existing suites while iterating, then applicable
integration/full acceptance once on stable inputs. Typical portable commands
from the repo root are:

```sh
flutter pub get
dart tool/format.dart --check
flutter analyze
TZ=America/New_York flutter test
```

Do not run `pub get` merely to review this document. During implementation,
inspect any lockfile effect and keep dependency work within authorization.

| Package | Primary retained proof | Additional boundary / limitation |
| --- | --- | --- |
| CQ-01 | Controller delayed/failing save, settings merge, scope isolation, logout, frozen expected-base tests; store compatibility/recovery tests | OS credential storage and physical filesystem claims need the relevant platform evidence. |
| CQ-02 | Controller subset/readiness/retry/restore tests; Plex IO cancellation | Stale suppression does not establish HTTP abortion. |
| CQ-03 | Coordinator supersession, stop, multipart, EOF, recovery, persisted channel, track confirmation tests; Windows adapter tests where changed | Fakes do not establish physical media behavior. |
| CQ-04 | Position coalescing, display holds, OSD deadlines, Player/shell focus/navigation tests | No performance benefit should be claimed without a distinguishing measurement. |
| CQ-05 | Draft and Studio repeated-occurrence, inventory refresh/loss, undo/reorder, save/conflict and focus tests | Keep widget/semantics proof even if pure domain tests become cheaper. |
| CQ-06 | Air Check bounded queue, stale result, retry, baseline/off-air outcomes; Studio save-gating tests | Rendering-independent ownership must still integrate correctly with widgets. |
| CQ-07 | Setup stale apply/removal confirmation; projection ordering/cache invalidation; builder and controller apply | Fresh review anchor differs from cached configuration preview. |
| CQ-08 | Display dynamic-range, guardian, admission/process, and affected native integration tests | Real Windows HDR/external-change/crash/restart/close acceptance remains separate. |
| CQ-09 | Existing parser fixtures plus wrong-shape controls; affected public scan/transport behavior | No live Plex interoperability or network-security campaign was performed here. |

Native targets are explicitly built and selected; they are not all part of the
default app build or CI. Use the current commands in
[the native test tiers](DEVELOPMENT.md#current-test-tiers-and-gaps) and inspect
target wiring rather than inventing target names from source filenames.
Stock-engine compilation is not a usable native-player or presentation result.

Keep test assertions tied to the protected behavior. When moving tests, map old
proof obligations to retained evidence. Do not update expectations simply because
the new architecture produces a different result. Do not impose a coverage
percentage, add redundant test layers, or require a new full application harness
for a pure domain extraction.

On Windows, `TZ` does not change Dart's effective OS timezone. Record the real
environment and follow the documented setup; do not change a user's system
timezone silently. Physical evidence records need the actual commit/build,
runtime/engine identities, hardware/display, scenario, and observed result.

## 11. What the Opus planning deliverable should contain

Produce a decision-complete plan covering CQ-01 through CQ-09, with a concise
top-level package table and enough detail for bounded implementation handoffs.
For each package, include:

1. Finding IDs, goal, concrete coordination or failure removed, and user-visible
   behavior expected to remain or intentionally change.
2. Chosen owner/state model/interface, representative caller flow, and the
   strongest simpler alternative with the decisive tradeoff.
3. Exact likely source, caller, and test scope; identify shared write areas and
   dependencies on other packages.
4. Migration sequence, obsolete paths to delete, intermediate-state safety,
   disk/wire compatibility, and rollback/recovery considerations.
5. Existing tests retained, meaningful missing cases, exact feasible commands,
   and target-runtime observations that remain unavailable or required.
6. Completion criteria that demonstrate simpler callers and preserved
   invariants, rather than a smaller file count or a new class roster.
7. Material uncertainty and the cheapest observation that settles it. Resolve
   engineering choices in the plan; ask the maintainer only for consequential
   product/compatibility decisions not established by current authority.

For CQ-01, CQ-03, CQ-06, and CQ-08, include short transition traces or tables for
the critical success/failure/supersession paths. Detailed class diagrams without
those behavioral traces would leave the hardest work to implementers.

The planner may consolidate packages where ownership is clearer, but preserve
traceability for all nine recommendations. Avoid turning this into a whole-repo
rewrite. Implementation, commits, separate chats, external messages, publication,
and deployment are not authorized by this report; obtain their actual scope
from the maintainer's subsequent instruction.

## 12. Modern-practice context and final calibration

Current [Flutter architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations)
support responsibility-based separation, immutable models, and moving domain
logic out of widgets, while treating architecture guidance as adaptable to the
application. [Effective Dart: Design](https://dart.dev/effective-dart/design)
provides language/API design guidance. These were checked during the assessment
as context, not used to mandate a framework, package roster, or uniform layering.

The central recommendation is to finish ownership where current callers still
coordinate policy: application commits, playback sessions/publication, and
authoring/verification. The native work is a bounded consolidation of safety
classification. The Plex work repairs a reproduced boundary inconsistency.

A successful plan will preserve the repository's strong existing contracts,
delete displaced coordination, and make future changes easier to reason about
without creating a second authority for the same behavior.
