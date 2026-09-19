# Lineup UX and Functionality Audit

Living report for issues found during hands-on Windows testing. Add new items
below without rewriting the original observations. Status values are: reported,
investigating, ready to implement, verified, or deferred.

## Test context

- Date: 2026-09-13
- Build: local patched-engine Windows debug build
- Server: local Plex server (private metadata intentionally omitted)
- State: clean first-run test is being prepared

## 1. Collection-based lineup generation produces too few channels

- Status: investigating
- Reported behavior: the Collections strategy created only 20 channels for the
  local Plex server, whereas the prior Lineup workflow generated substantially
  more.
- Expected behavior: every eligible collection in every selected library should
  be represented according to the selected builder policy; any exclusion or
  deduplication must be visible and explainable.

### Initial source observations

- `lib/channels/channel_builder.dart` derives collection channels from the
  `collections` lists attached to fetched library items.
- Plex item parsing reads the `Collection` tags in `lib/plex/plex_client.dart`.
- The setup screen owns strategy selection and builder application in
  `lib/app/channel_setup_view.dart`.

### Investigation plan

1. Record selected libraries and the count of distinct Plex collection names in
   each, without recording private names in this document.
2. Compare those counts with the builder input, generated candidates, rejected
   candidates, and applied channels.
3. Check whether the Plex fetch is paginated, media-type scoped, or omits
   collections that have no directly returned items.
4. Check normalized-name collisions, empty/unplayable collections, and any
   channel-cap policy.
5. Reproduce against the same local server and add a regression test for the
   confirmed failure mode.

### Acceptance criteria

- Generated count is reconcilable to an explicit input/exclusion report.
- Expected local-server collections produce channels.
- The UI explains any skipped collection before apply.

## 2. First Lineup screen action alignment

- Status: reported
- Reported behavior: **Back to configure** is not vertically aligned with
  **Create lineup**.
- Owner: `lib/app/channel_setup_view.dart` (the Back button is near the
  initial setup action controls).
- Investigation: inspect at the reported window size and representative compact
  and expanded sizes; compare button height, baseline, surrounding padding, and
  focus outline.
- Acceptance criteria: the two peer actions share an intentional vertical axis,
  control height, and focus geometry at supported sizes.

## 3. Channel Studio functionality and UX audit

- Status: investigating
- Scope: audit the full create/edit flow, content selection model, filters,
  schedule behavior, previews, validation, save/apply behavior, keyboard/focus,
  and empty/error states.
- Owner: `lib/app/channel_studio_view.dart` and its channel/scheduling models.

### Reported selection-model issue

- Choosing a TV show currently populates individual episodes immediately.
- Desired behavior: choosing a show should add the show as a series-level
  source, whose episodes are shuffled when the channel plays. Episode-level
  picking should appear only after deliberately opening a show to select
  specific episodes.
- Example intent: create a test channel from three or four specific shows, with
  each show contributing shuffled episodes.

### Questions to resolve before implementation

1. How should a series source interact with ordering, shuffle, limits, and
   duplicate episodes selected explicitly elsewhere?
2. Which source model is authoritative for an entire show versus a selected
   episode subset?
3. How does the Studio communicate that a show is included as a dynamic series
   source rather than a frozen list of episodes?
4. What is the least confusing drill-in and back-navigation behavior for
   episode selection?

### Acceptance criteria

- A user can add whole shows without selecting every episode.
- A user can intentionally drill into a show and select only specific episodes.
- Preview, persisted channel source, scheduling, and playback reflect the
  selected model exactly.
- The Studio’s key paths are auditable with focused widget/model tests.

## 4. Audio and subtitle track labels

- Status: reported
- Reported behavior: raw native track values are shown and do not make good
  user-facing labels.
- Owner: `lib/playback/player_view.dart` with metadata from
  `lib/playback/windows_native_player.dart`.
- Investigation: capture representative audio and subtitle metadata fields and
  define a stable display policy: language, codec, channels, title, default,
  forced, and external/embedded state where available.
- Acceptance criteria: labels are human-readable, consistent, localized where
  feasible, and retain enough technical detail to distinguish tracks.

## 5. Guide separators and program-card clarity

- Status: reported
- Reported behavior: unexpected vertical lines appear through portions of the
  Guide. Individual programs within a channel also need clearer visual
  separation.
- Owner: `lib/guide/guide_view.dart` and the shared theme in
  `lib/ui/app_theme.dart`.
- Investigation: capture the exact screen state, viewport size, horizontal
  offset, scale, theme, selected/focused item, and whether a line corresponds
  to a time/grid/program boundary. Inspect clipping, paint order, borders, and
  fractional-pixel calculations.
