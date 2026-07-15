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

Use `worker` by default. Use `worker_sol_low` when the frozen unit still needs
repository comprehension but no design judgment. Use `worker_luna` only for
exact, repeatable, cheap-to-verify work. Both lower-cost roles require explicit
plan selection, direct verification, and stop/escalation rules. Read exact model
and effort settings from the selected role's TOML.

Worker slices must have disjoint write scopes. Keep architecture decisions,
integration, final verification, and commit judgment in the controller session.
Do not delegate work that needs the worker to choose the seam, broaden scope, or
decide test depth mid-task.

## Delegation Record

Before dispatch, resolve the selected role in `.codex/config.toml`, record its
exact `config_file` value and corresponding `.codex/<config_file>` path in the
worker packet, and read that mapped TOML. At closeout, report the role, mapped
config path, `model`, and `model_reasoning_effort` read from that TOML. Treat
the worker's `CONFIGURED ROLE` opening line as a visibility aid, not independent
proof of the model selection.
