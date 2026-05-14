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
ARCH-01 adds the architecture-health stabilization pass before RD-14. The pass
remediates the renderer composition, renderer static asset, main composition,
and renderer overlay hotspots through behavior-preserving same-owner splits;
keeps preload single-file-compatible while hardening the preload bridge
source-shape/parity harness for channel constants, the single `lineupDesktop`
exposure, and approved `ipcRenderer` method/channel use; and leaves the
remaining large player, Plex, channel, contract, policy, and native-helper
owners in `docs/architecture/file-shape-guardrails.md` with reviewed deferral or
leave-alone triggers. ARCH-01 does not add RD-14 product behavior, native
video/fullscreen behavior, live Plex transport, production native-helper
playback, packaging/signing/update behavior, app-path or `safeStorage` runtime
wiring, new preload/renderer APIs, dependencies, or copied/adapted upstream
source.
RD-14 is complete. Unit 1 added the first focused renderer desktop input owner
under `src/renderer/desktopInput.ts`, keeping the renderer unprivileged and
fake-backed while preserving RD-13 route/focus behavior. The unit moves keyboard
shortcut mapping, text-entry bypass for editable targets, browser-safe gamepad
normalization/polling/repeat policy, fullscreen dispatch, and runtime input
cleanup out of the renderer composition root. Unit 2 added a focused main-owned
window controller under `src/main/window/shellWindowController.ts` for
BrowserWindow creation/options, fullscreen intent execution, normal bounds
capture, display id custody, and restore/fallback placement policy. It keeps
`src/main/index.ts` as composition/IPC wiring, preserves the existing
`window.setFullscreen(boolean)` response shape, waits for stable fullscreen
leave before restore, and fits restore bounds against current display work
areas. Unit 3 added a focused main-owned foreground app-command controller under
`src/main/window/shellAppCommandController.ts`. The controller listens only to
the shell `BrowserWindow` `app-command` event, uses no `globalShortcut`, maps
`browser-backward` to the existing renderer back path through synthetic
`Escape` input, intentionally ignores `browser-forward`, and leaves media app
commands unhandled by product code. Unit 4 added renderer-owned DOM cursor
presentation under `src/renderer/desktopCursor.ts`. The cursor state remains
renderer-local, starts visible, hides after inactivity or mapped desktop
keyboard/gamepad input, shows on pointer/mouse activity, and restores visible
state on unload cleanup through scoped CSS. Unit 5 closed the Windows platform
gate using the dev-only RD-06 native-presentation harness and local ignored
redacted evidence under `docs/runs/rd-14-window-input-fullscreen-ux/`.
Preflight and smoke passed on Windows with dummy local and HTTP media, active
video pixels, renderer overlay/native-boundary composition, fullscreen
composition, app-owned input/focus simulation, helper crash detection, cleanup,
no forbidden header, and redacted evidence scan success. The Windows matrix
records a two-display 100% DPI environment, media-key/gamepad availability
notes, and the lack of current text-entry controls in the fake settings/channel
setup UI while preserving Unit 1 automated text-input bypass proof. RD-14 added
no preload method, IPC channel, contract event, renderer-facing OS command
payload, main/native cursor control, production native-helper playback, Plex
runtime behavior, dependency, package, lockfile, or upstream source import.
RD-15 is complete. Units 1 and 2 hardened the renderer-owned fake-backed UI so
player overlays, OSD, mini guide, channel badge, guide/EPG, settings, and
channel setup compose predictably over the player presentation surface with
stable route reachability, z-order, fullscreen bridge continuity, deterministic
focus fallback, and Desktop-accurate local settings copy. Unit 3 extended and
ran the dev-only RD-06 native-presentation harness for RD-15 proof: Windows
preflight passed, Windows native-presentation smoke passed under
`docs/runs/rd-15-ui-over-native-video-integration/`, the manifest status is
`passed`, and the summary records `RD-15 native presentation UI: 16/16
observed` across windowed and fullscreen native-video composition, EPG, OSD,
mini guide, channel badge, settings, channel setup, overlays, renderer focus,
helper cleanup, and redaction gates. `npm run test:harness-docs`, `npm run
verify:redaction`, and `npm run verify` passed after the Unit 3 harness
revision, and implementation review found no blockers. RD-15 remains a
renderer/dev-harness integration closeout only: it adds no production
native-helper playback, live Plex transport, preload or contract expansion,
product IPC, packaging behavior, dependency or lockfile change, live renderer
Plex API, or upstream source import.
RD-16 is complete. Units 1 and 2 hardened the main/player stream-policy and
main/Plex resolver seams for subtitle, audio, HDR, and track identity behavior:
forced/default subtitles, subtitle-off, requested missing/incompatible audio
and subtitles, burn-in/conversion decisions, audio fallback, language metadata
preservation without language-preference selection, HDR10, Dolby Vision,
unknown dynamic range, explicit unsupported/unknown reasons, and public/private
track id separation are covered by deterministic tests. Unit 4 extended and ran
the dev-only RD-06 native-presentation harness for RD-16 proof: Windows
preflight passed, Windows native-presentation smoke passed under
`docs/runs/rd-16-subtitle-audio-hdr-hardening/`, and the summary records
`RD-16 media matrix: observed (multi-audio:observed,
subtitle-bearing:observed, hdr:observed, hdr-unavailable:observed)` while
keeping `tracks: not-proven-by-dummy-visual-media`. `npm run
test:harness-docs`, `npm run verify:redaction`, and `npm run verify` passed
during closeout. RD-16 remains policy/resolver/dev-harness hardening only: it
adds no production native-helper playback, live Plex transport, preload or
contract expansion, product IPC, packaging behavior, dependency or lockfile
change, live renderer Plex API, preferred-language selection, adapter
current-request membership validation, or upstream source import.
RD-17 is complete. It adds renderer-safe diagnostics contracts, RD-17 redaction
vocabulary, a main-owned diagnostic event store, support-bundle path/export
owners, diagnostics IPC/preload methods, a renderer settings export action, and
player/native-host/runtime diagnostic hooks for helper crash/restart and cleanup
reporting. Windows proof passed under ignored local evidence at
`docs/runs/rd-17-diagnostics-crash-recovery-support-bundle/windows-smoke`: the
summary records platform `win32`, status `passed`, helper crash detected, main
process alive, safe failed request state, helper cleanup/reap, replacement
helper use, a main-created bundle target under the injected parent,
renderer-visible output limited to bundle identity, completed-bundle scan status
`passed`, and no forbidden material. RD-17 adds no telemetry/cloud upload,
production native-helper playback, live Plex transport, packaging/signing or
release behavior, dependency or lockfile change, persisted credential/settings
schema change, or upstream source import.
RD-18 Unit 1 is complete for internal Windows x64 package tooling and proof.
The packaging/provenance owner is `tools/package-windows-internal.mjs`,
validated by `tools/verify-windows-internal-package.mjs` and
`tools/__tests__/package-windows-internal.test.mjs`. Windows closeout observed
`win32 x64`, `npm run build:electron`, internal package generation under
`out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/`, and package
verification passing with a clean tracked worktree. The generated artifact
contains `LineupDesktop.exe`, unpacked `resources/app` with main/preload/renderer
dist payload, provenance, deterministic checksums, internal notices, and blocked
native-helper/media-binary markers. RD-18 Unit 1 adds no package script,
dependency, lockfile, signing config, update metadata, native media
redistribution, Plex behavior, renderer/preload/IPC contract, runtime behavior,
or public release artifact.
RD-19 is complete for internal alpha/beta validation. The validation artifact is
`docs/development/rd-19-internal-validation-checklist.md`. Units A and B added
the redacted checklist and checklist-shape verifier, Unit C reran Windows x64
internal package proof, and Unit D executed the full RD-19 validation matrix on
Windows x64 using current fake-backed UI, injected/domain, package,
diagnostics, Electron smoke, and dev-only harness proof surfaces. Unit D
recorded only redacted summaries and blocker rows: auth, server selection,
channel creation, playback, switching, subtitles/audio, EPG, settings,
fullscreen, multi-monitor, crash recovery, diagnostics export, and
install/delete of the unpacked package have current passed proof for their
limited fake/injected/package/diagnostics surfaces; sleep/wake and real long
playback remain blocked and classified. RD-19 does not add live Plex transport,
renderer Plex APIs, production native playback, persistence IPC, signing/update
behavior, installer behavior, public release readiness, source/tool/package
script/dependency/lockfile changes, or tracked generated artifacts.

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
| Electron main shell | `src/main/index.ts`, `src/main/protocol.ts`, `src/main/smokeAssertions.ts`, `src/main/window/shellWindowController.ts`, and `src/main/window/shellAppCommandController.ts` | Secure shell frame with smoke-only assertion ownership split out of the startup/composition entrypoint, plus RD-14 Unit 2 main-owned BrowserWindow/fullscreen/display/restore controller and Unit 3 foreground app-command controller while `src/main/index.ts` remains composition and IPC wiring |
| Preload bridge | `src/preload/index.cts` | Narrow shell/window/player/diagnostics bridge with runtime payload guards; guard vocabulary is kept in the sandbox-compatible preload entrypoint, and the integration seam reads preload source text plus renderer-safe contracts to parity-test guard vocabulary, channel constants, the single `lineupDesktop` exposure, and approved `ipcRenderer` method/channel pairs without importing or executing preload |
| Renderer shell | [`docs/architecture/renderer-architecture.md`](./renderer-architecture.md) | RD-13/ARCH-01 unprivileged app shell with route, workflow, EPG, overlay, focus, and style surfaces; RD-14 focused desktop input and DOM cursor owners; and RD-15 fake-backed UI-over-player-surface composition for overlays, guide/EPG, settings, channel setup, z-order, fullscreen bridge continuity, and deterministic renderer focus |
| Shell contract vocabulary | `src/contracts/shell.ts` | Renderer-safe shell/window/player bridge contract |
| Player contract vocabulary | `src/contracts/player.ts` | Renderer-safe player command, state, event, request id, capability profile, opaque track, error, diagnostic, IPC result, and runtime event-guard contract |
| IPC contract vocabulary | `src/contracts/ipc.ts` | Shell/window/player/diagnostics IPC literals plus renderer-safe player intent and forbidden-field vocabulary |
| Persistence contract vocabulary | `src/contracts/persistence.ts` | Renderer-safe account, credential-handle, selected-server, storage-status, diagnostic, and persistence forbidden-field vocabulary |
| Plex contract vocabulary | `src/contracts/plex.ts` | Renderer-safe Plex profile, home-user, server, health, selection, library, media, collection, playlist, tag-directory summaries plus recursive forbidden-field checks for raw credentials, headers, URI-like fields, raw payloads, filesystem paths, and image keys |
| Diagnostics contract vocabulary | `src/contracts/diagnostics.ts` | Renderer-safe RD-17 diagnostic schema, result/error, summary, support-bundle export, redaction-scan, renderer-event, truncation, and sanitizer vocabulary |
| Main diagnostics and support bundle | `src/main/diagnostics/*` | Main-owned RD-17 diagnostic event store, support-bundle target/path creation, export assembly, redaction scanning, IPC authorization, renderer-event validation, and safe support-bundle result/failure envelopes; renderer never receives absolute export paths or raw diagnostic material |
| Desktop player adapter boundary | `src/main/player/desktopPlayerAdapter.ts`, `src/main/player/nativePlayerHostPort.ts`, `src/main/player/nativePlayerHostProcess.ts`, and `src/main/player/playerIpc.ts` | Main-owned RD-07 adapter core, fakeable native-host process seam, and player IPC owner with renderer-intent validation, fakeable native-host event validation, request-id stale-event quarantine, real spawned helper test-double proof, helper/process failure normalization, cleanup/reap handling, runtime main/preload delivery, development/smoke fake-host activation, production unsupported/noop behavior, and renderer-safe diagnostics |
| Desktop stream policy | `src/main/player/streamPolicy/desktopStreamPolicy.ts` and `src/main/player/streamPolicy/types.ts` | Main/player-owned deterministic fixture policy for capability-driven direct play, direct stream, transcode, unsupported decisions, RD-16 forced/default subtitle handling, subtitle-off, requested missing/incompatible audio and subtitles, burn-in/conversion decisions, audio fallback, language metadata preservation without language-preference selection, HDR/Dolby Vision/unknown dynamic-range handling, stable reason codes, explicit unknowns, Windows RD-06/RD-07 sample-matrix proof, RD-16 redacted media-matrix proof, and safe policy outputs; not wired to Plex runtime, renderer UI, native helper, secure storage, or runtime IPC |
| Plex stream resolver boundary | `src/main/plex/streamResolver.ts` | Main-owned RD-12/RD-16 resolver that consumes injected selected-connection, active-credential, media-detail, and PMS-session ports; maps Plex media details into stream-policy candidates; returns a private privileged playback descriptor separately from renderer-safe player load payloads, safe diagnostics, public renderer-safe track ids, and request-scoped PMS leases while keeping private Plex stream ids and future native/engine ids out of public surfaces |
| Plex playback runtime boundary | `src/main/player/plexPlaybackRuntime.ts`, `src/main/player/plexPlaybackBridge.ts`, and `src/main/player/plexPlaybackComposition.ts` | Main-owned RD-12 runtime, scheduler/channel bridge, and thin composition seam for resolving current scheduled Plex media into safe player loads, applying request id plus epoch stale-event custody, cleaning PMS/player state on stop/switch/error/logout/server-change/profile-change/helper-crash/teardown/failure paths, rejecting unsafe or mismatched leases before player dispatch, and keeping private playback setup out of renderer/preload contracts |
| Desktop persistence boundary | `src/main/persistence/appDataPaths.ts`, `src/main/persistence/secureStorageCodec.ts`, and `src/main/persistence/desktopPersistenceStore.ts` | Main-owned RD-09 app-data path, Electron safeStorage codec, encrypted Plex credential record, selected-server state, unavailable/corrupt classification, fail-closed no-plaintext fallback, and renderer-safe snapshot owner; not wired to Plex runtime, preload, renderer, scheduler/channel persistence, backup/restore, or production IPC |
| Desktop Plex library domain | `src/main/plex/library/*` | Main-owned RD-10 imported/adapted Plex library parser/domain owner for library sections, media metadata, seasons, collections, playlists, tag directories, search hubs, pagination, request intent, and renderer-safe summaries; no live fetch/cache runtime, image URL construction, stream resolver runtime, preload, renderer, or playback URL setup |
| Desktop Plex auth domain | `src/main/plex/auth/*` | Main-owned RD-10 imported/adapted Plex auth owner for PIN/profile/token validation, Plex Home users, profile switching, injected auth transport, sanitized errors, Desktop identity metadata, and RD-09 credential storage adapter; no live Plex transport composition, preload/renderer auth API, real Electron safeStorage/app-path wiring, package change, or OS-specific runtime behavior |
| Desktop Plex discovery domain | `src/main/plex/discovery/*` | Main-owned RD-10 imported/adapted Plex discovery and selected-server owner for resource parsing, connection probe policy, health classification, stale discovery-context invalidation, RD-09 selected-server summary persistence, and in-memory selected connection custody; restores by server id plus fresh probing and never persists or returns connection URI/server URI state |
| Domain architecture verifier | `tools/architecture-rules/*` and `tools/__tests__/build-eslint-architecture-rules.test.mjs` | RD-11 domain-boundary verifier for `src/domain/**`; blocks Electron, Node, main/preload/renderer/native-helper imports, dynamic owner imports, and browser/runtime globals including direct `globalThis` runtime access. F-004 removes the blanket `src/**/__tests__/**` production-boundary exemption and adds explicit test-owner coverage for `src/__tests__/contracts/**`, `src/__tests__/domain/**`, `src/__tests__/main/**`, `src/__tests__/preload/**`, and `src/__tests__/renderer/**`; `src/__tests__/integration/**` is denied by default except for data-declared named seams. The current integration exception is `preload-contract-vocabulary-parity` at `src/__tests__/integration/preloadContractVocabulary.test.ts`, which may compare preload source text with renderer-safe contract vocabulary while keeping production preload single-file-compatible. |
| Scheduler domain | `src/domain/scheduler/**` | Pure RD-11 imported/adapted deterministic scheduler and playback-ordering owner for anchor-time schedule calculation, loop wrapping, current/next/previous lookup, schedule windows, shuffle seeds, block playback validation, injected clock/timer ports, and event emission; not wired to Electron main/preload, renderer, Plex runtime, stream resolution, or native playback |
| Channel and content domain | `src/domain/channel/**` | Pure RD-11 imported/adapted channel authoring, import/export normalization, content resolution through injected domain-safe library ports, stale fallback, source/channel resolution caches, retry scheduling, lineup navigation, and channel persistence port owner; no raw Plex payload, tokenized URL, auth header, Electron, Node, browser storage, preload, renderer, or live network ownership |
| Channel persistence adapter | `src/main/persistence/desktopChannelPersistenceStore.ts` | Main-owned RD-11 separate versioned channel persistence file adapter behind an injected file path, temp-file write, mode hardening, and typed domain storage port; not wired to Electron app paths, existing credential/selected-server persistence, preload/renderer APIs, backup/restore, or runtime composition |
| Redaction contract vocabulary | `src/contracts/redaction.ts` | RD-17 redaction boundary and forbidden diagnostic field vocabulary shared by diagnostics contracts, scanner, and tests |
| External `mpv` POC tool | `tools/mpv-poc/rd-05-external-mpv-poc.mjs` | Dev-only disposable RD-05 evidence harness |
| Native libmpv spike tool | `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs` | Dev-only disposable RD-06 Windows WID/render API evidence harness |
| Internal Windows package tooling | `tools/package-windows-internal.mjs`, `tools/verify-windows-internal-package.mjs`, and `tools/__tests__/package-windows-internal.test.mjs` | RD-18 Unit 1 owner for internal Windows x64 unpacked package staging, provenance, checksums, internal notices, blocked native-helper/media-binary markers, and verifier coverage; generated artifacts stay ignored under `out/rd-18-windows-internal/**`, and public signing/update/native media redistribution remain blocked |
| Docs verifier | `tools/verify-docs.mjs` | Active |
| Redaction verifier | `tools/verify-redaction.mjs` | Active RD-17-aware scanner for secret-shaped values, raw auth/header material, privileged diagnostic fields, raw filesystem paths, process data, native handles, and raw IPC frames |
| RD-17 diagnostics smoke | `tools/rd17-diagnostics-smoke.mjs` | Windows-only ignored-evidence proof for diagnostics crash recovery and support-bundle redaction closeout |

