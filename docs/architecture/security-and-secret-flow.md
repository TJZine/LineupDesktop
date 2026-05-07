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

## Release Gates

Before public distribution, this repo must verify:

- credential storage availability and fallback behavior on Windows
- backup/restore behavior for encrypted credentials
- redaction scanner coverage for docs, tests, fixtures, diagnostics, and logs
- no token-bearing material in renderer-facing contracts
