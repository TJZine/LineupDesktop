---
name: parallel-sidecars
description: Use when Lineup Desktop work can benefit from bounded read-only sidecars for documentation research, repo discovery, adversarial review, or long waits without handing off implementation ownership.
---

# Parallel Sidecars

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. the active plan or handoff, if one exists

Use sidecars for bounded work that can run without blocking the immediate local
step:

- official docs checks for Electron, Vite, signing, packaging, or player APIs
- read-only repo discovery and impact checks
- adversarial review of a plan, diff, workflow artifact, or handoff
- long-running verification waits or polling

Give sidecars a narrow packet with task, files, invariants, verification already
run, and exact output expectation. Do not delegate urgent blocking decisions or
implementation slices that need unresolved architecture choices.
