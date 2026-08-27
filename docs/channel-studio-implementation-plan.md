# Channel Studio Implementation Plan

Status: Gate A reviewed and corrected on 2026-08-27; implementation must not
start until the fresh-session Gate B review passes

Locked product contract: [Channel Studio Product and UX Specification](channel-studio-spec.md)

Source baseline inspected while authoring this plan:
`65082bce82f005c1ff8842b887e1a27a39115203`

Gate A baseline: **the current-session handoff supplies the exact pushed commit;
Gate B must start at that commit rather than the repository default branch**

Slice 1 start baseline: **record in the fresh orchestrator's acceptance ledger
after all Gate B plan corrections are committed and pushed; do not write a
self-referential pre-implementation commit hash into this file**

## Objective

Implement the locked Channel Studio specification as one Desktop-owned Flutter
feature without replacing Generate Lineup, adding a second lineup, changing the
cyclic scheduler into a broadcast scheduler, adding a dependency, or moving any
product behavior into native code.

The implementation ends with one number-ordered lineup and two creation paths:

- **Generate lineup** creates and refreshes generator-owned channels.
- **New channel** opens Channel Studio to create one custom channel.

Channels, Guide, and Player continue to consume the same persisted `Channel`
objects and the same content resolver and scheduler.

## Ponytail decision

Apply Ponytail at **full** intensity throughout this plan. The smallest complete
implementation is to extend the owners already present:

- `Channel.builderKey` remains the sole generated/custom ownership seam.
- `Channel`, the current content sources, and the current persisted lineup remain
  the data model. Do not add a draft database or a second channel schema.
- `LineupController` remains the only durable mutation and rollback owner.
- `resolveContent`, `buildSchedule`, `programAt`, and schedule-window projection
  remain the scheduling path used by Studio, Guide, and Player.
- Studio draft state stays in the Studio route/widget until save.
- Existing Flutter and Dart libraries are sufficient. `pubspec.yaml` and native
  platform code are outside the implementation scope.

Ponytail does **not** permit simplifying away custom-channel protection, stale
edit rejection, atomic rollback, fail-closed filters, unavailable-item
retention, deterministic preview, accessibility, or the required responsive
states. Those are explicit correctness and product requirements.

## Baseline facts that the fresh session must reconfirm

At the authoring baseline:

- `lib/app/channel_setup_view.dart` owns the three-step Generate Lineup UI,
  materialized-plan review, impact counts, confirmation, and completion state.
- `lib/channels/channel_builder.dart` owns proposals, stable `builderKey` hashes,
  plan materialization, build modes, variants, and number allocation.
- Replace currently allocates as if no channel numbers are reserved, and
  `LineupController.applyChannelPlan` replaces the entire lineup.
- Merge matches generated channels by `builderKey`, but a changed match currently
  resets its visible name, anchor, and seed.
- `lib/app/lineup_shell.dart` owns Channels management and the current modal
  `ChannelEditor`. Source shape, as well as `builderKey`, currently determines
  whether programming is editable.
- `lib/channels/content_resolver.dart` silently ignores unknown filter keys or
  unsupported sort values. A stored manual source resolves its retained snapshot
  even if its Plex item is no longer in the current playable inventory.
- `lib/channels/scheduler.dart` is deterministic and pure. `scheduleWindow`
  silently stops at 1,000 projected programs.
- `lib/channels/schedule_worker.dart` is the existing isolate-backed resolver and
  schedule builder used through `LineupController.loadScheduleFor`.
- `LineupController.saveChannel` serializes mutations and rolls back failed
  persistence, but it is an upsert and has no expected-base check for an editor
  that has become stale.
- `LineupController.playbackFor` searches only `availableMedia`, while schedule
  resolution also accepts `availablePlaylists`; a playlist-only item may
  therefore appear in Guide/Air Check but fail to tune.
- `GuideController` already rejects stale asynchronous schedule results and
  bounds its row/schedule work. Its behavior is evidence, not a reason to create
  a new state-management layer.
- The first-release source model already represents a library, one value per
  filter key, a playlist, retained manual items, and a preserved mixed source.
  Repeated values for one filter key are not representable and must not be
  offered.

If any of these facts changed at the recorded Slice 1 start commit, update this
plan before editing production code.

## Cross-slice invariants

Every slice and reviewer must preserve these contracts:

1. `builderKey != null` is generator-owned; `builderKey == null` is custom-owned.
   Source shape never decides ownership.
2. Generate Lineup never removes, renumbers, or mutates a custom channel in any
   mode. Custom channel numbers are reserved before generated allocation.
3. Refreshing a matching generated channel preserves its ID, number, visible
   name, anchor, and shuffle seed while updating generator-owned source,
   playback mode, and block size.
4. There is one persisted lineup and one `Channel` serialization. No draft,
   recipe, or Studio state is persisted separately.
5. A Studio save is one serialized controller operation and one durable state
   write. Failure restores the exact prior lineup and leaves the complete draft
   editable.
6. Editing uses an expected base. A deleted or externally changed channel cannot
   be silently recreated or overwritten by a stale Studio draft.
7. Unknown filters and unsupported filter values fail closed. They never broaden
   resolved content.
8. Retained hand-picked records remain in `ManualSource` until the user removes
   them. Only currently playable Plex items enter the active schedule.
9. Air Check uses the draft's exact ID, source, mode, block size, anchor, and
   seed and the same resolver/scheduler path as Guide and Player. No widget may
   reimplement scheduling.
10. A new draft fixes one anchor and seed after its first successful resolution;
    save uses those exact values. An edit or duplicate preserves the existing
    scheduling identity required by the specification.
11. Async preview work is debounced, has at most one active request plus one
    latest pending snapshot, and rejects results from an older snapshot, content
    generation, or disposed route.
12. Generated/custom ownership, selection, availability, and validity are
    textual or semantic as well as visual. Every reorder action has a visible,
    keyboard-operable alternative.
13. The management rail remains the top-level navigation owner. Studio is a
    full page inside Channels, never a modal or a sixth top-level destination.
14. No slice adds dayparts, fixed starts, filler, exports, transcoding, arbitrary
    rules, station artwork, a WebView, native C++, or a new dependency.
15. Documentation continues to distinguish implemented, deterministically
    tested, platform validated, and supported behavior.
16. Any playable item accepted from the current playlist inventory is also
    discoverable by the controller's single playback lookup. Preview, Guide,
    and Tune in cannot disagree merely because an item is outside selected
    libraries.
