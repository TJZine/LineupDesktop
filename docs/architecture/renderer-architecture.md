# Renderer Architecture

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

## Current Behavior

RD-13 Units 1 through 6 establish the unprivileged app shell/navigation
foundation, fake-backed route/workflow skeleton, settings/channel setup details,
fake-backed EPG, fake-backed player overlays, and CSS/theme style surface.

The renderer owns primary route rail behavior, screen containers,
renderer-local route/focus/workflow/settings/EPG/overlay state, Desktop key
mapping, accessible primary navigation, renderer-safe fake view models,
local-only setup/guide/overlay actions, deterministic UTC fake schedule
formatting, overlay focus fallback behavior, CSS token/theme hooks,
reduced-motion and forced-colors policies, responsive constraints, and smoke
reachability/style proof.

Renderer code must remain unprivileged. It must not import Electron, Node, main,
preload, native-helper, Plex transport, persisted secrets, raw auth headers,
tokenized URLs, native handles, or privileged diagnostics.

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

## Verification

Renderer shell changes generally require `npm run verify` before closeout
because they affect source, architecture linting, smoke reachability, docs, and
redaction surfaces. For docs-only updates to this file, `npm run verify:docs` is
the narrow proof unless the change also alters source behavior.
