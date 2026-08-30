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

## Player: Protected Baseline

The current production OSD and Now Playing shelf are authoritative layouts.
The Cinema Continuity direction applies color roles only unless a later
structural proposal is approved separately.

Preserve:

- OSD surface geometry, safe-area insets, vertical placement, identity block,
  title/status hierarchy, action grouping and order, timing row, full-width
  progress lane, channel bug, focus behavior, and auto-hide behavior.
- Now Playing shelf width and height rules, poster split, information order,
  badges, cast treatment, progress placement, channel bug, entry/exit motion,
  and input behavior.
- Existing Player radii and spacing, even where other Cinema surfaces adopt the
  8px system radius.

The approved Player treatment changes only warm-black scrims and surfaces,
aged-paper text hierarchy, sepia borders/tracks, and projector-amber progress
and interaction color.

Any future Player structure proposal requires matched before/after renders from
the real Flutter widgets at 1280x720 and 1920x1080, using identical content,
clock, playback state, artwork state, and focused control. Change one variable
at a time and obtain separate approval before implementation.
