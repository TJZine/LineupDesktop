# Comprehensive review remediation plan — 2026-10-07

## Scope and authority

This companion to [REPORT.md](REPORT.md) was written as a planning-only artifact for reviewed source `0382c131713174d9f8bced9d5b942855a99a6414` on `codex/desktop-ui-second-pass`. Findings passed independent evidence calibration. On October 8 the user authorized local implementation from `01bda7960431ba8d7448a69cceabfaeb9cf686d4` through [the remediation handoff](../../codex-handoff-2026-10-08-remediation.md). The original review remained read-only; the execution authorization below supersedes its stopping boundary.

Authorized packages: P1–P7, P9, P10, and the new P11–P13 below. P13 shares P6's chat and follows P6's corrections. P8/F15 is deferred to the Windows session; H1/H2 and other live observations remain evidence requests. Existing planned native, release, token-compensation and live-collection refresh work is not duplicated. The user has now settled F03/F18/D3 as recorded below.

The constraints are the repository AGENTS.md/.agents/project.md, approved desktop UI/system contracts and current product behavior. Flutter owns interaction and application state; native code owns platform/media mechanisms. Preserve credentials and data scope, snapshot/save ordering, stale-work rejection, intentional off-air manual channels, stable schedule anchors/seeds and existing native reference security. No redesign, deployment, publication, external communication, broad cleanup, test-policy migration or dependency upgrade is part of these packages.

Concurrent Sleep-picker work has advanced the checkout to `01bda7960431ba8d7448a69cceabfaeb9cf686d4`. Before separately authorized execution, resolve the actual branch/tip and dirty state and reconcile the accepted mechanisms against that tip. Preserve the Sleep changes. Do not apply patches blindly against the reviewed SHA or infer authorization for unrelated changes.

## Package overview

| Package | Findings | Goal / risk reduced | Suggested executor | Required evidence |
| --- | --- | --- | --- | --- |
| P1 Inventory boundary | F01 | Malformed successful inventory cannot rewrite saved selection | worker | Real parser/controller persistence regression; explicit-empty control |
| P2 Effective generation | F02 | Generated channel can satisfy its chosen schedule policy | worker | Builder and real apply→production schedule regression, include-specials control |
| P3 Scan readiness and phases | F05/F06 | Offered continuation/retry is usable; ongoing playlist work has truthful phase | worker | Failed enrichment→targeted retry→commit; gated playlist phase; stale/cancel controls |
| P4 Nested picker origin | F04 | Back/Escape return to the origin through nested account pickers | worker_luna | Direct/nested origin widgets plus controller cancel behavior |
| P5 Player shortcut dispatch | F07/F08 | Documented activation and recovery/navigation keys work in affected overlays | worker_luna | Real key events against actual Player/Guide/native seams |
| P6 Guide interaction and geometry | F09–F12 | Search owns text; viewport projection, save feedback and DST instant are correct | worker | Physical-key widget tests; ultrawide hit target; failed save; both DST folds |
| P7 Studio task and navigation lifetime | F13/F14 | Inactive tasks do not strand selected source; late Tune respects newer route | worker | Source-switch task recovery; delayed native Tune with route replacement |
| P8 Native buffering projection | F15 | Cache waiting is observable without conflating user pause | worker | Producer/adapter state proof plus physical controlled starvation/recovery |
| P9 Support vocabulary | F16 | Copied report includes new safe failures while preserving filtering | worker_luna | Producer→report test and redaction/unknown-value controls |
| P10 Current contract reconciliation | F17 | Current user/testing authority describes the approved product and real evidence | worker_luna | Source/claim cross-check, links, dated PARITY evidence review |

The highest-risk implementation seam is P3: scope-sensitive scans, retained facts and commit eligibility share controller state. P1 protects saved selection and should be prioritized. P2 corrects ordinary generation success. P8 requires physical evidence and can remain pending independently of portable packages.

## Packages

### P1 — Reject malformed library inventories before durable filtering

**Owner/files:** one worker owns `lib/plex/plex_client.dart`'s library endpoint parsing and any strictly necessary `lib/app/lineup_controller.dart` inventory-error integration. Test ownership: `test/plex/plex_parser_test.dart`, `test/plex/plex_library_scan_test.dart` where relevant, and `test/app/lineup_controller_test.dart`.

