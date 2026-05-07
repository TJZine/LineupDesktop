# Feature Implement Launcher

Use this launcher to implement an approved Lineup Desktop feature/design plan.
Tier 2 uses the tracked `worker` role. Tier 3 uses the same implementer inside
the feature-quality loop with the active run bundle as task context.

## Read Order

1. [`AGENTS.md`](../../../AGENTS.md)
2. [`docs/AGENTIC_DEV_WORKFLOW.md`](../../AGENTIC_DEV_WORKFLOW.md)
3. the approved plan or active run bundle named by the handoff
4. [`docs/agentic/plan-authoring-standard.md`](../plan-authoring-standard.md)
5. [`docs/architecture/CURRENT_STATE.md`](../../architecture/CURRENT_STATE.md)
6. domain docs, source files, and skills named by the plan

## Rules

- Load the approved plan before editing.
- Re-check that the plan is fresh. If repo state contradicts the plan, update or
  re-review the plan before editing.
- Keep implementation inside the approved files, owner, and seam.
- Execute one bounded unit at a time unless the plan explicitly authorizes
  parallel work.
- Stop and replan if Electron IPC/security, native playback, storage/secrets,
  packaging, release gates, or import scope changes beyond the plan.
- Do not copy upstream Lineup code without updating
  [`import-ledger.md`](../../architecture/import-ledger.md) before or with the
  import.
- Do not expose persistent tokens, raw Electron APIs, native handles, raw auth
  headers, or tokenized URLs to renderer-facing contracts.
- Do not add fallback paths, compatibility shims, or temporary adapters unless
  the plan explicitly authorizes them with a removal trigger.
- Run the verification named by the plan before closeout.

## Closeout

Report files changed, commands run, observed results, remaining risks, and
review status. Do not claim verification that was not observed.

End with a `NEXT_SESSION_HANDOFF` routing the implementation to
`lineup-desktop-feature-review` unless the task is blocked before code changes.
