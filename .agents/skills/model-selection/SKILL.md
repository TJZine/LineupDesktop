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

- `planner` for Tier 3 plans and durable handoffs.
- `reviewer` for adversarial plan, implementation, workflow, security, and
  boundary review.
- `worker` for approved bounded implementation units.
- `docs_researcher` for official framework/API documentation checks.
- `explorer` for read-only repo evidence.
- `monitor` for waits and polling.

Recommend higher reasoning for Electron IPC/security, native playback,
storage/secrets, packaging/release, broad imports, or workflow harness changes.
Do not add model guidance to routine handoffs unless the user asks or the plan
is high risk.
