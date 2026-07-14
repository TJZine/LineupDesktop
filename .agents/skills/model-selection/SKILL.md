---
name: model-selection
description: Use when choosing a model or reasoning effort for Lineup Desktop planning, implementation, review, documentation research, monitoring, or a high-risk handoff.
---

# Model Selection

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. the active plan or handoff, if one exists

Select the smallest capable role:

- `planner`: Tier 3 plans and durable handoffs.
- `reviewer`: adversarial plan, implementation, workflow, security, or boundary
  review when the review gate is met.
- `worker`: normal approved bounded implementation; this is the default writer.
- `worker_sol_low`: approved bounded work with settled ownership that still
  needs repository comprehension but no new design or verification judgment.
- `worker_luna`: an explicitly eligible, exact, repeatable, cheap-to-verify unit
  with frozen files, invariants, direct proof, and stop/escalation conditions.
- `docs_researcher`: read-only official framework or API research.
- `explorer`: latency-sensitive read-only repository evidence; use
  `explorer_fallback` only when the primary role is unavailable or constrained.
- `monitor`: waits and polling; use `monitor_fallback` only when needed.

Treat `.codex/agents/<role>.toml` as the sole authority for exact model,
reasoning effort, sandbox, and fallback configuration. Read and report that
configuration when a handoff requires it; do not duplicate exact values in
plans, prompts, or workflow docs. Add or change a tracked role only after current
official guidance and representative evidence demonstrate a recurring need.
