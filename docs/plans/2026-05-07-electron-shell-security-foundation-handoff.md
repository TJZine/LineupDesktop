# Electron Shell Security Foundation Handoff

- **Status:** handoff-ready
- **Date:** 2026-05-07
- **Task family:** feature/design

This handoff is for a fresh Codex session rooted at
`/Users/tristan/Software/LineupDesktop`. The next session should create and
review an active Tier 3 plan before implementing product code.

## Next Session Objective

Create a tracked active plan for the Electron shell and security foundation
slice. Do not implement the shell in the planning session unless the user
explicitly changes scope after the plan is reviewed.

Suggested plan path:

```text
docs/plans/2026-05-07-electron-shell-security-foundation-plan.md
```

## Required Read Order

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/README.md`
4. `docs/agentic/session-prompts/feature-quality-loop.md`
5. `docs/agentic/plan-authoring-standard.md`
6. `docs/agentic/skill-strategy.md`
7. `docs/agentic/codanna-playbook.md`
8. `docs/architecture/CURRENT_STATE.md`
9. `docs/architecture/desktop-repo-genesis-adr.md`
10. `docs/architecture/security-and-secret-flow.md`
11. `docs/architecture/playback-architecture.md`
12. `docs/architecture/packaging-release-gates.md`
13. `docs/architecture/import-ledger.md`
14. `docs/development/testing.md`
15. current `git status --short --branch`

## Decisions Already Accepted

- Lineup Desktop is a separate Windows-first Electron repository.
- Renderer code must remain unprivileged.
- Preload must expose narrow typed APIs, not raw Electron primitives.
- Electron main and/or a privileged helper own persistent credentials,
  token-bearing setup, app paths, diagnostics, window lifecycle, and native
  process coordination.
- Helper-hosted libmpv is a production hypothesis, not yet proven.
- External mpv IPC may be a private disposable learning spike only.
- Public Windows distribution is blocked until signing, licensing, binary
  provenance, and diagnostics gates are recorded.
- Copied/adapted upstream Lineup slices require an import ledger entry before
  or with the import.

## Foundation Plan Must Freeze

- exact first implementation unit
- files in scope and out of scope
- Electron process ownership boundaries
- preload API shape and validation policy
- minimum renderer/main/preload directory structure
- secret-storage placeholder policy for private development
- diagnostics and redaction obligations
- architecture-lint expectations for new directories
- verification commands and expected outcomes
- replan triggers

The plan should freeze boundaries and contracts, not local helper names or full
function bodies.

## Recommended First Implementation Unit

The first implementation unit after plan review should be the secure Electron
shell frame:

- package scripts and dependencies required to run Electron locally
- `src/main/` entrypoint with BrowserWindow security defaults
- `src/preload/` typed bridge skeleton
- `src/renderer/` minimal renderer entrypoint
- IPC contract tests that prove renderer-facing payloads do not contain
  forbidden privileged fields
- redaction and architecture verification updated for any new surfaces

Do not import Plex, scheduler, EPG UI, native playback, secure storage, or
packaging implementation in this first unit unless the reviewed plan explicitly
changes that scope.

## Verification Baseline

The plan should start from these commands:

```sh
npm run verify
```

It should add narrower commands only when useful. For Electron runtime behavior,
the plan must define a manual or automated smoke proof before implementation
claims are accepted.

## Stop And Replan Triggers

Stop and replan if the proposed implementation requires:

- renderer access to persistent Plex credentials
- raw Electron APIs exposed through preload
- token-bearing URLs, auth headers, native handles, or secret-bearing logs in
  renderer-facing contracts
- compatibility shims just to preserve old webOS paths
- a production playback decision before the native playback spike proves the
  required behavior
- public release, auto-update, or installer commitments before the release gates
  are ready
- broad upstream Lineup imports without import-ledger entries

## Fresh Session Prompt

Use this prompt in the new Codex chat:

```text
We are in /Users/tristan/Software/LineupDesktop. Create a Tier 3 tracked plan for the Electron shell and security foundation slice. Use AGENTS.md, docs/AGENTIC_DEV_WORKFLOW.md, docs/agentic/session-prompts/feature-quality-loop.md, docs/agentic/plan-authoring-standard.md, docs/agentic/skill-strategy.md, docs/agentic/codanna-playbook.md, and the architecture docs. Do not implement product code. Freeze the first implementation unit, Electron process boundaries, preload/IPC security contract, renderer privilege limits, verification commands, and replan triggers. Use Codanna where useful and record fallback reads. Request read-only adversarial review of the plan before implementation starts.
```
