# Playback Architecture

Lineup Desktop playback is not implemented yet.

## Current Hypothesis

The production hypothesis is Electron plus a helper-hosted native libmpv path.
The helper process should isolate native media crashes and secret-bearing
playback setup from the renderer.

External `mpv` IPC may be used only as a private disposable POC to learn about
media behavior. It must not become production architecture.

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

Player integration must start from `src/contracts/player.ts` and its tests.
Concrete playback adapters must not leak native handles, raw media URLs, raw auth
headers, or engine-specific track ids into renderer-facing state without an
explicit reviewed contract.

Renderer-facing track state uses opaque UI ids only. Privileged mappings to
engine ids or Plex stream ids belong behind main/helper or domain-owned
boundaries and require a reviewed contract before they are introduced.