17. A full 1,000-number lineup has an explicit no-number-available state. New
    and duplicate drafts never fall back to an occupied number.

## Acceptance ledger

The fresh orchestrator must maintain a copy of this ledger in its working notes.
An item is complete only with a commit and observed evidence; prose assertions
do not count.

| ID | Locked outcome | Owning slice |
| --- | --- | --- |
| PN-1 | One number-ordered Channels list with textual ownership | 3 |
| PN-2 | New, edit, inspect, and duplicate open the correct full-page mode | 3 |
| PN-3 | Studio is neither a Generate Lineup step nor top-level navigation | 3 |
| PN-4 | Generation completion offers View lineup and Add a custom channel | 3 |
| OP-1 | Replace/add/refresh protect all custom channels | 1 |
| OP-2 | Generated allocation reserves custom numbers | 1 |
| OP-3 | Refresh preserves generated identity and user-visible station fields | 1 |
| OP-4 | Duplicate creates a new custom ID/free number and copies the recipe | 3 |
| OP-5 | Save failure rolls back while preserving the draft | 3 |
| OP-6 | Stale edits cannot overwrite newer state | 3 |
| OP-7 | A full number space produces an explicit unsaveable draft state | 3 |
| AU-1 | Every supported first-release source is authorable | 4 |
| AU-2 | Hand-picked search, facets, bulk actions, and ordering are complete | 4 |
| AU-3 | Unavailable hand-picked items are retained and identified | 4 |
| AU-4 | Plain-language playback and block-size rules map exactly to scheduler | 4 |
| AC-1 | Air Check and saved Guide/Player use the same resolver/scheduler result | 5 |
| AC-2 | Air Check exposes timing, counts, duration, reason, and failures | 5 |
| AC-3 | Unsupported filters fail closed | 2 |
| AC-4 | A new saved channel retains the previewed anchor and seed | 5 |
| AC-5 | Playlist-only scheduled content is discoverable by playback | 2 |
| UX-1 | Compact and expanded layouts retain Air Check and remain full-page | 6 |
| UX-2 | Pointer reorder has visible keyboard alternatives | 6 |
| UX-3 | Focus, semantics, live regions, text scale, motion, and focus settings pass | 6 |
| UX-4 | Required viewport matrix has no overflow or unreachable primary action | 6 |
| UX-5 | Large-library filtering and preview are bounded and stale-safe | 6 |
| RG-1 | Existing setup, Guide, Player, persistence, and 1,000-channel suites pass | 7 |

## Review gates before implementation

### Gate A — review and correction in the current session

This is the user-requested first review. A reviewer must read the complete
specification, this complete plan, the required repository documents, and the
current source/tests named under Baseline facts.

The review must check the checklist near the end of this document, identify
specific omissions or incorrect file/owner assumptions, and apply accepted
corrections to this plan. Do not begin Slice 1 in the same review pass. Commit
the specification, plan, navigation references, and accepted plan corrections
coherently, then push them. Record the pushed commit in the handoff.

**Gate A result, 2026-08-27:** passed after correcting four confirmed gaps:
playlist-only playback lookup, exact pushed-branch startup for Gate B, the full
1,000-number draft state, and one Channels-owned asynchronous leave guard. The
documentation index was also corrected to link this plan. No implementation
work was started during the review.

### Gate B — fresh orchestrator review and correction

The fresh orchestrator must start from the exact pushed `flutter-mvp` commit
produced by Gate A and supplied in the handoff. The repository default branch is
`main`; it is not an acceptable implicit starting point for this work.
Before dispatching an implementation worker it must:

1. Verify `git status --short` is empty and `git rev-parse HEAD` exactly equals
   the Gate A handoff commit. Do not continue from `origin/HEAD`, `main`, or an
   older `flutter-mvp` ref. A generated worktree branch need not already have an
   upstream, but its HEAD must be exact.
2. Record that Gate A commit in working notes. After all Gate B plan corrections
   are committed and pushed, record the final pushed commit as the exact Slice
   1 start baseline in the acceptance ledger. Do not edit this plan merely to
   embed that self-referential hash.
3. Re-read `AGENTS.md`, `docs/README.md`, `docs/DEVELOPMENT.md`,
   `docs/architecture.md`, `docs/product-parity.md`, `docs/ui-parity.md`, the
   locked spec, this plan, and the current source/tests named below.
4. Compare relevant owners with the source baseline using `git diff
   65082bce82f005c1ff8842b887e1a27a39115203..HEAD -- ...`.
5. Dispatch one fresh GPT-5.6 Sol **medium** read-only plan reviewer. Its task is
   to check current ownership, slice dependencies, complete acceptance mapping,
   verification gates, file overlap, and Ponytail violations. It must return
   evidence with paths and line numbers, not edit files.
6. Adjudicate every finding against source and the locked spec. Apply accepted
   corrections to this plan before production edits. A correction that changes
   locked product behavior requires user direction instead of a silent spec
   rewrite.
7. Run the baseline focused suites for builder, resolver, scheduler, schedule
   worker, controller, Channels UI, Guide, and product spine. A pre-existing
   failure must be understood and recorded; do not bury it under feature work.
8. Commit and push any plan-only correction. Re-run the plan-review checklist on
   that delta. If the worktree branch has no upstream, establish and record one
   before this push. Confirm the pushed commit is the recorded Slice 1 start
   baseline. Only then may Slice 1 start.

## Orchestrator implementation loop

Use this exact loop for Slices 1 through 7:

1. **Start clean.** Confirm the previous slice commit is present, pushed, and
   the worktree is clean. Record the slice number, start commit, allowed write
   set, and acceptance-ledger IDs.
2. **Dispatch one writer.** Create one fresh GPT-5.6 Sol worker at medium
   reasoning. Give it the complete slice text, cross-slice invariants, current
   start commit, required reads, allowed write set, and focused verification.
   It may edit only that slice and must not commit or push.
3. **No overlapping writer.** Do not dispatch another editing worker while that
   worker is active. All slices touch shared Dart owners; sequential commits are
   intentional.
4. **Inspect the result.** The orchestrator reads the full diff and confirms the
   worker did not change files outside the allowed set, add dependencies, change
   native code, or implement deferred behavior.
5. **Review before correction.** Dispatch at least one fresh GPT-5.6 Sol medium
   read-only reviewer against the uncommitted slice diff. For Slices 4, 5, and 6,
   two read-only reviewers may run concurrently after the writer stops: one for
   correctness/data ownership and one for UX/accessibility. Reviewers must not
   update goldens, format files, run write-producing commands, or edit source.
