---
name: review-adjudication
description: Use when Lineup Desktop receives reviewer findings, PR suggestions, AI review comments, or external feedback that must be accepted, modified, rejected, deferred, or validated.
---

# Review Adjudication

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. the reviewed plan, diff, or artifact

Do not treat reviewer output as automatically correct. For each material item:

- identify the exact claim and affected owner boundary
- classify evidence as observed, inferred, or unknown
- choose one verdict: accept, accept with modification, reject, defer, or needs
  validation
- decide whether the finding blocks the current plan or can be tracked later
- name the fix scope and verification before editing

Route missing architecture, security, storage, playback, packaging, or import
decisions back to planning instead of patching around them inside
implementation.
