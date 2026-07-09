---
name: bounded-worker-execution
description: Use when an approved Lineup Desktop plan has concrete, disjoint implementation slices that can be delegated to worker agents without inventing architecture, scope, or verification policy.
---

# Bounded Worker Execution

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-quality-loop.md`
4. the approved plan or run bundle

Delegate only after the plan names:

- exact task and files in scope
- files out of scope when ambiguity exists
- owner boundary and invariants
- required verification and expected outcome
- stop/replan conditions

Use `worker` (`gpt-5.6-sol medium`) by default. Use `worker_terra`
(`gpt-5.6-terra medium`) only when the approved plan or handoff explicitly
selects it for an exact, bounded, cheap-to-verify unit with direct verification
and stop/escalation rules.

Worker slices must have disjoint write scopes. Keep architecture decisions,
integration, final verification, and commit judgment in the controller session.
Do not delegate work that needs the worker to choose the seam, broaden scope, or
decide test depth mid-task.