6. **Adjudicate.** Confirm every review finding in source. Send accepted bounded
   fixes back to the slice writer, or use one new writer if the original is no
   longer available. Reject findings with a written evidence reason.
7. **Verify sequentially.** Run the slice's required focused tests. Do not run
   Flutter test/build processes concurrently in the shared checkout. Run format
   and `git diff --check`. Inspect any updated golden image before accepting it.
8. **Re-read the slice diff.** Check each behavior contract and ledger item.
   Nothing may be marked complete because a worker said it was complete.
9. **Commit once.** Create the named coherent slice commit only after all gates
   pass. Push it and confirm the upstream contains it. Do not mix the next slice
   into the same commit.
10. **Handoff.** Record commit, files, tests with counts/result, reviewed
    findings and dispositions, remaining known limits, ledger IDs completed,
    and the exact next slice. Then start the next clean worker.

Safe concurrency is limited to read-only source review after a writer has
finished. Tests, formatting, golden generation, edits, commits, and pushes are
always sequential. If a reviewer needs a code change, it stops being read-only
and must wait until it is the sole writer.

### Deviation protocol

The plan is authoritative for execution, but current evidence outranks stale
assumptions. When evidence requires a material deviation:

1. Stop the active slice before making the out-of-plan edit.
2. Confirm the evidence in source and state whether it changes implementation
   detail or locked product behavior.
3. For implementation detail, update this plan in a separate planning commit,
   run a read-only review of the plan delta, and push it before resuming.
4. For locked product behavior, stop and request user direction. Do not edit the
   specification or reinterpret an acceptance criterion silently.
5. Resume with a clean worktree and a new recorded start commit.

Small path corrections within the same owner, test fixture updates forced by a
public signature, and formatting are not material deviations, but they still
belong in the active slice commit and handoff.

## Slice 1 — generated/custom ownership and build modes

**Purpose:** Make regeneration safe before exposing richer custom-channel
authoring.

**Required inspection:**

- `lib/channels/channel.dart`
- `lib/channels/channel_builder.dart`
- `lib/app/lineup_controller.dart`
- the plan preparation, impact, confirmation, and completion code in
  `lib/app/channel_setup_view.dart`
- `test/channels/channel_builder_test.dart`
- the channel-plan transaction tests in `test/app/lineup_controller_test.dart`
- Channel Setup review tests in `test/app/ui_parity_test.dart` and
  `test/app/ui_review_regression_test.dart`
- the 1,000-channel path in `test/app/product_spine_test.dart`

**Allowed production writes:**

- `lib/channels/channel_builder.dart`
- `lib/app/lineup_controller.dart`
- `lib/app/channel_setup_view.dart`

**Allowed test writes:** the directly corresponding builder, controller, setup
UI, and product-spine test files named above.

**Behavior contract:**

1. Materialization reserves every custom-owned number for replace, append, and
   merge. Append and merge continue to reserve every existing number.
2. Merge matches only non-null equal builder keys. It cannot match a custom
   channel by name, number, or source.
3. A matching generated channel with changed generator-owned fields preserves
   the existing ID, number, name, anchor, and seed and receives the proposed
   source, mode, and block size. An exact generator-owned match may reuse the
   existing object.
4. Replace commits all pre-existing custom channels plus the planned generated
   set. Append keeps all channels and adds planned generated channels. Refresh
   replaces matching generated entries, retains unmatched existing entries,
   and keeps every custom entry.
5. Final full-lineup validation remains inside the serialized controller
   transaction. A caller that bypasses materialization and supplies a number
   conflict fails and rolls back.
6. Current-channel selection remains stable when its channel survives; the
   existing nearest-row fallback remains when a generated current channel is
   removed.
7. User-facing build labels become **Replace generated channels**, **Add
   generated channels**, and **Refresh generated channels**. Confirmation and
   impact counts name the generated channels removed and custom channels kept.
   Internal enum names may remain unchanged.
8. Replace impact reports preserved custom channels as unchanged, removes only
   generated channels, and calculates final count as custom plus planned.
9. Do not redesign Channel Setup proposals, strategy defaults, or review cards
   in this slice.

**Required tests:**

- Custom channels survive each build mode byte-for-byte through JSON.
- Replace and new allocation skip sparse custom numbers, including 1 and 1000.
- Refresh preserves matched generated identity/station fields while updating
  generator-owned fields.
- Unmatched generated and all custom channels remain in refresh.
- Conflict and persistence failure leave the old lineup/current channel exact.
- Review semantics/counts and confirmation copy distinguish generated removals
  from preserved custom channels.
- Existing expansion, truncation, 1,000-channel, and deterministic tests remain
  green.

**Focused verification:**

```sh
flutter test test/channels/channel_builder_test.dart
flutter test test/app/lineup_controller_test.dart
flutter test test/app/ui_parity_test.dart test/app/ui_review_regression_test.dart
flutter test test/app/product_spine_test.dart
dart format --output=none --set-exit-if-changed lib test
git diff --check
```

**Commit:** `fix(channels): preserve custom channels during generation`

**Stop/replan if:** preserving custom numbers makes the accepted maximum-channel
meaning ambiguous, a plan contains a null builder key, or another current caller
uses `applyChannelPlan` as a general custom-lineup replacement. Confirm the
caller and update the plan rather than weakening ownership checks.

## Slice 2 — fail-closed resolution, bounded projection, and safe saves

**Purpose:** Establish the correctness seams Studio and Air Check require before
building their UI.

**Required inspection:**

- `lib/channels/channel.dart`
- `lib/channels/content_resolver.dart`
- `lib/channels/scheduler.dart`
- `lib/channels/schedule_worker.dart`
- `LineupController.saveChannel`, schedule loading, and state-operation queue
- Guide row loading/projection in `lib/guide/guide_controller.dart`
- every `saveChannel`, `resolveContent`, and `scheduleWindow` caller and its tests

**Allowed production writes:**

- `lib/channels/content_resolver.dart`
- `lib/channels/scheduler.dart`
- `lib/channels/schedule_worker.dart` only if its input/output must change to
  preserve the resolver contract
- `lib/app/lineup_controller.dart`
- `lib/app/lineup_shell.dart` only for temporary compilation updates to the old
  editor's `saveChannel` calls; Slice 3 removes that editor
- `lib/guide/guide_controller.dart` only if the additive window-result contract
  requires a caller update

