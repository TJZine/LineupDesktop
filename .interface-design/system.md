# Lineup Desktop Interface System

## Status

Cinema Continuity is the approved internal design direction. The user-facing
theme name and persisted identity remain Ember & Steel. The tokens and
boundaries below are approved design inputs; production implementation is in
progress.

## Intent

Lineup is used to browse and watch a personal linear channel lineup from the
couch. It should feel like a restored-cinema program book viewed in a dark
projection room: atmospheric and editorial, but still immediate and legible as
a TV interface.

Domain cues: broadcast continuity, program logs, channel tuning, projection,
film gates, aperture cards, archive catalogues, and on-air state.

The signature is the program-specific Guide information bleed inside a stable
continuity frame. The program may change the atmosphere; navigation, focus,
and semantic states stay predictable.

## Palette

| Role | Value | Use |
| --- | --- | --- |
| Film gate | `#090806` | App canvas and deepest background |
| Booth surface | `#12100D` | Primary panels |
| Raised reel | `#1A1712` | Elevated controls and cards |
| Inset black | `#060504` | Inset fields and on-accent content |
| Overlay scrim | `#F20A0907` | Player and modal overlays |
| Selected row | `#2B2419` | Selection without implying focus |
| Tuned row | `#3B3020` | Currently tuned channel |
| Projector amber | `#CC9F5B` | Primary actions and progress |
| Focus light | `#F0D39A` | Keyboard/remote focus boundary |
| On-air coral | `#FF7768` | Live, error, and urgent state only |
| Aged-paper text | `#F3E8D2` | Primary text |
| Supporting text | `#C7B99F` | Secondary text and controls |
| Archive text | `#978B76` | Metadata and disabled content |
| Quiet border | `#2B261E` | Normal separation |
| Strong border | `#494031` | Emphasized separation |

Projector amber replaces the earlier brass `#C8A363`. Do not use amber as
blanket decoration. Focus light and on-air coral retain separate meanings.

