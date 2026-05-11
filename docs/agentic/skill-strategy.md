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

Desktop project skills have two forms:

- launcher wrappers named `lineup-desktop-*`
- same-name Lineup workflow and boundary skills adapted for Desktop

Both forms should load `AGENTS.md`, `docs/AGENTIC_DEV_WORKFLOW.md`, and the
matching launcher, architecture doc, or plan standard before adding local
instructions. Keep detailed workflow policy in tracked docs; keep skill bodies
focused on trigger routing, owner boundaries, and task-local checklists.

Add new project skills only when a repeated workflow or boundary problem needs a
stable trigger. Prefer architecture docs or launchers for one-off guidance.

## Current Project Skills

Launcher wrappers:

- `lineup-desktop-feature-plan`
- `lineup-desktop-feature-implement`
- `lineup-desktop-feature-review`
- `lineup-desktop-feature-quality-loop`
- `lineup-desktop-workflow-harness-review`

Reusable Lineup workflow and boundary skills adapted for Desktop:

- `architecture-boundaries`
- `bounded-worker-execution`
- `closeout-verification`
- `debugging-remediation`
- `execution-plan-authoring`
- `model-selection`
- `parallel-sidecars`
- `persistence-boundaries`
- `plex-integration-boundaries`
- `repo-production-review`
- `review-adjudication`
- `review-request`
- `ui-composition-patterns`
- `verification-strategy`

## Legacy Skill Adaptation Audit

The original Lineup repo's local skills are not copied byte-for-byte. Desktop is
a greenfield Windows-first Electron repo, so reusable skill triggers are
materialized as same-name Desktop adaptations while historical
maintenance-program mechanics stay behind.

| Original Skill Area | Desktop Adaptation |
| --- | --- |
| plan authoring | `execution-plan-authoring`, `docs/agentic/plan-authoring-standard.md`, and `lineup-desktop-feature-plan`; plans still require scope, seam, verification classification, acceptance criteria, rollback, and replan triggers. |
| verification strategy | `verification-strategy`, `docs/AGENTIC_DEV_WORKFLOW.md#verification-routing`, and active-plan verification classification; use focused contract, architecture, redaction, smoke, or manual proof instead of defaulting every change to brittle tests. |
| closeout verification | `closeout-verification`, `docs/AGENTIC_DEV_WORKFLOW.md#review-before-closeout`, and the feature-quality-loop closeout phase; completion claims require observed evidence. |
| review request and adjudication | `review-request`, `review-adjudication`, `lineup-desktop-feature-review`, and `lineup-desktop-workflow-harness-review`; reviewers stay read-only and the owning session adjudicates findings. |
| bounded workers and sidecars | `bounded-worker-execution`, `parallel-sidecars`, `.codex/agents/*.toml`, and `feature-quality-loop.md`; delegate only bounded, disjoint units after plan/review gates. |
| architecture boundaries | `architecture-boundaries`, `docs/AGENTIC_DEV_WORKFLOW.md#desktop-feature-quality-guardrails`, `docs/architecture/CURRENT_STATE.md`, and task-specific architecture docs; Electron main, preload, renderer, helper, Plex, scheduler, and packaging owners must stay narrow. |
| persistence, Plex, UI, and playback boundaries | `persistence-boundaries`, `plex-integration-boundaries`, `ui-composition-patterns`, `docs/architecture/security-and-secret-flow.md`, `docs/architecture/playback-architecture.md`, `docs/architecture/import-ledger.md`, current-state docs, and active plans. |
| debugging and model guidance | `debugging-remediation`, `model-selection`, the feature/design workflow, current architecture docs, and official docs checks. |

When a future Desktop workflow repeatedly needs a new direct trigger, add a
small `.agents/skills/lineup-desktop-*` or same-name Lineup adaptation in a
reviewed workflow pass and update this audit with the new owner.

## Local-Only Artifacts

Do not commit generated agent mirrors, caches, or run state:

- `.agent/`
- `.codex/cache/`
- `docs/runs/*` except `docs/runs/README.md`
