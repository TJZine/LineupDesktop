# RD-09 Secure Storage And Persistence Boundary Plan

**Plan Status:** complete

**Task family:** feature/design

**Tier:** Tier 3

**Controller phase:** done

**Verification classification:** new regression/contract test required

MODEL_SUGGESTION: GPT-5.5, high reasoning for review; GPT-5.5, medium reasoning for implementation.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: [$lineup-desktop-feature-quality-loop](/Users/tristan/Software/LineupDesktop/.agents/skills/lineup-desktop-feature-quality-loop/SKILL.md)
TASK: Plan RD-10 Plex Auth, Discovery, And Library Import
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: none
ARTIFACT: completed RD-09 Secure Storage And Persistence Boundary
FILES:
- AGENTS.md
- docs/AGENTIC_DEV_WORKFLOW.md
- docs/architecture/CURRENT_STATE.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/import-ledger.md
- docs/architecture/upstream-behavior-guardrails.md
- docs/roadmap/desktop-port-roadmap.md
- docs/plans/2026-05-10-rd-09-secure-storage-persistence-boundary-plan.md
- src/contracts/persistence.ts
- src/main/persistence/appDataPaths.ts
- src/main/persistence/secureStorageCodec.ts
- src/main/persistence/desktopPersistenceStore.ts
- src/__tests__/persistenceBoundary.test.ts
- package.json
BLOCKERS: none known.
MESSAGE: Create the RD-10 Plex Auth, Discovery, And Library Import plan. Start from completed RD-09: main-owned persistence now has renderer-safe account/server/credential-handle contracts, app-data path ownership, an injected Electron safeStorage codec seam, encrypted Plex credential records, selected-server state, unavailable/corrupt classification, fail-closed no-plaintext behavior, and tests. RD-09 does not wire Plex auth/discovery/library runtime, preload/renderer APIs, network transport, scheduler/channel persistence, backup/restore implementation, package/dependency changes, or copied/adapted upstream source. RD-10 should plan the first bounded Plex auth/discovery/library import behind this storage/redaction boundary, update the import ledger before or with any copied/adapted source, and keep tokens, raw headers, tokenized URLs, raw Plex payloads, and transport diagnostics out of renderer-facing contracts, logs, fixtures, docs, and Codex output.

## Goal

Create the first Desktop secure-storage and persistence boundary after RD-08:
`desktop-secure-storage-boundary-core`.

The unit must establish main-owned credential storage, app-data path ownership,
selected-server persistence shape, renderer-safe snapshot contracts, redacted
diagnostic expectations, and test coverage before RD-10 imports Plex auth,
discovery, or library runtime. It must use Electron `safeStorage` only through a
small injected main-process codec seam so unit tests can prove behavior without
loading Electron runtime.

## Non-Goals

- Do not import or adapt original Lineup product source in this unit.
- Do not contact Plex, start auth, discover servers, load libraries, create
  network transport, or resolve playback streams.
- Do not wire renderer UI, preload APIs, production IPC, player adapter,
  native-helper, scheduler, channel, settings, packaging, signing, installer,
  or dependency behavior.
- Do not store real credentials, add fixtures containing real secrets, or write
  local run evidence.
- Do not expose raw credential values, raw headers, tokenized URLs, raw Plex
  payloads, app paths, filesystem APIs, Electron objects, Node APIs, native
  handles, or secret diagnostics to renderer-facing contracts.
- Do not add backup/restore implementation. Document encrypted-credential
  backup/restore expectations and stop conditions for later release-gate work.

## Parent Architecture Alignment

`docs/architecture/CURRENT_STATE.md` states that RD-08 completed deterministic
fixture-only stream policy and that no Plex auth/discovery/library runtime,
secure storage, selected-server state, renderer UI, production native helper,
package/dependency change, or copied/adapted upstream source exists.

`docs/architecture/security-and-secret-flow.md` already requires persistent
Plex credentials to stay outside the renderer and Electron main to own secure
credential storage and app-data paths. RD-09 turns that policy into a concrete
main-owned storage seam without yet wiring product auth.

Chosen architecture seam: `src/main/persistence/*` owns secure credential and
app-data persistence. `src/contracts/persistence.ts` owns only renderer-safe
summary types and forbidden-field vocabulary. Renderer, preload, player,
stream policy, Plex runtime, scheduler, native-helper, and package owners stay
out of scope for this unit.

