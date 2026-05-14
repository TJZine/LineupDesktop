# RD-22 Live Plex Auth, Discovery, And Library Runtime UI

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3

## Goal

Deliver the smallest real Plex runtime UI slice that lets Lineup Desktop perform account setup and library selection through reviewed Desktop owners: live PIN/profile/Plex Home sign-in, selected-server discovery/restore, and renderer-safe library browse/search/metadata summaries.

This plan authorizes planning for implementation only. The planner pass that created this file does not implement source changes.

## Non-Goals

- No channel creation, channel editing, settings persistence, channel persistence, scheduler runtime, EPG runtime, playback, production native helper, package/dependency/lockfile/signing/update/native-media change, installer behavior, public release claim, platform expansion, or upstream source import.
- No renderer-owned token, auth-header, connection URI, filesystem path, raw Plex payload, Electron, Node, safeStorage, app-path, or transport retry policy.
- No broad preload RPC bridge, arbitrary channel strings, renderer persistence API, compatibility shim, old upstream path preservation, or fallback API family outside the exact RD-22 contract.
- No tracked Windows proof with private account, server, library, media, filesystem, token, header, raw payload, or connection detail.

## Parent Architecture Alignment

RD-22 is the first source/runtime slice after RD-21 docs/product-roadmap closeout. It advances the current `CURRENT_STATE.md` gaps for live Plex auth/discovery/library transport, live renderer Plex API, and renderer setup UI while preserving RD-09 persistence custody, RD-10 Plex domain seams, RD-13/RD-15 unprivileged renderer composition, and RD-17 diagnostics/redaction.

The owner seam is: renderer sends typed setup/library intents through preload; preload validates narrow method payloads and result envelopes; main authorizes IPC, owns live Plex transport, credentials, selected connection memory, selected-server storage, and sanitized diagnostics; existing Plex auth/discovery/library domain helpers parse and project summaries; renderer renders only safe setup/library view state.

## Required Reading

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-plan.md`
4. `docs/agentic/plan-authoring-standard.md`
5. `docs/architecture/CURRENT_STATE.md`
6. `docs/architecture/security-and-secret-flow.md`
7. `docs/architecture/renderer-architecture.md`
8. `docs/architecture/file-shape-guardrails.md`
9. `docs/architecture/import-ledger.md`
10. `docs/roadmap/desktop-port-roadmap.md` RD-22 section
11. `docs/development/windows-ui-proof-plan.md`
12. `docs/product/lineup-product-parity-matrix.md` Plex auth, discovery, and library rows
13. Source files named in `## Files In Scope`

Freshness gate: if any source contract, main/preload composition, persistence schema, Plex parser/domain owner, renderer route owner, verifier, or RD-21 roadmap/parity artifact changed materially after this plan was written, stop for review or update this plan before implementation.

## Required Skills

- `lineup-desktop-feature-plan`: tracked Tier 3 feature/design plan routing.
- `execution-plan-authoring`: scope, owner seams, verification, rollback, and stop conditions are frozen here instead of invented during implementation.
- `architecture-boundaries`: RD-22 changes IPC, contracts, preload, main composition, and renderer/main responsibility split.
- `persistence-boundaries`: credential and selected-server state must stay behind existing main-owned persistence owners.
- `plex-integration-boundaries`: live Plex transport, token handling, auth, discovery, selected server, and library summaries are in scope.
- `ui-composition-patterns`: renderer setup/library UI must remain unprivileged, focusable, accessible, and cleaned up.
- `verification-strategy`: live Windows proof plus automated seam tests are required because injected tests alone cannot prove RD-22.
- `review-request`: next gate is read-only plan review.
- `closeout-verification`: required before implementation closeout, staging, commit, or handoff.

## Evidence And Discovery