- Acceptance criteria: no unintended line appears at any supported scale or
  scroll position; program boundaries remain legible without weakening focus,
  now-playing, or time-grid hierarchy.

## 6. Discoverability, action placement, and missing UI controls

- Status: investigating
- Reported concern: some useful functions may be reachable only through
  keyboard shortcuts or otherwise hidden interactions. A new user should not
  need to know a shortcut before discovering an important surface.
- First example: the Now Playing information panel is available with the `I`
  shortcut, but has no apparent in-product control that advertises its
  existence.
- Scope: review every app surface for actions that are keyboard-only, buried in
  an unexpected menu, absent when contextually useful, or visually overexposed.
  This is not a request to add buttons indiscriminately; controls should earn
  their space through a clear user task and contextual value.

### Investigation plan

1. Inventory every command, shortcut, menu item, and overlay by screen and
   identify its current visual entry point.
2. Test first-run discoverability and common flows without using the keyboard
   shortcut reference.
3. Review comparable interaction patterns in established TV and streaming
   products: persistent player controls, contextual overflow menus, information
   panels, guide actions, and remote-friendly focus navigation.
4. For each candidate control, define its user task, trigger context, label or
   icon affordance, focus behavior, and why it belongs on that surface rather
   than in an overflow menu or shortcut-only path.
5. Validate that added controls improve discoverability without crowding the
   TV-first UI or duplicating the same action across unrelated surfaces.

### Acceptance criteria

- Every important user-facing function has a discoverable UI path.
- Keyboard shortcuts remain efficient accelerators, not the sole path to core
  functionality.
- New controls are contextual, legible, focusable, and consistent with the
  application’s visual hierarchy.
- The Now Playing information panel has an obvious contextual entry point.

## 7. Application-wide fullscreen

- Status: reported
- Reported behavior: fullscreen is available for player playback, but there is
  no fullscreen mode for the Lineup application as a whole.
- Desired behavior: users can enter and leave fullscreen while using any major
  application surface (Guide, Channels, setup, settings, or Player), not only
  during video playback. The application remembers the chosen window/fullscreen
  state across relaunches.
- Scope: this is a window-level mode and must remain distinct from player media
  fullscreen, which may have different playback and overlay behavior.

### Investigation plan

1. Identify the current authoritative window/fullscreen owner and the existing
   player-only fullscreen contract.
2. Define transitions between windowed app mode, application fullscreen, and
   player media fullscreen, including Escape, menu/shortcut access, focus, and
   restore behavior.
3. Decide the persisted state model: fullscreen preference, previous window
   bounds, monitor/DPI behavior, and safe recovery when a display disappears.
4. Verify all primary routes in fullscreen, including dialogs, overlays, native
   video composition, keyboard navigation, and exit behavior.

### Acceptance criteria

- A discoverable application-level fullscreen control is available outside the
  player.
- The selected mode persists across normal relaunches without trapping the user
  in an inaccessible window state.
- Player fullscreen and application fullscreen have clear, predictable
  transitions.
- Fullscreen behavior is verified on the Windows target with focus, resizing,
  multi-monitor, and DPI scenarios.

## Evidence and follow-up log

Add dated observations, screenshots only after private media and credentials
have been redacted, reproduction steps, confirmed causes, implementation links,
and verification results here.

- 2026-09-13: report created from initial hands-on findings; no causes are yet
  confirmed.

## 2026-09-14 source review and implementation handoff

### Evidence boundary and current disposition

This follow-up inspected commit `764848f7eda102be99be973884319f586fb11396`
on `dev/desktop-ui-refinement` through the GitHub connector. The original
observations above remain historical evidence, not conclusions inferred from
code. Repository guidance, the Dart/Flutter quality and test-design skills,
`.interface-design/system.md`, relevant source owners, existing test fixtures,
and the collection/freshness and fullscreen/HDR investigation documents were
read before preparing changes.

**This was source inspection, not a rerun of the native audit.** There was no
executable project checkout, Flutter/Dart test execution, physical Windows
session, local Plex response capture, or new screenshot evidence. No finding
is marked verified. Authored tests are proposed regression protection until
executed; a connector commit does not establish compilation or runtime safety.

| Finding | Current status | Implementation / remaining gate |
| --- | --- | --- |
| 1. Collections | investigating | Tag-derived coverage and allocation paths traced; exact local count of 20 remains unproven. Capture a count reconciliation before changing discovery. |
| 2. Review action alignment | investigating | Local geometry fix included in this follow-up; widget and physical visual acceptance pending. |
| 3. Studio / whole shows | investigating | Source-model gap identified; dynamic series selection and complete interactive audit remain open. |
| 4. Track labels | ready to implement | Presentation-policy and native-payload gaps identified; formatter and optional metadata bridge work remain open. |
| 5. Guide lines / clarity | investigating | Intentional line and native-aperture paint owners identified; reported unintended line still needs a captured reproduction. |
| 6. Discoverability | investigating | Now Playing menu path included; full command inventory and first-run usability audit remain open. |
| 7. App fullscreen | investigating | Existing native window owner and rollback traced; application policy, persistence, and native acceptance remain open. |

