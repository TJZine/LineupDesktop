# Android TV UI decisions: Guide rail/PiP, focus, Menu/details, Review footer and completion

Drafted by Opus on October 25, 2026; maintainer decisions recorded October 26, 2026.

Approved items are listed under Maintainer decisions; this document is the single TV UI contract. The specimen contract in `opus-specimens/spec.md` is superseded except where noted here.

The maintainer adopted the October 26 reconciliation (local evidence, not tracked), including item 7: no-change Review Back returns to Configure. Provisional override approvals yield to that reconciliation. Historical diagnoses, options and specimen evidence below retain their original source attribution; the approved rules and revised acceptance requirements govern current implementation.

## Maintainer decisions (October 26, 2026)

- **2. Composition: option A (desktop parity) is approved.** A bigger picture is only possible by making the info band taller, and that shortens every Guide row (option B). We stay with desktop.
- **4. Menu/details: M1 is approved, with no chevron.**
  - Menu always opens the Lineup menu.
  - Select or Down from hidden opens the compact OSD. Down again expands.
  - Info, the menu's Now Playing row, and returns from More info and the track drawers still expand directly.
  - The chevron can be revisited after the couch check.
- **5. Review footer: R1 is approved.**
  - Right from a read row or disclosure header goes to the footer. Up returns to the remembered row.
  - Hint copy: **"Press right on any channel to jump here"** (maintainer, October 26; replaces "Press ▶ …", because ▶ is the Fire remote's Play/Pause symbol).
  - Codex must still deliver the 184-row key-count proof and a Review render of the hint for Opus to check before integration.
- **6. Completion: approved.**
  - TV result actions are **Open guide** (primary, goes to Guide) and **Add a custom channel** (secondary, goes to Studio, already wired).
  - This holds for first creation and regeneration.
  - No-change Review shows **Open guide**.
  - Completed Back follows Open guide once; no-change Review Back returns to Configure. The no-change primary still opens Home Guide. Desktop is unchanged.
- **1. Rail numbers: approved** (maintainer, October 26).
  - The column fits the widest number in the lineup (§1c).
  - It ships on TV and desktop. The maintainer accepted the recommendation that included desktop; the desktop rail is the same bug.
  - Short-cell truncation is accepted. Revisit only if it becomes a problem in use.
- **3. Focus colours: approved.**
  - Slate & Pine uses pale sage. Mint Noir uses pale mint.
  - Ember & Steel stays cream. Satellite Blue stays yellow.
  - Exact roles are in §3b; the consumer renders are in §3c.

**Approval state:** items 1–6 are agreed. Implementation evidence is still owed under the acceptance matrix. Opus checks the Review hint render and the first integrated Guide/focus renders before the stick.

## Source and evidence attribution

- The G1 evidence baseline is `20763fc7`. These specimens were rendered from `d41df67c`, the current `platform/android-tv` HEAD.
  - Since 20763, the only tracked changes to `lib/guide` are the contextual `onBack` hook and logo alpha validation. Neither affects layout.
- The specimens ran in a disposable local worktree (not tracked).
  - The production patch is gated behind `GuideSpecimen` switches: `specimen.diff`.
  - The probe is `opus_guide_spec_test.dart`, and all 15 cases pass.
  - The specimen is reference only and must never be integrated. Main has no changes.
- Renders: `current/`, `A/` and `B/`, each with matching JSON. Comparison sheets are in `compare/`.
  - Each case is a real production Flutter widget raster at 1920×1080: TV at DPR 2 and 960×540 logical, desktop at DPR 1.
  - Clock is fixed at 06:40, with Ember & Steel, Inter test fonts, Reduce Motion, focus on channel 123, channel 1 selected and channel 999 watched.
  - The picture is a synthetic proxy, not native video.
- Note on the fixture domain: `Channel._validateStructure` limits numbers to **1–1000** (`lib/channels/channel.dart:542`).
  - G1's `1234` and `1400` are therefore outside the domain. The only four-digit number is `1000`.
  - These specimens use 1, 12, 123, 999 and 1000.
  - Names: one realistic long name, one unbreakable 34-character token and one name that overflows.

## 1 + 2. Guide composition (rail numbers and picture size)

### Diagnosis

- **Picture.**
  - The TV picture width comes from `W − 84 − identitySchema / identityFraction` (568/0.4 = 1420 cu). That reserves 852 cu for a synopsis that uses two lines, which caps the picture at 416×234.
  - The information band is the TV schema's measured height: 299 at 1.0, against 324 on desktop. The 416×234 picture is then centred inside it, with surround bands.
  - Desktop, which the maintainer has accepted as the baseline, shows 576×324 at every scale and keeps five rows (114.4/113.3/112.1 cu).
  - The TV deviation comes from a reservation formula. It is not a hard requirement.
- **Numbers.**
  - The number column is a fixed 48 cu with no explicit gap. Tabular Inter 28 needs 55 cu for `123` and 74 cu for `1000` at 1.0.
  - Desktop shares the defect.

### Options rendered (same content, focus and clock)

| | Picture (raster, TV) at 1.0 / 1.15 / 1.3 | Rows (cu) | Rail (cu) | Synopsis (cu) |
|---|---|---|---|---|
| Current | 416×234 / 505×284 / 442×249 | 119.4 / 121.3 / 114.7 | 300 / 345 / 390 | 852 / 666 / 697 |
| **A: desktop parity (recommended)** | **576×324 at all three** | **114.4 / 113.3 / 112.1 (= desktop)** | 340 / 398 / 456 | 692 / 628 / 564 |
| B: bigger picture | 614×346 at all three (capped by the 32% width limit) | 107.2 / 106.1 / 104.9 | as A | 654 / 588 / 524 |

- In all three variants, every case keeps five complete rows, every number stays on one line, Large Focus leaves the geometry unchanged, and no Flutter exceptions occur.
- **Recommendation: A.**
  - It is literally the desktop composition, consistent with the maintainer's "desktop size is the starting point" decision.
  - Picture area grows +92%. The identity schema is still reserved, so badges never churn.
  - B adds only +7% of picture width, and it costs about 7 cu per row plus a departure from desktop.

### Exact rules for A (TV only)

**Information height.**
- Height = `min(max(H − 1080 + 324, schema.informationHeight, placeholder.minHeight), available − 5·rowFloor)`.
- It is still bounded by the five-row floor.
- At 1920×1080 this is 324 at every linear scale: the schema measures 299/284/311 and fits inside it.

**Picture.**
- Width = `max(GuidePlaybackPlaceholder.minimumSize.width, min(info·16/9, 0.32·W, W − 12 − 40 − 32 − schema.identityWidth − 400·s))`.
- The 324 cu reference height and the 400 cu synopsis floor are named design constants in the implementation. The lower bound preserves space for the idle/error/Retry placeholder; it does not change approved pixels at 1920×1080.
- The picture is top-aligned exactly like desktop, at (0, 82), with no surround band.
- The native aperture keeps following Flutter geometry.

**Identity and synopsis.**
- Identity = `max(schema.identityWidth, fraction × text row)`, giving 568/633/697.
- The synopsis takes the remainder, with a floor of 400·s. It keeps its existing line clamp and ellipsis.
- Nothing depends on the focused program.

**Rail number.**
- The column width is the measured width of `1000` in the number style: Inter 28, w500, tabular, scaled. That gives 74/85/96 cu.
- Measure at 28 even when provenance is hidden, so the column never changes.
- Text is right-aligned, `maxLines: 1`, `softWrap: false`.
- An explicit gap of 14·s cu separates it from the name.
- **The rail grows by `numberWidth + gap − 48`, so the name budget is unchanged** (228/273/318 cu). The grid gives up 40/53/66 cu, out of about 1580/1500/1460.

**Name policy.**
- The support line (source or ▸ Watching) is reserved first.
- The name gets at most **2** whole-word lines, with an ellipsis at the end of line 2.
- A single token wider than the line breaks at character boundaries. This is unavoidable, and it is the only case where a mid-word break happens.
- The full name stays available in the inspected-identity eyebrow (`123 • Name`) when the row is focused, and in semantics.
- No marquee and no auto-scroll. Arbitrary input is not promised to fit.
- Fix included: today the support label is dropped whenever the *unbounded* name is taller than the row. The specimen keeps the support line and clamps the name instead.

**Desktop.** The rail fix ships on desktop as approved in §1c. The composition change remains TV-only. Desktop comparison permits only the rail-driven differences listed in the revised acceptance requirements below.

### 1b. Effects of the wider number column on the rest of the Guide

Renders: `short-current/` and `short-A/` (15–45-minute programs); comparisons in `compare/short-*`.

| Linear text | Rail (now → fixed `1000`) | Program grid | 30-minute slot |
|---|---|---|---|
| 1.0 | 300 → 340 | 1620 → 1580 (−2.5%) | 405 → 395 |
| 1.15 | 345 → 398 | 1575 → 1522 (−3.4%) | 394 → 381 |
| 1.3 | 390 → 456 | 1530 → 1464 (−4.3%) | 383 → 366 |

**What changes**
- Every time slot narrows by the same small fraction.
- Titles in short cells truncate about one character earlier: "Coastal Kit…" becomes "Coastal Ki…" at 1.3. 15-minute cells look essentially the same.
- The "All libraries" filter box follows the rail width, so it gets wider.

**What does not change**
- Row heights, five rows, and the top composition.
- Search, Now, the arrows and the hours control. The toolbar stays on one line, with about 700 cu to spare at 1.3.
- The Mini Guide in Player, which has its own number sizing.
- Desktop top composition and non-Guide surfaces. The approved desktop rail changes follow §1c.

**Sizing alternative to reduce the cost: size to the widest number in this lineup.**
- Sizing uses the whole lineup, never the filtered view, so filtering or browsing never shifts the column.
- Cost per lineup type:
  - lineups up to 99: +3 / +4 / +5 cu;
  - lineups up to 999, which is most of them: +22 / +31 / +42 cu;
  - only lineups that contain channel 1000 pay the full +40 / +53 / +66 cu.
- Numbers also sit closer to the names, with no empty space to the left of short numbers.
- Trade-off: the rail width changes when the lineup gains or loses a digit, for example after generating one with channel 100 or 1000.
- **Updated recommendation: size to the lineup's widest number.**

### 1c. Final number-column rule (approved; TV and desktop)

**Column width**
- The column width is the measured width of `max(99, largest channel number in the whole lineup)` (`LineupController.channels`). The floor is 99, including lineups with only one-digit numbers.
- Measure it in the number style: Inter 28, w500, tabular figures, through the active text scaler.
- Measure at 28 even when the rail hides provenance and draws 22, so the column never changes with provenance.
- Never measure the Guide's filtered or visible channels. Filtering, search and browsing must never move the column.

**Number text**
- Right-aligned, `maxLines: 1`, `softWrap: false`.
- Explicit gap after it of `14 × textScale`.

**Rail growth**
- The rail grows by `columnWidth + gap − previousNumberWidth`, at every base rail width.
- At 1800 cu and wider, the previous number width is 48. On desktop's narrow rails it is 40, below a 180 rail.
- The growth term is intentionally **unclamped**. The name budget `baseRailWidth − previousNumberWidth − 2·inset` is the invariant, independent of numbering. Growth may be slightly negative at text scales below 1; do not add `max(0, …)`.
- At 1920 canvas width the name budget is 228/273/318 cu at scales 1/1.15/1.3.

Resulting rail widths at 1920:

| Lineup | 1.0 | 1.15 | 1.3 |
|---|---|---|---|
| ≤ 99 | 303 | 349 | 395 |
| ≤ 999 | 322 | 377 | 432 |
| contains 1000 | 340 | 398 | 456 |

**Names**
- The support line is reserved first. Names get at most 2 whole-word lines, ending in an ellipsis.
- Over-long single tokens break at characters.

**When the column changes**
- The measurement cache key includes the whole-lineup number set, the active TextScaler, text direction and base style. Recompute only when one of those inputs changes.
- Provenance is deliberately absent from the cache key: the number is measured at 28 even when it is drawn at 22. Focus, scroll, filter and search do not invalidate the measurement or move the column.

**Evidence**
- `final-999/` and `final-1000/`: every number on one line, picture 576×324, five rows, on TV at 1/1.15/1.3 Large and desktop at 1/1.3.
- `current-999/`: the baseline, where 123 and 999 wrap.

## 3. Focus and highlight per theme

**Recommendation: confirm the current contract and make no palette change.** Evidence: the G1 runtime theme cycle, N3's 16-state Audio fixture, and the per-theme review below.

- **Focus colour by theme.**
  - Cream `#E9DCC3` with ink text in Ember & Steel, Slate & Pine and Mint Noir. Yellow `#FFCC00` with ink text in Satellite Blue.
  - This is the approved UX-F/UX-13 exception, and both colours read clearly as "you are here" against their themes.
  - Satellite Blue's yellow matches that theme's broadcast-guide identity, where cream would look foreign. Keep it.
- **Guide cells under Large Focus.**
  - A filled program cell (about 1150×110 cu) is already the largest possible focus signal. A 3 cu frame adds nothing.
  - **Recommendation: record this explicitly as an intended filled-cell exception**, together with the focused channel rail.
- **Selected, watched and focused stay distinct.**
  - Selected uses `elevatedSurface` tint. Watched uses the "▸ Watching" label. Focused uses the fill.
  - Selected is subtle in Ember and Mint Noir. That is acceptable, because on TV focus and selection only diverge while focus is in the toolbar or rail. Flagged for the couch check, not as a defect.
- **No change** for disabled controls (the alpha .22/.45 branch) or the O1 dark More info reader.
- **Still unverified, and owned by N1–N4 audits rather than settled here:**
  - live theme apply in Settings while a control stays focused, including preview, cancel and restart;
  - disabled rows;
  - track and Sleep readers.
  - The acceptance matrix below lists them.

### 3b. Maintainer feedback: cream looks off on some themes

**Approved focused support ink.** On the TV rail, Watching text and its icon use `focusSecondaryText`; provenance uses `focusMutedText`. This preserves the unfocused secondary/muted hierarchy. The approved per-theme tints and Large borders below carry forward unchanged.

- Desktop already uses a different focus colour per theme. The TV-only override forced cream onto Slate & Pine and Mint Noir, whose palettes are cool green and black.
- Renders: `focus/` and `compare/focus-*`. They show the A layout at 1.0 and at 1.3 Large.
- Each proposed tint keeps the TV fill model (light fill, ink text, no ring) and is derived from the theme's own accent.

| Theme | Fill | Ink contrast | Inset | Secondary / muted ink | Large-frame border |
|---|---|---|---|---|---|
| Ember & Steel | `#E9DCC3` cream (unchanged) | 14.8:1 | `#D7C7A8` | `#3B3226` / `#5B5141` | `#F0D39A` |
| Slate & Pine | **`#D3DECF` pale sage** | 14.4:1 | `#C1CFBC` | `#2F3B30` (8.5:1) / `#4A574B` (5.5:1) | `#A8C49E` |
| Mint Noir | **`#C6EEDB` pale mint** (alternative: `#E6EAE8` neutral white) | 15.9:1 (white 16.5:1) | `#B0E0C8` (white `#D2D8D5`) | `#22372D` / `#41554B` (white `#2E3330` / `#4B514E`) | `#6EE7B7` (white `#FFFFFF`) |
| Satellite Blue | `#FFCC00` yellow (unchanged) | 13.2:1 | as today | as today | `#FFCC00` (**corrected October 26:** the TV build previously used cream `#F0D39A` here; yellow is intended so the Large frame matches its fill) |

- **Recommendation:** pale sage for Slate & Pine and pale mint for Mint Noir.
  - Each matches its theme the way cream matches Ember's amber.
  - Each stays clearly lighter than that theme's accent, so focus never reads as a primary button.
- Neutral white is the alternative for Mint Noir, for a crisper Swiss look.
- Before Codex implements, Opus renders the chosen tints on the rest of the focus consumers:
  - buttons and menu rows;
  - Settings rows, including selected+focused;
  - disabled states;
  - the Player OSD action row.

### 3c. Approved tints on other focus consumers

**Renders**
- Folder: `focus-surfaces/<theme>-<current|tint>/<tv-1.0|tv-1.3-large>/`.
- Comparison sheets: `compare/focus-surfaces-slatePine-current-vs-tint.png` and `…-swiss-…`.
- Surfaces covered: Settings (every category, plus the Player overlays menu), Player OSD at three transparency levels, the profile PIN keypad, and all Configure sections.
- They come from the margin-review surface harness, with a forced theme plus a specimen focus map. The harness copy is at `opus-guide-spec/capture/r7/focus_capture_test.dart`.

**Results**
- The rail, keypad and Configure section focus read cleanly in both themes.

**Relationship to the primary accent**
- Focus is a pale tint; primary is the saturated accent: sage `#809A79` and mint `#34D399`.
- This is the same relationship as cream versus amber in Ember & Steel. Lightness separates them strongly: luminance 0.71 vs 0.31 for sage, and 0.78 vs 0.50 for mint.
- The couch check should still confirm that a focused primary button, such as Review channels or Create lineup, is unmistakable.

**The Settings Player overlays menu**
- In the render, this menu was opened by a tap, so it correctly shows no remote focus fill. This is not a defect.

**Implementation**
- Implement as per-theme TV focus roles in `LineupTheme.forName`, using the §3b table: fill, inset, secondary ink, muted ink and border.
- These replace the forced cream for Slate & Pine and Mint Noir only.
- Desktop roles are unchanged.
- The approved O1 More info dark reader stays dark. Its focused edge bar and scroll thumb already use `focusedSurface` (`player_view.dart` around 3766/3777), so they pick up each theme's tint automatically.

## 4. Menu, Info and expanded details on Player

**Key fact:** the Fire TV Stick 4K Max remote has **no Info key**. Its keys are D-pad, Select, Back, Home, Menu ≡, ⏪ ⏯ ⏩ and voice. On Fire, therefore, Menu is the only spare key, and Down is the only details gesture.

### Option M1 (recommended): one meaning per key

| Key | Hidden Player | Compact OSD visible | Expanded details | No current program |
|---|---|---|---|---|
| Select | compact OSD | activate focused action | activate focused action | compact OSD |
| Down | **compact OSD** | **expand details** (from the bottom of the OSD focus order) | move within details | compact OSD; second Down does nothing |
| Up | Mini Guide (unchanged) | unchanged | unchanged | unchanged |
| Info (if the remote has one) | expanded details | expanded details | collapse to compact | compact OSD |
| Menu ≡ | **Lineup menu** | Lineup menu | Lineup menu | Lineup menu |
| Back | unchanged leaf-first policy | hide OSD | collapse to compact | — |

- Every ordinary reveal (Select or Down) is compact, so an explicit minimize is respected automatically, with no hidden state and no new setting. Details are always one more Down away.
- The intentional expanded entries stay as they are:
  - the Lineup menu's **Now Playing** row;
  - Info;
  - return from More info;
  - track-drawer return.
- **Discoverability:** the Lineup menu already lists Now Playing. Optionally, a quiet "▾ Details" chevron on the compact OSD's bottom edge.
  - The chevron is a **change to the protected OSD layout**, so it would need its own render and approval. It is not in M1 by default.
- Menu → Lineup menu is consistent with Guide (UX-B) and replaces UX-A's Player Menu → Now Playing.

### Option M2: per-session memory

- Reveal shows whichever state the viewer last chose during this Player session.
- This respects a preference in both directions, but the reveal looks different depending on hidden state, which reads as inconsistency on a remote.

### Open choices for the maintainer

- M1 or M2.
- Whether the details chevron is wanted.

## 5. Review Channels: getting between the roster and the footer

### Recommendation R1

**Moving to the footer.**
- **Right** from any ordinary read row, or from a disclosure header, moves to the footer.
- Focus lands on the footer's enabled primary (Create / Update / Replace / Add as new). If that is disabled during consent or recalculation, it lands on **Back to configure**.
- **Down** from the last row also reaches the footer (existing behaviour).
- One press from any row.

**Returning to the roster.**
- **Up** from either footer button returns to the remembered row, identified by stable entry ID, and reveals it.
- Reveal that exact remembered row even if its lazy widget has been disposed; attachment is not a reason to choose another row.
- Fallback when the row was filtered out or removed:
  1. the nearest surviving row in the original order, with equal-distance ties choosing the preceding row;
  2. Search, if the filtered list is empty.

**Leaves keep their own keys.**
- Search/IME editing, segmented build-method and radio controls, removal controls, and footer Left/Right all keep their existing semantics. Right is only a region key on read rows and disclosure headers.

**Return-state rules (normative).**
- Right and Up act on KeyDown only. Consume KeyRepeat without remembering again, changing focus again or re-revealing a row.
- Up from the footer with no remembered row keeps normal traversal toward the last row. It must not jump to the first visible entry.
- Clear remembered row identity/order after a return, when focus leaves the footer by any other path, and when Review is rebuilt for a new review. Left/Right between the footer buttons keep their existing behavior.
- On every entries change, prune and dispose per-row focus state (`_rowScopes`) for IDs absent from the current `review.entries`.
- Right targets the enabled primary only if it is attached and focusable; otherwise try Back to configure. Skip detached or non-focusable targets.

**Guards.**
- Region moves never apply, toggle consent, save, recalculate, or clear the query or filter.

**Hint (TV only).**
- One `bodyMedium` / `mutedText` line in the footer summary slot at its leading edge, visible only while focus is in the roster.
- Copy: "Press right on any channel to jump here" (superseded the ▶ wording on October 26).

**Why not the alternatives.**
- **Back-first-to-footer:** a common TV list convention, but it rewrites the accepted Review Back → Configure model. Rejected unless the maintainer wants it.
- **⏩/⏪ as page keys:** not discoverable, and still not one step.
- **Focus starting on the footer:** fixes entry but not the return trip.

**Before adoption:** a real Review render plus a key-count proof with a 184-row virtualized roster. Not produced in this pass; it follows once the mapping and hint copy are agreed.

## 6. Post-generation destination (TV only; desktop View lineup → Channels unchanged)

| Context | Primary label | Destination | Back | Secondary |
|---|---|---|---|---|
| First creation | **Open guide** | Home Guide | Completed Back follows Open guide once | Add a custom channel → Studio (unchanged, already wired) |
| Regeneration (from Channels or origin) | **Open guide** | Home Guide | Completed Back follows Open guide once | same |
| No-change Review | **Open guide** | Home Guide | Review → Configure | — |

- The TV primary intent is **Open guide → Home Guide** for first creation, regeneration and no-change Review.
- No-change Review is still an editable Review step, not a completion: Back returns to Configure, preserving mode, search, filter and consent with zero saves. Completed Back follows Open guide once.
- Channel management stays one menu step away.
- Alternative: regeneration returns to its origin with the label **Back to channels**. More "correct" for a management task, but it gives two rules.
- Opening Guide never tunes, reloads, re-saves or undoes anything. Guide entry focus follows its existing policy. Applying stays non-cancellable, and the stale-review and zero-save guards stay as they are.

## Acceptance matrix for Codex after reconciliation

The reconciliation §5 (local evidence, not tracked) is the revised acceptance matrix; its rules are summarized below. Item 7 is adopted, so every conditional no-change Back requirement there now means Review → Configure. Its acceptance scope supplements and supersedes the earlier checklist below where they differ.

- Guide: prove constant name budget for lineups up to 99, up to 999 and containing 1000; stable column across provenance/focus/scroll/filter/search; the placeholder-minimum bound at a constrained size; and unchanged reference geometry at 1/1.15/1.3 × Large.
- Desktop Guide: compare full-frame d41/final pairs at 1/1.15/1.3 in all four themes. Allowed differences are rail width, right-aligned nonwrapping numbers, 14·s gap, name start, two-line name clamp with reserved support, time-header/grid offsets, slot widths/cell truncation and library-filter width. Top composition (picture, identity, synopsis), the toolbar right group, desktop focus roles and every non-Guide surface must remain equal.
- TV focus: verify the approved fill/inset/ink/Large-border roles, including a live focused theme switch and Watching secondary text/icon versus muted provenance.
- Review: add no-memory Up, inert repeats, consumed/cleared memory and pruning after recalculation to the existing 184-row, filter, disclosure, consent and zero-save proofs.
- Completion: no-change Back returns to Configure with retained state and zero saves; its primary still opens Home Guide once. First/regeneration completion, Completed Back once and Add custom → Studio remain required.
- Final renders compare against refreshed `integrated-renders/guide` and `final-renders/review`, not the superseded specimen render sets.
- Final-APK API34 retakes include hidden Player Menu82 after OSD teardown, a track reader and More info; progressive Down; Guide 1.15 Large aperture within 1 px/five rows/opaque corners; Review Right/Up with held keys; real first-creation/regeneration Generate → Open guide and no-change Back → Configure. Prior native observations retain their exact source attribution.
- No signed build, stick install, physical-device, account/PIN action or publication is authorized by this contract amendment.

**Earlier acceptance checklist with reconciled corrections.**

**Guide (A).**
- Portable positive proofs:
  - 1/12/123/999/1000 on one line at 1/1.15/1.3 × Large off/on;
  - name ≤ 2 lines, with the support line present;
  - unbreakable-token and overflow names;
  - picture 576×324;
  - rows equal to desktop;
  - five complete rows;
  - stable geometry through focus moves across rich/minimal/logo/fallback/no-schedule and idle/error/Retry (extend `guide_allocation_test.dart:804`).
- Baseline-negative proof: on current source, `123` and `1000` wrap and the picture is 416 wide.
- Desktop full-frame pairs equal d41 except the explicitly allowed rail-driven regions above.
- Full-bleed/aperture alpha (`guide_opacity_test`).
- Four themes, including a live switch on the mounted Guide.

**Native (API 34 emulator).**
- Retake the aperture at 576×324.
- Nonlinear font 1.3 with five rows.
- Full-bleed corners.

**Couch.** Five rows readable from the seat, plus the rail and picture proportion. Proxy pixels prove neither native video nor device responsiveness.

**Menu/details (M1).**
- Resolver tests per key and state in the table above, including the no-program case.
- Tests that explicit expanded entries still expand.
- Zero transport commands for navigation keys.
- Native observation of the Fire Menu keycode.

**Review (R1).**
- Bounded key count from the first, middle and last rows (virtualized, 184 rows), including filtered-empty, an expanded row, disabled Apply and recalculation.
- Return to the remembered row, with consent, save count and query unchanged.
- Baseline negative on current source.

**Completion.**
- Every TV primary in the table reaches Home Guide with zero tune/load/save; Completed Back follows that intent once. No-change Review Back returns to Configure with mode, search, filter and consent preserved and zero saves.
- Add custom observes actual Studio `createCustom` state.

**Standing.** A1/B2 deferred; B3, O1–O5 and the O5 Studio exclusion keep their dispositions.