- `semantic_search_with_context`: Codanna index was present, but the live Plex runtime query returned one useful library symbol, `getPlexRequestIntentForChannelSetup`, plus noisy stream-policy/player hits. It did not reliably locate the RD-22 seam, so direct reads are the primary evidence path.
- `semantic_search_docs`: no semantically similar RD-22 documentation was returned, so roadmap/parity/proof docs were read directly.
- Impact analysis: not run for this planning pass because no source edit is made; the implementation unit must use source reads and focused `rg`/Codanna checks again before editing public contracts or IPC.
- Direct reads / `rg`: inspected `src/contracts/plex.ts`, `src/contracts/ipc.ts`, `src/contracts/shell.ts`, `src/preload/index.cts`, `src/__tests__/integration/preloadContractVocabulary.test.ts`, `src/main/index.ts`, `src/main/plex/auth/*`, `src/main/plex/discovery/*`, `src/main/plex/library/*`, `src/main/persistence/*`, renderer shell/setup files, contract tests, package scripts, file-shape guardrails, current architecture, security flow, renderer architecture, roadmap, parity matrix, and Windows proof plan.
- Accepted review findings: same-file preload guard growth is required for RD-22 because the app uses sandboxed preload plus plain `tsc` without a preload bundler, and package/build changes are non-goals. The Plex bridge contract also needed exact channel, DTO, request-id, validation, error, cancellation, and stale-result decisions, now frozen below.
- Official docs: checked on 2026-05-14 for minimal Plex API claims only: `https://plexapi.dev/api-reference/plex/get-a-pin`, `https://plexapi.dev/api-reference/plex/get-access-token`, `https://plexapi.dev/api-reference/authentication/get-token-details`, `https://plexapi.dev/api-reference/authentication/get-user-sign-in-data`, `https://plexapi.dev/api-reference/library/get-library-sections-main-media-provider-only`, `https://plexapi.dev/api-reference/library/get-all-items-in-library`, `https://plexapi.dev/api-reference/search/search-hub`, `https://plexapi.dev/api-reference/content/get-a-metadata-item`, `https://docs.plex.tv/`, and `https://developer.plex.tv/pms/`. Keep implementation claims limited to the endpoints actually used and observed.
- Import ledger: no upstream Lineup import is planned. If an implementer proposes copied or adapted upstream source, stop, justify it, and update `docs/architecture/import-ledger.md` before or with the import.

## Impact Snapshot

- Owners that may change: Plex contracts, IPC contract literals, shell preload API type, preload bridge/guards, main Plex runtime/transport/IPC/composition owners, persistence composition wiring, diagnostics event reporting, and renderer setup/library UI modules.
- Public contracts that may change: `src/contracts/plex.ts`, `src/contracts/ipc.ts`, and `src/contracts/shell.ts` add a `plex` bridge namespace, specific Plex IPC channels, operation envelopes, request/result DTOs, runtime snapshot, and renderer-safe auth/profile/server/library summaries.
- Dependency, build-tool, configuration, and lockfile changes: none authorized. Use existing TypeScript/Electron/Node platform APIs and existing package scripts. Stop before adding packages, lockfile changes, build-tool changes, feature flags, env configuration, release metadata, or native media/helper assets.
- Commands/tests/docs that must change: contract tests, preload parity/guard tests, main Plex runtime/IPC/transport tests, renderer setup/library tests, and closeout docs after implementation. The active plan itself must pass docs/redaction/diff checks.
- User-visible behavior that must not change: existing shell/window/player/diagnostics APIs, fake-backed player/guide behavior, fullscreen bridge, support bundle export, and current renderer navigation must continue to work.
- Cross-boundary status: Unit 1 is a contract/bridge review gate. No main or renderer runtime implementation starts until the Plex contract and bridge shape are reviewed.

## Files In Scope

Execution Unit 1, contract and preload bridge gate:

- `src/contracts/plex.ts`: add Plex runtime operation/result envelopes, error codes, request ids, snapshots, and safe DTOs for PIN, profile, home users, servers, library sections/items/search/metadata. Existing forbidden-field guard remains the contract safety floor.
- `src/contracts/ipc.ts`: add exact Plex channel constants only for approved methods.
- `src/contracts/shell.ts`: add `lineupDesktop.plex` methods only; no generic invoke method.
- `src/preload/index.cts`: add only channel constants, the `plex` namespace object, and same-file Plex request/result guard vocabulary required by sandboxed preload. No preload module split is authorized in RD-22.
- `docs/architecture/file-shape-guardrails.md`: in scope only if `src/preload/index.cts` grows above its reviewed 1031-line baseline; update the existing preload row in the same implementation unit with the RD-22 same-file sandbox rationale and a future bundler/decomposition trigger.
- `src/__tests__/contracts/contracts.test.ts` and `src/__tests__/integration/preloadContractVocabulary.test.ts`: update public seam and same-file preload parity proof.

Execution Unit 2, main Plex runtime and storage composition:

- `src/main/plex/livePlexTransport.ts`: new main-owned fetch transport for plex.tv/PMS requests, auth headers, JSON/text response normalization, timeout/abort wiring, and status mapping.
- `src/main/plex/desktopPlexRuntime.ts`: new main-owned runtime orchestrator for active PIN, account/profile, Plex Home switch, credential availability, server discovery/restore/select, selected connection memory, and library operations.
- `src/main/plex/plexIpc.ts`: new authorized IPC handler owner that maps typed channels to runtime calls and returns safe envelopes.
- `src/main/plex/plexComposition.ts`: new composition owner for Electron app paths, safeStorage codec, RD-09 persistence store, RD-10 credential/selected-server adapters, live transport, runtime, and diagnostics ports.
- `src/main/index.ts`: limited to importing/registering Plex composition and teardown; no transport, retry, parsing, storage, or error policy lives here.
- Existing `src/main/plex/auth/*`, `src/main/plex/discovery/*`, `src/main/plex/library/*`, `src/main/persistence/*`, `src/main/diagnostics/*`, and focused main tests may be touched only to connect or public-test the approved runtime seam.

Execution Unit 3, renderer setup/library UI:

- New focused renderer modules under `src/renderer/plexRuntimeState.ts`, `src/renderer/plexRuntimeActions.ts`, and `src/renderer/plexRuntimeDom.ts` own Plex setup state, async bridge actions, cancellation cleanup, focus targets, and live library rendering.
- Existing `src/renderer/staticDom.ts`, `src/renderer/domBindings.ts`, `src/renderer/routeDom.ts`, `src/renderer/workflow.ts`, `src/renderer/settingsSetup.ts`, `src/renderer/navigation.ts`, `src/renderer/index.ts`, `src/renderer/styles.css`, and `src/renderer/styles/*` may change only to host the RD-22 account/server/library selection UI on current settings/channel-setup surfaces.
- Renderer tests under `src/__tests__/renderer/**` update for route reachability, focus, async state transitions, sanitized failures, and non-overlap/layout-safe DOM expectations.

Execution Unit 4, closeout proof and docs:

- `docs/architecture/CURRENT_STATE.md`, `docs/roadmap/desktop-port-roadmap.md`, `docs/product/lineup-product-parity-matrix.md`, and `docs/development/windows-ui-proof-plan.md` may be updated only after implementation/review/proof changes their durable conclusions.
- Ignored local Windows evidence may live under `docs/runs/rd-22-live-plex-auth-discovery-library-runtime-ui/` and must remain redaction-safe.

Parallelism: no source parallelism before Unit 1 review. After reviewed contracts, main and renderer work may proceed in parallel only if both use the frozen `src/contracts/plex.ts`/`shell.ts` API without changing it; any contract change reunifies the work and returns to review.

## Files Out Of Scope

- `package.json`, lockfiles, dependency manifests, build tooling, signing/update/installer/package output, native media assets, and public release docs.
- `src/native-helper/**`, production native playback owners, RD-06 spike tools except as unrelated proof references, and player adapter/runtime behavior not needed for RD-22.
- `src/main/player/**`, `src/main/plex/streamResolver.ts`, `src/contracts/player.ts`, `src/domain/scheduler/**`, `src/domain/channel/**`, and channel persistence/authoring runtime.
- Renderer guide/player overlay runtime beyond preserving existing behavior.
- New persistence schema, backup/restore, renderer persistence IPC, selected Plex Home profile persistence, and channel/settings persistence.
- Upstream source imports unless a reviewed replan justifies and ledgers them.
- Tracked raw run logs, raw screenshots containing private Plex names, raw support bundles, raw IPC frames, raw API responses, or token/header/URL/path evidence.

## Architecture Health

File-shape evidence from `docs/architecture/file-shape-guardrails.md`: `src/preload/index.cts` is 1031 lines and hard-overage; `src/main/player/plexPlaybackRuntime.ts` is 798; `src/contracts/player.ts` is 703; `src/main/plex/streamResolver.ts` is 662; `src/main/player/streamPolicy/desktopStreamPolicy.ts` is 627; channel/domain files also remain guarded. Current measured RD-22-adjacent files are `src/main/index.ts` 303, `src/contracts/plex.ts` 187, `src/contracts/ipc.ts` 106, `src/contracts/shell.ts` 141, `src/renderer/index.ts` 274, `src/renderer/workflow.ts` 375, `src/renderer/settingsSetup.ts` 394, `src/renderer/staticDom.ts` 164, and `src/renderer/routeDom.ts` 376.

