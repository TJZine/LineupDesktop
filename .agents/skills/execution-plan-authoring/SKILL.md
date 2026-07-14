---
name: execution-plan-authoring
description: Use when a Lineup Desktop task needs a durable implementation plan or execution brief that freezes scope, ownership seams, verification, acceptance criteria, and replan triggers without writing pseudo-code.
---

# Execution Plan Authoring

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/plan-authoring-standard.md`
4. `docs/architecture/CURRENT_STATE.md`

Plan the expensive decisions, not every local helper:

- task tier and workflow route
- goal and non-goals
- files in scope and out of scope
- architecture seam and owner boundaries
- invariants and forbidden shortcuts
- verification classification, commands, and expected outcomes
- acceptance criteria, rollback notes, and stop/replan triggers

Select a lower-cost worker only for a controller-approved unit whose files,
owner, invariants, verification, and stop conditions are frozen. The controller
integrates the result and reruns verification. Prefer `worker_sol_low` when the
unit needs codebase judgment and `worker_luna` only when it is repeatable and
cheap to verify; otherwise use `worker`.

See AGENTS.md and docs/AGENTIC_DEV_WORKFLOW.md for lifecycle and archival
policy, including `docs/plans/` archival guidance. For Tier 3 work, route
through the feature-quality loop before implementation.
