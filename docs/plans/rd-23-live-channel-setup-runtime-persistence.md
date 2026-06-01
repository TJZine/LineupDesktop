# RD-23 Live Channel Setup And Runtime Persistence

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3

## Goal

Complete the RD-23 roadmap item through the Tier 3 feature-quality loop:
turn the RD-22B live Plex onboarding/library state into real persisted Desktop
channels, replace or isolate reachable fake channel setup/settings controls,
and prove restart recovery on Windows without leaking private Plex, path, or
credential material.

The finished slice must provide the real MVP setup journey:

- resume from live Plex sign-in/profile/server/library state established by
  RD-22B
- choose renderer-safe library-backed setup inputs
- review validation, impact, destructive/replace confirmation, and failure
  states in the upstream-shaped channel setup/settings body
- commit channels through the existing channel domain and main-owned channel
  persistence owners
- recover persisted channels and setup status after app restart
- show Settings recovery/status for the persisted channel setup state

## Non-Goals

- No RD-24 scheduler-backed guide/player runtime, guide schedule refresh,
  current-channel playback route state, OSD, now-playing, mini-guide, channel
  badge, or channel-switch runtime.
- No RD-25 production native playback, media load, direct play/direct stream/
  transcode handoff, helper lifecycle changes, or playback control behavior.
- No RD-26 runtime media options, subtitle/audio/HDR mutation, or playback
  quality settings.
- No backup/restore, credential migration, package/release behavior, signing,
  updater, installer, CI, or public readiness change.
- No runtime dependency change. A reviewed development-only preload bundler and
  lockfile/script update is allowed only for the mandatory sandbox-compatible
  preload split described in Architecture Health; if that scope expands beyond
  bundling the preload entrypoint into one CommonJS file, stop and replan.
- No broad persistence IPC, arbitrary preload RPC, renderer-owned storage,
  browser storage, raw Electron/Node access, compatibility barrels, old
  upstream path shims, or fallback API variants.
- No renderer custody of credentials, auth headers, tokenized URLs, selected
  connections, raw Plex payloads, raw channel persistence files, app paths,
  filesystem paths, diagnostics internals, process ids, native handles, or raw
  private proof.
- No tracked screenshots, raw logs, support-bundle contents, account/server/
  library/media names, endpoint URLs, local paths, tokens, headers, payloads,
  native handles, or private Windows proof.

## Parent Architecture Alignment

Chosen route: Tier 3 feature/design through
`lineup-desktop-feature-quality-loop`: plan, read-only plan review, one
bounded implementation unit at a time, focused verification, read-only
implementation review, Windows proof, closeout, and durable memory updates.

Chosen seam: introduce a main-owned channel runtime/composition seam that
adapts RD-22B live Plex library summaries into the existing pure channel
domain and separate main-owned channel persistence store. Preload exposes only
a narrow validated channel setup namespace. Renderer owns the setup/settings
presentation, focus, text entry, transient draft choices, and renderer-safe
operation state only.

Owner responsibilities:

- Electron main owns channel manager composition, app-data channel persistence
  path resolution, selected profile/server/library access through existing
  Plex runtime custody, channel commit/replace/rerun operations, sanitized
  channel setup snapshots, and shutdown cleanup.
- Domain channel owners remain pure. They may validate/create/update persisted
  `ChannelConfig` and resolve content through injected ports, but they must not
  import Electron, Node, preload, renderer, live network, raw Plex payloads, or
  browser globals.
- Preload validates channel requests and results. It must remain a narrow typed
  bridge and must not expose raw `ipcRenderer`, arbitrary channel names,
  filesystem access, app paths, or privileged payloads.
- Renderer binds safe setup/settings state into the existing RD-22A/RD-22B
  body and removes or isolates fake draft channel controls from reachable
  product routes once the real setup path owns them.
- Contracts own renderer-safe channel setup, channel summary, persistence
  status, validation, operation, and error vocabulary only.

## Required Reading