**Allowed test writes:** resolver, scheduler, schedule-worker, controller,
Guide, player, and old editor tests directly forced by these public contracts.

**Behavior contract:**

1. `resolveContent` accepts only `genre`, `collection`, `studio`, `actor`,
   `director`, `decade`, and `sort=added:desc`. An unknown key or unsupported
   value throws a sanitized `FormatException`; it never returns the unfiltered
   input.
2. Manual resolution walks stored item IDs in stored order, substitutes the
   current playable `PlexMediaItem` projection, and omits IDs absent or
   unplayable in the current authoritative inventory. The stored `ManualSource`
   is not mutated, so unavailable records remain recoverable in Studio.
3. Mixed resolution applies the same strict behavior recursively and preserves
   existing concatenate/interleave ordering.
4. Keep `scheduleWindow` compatible for existing consumers, but add the
   smallest result-returning projection needed by Air Check to expose whether
   the 1,000-program safety ceiling truncated the requested window and the last
   projected end. Both paths must delegate to one loop.
5. Make `saveChannel` distinguish create from edit with an explicit expected
   base (`null` means create; a `Channel` means edit). At execution time inside
   the serialized queue, a create fails if the ID already exists, and an edit
   fails if the current canonical channel differs from the expected base or no
   longer exists.
6. The expected-base comparison uses canonical channel data already owned by
   `Channel.toJson`; do not add a persisted revision field.
7. The controller retains whole-lineup validation, one save, rollback, and
   notification behavior. Source-resolution validation must reject unsupported
   filters and empty live library/playlist sources. Retained nonempty manual
   content may remain saved even when some or all items are temporarily
   unavailable.
8. Do not globally tighten persisted block-size validation in a way that
   quarantines an older generated channel. Studio enforces its 2-through-5
   authoring range in Slice 4.
9. Give `LineupController` one playback-item lookup that searches current
   `availableMedia` first, then playable items from current video playlists in
   deterministic playlist/item order. `playbackFor` uses that lookup so every
   playlist-only item accepted by resolution can tune. Do not copy playlist
   items into durable state, broaden library selection, or add another playback
   model.

**Required tests:**

- Every supported filter still resolves correctly; unknown keys and sort values
  throw and do not broaden results.
- Manual resolution preserves stored order, refreshes available metadata, omits
  unavailable/unplayable items, and does not modify the stored source.
- Mixed manual/library/playlist sources remain deterministic.
- Window projection distinguishes exact completion from truncation and reports
  the last real end time.
- Create rejects an existing ID; edit rejects missing/changed expected bases;
  a matching expected base succeeds.
- A stale failure performs no store write and leaves controller state exact.
- A failed save after valid resolution still rolls back exactly.
- Guide and Player tests reflect the same manual availability behavior.
- A playable item present only in the current playlist inventory resolves,
  previews, saves, and produces a playback request. Duplicate IDs use the
  documented `availableMedia`-first precedence.

**Focused verification:**

```sh
flutter test test/channels/content_resolver_test.dart test/channels/scheduler_test.dart test/channels/schedule_worker_test.dart
flutter test test/app/lineup_controller_test.dart
flutter test test/guide/guide_controller_test.dart test/playback/player_coordinator_test.dart
flutter test test/app/ui_review_regression_test.dart
dart format --output=none --set-exit-if-changed lib test
git diff --check
```

**Commit:** `fix(channels): make channel resolution and saves fail closed`

**Stop/replan if:** the current media inventory is not authoritative in the
ready application, a legitimate current manual channel intentionally schedules
an item absent from `availableMedia`, or strict filter failure would quarantine
otherwise recoverable state during load. Keep persisted source records intact
and move the fail-closed behavior to the resolver boundary rather than silently
broadening or deleting data. Also stop if a playlist item lacks the same
playable Plex descriptor facts required by `_playbackRequest`; do not paper over
that mismatch with a second playback path.

## Slice 3 — full-page Studio routing, identity, and ownership modes

**Purpose:** Replace the modal editor with the four locked Studio modes and wire
the two creation paths into one Channels destination.

**Required inspection:**

- the shell route-selection and focus ownership in `lib/app/lineup_shell.dart`
- `LineupPage`, `LineupNotice`, selection/focus components, and all theme roles
- current Channels/editor widget and widget regression tests
- `PlayerCoordinator.tune` result/error behavior
- Channel Setup completion behavior and shell stage transition
- `safeFormError` and destructive confirmation patterns

**Allowed production writes:**

- new `lib/app/channel_studio_view.dart`
- `lib/app/lineup_shell.dart`
- `lib/app/channel_setup_view.dart`
- `lib/app/lineup_controller.dart` only for a correction directly required by
  the expected-base save seam established in Slice 2
- existing shared UI/theme files only if a repeated current primitive is proven
  missing; update this plan first if that is more than a localized extension

**Allowed test writes:**

- new `test/app/channel_studio_view_test.dart`
- `test/app/ui_parity_test.dart`
- `test/app/ui_review_regression_test.dart`
- `test/app/lineup_app_test.dart`
- `test/app/lineup_controller_test.dart` when the save seam requires it
- `test/support/ui_fixture.dart` only for deterministic public-seam support

**Behavior contract:**

1. Channels remains one stateful management destination. It switches its body
   between the number-ordered list and a full-page `ChannelStudioView`; do not
   push a full-screen root route, open a dialog, or add a navigation-rail item.
2. The header actions are **Generate lineup** and **New channel**. The empty
   state makes generation primary and custom creation secondary.
3. Rows show number, name, **Generated**/**Custom**, source summary,
   plain-language playback rhythm, and accessible **Open**/**Delete** actions.
   Generated deletion warns that refresh may propose it again.
4. Implement create custom, edit custom, inspect generated, and duplicate-as-
   custom modes. Mode title, ownership, editable controls, and primary action
   are unambiguous.
5. Generated programming, mode, block size, anchor, and seed are read-only.
   Generated identity saves name/number against the expected base.
6. Duplicate creates its ID immediately, clears `builderKey`, chooses the lowest
   free number, gives the name a visibly editable copy suffix, and preserves
   source, playback, anchor, seed, and block size in the draft. It never mutates
   the original.
7. New custom drafts choose the lowest free number. Names trim and require
   content; numbers require 1 through 1000 and uniqueness. Duplicate-number
   validation names the conflicting channel and offers **Use next available**.
