# Player Timing and Channel Creation Fix Plan

**Status:** Approved on October 7, 2026; all six units implemented locally.
Independent final review is complete with one accepted builder correction.
Final portable checks pass. Windows and live Plex acceptance remain outstanding.

- **Source:** `codex/desktop-ui-second-pass`, approved base `97cf093a`.
  The plan and handoff were committed together as `2e402473` before dispatch.
- **How the plan was built:**
  1. A controller investigation.
  2. An independent plan review.
  3. Two investigations of adjacent areas: Player timing, and the
     channel-creation pipeline.
- **Planning evidence:** source inspection only; no tests, Plex requests, or
  Windows runs were executed during planning. Implementation now has portable
  test and Flutter-render evidence, with no Windows or live Plex verification.
- **Product decisions:** the user made these on October 7, 2026. They are
  listed in [Decisions](#user-decisions-october-7-2026) and are binding.

Read first:

- [AGENTS.md](../AGENTS.md).
- The relevant sections of [.agents/project.md](../.agents/project.md):
  architecture owners, UI changes, and verification selection.
- [docs/DEVELOPMENT.md](DEVELOPMENT.md) for check commands.
- [guide-freshness-collection-investigation.md](guide-freshness-collection-investigation.md),
  for Package B identity rules. Its non-goals still apply.

The upstream behavioral reference is the named sibling Lineup checkout
(TypeScript) available to the orchestrator. It is evidence only, not a
compatibility target.

## Reported problems

1. The Player OSD never auto-hides, even though the setting is 4 seconds.
2. The Channel Setup **Collections** strategy produced only 4 channels on a
   Plex server with many Kometa-managed collections. Upstream Lineup produced
   channels for all of them.

## User decisions (October 7, 2026)

| # | Decision |
| --- | --- |
| D1 | **OSD focus suspension is keyboard-only.** The timed OSD stays open only while *keyboard-driven* focus is inside its controls. This matches the existing [user guide](user-guide.md) wording. After a mouse action (Sleep preset, app menu dismissal, clicking an OSD control), the OSD times out normally, and pointer activity re-arms the timer. |
| D2 | **TV libraries: hydrate show genres only.** Episodes inherit their show's genres so TV Genre channels work. Do not add a TV Studio or network strategy. TV Studios stays empty, matching upstream. Actors are unchanged. |
| D3 | **Playlists row shows a discovery failure with Retry.** If playlist discovery fails, or some playlists fail during setup, the Playlists strategy row shows an unavailable/partial state and a Retry action, instead of "None in your libraries". The new copy must be shown to the user for approval before merge. |
| D4 | **Append skips existing sources, and Update flags dead sources.** "Add as new channels" skips any proposal whose generated identity (`builderKey`) already exists. The Update review lists generated channels whose source is confirmed gone as **Source not found**, and the user chooses to keep or remove them. The default is keep. Nothing is deleted automatically. |

## Root causes (confirmed from source)

### OSD never hides

1. `windows/runner/native_player.cpp:641` observes mpv `time-pos`.
2. Every property change is forwarded to Dart (`:1217-1265`). For `time-pos`
   that happens on every presented frame, about 24–60 times per second.
3. `lib/playback/windows_native_player.dart` `_handleProperty`
   (`:503-531`) calls `_emit()` for every property. Each call publishes a full
   `PlayerEvent` carrying the current status.
4. `PlayerCoordinator._event` (`lib/playback/player_coordinator.dart`)
   acts on every event's state, not just on changes:
   - `playing` calls `_scheduleOverlayHide` (`:401-402`), which cancels and
     restarts the timer.
   - `paused` (and `ready/buffering/seeking`) calls `_setOverlay(osd)`
     (`:393-399`), which does the same. That call also replaces any open
     non-OSD overlay (track panel, Mini Guide, Sleep picker, number entry)
     with the OSD whenever another paused event arrives.
5. The 4-second timer is therefore restarted every frame and never fires.

Facts the implementer needs:

- **States sent on Windows.** The Windows transport only produces `loading`,
  `playing`, `paused` (through the mpv `pause` property), `stopped`, `error`,
  and `idle`. It never produces `ready`, `buffering`, `seeking`, or `ended`.
  End of file arrives as `stopped`.
- **Tune timing.** Tuning emits `loading` for the new generation
  (`windows_native_player.dart:133-136`). The coordinator hides the OSD on
  `loading` (`player_coordinator.dart:387-391`). After the load completes,
  `showOsd()` at `player_coordinator.dart:582` starts the hide timer. On a
  tune, the timer therefore runs from that `showOsd()`, not from the first
  `playing` event. Every production load passes through `loading`, so no
  per-load flag or `_status` reset is needed for transition detection.
- **Test fakes.** In tests, `_Player` starts in `playing`
  (`test/playback/player_coordinator_test.dart:4443-4446`), and
  `_EventPlayer.load` emits nothing. `emitStatus` reads `player.position`
  (`:4661-4672`). `test/support/ui_fixture.dart:100-103` emits `loading` on
  load, like production.

### Collections

Desktop never asks Plex which collections exist. It infers membership from
the `Collection` tags on scanned items:

- `parseMediaItem` (`lib/plex/plex_client.dart:1091`, `collections:` at
  `:1126`) reads the tags.
- The builder (`lib/channels/channel_builder.dart:195-199`), the resolver
  (`lib/channels/content_resolver.dart:48-50`), and the Studio facet
  (`lib/app/channel_studio_view.dart:2294, 2352`) all read `item.collections`.

Three kinds of collection are lost as a result:

1. **TV collections.** `libraryItems` scans episodes for show libraries
   (`type=4`, `plex_client.dart:382`), and episodes don't carry their show's
   collection tags.
2. **Smart collections.** They are saved filters, so their members carry no
   tag. Kometa often creates them.
3. **Possibly truncated tag lists.** Tag arrays in list responses may be
   shortened. This has not been verified on a live server.

**Kometa recreating collections is not the cause.** Saved channels identify a
collection by its **title** within a library. They use `LibrarySource` filters
keyed by name (`channel_builder.dart:164-170`), not a Plex `ratingKey`.

### Same class of problem in TV Genres (adjacent finding)

Episodes don't carry show-level genres either. Every tag is parsed from the
episode (`plex_client.dart:1125-1130`), so TV Genre channels count nothing,
and episode genres shown in the Guide and OSD are empty
(`content_resolver.dart:164`). Upstream resolves this from show-level genres
(`Lineup/src/.../ContentResolver.ts:196-200, 256-270`).

---

## Work units

Units in the same wave have **disjoint write ownership** and can run in
parallel in the one local checkout. Children run only the targeted tests for
their area. The orchestrator owns Git, the full-suite checks, integration, and
any change that needs the user's approval.

| Unit | Wave | Suggested executor | Writes (exclusive) |
| --- | --- | --- | --- |
| A1 Coordinator overlay and cursor timing | 1 | `worker_luna` | `lib/playback/player_coordinator.dart`, `test/playback/player_coordinator_test.dart` |
| A2 Keyboard-only focus suspension and pause during loading | 1 | `worker` | `lib/playback/player_view.dart`, `lib/app/lineup_shell.dart` (focus-restore paths only), `lib/playback/windows_native_player.dart`, `test/playback/player_view_test.dart`, `test/playback/windows_native_player_test.dart` |
| B1 Plex inventory: collection membership, show genres, failure policy | 1 | `worker` | `lib/plex/plex_client.dart`, `lib/plex/plex_models.dart`, `lib/app/lineup_controller.dart`, `test/plex/*`, `test/app/lineup_controller_test.dart`, `test/app/product_spine_test.dart`, `test/support/ui_fixture.dart` |
| B2 Builder rules | 1 | `worker_luna` | `lib/channels/channel_builder.dart`, `test/channels/channel_builder_test.dart` |
| A3 Player notification coalescing and view-owned clock | 2 (after A1 and A2) | `worker` | `lib/playback/player_coordinator.dart`, `lib/playback/player_view.dart`, `lib/app/lineup_shell.dart`, `lib/playback/windows_native_player.dart`, related tests |
| B3 Setup and Studio surfaces | 2 (after B1 and B2) | `worker` | `lib/app/channel_setup_view.dart`, `lib/app/channel_studio_view.dart`, `lib/app/lineup_controller.dart` (apply/review plumbing only), related `test/app/*` and goldens |

Documentation updates are assigned to the unit that changes each behavior.
The orchestrator reconciles them at the end.

---

### A1: Coordinator overlay and cursor timing

**Owner:** `PlayerCoordinator`.

1. **Act on state transitions, not on every event.** In `_event`, capture
   `previousState = _status.state` before `_status` is overwritten.
   - For `ready/paused/buffering/seeking`: call `_setOverlay(osd)` only when
     `event.status.state != previousState`. Keep the `nowPlaying` guard.
   - For `playing`: call `_scheduleOverlayHide` only when
     `previousState != PlayerState.playing` and the overlay is the OSD.
   - Leave `loading`, `stopped/ended` part advancement, `idle/unsupported`,
     and error handling as they are. Do not throttle events in the transport;
     position must stay exact.
2. **Pointer activity re-arms the OSD in any playback state.** At present,
   `handlePointerActivity` (`:1402-1410`) re-arms only while playing, so a
   paused OSD disappears under a moving mouse. Re-arm whenever the overlay is
   the OSD.
3. **Pointer activity ends keyboard focus suspension (D1).** If
   `_overlayFocusSuspended` is set, pointer activity clears it and schedules
   the hide. Pointer use is now the active input mode.
4. **Cursor auto-hide works with OSD timeouts of 4 seconds or more.**
   - **Current behavior:** `showCursor` (`:1387-1400`) arms a fixed 3-second
     check. It hides the cursor only if, at that moment, playback is playing
     and no overlay is open. With an OSD timeout of 4 seconds or more, the OSD
     is still visible at 3 seconds, and nothing checks the cursor again, so
     the cursor never hides.
   - **Fix:** when the OSD auto-hide fires, also hide the cursor if playback
     is playing and the pointer has been idle for at least 3 seconds. The
     equivalent alternative is to re-evaluate the cursor at
     `max(3 s, remaining OSD timeout)`.
   - Keep the 3-second idle rule for the case where no overlay is open.

**Required tests** (`test/playback/player_coordinator_test.dart`):

Tests must start from a non-`playing` state where a transition matters: set
`player.status` or emit `loading` first. Set `player.position` before each
emit.

- **Regression:** with steady `playing`, call `showOsd()`, then emit
  `playing` every 250 ms with increasing position. Assert the OSD is visible
  at timeout − 1 ms and hidden at timeout + 1 ms. Repeat with a 2-second
  setting.
- A `loading → playing` transition arms the hide timer. A
  `playing → paused → playing` sequence re-arms it at each transition.
  Repeated `paused` events do not postpone hiding.
- **No overlay replacement on repeated paused events:**
  - With the audio or subtitle track panel open, a further `paused` event
    (simulating a track-list update) does not replace the panel.
  - The same holds for the Mini Guide, the Sleep picker, and channel-number
    entry.
- **Pointer activity:**
  - While playing, pointer activity during repeated events postpones hiding
    until one timeout after the last pointer activity.
  - The same applies while paused.
  - Pointer activity clears a focus suspension.
- **Cursor:**
  - With the default 4-second OSD, after pointer activity while playing, the
    cursor is hidden once the OSD auto-hides.
  - The cursor stays visible while paused.
  - It reappears on pointer activity.
- The five existing timing tests stay green: lines `1644`, `1669`, `1719`,
  `1772`, `1797`.

**Docs:** in `docs/product-parity.md`, the "Cursor auto-hide and pointer wake"
row (`:286`) claims PARITY with tests. Make that claim accurate by citing the
new tests.

### A2: Keyboard-only focus suspension and pause during loading

1. **Keyboard-only suspension (D1). Owner:** `player_view.dart`.
   - **Current behavior:**
     - The view reports `overlayFocusChanged(..., true)` whenever focus is
       inside the OSD in `FocusHighlightMode.traditional` (`:116-131`,
       `:491-503`). On desktop, mouse use is also traditional, so it cannot
       tell keyboard focus from mouse focus.
     - The Sleep picker returns focus to its trigger after a mouse choice
       (`:2599-2604`, `:2663-2666`, `:372-376`).
     - Closing the app menu returns focus to the OSD menu button
       (`lib/app/lineup_shell.dart:273-288`).
     - Together these leave the OSD suspended indefinitely for mouse users.
   - **Required behavior:**
     - Report suspension only when the focus change came from keyboard
       interaction. For example, track the last input modality from key
       versus pointer events at the Player root; choose a mechanism that is
       testable.
     - Restore focus to an OSD control after Sleep or menu dismissal only
       when that action was keyboard-driven. Otherwise focus the Player root.
   - Keep every keyboard path the same: Tab or arrow keys into the OSD
     suspend; leaving restarts the full timeout.
2. **Pause pressed during loading is lost. Owner:**
   `WindowsNativePlayer`.
   - **Current behavior:**
     - `_handleProperty('pause')` (`:505-512`) ignores the value unless the
       state is already playing or paused.
     - Native reports `FILE_LOADED` as `playing`
       (`native_player.cpp:1103-1104`).
     - mpv only notifies `pause` when it changes. A pause requested during
       `loading` is therefore never reflected, and the coordinator shows
       "playing" over a frozen frame.
   - **Fix:** record the latest `pause` value whatever the state. When the
     state moves to `playing`, report `paused` if the recorded value is true.
     First check how `load()` and `pause()`/`play()` set the value across
     loads. mpv's `pause` persists across `loadfile`, so verify that a new
     load does not inherit a stale pause unintentionally. Do not change
     native code unless the Dart-side fix proves insufficient.
   - Replace the test at `windows_native_player_test.dart:1561-1566`. It sends
     a second `pause=true` that real mpv would not send. Use the realistic
     sequence: `pause=true` during loading, then `playing`.

**Required tests:**

- A widget test using **mouse** input (`tester.tap(..., kind:
  PointerDeviceKind.mouse)` or a `TestPointer` of kind mouse) covering:
  - choose a Sleep preset;
  - assert the OSD hides after the timeout.
- The same check for app-menu open and dismissal with the mouse.
- The keyboard equivalents must still suspend.
- The transport test for pause during loading.
- Run `test/playback/` and the affected `test/app/` Player and shell tests.

### A3: Player notification coalescing and view-owned clock (after A1 and A2)

The coordinator calls `notifyListeners()` once per native event (`_event`
ends with it), so about 24–60 times per second. Listeners include:

- `PlayerView._changed`, which calls `setState`;
- the shell `setState` (`lineup_shell.dart:84, 90-108`), which rebuilds the
  selected route on every event. That includes the Guide with
  picture-in-picture (`guide_view.dart:477-505`, a post-frame viewport request
  on each build), Channels, Settings, and Diagnostics (`diagnostics_view.dart:123-129`).

Only the OSD and Now Playing display player position, and they need at most
4 updates per second. This is measured nowhere yet; treat it as a
performance risk, not a confirmed defect.

1. **Coordinator.**
   - Keep consuming every event, so the internal position stays exact for
     `_nativePosition`, `seekBy`, and the resume position after a re-login.
   - Notify only when a visible fact changes: status, duration, tracks,
     telemetry, overlay, or error. A position change notifies only when it
     crosses a 250 ms boundary.
   - Keep tests deterministic.
2. **Shell.** Rebuild only when a player field that the shell actually uses
   changes.
3. **Transport.** Stop copying the track list again on every emit
   (`windows_native_player.dart:750`). It is already unmodifiable, and the
   copy defeats identity comparison.
4. **View-owned clock (pre-existing bug, and required before step 1).**
   - **Current behavior:** the Mini Guide clock and progress, the OSD and Now
     Playing current/next program, and Now Playing's schedule-based timing
     (`player_view.dart:720, 2117, 2321-2332`) refresh only because
     coordinator notifications keep arriving. They already freeze while
     paused or stopped.
   - **Fix:** add a view-owned periodic refresh while those surfaces are
     visible. It should resemble the Guide's existing 30-second clock, with a
     cadence suited to its display.

**Required tests:**

- **Notification count:** 60 position-only events in one second cause at
  most ~4 notifications.
- A status, track, or overlay change still notifies immediately.
- The Mini Guide refreshes while paused, with no player events.
- A seek or resume after a re-login still uses the exact position.

**Outstanding acceptance:** a Windows profile-build timeline on the Player
(OSD hidden) and on the Guide with picture-in-picture, measuring frames per
second and mpv frame drops. Record before and after.

### B1: Plex inventory (collection membership, show genres, failure policy)

**Design:** membership from Plex's own collection endpoints is authoritative,
and the persisted source shape is unchanged. Saved
`LibrarySource(filters: {collection: [title]})` channels stay valid; there is
no migration. Name identity means that a collection Kometa deletes and
recreates under the same title resolves after the next scan.

The plan rejects the alternatives below:

- **Persisting a collection `ratingKey`, as upstream does.** It needs a schema
  migration, and it brings back upstream's recreation fragility.
- **Proposals from the collection listing only.** The resolver and Studio
  would still match tags.

#### Client (`plex_client.dart`)

Keep `libraryItems` as the item pager only. About 20 transport tests depend on
its exact request sequence.

Add the following methods.

1. **`libraryCollectionMembership(server, token, libraryId, {isCurrent, cancelled})`**
   - **Listing.**
     - Request `GET /library/sections/{id}/all?type=18`, paged with
       `X-Plex-Container-Start/Size`. Upstream uses this endpoint
       (`Lineup/src/modules/plex/library/PlexLibrary.ts:642-652`).
     - Validate pages as strictly as `libraryItems` does.
     - Parse `ratingKey` and `title`. Normalize the title the same way
       `_tagNames` normalizes tags (trim through `_optionalText`), so tag-era
       saved filters still match.
     - `childCount` is optional (`_optionalInteger`). Skip a collection only
       when `childCount` is **explicitly 0**.
     - Do not parse `smart`.
   - **Children.**
     - Request `GET /library/collections/{key}/children`, URL-encoding the
       key the same way playlists do (`plex_client.dart:745`).
     - Request pages, but tolerate a server that ignores container size: a
       response larger than requested is valid only if it completes the
       reported total. Otherwise it is malformed.
     - A member row without `ratingKey` is malformed.
     - A repeated `ratingKey` in the same collection is a page that is not
       progressing.
     - Collect member rating keys only.
   - **Concurrency.** Use a sliding worker pool, not fixed `Future.wait`
     batches, so one slow smart collection doesn't stall its batch. Use a
     per-library limit (e.g. 4) and a total cap across concurrent library
     scans (e.g. 8; the controller scans up to 4 libraries at once,
     `lineup_controller.dart:974-976`). Check `isCurrent` and `cancelled`
     between requests.
   - **Authorization and cancellation.** A fatal authorization failure aborts
     sibling IO and propagates, following the attempt-abort structure in
     `playlists()` (`:515-625`). Cancellation also propagates.
   - **Collection that returns 404** (`PlexException('resource-not-found')`,
     `:1326-1334`):
     - re-list the library's collections once;
     - if the same title now has a different key, fetch that key;
     - if the title is gone from the fresh listing, skip it (confirmed
       deleted);
     - otherwise mark the title as failed.
   - **Any other per-collection failure** (transport, timeout, 5xx,
     malformed) marks that **title** as failed. It does not fail the library.
   - **Listing failure** marks the library's membership as **unavailable**.
     It does not fail the item scan.
   - **Limits.** Collection count and total member entries per library are
     bounded, with `library-scale-exceeded`-style errors. Use limits of the
     same order as `libraryItems`' 1000-page guard, and document the chosen
     constants.
   - **Return value:** a reverse index (member rating key → set of titles;
     duplicate titles merge), the failed titles, and the unavailable flag.
2. **`libraryShowGenres(...)`** (TV libraries only, D2)
   - Request `GET /library/sections/{id}/all?type=2`, paged with the same
     validation.
   - Return show `ratingKey` → genres, normalized like `_tagNames`.
   - A failure here fails that library's scan, like an item-page failure.
     This is the core episode metadata, not optional enrichment.
3. **`scanLibrary(...)`**
   - Combines `libraryItems`, `libraryCollectionMembership`, and (for TV)
     `libraryShowGenres`.
   - Applies the annotation in **one pass** over the items:
     - `collections` = the union of titles indexed under `item.id`,
       `parentRatingKey`, and `grandparentRatingKey`, with duplicates
       removed. This **replaces** the item's tags; do not union with them.
     - For episodes, `genres` = the episode's genres plus the show's genres,
       with duplicates removed.
   - Report progress monotonically: `LibraryScanFact` counters must not go
     backwards. Do not add new UI text.

#### Model (`plex_models.dart`)

- Add `parentRatingKey`, validated like `grandparentRatingKey`, and parse it
  in `parseMediaItem` (`plex_client.dart:1091`).
- `PlexMediaItem` has no `copyWith`. Build the annotated items without
  parsing twice.
- Playlist items (`plex_client.dart:582`) keep their tag-parsed
  `collections`. B3 excludes items without a library from the Studio
  collection facet.

#### Controller (`lineup_controller.dart`)

- Call `plex.scanLibrary` at `:900`, inside the existing
  `_withPmsAuthorization`.
- Extend `_LibraryScanResult` (`:25`) with:
  - failed collection titles per library;
  - the IDs of libraries whose collection membership is unavailable.
- **Launch path.** Server restoration calls `_loadLibraries` **without**
  `settleFailures` (`:695-705`), and any library failure blocks Ready
  (`:978-979`). Add `_requireAvailableCollections`, modeled on
  `_requireAvailablePlaylists` (`:1083-1094`).
  - It throws a retryable `PlexException('collection-unavailable', ...)`
    only when a saved channel's `LibrarySource` collection filter (including
    inside `MixedSource`) refers to a failed title in that library, or to a
    library whose membership is unavailable.
  - Otherwise, failures only produce a diagnostic, with redacted counts and
    no titles.
