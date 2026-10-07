# Player and Guide Polish Plan (October 7, 2026)

**Status:** approved for implementation.

**Source:** `codex/desktop-ui-second-pass` at `c5fccffe`.

**Inputs:** the user's Windows observations from two screenshots (Player OSD
over dark footage, and the Guide at about 2000×1125) and the user's decisions
below. Every cause was confirmed by reading source; nothing was executed for
this plan.

**Independence:** this plan is independent of
[setup-reentry-startup-plan.md](setup-reentry-startup-plan.md). Their write
ownership is disjoint, except that both run the shared full checks, so they can
run in parallel under one orchestrator.

Read first:

- [AGENTS.md](../AGENTS.md);
- the relevant sections of [.agents/project.md](../.agents/project.md),
  especially UI changes and verification;
- [the second-pass decision log](desktop-ui-second-pass.md): F1, F2/G2, F5, F8,
  Guide, and Player;
- [.interface-design/system.md](../.interface-design/system.md).

The decisions below **supersede** the named second-pass locks where they
conflict. Record each supersession in the decision log's "Supersedes" list.

## User decisions (October 7)

| # | Decision | Supersedes |
| --- | --- | --- |
| P1 | `Up` opens the Mini Guide while the OSD is showing, as well as when no overlay is showing. It does not do so from expanded Now Playing (there, `Up`/`Down` keep their current meaning). | — |
| P2 | The Sleep picker becomes a layer **inside** the OSD presentation. See P2 below for the behavior. | — |
| G1 | Remove the half-hour lines drawn through grid rows. Keep tick marks in the time header and the now-line. Separate adjacent program cells with a slim gap or edge in the theme's subtle border role. | — |
| G2 | Scroll snaps to whole rows, so no partial row sits under the time header. The grid runs to the window's bottom edge. | — |
| G3 | **Full-bleed sides.** The Guide's grid, channel column, picture, and information area extend to the window's left and right edges, and the 20px side insets are removed. Content inside cells and panels keeps its own padding. The top bar's leading content aligns with the channel column's text inset, preserving G2's alignment intent at the new edge. | G2 "bar and grid share 20px side insets" |
| G4 | **Keep the picture-in-picture size.** Reorganize the information area to use the horizontal space beside it. See G4 below. | Guide "details sit in one 920px column … synopsis … clamped at three" |
| G5 | **Bug fixes.** The "Visible hours" dropdown's closed state shows plain text. The "Search channels" placeholder and typed text are vertically centered. | — |

| P3 | **Audio and subtitle labels.** Show the language's self-name only ("English"). Add the regional qualifier only when it is needed to tell same-language tracks of that type apart (for example, US versus UK English). In the track drawer, the region may still appear as a secondary fact. | Track-label plan: "self-named regional qualifier when the supplied tag supports one reliably" (`docs/audio-subtitle-track-label-implementation-plan.md`) |
| P4 | **Codec chip.** The Now Playing video-codec chip shows a short canonical name (HEVC, H.264, AV1, VP9, MPEG-2, VC-1…), never mpv's descriptive string. | — |
| P5 | **Cast portraits must work.** On the user's remote server, Now Playing showed no cast photos. The local server is untested; both servers are on one Plex account. Load every cast portrait through the selected server's photo transcoder at display size. See D5. | Direct-fetch-only portrait handling |
| P6 | **OSD title-logo size.** Decided from renders, not in advance. The user is concerned that smaller logos would become too small. | — |
| P7 | **OSD and Guide color pass: not in this plan.** The user will analyze and lock color decisions with Claude in a separate session, then hand them over as their own plan. Do not change colors or theme roles here, except as G1 requires for cell separation. Clear logos are never tinted. | — |

## Confirmed causes

### P1. `Up` ignored while the OSD shows

`PlayerView._key` (`lib/playback/player_view.dart:355`) opens the Mini Guide
only when `overlay == PlayerOverlay.none`.