**Behavior/approach:** validate the successful inventory envelope and list shape at that endpoint. Distinguish malformed/missing data from an explicitly empty inventory. Do not let a malformed response enter the controller's authoritative selection-filter/save path. Surface its existing recoverable error while retaining the prior libraries, channels and saved selection. Correct the responsible parser rather than making every consumer guess whether an empty list is valid.

**Evidence:** adapt E01's real parser/controller scenario into repository regressions only after implementation approval. Assert malformed success reports failure and leaves the durable selection/channel snapshot unchanged; explicit `size=0` with a valid envelope remains accepted; valid nonempty and legitimate removed-library behavior remain covered. Run the relevant Plex/controller files with `TZ=America/New_York flutter test --no-pub <test paths>`.

**Safety/rollback:** no schema migration or credential change. Preserve the existing handling of genuinely removed libraries. Reverting this package reintroduces the selection-loss risk; rollback must not write an old snapshot over subsequent user edits. Requires no product decision. Coordinate controller/test ownership with P2–P4.

### P2 — Make generator eligibility schedule-effective

**Owner/files:** one worker owns `lib/channels/channel_builder.dart`, the generated-apply seam in `lib/app/lineup_controller.dart`, and only necessary presentation of the resulting valid proposals in `lib/app/channel_setup_view.dart`. Tests: builder/controller/setup files and the existing production `schedule_worker_test.dart` as needed. The scheduler remains the schedule-policy authority; change it only if shared effective eligibility requires a coherent reusable seam.

**Behavior/approach:** apply chosen block/specials policy when determining eligible content, before channel allocation and again at the generated commit boundary. A specials-only TV source with specials excluded must not be reported as successfully created and later rejected by scheduling. Use the existing build-mode/result contract for unavailable proposals. Avoid independently duplicating scheduler rules in UI/controller code.

**Evidence:** use E02's synthetic source through actual builder, controller apply and production schedule worker. Prove exclusion cannot persist an unairable generated proposal, inclusion produces a usable schedule, and a mixed regular/specials source remains usable. Reuse meaningful coverage for each supported build mode, numbering/seed/anchor behavior and retained manual unavailable sources. Test effective behavior, not a duplicated predicate.

**Safety/rollback:** no durable schema or schedule-policy migration. Preserve deliberately saved manual/off-air channels; do not introduce a universal “all channels must tune” guard. Preserve sequential/block distinctions. Rollback is code-only; never regenerate the user's lineup as a rollback procedure. No product decision is needed for the demonstrated impossible generated result. Controller/setup ownership overlaps P3; integrate serially or use isolated worktrees with one controller integration owner.

### P3 — Recover failed enrichment and expose playlist work

**Owner/files:** one worker owns scan readiness/retry/phase state in `lib/app/lineup_controller.dart`, necessary facts in `lib/plex/plex_models.dart` or `plex_client.dart`, and their consumers in `lib/app/channel_setup_view.dart` / `lineup_restore_view.dart`. Test ownership: controller/setup/restore tests and relevant Plex scan tests.

**Behavior/approach:** represent required-source readiness separately from successful item inventory. Retry failed required enrichment even when item facts are complete, retaining already valid facts and avoiding unnecessary successful scans. Align Continue's offered eligibility with the commit guard; retain the guard. Track playlist discovery/content loading explicitly so the existing phase/progress surface describes work actually underway. Respect scoped selection, scan generation/currentness, cancellation and partial-failure policy.

**Evidence:** reproduce E04 with an initially failed collection request, successful retry, increased appropriate IO and successful continuation. Assert unrelated sources can continue when enrichment is optional, full Scan again still works, and retry neither erases usable facts nor publishes stale results. Gate playlist IO after all library facts complete and assert playlist phase until completion; cancel/server change must retire it. Reuse existing scoped commit, stale scan and restore tests.

**Safety/rollback:** no broad readiness relaxation, no disappearance of required failure facts, no automatic deletion/regeneration of channels. Routine phase wording fits the approved existing status surface. Reverting restores the known recovery/feedback limitations; durable data format stays unchanged. Shares controller/setup/Plex files with P1/P2 and origin tests with P4; these require explicit integration order, not simultaneous shared-tree edits.

### P4 — Preserve nested account-picker cancel origin

**Owner/files:** one worker_luna owns the runtime origin/cancel transitions in `lib/app/lineup_controller.dart` and their Back/Escape visibility in `lib/app/onboarding_view.dart`; controller, onboarding and navigation tests.

**Behavior/approach:** preserve each picker's immediate origin, including the outer server picker's own return state. Use a coherent origin representation rather than adding stage-specific booleans that lose nesting. This package does not add first-run account-exit UI (F03).

