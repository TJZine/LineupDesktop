# UI Parity Audit: Lineup Desktop vs. WebOS Lineup

Updated: 2026-06-12

Target reference: `/Users/tristan/Software/Lineup`

Desktop target: `/Users/tristan/Software/LineupDesktop`

This audit checks the current Lineup Desktop renderer against the WebOS Lineup UI with style parity as the primary goal. It is based on direct source reads because Codanna returned stale Desktop symbol signatures and does not index the sibling WebOS source reliably for this comparison.

## Executive Summary

Lineup Desktop has the right product surfaces, but it is still not visually close enough to WebOS Lineup. The largest parity gaps are not copy or button labels; they are layout language, density, overlay choreography, artwork usage, focus treatment, and guide rendering.

The WebOS app is a 10-foot media UI: full-screen, dark glass, high-contrast focus, large type, edge-attached overlays, cinematic media art, and time-math guide cells. Desktop still often reads like a desktop control panel: bordered route cards, smaller tokens, generic buttons, summary definition lists, and simplified grid/list renderers.

Recommended direction: keep Desktop's Electron security/process architecture, but adopt WebOS's visual system and screen-specific composition patterns where the renderer only consumes safe view models.

## Parity Matrix

| Surface | Current Desktop Status | Recommendation |
| :--- | :--- | :--- |
| Global visual tokens | Major divergence | Align Desktop base tokens with WebOS 10-foot sizing, focus color, progress heights, scrim/radius vocabulary, and text scale. |
| App shell / route chrome | Major divergence | Reduce generic desktop rail/card chrome on media routes; use immersive full-screen surfaces closer to WebOS shells. |
| OSD panel | Moderate divergence | Keep Desktop actions that map to real desktop controls, but restyle to WebOS bottom OSD: thicker progress, monospace/tabular meta strip, clear-logo/title zone, direct Audio/Subtitles affordances. |
| Now Playing | Major divergence | Highest-impact visual gap. Add poster/backdrop/clear-logo support, metadata badges, richer description area, progress meta, and cast/art-ready layout. |
| Mini guide | Moderate divergence | Convert centered card into WebOS-style top shelf with five-row layout, channel icon slot, start time, progress, next title, and footer key hints. |
| Channel number overlay | Moderate divergence | Prefer WebOS auto-commit digit buffer and underscore presentation. Keep explicit buttons only as accessibility/dev fallback if needed. |
| Playback options | Moderate divergence | Convert centered modal into right-side rail. Add selected-track equalizer, meta pills, selected/focused left accent, and WebOS section rhythm. |
| Plex auth | Moderate divergence | Add QR card and per-character PIN boxes. Preserve Desktop main-owned auth boundaries. |
| Profile PIN | Major divergence | Replace inline text input with WebOS-style modal PIN slots and on-screen numpad for remote/gamepad parity. |
| Server selection | Minor to moderate divergence | Desktop now has live rows and server summaries. Add WebOS-like status/health pills and stronger auto-connect/latency affordances where data exists. |
| Channel setup | Major divergence | Current combined sequential Desktop setup is functional but not WebOS-like. Move toward a side-rail/category + detail flow only after runtime setup behavior is stable. |
| Settings | Major divergence | Desktop settings are still a flat route. Adopt WebOS left category rail, profile row, cardless detail pane, and WebOS toggle/select controls. |
| Guide / EPG | Major divergence | Replace fixed 6-column CSS grid with time-math layout: pixel widths, absolute positioning, live marker, edge masks, library pill, tickers, compact tiers. |

## Confirmed Findings

### 1. Global Styling Tokens Are Too Desktop-Compact

Desktop base tokens use smaller intermediate spacing and type than WebOS. Desktop has `--space-2: 6px`, `--space-4: 10px`, `--space-8: 18px`, `--button-min-height: 42px`, and base route/card styling in `/Users/tristan/Software/LineupDesktop/src/renderer/styles/base.css:1`. WebOS uses a clearer 10-foot scale with `--text-base: 20px`, `--text-2xl: 36px`, `--space-2: 8px`, `--space-4: 16px`, `--space-8: 32px`, `--progress-height-lg: 10px`, and `--focus-ring-width: 3px` in `/Users/tristan/Software/Lineup/src/styles/tokens.css:88`.

