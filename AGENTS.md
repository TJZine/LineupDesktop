# Agents

This file is the entrypoint map for Lineup Desktop's control plane.
Use [`docs/AGENTIC_DEV_WORKFLOW.md`](./docs/AGENTIC_DEV_WORKFLOW.md) as the
single operating runbook for workflow, precedence, verification routing, and
where to look next.

## Always-On Defaults

- Keep the authoritative execution state in Codex `update_plan`.
- Treat implementation plans as local by default; promote them into
  `docs/plans/*` only when durable handoff memory is needed.
- Use [`docs/architecture/CURRENT_STATE.md`](./docs/architecture/CURRENT_STATE.md)
  for current architecture truth.
- Use [`docs/architecture/desktop-repo-genesis-adr.md`](./docs/architecture/desktop-repo-genesis-adr.md)
  for repo-genesis decisions until those decisions are superseded by a reviewed
  ADR.
- Record every copied or adapted upstream Lineup slice in
  [`docs/architecture/import-ledger.md`](./docs/architecture/import-ledger.md)
  before or with the import.
- Do not claim files changed, commands run, or tests passed unless you observed
  that evidence in this workspace.
- Run `npm run verify:docs` for workflow, control-plane, launcher, or
  reference-doc changes.
- Run `npm run verify` before calling scaffold, contract, IPC/security, or
  implementation work complete unless a plan names a narrower verified surface.

## Where To Look Next

- [`docs/AGENTIC_DEV_WORKFLOW.md`](./docs/AGENTIC_DEV_WORKFLOW.md): operating
  runbook, precedence, routing, verification, and review rules
- [`docs/agentic/session-prompts/README.md`](./docs/agentic/session-prompts/README.md):
  launcher templates and routing table
- [`docs/architecture/CURRENT_STATE.md`](./docs/architecture/CURRENT_STATE.md):
  current architecture truth
- [`docs/architecture/import-ledger.md`](./docs/architecture/import-ledger.md):
  copied/adapted upstream source ledger