The handoff destinations are explicit:

| Entry chain | Profiles Back/Escape | Subsequent Servers Back/Escape | Profile Back label |
| --- | --- | --- | --- |
| Ready/Settings Account→Profiles directly | Existing Ready/Settings Account destination | Not applicable | Existing `‹ Settings · Account` in Account context, existing `Back` otherwise |
| Ready/Settings Account→Servers→Profiles | Servers, without reconnecting or changing scope | Original Ready/Settings Account destination | Existing generic `Back`, because the immediate destination is Servers |
| First setup Libraries→Servers→Profiles | Servers | Same library step/server, preserving its existing cancelability | `Back` |
| Regeneration Libraries→Servers→Profiles | Servers | Same library step/server, preserving regeneration cancelability | `Back` |
| Saved-lineup Restore→Servers→Profiles | Servers | Restart the original restore, as the approved server-origin contract requires | `Back` |
| Initial Servers→Profiles via the existing Switch profile action, without retained outer origin | Servers | Remains unavailable, as before | `Back` |

Initial profile selection reached during linking retains its existing noncancellable behavior. A nested protected-PIN Back returns to its Profiles picker without discarding the outer Servers origin; preserve the existing direct Account/PIN cancellation behavior. Keep the existing button style/layout and origin-sensitive labels rather than adding new UI direction.

**Evidence:** E03 direct profile cancellation is the positive control. Test every destination in the matrix with Back and Escape, nested PIN return, successful selection, preserved outer origin and initial linking's uncancellable profile state. Include a nested origin with no current server so the old `server != null` guard cannot defeat the immediate return. Reuse tests for scan cancellation and profile/server invalidation; do not alter deferred credential compensation.

**Safety/rollback:** origin is ephemeral; no persistence migration or new token operation. Keep authorization scope clearing on actual profile/server switch. Coordinate controller ownership after P1–P3 integration. No unresolved product choice for restoring an already supported cancel route.

### P5 — Dispatch documented Player keys by context

**Owner/files:** one worker_luna owns `lib/playback/player_view.dart` and `test/playback/player_view_test.dart`; only add shell navigation tests if the corrected contract needs them. Preserve the concurrent Sleep-picker implementation at the starting tip.

**Behavior/approach:** include Space in Mini Guide activation and scope overlay-local key handling to the keys it owns. Preserve documented error Page Up/Down channel recovery and Guide G/F2 routing from track drawers. Keep native row focus/traversal, Escape behavior, transport policy with DVR off, approved Now Playing exceptions and app route chords. Do not remove overlay protections wholesale or add unapproved shortcuts.

**Evidence:** convert E05's failed intended-contract assertions to faithful actual-key regressions. Assert Enter/Space/Select equivalents where supported, error channel changes, G/F2 from audio/subtitle drawers, and controls for normal OSD plus track-local navigation/activation. Existing Sleep keyboard tests must continue passing. Run Player view and any directly affected navigation tests; native playback is unnecessary for proving this Flutter dispatch change.

**Safety/rollback:** interaction-only; no layout, OSD timeout redesign, data or native protocol change. Over-broad key routing is the main regression risk. Independent of controller packages; serialize only any shared test/native acceptance resources.

### P6 — Correct Guide editor ownership, projection, feedback and DST

**Owner/files:** one worker owns `lib/guide/guide_view.dart`, `lib/guide/guide_controller.dart`, `test/guide/guide_view_test.dart` and `guide_controller_test.dart`. Controller persistence policy stays unchanged unless a necessary typed error seam is justified.

**Behavior/approach:** let a focused search editor own unmodified text keys while preserving explicit Escape/Enter and modified app/search shortcuts. Remove the incidental 2000-pixel program cap in favor of already bounded projected/clipped timeline geometry. Present local Guide-hours save failure and recovery in the existing UI without changing persist-before-publication ordering. Floor the actual instant to the half-hour without reconstructing ambiguous local wall time; preserve display timezone and approved Now/window behavior.

**Evidence:** use actual key events for G/P while search is focused, and prove normal unfocused shortcuts plus Escape/Enter still work. At 3440×1440, prove a long program covers the visible timeline and the formerly blank strip is hit-testable; reuse narrow-window and text-scale coverage. Inject store failure and assert visible failure, old durable/published hours retained and successful retry. Under `TZ=America/New_York`, prove first and second fall-back folds, spring-forward and normal midnight controls. E06's expired-window observation is not an acceptance requirement for automatic rolling.

