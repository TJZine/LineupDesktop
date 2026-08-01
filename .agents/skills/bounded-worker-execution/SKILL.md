---
name: bounded-worker-execution
description: Use when Lineup Desktop has a bounded implementation slice suitable for the cost-efficient worker_luna role.
---

# Bounded Worker Execution

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. the approved plan or run bundle
4. `docs/agentic/session-prompts/feature-quality-loop.md` when the approved plan
   is Tier 3

Delegate only after the plan or execution brief names:

- exact objective and acceptance criteria
- owner/write boundary and out-of-scope owners
- owner boundary and invariants
- required verification and expected outcome
- stop/replan conditions

Use `worker_luna` by default when the outcome, owner seam, contracts, acceptance
criteria, and direct proof are clear. It may discover exact files, use repository
comprehension and routine local design judgment, add focused tests and related
documentation, and diagnose failures caused by its implementation. Use `worker`
when the same settled bounded unit needs material local design judgment,
cross-boundary comprehension, complex diagnosis, or proof interpretation. Return
unresolved product, ownership, public-contract, architecture, or proof decisions to
planning. Read exact model and effort settings from the selected role's TOML.

Worker slices must have disjoint write scopes. Require exact files only for
concurrent writers or sensitive shared surfaces. Keep architecture decisions,
integration, final verification, and commit judgment in the controller session.
The worker may choose implementation details and focused test organization within
the approved seam, but must stop when evidence exposes unresolved product intent,
ownership, public behavior, architecture, proof depth, dependency or compatibility
policy, or scope expansion.

## Delegation Record

Before dispatch, resolve the selected role in `.codex/config.toml`, record its
exact `config_file` value and corresponding `.codex/<config_file>` path in the
worker packet, and read that mapped TOML. At closeout, report the role, mapped
config path, `model`, and `model_reasoning_effort` read from that TOML. Treat
the worker's `CONFIGURED ROLE` opening line as a visibility aid, not independent
proof of the model selection.
