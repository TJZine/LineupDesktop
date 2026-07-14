# File Shape Guardrails

Lineup Desktop uses file size as an architecture attention signal, never as a
decomposition target or CI failure. Cohesion, ownership, dependency direction,
and present requirements decide whether code stays together or is extracted.

## Policy

- Run `npm run verify:maintainability` after changing production source shape.
  It reports deterministic evidence and never approves or rejects a design.
- A touched production owner over 500 lines needs this compact disposition:

  ```text
  Owner:
  Existing responsibility:
  New behavior:
  Decision: cohesive growth | extract
  Evidence:
  ```

- A file over 800 lines, a named hotspot below, or a composition root requires
  a fresh `reviewer` architecture review before closeout.
- Line count alone never requires extraction. Keep behavior together when it
  shares the owner's invariants, state, lifecycle, and reason to change.
- Extract only a distinct current policy, lifecycle, trust boundary, or
  consumer into a module that owns meaningful logic. Do not create forwarding
  wrappers, speculative interfaces, or one-method services to reduce a count.
- Composition roots own wiring and lifecycle coordination, not domain policy.
  Dependency and Electron privilege rules remain hard mechanical gates.

## Named Review Surfaces

Review these whenever touched, regardless of their current line count:

- `src/main/index.ts`: main-process composition root
- `src/preload/index.cts`: sandboxed preload bridge composition root
- `src/renderer/index.ts`: renderer composition root
- `src/domain/channel/channelManager.ts`: channel mutation and state owner
- `src/main/player/desktopPlayerAdapter.ts`: player boundary adapter

Update this list only when architecture ownership changes. Do not use it as an
allowlist or line-count baseline.
