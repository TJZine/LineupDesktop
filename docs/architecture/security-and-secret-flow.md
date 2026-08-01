# Security And Secret Flow

Persistent Plex credentials belong outside the renderer.

## Initial Policy

- Renderer receives safe auth/profile/server state and sends typed intents.
- Electron main owns secure credential storage and app data paths.
- A privileged helper may receive only the minimum secret-bearing playback
  material needed to load media.
- Preload exposes narrow methods, not raw Electron APIs.
- Renderer-originating and helper-originating payloads are schema validated.
- Token-bearing headers may exist only inside privileged main/helper network or
  playback setup.
- Token-bearing URLs are forbidden outside the same privileged setup boundary;
  prefer header-based auth when the playback stack allows it.
- If an import appears to require renderer token access, stop and replan the
  boundary instead of adding an exception.

## Current Shell Boundary

The initial Electron shell serves local renderer content only from
`lineup://shell/index.html`. Electron main owns shell/window IPC handlers and
authorizes calls against the expected `webContents`, main frame, and
`lineup://shell` origin before acting.

Preload exposes only the typed `window.lineupDesktop` shell/window API. It does
not expose raw `ipcRenderer`, arbitrary channel names, Node modules, Electron
objects, filesystem access, native handles, tokens, or auth headers.

The minimal renderer is sandboxed and context-isolated. Runtime smoke
verification checks that `process`, `require`, `Buffer`, raw Electron bridge
names, navigation/new-window/permission containment, CSP, and the approved
preload bridge behave as expected.

## Current Persistence Boundary

RD-09 adds a main-owned persistence core under `src/main/persistence/*`.
Electron `safeStorage` is represented by an injected async codec seam, so the
store can fail closed when encryption is unavailable without falling back to
plaintext. App-data paths are resolved only in the main-owned persistence
module, and renderer-safe snapshots expose account summaries, credential
handles, selected-server summaries, storage status, and redacted diagnostics
only.

The persistence file stores encrypted Plex credential records and
selected-server state. Main-owned credential reads may recover the decrypted
value for future Plex auth/runtime owners, but preload, renderer, player,
stream policy, tests, docs, diagnostics, and IPC contracts must not receive raw
credential values, raw headers, tokenized URLs, raw Plex payloads, filesystem
paths, Electron objects, Node APIs, or secret diagnostics.

Encrypted credential backup/restore remains a release-gate risk. Records are
expected to be bound to the local OS user/profile and may be unrecoverable
after machine, profile, or password-manager changes. A future release plan must
prove restore behavior, recovery UX, and credential cleanup before public
distribution.

Package 4 and WS3 own a separate, non-secret Desktop Settings record at
`<appData>/lineup-desktop-settings.json`. Electron main alone resolves this
path and owns serialized whole-record compare-and-swap reads, version-1 to
version-2 migration, normalization, and replacements. Writes use a
same-directory mode-0600 temporary file and atomic rename; corrupt or
unsupported schema bytes are neither rewritten nor replaced. The renderer
holds only ephemeral renderer-safe Settings values, capability projection,
revision, and fixed status/error state and has no filesystem, browser-storage,
migration, or fallback-store access.

Preload exposes exactly `settings.getSnapshot`, `settings.replace`, and
`settings.getAudioOutputs` on the existing `window.lineupDesktop` namespace.
It validates exact request/result shapes and request-id echoing, catches invoke
rejection, and never exposes raw Electron, filesystem paths, record contents,
native device keys, or exception detail. Main applies the existing shell
sender, main-frame, and `lineup://shell` origin authorization before delegating
to the Settings store or audio-output owner. All expected failures resolve one
fixed renderer-safe typed result rather than rejecting.

