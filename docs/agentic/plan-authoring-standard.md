# Plan Authoring Standard

Use a tracked plan only when serious Lineup Desktop work must survive a fresh
session. The plan freezes expensive decisions; it does not narrate discovery or
specify every helper.

## Activation And Metadata

Before the first `##` heading, an active tracked plan declares:

```md
**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 1 | Tier 2 | Tier 3
```

Tier 1 work normally stays local. Tier 2 uses a bounded plan when handoff value
justifies it. Tier 3 routes through the feature-quality loop.

## Required Sections

Active plans use these exact headings:

1. `## Goal`
2. `## Non-Goals`
3. `## Architecture And Invariants`
4. `## Files In Scope`
5. `## Files Out Of Scope`
6. `## Execution Packages`
7. `## Verification Commands`
8. `## Acceptance Criteria`
9. `## Replan Triggers`

Add rollback and commit checkpoints when the work has a meaningful partial-state
or multi-commit risk. Add reading, evidence, import, or handoff sections only
when they reduce a real implementation or review risk.

## Decision-Complete Content

A fresh implementer must not invent product behavior, ownership, Electron/IPC or
security policy, persistence, playback, packaging, imports, or proof depth.
Record:

- the current goal, explicit non-goals, public behavior, and trust boundaries;
- the chosen owner seam, dependency direction, invariants, and forbidden
  shortcuts;
- likely files or the allowed write boundary for the current execution unit, plus
  important adjacent owners that require replan before editing;
- exact verification commands, expected outcomes, acceptance criteria, and
  stop/replan conditions; and
- rollback/commit intent when partial completion could create ambiguity.

Future packages may remain less detailed until they become current. Before
delegation, confirm the current package's owner/write boundary and re-review the
plan if ownership or contracts changed. Require exact files only when concurrent
writers or sensitive shared surfaces need collision protection. A local execution
packet may summarize the current unit, but it cannot contradict or replace tracked
scope and policy.

## Evidence, Skills, And Freshness

Record only evidence that justifies a decision: inspected owners/contracts,
targeted repository search or impact results, direct-read fallback, official
platform guidance when external behavior changes, and upstream paths/import
ledger obligations when code or assets are adapted. Do not preserve a search
transcript.

Name only the skills that constrain the task. Serious work commonly uses
`execution-plan-authoring`, `verification-strategy`, the matching boundary and
quality/test skills, `review-request`, and `closeout-verification`.

Before each package, compare current source, contracts, ownership, dependencies,
and relevant docs with the plan. Refresh and re-review after a material
contradiction; do not continue because the intended answer seems obvious.

## Architecture And YAGNI Gate

State whether the current unit changes an owner's responsibility. Apply
`docs/architecture/file-shape-guardrails.md`: line count triggers attention, not
decomposition. For each touched attention owner, record the compact cohesion
disposition and required independent review. Extract only a distinct current
responsibility, lifecycle, trust boundary, policy, or consumer into an owner
with meaningful behavior.

Do not plan forwarding wrappers, one-implementation interfaces, generic service
layers, compatibility shims, speculative extension points, dependencies, or
fallbacks without a demonstrated present requirement, one owner, proof, and a
removal/revisit trigger.

## Verification Classification

Include exactly one marker under `## Verification Commands`:

- `new regression/contract test required`
- `existing coverage sufficient`
- `broader integration/manual proof required`
- `no new automated test needed`

Name the exact automated, manual, smoke, static-analysis, or source-audit proof
and its expected outcome. Protect stable behavior and public seams; avoid tests
that only restate private helpers or giant output snapshots.

## Worker And Review Routing

Plans describe implementation risk and constraints rather than permanently binding
a model. At dispatch, use `worker_luna` by default for a bounded unit whose outcome,
owner seam, contracts, acceptance criteria, and direct proof are clear, including
work that needs repository comprehension, exact-file discovery, routine local design
judgment, focused test design, and diagnosis of failures caused by the
implementation. Use `worker` when the same settled bounded unit needs material
local design judgment, cross-boundary comprehension, complex diagnosis, or proof
interpretation. Return unresolved product, ownership, public-contract, architecture,
or proof decisions to planning. The controller selects the current role, integrates
the result, and reruns verification.

Require independent review when risk, novelty, blast radius, or weak evidence
makes hidden risk substantial. Repeat only after a material finding or material
review-surface change. Exact model and reasoning settings come only from the
selected role TOML.

## Closeout

Keep workflow/control-plane changes separate from product implementation when
practical and use conventional commits. Before closeout, update current
architecture/public-contract docs made stale by the change, inspect the diff,
run risk-matched verification, preserve unrelated work, and follow the runbook's
active-plan archival policy.