8. When all 1,000 numbers are occupied, New channel and Generate Lineup's **Add
   a custom channel** open an explicit no-number-available draft state with save
   disabled and guidance to free or renumber a channel. Duplicate as custom
   preserves the copied recipe in the same state. No entry path defaults to 1
   or another occupied number.
9. Name duplication remains valid. Focus moves to the first invalid field after
   a failed save attempt and a bounded summary is announced.
10. Draft edits never mutate the live `Channel`. Save disables mutations and
   navigation, uses the expected-base controller transaction, retains the draft
   on failure, and changes to a clean saved state on success.
11. `ChannelsView` owns one asynchronous `requestLeave` guard. The shell keeps
    one guarded destination-selection method; whenever selection would leave
    Channels, it awaits that guard before changing `_selectedIndex`. Rail and
    global-key handlers mark the input handled and start this same guarded
    selection without creating a second policy. Studio Back/Cancel and
    app-level Back delegate to the same Channels-owned method. Dirty drafts
    offer **Discard changes** and **Keep editing**; clean drafts leave directly;
    saving drafts cannot leave. Keep this seam in the shell/Channels widget—no
    controller draft state, global service, or routing package.
12. Returning to Channels restores focus to the invoking or saved row. Delete
    retains its current focus restoration. A deleted or externally changed base
    is shown as a reload/reapply conflict, never overwritten.
13. A clean saved Studio exposes **Tune in**. The shell waits for
    `PlayerCoordinator.tune`; success opens Player, while a coordinator error is
    returned to Studio without rolling back the saved channel.
14. Channel Setup completion exposes **View lineup** and **Add a custom
    channel** only after durable apply. Both complete setup and select Channels;
    the latter then opens a separate new draft. It is never part of the apply
    transaction.
15. Preserve current lossless library/manual source editing in this slice.
    Existing playlist, filtered, or mixed custom sources must remain visible and
    unchanged until replaced; Slice 4 adds every authoring control. Do not create
    a placeholder source conversion or discard an unrepresentable source.
16. Put the draft and Studio-specific private helpers in the Studio feature file.
    Do not add a repository, service, provider, event bus, or global draft owner.

**Required tests:**

- Correct row ordering, ownership text, source/rhythm copy, action names, and
  generated delete warning.
- Every entry path opens the correct mode and full-page layout; no Studio dialog
  or top-level destination exists.
- Create/edit/generated identity/duplicate use correct ID, number, builder key,
  source, mode, block size, anchor, and seed.
- A full 1,000-number lineup gives New channel, Generate Lineup's Add a custom
  channel, and Duplicate as custom the explicit no-number state; none proposes
  an occupied fallback or permits save until a number is freed.
- Duplicate and cancel leave the source channel unchanged.
- Dirty leave confirmation covers header Back, Cancel, rail, shortcut, and app
  Back; clean leave has no confirmation.
- Invalid name/number, conflict action, focus-to-first-error, save-in-progress,
  failure rollback/live announcement, success/clean state, and stale base.
- Tune success changes destination; tune failure remains in Studio with the
  saved channel intact.
- Generate completion actions occur after apply and open the intended state.

**Focused verification:**

```sh
flutter test test/app/channel_studio_view_test.dart
flutter test test/app/ui_parity_test.dart test/app/ui_review_regression_test.dart
flutter test test/app/lineup_controller_test.dart test/app/lineup_app_test.dart
dart format --output=none --set-exit-if-changed lib test
git diff --check
```

**Commit:** `feat(channels): add the Channel Studio workspace`

**Stop/replan if:** the current shell cannot intercept navigation without a
second route owner, focus restoration would require global focus state, or Tune
in would require combining save and playback. Prefer a small Channels-owned
`requestLeave` guard and one shell selection method that awaits it; do not add a
routing or state-management package or scatter leave checks across call sites.

## Slice 4 — programming sources and hand-picked workbench

**Purpose:** Make every representable first-release custom source authorable and
make large manual selections usable without changing scheduling.

**Required inspection:**

- all `ContentSource` variants and canonical serialization
- all metadata present on `PlexMediaItem` and `ChannelItem`
- selected-library and playlist inventory ownership in `LineupController`
- current builder filter keys and strict resolver behavior from Slice 2
- the Studio draft/source preservation behavior from Slice 3

**Allowed production writes:**

- `lib/app/channel_studio_view.dart`
- `lib/channels/channel.dart` only if a locked source cannot be represented
  losslessly; any such change is a stop/replan event because no extension is
  expected
- `lib/channels/content_resolver.dart` only for a confirmed supported-facet bug

**Allowed test writes:**

- `test/app/channel_studio_view_test.dart`
- `test/channels/content_resolver_test.dart`
- persistence round-trip tests only if canonical source serialization changes

**Behavior contract:**

1. Offer exactly four programming choices: **Library**, **Playlist**,
   **Collection or filter**, and **Hand-picked**. One is active and only it is
   saved. Each choice retains its unsaved local values while the user switches
   among choices.
2. Library chooses one currently selected movie/show library and exposes
   **Include watched items**.
3. Playlist chooses one current video playlist by stable Plex ID. A disappeared
   saved playlist remains named by its retained ID/summary as unavailable and
   may be replaced; it is not silently changed.
4. Collection/filter starts with a library and browseable values derived from
   the already-loaded inventory. It permits at most one value for each of
   collection, genre, studio, actor, director, and decade plus the supported
   newest-first order. Different selected keys combine through the resolver's
   existing AND behavior. The UI does not offer repeated same-key OR, unknown
   fields, or a free-form expression editor.
5. Filter options and representative/matching counts are derived locally from
   the loaded inventory. No search or facet change starts a Plex request.
6. Hand-picked search matches displayed title and show title case-insensitively.
   Filters include library and media type when present plus collection, genre,
   studio, actor, director, and decade facts already loaded.
7. Maintain an ordered list of selected IDs, not a set. **Select visible**
   appends only unselected visible results in current result order. **Clear
   visible** removes only selected items currently matching the active search
   and facets. Hidden selections remain selected.
8. The rundown shows current selected order and unavailable retained records.
   Each row exposes Move earlier, Move later, and Remove buttons with channel-
   and item-specific semantics. `Alt+ArrowUp`, `Alt+ArrowDown`, and `Delete` (or
   a better existing management convention found during review) perform the
   same actions when that row has focus. Drag and drop is omitted in v1 because
   it is optional and adds no capability.
9. Moving/removing an item restores focus predictably to the moved item or the
   nearest surviving row. Search never puts focus into a filtered-off result.