- **Setup path** (`settleFailures: true`, `:745-751`). Record the failure
  information for B3 and the builder. Failed titles simply have no members,
  so they produce no proposals.

#### Required tests

- **`test/plex/plex_transport_test.dart`** (or a new focused file) must cover:
  - listing pagination and validation;
  - children pagination, including oversized complete responses and
    oversized incomplete ones;
  - smart collections and regular collections;
  - `childCount` 0 skipped, while a missing count is fetched;
  - a children 404 where the collection is recreated mid-scan (re-list, then
    fetch the new key);
  - a children 404 where the collection is gone (skip);
  - a 404 that is still listed (failed title);
  - 500, timeout, or malformed responses (failed title, library intact);
  - a listing failure (unavailable);
  - 401/403 aborting siblings and propagating;
  - cancellation and `isCurrent` false stopping IO;
  - the sliding pool bound being respected;
  - scale limits;
  - show-genre paging.
- **Annotation:**
  - movie, show, season, and episode collections;
  - a stale tag on a non-member is not kept;
  - duplicate titles merge;
  - a trimmed title matches a saved tag-era filter string;
  - episodes inherit show genres.
- **`test/plex/plex_parser_test.dart:49`.** It currently says tags are the
  builder's source. Re-scope it.
- **Controller tests:**
  - Launch with a failed title used by a saved channel throws a retryable
    `collection-unavailable`.
  - Launch with a failed title nobody uses reaches Ready.
  - A stale or superseded scan cannot publish annotated items.
  - A **Kometa recreation** across two scans (same title, new key, same
    members) resolves the saved channel to the same content and schedule.
