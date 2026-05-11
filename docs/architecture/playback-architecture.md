# Playback Architecture

Lineup Desktop runtime playback is only partially wired. RD-07 adds a
main-owned Desktop player adapter boundary core, a narrow runtime main/preload
player IPC bridge backed by a development/smoke fake host, and a native-host
process seam behind the adapter host port. Windows closeout proof covers the
process seam with a real spawned helper test double and reruns the RD-06
app-owned native-presentation smoke as RD-07's native surface proof. Production
player commands currently return renderer-safe unsupported failures. RD-12 adds
an injected main-owned Plex stream resolver and playback runtime, but production
native-helper playback, live Plex transport composition, renderer UI
integration, and product helper wiring remain unimplemented.

## Current Hypothesis

The production hypothesis is Electron plus a helper-hosted native libmpv path.
The helper process should isolate native media crashes and secret-bearing
playback setup from the renderer.

External `mpv` IPC may be used only as a private disposable POC to learn about
media behavior. It must not become production architecture.

## RD-05 External mpv POC Observations

RD-05 created a dev-only external `mpv` POC under
`tools/mpv-poc/rd-05-external-mpv-poc.mjs`. It is quarantined as a disposable
tool with no package script, dependency, product IPC, renderer, preload, main,
native-helper, Plex, scheduler, or adapter ownership.

Redacted local evidence under ignored
`docs/runs/rd-05-external-mpv-poc/` observed:

- local dummy HTTP playback was requested by `mpv`
- dummy non-secret header handling worked for `X-Lineup-POC: rd-05-dummy`
- forbidden header observation was false
- one renderer-safe normalized audio track was observed
- start-offset/time-position evidence was nonzero
- `stop` succeeded and process, IPC socket, HTTP server, temp input, and
  forbidden-field cleanup checks passed

RD-05 also observed four sanitized events after stop before quit. That is a
future stale-event/channel-switch risk for RD-06/RD-07, not accepted Desktop
production behavior. Subtitle behavior remains unproven by the dummy audio-only
input and must be proved by RD-06 or a reviewed follow-up plan before product
contracts or adapters rely on it.

## RD-06 Native libmpv Spike Observations (WID, Render API, App-owned Native Presentation)

RD-06 added a dev-only Windows native libmpv WID/render API spike under
`tools/libmpv-spike/`. It remains evidence tooling only: no product IPC,
renderer, preload, main, Plex, scheduler, adapter, package metadata, lockfile,
native binary, or packaging ownership changed.

Redacted local evidence under ignored
`docs/runs/rd-06-native-libmpv-host-spike/` observed:

- local dummy visual media loaded through helper-hosted libmpv
- dummy HTTP media loaded with only the non-secret `X-Lineup-RD06: dummy`
  header
- forbidden header observation was false
- libmpv client API version evidence was recorded in addition to local
  prerequisite and `mpv` executable version evidence
- overlay visibility, renderer focus, fullscreen toggle, and in-memory video
  surface pixel checks run only while helper local playback is active
- helper crash detection was observed without product renderer/preload/main IPC
  involvement
- helper build output, dummy inputs, and local HTTP server cleanup were
  temporary/local only
- evidence redaction checks passed for raw local paths, raw URLs, raw native
  values, and raw diagnostics

The revised Windows WID smoke fails the full RD-06 proof because
active-playback fullscreen video pixels were not captured even though windowed
video pixels, overlay pixels, focus, dummy HTTP loading, helper crash detection,
and redaction checks were observed. WID is therefore blocked as the RD-07
production direction unless a later reviewed plan reopens it with new evidence.