Decision: decompose and avoid owner hotspots except for a reviewed RD-22 same-file preload exception. Add Plex runtime behavior in new focused main and renderer modules; keep `src/main/index.ts` as composition/IPC wiring only; keep `src/preload/index.cts` limited to required channel constants, the `plex` bridge namespace, and same-file Plex request/result guards. Do not add a preload guard module, bundler, package/build change, player, stream resolver, stream policy, scheduler, or channel hotspot work in RD-22.

The same-file preload exception is temporary and narrow: because sandboxed preload plus plain `tsc` cannot safely split preload guard code without build/bundler scope, RD-22 may grow `src/preload/index.cts` only for exact Plex bridge vocabulary. If the file exceeds its 1031-line allowlist baseline, update `docs/architecture/file-shape-guardrails.md` before or with the source change, explain the sandboxed preload rationale, and set the decomposition trigger to introduce reviewed preload bundling or another reviewed split before any later bridge namespace or broad guard family is added.

The implementation must not raise file-shape baselines to pre-authorize future growth. Run `npm run verify:maintainability` through `npm run verify:architecture`/`npm run verify` after production source changes, and stop if any touched guarded file grows beyond its reviewed baseline without a new review decision.

## Planner Self-Check

1. Product/architecture/ownership/dependency/verification decisions are resolved for this slice: main owns live Plex transport, storage, selected connection, diagnostics, and IPC; preload owns narrow guards; renderer owns UI state only; no dependency or package change is allowed.
2. Adjacent contract/type changes are in scope where needed: `plex.ts`, `ipc.ts`, `shell.ts`, preload parity, contract tests, main IPC tests, and renderer tests.
3. Files frozen out of scope are not hidden wiring dependencies. Playback, channel creation, package, native helper, stream resolver, and scheduler/channel owners are not needed to prove account setup and library selection.
4. Evidence path and Codanna fallback are recorded.
5. Work is assigned to repo-preferred owners and decomposes around `src/preload/index.cts` and `src/main/index.ts`.
6. Tier 3 Architecture Health includes file-shape evidence plus decomposition/avoidance decisions.
7. A fresh implementer should not need to invent security, IPC, persistence, Plex transport, renderer, packaging, import, rollback, or verification policy.
8. Verification commands, expected outcomes, Windows proof, and stop/replan triggers are explicit below.

## Architecture Seam Decision Gate

Chosen seam: `LineupDesktopPreloadApi.plex` exposes specific methods backed by exact IPC channels. No method accepts a channel name, arbitrary operation string, raw endpoint, raw query, raw payload, or caller-supplied request id.

`src/contracts/ipc.ts` must add exactly these constants:

- `LINEUP_PLEX_GET_SNAPSHOT_CHANNEL = 'lineup:plex:getSnapshot'`
- `LINEUP_PLEX_REQUEST_PIN_CHANNEL = 'lineup:plex:requestPin'`
- `LINEUP_PLEX_POLL_PIN_CHANNEL = 'lineup:plex:pollPin'`
- `LINEUP_PLEX_CANCEL_PIN_CHANNEL = 'lineup:plex:cancelPin'`
- `LINEUP_PLEX_GET_HOME_USERS_CHANNEL = 'lineup:plex:getHomeUsers'`
- `LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL = 'lineup:plex:switchHomeUser'`
- `LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL = 'lineup:plex:restoreSelectedServer'`
- `LINEUP_PLEX_REFRESH_SERVERS_CHANNEL = 'lineup:plex:refreshServers'`
- `LINEUP_PLEX_SELECT_SERVER_CHANNEL = 'lineup:plex:selectServer'`
- `LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL = 'lineup:plex:listLibrarySections'`
- `LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL = 'lineup:plex:listLibraryItems'`
- `LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL = 'lineup:plex:searchLibrary'`
- `LINEUP_PLEX_GET_METADATA_CHANNEL = 'lineup:plex:getMetadata'`

`src/contracts/shell.ts` must add exactly this `lineupDesktop.plex` method surface:

- `getSnapshot()`
- `requestPin()`
- `pollPin({ pinId })`
- `cancelPin({ pinId })`
- `getHomeUsers()`
- `switchHomeUser({ userId, pin? })`
- `restoreSelectedServer()`
- `refreshServers()`
- `selectServer({ serverId })`
- `listLibrarySections()`
- `listLibraryItems({ sectionId, offset?, limit?, sort? })`
- `searchLibrary({ query, sectionId?, limit? })`
- `getMetadata({ ratingKey })`

`src/contracts/plex.ts` must define these request envelopes. Preload creates `requestId` values; renderer callers cannot provide them:

- `PlexEmptyRequest = PlexIpcRequest<Record<string, never>>`
- `PlexPollPinRequest = PlexIpcRequest<{ pinId: number }>`
- `PlexCancelPinRequest = PlexIpcRequest<{ pinId: number }>`
- `PlexSwitchHomeUserRequest = PlexIpcRequest<{ userId: string; pin?: string | null }>`
- `PlexSelectServerRequest = PlexIpcRequest<{ serverId: string }>`
- `PlexListLibraryItemsRequest = PlexIpcRequest<{ sectionId: string; offset?: number; limit?: number; sort?: string }>`
- `PlexSearchLibraryRequest = PlexIpcRequest<{ query: string; sectionId?: string; limit?: number }>`
- `PlexGetMetadataRequest = PlexIpcRequest<{ ratingKey: string }>`

`PlexIpcRequest<TPayload>` is exactly `{ requestId: string; payload: TPayload }`. Empty-payload methods still send `{ requestId, payload: {} }`.

Request id policy: preload creates request ids using the prefix for the method family, the current timestamp, and random base36 suffix; ids must match `^[A-Za-z0-9._-]{1,120}$`. Main rejects invalid ids as `PLEX_VALIDATION_FAILED`. Preload never forwards invalid renderer input; it returns a local validation failure with a generated `plex-validation-*` request id that also satisfies the same pattern.

Every method returns `PlexIpcResult<TValue>`:

- success: `{ ok: true; value: TValue; requestId: string }`
- failure: `{ ok: false; error: PlexRuntimeError; requestId: string; cancelled?: true; stale?: true }`

`PlexRuntimeError` is exactly `{ code: PlexRuntimeErrorCode; message: string; retryable: boolean; recoverable: boolean; operation: PlexRuntimeOperation; httpStatus?: number }`. Error messages must be generic and sanitized. `PlexRuntimeOperation` is exactly `'getSnapshot' | 'requestPin' | 'pollPin' | 'cancelPin' | 'getHomeUsers' | 'switchHomeUser' | 'restoreSelectedServer' | 'refreshServers' | 'selectServer' | 'listLibrarySections' | 'listLibraryItems' | 'searchLibrary' | 'getMetadata'`. The error taxonomy is exactly: `PLEX_UNAUTHORIZED`, `PLEX_VALIDATION_FAILED`, `PLEX_CANCELLED`, `PLEX_STALE_RESULT`, `PLEX_AUTH_REQUIRED`, `PLEX_AUTH_INVALID`, `PLEX_PIN_EXPIRED`, `PLEX_PIN_TIMEOUT`, `PLEX_RATE_LIMITED`, `PLEX_SERVER_UNREACHABLE`, `PLEX_ACCESS_DENIED`, `PLEX_RESOURCE_NOT_FOUND`, `PLEX_STORAGE_UNAVAILABLE`, `PLEX_STORAGE_CORRUPT`, `PLEX_PARSE_FAILED`, `PLEX_LIBRARY_FAILED`, and `PLEX_UNKNOWN`.

Cancelled, aborted, and stale semantics:

- Explicit user cancellation through `cancelPin` returns success with `{ pinId, snapshot }` when main accepted the cancellation.
- Work aborted by user navigation, newer same-family request, shutdown, or runtime reset returns failure code `PLEX_CANCELLED` with `cancelled: true`.
- Late results from an older runtime epoch or superseded request return failure code `PLEX_STALE_RESULT` with `stale: true` if surfaced at all, and must not mutate snapshot, selected server, account/profile, library results, or diagnostics beyond a sanitized stale/cancelled event.
- Aborted/stale failures are recoverable, not retryable by default, and must not include raw operation inputs.

`getSnapshot()` returns `PlexIpcResult<PlexRuntimeSnapshot>`. `PlexRuntimeSnapshot` is exactly:

