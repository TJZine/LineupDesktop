# Current Architecture State

> Established 2026-05-07. This is the canonical current-state architecture
> document for Lineup Desktop.

## Scope

Lineup Desktop is a new Windows-first Electron repository. It currently has a
minimal secure Electron shell frame plus docs, workflow, contract, and harness
scaffolding. There is no Plex integration, native playback host, scheduler,
secure credential storage, copied TV UI, or installer implementation yet.
RD-04 adds documentation and harness ownership for upstream behavior guardrails
only; it does not import product runtime code. RD-05 adds a disposable
dev-only external `mpv` POC tool and ignored redacted local evidence only; it
does not create production playback architecture. RD-06 adds a dev-only Windows
native libmpv spike tool and ignored redacted local evidence only. The spike
must use dummy visual media, active-playback overlay/focus/fullscreen checks,
and libmpv client API evidence. Current Windows WID and helper-owned render API
proofs are blocked on fullscreen video-surface evidence; render API also failed
composition and render-thread-discipline proof. RD-06 therefore does not create
a production playback host or settle the RD-07 native surface direction.

## Product Invariants

- Preserve the core Lineup product concept: local Plex-backed virtual channels
  with deterministic scheduling and a TV-style DOM UI.
- Keep the desktop app local-first with no Lineup cloud backend.
- Keep the renderer unprivileged.
- Keep persistent Plex credentials outside the renderer.
- Keep playback capability-driven; webOS browser playback assumptions do not
  define desktop support.
- Keep workflow and verification rules active before product implementation.

## Current Owners

| Surface | Current owner | Status |
| --- | --- | --- |
| Workflow/control plane | `AGENTS.md` and `docs/AGENTIC_DEV_WORKFLOW.md` | Scaffolded |
| Architecture truth | `docs/architecture/CURRENT_STATE.md` | Scaffolded |
| Port roadmap | `docs/roadmap/desktop-port-roadmap.md` | Scaffolded |
| Upstream behavior guardrails | `docs/architecture/upstream-behavior-guardrails.md` | RD-04 docs/harness owner |
| Repo genesis decision | `docs/architecture/desktop-repo-genesis-adr.md` | Accepted |
| Import provenance | `docs/architecture/import-ledger.md` | Scaffolded |
| Electron main shell | `src/main/index.ts` and `src/main/protocol.ts` | Minimal secure shell frame |
| Preload bridge | `src/preload/index.cts` | Narrow shell/window bridge |
| Renderer shell | `src/renderer/index.ts` and `src/renderer/index.html` | Minimal unprivileged boot proof |
| Shell contract vocabulary | `src/contracts/shell.ts` | Renderer-safe shell/window bridge contract |
| Player contract vocabulary | `src/contracts/player.ts` | Renderer-safe player command, state, event, request id, capability profile, opaque track, error, and diagnostic contract |
| IPC contract vocabulary | `src/contracts/ipc.ts` | Shell/window IPC literals plus renderer-safe player intent and forbidden-field vocabulary |
| Redaction contract vocabulary | `src/contracts/redaction.ts` | Stub contract only |
| External `mpv` POC tool | `tools/mpv-poc/rd-05-external-mpv-poc.mjs` | Dev-only disposable RD-05 evidence harness |
| Native libmpv spike tool | `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs` | Dev-only disposable RD-06 Windows evidence harness |
| Docs verifier | `tools/verify-docs.mjs` | Active |
| Redaction verifier | `tools/verify-redaction.mjs` | Active |

## Not Yet Implemented

- Plex auth/discovery/library/stream imports
- scheduler/channel imports
- native playback helper
- production playback host or adapter
- player runtime adapter or preload/main player IPC
- secure storage implementation
- packaging/signing/update pipeline

## Electron Shell Frame

The first shell frame registers the `lineup` scheme before app readiness as a
standard secure scheme and serves the renderer only from
`lineup://shell/index.html`. Electron main owns the `BrowserWindow`, local
protocol handler, containment handlers, and shell/window IPC authorization.

The renderer remains unprivileged. It receives only
`window.lineupDesktop.shell.getCapabilities()`,
`window.lineupDesktop.shell.onStatusChanged(listener)`, and
`window.lineupDesktop.window.setFullscreen(enabled)` from preload. Fullscreen
requests map to the existing `window.enterFullscreen` and
`window.exitFullscreen` renderer intents.

## Roadmap

Use [`docs/roadmap/desktop-port-roadmap.md`](../roadmap/desktop-port-roadmap.md)
for the ordered port checklist after the current active plan or handoff is
understood. It records what comes next after the secure Electron shell
foundation, which original Lineup slices are likely reusable, which surfaces
must be newly designed for Desktop, and the global gates that block broad port
work.
