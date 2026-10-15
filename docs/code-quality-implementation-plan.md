# Lineup Desktop: code-quality and macOS-readiness implementation plan

Status: **revision 3 executed for portable code; F unmerged/unverified;
G documentation integrated and reviewed; portable final verification passed; plan not fully complete.**
Original plan prepared October 15, 2026. Its specifications and native review
conditions remain active. No push, PR, merge into `main`, branch-default change,
or unrelated deletion is authorized by this closure. See the execution closure
below for actual integration identities and remaining gates.

## Execution closure October 15 2026

**Portable code packages integrated and reviewed; native candidate pending;
plan not fully complete.** This supersedes the pre-execution status at the
original planning baseline, while preserving the revision-3 specifications and
review conditions below as F's live contract. Unfinished execution, product and
physical rows are routed through [open obligations](open-obligations.md).

BASE was `14ac167be4d0007cf61ce85f9ed4879ca6d5c3b1`. The following are actual
fast-forward integration commits (not fabricated merge commits). Portable code
SHAs were verified as ancestors of G's base
`d15184831213dd6403ccb80da24a3ea17ffe088c`; G is recorded after parent integration:

| Package | Integrated commit | Status |
| --- | --- | --- |
| P0 | Baseline/preflight, no product merge | Accepted preparation; not a code package |
| A | `5990c0217b33d6d690b663f177fbe62e2635b557` | Integrated; portable gates and required reviews accepted |
| H | `2a785c456c7238fc1221202f6be5930681d02711` | Integrated; portable gates and required reviews accepted |
| T | `dbc4dea073cea9f4eec0eba500306f195c7b7f8c` | Integrated; portable gates and required reviews accepted |
| M | `d2213d4d7a06181cff341892d899f3b398627b2b` | Integrated; portable gates and required reviews accepted |
| B | `bf65e00ad1c99677a2a546da6a72f669056ade8b` | Integrated; portable gates and required reviews accepted |
| L | `441950df7f3b1a6758951ac4cfff20a1ce629295` | Integrated; portable gates and required reviews accepted |
| C | `9d9ec78e79ef4de2e7fb0a1ca3c050d61ec90701` | Integrated; portable gates and required reviews accepted |
| W | `a6a2d46ff782c96f2cdcfbb34e277fc2a4fe4202` | Integrated; portable gates and required reviews accepted |
| S | `b078944a8cc8b6999badb477f2401257a330bf53` | Integrated; portable gates and required reviews accepted |
| D | `4615b7c057aba53b5530de396c2bef1e2d1c5700` | Integrated; portable gates and required reviews accepted |
| E | `edd123079c8bd8ebc929c3e768331e982c9a943c` | Integrated; portable gates and required reviews accepted |
| Y | `f7ede071eca92d82c72d02fbfb13b44aee1635f5` | Integrated; portable gates and required reviews accepted |
| V | `b75a6ebb1110c8cdf89a7737f9ed7548be377bac` | Integrated; portable gates and required reviews accepted |
| U | `bec2e8bac096b7b20536e53219c138a4b9020080` | Integrated; portable gates and required reviews accepted |
| K | `9c3c62e6645913bda54dfefadff810fcc6db87f7` | Integrated; portable gates and required reviews accepted |
| F | No integrated SHA | Candidate `040e4a64bdc667bae9673d61a39a8d15261959c3` retained unmerged/unverified; four Windows CTests and acceptance pending |
| G | `c571baf2303ee8f4ea9fd932116f04ccac42b227` | Integrated; preservation review, final portable gates and macOS build accepted |

L's controller authorization-getter glue was integrated at
`bc231cefcf8cd6ae12b8cf008b70f64b53b7ab2e`. The parent-owned
[execution record](reviews/code-quality-2026-10-15/EXECUTION.md) preserves package
bases, rebases, before/after evidence, failures, repairs, counts and acceptance.
The [combined review](reviews/code-quality-2026-10-15/IMPLEMENTATION_COMBINED_REVIEW.md)
and [final whole-branch review](reviews/code-quality-2026-10-15/IMPLEMENTATION_FINAL_REVIEW.md)
closed clear at inspected HEAD `a620790e642d8c72fcdb2d76602a3a5f49bf16af`
(product HEAD `9c3c62e6645913bda54dfefadff810fcc6db87f7`). That stable main gate
observed pin 3.47.7, 144 formatted files unchanged, clean analysis and 1,690 tests.
These are attributed earlier checks, not new G checks or physical acceptance.

G preservation review is clear; its actual integration identity is recorded above.
Final stable verification at `476750d950744d6f22de99a170d4a6dfde4042d4` passed: pin3.47.7,
format144 unchanged, analysis clean, all1,690 tests, and macOS release build54.4MB.
Accepted task worktrees/fully integrated task branches are cleaned; F and the
unmerged preflight probe remain recoverable. The final results record changes
only closeout facts after that validated input tree; no product/test/build input changed. F must retain
its branch/worktree until Windows verification, review and integration; no full
plan completion while it is unmerged. W1–W12 remain separate, unobserved physical
acceptance even after deterministic gates. The branch-repair proposal is text
only and has not been executed.

## Inputs and evidence

