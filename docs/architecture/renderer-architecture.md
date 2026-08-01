# Renderer Architecture

Packages 0–8 of the WebOS UI parity reopen are complete. The current renderer
uses runtime-backed onboarding, setup, Settings, Guide, Player, and overlay
owners and has fresh local exact-viewport, media-query, and fullscreen
continuity proof for the historical Package 8 surface. WS3 has landed its
version-2 Settings owners and closes its local renderer gate through final
product checkpoint `87662b5`; prior Unit 3C-D `5f368d4`, viewport repair
`77d09ad`, test-only harness checkpoint `f0e2817`, and reviewed focus plan
`c59124a` remain accepted history. Unit 3C-D adds honest
missing-output presentation without a public contract or persistence change.
Unit 3D is accepted and WS3's local renderer gate is closed. WS4 targeted
scope-load/planning is active; product/test/package/config edits require its own
decision-complete plan and fresh approval of an exact first unit. Windows operational proof, including
the mandatory three-row Package 6 operator-assisted fullscreen audit, remains
pending. Historical completed units below describe their bounded
implementation history only.

This document owns the detailed renderer shell breakdown referenced by
[`CURRENT_STATE.md`](./CURRENT_STATE.md). Keep the current-state table concise;
record renderer module ownership and completed renderer architecture units here.

## Owner Surface

The renderer shell currently spans:

- `src/renderer/index.ts`
- `src/renderer/staticDom.ts`
- `src/renderer/domBindings.ts`
- `src/renderer/focusDom.ts`
- `src/renderer/routeDom.ts`
- `src/renderer/index.html`
- `src/renderer/styles.css`
- `src/renderer/styles/*`
- `src/renderer/navigation.ts`
- `src/renderer/workflow.ts`
- `src/renderer/settingsSetup.ts`
- `src/renderer/settings/settingsRuntime.ts`
- `src/renderer/settings/settingsPlaybackLifecycle.ts`
- `src/renderer/settings/audioSetupRuntime.ts`
- `src/renderer/settings/audioSetupDom.ts`
- `src/renderer/epg.ts`
- `src/renderer/overlays.ts`
- `src/renderer/overlayViewModels.ts`
- `src/renderer/playerOverlayPresentation.ts`
- `src/renderer/playerOverlayController.ts`
- `src/renderer/playerOverlayDom.ts`
- `src/renderer/playerBridgeSubscription.ts`
- `src/renderer/guidePresentation.ts`
- `src/renderer/guidePresentationPolling.ts`
- `src/renderer/guideTuneController.ts`
- `src/renderer/desktopInput.ts`
- `src/renderer/desktopCursor.ts`

## Current Behavior

The renderer owns screen and overlay DOM/CSS, route/focus/input state,
renderer-safe view-model translation, timer/listener cleanup, stale-result
rejection, and narrow intent dispatch through `window.lineupDesktop`. Main-owned
Plex, channel, scheduler, Settings, and player bridges supply the runtime truth.
The reachable product routes no longer depend on deterministic Guide/player
presentation fixtures, default overlay stacks, proxy Guide controls, or
session-only Settings.

Guide projection comes from persisted-channel scheduler state and distinguishes
loading, no-channel, no-program, failure, and ready states. Player presentation
and overlay precedence come from safe player snapshots, channel status, and
Guide presentation; overlay timers, command generations, focus return, and
cleanup remain renderer-owned. `playerOverlayDom.ts` owns the semantic overlay
hierarchy and dynamic menu rows, while the shared, information, and menu
stylesheets own their separate visual families. Reduced-motion, forced-colors,
exact viewport, focus, and local fullscreen continuity proof passed at Package 8
closeout.

Renderer code must remain unprivileged. It must not import Electron, Node, main,
preload, native-helper, Plex transport, persisted secrets, raw auth headers,
tokenized URLs, native handles, or privileged diagnostics.

Packages 5–8 did not add renderer privilege, raw Plex access, token-bearing
media state, native handles, new IPC/preload methods, persistence custody, or
native-helper ownership.

## WS3 Settings Renderer Ownership