10. Show settled matching and selected counts in a bounded live region. Debounce
    text-derived filtering for announcements, not network activity. Do not
    announce each keystroke.
11. A custom source must have at least one resolved or retained program before
    save. Unavailable retained items stay in `ManualSource`; currently available
    selections save fresh `ChannelItem` projections in explicit order.
12. Playback labels are **In order**, **Mix it up**, and **Mini-marathons**.
    Mini-marathons exposes 2 through 5, defaults to 3, and remains invalid with
    an explanation when the resolved content has no episode/show grouping. Do
    not silently switch an invalid selected rhythm.
13. Custom-owned filtered, playlist, and currently representable mixed sources
    are editable or losslessly inspectable based on representation, never on
    ownership. A preserved mixed source not directly representable remains
    intact while the user chooses a replacement source.
14. When there is no usable inventory, preserve an existing source and explain
    that a new channel needs selected Plex libraries or a video playlist. Link
    to the existing library-owning Generate Lineup route through the same dirty-
    leave guard. Loading shows bounded progress without disabling identity;
    cancelled/failed inventory preserves the last usable inventory and offers
    the owning retry rather than clearing draft selections.

**Required tests:**

- Each source round-trips exact ID, library type, watched choice, filters, order,
  and custom ownership.
- Unsupported same-key multi-select is absent, while different facet types AND
  correctly and newest-first remains exact.
- Missing library/playlist and zero-match states preserve the draft and disable
  save with actionable copy.
- No-inventory, loading, cancelled, and failed states retain the draft and route
  recovery through the existing library-scan owner.
- Search includes show titles, facet intersections are correct, counts settle,
  and no operation calls Plex.
- Select/Clear visible preserve hidden selection; reordering and removal preserve
  exact order through save and reload.
- Unavailable records remain visible and retained but not scheduled.
- Pointer buttons and keyboard commands produce identical results and focus.
- Mini-marathon eligibility and every 2-through-5 block size map exactly to the
  existing scheduler.
- A deterministic large inventory demonstrates local, bounded filtering without
  building every result widget or starting unbounded asynchronous work.

**Focused verification:**

```sh
flutter test test/app/channel_studio_view_test.dart
flutter test test/channels/content_resolver_test.dart test/channels/scheduler_test.dart
flutter test test/app/ui_parity_test.dart
dart format --output=none --set-exit-if-changed lib test
git diff --check
```

**Commit:** `feat(channels): add Studio programming controls`

**Stop/replan if:** a requested facet needs multiple same-key values, the loaded
Plex model lacks the required fact, or deterministic scale evidence shows local
filtering blocks frames. Do not add a rule language, network search, isolate, or
cache without first recording the concrete gap and updating this plan.

## Slice 5 — deterministic Air Check and channel health

**Purpose:** Add the signature preview using the authoritative content and
schedule path, then surface schedule health in Channels.

**Required inspection:**

- final resolver/window contracts from Slice 2
- Studio draft snapshots and source controls from Slices 3 and 4
- `LineupController.loadScheduleFor` and `ScheduleWorker` lifecycle
- `GuideGeometry`, `GuideProgram`, time formatting, and current Guide semantics
- the injected Guide clock in `LineupShell`
- Player/Guide current-program boundary behavior

**Allowed production writes:**

- `lib/app/channel_studio_view.dart`
- new `lib/app/channel_air_check.dart` for the significant async ribbon and its
  presentation; do not create additional model/service layers
- `lib/app/lineup_shell.dart` to pass the existing injected clock
- `lib/channels/scheduler.dart` only for a bug in the Slice 2 projection result
- `lib/app/lineup_controller.dart` or `lib/channels/schedule_worker.dart` only if
  current measured worker ownership cannot build a draft safely; update this
  plan before adding another worker/cache

**Allowed test writes:**

- `test/app/channel_studio_view_test.dart`
- new `test/app/channel_air_check_test.dart`
- scheduler, worker, Guide, Player, and shell tests directly affected by the
  authoritative preview contract

**Behavior contract:**

1. Air Check is present in every Studio mode. Expanded layouts show bounded past
   context, On now, and following programs over no more than six hours; compact
   layout preserves at least now/next and the semantic program list.
2. Build one immutable draft `Channel` snapshot and send it through
   `LineupController.loadScheduleFor`. Project programs with the Slice 2 bounded
   schedule-window result. Do not call `buildSchedule`, reorder content, or
   calculate program boundaries in the widget.
3. Use the shell's injected clock for deterministic tests and Guide agreement.
   A periodic UI clock moves the visual now line while open, but its semantics
   are excluded from continuous announcements and the timer is disposed.
4. Debounce schedule-affecting input by one documented short constant. Permit at
   most one worker request plus one latest pending snapshot. Snapshot identity
   includes source, mode, block size, anchor, seed, and controller content
   generation. Ignore all stale/disposed results.
5. Keep the last successful preview only when it is visibly marked stale during
   recalculation. Loading, empty, unsupported-filter, missing-source, truncated,
   and general error states have explicit presentations and recovery; no fake
   programs appear.
6. Show resolved playable count, total cycle duration, playback rhythm, selected
   program start/end, and a plain-language inclusion reason derived from the
   active source/facets. Show unavailable retained items and known skipped or
   invalid input with an actionable explanation.
7. A truncated six-hour result says it is truncated and exposes the last actual
   projected end. It never implies full coverage.
8. A new draft uses a candidate ID/seed and candidate anchor for its first valid
   calculation. Commit them to draft state only when that snapshot resolves
   successfully; all later previews and save reuse them exactly.
9. Existing edits preserve anchor/seed. If programming/rhythm changes project a
   different current item from the original at the same instant, show **Saving
   these programming changes may change what is on now**. Identity-only changes
   do not show it.
10. Selecting a ribbon program exposes title, start/end, temporal state, and
    inclusion reason. Semantic entries include channel, title, start, end, and
    past/current/future state; visual selection is not color-only.
11. Save remains disabled when schedule correctness cannot be established,
    except that a nonempty retained manual source may be saved in its explicit
    unavailable/off-air state as allowed by the locked retained-content rule.
12. Channels rows lazily expose an issue indicator when their currently visible
    channel cannot build a schedule. Reuse the existing async schedule owner and
    keep work proportional to lazily built rows; do not synchronously resolve
    all 1,000 channels in `build`.
13. After save, build the saved-channel preview through the same path. A focused
    agreement test must show that Studio, Guide, and Player select the same item
    and boundaries for the saved channel at the fixed instant.