```ts
interface PlexRuntimeSnapshot {
  auth: {
    state: 'signed-out' | 'pin-pending' | 'signed-in';
    pin: PlexPinSummary | null;
    profile: PlexAuthProfileSummary | null;
    homeUsers: readonly PlexHomeUserSummary[];
    credentialStatus: 'missing' | 'present' | 'unavailable' | 'corrupt';
  };
  servers: {
    status: 'idle' | 'loading' | 'ready' | 'failed';
    selected: PlexServerSummary | null;
    items: readonly PlexServerSummary[];
    lastSelection: PlexServerSelectionSummary | null;
  };
  library: {
    status: 'idle' | 'loading' | 'ready' | 'failed';
    sections: readonly PlexLibrarySectionSummary[];
    selectedSectionId: string | null;
    items: readonly PlexMediaItemSummary[];
    search: { query: string; items: readonly PlexMediaItemSummary[] } | null;
    metadata: PlexMediaItemSummary | null;
  };
  lastError: PlexRuntimeError | null;
  updatedAtMs: number;
}
```

`PlexPinSummary` is exactly `{ id: number; code: string; expiresAtMs: number; claimed: boolean }`; it must not expose client identifiers or auth material.

Method result values are exact:

- `requestPin()` -> `{ pin: PlexPinSummary; snapshot: PlexRuntimeSnapshot }`
- `pollPin({ pinId })` -> `{ pin: PlexPinSummary; profile: PlexAuthProfileSummary | null; snapshot: PlexRuntimeSnapshot }`
- `cancelPin({ pinId })` -> `{ pinId: number; snapshot: PlexRuntimeSnapshot }`
- `getHomeUsers()` -> `{ users: readonly PlexHomeUserSummary[]; snapshot: PlexRuntimeSnapshot }`
- `switchHomeUser({ userId, pin? })` -> `{ profile: PlexAuthProfileSummary; snapshot: PlexRuntimeSnapshot }`
- `restoreSelectedServer()` -> `{ selection: PlexServerSelectionSummary; snapshot: PlexRuntimeSnapshot }`
- `refreshServers()` -> `{ servers: readonly PlexServerSummary[]; snapshot: PlexRuntimeSnapshot }`
- `selectServer({ serverId })` -> `{ selection: PlexServerSelectionSummary; snapshot: PlexRuntimeSnapshot }`
- `listLibrarySections()` -> `{ sections: readonly PlexLibrarySectionSummary[]; snapshot: PlexRuntimeSnapshot }`
- `listLibraryItems({ sectionId, offset?, limit?, sort? })` -> `{ sectionId: string; offset: number; limit: number; items: readonly PlexMediaItemSummary[]; snapshot: PlexRuntimeSnapshot }`
- `searchLibrary({ query, sectionId?, limit? })` -> `{ query: string; sectionId: string | null; items: readonly PlexMediaItemSummary[]; snapshot: PlexRuntimeSnapshot }`
- `getMetadata({ ratingKey })` -> `{ item: PlexMediaItemSummary; snapshot: PlexRuntimeSnapshot }`

Per-method validation policy: preload and main both require finite positive `pinId`, non-empty trimmed `userId`, optional protected-home `pin` as a short string or null, non-empty `serverId`, non-empty `sectionId`, normalized non-negative `offset`, bounded positive `limit`, optional short `sort`, non-empty search `query`, and non-empty `ratingKey`. Invalid inputs return `PLEX_VALIDATION_FAILED` without IPC when caught in preload and without runtime mutation when caught in main. Protected-home `pin` may transit renderer to main only for the switch call; it must not be persisted, logged, echoed, included in diagnostics, or retained after the call.

Transport owner: `src/main/plex/livePlexTransport.ts` owns all live HTTP details, auth headers, endpoint URLs, status mapping, response parsing, timeout, and abort propagation. It may use built-in `fetch`, `URL`, and `AbortController`; it must not add dependencies. It returns only payloads to existing domain parsers or sanitized transport errors to the runtime, never to renderer/preload.

Storage owner: `src/main/plex/plexComposition.ts` wires `resolveDesktopAppDataPaths(app)`, `createElectronSafeStorageCodec(safeStorage)`, `DesktopPersistenceStore`, `DesktopPlexCredentialStore`, and `DesktopPlexSelectedServerStore`. RD-22 persists only the Plex account credential already supported by RD-09 and selected-server summary already supported by RD-09/RD-10. Active Plex Home switched-profile tokens remain main-memory only; adding persisted active-profile credentials is a replan.