Recommendation: make token parity a first implementation unit before changing individual screens. Otherwise each screen will keep re-solving density, focus, and progress styling locally.

### 2. Desktop Route Chrome Is Still More "App Dashboard" Than "TV App"

Desktop wraps most surfaces inside a topbar, route rail, bordered screen panel, and fixed route card layout in `/Users/tristan/Software/LineupDesktop/src/renderer/styles/base.css:92` and `/Users/tristan/Software/LineupDesktop/src/renderer/staticDom.ts:94`. WebOS settings, onboarding, EPG, and overlays are screen-owned immersive surfaces, not nested cards.

Recommendation: keep route ownership, but restyle the primary routes into full-screen shells. The global route rail can remain a Desktop navigation fallback, but should not visually dominate player, guide, onboarding, settings, or playback overlay states.

### 3. Now Playing Is the Biggest Visual Parity Gap

WebOS builds a cinematic now-playing panel with backdrop, poster, clear logo, badges, playback summary, metadata, autoscrolling description, actor/cast regions, and progress meta in `/Users/tristan/Software/Lineup/src/modules/ui/now-playing-info/NowPlayingInfoOverlay.ts:41` and `/Users/tristan/Software/Lineup/src/modules/ui/now-playing-info/styles.core.css:22`. Desktop currently renders a small bottom-right text card with channel/title/subtitle/status and progress only in `/Users/tristan/Software/LineupDesktop/src/renderer/staticDom.ts:13` and `/Users/tristan/Software/LineupDesktop/src/renderer/styles/player-overlays.css:80`.

Recommendation: prioritize this after tokens. Even if live artwork URLs are not fully available yet, the DOM/CSS should be artwork-ready and render safe placeholder states. Use renderer-safe image descriptors only; do not expose tokenized Plex URLs.

### 4. OSD Is Structurally Functional But Not WebOS-Polished

WebOS OSD has a title/clear-logo area, direct Subtitles/Sleep/Audio actions, monospace tabular timecode, and a 10px progress bar in `/Users/tristan/Software/Lineup/src/modules/ui/player-osd/PlayerOsdOverlay.ts:354` and `/Users/tristan/Software/Lineup/src/modules/ui/player-osd/styles.meta-progress.css:1`. Desktop OSD has Mini guide, Options, number shortcuts, Close, audio/subtitle pills, and a 5px progress bar in `/Users/tristan/Software/LineupDesktop/src/renderer/staticDom.ts:20` and `/Users/tristan/Software/LineupDesktop/src/renderer/styles/player-overlays.css:120`.

Recommendation: style the Desktop OSD to match WebOS. Keep Mini guide and Options if those are the real Desktop actions, but surface Audio/Subtitles as first-class actions and make numeric entry a channel-number overlay concern rather than primary OSD chrome.

Skip: Sleep timer can be deferred if Desktop does not own an actual sleep-timer feature yet. Adding a fake WebOS button would be worse than a visible style divergence.

### 5. Mini Guide Should Become a Top Shelf

WebOS mini guide is edge-attached at the top, five rows, with channel number, branding icon slot, channel name, now title/start time, progress, next title, loading shimmer, and a footer remote hint in `/Users/tristan/Software/Lineup/src/modules/ui/mini-guide/MiniGuideOverlay.ts:162` and `/Users/tristan/Software/Lineup/src/modules/ui/mini-guide/styles.core.css:5`. Desktop renders a centered modal-like card with previous/next buttons and article rows in `/Users/tristan/Software/LineupDesktop/src/renderer/staticDom.ts:49` and `/Users/tristan/Software/LineupDesktop/src/renderer/routeDom.ts:395`.

Recommendation: change the Desktop mini guide to the WebOS top shelf. Keep mouse/click controls accessible, but visually subordinate them to remote/key hints.

### 6. Playback Options Should Be a Side Rail

