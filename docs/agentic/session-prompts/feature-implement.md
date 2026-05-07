# Feature Implement Launcher

Use this launcher to implement an approved Lineup Desktop feature/design plan.

## Rules

- Load the approved plan before editing.
- Keep the implementation inside the approved files and seam.
- Stop and replan if Electron IPC/security, native playback, storage/secrets,
  packaging, or import scope changes beyond the plan.
- Do not copy upstream Lineup code without updating
  [`import-ledger.md`](../../architecture/import-ledger.md).
- Do not expose persistent tokens, raw Electron APIs, native handles, raw auth
  headers, or tokenized URLs to renderer-facing contracts.
- Run the verification named by the plan before closeout.

## Closeout

Report files changed, commands run, observed results, remaining risks, and
review status. Do not claim verification that was not observed.