Renderer-safe shapes: `src/contracts/plex.ts` keeps display summaries for UI while forbidding secret and transport fields. PIN summary exposes `id`, `code`, expiry, and claimed state only. Profile/home-user summaries use existing safe fields. Server summaries use existing safe fields without connection URI/address/port. Library sections/items/search/metadata use existing safe summaries and may include titles needed for UI; diagnostics and tracked proof must treat account/server/media names as private and redact or replace them with counts/categories.

Diagnostics/redaction: main reports operation, surface, status, safe error code, retryable/cancelled flags, storage availability, and counts only. No token, header, tokenized URL, raw Plex payload, connection detail, app path, local path, private display name, raw response, raw IPC frame, or raw support-bundle content may enter renderer diagnostics, support bundles, tracked docs, or Codex output. Use existing RD-17 redaction vocabulary and run `npm run verify:redaction`.

Forbidden shortcuts: broad RPC bridges, arbitrary renderer channel strings, renderer transport/fetch for Plex, renderer storage, token-bearing preload state, preload module splitting without a reviewed bundler/build plan, raw secret diagnostics, compatibility shims, dependency additions, package edits, production playback hooks, channel persistence, upstream imports without ledger, and changing `connect-src 'none'` to allow renderer network.

Stop at this gate if implementation requires any forbidden shortcut or contradicts the exact API shape above.

## Verification Commands

Verification classification: broader integration/manual proof required.

Planner-pass verification after this file is created:

- `npm run verify:docs`: expected to pass active-plan structure checks, Tier 3 handoff checks, and Architecture Health checks.
- `npm run verify:redaction`: expected to pass with no secret, path, token/header, raw Plex, or privileged diagnostic findings in the tracked plan.
- `git diff --check`: expected to report no whitespace errors.

Implementation closeout verification:

- `npm run verify`: expected to pass typecheck, architecture lint/maintainability, all contract/main/preload/renderer/harness tests, docs, and redaction.
- `npm run verify:docs`: expected to pass after plan/source-closeout doc updates.
- `npm run verify:redaction`: expected to pass after tests, fixtures, docs, diagnostics, and ignored proof summaries are scanned or sanitized as applicable.
- `git diff --check`: expected to report no whitespace errors.

Focused proof expected inside `npm run verify` or explicit command output before closeout:

- Contract tests prove the exact Plex preload API keys, channel literals, operation envelopes, forbidden field guards, and no generic invoke method.
- Preload tests prove same-file Plex guard behavior, approved IPC method/channel use, single `lineupDesktop` exposure, and no raw Electron/Node/secret forwarding.
- Main tests prove auth PIN/poll/cancel, Plex Home user switch, credential storage failures, server refresh/restore/select, selected-connection main custody, library section/items/search/metadata projection, cancellation, stale result rejection, sanitized errors, and diagnostics redaction.
- Renderer tests prove setup/library route reachability, focus behavior, async loading/cancel/failure states, safe display summaries, search/metadata interactions, cleanup on route/window teardown, and no regression of existing fake-backed player/guide surfaces.

Windows proof before implementation closeout:

- Run the live RD-22 product path on Windows and store only ignored redaction-safe evidence under `docs/runs/rd-22-live-plex-auth-discovery-library-runtime-ui/`.
- The summary must record platform, app mode/build identity, credential availability status, PIN requested/polled/cancelled or claimed, profile/Plex Home selection observed, server count/selection/restore observed, library section count, browse count, search count, metadata summary category/counts, sanitized auth/discovery/library failures, and redaction scan status.
- The summary must not record private account names, server names, library titles, media titles, raw screenshots, raw responses, tokens, headers, URLs, connection details, filesystem paths, or support-bundle contents.

## Acceptance Criteria

