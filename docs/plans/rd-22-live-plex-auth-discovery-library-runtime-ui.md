# RD-22 Upstream-Parity Plex Onboarding And Runtime Rebuild

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3

## Goal

Stop treating RD-22 as a nearly complete live-proof item. The Windows proof and
user-driven manual testing exposed repeated divergences from upstream Lineup in
basic Plex onboarding behavior: the PIN request shape, account profile parsing,
server connection probing, and the reachable setup UI all drifted from the
working upstream product path. Continuing to patch one live failure at a time is
not a reliable path.

This plan supersedes the prior RD-22 renderer-panel remediation plan. RD-22 now
becomes an upstream-parity rebuild of the Plex onboarding and library runtime
path, with one mandatory first unit: a direct code-level parity audit against
the upstream Lineup repo before any more product behavior is changed. The audit
must produce a durable matrix of upstream behavior, current Desktop behavior,
gap, decision, owner, files, tests, and import-ledger obligation. Only after
review of that matrix may implementation units replace the fake/debug setup
surface and weak desktop-only Plex logic with real Desktop-owned equivalents.

The target product path is a normal app onboarding flow, not proof-of-concept
UI:

- restore or request Plex sign-in
- select Plex Home/profile when applicable
- discover, restore, and explicitly select a Plex server
- list libraries
- browse/search library items
- open metadata summaries
- report failures through sanitized, user-actionable states
- preserve credential/connection/token custody in Electron main

RD-22 remains open until the upstream parity audit, implementation units,
adversarial reviews, automated verification, and live redaction-safe Windows
proof all pass.

## Non-Goals

- Do not mark RD-22 complete, archive this plan, update closeout docs, update
  roadmap/current-state/parity closeout claims, or route to RD-23 until the
  rebuilt path passes reviewed live Windows proof.
- Do not continue one-off live-patch remediation without first completing the
  upstream parity audit unit.
- Do not preserve fake setup controls, placeholder channel-authoring affordances,
  fake guide/player proof fixtures, or transport-debug panels inside reachable
  onboarding routes once the corresponding real workflow is in scope.
- Do not add RD-23 scope: no channel creation from library selections, persisted
  channel settings, scheduler-backed guide runtime, playback, production native
  helper behavior, package signing, update/install/delete, public release
  readiness, platform expansion, or upstream source import parity outside the
  RD-22 Plex onboarding/library runtime path.
- Do not use upstream path shims, compatibility barrels, broad wrappers, or
  fallback variants merely to make Desktop look like upstream. Desktop owners may
  adapt upstream behavior, but the resulting code must fit Desktop boundaries.
- Do not expose raw Plex tokens, auth headers, tokenized URLs, raw endpoint URLs,
  connection details, raw Plex payloads, local paths, account names, server
  names, library titles, media titles, raw screenshots, raw logs, raw IPC frames,
  native handles, process ids, certificates, or support bundles in tracked docs,
  diagnostics, tests, proof artifacts, or chat. The local runtime UI may display
  renderer-safe account/profile/server/library/media names returned by public
  Plex summaries because a normal app must show the user's selected content; do
  not copy those values into tracked proof, logs, docs, diagnostics, test
  fixtures, or Codex output.
- Do not change dependencies, package files, lockfiles, native helper,
  packaging, signing, update, or installer behavior.

## Parent Architecture Alignment

Desktop's intended architecture remains correct, but the implementation has not
faithfully reproduced the upstream Plex behavior:

- Renderer is unprivileged and owns display, focus, keyboard/remote interaction,
  local UI state, and sanitized presentation only.
- Preload exposes one narrow, typed `lineupDesktop.plex` bridge and validates
  request/result envelopes.
- Electron main owns Plex auth, profile switching, discovery, selected server
  persistence, selected connection custody, live Plex transport, token-bearing
  calls, library payload parsing, operation abort/stale handling, and sanitized
  diagnostics.
- Persistence owners store credentials and selected-server summaries without
  persisting raw tokens, raw connection URIs, headers, or Plex payloads.

The rebuild must preserve that Desktop process boundary while importing the
working behavior and product flow from upstream. The main architectural change
is product posture: fake scaffold surfaces are no longer acceptable for RD-22.
The reachable Plex setup path must become the actual upstream-equivalent
onboarding flow adapted for Desktop, and runtime code must be proven against
upstream semantics before live Windows proof is attempted again.

## Required Reading

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-plan.md`
4. `docs/agentic/session-prompts/feature-quality-loop.md`
5. `docs/agentic/plan-authoring-standard.md`
6. `docs/architecture/CURRENT_STATE.md`
7. `docs/architecture/security-and-secret-flow.md`
8. `docs/architecture/file-shape-guardrails.md`
9. `docs/architecture/import-ledger.md`
10. `docs/development/windows-ui-proof-plan.md`
11. `docs/product/lineup-product-parity-matrix.md`
12. `docs/roadmap/desktop-port-roadmap.md`
13. `docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md`
14. Local ignored run notes under
    `docs/runs/rd-22-live-plex-auth-discovery-library-runtime-ui/`
15. Desktop source and test files listed in `## Files In Scope`
16. Upstream source and test files listed in `## Files In Scope`

