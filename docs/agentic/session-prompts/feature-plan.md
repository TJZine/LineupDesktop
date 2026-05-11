# Feature Plan Launcher

Use this launcher to write or refresh a serious Lineup Desktop feature/design
plan. Run it with the tracked `planner` role when delegated planning is useful.

## Read Order

1. [`AGENTS.md`](../../../AGENTS.md)
2. [`docs/AGENTIC_DEV_WORKFLOW.md`](../../AGENTIC_DEV_WORKFLOW.md)
3. [`docs/agentic/external-guidance.md`](../external-guidance.md) when planning
   workflow, harness, skill, verifier, or agent-control changes
4. [`docs/agentic/plan-authoring-standard.md`](../plan-authoring-standard.md)
5. [`docs/architecture/CURRENT_STATE.md`](../../architecture/CURRENT_STATE.md)
6. task-specific architecture docs, run bundle, or source files

## Invocation Inputs

Accept either:

- a pasted `NEXT_SESSION_HANDOFF` block naming `TASK`, `PLAN`, `ARTIFACT`,
  `FILES`, and `MESSAGE`
- one short follow-up naming the feature/design scope, plan seed, or run bundle

Do not wait for a formal handoff when the short follow-up gives an unambiguous
scope.

## Required Work

- Confirm this is feature/design work and choose Tier 1, Tier 2, or Tier 3.
- Use `update_plan` for authoritative state.
- Gather source evidence before freezing scope. Use Codanna or direct reads as
  appropriate, and record fallback when the preferred tool is unavailable or not
  the right surface.
- Resolve architecture, IPC, renderer/preload/main/helper, playback, storage,
  packaging, and import decisions before implementation steps are locked.
- Produce or refresh a tracked plan in `docs/plans/` only while active durable
  handoff memory is needed; after closeout, durable conclusions move to roadmap,
  architecture, import-ledger, workflow, or verifier docs and the full plan body
  moves to the local ignored archive.
- For Tier 3, identify the first bounded execution unit and whether any
  parallelism is allowed.
- Run the Planner Self-Check from the plan standard before calling the plan
  implementation-ready.

## Output Requirements

- Satisfy [`plan-authoring-standard.md`](../plan-authoring-standard.md) for
  active tracked plans.
- Declare `**Task family:** feature/design`.
- Name the architecture seam, files in scope, files out of scope, invariants,
  verification commands, expected outcomes, acceptance criteria, rollback notes,
  and replan triggers.
- Record import ledger obligations when copied/adapted upstream code is in
  scope.
- Include a `NEXT_SESSION_HANDOFF` routing the plan to
  `lineup-desktop-feature-review`.
- Include model guidance only when the user asks for it or the plan is Tier 3.
- Use the exact handoff shape in
  [`docs/AGENTIC_DEV_WORKFLOW.md#session-handoffs`](../../AGENTIC_DEV_WORKFLOW.md#session-handoffs).