### P2. Sleep picker blocks OSD controls and replays the OSD entrance

`PlayerOverlay.sleepTimer` is a separate `AnimatedSwitcher` child
(`player_view.dart:574`). It renders an `ExcludeFocus` copy of `_Osd`
underneath `_SleepTimerPicker`, so the real OSD is unmounted and its controls
don't respond.

On close, `closeOverlay()`/`showOsd()` switches back to the OSD presentation
key. That swaps the subtree and replays the OSD `SlideTransition` from the
bottom. The view's root `onTap` closes the picker on a video click
(`:437-445`).

### G1. Lines through rows

`guide_view.dart:1756-1771` paints a 1px `subtleBorder` line every half hour in
every row's `Stack`, behind transparent program cells. The time header also
draws a left border per slot (`:1404-1414`); keep that one.

### G2. Partial rows and bottom gap

The screenshot shows half of row 72 under the header and half of row 77 at the
bottom.

`GuideLayoutPolicy.forSize` (`:30-90`) sizes five rows plus the information
area. Investigate:

- the vertical scroll and focus-follow logic for the unsnapped offset;
- any bottom padding or chrome reserve that leaves a gap below the grid.

Keep F8's rule: extra height in 16:10 windows goes to the information area,
not the five reference rows.

### G4. Information-area height

The information area's height equals the picture's height:
`pictureHeight = min(324, …)` at the reference (`:47-57`).

Its text sits in one 920px column with the synopsis clamped at three lines.
That leaves ~400px of unused width at 1920 and cuts long synopses. Because the
user chose to keep the picture size, the area keeps its height. The goal is to
fit everything elegantly without cutting the synopsis.

### G5. Visible-hours dropdown

The `guide-hours` `DropdownButton` (`:1015-1046`) only supplies
`selectedItemBuilder` when `enlargedControls` is on. Otherwise Flutter renders
the selected `lineupMenuItems` row as the closed value, and that row is a
`LineupDropdownMenuRow(selected: true)` with a raised fill and gold bar. The
Library picker (`:911`) and `lineupDropdownField` already pass plain text.

### G5. Search text offset (likely; confirm with a render)

The field is in a `SizedBox(height: controlHeight)`: 48px at the reference
(`GuideLayoutPolicy.controlHeight`, `:99-103`). The theme's non-compact input
decoration assumes `minHeight: 56` with vertical padding 16
(`lib/ui/app_theme.dart:401-410`). The hint uses `LineupTypography.body`, but
the input uses the `bodyMedium` copy. Use the compact field metrics (F6: 44px
compact) or matched padding so the hint and text center at every supported
text scale.

### P4. Codec chip shows the long descriptive name

The Now Playing badges prefer `controller.telemetry.videoCodec`
(`player_view.dart:1376-1384`). On Windows that value is mpv's `video-codec`
property (`native_player.cpp:645`), which is descriptive, for example
`hevc (HEVC (High Efficiency Video Coding))`. The code uppercases it whole.

Use a short canonical label instead. Derive it from mpv's `video-format`
(already observed and stored as `telemetry.videoFormat`) or from Plex's
`item.videoCodec`, through one shared mapping. Check other consumers of
`telemetry.videoCodec` for the same problem. Diagnostics may keep the
descriptive value.

### P5. Cast portraits (cause not yet confirmed)

`_castMembers` (`plex_client.dart:1679`) keeps a portrait only when
`canonicalPlexCastPortrait` (`lib/channels/channel.dart:371`) accepts it:

- a PMS `/library/metadata/...` path; or
- `https://metadata-static.plex.tv/...`, which `artworkForPath` fetches
  directly (`lineup_controller.dart:1900`).

Anything else becomes `null` and shows `_CastFallback`
(`player_view.dart:1977`). The widget itself fills its circle with
`BoxFit.cover`, so "not filled" most likely means the fallback is shown.

Candidate causes:

- a thumb URL on another host, such as `image.tmdb.org`, or using `http`;
- the list-view `Role` data lacking `thumb` (the plan's live probe 7.1/7.2
  asks about Role truncation);
- a failed direct fetch from `metadata-static`.

### D5. Approved fix route for P5

The user reported missing portraits on a **remote** server. Plex chooses
portrait sources per server and library agent, so the two servers can differ.
Remote and relayed connections are also slow for full-size images: the app
fetches artwork at full resolution, capped at 4 MB, with no resizing
(`plex_client.dart:1192`).

Upstream Lineup requests sized images through PMS's `/photo/:/transcode`
(`Lineup/src/modules/plex/library/PlexLibrary.ts`, `getImageUrl`).

**Approved route.**

1. **Request.** Fetch every cast portrait as
   `GET <selected server>/photo/:/transcode?width=W&height=H&minSize=1&upscale=1&url=<thumb>`.
   - W×H is the rendered portrait size times the device pixel ratio.
   - The token goes in the header, never the URL.
   - `<thumb>` is the value Plex returned:
     - a PMS-relative path, such as `/library/metadata/…` or another PMS
       path without authority, query, or traversal;
     - an `https` URL (any host);
     - an `http` URL (any host).
2. **Server-side fetch.** PMS fetches and resizes the image. The app contacts
   only the user's own server and adds no new outbound host. Portraits become
   small, which makes them fast over remote and relayed connections.
3. **Accepted values.** Widen `canonicalPlexCastPortrait` and the persisted
   validator to accept these shapes, with:
   - no user info;
   - no fragment;
   - a length bound;
   - only `http`/`https` schemes or PMS-relative paths.

   Old builds reading new state drop unknown portraits rather than
   quarantining, because `_optionalCastPortraitUri` returns `null`. Confirm
   that with a persistence test.
4. **`metadata-static` portraits** also use the transcoder, so one path
   serves every portrait.
5. **Failure.** A transcoder failure shows the existing fallback. Record a
   bounded Diagnostics count by failure class and portrait-source class, with
   no URLs or names.
6. **Probe 7.5** in the Windows handoff is still run on both servers. It
   confirms the source classes and that the transcoder route loads them, and
   it shows whether some items lack `thumb` in list responses. If items lack
   `thumb`, report that back. The proposed follow-up is an on-demand detail
   fetch for the tuned item's cast.

**Recommended follow-up, not in this unit:** use the same sized-transcoder
path for posters, backdrops, and logos. Over a remote server, full-size
artwork is the same performance problem.

### P6. Title-logo size, current behavior

`ClearLogoImage` contains the logo in a box, then crops transparent padding
(`lib/ui/app_ui.dart:550-600`). The collapsed OSD box is 520×128 at
1080p-class sizes (`player_view.dart:941-944`), with a readability floor of
96×28 visible pixels, below which it falls back to the text title.

`BoxFit.contain` scales small source images **up**, so the source image's
resolution doesn't shrink a logo. Its aspect ratio decides the rendered size:

- **wide** logos (6:1 or more) hit the 520px width first and render about
  80–90px tall; a height cap barely affects them;
- **balanced** logos (about 3:1, like American Horror Story) hit the 128px
  height and render about 400px wide, which is the dominant case;
- **compact or tall** logos (about 1.5:1) hit 128px tall and only about 190px
  wide.

## Work units

| Unit | Executor | Writes (exclusive) |
| --- | --- | --- |
| A Player (P1, P2) | `worker_luna` | `lib/playback/player_view.dart`, `lib/playback/player_coordinator.dart` (only if the sleep-picker transition needs it), `test/playback/player_view_test.dart`, `test/playback/player_coordinator_test.dart` |
| D Player details (P3–P6), after A is integrated | `worker` | `lib/playback/player_track_label.dart`, `lib/playback/player_view.dart` (chips, cast, logo), `lib/plex/plex_client.dart` and `lib/channels/channel.dart` (portrait route), `lib/app/lineup_controller.dart` (`artworkForPath` only), related tests |
| B Guide fixes (G1, G2, G3, G5) | `worker` | `lib/guide/guide_view.dart` (grid, rows, scroll, insets, controls), `lib/ui/app_theme.dart` (only if the compact field fix belongs there), `test/guide/*`, the Guide layout tests in `test/app/*` |
| C Guide information area (G4) | `worker` | `lib/guide/guide_view.dart` (information-area builder only), related tests and captures |

