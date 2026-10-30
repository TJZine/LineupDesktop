# Subtitle settings UI: decisions record (APPROVED October 29, 2026)

- **Status:** drafted by Claude (UI/UX owner) and **approved by the maintainer on October 29, 2026** with the answer "Approve as drafted" to "Approve the draft as recommended?". The approval covers every item's **Recommended** choice, UI-1 through UI-12. That includes the separate protected-Player change UI-9 (SD-17) and the scoped golden/render update in UI-12. The rendered alternatives are not approved.
- **Amended October 29, 2026** after a read-only adversarial review by Codex (`review/report.md`, findings R-1 to R-7). The maintainer decided its three open questions: clip the top when a cue cannot fit above the panel; fall back to A and shrink only the preview crop when A2 is too narrow or text is very large; Reset keeps device mode. The amended text below is authoritative. The pre-amendment copy is `review/subtitle-ui-decisions.before-amendment.md`; see "Amendments" at the end.
- **Source:** integration `0a10575601a390a202d3a7c0d007d95daf161042` (D1, N1, N2, F1 integrated; landed mobile foundation `ab6afd55` included). Specimen worktree `ui/specimen/` (detached, uncommitted edits only).
- **Brief:** `docs/handoffs/subtitle-style-plan.md` §8, contracts §§6–7. Maintainer decisions already in force: SD-3 maximum, SD-4 Standard/no box, all SD defaults, device size applies to all formats when device settings are on, SD-9 out of v1.
- **Handheld viewport:** no approved mobile UI-A record exists in the pinned tree, so handheld uses the §8 fallback 412×915 dp. Replace this if a mobile record is approved first.
- **Limits:** these are widget captures from the real Flutter Settings, `SubtitleStyle`, `SubtitleLayer` and Player widgets in flutter_test. They prove layout and look, not runtime behavior. V1 and the physical pass remain separate.

## How to read the evidence

All paths are under `/Users/tristan/Software/lineup-subtitles-work/ui/`.

| What | Where |
| --- | --- |
| Options A, A2, B, C per viewport (rows: options; columns: top, first focus, scrolled focus, bottom) | `sheets/options-<config>.png` (9 configs) |
| Full-resolution captures | `captures/<config>/option-<A\|A2\|B\|C>--*.png` |
| Configs | `tv-960x540@2-text{1.0,1.15,1.3}[-large]`, `desktop-1920x1080`, `desktop-1280x720`, `handheld-412x915@2` |
| TV text scale × Large Focus | `sheets/tv-option-{A,A2,B}-textscales.png` |
| States (Classic box, Custom, Android device style on) | `sheets/tv-states.png`; `captures/<config>/states--*.png` |
| Open menus (Size 7, Text color 8, Font 7) | `sheets/tv-menus.png`; `captures/<config>/states--menu-*.png` |
| Four themes | `sheets/desktop-themes.png`; `captures/{desktop-*,tv-960x540@2-text1.0,handheld-*}/themes--*.png` |
| Look matrix (1920×1080 frames, real `SubtitleLayer`) | `sheets/look-{presets,edges,fonts,fonts-bold,boxes,sizes,positions}.png`; `captures/look/*.png` |
| Metric alternatives | `sheets/metric-{outline,outline-p50,shadow,inset}.png` |
| SD-17 (no cue / in place / moved) | `sheets/sd17-{osd,np}-{1920x1080,1280x720}.png`; `captures/desktop-*/sd17--*.png` |
| Existing golden effect | `sheets/golden-settings-before-after.png`; `evidence-golden-failures-specimen/` (with specimen); `evidence-golden-failures-clean/` (pinned commit, no specimen) |
| Harness | `specimen/tool/design-review/subtitle_gate_test.dart` (untracked copy of `capture_test.dart`), assembled from `harness/{head,body,tail}.dart` by `harness/assemble.py` |

Reproduce: from `ui/specimen`, with the pinned Flutter on PATH, run `TZ=America/New_York [LOOK=1] [SCENES=…] [CONFIGS=…] flutter test tool/design-review/subtitle_gate_test.dart`.

