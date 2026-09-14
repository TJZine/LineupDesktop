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
