# Playback Architecture

Lineup Desktop runtime playback is code complete and reviewed, with
Windows/manual product proof still pending. WS2 now closes the current
platform-neutral playback implementation gate without promoting the
conservative production profile. WS3 now adds locally verified Settings
preference/control contributions and request-bound Settings pause/resume
without promoting that profile. WS4 adds locally verified guarded stop/
relative-seek input, foreground media-command contribution, and guarded sleep-
expiry pause without promoting that profile; `WS4-PROOF-01` and
`WS4-PROOF-03` retain production Windows/native observation. RD-25 implements the production
native playback MVP, replacing the fake playback bootstrap with a
production-shaped, main/helper-owned native playback path for live Plex-backed
scheduled media. A main-only privileged load context propagates the private
playback descriptor to the helper host, which runs a repo-owned C# native helper
process. The helper communicates with the main process via an NDJSON protocol
over stdin/stdout. Live Plex stream resolution, media detail, and PMS session
ports are composed and wired. Renderer player UI state binds dynamically to safe
player IPC events. Manual proof of running native playback on Windows is
deferred to RD-27 and remains pending; the WS2-specific native/live subset is
also carried as nonblocking `WS2-POST-VALIDATION-01`.

WS5 Unit 5D checkpoint `81cf42c` adds the production app-owned native
presentation path: one exact renderer/preload/main contract, epoch/revision
currentness, hide-before-load/switch/cleanup barriers, and a Win32 child HWND
owned by the existing shared native helper. Host-owned monotonic operation IDs
reject replay in constant space, and context-wrong post-send ACKs quarantine the
shared helper. Windows compilation and live composition proof remain deferred
to Unit 5H; this local checkpoint does not promote capabilities or close WS5.

## Current Hypothesis

The production hypothesis is Electron plus a helper-hosted native libmpv path.
The helper process should isolate native media crashes and secret-bearing
playback setup from the renderer.

External `mpv` IPC may be used only as a private disposable POC to learn about
media behavior. It must not become production architecture.

## RD-05 External mpv POC Observations

RD-05 created a dev-only external `mpv` POC with no package script, dependency,
product IPC, renderer, preload, main, native-helper, Plex, scheduler, or adapter
ownership. Its disposable source and dedicated test were removed after the
observations below were preserved. The reviewed main/helper-owned native
architecture—not the POC—now owns the production direction; Windows/manual
proof remains pending.

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

## RD-15 Native Presentation UI Proof

RD-15 reuses the reviewed app-owned native-presentation direction as a
dev-only proof boundary. Windows preflight and native-presentation smoke passed
under `docs/runs/rd-15-ui-over-native-video-integration/`, the manifest status
is `passed`, and the summary records `RD-15 native presentation UI: 16/16
observed`.

That proof covers active native video with RD-15 EPG, OSD, mini guide, channel
badge, settings, channel setup, overlays, windowed composition, fullscreen
composition, renderer focus, helper cleanup, and redaction gates. It remains
evidence for renderer/native presentation composition only. Production
native-helper playback, live Plex transport, preload/contracts, product IPC,
packaging, and live renderer Plex APIs are still future roadmap work.

## RD-16 Subtitle, Audio, HDR, And Track Identity

RD-16 extends the existing main/player stream-policy and main/Plex resolver
seams without expanding renderer, preload, product IPC, or production helper
contracts. Renderer-facing track ids remain opaque public ids scoped to a
resolved candidate/request. Plex stream ids, part keys, stream keys, URLs,
headers, future native engine ids, and native handles remain private to
main/helper setup and are not exposed in player load payloads, diagnostics, or
renderer-safe events.

The deterministic policy and resolver tests now cover forced/default subtitle
selection, requested subtitle off, requested missing or incompatible audio and
subtitles, burn-in/conversion decisions, audio fallback, language metadata
preservation without preferred-language selection, HDR10, Dolby Vision, unknown
dynamic range, explicit unsupported/unknown reasons, and public/private track
id separation.

Windows closeout proof used the dev-only native-presentation harness with an
ignored redacted RD-16 media-matrix descriptor. Preflight and smoke passed under
`docs/runs/rd-16-subtitle-audio-hdr-hardening/`; the smoke summary records
`RD-16 media matrix: observed (multi-audio:observed,
subtitle-bearing:observed, hdr:observed, hdr-unavailable:observed)`. The
manifest deliberately keeps `tracks: not-proven-by-dummy-visual-media`; RD-16
media proof comes from tester-observed safe local samples summarized through the
redacted descriptor, not from dummy GIF playback.

RD-16 does not add production native-helper playback, live Plex transport,
preload or contract expansion, product IPC, packaging behavior,
package/dependency/lockfile changes, live renderer Plex APIs, adapter
current-request membership validation, preferred-language selection, or a
Plex HTPC parity claim.

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

