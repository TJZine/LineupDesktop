# Desktop Repo Genesis ADR

- **Status**: Accepted
- **Date**: 2026-05-07
- **Drivers**: Windows desktop port, Electron shell direction, native playback
  requirements, workflow/control-plane preservation, and prevention of new debt
  at repo genesis.

## Context

Lineup Desktop is a separate Windows-first repository. It starts from the
accepted upstream decision that desktop should not mutate the webOS app into a
multi-platform monolith.

The desktop app will reuse proven Lineup concepts and platform-neutral
TypeScript modules where practical, but it needs a different runtime, security
model, storage model, media engine, packaging model, and verification surface.

## Decision

Create Lineup Desktop as a separate Electron desktop repository.

Initial reuse is copy/adapt by coherent slice with an import ledger. Shared
package extraction is not a genesis default; it is allowed later only when
repeated maintenance pressure proves it is better than ledgered divergence.

The production playback hypothesis is Electron plus a helper-hosted native
libmpv path. The helper approach is preferred at genesis because it isolates
native media crashes and secret-bearing playback operations from the renderer.
External `mpv` IPC may be used only as a private disposable learning spike.

The renderer must be unprivileged. Persistent Plex tokens and credential storage
must not live in the renderer. Electron main and/or a privileged helper own
secrets, secure storage, token-bearing playback setup, redacted diagnostics,
window lifecycle, and native process coordination. If an import appears to
require renderer token access, the import must stop and replan the boundary.

Private MVP and spike builds may use GPL-capable media binaries when that is the
fastest way to prove playback. Public distribution is blocked until this repo
records a licensing and binary-provenance decision for the exact artifacts being
shipped.

The intended public Windows release shape is a signed NSIS x64 installer.
Unsigned dev, unpacked, or portable internal artifacts are acceptable before MVP.
Auto-update is deferred until signing, release channels, rollback behavior, and
native binary layout are stable.

## Non-Goals

- No Electron runtime implementation in this scaffold.
- No Plex, scheduler, navigation, UI, settings, or player implementation import
  before an import ledger row exists.
- No workspace, shared package, or compatibility-shim mirror at repo genesis.
- No Chromium `<video>` as final desktop playback architecture.
- No external `mpv` IPC as production architecture.
- No cloud sync, telemetry, plugin architecture, public installer, auto-update,
  Microsoft Store distribution, or macOS/Linux release support in genesis scope.
- No upstream cleanup backlog or score artifacts as active desktop authority.

## Consequences

Positive:

- Keeps desktop architecture clean while preserving proven Lineup concepts.
- Forces workflow and verification to exist before product implementation.
- Makes source provenance explicit for every copied/adapted slice.
- Creates release gates for secrets, playback, licensing, packaging, and
  diagnostics.

Negative:

- Copy/adapt reuse creates temporary divergence from upstream Lineup.
- Separate repo maintenance requires import ledger discipline.
- Helper-hosted native playback adds process and IPC complexity.
- Public release waits on licensing and signing decisions private MVP work can
  defer but not ignore.
