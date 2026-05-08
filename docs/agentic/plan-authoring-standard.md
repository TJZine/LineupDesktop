# Plan Authoring Standard

Use this standard for serious Lineup Desktop plans that must survive a fresh
session handoff. The goal is decision-complete planning, not pseudo-code and not
ceremony for its own sake.

When a tracked plan in `docs/plans/` is the current durable handoff surface,
mark it before the first `##` heading with this exact line:

```md
**Plan Status:** active
```

`npm run verify:docs` uses that marker to decide whether the plan must satisfy
the full active-plan structure.

## Required Classification

Every serious tracked plan must declare:

- `**Task family:** feature/design`

Do not declare cleanup subtypes or import upstream cleanup program package
mechanics, detector ids, score artifacts, or checklist status as Desktop
authority. If this repository later creates its own maintenance track, add it in
a separate reviewed workflow pass.

## Required Sections

Active serious plans must include these exact headings:

1. `## Goal`
2. `## Non-Goals`
3. `## Parent Architecture Alignment`
4. `## Required Reading`
5. `## Required Skills`
6. `## Evidence And Discovery`
7. `## Impact Snapshot`
8. `## Files In Scope`
9. `## Files Out Of Scope`
10. `## Planner Self-Check`
11. `## Architecture Seam Decision Gate`
12. `## Verification Commands`
13. `## Acceptance Criteria`
14. `## Replan Triggers`
15. `## Rollback Notes`
16. `## Commit Checkpoints`

Add optional sections for current-unit execution packets, interface snippets, or
manual QA scripts only when they materially reduce implementation or review
risk.

## Fresh-Session Rules

- Assume the implementer starts with no task memory beyond tracked docs.
- Include the minimum reading order needed to execute safely.
- Add a freshness gate: if referenced files, ownership, dependency behavior, or
  docs changed materially since the plan was written, update or re-review the
  plan before editing.
- Do not continue through contradicted assumptions because intent seems obvious.
- Keep the plan decision-complete at seam, scope, ownership, and verification
  level. Leave ordinary local coding choices to the implementer.
- A fresh session should not need to invent Electron, IPC, security, playback,
  persistence, packaging, import, or verification policy.

## Evidence And Discovery

Plans should record enough evidence for a fresh session to see why the chosen
scope and owner are correct:

- source files, symbols, docs, and contracts inspected
- Codanna or repo-search evidence when code or repo-doc discovery matters
- direct-read fallback when a preferred tool is unavailable, stale, too noisy, or
  not the right surface
- upstream Lineup source paths when copied/adapted code is in scope
- import-ledger obligations
- official external docs checks when changing Electron, dependency, platform,
  packaging, signing, native player, API, or agent-control behavior

Use this evidence mini-template when the work is non-trivial:

- `semantic_search_with_context`: result summary or explicit fallback note
- `semantic_search_docs` or repo-doc search: result summary or explicit fallback
  note when repo-doc context matters
- impact analysis: result summary or note that it was not required for the
  current risk level
- direct reads / `rg`: what was read and why fallback was needed
- official docs: source checked and date checked when external behavior matters

The evidence trail should justify decisions. It should not become a transcript.

## Required Skills

Name the project skills that should shape the task and why they apply. At
minimum, serious Desktop plans usually need:

- `execution-plan-authoring` for plan shape and decision completeness
- `verification-strategy` when proof depth is not obvious
- one or more boundary skills when the plan touches architecture, persistence,
  Plex, UI, playback, packaging, or Electron process ownership
- `review-request` when the next gate is read-only adversarial review
- `closeout-verification` before staging, committing, or calling the work done

Do not list skills as decoration. If a skill is named, its constraints should be
visible in the plan.

## Impact Snapshot

State the expected blast radius before implementation:

- owners that may change
- public contracts that may change
- commands/tests/docs that must change
- user-visible or runtime behavior that must not change
- local-only artifacts that must stay untracked

If more than one owner boundary is implicated, say whether the first execution
unit remains single-owner or why the cross-boundary work cannot be split safely.