## Items

Each item: **Recommended** (what I ask you to approve), then the alternatives rendered.

### UI-1. Where the controls live (SD-8)

- **Recommended: a new Subtitles category in Settings, between Playback and Accessibility.**
  - **Which layout applies (amended, R-2):**
    - The Settings shell is compact when `LineupLayout.isCompactWidth(constraints.maxWidth)` **or** `MediaQuery.textScalerOf(context).scale(1) >= 2`, evaluated inside `LineupCanvas`. The 900 threshold is in **canvas units**, not physical pixels: desktop scales the canvas by at least 0.8.
    - **Compact Settings uses A:** a full-width preview band pinned above the rows.
    - **Non-compact Settings uses A2,** rows on the left and an actual-size preview pinned on the right, **only when the rows column (0.54 × detail width − 32) is at least 560 canvas units.** In practice that means a detail width of about 1,096 or more: TV and desktop at 1280×720 and above.
    - **Otherwise, non-compact Settings uses A** inside the same shell. This fallback was approved by the maintainer on October 29; it does not adopt B or change any other Settings category.
  - Row labels and helpers may grow vertically; 72 is a minimum, not a fixed height. Selected dropdown values must always be fully legible.
- **Why A2 on wide layouts:**
  - At 1080 canvas height it shows about 7 rows on TV and desktop. The plain band (A) shows 3, and only 2 at 1280×720 (`sheets/options-desktop-1280x720.png`).
  - Its tall preview shows every Position, and every size up to 300%, at their true height.
  - It keeps the existing Settings shell, rail, Back behavior and traversal.
- **A2's limitation (disclosed):** the preview is a crop about 46% of the pane wide. Lines wrap at that width, so a long line wraps in the preview earlier than it would full screen. In the reference configurations the short sample lines wrap only at 300%; near the A2 boundary they can wrap at smaller sizes. The em scale and the bottom and Position distances are always exact, because they come from the reference frame height.
- **Alternatives rendered:**
  - **A (band above rows) everywhere:** faithful line width, but too few rows on TV and desktop.
  - **B (full-screen page, rows in a 40% sheet over a full-bleed frame):**
    - The most faithful preview, and the most rows (about 9).
    - But it is a new page pattern that leaves the Settings shell, Back has to return to the rail, and the sheet's minimum width overflows on handheld (`sheets/options-handheld-412x915@2.png`).
    - The strongest alternative for TV only.
  - **C (rows inside Playback):** the preview scrolls away and is a thumbnail, not actual size. Not recommended.
  - **Two- and three-up grids (plan sketch):** not rendered. Left/Right inside a row conflicts with Left returning to the rail on TV, and halves narrower than 900 force every row to reflow on desktop.

### UI-2. Preview