**Safety/rollback:** no schedule seed, anchor, persisted timestamp format, global window-follow policy or redesign. Windows Eastern-timezone behavior remains an L12 physical acceptance step; portable timezone evidence must not be relabeled physical. Risks are shortcut precedence, clipping/hit regions and accidentally weakening save ordering. The four findings share these Guide owners; internal commits may remain focused without separate competing writers.

### P7 — Scope Studio pending work and retire stale navigation

**Owner/files:** one worker owns `lib/app/channel_studio_view.dart` and `lib/app/channels_view.dart`, their widget tests, and narrowly necessary `lineup_shell.dart` navigation intent if the caller needs it. No global navigation rewrite.

**Behavior/approach:** cancel or scope pending ephemeral Library filter work when selecting a different source, so a valid selected source does not inherit invisible blockers. Preserve completed inactive source drafts. For Tune, verify the originating navigation intent before its post-await Player transition. A newer Settings/Guide destination wins; a valid tune may continue playback. Put currentness checking before the caller's route callback, not after it.

**Evidence:** E07's actual Studio source-switch and delayed native load are the regression basis. Assert valid playlist Save/Tune eligibility with pending former Library task, completed-choice preservation when switching back, and ordinary Cancel behavior. Start Tune, navigate Settings/Guide, then complete load; assert latest route remains while current playback loads. Also prove normal Tune still opens Player and failure retains existing recovery. Reuse unsaved-draft/save guards and rapid tune tests.

**Safety/rollback:** do not use a global busy lock to prevent allowed navigation, or cancel valid playback merely to suppress obsolete routing. No draft/schema migration. Rollback must preserve durable drafts. Risks: discarding completed filters, losing normal post-Tune navigation or confusing playback load identity with route intent. Coordinate shell ownership with any separately approved navigation work; otherwise independent of P1–P6.

### P8 — Observe and project native cache waiting

**Owner/files:** one worker owns `windows/runner/native_player.cpp` and the corresponding header/event contract, `lib/playback/windows_native_player.dart`, and adapter tests. Touch `native_player.dart` / `player_coordinator.dart` only if required by a coherent existing typed state boundary; keep Flutter policy out of native code. Native harness/test files are owned by this package if the observed-property seam is exercised there.

**Behavior/approach:** first establish F15's physical manifestation with L1. Inspect libmpv `paused-for-cache` facts and their precedence with loading, user pause, stop/end/error and current load identity. Add the missing bounded observation/event mapping and truthful buffering state. Cache recovery must return to user-paused or playing state correctly; stale old-load cache events must not change a newer tune. Do not ship a new projection if physical/API observation disproves the assumed state mechanism.

**Evidence:** native producer/harness proof for observed property changes and a Dart adapter regression for buffering→recovery with pause/load controls. Preserve bounded queues/event costs and typed values; do not log descriptive/raw mpv fields. Compile with the project's pinned Windows engine/libmpv and run applicable native tests. Physical L1 must independently establish >2s cache waiting, visible buffering, recovered playing and separate user pause; portable fake-state tests alone do not close F15.

**Safety/rollback:** protocol consistency and event precedence are the risks. No codec, HDR, redirect, reference-security or package-policy changes. Revert native producer and Dart mapping together if needed; no durable migration. This package may be approved conditionally for observation first and remain unclosed until physical acceptance. It can run independently with a single exclusive Windows media session.

### P9 — Extend only the safe support-report vocabulary

**Owner/files:** one worker_luna owns `lib/diagnostics/diagnostics.dart` and `test/diagnostics/diagnostics_test.dart`; producer integration tests may use `test/app/desktop_diagnostics_test.dart`. Change `lineup_controller.dart` producers only if necessary to express already safe bounded facts, with coordinated ownership.

**Behavior/approach:** add the exact new collection/portrait event names and permitted bounded failure/status values to the export vocabulary. Keep storage and copied-report filtering independently explicit. Do not broadly include arbitrary producer payloads or expose server addresses, media identities, titles, paths, credentials or tokens.

**Evidence:** use E01's real producer-to-copy failure plus collection producers. Assert these safe events appear in exported support text, diagnostics-off still behaves as intended, unknown values remain excluded/redacted and malicious token/address/path/title sentinels cannot leak. Reuse existing redaction/size/bounds tests rather than replacing them.

**Safety/rollback:** privacy is the primary acceptance gate. Rollback may omit new events again but must never relax filtering. No data schema/product choice. Independent unless controller producer changes are needed; prefer exact consumer vocabulary correction.

