# External Agentic Guidance Baseline

This document records the official guidance baseline used by the Lineup Desktop
control plane. It is not a second workflow runbook; it explains why the local
workflow is shaped the way it is.

## Sources

OpenAI:

- [Codex best practices](https://developers.openai.com/codex/learn/best-practices)
- [Prompt engineering for coding and agentic tasks](https://developers.openai.com/api/docs/guides/prompt-engineering#coding)
- [GPT-5.5 behavioral changes](https://developers.openai.com/api/docs/guides/latest-model#behavioral-changes)
- [Using PLANS.md for multi-hour problem solving](https://developers.openai.com/cookbook/articles/codex_exec_plans)

Anthropic:

- [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)
- [Claude Code common workflows](https://docs.anthropic.com/en/docs/claude-code/tutorials)
- [Claude Code memory](https://docs.anthropic.com/en/docs/claude-code/memory)
- [Claude Code subagents](https://docs.anthropic.com/en/docs/claude-code/sub-agents)
- [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks)
- [Writing effective tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents)
- [Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)

Checked on 2026-05-07.

## Local Conclusions

- Keep `AGENTS.md` concise and practical. Move detailed workflow policy into
  tracked docs and reusable skills.
- Use durable execution plans only when work is complex, risky, or likely to
  need fresh-session handoff.
- Treat plans as execution specifications for a fresh session with no hidden
  memory. They must name goal, constraints, ownership, verification, rollback,
  and stop conditions.
- Use explicit progress tracking for long-running work and require observed
  verification before closeout.
- Use sidecars for bounded research, review, and context isolation when they
  materially improve reliability.
- Use evaluator-style review loops when criteria are clear and iterative
  improvement is valuable.
- Keep agent systems simple and composable. Add loops, project skills, hooks,
  or automations only when a manual workflow has proved the need.
- Treat verifiers, review prompts, and tool descriptions as part of the harness.
  They must be tested and reviewed like product code.

## Refresh Triggers

Refresh this document and the workflow docs when:

- official OpenAI or Anthropic guidance changes materially
- a repeated agent failure shows a local rule is missing or misleading
- a new reusable workflow graduates into a project skill
- verifier behavior changes what agents can safely claim
- the repo adds hooks, automations, or model-specific orchestration policy