- **Recommended:**
  - **Source:** `SubtitleLayer` with the sample cue "Look out!" / "[Door creaks]" (align 2).
  - **Frame:** laid out against the real full-screen video height, so text is drawn at actual size. Frame height = the shorter side of the window in canvas units; handheld therefore uses landscape, the way people watch. The layout ignores the app `TextScaler`, as confirmed across text scales 1.0, 1.15 and 1.3.
  - **Wide (A2):**
    - column width 46% of the detail width, 32 gap from the rows;
    - height = min(available height − 24, 0.72 × frame height), top-aligned;
    - the cue sits at its true distance from the frame bottom.
  - **Compact (A):** full detail width, height 0.36 × frame height, bottom-anchored. At large sizes or positions the top line clips, which honestly says "this is big".
  - **Scene:** synthetic, no asset.
    - A horizontal gradient so one line crosses both a bright and a dark picture: `#F1EADB` → `#C9BFA8` at .38 → `#4A4136` at .62 → `#0C0B09`.
    - Overlaid by a vertical gradient from 0% to 20% black.
    - The plan's vertical sky-to-ground gradient would put the whole cue on dark ground.
  - **Frame chrome:** 1 px `subtleBorder`, 8 px radius (the panel radius).
  - **Never focusable.**
  - **Height bounds and adaptive crop (amended, R-2):**
    - Let F = min(window canvas width, window canvas height), and A = the detail body's available height below the Subtitles heading, helper and their gaps.
    - The requested preview height is min(max(0, A − 24), 0.72F) for A2, and 0.36F for A. Both are bounded by A.
    - At short heights or large text, **shrink only the preview's visible crop** until one complete focused row fits in the scroll viewport, including its focus frame and any save feedback.
    - Never reduce the `SubtitleLayer` reference-frame height or the subtitle em size to make room.
    - This was approved by the maintainer on October 29. U1 adds matched captures at the A2/A boundary and at text scale 2.
  - **Conditional heading scroll (maintainer-approved amendment, October 29, 2026):**
    - Only when the focused row, its save feedback and focus clearance still cannot fit after the preview crop and its adjoining gap reach zero, the Subtitles heading and helper join the detail scroll content, as shown in `ui/adaptive-feedback/compare-saving.png` and `compare-error.png`.
    - The global Settings header, rail, typography, controls and rows remain unchanged. Every normal fitting layout must render pixel-identically.
    - Entering or leaving this exception must keep the focused control fully visible and focused. The layout must not oscillate as Saving or error feedback appears and disappears on the same row.
    - U1 must test both transition focus/visibility and same-row feedback stability. The `SubtitleLayer` reference-frame height and subtitle em size remain unchanged.
  - **What it shows (amended, R-3):**
    - **The displayed Settings value,** including accepted selections whose save is still pending, like every other Settings row. Highlighting an option in an open menu never changes it.
    - Back cancels only the open menu. A failed save restores the committed value and recomposes the other pending changes, matching the rows.
    - **Device mode:**
      - Resolve the shared source's latest valid device snapshot (`SubtitleAppearanceSource.deviceCaptions`) against the displayed Lineup style, so pending Position and Bold changes show immediately.
      - Before any snapshot exists, show the displayed Lineup style as a temporary fallback.
      - After a failed refresh, keep the latest valid snapshot; with none, keep the Lineup fallback.
      - The "captions are off there" helper appears only when a valid snapshot reports `enabled == false`.
    - **U1 must not:** create another device client or subscription; publish preview-only choices to the shared playback source; or send native changes before a commit. The production source keeps owning device reads on the committed toggle's lifecycle.
- **U1 wiring note:** Settings currently receives only `LineupController`. The specimen passes `PlayerCoordinator.subtitleAppearance` into `SettingsView` from `lineup_shell.dart`, the one shared source per F1's contract. U1 should do the same rather than create a second source.

### UI-3. Rows, grouping and order

- **Recommended: one control per line in a compact row**, a new row density for this page only.
  - **Row:** minimum height 72; vertical padding 12; horizontal padding 16 on TV (0 elsewhere); bottom border `subtleBorder`; gap 24 between label and control.
  - **Label:** `LineupTypography.control` in `primaryText` (`mutedText` when disabled).
  - **Optional helper:** used only on the two toggles. 16/1.4 `LineupTypography.body`, `secondaryText`.
  - **Dropdown width:** min(280, 55% of the row).
  - **Switch control:** its own 56-wide box. The specimen used 55%, which needlessly squeezes switch labels on handheld; U1 should use 56.
  - **Why not the existing 132-tall rows with helper text:** at 15 controls they would show about 2 rows on TV.
- **Group labels:** uppercase `LineupTypography.small`, letter spacing 1.2, `mutedText`; padding 24 above and 8 below (TV adds 16 left); exposed as headers in semantics.
- **Order:**
  1. Use device subtitle settings (Android only, per E5).
  2. Style.
  3. Size.
  4. Position.
  5. TEXT: Color, Opacity, Font, Bold.
  6. EDGES: Style, Color.
  7. BACKGROUND (BEHIND EACH LINE): Opacity, Color.
  8. WINDOW (ONE BOX BEHIND THE CAPTION): Opacity, Color.
  9. STYLED SUBTITLES: Apply my style to styled subtitles.
  10. Reset to standard.
