---
name: ui-composition-patterns
description: Use when Lineup Desktop work builds or refactors renderer screens, overlays, focus flows, keyboard/remote interactions, media surfaces, motion, or desktop UI composition.
---

# UI Composition Patterns

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/architecture/CURRENT_STATE.md`
4. task-specific UI or architecture docs named by the plan

Desktop renderer UI stays unprivileged and display-focused:

- UI code must not own Plex transport, secret storage, native playback process
  control, app paths, packaging policy, or raw Electron APIs.
- Keep focus, keyboard/remote interactions, timers, subscriptions, and media
  surface lifecycle explicit and cleaned up.
- Prefer renderer-safe view models and public seams over private probing or
  broad snapshots.
- Preserve accessibility, reduced-motion behavior, and visual/manual proof when
  layout, focus, motion, or media presentation changes.

If UI work touches persisted preferences, Plex-driven state, or Electron process
ownership, load `persistence-boundaries`, `plex-integration-boundaries`, or
`architecture-boundaries`.

Use existing Lineup UI patterns where they fit, but do not add old webOS path
shims or compatibility wrappers just to preserve upstream file shapes.
