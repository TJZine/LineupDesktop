---
name: large-task-orchestration
description: Use when a large Lineup Desktop task needs explicit controller-led delegation across multiple independent research, planning, implementation, or review units.
---

# Large Task Orchestration

Use this only from the Lineup Desktop repo.

Read `AGENTS.md`, `docs/AGENTIC_DEV_WORKFLOW.md`, and the approved plan. Use
delegation only when it reduces critical-path time or protects controller
context; keep small or tightly coupled work local.

- Keep the controller responsible for decisions, integration, verification,
  review adjudication, and closeout.
- Keep `max_threads = 6` and `max_depth = 1`; do not create nested agent trees.
- Give each agent one bounded output, exact scope, invariants, evidence needs,
  and stop conditions. Writers must have disjoint files and owners.
- Reuse a worker when retained task context helps the next unit and the scope
  remains unchanged. Use fresh context for independent final review or when
  prior assumptions could bias the result.
- Use read-only sidecars for discovery and documentation. Delegate writes only
  after the plan freezes architecture and verification.
- Use `worker` by default, `worker_sol_low` for bounded code-aware work, and
  `worker_luna` for exact repeatable work. Stop lower-cost workers on ambiguity.
- Require a fresh `reviewer` after the integrated diff when risk, novelty,
  blast radius, weak evidence, composition roots, or named hotspots warrant it.
  Add another pass only after a material finding or review-surface change.