Freshness gate: before editing, run `git status --short --branch`,
`git diff --stat`, and `git -C C:\Software\Lineup rev-parse HEAD`, then compare
the current Desktop and upstream file lists against this plan. If upstream paths
moved, Desktop Plex/runtime files changed materially, the active branch changed,
the dirty baseline changed, or live proof produced a new sanitized blocker
category, update and re-review this plan before implementation.

## Required Skills

- `execution-plan-authoring`: required because the plan freezes a multi-unit
  Tier 3 rebuild, not a local patch.
- `lineup-desktop-feature-quality-loop`: required for repeated plan, review,
  implementation, verification, implementation review, and closeout gates.
- `lineup-desktop-feature-review`: required for the plan and each
  implementation unit before closeout.
- `plex-integration-boundaries`: required because Plex auth, discovery,
  selected-server state, library data, token handling, and selected connection
  custody are in scope.
- `persistence-boundaries`: required because credential and selected-server
  restore/persistence behavior must be compared and may change.
- `ui-composition-patterns`: required because the reachable setup route must be
  rebuilt as real onboarding with focus, keyboard/remote, scroll, error, and
  accessibility behavior.
- `architecture-boundaries`: required because renderer/preload/main ownership
  must remain narrow while upstream behavior is adapted.
- `verification-strategy`: required because live Windows proof is necessary but
  must not substitute for upstream parity tests.
- `review-request` and `review-adjudication`: required because Tier 3 plans,
  copied/adapted upstream behavior, Plex boundary changes, and fake-surface
  removal need adversarial review and explicit finding resolution.
- `closeout-verification`: required before staging, committing, handing off, or
  calling any unit done.

## Evidence And Discovery

- `semantic_search_with_context`: attempted through Codanna with a Plex
  onboarding/discovery/library runtime query; failed because no embeddings were
  available.
- `search_symbols`: attempted through Codanna for `Plex`; returned no symbols.
  Codanna is not useful for this pass, so direct reads and `rg` are the
  authoritative evidence path.
- `semantic_search_docs`: not useful for this pass because the active repo-doc
  paths are known and were read directly.
- impact analysis: not run because Codanna anchoring was unavailable; impact
  will be derived from direct source/test ownership reads in Unit 1 and then
  re-reviewed before implementation.
- direct reads / `rg`: read the workflow, plan standard, current RD-22 plan,
  file-shape guardrails, import ledger, active Desktop Plex file inventory,
  active Desktop renderer file line counts, upstream Plex module inventory,
  upstream onboarding/setup search results, and upstream discovery request/probe
  implementation.
- upstream evidence already present in import ledger: prior Desktop imports
  adapted upstream auth, discovery, and library behavior from upstream commit
  `bb3da904aa87be6c6a00c25e6fa340f16f788709`, but live proof now shows the
  adaptation and later live-runtime bridge/UI work diverged from upstream
  behavior in critical areas.
- upstream audit target: Unit 1 must record the current `C:\Software\Lineup`
  branch and HEAD at audit start, audit that exact upstream checkout, and note
  where that behavior differs from the older import-ledger source commit
  `bb3da904aa87be6c6a00c25e6fa340f16f788709`. Do not hardcode a stale upstream
  HEAD as the future audit target.
- dirty Desktop baseline evidence: this plan was written with a dirty worktree
  containing pre-audit live-debug patches in `src/main/plex/auth/**`,
  `src/main/plex/discovery/**`, `src/main/plex/livePlexTransport.ts`,
  `src/main/plex/desktopPlexRuntime.ts`, renderer Plex setup files, CSS, and
  focused tests. Unit 1 must classify every existing dirty source/test change as
  `retain`, `replace`, `drop`, or `rework` in the tracked parity matrix before
  those patches are committed or used as the trusted Desktop baseline.
- live Windows evidence from the current session, kept sanitized here:
  account sign-in now reaches credential-present state after local remediation;
  profile/Plex Home selection was observed; server discovery/selection still
  fails to reach the server; earlier failures included the wrong PIN code shape
  and misleading renderer error copy. Raw screenshots and private names were
  not promoted into tracked docs.
