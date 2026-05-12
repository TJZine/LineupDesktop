# Current Architecture State

> Established 2026-05-07. This is the canonical current-state architecture
> document for Lineup Desktop.

## Scope

Lineup Desktop is a new Windows-first Electron repository. It currently has a
secure Electron shell frame, the RD-13 renderer app shell/navigation, workflow,
settings/channel setup, fake-backed EPG, fake-backed overlay, and CSS/theme
style surfaces, docs, workflow, contract, harness scaffolding, and main-owned
Plex auth/discovery/library domain seams. There is no production native playback
host, copied/adapted upstream TV UI source, installer implementation, live Plex
transport wiring, or renderer Plex API yet.
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
unknowns, and forbidden-field invariants. Windows closeout adds a conservative
RD-06/RD-07 capability/sample matrix and keeps container, codec, audio,
subtitle, direct stream, transcode, track switching, HDR, Dolby Vision, and
Plex HTPC parity as unknown or unsupported where the Windows proof does not
establish them. RD-08 does not contact Plex, add secure storage, wire renderer
UI, launch native playback, change package/dependencies, or import/adapt
upstream source. RD-09 adds the first main-owned secure storage and persistence
boundary core under `src/main/persistence/*`, plus renderer-safe persistence
summary contracts in `src/contracts/persistence.ts`. The boundary uses an
injected Electron `safeStorage` codec seam, app-data path resolver,
file-backed encrypted Plex credential records, selected-server state,
unavailable/corrupt classification, fail-closed behavior with no plaintext
fallback, and tests for renderer-safe snapshots and forbidden fields. RD-09
does not wire Plex auth/discovery/library runtime, preload or renderer APIs,
network transport, scheduler/channel persistence, backup/restore
implementation, package/dependency changes, or copied/adapted upstream source.
RD-10 adds main-owned Plex library, auth, discovery, selected-server, and
renderer-safe Plex contract seams under `src/main/plex/*` and
`src/contracts/plex.ts`. The imported/adapted upstream behavior is kept behind
injected transports and RD-09 storage adapters: library parsing is metadata and
summary only, auth uses injected transport plus fail-closed credential storage,
and discovery restores by persisted server id plus fresh probing while keeping
connection details in main-owned memory only. RD-10 does not wire live Plex
network transport, preload/renderer Plex APIs, `src/main/index.ts`
composition, real Electron safeStorage/app paths, package/dependency changes,
stream resolver/runtime playback URL setup, scheduler/channel persistence, or
backup/restore implementation.
RD-11 adds pure scheduler and channel/content domains plus a main-owned channel
persistence adapter; these owners remain runtime-free, use injected
clocks/timers/library/persistence ports, and keep Electron, Node, browser
globals, live Plex transport, raw Plex payloads, auth headers, tokenized URLs,
and native playback details out of domain state. RD-12 adds the first
main-owned Plex-to-player runtime path through
`src/main/player/plexPlaybackRuntime.ts`, `src/main/plex/streamResolver.ts`,
`src/main/player/plexPlaybackBridge.ts`, and
`src/main/player/plexPlaybackComposition.ts`. The runtime resolves current
scheduled/channel media through injected main-owned seams, applies the RD-08
policy, dispatches renderer-safe load payloads through the RD-07 player adapter
boundary, and owns PMS cleanup for stop, switch, error, logout, server change,
profile change, helper crash, teardown, failed resolver/player paths, stale
events, and rejected leases. RD-12 keeps private Plex playback descriptors and
PMS lease custody out of renderer-facing contracts and does not add
preload/renderer Plex APIs, live transport composition, real Electron
safeStorage/app-path wiring, production native-helper playback, packaging, or
additional copied/adapted upstream product code. RD-13 Unit 1 adds a
renderer-owned app shell/navigation foundation under `src/renderer/**`: primary
route rail, player/guide/settings/channel-setup screen containers,
renderer-local route and focus state, Desktop key mapping, accessible primary
navigation, and Node-safe navigation tests. It also resolves the existing
sandboxed-preload smoke blocker by keeping preload guard vocabulary
single-file-compatible with Electron sandboxed preload runtime while preserving
the existing shell/window/player preload API shape and smoke containment checks.
RD-13 Unit 2 adds a renderer-local fake-backed route/workflow skeleton for the
player, guide, settings, and channel-setup routes. It uses renderer-safe fake
view models, local route action transitions, and Node-safe workflow tests; it
does not import domain code, add preload/main contracts, contact Plex, persist
settings, or wire runtime playback. RD-13 Unit 3 adds renderer-local
settings/channel setup details with fake settings sections, channel setup draft
state, local-only settings/setup actions, validation copy, and Node-safe tests.
It does not persist settings, use browser storage, contact Plex, add selected
server runtime, or import domain code. RD-13 Unit 4 adds a renderer-local
fake-backed EPG surface with deterministic UTC fake schedule formatting,
schedule slots, program span calculation, guide detail/grid rendering, guide
route smoke reachability assertions, and Node-safe EPG tests. It does not import
domain code, contact Plex, add renderer/preload APIs, load remote/tokenized
assets, or wire scheduler/runtime playback. RD-13 Unit 5 adds renderer-local
fake-backed player overlays: OSD controls, now-playing, mini guide, channel
number entry, channel badge, playback options, overlay stack state, focus
fallback behavior, smoke reachability assertions, and Node-safe overlay tests.
It uses renderer-safe player snapshot vocabulary only and does not wire runtime
playback, expose native/helper internals, contact Plex, or add preload APIs.
RD-13 Unit 6 adds renderer-local CSS-only assets/styles completion through CSS
custom-property tokens, theme hooks, focus-visible styling, reduced-motion and
forced-colors policies, responsive constraints, loaded-style smoke assertions,
and no protocol, static asset, dependency, or lockfile expansion. Units 1
through 6 used upstream Lineup UI/navigation/assets only as reference; no
copied/adapted upstream source landed, so no RD-13 import-ledger row was needed.
RD-13 is complete at the renderer UI and navigation import level.

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
| File-shape guardrails | `docs/architecture/file-shape-guardrails.md` and `tools/verify-maintainability.mjs` | Architecture Health owner for production file-size guardrails, temporary oversized-file allowlist rationale, decomposition/revisit triggers, and Tier 3 file-shape verification |
| Electron main shell | `src/main/index.ts` and `src/main/protocol.ts` | Minimal secure shell frame |
| Preload bridge | `src/preload/index.cts` | Narrow shell/window/player bridge with runtime payload guards; guard vocabulary is kept in the sandbox-compatible preload entrypoint and parity-tested against renderer-safe contracts |
| Renderer shell | `src/renderer/index.ts`, `src/renderer/index.html`, `src/renderer/styles.css`, `src/renderer/navigation.ts`, `src/renderer/workflow.ts`, `src/renderer/settingsSetup.ts`, `src/renderer/epg.ts`, and `src/renderer/overlays.ts` | RD-13 Units 1-6 unprivileged app shell/navigation foundation, fake-backed route/workflow skeleton, settings/channel setup details, fake-backed EPG, fake-backed player overlays, and CSS/theme style surface with primary route rail, screen containers, renderer-local route/focus/workflow/settings/EPG/overlay state, Desktop key mapping, accessible primary navigation, renderer-safe fake view models, local-only setup/guide/overlay actions, deterministic UTC fake schedule formatting, overlay focus fallback behavior, CSS token/theme hooks, reduced-motion and forced-colors policies, responsive constraints, and smoke reachability/style proof |
| Shell contract vocabulary | `src/contracts/shell.ts` | Renderer-safe shell/window/player bridge contract |
| Player contract vocabulary | `src/contracts/player.ts` | Renderer-safe player command, state, event, request id, capability profile, opaque track, error, diagnostic, IPC result, and runtime event-guard contract |
| IPC contract vocabulary | `src/contracts/ipc.ts` | Shell/window/player IPC literals plus renderer-safe player intent and forbidden-field vocabulary |
| Persistence contract vocabulary | `src/contracts/persistence.ts` | Renderer-safe account, credential-handle, selected-server, storage-status, diagnostic, and persistence forbidden-field vocabulary |
| Plex contract vocabulary | `src/contracts/plex.ts` | Renderer-safe Plex profile, home-user, server, health, selection, library, media, collection, playlist, tag-directory summaries plus recursive forbidden-field checks for raw credentials, headers, URI-like fields, raw payloads, filesystem paths, and image keys |
| Desktop player adapter boundary | `src/main/player/desktopPlayerAdapter.ts`, `src/main/player/nativePlayerHostPort.ts`, `src/main/player/nativePlayerHostProcess.ts`, and `src/main/player/playerIpc.ts` | Main-owned RD-07 adapter core, fakeable native-host process seam, and player IPC owner with renderer-intent validation, fakeable native-host event validation, request-id stale-event quarantine, real spawned helper test-double proof, helper/process failure normalization, cleanup/reap handling, runtime main/preload delivery, development/smoke fake-host activation, production unsupported/noop behavior, and renderer-safe diagnostics |
| Desktop stream policy | `src/main/player/streamPolicy/desktopStreamPolicy.ts` and `src/main/player/streamPolicy/types.ts` | Main/player-owned RD-08 deterministic fixture policy for capability-driven direct play, direct stream, transcode, unsupported decisions, audio/subtitle fallback, HDR/Dolby Vision handling, stable reason codes, explicit unknowns, Windows RD-06/RD-07 sample-matrix proof, and safe policy outputs; not wired to Plex runtime, renderer UI, native helper, secure storage, or runtime IPC |
| Plex stream resolver boundary | `src/main/plex/streamResolver.ts` | Main-owned RD-12 resolver that consumes injected selected-connection, active-credential, media-detail, and PMS-session ports; maps Plex media details into RD-08 stream-policy candidates; returns a private privileged playback descriptor separately from renderer-safe player load payloads, safe diagnostics, and request-scoped PMS leases |
| Plex playback runtime boundary | `src/main/player/plexPlaybackRuntime.ts`, `src/main/player/plexPlaybackBridge.ts`, and `src/main/player/plexPlaybackComposition.ts` | Main-owned RD-12 runtime, scheduler/channel bridge, and thin composition seam for resolving current scheduled Plex media into safe player loads, applying request id plus epoch stale-event custody, cleaning PMS/player state on stop/switch/error/logout/server-change/profile-change/helper-crash/teardown/failure paths, rejecting unsafe or mismatched leases before player dispatch, and keeping private playback setup out of renderer/preload contracts |
| Desktop persistence boundary | `src/main/persistence/appDataPaths.ts`, `src/main/persistence/secureStorageCodec.ts`, and `src/main/persistence/desktopPersistenceStore.ts` | Main-owned RD-09 app-data path, Electron safeStorage codec, encrypted Plex credential record, selected-server state, unavailable/corrupt classification, fail-closed no-plaintext fallback, and renderer-safe snapshot owner; not wired to Plex runtime, preload, renderer, scheduler/channel persistence, backup/restore, or production IPC |
| Desktop Plex library domain | `src/main/plex/library/*` | Main-owned RD-10 imported/adapted Plex library parser/domain owner for library sections, media metadata, seasons, collections, playlists, tag directories, search hubs, pagination, request intent, and renderer-safe summaries; no live fetch/cache runtime, image URL construction, stream resolver runtime, preload, renderer, or playback URL setup |
| Desktop Plex auth domain | `src/main/plex/auth/*` | Main-owned RD-10 imported/adapted Plex auth owner for PIN/profile/token validation, Plex Home users, profile switching, injected auth transport, sanitized errors, Desktop identity metadata, and RD-09 credential storage adapter; no live Plex transport composition, preload/renderer auth API, real Electron safeStorage/app-path wiring, package change, or OS-specific runtime behavior |
| Desktop Plex discovery domain | `src/main/plex/discovery/*` | Main-owned RD-10 imported/adapted Plex discovery and selected-server owner for resource parsing, connection probe policy, health classification, stale discovery-context invalidation, RD-09 selected-server summary persistence, and in-memory selected connection custody; restores by server id plus fresh probing and never persists or returns connection URI/server URI state |
| Domain architecture verifier | `tools/architecture-rules/*` and `tools/__tests__/build-eslint-architecture-rules.test.mjs` | RD-11 domain-boundary verifier for `src/domain/**`; blocks Electron, Node, main/preload/renderer/native-helper imports, dynamic owner imports, and browser/runtime globals including direct `globalThis` runtime access. F-004 removes the blanket `src/**/__tests__/**` production-boundary exemption and adds explicit test-owner coverage for `src/__tests__/contracts/**`, `src/__tests__/domain/**`, `src/__tests__/main/**`, `src/__tests__/preload/**`, and `src/__tests__/renderer/**`; `src/__tests__/integration/**` is denied by default except for data-declared named seams. The only current integration exception is `preload-contract-vocabulary-parity` at `src/__tests__/integration/preloadContractVocabulary.test.ts`, which may compare `src/preload/vocabulary.cjs` with renderer-safe contract vocabulary. |
| Scheduler domain | `src/domain/scheduler/**` | Pure RD-11 imported/adapted deterministic scheduler and playback-ordering owner for anchor-time schedule calculation, loop wrapping, current/next/previous lookup, schedule windows, shuffle seeds, block playback validation, injected clock/timer ports, and event emission; not wired to Electron main/preload, renderer, Plex runtime, stream resolution, or native playback |
| Channel and content domain | `src/domain/channel/**` | Pure RD-11 imported/adapted channel authoring, import/export normalization, content resolution through injected domain-safe library ports, stale fallback, source/channel resolution caches, retry scheduling, lineup navigation, and channel persistence port owner; no raw Plex payload, tokenized URL, auth header, Electron, Node, browser storage, preload, renderer, or live network ownership |
| Channel persistence adapter | `src/main/persistence/desktopChannelPersistenceStore.ts` | Main-owned RD-11 separate versioned channel persistence file adapter behind an injected file path, temp-file write, mode hardening, and typed domain storage port; not wired to Electron app paths, existing credential/selected-server persistence, preload/renderer APIs, backup/restore, or runtime composition |
| Redaction contract vocabulary | `src/contracts/redaction.ts` | Stub contract only |
| External `mpv` POC tool | `tools/mpv-poc/rd-05-external-mpv-poc.mjs` | Dev-only disposable RD-05 evidence harness |
| Native libmpv spike tool | `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs` | Dev-only disposable RD-06 Windows WID/render API evidence harness |
| Docs verifier | `tools/verify-docs.mjs` | Active |
| Redaction verifier | `tools/verify-redaction.mjs` | Active |

## Not Yet Implemented

- Live Plex auth/discovery/library transport and runtime composition
- Windows-proven production native playback helper
- Windows-proven production playback host
- Production Plex-to-native-helper playback setup using the private RD-12
  playback descriptor
- production renderer player UI wiring
- preload/renderer persistence IPC wiring
- encrypted credential backup/restore implementation
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
