## Description

Summarize the change, the reason for it, and the approved plan or issue it follows.

## Type Of Change

- [ ] Feature or product behavior
- [ ] Architecture or contract change
- [ ] Security, secret flow, or redaction change
- [ ] Workflow, harness, or documentation change
- [ ] Refactor with no intended behavior change

## Verification

List the commands and manual checks you ran.

- [ ] `npm run verify`
- [ ] `npm run verify:docs` for docs/workflow-only changes
- [ ] Manual proof recorded when Electron, UI, playback, or packaging behavior is involved

## Desktop Boundary Checklist

- [ ] Renderer remains unprivileged
- [ ] Preload exposes only narrow typed APIs
- [ ] Persistent Plex credentials remain outside renderer code
- [ ] Token-bearing URLs, auth headers, native handles, and secret logs are not exposed to renderer-facing surfaces
- [ ] Import ledger updated for copied or adapted upstream Lineup slices
- [ ] Public release gates are not weakened
