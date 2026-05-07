# Repo Bootstrap Plan

- **Status**: completed by initial scaffold
- **Date**: 2026-05-07
- **Task family:** feature/design

## Goal

Scaffold Lineup Desktop with workflow/control-plane docs, architecture docs,
contract stubs, package scripts, and verifiers before product implementation.

## Non-Goals

- No Electron runtime implementation.
- No Plex or scheduler imports.
- No renderer UI.
- No native playback host or external media POC.
- No packaging/signing implementation.

## Architecture Seam

This plan creates the repository control plane only. Product implementation waits
for future approved plans.

## Verification Commands

Classification: broader integration/manual proof required.

```sh
npm install
npm run verify
```

Expected: package dependencies install, TypeScript contracts typecheck, contract
tests pass, docs verifier passes, redaction verifier passes.

## Completion Evidence

Completion is valid only after a read-only adversarial review has no unresolved
blockers and `npm run verify` passes locally.

Observed on 2026-05-07:

- `npm install` passed.
- `npm run verify` passed.
- Architecture/security review blockers were resolved.
- Workflow/harness review blockers were resolved.
