---
name: review-request
description: Use when Lineup Desktop needs an adversarial read-only review of a plan, implementation diff, workflow artifact, skill, verifier, launcher, or completed handoff before closeout.
---

# Review Request

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-review.md` or
   `docs/agentic/session-prompts/workflow-harness-review.md`

Send reviewers a bounded packet:

- task, task family, tier, and review target
- files in scope and out of scope
- key invariants and non-goals
- verification already run and observed result
- known risks and what to prioritize
- exact output expectation

Reviewers stay read-only and lead with findings ordered by severity. The owning
session adjudicates findings, applies accepted fixes, reruns verification, and
requests re-review only when material review surface changed.