## Required Reading

Read in this order before review or implementation:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-quality-loop.md`
4. `docs/agentic/plan-authoring-standard.md`
5. `docs/architecture/CURRENT_STATE.md`
6. `docs/architecture/security-and-secret-flow.md`
7. `docs/architecture/playback-architecture.md`
8. `docs/architecture/import-ledger.md`
9. `docs/roadmap/desktop-port-roadmap.md`
10. `docs/plans/2026-05-10-rd-08-desktop-stream-policy-plan.md`
11. this plan
12. `src/contracts/player.ts`
13. `src/contracts/ipc.ts`
14. `src/contracts/redaction.ts`
15. `src/main/redactedDiagnostics.ts`
16. `tools/verify-redaction.mjs`
17. `package.json`

Freshness gate: rerun `git status --short --branch` before implementation.
Stop for plan update and re-review if architecture docs, roadmap status,
Electron version/API behavior, verifier behavior, package scripts, or this plan
changed materially after this planning pass. The worktree has unrelated dirty
prior plan files; leave them untouched unless a later request expands scope.

## Required Skills

- `lineup-desktop-feature-quality-loop`: required Tier 3 controller because the
  slice touches storage/secrets and future Plex import boundaries.
- `execution-plan-authoring`: freezes the seam, scope, verification, rollback,
  and stop conditions without routine helper pseudo-code.
- `architecture-boundaries`: applies because contracts, main ownership, and
  future preload/renderer boundaries are implicated.
- `persistence-boundaries`: applies because the slice owns credentials,
  selected-server state, app paths, secure storage, and local files.
- `plex-integration-boundaries`: applies because the first credential and
  selected-server shapes are Plex-specific while Plex runtime remains out of
  scope.
- `verification-strategy`: requires new contract-style tests for storage
  status, corruption, unavailable secure storage, renderer-safe snapshots, and
  redaction invariants.
- `review-request`: plan and implementation require adversarial read-only
  review before closeout.
- `review-adjudication`: required before acting on review findings.
- `closeout-verification`: required before calling RD-09 done.

## Evidence And Discovery

- `semantic_search_with_context`: not needed after the initial doc/symbol
  search because RD-09 has no existing source owner in this checkout.
- `semantic_search_docs`: queried for secure storage, persistence,
  credentials, selected server, app data, and redaction. Codanna reported an
  enabled index but returned stale upstream-shaped `src/modules/plex/*` and
  localStorage results that are not present in this checkout.
- Impact analysis: not used because no existing in-repo storage owner exists
  and Codanna results were stale for this checkout.
- Direct reads / `rg`: read workflow docs, plan standard, current architecture,
  security/secret flow, playback architecture, import ledger, roadmap, RD-08
  plan, player/IPC/redaction contracts, main redaction helper, redaction
  verifier, package scripts, architecture lint, and source file inventory.
  Direct source inventory confirmed `src/modules` is absent and current source
  contains only shell/contracts/main-player scaffold plus RD-08 policy files.
- Official docs: Context7 checked Electron `/electron/electron` safeStorage
  docs on 2026-05-10. Electron docs describe `safeStorage` as OS-provided
  local-machine string encryption, recommend async
  `encryptStringAsync`/`decryptStringAsync`, expose
  `isAsyncEncryptionAvailable()`, and note platform caveats including Windows
  DPAPI user binding and Linux fallback/backends. Local Electron 42 typings in
  `node_modules/electron/electron.d.ts` confirm the async methods are available.

Evidence conclusions:

- RD-09 can use Electron `safeStorage` without a new dependency.
- The first unit should inject a secure-string codec instead of importing
  Electron into pure store tests.
- Renderer-facing contracts need safe profile/server/handle summaries only; raw
  credential reads must stay private to `src/main/persistence/*`.
- Backup/restore remains a documented release-gate risk because encrypted
  records may not decrypt for another OS user/profile/machine.

## Impact Snapshot

Expected blast radius:

- Owners that may change:
  - `src/contracts/persistence.ts`
  - `src/main/persistence/appDataPaths.ts`
  - `src/main/persistence/secureStorageCodec.ts`
  - `src/main/persistence/desktopPersistenceStore.ts`
  - `src/__tests__/persistenceBoundary.test.ts`
  - `docs/architecture/CURRENT_STATE.md`
  - `docs/architecture/security-and-secret-flow.md`
  - `docs/roadmap/desktop-port-roadmap.md`
  - this plan for status and closeout notes
- Public contracts that may change: add a new renderer-safe persistence
  contract module. Do not change player, IPC, shell, preload, or renderer APIs.
- Dependencies, build tools, configuration, lockfiles, and package scripts: no
  changes allowed.
- Runtime behavior: no user-visible behavior. No production IPC or UI wiring.
- Import ledger: no change unless implementation copies or adapts upstream
  Lineup source, which this unit forbids.
- Local-only artifacts: none expected.

The first unit crosses contracts and main-owned persistence, but it remains a
single persistence-boundary unit because the renderer-safe summary vocabulary
and main store shape must be reviewed together before RD-10 imports auth code.

## Files In Scope

Planning write scope:

- `docs/plans/2026-05-10-rd-09-secure-storage-persistence-boundary-plan.md`

Implementation write scope after plan review:

- `src/contracts/persistence.ts`
- `src/main/persistence/appDataPaths.ts`
- `src/main/persistence/secureStorageCodec.ts`
- `src/main/persistence/desktopPersistenceStore.ts`
- `src/__tests__/persistenceBoundary.test.ts`

Factual closeout write scope after implementation review:

- `docs/plans/2026-05-10-rd-09-secure-storage-persistence-boundary-plan.md`
- `docs/architecture/CURRENT_STATE.md`
- `docs/architecture/security-and-secret-flow.md`
- `docs/roadmap/desktop-port-roadmap.md`

## Files Out Of Scope

- `src/main/index.ts`
- `src/preload/**`
- `src/renderer/**`
- `src/main/player/**`
- `src/main/player/streamPolicy/**`
- `src/contracts/player.ts`
- `src/contracts/ipc.ts`
- `src/contracts/shell.ts`
- `tools/**`
- `package.json`
- `package-lock.json`
- `docs/architecture/import-ledger.md`, unless source is copied or adapted
- upstream Lineup checkout files
- local `docs/runs/**` evidence bundles

## Planner Self-Check

1. No product, architecture, ownership, dependency, or verification decision is
   unresolved for the first storage-boundary unit.
2. The plan does not depend on preload, renderer, Plex runtime, player, or
   package changes outside scope.
3. The files out of scope are not hiding required wiring; runtime wiring is a
   later RD-10/RD-11 unit after this seam is proven.
4. Evidence records Codanna staleness, direct reads, source inventory, and
   official Electron safeStorage docs.
5. The work is assigned to main-owned persistence and contract-safe summary
   owners, not a broad utility module.
6. A fresh implementer should not need to invent storage owner, schema shape,
   redaction rules, no-migration policy, backup/restore posture, or
   verification depth.
7. Verification commands and replan triggers are explicit below.

## Architecture Seam Decision Gate

The chosen seam is main-owned persistence:

- `src/main/persistence/appDataPaths.ts` resolves app-data file locations from
  Electron main-owned app paths.
- `src/main/persistence/secureStorageCodec.ts` adapts Electron `safeStorage`
  behind an injected async codec and reports unavailable encryption without
  falling back to plaintext.
- `src/main/persistence/desktopPersistenceStore.ts` owns encrypted credential
  records, selected-server state, corruption classification, and renderer-safe
  snapshots.
- `src/contracts/persistence.ts` exposes only safe summaries and forbidden-field
  vocabulary.

Forbidden shortcuts:

- plaintext fallback for credentials
- renderer, preload, browser storage, or broad IPC custody of secrets
- raw app paths in renderer-facing snapshots
- broad storage utilities imported across runtime owners
- old upstream path mirrors, compatibility barrels, or copied source without an
  import-ledger row
- backup/restore claims beyond documented encrypted-record expectations

Stop and replan if implementation needs renderer/preload IPC, real Plex
transport, migration from upstream localStorage, package changes, copied
upstream code, or plaintext credential persistence.

## Verification Commands

Run these after implementation:

- `npm run test:contracts`
  - Expected: passes, including new persistence-boundary tests for encrypted
    write/read, selected-server snapshots, unavailable secure storage,
    corruption handling, app-data paths, safeStorage codec behavior, and
    forbidden-field recursion.
- `npm run verify:redaction`
  - Expected: passes with no tokenized URL, raw header, or bearer-style
    credential examples in source, tests, docs, or fixtures.
- `npm run verify:docs`
  - Expected: passes after this plan and closeout docs are updated.
- `npm run verify`
  - Expected: passes before RD-09 is called complete.

Scoped source audit before closeout:

- Confirm no renderer/preload/player files changed.
- Confirm `desktopPersistenceStore` never writes plaintext credential values to
  disk and renderer-safe snapshots contain no forbidden keys or raw app paths.
- Confirm Electron `safeStorage` is only used through the main-owned codec seam
  and no plaintext fallback exists for unavailable encryption.

## Acceptance Criteria

- A tracked RD-09 plan exists and records the storage owner, schema shape,
  redaction rules, no-migration policy, backup/restore expectations,
  verification, and replan triggers.
- Main-owned persistence code can write encrypted Plex credential records and
  selected-server state to an app-data file through injected dependencies.
- Main-owned credential reads can classify present, missing, unavailable, and
  corrupt records without exposing raw credential values through renderer-safe
  snapshots.
- Renderer-safe persistence contracts contain only account/server/credential
  handle summaries and forbid privileged field keys recursively.
- Secure-storage unavailable behavior fails closed and records safe diagnostics;
  it does not store plaintext credentials.
- Backup/restore expectations are documented: encrypted credential blobs are
  local OS-user/profile bound, may be unrecoverable after machine/profile
  restore, and must be validated before public release.
- No upstream Lineup product source is copied or adapted.
- Required verification passes and implementation review is clean before the
  roadmap marks RD-09 complete.

## Replan Triggers

- Electron `safeStorage` async APIs are unavailable in the installed Electron
  version or cannot be represented without unsafe runtime imports.
- The store needs plaintext credential fallback, renderer/preload storage, raw
  app paths in contracts, or browser localStorage migration.
- Plex auth import work becomes necessary to prove the storage seam.
- Selected-server state needs network connection URLs, raw Plex payloads,
  auth material, or retry/transport policy.
- Backup/restore requirements must be implemented, not only documented.
- A package, dependency, lockfile, packaging, installer, or signing change is
  needed.
- Tests require live Plex, real credentials, OS keychain access, or local
  machine-specific evidence.
- Any copied/adapted upstream source is needed.

## Rollback Notes

Rollback is source-only for this unit: remove the new `src/contracts/persistence.ts`,
`src/main/persistence/*`, and `src/__tests__/persistenceBoundary.test.ts` files,
then revert the RD-09 plan/status docs. No migration, credential cleanup,
package restoration, helper teardown, or import-ledger cleanup is expected
because runtime wiring, real credentials, dependencies, native helper,
packaging, and upstream imports are out of scope.

If a local developer used the test store manually, delete only the local
development app-data file they created; do not add cleanup scripts or checked-in
local paths.

## Commit Checkpoints

Use one focused conventional commit after clean implementation review, for
example:

```text
feat: add secure persistence boundary
```

Do not stage unrelated dirty prior plan files unless explicitly requested.

## Closeout Notes

Implementation completed on 2026-05-10 through:

- `src/contracts/persistence.ts`
- `src/main/persistence/appDataPaths.ts`
- `src/main/persistence/secureStorageCodec.ts`
- `src/main/persistence/desktopPersistenceStore.ts`
- `src/__tests__/persistenceBoundary.test.ts`

Observed verification before closeout:

- `npm run test:contracts` passed with 75 tests.
- `npm run typecheck` passed.
- `npm run verify:architecture` passed.
- `npm run verify:redaction` passed.
- `npm run verify` passed with 75 contract tests and 69 harness/doc tests.

Review/adjudication notes:

- Implementation review found one material edge case: selected-server writes
  over a corrupt persistence file would have replaced the corrupt file with a
  new empty persistence file. The finding was accepted and fixed so
  `setSelectedPlexServer()` now returns a corrupt renderer-safe snapshot and
  leaves the corrupt file untouched.
- Source audit confirmed no preload, renderer, player, stream-policy, package,
  dependency, lockfile, native-helper, or upstream Lineup source changes landed.
- Import ledger was not updated because RD-09 copied or adapted no upstream
  Lineup product source.