### Changes included in this follow-up

- `lib/app/channel_setup_view.dart`: review secondary and primary actions now
  share minimum size, vertical padding, and text sizing. The setup action Wrap
  centers its children vertically. Existing actions, confirmation, allocation,
  and persistence behavior are unchanged; TextButton versus FilledButton still
  expresses secondary versus primary emphasis.
- `lib/app/lineup_shell.dart`: a contextual **Now Playing** entry opens the
  existing coordinator-owned information overlay from the shared Lineup menu.
  It reuses the normal destination/unsaved-change guard, rechecks context after
  awaiting navigation, and explicitly restores Player focus after menu dismissal.
  It issues no tune, load, seek, pause, or native fullscreen command.
- `test/app/desktop_native_audit_test.dart`: nine widget cases are authored for
  navigation from Guide, Player, and Settings; absence without program metadata;
  unchanged playback-command history; Escape/focus behavior; and review action
  alignment at four viewport sizes. These cases have not been executed here.

**Tester-facing change:** while a scheduled program is available and playback
is not tuning or in error, open the visible Lineup menu and choose **Now
Playing**. The tooltip also advertises `I`. The entry is absent when there is
no usable program context. The existing `I` shortcut and information overlay
remain; this is not a second details implementation or an OSD redesign.

### Finding 1: reconcile collection discovery before changing it

**Established by inspected code:**

- `buildChannelProposals` in `lib/channels/channel_builder.dart` builds collection
  candidates from collection tags on scanned playable items. This is not a
  complete enumeration of Plex collection entities by stable collection key.
- `lib/plex/plex_client.dart` requests movie items with `type=1` and TV episodes
  with `type=4`. It already has library pagination. A blanket claim that the
  client fetches only the first page would therefore be incorrect.
- Item parsing reads `Collection` tags on the returned item. A collection present
  only on a parent show, but absent from returned episode tags, cannot be inferred
  by this path alone. This is a confirmed representational limitation, not proof
  that this particular server omitted its tags.
- Setup initially uses minimum five programs, maximum 200 generated channels,
  all eight strategies enabled, and additional versions disabled. Its candidate
  call removes the proposal-level cap; allocation applies the overall limit.
  Allocation takes one eligible original from each enabled source in order and
  repeats, rather than dedicating the entire limit to Collections.
- The UI already distinguishes qualifying and included counts and reports
  aggregate channel-limit/number-exhaustion exclusions. The missing evidence is
  per-collection reconciliation, not the complete absence of allocation feedback.
  Collections are not one of the strategies offered cross-library grouping.

**Not established:** no hard-coded 20-collection cap was found in this path, and
no captured response establishes the actual cause of the reported 20. Plausible
contributors include tag coverage, minimum-size filtering, playable filtering,
selected-library/profile scope, or allocation. Do not present any one as proven.

**Next investigation, using the same account/profile, server, and selection:**

1. Capture only bounded, redacted facts: selected libraries, scan completion,
   page/item totals, playable counts, and distinct collection membership counts.
   Compare the server's collection inventory with tags in actual movie/episode
   responses. Include a missing collection and a represented collection.
2. Produce a reconciliation table per library: server collections, represented
   collection tags, candidates below the minimum, qualifying originals,
   allocated originals/extras, unavailable channel numbers, and applied results.
   Use synthetic aliases rather than private names or raw responses in this file.
3. Isolate discovery from policy with Collections alone, extras off, minimum one,
   and sufficient channel capacity. Then restore the original selection and
   options. This is a diagnostic experiment, not a change to shipped defaults.
4. If parent membership or entity enumeration is the cause, reproduce it with
   sanitized fixtures before selecting an implementation. Verify collection
   endpoints and pagination against the actual PMS version; do not invent an API
   contract from a presumed endpoint. Keep existing profile/server cancellation,
   scope isolation, and publish-after-persistence behavior.
5. If stable collection identities are introduced, explicitly handle old
   name-based sources, same-name collections in different libraries, renamed or
   recreated collections, and missing membership. Never silently merge sources
   by display name or reset channel identity/seed as a side effect.