- **Opacity before Color** in Background and Window, so the enabling control comes first. The plan's sketch had Color first.
- **Semantics:** names carry the group, for example "Text Color" and "Edge Style"; the specimen's field keys follow this.
- **Category description:** the plan's helper copy, "Applies to text subtitles. Image subtitles follow Size and Position only."

### UI-4. Menus

- **Recommended:**
  - the existing `lineupDropdownField` menus;
  - **the Font menu draws each name in its own typeface** (`states--menu-font.png`);
  - **the Style menu** lists the 5 presets. When no preset matches, "Custom" is the shown value and a disabled last item, never an action (§4a).
  - **Custom focus exception (amended, R-5):**
    - For ordinary values, opening a menu focuses its current value.
    - For Style = Custom, Custom stays the displayed, disabled status item and cannot take focus. Opening the menu focuses **Standard**, the first enabled preset; that initial focus changes neither the style nor the preview.
    - Back keeps Custom and returns focus to the trigger; Select applies the focused preset.
    - Verify this with the remote keys.
- **Live preview while a menu is open (optional §7.1 item): recommend not in v1.** The preview shows the displayed value (UI-2), never the highlighted option. The open menus do not cover the preview cue in A or A2 (`sheets/tv-menus.png`), so it is feasible later. It needs a focus hook in the shared `lineup_controls.dart` under the TV non-regression rule, and Select-then-look is one press to undo. Record it as a follow-up.

### UI-5. Disabled states

- **Recommended:**
  - **Device style on:** disables Style, Size, Text color, Text opacity, Font, Edge style, Edge color, Background and Window.
    - Size is included per your device-size approval.
    - Position, Bold, the styled toggle and Reset (subject to its own rule below) stay enabled.
  - **Background color** is disabled while Background opacity is Off; **Window color** while Window opacity is Off. Both are disabled by default.
  - **New: Edge color is disabled while Edge style is None** (`states--classic-box.png`).
  - **Reset (amended, R-4; maintainer decided October 29: keep device mode):**
    - Reset restores every saved Lineup subtitle field to Standard **except `useDeviceStyle`, which it preserves.** This supersedes §7.1's "restores every field" for that one flag.
    - It is disabled when every field other than `useDeviceStyle` already equals its default; device mode alone never enables it.
    - It is one queued settings transformation, evaluated against committed state, with its own `_SettingKey` and the normal feedback.
    - It composes with other pending controls in action order: changes queued before Reset are reset, and changes queued after it remain.
    - It never captures and rewrites an old complete settings snapshot.
  - Disabled rows use the existing disabled field look plus a `mutedText` label. Traversal skips them; semantics still announces them (§7.2).

### UI-6. Android device toggle copy (SD-7)

- **Recommended:**
  - **Normally:** "Uses the caption style from Android settings. Position and Bold stay here."
  - **When the system captions switch is off:** "Uses the style from Android settings. Captions are off there; Lineup uses their style anyway."
- **Evidence:** `states--device-on*.png`, using a mocked device style of yellow serif text at 150% on 60% black.

### UI-7. Styled-subtitles toggle copy (SD-5)

- **Recommended:** "Apply my style to styled subtitles", with the helper "ASS/SSA dialogue uses your style. Signs and author positioning are dropped."

### UI-8. Look metrics (§6.4; F2 applies them)

**Recommended, with the provisional value each replaces:**

