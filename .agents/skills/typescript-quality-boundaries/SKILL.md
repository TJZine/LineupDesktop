---
name: typescript-quality-boundaries
description: Use for Lineup Desktop TypeScript production code, Electron process boundaries, typed contracts, lifecycle cleanup, error handling, or external payload translation.
---

# TypeScript Quality Boundaries

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/architecture/CURRENT_STATE.md`
4. the tracked architecture owner for the affected boundary
5. only the additional boundary skills required by the change

- Keep `unknown` at external boundaries and narrow it once at the owning seam.
  Do not use `any`, double assertions, non-null assertions, or broad option bags
  to bypass a missing contract.
- Prefer small discriminated unions or result types when states have different
  valid data. Do not add types for hypothetical variants.
- Electron main owns privileged operations; preload exposes a narrow validated
  bridge; renderer consumes renderer-safe contracts. Do not leak Electron
  objects, credentials, handles, or token-bearing payloads across IPC.
- Give timers, listeners, abort controllers, child processes, and async work one
  explicit lifecycle owner. Handle cleanup, stale completion, and failure at
  that owner.
- Preserve error causes internally and expose sanitized, actionable errors at
  trust or UI boundaries.
- Put new behavior in the existing focused owner. Add no generic helper, base
  class, service registry, compatibility layer, dependency, or extension point
  without a demonstrated present requirement.
- Extract only a distinct current responsibility, lifecycle, trust boundary,
  policy, translation, or independently changing consumer; otherwise keep the
  cohesive behavior together.

Verify the smallest affected seam with focused tests, `npm run typecheck`,
relevant lint, and any stronger runbook gate required by the risk. Also use
`typescript-test-design` when tests change.
