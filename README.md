# Lineup Desktop

Lineup Desktop is the Windows-first Electron version of Lineup. This repository
is intentionally scaffolded with docs, workflow rules, contracts, and harness
checks before product implementation begins.

## Current State

- Separate repo for the desktop app.
- Electron shell and helper-hosted native playback are architecture hypotheses
  recorded in [`docs/architecture/desktop-repo-genesis-adr.md`](./docs/architecture/desktop-repo-genesis-adr.md).
- Renderer shell, Plex auth/discovery/library domains, scheduler/channel domains,
  persistence adapters, stream policy, and fakeable playback seams now exist
  behind Desktop contracts and verifiers.
- Live Plex runtime transport, production native playback host, production
  renderer player wiring, and packaging implementation are not complete yet.
- All future copied/adapted Lineup slices must be recorded in
  [`docs/architecture/import-ledger.md`](./docs/architecture/import-ledger.md).

## First Checks

```sh
npm ci
npm run verify
```

Use the Node version pinned by [`.nvmrc`](./.nvmrc) before installing.

Use [`AGENTS.md`](./AGENTS.md) and
[`docs/AGENTIC_DEV_WORKFLOW.md`](./docs/AGENTIC_DEV_WORKFLOW.md) before making
changes.

## Control Plane

- Codex role configs live in `.codex/`.
- Desktop project skill wrappers live in `.agents/skills/`.
- Codanna generated indexes are local-only; use `.codannaignore` and
  [`docs/agentic/codanna-playbook.md`](./docs/agentic/codanna-playbook.md).
- CI runs `npm run verify` on Linux and Windows.
