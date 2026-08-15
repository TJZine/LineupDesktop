# Guide PiP and Now Playing Composition Specification

Status: Approved for implementation

Issue: [TJZine/LineupDesktop#30](https://github.com/TJZine/LineupDesktop/issues/30)

Repository: `TJZine/LineupDesktop`

Branch: `replatform/flutter-native`

Investigation baseline: `430264b897cb5a6e435eb4fe9a4ee2ad41bb7aaf`

Upstream visual reference: `TJZine/Lineup` `origin/code-health` at
`f5f587c93cbea74f6c23f2df86ddae15fcb40e65`

## Purpose

Fix the non-visible real-video PiP in the default Classic Guide and materially
improve the Classic and Overlay Guide compositions. The result must preserve
the Guide as an effective schedule browser while giving active playback and
program information appropriate visual weight.

Upstream Lineup supplies structural inspiration, especially its dedicated
showcase and information hierarchy. Exact upstream dimensions are not the
Desktop policy. Lineup Desktop must adapt to resizable windows and reserve a
useful minimum number of schedule rows before allowing the showcase to grow.

## Confirmed evidence

The Classic failure is sufficiently evidenced as a Flutter compositing defect:

- Classic Guide paints an opaque full-window `Material` in
  `lib/guide/guide_view.dart`.
- `NativeVideoSurface` paints no Flutter content. It reports its global logical
  bounds and device-pixel ratio to the native player.
- The native video host is a disabled child HWND kept at the bottom of the
  Flutter view's child order. Transparent Flutter pixels reveal it; opaque
  Flutter pixels cover it.
- `WindowsNativePlayer.setVideoRect` forwards the logical rectangle and scale.
  `WindowsNativePlayer::SetVideoRect` converts it to physical pixels and calls
  `SetWindowPos(..., HWND_BOTTOM, ...)` without reloading playback.
- Guide and Player routes retain the same `PlayerCoordinator`, `NativePlayer`,
  and playback session. Entering Guide does not intentionally dispose or
  recreate those owners.
- Existing tests prove widget allocation, 16:9 aspect ratio, route transitions,
  focus, tune ownership, and mocked platform calls. They do not prove that a
  native frame is visible through Flutter.

The expected root fix is therefore a genuine transparent aperture in the
Classic Flutter composition at the exact PiP bounds. The rest of the Guide
must remain deliberately Flutter-painted and opaque. Physical Windows proof is
still required to confirm the complete native presentation path.

## Product hierarchy

When the Guide is open, priorities are:

1. Schedule browsing and clearly visible focus.
2. Continued awareness of playing video.
3. Focused-program information.
4. Secondary metadata.

The Guide is primarily a schedule browser. A composition that leaves only
three schedule rows at 720p gives the showcase too much vertical authority.
The current tiny PiP has the opposite problem and makes playback continuity
nearly meaningless.

Focused, selected, tuned, and currently airing identities must remain distinct:

- Focus changes the program information being inspected.
- Selection remains an explicit program identity.
- Tuned/Now Playing remains stable while focus moves.
- Currently airing remains clock-derived and does not imply tune or selection.

## Resolved responsive policy

The layout must use a row-budgeted adaptive policy. Reserve the minimum schedule
height first, then size the Classic showcase and PiP from the remaining height,
subject to sensible minimum and maximum dimensions. Use actual logical layout
constraints rather than assuming that a nominal 720p window has exactly 720
logical client pixels.

Minimum fully visible schedule rows:

| Logical viewport height | Minimum rows | Intended presentation |
| --- | ---: | --- |
| 600-719 px | 4 | Compact rows and compact showcase |
| 720-899 px | 5 | Compact rows and medium PiP |
| 900-1079 px | 5 | Comfortable rows and full information hierarchy |
| 1080 px and above | 7 | Comfortable rows and upstream-scale showcase |

A clipped partial row does not satisfy the minimum.

Target Classic PiP guidance, not duplicated constants:

- Around 720p: approximately `500 x 281` logical pixels.
- Around 600p: approximately `420 x 236` logical pixels.
- At sufficiently large heights: grow toward an upstream-shaped
  `640-672 x 360-378` logical-pixel region.
- Preserve 16:9 throughout.

These targets may move modestly when real text metrics, focus borders, SafeArea,
or exact row geometry require it. The row contract and visual hierarchy outrank
literal target numbers.

Do not add a user-adjustable split, collapsible showcase, floating PiP, or new
persisted setting. The existing Guide density setting remains authoritative,
but the layout may select the compact presentation necessary to honor the
low-height contract. Do not make text unreadably small to retain metadata.

## Progressive information disclosure

As height decreases, simplify information in this order:

1. Remove or clamp description text.
2. Remove secondary metadata and playback diagnostics.
3. Reduce poster or artwork size.
4. Tighten spacing and modestly reduce title scale.
5. Preserve channel identity, program title, time/status, and tuned identity.

Do not uniformly scale the whole composition. Essential text and focus
indicators must remain legible and accessible.

Use only facts already available through current Dart models and controllers.
Do not expand Plex models or fabricate descriptions, ratings, genres, badges,
logos, or quality claims solely to fill the new space.

## Classic Guide requirements

- Real native video must be visible inside one Flutter-owned 16:9 aperture.
- Only the PiP aperture should reveal the native child. Surrounding Guide
  background, toolbar, information, time header, grid, gutters, and focus
  treatment remain Flutter-painted.
- The aperture geometry and `PlayerSurface` geometry must have one owner and
  cannot drift apart.
- Rounded-corner treatment may be achieved by Flutter masking above the
  rectangular native child. Do not require native window-shape ownership.
- PiP geometry changes must not restart, stop, or reload playback.
- The showcase places PiP beside a materially stronger information hierarchy.
- Tuned/Now Playing identity stays visible while focused-program details change
  during Guide navigation.
- At low heights, preserve the row contract by progressively compressing the
  showcase and its nonessential information.
- Opening PiP returns to the existing full Player route and restores Player
  focus through the existing route owner.

## Overlay Guide requirements

- Retain the same real video beneath Flutter; do not create a second player or
  PiP surface.
- Give poster/artwork and program information substantially more visual weight
  than the current `112 x 86` artwork treatment.
- Use the same information-priority rules as Classic, with Overlay-specific
  constraints rather than identical geometry.
- At large heights, provide an upstream-informed poster and full information
  composition.
- At 720p, retain a medium poster, program title, channel, timing/status, and
  concise metadata while preserving at least five schedule rows.
- Around 600p, retain essential poster/Now Playing context while preserving at
  least four schedule rows.
- Maintain sufficient scrim and opaque panel coverage for text and focus
  legibility without unnecessarily hiding the playing video.

## Ownership and implementation boundaries

Flutter/Dart remains authoritative for:

- Guide layout and responsive policy;
- the transparent PiP aperture;
- Now Playing and focused-program presentation;
- poster/artwork presentation;
- navigation, focus, input, semantics, and overlays; and
- route transitions and tune policy.

C++ remains authoritative only for:

- the existing native video child;
- libmpv and media lifetime;
- DirectComposition/native presentation; and
- applying the physical video rectangle.

Retain exactly:

- one native player;
- one `PlayerCoordinator`;
- one Guide layout owner; and
- one native video geometry contract.

Do not add Electron compatibility, another player, another PiP owner, helper
processes, WebViews, C#, retries, delays, polling, decoder reloads, speculative
interfaces, or a new state-management system.

## Expected source scope

Primary implementation owner:

- `lib/guide/guide_view.dart`

Inspect and change only if evidence requires it:

- `lib/app/lineup_shell.dart`
- `lib/playback/player_view.dart`
- `lib/playback/native_video_surface.dart`

Native files should remain unchanged unless physical evidence disproves the
confirmed Flutter occlusion diagnosis:

- `lib/playback/windows_native_player.dart`
- `windows/runner/native_player.cpp`
- `windows/runner/native_player.h`
- `tool/flutter_engine/0001-windows-direct-composition.patch`

Likely regression coverage:

- `test/guide/guide_view_test.dart`
- `test/app/lineup_app_test.dart`
- `test/app/ui_acceptance_golden_test.dart`
- the smallest relevant golden baselines under `test/app/goldens/`

Avoid tests that merely duplicate layout constants. Protect the row-budget
behavior, 16:9 geometry, identity distinction, bounded row construction, and
route/player ownership. Goldens protect stable composition, not native-video
visibility.

## Implementation sequence

1. Reconfirm the current clean baseline and trace the complete geometry call
   path before editing.
2. Make the Classic PiP aperture genuinely transparent without changing native
   playback ownership or reload behavior.
3. Replace fixed showcase sizing with the agreed row-budgeted responsive policy.
4. Strengthen Classic information hierarchy using current data.
5. Strengthen Overlay poster/information composition using the same priority
   rules and mode-specific constraints.
6. Update the smallest stable widget/layout coverage and adjudicated goldens.
7. Run focused tests, full format/analyze/test verification, and inspect the
   final diff for duplicate ownership or unnecessary abstractions.
8. Build and physically validate the Windows application with real Plex video.

Do not declare the functional PiP defect fixed before step 8 succeeds.

## Deterministic verification

At minimum, verify logical layouts at:

- `800 x 600`;
- `1280 x 720`;
- `1360 x 840`;
- `1600 x 900`;
- `1920 x 1080`; and
- existing 4K and 200-percent-DPI regimes.

Verify:

- required fully visible row counts;
- 16:9 Classic PiP geometry;
- no overflow or clipped essential information;
- focused, selected, tuned, and airing identities remain distinct;
- tuned/Now Playing information remains stable while focus moves;
- compact metadata disappears in the agreed priority order;
- overlay poster and information hierarchy remain legible;
- route focus restoration remains correct;
- the 1,000-channel Guide retains bounded lazy work; and
- geometry-only changes do not invoke media load, stop, or player recreation.

Expected commands include:

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Run narrower focused suites during development before the full verification.

## Physical Windows acceptance

Use the pinned Flutter engine and packaged/runtime requirements documented in
`docs/DEVELOPMENT.md` and `docs/windows-runtime.md`.

Required proof:

- Real Plex video visibly occupies the Classic Guide PiP bounds.
- Flutter content remains above video and retains keyboard, pointer, focus, and
  accessibility ownership.
- Overlay Guide retains real video beneath Flutter.
- Full Player -> Classic Guide PiP -> replacement tune -> full Player succeeds.
- Replacement tune has no stale audio, duplicate playback, persistent black
  frame, focus theft, or second player.
- Resizing across the required viewports updates native geometry correctly.
- DPI conversion is correct in existing 4K/high-DPI regimes.
- Geometry changes do not recreate the decoder or reload playback.
- Minimize/maximize and fullscreen transitions do not leave stale bounds or a
  hidden/incorrectly stacked native child.

If physical validation fails, record whether audio continues, the actual native
rectangle, DPI scale, HWND visibility, stacking, clipping, and Flutter opacity
at the intended aperture before changing architecture.

## Acceptance criteria

- [ ] Classic Guide presents visible real video in its Flutter-owned PiP bounds.
- [ ] Classic PiP is materially larger than the current implementation while
      honoring the minimum schedule-row contract.
- [ ] Classic Now Playing and focused-program information have clear hierarchy
      and adequate space.
- [ ] Overlay poster and program information are materially stronger while
      honoring the same row contract.
- [ ] Five fully visible schedule rows are retained at 720-899 logical pixels.
- [ ] Four fully visible schedule rows are retained at 600-719 logical pixels.
- [ ] Five comfortable rows are retained at 900-1079 logical pixels.
- [ ] Seven comfortable rows are retained at 1080 logical pixels and above.
- [ ] Focused, selected, tuned, and currently airing identities remain distinct.
- [ ] The 1,000-channel Guide remains bounded and responsive.
- [ ] Player/Guide transitions and replacement tuning preserve one playback
      owner and do not reload solely for geometry changes.
- [ ] Deterministic tests and goldens pass, with no claim that they prove native
      composition.
- [ ] Physical Windows acceptance passes with real Plex playback.

## Non-goals

- HDR output or tone-mapping validation.
- Audio passthrough or output-device work.
- Physical gamepad acceptance beyond avoiding regressions.
- New Plex metadata fields or background data fetches.
- A redesigned schedule engine, horizontal scrolling model, or Guide controller.
- User-configurable PiP size or showcase collapse behavior.
- Native rounded-window or clipping ownership.

## New-session handoff

Work from the repository root on branch `replatform/flutter-native`. The
investigation baseline was clean and pushed at
`430264b897cb5a6e435eb4fe9a4ee2ad41bb7aaf`; fetch and fast-forward before
starting, then report the actual HEAD and worktree state.

Before implementation, compare the current HEAD with that baseline. If the
referenced sources, ownership boundaries, dependencies, or documentation have
materially changed since the baseline, stop and update or re-review this
specification before using its diagnosis or implementation instructions.
Preserve the implementation scope and non-goals unless that freshness review
explicitly revises them.

Read `AGENTS.md`, `docs/DEVELOPMENT.md`, `docs/architecture.md`,
`docs/ui-parity.md`, this specification, and GitHub issue #30 before editing.
Inspect the exact upstream reference `TJZine/Lineup` `origin/code-health` at
`f5f587c93cbea74f6c23f2df86ddae15fcb40e65`, especially its EPG shell,
Classic showcase, info panel, poster, and Overlay composition. Treat upstream
as structural inspiration rather than a fixed Desktop coordinate system.

Implement the specification above using the existing Flutter Guide owner. The
functional diagnosis is that Classic's opaque full-surface Flutter `Material`
covers the correctly bottom-stacked native video child. Create a genuine
transparent aperture at the single PiP geometry while keeping all other Guide
regions deliberately Flutter-painted. Keep the existing native player,
`PlayerCoordinator`, `PlayerSurface`, logical-to-physical rectangle contract,
child HWND, and DirectComposition architecture. Do not change C++ unless fresh
physical evidence disproves the Flutter occlusion diagnosis.

Use a row-budgeted responsive layout, not fixed upstream dimensions. Preserve
at least five fully visible rows at 720-899 logical pixels and four at 600-719;
use comfortable five-row and seven-row targets at 900 and 1080 respectively.
Grow Classic PiP toward `640-672 x 360-378` only after the row budget is met.
Around 720p, expect roughly `500 x 281`; around 600p, roughly `420 x 236`.
Apply progressive disclosure to metadata rather than shrinking essential text.

Strengthen Classic and Overlay hierarchy using only existing Dart facts. Keep
tuned/Now Playing context stable while focused-program details follow Guide
focus. Overlay must retain real video beneath Flutter and gain a stronger
poster/information composition without sacrificing its row budget.

Add only the smallest stable regression coverage. Widget and golden tests may
protect structure, rows, focus identities, and geometry, but cannot prove
native video. Complete the required real-Plex Windows matrix before declaring
the issue fixed. Do not use retries, delays, polling, reloads, another player,
another PiP/layout owner, WebViews, helper processes, or speculative
abstractions.

At closeout, report changed files, deterministic results, physical Windows
evidence, remaining limitations, and whether independent review is specifically
recommended. Independent review is specifically recommended for the completed
change because it alters Windows native-video visibility and presentation
behavior even if the final source change remains Flutter-only. Do not launch
that review automatically; it is user-controlled.