- Code-quality assessment handoff (CQ-01 to CQ-09), archived in full:
  `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/code-quality-refactor-planning-handoff.md`.
  This plan is its requested planning deliverable; see the
  [preservation map](open-obligations.md#archive-recovery-and-preservation-map).
- [Verification traces](reviews/code-quality-2026-10-15/TRACES.md) T1 to T7.
  Seven read-only investigations traced every report area, the
  macOS-readiness question, and the previously unexamined UI, domain, and
  Plex code. Every child handoff includes its matching trace section (§6.5).
- Three adversarial reviews of revision 1 (factual accuracy, executability,
  design and behavior preservation). Every Blocking or Major finding is
  either incorporated or explicitly rejected in §12.
- Final review of revision 2 checked state, authoring/UI, native/protocol, and
  Plex/domain/diagnostics separately against current source. Its accepted
  corrections and limits are recorded in §13 and
  `docs/reviews/code-quality-2026-10-15/FINAL_REVIEW.md`.

Read [AGENTS.md](../AGENTS.md) and the relevant sections of
[the project profile](../.agents/project.md) before any package.

## Line-anchor convention

Every source and test line number in this plan and in TRACES refers to
**commit `7afa3688`**. Commits through `8c824420` changed no `lib/` or `test/`
file. Wave-0 packages will shift lines. Resolve an anchor with
`git show 7afa3688:<path> | sed -n '<line>p'`, then work from the symbol or
test name. Symbols and test names are authoritative; numbers are navigation
aids.

## Contents

1. Source identity and baseline
2. Maintainer decisions: preconditions and approvals
3. Outcome, scope, and non-goals
4. Finding register
5. Packages, waves, write ownership
6. Execution model for the Codex orchestrator
7. Package specifications
8. Integration, review, and verification gates
9. macOS strategy and deferred port backlog
10. Windows physical-acceptance checklist
11. Orchestrator kickoff prompt
12. Review-finding disposition
13. Final-readiness corrections and execution handoff

---

## 1. Source identity and baseline

| Item | Value at plan revision 3 |
| --- | --- |
| Repository | `LineupDesktop` (`origin` = `github.com/TJZine/LineupDesktop`) |
| Branch | `codex/desktop-ui-second-pass` |
| HEAD | `8c824420` (anchor commit `7afa3688`; see the convention above) |
| Maintainer's in-progress dirty work | `.github/workflows/ci.yml`, `docs/README.md` |
| Untracked planning artifacts | this plan, `docs/code-quality-refactor-planning-handoff.md`, `docs/feature-validation-findings.md`, `docs/reviews/code-quality-2026-10-15/` |
| Default branch | `origin/main` = `1d5b4ef9` (2026-05-09, Electron era, no `lib/`), about 1,000 commits behind |

The orchestrator re-reads `git log` and `git status` at P0; this table may
already be stale.

Baseline observed by the plan author at `7afa3688` plus the then-dirty
engine-upgrade files, with the pinned Flutter 3.47.7
(`~/.cache/lineup-flutter/3.47.7/flutter/bin`):

- format check clean (104 files);
- `flutter analyze` clean;
- `TZ=America/New_York flutter test`: **1,567 passed**.

The default `PATH` on this Mac resolves Flutter **3.47.6**. Until package H
lands, every executor must select the pin explicitly (§6.4). No Windows
build, CTest, or physical run was performed for this plan.

## 2. Maintainer decisions

### 2.1 Preconditions (before dispatch)

1. **Settle the in-progress work.** Commit or stash the dirty `ci.yml` and
   `docs/README.md` changes. Package H edits `ci.yml` and package G edits
   `README.md`.
2. **Commit the planning artifacts.** Commit this plan, the handoff, and
   `docs/reviews/code-quality-2026-10-15/` (TRACES must be present in every
   worktree). `feature-validation-findings.md` belongs to the separate
   feature-research track; commit it or leave it, as the maintainer prefers.
   The resulting commit is **`BASE_SHA`**.
3. **Authorize the Git and worktree model** (§6.2). The orchestrator:
   - switches the main checkout to a new integration branch
     `codex/code-quality-2026-10` at `BASE_SHA`;
   - creates `git worktree`s `../LineupDesktop-<pkg>` on `cq/<pkg>` branches
     from the current integration head;
   - makes local commits;
   - removes accepted, recoverable task worktrees and merged task branches;
     retains any pending native candidate.

   Children may commit only on their own `cq/<pkg>` branch. Push, PR, merge
   to `main`, and deleting pre-existing branches are not authorized.
4. **Package F's Windows route:** use an available Windows host for every
   required CTest, or retain F unmerged as `pending Windows CTests`. A
   separately authorized push may supply CI-selected display suites, but CI
   does not replace the additional native-player/runner suites. If no route is
   supplied at kickoff, default to the unmerged pending candidate. `Pending`
   does not authorize integrating unverified F code.

### 2.2 Behavior changes the maintainer approves by accepting this plan

Each is a defect fix or a narrow, visible correction. Strike any line to
decline it; that package then preserves current behavior.

| # | Change | Package | Current behavior |
| --- | --- | --- | --- |
| 2.2a | Studio Save button disabled until the verified schedule identity is committed (matches the `_save` gate) | D | Button can be enabled; Save returns early |
| 2.2b | "Undo last addition" disappears after rundown replacement (reload/conflict); removing occurrences prunes their undo membership, hiding it when none remain | D | Membership can stay stale and the affordance inert |
| 2.2c | Now Playing no longer shows an "UNKNOWN" dynamic-range badge (if NF-23's confirming test shows it does) | U | Shows "UNKNOWN" |
| 2.2d | Player and Guide badge rules unified. **Recommended default:** keep each surface's current set of badges, and fix only the `unknown` case and the "3ch" / "3 CH" channel-label mismatch, using the Guide's "3 CH" | U | Divergent |
| 2.2e | A malformed Plex library page (structural shape) fails that library's scan with a typed `PlexException`, keeping prior readiness, instead of an untyped `_TypeError` | A | Untyped error; scan fails |
| 2.2f | TLS handshake failures are classified as `network-unavailable` instead of `unexpected` | A | `unexpected` |
| 2.2g | A client-identifier file that exists but cannot be read raises an error instead of being silently replaced (if NF-16's test confirms) | B | Silent replacement (new Plex device) |
| 2.2h | A Plex link PIN is expired at `now == expiresAt` consistently in polling and UI | Y | UI rejects equality; polling expires only after it |

### 2.3 Later decisions (not blocking dispatch)

- **Default-branch repair** (NF-02). Do it before anyone clones for macOS
  work; package G drafts the commands (§7.G).
- **macOS repository strategy** (§9.1). This plan assumes one repository.

## 3. Outcome, scope, and non-goals

**Outcome.** When the plan is complete:

- Callers express named operations instead of coordinating internal state.
- Every suspected defect is confirmed and fixed, or refuted by a test.
- Analyzer strictness and shared test doubles lower the cost of change.
- Duplicated policies (Plex paging, diagnostics events, media badges, key
  handling) have one owner.
- The Dart side of native playback is a documented, platform-neutral
  protocol that a macOS implementation can satisfy without touching
  application policy.
- The docs show what is current.
- All existing behavioral proof is kept.

**Non-goals.** These carry forward handoff §7.

- No state-management framework, event bus, or generic
  transaction/undo/command framework. No code generation.
- No persisted JSON, journal/guardian wire, or Dart↔native payload change.
- No visual or interaction change except §2.2. Approved Player, OSD, Now
  Playing, and Guide layouts are protected.
- No scheduler/resolver rewrite, native-player rewrite, queue rewrite, or
  `PlexClient` interface or file split (T6 verdict).
- No macOS media implementation (§9).
- No broad test pruning, coverage gate, or E2E harness.
- No mechanical file splitting justified only by navigation.

## 4. Finding register

"Confirmed" means verified by reading current source. **Suspected** findings
must be confirmed or refuted by the named test before any fix. TRACES holds
the detailed evidence.

### 4.1 Report findings (CQ)

| ID | Verdict | Material adjustments | Pkg |
| --- | --- | --- | --- |
| CQ-01 | Confirmed | Also: `clearSavedServer` assembles state by hand; the empty-lineup publication appears 4×; the `selectServer` restore path and `_migrateLegacySchedules` are extra derive/save/publish flows (T1) | B |
| CQ-02 | Confirmed | Partly redundant pre-queue checks. `library_scan_state.dart` is a `part` of the controller, so renaming fields private enforces nothing; enforce the boundary through the API and a grep (T1) | B |
| CQ-03 | Confirmed | Dead code at PC 758-770. Partial clears at 1028, 1785, 1906, 2019. The `_tuneOperations` serialization invariant. A null channel at commit is current behavior and is preserved (T2) | C |
| CQ-04 | Partly confirmed | Policy work inside `notifyListeners` and double notification on re-entry are confirmed. Narrowing consumers is not justified: only the shell filters (T2) | C |
| CQ-05 | Confirmed | Test 2636 covers single add; the batch fallback is test 4707 (T3) | D |
| CQ-06 | Confirmed, conditional | The UI `canSave` gate ignores identity commit (2.2a). Projection failures arise during `build`, so the controller must own projection and its clock (T3, design review) | D |
| CQ-07 | Confirmed | Plan composed twice per build. `_missingSources` is live controller evidence and must stay live. The notice-clearing behavior on mode change must be preserved (T3, design review) | E |
| CQ-08 | Confirmed, refined | The live and durable "late attempt" inputs are not interchangeable. `Reconcile` applies a third rule. Implicit ordinals cross the wire at `display_recovery.cpp:76,81-82,94-95`. L3 and L7 are untested (T4) | F |
| CQ-09 | Confirmed, wider | Also `_streamCodecs` (1642) and discovery `connections` (206). Elements that are not maps are already skipped and `Image` is already guarded, so only non-list containers fail today (T6, factual review) | A |

### 4.2 New findings (NF)

| ID | Finding | Pkg |
| --- | --- | --- |
| NF-01 | No guard against the wrong Flutter SDK (3.47.6 on `PATH` passes silently). The pin lives in `DEVELOPMENT.md`, `build-metadata.psd1`, and 4 `ci.yml` lines | H |
| NF-02 | `main` is the Electron-era `1d5b4ef9`. About 20 stale local branches, including 7 `worktree-agent-*` | G (maintainer acts) |
| NF-03 | Strict analyzer modes produce only 28 issues; a curated lint set adds a small number of defect-relevant fixes | A |
| NF-04 | Duplicated test doubles: 7 NativePlayer, 9 AppStore, 11 CredentialStore. `ui_fixture.dart` already shares a store and credentials. About 400 lines removable | T |
| NF-05 | The transport is platform-neutral but named and messaged for Windows; `main.dart` contains a platform conditional; the protocol is unwritten; unchecked casts at `windows_native_player.dart:458, 482` and in `_copyTelemetry` (747-785); `lineup_app.dart:190-194` recognizes the engine failure through two types | M |
| NF-06 | Docs: about 21.9k lines, stale "approved" headings, references to absent files, open obligations scattered across about 10 plans | G |
| NF-07 | **Suspected:** `refreshServers` during a blocked `selectServer` save leaves `_restoringSavedLineup` true. It requires a saved, non-empty lineup for the target server (LC 931, 958, 2645) | B |
| NF-08 | **Suspected:** `commitLibraryScan` returns `true` without publishing. Mechanism: a queued predecessor (`selectServer`/`selectProfile`) retires the scope; the scan body returns early at LC 1043-1045 while `_isCurrent` stays true (2622). The 1065 path is unreachable | B |
| NF-09 | Confirmed: the scan commit publishes migrated channels without `_recordChannelChanges` (LC 1069) | B |
| NF-10 | **Suspected:** a 401 recovery completing while `setCurrentChannel` is awaited (PC 771) leaves `_tuning` true with no error (PC 785, 1028) | C |
| NF-11 | `StateError` signals supersession (LC 1671, 1737, 2124, 2360). Catch-alls at PC 661/808/1065/1311 hide programming errors (they record `unexpected` without stack). `PlayerTelemetry` lacks `==` | B, C, M |
| NF-12 | Confirmed from source: `_lastAddedEntries` is cleared only by undo (SV 2074), so the undo affordance survives a rundown replacement | D |
| NF-13 | Studio is a true god-State. Setup's State is mostly long per-step helpers | D, E |
| NF-14 | Native duplication: `Handle` RAII 2×, teardown/relinquish 3×, `command_queue_full` 6×, inline `Find`+`get_if` about 8×, `FindNode`≈`FindTrackNode`. Plex version hard-coded | F, A |
| NF-15 | **Suspected:** TLS `HandshakeException`/`TlsException` escapes `_send` unmapped (`plex_client.dart:1367-1384`) | A |
| NF-16 | **Suspected:** `FileAppStore` client-identifier read uses `catch (_) {}` and silently regenerates on any read error (`app_store.dart:233-239`) | B |
| NF-17 | **Suspected:** `_findTokenInXml` accepts an empty `authToken=""` (`plex_client.dart:1981-1997`). `createPin` uses `DateTime.parse`, which can throw `FormatException` (74) | A |
| NF-18 | Four hand-written pagers with copied bounds and cancellation joins; `'cancelled'` literal 6×; three loops hard-code `page < 1000` while `maximumLibraryMetadataPages = 1000` exists (`plex_client.dart:398-461, 769-851, 986-1064, 1075-1142`) | L |
| NF-19 | The authorization-failure code set is copied 4× (`plex_client.dart:276, 626, 913`; LC 2658). `_annotateLibraryItem` copies 33 fields by hand, so a field can be silently dropped | L |
| NF-20 | The diagnostics event allowlist is 17 `(area, message)` string pairs that must match `add(...)` call sites, with nothing linking them at compile time | K |
| NF-21 | Schedule-worker isolate messages are positional lists with casts; a failed cast after `_pending.remove` can hang `build()`; the worker error loses its message and stack (`schedule_worker.dart:111-199`) | S |
| NF-22 | The series/episode rule is written twice (`scheduler.dart:166-170, 475-479`). Filter names are passed as strings and the facet mapping is duplicated (`channel_builder.dart:100-302, 690`; `library_facets.dart:18-29`) | S |
| NF-23 | **Suspected:** an "UNKNOWN" badge in Now Playing; Player and Guide badge rules diverge (`player_view.dart:1434-1441, 3579-3602`; `guide_view.dart:2967-2986`) | U |
| NF-24 | Shell routes are int sentinels 0-4. Navigation shortcuts are Ctrl-only (a macOS gap). App-menu state is three correlated fields. Settings use string keys across five collections (`lineup_shell.dart`, `navigation_shortcuts.dart`) | U |
| NF-25 | Keyboard/pointer modality is tracked by three handlers with different reset rules (`lineup_focus.dart`, `player_view.dart`, `lineup_shell.dart`). Intent unverified | U |
| NF-26 | 230-line Player key handler with repeated key lists and about 18 `closeSleepPicker()` calls (`player_view.dart:183-412`). `LayerLink` recreated on every build. The poster-path rule is duplicated | U |
| NF-27 | "Watching" and "presented state" rules are written in several places (`player_view.dart`, `lineup_shell.dart`) | U |
| NF-28 | ChannelsView State owns a schedule-health job queue started from `build` (`channels_view.dart:44-71, 1155-1256, 251-278, 441`) | W |
| NF-29 | **Suspected:** duplicate changed-row notifications. Stale completion can still require publication because active-load/queue state changes. Query-time projection failures silently mutate rows; selection pairs and viewport requests also need discipline (`guide_controller.dart`, `guide_view.dart:644-663`) | V |
| NF-30 | Onboarding: `_serverError` is ambiguous; PIN expiry is duplicated and uses an untestable clock (`onboarding_view.dart:49-52, 322, 385-388, 919-952`; LC 625) | Y |

## 5. Packages, waves, write ownership

| Pkg | Findings | Goal | Executor | Wave |
| --- | --- | --- | --- | --- |
| P0 | §2.1 | Base, integration branch, worktree preflight | Maintainer + orchestrator | 0 |
| A | CQ-09, NF-03, NF-14 (version), NF-15, NF-17 | Typed Plex boundary decoding; strict analyzer; one version source | `worker_luna` | 0a |
| H | NF-01 | Toolchain guard with checked pin consistency | `worker_luna` | 0a (merge after A) |
| T | NF-04 | Shared test doubles | `worker_luna` | 0b |
| M | NF-05, NF-11 (telemetry) | Platform-neutral transport, factory, protocol spec | `worker_luna` | 0c |
| B | CQ-01, CQ-02, NF-07, NF-08, NF-09, NF-11 (type), NF-16 | Scoped lineup value, named commits, scan candidate | `worker` | 1 |
| C | CQ-03, CQ-04, NF-10, NF-11 (catches) | Active-program value, explicit reconcile and publish; C4 after B | `worker` | 1 (+C4 in 2) |
| D | CQ-05, CQ-06, NF-12, NF-13 | Rundown owner, verification controller, Studio editor widgets | `worker` | 1 |
| E | CQ-07, NF-13 | Setup review value and phase; per-step widgets | `worker_luna` | 1 |
| F | CQ-08, NF-14 (native) | Restoration classifier, explicit ordinals, native dedup, missing tests | `worker` | 1 |
| L | NF-18, NF-19 | Plex paging and cancellation consolidation; error-category getters; tagged copy | `worker` | 1 |
| S | NF-21, NF-22 | Typed worker messages; one series rule; typed filters and one facet mapping | `worker_luna` | 1 |
| V | NF-29 | Guide notification discipline, selection records, viewport scheduling | `worker_luna` | 1 |
| W | NF-28 | `ChannelHealthMonitor` out of ChannelsView | `worker_luna` | 1 |
| K | NF-20 | Typed diagnostics events | `worker_luna` | 2 |
| U | NF-23 to NF-27 | Badge rules, shell destinations and settings keys, modality, Player key resolver | `worker` | 2 |
| Y | NF-30 | Onboarding server-attempt state and testable PIN expiry | `worker_luna` | 2 |
| G | NF-02, NF-06 | Docs consolidation, register, branch-repair proposal | `worker_luna` | 3 |

Concurrency: wave 1 has 9 packages. Run at most **4 children at once**
(machine load and SDK lock). Start in this order: B, C, D, F; then L, E, S,
V, W as slots free.

### 5.1 Dependencies

```text
P0 → A ─┐
P0 → H ─┴→ (merge A, then H) → T → M → wave 1 {B, C0-C3, D, E, F, L, S, V, W}
B → C4;  B + C + V → K;  C → U;  B → Y;  L → (orchestrator applies LC 2658 getter use during B or after)
available code packages → integration review → G → portable delivery if F pending
F Windows proof → rebase/recheck + integrate F → affected review/gates + G closure
```

### 5.2 Write ownership

A child needing anything outside its row stops and reports the exact change
(§6.6).

| Pkg | Owns |
| --- | --- |
| A | `analysis_options.yaml`; `lib/plex/plex_client.dart` decoding functions and `_send` exception mapping; `test/plex/plex_parser_test.dart`, `plex_library_scan_test.dart`, `plex_transport_test.dart` (new cases); `lib/app_version.dart` (new); `lib/app/diagnostics_view.dart` (version lines only); `test/` version-consistency test. **Mechanical lint fixes in any file** (wave 0a only) |
| H | `tool/check_toolchain.dart` (new), `tool/flutter_version.json` (new), `tool/format.dart`, `test/tool/format_test.dart`, `test/tool/check_toolchain_test.dart` (new), `.github/workflows/ci.yml`, `tool/windows/verify-release-policy.ps1` (one consistency assertion) |
| T | `test/support/**`; fake definitions and their construction sites in any test file (wave 0b only) |
| M | `lib/playback/windows_native_player.dart` → `method_channel_native_player.dart`; `lib/playback/unsupported_native_player.dart`; `lib/playback/native_player.dart`; `lib/playback/native_player_factory.dart` (new); `lib/main.dart`; `lib/app/lineup_app.dart` (engine-failure check only); renamed transport test; `test/playback/unsupported_native_player_test.dart`; **all imports and constructor references of the renamed class anywhere** (wave 0c only); `docs/native-player-protocol.md` (new) |
| B | `lib/persistence/app_store.dart`, `lib/app/lineup_controller.dart`, `lib/app/library_scan_state.dart`, `lib/app/lineup_scenario.dart`, `test/app/lineup_controller_test.dart`, `test/persistence/**` |
| C | `lib/playback/player_coordinator.dart`, `lib/playback/display_matching.dart`, `test/playback/player_coordinator_test.dart`, `test/playback/display_matching_test.dart` |
| D | `lib/app/channel_studio_view.dart`, `channel_studio_draft.dart`, `channel_air_check.dart`; new `lib/app/manual_rundown.dart`, `lib/app/air_check_verification.dart`, `lib/app/channel_studio/**`; `test/app/channel_studio_view_test.dart`, `channel_studio_draft_test.dart`, `channel_air_check_test.dart`, new unit tests |
| E | `lib/app/channel_setup_view.dart`; new `lib/app/setup_review.dart`, `lib/app/channel_setup/**`; `test/app/desktop_setup_test.dart`, `channel_setup_projection_test.dart`, new unit tests |
| F | `windows/runner/**` |
| L | `lib/plex/**` (after A merged); `test/plex/**` |
| S | `lib/channels/schedule_worker.dart`, `scheduler.dart`, `channel_builder.dart`, `library_facets.dart`; `test/channels/**` |
| V | `lib/guide/guide_controller.dart`, `lib/guide/guide_view.dart`; `test/guide/**` |
| W | `lib/app/channels_view.dart`; new `lib/app/channel_health_monitor.dart`; `test/app/channels_view_test.dart`; new unit test. It must not edit `channel_studio_view_test.dart` (owned by D); report there if those tests break |
| K | `lib/diagnostics/**`; `add(...)` call sites in `lineup_controller.dart`, `player_coordinator.dart`, `guide_controller.dart` (wave 2, after their owners merged); `test/diagnostics/**` |
| U | `lib/playback/player_view.dart`, `lib/app/lineup_shell.dart`, `lib/app/navigation_shortcuts.dart`, `lib/ui/lineup_focus.dart`, `lib/guide/guide_view.dart` badge code only, `lib/playback/player_coordinator.dart` new getters only (NF-27); `test/playback/player_view_test.dart`, `test/app/{desktop_navigation,desktop_settings,theme_shell,ui_review_regression}_test.dart`; new unit tests |
| Y | `lib/app/onboarding_view.dart`; `lineup_controller.dart` PIN getters only; `test/app/desktop_onboarding_test.dart` |
| G | `docs/**` (except M's protocol file), root `README.md`, `CONTRIBUTING.md`, `.agents/project.md` (path and platform facts only) |

No package may modify golden images (`tool/visual/goldens/**`,
`test/**/goldens/**`).

## 6. Execution model for the Codex orchestrator

### 6.1 Roles and executors

- **Orchestrator** (the maintainer's selected high-reasoning model) owns the
  plan, dispatch, integration branch, commits, adjudication, and final
  evidence. It writes only integration repairs and small cross-owner edits
  (§5.2).
- **Children:** one chat per package via `create_thread`.
  - Read the preset file before dispatch: `.codex/agents/worker-luna.toml`
    (alias `worker_luna`) or `.codex/agents/worker.toml` (alias `worker`).
  - Pass `model` and `model_reasoning_effort` explicitly as
    `model`/`thinking`, and include the preset's `developer_instructions`.
  - If a `worker_luna` child returns evidence that the unit needs more
    judgment, reassign it to `worker`. That is allowed by the skill; report
    it.
- **Reviewer:** `.codex/agents/reviewer.toml`, read-only (§8.2).

### 6.2 Isolation and integration

1. **P0 preflight.** The orchestrator creates one throwaway worktree and asks
   one child to do all of the following there:
   - write a file;
   - `git commit` on its `cq/preflight` branch;
   - run `flutter --version` with the pinned SDK;
   - run `flutter pub get` and `flutter test test/tool`.

   This confirms that the host sandbox allows writes to the worktree, the
   shared `.git`, `~/.cache/lineup-flutter`, and `~/.pub-cache`. Remove the
   worktree after. If it fails, use the serial fallback (step 6).
2. **Main checkout.** Switch it to `codex/code-quality-2026-10`. All
   integration gates run there.
3. **Per package:**
   `git worktree add ../LineupDesktop-<pkg> -b cq/<pkg> <integration-head>`.
   The child works only in that path and commits on `cq/<pkg>`.
4. **Integrate.** Run `git -C ../LineupDesktop-<pkg> rebase <integration-head>`;
   the child resolves conflicts if it is still active, otherwise the
   orchestrator does. Then run
   `git merge --ff-only cq/<pkg>` in the main checkout, then the §8.1 gate.
5. **Package F** stays unmerged until all required Windows CTests (§2.1.4)
   pass on its candidate. If unavailable, retain its branch/worktree and report
   `implemented; pending Windows CTests; not integrated`. Continue independent
   portable packages. Integrating unverified F code would require a separate
   explicit maintainer decision, not an interpretation of `pending`.
6. **Serial fallback** (no worktree authorization or preflight failure): run
   each package in the main checkout on its own branch in wave order, one at
   a time. Shared-tree parallel writing is not used: full-suite checks would
   observe other children's edits.
7. **Cleanup:** remove only task-created worktrees whose accepted work is
   recoverable, then delete only their fully merged `cq/<pkg>` branches. Retain
   F and other unintegrated candidates and report their locations. Never sweep
   unrelated branches by a prefix glob.

### 6.3 Same-child follow-ups

- **C** reports "C0-C3 complete, C4 pending". After B merges, the
  orchestrator rebases `cq/C` and sends a focused follow-up to the **same C
  chat** with the new base SHA and the C4 instructions. C is reviewed once,
  after C4.
- Review corrections also go to the original child.

### 6.4 Toolchain for every child

```sh
export PATH="$HOME/.cache/lineup-flutter/3.47.7/flutter/bin:$PATH"
flutter --version   # 3.47.7, framework abaf9c5237
```

If the path is absent on the child's host, stop and report. After H lands,
`dart tool/check_toolchain.dart` must pass.

### 6.5 Child handoff packet

Build each prompt from the skill's handoff template. It contains:

1. Parent thread and host IDs, and the reference to the maintainer's
   authorizing turn (callback verification per the skill).
2. Repository, worktree path, branch, integration head SHA, toolchain (§6.4),
   and the line-anchor convention.
3. "Read `docs/code-quality-implementation-plan.md` §3, §5.2 (your row), §6,
   §7.<pkg>, §8, and the trace section for your package. Also read
   `AGENTS.md` and `.agents/project.md` sections Architecture, Verification
   selection, and Commands."

   | Packages | Trace section |
   | --- | --- |
   | B | T1 |
   | C | T2 |
   | D, E | T3 |
   | F, M | T4 |
   | T, G, H | T5 |
   | A, L, S | T6 |
   | U, V, W, Y, K | T7 (and T6 for K) |
4. Preset responsibility text; shared skills `develop-code` and
   `verify-code`.
5. Ownership row, Git authority (commit on `cq/<pkg>` only), and the
   forbidden list: push, golden edits, edits outside ownership, recursive
   delegation, user-visible changes outside §2.2.
6. The completion report (§6.6) and callback route.

### 6.6 Completion report

- Package, child thread ID, worktree, branch, start SHA, end SHA.
- Each step: done or not, with evidence.
- Suspected defects: the test name and its result **before** the fix
  (confirms or refutes), then after.
- Exact commands and results; skipped checks with the reason.
- Tests moved, renamed, or removed, as an old obligation → retained evidence
  map.
- Cross-owner change requests.
- Local decisions and returned decisions.
- Remaining limits, especially unavailable platform evidence.

## 7. Package specifications

Commands assume the worktree root and the pinned SDK. "Focused tests" means
the listed files; run the full suite (`TZ=America/New_York flutter test`)
once at the end of each package.

### P0: Base preparation

1. §2.1 items 1-2. Record `BASE_SHA`.
2. Re-run the §1 baseline on `BASE_SHA`. If it is not all-green, stop and
   report. Record the test count.
3. §6.2 steps 1-2.

### A: Plex boundary decoding, analyzer strictness, one version source

**Decoding policy** (`plex_client.dart`; approved behavior 2.2e):

| Category | Fields | Malformed **container** (non-list) | Malformed element (non-map) |
| --- | --- | --- | --- |
| Required identity | `ratingKey`, `title`, `type` | Unchanged: typed `PlexException` | — |
| Structural | `Media`, `Media[].Part`, `Part[].Stream` | **Typed `PlexException`**, using the existing page/row parse-failure code family (inspect existing codes; reuse one such as the current invalid-page code rather than inventing one). The library scan then fails through its existing failure path and keeps prior readiness | Skipped (existing behavior) |
| Enrichment | `Genre`, `Collection`, `Director`, `Role` (`Image` is already guarded) | Treated as empty | Skipped (existing) |
| Discovery | `connections` | That resource has no connections | Typed (existing `_record`) |

Rationale: treating malformed structure as "no parts" would make retained
items look gone and offer generated channels for removal. That violates
`architecture.md` ("retained evidence cannot prove that a generated source
has disappeared"). Failing typed keeps the existing "scan failed" semantics.

Missing or explicit `null` lists keep today's empty-list behavior in every
category. `Malformed non-list` means a present, non-null scalar/object. Preserve
the first-Media and first-Part selection used for stream codec enrichment; do
not start parsing unused media versions as part of shape validation. Include
missing/null controls alongside the malformed-container tests.

Implement with two private helpers: `_optionalList(raw)` (enrichment and
discovery) and `_structuralList(raw, label)` (throws `PlexException`). Apply
them at lines 206, 1579, 1582, 1587, 1642, 1659, 1680.

**Small boundary fixes:**

- `_send` maps `TlsException` (which covers `HandshakeException`) to
  `network-unavailable` (NF-15, approved 2.2f). Confirm first with a
  `MockClient` that throws `HandshakeException`.
- `_findTokenInXml` uses `_optionalText` (NF-17).
- `createPin` uses `DateTime.tryParse` and throws a typed `parse-error` on
  failure (NF-17).

**Analyzer** (`analysis_options.yaml`). Keep `include` and `exclude`. Add:

```yaml
analyzer:
  language: { strict-casts: true, strict-inference: true, strict-raw-types: true }
linter:
  rules: [unawaited_futures, discarded_futures, avoid_dynamic_calls, only_throw_errors,
          close_sinks, test_types_in_equals, prefer_final_locals, unnecessary_lambdas,
          use_super_parameters]
```

Record the rejected rules in a YAML comment:

- `specify_nonobvious_local_variable_types`: about 4,400 hits of noise.
- `prefer_const_constructors`: deliberately removed from `flutter_lints`.
- `avoid_catches_without_on_clauses`: boundary catches are deliberate; C
  handles the questionable ones.
- `cancel_subscriptions`: false positives on fields.

Measured volume: 28 strict-mode issues and about 105 lint issues, mostly in
tests.

For the `only_throw_errors` sites at `player_coordinator.dart:955` and
`windows_native_player.dart:309`: if a stack trace is available or can be
captured (at PC 947, capture it in the `catch`), rethrow with
`Error.throwWithStackTrace`. Otherwise use a commented `// ignore:`. Do not
wrap the value in a new type.

**Version.** Add `lib/app_version.dart`:

```dart
const lineupVersion = String.fromEnvironment('LINEUP_VERSION', defaultValue: '0.1.0');
const lineupVersionDefined = bool.hasEnvironment('LINEUP_VERSION');
```

- Use it for `X-Plex-Version`.
- In `diagnostics_view.dart`, use `lineupVersionDefined ? lineupVersion : 'Unavailable'`
  so diagnostics output is unchanged.
- Add a test that reads `pubspec.yaml` and asserts that the default equals
  its `version` without the `+build` suffix. That checks consistency of the
  two sources; it does not make them one source.

**Tests to add** (they must fail with `_TypeError` before the change for the
non-list containers only):

- `plex_parser_test.dart`:
  - a valid control;
  - a non-list `Genre`, `Collection`, `Director`, or `Role` → empty;
  - a non-list `Media`, `Part`, or `Stream` → typed `PlexException`;
  - a map in `connections` → no connections.
- `plex_library_scan_test.dart`: a page containing a malformed structural
  row fails that library's scan with the typed code. Assert the existing
  failure path.
- `plex_transport_test.dart`: TLS, the empty XML token, and an invalid PIN
  date.

**Commands.** Format check, `flutter analyze`, `flutter test test/plex`, the
full suite.

**Completion.**

- Analyze is clean under the new config.
- There is no unguarded `as List` or `as Map` on external Plex data.
- The new tests pass; the before/after results are reported.
- Diagnostics output is unchanged.

**Escalate** if an existing test contradicts the structural-typed policy.

### H: Toolchain guard

**Design.**

- `tool/flutter_version.json` holds
  `{"version":"3.47.7","frameworkRevision":"abaf9c523780a608bd46686fd5e53740a07077f8"}`.
- `tool/check_toolchain.dart` runs `flutter --version --machine` (with
  `runInShell: Platform.isWindows`), compares the result to the JSON, and on
  mismatch exits non-zero with a message naming the expected SDK and its
  location.
- `tool/format.dart` calls the check first, unless `--skip-toolchain-check`
  is explicitly passed. A missing/malformed JSON in the real repository fails
  with guidance; absence must not silently disable the check.
  - `test/tool/format_test.dart` runs `format.dart` in temporary
    repositories. Update it to pass the skip flag; its assertions are
    otherwise unchanged.
- **CI:** add a `dart tool/check_toolchain.dart` step after setup in each
  Flutter job. Keep the `flutter-version` literals.
- In the existing `windows-release-policy` job (pwsh on Ubuntu), add one
  assertion to `verify-release-policy.ps1` that the JSON revision equals the
  psd1 `FlutterFrameworkRevision`.
  - The Mac child may not have `pwsh`. If so, CI is the proof; report that.
- The goal is **checked consistency**, not a single source. Five pin
  locations remain, each now checked or documented.
- Do not add a `pubspec.yaml` `flutter:` constraint unless the child shows
  that pub enforces it clearly on 3.47.7. Report either way.
- Hand the one-sentence `DEVELOPMENT.md` addition to G (record it in the
  completion report).

**Tests.** `check_toolchain_test.dart` covers the pure compare function:
match, version mismatch, revision mismatch, malformed output, and missing or
malformed pin configuration. Temporary formatter fixtures opt out explicitly.

**Commands.** The new test, the format test, and
`dart tool/check_toolchain.dart`, run under both 3.47.7 (passes) and 3.47.6
(fails). Report both.

**Completion.** The wrong SDK fails `dart tool/format.dart --check` with
guidance, and `format_test.dart` is green.

### T: Shared test doubles

**Design** (`test/support/`):

- Merge the existing shared `FixtureStore` and `_MemoryCredentials`
  (`ui_fixture.dart:200, 212`) into:
  - `MemoryAppStore({PersistedState? initial})`, which records saves;
  - `MemoryCredentialStore({String? accountToken, Map<String,String> profileTokens = const {}})`.
- Re-base `_RetryStore` and `_FailingStore` on `MemoryAppStore`.
- These stay local: `lineup_controller_test` `_MemoryStore` (with
  `failNextSave` and `recoveredCorruptState`), `_ConcurrentStore`, and
  `_AmbiguousWriteCredentials`.
- `FakeNativePlayer` is **inert by default**: it records commands, `load`
  does not emit, and status, tracks, and position are settable. Event and
  display-report emission are **opt-in** through explicit methods
  (`emit(...)`) or a flag.
  - Re-base `FixturePlayer`'s current emitting behavior on that opt-in, so
    `ui_fixture` users keep their exact behavior.
  - Replace the inert fakes in `lineup_app_test` (2112),
    `native_video_surface_test` (113), `product_spine_test` (426), and the
    base `_Player` in `player_coordinator_test` (6518). Its **26** scenario
    subclasses re-base and stay local.
  - These stay local: `player_view_test` `_Native` (6331) and
    `display_matching_test` `_Player` (494, which uses `noSuchMethod` by
    design).
- Leave the `PlexClient` subclasses as they are. Only their shared
  boilerplate moves: `testPlexHttpClient()` (a `MockClient` that throws
  "unexpected HTTP"), and only if 3 or more files use it.

**Semantics guard.**

- For every replaced fake, assert in review that the test reaches the same
  coordinator state: no new `loading` events, and no new busy timer.
- Client IDs (`'test'` vs `'lineup-desktop-test-…'`) are constructor
  parameters; keep each test's value.
- Assertions are unchanged.

**Completion.**

- The full suite is green and retains the tests/behavior at T's actual starting
  commit; A/H may already have added cases. Map any consolidation. Raw count
  equality is a diagnostic, not a substitute for preserved proof.
- Report net lines removed (estimate about 400).
- No plain duplicate remains per T5.

### M: Platform-neutral transport and protocol specification

1. **Rename.** `WindowsNativePlayer` → `MethodChannelNativePlayer`, file
   → `lib/playback/method_channel_native_player.dart`. Update **every**
   import and constructor reference, including
   `test/playback/player_coordinator_test.dart:13, 1692, 1795` (M owns these
   in wave 0c).
   - Same channel name, payloads, codes, and **status messages**. "Native
     libmpv player ready" is also emitted by native code
     (`native_player.cpp:711`), so leave it.
   - Change only the handler-owner exception text ("Another native player
     already owns the platform channel"), which is not user-facing.
2. **Factory.** `lib/playback/native_player_factory.dart`:

   ```dart
   NativePlayer createPlatformNativePlayer({required bool isWindows, required bool isMacOS})
   ```

   It returns `MethodChannelNativePlayer()` on Windows, otherwise
   `UnsupportedNativePlayer(message: …)`.
   - Keep the exact macOS message ("Playback is not implemented on macOS" /
     "Native playback is not implemented on macOS.").
   - Other platforms (Linux, unshipped) get "…not implemented on this
     platform".
   - `main.dart` passes `Platform.isWindows`/`Platform.isMacOS`.
   - Test both branches through the injected booleans.
3. **Casts.** Make the casts at 458 and 482 and in `_copyTelemetry`
   (747-785) checked. Malformed values are dropped silently, consistent with
   the existing invalid-payload handling at 403. Add a test per path.
4. **Engine failure.** The transport converts the
   `required_engine_unavailable` `PlatformException` into `PlayerUnavailable`
   with that `failureCode`. Simplify `lineup_app.dart:190-194` to check one
   type.
5. **Interface documentation.** In `native_player.dart`, rewrite the doc
   comment at 30-37 as a platform-neutral token-safety contract. Add
   `PlayerTelemetry` `==` and `hashCode`. Leave the `DisplayMatching*`
   types unchanged.
6. **Protocol specification.** Write `docs/native-player-protocol.md` from
   TRACES T4, re-checked against the current Dart and C++ sources. It covers:
   - methods, arguments, and ranges;
   - result and error codes, including `NotImplemented` →
     `MissingPluginException` for unknown methods (a version-skew signal; do
     **not** remap it);
   - events and keys;
   - forwarded mpv properties, noting `sub` vs `subtitle`;
   - display report fields;
   - failure codes and the codes Dart synthesizes;
   - correlation rules for load, stop, track request, and generation;
   - queue capacity (256). When full, evict the oldest queued `property` if
     one exists, regardless of incoming type. If no property exists, drop an
     incoming `property`; otherwise evict the oldest event of any type.
     Verify this against `native_player.cpp:1254-1267` before
     documenting.
   - `setVideoRect` → `invalid_argument` when the host window is missing or
     `SetWindowPos` fails;
   - presentation obligations (§9.3);
   - which fields are Windows diagnostics a new platform may report as
     unavailable.

   List any Dart/C++ mismatch found.
7. **Tests.** Rename the transport test to
   `method_channel_native_player_test.dart`, with a header naming it the
   Dart-side protocol conformance suite.

**Commands.** `flutter test test/playback test/app/lineup_app_test.dart`, the
full suite, analyze, and `flutter build macos`.

**Completion.**

- No transport identifier contains "Windows".
- `main.dart` has no platform conditional of its own.
- The protocol doc is cross-checked against both sources.
- The macOS build is green.
- No user-visible text changed.

### B: Scoped lineup state and scan commit candidate

**Design.**

- **`app_store.dart`.** Constructor, fields, and JSON unchanged. Add:
  - `@immutable LineupScope(profileKey, serverId)`, where `profileKey` is
    `profile?.id ?? account?.id`. Name it `profileKey`, not `profileId`: the
    persisted `profileId` stays null for the owner account.
  - `@immutable ScopedLineup(libraryIds, channels, currentChannelId)` with
    `empty`.
  - `PersistedState` methods: `lineupFor`, `withLineup` (records the
    selected server, matching `_stateSnapshot` 2298-2299), `withSettings`,
    `withProfile`, `withoutSelectedServer`.
  - Absent scopes stay absent.
- **Controller derivation base (explicit).** Today every save writes the
  runtime settings, runtime profile, and runtime server selection, plus the
  scoped lineup. **Preserve that.**
  - Replace `_stateSnapshot(overrides…)` with one
    `PersistedState _persistedFromRuntime({ScopedLineup? lineup, LineupSettings? settings})`.
    It applies the runtime profile, settings, and server to `_persisted`,
    then `withLineup(scope, lineup ?? _lineup)`.
  - Commits call `_commitLineup(next)` / `_commitSettings(next)` through it.
  - `clearSavedServer` uses the same base (runtime settings, which corrects
    its divergent use of persisted settings) plus `withoutSelectedServer`,
    with a disposal check after the save.
- **Runtime state.** `ScopedLineup _lineup` replaces the three runtime
  fields. Public getters are unchanged.
- **Proposals.** `_ServerSelection` and `_ProfileSelection` are built inside
  the queue from committed state.
- **Publications.** `_publishServerSelection`, `_publishProfileSelection`,
  `_publishEmptyLineup` (replaces the 4 duplicates), and `_publishLineup`.
  Server credentials are published by `_publishServerSelection`. Profile
  selection still installs `_profileToken` and clears old server access/tokens
  after its own save; initialization and logout retain their separate credential
  duties. Credentials do not enter `ScopedLineup`.
- **Supersession type.** Add
  `final class LineupScopeSuperseded implements Exception`.
  - Throw it at **every** supersession site: 1671, 1737, 2124, and 2360
    (`_queueScopeOperation`).
  - Keep `StateError` for disposal (2405), scenario misuse (125), and
    invariants.
  - Update the supersession assertions in `lineup_controller_test.dart` from
    `throwsStateError` to `throwsA(isA<LineupScopeSuperseded>())`. Classify
    all 25 `throwsStateError` uses; supersession cases include 7322, 8175,
    and 8304. Persistence-failure fakes that throw `StateError` (2258, 2568,
    6152, 6228) are left unchanged.
  - Check `_run` (2623-2633): it must still treat supersession under a stale
    epoch as silent.
- **Scan candidate** (`library_scan_state.dart`; a `part` of the
  controller, so the boundary is enforced by API and review):
  - `_ScanCommitCandidate {readiness, libraryIds, media, playlists, evidence, status}`;
  - `candidateFor(ids, contentScope, inventoryOrder)`, which reads the
    readiness snapshot (equivalent to live rows in practice, T1);
  - `isCurrent(c, scope)`;
  - `didCommit(c)`;
  - a restore-status method for the `selectServer` restore path and
    `lineup_scenario.dart`.

  The controller no longer touches `rows` or `status` directly. Verify with
  `grep -n "_scan\.\(rows\|status\)\b" lib/app/lineup_controller.dart`,
  which must return empty.
- **NF-08 fix.** The scan body returns a `bool committed`.
  `commitLibraryScan` returns `committed && _isCurrent(op)`. It never throws
  `LineupScopeSuperseded` for this case, because `_run` would show a visible
  error.
- **NF-07 fix (after confirmation).** At the existing publication assignment
  (LC 931), set restore intent only when `_isCurrent(operation)` and the saved
  library/channel sets are non-empty. A started successful save still publishes
  all committed state if its request epoch became obsolete; obsolete work
  merely cannot create a restore intent it will never execute. Subsequent
  `_invalidateOperation` already clears the flag. Do not clear it unconditionally
  in stale continuations: an old scan may finish while a newer restore owns the
  flag. Preserve the restartable-restore contract.
- **NF-09 fix.** The scan commit records channel revisions like
  `_commitChannelList`.
- **NF-16** (`FileAppStore.clientIdentifier`):
  - First add a POSIX test (skip on Windows): a valid ID file made unreadable
    (`chmod 000`), expecting an error and the file unchanged.
    Verify the host actually denies reading before interpreting the result;
    privileged/filesystem permission bypass is an unavailable observation,
    not a refutation. Restore permissions in teardown.
  - If confirmed, regenerate only for missing files and malformed contents.
    Catch `PathNotFoundException` for absence and preserve regeneration for
    invalid text/UTF-8 as a separate decoding case; propagate other filesystem
    read errors. A broad IO catch must not regenerate identity. Approved 2.2g.
- **NF-19 consumer.** After L merges, replace the authorization code set at
  LC 2658 with L's `PlexException.isAuthorizationFailure`. If B is already
  merged, the orchestrator applies this one-line change at L's integration.

**Steps** (one child, commit per step):

- **B0:** tests for NF-07 (preconditions: a saved, non-empty lineup for the
  target server; `_ControlledSaveStore.blockNext`; `refreshServers` during
  the save; also an old delayed scan finishing during a newer saved-server
  restore), NF-08 (a queued `selectServer` body blocked in save, then
  `commitLibraryScan` at the same epoch, then release), NF-09, and NF-16.
  Record the results.
- **B1:** scoped accessors, plus unit tests: absent-scope preservation, JSON
  round-trip byte-identical against a stored fixture, owner-account
  `profileKey` round-trip.
- **B2:** `selectServer`, keeping persist-before-retire exactly.
- **B3:** `selectProfile`, `clearSavedServer`, `initialize`, logout.
- **B4:** channel, current-channel, settings, and migration commits; delete
  `_stateSnapshot` and the override parameters.
- **B5:** scan candidate.
- **B6:** supersession type and test updates; the NF fixes confirmed in B0.

**Transitions to preserve** (T1 has the full traces):

| Case | Test |
| --- | --- |
| Server selection success | 8076 (5 variants), 7550 |
| Save failure | 8076 failure variants, 8008 |
| Refresh during save | 8464 |
| `refreshServers` during save (NF-07) | **new** |
| Logout during commit; credential-cleanup failure leaves the target published (current behavior, kept) | 8272, 8335, 8385, 7031 |
| A→B→A | 951, 4711 |
| Scan commit with a queued predecessor (NF-08) | **new** |
| Migrating scan commit records revisions (NF-09) | **new** |

**Keep.** All tests listed in T1, including those relying on runtime state
as the save base (8292, 8316, 8485, 8533). They must pass with only the
supersession-type assertion edits.

**Commands.** `flutter test test/app/lineup_controller_test.dart test/persistence`,
then the full suite, analyze, and format check.

**Completion.**

- No `PersistedState(` constructor call remains in the controller.
- The grep above is empty.
- No caller outside `_commit*`/`_publish*` writes the lineup.
- Disk JSON is byte-identical for unchanged state.
- Suspected defects are reported before and after.

**Escalate** if preserving a traced behavior requires a product choice.

### C: Playback session value and explicit reconciliation

**Design** (in `player_coordinator.dart`):

- **Active program.** Add
  `final class _ActiveProgram { request; Channel? channel; program; }` and
  one field `_active`.
  - **The channel stays nullable.** Today a channel deleted during a tune
    leaves playback running orphaned while `tune()` returns false. That
    behavior is preserved.
  - Transitions: `_commitActive`, `_releaseActive({ifRequest})`,
    `_replaceActiveRequest` (1028), `_refreshActiveChannel` (1785).
  - `_resetScopeState` and `dispose` release the whole value (equivalent;
    T2/design review).
  - `_releaseActive` replaces the conditional clears at 521, 745, 774, 811,
    816, 1675, and 1959. Sites 760 and 764 are inside the dead block and are
    deleted with it.
- **Dead code.** Delete 758-770 (749-770 is synchronous; confirmed).
- **Named predicate.** `_supersededByTune` (`_tuning || _disposed`) at 750
  and 782.
- **Serialization invariant.** Add a comment at `_tuneOperations`: tunes run
  serially, so a loser's cleanup reaches only its own load or the pending
  stop.
- **Track confirmation.** `_TrackConfirmation {type, id, timer, error}`
  replaces the four fields. `_eventVisibleFacts` (374-375) must keep
  comparing **type and id values**, never the object, because it holds a
  timer. `_trackSelectionGeneration` stays separate.
- **Reconciliation (CQ-04).** Keep the `notifyListeners` override as the
  single guarded entry point. It keeps the disposal guard at 285-286, which
  late `DisplayMatching` callbacks rely on. Restructure it as:

  ```dart
  @override
  void notifyListeners() {
    if (_disposed) return;
    if (_publishing) { _republish = true; return; }   // coalesce re-entrant publication
    _publishing = true;
    try {
      // Requests raised during _reconcile are absorbed by the notify that follows;
      // requests raised by listeners trigger one more round.
      do {
        if (_disposed) break;
        _reconcile();
        if (_disposed) break;
        _republish = false;
        super.notifyListeners();
      } while (!_disposed && _republish);
    } finally { _publishing = false; }
  }
  void _reconcile() { _updateDisplaySession(); _reconcileBusy(); }  // order matters: session before busy
  ```

  Give the override a doc comment that states this contract.

  The loop must not drop a publication that arrives during listener
  callbacks. If a nested request arrives while `super.notifyListeners()` is
  running, it requests another round. Reconciliation-origin requests are
  absorbed by the following notification. Disposal ends further rounds; this
  is a defensive lifetime guard, not permission for listeners to violate
  ChangeNotifier's synchronous-disposal contract. Verify OSD, focus, and busy
  behavior, plus a bounded listener-origin re-publication case.

  Keep:
  - the direct reconciliation in `_startLoad` (`cancelLoad` →
    `_updateDisplaySession` → `beginLoad`);
  - the `_event` ordering;
  - busy changes in `_clearTransientStatus`, now through `_reconcileBusy`.

  There are no new listenables. `PlayerTelemetry ==` comes from M.
- **NF-10 outcome (after confirmation).** Authorization recovery that only
  replaces the active request during a blocked current-channel save remains
  part of the same tune/session. Use stable session identity or explicit request
  lineage across `_replaceActiveRequest`: successful recovery completes the tune
  with the recovered request active, `_tuning == false`, no rollback, no stop,
  and no error. Failed recovery must also settle its owning tune with
  `_tuning == false`, safe failure/error publication, and matching-load cleanup;
  do not preserve a stuck-tuning early return as "existing behavior". Restore
  the previous current-channel selection only if this session still owns the
  tune/content lifetime and the failed target is still the committed selection.
  A rollback IO failure retains truthful committed state and a safe error,
  never a stuck tuning flag. A newer tune/scope remains untouched. Cover
  successful recovery, recovery failure before save release, and true
  supersession. A request-object comparison alone cannot identify supersession.
- **C4** (after B, same chat):
  - Catch `LineupScopeSuperseded` explicitly where the coordinator calls
    controller mutations (`setCurrentChannel` paths).
  - PC 1014 and 1026 are coordinator-internal playback supersession. Replace
    their `StateError` with a private `_PlaybackSuperseded` sentinel caught
    explicitly.
  - Narrow the catch-alls at 661, 808, 1065, and 1311. Expected types
    (`PlayerUnavailable`, `PlexException`, `LineupScopeSuperseded`,
    `_PlaybackSuperseded`, `TimeoutException`, `PlatformException`, and actual
    store IO failures such as `FileSystemException`) keep their current handling.
    An ordinary save failure is not a programming-error report. Anything else
    keeps the current safe user-facing error and normalized `unexpected` event,
    and also calls `FlutterError.reportError` with a **new fixed**
    `StateError('Unexpected playback operation failure.')` and fixed operation
    context. Do not forward raw `e` or `s` to logging/support output. This matches
    PC 2032's fixed-error pattern; that source does not report the caught value.
    Any developer-only stack sink needs its own explicit privacy contract and
    is outside this package.
  - No change to the diagnostics allowlist or export.
  - Fakes in the coordinator test that throw `StateError('persistence failed')`
    (6496) to mean a persistence failure may stay. If one now triggers
    `reportError` in a test that sets `FlutterError.onError` expectations,
    switch it to a representative `FileSystemException` and record that in the
    test map. Verify expected IO failures retain their current user error without
    programming-error reporting, while an unexpected safe fixture reports the
    fixed error. A token-bearing synthetic exception must not leak its payload.

**Tests.**

- **C0 (new):**
  - NF-10: gate persistence as in the test "terminal error during
    persistence restores the previous channel" (PCT 4838); emit a 401 on the
    active generation; complete recovery; release; assert `tuning`, `error`,
    stop calls, and `currentChannelId` against the NF-10 outcome above. Add
    recovery-failure and true-supersession controls.
  - Single notification: count listener calls across a display-hold
    `_finish` path; expect exactly 1 where the trace shows 2.
- **Transitions to preserve** (T2): 1919 (success); 3726-4042
  (supersession); 3793 or 3903 (Stop during load); the test named for
  native load or readiness failure (resolve by name at `7afa3688`; not
  1973, which is stop failure); 1995 and 4838 (persistence); 4583 and 4620
  (recovery); 4902-6038 (multipart); 640 (live join); 2209-2320 (tracks);
  1332, 3091, 2922 (publication); 67-433 and 1464 (busy/HDR); the
  `display_matching_test` suite.
- Also run `player_view_test.dart` 43 and 96,
  `desktop_navigation_test.dart`, and `lineup_app_test.dart` 466. These are
  read-only for C.

**Steps.** C0 tests → C1 active program and dead code → C2 track
confirmation → C3 reconciliation → report → (after B) C4.

**Commands.**
`flutter test test/playback test/app/desktop_navigation_test.dart test/app/lineup_app_test.dart`,
then the full suite.

**Completion.**

- The triple and track fields no longer exist separately.
- The `notifyListeners` contract is documented and single-notification is
  proven.
- NF-10 is settled.
- After C4, no unexpected error type is swallowed without `reportError`.
  Expected persistence IO remains expected; reports contain fixed safe data.

### D: Studio manual rundown, Air Check verification, Studio editor widgets

**D1: `ManualRundown`** (`lib/app/manual_rundown.dart`, owned by
`ChannelStudioDraft`):

- `ManualOccurrence` is an opaque identity carrying an occurrence index for
  keys.
- API (T3): `replaceFrom`, `addCurrent`, `addBatch`, `undoLastAddition`,
  `move`, `moveTo`, `reorder`, `remove`, `resolvedItems`, `snapshotItems`,
  `acceptSaved`.
- Keep the single, batch, and repeated-ID semantics exactly (T3).
- **Undo policy (approved 2.2b):**
  - the undo set **clears on `replaceFrom`**;
  - `remove` prunes the removed occurrence and clears only when the set
    becomes empty (a narrow approved 2.2b correction, **not** current behavior);
  - `move`, `reorder`, and `acceptSaved` leave it unchanged. That is current
    behavior; undo after a move or a save still works (test 4812).
- **NF-12 test:** add an item, force a conflict, "Use saved version",
  **switch to browse mode** (the button lives in the browse branch, SV
  1886-1891), then assert the button state before and after the change.
  Also cover removing the last undoable occurrence and removing only one of
  several undoable occurrences; moving/saving must retain the existing policy.
- `ChannelStudioDraft.signature`/`editedSource` read the rundown.

**D2: `AirCheckVerification`** (`lib/app/air_check_verification.dart`,
`ChangeNotifier`):

- Studio's State owns it (create in `initState`, dispose in `dispose`).
  `ChannelAirCheck` is used only by Studio (SV 474).
- **It owns projection, including the horizon (`_futureHours`) and the clock
  timer.** It recomputes the projected window and on-now comparison when
  results, horizon, or clock change, outside `build`. Projection failures
  are therefore ordinary synchronous transitions in the controller, and
  nothing calls `setState` during build.
- It also owns:
  - debounce (80 ms);
  - one active request plus the latest pending;
  - a sealed baseline:
    `BaselineLoading | BaselineAvailable | BaselineOffAir | BaselineFailed`;
  - same-key baseline recovery;
  - stale suppression;
  - the result `AirCheckResult {revisionKey, validity, preview?, error?, projectedWindow}`.
- Inject the existing schedule loader and clock.
- **One input transition.** Studio's `_updateVerification()` resolves the
  draft once, stages schedule identity, and calls
  `verification.update(preview, original, generation, sourceIssue)`.
  - It is called from `_changed`, reload, save-as-new, after save,
    `didUpdateWidget`, and `initState`.
  - It runs **outside build**: `didUpdateWidget` and `initState` are not
    build. `_changed` is a listener.
  - Remove `_stageScheduleIdentity` from `build`.
- **Commit location.** A `verification` listener commits the exact previewed
  anchor/seed when the current key's result is `valid` **or** `retainedOffAir`,
  matching today's predicate. Off-air retained manual programming remains
  repairable/saveable. Preserve one-time staging, dirty-baseline updates,
  save-as-new candidate retirement, and preview/save identity agreement.
- **Save gate** (approved 2.2a): `canSave` and `_save` share one getter.
- **Widget.** `ChannelAirCheck` becomes presentation: it observes the
  controller and keeps selection, synopsis expansion, and layout.
  - The "show more hours" button calls `verification.extendHorizon()`.
  - Delete `onValidityChanged`, `_reportValidity`, `_reportedStatus`, the
    post-frame callback in `_changesOnNow`, and Studio's
    `_isCurrentAirCheckStatus`.
- **Fallback.** If owning projection in the controller would change the
  rendered schedule or selection behavior, stop. Implement only the sealed
  baseline inside the widget, and report why. Do not relocate the handshake.
- **Tests.**
  - Re-point the queue and outcome cases in `channel_air_check_test.dart`
    at `AirCheckVerification` (about 13 constructions).
  - Keep widget tests for rendering, stale visible preview (752), the on-now
    warning (1026), and projection failure and retry (58, 103), as widget
    observations.
  - Map every moved test.
  - The transition table in T3 lists the tests to preserve.

**D3: Studio editor widgets.** After D1 and D2, split the remaining State
along T3's sections:

- title and actions;
- recovery;
- station;
- playlist editor;
- filter editor and picker, sharing one `_FilterPickerController` (required
  because of `_pickerForBrowse`);
- manual editor.

Focus nodes stay with the widget that renders them. Pass explicit
parameters.

**Render evidence for D3** (no Studio goldens exist):

1. Before D3, create an **uncommitted** scratch test file under the
   worktree's `test/_scratch/` that pumps the Studio states used by
   `channel_studio_view_test.dart` (each source type, dirty, conflict,
   saving, Air Check states) and calls `matchesGoldenFile`. Run it with
   `--update-goldens` at the pre-D3 commit.
2. After D3, run it without updating. All images must match.
3. Delete the scratch directory. Report the state list and the result.
4. Use string-literal differences as review triage. Classify internal keys,
   debug labels, and code-only identifiers separately; user-visible text remains
   unchanged except §2.2. Do not keep dead internal strings merely for equality.

D3 remains in the agreed scope. Its decomposition must remove the specific
picker/editor state coordination in T3, with explicit parameter contracts;
do not use a file-length threshold to omit it or to justify extraction. If a
newly approved mixed-source design creates an actual conflict, return the
specific conflict to the maintainer instead of silently reducing scope.

**Commands.** Focused Studio, draft, and Air Check tests; then the full
suite.

**Completion.**

- No rundown records or snapshot repair remain in the widget.
- No identity staging or validity reporting happens in build.
- One save-authorization expression.
- NF-12 is settled.
- The D3 render evidence matches (if D3 is done).

### E: Setup review snapshot and per-step widgets

**E1.** `lib/app/setup_review.dart`:

- `SetupReview {base, plan, mode, removeSourceIds, strategyBySource, finalChannels, entries, counts}`.
  It composes once per materialization.
- `withMode(mode, anchor)` re-materializes and clears the removal choices
  (current behavior, test 1095). `withRemoval(id, remove)` recomputes.
- **`missingSources` stays live:** it is computed from
  `widget.controller.isGeneratedSourceConfirmedGone` at render time, because
  it can change during review.
- `sealed SetupPhase`: `Reviewing(review, confirmed)`, `Applying(review)`,
  `Failed(review, error)`, `Completed(review)`. `_appliedEntries` becomes
  `Completed.review.entries`.
- `enum _SetupStep { libraries, configure, review, result }` replaces the
  int.
- **The `_notice` sentinel.** Keep the visible notice lifecycle identical,
  including the mode-change post-frame callback clearing all notices. Model
  "updating" as a separate field only if tests 1095 and 1509 and the notice
  rendering are unchanged. Otherwise leave the string sentinel and report it.
- Keep the fresh anchor (projection test 253) and `applyReviewedChannelPlan`
  as the expected-base authority.

**E2.** Split the step widgets: library, configure (sources, playback, rules,
order), review, and result. Use the same scratch-golden and string-literal
render evidence as D3, covering the setup states pumped by
`desktop_setup_test.dart`.

Give each step explicit immutable presentation inputs and named intent callbacks;
keep shared configuration/review/apply authority in the flow owner. Move genuinely
step-local presentation/focus lifetime with its rendering widget when semantics
permit, without resetting it unexpectedly on back/forward navigation. Do not
pass the entire parent State or create forwarding helpers that preserve every
old coupling; the extraction must clarify those responsibilities, not merely
distribute lines among files.

**Keep.** T3's setup and projection tests. **Add** `SetupReview` unit tests.

**Completion.**

- Review and apply consume one review value carried by the phase.
- No `_plan!` and no integer step.
- Render evidence matches.

### F: Native restoration classifier and native hygiene

**Design.**

- **Classifier** in `display_recovery.h` (already included by both callers;
  no CMake change):

  ```cpp
  enum class RestorationDecision { target_unknown, unresolved_attempt, already_original, external_change, restore_original };
  struct RestorationHistory { DisplayOwnership ownership; bool attempt_may_land_late; };
  constexpr RestorationDecision ClassifyRestoration(const RestorationHistory&, DisplayState observed);
  constexpr bool DurableAttemptMayLandLate(const DisplayOwnership&);
  ```

  The logic and caller mappings are in T4.
  - Live: `{record.ownership, record.unobserved_attempt}`; it keeps L0, L4,
    L6, and L7.
  - Recovery: `{own, DurableAttemptMayLandLate(own)}`.
  - Document the three divergence cases at the struct.
- **`Reconcile`.** Leave its suspend rule as is; add a comment and a test.
- **Preserve these asymmetries:** L3 ignores the `Disarm` result and sends
  no report; recovery makes a single unjournaled `Set`. Record either as a
  finding if it looks wrong. Do not change it.
- **Explicit ordinals.** `DisplayState{unknown=0,sdr=1,hdr=2}` and
  `DisplayRoute{none=0,hdr_state=1,advanced_color=2}`. Add `static_assert`s
  next to the literal wire checks at `display_recovery.cpp:76, 81-82, 94-95`.
  `display_guardian.cpp:28-35` already uses `static_cast` and needs nothing.
  The test file includes `display_recovery.h`.
- **Hygiene:**
  - one shared `Handle` RAII header;
  - `Record` helpers `Relinquish()` and `MarkGuardianLost()` (replacing the
    3× repeats);
  - in `native_player.cpp`: `QueueFullError`, `FindString`/`FindBool`, and
    one `AsciiLower`;
  - reuse `FindTrackNode` if its signature matches.
  - The `SessionState` enum is **dropped** (low value).
- **Tests to add:**
  - `static_assert` decision table;
  - live L3 (genuine external change at release);
  - live L7 (`Disarm` returns false);
  - an explicit L2 assertion;
  - divergence 1 (a fake `Execute` returns false without acting);
  - recovery with `verified==original` and an unverified opposite attempt;
  - recovery with `attempted==original, verified=hdr`;
  - R1/R3 return values, plus extending `NoActionCases` to assert results.
- **Keep:** T4's covered list.

**Verification.**

- A macOS child cannot compile these sources (Win32 headers). Its result is
  **"implemented, unverified"**.
- Verification follows §2.1.4:
  - `display_dynamic_range` and `display_guardian` CTests, which CI runs;
  - `native_player_contract` and `runner_lifecycle` (Windows host only, per
    `docs/DEVELOPMENT.md` "Current test tiers").
- Physical behavior goes to §10.

**Completion.**

- Both callers use `ClassifyRestoration`.
- No duplicate predicate remains.
- Ordinals are explicit and asserted.
- Windows CTests are green (or explicitly pending).
- An existing journal fixture still parses; add one if absent.

### L: Plex client consolidation

Runs after A is merged.

- **One pager.** A private `_pageMetadata<T>(...)` takes:
  - the request builder;
  - max pages and entries (use the named constants; replace the three
    hard-coded `page < 1000`, **keeping each endpoint's current effective
    limit** unless a test shows the constant was intended);
  - a per-page callback (dedup or parse);
  - `checkCurrent`;
  - the endpoint's error codes.

  Migrate `libraryItems`, `_libraryMetadata`, `_playlistCatalogRaws`, and
  `_playlistItemRaws`. Their error codes and duplicate-key policies stay
  exactly as they are.
  - Preserve `allowOversizedComplete` for endpoints that permit a complete
    oversized envelope, raw-row offset/count accounting, total/size validation,
    progress/check ordering, and repeated media occurrences in order; duplicate
    supplied `playlistItemID` values remain invalid.
  - Preserve endpoint-specific exception **types** as well as codes/messages:
    collection callers distinguish `_LibraryMetadataPageLimitException` from
    other scale failures to classify paging versus listing/member limits.
    Supply an explicit limit-exception factory/policy; do not flatten that subtype.
  - Build a small endpoint-policy matrix from the four current loops before
    extraction and map every differing policy to retained tests. The existing
    thousand-page classification test near `plex_library_scan_test.dart:672`
    must retain its distinct outcome.
- **Cancellation.** One helper joins caller and local abort futures (565,
  779, 875, 1302). Use `_scanCancelledException` everywhere.
- **Error categories.** `PlexException.isAuthorizationFailure` and
  `isCancellation` getters in `plex_models.dart`. Use them at 276, 626, and
  913. The LC 2658 use belongs to B or the orchestrator (§7.B).
- **Tagged copy.** A `PlexMediaItem.withTags({collections, genres})`
  constructor next to `_immutable` replaces the 33-field manual copy in
  `_annotateLibraryItem`.
- **Tests.**
  - Keep all `plex_transport_test.dart` and `plex_library_scan_test.dart`
    cases; T6 cites the bad-page matrix at 400-430.
  - Add one test per pager showing the max-page bound is enforced with the
    current limit.

**Completion.**

- One pager and one cancellation join.
- No `page < 1000` literal.
- No hand-written 33-field copy.
- Full suite green with an unchanged test count plus the additions.

### S: Domain small consolidations

- **Schedule worker** (NF-21). Private record or sealed message types
  replace the positional lists. A failed decode completes the matching
  pending request with an error; it does not throw after
  `_pending.remove`. Unexpected worker failures carry their message and
  stack as a `RemoteError` to the caller; keep the current user-facing
  "could not build the schedule" path. Keep all 9 `schedule_worker_test.dart`
  cases and add a malformed-message test.
  Application bootstrap/request/result messages become typed. VM-origin
  `onError` two-element lists and null `onExit` remain explicitly decoded
  boundary signals. Malformed payload with a valid pending ID completes that
  request with an error; an uncorrelatable message fails startup/current waiters
  and retires that generation. Valid unknown IDs and retired-generation
  messages remain ignored. Test both correlated and uncorrelatable failures.
- **Series rule** (NF-22). One private `_seriesKey(ChannelItem)` used by
  both the specials filter and block grouping. Keep `scheduler_test.dart`.
- **Filters** (NF-22). `addTags` takes a `LibraryFilter`.
  `libraryFacetValues(item, filter)` in `library_facets.dart` is used by the
  builder and the facets. Keep `channel_builder_test.dart` and
  `content_resolver_test.dart`.

**Completion.** No positional application-owned isolate messages (VM signals
remain decoded); one series rule; no
string-named filter lookups.

### V: Guide notification discipline

- **Confirm NF-29 first.**
  - Copy the setup of the test at `guide_controller_test.dart:55`, add a
    listener counter, and call `currentProgram(id, boundary)` where the
    schedule throws at the boundary. Assert the row state and the counter.
  - Separately, count notifications for one row load.
- **Fixes.**
  - Publish once after completion bookkeeping and pumping when an observable
    changed. Stale completion still decrements `activeLoadCount` and can start
    queued work; GuideView uses that count for its activity pulse. Do not remove
    those meaningful notifications merely because the row result was stale.
    Add stale-final-load and stale-completion/current-queue regression cases.
  - Projection failures discovered by a query from `build` are published
    through a coalesced, disposal/currentness-guarded post-frame notify, not a
    silent mutation or synchronous notify during build.
  - Correlated selected and preserved pairs become nullable records. Leave
    the inspection triple alone (T7).
  - `guide_view.dart` requests the viewport only when demand changes, including
    (first, count, channel snapshot, content/schedule generation). Equal IDs and
    range do not suppress a request after the controller invalidates schedules.
- **Keep.** `guide_controller_test.dart` and `guide_view_test.dart`,
  including the 1000-channel profile tests. Report their `GUIDE_PROFILE`
  numbers before and after; they must not regress materially.

**Completion.** One completion publication for changed observables, including
load-count changes from obsolete work; no silent query mutation; same-ID
content invalidation still reloads visible schedules.

### W: Channel health monitor

- Add `ChannelHealthMonitor extends ChangeNotifier`
  (`lib/app/channel_health_monitor.dart`) with `request(channel)`,
  `issueFor(id)`, and invalidation on `contentGeneration`. It keeps the
  current concurrency (2), pending queue bound (12), LRU size (1000), epochs,
  content/channel-revision signatures, and same-channel serialization.
- `ChannelsView.build` only reads from it. Requests are issued from
  `didUpdateWidget`, `initState`, or the visible-item callback, not by
  mutating inside `build`. If visible demand is discovered during item building,
  collect and coalesce it for a guarded post-frame transition; do not call a
  queue-mutating `request` synchronously from `itemBuilder` under a new name.
- Add unit tests for the monitor.
- Keep `channels_view_test.dart`. Run (read-only)
  `channel_studio_view_test.dart` 4079-4217; if those fail, report to the
  orchestrator.

**Completion.** No job queue state remains in the widget, and `build` has no
side effects on health state.

### K: Typed diagnostics events

Wave 2, after B, C, and V have merged.

- Add `enum DiagnosticEvent(area, message)`. `Diagnostics.add` takes it.
- The allowed set becomes `DiagnosticEvent.values`.
- Share per-key policy definitions while keeping **separate storage sanitation
  and export admission** operations. Today ingest retains syntactically safe
  tokens verbatim and replaces unsafe strings with `unexpected`; export admits
  only recognized categorical values, normalizes their case, and omits unknowns.
  The diagnostics UI displays stored context, so changing storage to export
  policy would alter behavior. Preserve validation of directly constructed
  snapshots/entries as well as ordinary producer output.
- Migrate the actual call sites (17 admitted event pairs, about 30 producer
  calls; re-inventory on the post-owner-merge base).
- **The support report output is byte-identical.** Add a golden-text test of
  fixed snapshots before migrating and keep them passing. Include mixed-case
  recognized values, safe unknowns, unsafe strings, invalid primitives, and
  forged entries, and assert retained in-memory/UI values separately.

**Completion.** No string pair is used to admit an event; the report test
passes.

### U: Shell and Player interaction consolidation

Wave 2, after C has merged.

1. **Badges** (NF-23, approved 2.2c/2.2d).
   - First, the confirming test: Now Playing with `dynamicRange: 'unknown'`;
     expect no "UNKNOWN".
   - Then one pure
     `mediaBadges(item, {required MediaBadgeSurface surface, bool runtimeHdr,
     String? effectiveVideoCodec})` (or leave codec composition outside it).
     Per-surface differences are kept by the `surface` parameter. Only
     `unknown` and the channel-label mismatch change.
     Preserve Now Playing codec precedence:
     `telemetry.videoFormat → item.videoCodec → telemetry.videoCodec`, through
     the current formatting helper. Add a regression for the runtime override.
   - Unit-test the function. Update `player_view_test.dart:5198` (it uses a
     non-canonical `'SDR'`) to the canonical value.
2. **Shell destinations** (NF-24).
   - `enum ShellDestination` replaces route ints and the `views` index; use
     a switch instead of a list index.
   - App-menu state becomes one nullable record.
   - Settings use a typed key with
     `Map<key, _PendingSave(change, timer, showSaving)>` plus errors, and
     one `_settingControl` helper.
   - Add a `commandModifier` helper in `navigation_shortcuts.dart` that
     returns Ctrl on all platforms **for now**. The macOS ⌘ decision is §9;
     this creates the single seam.
3. **Modality** (NF-25). First run `git log -L` on the Player's hover reset
   (`player_view.dart:450`) and the shell's pointer-down reset to establish
   intent.
   - If they are deliberate, document them in `lineup_focus.dart` and stop.
   - If history is inconclusive, preserve current reset behavior and report the
     evidence; silence in history does not establish that it was accidental.
   - If they are accidental, expose `lastInputWasKeyboard` from
     `LineupFocusScope` and replace the separate handlers, keeping the
     Player hover reset if it was intended.
     Actual input modality must stay distinct from focus-ring visibility:
     focus visibility currently responds only to navigation keys, while Player
     and shell observe all key-down/repeat input. Preserve the Player's
     `handlePointerActivity()` call independently of shared bookkeeping.
   - Report which path was taken.
4. **Player key resolver** (NF-26). A pure
   `resolvePlayerKey(key, overlay, dvr, unsupported, initialPress, hasProgram) → PlayerCommand`
   with table tests. The State executes commands, and the sleep picker
   closes once in the executor. Keep the `LayerLink` in State, and use one
   poster-path function for the Guide and the Player.
5. **Presented state** (NF-27). Coordinator getters `watchingChannelId` and
   `presentedState`. Replace the duplicated expressions and the duplicated
   status `Text`.

**Render evidence.** Same scratch-golden method as D3, for the Player
OSD/Now Playing/Mini Guide states and the shell routes. It must match,
except for the approved 2.2c/2.2d badge differences, which are listed
explicitly.

**Keep.** Tests named in T7 for each item.

**Completion.** No int routes; one badge rule; one key-resolution table; the
modality outcome reported.

### Y: Onboarding state

Wave 2, after B has merged.

- A sealed `_ServerAttempt` state replaces `_serverError` + `_failedServerId`.
- The controller exposes `pinUsable`/`pinExpired` using an injectable clock.
  Remove the widget's duplicate expiry rule.
- Keep `desktop_onboarding_test.dart` 779, 830, 869 and
  `lineup_app_test.dart` 938. Add before/exactly-at/after-expiry clock tests.
  Use the approved 2.2h boundary (`now >= expiresAt` means expired) consistently
  for polling and projection; preserve secure-cancellation/error gating and
  the displayed countdown. Record the exact boundary in the clock tests.

### G: Documentation consolidation and branch-repair proposal

Wave 3, after the final code review.

1. **Register.** Add `docs/open-obligations.md` with columns: obligation,
   source §, platform, status, evidence. Populate it from the active and
   completed plans (T5), this plan's §10, and H's `DEVELOPMENT.md` sentence.
2. **Archive** only after preserving open obligations **and** still-useful
   design rationale, source/build identities, and attributed evidence. Each
   historical source in the register needs a recoverable full-commit `git show`
   reference or a retained current authority; a link to a file about to be
   deleted is insufficient. If a listed document still uniquely owns a live
   contract, migrate that contract to its current owner before deleting it;
   otherwise retain the document and explain why. Candidate deletions:
   - `desktop-ui-implementation-plan`, `desktop-ui-execution`,
     `desktop-ui-readiness-review`, `desktop-ui-scaling-progress`
   - `ui-parity`, `fullscreen-hdr-discovery-plan`,
     `windows-collaborative-acceptance-handoff`
   - `setup-reentry-startup-plan`, `player-guide-polish-plan`
   - `code-quality-refactor-planning-handoff`; update this plan's input links
     to a `git show` reference.

   **Keep:** `feature-opportunity-report` and `opus-feature-research-request`
   (pending feature-track inputs), `feature-validation-findings`, and every
   product or design decision record (T5).
3. **Index.**
   - Remove the absent-file entries.
   - Date-label `product-parity.md`.
   - Fix root `README.md:107` (`ui-parity` link) and `CONTRIBUTING.md`
     links.
   - Links inside `docs/reviews/**` to archived documents are historical and
     **exempt** from the dangling-link check.
4. **Platform framing.**
   - In `architecture.md`, separate the platform-neutral protocol section
     (link `native-player-protocol.md`) from the Windows presentation
     section.
   - In `.agents/project.md`, update the renamed paths, the new owners, and
     the macOS line ("development surface; native playback not yet
     implemented; see `docs/native-player-protocol.md`").
5. **Branch-repair proposal**, as text in the completion report (the
   maintainer executes it):
   - make the Flutter line the default branch;
   - delete merged or stale local branches (`worktree-agent-*`, `rd-*`
     without upstream, gone upstreams);
   - optionally tag `electron-ui`/`initial-build`.
6. **Closure.** Mark this plan's packages with merge SHAs after the final
   review. Move unfinished rows to the register.

**Commands.**

- `git diff --check`.
- A scratch link check over `docs/**/*.md`, `README.md`, and
  `CONTRIBUTING.md` (excluding `docs/reviews/**`).
- A grep showing that no live document links a deleted file.

## 8. Integration, review, and verification gates

### 8.1 After every merge (orchestrator, main checkout)

```sh
export PATH="$HOME/.cache/lineup-flutter/3.47.7/flutter/bin:$PATH"
dart tool/format.dart --check          # includes the toolchain check after H
flutter analyze
TZ=America/New_York flutter test       # count recorded; changes must be mapped
```

Also run `flutter build macos` after M and at the end, and F's Windows CTests
per §2.1.4.

### 8.2 Review

Use the `reviewer` preset in a separate chat, read-only, with the package
diff, its §7 section, its trace section, and the test map.

| Packages | Review |
| --- | --- |
| B, C (once, after C4), D, F, L, U | Required, before merge |
| A, E, M, S, V, W, K, Y | One combined review after their merges |
| H, T, G | Orchestrator inspection |

The orchestrator adjudicates findings using `review-code`. A final
whole-branch code review runs before G. It focuses on composition:

- B↔C supersession type;
- M↔C telemetry;
- B↔L authorization getter;
- K's call sites across B, C, and V;
- U's coordinator getters.

### 8.3 Invariants at every gate

- **Persisted state.** The JSON round-trip test (B) passes. The journal
  fixture parses (F). The protocol conformance suite passes (M).
- **Goldens.** `git diff --stat <pre>..<post> -- tool/visual/goldens test/**/goldens`
  is empty.
- **Visible text.** For packages other than D3, E2, and U, review every
  changed string literal in the `lib/` diff
  (`git diff <pre>..<post> -- lib | grep -E "^[+-].*'[^']*[A-Za-z] [A-Za-z][^']*'"`
  as a starting filter). For D3, E2, and U, classify the string-literal-set diff
  as review evidence: deleted internal settings keys/debug labels and new
  internal identifiers are allowed when justified. Require preservation of
  user-visible text except accepted §2.2 differences; never retain dead strings
  to satisfy an all-literals equality gate.
- **Privacy.** No credentials, tokens, or private media identifiers in
  tests, docs, or reports.
- **Tests.** Record counts relative to each actual package base and explain
  changes. Preserve distinct behavioral obligations, including moved or
  consolidated tests, through the old-obligation → retained-evidence map.
  Counts do not have to be monotonic and do not justify losing proof.

### 8.4 Plan completion

Full code integration is complete when all of the following hold:

- every package meets its completion criteria;
- review findings are adjudicated;
- the §8.1 gate is green on the integration head;
- `flutter build macos` is green;
- F's required Windows CTests are green on its candidate and F is integrated;
- G is delivered;
- accepted worktrees and merged task branches are cleaned up (§6.2.7).

If F lacks Windows CTests, report **portable packages integrated; native
candidate pending; plan not fully complete**, retain its branch/worktree, and
record the outstanding tests in G's register. G can document that partial
delivery without representing F as integrated. When Windows proof arrives,
rebase/recheck the F candidate, integrate it, rerun affected combined checks,
and update closure. Physical Windows acceptance in §10 remains a separate
status even after every deterministic code gate passes.

Push, PR, and merge remain maintainer actions.

## 9. macOS strategy and deferred port backlog

### 9.1 Repository strategy (recommendation)

Use **one repository and one Flutter application, with macOS as a second
platform implementation.** Do not fork.

- About 40k lines of `lib/` and about 65k lines of tests are
  platform-neutral policy (controller, scheduler, Plex, Guide, Studio, Player
  UI). A fork duplicates all of it, and every fix then has to be ported
  twice.
- The platform-specific surface is narrow by design: the native player
  handler and presentation, the runner, packaging, and CI jobs. Flutter's
  `windows/` and `macos/` directories already separate it. Package M makes
  the Dart seam explicit and documents the protocol.
- If isolation is wanted while the macOS player is experimental, use a
  long-lived `platform/macos` branch off the repaired default branch and
  merge into it regularly.
- A separate repository is justified only by a deliberate product
  divergence, or by a distribution or licensing constraint the Windows build
  cannot share (for example App Store sandboxing versus LGPL libmpv
  linking). Decide that explicitly.

### 9.2 Decisions required before macOS media work

1. **Media engine.**
   - libmpv (render API into a `CAMetalLayer`/`NSView`; reuses the protocol
     vocabulary). Recommended for parity; it needs a spike.
   - AVFoundation (must synthesize the mpv properties; narrower format
     support).
2. **Presentation.** A native layer under a transparent Flutter view, which
   needs the Guide alpha proof on a signed build, versus a Flutter `Texture`,
   which contradicts `architecture.md` (`design-code` decision).
3. **Fullscreen.** The green button and the `toggleFullScreen:` menu item
   bypass Dart. Add a native→Dart fullscreen event (protocol change) or have
   the runner intercept them.
4. **Keyboard.** ⌘ vs Ctrl (U adds the seam). Wire `Preferences… ⌘,` to
   Settings.
5. **Copy.** "Switch Windows HDR…", the diagnostics "Windows display" row,
   and the unsupported-playback slate.
6. **HDR.** macOS EDR is system-managed: report `unavailable` or a new
   session state.
7. **Distribution.**
   - Signing, hardened runtime, notarization, libmpv embedding.
   - Verify `Process.run('open')` and keychain access under the sandbox.
   - Bundle-ID continuity: a new ID starts with empty data.
8. **CI.** The full portable suite on macOS; a native macOS test target.

Optional: `docs/design/` tracks about 36 MB of images. Put future visual
evidence in release assets or LFS. Do not rewrite history.

### 9.3 Presentation obligations for any platform

These come from `NativeVideoSurface` and the Windows implementation (T5).

1. Real alpha compositing under the transparent Flutter routes, matching the
   exact Guide alpha.
2. The rect is in logical units with a top-left origin. Windows multiplies by
   `scale`; AppKit uses points with a bottom-left origin unless the view is
   flipped.
3. Keep the rect across load and stop; hide the video on a zero rect or when
   minimized.
4. The video is passive: no hit-testing, focus, or accessibility.
5. `setFullscreen` completes after the transition.
6. The token-safety contract in `native_player.dart`.

## 10. Windows physical-acceptance checklist (batched)

The maintainer runs these in one full-app pass after integration. Record the
commit, engine and libmpv identities, hardware, display, and result.

| Row | Pkg | Scenario |
| --- | --- | --- |
| W1 | C | Tune, rapid channel surf, Stop during load, retry |
| W2 | C | Multipart program across a part boundary, with a seek near it |
| W3 | B, C | 401 during playback, and during a tune while the current channel saves |
| W4 | C, F | HDR content on an HDR display: hold, match, release on stop and on exit |
| W5 | F | External HDR toggle during playback; kill the process, then restart and restore |
| W6 | F | Display target change during a session |
| W7 | B | Profile switch, server switch, logout with playback active; leave and return to a server |
| W8 | D | Studio rundown edit, save, conflict reload, undo state; Air Check gating with a slow worker |
| W9 | E | Setup review: mode change, removal confirmation, stale apply |
| W10 | M | Start, play, diagnostics: native-ready behavior unchanged |
| W11 | U | Player keyboard and remote keys across overlays; Now Playing badges; shell navigation |
| W12 | A, L | Full library scan on a real server; playlist catalog; collection membership |

## 11. Orchestrator kickoff prompt

For a complete copyable prompt with explicit defaults, use
[the orchestration handoff](code-quality-orchestration-handoff.md). The template
below remains useful when the maintainer chooses a different Windows route.

Paste this into a new Codex chat with the selected high-reasoning
orchestrator after completing §2.1 items 1-2 (or authorizing the orchestrator
to do item 2):

```text
Use the orchestrate-implementation-chats skill to execute
docs/code-quality-implementation-plan.md (revision 3) in
/Users/tristan/Software/LineupDesktop.

This turn authorizes:
- Creating separate Codex child chats for packages A, H, T, M, B, C, D, E, F,
  L, S, V, W, K, U, Y, G and reviewer chats per §8.2, choosing worker_luna or
  worker per §5 (read .codex/agents/*.toml; pass model and thinking
  explicitly). Children may send completion and blocker callbacks to this chat
  only, and must verify this authorization per the skill.
- Git per §2.1.3: switch the main checkout to codex/code-quality-2026-10 at
  BASE_SHA <fill in>; create worktrees ../LineupDesktop-<pkg> on cq/<pkg>
  branches from the current integration head (never from main); local commits;
  fast-forward integration; cleanup of those worktrees and merged cq/* branches.
  Children commit only on their own cq/<pkg> branch.
- §2.2 behavior changes: <"all accepted" | list declined rows>.
- Package F Windows verification: <"I will provide a Windows host for all required
  CTests" | "keep F unmerged pending Windows CTests">. Any later CI push needs
  separate explicit authorization and proves only its selected targets.

Not authorized: push, PR, merge to main, deleting pre-existing branches, golden
updates, user-visible changes outside §2.2, persisted/wire format changes.

Run the P0 preflight (§6.2.1) first. Follow waves (§5.1), ownership (§5.2), the
handoff packet (§6.5), completion reports (§6.6), and gates (§8). Escalate
consequential decisions; resolve routine ones. With children in flight and
nothing independent left, end your turn and let callbacks resume you.
```

## 12. Review-finding disposition (revision 1 → 2)

| Source | Finding | Disposition |
| --- | --- | --- |
| Executability | M's rename breaks C's test file in the same wave | M moved to wave 0c and owns every rename reference |
| Executability, Factual | §1 Git state stale; TRACES not committed at P0 | §1 rewritten; anchor-commit convention; P0 commits TRACES |
| Executability, Factual, Design | Supersession conversion incomplete; PC 1014/1026 misdescribed; test assertions | B converts 1671, 1737, 2124, 2360 and updates the classified assertions; C4 adds a private sentinel for 1014/1026 |
| Executability, Factual, Design | C4 diagnostics stack impossible | Replaced with `FlutterError.reportError` (existing pattern); no allowlist change |
| Executability | C4 lifecycle undefined | §6.3 |
| Executability | Worktree and sandbox mechanics; integration checkout; cleanup | §6.2 preflight, main checkout switch, rebase in worktree, cleanup |
| Executability | H breaks `format_test`; "one source" contradiction; `runInShell`; pwsh | H owns `format_test` with a skip flag; goal is "checked consistency"; `runInShell`; CI proves pwsh |
| Executability | F unverifiable on Mac | "Implemented, unverified"; merge gated by §2.1.4 |
| Executability | Line anchors shift | Anchor-commit convention with `git show` |
| Executability, Factual | No Studio/Setup goldens | Scratch-golden plus string-set evidence for D3, E2, U |
| Executability, Design | Undecided behavior changes | §2.2 approval table; undo narrowed; null channel preserved |
| Executability | G link cleanup scope; active docs deleted | G owns root README/CONTRIBUTING; reviews exempt; feature docs kept |
| Executability | A ownership gaps; version duplication | A owns the version files; consistency test; T6 mapped |
| Executability | H authored without strict analyzer | H merges after A; it is re-analyzed at merge |
| Executability | `part` privacy | API plus a grep criterion |
| Executability | Fallback rationale; factory on Linux | Rewritten; injected booleans; generic non-macOS message |
| Factual | NF-08 mechanism wrong | Restated as the queued-predecessor path at 1043-1045 |
| Factual | NF-07 test preconditions | A saved, non-empty lineup is required |
| Factual | A "fails before" cases | Limited to non-list containers |
| Factual | Undo-after-move behavior | Preserved (2.2b narrowed) |
| Factual | Preset filename; 26 subclasses; 30 call sites; test anchors 1973 and 4004; literal sites; casts 478/489 already guarded | Corrected |
| Factual | `native_unavailable` and the `MissingPluginException` remap | Dropped; documented as version skew in the protocol |
| Factual | T4 queue eviction incomplete | Corrected in TRACES and in M's documentation task (verify against source) |
| Design | A treats malformed structure as absent → false "gone" evidence | Structural malformation becomes a typed failure (2.2e) |
| Design | D2 synchronous projection failure during build | The controller owns projection, horizon, and clock outside build |
| Design | Derivation base for non-lineup fields | Explicit `_persistedFromRuntime` preserves today's semantics; `profileKey` naming |
| Design | NF-08 throw is user-visible | `bool committed` return |
| Design | E freezes `missingSources`; notice lifecycle | Stays live; notice lifecycle preserved or the sentinel is kept |
| Design | Removing the notify override drops the disposal guard | The override is kept as the guarded single entry, with coalescing |
| Design | T shared player emits events | Inert by default; emission opt-in; state check |
| Design | M message rename inconsistent with native | Messages kept |
| Design | `SessionState` enum low value | Dropped |
| Design | D3 before mixed-source design | Kept, with an explicit deferral rule |
| Design | Scope: PlayerView, GuideView, and Shell unexamined | Gap sweeps added packages U, V, W, Y |
| Gap sweeps | Plex paging, diagnostics, worker, scheduler, builder, UI items | Packages L, K, S, V, W, U, Y; suspected defects confirmed by tests first |
| Gap sweeps | PlexClient interface or file split | Rejected (T6): one production consumer; no defect; fakes kept |

## 13. Final-readiness corrections and execution handoff (revision 2 → 3)

The saved TRACES file already contained T6 and T7 when this review began.
Both sections were reviewed and their remaining factual errors corrected;
they were not reconstructed from the interrupted chat's last status message.

The final pass accepted source-supported corrections to NF-07 restore intent,
NF-10 request replacement during persistence, expected IO failures and sanitized
error reporting, profile credential publication, native queue eviction,
pending-native delivery status, rundown undo policy, Air Check retained-off-air
authorization, runtime codec precedence, Guide activity publication and content
invalidation, the health queue bound, modality, pager policies, diagnostics
storage/export differences, and VM isolate signals. It also removed raw test-
count/literal-set gates and the line-count-based D3 deferral.

See [the review record](reviews/code-quality-2026-10-15/FINAL_REVIEW.md) for
evidence and dispositions, and [the execution handoff](code-quality-orchestration-handoff.md)
for a copyable authorization prompt. Implementation readiness means the design,
ownership, execution path, and required confirming tests are specified. It does
not mean suspected failures were reproduced by this review, product tests were
rerun, or Windows/native behavior was accepted. P0 still establishes the actual
baseline and execution source before any product edits.