- **Fakes.** Update the fakes to override `scanLibrary`:
  - `_FakePlex` (`test/app/lineup_controller_test.dart:5822-5829`);
  - `_ProductPlex` (`test/app/product_spine_test.dart:262-266`);
  - `test/support/ui_fixture.dart:43-48`.
  Their HTTP clients throw on unexpected requests.
- **`content_resolver_test.dart`.** A persisted collection filter resolves TV
  and smart collection content from annotated inventory.

#### Docs

- **`docs/product-parity.md:212`** ("Eight strategy families") claims PARITY,
  but collections and TV genres were partial. Update it with the evidence.
- **`guide-freshness-collection-investigation.md`.** Add a note that
  membership now comes from Plex, so a same-title recreation resolves after
  the next scan. Live-session refresh is still deferred.

#### B1 implemented bounds and approved live measurement budget

Collection children use four sliding workers per library and a shared cap of
eight active collection streams per `PlexClient`, across up to four simultaneous
library scans. Pages request 100 records and each metadata stream stops at 1,000
pages. Each collection listing is limited to 100,000 records; a library scan is
limited to 100,000 aggregate member entries, counting repeated membership across
collections and 404 recovery fetches. Oversized child pages are accepted only when
they complete the reported total. A scale failure marks membership unavailable
and publishes no partial index. These bounds have synthetic test coverage.