## Planner Self-Check

Before treating a plan as implementation-ready, answer:

1. Is any product, architecture, ownership, dependency, or verification decision
   still unresolved?
2. Does the plan depend on adjacent files needing contract or type changes that
   are not in scope?
3. Did the plan freeze any file out of scope while still relying on hidden
   wiring inside it?
4. Did the plan record the evidence path and fallback reads?
5. Is the work assigned to the repo-preferred owner, or is it growing a hotspot?
6. Would a fresh implementer need to invent security, IPC, playback,
   persistence, packaging, import, or verification policy?
7. Did the plan record exact verification commands, expected outcomes, and
   explicit stop/replan triggers?

If any answer exposes a live ambiguity, resolve it before implementation.

## Architecture Seam Decision Gate

- Name the chosen owner seam before implementation steps are locked.
- Do not hide an unresolved architecture seam behind "mechanical wiring."
- If adjacent contracts or ownership boundaries must change, include those files
  in scope or explain how the execution unit works without changing them.
- State forbidden shortcuts, such as broad RPC bridges, renderer privilege
  concessions, compatibility shims, temporary adapters, raw secret exposure, or
  old upstream path preservation.
- Stop and replan when discovery invalidates the chosen seam.

## Invariants And Scope Rules

- Name exact files in scope and out of scope.
- State which architecture boundary the task advances.
- Preserve renderer privilege limits, preload narrowness, main/helper ownership,
  redaction, and import provenance whenever implicated.
- For UI/runtime work, include preservation contracts for focus, keyboard/remote
  behavior, timers/listeners, accessibility, motion, media surface lifecycle, and
  startup/shutdown ordering when relevant.
- For source imports, update the import ledger before or with the import.
- Do not add fallback paths, compatibility shims, or temporary adapters unless
  the plan names one owner, reason, verification, and removal trigger.

## Verification Classification

Each active serious plan must include exactly one exact marker:

- `new regression/contract test required`
- `existing coverage sufficient`
- `broader integration/manual proof required`
- `no new automated test needed`

The plan must name exact commands and expected outcomes. When the classification
is `existing coverage sufficient`, name the existing proof target. When the
classification is `broader integration/manual proof required` or
`no new automated test needed`, name the manual, integration, smoke,
static-analysis, or source-audit proof surface.

Do not default every plan to fail-first TDD. New tests are required when they
protect a stable behavior or contract seam. Avoid tests that only restate helper
internals likely to move during implementation.

## Current-Unit Execution Packets

When an implementer needs more current-unit detail than the master plan should
carry, emit a bounded execution packet instead of expanding the whole plan into
pseudo-code.

The packet should name:

- exact execution unit
- files in scope and out of scope
- constraints and invariants
- verification commands plus expected outcomes
- explicit stop/replan conditions

The packet may live inside a `NEXT_SESSION_HANDOFF` or a local run-bundle
artifact. It does not replace the tracked plan as the durable source of scope,
seam, and verification policy.

## Commit Checkpoints

Plans should state whether the execution unit should produce a focused commit.
Use conventional commits. Keep workflow/control-plane changes separate from
product implementation when practical, and do not stage unrelated local changes.

For Tier 3 work, prefer one commit per reviewed execution unit unless the plan
records why a no-commit handoff is safer.

## Anti-Patterns To Avoid

- vague scope such as "touch whatever is needed"
- unresolved seams hidden inside "mechanical wiring"
- pseudo-code for every future helper instead of seam and invariant decisions
- broad framework setup that cannot be reviewed for behavior
- raw Electron, Node, filesystem, token, auth-header, or native-handle access in
  renderer-facing contracts
- broad preload RPC or arbitrary channel strings from renderer code
- copied upstream Lineup code without an import-ledger row
- local-only artifact paths in tracked plan instructions when relative tracked
  references are enough
- brittle line-number anchoring without a freshness guard
- verification commands without expected outcomes
- handoffs that require the next session to reconstruct scope from prose