**Required tests:** more than 20 eligible collections; multiple pages; TV
parent-only membership; selected-library isolation; empty/unplayable collections;
minimum boundaries; mixed strategies with a 200-channel cap; number exhaustion;
and merge/append/replace persistence. Add a count assertion for each exclusion
reason, not a fixture that merely happens to return 20.

Cross-reference `docs/guide-freshness-collection-investigation.md`. Freshness,
collection identity, and cold-restart schedule determinism are related contracts
but separate failure modes. Do not bundle an unproven reseeding/order change into
this count fix. Capture server facts on Windows where the report occurred; write
portable client/model/controller tests on macOS. PMS requests themselves are not
inherently Windows-only if the Mac has equivalent server access.

### Finding 2: local geometry fix, visual acceptance still required

In `_reviewStep`, the secondary Back TextButton inherited different minimum
height and padding from the primary FilledButton. `_Footer` placed those controls
in a Wrap whose cross-axis alignment was not centered. This supplies a concrete
source explanation for a vertical mismatch without changing the page design.

The follow-up gives both review actions the same scaled minimum size and padding
and centers the action group. It does not apply a global button theme override or
change configure/review behavior. The primary label and removal confirmation
remain dependent on the existing plan and build mode.

Run the new four-size geometry cases, then inspect 1280x720, 1920x1080,
2560x1440, and 3840x2160 with focused/unfocused and enabled/disabled controls.
Also inspect text scale 1.5/2, narrow reflow, and Windows 125/150/200% scaling.
The four new tests use DPR 1; they do not substitute for that DPI matrix.
Check Create lineup, Apply changes, Add channels, Replace generated channels,
and the no-change View lineup case. Do not automatically update approved goldens
to hide a failed geometry or focus assertion.

### Finding 3: a whole show is a source, not a bulk episode selection

**Established model limitation:** `lib/channels/channel.dart` currently models
LibrarySource, PlaylistSource, ManualSource, and MixedSource. The library filter
set does not include a stable series selector. ChannelItem series metadata is
used for episode grouping; it does not make a saved manual episode list into a
dynamic declaration that the entire show is included.

`ChannelStudioView` exposes library, playlist, filtered-library, and hand-picked
choices. Its manual entries retain item/occurrence information and its draft
signature accounts for repeated IDs. Simply replacing a show click with
"select all current episodes" would freeze today's inventory and would not
satisfy the requested dynamic-series behavior.

**Preserve the existing workflow contracts:** source draft resolution feeds the
preview path; saving checks identity/programming and requires a verified Air
Check schedule. `_scheduleIdentityCommitted`, expected-base checks passed to
`saveChannel`, dirty state, conflict/base-deleted state, and generated-channel
inspection are existing safeguards, not missing features to replace. This
review did not exercise them interactively or establish that every edge case is
correct. Keep preview and eventual playback on the same resolver/scheduler.

**Recommended implementation shape:**

- Add a stable, scoped series selection to the source model, using the current
  server/library identity and parent metadata key, not the show title. Decide
  whether a typed series source or a constrained extension of an existing source
  is the smaller coherent change after enumerating all serialization, resolver,
  Studio, source-label, canonical-identity, and persistence consumers.
- Keep explicit episode subsets as explicit selections. Make the whole-show
  action and the episode drill-in different visible actions. Show a series-level
  summary in the selected programming list, not hundreds of episode rows unless
  the user deliberately opens them. Back from drill-in must restore search,
  selection, and focus without discarding the draft.
- Resolve whole shows against current scoped playable inventory; include newly
  discovered episodes after the application's normal refresh. Do not promise
  immediate discovery before inventory refresh exists. Make unavailable shows
  visible and recoverable rather than silently turning them into empty success.
- Use the existing deterministic scheduler for shuffle. A pool of shuffled
  episodes weights longer shows more heavily; equal show weighting/interleaving
  is a different policy. Preserve the current scheduling meaning unless the
  product decision explicitly chooses a new one. Likewise, decide how overlap
  between a whole show and explicit episodes behaves without erasing intentional
  manual repeated occurrences.
- Preserve existing channel IDs, numbers, anchor, shuffle seed, schedule version,
  and saved-state currentness where the user has not requested a scheduling
  change. Coordinate any necessary persistence/migration change with the channel
  store/controller tests, rather than hiding it inside widget state.

**Focused acceptance matrix for the broader Studio audit:**