The October 10 follow-up retains these limits. Recovery distinguishes collection
listing exhaustion, aggregate member exhaustion, and page-budget exhaustion from
transient discovery failure. Affected saved channels remain preserved; an
over-limit inventory must be reduced in Plex before rescanning can recover it.
A larger work budget is not approved by this correction. Neither synthetic
coverage nor this recovery change establishes the live measurement budget below.

**Approved budget (October 7, 2026); no live measurement performed:** added
median scan time must be at most `max(20 seconds, 50% of the item-only median)`,
with no single paired run adding more than twice that allowance. Measure launch
and setup separately; a pass on one path does not establish the other. These are
acceptance thresholds, not runtime timeouts or permission to omit membership.

**Measurement instrument (added October 7, 2026, after implementation).** With
Diagnostics recording enabled, every successful library scan records one
`plex-library: Library scan timing` event. It holds:

- `scanPath`: `launch` (selected-server restoration) or `setup` (Channel Setup
  scan);
- `libraryType`;
- monotonic phase durations: `itemsMs`, `collectionsMs`, and `showGenresMs`;
- redacted counts: `items`, `collections` (distinct titles with members),
  `members`, and `shows`.

The event never includes titles, keys, or URLs. It appears in the Diagnostics
view and in the copied support report.

`PlexClient.scanLibrary` runs its phases sequentially, so `itemsMs` is the
item-only baseline. `collectionsMs + showGenresMs` is the added time for the
same scan. Each successful scan is therefore one self-contained pair, and no
second build is needed.