WS3 replaces the former three-category surface with exactly seven categories:
Audio & Subtitles, Playback & HDR, Appearance, Guide, Account, Developer, and
Recovery. `settingsRuntime.ts` owns renderer-safe whole-snapshot loading,
coalesced compare-and-swap replacement, one conflict rebase, failure state, and
capability-gated nonmutation. `settingsSetup.ts` owns closed category/control
view models. `audioSetupRuntime.ts` owns first-run safe audio rows and System
Default completion. The persistent Switch Profile action reuses the existing
renderer-safe Plex Home flow; it adds no Plex contract or privilege.

`settingsPlaybackLifecycle.ts` owns route-scoped guarded pause/resume. It sends
the exact observed snapshot request id and retains resume custody only for the
same successfully paused request. Theme projection and the closed
Now Playing auto-hide value remain renderer-owned; the overlay controller
receives only the duration and owns its timers.

Inactive Settings articles are semantically hidden/inert and excluded by the
existing focus registry. Focus tests cover active enabled controls, the
Recovery-to-Switch Profile edge, and direct audio-setup primary focus. However,
the controller's first local viewport inspection at approximately 900×700
observed that focus can move from Recovery to Switch Profile while the
non-scrolling rail leaves most of the button below the visible viewport. This
was an implementation defect routed back to Unit 3C, not consolidated Windows
or visual proof debt. Reviewed repair `77d09ad` makes the rail scrollable and
scrolls active Settings focus to its nearest visible position. It passes the
focused/full Unit 3C gates, clean re-review, and repeated local inspection at
1280×720 and approximately 900×700; the latter shows the complete Switch
Profile button and focus ring and preserves Up back to Recovery. Non-Settings
global focus does not trigger this scrolling.

Unit 3C-D checkpoint `5f368d4` makes current audio enumeration authoritative
for presentation without making it authoritative for persistence. When a saved
opaque output id is absent from injected safe rows, `audioSetupRuntime.ts`
selects the visible System Default fallback and explains that the saved output
is unavailable, while retaining the saved id until explicit completion.
`settingsSetup.ts` labels a non-null preference as a saved output whose current
availability is checked in Audio Output. This injected missing-row behavior is
local proof; real Windows disappearance/relaunch and playback application
remain `WS3-PROOF-01`.

Unit 3C-F checkpoint `87662b5` derives each Settings category's Right entry
from the current hidden/disabled/inert-filtered focus collection and existing
category order. Audio & Subtitles therefore reaches the first enabled detail
under the conservative production set; a category without enabled detail
self-contains instead of falling into another category. Detail Left ownership
and non-Settings/global behavior remain unchanged. Reviewed proof passed 17/17
focused and 265/265 aggregate after plan amendment `c59124a` corrected the
baseline from 264/264 to expected 265/265.

No current-upstream paired Settings visual inspection has passed. The local
viewport proof does not close paired-visual rows; Windows/native-video
continuity remains `WS3-PROOF-06`.

## ARCH-01 Renderer Units

ARCH-01 Unit 1 keeps `index.ts` as the startup/orchestration entrypoint and
splits renderer DOM querying/action readers, focus DOM registration/rendering,
and route/workflow/EPG/overlay DOM rendering into same-owner renderer modules
before RD-14 input/window behavior.

ARCH-01 Unit 2 keeps `index.html` and `styles.css` as static entry assets while
moving bulky trusted screen markup to `staticDom.ts` and CSS rule groups to
copied same-origin CSS modules under `src/renderer/styles/*`.

ARCH-01 Unit 5 keeps `overlays.ts` as the renderer overlay action/state
entrypoint and splits renderer-safe overlay fixtures, view models, passive
overlay focus projection, and now-playing progress clamping into
`overlayViewModels.ts` before RD-15 native-video overlay integration.

## RD-15 UI Over Native Video Integration

RD-15 is historical. It first established the player surface as the
presentation background for renderer overlays and routes and proved the named
surfaces over active native video in a dev-only Windows harness. Packages 5–8
later replaced the reachable Guide/player fixture presentation with the current
runtime-backed owners and exact local proof described above.

The durable proof remains scoped to renderer composition and the dev-only
harness. It is not a production playback implementation and does not make
renderer code responsible for Plex transport, native handles, secrets, or
product playback setup.

## Verification

Renderer shell changes generally require `npm run verify` before closeout
because they affect source, architecture linting, smoke reachability, docs, and
redaction surfaces. For docs-only updates to this file, `npm run verify:docs` is
the narrow proof unless the change also alters source behavior.