- **Sequencing:**
  - A runs in parallel with B.
  - D starts after A is integrated, because both edit `player_view.dart`.
  - C starts after B is integrated, because both edit `guide_view.dart`.
- **Gates:** B, C, and D each stop at a render or evidence approval gate
  before committing.

### A. Player

1. **P1.** `Up` opens the Mini Guide from `none` and from `osd`. If keyboard
   focus is inside an OSD control, `Up` still opens the Mini Guide, because the
   OSD action row has no row above it. Update the user guide's key table if
   wording changes. The `nowPlaying` behavior is unchanged.
2. **P2.** Render the Sleep picker as a layer within the OSD presentation.
   - **Presentation:** the OSD stays mounted with the same presentation key, so
     opening and closing the picker never replays the OSD entrance.
   - **Other OSD controls:** while the picker is open, OSD controls stay
     interactive. Activating one closes the picker and performs that action.
   - **Video click:** closes the picker. The OSD stays visible, and its
     auto-hide timer restarts (keyboard-only suspension rules from D1 still
     apply).
   - **Closing:** Close, `Esc`, or a preset choice closes the picker with the
     OSD remaining. Focus is restored as today: keyboard-driven actions return
     focus to the Sleep control, and pointer-driven ones go to the Player root.
   - **Coordinator:** keep the coordinator's overlay model coherent. A
     sub-state of the OSD or an explicit flag is preferable to keeping
     `PlayerOverlay.sleepTimer` as a separate presentation.
   - **Same pattern elsewhere:** check whether the app menu opened from the OSD
     has the same unmount and replay problem. If so, fix it the same way and
     report it.
3. **Tests:**
   - `Up` from `osd` and from focused OSD controls opens the Mini Guide.
   - The picker opens and closes without the OSD presentation key changing (no
     re-entrance).
   - With the mouse: clicking Subtitles while the picker is open opens
     Subtitles.
   - A video click closes the picker and keeps the OSD visible with the timer
     restarted.
   - Keyboard focus restoration.
   - The existing sleep and D1 tests stay green.

### D. Player details (after A)

1. **P3, track labels.** Update `formatPlayerTrackDisplay`. The primary text
   is the language self-name. The region qualifier appears in the primary text
   only when another same-type track has the same language and a different
   region. Otherwise it appears as a secondary drawer fact. The OSD action
   label (`compactText`) never shows a region unless it is needed for
   disambiguation. Update the track-label plan doc's fixed decision and its
   tests:
   - an `en-US` track alone shows "English";
   - `en-US` alongside `en-GB` keeps both regions;
   - an untagged region is unchanged;
   - accessibility facts (SDH, forced) still outrank the codec.
2. **P4, codec chip.** Use one shared short-codec mapping. Test the
   descriptive mpv string, Plex `hevc`/`h264`/`av1`/`mpeg2video`, and unknown
   codecs (show a sanitized uppercase short token, never a parenthesized
   description).
3. **P5, cast portraits.** Implement D5 (steps 1–5) directly.

   Tests:
   - each portrait shape is requested only through `/photo/:/transcode` on
     the selected server, at the rendered size, with the token in a header,
     and no direct external request is made;
   - unsafe values (user info, fragment, other schemes, traversal, overlong)
     are rejected;
   - persisted portraits round-trip, and old-shape state still loads;
   - a failure shows the fallback and records the bounded count;
   - a server switch or logout cannot publish a stale portrait.

   Report probe 7.5's results from both servers when the user supplies them.