## WS2 Playback Implementation Gate

The reviewed WS2 plan checkpoints are `9a66dd6` and `60c68f4`. Package 2A
(`8dc1057`) added bounded 1,000/2,000/4,000 ms current-program recovery.
Package 2B (`d2f1e97`) added the closed Retry-current/Skip-next operation:
`playbackProgramTransitionOwner` and `playerRecoveryIpc` keep exact schedule
identity and transition authority in main, `playerRecoveryBridge` validates the
narrow preload result, and `playerErrorRecoveryController` owns only
renderer-safe focus/busy/error settlement. Both packages received clean final
reviews.

Observed Package 2B proof included 46/46 cleanup/runtime/composition tests,
114/114 remediation tests, 196/196 complete-package tests, 994 aggregate
contract passes plus one intentional skip, 179/179 harness/docs tests,
typecheck, Electron build, static and live Electron smoke, architecture,
maintainability, redaction, docs, full `npm run verify`, and
`git diff --check`. The 794-line runtime and 799-line overlay controller remain
cohesive and below the existing 800-line threshold with no growth headroom.

Package 2D was independently reviewed as a conservative no-op: MP4/H.264/AAC
Direct Play remains the only production profile, subtitle delivery remains
`none`, and audio/subtitle switching, Direct Stream/remux, transcode, HDR, and
Dolby Vision remain unsupported. Its focused profile test passed 2/2; it made
no source, test, evidence, capability, or commit change.

`WS2-POST-VALIDATION-01` carries every unavailable Windows/.NET Release/native
build, live libmpv ERROR/EOF, representative-media, native-video/focus/input,
manual/soak, track-delivery/switching, HDR/display/hardware-capability, and
helper-replacement observation. This is nonblocking post-WS2 debt, not a
support claim or capability promotion.

## WS3 Settings Contributions To Playback

WS3 checkpoints `11dd704` and `1540de3` add the playback-adjacent Settings
consumers while preserving main/helper custody. `DesktopSettingsPolicy`
projects renderer-safe audio, subtitle, HDR, and transcode preferences into
the stream policy and resolver per playback request. Those preferences may
narrow or select only behavior already allowed by the authoritative capability
profile; they never turn `unsupported` or `unproven` into support.

Main constructs at most one production native host and shares it between
player IPC and `SettingsAudioOutputOwner`. Private correlated audio queries,
raw device keys, missing-device fallback, and selected-output/DTS setup remain
inside main/helper custody. Renderer sees only opaque audio ids, bounded labels,
fixed list status/reasons, and the conservative capability projection.
Test-only checkpoint `f0e2817` updates the smoke source-shape proof to require
the one production factory/host invocation and both same-binding consumer
injections while retaining development/smoke fallback assertions. It changes
no playback or Settings runtime source and does not promote capability state.
Prior Unit 3C-D checkpoint `5f368d4` gives the live
`PlexStreamResolver` one optional narrow subtitle-diagnostic port backed by the
existing main-owned diagnostic store. It emits only the reviewed fixed-schema,
bounded policy summary when both Settings admissions allow it; a throwing
recorder cannot change resolver settlement. This makes the local `ST-25`
producer real without claiming Windows subtitle delivery, support-bundle
observation, or a capability promotion.
Final WS3 product checkpoint `87662b5` changes only renderer focus derivation;
it does not alter playback ownership, policy, settlement, or capability state.
Unit 3D acceptance changes only workstream status; all playback proof and
capability gates below remain unchanged.

Renderer-owned Settings lifecycle dispatches exact
`player.pauseIfCurrent`/`player.playIfCurrent` intents with the observed
snapshot request id. `rendererIntentMapping.ts` maps them to the existing empty
internal pause/play command plus nonforwarded expected identity;
`DesktopPlayerAdapter` rejects stale identity before request custody or host
submission and preserves same-turn submission for a matching request. Existing
empty-payload play/pause, `PlayerCommand`, player IPC, privileged dispatch
context, and helper command vocabulary are unchanged.

`PB-22`–`PB-24` remain WS2-owned/open. WS3 has supplied their preference and
control contribution, but `WS3-PROOF-02` and the separate
`WS2-POST-VALIDATION-01` native/live obligations remain open. MP4/H.264/AAC
Direct Play remains the only supported production media path; DTS, subtitle
delivery/switching, HDR/Dolby Vision, Direct Stream, and transcode remain
unsupported or unproven until later reviewed evidence changes the capability
provider.

## WS4 Guarded Input And Sleep Contributions To Playback