| Flow | Required observation / regression test |
| --- | --- |
| Three or four whole shows | Saved source retains stable series identities; deterministic preview and playback agree; newly scanned episodes are included. |
| Explicit episode subset | Drill-in is intentional; unselected episodes stay excluded after refresh/restart. |
| Duplicate/overlap | Same-title shows in different libraries remain distinct; intentional repeated manual items follow an explicit documented policy. |
| Filters / limits / order | Include-watched, specials, missing metadata, empty results, sequential/shuffle/block semantics match preview and saved source. |
| Create / edit / duplicate | New identities only when expected; edits preserve unrelated schedule identity and fields; generated inspection stays constrained. |
| Save / discard / conflict | Save failure preserves draft and committed state; stale expected base is rejected; deleted base and save-in-flight navigation recover safely. |
| Keyboard / focus | Whole-show action, episode drill-in, back, search, error recovery, and unsaved-change dialog are operable without a pointer. |
| Scope / lifecycle | Profile/server changes invalidate stale results; restart and inventory refresh do not cross scopes or silently rewrite sources. |

Implement and test the portable source/resolver/Studio work on macOS. Windows
is required for final actual playback and native input/overlay acceptance, not
for writing the Dart source-model tests. This finding is not closed by the two
small UI fixes included here.

### Finding 4: normalize presentation first; expose only factual native metadata

The current end-to-end payload is narrower than the desired display policy:

- `windows/runner/native_player.cpp` whitelists track `id`, `type`, `title`,
  `lang`, `codec`, and `selected` from libmpv's track list.
- `PlayerTrack` in `lib/playback/native_player.dart` carries the corresponding
  title/language/codec presentation inputs. It has no channel-count, default,
  forced, or external/embedded fields.
- `_TrackRail` in `lib/playback/player_view.dart` prefers raw title, then raw
  language, then a type/ID fallback; its detail combines raw language/codec.
  A non-null blank title can defeat a useful fallback. `_osdTrackLabel` performs
  trimming, so rail and OSD do not share one presentation policy.

**Portable first increment:** extract one small track-label policy used by both
surfaces. Trim blank fields; map supported language codes to readable names while
preserving unknown codes; provide readable known codec names; keep custom titles
that distinguish commentary or alternate mixes; avoid repeated title/language
text; retain a stable track-ID disambiguator where otherwise identical labels
would be ambiguous. Examples are illustrative output policy, not captured data:
`English — AAC`, `English — Director commentary`, or `Audio track 3` when metadata
is absent. Subtitle Off remains a distinct action, not a fabricated native track.

Add table-driven tests for null/blank/whitespace title, common language codes,
unknown language/codec, commentary, identical display metadata with different
IDs, missing fields, Unicode titles, and the Off selection. Test a long label at
compact and enlarged text sizes. Use a maintained language mapping only if its
scope/license/dependency cost is proportionate; do not claim a tiny hand-written
map is complete localization.

**Optional second increment:** add channel count/default/forced/external facts
only when libmpv supplies them and the bounded native whitelist, Dart decoder,
and typed model preserve their meaning. Confirm the bundled libmpv contract;
unknown is not false. Do not infer Atmos from a codec, guess forced status from a
filename/title, or display metadata the bridge never received. Keep changes
separate from track selection IDs, load/request generation, acknowledgments,
timeouts, and restoration of the previously confirmed selection.

macOS can implement formatter/model/widget coverage. A redacted Windows capture
should establish representative payloads and verify actual selection for multiple
audio tracks, embedded/external subtitles where present, absent metadata, and
failed switching. Native bridge additions require Windows compilation and runtime
readback. Label cleanup itself does not inherently require Windows.

### Finding 5: distinguish intended lines from a reproducible paint defect

`lib/guide/guide_view.dart` has several deliberately different paint owners:

- `guide-now-line` is an explicit full-height current-time indicator, positioned
  after the rows in the schedule Stack. Its position is based on the visible time
  fraction; it is not an accidental program-card border merely because it crosses
  multiple rows.
- The time header has slot borders, while the channel rail and focused programs
  have their own focus treatment. `_guideTimelineGutter` separates rail/timeline.
- `_ClassicGuideSurface` deliberately overlaps opaque neighbors around the
  fractional 16:9 video aperture (`_paintOverlap`). Removing that overlap or making
  the whole Guide opaque can regress native composition even if a portable
  screenshot looks cleaner.
- Program/time geometry contains fractional coordinates; the existing five-row
  rounding adjustment is not evidence that it caused the reported vertical line.

No supplied reproduction identifies which owner paints the unwanted line. Before
changing borders, capture the full redacted screen and a crop at the same commit,
with logical viewport, physical resolution, DPR/Windows scaling, text scale,
theme, selected/focused/tuned channel, time window, and horizontal/vertical scroll
position. Record the line's x coordinate, color, and extent. Compare it with the
current-time indicator, header slots, program boundaries, rail gutter, and video
aperture. Repeat with playback stopped and active to isolate native composition.