Use the same host, Plex profile/server, route, library selection, and unchanged
contents.

- **Launch:** relaunch the app; each relaunch with saved channels is one launch
  sample.
- **Setup:** run Channel Setup's scan; each run is one setup sample.

Discard the first sample on each path as a warm-up. Then record five sequential
samples per path for the largest library, without overlapping scans. Count only
fully successful scans with the same `items` count. For each path, record:

- every `itemsMs` and added duration;
- the item-only median;
- the added-time median and maximum;
- the commit and route class (local or remote);
- `libraryType` and the redacted counts.

Repeat with the normal selected-library set, where libraries scan concurrently
and share the collection request cap, and report that separately.

If live measurement exceeds the budget, report the measured path and results
back to the user. The fallback to propose is to load collection membership on
launch only for libraries with saved collection channels, and load the remaining
libraries' membership during setup. This fallback is not implemented or approved
for immediate activation; it is conditional on the live results. It must preserve
saved-source resolution and cannot convert missing membership into source absence.

### B2: Builder rules (`channel_builder.dart`)

1. **TV Recently Added plays shuffled instead of newest-first.**
   - **Current behavior:** `materializeChannelPlan` (`:321-322`) applies the
     series mode to every show-library proposal. That includes the
     `sequential` Recently Added channel (`:214`), and it then gains Alt
     copies (`:537-546`).
   - **Fix:** apply the series mode only when
     `proposal.mode == PlaybackMode.shuffle`, matching upstream
     (`ChannelSetupPlanner.ts:432`). Check that the variant logic at `:506`
     stays consistent.
