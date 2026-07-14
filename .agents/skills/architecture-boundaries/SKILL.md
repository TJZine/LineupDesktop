---
name: architecture-boundaries
description: Use when Lineup Desktop work changes Electron process ownership, module boundaries, composition roots, IPC wiring, renderer/preload/main/helper responsibilities, or shared contracts.
---

# Architecture Boundaries

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/architecture/CURRENT_STATE.md`
4. the task-specific architecture doc named by the plan

Keep one owner per runtime concern:

- Electron main owns app lifecycle, windows, app paths, privileged IPC, and
  redacted diagnostics.
- Preload owns the narrow validated bridge and must not become a broad RPC
  passthrough.
- Renderer owns UI composition and renderer-safe state only.
- Native/helper code owns native playback process concerns only after a reviewed
  plan proves that boundary.
- Contracts own renderer-safe public shapes, not secrets, handles, Electron
  objects, or token-bearing values.

If the change touches persisted state, Plex, or renderer UI/focus/media
composition, also load `persistence-boundaries`, `plex-integration-boundaries`,
or `ui-composition-patterns`.

Before editing, name the seam, files in scope, files out of scope, verification
proof, and stop/replan triggers. Stop if implementation would add compatibility
barrels, old upstream path shims, broad utility owners, or privileged renderer
access not approved by the plan.

Decide file shape from present responsibilities, not a target line count:

- Keep behavior together when it shares the owner's invariants, state,
  lifecycle, and reason to change.
- Extract when the change introduces a distinct current policy, lifecycle,
  trust boundary, or consumer and the extracted module owns meaningful logic.
- Do not extract for line count, test convenience, speculative reuse, or a
  preferred pattern. Reject forwarding wrappers and one-method "services."
- Keep composition roots to wiring and lifecycle coordination; move domain
  policy to its real owner.
- For a touched owner over 500 lines, record `Owner`, `Existing responsibility`,
  `New behavior`, `Decision: cohesive growth | extract`, and evidence.
- For a file over 800 lines, a named hotspot, or a composition root, require a
  fresh `reviewer` architecture review. Size triggers review, never an
  automatic split or failure.