### P10 — Reconcile current contracts and evidence claims

**Owner/files:** one worker_luna owns the current-authority sections of `docs/user-guide.md`, `docs/product-parity.md`, `docs/architecture.md`, and the specific README/documentation index links to the absent audio-passthrough document. Other documentation changes require a demonstrated current-reference need, not a broad historical rewrite.

**Behavior/approach:** reconcile current theme names/count, removed Glass theme, overlay transparency and channel-source settings, account controls actually offered, approved warning removal, Guide layout/controls, Mini Guide behavior, Now Playing presentation and Settings operation policy. Correct broken links with a real existing destination or remove a stale reference when its content no longer exists. For each current PARITY claim, identify actual source and dated behavioral/native evidence; label remaining live/physical acceptance explicitly. Keep historical observations, commits and dated matrices as historical rather than silently updating their evidence date.

**Evidence:** cross-check the user-guide shortcut matrix against source and meaningful tests, including P5/P6 when integrated. Check all changed local links and claimed controls/names; source searches are adequate for document corrections. No ceremony tests or full suite solely for prose changes. F03/F18/D3 are now decided below; distinguish approved behavior from implementation and available evidence. Read the final actual source before declaring an implemented remediation's current behavior.

**Safety/rollback:** no product behavior changes or retroactive PARITY evidence. Current claims can be drafted independently, but final reconciliation follows approved package integration and their available evidence. Rollback restores the known document drift; it cannot make unavailable native evidence true. No unresolved product decision for describing already approved behavior.

## Sequencing and write ownership

One integration owner resolves the starting source, approves file ownership, adjudicates findings and records completion. Suggested priority: P1 and P2 first, then P3; controller/origin integration P4 follows those overlapping changes. This is an overlap constraint, not a requirement that all work be sequential.

P5, P6, P7, P9 and the independent documentation portion of P10 can proceed concurrently when authorized, with disjoint file ownership. P8 has its own native/adapter seam and exclusive physical Windows session. If P9 needs controller producer edits or P7 needs shell edits shared with other work, coordinate them explicitly. Independent writers use isolated worktrees when they otherwise touch the same files; do not concurrently modify shared controller/tests. Worktree creation and implementation dispatch are future execution choices, not actions taken by this review.

P10's final current-contract reconciliation follows the integrated behavior/evidence. F03/F18/D3 decisions can be obtained independently and do not block the no-decision packages. No known deferred work becomes a dependency merely because it shares a subsystem.

## Verification and review gates

| Gate | Proof / failure condition |
| --- | --- |
| Starting state | Resolve actual target/dirty state; reconcile fixed-SHA finding against newer source and prior fixes. Drop a finding if the starting tip already resolves its mechanism. |
| Focused regression | Run existing affected test files plus faithful regression scenarios under `TZ=America/New_York flutter test --no-pub <paths>`. Correct behavior and mitigating controls must pass; retain distinct existing proof obligations. |
| Independent correction review | Verify the cause is removed, no guard/rollback/privacy policy is weakened, and no product decision was smuggled into implementation. Reconcile external suggestions against actual source. |
| Integrated deterministic gate | Once for the final authorized integration: `dart format --output=none --set-exit-if-changed .`; `flutter analyze`; `TZ=America/New_York flutter test`. Repeat only for subsequent changes/failures that invalidate evidence. |
| Native/physical | P8 requires actual pinned Windows compile/native tests and L1; P6 timezone target acceptance uses L12. Other report L1–L13 observations retain their original scope and do not all become mandatory tests for every package. |
| Final evidence | Record starting/final SHAs, commands/results, unchanged obligations, remaining physical acceptance and known limitations. No portable test, fake backend or source trace substitutes for physical media/monitor/package evidence. |

The review's 1,204-pass baseline is valid for its frozen SHA and must be preserved as historical evidence. Ignored review probes are diagnostic recipes, not the repository regression suite. Under later implementation authorization, express the accepted behaviors in the existing meaningful test tools/fixtures; do not copy incidental probe scaffolding wholesale into test/.

## Parking lot — user decisions and remaining observations