| Metric | Recommended | Provisional | Evidence |
| --- | --- | --- | --- |
| Outline stroke | **0.10 em** (about 2.9 px visible outside the glyph at 1080) | 0.06 em: half the stroke is hidden under the fill, so only about 1.7 px shows and it is weak on bright scenes | `sheets/metric-outline*.png` |
| Drop shadow | **offset 0.06 em, blur 0.06 em** | 0.05 / 0.025 | `sheets/metric-shadow.png` |
| Raised / depressed | 0.03 em (unchanged) | same | `sheets/look-edges.png` |
| Background horizontal inset | **0.2 em** | 0.1 em: the box hugs the first and last glyphs | `sheets/metric-inset.png` |
| Window padding | 0.25 em (unchanged) | same | `sheets/look-boxes.png` |
| Bottom margin | 0.06 × height (unchanged) | same | `sheets/look-positions.png` |
| Line height / wrap width | 1.2 em / 90% (unchanged) | same | `sheets/look-sizes.png` |
| Position raise | .05 / .10 / .15 of height (unchanged) | same | `sheets/look-positions.png` |
| Fonts | the seven bundled OFL families as rendered | same | `sheets/look-fonts*.png` |

The outline is the only legibility device in the no-box default (SD-4), so it is the most consequential number here. The 0.14 em alternative reads as heavy.

### UI-9. Subtitles and the Player controls (SD-17; protected Player)

- **Recommended: move Lineup-drawn cues above the OSD and above Now Playing while either is visible,** and return them when it hides.
- **Scope (amended, R-1):**
  - Applies only to **bottom-aligned** Lineup-drawn cues (align 1–3) in the full Player.
  - Applies while an OSD or Now Playing bottom panel is displayed, **including a retiring panel during its transition.**
  - Top and middle cues, engine-drawn subtitles, and Guide/PiP surfaces keep normal placement.
  - Move each eligible cue individually. **Never translate the whole mixed-alignment layer,** and never leak a lift into other `PlayerSurface` consumers.
- **Geometry (amended, R-1):**
  - Compute normal cue placement first, including the user's Position.
  - Work in the `SubtitleLayer`'s presentation-rectangle coordinates:
    - H = the layer's current height;
    - F = the highest material-paint top among eligible visible and retiring panels;
    - B = the bottom of the cue's rendered block, including visible Background, Window and edge outsets.
  - Lift the cue by max(0, B − (F − 0.02H)). A cue that already clears the panel, such as one at Highest, stays put.
  - F includes the material painter's **55 canvas-unit feather**, mapped through the same coordinate transform. The specimen's 0.047H was a measurement, not a production constant.
  - Derive F from the actual current panel geometry, including DVR controls, action wrapping, Up Next and safe-area changes.
- **Timing (amended, R-1):**
  - Drive avoidance from the same presentation lifecycle and progress as the panel, including expansion and collapse, and outgoing panels.
  - Release clearance when the outgoing panel finishes hiding. Reduce Motion settles immediately.
  - A cue arriving during a transition uses the current avoidance state.
  - Cue changes stay local to `SubtitleLayer` and must not trigger general Player rebuilds.
  - Track drawers, the sleep picker, the mini-guide and the channel bug get no avoidance rule of their own; a still-visible bottom panel keeps counting.
- **No room (maintainer decided October 29: clip the top):** if a cue cannot fit above the panel at its selected size, clearance wins. Keep its bottom above F − 0.02H and clip its top at the presentation rectangle. Never shrink the text.
- **Protected baseline:** the OSD, Now Playing, the channel bug and every control and overlay keep their exact geometry; only eligible cues move.
- **F2 verification:** render the no-room case and the dynamic states — DVR controls, expansion and collapse, a retiring panel, Reduce Motion, mixed alignments, a large cue — at 1280×720 and 1920×1080, plus the TV OSD. The existing sheets only establish the approved direction and the settled reference states.
- **Why:** left in place, the cue sits under the OSD scrim and collides with the action labels; it is unreadable (`sheets/sd17-osd-*.png`, middle frame).
- **Alternative: leave cues in place.** No Player change, but they are unreadable under the OSD.
- **Evidence:** matched content, clock, paused state and focus at 1280×720 and 1920×1080, as no cue / in place / moved. Under Now Playing the moved cue sits in the upper half (`sheets/sd17-np-*.png`), as Apple TV does.
- **Separate approval needed:** this needs its own approval under the protected-Player rule; please mark it separately from UI-1 to UI-8.

### UI-10. Settings background (gate confirmation from §6.4)