**Required tests:**

- Sequential, shuffle, and mini-marathon previews match `programAt` and Guide
  at exact boundaries and before/after the anchor.
- The previewed new anchor/seed equal the persisted values and survive reload.
- Rapid edits, content-generation change, retry, route close, and out-of-order
  completion cannot publish stale preview data; active/pending work is bounded.
- Empty, missing, unavailable, strict-filter error, generic worker error, stale,
  and truncated states are explicit and do not fabricate programs.
- Current-program-change warning is exact and absent for identity-only edits.
- Timer movement updates visuals without repeated semantic live announcements.
- Compact and expanded semantic program lists remain present.
- Channels issue work remains lazy under a 1,000-channel fixture.
- Tune uses the saved channel and remains separate from persistence failure.

**Focused verification:**

```sh
flutter test test/app/channel_studio_view_test.dart test/app/channel_air_check_test.dart
flutter test test/channels/scheduler_test.dart test/channels/schedule_worker_test.dart
flutter test test/guide/guide_controller_test.dart test/playback/player_coordinator_test.dart
flutter test test/app/product_spine_test.dart
dart format --output=none --set-exit-if-changed lib test
git diff --check
```

**Commit:** `feat(channels): add deterministic Air Check`

**Stop/replan if:** `loadScheduleFor` cannot accept unsaved channels, worker
requests cannot be kept to one active plus one pending, preview and Guide need
different resolution semantics, or channel-row health creates an unbounded
1,000-channel queue. Measure first; extract a shared bounded loader only if the
current owner demonstrably cannot satisfy the contract.

## Slice 6 — accessibility, responsive composition, and visual acceptance

**Purpose:** Prove the locked interaction and presentation states and make only
the fixes those proofs require.

**Required inspection:**

- final Studio and Air Check widgets
- all shared theme roles and management layout thresholds
- current semantics/focus conventions in Channels, Guide, Settings, and dialogs
- `test/app/ui_acceptance_golden_test.dart` font, clock, viewport, and matching
  harness
- existing focus, Reduce Motion, large-focus, and text-scale tests

**Allowed production writes:**

- `lib/app/channel_studio_view.dart`
- `lib/app/channel_air_check.dart`
- `lib/app/lineup_shell.dart`
- existing shared UI/theme files only for a proven application-wide primitive;
  otherwise keep the fix feature-local

**Allowed test/artifact writes:**

- `test/app/channel_studio_view_test.dart`
- `test/app/channel_air_check_test.dart`
- `test/app/ui_parity_test.dart`
- `test/app/ui_review_regression_test.dart`
- `test/app/ui_acceptance_golden_test.dart`
- the smallest stable new PNG set under `test/app/goldens/`
- `test/support/ui_fixture.dart` and deterministic synthetic assets only when
  necessary; never use private Plex media or token-bearing URLs

**Behavior and proof contract:**

1. Exercise `800x600`, `1280x720`, `1360x840`, `1600x900`, `1920x1080`, and
   `3840x2160`, including the existing DPR-2 high-DPI regime. Below 900 logical
   pixels Studio stacks Programming before Station and keeps compact Air Check.
2. At ordinary/large widths the workspace is capped at the existing 1,120
   logical pixels. Primary fields, save status, and actions remain reachable at
   every size.
3. Exercise 200 percent text scale with no horizontal clipping of primary
   fields, errors, actions, or semantic Air Check content. Vertical scrolling is
   allowed at 800x600.
4. Verify focus order: header, Air Check, programming, station/playback, actions.
   Filtered-off items do not retain focus. Back/Cancel/Delete/save restore the
   required target. Save-in-progress excludes mutating controls and navigation.
5. Verify pointer and keyboard parity for source selection, bulk operations,
   rundown ordering, ribbon selection, validation recovery, and leave dialogs.
6. Verify live regions announce settled counts and bounded loading/error/save
   state, not every keystroke or clock tick.
7. Verify semantic text for ownership, unavailable content, selection,
   past/current/future programs, and invalid schedule independent of color/icons.
8. Run Studio under every current theme, Reduce Motion, and large focus. Assert
   shared `LineupThemeRoles` are consumed and no hard-coded Ember-only color or
   second shadow/elevation language was added.
9. Add only two stable goldens unless visual inspection proves a third is
   necessary: expanded custom authoring with Air Check at `1280x720`, and compact
   authoring at `800x600`. Exercise generated inspection and error states with
   widget assertions rather than multiplying snapshots.
10. Generate goldens only on the canonical macOS/TZ harness, inspect each image
    visually, then rerun without `--update-goldens`. A generated image is not
    accepted merely because pixel comparison passes.
11. Use deterministic synthetic titles/artwork only. No credentials, private
    metadata, personal paths, or captured live screenshots enter the repository.

**Focused verification:**

```sh
flutter test test/app/channel_studio_view_test.dart test/app/ui_parity_test.dart test/app/ui_review_regression_test.dart
TZ=America/New_York flutter test --update-goldens test/app/ui_acceptance_golden_test.dart
TZ=America/New_York flutter test test/app/ui_acceptance_golden_test.dart
flutter test test/app/theme_shell_test.dart test/ui/app_theme_test.dart
dart format --output=none --set-exit-if-changed lib test
git diff --check
```

The golden update command is authorized only when the expected new/changed
goldens have been identified from the locked design. Unexpected diffs must be
investigated, not accepted wholesale.

**Commit:** `fix(channels): finish Studio accessibility and responsive states`

**Stop/replan if:** 200 percent text or 800x600 requires hiding Air Check,
keyboard parity would require drag-only behavior, shared UI changes regress
other destinations, or a golden differs outside the intended Studio surface.

## Slice 7 — documentation, full verification, and closeout audit

**Purpose:** Update claims only after evidence exists, run the full repository
gate, and audit the net feature rather than merely the last slice.

**Required inspection:**

- the complete diff from the recorded Slice 1 start baseline through Slice 6
- locked spec acceptance criteria and this plan's ledger
- `docs/README.md`, `docs/user-guide.md`, `docs/product-parity.md`,
  `docs/ui-parity.md`, `docs/architecture.md`, and applicable Windows evidence
- all test output and golden images produced by earlier slices

**Allowed writes:**

- `docs/README.md`
- `docs/user-guide.md`
- `docs/product-parity.md`
- `docs/ui-parity.md`
- `docs/channel-studio-spec.md` only to update implementation/evidence status,
  never to rewrite locked requirements after the fact