4. **P6, logo size, render-gated.** Render the collapsed OSD at 1920×1080
   and 1280×720 with three logo fixtures (wide about 6:1, balanced about 3:1,
   compact about 1.5:1). Compare these maximum heights:
   - **current:** 128px;
   - **104px:** about −19%;
   - **96px:** about −25%;
   - **optical:** the height cap scales with aspect ratio, so compact logos
     are capped near 96, balanced near 104, and wide logos keep their
     width-limited size.

   Keep the 520px width cap and the 96×28 readability fallback in every
   variant. The user picks from the renders. Implement only the chosen variant.
5. **P7: excluded.** Color decisions are made separately (see the P7
   decision row).
6. **Tests:** as listed in each item. The existing OSD layout, F5 focus, and
   sleep tests stay green.

### B. Guide fixes

1. **G1:** remove the per-row half-hour lines and add slim cell separation.
   The focused-cell fill rule (the strongest surface) is unchanged.
2. **G2:** snap rows, including focus-follow, page keys, mouse wheel, and
   scrollbar drags. Remove the bottom gap. Check 1280×720, 1920×1080,
   1920×1200, 2560×1440, and 3440×1440 at 100%, and 1080p at 150% text.
3. **G3:** apply full-bleed sides. Keep cell and panel inner padding and the
   edge fades. Align the bar's leading content with the channel column's text.
   The PiP video aperture moves to the left edge; it must stay pixel-aligned
   with the native video rectangle (F8 geometry tests at 1080p and 2160p).
4. **G5:** fix the plain-text closed state for "Visible hours". Audit every
   `DropdownButton` using `lineupMenuItems` for the same missing
   `selectedItemBuilder`. Center the search field text.
5. **Tests:** layout-policy tests for full-bleed widths and row snapping, a
   widget test for the dropdown's closed-state content, and a centering test
   comparing the hint and text vertical centers with the field center.

### C. Guide information area

