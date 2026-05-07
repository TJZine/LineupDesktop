# Agentic Development Workflow

This is the operating runbook for Lineup Desktop.

## Authority And Document Roles

- [`AGENTS.md`](../AGENTS.md) is the concise entrypoint map and always-on
  defaults surface.
- This file is the single operating runbook for workflow, precedence, routing,
  verification, review, and where to look next.
- [`docs/agentic/external-guidance.md`](./agentic/external-guidance.md) records
  the official OpenAI and Anthropic guidance baseline used by this control
  plane.
- [`docs/agentic/plan-authoring-standard.md`](./agentic/plan-authoring-standard.md)
  owns the required shape for durable tracked plans.
- [`docs/architecture/CURRENT_STATE.md`](./architecture/CURRENT_STATE.md) is
  current architecture truth.
- [`docs/architecture/desktop-repo-genesis-adr.md`](./architecture/desktop-repo-genesis-adr.md)
  owns accepted repo-genesis decisions.
- [`docs/architecture/import-ledger.md`](./architecture/import-ledger.md) owns
  provenance for copied or adapted upstream Lineup code and docs.

## Default Read Order

1. [`AGENTS.md`](../AGENTS.md)
2. this workflow runbook
3. [`docs/agentic/session-prompts/README.md`](./agentic/session-prompts/README.md)
4. [`docs/agentic/plan-authoring-standard.md`](./agentic/plan-authoring-standard.md)
   when authoring or reviewing a durable plan
5. [`docs/architecture/CURRENT_STATE.md`](./architecture/CURRENT_STATE.md)
6. the active plan in [`docs/plans/`](./plans/README.md), when one exists
7. task-specific architecture docs named by the plan or launcher

Keep always-loaded guidance short. Put detailed task workflow in launchers,
project skills, architecture docs, or tracked plans so sessions load only what
they need.

## Guidance Baseline

This workflow follows the current official guidance summarized in
[`docs/agentic/external-guidance.md`](./agentic/external-guidance.md):

- durable repo instructions belong in `AGENTS.md`, with specialized guidance
  referenced from task docs or skills
- complex or ambiguous work plans before edits and records success criteria,
  constraints, verification, and stop conditions
- agentic coding work needs explicit orchestration, bounded tool/subagent use,
  test expectations, review, and acceptance criteria
- context is finite; delegate bounded research or review to sidecars when it
  preserves main-thread context and improves reliability
- agent systems should stay simple and composable, adding loops, skills, hooks,
  or automations only when they demonstrably improve outcomes
- verifiers and review loops are part of the harness, not optional afterthoughts

When official guidance changes materially, update
[`docs/agentic/external-guidance.md`](./agentic/external-guidance.md), this
runbook, launchers, project skills, and verifier tests in one reviewed pass.

## Routing

All desktop delivery routes as `feature/design` unless this repository later
creates its own reviewed maintenance backlog. Do not import upstream cleanup
program state, score artifacts, detector issue ids, package fields, or package
mechanics as active desktop authority.

Use the smallest tier that keeps the work reliable:

- Tier 1: one-session small docs, harness, or contract changes with
  risk-matched verification. Use review when the surface appears in
  [Review Before Closeout](#review-before-closeout), when the plan requires it,
  or when the change could weaken a desktop feature quality guardrail.
- Tier 2: serious feature/design work uses
  `feature-plan -> feature-review -> feature-implement -> feature-review`.
- Tier 3: cross-boundary or multi-session work uses a task-specific run bundle
  plus the desktop feature-quality loop in
  [`feature-quality-loop.md`](./agentic/session-prompts/feature-quality-loop.md).

Tier 3 is required by default for Electron IPC/security, native playback,
storage/secrets, packaging/release, broad upstream imports, or any change where
implementation would otherwise need to invent ownership or verification policy.

## Desktop Feature Quality Guardrails

For every non-trivial code change, check the planned diff and final diff against
these regression categories:

- hotspot growth: composition roots, Electron main, preload, player host,
  scheduler, and Plex owners must not absorb unrelated feature policy
- compatibility residue: no migration barrels, old-path wrappers, compatibility
  re-exports, fallback API variants, or temporary adapters unless an approved
  plan names a removal trigger
- boundary leakage: renderer code must not gain persistent secrets, raw Electron
  APIs, native handles, tokenized URLs, Plex transport policy, secure-storage
  policy, or packaging policy
- contract drift: keep one public shape per operation, one owner for shared
  literal unions, explicit redaction behavior, and aligned public/concrete
  signatures
- test debt: prefer public-seam behavior, contract, integration, or manual proof
  over brittle private probes and broad snapshots
- source signal: avoid generated-looking scaffolding, no-value forwarding,
  broad helper names, stale comments, and unrelated cleanup mixed into a feature
  unit
- release debt: do not weaken licensing, signing, update, diagnostics, or binary
  provenance gates to accelerate a private spike

Intentional exceptions need an approved plan note with one owner, reason,
verification, and removal or revisit trigger.

## Feature-Quality Loop

The full Tier 3 controller lives in
[`feature-quality-loop.md`](./agentic/session-prompts/feature-quality-loop.md).
The invariant is simple: plan with a tracked planner, review read-only, implement
one approved bounded unit with a tracked worker, review read-only again, and do
not advance while material findings remain.

Use `docs/runs/` only for gitignored local run bundles. Promote durable
decisions into tracked docs instead of committing raw run logs.

## Implementation Rules

- Keep renderer code unprivileged.
- Keep preload APIs narrow, typed, and validated.
- Keep persistent secrets and token-bearing operations in Electron main and/or a
  privileged helper.
- Treat helper-hosted libmpv as a hypothesis until a Windows spike proves video
  surface, overlay, fullscreen, focus, track list, crash recovery, and redaction
  behavior.
- Treat external `mpv` IPC as a private disposable POC only.
- Record every copied/adapted upstream Lineup slice in the import ledger before
  or with the import.
- Do not add compatibility barrels or old-path shims just to mirror upstream
  paths.
- Prefer small, verifiable units over broad framework setup that cannot be
  reviewed for behavior.

## Verification Routing

- Docs, workflow, launcher, architecture, or plan changes: `npm run verify:docs`.
- Contract, IPC payload, or security-boundary changes: `npm run typecheck`,
  `npm run test:contracts`, and `npm run verify:redaction`.
- Any scaffold or implementation closeout: `npm run verify` unless an approved
  plan names a narrower verified surface.
- Electron runtime, native playback, persistence/secrets, or packaging work must
  expand verification before implementation begins.
- UI work must include visual or browser evidence when layout, focus,
  interaction, media surface, or accessibility behavior could regress.

Verification claims require observed command output or recorded manual proof.
Do not hide a failed required check behind unrelated passing checks.

## Review Before Closeout

Use read-only adversarial review for:

- workflow/control-plane, launcher, project skill, or verifier changes
- Electron IPC/security boundaries
- native playback or player contract changes
- persistence/secrets changes
- packaging/release changes
- copied/adapted upstream Lineup imports
- Tier 3 plan and implementation gates

Reviewers should lead with findings, cite files and lines, prioritize security,
boundary, verification, and scope issues, and state explicitly when no blockers
remain. The owning session adjudicates reviewer findings before editing.

## Redaction Rules

Never put raw Plex tokens, tokenized URLs, raw auth headers, native media logs,
crash dumps with secrets, or secret-bearing fixtures into renderer-facing
surfaces, persisted logs, diagnostics, tests, docs, or Codex output.

## Memory Surface Updates

- Update current-state or architecture docs when ownership changes.
- Update the import ledger before or with copied/adapted upstream Lineup code.
- Update project skills under `.agents/skills/` only when a reusable workflow
  actually changes.
- Keep raw `docs/runs/` bundles local and ignored unless the workflow later
  explicitly promotes a curated summary into a tracked doc.
- Commit workflow/control-plane changes separately from product implementation
  when practical.
