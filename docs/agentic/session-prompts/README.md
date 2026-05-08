# Session Launcher Templates

This directory contains the tracked Lineup Desktop launcher templates. Launcher
skills in `.agents/skills/lineup-desktop-*` should stay thin and point back to
these files instead of duplicating policy. Same-name workflow and boundary
skills may add concise Desktop-specific checklists, but this directory and the
main runbook remain the launcher authority.

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

## Launcher Routing Matrix

| Need | Use | Expected Next Gate |
| --- | --- | --- |
| Create or refresh a serious feature/design plan. | `lineup-desktop-feature-plan` / `feature-plan.md` | Read-only plan review. |
| Implement one approved feature/design execution unit. | `lineup-desktop-feature-implement` / `feature-implement.md` | Read-only implementation review. |
| Review a plan, implementation, diff, or review-fix handoff. | `lineup-desktop-feature-review` / `feature-review.md` | Plan revision, implementation, or closeout. |
| Orchestrate Tier 3 cross-boundary work across planning, review, implementation, and closeout. | `lineup-desktop-feature-quality-loop` / `feature-quality-loop.md` | Continue the controller state machine until clean closeout or blocked. |
| Review workflow, role, verifier, launcher, project-skill, or control-plane changes. | `lineup-desktop-workflow-harness-review` / `workflow-harness-review.md` | Adjudicate findings, then rerun `npm run verify:docs`. |

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

## Handoff Format

When another session is expected, launchers should emit the
`NEXT_SESSION_HANDOFF` shape defined in
[`docs/AGENTIC_DEV_WORKFLOW.md#session-handoffs`](../../AGENTIC_DEV_WORKFLOW.md#session-handoffs).
Do not make users reconstruct the next launcher, plan path, files, or message
from prose.
