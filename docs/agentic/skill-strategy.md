# Skill And Role Strategy

Lineup Desktop keeps the control plane small while preserving the role
separation needed for production-quality Electron work.

## Tracked Surfaces

- `.codex/config.toml` declares available Codex roles for this repo.
- `.codex/agents/*.toml` owns role defaults and role-specific instructions.
- `.agents/skills/*/SKILL.md` contains thin Desktop project skill wrappers.
- `docs/agentic/session-prompts/*.md` owns launcher policy.
- `docs/AGENTIC_DEV_WORKFLOW.md` owns workflow routing and verification.

## Codex Skill Discovery

Use `.agents/skills/` as the repository-scoped project skill home. Current
OpenAI Codex skills guidance says repository skills are discovered from
`.agents/skills` from the current working directory up to the repository root:
<https://developers.openai.com/codex/skills#where-to-save-skills>.

Keep `.codex/config.toml` and `.codex/agents/*.toml` for repo role/team
configuration. Do not create a parallel `.codex/skills/` tree unless a future
reviewed Codex configuration pass proves that this repo needs both locations.
Duplicating the same skill policy in two trees would create drift without
improving fresh-chat reliability.

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

## Legacy Skill Adaptation Audit

The original Lineup repo's local skills were not copied wholesale. Desktop is a
greenfield Windows-first Electron repo, so it carries forward the production
guardrails that apply here and leaves historical maintenance-program mechanics
behind.

| Original Skill Area | Desktop Adaptation |
| --- | --- |
| plan authoring | `docs/agentic/plan-authoring-standard.md` plus `lineup-desktop-feature-plan`; plans still require scope, seam, verification classification, acceptance criteria, rollback, and replan triggers. |
| verification strategy | `docs/AGENTIC_DEV_WORKFLOW.md#verification-routing` plus active-plan verification classification; use focused contract, architecture, redaction, smoke, or manual proof instead of defaulting every change to brittle tests. |
| closeout verification | `docs/AGENTIC_DEV_WORKFLOW.md#verification-routing`, `docs/AGENTIC_DEV_WORKFLOW.md#review-before-closeout`, and the feature-quality-loop closeout phase; completion claims require observed evidence. |
| review request and adjudication | `lineup-desktop-feature-review`, `lineup-desktop-workflow-harness-review`, and the controller's revise phases; reviewers stay read-only and the owning session adjudicates findings. |
| bounded workers and sidecars | `.codex/agents/*.toml` plus `feature-quality-loop.md`; delegate only bounded, disjoint units after plan/review gates. |
| architecture boundaries | `docs/AGENTIC_DEV_WORKFLOW.md#desktop-feature-quality-guardrails`, `docs/architecture/CURRENT_STATE.md`, and task-specific architecture docs; Electron main, preload, renderer, helper, Plex, scheduler, and packaging owners must stay narrow. |
| persistence, Plex, UI, and playback boundaries | `docs/architecture/security-and-secret-flow.md`, `docs/architecture/playback-architecture.md`, `docs/architecture/import-ledger.md`, current-state docs, and active plans; add a new project skill only after repeated Desktop work shows a thinner launcher is not enough. |
| debugging and model guidance | Use the feature/design workflow, current architecture docs, official docs checks, and Tier 3 model guidance when requested or when the plan is high risk; add dedicated skills later only from observed repeated need. |

When a future Desktop workflow repeatedly needs one of these areas as a direct
skill trigger, add a small `.agents/skills/lineup-desktop-*` wrapper in a
reviewed workflow pass and update this audit with the new owner.

## Local-Only Artifacts

Do not commit generated agent mirrors, caches, or run state:

- `.agent/`
- `.codex/cache/`
- `docs/runs/*` except `docs/runs/README.md`