2. **Running out of channel numbers stops updates.**
   - **Current behavior:** on the first new channel that cannot get a number,
     the loop `break`s (`:408-414`). Later entries that would only update an
     existing channel are then skipped and keep their old settings.
   - **Fix:** skip the entry and continue. `numberLimitExcluded` counts only
     the entries actually excluded.
3. **Append skips existing sources (D4).** In `ChannelBuildMode.append`,
   skip any planned original or extra whose `builderKey` matches an existing
   channel. Report the count in `ChannelPlanAllocation` (e.g.
   `existingSkipped`) for B3 to display.
4. **Unmatched existing channels for Update (D4).** In merge mode, return the
   existing generated channels (`builderKey != null`) that no planned channel
   re-matches. B3 decides which of them are confirmed "Source not found".
   The builder does not delete or classify them.

**Required tests:**

- A TV Recently Added channel stays sequential and has no Alt copies. TV
  shuffle strategies (including collections) still use the series mode.
- After the numbers run out, merge entries still update.
- Append skips existing keys and reports the count.
- Merge returns the unmatched generated channels.
- Existing fixtures at `channel_builder_test.dart:166, 710` use
  shuffle-mode Recently Added and are expected to stay green.

### B3: Setup and Studio surfaces (after B1 and B2)

All new copy and states follow `.interface-design/system.md` and the existing
row and review patterns. Before merge, the orchestrator shows the user the
exact copy and matched before/after screenshots or goldens at the relevant
sizes. A golden update is not approval.

