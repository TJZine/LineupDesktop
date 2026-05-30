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

## Plan Review Handoff

MODEL_SUGGESTION
PLANNER: n/a
IMPLEMENTER: gpt-5 high reasoning
REVIEWER: gpt-5 high reasoning
WHY: RD-23 is Tier 3 work across live Plex library state, pure channel domain, main-owned persistence, preload IPC, renderer UI, upstream source adaptation, redaction, file-shape guardrails, and Windows proof.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-review
TASK: Review RD-23 Live Channel Setup And Runtime Persistence Plan
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/rd-23-live-channel-setup-runtime-persistence.md
ARTIFACT: active RD-23 tracked plan
FILES:
- docs/plans/rd-23-live-channel-setup-runtime-persistence.md
- docs/architecture/CURRENT_STATE.md
- docs/architecture/file-shape-guardrails.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/import-ledger.md
- docs/roadmap/desktop-port-roadmap.md
- docs/product/lineup-product-parity-matrix.md
- docs/development/windows-ui-proof-plan.md
BLOCKERS: none known; implementation must not start until read-only plan review is clean.
MESSAGE:
Review the active RD-23 plan for decision completeness before implementation.
Prioritize architecture seams, file-shape decisions for preload/channel
hotspots, exact files in/out of scope, import-ledger duties, fake setup route
retirement, Windows proof requirements, verification commands, acceptance
criteria, and stop/replan triggers. Confirm whether the bounded vertical units
cover the whole RD-23 roadmap item without pulling in RD-24 guide runtime,
RD-25 playback, RD-26 media options, backup/restore, broad RPC, renderer-owned
storage, raw Plex material, credentials, app paths, or private proof.
