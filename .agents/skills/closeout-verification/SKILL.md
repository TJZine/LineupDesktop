---
name: closeout-verification
description: Use before Lineup Desktop work is called done, staged, committed, pushed, handed off, or closed after code, docs, workflow, verifier, skill, or review changes.
---

# Closeout Verification

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. the active plan or handoff, if one exists

Before completion or git actions, verify:

- what changed and why it is in scope
- which command or manual proof was run fresh
- whether output and exit code were observed
- whether the diff contains only intended files
- whether docs, architecture state, import ledger, plans, or skill strategy need
  updates
- whether requested or required adversarial review is complete

Use repo routing first: `npm run verify:docs` for workflow/docs/control-plane
changes, and `npm run verify` for source, scaffold, IPC/security, runtime, or
implementation closeout unless an approved plan names a narrower proof.
