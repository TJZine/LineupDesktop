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

## Release Gates

Before public distribution, this repo must verify:

- credential storage availability and fallback behavior on Windows
- backup/restore and recovery behavior for encrypted credentials
- redaction scanner coverage for docs, tests, fixtures, diagnostics, and logs
- no token-bearing material in renderer-facing contracts