- **Recommended: confirm `PlayerSurface(showSubtitles: false)` behind Settings,** as integrated. Live cues never show faintly through the 0.94 scrim, and the preview is the only subtitle on the page.

### UI-11. TV remote interaction (§7.2, normative once approved)

- **Recommended:**
  - Rail → Right enters the first row: the device toggle on Android, otherwise Style.
  - Up/Down move through one column; Left returns to the rail at Subtitles.
  - Select opens a menu on the current value; Select commits and returns to the row, which stays enabled during its own save; Back cancels.
  - The preview is never a focus stop. Disabled rows are skipped.
  - Focus fills and Large Focus follow the existing TV treatment, as rendered at text scales 1.0/1.15/1.3 with Large Focus on and off.

### UI-12. Scoped golden and render approval (for U1)

- **Committed goldens:** the desktop suites were run against the specimen without `--update-goldens`.
  - Exactly one changes: **`tool/visual/goldens/settings-appearance-ember-steel-1920x1080.png`**.
  - It differs by 0.13% (2,764 px), inside the box x 64–174, y 450–666: the new "Subtitles" rail row, with Accessibility, Account and Support moving down one row. Nothing else changes.
  - `guide-rich`, `guide-reference-free`, `player-osd` and `player-now-playing` are unaffected (with the specimen, which includes the SD-17 hook at zero lift).
  - **Requested:** approval to update exactly that one golden in U1's separate commit.
- **TV matched renders:** every TV Settings render that shows the rail gets the same rail-only difference. U1 must list each by name against base, with a rail-only diff box, and every other TV render must stay identical.
- **The affected TV Settings renders** (from `tool/design-review/capture_test.dart`), under each required matched TV configuration:
  - `settings--{appearance,player-overlays-menu,guide,visible-hours-menu,playback,accessibility,account,support}`;
  - `settings-over-playback--appearance`;
  - `theme-{ember-steel,slate-pine,swiss,directv}--settings`.
  - The rail-only allowance applies to exactly these surfaces. The new Subtitles scenes have no baseline.
- **Untracked design-review captures:** the same scenes on desktop change the same way. No golden approval is needed because they are not committed, but untracked status approves no other change.
- **Provisional versus final metrics (R-6):**
  - The look matrix, Settings pages and SD-17 sheets were rendered with the **provisional** metrics, except the individually named metric alternatives. UI-8's table is the approved final combination, and F2 renders that combination.
  - For matched U1/F2 comparisons against the specimens, the only allowed differences are: the resulting subtitle-paint changes; UI-3's 56-wide switch allocation; and the approved adaptive-crop and SD-17 rules. Document each one.
  - With no cues present, the protected Player and every non-Settings render stay pixel-identical.
  - Never update unrelated goldens to absorb provisional-versus-final subtitle differences.
- **Unrelated, pre-existing:** `tool/visual/player_track_label_visual_test.dart` fails on the pinned commit without any specimen change (24–42%, in `evidence-golden-failures-clean/`). It compares against the September 22 track-label evidence images, not committed goldens, and is outside this gate and S0's 5/5 golden suites. Nothing here changes it.

## Findings for the orchestrator (not UI decisions)

1. **F1 font loading needs runtime verification.**
   - In flutter_test, `SubtitleFonts.load` returns `true` but its family never registers: text measures as the fallback.
   - Isolated cause: the pattern `Future.wait([...rootBundle.load...])` and then `loader.addFont(Future.value(bytes))` fails to register. `loader.addFont(rootBundle.load(...))` with the same files registers correctly. I swapped the two fonts between methods to confirm.
   - The specimen works around it by registering directly in the harness.
   - **Action:** F1/R1 should check whether production is affected. Look on the device or emulator for a non-Standard font actually drawn in its typeface (V1). Add a widget test that measures the glyph width, not just the `load()` result. If production is affected, switch to the direct `addFont(rootBundle.load(...))` form.