Then fix only the demonstrated owner. Validate adjacent short programs, long
programs clipped at each viewport edge, current/future windows, focus/selection,
now-playing decoration, scrolling, and fractional scaling. Keep a clear hierarchy
between ordinary program separators, focused outlines, and the current-time line.
Snap to device pixels only when measurement demonstrates a seam and the change
keeps header/cells/indicator coordinates consistent; do not blindly round every
program width independently.

Use macOS for required alpha tests and reproducible portable visual work. Use
physical Windows for the observed line and patched-engine video layering. Any
program-card design adjustment must respect `.interface-design/system.md`; an
unverified line report does not authorize redesigning the approved Guide.

### Finding 6: Now Playing addressed; broader discoverability remains open

`PlayerCoordinator.showNowPlaying()` and the Player's `I` shortcut already owned
the rich information surface. The shared menu previously offered no matching
entry. The new menu action routes to Player through `_select(4)` and invokes the
same overlay after checking that navigation succeeded and program context is
still valid. This retains the Channels/Studio route-leave guard and avoids adding
a second playback owner or a new fixed control to the protected OSD.

The information entry is contextual, separate from the Player destination, and
hidden when unusable. Focus is explicitly transferred to Player after dismissal
because same-route menu closing can otherwise restore focus to its now-hidden
OSD invoker. The authored tests cover representative route/focus/command paths;
add or run adjacent guard tests for cancelled dirty-Studio navigation, saves in
flight, rapid selection, and context becoming invalid while awaiting navigation.

**Remaining inventory:** enumerate every command in shell, Guide, Player, Mini
Guide, setup, Studio, Settings, and Diagnostics. Record command, existing visible
entry, availability predicate, keyboard accelerator, and recovery/exit path.
Known starting points include Guide search/library/jump-to-now, OSD audio/subtitle
and sleep controls, channel surfing/number entry, Mini Guide, DVR-gated transport,
Settings/Account/Diagnostics, and fullscreen. A shortcut is not automatically a
missing-button defect; determine whether an important task already has an
appropriate equivalent UI route. Conversely, a keyboard-only core surface needs
an understandable entry, not just a line in the shortcut table.

Run a first-time, pointer-only and then keyboard-only walkthrough with no shortcut
reference. Comparable-product interaction research and that walkthrough were not
performed in this connector session. Treat them as remaining evidence, not as
validation of the new menu placement. After acceptance, keep `docs/user-guide.md`
in sync with the contextual Now Playing menu path described above.

### Finding 7: reuse the native window owner; separate app and media policy

**Existing behavior is already window-level at the native layer.**
`WindowsNativePlayer::SetFullscreen` in `windows/runner/native_player.cpp` changes
the top-level window, snapshots window style/placement, chooses the nearest
monitor, removes the overlapped-window style for borderless fullscreen, and
restores the prior placement on exit. It already reports transition failures and
attempts rollback. Do not replace this with a competing native window-management
path just because the UI currently exposes it through Player.

The missing application feature is broader intent, access, persistence, and
lifecycle behavior. `PlayerView` owns the current `F`/`F11` entry; coordinator and
adapter own its asynchronous player-facing contract. Setup and idle routes also
need window control without requiring a loaded media item. Audit initialization,
stop/logout, route transitions, and shutdown before moving ownership: copying a
player fullscreen boolean into settings would create conflicting state owners.

**Implementation decisions and acceptance work:**

1. Keep one native owner for actual top-level mode and restoration. Introduce an
   application-level intent/acknowledgment seam only as needed. Distinguish the
   remembered app-window preference from a temporary media-presentation request;
   neither should silently overwrite the other during tune, stop, or sign-out.
2. Make app fullscreen discoverable in ready routes and setup/onboarding. A
   global shortcut must avoid stealing normal text editing or a modal dialog's
   input. Define Escape precedence: dismiss a dialog/overlay first, then handle
   window-mode exit according to explicit policy. Preserve a reliable visible exit.
3. Persist the chosen mode only after a confirmed transition. Define normal,
   maximized, and fullscreen restoration, safe bounds, monitor disappearance,
   DPI changes, and cold-start fallback. Window preferences should not accidentally
   become tied to a Plex profile/server's media state. Inspect the store and
   migration policy before adding fields; use normal failure/rollback tests.
4. Test actual mode versus reported mode on failed native calls, rapid toggles,
   stop/logout, initialization failure, app close while transitioning, and a
   missing native window. Existing rollback is useful evidence, not proof every
   new application lifecycle path is safe.
5. Build and run the exact commit on physical Windows with the patched-engine
   workflow. Exercise Guide, Channels, Studio, setup, Settings, dialogs, and
   Player before/during/after playback; alt-tab; minimize/maximize; two displays;
   mixed DPI; disconnect/reconnect; restart; mouse/keyboard focus; and the native
   video aperture. Preserve the originally working playback behavior.

