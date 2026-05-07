# Agentic Development Workflow

This is the operating runbook for Lineup Desktop.

## Authority And Document Roles

- [`AGENTS.md`](../AGENTS.md) is the entrypoint map and always-on defaults
  surface.
- This file is the single operating runbook for workflow, precedence, routing,
  verification, review, and where to look next.
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
4. [`docs/architecture/CURRENT_STATE.md`](./architecture/CURRENT_STATE.md)
5. the active plan in [`docs/plans/`](./plans/README.md), when one exists

## Routing

All desktop work routes as `feature/design` unless this repository later creates
its own reviewed cleanup backlog. Do not import upstream cleanup program state,
score artifacts, detector issue ids, or package mechanics as active desktop
authority.

Use the smallest tier that keeps the work reliable:

- Tier 1: one-session small docs, harness, or contract changes with review before
  closeout.
- Tier 2: planner -> reviewer -> worker -> reviewer for serious feature/design
  work.
- Tier 3: task-specific run bundle for cross-boundary work such as Electron
  IPC/security, native playback, storage/secrets, packaging, or large imports.

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

## Verification Routing

- Docs, workflow, launcher, architecture, or plan changes: `npm run verify:docs`.
- Contract, IPC payload, or security-boundary changes: `npm run typecheck`,
  `npm run test:contracts`, and `npm run verify:redaction`.
- Any scaffold or implementation closeout: `npm run verify` unless an approved
  plan names a narrower verified surface.
- Electron runtime, native playback, persistence/secrets, or packaging work must
  expand verification before implementation begins.

## Review Before Closeout

Use read-only adversarial review for:

- repo-genesis workflow/control-plane changes
- Electron IPC/security boundaries
- native playback or player contract changes
- persistence/secrets changes
- packaging/release changes
- copied/adapted upstream Lineup imports

Reviewers should lead with findings, cite files and lines, prioritize security,
boundary, verification, and scope issues, and state explicitly when no blockers
remain.

## Redaction Rules

Never put raw Plex tokens, tokenized URLs, raw auth headers, native media logs,
crash dumps with secrets, or secret-bearing fixtures into renderer-facing
surfaces, persisted logs, diagnostics, tests, docs, or Codex output.
