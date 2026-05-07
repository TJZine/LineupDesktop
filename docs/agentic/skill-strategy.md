# Skill And Role Strategy

Lineup Desktop keeps the control plane small while preserving the role
separation needed for production-quality Electron work.

## Tracked Surfaces

- `.codex/config.toml` declares available Codex roles for this repo.
- `.codex/agents/*.toml` owns role defaults and role-specific instructions.
- `.agents/skills/*/SKILL.md` contains thin Desktop project skill wrappers.
- `docs/agentic/session-prompts/*.md` owns launcher policy.
- `docs/AGENTIC_DEV_WORKFLOW.md` owns workflow routing and verification.

## Role Policy

Use the smallest role set that keeps work reliable:

- `explorer`: read-only evidence and impact discovery
- `docs_researcher`: read-only official documentation checks
- `planner`: durable plans and handoff artifacts
- `worker`: one bounded implementation unit
- `reviewer`: read-only adversarial review
- `monitor`: waits, polling, and status checks

Desktop does not define a dedicated maintenance-worker role yet. If this repo
later needs a maintenance backlog, add that role in a separate reviewed
workflow pass.

## Project Skill Policy

Desktop project skills should stay thin. They should load:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. the matching tracked launcher or architecture doc

Then they should follow the tracked doc instead of duplicating policy.

Add new project skills only when a repeated workflow or boundary problem needs a
stable trigger. Prefer architecture docs or launchers for one-off guidance.

## Current Project Skills

- `lineup-desktop-feature-plan`
- `lineup-desktop-feature-implement`
- `lineup-desktop-feature-review`
- `lineup-desktop-feature-quality-loop`
- `lineup-desktop-workflow-harness-review`

## Local-Only Artifacts

Do not commit generated agent mirrors, caches, or run state:

- `.agent/`
- `.codex/cache/`
- `docs/runs/*` except `docs/runs/README.md`
