---
name: typescript-test-design
description: Use when changing Lineup Desktop node:test coverage, fixtures, Electron IPC tests, renderer tests, mocks, subprocess tests, or runtime-boundary verification.
---

# TypeScript Test Design

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/development/testing.md`
4. the tracked architecture owner and boundary skill for the production surface
   under test

- Add a regression test for a demonstrated defect. For a refactor, test the
  behavior or contract that must remain invariant.
- Test public seams and observable outcomes: IPC contracts, renderer state/DOM,
  persisted values, focus, process results, and boundary requests. Avoid private
  probes, implementation-order assertions, and full help/output snapshots.
- Mock external boundaries, not the collaborator whose behavior is under test.
  Keep fixtures local and typed unless several tests share a stable contract.
- Await work deterministically. Exercise cleanup, cancellation, stale completion,
  hidden/destroyed UI, and failure only when the changed lifecycle can produce
  those states.
- Give every direct `spawn`, `execFile`, or other child-process test an explicit
  timeout and cleanup path. Do not leave processes or handles alive.
- Restore fake timers, spies, DOM, listeners, globals, storage, and environment
  changes in the test that owns them.
- Prefer semantic assertions over giant snapshots or restating every branch.
  A need to reach private state usually signals a missing public owner or
  contract; fix that seam only when the production design actually needs it.

Run the focused test, `npm run typecheck`, and the smallest matching verification
gate from the runbook. Use the full `npm run verify` for IPC, lifecycle, renderer
composition, persistence, native integration, or release-surface changes.
