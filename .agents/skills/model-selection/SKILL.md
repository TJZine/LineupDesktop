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

Use the smallest capable role/model:

- `planner`: `gpt-5.6-sol high` for Tier 3 plans and durable handoffs.
- `reviewer`: `gpt-5.6-sol high` for adversarial plan, implementation,
  workflow, security, and boundary review.
- `worker`: `gpt-5.6-sol medium`; the default for normal approved bounded
  implementation units.
- `worker_terra`: `gpt-5.6-terra medium`; use only when an approved plan or
  handoff explicitly declares an exact, bounded, cheap-to-verify unit eligible
  and supplies stop/escalation conditions.
- `docs_researcher`: `gpt-5.6-terra medium` for official framework/API checks.
- `explorer`: keep `gpt-5.3-codex-spark xhigh` for latency-sensitive read-only
  repo evidence; use `explorer_fallback` at `gpt-5.6-terra high` when Spark is
  unavailable or constrained.
- `monitor`: keep `gpt-5.3-codex-spark low`; use `monitor_fallback` at
  `gpt-5.6-luna low` when Spark is unavailable or constrained.

For routine work, preserve the tracked reasoning effort. Recommend direct Sol
`xhigh` only for unusually difficult Electron IPC/security, native playback,
storage/secrets, packaging/release, broad-import, or workflow-harness work.
Reserve `max` for measured quality-first cases where `xhigh` is insufficient;
do not make `max` or host-specific `ultra` a tracked default.

Use `gpt-5.5` at the same effort as the reliability fallback for Sol/Terra
roles when GPT-5.6 is unavailable. Use `gpt-5.4-mini` only for low-risk,
cost-sensitive work that would otherwise use Luna or a lightweight Terra role.
Do not add model guidance to routine handoffs unless the user asks or the plan
is high risk.
