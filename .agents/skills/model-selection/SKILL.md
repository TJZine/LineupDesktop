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

Choose the smallest capable role permitted by the active plan and task risk.
Use the canonical role policy in
[`docs/agentic/skill-strategy.md`](../../../docs/agentic/skill-strategy.md), then
resolve the selected role's exact `config_file` mapping from `.codex/config.toml`.
The mapped TOML is the sole authority for model, reasoning effort, sandbox, and
fallback configuration. Do not duplicate those values in this skill, plans,
prompts, or workflow docs.
