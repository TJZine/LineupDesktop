# External Agentic Guidance Baseline

This document records the official guidance baseline used by the Lineup Desktop
control plane. It is not a second workflow runbook; it explains why the local
workflow is shaped the way it is.

## Sources

OpenAI:

- [How OpenAI uses Codex](https://openai.com/business/guides-and-resources/how-openai-uses-codex/)
- [Evaluation best practices](https://developers.openai.com/api/docs/guides/evaluation-best-practices)
- [Safety in building agents](https://developers.openai.com/api/docs/guides/agent-builder-safety)
- [Agents SDK](https://platform.openai.com/docs/guides/agents-sdk/)

Anthropic:

- [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)
- [Claude Code memory](https://docs.anthropic.com/en/docs/claude-code/memory)
- [Claude Code subagents](https://docs.anthropic.com/en/docs/claude-code/sub-agents)
- [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks)

Electron:

- [Security](https://www.electronjs.org/docs/latest/tutorial/security)
- [Process model](https://www.electronjs.org/docs/latest/tutorial/process-model)
- [Process sandboxing](https://www.electronjs.org/docs/latest/tutorial/sandbox)

Production engineering:

- [Google Engineering Practices: code review](https://google.github.io/eng-practices/review/)
- [Google Engineering Practices: small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html)
- [Google Engineering Practices: what to look for in a code review](https://google.github.io/eng-practices/review/reviewer/looking-for.html)
- [OWASP Developer Guide: secure coding](https://devguide.owasp.org/en/12-appendices/01-implementation-dos-donts/02-secure-coding/)
- [Twelve-Factor App: config](https://www.12factor.net/config)

Checked on 2026-05-08.

## Local Conclusions

- Keep `AGENTS.md` concise and practical. Move detailed workflow policy into
  tracked docs and reusable skills.
- Use durable execution plans only when work is complex, risky, or likely to
  need fresh-session handoff.
- Treat plans as execution specifications for a fresh session with no hidden
  memory. They must name goal, constraints, ownership, verification, rollback,
  and stop conditions.
- Scope implementation units tightly enough to review. Large or cross-boundary
  changes should start with a plan, evidence sweep, review gate, and an explicit
  next implementation unit rather than a broad code-generation pass.
- Use explicit progress tracking for long-running work and require observed
  verification before closeout.
- Use sidecars for bounded research, review, and context isolation when they
  materially improve reliability.
- Use evaluator-style review loops when criteria are clear and iterative
  improvement is valuable.
- Keep the owning session responsible for synthesis, scope, verification
  claims, and final handoff. Sidecars and workers provide bounded evidence or
  approved implementation slices; they do not choose new architecture seams.
- Treat workflow verifiers as small repo evals: they should encode durable
  pass/fail criteria for guidance freshness, handoff shape, required anchors,
  local-only artifacts, and forbidden baggage without becoming a brittle process
  scorecard.
- Keep agent systems simple and composable. Add loops, project skills, hooks,
  or automations only when a manual workflow has proved the need.
- Treat verifiers, review prompts, and tool descriptions as part of the harness.
  They must be tested and reviewed like product code.
- Preserve Electron secure defaults in workflow and plans: renderer sandboxing,
  context isolation, no renderer Node or raw Electron access, narrow preload
  bridges, IPC sender/origin validation, navigation/new-window containment, and
  custom local protocol preference over broad `file://` loading.
- Preserve production code health: prefer small self-contained changes, keep the
  build green after each committed checkpoint, test stable behavior, separate
  broad refactors from feature changes, and reject avoidable complexity even
  when it arrives in small increments.
- Treat dependency, build-tool, configuration, diagnostics, and logging changes
  as architecture decisions when they alter runtime behavior, security posture,
  provenance, or long-term maintenance cost.
- Treat hook-style automation as inspiration for checkpoints only. Do not add
  privileged hooks or background automations unless a reviewed repo need,
  sanitization model, and verification path exist.

## Refresh Triggers

Refresh this document and the workflow docs when:

- official agentic, Electron, security, or production-engineering guidance
  changes materially
- a repeated agent failure shows a local rule is missing or misleading
- a new reusable workflow graduates into a project skill
- verifier behavior changes what agents can safely claim
- the repo adds hooks, automations, or model-specific orchestration policy