- Desktop file inventory evidence:
  `src/main/plex/livePlexTransport.ts`, `src/main/plex/desktopPlexRuntime.ts`,
  `src/main/plex/desktopPlexRuntimeSupport.ts`,
  `src/main/plex/auth/**`, `src/main/plex/discovery/**`,
  `src/main/plex/library/**`, `src/main/plex/plexIpc.ts`,
  `src/main/plex/plexComposition.ts`, `src/preload/index.cts`,
  `src/contracts/plex.ts`, `src/renderer/plexRuntimeState.ts`,
  `src/renderer/plexRuntimeActions.ts`, `src/renderer/plexRuntimeDom.ts`,
  `src/renderer/staticDom.ts`, `src/renderer/workflow.ts`,
  `src/renderer/routeDom.ts`, `src/renderer/index.ts`, and renderer CSS are the
  current RD-22 implementation surfaces.
- upstream file inventory evidence:
  `src/modules/plex/auth/**`, `src/modules/plex/discovery/**`,
  `src/modules/plex/library/**`, `src/modules/plex/shared/**`,
  `src/core/server-selection/**`, `src/modules/ui/profile-select/**`,
  `src/modules/ui/server-select/**`, `src/modules/ui/channel-setup/**`,
  `src/core/initialization/**`, `src/core/channel-setup/**`, and onboarding CSS
  under `src/styles/**` are the upstream behavior and product-flow reference
  surfaces for RD-22.
- known parity gaps from direct observation:
  Desktop live PIN request used a strong/alphanumeric code until patched;
  Desktop account parser was too strict until patched; Desktop server probes did
  not follow upstream auth-header behavior until patched; Desktop discovery
  still lacks upstream request variants/XML policy coverage in the live bridge;
  Desktop setup route is still a debug/control panel rather than upstream-style
  auth/profile/server/channel setup screens; existing tests are not organized as
  upstream parity tests.

## Impact Snapshot

Expected blast radius is intentionally large inside RD-22, but bounded outside
it:

- Plex runtime owners may change: `src/main/plex/livePlexTransport.ts`,
  `src/main/plex/auth/**`, `src/main/plex/discovery/**`,
  `src/main/plex/library/**`, `src/main/plex/desktopPlexRuntime.ts`,
  `src/main/plex/desktopPlexRuntimeSupport.ts`, `src/main/plex/plexIpc.ts`, and
  `src/main/plex/plexComposition.ts`.
- Persistence owners may change only for Plex credential/selected-server
  restore semantics and only if Unit 1 proves upstream-equivalent onboarding
  requires a Desktop persistence behavior change.
- Renderer owners may change: `src/renderer/plexRuntimeState.ts`,
  `src/renderer/plexRuntimeActions.ts`, `src/renderer/plexRuntimeDom.ts`,
  `src/renderer/staticDom.ts`, `src/renderer/domBindings.ts`,
  `src/renderer/index.ts`, `src/renderer/workflow.ts`,
  `src/renderer/routeDom.ts`, `src/renderer/navigation.ts`,
  `src/renderer/desktopInput.ts`, and renderer CSS.
- Public contracts may change only after Unit 1 proves a current contract cannot
  express upstream-equivalent behavior safely. Any contract/preload change must
  be a separate reviewed execution unit.
- Dependency, package, lockfile, native helper, packaging, signing, update, and
  installer changes are not authorized.
- Tests must change materially: add upstream-parity source audits and focused
  contract/integration tests for auth, discovery request policy, server probing,
  selected-server restore, library calls, renderer onboarding flow, fake-surface
  retirement, and redaction boundaries.
- User-visible behavior must change: the reachable setup route should stop
  looking like fake/debug scaffolding and become a normal onboarding/setup flow.
- User-visible behavior that must not regress: app shell launch, route
  navigation, keyboard/remote focus, diagnostics support-bundle safety, player
  and guide placeholder routes that remain outside RD-22, secure renderer CSP,
  and existing redaction guarantees.
- Local proof artifacts remain ignored under
  `docs/runs/rd-22-live-plex-auth-discovery-library-runtime-ui/`.

First execution unit is audit-only. No additional product behavior changes are
authorized until the parity matrix is reviewed.

## Files In Scope

### Desktop Source In Scope

- `src/contracts/plex.ts`
- `src/contracts/ipc.ts`
- `src/contracts/persistence.ts`
- `src/contracts/shell.ts`
- `src/preload/index.cts`
- `src/main/plex/livePlexTransport.ts`
- `src/main/plex/desktopPlexRuntime.ts`
- `src/main/plex/desktopPlexRuntimeSupport.ts`
- `src/main/plex/plexIpc.ts`
- `src/main/plex/plexComposition.ts`
- `src/main/plex/desktopPlexClientIdentity.ts`
- `src/main/plex/auth/**`
- `src/main/plex/discovery/**`
- `src/main/plex/library/**`
- `src/main/persistence/desktopPersistenceStore.ts`
- `src/main/persistence/secureStorageCodec.ts`
- `src/renderer/plexRuntimeState.ts`
- `src/renderer/plexRuntimeActions.ts`
- `src/renderer/plexRuntimeDom.ts`
- `src/renderer/staticDom.ts`
- `src/renderer/domBindings.ts`
- `src/renderer/index.ts`
- `src/renderer/workflow.ts`
- `src/renderer/routeDom.ts`
- `src/renderer/navigation.ts`
- `src/renderer/desktopInput.ts`
- `src/renderer/styles.css`
- `src/renderer/styles/base.css`
- `src/renderer/styles/workflow-screens.css`
- `src/renderer/styles/responsive-accessibility.css`