WS4 Unit 4A `f4570df` adds only the closed renderer intents
`player.stopIfCurrent` and `player.seekRelativeIfCurrent`, plus required safe
`seekSupport` on load/snapshot projection. The selected main-owned capability
profile remains authoritative; renderer seek is inert unless support is exactly
`supported`. Renderer snapshot identity is validator-checked and mapped only to
the adapter's existing pre-custody expected-identity comparison, never to
`PlayerCommand` or the helper. A stale request creates no custody, host call, or
snapshot mutation. Existing unguarded internal commands and native-helper
protocol remain unchanged.

Unit 4D `3258511`, with post-closeout correction `1f815f3`, reuses guarded
`player.pauseIfCurrent` through the serialized renderer direct-command owner for
sleep expiry. It starts a pause only for the exact current consistent playing
snapshot. When a play or relative-seek command is in flight, the owner retains
exactly one sleep-specific deferred pause, then rereads the safe snapshot and
validates the same request and playing state before dispatch. An in-flight stop
is immediately ineligible. For an accepted deferral, rejection or timeout of the
in-flight play/seek command, route leave, cleanup, request replacement, or failed
fresh validation resolves it as rejected. Immediate ineligibility or deferral
rejection yields bounded UI/diagnostic failure. Once pause dispatch starts, its
settlement remains direct-command-owned; later pause rejection, timeout, or
failure is diagnostic-only, and no outcome retries the pause. The timer remains
session-only and adds no main timing, persistence, power, or lifecycle owner.

Final local proof and full verification pass only the platform-neutral input/
overlay implementation gate. MP4/H.264/AAC Direct Play remains the sole
supported production media path; Direct Stream, transcode, subtitles, DTS,
track switching, HDR/Dolby Vision, and wider seek/native claims remain
unsupported or unproven. `PB-22`–`PB-24` remain WS2-owned/open,
`WS2-POST-VALIDATION-01` and WS3 proof remain separate, `UI-47` remains partial,
and real physical Windows command plus production-native sleep/overlay proof is
`WS4-PROOF-01`/`WS4-PROOF-03`. No upstream source was copied or adapted.

## RD-25 Production Native Playback MVP

RD-25's historical code implementation is complete and reviewed at its recorded
scope; WS2 closes the current platform-neutral implementation gate while
Windows/manual product proof remains open. The production native playback MVP replaces the fake playback bootstrap with a production-shaped, main/helper-owned native playback path for live Plex-backed scheduled media.

### Seam Propagation and Setup Flow

1. **Privileged Setup Handoff**: A main-only privileged load context propagates the `PlexPrivilegedPlaybackDescriptor` from `PlexStreamResolver` through `PlexPlaybackBridge`, `PlexPlaybackRuntime`, and `DesktopPlayerAdapter` into `NativePlayerHostProcess`.
2. **Helper Command Execution**: The process setup is serialized into a private helper command and written to the C# helper (`Lineup.NativePlayerHost`) stdin using NDJSON, preventing secrets from leaking into argv, env, or process lists.
3. **Plex Live Transport Composition**: A live stream resolver composition wires PMS session start/release ports and selected connection/token settings from `DesktopPlexRuntime` to obtain real stream details instead of fake placeholders.
4. **Lifecycle Hooks and Cleanup**: App cleanup, user profile switches, server selection changes, program scheduling transitions, manual stops, and native helper crashes successfully trigger runtime cleanups and PMS session releases.
5. **Renderer Binding**: The renderer player UI dynamically updates from IPC event notifications, keeping track of safe player snapshots without exposing tokenized URLs, credential headers, or libmpv details.

Manual proof of running native playback on Windows is deferred to RD-27, leaving production native playback proof pending.

## RD-26 Runtime Media Options And Playback Quality

RD-26's historical code implementation is complete and reviewed at its recorded
scope; WS2 does not promote the conservative profile, and Windows/manual
product proof remains open. It implements runtime media options and playback quality over the production native playback path.

### Seam Propagation and Setup Flow

1. **Track and Quality State Management**: The C# native helper (`Lineup.NativePlayerHost`) is extended to observe libmpv properties (`aid`, `sid`, `vid`, `video-params`, `video-codec`, `audio-codec`) and emit public track and quality summaries over NDJSON.
2. **Main Selection Validation**: The main process (`DesktopPlayerAdapter` and `playerTrackSelectionValidation.ts`) gates renderer track selection requests against the player snapshot, validating that the request targets the current snapshot and that the requested track exists and is selectable before delegating the actual switch to the native helper.
3. **Renderer Option Views**: The renderer overlay views query the active player snapshot's track and quality summaries to dynamically render track buttons and playback quality status, replacing the old mock controls.
4. **Renderer Action Dispatch**: Selecting a track row or toggling volume/mute in the renderer overlays constructs and dispatches corresponding player intents (`player.selectAudio`, `player.selectSubtitle`, `player.setVolume`, `player.setMute`) to the player bridge.

Manual proof on Windows is deferred to RD-27, leaving production native playback and media options proof pending.