The Windows render API smoke also fails the full RD-06 proof. It observed
render API symbol availability, render-context creation, app-owned input
simulation, local dummy visual media, dummy HTTP visual media with the approved
non-secret header, windowed active-playback video pixels, overlay pixels, focus,
helper crash detection, temp cleanup, libmpv client API/version evidence, and
no forbidden header observation. It records render-thread discipline and
composition proof as not proven by this helper loop, and it still did not
capture active fullscreen video pixels while the BrowserWindow was fullscreen.
The amended helper-owned Win32 screen-pixel fallback was requested only after
Electron confirmed BrowserWindow fullscreen and was scoped to the helper render
child surface; it also reported fullscreen video pixels as not captured. Render
API therefore does not currently close the native surface proof gap or unlock
RD-07.

The active RD-06 plan now routes the next bounded proof to an app-owned native
presentation boundary. That path must prove fullscreen active video pixels,
native-boundary overlay/composition, render-thread discipline, cleanup, and
redaction before RD-06 can route RD-07 toward a native surface direction.

The revised Windows app-owned native presentation probe records a passing
redacted smoke under the stricter proof semantics. It observed local dummy
visual playback, dummy HTTP visual playback with only `X-Lineup-RD06: dummy`,
fullscreen active video pixels and distinct fullscreen-composition evidence
after the native host entered fullscreen and settled, render-thread discipline
through fresh bounded nonblocking render-loop progress, app-owned input
simulation, helper crash detection, helper cleanup/reap evidence after child
exit, temp cleanup, libmpv client API/version evidence, render API symbol
evidence, and no forbidden header observation. This remains dev-only and does
not create production playback architecture. Clean implementation re-review
reported no material blockers, so the native presentation boundary is the
reviewed RD-07 direction.

Track selection and subtitle behavior remain unproven by the tiny dummy visual
input. DPI and multi-monitor behavior are noted only as redacted smoke
observations rather than an MVP manual matrix.

## Required Spike Proof

Before production playback design hardens, a Windows spike must prove:

- local media playback
- Plex-like stream loading without renderer secret exposure
- overlay visibility above video in windowed and borderless fullscreen modes
- renderer focus/input continuity while video plays
- audio/subtitle track list observation and selection
- helper crash detection without corrupting current player state
- redacted logs and diagnostics
- acceptable DPI and multi-monitor behavior for MVP

## Contract First

Player integration starts from `src/contracts/player.ts` and its tests. RD-03
defined the renderer-safe contract vocabulary for commands, request ids,
snapshots, events, capability profiles, opaque track ids, error taxonomy, and
diagnostics before the first adapter boundary existed.

RD-07 now defines the first main-owned Desktop adapter core in
`src/main/player/desktopPlayerAdapter.ts` with a private fakeable host port in
`src/main/player/nativePlayerHostPort.ts`. The adapter accepts
renderer-originating `RendererIntentEnvelope<unknown>` values at the boundary,
validates closed player intents before host calls or state mutation, validates
fake-host events before state mutation, quarantines stale request ids including
late post-cleanup events, and normalizes helper failures into renderer-safe
`PlayerError` values. The boundary is tested at
`src/__tests__/desktopPlayerAdapter.test.ts`.

RD-07 also wires the adapter through a main-owned player IPC registrar in
`src/main/player/playerIpc.ts` and the narrow `window.lineupDesktop.player`
preload API. The bridge exposes only `dispatch`, `getSnapshot`, `cleanup`, and
`onEvent`; it returns renderer-safe `PlayerIpcResult` values and dispatch
results without internal `PlayerCommand` objects. `src/main/index.ts` passes
only shell mode and authorization/event callbacks into the registrar. The
registrar owns development/smoke fake-host activation and production
unsupported/noop behavior. Preload guards player events at runtime before
invoking renderer listeners, including nested forbidden-field checks.