WebOS playback options open as a right-side rail and selected rows use an animated equalizer plus meta pills in `/Users/tristan/Software/Lineup/src/modules/ui/playback-options/PlaybackOptionsModal.ts:130` and `/Users/tristan/Software/Lineup/src/modules/ui/playback-options/styles.core.css:17`. Desktop uses a centered modal with summary cards, two columns, extra volume/rate controls, and no equalizer in `/Users/tristan/Software/LineupDesktop/src/renderer/staticDom.ts:63` and `/Users/tristan/Software/LineupDesktop/src/renderer/routeDom.ts:488`.

Recommendation: move to the WebOS side rail. Add the equalizer, meta pill styling, selected/focused accent treatment, and one-column section flow. Keep Desktop-only volume/rate controls only if they are backed by real player commands; otherwise drop them from the parity target.

### 7. Auth and Profile Selection Need Remote-First Input

WebOS auth uses a QR card and per-character PIN boxes in `/Users/tristan/Software/Lineup/src/modules/ui/auth/AuthScreen.ts:99` and `/Users/tristan/Software/Lineup/src/styles/shell.onboarding.auth.css:12`. Desktop displays the PIN as a single `strong` inside the channel setup flow in `/Users/tristan/Software/LineupDesktop/src/renderer/plexRuntimeDom.ts:85`.

WebOS profile PIN uses a modal with four PIN slots and a 0-9 on-screen numpad in `/Users/tristan/Software/Lineup/src/modules/ui/profile-select/ProfileSelectScreen.ts:147` and `/Users/tristan/Software/Lineup/src/modules/ui/profile-select/styles.pin-modal.css:1`. Desktop uses an inline numeric text input in `/Users/tristan/Software/LineupDesktop/src/renderer/staticDom.ts:216`.

Recommendation: implement the WebOS auth PIN/QR visuals and profile PIN modal. This is important for style parity and for non-keyboard desktop living-room use.

Skip: do not copy WebOS direct token/fetch behavior. Desktop must keep auth, credentials, and raw Plex connection data main-owned.

### 8. Server Selection Is Closer Than the Current Audit Claimed

Desktop now renders live profile rows and server rows with ownership/connection/health summaries in `/Users/tristan/Software/LineupDesktop/src/renderer/plexRuntimeRows.ts:32`. WebOS has richer status pills, auto-connect hint, glyph, and health/latency styling in `/Users/tristan/Software/Lineup/src/modules/ui/server-select/ServerSelectScreen.ts:111` and `/Users/tristan/Software/Lineup/src/modules/ui/server-select/styles.css:12`.

Recommendation: treat this as a style polish task, not a full rebuild. Add status pill shapes, stronger selected/connected treatment, and latency text only when the Desktop runtime can safely provide it.

Skip: do not invent latency badges without measured latency. A decorative latency badge would mislead the user.

### 9. Settings and Channel Setup Are Functionally Ahead But Visually Behind

WebOS settings use a full-screen overlay with left category rail, animated entry, profile switch row, and cardless detail pane in `/Users/tristan/Software/Lineup/src/modules/ui/settings/SettingsScreen.ts:107` and `/Users/tristan/Software/Lineup/src/modules/ui/settings/styles.core.css:1`. Desktop settings are a flat screen route with summary cards, generated sections, and shell controls in `/Users/tristan/Software/LineupDesktop/src/renderer/staticDom.ts:151` and `/Users/tristan/Software/LineupDesktop/src/renderer/styles/workflow-screens.css:135`.

WebOS channel setup is a multi-step setup shell with dedicated presenters and setup styling in `/Users/tristan/Software/Lineup/src/modules/ui/channel-setup/ChannelSetupScreen.ts:64`. Desktop channel setup now combines Plex onboarding, library browse, build review, and metadata preview in one long page in `/Users/tristan/Software/LineupDesktop/src/renderer/staticDom.ts:180` and `/Users/tristan/Software/LineupDesktop/src/renderer/styles/plex-onboarding.css:24`.

Recommendation: bring settings to WebOS rail parity earlier than channel setup. Channel setup should wait until product setup behavior is stable enough to avoid redesigning the flow twice.

Skip: do not copy WebOS drag/drop or exact channel-reorder UI until Desktop has the same scheduler/channel ordering contract. The style can be WebOS-like without importing unsupported interaction semantics.

### 10. Guide / EPG Needs a Real Parity Pass