### Desktop Tests In Scope

- `src/__tests__/main/plexAuth.test.ts`
- `src/__tests__/main/plexDiscovery.test.ts`
- `src/__tests__/main/plexLibrary.test.ts`
- `src/__tests__/main/plexRuntimeIpc.test.ts`
- `src/__tests__/integration/preloadContractVocabulary.test.ts`
- `src/__tests__/contracts/contracts.test.ts`
- `src/__tests__/renderer/plexRuntime.test.ts`
- `src/__tests__/renderer/workflow.test.ts`
- `src/__tests__/renderer/routeDom.test.ts`
- new focused parity tests under the existing `src/__tests__/**` structure when
  Unit 1 identifies missing coverage

### Upstream Source In Scope

Read-only upstream reference paths:

- `C:\Software\Lineup\src\modules\plex\auth/**`
- `C:\Software\Lineup\src\modules\plex\discovery/**`
- `C:\Software\Lineup\src\modules\plex\library/**`
- `C:\Software\Lineup\src\modules\plex\shared/**`
- `C:\Software\Lineup\src\core\server-selection/**`
- `C:\Software\Lineup\src\modules\ui\profile-select/**`
- `C:\Software\Lineup\src\modules\ui\server-select/**`
- `C:\Software\Lineup\src\modules\ui\channel-setup/**`
- `C:\Software\Lineup\src\core\initialization/**`
- `C:\Software\Lineup\src\core\channel-setup/**`
- `C:\Software\Lineup\src\App.ts`
- `C:\Software\Lineup\src\index.ts`
- `C:\Software\Lineup\src\styles\shell.onboarding.*.css`

The upstream repo is a read-only reference for this plan. Do not edit it.

### Plan And Evidence Files In Scope

- `docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md`
- `docs/plans/rd-22-upstream-parity-audit-matrix.md` for Unit 1 tracked audit
  output
- `docs/architecture/import-ledger.md` when copying/adapting upstream code
- ignored, redaction-safe run notes under
  `docs/runs/rd-22-live-plex-auth-discovery-library-runtime-ui/`

## Files Out Of Scope

- `docs/architecture/CURRENT_STATE.md`,
  `docs/roadmap/desktop-port-roadmap.md`,
  `docs/product/lineup-product-parity-matrix.md`, and
  `docs/development/windows-ui-proof-plan.md` until RD-22 proof and review
  pass. Do not add closeout claims there during audit or implementation.
- `src/domain/channel/**` except read-only evidence when upstream channel setup
  behavior informs future RD-23 handoff. RD-22 must not implement channel
  authoring.
- `src/domain/scheduler/**`
- `src/main/player/**`
- `src/contracts/player.ts`
- `src/main/plex/streamResolver.ts` except read-only reference for redaction and
  future playback boundaries. Playback is out of RD-22.
- native helper source, package scripts unrelated to existing verification,
  dependency manifests, lockfiles, signing/update/installer/public-release
  files, and CI configuration.
- tracked raw proof artifacts, screenshots, logs, support bundles, raw Plex
  payloads, local paths, endpoint URLs, connection details, tokens, headers,
  account/server/library/media names, or raw IPC frames.

## Planner Self-Check

1. Product/architecture/ownership decisions are resolved for the first unit:
   Unit 1 is audit-only and may not change product behavior.
2. Implementation decisions are intentionally not frozen before the audit.
   Later units must be approved by review after the matrix names exact gaps,
   files, and boundaries.
3. No file is frozen out of scope while relying on hidden behavior inside it;
   out-of-scope product owners are excluded because RD-22 should not require
   channel authoring, scheduler, playback, native helper, package, or release
   behavior.
4. Evidence path and Codanna fallback are recorded.
5. The work is assigned to repo-preferred owners: main owns Plex transport and
   secrets; renderer owns onboarding composition; preload/contracts stay narrow.
6. Tier 3 Architecture Health evidence and decomposition/avoidance policy are
   recorded below.
7. A fresh implementer should not need to invent security, IPC, playback,
   persistence, packaging, import, or verification policy.
8. Verification commands, expected outcomes, manual proof, and stop/replan
   triggers are explicit.

## Architecture Seam Decision Gate

The selected seam is a reviewed upstream-parity rebuild inside existing Desktop
owners:

- Main Plex runtime, auth, discovery, library, and live transport may be
  replaced or adapted to match upstream behavior, but main keeps custody of
  tokens, headers, endpoints, selected connection details, raw Plex payloads,
  credential persistence, selected-server persistence, retry policy, operation
  cancellation, and sanitized diagnostics.