RD-07 adds a native-host process seam in
`src/main/player/nativePlayerHostProcess.ts`. The seam translates private
main-owned process messages behind `NativePlayerHostPort`, normalizes spawn,
exit, timeout, malformed-output, cleanup, and helper failures into
renderer-safe host failures, ignores late process output after cleanup, and is
covered with in-memory and real spawned helper test doubles at
`src/__tests__/nativePlayerHostProcess.test.ts`. Windows RD-07 closeout also
reran the RD-06 app-owned native-presentation smoke successfully, observing
local and dummy HTTP native playback, fullscreen/composition through the
native-presentation host, focus/input continuity, helper crash detection,
helper cleanup/reap, and redacted diagnostics. This does not ship a production
native helper binary, bind libmpv in product code, wire Plex streams, or change
renderer, preload, or contract shapes.

RD-08 adds a deterministic main/player stream policy fixture core in
`src/main/player/streamPolicy/*`, covered by
`src/__tests__/desktopStreamPolicy.test.ts`. It evaluates safe capability
profiles and normalized candidate facts to choose direct play, direct stream,
transcode, or unsupported outcomes with stable reason codes and explicit
unknowns. The fixture core covers audio fallback, subtitle fallback, HDR/Dolby
Vision handling, direct-stream remediation rules, and recursive forbidden-field
invariants. Windows closeout adds a conservative RD-06/RD-07 capability/sample
matrix that keeps exact container, codec, audio, subtitle, direct stream,
transcode, track switching, HDR, Dolby Vision, and Plex HTPC parity support
unknown or unsupported where the Windows proof does not establish them. It does
not contact Plex, normalize real Plex payloads, create playback URLs, start
native playback, wire runtime IPC, or change renderer, preload, adapter,
native-host, storage, package, or dependency behavior.

RD-12 adds the first main-owned Plex-to-player runtime boundary without turning
on production native-helper playback. `src/main/plex/streamResolver.ts`
resolves injected selected-connection, active-credential, media-detail, and
PMS-session ports into two separate outputs: a private privileged playback
descriptor for future main/helper setup and a renderer-safe
`PlayerLoadCommandPayload` for the existing player adapter boundary. The
resolver applies the RD-08 stream policy and keeps raw credentials, auth
headers, raw Plex payloads, token-bearing URLs, connection URI details, Plex
part/stream keys, and private track ids out of public diagnostics and fixtures.

`src/main/player/plexPlaybackRuntime.ts` owns request/epoch custody and PMS
cleanup. It asks an injected scheduler/channel port for the current scheduled
selection, resolves a safe playback candidate, rejects unsafe payloads and
mismatched PMS leases before player dispatch, releases rejected/stale leases,
dispatches only safe player commands, quarantines stale player/helper events,
and cleans PMS/player state for stop, switch, error, logout, server change,
profile change, helper crash, teardown, failed resolver/player paths, and stale
candidate paths. `src/main/player/plexPlaybackBridge.ts` maps pure RD-11
scheduler/channel current-program state into resolver input without giving the
domain Plex credentials, URLs, Electron objects, Node objects, helper internals,
or cleanup policy. `src/main/player/plexPlaybackComposition.ts` is only a thin
injected factory and adapter port mapper.

RD-12 proof is Mac/local automated proof sufficient: the runtime, resolver,
bridge, and composition seams are injected and fakeable, and `npm run verify`
passed on 2026-05-11. RD-12 does not add preload or renderer Plex APIs, live
Plex transport composition, real Electron app-path or `safeStorage` wiring,
package/dependency changes, Windows-specific proof surfaces, or production
native-helper playback. Future production native playback must replan before
using the private playback descriptor with a real helper.

Concrete playback adapters must not leak native handles, raw media URLs, raw
auth headers, tokenized URLs, raw Plex payloads, Electron or Node APIs,
libmpv-specific objects, or engine-specific track ids into renderer-facing state
without an explicit reviewed contract.

Renderer-facing track state uses opaque UI ids only. Privileged mappings to
engine ids, Plex stream ids, Plex part keys, stream keys, URLs, headers, or
native handles belong behind main/helper or domain-owned boundaries and require
a reviewed plan before they are introduced.