## Not Yet Implemented

- Live Plex auth/discovery/library transport and runtime composition
- Windows-proven production native playback helper
- Windows-proven production playback host
- Production Plex-to-native-helper playback setup using the private RD-12
  playback descriptor
- live renderer Plex APIs and production renderer-to-Plex/player API wiring
- preload, contract, and product IPC expansion for live Plex/player runtime
  beyond the RD-17 local diagnostics surface
- preload/renderer persistence IPC wiring
- encrypted credential backup/restore implementation
- public signing/update pipeline
- production native-helper and media-binary redistribution inside packages

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
RD-17 also exposes `window.lineupDesktop.diagnostics.recordRendererEvent()`,
`window.lineupDesktop.diagnostics.getSummary()`, and
`window.lineupDesktop.diagnostics.exportSupportBundle()` through preload; those
methods return renderer-safe diagnostics envelopes and never expose absolute
paths, raw helper output, process identifiers, native handles, raw Plex payloads,
credentials, auth headers, tokenized URLs, or raw IPC traces.

## Roadmap

Use [`docs/roadmap/desktop-port-roadmap.md`](../roadmap/desktop-port-roadmap.md)
for the ordered port checklist after the current active plan or handoff is
understood. It records what comes next after the secure Electron shell
foundation, which original Lineup slices are likely reusable, which surfaces
must be newly designed for Desktop, and the global gates that block broad port
work.