- Renderer may be rebuilt to match upstream onboarding flow concepts, but it
  remains display-only and receives only renderer-safe summaries.
- Renderer runtime UI may display user-facing names and titles carried by
  renderer-safe summaries. Redaction restrictions apply to tracked proof, docs,
  tests, diagnostics, logs, raw support artifacts, and chat, not to normal
  local app display.
- Preload and contracts stay narrow; any bridge expansion requires a separate
  reviewed unit with contract tests and redaction tests.
- Upstream code may be copied/adapted only when the parity matrix records the
  source path, Desktop owner, adaptation reason, retained tests, and import
  ledger update requirement.
- Fake or placeholder surfaces must be deleted from reachable product routes
  once the corresponding real flow is implemented. Tests and smoke harnesses may
  keep fake fixtures when they are explicit, isolated, and not user-reachable.

Forbidden shortcuts:

- broad RPC bridge or arbitrary IPC channels
- renderer fetch to Plex or renderer-owned tokens/auth headers/URLs
- persisted raw connection URI, token, header, endpoint, or raw Plex payload
- compatibility wrappers or old upstream path shims
- fake controls layered beside real onboarding controls
- tests that only bless private helper shape without upstream behavior coverage
- live Windows proof used as the only evidence for a behavior that upstream
  already expresses in source/tests
- import-ledger omissions for copied/adapted upstream code

Stop and replan if a parity gap cannot be resolved without violating these
seams.

## Verification Commands

Verification classification: broader integration/manual proof required.

Plan and audit verification:

- `npm run verify:docs`: expected to pass active-plan structure and Tier 3
  checks.
- `npm run verify:redaction`: expected to pass without raw tokens, headers,
  URLs, connection details, local paths, private names, raw payloads, or raw
  proof.
- `git diff --check`: expected to report no whitespace errors.
- Unit 1 must add or update the tracked redaction-safe parity matrix at
  `docs/plans/rd-22-upstream-parity-audit-matrix.md`, then run
  `npm run verify:docs`, `npm run verify:redaction`, and `git diff --check`.

Implementation verification, exact commands to retain unless a reviewed unit
narrows or expands them:

- `npm run test:contracts -- --test-name-pattern "plex auth|plex discovery|plex library|plex runtime|Plex runtime"`:
  expected to pass focused Plex contracts and renderer flow coverage.
- `npm run test:contracts`: expected to pass all contract/renderer/main tests
  affected by the rebuild.
- `npm run build:electron`: expected to pass and produce a runnable local
  Electron build.
- `npm run verify`: expected to pass typecheck, architecture lint,
  maintainability, tests, docs, and redaction.
- `git diff --check`: expected to pass after all tracked edits.

Live Windows proof required after implementation review:

- Launch local Electron build on Windows.
- Exercise only RD-22: sign-in request/cancel/poll/claim, credential
  availability category, profile/Plex Home selection including protected PIN
  handling when available, server discovery/selection/restore, library section
  listing, browse, search, metadata summary opening, and naturally observed
  sanitized failures.
- Record only redaction-safe counts/categories under the ignored RD-22 run
  directory.
- Do not claim channel creation, scheduler guide runtime, playback, package
  signing/update/install/delete, public release readiness, platform expansion,
  or full upstream import parity.
- Run `npm run verify:docs`, `npm run verify:redaction`, and
  `git diff --check` after any tracked proof-summary edits.

## Acceptance Criteria

- A reviewed upstream parity matrix exists before implementation continues. It
  names every RD-22 upstream behavior area, Desktop equivalent, current gap,
  implementation decision, files, tests, dirty pre-audit patch disposition, and
  import-ledger obligation.
- Fake/debug setup controls are removed from the reachable RD-22 onboarding
  route and replaced by real onboarding flow surfaces.
- The reachable RD-22 setup path no longer contains fake setup summary text,
  draft channel controls, placeholder setup steps, smoke-only Plex debug
  controls, or standalone transport-operation buttons as the primary UX. Any
  remaining fake player/guide surfaces outside RD-22 are explicitly out of
  scope and must not be used to claim onboarding completion.
- Desktop auth behavior matches upstream semantics where applicable: PIN
  request shape, polling, cancellation, expiration/failure handling, account
  validation, Plex Home profile listing/switching, protected profile PIN, active
  profile token custody, and credential restore.
- Desktop discovery behavior matches upstream semantics where applicable:
  discovery request variants, JSON/XML resources handling, retry/rate-limit
  policy, connection parsing/sanitization, mixed-content priority, authenticated
  identity probing, server selection, selected-server restore, profile scoping,
  and health/failure classification.
- Desktop library behavior matches upstream semantics where applicable:
  library sections, browse/listing pagination, search, metadata parsing, empty
  states, parse/network/auth/rate-limit failure categories, and renderer-safe
  summaries.