`docs/fullscreen-hdr-spec.md` is a separate deferred HDR/presentation design.
Borderless app fullscreen does not by itself prove HDR output or authorize changing
Windows' global HDR state. Do not implement this audit item by toggling registry
settings, resetting renderer options, or treating source HDR metadata as evidence
of display output. Coordinate shared native ownership without merging two
unverified feature implementations into one patch.

Prefer Windows for implementing and iterating on the native portion, despite the
less convenient shell, because compile/transition evidence is central here.
macOS is suitable for Dart policy/store tests and design preparation; it is not
native fullscreen acceptance. Reuse repository PowerShell scripts instead of
building a new shell abstraction just for this task.

### Recommended execution order and host split

| Work package | Preferred authoring host | Required additional evidence |
| --- | --- | --- |
| Validate the two included UI fixes and new tests | macOS | Physical Windows menu/focus/review geometry at the tested commit |
| Capture collection counts, track payloads, and Guide line reproduction | Windows on the original test setup | Redacted fixtures and precise reproduction conditions |
| Collection discovery fix after reconciliation | macOS, or any host with equivalent PMS access | Same-server Windows count comparison and playback regression check |
| Track-label formatter and Studio source/model work | macOS | Windows actual tracks/playback/input acceptance; native build if bridge changes |
| Guide paint fix after reproduction | macOS for deterministic rendering/alpha tests | Patched-engine Windows playback/layering comparison |
| Application fullscreen/native transitions | Windows for native implementation; macOS optional for portable policy tests | Physical Windows multi-monitor/DPI/lifecycle matrix |

This split uses the maintainer's stated preference for macOS authoring and the
repository's evidence requirements. It is not a claim that Codex is intrinsically
more capable on one OS. Use the same branch sequentially, record the exact tested
commit on each host, and avoid concurrent edits/force-pushes to overlapping owners.

### Verification ledger and commands for the next session

**Performed here:** inspected the original commit and branch source; traced the
relevant model/UI/native owners; authored two scoped production changes and nine
widget cases; expanded this report. **Not performed here:** Dart formatting,
static analysis, any test run, golden/alpha rendering, native compilation, live
Plex reconciliation, Windows playback, or package acceptance. Test failures in
the new cases must be diagnosed and fixed rather than described as pre-existing.

At the reviewed commit, `docs/DEVELOPMENT.md` pins Flutter `3.47.4`, revision
`9584c6713b324636289d067944a46fd6b49df14b`, with Dart `3.13.3`. Use that
repository toolchain rather than a different SDK on PATH. Re-read current repo
guidance if the branch changes. On macOS, with the pinned SDK selected:

```sh
flutter pub get
dart format lib/app/lineup_shell.dart lib/app/channel_setup_view.dart test/app/desktop_native_audit_test.dart
TZ=America/New_York flutter test test/app/desktop_native_audit_test.dart
flutter analyze
dart format --output=none --set-exit-if-changed .
TZ=America/New_York flutter test
git diff --check
```

Formatting and dependency commands modify the working tree/cache; inspect their
diff and do not silently commit unrelated changes. Run the required macOS alpha
suite for Guide surface work (`test/app/guide_opacity_test.dart`), and use the
optional visual-review procedure in `docs/DEVELOPMENT.md` without automatically
accepting changed goldens. The new UI tests do not replace existing setup,
navigation, Studio, player/coordinator, or controller regression coverage.

For physical Windows, follow `docs/DEVELOPMENT.md` and
`docs/windows-native-validation.md`, including the prepared libmpv and patched
engine run/build workflow. A stock-engine compile is not proof of a runnable
Lineup composition. Windows localized schedule assertions use the OS timezone;
setting `TZ` alone is not equivalent to the canonical macOS test environment.
Record commit, toolchain/engine, display/scaling, scenario, and observed result.
Never append raw tokens, private media names, headers, or tokenized URLs.

### Copyable Codex task boundary

Continue on `dev/desktop-ui-refinement` from its current head. First read
`AGENTS.md`, relevant repository skills, `docs/DEVELOPMENT.md`, this dated
follow-up, and `.interface-design/system.md`. Validate the two included fixes
and new test file before expanding scope. Preserve the original audit
observations and append dated evidence for each investigation. Treat hypotheses
as hypotheses until a fixture or native capture proves them. Work through the
host split above; do not skip portable implementation merely because Windows
acceptance is pending, and do not claim native acceptance from macOS. Preserve
channel identity, deterministic scheduling, credential isolation, native
composition, and the originally working playback behavior. Report exact files,
commands actually run, results, remaining blockers, and tested commit hashes.

