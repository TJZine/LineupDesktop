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
- Prefer Codanna for repo discovery when the index is useful; record fallback
  to direct reads or `rg` when it is unavailable, stale, or too noisy.
- Record every copied or adapted upstream Lineup slice in
  [`docs/architecture/import-ledger.md`](./docs/architecture/import-ledger.md)
  before or with the import.
- Route greenfield desktop delivery through feature/design workflows. Tier 3
  cross-boundary work uses the desktop feature-quality loop, not historical
  upstream cleanup program mechanics.
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
- [`docs/agentic/external-guidance.md`](./docs/agentic/external-guidance.md):
  official OpenAI and Anthropic guidance baseline used by this control plane
- [`docs/agentic/codanna-playbook.md`](./docs/agentic/codanna-playbook.md):
  Codanna-first discovery and fallback rules
- [`docs/agentic/skill-strategy.md`](./docs/agentic/skill-strategy.md):
  Desktop role and project skill topology
- [`docs/architecture/CURRENT_STATE.md`](./docs/architecture/CURRENT_STATE.md):
  current architecture truth
- [`docs/architecture/import-ledger.md`](./docs/architecture/import-ledger.md):
  copied/adapted upstream source ledger