- Renderer onboarding flow matches upstream product intent while preserving
  Desktop boundaries: sign-in, profile select, server select, library
  browsing/search/metadata, clear/back/cancel behavior, scroll/focus,
  keyboard/remote interaction, accessibility, and sanitized error states.
- Renderer/preload/main boundaries remain intact. Renderer does not receive raw
  tokens, auth headers, endpoint URLs, connection details, raw Plex payloads,
  local paths, native handles, or privileged storage/electron APIs.
- Import ledger is updated before or with any copied/adapted upstream source.
- `npm run verify`, `npm run build:electron`, `npm run verify:docs`,
  `npm run verify:redaction`, and `git diff --check` pass after implementation.
- Live redaction-safe Windows proof passes and is reviewed before RD-22 closeout
  claims are written.

## Replan Triggers

- Unit 1 parity audit finds that RD-22 cannot be rebuilt without changing
  package dependencies, package scripts, lockfiles, native helper, playback,
  signing/update/installer/public-release surfaces, channel authoring, or
  scheduler runtime.
- Upstream behavior requires renderer-held secrets, renderer Plex fetches, raw
  endpoint URLs, raw connection details, or renderer persistence.
- A needed bridge/contract change is broader than the existing typed Plex
  operation vocabulary.
- Live server discovery still fails after upstream-equivalent discovery request
  policy and authenticated probing are implemented.
- A production file crosses 500 lines or an allowlisted hotspot grows without a
  reviewed Architecture Health decision.
- Redaction verification flags raw proof, token/header/URL/connection leakage,
  private names, local paths, raw payloads, or raw IPC frames.
- The upstream repo cannot be used as a stable reference because required files
  are missing, materially changed, or unreviewed relative to the import-ledger
  source date.
- Unit 1 cannot classify the existing dirty live-debug patches without either
  reverting user work or committing unreviewed behavior.
- Reviewer finds material plan, boundary, security, parity, fake-surface,
  import-ledger, or verification gaps.
- User changes the product strategy, for example choosing a full reset over a
  bounded RD-22 parity rebuild.

## Rollback Notes

- Unit 1 audit changes should be rollbackable by reverting the plan/matrix
  update only; it must not change product source.
- Later implementation units must be separately rollbackable by owner:
  runtime/auth/discovery/library changes, renderer onboarding changes, and
  contract/preload changes should not be mixed unless a reviewed unit explains
  why atomicity is required.
- If implementation fails or live proof remains blocked, keep this plan active,
  keep RD-22 open, and do not promote closeout docs.
- Ignored run notes under
  `docs/runs/rd-22-live-plex-auth-discovery-library-runtime-ui/` may be deleted
  without affecting source.
- Do not roll back unrelated user changes or prior committed roadmap work unless
  explicitly requested.

## Commit Checkpoints

- Commit 1: `docs(plans): supersede RD-22 with upstream parity rebuild plan`
  after plan review and docs/redaction/diff checks.
- Commit 2: `docs(plans): add RD-22 upstream parity audit matrix` or similar
  after Unit 1 audit review.
- Later commits should be one focused implementation unit each, for example:
  `fix(plex): restore upstream discovery request policy`,
  `fix(plex): align auth and profile switching parity`,
  `feat(renderer): replace fake Plex setup with onboarding flow`.
- Keep plan/audit, runtime, renderer, and proof-summary commits separate when
  practical.
- Do not stage unrelated local changes.
- Do not commit the current pre-audit live-debug patches until Unit 1 classifies
  them in the tracked matrix and review accepts their disposition.

## Architecture Health

Current large-file guardrail evidence:

- `src/preload/index.cts`: allowlisted at 2045 lines. Avoid growth unless a
  later reviewed bridge unit proves it is necessary. Any growth requires
  contract, preload, redaction, and Architecture Health review.
- `src/main/plex/streamResolver.ts`: allowlisted over 500 lines and out of
  RD-22 implementation scope except read-only evidence.
- Current Desktop Plex runtime files near the threshold:
  `src/main/plex/desktopPlexRuntime.ts` about 476 lines and
  `src/main/plex/desktopPlexRuntimeSupport.ts` about 457 lines. Do not grow
  either past 500 lines without decomposing runtime support or recording a
  reviewed temporary allowlist decision.
- Current renderer files near the threshold:
  `src/renderer/plexRuntimeActions.ts` about 454 lines,
  `src/renderer/index.ts` about 403 lines,
  `src/renderer/styles/workflow-screens.css` about 398 lines,
  `src/renderer/plexRuntimeDom.ts` about 365 lines, and
  `src/renderer/plexRuntimeState.ts` about 363 lines. The onboarding rebuild
  should decompose renderer setup UI rather than inflate these into broad
  controllers.

Decision: decompose runtime and renderer hotspots or avoid growing them; do not add
a temporary allowlist row unless a later reviewed implementation unit proves
decomposition is more risky than a small, bounded owner increase.

