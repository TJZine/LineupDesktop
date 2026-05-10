# Current Architecture State

> Established 2026-05-07. This is the canonical current-state architecture
> document for Lineup Desktop.

## Scope

Lineup Desktop is a new Windows-first Electron repository. It currently has a
minimal secure Electron shell frame plus docs, workflow, contract, and harness
scaffolding. There is no Plex integration, production native playback host,
scheduler, secure credential storage, copied TV UI, or installer implementation
yet.
RD-04 adds documentation and harness ownership for upstream behavior guardrails
only; it does not import product runtime code. RD-05 adds a disposable
dev-only external `mpv` POC tool and ignored redacted local evidence only; it
does not create production playback architecture. RD-06 adds dev-only Windows
native libmpv WID, render API, and app-owned native presentation spike modes
with ignored redacted local evidence only. The spike must use dummy visual
media, active-playback overlay/focus/fullscreen checks, and libmpv client API
evidence. The Windows WID and helper-owned render API proofs are blocked on
fullscreen video-surface evidence; render API also failed composition and
render-thread-discipline proof. The revised Windows app-owned native
presentation probe records fresh redacted proof under the stricter fullscreen,
cleanup, and render-thread semantics. Clean implementation re-review reported no
material blockers, so RD-06 can route RD-07 toward the app-owned native
presentation boundary. RD-07 adds the first main-owned Desktop player adapter
boundary core with a fakeable native host port and public-seam tests, runtime
main/preload player IPC delivery through a development/smoke fake host, and a
native-host process seam with lifecycle/reap, safe failure normalization, and
redaction tests. Windows closeout proof now covers the process seam with a real
spawned helper test double and reruns the RD-06 app-owned native-presentation
smoke as the native surface proof inherited by RD-07. Production player
commands still return renderer-safe unsupported failures until a later product
native-helper plan enables real Plex-backed playback. RD-07 does not wire
renderer UI, Plex stream setup, or a production native helper. RD-08 adds the
first deterministic Desktop stream policy fixture core under
`src/main/player/streamPolicy/*`. The policy is capability-driven and
fixture-only, with tests for direct play, direct stream, transcode, unsupported
decisions, audio/subtitle fallback, HDR/Dolby Vision, stable reasons, explicit
unknowns, and forbidden-field invariants. RD-08 does not contact Plex, add
secure storage, wire renderer UI, launch native playback, change
package/dependencies, or import/adapt upstream source.

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
| Preload bridge | `src/preload/index.cts` | Narrow shell/window/player bridge with runtime payload guards |
| Renderer shell | `src/renderer/index.ts` and `src/renderer/index.html` | Minimal unprivileged boot proof |
| Shell contract vocabulary | `src/contracts/shell.ts` | Renderer-safe shell/window/player bridge contract |
| Player contract vocabulary | `src/contracts/player.ts` | Renderer-safe player command, state, event, request id, capability profile, opaque track, error, diagnostic, IPC result, and runtime event-guard contract |
| IPC contract vocabulary | `src/contracts/ipc.ts` | Shell/window/player IPC literals plus renderer-safe player intent and forbidden-field vocabulary |
| Desktop player adapter boundary | `src/main/player/desktopPlayerAdapter.ts`, `src/main/player/nativePlayerHostPort.ts`, `src/main/player/nativePlayerHostProcess.ts`, and `src/main/player/playerIpc.ts` | Main-owned RD-07 adapter core, fakeable native-host process seam, and player IPC owner with renderer-intent validation, fakeable native-host event validation, request-id stale-event quarantine, real spawned helper test-double proof, helper/process failure normalization, cleanup/reap handling, runtime main/preload delivery, development/smoke fake-host activation, production unsupported/noop behavior, and renderer-safe diagnostics |
| Desktop stream policy | `src/main/player/streamPolicy/desktopStreamPolicy.ts` and `src/main/player/streamPolicy/types.ts` | Main/player-owned RD-08 deterministic fixture policy for capability-driven direct play, direct stream, transcode, unsupported decisions, audio/subtitle fallback, HDR/Dolby Vision handling, stable reason codes, explicit unknowns, and safe policy outputs; not wired to Plex runtime, renderer UI, native helper, secure storage, or runtime IPC |
| Redaction contract vocabulary | `src/contracts/redaction.ts` | Stub contract only |
| External `mpv` POC tool | `tools/mpv-poc/rd-05-external-mpv-poc.mjs` | Dev-only disposable RD-05 evidence harness |
| Native libmpv spike tool | `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs` | Dev-only disposable RD-06 Windows WID/render API evidence harness |
| Docs verifier | `tools/verify-docs.mjs` | Active |
| Redaction verifier | `tools/verify-redaction.mjs` | Active |

## Not Yet Implemented

- Plex auth/discovery/library/stream imports
- scheduler/channel imports
- Windows-proven production native playback helper
- Windows-proven production playback host
- production renderer player UI wiring
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
`window.lineupDesktop.window.setFullscreen(enabled)` from preload for shell
behavior. RD-07 also exposes the narrow `window.lineupDesktop.player` methods
`dispatch(envelope)`, `getSnapshot()`, `cleanup()`, and `onEvent(listener)`.
Player preload events are runtime-guarded before listener invocation. Runtime
commands remain backed by a development/smoke fake host by default, and the
main/player process seam is covered by in-memory and real spawned helper
test-double proof. Fullscreen requests map to the existing
`window.enterFullscreen` and `window.exitFullscreen` renderer intents.

## Roadmap

Use [`docs/roadmap/desktop-port-roadmap.md`](../roadmap/desktop-port-roadmap.md)
for the ordered port checklist after the current active plan or handoff is
understood. It records what comes next after the secure Electron shell
foundation, which original Lineup slices are likely reusable, which surfaces
must be newly designed for Desktop, and the global gates that block broad port
work.
