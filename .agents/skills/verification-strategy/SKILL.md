---
name: verification-strategy
description: Use when Lineup Desktop work needs an explicit verification mode and proof surface without defaulting every change to fail-first TDD, brittle tests, or no verification.
---

# Verification Strategy

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/plan-authoring-standard.md` when a tracked plan is involved

Choose the smallest proof that actually protects the seam:

- `new regression/contract test required`
- `existing coverage sufficient`
- `broader integration/manual proof required`
- `no new automated test needed`

Name exact commands, manual proof steps, expected outcomes, why this depth fits
the risk, and why new tests are or are not justified. Prefer public contract,
architecture, redaction, integration, smoke, or manual proof over brittle
private helper tests. Verification is mandatory; fail-first TDD is optional only
when it is the right signal.
