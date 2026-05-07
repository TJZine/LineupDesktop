# Session Launcher Templates

This directory contains the tracked Lineup Desktop launcher templates. Local
project skills in `.agents/skills/` should stay thin and point back to these
files instead of duplicating policy.

## Launcher Template Set

- [`feature-plan.md`](./feature-plan.md): serious feature/design planning
- [`feature-review.md`](./feature-review.md): read-only adversarial review of a
  feature/design plan or implementation
- [`feature-implement.md`](./feature-implement.md): implementation of an
  approved feature/design plan
- [`feature-quality-loop.md`](./feature-quality-loop.md): Tier 3 controller for
  cross-boundary feature/design work
- [`workflow-harness-review.md`](./workflow-harness-review.md): read-only review
  of workflow, role, verifier, skill, and control-plane behavior

## Routing

All work routes as feature/design unless this repository later creates its own
reviewed maintenance backlog. Serious Tier 2 work uses:

```text
feature-plan -> feature-review -> feature-implement -> feature-review
```

Tier 3 work uses a task-specific run bundle in
[`docs/runs/`](../../runs/README.md) plus the feature-quality loop when work is
cross-boundary or likely to span sessions, especially Electron IPC/security,
native playback, storage/secrets, packaging, release gates, or broad imports.

Do not use upstream cleanup program artifacts, detector ids, score artifacts, or
package mechanics as desktop routing authority.

## Project Skill Names

Recommended project skill entrypoints:

- `lineup-desktop-feature-plan`
- `lineup-desktop-feature-review`
- `lineup-desktop-feature-implement`
- `lineup-desktop-feature-quality-loop`
- `lineup-desktop-workflow-harness-review`

Each skill should load `AGENTS.md`, `docs/AGENTIC_DEV_WORKFLOW.md`, and the
matching launcher in this directory, then follow the tracked launcher exactly.