- `lineupDesktop.plex` contains only the approved methods in the seam gate, with no broad invoke or arbitrary channel parameter.
- Main owns live Plex transport, credentials, selected connection memory, selected-server persistence, cancellation, error normalization, and diagnostics.
- Preload validates renderer inputs/results and forwards only typed envelopes through approved channel constants.
- Renderer shows a usable account setup and library selection path for sign-in, profile/Plex Home, server discovery/restore/select, library browse/search, and metadata summaries without owning transport or storage.
- Existing player, guide, settings, support bundle, shell, fullscreen, and diagnostics behavior remains compatible.
- Safe storage unavailability, credential missing/corrupt/unavailable states, auth failures, discovery failures, library failures, cancellation, and stale results are visible as sanitized UI states.
- Windows proof observes live sign-in/profile/server picker/restore/library browse-search/sanitized failures/credential availability with redaction-safe summaries only.
- No dependency, package, native-helper, playback, channel persistence, settings persistence, public release, or upstream import scope lands in RD-22.
- Plan review and implementation review are clean before closeout.

## Replan Triggers

- Any Plex endpoint or official docs behavior requires renderer-held tokens, raw URLs, raw auth headers, broad network access from renderer, or new dependencies.
- Live Plex API response format cannot be parsed safely by existing parser/domain boundaries without broad new parsing policy.
- Active Plex Home profile persistence is required for the slice to be acceptable.
- Selected-server restore requires persisting connection URI/address/port or exposing connection details outside main memory.
- Cancellation cannot prevent stale PIN/profile/server/library commits.
- `src/preload/index.cts`, `src/main/index.ts`, `src/contracts/plex.ts`, or renderer composition files grow into hotspot behavior instead of focused modules.
- Windows proof cannot be captured without raw/private tracked evidence.
- Redaction verifier flags planned docs, tests, fixtures, diagnostics, or proof summaries.
- Channel creation, playback, package/release, native-helper, dependency, signing/update, or public release scope becomes necessary to prove RD-22.
- Review finds unresolved ownership, IPC/security, persistence, renderer, diagnostics, or verification ambiguity.

## Rollback Notes

- Unit 1 rollback removes Plex contract additions, channel constants, preload API additions, same-file Plex preload guards, any preload file-shape guardrail row update, and related tests, returning the public API to shell/window/player/diagnostics only.
- Unit 2 rollback unregisters Plex IPC, removes live transport/runtime/composition files, and leaves RD-09/RD-10 domain/persistence code unchanged. Persisted account credentials and selected-server summaries use existing RD-09 records; no RD-22 schema migration is authorized.
- Unit 3 rollback removes renderer Plex runtime modules and route UI wiring, restoring fake-backed settings/channel-setup behavior.
- Ignored Windows evidence under `docs/runs/rd-22-live-plex-auth-discovery-library-runtime-ui/` can be deleted without affecting source.
- Durable docs should only be updated after reviewed implementation/proof; if implementation rolls back, do not promote RD-22 completion claims to current-state, roadmap, parity, or proof docs.

## Commit Checkpoints

- Use one focused commit per reviewed execution unit unless review requests a smaller split.
- Suggested commits: `feat: add plex runtime bridge contracts`, `feat: add live plex runtime ipc`, `feat: add plex setup library ui`, and `docs: close rd-22 live plex proof`.
- Keep the active plan change separate from product implementation when practical.
- Do not stage unrelated RD-21 unstaged docs unless the user explicitly asks.

MODEL_SUGGESTION
PLANNER: gpt-5 high reasoning
IMPLEMENTER: gpt-5 high reasoning
REVIEWER: gpt-5 high reasoning
WHY: Tier 3 work touches Electron IPC/security, live Plex transport, storage/secrets, renderer UI, diagnostics, and Windows proof.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-review
TASK: Review RD-22 Live Plex Auth, Discovery, And Library Runtime UI Plan
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md
ARTIFACT: docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md
FILES:
- docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md
- docs/agentic/plan-authoring-standard.md
- docs/architecture/CURRENT_STATE.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/file-shape-guardrails.md
- src/contracts/plex.ts
- src/contracts/ipc.ts
- src/contracts/shell.ts
- src/preload/index.cts
- src/main/index.ts
- src/main/plex/**
- src/main/persistence/**
- src/renderer/**
BLOCKERS: none
MESSAGE:
Review the active RD-22 Tier 3 plan for Lineup Desktop. Stay read-only. Prioritize whether the main/preload/renderer Plex contract, live transport ownership, persistence boundary, renderer-safe shapes, diagnostics/redaction policy, Windows proof strategy, file-shape decisions, execution units, rollback notes, and verification commands are decision-complete and consistent with the current repo architecture. Lead with blocking findings and exact file/section references. If clean, say the plan is ready for implementation handoff through the feature-quality loop.