- **F03 — decided October 8:** add a quiet **Sign out** text action on the server picker and the no-usable-libraries state, next to Switch server. Reuse the existing Account sign-out flow, including its confirmation and credential cleanup. Credential policy is unchanged. P11's matched renders require user approval before commit.
- **F18 — decided October 8:** shuffle from a canonical stable unique media identity order. The user accepts a one-time schedule shift for existing shuffled channels on first launch after the update. Sequential and block rules are unchanged; no migration flag. P12 owns implementation and scenario-A documentation.
- **D3 — decided October 8:** **follow live, keep browsing**. Initial open/Now establishes live mode; while the user has not browsed the time window, roll it forward and keep focus on the same channel's current program. Browsing earlier/later preserves position and inspected focus. Now restores live mode. When Now is off-screen, emphasize the existing Now control within existing styling. P13's emphasis renders require user approval before commit.
- **H1/H2 and live/physical L1–L13:** collect the report's exact bounded observations. H1's possible Home JSON shapes are not sufficient evidence for compatibility scaffolding. Native/release work already planned stays in its existing owner/scope.

Normal implementation choices remain with their owner under approved scope. The user authorizes separate local implementation chats and callbacks to the orchestrator, no worktrees, no child commits, and conventional package commits by the orchestrator. No push, PR or merge. Preserve the handoff's protected untracked paths. Any unsettled consequential decision or removal of protection returns to the user.

## Additional authorized packages — October 8

### P11 — F03 first-run account exit (worker_luna)

**Ownership:** `lib/app/onboarding_view.dart`, `lib/app/channel_setup_view.dart` and their affected onboarding/setup tests; narrowly necessary existing sign-out callback wiring in `lib/app/lineup_shell.dart` by agreement with the integration owner. No new credential policy/controller cleanup implementation.

Add quiet Sign out in the two approved states and reuse Account confirmation/cleanup/Welcome behavior. Prove zero/one-profile no-PMS recovery from both places and existing retry behavior after cleanup failure. Capture matched real-Flutter before/after at **1920×1080 and 960×720 for both states** using identical synthetic content/theme/clock/focus. Stop for the user's render approval before committing. Depends on P4 and P3; no overlap with controller/setup writers.

### P12 — F18 canonical shuffle input (worker)

**Ownership:** `lib/channels/scheduler.dart`, `content_resolver.dart` only if needed for canonical identity ownership, relevant channel tests, `docs/guide-freshness-collection-investigation.md` and existing user-facing release notes if present. Starts after P2 integrates.

First prove stable unique identity for multipart and mixed sources. Canonicalize resolved input before the seeded shuffle in the single scheduling owner. Preserve sequential/block rules and real membership changes. No migration flag; the one-time existing shuffled-schedule shift is accepted. Test meaningful same-ID/duration permutations for ordered IDs, offsets, program-at-time and Guide windows; unchanged sequential/block behavior; and genuine membership change. Record scenario A resolved with actual evidence; do not claim live collection refresh.

### P13 — D3 live-following Guide (worker, in P6's chat)

**Ownership:** P6's `lib/guide/*` and Guide test scope, after its own corrections. Track whether initial open/Now set the time window without subsequent time browsing. Roll live windows through boundaries/midnight, keeping channel/current-program focus without discarding actively inspected focus. Preserve browsed position/focus; Now re-enters live mode. Prove both DST folds using P6's instant correction. Render-gate the existing Now control's return-to-live emphasis before commit. No new schedule refresh service or persisted state.

## Authorized execution schedule and approval gates

Wave 1: P1, P5, P6 (+P13 after P6), P7, P9 and P10 research run in parallel with disjoint writes. Shared controller chain is **P1→P2→P3→P4→P11**. P12 begins after P2 integrates. P10 final reconciliation runs last against integrated behavior. All execution is in the current local checkout, without worktrees; shared Flutter runtime/check resources are serialized and combined gates run on stable wave inputs.

Before each package, recheck its mechanism at `01bda796`/the actual integrated starting state and drop/narrow already resolved work with evidence. Each child follows its configured worker/worker_luna preset, owns only assigned files, formats its changed paths, runs meaningful existing targeted checks and returns one terminal completion/blocked report. The controller reviews and commits accepted packages with finding IDs. After each integration wave run formatting, analysis and the full Eastern-timezone suite. At the end, obtain one independent read-only review of the complete diff from `01bda796`, adjudicate/repair accepted findings, rerun the full checks and annotate REPORT.md with resolution commits.

Hold P11 Sign out renders, P13 Now-emphasis renders, and any visible copy/layout beyond this plan's stated direction for user approval **before commit**. Include P3's playlist phase in that render review; routine status-line copy may be batched. Complete concrete implementation/evidence before requesting approval. Native Windows behavior remains unverified until its separate session.