Fresh-session implementers and reviewers must read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-quality-loop.md`
4. `docs/agentic/session-prompts/feature-plan.md`
5. `docs/agentic/session-prompts/feature-review.md`
6. `docs/agentic/plan-authoring-standard.md`
7. `docs/architecture/CURRENT_STATE.md`
8. `docs/architecture/file-shape-guardrails.md`
9. `docs/architecture/security-and-secret-flow.md`
10. `docs/architecture/import-ledger.md`
11. `docs/roadmap/desktop-port-roadmap.md`
12. `docs/architecture/renderer-architecture.md`
13. `docs/product/lineup-product-parity-matrix.md`
14. `docs/development/windows-ui-proof-plan.md`
15. `docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md`
16. `docs/plans/rd-22a-upstream-ui-body-parity-matrix.md`
17. This plan.

Freshness gate: before product source edits, rerun `git status --short
--branch`, inspect this plan against the current roadmap/current-state docs,
and refresh direct `rg` evidence for the files in scope. If Desktop source,
upstream source evidence, file-shape guardrails, or RD-23 roadmap scope changed
materially after this plan was written, update and re-review the plan before
editing product source.

## Required Skills

- `lineup-desktop-feature-quality-loop`: required because RD-23 crosses live
  Plex state, channel domain, main persistence, preload, renderer UI, redaction,
  and Windows proof.
- `execution-plan-authoring`: freezes scope, seams, verification, rollback, and
  replan triggers for fresh sessions.
- `architecture-boundaries`: applies to contracts, IPC, preload, main
  composition, renderer ownership, and module/file-shape decisions.
- `persistence-boundaries`: applies to app-data channel storage, restart
  recovery, corruption/unavailable states, and the no-renderer-storage rule.
- `plex-integration-boundaries`: applies to using RD-22B live Plex library,
  profile, and server state without exposing tokens, raw payloads, connection
  details, or transport policy.
- `ui-composition-patterns`: applies to setup/settings hierarchy, validation,
  destructive states, focus/back/text-entry/scroll behavior, and fake-route
  retirement.
- `verification-strategy`: required because public-seam automated proof must be
  paired with redaction-safe Windows restart/live setup proof.
- `review-request`: required for read-only plan and implementation reviews.
- `closeout-verification`: required before calling RD-23 complete, staging,
  committing, or handing off.

## Evidence And Discovery

- `semantic_search_with_context`: Codanna `get_index_info` was observed with
  `0 symbols`, `0 files`, and `0 embeddings`; semantic code discovery is not
  useful for this plan.
- `semantic_search_docs` or repo-doc search: same Codanna fallback. Required
  docs were read directly.
- impact analysis: not run because Codanna has no indexed graph. Direct reads
  and `rg` are the recorded fallback.
- direct reads / `rg`: read the workflow runbook, feature-quality-loop
  launcher, feature-plan launcher, plan standard, current-state architecture,
  file-shape guardrails, security/secret-flow, roadmap RD-23 section, renderer
  architecture, product parity matrix, Windows proof plan, import ledger,
  existing RD-22/RD-22A plans, `package.json`, contracts, channel domain,
  channel persistence adapter, main Plex IPC/composition/preload bridge, and
  renderer setup/settings/focus/route files.
- upstream source: upstream Lineup was observed at commit
  `613b1c516c7c9e37f9c18ea3e92c474013472b11` on `code-health`. Direct `rg`
  and file listing covered upstream `src/core/channel-setup/**`,
  `src/modules/ui/channel-setup/**`, `src/modules/ui/settings/**`, and
  `src/modules/settings/**`.
- existing Desktop evidence: `src/domain/channel/**` already owns pure channel
  authoring, replacement state, manager mutation/persistence coordination,
  repository normalization, content resolution, and stored-data codecs.
  `src/main/persistence/desktopChannelPersistenceStore.ts` already owns a
  separate versioned temp-file-backed channel persistence adapter behind an
  injected path. RD-22B live Plex runtime already provides renderer-safe
  profile/server/library/media summaries through main/preload/renderer, but it
  intentionally did not create channels or persist channel setup.
- current fake setup evidence: direct `rg` found reachable renderer strings and
  bindings for `channel-setup-fixture`, local-only settings copy, draft channel
  lists, setup validation, and preview-only state in `src/renderer/staticDom.ts`,
  `src/renderer/settingsSetup.ts`, `src/renderer/workflow.ts`, and
  `src/renderer/routeDom.ts`.
- import-ledger obligation: prior RD-11 and RD-22A/RD-22B ledger rows cover
  already-imported domain/UI/runtime source. Any new copied/adapted upstream
  channel setup, settings, setup workflow, settings store, CSS, copy, or test
  source for RD-23 needs a new or amended import-ledger row before or in the
  same change.
- official docs: Electron sandbox and preload documentation checked on
  2026-05-30 for the preload split decision. Sandboxed preload has only a
  limited polyfilled `require`, cannot use sibling CommonJS modules as a
  runtime split, and needs a bundled single-file preload when preload code is
  split. If implementation proposes a different Electron loading model, stop
  and add fresh official-doc evidence before plan review resumes.

## Impact Snapshot

Expected blast radius is cross-boundary but bounded to channel setup and
runtime persistence:

- New or changed public contract vocabulary for renderer-safe channel setup,
  channel summaries, commit/replace/rerun operations, validation messages,
  persistence status, and sanitized errors.
- New or changed main-owned channel runtime/composition/IPC owners that combine
  existing channel domain, existing channel persistence adapter, and existing
  RD-22B live Plex library state.
- Narrow preload exposure for channel setup operations. Preload file shape is a
  known hard-overage risk; Unit 2 must implement the Architecture Health
  preload bundling decision before adding the channel namespace.
- Renderer setup/settings owners change from fake draft controls to real
  renderer-safe setup, review, commit, persisted recovery, and failure states.
- Focused tests must change for contract/preload/main/domain/renderer seams.
- `docs/architecture/import-ledger.md` changes before or with any new upstream
  copied/adapted source.
- `package.json`, `package-lock.json`, and one focused build tool may change
  only for the mandatory development-only preload bundling step described in
  Architecture Health. No runtime package, release, native-helper, installer,
  signing, update, or CI behavior is approved.
- `docs/architecture/CURRENT_STATE.md`,
  `docs/roadmap/desktop-port-roadmap.md`, and the product parity/proof docs
  change only at RD-23 closeout after observed implementation, verification,
  Windows proof, and clean review.
- No runtime dependency, native-helper, playback, signing, installer, release,
  or CI change is expected or approved.

The implementation units must be sequential. Parallel work is not approved
because contracts/preload/main/renderer setup and Windows proof all depend on
the same public channel setup seam.

## Architecture Health

Tier 3 file-shape evidence, refreshed in this workspace on 2026-05-30:

- Controller-observed `git status --short --branch`:
  `## initial-build...origin/initial-build [ahead 3]` and
  `?? docs/plans/rd-23-live-channel-setup-runtime-persistence.md`. The RD-23
  plan itself is untracked, so do not claim a clean or unmodified worktree.
- Direct production line-count sweep found these `src/**` non-test files above
  500 lines: `src/preload/index.cts` 2116,
  `src/main/player/desktopPlayerAdapter.ts` 1225,
  `src/domain/channel/channelManager.ts` 1022,
  `src/domain/channel/channelRepository.ts` 770,
  `src/main/player/plexPlaybackRuntime.ts` 751,
  `src/contracts/player.ts` 703,
  `src/main/plex/desktopPlexRuntime.ts` 664,
  `src/main/plex/streamResolver.ts` 660,
  `src/main/persistence/desktopPersistenceStore.ts` 625,
  `src/main/player/streamPolicy/desktopStreamPolicy.ts` 624,
  `src/contracts/diagnostics.ts` 553, and
  `src/domain/channel/channelAuthoringService.ts` 521.
- `docs/architecture/file-shape-guardrails.md` currently allowlists these
  production over-threshold files. Do not raise baselines as part of RD-23
  unless the same reviewed implementation change proves decomposition is not
  the safer move.

Affected owner hotspots and decisions:

- `src/preload/index.cts` is a hard-overage file and its allowlist trigger says
  reviewed bundling or another reviewed split is required before any later
  bridge namespace grows it. RD-23 needs a channel namespace, so Unit 2 must
  introduce a bundled preload split before adding channel bridge behavior.
  Because the shell uses `sandbox: true`, `index.cts` must not runtime-require
  a sibling preload module. The approved approach is:
  - add `src/preload/channelBridgeGuards.cts` as the source owner for RD-23
    channel bridge request/result guard vocabulary, sanitized channel setup
    result construction, and channel-specific forbidden-field checks
  - keep the single Electron value binding and the single
    `contextBridge.exposeInMainWorld('lineupDesktop', lineupDesktop)` call in
    `src/preload/index.cts`
  - have `src/preload/index.cts` statically import/use only the channel bridge
    factory and guard functions it needs from `channelBridgeGuards.cts`; it may
    add the `lineupDesktop.channelSetup` namespace wiring, approved channel IPC
    constants, and listener/invoke calls, but not duplicate moved vocabulary
  - add a reviewed preload bundle step to the current Electron build so the
    distributed `dist/preload/index.cjs` is one CommonJS file with local
    preload modules bundled and only `require('electron')` left external; main
    continues loading `dist/preload/index.cjs`
  - use a focused development-only bundler dependency such as `esbuild` only
    for this preload bundle, recording package/lockfile impact in Unit 2; no
    runtime dependency, sandbox disablement, ESM preload, broad webpack-style
    app build, or package/release behavior is approved
  - update `src/__tests__/integration/preloadContractVocabulary.test.ts` to
    parse both preload source files, assert moved channel guard vocabulary
    matches the channel contract constants, reject Electron value imports or
    Electron requires outside `index.cts`, assert the bundled preload output has
    no local `require('./...')` preload-module dependency, and continue proving
    one `lineupDesktop` exposure plus approved `ipcRenderer` methods/channels
  Stop and replan if the bundle cannot be proven under `sandbox: true`, if the
  emitted preload still depends on sibling runtime modules, if channel guards
  must remain in `index.cts`, or if the bundling scope requires disabling
  sandbox/context isolation, adding broad build infrastructure, changing main's
  preload path contract, or weakening bridge vocabulary tests.
- `src/domain/channel/channelManager.ts` is a hard-overage file. RD-23 must
  consume existing manager methods where possible. If live setup needs new
  mutation/persistence behavior inside this file, split mutation queue/current
  channel/persistence coordination first or stop for reviewed allowlist change.
- `src/domain/channel/channelRepository.ts` is allowlisted. RD-23 should avoid
  repository growth; if persisted channel editing expands normalization/cache
  behavior, split cache/source resolution from import normalization first.
- `src/main/plex/desktopPlexRuntime.ts` is allowlisted. RD-23 may read existing
  library/profile/server state through a focused main-owned adapter, but must
  not add a new Plex operation family or broaden live browsing beyond RD-22B.
- `src/main/persistence/desktopPersistenceStore.ts` is allowlisted and should
  not receive a new channel/settings state family. Channel state belongs in the
  separate channel persistence file/owner.
- Desktop player adapter, Plex playback runtime, player contract, diagnostics
  contract, stream resolver, and stream policy oversized files are out of scope
  and must not grow for RD-23.

Decision: avoid growth in existing hard-overage files by creating focused
RD-23 channel runtime, channel IPC/composition, channel contract, preload guard
bundled split, and renderer channel setup binding owners; decompose channel
manager, repository, or preload ownership before adding new behavior that would
exceed reviewed guardrails. No temporary allowlist increase is approved by this
plan. Run `npm run verify:maintainability` after any production source-shape
change or preload build-shape change and before implementation closeout.

## Files In Scope

Plan/review/control surfaces:

- `docs/plans/rd-23-live-channel-setup-runtime-persistence.md`
- `docs/architecture/import-ledger.md` only for copied/adapted upstream source
- `package.json`, `package-lock.json`, and a focused preload bundle tool only
  for the mandatory sandbox-compatible preload split
- `docs/architecture/CURRENT_STATE.md` only during RD-23 closeout
- `docs/roadmap/desktop-port-roadmap.md` only during RD-23 closeout
- `docs/product/lineup-product-parity-matrix.md` only during RD-23 closeout if
  observed proof changes RD-23 classifications
- `docs/development/windows-ui-proof-plan.md` only if proof rules need a
  reviewed RD-23-specific clarification

Source implementation scope after clean read-only plan review:

- `src/contracts/channel.ts`
- `src/contracts/ipc.ts`
- `src/contracts/shell.ts`
- `src/preload/index.cts`
- `src/preload/channelBridgeGuards.cts`
- `src/main/index.ts`
- `src/main/channel/channelRuntime.ts`
- `src/main/channel/channelIpc.ts`
- `src/main/channel/channelComposition.ts`
- `src/main/persistence/appDataPaths.ts`
- `src/main/persistence/desktopChannelPersistenceStore.ts`
- `src/domain/channel/channelAuthoringService.ts`
- `src/domain/channel/channelManager.ts`
- `src/domain/channel/channelRepository.ts`
- `src/domain/channel/channelPersistenceCoordinator.ts`
- `src/domain/channel/channelPersistenceSaveQueue.ts`
- `src/domain/channel/channelPersistenceStore.ts`
- `src/domain/channel/storedChannelDataCodec.ts`
- `src/domain/channel/types.ts`
- `src/domain/channel/interfaces.ts`
- `src/domain/channel/index.ts`
- `src/main/plex/desktopPlexRuntime.ts`
- `src/main/plex/desktopPlexRuntimeSupport.ts`
- `src/main/plex/library/**`
- `src/renderer/channelRuntimeState.ts`
- `src/renderer/channelRuntimeActions.ts`
- `src/renderer/channelRuntimeDom.ts`
- `src/renderer/channelRuntimeRows.ts`
- `src/renderer/settingsSetup.ts`
- `src/renderer/workflow.ts`
- `src/renderer/routeDom.ts`
- `src/renderer/staticDom.ts`
- `src/renderer/domBindings.ts`
- `src/renderer/focusDom.ts`
- `src/renderer/navigation.ts`
- `src/renderer/desktopInput.ts`
- `src/renderer/plexRuntimeState.ts`
- `src/renderer/plexRuntimeActions.ts`
- `src/renderer/plexRuntimeDom.ts`
- `src/renderer/plexRuntimeRows.ts`
- `src/renderer/styles/workflow-screens.css`
- `src/renderer/styles/plex-onboarding.css`
- `src/renderer/styles/plex-onboarding-cards.css`
- focused tests under `src/__tests__/contracts/**`,
  `src/__tests__/integration/preloadContractVocabulary.test.ts`,
  `src/__tests__/domain/channelDomain.test.ts`,
  `src/__tests__/domain/channelPersistence.test.ts`,
  `src/__tests__/main/channelPersistenceAdapter.test.ts`,
  `src/__tests__/main/channelRuntimeIpc.test.ts`, and
  `src/__tests__/renderer/**`

Read-only upstream source may be inspected under relative upstream paths:
`src/core/channel-setup/**`, `src/modules/ui/channel-setup/**`,
`src/modules/ui/settings/**`, and `src/modules/settings/**`. Copy/adaptation
requires the import-ledger obligation above.

## Files Out Of Scope

- `src/main/player/**`
- `src/main/plex/streamResolver.ts`
- `src/main/player/streamPolicy/**`
- `src/contracts/player.ts`
- `src/domain/scheduler/**` except read-only context for RD-24 handoff
- `src/native/**`
- `tools/libmpv-spike/**`
- `tools/mpv-poc/**`
- `tools/package-windows-internal.mjs`
- `tools/verify-windows-internal-package.mjs`
- unrelated package manifests, lockfiles, dependency configuration, and build
  configuration; the only approved exception is the Unit 2 change to
  `package.json`, `package-lock.json`, and one focused development-only preload
  bundler/build script/config needed for the mandatory sandbox-compatible
  preload bundle. Signing/update/installer/release docs and CI configuration
  remain out of scope
- production native helper files or playback package assets
- RD-24 guide/player runtime, RD-25 playback, RD-26 media option runtime, and
  RD-27/RD-28 proof/package owners
- tracked raw proof artifacts, screenshots, logs, support-bundle contents,
  account/server/library/media names, local paths, endpoint URLs, connection
  details, auth headers, tokens, raw Plex payloads, raw persistence files,
  process ids, native handles, and private diagnostic output

## Planner Self-Check

1. No product, ownership, dependency, import, or verification decision is left
   unresolved for plan review. The only approved seam is main-owned channel
   runtime/persistence with narrow bundled preload and renderer-safe UI.
2. Adjacent contract/preload/main/domain/renderer files that may need changes
   are in scope; out-of-scope files are not hidden dependencies for RD-23.
3. The plan does not rely on RD-24 scheduler guide/player runtime, RD-25
   playback, RD-26 media options, package behavior, or renderer-owned storage.
4. Evidence records Codanna fallback plus direct doc/source/upstream reads.
5. Work is assigned to repo-preferred owners and avoids growing hard-overage
   files without decomposition or reviewed allowlist action.
6. Tier 3 Architecture Health includes current line-count evidence and
   decisions for affected hotspots.
7. A fresh implementer should not need to invent security, IPC, Plex,
   persistence, import-ledger, UI, Windows proof, rollback, or verification
   policy.
8. Exact verification commands, expected outcomes, Windows proof categories,
   acceptance criteria, and stop/replan triggers are recorded.

## Architecture Seam Decision Gate

The selected architecture seam is:

`Renderer channel setup/settings UI -> narrow preload channel bridge -> main channel runtime -> pure channel domain + main channel persistence + existing main Plex library custody`.

Required decisions before implementation starts:

- Channel setup public shape must be a renderer-safe contract. It may include
  channel ids, channel numbers, names, source summaries, setup status,
  operation ids, validation messages, and sanitized counts. It must not include
  raw Plex payloads, token-bearing URLs, connection URIs, file paths, app paths,
  raw persisted JSON, credentials, headers, native handles, or diagnostics
  internals.
- Channel persistence uses the existing separate channel persistence adapter
  and a main-owned app-data path. It must not be stored in renderer state,
  browser storage, the RD-09 credential/selected-server store, or tracked proof.
- No migration is expected beyond absent or corrupt channel-persistence-file
  recovery. If implementation needs migration from fake renderer state,
  selected-server state, browser storage, or another persisted schema, stop and
  replan.
- Preload split decision: RD-23 channel setup bridge code must be split at
  source level and bundled into a single sandbox-loadable CommonJS preload
  artifact. Runtime local CommonJS module loading from preload is forbidden.
  `src/preload/index.cts` remains the only file allowed to require Electron,
  access `ipcRenderer`, and expose `lineupDesktop`; the split guard module owns
  channel-specific validators and sanitized result guards only.
- Channel setup may use existing RD-22B live library summaries and main-owned
  library access. It must not broaden live Plex browsing, add raw media files,
  expose artwork URLs, or claim scheduler/playback readiness.
- Replacing channels is allowed only with an explicit renderer-safe review and
  confirmation state. Destructive behavior must be covered by tests and
  Windows proof.
- Fake setup summaries and draft controls must be removed from the reachable
  product route or isolated behind an explicit test/dev-only fixture before
  RD-23 closeout.

Forbidden shortcuts: broad RPC, arbitrary channel strings, renderer storage,
raw Plex or persistence payloads, compatibility wrappers, upstream path mirrors,
fallback API variants, preload namespace growth without the mandatory bundled
split, runtime sibling preload requires, sandbox/context-isolation disablement,
and hidden package/dependency/native-helper changes.

Stop and replan if discovery invalidates this seam.

## Verification Commands

Verification classification: `broader integration/manual proof required`.

Plan-only checkpoint:

- `npm run verify:docs` should pass for this active tracked plan.
- `git diff --check -- docs/plans/rd-23-live-channel-setup-runtime-persistence.md`
  should pass.

Implementation units must run focused proof for touched owners, then close with
the full source proof:

- `npm run typecheck` should pass after contract, preload, main, domain, or
  renderer type changes.
- `npm run build:electron` should pass after the mandatory preload bundle step,
  and `dist/preload/index.cjs` should be a single sandbox-loadable CommonJS
  artifact with no local preload-module `require('./...')` dependency.
- `npm run test:contracts -- --test-name-pattern "channel runtime|channel persistence|channel domain|preload channel|contract|plex runtime"`
  should pass when channel runtime, persistence, contract, preload, or Plex
  adapter behavior is touched.
- `node --import tsx --test src/__tests__/main/channelRuntimeIpc.test.ts src/__tests__/main/channelPersistenceAdapter.test.ts src/__tests__/domain/channelDomain.test.ts src/__tests__/domain/channelPersistence.test.ts`
  should pass after main channel runtime, channel persistence, or channel
  domain changes.
- `node --import tsx --test src/__tests__/renderer/workflow.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/plexRuntime.test.ts`
  should pass after setup/settings renderer, focus, route, or RD-22B library
  binding changes.
- `npm run verify:redaction` should pass after any contract, Plex, persistence,
  diagnostics, test, docs, or proof-surface change.
- `npm run verify:maintainability` should pass after any production source
  shape change or file-shape guardrail change.
- `npm run smoke:electron` should pass before implementation closeout because
  the preload/main channel bridge is composed during shell startup.
- `npm run verify` should pass before source implementation closeout unless a
  reviewed replan names a narrower verified surface with justification.
- `npm run verify:docs` should pass after closeout memory updates.
- `git diff --check` should pass before commit.

Expected automated outcomes:

- Contract/preload tests reject forbidden fields, malformed requests/results,
  invalid operation ids, invalid channel ids/numbers, raw persistence fields,
  raw Plex fields, and unsafe bridge exposure.
- Preload vocabulary tests prove moved channel guard vocabulary in
  `src/preload/channelBridgeGuards.cts` matches renderer-safe channel contract
  constants, `index.cts` keeps the only Electron binding and contextBridge
  exposure, and the bundled preload output has no runtime dependency on sibling
  preload modules.
- Main tests prove channel setup uses main-owned Plex/library and persistence
  custody, handles missing/corrupt/unavailable persistence safely, commits and
  replaces channels through the channel domain, preserves current-channel
  recovery semantics, ignores stale operations, and returns sanitized errors.
- Domain tests prove channel authoring, replacement, validation, and stored
  data normalization remain deterministic and pure.
- Renderer tests prove fake setup controls are not reachable in product routes,
  persisted setup/settings state renders safely, destructive confirmation is
  explicit, focus/back/text-entry/scroll behavior stays stable, and no
  forbidden fields are stored in renderer state.
- Smoke proves shell startup, sandbox/containment, and bridge composition stay
  intact.

Windows proof is mandatory before RD-23 closeout. Tracked summaries may include
only platform family, scenario counts, route names, command names, pass/fail/
blocked status, and sanitized blocker categories. Required proof categories:

- live library-backed channel setup from the RD-22B body
- validation, empty, loading, failed, cancelled, stale, and retry states
- review impact and destructive replace confirmation
- channel commit through main-owned persistence
- app restart and persisted channel/settings recovery
- setup rerun after existing channels
- focus, back, clear, text-entry, list/scroll, and route cleanup behavior
- redaction scan: no raw account, server, library, media, endpoint, path,
  token, header, payload, persistence-file, screenshot, log, process, native
  handle, support-bundle, or private proof material

Use a tracked proof summary shape like:
`RD-23 channel setup persistence: <passed>/<total> observed; blocked=<count>`.

## Acceptance Criteria

- Channel setup commits real library-backed channels through the reviewed
  channel runtime, pure channel domain, and main-owned channel persistence
  owners.
- Reachable channel setup and Settings surfaces no longer read as draft/
  scaffold UI after the owned workflow starts. Any remaining fake setup data is
  isolated to tests, smoke fixtures, or explicit dev-only harnesses.
- Setup UI has reviewed upstream parity evidence for hierarchy, controls,
  validation, review impact, destructive/confirmation states, focus/back,
  empty/error/loading states, and Desktop divergence notes.
- Settings shows renderer-safe persisted channel/setup recovery status and
  setup rerun affordances without claiming playback, guide runtime, or
  arbitrary preference persistence.
- Restart/recovery proves persisted channels and setup status without exposing
  private Plex, path, credential, raw persistence, or proof details.
- Main/preload/renderer contracts expose only renderer-safe summaries and
  reject forbidden fields.
- Import ledger is updated before or with any copied/adapted upstream channel
  setup/settings/setup-workflow/CSS/copy/test source.
- Windows proof, `npm run verify`, `npm run smoke:electron`,
  `npm run verify:redaction`, required focused tests, and read-only
  implementation review pass before RD-23 is closed.

## Replan Triggers

- RD-23 requires broad persistence IPC, renderer-owned storage, browser
  storage, raw persistence files, raw Plex payloads, tokenized URLs, auth
  headers, selected connections, credentials, app paths, filesystem paths,
  Electron/Node APIs, native handles, or privileged diagnostics in renderer.
- The preload bridge would need broad RPC, arbitrary channel strings, another
  contextBridge exposure, channel guard vocabulary in `src/preload/index.cts`,
  runtime local preload-module requires, sandbox/context-isolation disablement,
  main preload path contract changes, or a preload bundle that cannot be proven
  as one sandbox-loadable CommonJS artifact.
- Channel-authoring, repository, manager, Plex runtime, or persistence hotspots
  must grow beyond reviewed guardrails without decomposition or an explicit
  allowlist update.
- Live setup needs RD-24 scheduler-backed guide/player runtime, RD-25 playback,
  RD-26 media options, package/release behavior, native helper changes, or a
  new dependency to prove the slice.
- Setup persistence needs backup/restore, credential migration, selected-server
  schema migration, browser storage migration, or public-release recovery
  claims.
- Windows proof cannot be completed without tracking raw screenshots, logs,
  paths, private Plex names, endpoint URLs, tokens, headers, payloads,
  persistence files, support bundles, process ids, native handles, or private
  proof.
- Required verification fails in a way that invalidates the chosen seam.
- Read-only plan or implementation review reports a material security,
  boundary, scope, import-ledger, verification, UI-parity, file-shape, or
  Windows-proof blocker.

## Rollback Notes

- Plan-only changes can be reverted by reverting this file.
- Implementation should use one focused commit per reviewed execution unit so a
  failed unit can be reverted without disturbing prior RD-22A/RD-22B behavior.
- If the preload/channel bridge is wrong, revert the channel bridge namespace
  and leave existing shell/window/player/diagnostics/Plex bridge behavior
  intact.
- If channel runtime commit/recovery fails, revert the focused main channel
  runtime/composition/persistence changes and keep RD-11 domain and RD-22B Plex
  runtime behavior unchanged.
- If renderer setup/settings binding regresses, revert the renderer channel
  setup binding while preserving the existing RD-22B onboarding/library flow.
- Ignored local proof under `docs/runs/**` can be deleted without affecting
  tracked source. Do not commit raw proof.
- Do not revert unrelated user changes or prior committed RD-22A/RD-22B fixes
  unless explicitly requested.

## Commit Checkpoints

- Checkpoint 1: `docs(plan): activate RD-23 channel setup persistence plan`
  after this plan passes `npm run verify:docs` and read-only plan review.
- Checkpoint 2: `feat(channel): wire persisted setup recovery seam` after the
  approved first implementation unit passes focused tests, maintainability,
  smoke if required, full verification, and implementation review.
- Checkpoint 3: `feat(channel): commit live library-backed channels` after the
  approved live setup/commit unit passes focused tests, Windows proof for live
  commit, full verification, and implementation review.
- Checkpoint 4: `docs(roadmap): close RD-23 channel setup persistence` only
  after all RD-23 units, Windows proof, read-only reviews, import-ledger duties,
  and durable memory updates are complete.
- Keep workflow/control-plane/docs changes separate from product source when
  practical. Do not stage unrelated files or combine RD-24/RD-25/RD-26 work
  into RD-23 commits.

## Execution Units

### Unit 1: Plan Activation And Review

Scope:

- Create this active tracked plan.
- Do not edit product source.

Verification:

- `npm run verify:docs` should pass.
- `git diff --check -- docs/plans/rd-23-live-channel-setup-runtime-persistence.md`
  should pass.
- Read-only plan review through `lineup-desktop-feature-review` must report no
  material blockers before product implementation begins.

### Unit 2: Persisted Channel Recovery And Settings Status Seam

Scope after clean plan review:

- Establish the renderer-safe channel contract, main channel composition,
  channel IPC/preload namespace, and app-data channel persistence path needed
  to load existing channels and expose safe setup/settings status.
- First implement the mandatory bundled preload split: move RD-23 channel guard
  vocabulary into `src/preload/channelBridgeGuards.cts`, have `index.cts`
  statically import/use that split owner while retaining the single Electron
  binding and `lineupDesktop` exposure, add the focused build step that emits
  one sandbox-loadable `dist/preload/index.cjs`, and update
  `src/__tests__/integration/preloadContractVocabulary.test.ts` to cover both
  moved vocabulary and bundled-output constraints.
- Settings and channel setup surfaces should show real persisted channel/setup
  status and remove or isolate fake draft status where this unit owns the path.

Files in scope: the contract/preload/main/channel persistence/renderer files
listed in `## Files In Scope`.

Verification:

- Focused commands from `## Verification Commands` for touched owners.
- `npm run verify:maintainability`
- `npm run build:electron`
- `npm run verify:redaction`
- `npm run smoke:electron`
- `npm run verify`
- Read-only implementation review.

Stop/replan:

- Any preload bundle proof, hard-overage, broad IPC, renderer storage, raw
  payload, app-path, migration, or file-shape trigger fires.

### Unit 3: Live Library-Backed Channel Setup And Commit

Scope after Unit 2 review is clean:

- Use RD-22B live Plex library/profile/server state through main custody to
  create, review, validate, replace/append, and persist Desktop channels.
- Commit through the existing pure channel domain and separate channel
  persistence adapter.
- Bind the real setup journey into the RD-22A/RD-22B body, including upstream
  setup/settings parity where compatible with Desktop boundaries.
- Retire reachable fake draft setup controls from the product route.

Files in scope: the main channel runtime, domain channel, renderer setup,
Plex-library adapter, contract/preload, test, and import-ledger files listed in
`## Files In Scope`.

Verification:

- Focused channel runtime/domain/preload/renderer commands from
  `## Verification Commands`.
- `npm run verify:redaction`
- `npm run verify:maintainability`
- `npm run smoke:electron`
- redaction-safe Windows proof for live setup and commit
- `npm run verify`
- Read-only implementation review.

Stop/replan:

- Live commit needs scheduler guide runtime, playback, broader Plex browsing,
  raw Plex material, raw persistence state, new dependency, backup/restore, or
  hot-file growth beyond guardrails.

### Unit 4: Restart Recovery, Windows Proof, And Closeout

Scope after Unit 3 review is clean:

- Prove restart recovery for persisted channels and setup/settings status on
  Windows.
- Verify setup rerun/destructive state behavior against existing channels.
- Record only redaction-safe proof summaries.
- Update import ledger, current-state architecture, roadmap, and parity/proof
  docs only for observed RD-23 outcomes.
- Route the completed implementation and proof package to read-only review.

Verification:

- exact focused commands required by touched closeout files
- `npm run verify:docs`
- `npm run verify:redaction`
- `npm run smoke:electron`
- `npm run verify`
- `git diff --check`
- read-only implementation/proof review clean

Stop/replan:

- Windows proof is blocked, private evidence would need tracking, durable docs
  would overclaim RD-24/RD-25/RD-26 readiness, or material review findings
  remain.

## Unit 4 Closeout Attempt

2026-05-30 Windows proof status: blocked.

Observed redaction-safe proof:

- `npm run build:electron` passed before proof.
- A focused Electron/CDP proof command launched the built app on Windows,
  exercised only renderer-safe `window.lineupDesktop.plex` and
  `window.lineupDesktop.channelSetup` bridge methods, and printed only
  category/count/pass-fail facts.
- Proof summary: `RD-23 channel setup persistence: 2/8 observed; blocked=6`.
- Passing categories: validation failure state and Settings route recovery
  surface availability.
- Sanitized blocker probe: Windows platform and bridge readiness were observed;
  Plex snapshot and selected-server restore calls returned safely; movie/show
  library section count was `6`; active profile readiness was `false`;
  selected server readiness was `false`; persisted channel count was `0`.

Blocked categories:

- live library-backed channel commit
- destructive replace confirmation through a committed channel set
- persisted channel recovery after restart
- setup rerun after existing channels
- full focus/back/text-entry/list/scroll proof for the committed setup path
- redaction-safe closeout summary for the complete RD-23 proof package

Conclusion: RD-23 is not ready for closeout review and must not route to RD-24.
The blocker is missing active live Plex profile/server state for the channel
commit path in this Windows proof environment. No private account, server,
library, media, endpoint, token, header, raw payload, local path, process id,
native handle, screenshot, raw log, support bundle, or raw persistence evidence
was tracked.

2026-05-30 second Windows proof-remediation attempt: blocked.

Observed redaction-safe proof:

- `npm run build:electron` passed before proof.
- A focused Electron/CDP proof command launched the built app on Windows and
  used only renderer-safe `window.lineupDesktop.plex` and
  `window.lineupDesktop.channelSetup` bridge methods. Output was limited to
  platform, bridge readiness, operation pass/fail, sanitized error codes,
  category counts, and booleans.
- Initial snapshot readiness was `activeProfileReady=false` and
  `selectedServerReady=false`; `restoreSelectedServer()` returned safely with
  `selectionKind=selected`, `activeProfileReady=true`, and
  `selectedServerReady=true`.
- `listLibrarySections()` returned safely with six movie/show candidate
  sections. A follow-up sanitized item-page probe returned safely for all six
  candidates; observed item counts were non-zero for all candidates, and all
  observed item pages had positive-duration items.
- `channelSetup.commit({ mode: "append" })` returned
  `CHANNEL_VALIDATION_FAILED` for all six candidate sections. Persisted channel
  count remained `0`.
- Settings/channel setup route availability and text-entry presence were
  observed. Full focus/back/clear/list/scroll proof remains blocked because the
  committed setup path does not exist yet.

Proof summary: `RD-23 channel setup persistence: 2/8 observed; blocked=6`.

Passing categories:

- validation failure state
- Settings/channel setup route recovery surface availability

Sanitized blocker categories:

- live library-backed channel commit: blocked by
  `CHANNEL_VALIDATION_FAILED` across `6/6` movie/show candidate sections after
  active profile and selected server restore succeeded
- destructive replace confirmation through a committed channel set: blocked
  because persisted channel count remained `0`
- persisted channel recovery after restart: blocked because no channel commit
  was persisted
- setup rerun after existing channels: blocked because no existing channel set
  was created
- full focus/back/clear/text-entry/list/scroll proof for the committed setup
  path: blocked because the committed setup path does not exist yet
- redaction-safe closeout summary for the complete RD-23 proof package: blocked
  because RD-23 channel commit and restart recovery did not pass

Conclusion: RD-23 is still not ready for closeout review and must not route to
RD-24. The original active profile/server readiness blocker was not reproduced
after invoking the existing RD-22B selected-server restore bridge operation;
the current sanitized blocker is channel commit validation after live profile,
server, library-section, and item-page readiness are observed. No private
account, server, library, media, endpoint, token, header, raw payload, local
path, process id, native handle, screenshot, raw log, support bundle, or raw
persistence evidence was tracked.

## Direction Correction: Upstream Setup UI Before Proof

2026-05-31 controller/user direction correction:

- Do not run further Electron app proof, Windows proof, or manual runtime proof
  for RD-23 channel setup until the reachable setup UI is complete enough to
  match the upstream Lineup/webOS onboarding and channel-setup journey in the
  Desktop stack.
- Local implementation checks such as typecheck, focused unit tests,
  maintainability, docs verification, and redaction verification remain allowed.
  They are not a substitute for product proof and must not be described as app
  proof.
- The current product route must not be closed with a hybrid of RD-22 Plex
  browsing, fake/draft channel setup review, and bolted-on append/replace
  controls. That hybrid caused the observed manual confusion and invalidates
  further incremental UI proof for this area.
- Future workers must treat upstream UI parity as the next blocking RD-23 unit:
  first make the live setup journey coherent and upstream-shaped, then diagnose
  any remaining `CHANNEL_VALIDATION_FAILED` commit branch, then resume app proof.

Research and review evidence:

- Upstream reference repo is available locally at `C:\Software\Lineup` on commit
  `613b1c516c7c9e37f9c18ea3e92c474013472b11`.
- Upstream channel-setup UI source to audit/adapt:
  `src/modules/ui/channel-setup/**`, including `ChannelSetupScreen.ts`,
  `ChannelSetupSessionController.ts`, `ChannelSetupWorkflowPresenter.ts`,
  `ChannelSetupUserCopy.ts`, `steps/LibraryStepController.ts`,
  `steps/LibraryStepPresenter.ts`, `steps/StrategyStepController.ts`,
  `steps/BuildReviewStepController.ts`, `steps/BuildProgressStepController.ts`,
  and `styles*.css`.
- Upstream channel-setup domain/workflow source to use as behavior evidence:
  `src/core/channel-setup/**`, especially `ChannelSetupCoordinator.ts`,
  `ChannelSetupRerunController.ts`, `workflow/**`, `build/**`,
  `planning/**`, and `shared/formatChannelSetupWarning.ts`.
- Upstream settings UI source to audit/adapt for recovery/settings parity:
  `src/modules/ui/settings/**`, especially `SettingsScreen.ts`,
  `SettingsScreenStateController.ts`, `SettingsStore.ts`, `SettingsToggle.ts`,
  `SettingsSelect.ts`, and `styles*.css`.
- The upstream-equivalent user flow is: enter setup, choose/auth Plex runtime,
  select live library source, configure channel strategy, review build/validation,
  commit append/replace/confirm, and recover the persisted result through
  Settings/setup rerun.

Current Desktop divergence to fix before proof:

- `src/renderer/settingsSetup.ts` still owns fake `Demo Library` draft setup
  state and demo channel rows.
- `src/renderer/staticDom.ts` mixes RD-22 Plex browse/metadata panels with
  fake review/status content and commit buttons.
- `src/renderer/workflow.ts` and `src/renderer/routeDom.ts` can render setup
  summaries, counts, validation, and button states from draft or stale runtime
  state instead of one authoritative live setup model.
- The user can browse a live library and preview metadata, but the visible
  product path does not clearly become "create channels from this selected
  library" in the same upstream-shaped setup journey.
- Replace/confirm behavior and selected-library readiness need to reflect
  persisted channel status and current live library state; they must not appear
  as unexplained controls.

Uncommitted worker patch status:

- A 2026-05-31 worker patch is present in the worktree and is not committed.
  It changed renderer setup copy/state and added
  `src/renderer/channelSetupLiveSelection.ts` plus focused renderer tests.
- Read-only review found the patch directionally useful but not clean as a
  standalone checkpoint. It can show stale selected-library readiness/item
  counts, exposes replace too early, and lacks coverage for the actual renderer
  action path.
- Next session must either fold this patch into the full upstream UI parity
  unit or replace it cleanly. Do not commit it as an RD-23 fix by itself.

## Required Next Unit: RD-23 Live-Onboarding Setup Parity

Purpose:

- Replace the reachable fake/draft setup review with a single authoritative,
  upstream-shaped Desktop setup journey backed by live Plex section selection
  and main-owned persisted channel status.
- Preserve Desktop boundaries: renderer owns display and interaction state;
  main owns Plex transport, raw payloads, tokens, selected connections,
  channel authoring, and persistence.

Files expected in scope:

- `src/renderer/staticDom.ts`
- `src/renderer/workflow.ts`
- `src/renderer/routeDom.ts`
- `src/renderer/settingsSetup.ts`
- `src/renderer/index.ts`
- `src/renderer/plexRuntimeActions.ts`
- `src/renderer/plexRuntimeState.ts`
- `src/renderer/plexRuntimeDom.ts`
- `src/renderer/plexRuntimeRows.ts`
- `src/renderer/channelRuntimeActions.ts`
- `src/renderer/channelRuntimeState.ts`
- focused renderer tests under `src/__tests__/renderer/**`
- `docs/architecture/import-ledger.md` if upstream source/copy/CSS/tests are
  copied or adapted
- this plan, if scope or proof rules change

Files out of scope unless a reviewed replan says otherwise:

- RD-24 scheduler-backed guide runtime
- RD-25 playback/native-helper production behavior
- RD-26 media options
- package/release/signing/update behavior
- backup/restore
- broad RPC or renderer-owned storage
- raw Plex payloads, tokenized URLs, credentials, app paths, private proof, or
  raw persistence inspection

Implementation requirements:

- Remove or fence fake `Demo Library`/draft channel setup as a reachable product
  path. It may remain only as an explicitly non-product test fixture.
- Structure the UI as a wizard-like upstream flow rather than a Plex browser
  with a separate review panel underneath.
- Make selected library state explicit and current. The setup path must
  distinguish library-section selection from media-item metadata preview.
- Represent setup stages with upstream-equivalent semantics: source/library,
  strategy/channel creation, review/validation, build/commit result, and
  persisted recovery/rerun.
- Derive replace/confirm availability from persisted channel status and the
  explicit confirmation-required result, not from a generic selected-library
  boolean.
- Surface sanitized commit failures in the setup result stage, preserving the
  distinction between invalid library ids and no usable library content.
- Keep settings recovery tied to `channelSetup.getStatus()` and persisted
  channel summaries; do not show synthetic setup success.
- Update focused renderer tests to cover live selection resolution, stale item
  avoidance, no-library state, first-run create state, existing-channel
  append/replace/confirm states, and sanitized failure rendering.

Verification allowed before UI parity completion:

- `npm run typecheck`
- focused renderer/unit tests for touched owners
- `npm run verify:maintainability`
- `npm run verify:docs` for docs changes
- `npm run verify:redaction`
- `git diff --check`
- read-only implementation review

Verification explicitly paused until this unit is complete and reviewed:

- Electron app launch proof
- smoke/electron proof for this RD-23 setup route
- Windows live manual proof
- restart/recovery runtime proof
- screenshot/pixel/UI proof
- any proof that asks the user to manually test the setup flow before the
  upstream-shaped UI is complete

Acceptance criteria before app proof resumes:

- The reachable Channel setup route no longer presents fake draft setup as a
  product workflow.
- A user can understand the intended path from UI alone: choose/auth Plex,
  select a movie/show library source, configure/create channels, review result,
  and recover/rerun from Settings.
- The setup panel never says no library is selected when a current movie/show
  library section is selected.
- Media item preview is visually secondary and cannot be mistaken for the
  channel-creation input.
- Replace and confirm replace states are understandable and only shown when
  applicable.
- Sanitized runtime failures are visible where the user attempted the action.
- The implementation review is clean for UI parity, renderer state ownership,
  stale selection behavior, and no fake-route leakage.

Stop/replan triggers:

- The UI parity unit needs scheduler guide runtime, playback, media options,
  package/release behavior, backup/restore, raw Plex payloads, renderer-owned
  storage, or private proof.
- A copied/adapted upstream source slice lacks an import-ledger row.
- File-shape guardrails are breached without a reviewed split.
- The implementation cannot preserve Desktop process/security boundaries while
  matching the upstream setup flow.

## Continuation Handoff

MODEL_SUGGESTION
PLANNER: gpt-5 high reasoning if scope must be rewritten again
IMPLEMENTER: gpt-5 high reasoning
REVIEWER: gpt-5 high reasoning
WHY: RD-23 remains Tier 3 cross-boundary work, but the immediate blocker is
upstream setup UI parity before app proof. The next worker must understand
renderer UI composition, live Plex renderer state, main-owned persistence, and
import-ledger duties.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop
TASK: Continue RD-23 With Live-Onboarding Setup UI Parity Before Proof
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/rd-23-live-channel-setup-runtime-persistence.md
ARTIFACT: active RD-23 tracked plan with 2026-05-31 direction correction
FILES:
- docs/plans/rd-23-live-channel-setup-runtime-persistence.md
- AGENTS.md
- docs/AGENTIC_DEV_WORKFLOW.md
- docs/architecture/CURRENT_STATE.md
- docs/architecture/file-shape-guardrails.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/import-ledger.md
- docs/roadmap/desktop-port-roadmap.md
- docs/product/lineup-product-parity-matrix.md
- docs/development/windows-ui-proof-plan.md
- C:\Software\Lineup\src\modules\ui\channel-setup\**
- C:\Software\Lineup\src\core\channel-setup\**
- C:\Software\Lineup\src\modules\ui\settings\**
- src/renderer/staticDom.ts
- src/renderer/workflow.ts
- src/renderer/routeDom.ts
- src/renderer/settingsSetup.ts
- src/renderer/index.ts
- src/renderer/plexRuntime*.ts
- src/renderer/channelRuntime*.ts
- src/__tests__/renderer/**
CURRENT_WORKTREE:
- Branch `initial-build` is ahead of origin.
- RD-23 commits already created: plan activation, persisted setup recovery seam,
  and live library-backed channel commit.
- Uncommitted product/test changes from the 2026-05-31 worker exist and are not
  approved as a standalone checkpoint. Inspect and either fold them into the
  parity unit or replace them cleanly.
BLOCKERS:
- No app proof is allowed until the upstream-shaped setup UI is implemented and
  reviewed clean.
- Existing Windows proof remains blocked by `CHANNEL_VALIDATION_FAILED`, but
  that runtime diagnosis is intentionally deferred until the UI is coherent.
MESSAGE:
Use the feature-quality loop as controller. Start by reading this direction
correction and the upstream source paths listed above. Do not run Electron app
proof, Windows proof, or manual proof for RD-23 channel setup yet. First
implement the RD-23 Live-Onboarding Setup Parity unit: remove/fence fake draft
setup from the reachable product route, adapt the upstream setup/settings flow
into Desktop renderer boundaries, make live library selection and persisted
status the only product setup sources, and add focused unit coverage. Record
any copied/adapted upstream source in the import ledger before or with the
implementation. After focused checks and clean read-only implementation review,
only then resume runtime/app proof to diagnose any remaining
`CHANNEL_VALIDATION_FAILED` commit path.