If the scoped UI patch needs rollback, use a normal revert of its follow-up
commit rather than rewriting this shared branch. Preserve this investigation
record when resolving or reverting individual changes.

**Independent review:** not automatically launched. Normal self-review plus the
listed tests/visual checks is proportionate for the included local UI changes.
Independent review is specifically recommended before accepting subsequent
series/persistence migration or application-wide native fullscreen work because
those touch saved schedules, asynchronous ownership, and native presentation.

## 2026-09-19 playlist review remediation (R1–R3)

Focused remediation of `docs/lineup-three-commit-review-and-fix-plan.md`
sections 3–5 on `dev/desktop-ui-refinement`. Reviewed head `d2b99893`;
final head `4d2470c5`, via three local conventional commits (one per
increment; nothing pushed). C1 library pagination and C3 track-label
normalization were retained unchanged. This remediation is not a collections
claim: the builder still derives collection proposals from `item.collections`
tags, and no unpushed local collection implementation was found or modified.

### Evidence boundary

Portable Dart contracts only, executed on macOS with the repository-pinned
Flutter framework revision `9584c6713b324636289d067944a46fd6b49df14b`
(Dart `3.13.3`) through a detached worktree (the checkout on PATH reported
`3.47.0`, so the pinned revision was selected explicitly rather than
silently using PATH). Full portable suite `TZ=America/New_York flutter test`
passed 887 tests; `flutter analyze` reported no issues; `git diff --check`
is clean and every changed Dart file is format-clean (the remaining format
drift is confined to gitignored `build/` capture artifacts). No live Plex
server, physical Windows session, or patched-engine rebuild was part of this
remediation, and none is claimed.

### Increments and regression evidence

- R1 `9d747a18` `fix(plex): preserve canonical playlist failure identities`
  (`lib/plex/plex_client.dart`, `test/plex/plex_transport_test.dart`,
  `test/app/lineup_controller_test.dart`). The playlist catalog now carries
  one normalized ID per row: unidentifiable rows fail the catalog with fixed
  `playlist-page-invalid` before any member request, and requests, models,
  and every `failedIds` branch reuse the canonical ID. Fail-before: 6
  unidentifiable-identity cases plus the second-page and padded-ID cases
  failed on unfixed code (empty success / `failedIds == {' p1 '}`); both
  controller cases committed a replacement inventory (`setLibraries`
  returned true). Passing-after: all new cases green, including blank-title
  per-playlist failure, padded-duplicate rejection, numeric normalization,
  and explicit-empty-catalog guards.
- R2 `f6bdae5b` `fix(plex): reject repeated playlist occurrence identities`
  (`lib/plex/plex_client.dart`, `test/plex/plex_transport_test.dart`).
  Repeated media ratingKeys (including identical blocks) stay preserved in
  order, while a repeated or malformed supplied `playlistItemID` fails that
  playlist under its canonical ID; absent occurrence identity stays
  compatible and occurrence state is scan-local per playlist. Fail-before:
  5 duplicate/invalid-occurrence cases returned success on unfixed code.
  Passing-after: all 8 new cases plus the retained no-occurrence
  repeat-preservation tests green.
- R3 `4d2470c5` `fix(plex): abort sibling loads after fatal playlist errors`
  (`lib/plex/plex_client.dart`, `test/plex/plex_transport_test.dart`,
  `test/app/lineup_controller_test.dart`). Each `playlists()` invocation owns
  one attempt-local lifetime: the first fatal authorization failure is
  recorded with its stack and aborts active sibling IO through the existing
  abortable transport, stopping subsequent pages and batches; already-started
  futures are drained and the original error reaches the existing controller
  recovery path. Fail-before: both fatal-abort cases and the first-wins and
  controller-recovery cases hung or surfaced the wrong error on unfixed code
  (10-second deadlock backstops, no sleeps). Passing-after: 401/403 abort
  with the original code, first-fatal wins, 500-among-success, fresh-retry,
  external-cancellation-still-throws, and controller recovery with refreshed
  access all green. Adversarial review caught one must-fix during R3
  (external-only `cancelled` reaching `failedIds`); fixed and locked with the
  external-cancellation regression before commit.

### Remaining acceptance

Live Plex behavior (real 401/403 timing, real `playlistItemID` values,
concurrent-edit snapshot limits) and physical Windows acceptance at the exact
tested commit are still outstanding and must follow the repository's native
validation procedure. Existing CI results predate these fixes and are not
evidence for them.

**Independent review:** not automatically launched. The per-increment
adversarial reviews above are recorded with dispositions; no separate
independent review is requested by this remediation beyond Tristan's normal
push/return-for-review flow.
