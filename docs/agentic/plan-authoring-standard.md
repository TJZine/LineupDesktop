# Plan Authoring Standard

Use this standard for serious Lineup Desktop plans that should survive a fresh
session handoff.

When a tracked plan is active, mark it before the first `##` heading:

```md
**Plan Status:** active
```

## Required Classification

Every serious tracked plan must declare:

- `**Task family:** feature/design`

Do not declare a cleanup subtype unless this repository later creates its own
reviewed cleanup backlog.

## Required Sections

Active serious plans must include:

1. `## Goal`
2. `## Non-Goals`
3. `## Parent Architecture Alignment`
4. `## Required Reading`
5. `## Files In Scope`
6. `## Files Out Of Scope`
7. `## Architecture Seam Decision Gate`
8. `## Verification Commands`
9. `## Replan Triggers`
10. `## Rollback Notes`

## Verification Classification

Each active serious plan must include one exact marker:

- `new regression/contract test required`
- `existing coverage sufficient`
- `broader integration/manual proof required`
- `no new automated test needed`

## Planning Rules

- Freeze ownership, scope, invariants, verification, and stop conditions.
- Leave ordinary local coding choices to the implementer.
- Do not hide Electron, native playback, secret storage, or packaging decisions
  behind mechanical wiring language.
- Do not copy upstream Lineup code without an import ledger row.
- Do not accept renderer-held persistent secrets.