- Unit 1 is audit-only and should not grow production source.
- Runtime implementation units should extract focused helpers only when they map
  to real upstream behavior boundaries, such as discovery request policy,
  response normalization, server probe policy, or library transport policy.
- Renderer implementation units should split onboarding screen/view-model
  ownership if necessary instead of growing `plexRuntimeDom.ts`,
  `plexRuntimeActions.ts`, or `index.ts` into generic setup controllers.
- Do not raise file-shape guardrails to pre-authorize growth. Run
  `npm run verify:maintainability` directly or through `npm run verify` after
  source changes.

## Execution Units

### Unit 1: Upstream Parity Audit Matrix

Type: docs/source-audit only.

Files in scope:

- this plan
- `docs/plans/rd-22-upstream-parity-audit-matrix.md`
- ignored redaction-safe run notes under the RD-22 run directory
- read-only Desktop and upstream files listed above

Required output:

- A matrix covering auth, profile/Plex Home, startup/restore, discovery request
  policy, server probing, selected-server persistence/restore, library
  sections, browse, search, metadata, renderer onboarding screens, fake-surface
  removal, tests, and proof.
- Each row must include upstream files/tests, Desktop files/tests, behavior
  expectation, current gap, decision (`copy`, `adapt`, `rewrite`, `remove`,
  `keep`), owner, verification, dirty pre-audit patch disposition,
  import-ledger action, and stop/replan notes.
- A point-of-contention section naming risky decisions for the user to review.

Verification:

- `npm run verify:docs`
- `npm run verify:redaction`
- `git diff --check`

Review:

- Send Unit 1 matrix to read-only adversarial review.
- Do not implement product changes until material review findings are resolved.

### Unit 2: Main Plex Runtime Parity Rebuild

Type: implementation after Unit 1 review only.

Likely scope, subject to Unit 1:

- live transport discovery request variants and response normalization
- auth/profile parser and service parity
- Plex Home switch behavior
- server discovery/probe/selection/restore parity
- library transport and parser parity
- runtime failure vocabulary and state transitions
- tests against upstream fixtures and redaction contracts

Verification:

- focused Plex main/runtime tests named by Unit 1
- `npm run test:contracts`
- `npm run verify:redaction`
- `npm run build:electron`
- `npm run verify`

### Unit 3: Contract And Preload Adjustments If Required

Type: optional implementation after Unit 1 review only.

Trigger:

- Unit 1 proves the existing `src/contracts/plex.ts` and `src/preload/index.cts`
  vocabulary cannot represent upstream-equivalent behavior while staying
  renderer-safe.

Likely scope, subject to Unit 1:

- add or adjust narrow Plex operation/result vocabulary
- update preload validation for exact new shapes only
- update contract, preload, IPC vocabulary, and redaction tests

Verification:

- contract and preload vocabulary tests named by Unit 1
- `npm run test:contracts -- --test-name-pattern "plex runtime|preload|contract"`
- `npm run verify:redaction`
- `npm run verify`

### Unit 4: Renderer Onboarding Flow Replacement

Type: implementation after Unit 1 review and after needed Unit 2 runtime seams
are stable.

Likely scope, subject to Unit 1:

- remove reachable fake/debug setup panel controls
- implement real onboarding flow screens or sections for sign-in, profile,
  server, library, search, and metadata
- keyboard/remote focus, scroll, clear/back/cancel, loading/empty/error states
- tests proving fake-surface retirement and setup flow behavior

Verification:

- focused renderer onboarding tests
- route/workflow/focus tests
- visual/manual Windows layout proof
- `npm run verify`

### Unit 5: Live Windows Proof And Closeout Review

Type: proof/review/docs after Units 1-4 pass.

Scope:

- live RD-22 proof only
- redaction-safe ignored proof notes
- docs/redaction/diff checks
- implementation and proof review
- only then closeout docs if approved

## Upstream Parity Areas To Audit

Minimum Unit 1 rows:

- Auth identity/client identifier
- PIN request shape and claim guidance
- PIN polling/cancel/expiry/failure
- account validation and profile parsing
- credential restore/corruption/unavailable states
- Plex Home users endpoint and parser
- protected Plex Home profile switch
- active profile/account token distinction
- startup restore policy and route decisions
- discovery fetch variants
- discovery response JSON/XML normalization
- discovery retry/rate-limit/server error policy
- resource parser and connection sanitizer
- mixed-content connection priority
- authenticated identity probe
- selected server persistence and profile scoping
- upstream core server-selection runtime and persistence controller behavior
- selected server restore after restart
- server health/failure classification
- library sections transport and parser
- library item browse pagination/sort
- library search transport and parser
- metadata summary transport and parser
- sanitized runtime error vocabulary
- renderer auth/profile/server/library onboarding flow
- focus/back/scroll/text-input behavior
- fake/debug surface retirement
- upstream tests retained/adapted into Desktop tests
- Windows live proof acceptance