`DesktopSettingsPolicy` caches only the last accepted renderer-safe snapshot
and projects narrow preference inputs to stream policy, Plex resolution,
diagnostic admission, and private native setup. `SettingsAudioOutputOwner`
alone maps raw native audio keys to stable opaque ids and bounded labels;
persisted `null` means System Default. Raw keys remain ephemeral in main/helper
custody and are resolved immediately before private setup. Main shares the one
production helper host with player IPC; private audio-query correlation,
timeout, quarantine, crash, and cleanup use that same process owner.
Test-only checkpoint `f0e2817` strengthens smoke proof that main constructs one
production host and injects the same binding into player IPC and the audio
owner, while keeping the optional factory inside development/smoke custody. It
adds no runtime path, secret flow, renderer exposure, or capability claim.
Prior Unit 3C-D checkpoint `5f368d4` connects the accepted Settings and
subtitle debug admissions to two production events with exact fixed keys,
bounded closed values, and no ids, labels, language text, connection/auth data,
URLs, headers, paths, raw Plex/native values, diagnostic arrays, or free-form
errors. Recording is best-effort: a throwing recorder cannot alter Settings
acceptance or playback settlement. Windows support-bundle contents and
redaction remain proof-open.
Final WS3 product checkpoint `87662b5` is a two-file renderer focus repair and
adds no secret flow, privileged custody, diagnostic field, or public surface.
Unit 3D acceptance changes only workstream status and no security boundary.

WS3 also adds exact request-bound `player.pauseIfCurrent` and
`player.playIfCurrent` renderer intents on the existing player channel.
Preload admits only the literals and exact outer envelope. Main validates the
snapshot request id and rejects stale identity before custody or host
submission; the identity is never added to `PlayerCommand`, privileged setup,
or helper input. No Settings value, capability, audio row, intent, diagnostic,
or proof artifact may expose credentials, headers, tokenized URLs, paths, raw
payloads, native handles, helper output, or raw device ids.

## Current Plex Domain Boundary

RD-10 adds main-owned Plex library, auth, and discovery modules under
`src/main/plex/*`. Auth and discovery remain behind injected transport seams,
and credential persistence goes through the RD-09 store adapter only. Renderer
contracts in `src/contracts/plex.ts` expose profile, home-user, server, health,
selection, and library summaries without raw credentials, headers, tokenized
URLs, connection URIs, raw Plex payloads, filesystem paths, or image keys.

Selected-server restore persists and restores only the RD-09 selected-server
summary. The current connection is resolved by fresh discovery/probing and may
exist only in main-owned runtime memory. RD-10 does not wire live Plex
transport, preload/renderer Plex APIs, real Electron safeStorage/app paths, or
OS-specific credential behavior.

## Current Plex Playback Boundary

RD-12 adds a main-owned Plex-to-player boundary without adding renderer or
preload Plex APIs. The stream resolver may consume selected-connection,
credential, media-detail, and PMS-session ports inside main-owned code, but it
projects only renderer-safe player load payloads, policy decisions, safe
diagnostics, and request-scoped PMS lease summaries across public seams.
Private playback descriptors may contain privileged playback setup for future
main/helper use, but they are not persisted, logged, returned through contracts,
included in renderer-facing fixtures, or exposed to preload/renderer code.

The playback runtime owns PMS cleanup and stale-event custody. It binds PMS
leases to the active player request, releases stale or rejected leases, rejects
mismatched leases before player dispatch, and normalizes cleanup, resolver, and
player failures into renderer-safe player events. Stop, switch, error, logout,
server change, profile change, helper crash, teardown, failed resolver/player
load, and stale candidate paths are all covered by injected tests.

RD-12 keeps raw tokens, auth headers, raw Plex payloads, tokenized URLs,
runtime filesystem paths, Electron/Node objects, and native/helper internals
out of renderer-facing contracts, fixtures, diagnostics, docs, and Codex
output. Production native-helper playback, live Plex transport composition,
real Electron app-path or `safeStorage` wiring, packaging, and
Windows-specific proof surfaces remain future replanning triggers.

## UI Parity Closeout Boundary

Packages 5–8 completed scheduler-backed Guide presentation, runtime Player and
overlay state, overlay presentation parity, and integrated local proof without
widening renderer privilege or secret custody. They added no IPC/preload method,
persistence schema or owner, native-helper behavior, raw playback descriptor,
token-bearing URL/header, raw Plex payload, filesystem path, or native handle to
renderer-facing state. Package 8 evidence is ignored and indexed only by
sanitized metadata, hashes, and counts. Windows operational proof remains an
RD-27 gate and does not change these trust boundaries.

## Release Gates

Before public distribution, this repo must verify:

- credential storage availability and fallback behavior on Windows
- backup/restore and recovery behavior for encrypted credentials
- redaction scanner coverage for docs, tests, fixtures, diagnostics, and logs
- no token-bearing material in renderer-facing contracts
