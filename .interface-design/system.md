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
  place the logo first, then the wordmark. Preserve the approved Arial Regular
  uppercase/letter-spaced wordmark treatment in the configuration header. This
  September 9 refinement changes order only; menu hamburger/chevron icons and
  standalone branding retain their own roles.

## First-run setup

UX assessment decision, 2026-11-13/14. A sole reachable server opens
Choose libraries directly on unresolved first run. In the server picker, show
one “Unreachable” status with “Retry” on the row whose reachability probe
failed. The first Libraries step uses origin-specific Back copy on desktop
and the contextual Back action on TV.

## Channel identity and setup

UX assessment decision, 2026-11-13/14. The channel number and outlined
TV, Film or mixed-media glyph stay visible when the name truncates. A
single-source library tag disambiguates equal names from different libraries.
Use supporting ink for the glyph and library tag, along with one accessible
label. Keep the existing surface geometry. Wrap between words where the
surface allows multiple lines. Use a one-line ellipsis when a word exceeds
the name column. Where the Guide or Mini Guide has a spare line, move a
library tag there when it cannot fit beside the name. Keep the full library
in the accessible label.

Setup names its steps Libraries, Channels and Review. Choose channels adds
the saved Channel order choice and retains two-column source rows with at
least 16 px of TV focus padding.

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

## Player: Protected Baseline

The OSD and its expanded Now Playing state are the approved structural
baseline. The October second pass in
[the decision log](../docs/desktop-ui-second-pass.md) supersedes the earlier
floating shelf, with matched real-Flutter renders approved before integration.
Future changes preserve this baseline unless separately approved.

Preserve:

- The bottom OSD's safe-area insets, title/status hierarchy, five standard
  actions and optional DVR controls, timing row, full-width progress lane,
  channel badge, keyboard focus, and auto-hide behavior. UX assessment decision,
  2026-11-13/14: on desktop, a labelled Guide control precedes the five standard
  actions. The controls adapt to the available width while preserving the
  title, status and timing stack. The channel badge opens the Mini Guide and
  reveals aligned channel step controls only on pointer hover. The channel badge enters
  on its own with a fade and small drop (fade only with Reduce Motion), and
  shows with the OSD and for about 4 s after a channel change.
- Now Playing expands the same bottom panel upward and shares its actions,
  Up Next, timing and progress. Preserve its poster/text split, compact title
  artwork, single metadata line, format chips, three-line synopsis, and at most
  four cast members with roles in one row. Runtime decoder/dimension facts
  belong in Diagnostics.
- UX assessment decision, 2026-11-13/14: Subtitles, Audio, and Sleep use an
  anchored popover for up to six choices (including Subtitle Off). Track lists
  with seven or more choices use the side panel. TV keeps selected-choice
  focus and returns to the invoking action.
- UX assessment decision, 2026-11-13/14: channel entry uses the overlay
  material at the top center, with 48 px digits above a matched 20 px channel
  identity. The Mini Guide paints a standard desktop focus border separately
  from Watching and keeps the existing TV fill.
- The shared themed overlay material, per-level transparency and feather only
  beyond text; preserve spacing, scalable controls and Reduce Motion behavior.
- `I` or `Down` expands Now Playing; `I`, `Enter`, Close or Back/Esc collapses it
  to the OSD. Preserve artwork currentness and text/portrait fallbacks.

Any future Player structure proposal requires matched before/after renders from
the real Flutter widgets at 1280x720 and 1920x1080, using identical content,
clock, playback state, artwork state, and focused control. Change one variable
at a time and obtain separate approval before implementation.

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


## September 12 collaborative Diagnostics refinement

Diagnostics42–45 use a local96px header and48px horizontal margins at1080p,
32px heading and16px supporting/action text. Keep one filled accent action for
Copy redacted report, with stable feedback space. Present the four summary groups
Playback, Video, Media signal and Plex before optional grouped technical details
and recent events. Reported media facts do not establish physical HDR output;
unavailable method/stream decisions must remain explicit.

Use one quiet inline “Per-stream handling · Unavailable” while those facts are
not supplied. Expanded events align beneath the message and lay out labeled facts
horizontally with24px gaps/8px wrap spacing, muted labels and brighter16px values.
Keep event times local with seconds and accessible dates; arriving events must
not displace the user's current reading before explicit refresh.

The user replaced the Settings LINEUP ellipsis with a small18px hamburger;
Diagnostics uses the same neutral indicator. This amendment does not change other
menu content or unrelated dropdown chevrons. Evidence and exact conditional lock:
[Diagnostics approval](../docs/design/desktop-ui/approved/2026-09-12-diagnostics/evidence.json).
Adaptive and physical Windows validation remain separate pending work.