## Points Of Contention For User Review

- Scope size: a faithful rebuild is larger than a patch. The safe path is still
  bounded by units, but it will delay RD-22 closeout.
- Upstream exactness vs Desktop boundaries: exact file sharing is unlikely
  because upstream uses browser/webOS storage, routing, and UI assumptions.
  The plan favors behavior parity with Desktop-owned modules over path parity.
- Selected-server persistence: upstream stores server id and URI-like state by
  user/profile; Desktop intentionally avoids persisting raw connection URIs. The
  audit must decide whether server-id-only restore is enough or whether Desktop
  needs a safe additional persisted summary without raw connection details.
- Discovery request policy: upstream has fetch variants, XML parsing, retry, and
  response policy that Desktop's live bridge does not fully carry today. This is
  a likely source of the current server failure and should be audited before any
  further live patches.
- Dirty baseline: the current worktree contains live-debug patches made before
  this rebuild plan. The audit must treat them as candidate changes, not trusted
  baseline behavior, and decide which to retain, replace, drop, or rework.
- Runtime privacy: renderer-safe names and titles are allowed in the local app
  UI because users need to select real profiles, servers, libraries, and media.
  The strict redaction ban applies to proof, docs, logs, diagnostics, tests, and
  chat.
- Upstream target: record the current upstream branch and HEAD at audit start,
  audit that exact checkout, and note divergences from the older import-ledger
  commit.
- Renderer onboarding shape: upstream uses separate auth/profile/server/channel
  screens, while Desktop currently has a left rail and route shell. The plan
  should copy the product flow and interaction semantics, not necessarily the
  exact upstream DOM structure.
- Fake-surface removal: removing fake setup scaffolding may expose that adjacent
  fake player/guide routes are still placeholders. RD-22 should remove fake
  garbage from the Plex onboarding path only; broader fake player/guide
  retirement belongs to later roadmap items unless the user explicitly expands
  scope.
- Live proof vs automated proof: Windows live proof is mandatory but not enough.
  The rebuild must add parity tests so we are not debugging every upstream
  behavior through the real Plex account.

MODEL_SUGGESTION
PLANNER: gpt-5 high reasoning
IMPLEMENTER: gpt-5 high reasoning
REVIEWER: gpt-5 high reasoning
WHY: Tier 3 rebuild spans upstream parity, Plex auth/discovery/library, renderer onboarding, persistence boundaries, redaction policy, and live Windows proof.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop
TASK: Complete RD-22 Upstream-Parity Plex Onboarding And Runtime Rebuild
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md
ARTIFACT: active plan awaiting or incorporating plan review
FILES:
- docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md
- docs/architecture/import-ledger.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/file-shape-guardrails.md
- docs/development/windows-ui-proof-plan.md
- docs/product/lineup-product-parity-matrix.md
- src/main/plex/livePlexTransport.ts
- src/main/plex/desktopPlexRuntime.ts
- src/main/plex/auth/**
- src/main/plex/discovery/**
- src/main/plex/library/**
- src/renderer/plexRuntimeState.ts
- src/renderer/plexRuntimeActions.ts
- src/renderer/plexRuntimeDom.ts
- src/renderer/staticDom.ts
- src/renderer/index.ts
- src/renderer/styles/**
- C:\Software\Lineup\src\modules\plex\auth/**
- C:\Software\Lineup\src\modules\plex\discovery/**
- C:\Software\Lineup\src\modules\plex\library/**
- C:\Software\Lineup\src\core\server-selection/**
- C:\Software\Lineup\src\modules\ui\profile-select/**
- C:\Software\Lineup\src\modules\ui\server-select/**
- C:\Software\Lineup\src\modules\ui\channel-setup/**
BLOCKERS: RD-22 live Windows proof is failing at server reachability; do not continue one-off patches or closeout until Unit 1 upstream parity audit and review pass.
MESSAGE:
Start with Unit 1 only: create the tracked RD-22 upstream parity audit matrix at `docs/plans/rd-22-upstream-parity-audit-matrix.md`, comparing current upstream Lineup Plex auth/profile/discovery/core server-selection/library/onboarding behavior against Desktop source and tests. Do not implement product changes in Unit 1. Treat the current dirty RD-22 live-debug patches as untrusted pre-audit candidate changes and classify each as retain, replace, drop, or rework before any commit. Record gaps, decisions, owners, tests, import-ledger obligations, and points of contention. Run `npm run verify:docs`, `npm run verify:redaction`, and `git diff --check`, then send the matrix for read-only adversarial review. After review findings are resolved, implement reviewed units in order: main Plex runtime parity, optional contract/preload adjustments if needed, renderer onboarding fake-surface replacement, then live Windows proof and closeout review. Keep renderer unprivileged, main-owned secrets/transport/connection custody intact, and tracked evidence redaction-safe.