1. **Playlists row failure (D3).**
   - Carry the playlist discovery outcome from the controller:
     - catalog unavailable (`lineup_controller.dart:1005-1021`);
     - N playlists failed (`:1030-1034`).
   - The Playlists strategy row shows an unavailable or partial state with
     Retry, instead of "None in your libraries" (`channel_setup_view.dart:1298-1299`).
   - Retry reuses the existing scan-retry path. It does not create a second
     loader.
2. **Collection failures** (from B1). If collections failed or membership is
   unavailable for a library, the Collections row says so, using the same
   pattern as Playlists. It must never say "None".
3. **Append (D4).** Show the skipped count in the review, e.g. "N already in
   your lineup". The exact copy needs the user's approval.
4. **Update review: "Source not found" (D4).**
   - From B2's unmatched channels, classify a channel as **confirmed gone**
     only when:
     - its library's scan completed;
     - it is not affected by any failed collection title, unavailable
       membership, or failed playlist; and
     - its source resolves to zero playable items against that complete
       inventory.
   - List those channels in a **Source not found** section, with keep or
     remove per channel. **The default is keep.**
   - Unmatched channels that are not confirmed gone stay as they are today
     and are not listed as removed.
   - Apply the choices atomically through the existing build-apply path:
     - rollback on save failure is unchanged;
     - content-generation invalidation is unchanged.