- this plan only to record final baseline/evidence or a required corrected step
- focused production/test fixes found by the net-diff audit; such a fix requires
  rerunning the owning slice review and tests before the closeout commit

**Documentation contract:**

1. User Guide uses final visible labels and explains Generate Lineup versus New
   channel, Studio modes, source options, playback rhythms, Air Check, ownership,
   regeneration safety, unavailable content, save/tune separation, and recovery.
2. Product Parity and UI Parity classify only behavior supported by fresh
   deterministic evidence. They retain historical evidence boundaries.
3. Architecture is changed only if an accepted owner actually changed. Do not
   duplicate the feature spec into it.
4. The spec status may say implemented/deterministically tested only for checked
   ledger items. It must not claim physical Windows validation or support.
5. Documentation navigation links the specification and this implementation
   plan without duplicating volatile commands.

**Full verification, sequential:**

```sh
dart format .
dart format --output=none --set-exit-if-changed .
flutter analyze
TZ=America/New_York flutter test
flutter build macos
git diff --check
git status --short
```

Also audit the net diff:

- No `pubspec.yaml`/lockfile dependency change.
- No C++, runner, Flutter engine patch, platform packaging, or WebView change.
- No second channel/persistence/scheduler owner.
- No deferred daypart/fixed-start/filler/export/transcode/rule-language behavior.
- No token, private-media, personal-path, or unredacted-log artifact.
- Every spec acceptance checkbox maps to a passing test, inspected golden, or an
  explicitly named remaining physical/manual evidence boundary.
- Existing Channel Setup, Guide, Player, persistence, and 1,000-channel product
  spine remain green.

If the host cannot build macOS, record that fact and run the appropriate current
host build through the repository's documented toolchain; do not claim an
unobserved build. Windows CI may compile this Flutter-only change, but physical
Windows evidence is calibrated separately below.

**Commit:** `docs(channels): document Channel Studio behavior`

Push the commit, confirm the worktree is clean and upstream contains every local
commit, then produce the final handoff with the completed ledger.

## Plan-review checklist

Both Gate A and Gate B reviewers must answer every item:

### Scope and ownership

- [ ] The locked spec and current source agree on the feature boundary.
- [ ] Each production behavior has one existing or explicitly justified owner.
- [ ] `builderKey`, not source shape, is the only ownership discriminator.
- [ ] The plan adds no top-level destination, second lineup, draft persistence,
      scheduler, resolver, mutation owner, state framework, or dependency.
- [ ] Deferred broadcast features and non-goals cannot leak into a slice.

### Correctness and persistence

- [ ] Replace/add/refresh semantics are exact for generated and custom channels.
- [ ] Number allocation reserves custom numbers before materialization.
- [ ] Generated refresh preserves the exact locked station/schedule identity.
- [ ] Create/edit expected-base semantics reject ID collisions and stale state.
- [ ] Save validation, single write, rollback, draft retention, and tune separation
      are explicitly tested.
- [ ] Strict filters fail closed without destroying recoverable stored sources.
- [ ] Manual unavailable records remain persisted while active schedule content
      comes from current playable Plex inventory.
- [ ] Playlist-only items accepted by resolution use the controller's one
      deterministic playback lookup and can tune.
- [ ] A full 1,000-number lineup never proposes an occupied fallback for a new
      or duplicated custom draft.

### UX and accessibility

- [ ] All four modes and both entry paths are mapped to reachable UI.
- [ ] Every first-release source and recovery state is mapped to a slice/test.
- [ ] Unsaved navigation covers rail, shortcuts, Back, Cancel, and save-in-flight.
- [ ] Air Check has one authoritative scheduling path and exact anchor/seed rules.
- [ ] Search/bulk/reorder behavior specifies order, hidden selections, focus, and
      keyboard parity.
- [ ] Viewport, text scale, semantics, themes, Reduce Motion, focus, and goldens
      are explicit and bounded.

### Execution quality

- [ ] Each acceptance-ledger item has exactly one owning slice and evidence gate.
- [ ] Each slice has required reads, allowed writes, tests, commit, and stop rule.
- [ ] No two write agents can edit overlapping owners concurrently.
- [ ] Read-only concurrency cannot mutate goldens or shared build output.
- [ ] Evidence-driven deviation updates the plan before implementation resumes.
- [ ] Gate B starts at the exact pushed Gate A `flutter-mvp` commit, never the
      repository default `main` branch.
- [ ] Every slice ends clean, committed, pushed, reviewed, and handed off.
- [ ] Final claims are calibrated and independent review remains user-controlled.

## Windows and native validation calibration

This feature is Flutter/Dart product UI, content policy, schedule projection, and
persistence. It must not modify native C++, libmpv, DirectComposition, the owned
Flutter engine patch, packaging, or media format behavior.

Deterministic macOS/CI widget tests can establish layout, focus traversal,
semantics structure, resolver/scheduler agreement, persistence, rollback, and
responsive composition. They cannot establish physical Windows DPI mapping,
screen-reader behavior, real keyboard/remote delivery, native video layering,
playback compatibility, or package readiness.

No new physical Windows campaign is required merely to merge the Flutter-only
feature if the net diff stays outside native/player composition. Before making a
Windows accessibility/support claim, run the exact-commit physical matrix for:

- 800x600 and ordinary/high-DPI Studio layout;
- keyboard-only creation, source selection, reorder, save, discard, and focus
  restoration;
- the supported Windows screen reader across ownership, Air Check semantics,
  counts, errors, and live regions; and
- Tune in transition to existing Player without a layering/focus regression.

Record that evidence under the existing Windows-native validation authority and
redact all private Plex content. Do not generalize a successful widget test or
macOS golden into Windows platform validation.

## Independent review and final handoff

The requested plan and slice reviews are part of this orchestrated implementation
workflow. A separate independent review remains user-controlled and must not be
launched automatically.

Because this feature changes generator/custom ownership and stale-safe persisted
mutation semantics, independent review is **specifically recommended** after the
final net-diff audit. The final handoff must state that recommendation and let the
user decide whether to launch it.

The final handoff must include:

- Gate A, Slice 1 start, and final commit hashes;
- ordered slice commits and pushed branch;
- changed files grouped by owner;
- the completed acceptance ledger with observed evidence;
- focused and full verification commands/results;
- inspected golden names;
- any physical Windows evidence, or an explicit statement that none was run;
- remaining product or platform limitations;
- confirmation that the worktree is clean and all commits are pushed; and
- the independent-review recommendation without launching it.
