# Feature Quality Loop Launcher

Use this launcher for Tier 3 Lineup Desktop feature/design work. Tier 3 work is
cross-boundary, multi-session, or high-risk enough that it needs a controller
state machine rather than a one-pass planner/implementer handoff.

## Read Order

1. [`AGENTS.md`](../../../AGENTS.md)
2. [`docs/AGENTIC_DEV_WORKFLOW.md`](../../AGENTIC_DEV_WORKFLOW.md)
3. [`docs/agentic/session-prompts/README.md`](./README.md)
4. [`docs/agentic/plan-authoring-standard.md`](../plan-authoring-standard.md)
5. [`docs/architecture/CURRENT_STATE.md`](../../architecture/CURRENT_STATE.md)
6. active run bundle or tracked plan named by the user

## Use For

- Electron IPC/security boundaries
- native playback or helper process work
- storage/secrets work
- packaging, signing, licensing, or release-gate work
- broad copied/adapted upstream Lineup imports
- multi-session implementation where context loss would create risk

## Controller State Machine

1. `scope-load`
2. `plan`
3. `plan-review`
4. `plan-revise`
5. `execution-unit-select`
6. `implement`
7. `implementation-review`
8. `implementation-revise`
9. `closeout`
10. `done`
11. `blocked`

## Phase Rules

- `scope-load`: confirm Tier 3 routing, load authority docs, identify the exact
  target, initialize `update_plan`, and create or refresh a gitignored local run
  bundle when repeated handoff context is likely.
- `plan`: route plan authoring through a tracked `planner` pass using
  `lineup-desktop-feature-plan`. The controller may resolve controller-only
  routing decisions, but it must not replace the planner for Tier 3 plan
  authoring.
- `plan-review`: use a fresh read-only `reviewer` pass. Do not implement while
  material plan findings remain.
- `plan-revise`: route findings back to planning. Require a clean final review
  when material plan blockers were fixed.
- `execution-unit-select`: choose one approved bounded unit from the plan.
  Parallel units require explicit disjoint owners, files, and verification.
- `implement`: use a tracked `worker` pass for the approved execution unit. If
  the work is small enough for controller-local editing, downgrade the task out
  of this Tier 3 loop before editing.
- `implementation-review`: use a fresh read-only `reviewer` pass against the
  implemented unit, observed verification, and current diff.
- `implementation-revise`: fix accepted findings inside the approved unit. Route
  missing decisions or changed boundaries back to planning.
- `closeout`: rerun required verification, audit the diff, update required docs,
  and ensure import ledger and redaction rules are satisfied.
- `done`: use only when review is clean, verification passed, and closeout
  memory surfaces are current.
- `blocked`: use when progress requires user input, a boundary decision, or a
  workflow exception.

## Completion Gate

The controller may call the task complete only when:

- plan review is clean
- every implemented execution unit has clean implementation review
- required verification commands were observed
- import ledger, architecture docs, plan status, and run-bundle conclusions are
  current where applicable
- no material desktop feature quality guardrail finding remains

## Output Contract

Return:

1. current phase reached
2. artifacts produced or updated
3. verification performed
4. review status and any blocking findings
5. next exact action if not complete
6. whether the task is `done`, `closeout pending`, or `blocked`