Desktop guide has improved since the earlier audit: it now has a classic header, now-watching banner, focus hints, info detail, and row/cell view model state in `/Users/tristan/Software/LineupDesktop/src/renderer/routeDom.ts:207`. However, it still uses a fixed six-column CSS grid and `grid-column` spans in `/Users/tristan/Software/LineupDesktop/src/renderer/routeDom.ts:297` and `/Users/tristan/Software/LineupDesktop/src/renderer/styles/guide-epg.css:180`.

WebOS computes real pixel positions from schedule time and duration in `/Users/tristan/Software/Lineup/src/modules/ui/epg/view/EPGProgramCellPosition.ts:4`, renders absolute cells with text shifting, compact tiers, episode badges, live badges, tickers, and progress in `/Users/tristan/Software/Lineup/src/modules/ui/epg/view/cells/EPGCellRenderer.ts:52`, and styles library tabs, sticky header, edge masks, and a current-time indicator in `/Users/tristan/Software/Lineup/src/modules/ui/epg/styles.grid.css:145` and `/Users/tristan/Software/Lineup/src/modules/ui/epg/styles.cells.css:1`.

Recommendation: make EPG parity its own focused plan. This is not just CSS; Desktop needs renderer-safe guide presentation data with pixel positioning, visible-window clipping, focused overflow behavior, live/current marker state, and library tabs.

Skip: defer aggressive virtualization and background schedule warming unless Desktop guide performance actually requires it. The visual parity need is time-math layout and cell presentation first, not the whole WebOS runtime stack.

## Recommended Implementation Sequence

1. **Visual token parity foundation**
   - Align `base.css` tokens with WebOS text scale, spacing, focus, progress, scrim, and radius vocabulary.
   - Verify route/player/guide/settings still fit at desktop and TV-ish window sizes.

2. **Overlay parity package**
   - Now Playing artwork-ready panel.
   - OSD visual restyle.
   - Mini guide top shelf.
   - Playback options right rail with equalizer.
   - Channel number auto-commit visual buffer.

3. **Onboarding input parity**
   - Auth QR/PIN boxes.
   - Profile PIN modal/numpad.
   - Server status pill polish.

4. **Settings rail parity**
   - Replace flat settings route with left rail + detail pane.
   - Preserve Desktop support-bundle and persistence boundaries.

5. **Guide parity plan**
   - Implement time-math guide layout and WebOS-like cell presentation.
   - Add library pill/tabs only from safe library state.
   - Add visual/browser proof because this is the highest-risk layout surface.

6. **Channel setup parity pass**
   - Recompose the long setup page into a WebOS-like staged shell after setup behavior stabilizes.
   - Keep Desktop-specific build/replacement semantics visible, but style them inside WebOS-like panels.

## Intentional Divergences To Keep

1. **Renderer security boundary**
   - Keep raw tokens, tokenized URLs, Plex connection details, secure storage, and transport in main-owned seams. WebOS renderer patterns must be adapted into renderer-safe view models.

2. **No webOS compatibility shims**
   - Do not add old path barrels or class-name compatibility wrappers just to mirror source structure. Copy visual behavior intentionally into Desktop-owned files.

3. **No fake controls for missing features**
   - Sleep timer, latency badges, channel reordering, cast headshots, and clear-logo/artwork should appear only when backed by safe data or an honest empty/placeholder state.

4. **Desktop diagnostics/support actions**
   - Keep Desktop-only support bundle export and diagnostic states. They are not WebOS parity features, but they are valid Desktop product requirements.

5. **Mouse/keyboard accessibility**
   - Preserve clickable controls and text input fallbacks where useful, but do not let them drive the primary visual language. The main style target should be remote/gamepad/10-foot parity.

## Verification Notes

- Directly read current Desktop renderer files under `src/renderer/**`.
- Directly read WebOS UI files under `/Users/tristan/Software/Lineup/src/modules/ui/**` and `/Users/tristan/Software/Lineup/src/styles/**`.
- Codanna retry found stale Desktop symbol signatures and did not cover WebOS source, so direct file reads are the audit source of truth.
- This document changes recommendations only; source implementation still needs separate plans and visual/browser proof.
