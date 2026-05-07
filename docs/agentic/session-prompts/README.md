# Session Launcher Templates

This directory contains the initial Lineup Desktop launcher templates.

## Launcher Template Set

- [`feature-plan.md`](./feature-plan.md): serious feature/design planning
- [`feature-implement.md`](./feature-implement.md): implementation of an
  approved feature/design plan
- [`feature-review.md`](./feature-review.md): read-only adversarial review of a
  plan or implementation
- [`workflow-harness-review.md`](./workflow-harness-review.md): read-only review
  of workflow, role, verifier, and control-plane behavior

## Routing

All work routes as feature/design unless this repository later creates its own
reviewed cleanup backlog. Serious work uses planner -> reviewer -> worker ->
reviewer sequencing.

Use a task-specific run bundle in [`docs/runs/`](../../runs/README.md) when work
is cross-boundary or likely to span sessions, especially Electron IPC/security,
native playback, storage/secrets, packaging, or broad imports.
