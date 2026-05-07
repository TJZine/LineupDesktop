# Lineup Desktop

Lineup Desktop is the Windows-first Electron version of Lineup. This repository
is intentionally scaffolded with docs, workflow rules, contracts, and harness
checks before product implementation begins.

## Current State

- Separate repo for the desktop app.
- Electron shell and helper-hosted native playback are architecture hypotheses
  recorded in [`docs/architecture/desktop-repo-genesis-adr.md`](./docs/architecture/desktop-repo-genesis-adr.md).
- No renderer UI, Plex import, native playback host, packaging implementation,
  or copied product modules exist yet.
- All future copied/adapted Lineup slices must be recorded in
  [`docs/architecture/import-ledger.md`](./docs/architecture/import-ledger.md).

## First Checks

```sh
npm install
npm run verify
```

Use [`AGENTS.md`](./AGENTS.md) and
[`docs/AGENTIC_DEV_WORKFLOW.md`](./docs/AGENTIC_DEV_WORKFLOW.md) before making
changes.