5. **Studio collection facet.** Exclude items with `libraryId == null`
   (playlist-only items carrying stale tags) from the collection values
   (`channel_studio_view.dart:2291-2296`), so every value offered can
   resolve.

**Required tests:**

- Widget tests for:
  - the Playlists unavailable and partial states, plus Retry;
  - the Collections failure state;
  - the append skipped count;
  - the Source not found list with keep and remove choices;
  - never listing a channel affected by a failure;
  - the Studio facet excluding items without a library.
- A controller test showing that applying a removal is atomic and rolls back
  on save failure.
- Golden and visual updates only with the user's approval of the design.

---

## Recorded and out of scope this pass

- **Live-session refresh.** Updating collection membership while the app
  stays open (the freshness doc's deferred question).
- **Rebinding renamed collections.** Also fuzzy or cross-library matching.
- **Stable-order shuffle.** Canonicalizing shuffle order (freshness doc,
  scenario A).
- **Tag truncation in `/all` list views** for Role, Genre, and Director. It
  is unverified. Settle it with the live probe below before scoping any
  "full tag membership" work.
- **TV Studios and network channels** (D2).
- **Actors on TV** (unchanged).
- **Recently Added content.** Unlimited size and ID tie-break order; same as
  upstream; a product question.
- **Continue with partial libraries.** Its side effects (finding F9) are a
  product question for later.
- **Naming collisions.** Genre, collection, and playlist channels can share a
  name in single-library mode, and variant suffixes use raw mode names.
- **Smart playlist paging stability.** Needs live observation first.
- **The `loading` flash on tune.** The `loading` event hides the OSD that
  `tune()` shows (`player_coordinator.dart:387-392`, `461-463`). Observe it
  on Windows before changing anything.
- **Multi-part duration capture at end of file.** Get a Windows event trace
  first.

## Independent implementation review

The read-only review of `97cf093a` through `95056800` found one P2 issue:
when all channel numbers were occupied and a generated original was absent,
its surviving Alt or variant could miss an Update and be reported unmatched.
The accepted correction retains the proposal for extra expansion even when
the original cannot be allocated. A focused regression verifies the surviving
Alt's identity, updated settings, unmatched result, and exclusion counts.
The correction is committed as `c732f79f`. No other material findings were
established.

Integrated checks passed after Wave 1 (1,122 tests), after Wave 2 (1,142 tests),
and after review remediation (1,143 tests at `c732f79f`). Each run used full
repository formatting verification, `flutter analyze`, and
`TZ=America/New_York flutter test`. B3's approved layout changes were rendered
in matched 1920×1080 and 960×720 states; no goldens were updated. Its regression
confirms that selecting Remove changes 7 final / 0 Removed to 6 final /
1 Removed and updates the table row from Unchanged to Removed. This review,
rendering, and the portable checks do not replace the acceptance below.

## Acceptance outside this checkout (user)

Use redacted counts and timings only. Record no collection names, server
addresses, or tokens.

1. **Windows Player:**
   - the OSD hides after 4 s and after one other setting;
   - the cursor hides after the OSD;
   - a mouse Sleep preset or menu dismissal still times out;
   - keyboard focus in the OSD still keeps it open;
   - pausing during "Preparing playback" with DVR on shows paused.
2. **Windows profile timeline** before and after A3.
3. **Plex:**
   - Collections in a movie library and a TV library produce close to the
     expected number of channels.
   - TV collection counts are in episodes, so Desktop legitimately exceeds
     upstream's show-based counts.
   - Tune a TV collection channel and a smart collection channel.
   - Relaunch after a Kometa run; saved channels still resolve.
   - Measure launch and setup separately for the largest library: added
     median must be at most `max(20 s, 50% of the item-only median)`, with
     no single paired run above twice that allowance. Follow the paired
     measurement protocol above and report any exceedance before changing
     the launch policy.
4. **Live probes** (they settle the open hypotheses):
   - Compare tag array lengths in `/all?type=1` against `/library/metadata/{id}`
     for 20 movies.
   - Does `/children` honor paging?
   - Do smart collections report `childCount`?

## Verification commands (orchestrator, after integration)

On macOS/Linux, run the portable commands from the pinned toolchain:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
TZ=America/New_York flutter test
```

On Windows, follow [Development's portable commands](DEVELOPMENT.md#portable-commands),
record the machine's actual OS timezone, and do not treat `TZ` alone as
canonical. Do not change the OS timezone automatically.