UX assessment decision, 2026-11-13/14 (Q6), updated in the Wave 1 review.
The TV profile picker uses the active theme's TV focus fill color for the
avatar ring and the canvas color for the gap. The
[TV profile tile exception](../docs/design/tv-ui-decisions.md#profile-tile-exception-q6)
records the dimensions and motion.

## Construction

- Depth comes from warm near-black surface shifts and quiet borders, not drop
  shadows.
- Use a 4px spacing base, predominantly in 8px multiples.
- Use 8px panel radii where a surface is not already structurally protected.
- Preserve the current production type family, sizes, weights, and hierarchy
  until typography changes receive separate approval.
- Navigation and main content share the film-gate canvas; a border provides
  separation.
- Inputs are darker than their parent surface.
- Motion is short and decelerating. Reduce Motion must settle immediately.
- When the actual Lineup logo and LINEUP wordmark appear together horizontally,
  place the logo first, then the wordmark. Use bundled Arimo Regular for LINEUP
  only, at 22 px, weight 400, and letter spacing 3. UX assessment decision,
  2026-11-13/14 (N20). The pinned font and licence are listed in the
  [font provenance record](../docs/licenses-and-rebuilding.md#arimo-wordmark).

## Separators and empty states

UI audit 2 decision, 2026-11-16. Channel identity shows the number, kind icon,
name and optional library tag without a bullet. Use equal gaps around the kind
icon; plain-text number/name identities use two spaces. Use · between metadata
items. Preserve punctuation from authored episode and program titles.

Use the shared `LineupEmptyState` where a surface has no content. It centers a
24 px heading, one sentence, and up to one action using existing theme tokens.
The empty Guide fills the content area with **No channels yet** and **Set up
channels**, focused on entry with a remote. Manage channels keeps **Generate
lineup…** as the primary action and offers **Add a custom channel** separately.
Studio offers **Update lineup…** when programming is unavailable. Diagnostics
uses the shared component for the recent-events area and keeps its idle
playback summary inline.

## TV typography floor

UX assessment decision, 2026-11-13/14 (N14). The floor for meaning-bearing
TV text is 20 px on the 1920×1080 design canvas at 1.0 text scale. Verify the
existing layout at 1.0 and 1.3. Preserve a smaller size where a 20 px trial
demonstrates wrapping, clipping, overlap, truncation, or movement of existing
rows or controls. Buttons and selectors in the same action row use the floor
together when it fits. Retain the group's prior sizes when the shared increase
exceeds that layout. The Guide's episode code yields to the title in tight cells.

UI audit 2 decision, 2026-11-16. Settings › Accessibility offers Text size:
Standard, Large and Larger multiply the platform text scale by 1.0, 1.15 and
1.3, clamped to 2.0, once above the design canvas on every platform. Larger text
can show fewer Guide rows.

## First-run setup

UX assessment decision, 2026-11-13/14. A sole reachable server opens
Choose libraries directly on unresolved first run. In the server picker, show
one “Unreachable” status with “Retry” on the row whose reachability probe
failed. The first Libraries step uses origin-specific Back copy on desktop
and the contextual Back action on TV.

UI audit 2 decision, 2026-11-16. Welcome uses the standard deep background and the setup
result atmosphere's one-time settle, with a still ring for Reduce Motion. Sign in places
With your phone and On another device in equal panels, stacking phone first when needed.
TV keeps Open on this TV focused on entry and omits Copy code. Unusable libraries and
source kinds display unchecked, muted and disabled while retaining the underlying
selection/configuration; library retry actions remain available. Continue receives TV
focus when scanning settles.

## Channel identity and setup

UX assessment decision, 2026-11-13/14. The channel number and outlined
TV, Film or mixed-media glyph stay visible when the name truncates. A
single-source library tag disambiguates equal names from different libraries.
Use supporting ink for the glyph and library tag, along with one accessible
label. Keep the existing surface geometry. Wrap between words where the
surface allows multiple lines. Use a one-line ellipsis when a word exceeds
the name column. Where the Guide has a spare line, move a library tag there when it
cannot fit beside the name. Mini Guide keeps library and Watching inline (UI audit 2
decision, 2026-11-16). Keep the full library
in the accessible label.

Setup names its steps Libraries, Channels and Review. Choose channels adds
the saved Channel order choice and retains two-column source rows with at
least 16 px of TV focus padding.

## Manage channels and Studio

UX assessment decision, 2026-11-13/14 (Q5, N17, N18). UI audit 2 decision, 2026-11-16.
The Channel cell shows the kind icon and
name, then an applicable plain secondary library label, outlined Custom tag
and filled accent favourite star, within the existing row height. Accessible
labels retain the full identity and applicable marker facts once. Channel
order keeps the single Source line for type and library. The optional Grouped
by source view shows Custom first and the remaining source groups in lineup
source order; Custom starts open, others collapsed. Its rows replace Source
with current program and time left, omit Custom tags and keep channel numbers. At TV 1080p
and 1.3 text scale, the directory aims for about nine visible rows. Add a custom
channel is the filled action for populated lineups. Generate lineup… fills
that role when the lineup is empty. In Studio on TV, focus the programming source
choice at entry for a new custom draft.

UI audit 2 decision, 2026-11-16. Studio shows one outlined Draft, Unsaved changes
or Saved tag beside the channel name. Filter values apply as they are chosen and
stay when the picker closes; an open picker never blocks Save or Tune in. The
schedule preview starts with the ON NOW row and shows the detail block only for a
later program the user selects. Its list scrolls inside a bounded panel whose
footer stays visible; when too little height remains below the fields, the panel
takes one viewport height and the page scrolls to it. Program rows load small
sized artwork only for rows that are built, with a neutral placeholder. The
footer note reads Updates as you edit, Matches the saved channel or Updating…, and
is omitted while a failed check offers Retry.

## Guide

- Preserve the existing dynamic information-background behavior.
- `Bleed` remains the default: extract the focused program poster color,
  normalize saturation and lightness, then blend it into the information
  surface. Cinema colors are the structural fallback, not a replacement.
- Preserve the current 400ms background transition and its Reduce Motion
  bypass.
- `Artwork` continues to show the program backdrop beneath a legibility scrim.
- `Theme Default` remains the deterministic static alternative.
- Program-derived color must not redefine focus, live, error, or tuned-state
  semantics.

The typography change approved on 2026-11-13 centres a program-independent
information block and caps the synopsis measure at 34 em. Title art is sized by
its visible pixels, with a full-width title line in the identity column as the
fallback. In the non-dense desktop band, `k = clamp((band − 28)/296, 1, 1.4)`
scales the title, episode line and title art. The synopsis scales by
`1 + (k − 1)/2`. Use the base title size when the scaled title exceeds one line.

UX assessment decision, 2026-11-13/14: keep the now-line behind cell text.
Place the idle watch prompt over a bottom gradient, 24 px from the bottom and
leading edges; keep channel identity in the information block. Keep the
toolbar filter in place and show counts for All channels, Favourites when
present, available source types, and libraries. On desktop **Back to player**
appears only during active playback; TV uses Back. Fit TV title logos using
their visible content within the approved information slot and keep the previous
decode visible during a size replacement. In the unavailable picture slot,
**Retry** uses the failed tune and **Next channel** follows the Guide filter
and channel order.

UI audit 2 decision, 2026-11-16. Guide uses a 72 px merged header when its existing
controls fit: channel filter and active-filter removal, earlier/Now/later, visible hours
and Search channels, followed by the flexible watching context, date/time and desktop
Back to player. Search replaces time navigation/hours while open; an applied search
remains open. Narrow or enlarged layouts retain the 80 px header and existing wrapping
controls. TV retains the picture/information size and allocates five or six rows using
its measured minimum; desktop retains its allocation policy. A live-accent h:mm pill
marks now. Opaque 6 px text backings mask the line under both cell lines. Remove the
airing dot; place the existing episode code 8 px after the title, use a 19 px second
line and hide text in cells narrower than four title characters. Keep the episode title
when its time range will not fit.

## Player: Protected Baseline

The OSD and its expanded Now Playing state are the approved structural
baseline. The October second pass in
[the decision log](../docs/desktop-ui-second-pass.md) supersedes the earlier
floating shelf, with matched real-Flutter renders approved before integration.
Future changes preserve this baseline unless separately approved.

Preserve:

- The bottom OSD's safe-area insets, title/status hierarchy, five standard
  actions and optional DVR controls, one inset elapsed/progress/time-left/Up next row
  (four-pixel line, 96 side insets and 54 above the bottom at 1920×1080),
  channel badge, keyboard focus, and auto-hide behavior. UX assessment decision,
  2026-11-13/14: on desktop, a labelled Guide control precedes the five standard
  actions. The controls adapt to the available width while preserving the
  title, status and timing stack. The channel badge opens the Mini Guide and
  reveals aligned channel step controls only on pointer hover. The channel badge enters
  on its own with a fade and small drop (fade only with Reduce Motion), and
  shows with the OSD and for about 4 s after a channel change.
  UI audit 2 decision, 2026-11-16: OSD title art may reach 168 high, episode text is 26,
  and actions use 26 icons with 22 semibold labels and regular secondary values, 60
  height, 20 horizontal padding, radius 6 and 6 gaps. More labels the existing Lineup
  menu action. The channel badge targets 52 high with 22 semibold identity; Playing is
  omitted as a state label.

- Now Playing expands the same bottom panel upward and shares its actions,
  Up Next, timing and progress. Preserve its poster/text split, with series art up to
  110 first, episode title 40, single metadata line, format chips, three-line 21
  synopsis up to 1040 wide, More info and at most four cast members. Poster is 248×372
  with radius 6; cast keeps portrait-above-text columns with 56 portraits, 20 names and
  18 roles. The top feather is 180 without changing overlay opacity. Runtime
  decoder/dimension facts belong in Diagnostics. UI audit 2 decision, 2026-11-16.
- UX assessment decision, 2026-11-13/14: Subtitles, Audio, and Sleep use an
  anchored popover for up to six choices (including Subtitle Off). Track lists
  with seven or more choices use the side panel. Fit the choice labels up to the width
  cap, omit key-hint lines, and keep the chosen presentation while the
  picker is open. Fit Sleep from its choices and header, including Close,
  within the same cap. Closing returns keyboard focus to its invoking action.
  UI audit 2 decision, 2026-11-16: picker titles are 36 in side panels and 26 in
  popovers; row primary/secondary text is 23 semibold/19 secondary. Audio retains layout
  and format; subtitles show supporting facts only to distinguish equal primary labels.
  TV focus fill has crisp edges.

- UX assessment decision, 2026-11-13/14: channel entry uses the overlay
  material at the top center, width up to 460, with 84 display digits above the matching
  22 semibold kind/name and a 19 secondary current-program/time-left line. The Mini
  Guide keeps five top-table rows, 84 high, a shared right-aligned number column with a
  46 reference floor, inline library/Watching, inset radius 6 focus and no key-hint
  line. Its scrim keeps the current opacity through every row and 24 beyond the last
  before fading. Desktop focus remains separate from Watching; TV keeps its standard
  fill. UI audit 2 decision, 2026-11-16.
- The shared themed overlay material, per-level transparency and feather only
  beyond text; preserve spacing, scalable controls and Reduce Motion behavior.
- On desktop, clicking the program block opens Now Playing.
- `I` or `Down` expands Now Playing; `I`, `Enter`, Close or Back/Esc collapses it
  to the OSD. Preserve artwork currentness and text/portrait fallbacks.

Any future Player structure proposal requires matched before/after renders from
the real Flutter widgets at 1280x720 and 1920x1080, using identical content,
clock, playback state, artwork state, and focused control. Change one variable
at a time and obtain separate approval before implementation.

Use a shared right-aligned number column with a 46 reference floor, scaled by platform
text settings and expanded only to the actual largest rendered number extent plus one
pixel when needed; keep type, style and icon/name gaps unchanged (UI audit 2 decision,
2026-11-16; Astra P-D3 measured-fit interpretation, 2026-11-17).

At short window heights, expanded Now Playing reserves the actual resting channel badge
bottom plus at least 8 logical pixels above the header and full Close hit region, using
the same badge text/scaler/padding/safe-inset metrics. Keep bottom anchoring, fixed
controls and timing/progress; reduce only the existing scrolling details allocation when
needed. The constraint is inert where the approved content already fits. UI audit 2
decision, 2026-11-16; Astra P-D4 adaptive-clearance decision, 2026-11-17.

## Approved desktop refinement campaign — design only

The [Desktop UI specification](../docs/desktop-ui-design-spec.md) records the
September 8, 2026 consolidated target and explicitly supersedes older corresponding
choices: PiP-only full Guide, five comfortable rows, current-and-upcoming timeline,
persistent search/library control, unified compact Lineup menu and the approved
onboarding/management/player-panel refinements. Use its
[visual manifest](../docs/design/desktop-ui/README.md) for selected compositions and
later prose refinements. These are approved designs, not implemented/validated claims.

Cinema Continuity tokens remain authoritative where the October second-pass
decision log is silent. The protected Player baseline above reflects the
separately approved expanded OSD; earlier shelf-specific rules are superseded.


## Settings and Lineup menu

UX assessment decision, 2026-11-13/14: Settings has a 16px supporting label
above its seven-section rail and one section headline. Detail labels share a
leading edge with 16px clearance within the TV focus fill. TV opens a category
after a 150ms dwell; Right enters the page, and Select opens it immediately.
Desktop categories still open on click or Enter.

UI audit 2 decision, 2026-11-16. Settings content is left-aligned and capped at 1040
canvas units except Subtitles. Appearance uses four theme swatches, wrapping to two
columns when needed, with the selected theme marked by the current accent ring.
Subtitles keeps Style, Size and Position on its main page and places Text, Edges,
Background and Window behind Customise; Back returns focus to that row. Its generated
preview is a proportional 16:9 picture on both pages. At a detail width of 1212 or more,
use a 620-unit controls column, 32-unit gap and preview capped at 800; below that, put
the preview above the controls.

The menu starts with the tuned channel identity and program title on separate
lines when available. Guide, Manage channels, Settings, and the profile/server
card follow. The tuned row opens the Player, and connection measurements belong
in Account and Diagnostics. TV Menu opens or closes this menu on ready screens.
On Manage channels it first closes an open row-action popup.

## September 12 collaborative Diagnostics refinement

Diagnostics42–45 use a local96px header and48px horizontal margins at1080p,
32px heading and16px supporting/action text. Keep one filled accent action for
Copy redacted report, with stable feedback space. UI audit 2 decision, 2026-11-16.
Present four equal summary cards for Playback, Video, Picture and Plex before optional
technical details and recent events. Unknown playback method has no supporting line.
Picture reports HDR for PQ/HLG, SDR for another reported transfer, and Unknown when
transfer is absent. Technical details use Application, Video output, Media signal and
platform-applicable Display columns. UX assessment decision, 2026-11-13/14: collapse the
summary
when idle. **Details** on the Player failure slate opens Diagnostics with
**Back to Player**. Settings opens Diagnostics with a link back to Support.
Show platform-supported facts in technical details and copied reports. Include
the Plex route and latency in technical details when measured. Reported media facts do
not establish physical HDR output.
Unavailable playback method omits the summary supporting line; unavailable stream
decisions remain explicit (UI audit 2 decision, 2026-11-16).

On Windows and macOS, keep one quiet inline “Per-stream handling · Unavailable” while those facts are not supplied. Expanded events align beneath the message and lay out labeled facts
horizontally with24px gaps/8px wrap spacing, muted labels and brighter16px values.
Keep event times local with seconds and accessible dates; arriving events must
not displace the user's current reading before explicit refresh.

The user replaced the Settings LINEUP ellipsis with a small18px hamburger;
Diagnostics uses the same neutral indicator. This amendment does not change other
menu content or unrelated dropdown chevrons. Evidence and exact conditional lock:
[Diagnostics approval](../docs/design/desktop-ui/approved/2026-09-12-diagnostics/evidence.json).
Adaptive and physical Windows validation remain separate pending work.
