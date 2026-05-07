# Plan Authoring Standard

Use this standard for serious Lineup Desktop plans that should survive a fresh
session handoff. The goal is decision-complete planning, not pseudo-code.

When a tracked plan is active, mark it before the first `##` heading:

```md
**Plan Status:** active
```

`npm run verify:docs` uses that marker to decide whether the plan must satisfy
the full active-plan structure.

## Required Classification

Every serious tracked plan must declare:

- `**Task family:** feature/design`

Do not declare a cleanup subtype unless this repository later creates its own
reviewed maintenance backlog. Feature plans must not import upstream cleanup
program package mechanics, detector ids, or score artifacts as authority.

## Required Sections

Active serious plans must include these exact headings:

1. `## Goal`
2. `## Non-Goals`
3. `## Parent Architecture Alignment`
4. `## Required Reading`
5. `## Evidence And Discovery`
6. `## Files In Scope`
7. `## Files Out Of Scope`
8. `## Architecture Seam Decision Gate`
9. `## Verification Commands`
10. `## Acceptance Criteria`
11. `## Replan Triggers`
12. `## Rollback Notes`

Add separate sections for required skills, impact snapshots, planner self-check,
guardrail proof, or commit checkpoints only when those details would materially
reduce implementation or review risk.

## Verification Classification

Each active serious plan must include one exact marker:

- `new regression/contract test required`
- `existing coverage sufficient`
- `broader integration/manual proof required`
- `no new automated test needed`

The plan must name exact commands and expected outcomes. When the classification
is `existing coverage sufficient`, name the existing proof target. When the
classification is `broader integration/manual proof required` or
`no new automated test needed`, name the manual, integration, static-analysis, or
source-audit proof surface.

## Evidence And Discovery

Plans should record enough evidence for a fresh session to see why the chosen
scope and owner are correct:

- source files, symbols, or docs inspected
- Codanna or search evidence when code or repo-doc discovery matters
- direct-read fallback when a tool is unavailable or not the right surface
- upstream Lineup source paths when copied/adapted code is in scope
- import ledger obligations
- external official-doc checks when changing workflow, harness, dependency,
  platform, packaging, or agent-control behavior

The evidence trail should justify decisions. It should not become a transcript.

## Planner Self-Check

Before treating a plan as implementation-ready, answer:

1. Is any product, architecture, ownership, or verification decision still
   unresolved?
2. Does the plan depend on adjacent files needing contract or type changes that
   are not in scope?
3. Did the plan freeze any file out of scope while still relying on hidden
   wiring inside it?
4. Is the work assigned to the repo-preferred owner, or is it growing a hotspot?
5. Would a fresh implementer need to invent security, IPC, playback, persistence,
   packaging, or import policy?
6. Did the plan record the required verification classification and commands?
7. Did the plan include explicit stop-and-replan triggers?

If any answer exposes a live ambiguity, resolve it before implementation.

## Guardrail Proof

Plans for non-trivial work must state which desktop feature quality guardrails
from [`docs/AGENTIC_DEV_WORKFLOW.md`](../AGENTIC_DEV_WORKFLOW.md) apply and how
the implementation/review will prove they were preserved.

## Planning Rules

- Freeze ownership, scope, invariants, verification, rollback, and stop
  conditions.
- Leave ordinary local coding choices to the implementer.
- Use durable tracked plans only when the task needs handoff memory, crosses
  boundaries, spans sessions, or carries enough risk that review needs a stable
  artifact.
- Do not hide Electron, native playback, secret storage, packaging, or broad
  import decisions behind mechanical wiring language.
- Do not copy upstream Lineup code without an import ledger row before or with
  the import.
- Do not accept renderer-held persistent secrets.
- Do not add fallback paths, compatibility shims, or temporary adapters unless
  the plan names one owner, the reason, verification, and removal trigger.
- For Tier 3 work, name the first approved execution unit and whether any
  parallel units are allowed. Parallel work requires disjoint owners, files, and
  verification surfaces.