Keep the picture at its current size. Design within the area's existing height
(the picture's height) using the full width beside it. Render **two candidates**
for the user to choose from:

- **C1, recommended: identity column plus synopsis column.**

  ```
  ┌──────────────────┬────────────────────────────┬────────────────────────────────────┐
  │                  │ 75 · TV Shows • Mystery    │ Ben DeSoto, a hospice caregiver    │
  │   PiP (as now)   │ AMERICAN HORROR STORY      │ with a fear of the number 13,      │
  │                  │ S13E01 · 13                │ survives a plane crash… (synopsis  │
  │                  │ 6:44–7:17 PM · 33m · 2026  │ uses the column's full height)     │
  │                  │ Drama · Mystery            │                                    │
  │                  │ [TV-MA] [4K] [EAC3] [5.1]  │                                    │
  │                  ├────────────────────────────┴────────────────────────────────────┤
  │                  │ ━━━━━━━━━━━━━━━━ progress across both columns ━━━━━━━━━━━━━━━━━ │
  └──────────────────┴─────────────────────────────────────────────────────────────────┘
  ```

  - **Identity column** (about 40% of the width beside the picture):
    - the channel eyebrow (number · name) above the title, as the user
      suggested;
    - the title or logo (logo bounded so a tall logo can't push the column);
    - the episode line;
    - the time · duration · year line;
    - the genres;
    - the chips.
  - **Synopsis column:** the remaining width. It is top-aligned with the
    title, unclamped while it fits the area's height, and ellipsized only if
    it would overflow.
  - **Progress bar:** spans both columns along the bottom.
- **C2: header band plus two columns.**
  - **Band:** a full-width top band holds the channel eyebrow on the left, and
    the airing time with time remaining on the right.
  - **Below the band:**
    - a left column with the title/logo, episode, metadata and chips;
    - a right column with the synopsis.
  - **Progress bar:** at the bottom.
  - **Trade-off:** it uses one line of height for the band, in exchange for
    clearer hierarchy.

Both candidates must:

- follow F3 typography (title widths, tabular figures) and the four themes;
- use the existing artwork, bleed, and background modes;
- survive 150% text (the synopsis ellipsizes before anything else is cut);
- handle the "Schedule unavailable", empty, and no-playback states;
- handle a missing logo (text title fallback) and a missing synopsis (identity
  column widens or centers; no empty column).

Render both at 1920×1080, 2560×1440, 3440×1440, and 1280×720, with one long and
one short synopsis and one non-default theme. Use real Flutter captures from
synthetic fixtures (`tool/design-review/capture_test.dart`). Show them to the
user and wait for a choice before implementing the final version.

## Approval gates (orchestrator stops and asks the user)

- **B:** matched before/after renders of the grid, with lines removed, rows
  snapped, bottom filled, full-bleed sides, the dropdown, and search, at
  1920×1080 and 1280×720 plus one non-default theme.
- **C:** the C1 and C2 candidate renders, then the final implementation
  renders.
- **D:**
  - the P6 logo comparison, for the user's choice;
  - before/after renders of the P3 label, the P4 chip, and P5 portraits
    loaded from a synthetic transcoder fixture.
- **Goldens:** no golden updates without approval.

## Verification

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
TZ=America/New_York flutter test
```

**Windows acceptance (add to the collaborative session):**

- `Up` from the OSD;
- the Sleep picker with the mouse (other controls, video click, Close) and
  with the keyboard;
- Guide lines, row snapping, bottom edge, and full-bleed sides with PiP video
  alignment;
- the dropdown and search;
- the chosen information-area layout with a long synopsis.

## Copy-ready Codex orchestrator prompt

```text
Use orchestrate-implementation-chats to implement docs/player-guide-polish-plan.md.
Dispatch unit A (worker_luna) and unit B (worker) in parallel; dispatch unit C
(worker) after B is accepted and integrated, and unit D (worker) after A is
accepted and integrated. Read the current
.codex/agents/worker.toml and worker-luna.toml and map model/effort onto
create_thread. Each child sends its terminal completion or blocked report back to
this orchestrator chat. I authorize creating those child chats and their callbacks
to this chat, for this task only. If docs/setup-reentry-startup-plan.md is also
being orchestrated, its file ownership is disjoint; serialize only the shared full
checks and Git integration.

Source: local checkout /Users/tristan/Software/LineupDesktop, branch
codex/desktop-ui-second-pass, base c5fccffe (or the current integrated tip if the
setup plan has landed; record it). Local execution, no worktrees. Preserve the
existing untracked files. Commit this plan file as a docs commit before dispatch.

Read AGENTS.md, the relevant .agents/project.md sections, the second-pass
decision log (F1, F2/G2, F5, F8, Guide, Player) and the whole plan. Child packets
contain the plan path, the unit section, decisions P1–P7 and G1–G5 (with the
supersessions) and D5's fix route, source identity,
write ownership, required tests, targeted commands, no commit/push, and the
callback route.

You own Git: inspect each diff, commit each accepted unit locally on
codex/desktop-ui-second-pass, run the full format/analyze/test checks on the
integrated tree. No push, PR or merge. Record the supersessions in
docs/desktop-ui-second-pass.md.

Approval gates: stop and show me B's before/after renders before committing B;
for D, show me the P6 logo comparison and wait for my choice,
show P3/P4/P5 before/after renders (P5 follows the approved transcoder route
in D5); P7 color work is excluded;
show me C's two candidates (C1, C2) and wait for my choice before C implements
the final layout, then show its final renders before committing. No golden
updates without approval. Ask me for any decision the plan doesn't settle.

After all units, run one independent read-only review of the full diff against
the plan, adjudicate, apply accepted findings, rerun the full checks, and report
units, executors, commits, checks, findings and the remaining Windows acceptance
items. Do not claim Windows behavior as verified.
```
