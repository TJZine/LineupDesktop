# Renderer Architecture

Packages 0–8 of the WebOS UI parity reopen are complete. The current renderer
uses runtime-backed onboarding, setup, Settings, Guide, Player, and overlay
owners and has fresh local exact-viewport, media-query, and fullscreen
continuity proof. RD-27 is the next Tier 3 planning target; Windows operational
proof, including the mandatory three-row Package 6 operator-assisted
fullscreen audit, remains pending. Historical completed units below describe
their bounded implementation history only.

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