2. **Settings needs the shared appearance source** (UI-2 wiring note). This is a one-line constructor addition in `lineup_shell.dart`, a file M1 rewrote; keep it additive.
3. **`test/app/desktop_settings_test.dart` has two exhaustive switches over `SettingsCategory`** (lines 409–424). U1 adds the new case to both.
4. **The specimen edits are disposable.** They are in `lib/app/settings_view.dart`, `lib/app/settings_subtitles_specimen.dart`, `lib/app/lineup_shell.dart`, `lib/playback/player_view.dart` and `lib/playback/subtitle_layer.dart` (debug metric knobs). U1/F2 implement from this record, not by copying specimen code, which uses debug globals.
5. **Semantics and save focus are U1 extensions (R-7).** The specimen proves appearance only, not grouped spoken labels or focus kept during a save.
   - **Semantics:** implement real group-qualified semantics names, such as "Text Color", and keep disabled-state and value announcements. A widget key is not a spoken label.
   - **Save wiring:** a row's own pending save must not null its `onChanged` or remove its focus. Identical selections must not enqueue duplicate writes; distinct later choices must not be silently dropped. Other keys keep using the controller's serialized transformations.
   - **Feedback:** keep Saving and error text directly below its row, outside the 72 minimum. It may grow or wrap, and must stay visible with the focused control.
   - **Tests:** verify the §9.7 obligations with delayed and failing persistence plus semantics assertions.
6. **The review's probes** are in `review/`, with exact invocations in `review/commands.json` and `review/boundary-commands.json`. The A2 boundary capture is `review/captures/boundary-721x720-text1/option-A2--top.png`.

## Approval summary

| Item | Approved choice |
| --- | --- |
| UI-1 | Subtitles category after Playback; A2 (rows left, preview right) when non-compact and the rows column is at least 560 canvas units; A (band above rows) otherwise |
| UI-2 | Actual-size preview as specified, with the adaptive crop (only the crop shrinks) and displayed-value/device-snapshot rules; shared `SubtitleAppearanceSource` passed into Settings |
| UI-3 | Compact one-control rows, groups and order as specified; switch control 56 wide |
| UI-4 | Existing menus; Font menu in each typeface; Custom shown only when no preset matches, with the menu focusing Standard; no open-menu live preview in v1 |
| UI-5 | Disabled states as specified, including Edge color disabled while Edge style is None; Reset preserves `useDeviceStyle` |
| UI-6, UI-7 | Copy as specified |
| UI-8 | Outline 0.10 em; drop shadow 0.06 em offset / 0.06 em blur; background inset 0.2 em; all other metrics unchanged |
| UI-9 | SD-17: bottom-aligned cues move individually above the OSD and Now Playing (feather included, retiring panels count); clip the top when there is no room (protected-Player change approved) |
| UI-10 | `PlayerSurface(showSubtitles: false)` behind Settings confirmed |
| UI-11 | TV remote interaction as specified |
| UI-12 | Update exactly `tool/visual/goldens/settings-appearance-ember-steel-1920x1080.png`, plus the listed rail-only TV Settings renders; provisional-versus-final metric allowances as specified; everything else identical |

The findings for the orchestrator above are not UI decisions; route them through F1/R1/V1.

## Amendments (October 29, 2026)

After the Codex adversarial review (`review/report.md`), Claude adjudicated every finding as valid:

- **R-1 and R-2:** dispatch blockers, amended in UI-9 and UI-1/UI-2.
- **R-3, R-4 and R-5:** contract clarifications, amended in UI-2/UI-4, UI-5 and UI-4.
- **R-6 and R-7:** evidence and implementation notes, in UI-12 and orchestrator finding 5.

The maintainer answered the three product questions with the recommended choices:

1. **SD-17 no room:** clip the top, and keep the panel clear.
2. **Narrow or large text:** fall back to A when the A2 rows column is under 560 canvas units, and shrink only the preview crop so one complete focused row fits.
3. **Reset:** keep device mode.

One divergence from the review's R-2 text: it asked A2 to apply only when every label and value "can display". This record replaces that with the deterministic 560-unit rows-column rule, which is testable, and requires selected values to stay legible.
