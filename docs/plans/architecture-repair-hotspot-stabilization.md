# Architecture Repair Hotspot Stabilization Plan

**Plan Status:** active

**Task family:** feature/design

**Tier:** Tier 3

**Verification classification:** new regression/contract test required

**Branch target:** `initial-build`

**Current phase:** plan authored; read-only plan review required before any source edit.

**MODEL_SUGGESTION:** Use the repo planner/reviewer/worker roles named by
`docs/agentic/session-prompts/feature-quality-loop.md`. Implementation workers
should use a high-reasoning model because the work changes ownership seams
across main, preload, renderer, Plex, and helper boundaries.

## Goal

Run a Tier 3 architecture repair program that reduces near-term growth risk in
Lineup Desktop's largest temporary owners before the next feature slice adds
more behavior.

This plan covers all material hotspots named by
`docs/agentic/architecture-repair-goal-brief.md`:

- `src/preload/index.cts`
- `src/main/player/desktopPlayerAdapter.ts`
- `src/main/player/nativePlayerHostProcess.ts`
- `src/main/player/plexPlaybackRuntime.ts`
- `src/main/plex/desktopPlexRuntime.ts`
- `src/renderer/index.ts`
- watch-list owners: `src/contracts/player.ts`,
  `src/main/plex/streamResolver.ts`,
  `src/main/player/streamPolicy/desktopStreamPolicy.ts`,
  `src/domain/channel/channelManager.ts`,
  `src/domain/channel/channelRepository.ts`, `src/renderer/epg.ts`, and
  `src/renderer/routeDom.ts`

The program is behavior-preserving. Each repair package must be reviewed,
implemented, verified, and reviewed again before the next package starts.

## Non-Goals

- No new product features, RD-26 media options, playback behavior, live
  transport growth, renderer workflows, Windows proof closeout, packaging,
  signing, installer, update, dependency, package, lockfile, or native binary
  redistribution work.
- No broad cleanup or rewrites merely to reduce line counts.
- No file-shape baseline increases to pre-authorize future growth.
- No compatibility barrels, old-path shims, fallback API variants, temporary
  adapters, or no-value forwarding owners.
- No renderer privilege, token-bearing renderer state, raw Electron/native
  handles, tokenized URLs, raw Plex payloads, privileged preload passthroughs,
  or broad RPC bridges.
- No copied/adapted upstream source unless a reviewed replan names provenance
  and updates `docs/architecture/import-ledger.md` before or with the import.
- No source edits before read-only plan review and adjudication are clean.

## Parent Architecture Alignment

- `AGENTS.md` and `docs/AGENTIC_DEV_WORKFLOW.md` route this as Tier 3
  feature/design work through the feature-quality loop.
- `docs/architecture/CURRENT_STATE.md` says RD-25 production native playback is
  code-complete but Windows manual proof remains pending; this repair program
  must not claim or alter that proof.
- `docs/architecture/file-shape-guardrails.md` treats large files as
  architecture surfaces. It names the same hotspot files and requires
  decomposition before further feature behavior grows hard-overage owners.
- `docs/architecture/security-and-secret-flow.md` requires Plex tokens,
  auth headers, tokenized URLs, raw Plex payloads, Electron/Node objects, native
  handles, helper process details, and app paths to remain outside renderer and
  preload-facing contracts.
- `docs/architecture/playback-architecture.md` keeps runtime playback
  main/helper-owned through a helper-hosted native libmpv path and NDJSON helper
  protocol, with manual Windows proof pending.
- `docs/architecture/packaging-release-gates.md` blocks public release,
  native-helper redistribution, and media binary redistribution changes.

## Required Reading

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-quality-loop.md`
4. `docs/agentic/architecture-repair-goal-brief.md`
5. `docs/agentic/plan-authoring-standard.md`
6. `docs/architecture/CURRENT_STATE.md`
7. `docs/architecture/file-shape-guardrails.md`
8. `docs/architecture/security-and-secret-flow.md`
9. `docs/architecture/playback-architecture.md`
10. `docs/architecture/packaging-release-gates.md`
11. `docs/architecture/import-ledger.md`
12. Current source and tests for the selected package's files in scope.

Freshness gate: before any implementation package starts, rerun `git status
--short --branch`, `wc -l` for the package hotspots, and targeted `rg` imports
for the package files. If source, tests, guardrails, or architecture docs have
changed materially since this plan was authored, stop for plan refresh and
read-only re-review.

## Required Skills

- `lineup-desktop-feature-quality-loop`: controls Tier 3 sequencing, role
  separation, review gates, and current execution-unit state.
- `execution-plan-authoring`: keeps the durable plan decision-complete without
  pseudo-code.
- `architecture-boundaries`: governs Electron main, preload, renderer, helper,
  IPC, and contract owner seams.
- `verification-strategy`: fixes package proof depth and expected commands.
- `plex-integration-boundaries`: applies to Plex runtime, selected connection,
  tokens, library transport, stream resolution, and PMS lease custody.
- `persistence-boundaries`: applies when Plex runtime or channel watch-list
  repairs touch selected server state, credentials, app paths, or persisted
  channel data.
- `ui-composition-patterns`: applies to renderer bootstrap, EPG, route DOM,
  focus, keyboard, polling, and overlay composition.
- `review-request`: required for the plan and every implementation package.
- `review-adjudication`: required before revising the plan or acting on
  reviewer findings.
- `closeout-verification`: required before calling a package or the program
  complete.

## Evidence And Discovery

Codanna evidence:

- `codanna retrieve search "DesktopPlayerAdapter" --limit 8` found
  `DesktopPlayerAdapter` in `src/main/player/desktopPlayerAdapter.ts` and the
  runtime port in `src/main/player/plexPlaybackComposition.ts`.
- `codanna retrieve search "NativePlayerHostProcess" --limit 8` found
  `NativePlayerHostProcess` in `src/main/player/nativePlayerHostProcess.ts`
  implementing `NativePlayerHostPort`.
- `codanna retrieve search "PlexPlaybackRuntime" --limit 8` found
  `PlexPlaybackRuntime` and its scheduler, channel, player, PMS, and clock
  ports in `src/main/player/plexPlaybackRuntime.ts`.
- `codanna retrieve search "DesktopPlexRuntime" --limit 8` found
  `DesktopPlexRuntime` in `src/main/plex/desktopPlexRuntime.ts`.
- `codanna retrieve search "lineupDesktop" --limit 8` found the preload bridge
  exposure in `src/preload/index.cts`.
- `codanna documents search "architecture repair hotspot native player preload"
  --limit 5` returned mostly archived plan context. Semantic/doc discovery was
  too noisy for scope freezing, so this plan uses exact symbol hits plus
  `rg`, `wc -l`, and direct reads as the authoritative fallback.

Direct evidence read:

- `docs/architecture/file-shape-guardrails.md` currently lists every required
  hotspot above 500 lines, with hard-overage triggers for several files.
- `wc -l` observed current counts: preload 2120, adapter 1368, native host
  process 541, playback runtime 773, Plex runtime 657, renderer bootstrap 724,
  player contract 703, stream resolver 660, stream policy 624, channel manager
  1022, channel repository 770, EPG 725, route DOM 511.
- Direct reads confirmed:
  - `NativePlayerHostProcess` mixes process spawn/reap, stdin/stdout/stderr IO,
    NDJSON framing, pending request resolution, helper failure normalization,
    helper diagnostics, and private load setup serialization.
  - `DesktopPlayerAdapter` mixes renderer intent mapping, runtime command
    dispatch, duplicate request-id custody, snapshot mutation, host event
    validation, stale event quarantine, cleanup, and diagnostics.
  - `PlexPlaybackRuntime` mixes scheduler selection, candidate safety, PMS
    release, player dispatch, stale event custody, helper-crash cleanup, epoch
    state, diagnostics, and renderer-safe error construction.
  - `DesktopPlexRuntime` mixes auth/profile/server operations, selected-server
    orchestration, library sections/items/search/metadata operations,
    abort/stale operation custody, snapshot mutation, and diagnostics.
  - `src/preload/index.cts` keeps the sandbox-compatible single bridge and all
    guard/channel families in one entrypoint.
  - `src/renderer/index.ts` mixes bootstrap, bridge subscriptions, route
    actions, Plex/channel controllers, guide polling, input/focus, fullscreen,
    support-bundle export, and render orchestration.
  - Watch-list owners have existing seams and tests but are not the highest
    production-safety risk unless new behavior targets them.

Current tests protecting seams:

- Native/helper: `src/__tests__/main/player/nativePlayerHostProcess.test.ts`,
  `src/__tests__/main/player/productionNativeHostFactory.test.ts`,
  `src/__tests__/main/player/playerPublicSafetyAssertions.ts`.
- Adapter/player IPC/runtime:
  `src/__tests__/main/player/desktopPlayerAdapter.test.ts`,
  `src/__tests__/main/playerIpc.test.ts`,
  `src/__tests__/main/player/plexPlaybackRuntime.test.ts`,
  `src/__tests__/main/player/plexPlaybackLifecycleIntegration.test.ts`,
  `src/__tests__/main/player/plexPlaybackBridge.test.ts`,
  `src/__tests__/main/player/plexPlaybackComposition.test.ts`,
  `src/__tests__/main/player/playbackRuntimeBootstrap.test.ts`.
- Preload/contracts: `src/__tests__/integration/preloadContractVocabulary.test.ts`,
  `src/__tests__/contracts/contracts.test.ts`,
  `src/__tests__/main/shellSecurity.test.ts`.
- Plex: `src/__tests__/main/plexRuntimeIpc.test.ts`,
  `src/__tests__/main/plexStreamResolver.test.ts`,
  `src/__tests__/main/plexStreamResolverComposition.test.ts`,
  `src/__tests__/main/plexPlaybackMediaDetailPort.test.ts`,
  `src/__tests__/main/plexPmsPlaybackSessionPort.test.ts`.
- Channel/domain: `src/__tests__/domain/channelDomain.test.ts`,
  `src/__tests__/domain/channelPersistence.test.ts`,
  `src/__tests__/main/channelRuntimeIpc.test.ts`,
  `src/__tests__/main/channelPersistenceAdapter.test.ts`.
- Renderer: `src/__tests__/renderer/navigation.test.ts`,
  `src/__tests__/renderer/workflow.test.ts`,
  `src/__tests__/renderer/overlays.test.ts`,
  `src/__tests__/renderer/epg.test.ts`,
  `src/__tests__/renderer/epgStateUpdate.test.ts`,
  `src/__tests__/renderer/routeDom.test.ts`,
  `src/__tests__/renderer/plexRuntime.test.ts`,
  `src/__tests__/renderer/channelRuntimeActions.test.ts`,
  `src/__tests__/renderer/channelSetupLiveSelection.test.ts`,
  `src/__tests__/renderer/supportBundleExport.test.ts`.

Inventory summary:

| Hotspot | Current owner responsibility | Custody / public exposure / stale behavior | Decision |
| --- | --- | --- | --- |
| `src/main/player/nativePlayerHostProcess.ts` | Helper process lifecycle, IO streams, NDJSON framing, pending commands, cleanup/reap, failure normalization, helper diagnostics, private load setup serialization. | Handles private playback context before helper write; public exposure is only `NativePlayerHostPort`; request identity lives in `#pending`; malformed/oversized output quarantines child. | Package 1 decomposes process IO/framing from message validation/command settlement. |
| `src/main/player/desktopPlayerAdapter.ts` | Renderer intent mapping, runtime command dispatch, snapshot mutation, duplicate request-id custody, host event validation, stale-event quarantine, cleanup diagnostics. | Privileged context is accepted only for runtime load; renderer loads can be rejected; public exposure is adapter dispatch result and player events. | Package 2 extracts request custody/dispatch coordination while preserving public adapter shape. |
| `src/main/player/plexPlaybackRuntime.ts` | Scheduler selection, playback candidate safety, epoch custody, PMS release, player dispatch, cleanup, stale-event quarantine, error/diagnostic projection. | PMS leases and private playback descriptors stay main-owned; stale async paths use epochs and request ids; public exposure is renderer-safe player events. | Package 3 extracts cleanup/stale custody before more playback growth. |
| `src/preload/index.cts` | Single sandbox-compatible typed bridge, channel constants, guards, invokers, event listener guards, diagnostics/Plex/player/channel families. | Renderer sees only `window.lineupDesktop`; no raw Electron/Node or arbitrary channels; guard duplication is high. | Package 4 splits channel-family guards into sandbox-compatible modules only after Packages 1-3 are stable. |
| `src/main/plex/desktopPlexRuntime.ts` | Auth/profile/server orchestration, library operations, operation abort/stale custody, snapshot commits, diagnostics. | Token and selected connection remain main-owned; request identity keyed by operation; public exposure is `PlexIpcResult` snapshots. | Package 5 splits server/profile orchestration from library operations and operation custody. |
| `src/renderer/index.ts` | Renderer bootstrap, bridge subscriptions, route actions, Plex/channel controllers, guide polling, fullscreen, input/focus, cleanup, render loop. | Renderer-safe state only; stale guide polling uses incrementing ids; listeners/timers clean up on unload. | Package 6 extracts bootstrap/action registration/polling owners without changing UI behavior. |
| `src/contracts/player.ts` | Renderer-safe player vocabulary and forbidden-field guards. | Public contract; changing it requires impact analysis and contract tests. | Watch-list Package 7 audits and defers unless another package proves a contract split is necessary. |
| `src/main/plex/streamResolver.ts` | Selected connection/auth/media detail/PMS ports, policy evaluation, public load projection, private playback descriptor projection. | Raw URLs/auth headers/private track ids stay private; public load payload is renderer-safe. | Watch-list Package 7 audits; no first-slice touch unless Package 3 reveals coupling. |
| `src/main/player/streamPolicy/desktopStreamPolicy.ts` | Deterministic fixture policy for direct play/direct stream/transcode/unsupported and track selection. | No privileged data; public policy decisions are fixture-safe. | Watch-list Package 7 audits; avoid growth until new codec/track behavior exists. |
| `src/domain/channel/channelManager.ts` | Pure domain channel mutation, current-channel state, persistence coordination, cache/retry, events. | No Electron/Plex secret/native custody; mutation serialization via `mutationChain`. | Watch-list Package 7 audits; defer source split until live channel editing or backup/restore growth. |
| `src/domain/channel/channelRepository.ts` | Persisted channel normalization/repair, order/current-channel correction, save wrappers. | Reads/writes through domain persistence port; malformed persisted shape repair is tested. | Watch-list Package 7 audits; defer until persisted channel editing expands. |
| `src/renderer/epg.ts` | Guide presentation normalization, demo source, EPG state/window math, view projection. | Renderer-safe UI state only; no privileged custody. | Package 7 audits; defer split unless Package 6 needs a guide polling/view boundary. |
| `src/renderer/routeDom.ts` | Route shell DOM, workflow rendering, EPG DOM, overlays, settings/channel setup route branches. | Renderer-safe DOM only; tests cover route DOM behavior. | Package 7 audits; defer split unless Package 6 reveals render registration coupling. |

## Impact Snapshot

Expected blast radius:

- Production source changes are limited to package-specific owners and adjacent
  same-boundary modules named in `Files In Scope`.
- Public contracts should not change in Packages 1-6. Package 7 may recommend a
  reviewed follow-up if player-contract sub-vocabulary splitting is justified.
- No dependency, build-tool, configuration, package, lockfile, native binary, or
  release artifact changes are expected.
- Runtime behavior must not change. Renderer-visible snapshots/events,
  preload API shape, Plex IPC results, diagnostics redaction, channel behavior,
  focus, keyboard, fullscreen, guide polling, and support-bundle behavior must
  remain equivalent.
- Local-only artifacts that must stay untracked: Codanna indexes, caches,
  run bundles, manual proof output, screenshots, package output, helper build
  output, raw logs, support bundles, and private Plex evidence.
- Every source package requires maintainability verification, package-specific
  tests, `npm run verify:redaction` when diagnostic/secret surfaces are
  touched, and `npm run verify` before implementation closeout.

## Architecture Health

File-shape evidence is from `docs/architecture/file-shape-guardrails.md` and
fresh `wc -l` direct reads on 2026-06-11. The program decomposes hard-overage
owners instead of raising baselines.

Decision: decompose `src/main/player/desktopPlayerAdapter.ts`,
`src/preload/index.cts`, and `src/domain/channel/channelManager.ts` only through
bounded packages with public-seam proof; avoid source growth in watch-list
files until a reviewed package selects them.

Decision: extract from `src/main/player/nativePlayerHostProcess.ts`,
`src/main/player/plexPlaybackRuntime.ts`,
`src/main/plex/desktopPlexRuntime.ts`, and `src/renderer/index.ts` before the
next feature slice grows helper, playback, Plex, or renderer orchestration
policy.

Decision: keep `src/contracts/player.ts`, `src/main/plex/streamResolver.ts`,
`src/main/player/streamPolicy/desktopStreamPolicy.ts`,
`src/domain/channel/channelRepository.ts`, `src/renderer/epg.ts`, and
`src/renderer/routeDom.ts` under avoidance/deferral for the first repair
sequence unless package evidence shows hidden coupling.

Maintainability verification route:

```bash
npm run verify:maintainability
```

Expected outcome: no touched production file grows beyond its current guardrail
baseline without a reviewed guardrail update; at least one hotspot shrinks or
has behavior moved to a focused same-owner module in each source package.

## Files In Scope

Plan/review:

- `docs/plans/architecture-repair-hotspot-stabilization.md`

Package 1, native host process IO/framing extraction:

- `src/main/player/nativePlayerHostProcess.ts`
- New focused modules under `src/main/player/` for helper message parsing,
  command serialization, pending request settlement, or process IO as selected
  by implementation review.
- `src/main/player/nativeHelperProtocol.ts`
- `src/main/player/nativePlayerHostPort.ts` only if an existing private main
  port type must move with the extraction.
- `src/__tests__/main/player/nativePlayerHostProcess.test.ts`
- Focused new tests under `src/__tests__/main/player/`.

Package 2, player adapter request custody extraction:

- `src/main/player/desktopPlayerAdapter.ts`
- New focused modules under `src/main/player/` for request custody, command
  dispatch, renderer intent mapping, host event projection, or adapter
  diagnostics as selected by implementation review.
- `src/main/player/privilegedPlaybackDispatchContext.ts`
- `src/main/player/nativePlayerHostPort.ts` only if the private port boundary
  needs type relocation.
- `src/__tests__/main/player/desktopPlayerAdapter.test.ts`
- `src/__tests__/main/player/playerPublicSafetyAssertions.ts`
- Focused new tests under `src/__tests__/main/player/`.

Package 3, Plex playback runtime cleanup/stale custody extraction:

- `src/main/player/plexPlaybackRuntime.ts`
- New focused modules under `src/main/player/` for cleanup orchestration,
  stale-event custody, PMS release coordination, or runtime diagnostics.
- `src/main/player/plexPlaybackBridge.ts` and
  `src/main/player/plexPlaybackComposition.ts` only for private same-boundary
  port type movement required by the extraction.
- `src/__tests__/main/player/plexPlaybackRuntime.test.ts`
- `src/__tests__/main/player/plexPlaybackLifecycleIntegration.test.ts`
- `src/__tests__/main/player/plexPlaybackBridge.test.ts`
- `src/__tests__/main/player/plexPlaybackComposition.test.ts`

Package 4, preload bridge guard/channel-family split:

- `src/preload/index.cts`
- Existing preload helper files such as `src/preload/channelSetupBridge.cts`
  and `src/preload/guideBridge.cts`
- New focused preload modules under `src/preload/` for channel constants,
  player guards, Plex guards, diagnostics guards, or shared validation helpers,
  provided they remain sandbox-compatible CommonJS preload code.
- `src/__tests__/integration/preloadContractVocabulary.test.ts`
- `src/__tests__/main/shellSecurity.test.ts`
- `src/__tests__/contracts/contracts.test.ts`

Package 5, Plex runtime operations split:

- `src/main/plex/desktopPlexRuntime.ts`
- `src/main/plex/desktopPlexRuntimeSupport.ts`
- New focused modules under `src/main/plex/` for operation custody,
  server/profile orchestration, or library operations.
- `src/main/plex/livePlexTransport.ts` only for type-only private port
  movement required by the split.
- `src/__tests__/main/plexRuntimeIpc.test.ts`
- `src/__tests__/main/plexLibraryMinimalAdapter.test.ts`
- `src/__tests__/main/plexStreamResolverComposition.test.ts` only if private
  runtime ports move.

Package 6, renderer bootstrap/action registration split:

- `src/renderer/index.ts`
- Existing renderer owners already imported by `index.ts`, only where their
  public renderer-safe registration boundary must move.
- New focused modules under `src/renderer/` for bootstrap, bridge
  subscriptions, guide polling, route action registration, Plex/channel action
  wiring, or cleanup.
- `src/__tests__/renderer/navigation.test.ts`
- `src/__tests__/renderer/workflow.test.ts`
- `src/__tests__/renderer/plexRuntime.test.ts`
- `src/__tests__/renderer/channelRuntimeActions.test.ts`
- `src/__tests__/renderer/supportBundleExport.test.ts`
- `src/__tests__/renderer/epgStateUpdate.test.ts`

Package 7, watch-list audit and explicit deferrals or follow-up packets:

- Source reads and tests only unless reviewed package evidence requires a
  source package for one of the watch-list files.
- Potential future package files:
  `src/contracts/player.ts`, `src/main/plex/streamResolver.ts`,
  `src/main/player/streamPolicy/desktopStreamPolicy.ts`,
  `src/domain/channel/channelManager.ts`,
  `src/domain/channel/channelRepository.ts`, `src/renderer/epg.ts`,
  `src/renderer/routeDom.ts`, and their tests.

## Files Out Of Scope

- `package.json`, lockfiles, build tooling, Electron packaging scripts, native
  helper redistribution, signing, installer, update metadata, and generated
  output.
- `src/main/index.ts` unless a reviewed package discovers an unavoidable
  composition-only import path update. If touched, it must not absorb new
  feature policy.
- Renderer product UX, visual redesign, new routes, new playback controls,
  RD-26 media options, live transport growth, Windows manual proof, and
  upstream parity changes.
- Public contract expansion in `src/contracts/player.ts`,
  `src/contracts/plex.ts`, `src/contracts/shell.ts`, or `src/contracts/ipc.ts`
  unless a reviewed replan makes that contract package current.
- Persistence schema or credential format changes.
- `docs/architecture/file-shape-guardrails.md` baseline raises. Shrink/removal
  updates are allowed only with the source package that earns them and after
  review.
- `docs/architecture/import-ledger.md` unless a reviewed replan adds
  copied/adapted upstream source, which this plan currently forbids.

## Planner Self-Check

1. No product, ownership, dependency, packaging, security, or verification
   decision is intentionally left to the first implementation worker.
2. Adjacent type or contract moves are in scope only where named for the active
   package; public contract expansion stops for replan.
3. Files out of scope are not required for hidden behavior changes. If a source
   package needs them, it must stop and refresh the plan.
4. Evidence records Codanna exact-symbol use, Codanna doc-search noise, direct
   reads, `rg`, and current line counts.
5. Packages target existing repo-preferred owners and avoid growing hard
   hotspots.
6. Tier 3 Architecture Health evidence is included, with decomposition,
   avoidance, and deferral decisions.
7. A fresh implementer should not need to invent IPC, security, playback,
   Plex, persistence, packaging, import, or verification policy.
8. Exact verification commands, expected outcomes, rollback notes, and stop
   triggers are listed.

## Architecture Seam Decision Gate

Program seam: behavior-preserving owner decomposition. The public runtime
boundary must stay the same unless a reviewed replan selects a contract package.

Package order:

1. **Native host process IO/framing extraction.** Highest production-safety
   risk because it owns spawned process lifecycle, helper protocol framing,
   private playback serialization, and failure normalization. Owner seam:
   main/helper process transport remains behind `NativePlayerHostPort`; the
   extraction separates process IO/framing from host event validation and
   command settlement.
2. **Desktop player adapter request-custody extraction.** Owner seam:
   `DesktopPlayerAdapter` remains the public adapter facade, while request
   identity, duplicate rejection, runtime-vs-renderer dispatch, and host event
   projection move to focused main/player owners.
3. **Plex playback runtime cleanup/stale custody extraction.** Owner seam:
   `PlexPlaybackRuntime` remains the orchestrator facade, while PMS release,
   stale-event quarantine, and cleanup diagnostics move to focused owners.
4. **Preload guard/channel-family split.** Owner seam: preload remains the
   single sandbox-compatible typed bridge and may split guard families only into
   preload-local modules. No new bridge namespace or broad RPC shape.
4S. **Smoke blocker repair if needed before accepting Package 4.** Owner seam:
   main/channel composition may inject the scheduler clock required by the
   existing domain scheduler constructor when `npm run smoke:electron` fails
   before preload smoke proof can complete. This is not a product feature and
   must stay limited to restoring the already-required smoke gate.
4T. **Smoke assertion realignment if needed after Package 4S.** Owner seam:
   smoke assertions may be updated to prove current live-runtime/shell safety
   instead of stale fake-route text when `npm run smoke:electron` reaches the
   renderer and fails only on outdated guide/channel-setup/player smoke
   expectations. This is harness proof maintenance, not product UI behavior.
4U. **Fullscreen smoke observation realignment if needed after Package 4T.**
   Owner seam: fullscreen smoke assertions may distinguish renderer API success
   from observed BrowserWindow fullscreen state without expanding product
   fullscreen behavior.
4V. **Fullscreen focus-limited smoke fallback if needed after Package 4U.**
   Owner seam: fullscreen smoke proof may distinguish a focused fullscreen
   transition failure from an unfocused desktop smoke environment that cannot
   activate the window even after an explicit app/window focus request.
5. **Desktop Plex runtime operation split.** Owner seam:
   `DesktopPlexRuntime` remains the main-owned runtime facade while
   server/profile orchestration, library operations, and operation abort/stale
   custody move to focused main/Plex owners.
6. **Renderer bootstrap/action registration split.** Owner seam:
   `src/renderer/index.ts` remains the composition root, while bootstrap,
   bridge subscriptions, guide polling, route action registration, and cleanup
   move to renderer-safe owners.
7. **Watch-list audit and deferrals.** Owner seam: source changes happen only
   if audit evidence proves one watch-list file is materially blocking the
   completed packages or upcoming features. Otherwise update the plan with
   explicit deferrals, owner, risk, revisit trigger, and tests protecting the
   seam.

Forbidden shortcuts:

- No broad preload RPC, arbitrary channel strings, renderer privilege
  concessions, raw secret exposure, helper/native object exposure, compatibility
  shims, temporary adapters, or old upstream path preservation.
- No behavior changes hidden under file-shape work.
- No source package may change more than one primary owner seam unless the
  plan is reviewed again.
- Stop if a package needs new IPC/preload APIs, public contract expansion,
  dependency/build changes, packaging changes, or Windows/native proof.

Review gates:

- Read-only plan review before Package 1.
- Adjudicate every material plan finding before source edits.
- For each package: select one bounded unit, implement only that unit, run
  package verification, run implementation review, adjudicate findings, then
  commit or hand off.
- Do not start the next package while material review findings remain.

## Verification Commands

Plan-only verification:

```bash
npm run verify:docs
```

Expected outcome: docs verifier passes, including active-plan structure,
Architecture Health, Tier 3 handoff fields, and exactly one verification
classification marker.

Source package baseline commands:

```bash
npm run verify:maintainability
npm run typecheck
npm run verify:architecture
npm run verify:redaction
npm run verify
```

Expected outcome: all pass before package closeout unless a reviewed package
narrows the proof with a specific rationale. `npm run verify` remains required
before calling scaffold, IPC/security, contract, runtime, or implementation
work complete.

Package-specific commands:

- Package 1:
  `node --import tsx --test src/__tests__/main/player/nativePlayerHostProcess.test.ts`
  after typecheck/build, plus any new focused helper-protocol tests.
- Package 2:
  `node --import tsx --test src/__tests__/main/player/desktopPlayerAdapter.test.ts`
  and player public safety assertions after build/typecheck.
- Package 3:
  `node --import tsx --test src/__tests__/main/player/plexPlaybackRuntime.test.ts`
  and
  `node --import tsx --test src/__tests__/main/player/plexPlaybackLifecycleIntegration.test.ts`
  after build/typecheck.
- Package 4:
  `node --import tsx --test src/__tests__/integration/preloadContractVocabulary.test.ts`
  and `npm run smoke:electron`.
- Package 4S, only if Package 4 smoke proof is blocked by
  `ChannelScheduler requires an injected SchedulerClock`:
  `node --import tsx --test src/__tests__/main/channelComposition.test.ts`,
  `npm run smoke:electron`, and `npm run verify`.
- Package 4T, only if Package 4S clears scheduler construction and smoke then
  fails on stale guide/channel-setup/player smoke assertions:
  `npm run smoke:electron`, `npm run verify`, and focused source audit of
  `src/main/smokeAssertions.ts`.
- Package 4V, only if Package 4U proves the smoke window remains unfocused after
  a bounded app/window focus request:
  `npm run smoke:electron`, `npm run verify`, and focused source audit of
  `src/main/smokeFullscreenAssertions.ts`.
- Package 5:
  `node --import tsx --test src/__tests__/main/plexRuntimeIpc.test.ts` after
  build/typecheck, plus focused tests for extracted operation owners.
- Package 6:
  renderer tests for navigation, workflow, Plex runtime, channel runtime,
  support-bundle export, and EPG state after build/typecheck, plus
  `npm run smoke:electron`.
- Package 7:
  no source verification if audit-only; if promoted to source, use that
  watch-list owner's focused tests and full source package baseline commands.

## Acceptance Criteria

Program acceptance:

- Plan review is clean or all material findings are adjudicated and fixed.
- Every material hotspot from the brief is either repaired through a reviewed
  package or explicitly deferred by reviewed replan with owner, risk, proof,
  and revisit trigger.
- Each source package preserves public behavior and renderer/preload/main/helper
  privilege boundaries.
- At least Packages 1-6 complete, or a reviewed replan removes/defer a package
  because evidence proves it is no longer material.
- No package introduces dependencies, lockfile changes, packaging changes,
  public contract expansion, renderer privilege, raw secret exposure, or
  unreviewed guardrail baseline growth.
- `docs/architecture/file-shape-guardrails.md` remains accurate after source
  packages. Shrunk files may remove or lower guardrail rows only with observed
  line counts and review.
- Source verification commands for the implemented package were observed.
- Implementation review for each package is clean before continuing.

Per-package acceptance:

- Package 1: helper process transport behavior, private load serialization,
  duplicate request rejection, timeout/quarantine, malformed/oversized output,
  stderr dropping, cleanup/reap, lifecycle failure reporting, and diagnostics
  remain covered.
- Package 2: renderer intent dispatch, runtime command dispatch, duplicate
  request rejection, privileged load validation, host event validation,
  stale-event quarantine, cleanup, and snapshot/event output remain equivalent.
- Package 3: scheduler selection, request/epoch custody, PMS release for stop,
  switch, error, helper crash, teardown, rejected/stale sessions, and
  renderer-safe errors remain equivalent.
- Package 4: the single `window.lineupDesktop` bridge, approved channel
  constants, runtime guard behavior, listener cleanup, sandbox compatibility,
  and smoke containment remain equivalent.
- Package 4S: main/channel composition injects a stable scheduler clock into
  `ChannelScheduler` without changing channel runtime, guide behavior,
  renderer/preload APIs, scheduler domain policy, persistence schema, or Plex
  behavior; `npm run smoke:electron` reaches its normal preload/shell proof
  instead of failing on scheduler construction.
- Package 4T: smoke assertions prove current renderer route reachability,
  bridge containment, safe live guide/setup/player states, overlay/focus
  sanity, and preload bundling without requiring obsolete fake guide text,
  deleted fake setup controls, or brittle overlay rectangle non-overlap that is
  not part of the current architecture contract.
- Package 4V: fullscreen smoke still fails if a focused, fullscreen-capable
  smoke window does not enter fullscreen; only an observed inability to focus the
  smoke window may skip BrowserWindow transition proof while preserving renderer
  bridge envelope, route/focus, z-order, and non-fullscreen cleanup checks.
- Package 5: auth/profile/server/library results, operation abort/stale
  handling, snapshot mutation, token/connection custody, validation, and
  diagnostics remain equivalent.
- Package 6: initial render, route/focus/input/fullscreen behavior, player
  event binding, Plex/channel actions, guide polling freshness, support-bundle
  export, cleanup on unload, and smoke reachability remain equivalent.
- Package 7: every watch-list file has a reviewed keep/defer/follow-up decision
  with tests and guardrail triggers named.

## Replan Triggers

- Evidence contradicts `docs/architecture/CURRENT_STATE.md`,
  `docs/architecture/file-shape-guardrails.md`, this plan, or current source.
- A package cannot remain inside the named owner seam or files in scope.
- A repair requires new IPC/preload APIs, broad RPC, renderer privilege,
  token-bearing renderer state, raw Plex/native/helper data exposure, or public
  contract expansion.
- Dependency, package, lockfile, build-tool, packaging, signing, installer,
  update, native-helper redistribution, or media-binary changes become
  necessary.
- Behavior must change without stable public-seam proof.
- A hotspot must grow beyond reviewed baseline without a better decomposition.
- Tests fail for unrelated reasons or existing failures cannot be separated from
  the package.
- User or other agent changes overlap selected package files.
- Review finds material architecture, security, verification, or maintainability
  blockers.
- Windows/native manual proof becomes necessary to validate a package.

## Rollback Notes

- Each package should be a focused commit after clean implementation review.
- Roll back by reverting only the package commit and any package-specific test
  additions. Do not revert unrelated user changes.
- Do not delete local ignored evidence unless it was created by the failed
  package and is not needed for review.
- If a package updates `docs/architecture/file-shape-guardrails.md`, rollback
  must revert that row change with the source change.
- If a package unexpectedly touches import provenance, rollback must keep
  `docs/architecture/import-ledger.md` consistent with the resulting source
  state.

## Commit Checkpoints

- Plan authoring commit, if requested: `docs: add architecture repair hotspot plan`
- Package 1: `refactor: split native host process framing`
- Package 2: `refactor: split player adapter request custody`
- Package 3: `refactor: split plex playback cleanup custody`
- Package 4: `refactor: split preload bridge guard families`
- Package 5: `refactor: split plex runtime operation owners`
- Package 6: `refactor: split renderer bootstrap orchestration`
- Package 7 or final docs: `docs: record architecture repair closeout`

Keep workflow/control-plane docs separate from source package commits when
practical. Do not stage unrelated local changes.

## Repair Package Program

### Package 1: Native Host Process IO And Framing

Priority rationale: highest production-safety risk because helper process IO
owns private playback setup, failure normalization, and cleanup/reap behavior.

Owner seam: `NativePlayerHostProcess` remains the `NativePlayerHostPort`
facade. New modules may own protocol parsing/serialization and pending command
settlement, but they must not expose helper stdout/stderr, raw IPC frames,
native handles, private playback descriptors, raw URLs, or auth headers outside
main/helper setup.

Acceptance: current native host tests continue to prove in-memory and real
spawned helper doubles, duplicate request rejection, timeout, malformed output,
oversized output, stream errors, stderr redaction, cleanup/reap, late output
ignore, private playback serialization, and safe failure normalization.

Stop triggers: any new helper channel, helper protocol mode, public contract,
native binary/package change, or proof need beyond the existing injected helper
tests.

### Package 2: Desktop Player Adapter Request Custody

Priority rationale: blocks upcoming playback/control growth because the adapter
currently centralizes renderer mapping, runtime dispatch, snapshot mutation,
request identity, host event validation, stale-event quarantine, cleanup, and
diagnostics.

Owner seam: `DesktopPlayerAdapter` remains the facade used by player IPC and
runtime composition. New main/player owners may split request custody,
renderer-intent mapping, runtime load dispatch, host event projection, and
diagnostics. Renderer-facing `PlayerEvent`, `PlayerSnapshot`, and
`DesktopPlayerAdapterDispatchResult` shapes must not change.

Acceptance: adapter tests prove renderer command handling, production renderer
load rejection, privileged runtime load validation, duplicate request rejection,
host event validation, stale warning behavior, helper crash/lifecycle cleanup,
and redaction.

Stop triggers: need to change `src/contracts/player.ts`, preload API, player
IPC result shape, or native host port public shape.

### Package 3: Plex Playback Runtime Cleanup And Stale Custody

Priority rationale: production playback safety depends on PMS release, stale
async event quarantine, helper-crash cleanup, and request/epoch identity staying
reviewable before RD-26 media options or live playback growth.

Owner seam: `PlexPlaybackRuntime` remains the orchestrator facade. New
main/player owners may own cleanup orchestration, PMS release, stale-event
custody, and cleanup diagnostics. Scheduler, channel, player, and PMS ports
remain injected private main boundaries.

Acceptance: runtime and lifecycle tests prove stop/switch/error/logout/server
change/profile change/helper crash/teardown cleanup, rejected/stale PMS release,
mismatched lease rejection, unsafe candidate rejection, stale player event
quarantine, and renderer-safe diagnostics.

Stop triggers: need to change stream resolver public output, player contracts,
Plex contracts, preload APIs, or scheduler/channel domain behavior.

### Package 4: Preload Bridge Guard And Channel Families

Priority rationale: preload is the largest hotspot and the security boundary is
critical, but it should follow the main/player decompositions so no bridge
behavior is moving underneath it.

Owner seam: preload remains a single sandbox-compatible bridge exposing only
`window.lineupDesktop`. New preload-local modules may hold constants, guards,
and invoke/listener helpers by channel family. They must work in the existing
CommonJS/sandbox preload runtime and must not import main/runtime-only modules.

Acceptance: preload vocabulary tests prove channel constants, approved
`ipcRenderer` use, one bridge exposure, guard parity, forbidden-field rejection,
listener cleanup, and sandbox smoke containment.

Stop triggers: bundling breaks sandbox preload, a guard split needs raw Electron
objects in renderer, a new bridge namespace appears, or parity tests cannot
cover the split.

### Package 4S: Smoke Blocker Clock Injection

Priority rationale: Package 4 requires `npm run smoke:electron`, and current
smoke proof is blocked after successful preload bundling by
`ChannelScheduler requires an injected SchedulerClock`. Direct evidence points
to `src/main/channel/channelComposition.ts` constructing `new
ChannelScheduler()` without options while `ChannelScheduler` requires an
injected clock. This is a gate-restoration repair, not a new feature.

Owner seam: main/channel composition may own process-local scheduler clock
injection for the active guide scheduler. The scheduler domain requirement
remains unchanged, and channel runtime, guide runtime, renderer, preload,
Plex, persistence schema, player, package/dependency, and product behavior
must not expand.

Files in scope:

- `src/main/channel/channelComposition.ts`
- `src/__tests__/main/channelComposition.test.ts`

Acceptance: focused main/channel composition proof covers clock injection;
`npm run smoke:electron` no longer fails during channel composition scheduler
construction; `npm run verify` passes.

Stop triggers: the fix needs scheduler domain policy changes, persisted state
changes, renderer/preload/API changes, guide behavior changes, Plex/runtime
changes, package/dependency changes, or Windows/native proof.

### Package 4T: Smoke Assertion Realignment

Priority rationale: after Package 4S clears the scheduler-construction blocker,
`npm run smoke:electron` reaches renderer assertions and may fail on stale
fake-route expectations: fake guide detail text, fake guide grid data, absence
of old setup controls, or OSD/now-playing rectangle overlap. These assertions
can block Package 4 preload proof even when preload bundling and security
containment are intact.

Owner seam: `src/main/smokeAssertions.ts` owns Electron smoke proof
expectations. It may be realigned to current runtime-backed guide/setup/player
states only as proof maintenance. Renderer source, preload API, main runtime
composition, guide/channel behavior, player behavior, CSS layout, tests, and
product copy are out of scope unless a fresh reviewed replan promotes a real
product defect.

Files in scope:

- `src/main/smokeAssertions.ts`

Acceptance: `npm run smoke:electron` passes; `npm run verify` passes; the
smoke still proves shell URL/CSP, bridge containment, route reachability,
preload/player/diagnostics/Plex/channel bridge availability, guide/setup/player
safe-state rendering, overlay stack/focus basics, and containment counters.

Stop triggers: the failure requires renderer behavior, CSS layout, route DOM,
preload API, main runtime, scheduler/channel/Plex/player changes, or a new
smoke-only fixture; the smoke would stop proving a meaningful security or
route-reachability contract; or the assertion change would hide a real
renderer overlap/accessibility bug without separate proof.

### Package 4U: Fullscreen Smoke Transition Proof

Priority rationale: after Package 4T realigns stale renderer smoke assertions,
`npm run smoke:electron` may reach `src/main/smokeFullscreenAssertions.ts` and
fail on `fullscreen enter BrowserWindow state` even though the renderer bridge
returns the expected fullscreen result envelope. Package 4 acceptance still
needs smoke proof, but fullscreen transition polling is a smoke harness concern
unless fresh evidence shows the window controller or renderer fullscreen flow is
defective.

Owner seam: `src/main/smokeFullscreenAssertions.ts` owns fullscreen continuity
smoke proof. It may improve transition observation, diagnostics, or platform
fallback handling for smoke mode only. `src/main/window/shellWindowController.ts`,
renderer fullscreen dispatch, preload/window API, CSS layout, package/dependency
configuration, and product fullscreen behavior are out of scope unless reviewed
evidence promotes a real defect.

Files in scope:

- `src/main/smokeFullscreenAssertions.ts`

Acceptance: `npm run smoke:electron` passes; `npm run verify` passes; fullscreen
smoke still proves the renderer bridge returns expected fullscreen envelopes,
player route/focus continuity, presentation/screen/overlay z-order, and
restoration to non-fullscreen when Electron reports fullscreen support.

Stop triggers: the fix requires changing the window controller, renderer
fullscreen behavior, preload/window contracts, CSS, package/dependency settings,
or platform/runtime assumptions beyond smoke harness proof; or Electron reports
a deterministic product fullscreen failure rather than an unsupported or
unobservable smoke transition.

### Package 4V: Fullscreen Smoke Focus-Limited Fallback

Priority rationale: Package 4U retained the supported-window BrowserWindow
transition proof and added bounded focus attempts. In the current smoke run,
Electron reports the window as visible and fullscreenable but not focused even
after `app.focus({ steal: true })` and `window.focus()`, then never reports
fullscreen entry. This blocks Package 4 acceptance through an environment-limited
smoke observation failure, not through evidence of a window controller or
renderer fullscreen behavior regression.

Owner seam: `src/main/smokeFullscreenAssertions.ts` may distinguish focused
fullscreen transition failures from unfocused smoke-session limitations. It must
not change `src/main/window/shellWindowController.ts`, renderer fullscreen
dispatch, preload/window API, CSS, package/dependency configuration, or product
fullscreen behavior.

Files in scope:

- `src/main/smokeFullscreenAssertions.ts`

Acceptance: `npm run smoke:electron` passes; `npm run verify` passes; fullscreen
smoke still validates the renderer bridge returns expected fullscreen envelopes,
player route/focus continuity, presentation/screen/overlay z-order, and
non-fullscreen cleanup. A focused fullscreen-capable window that fails to enter
fullscreen must still fail smoke. An unfocused window may skip only the
BrowserWindow fullscreen transition proof after the harness records bounded
focus evidence.

Stop triggers: the smoke window becomes focused but still cannot enter
fullscreen; focus failure requires app/window creation, shell controller,
renderer, preload, CSS, package/dependency, or OS permission changes; or the
fallback would suppress route/focus/z-order/bridge envelope proof.

### Package 5: Desktop Plex Runtime Operation Owners

Priority rationale: Plex runtime now combines auth/profile/server/library
operations and operation abort/stale custody, which will block future Plex
flows if not split.

Owner seam: `DesktopPlexRuntime` remains the main-owned facade used by IPC and
stream resolver composition. New main/Plex owners may own operation custody,
server/profile orchestration, and library operations. Token, selected
connection, and transport custody remain main-owned and never reach renderer.

Acceptance: Plex runtime IPC tests prove auth, profile switch, server restore,
refresh/select, library sections/items/search/metadata, validation,
abort/stale handling, snapshot commits, diagnostics, and redaction.

Stop triggers: persistence schema change, selected-server format change, new
Plex IPC contract, live transport behavior change, or credential custody change.

### Package 6: Renderer Bootstrap And Action Registration

Priority rationale: renderer bootstrap is a cross-route orchestrator and will
grow with future workflows unless bridge subscriptions, guide polling, action
registration, and cleanup are split.

Owner seam: `src/renderer/index.ts` remains the renderer composition root.
New renderer-safe owners may initialize bridge subscriptions, register route
actions, manage guide polling freshness, and own unload cleanup. They must not
introduce browser storage, Node/Electron access, raw Plex/player data, or UI
behavior changes.

Acceptance: renderer tests and Electron smoke prove initial render, route
activation, focus, desktop input, fullscreen, player event binding, Plex/channel
actions, guide polling staleness, support-bundle export, and unload cleanup.

Stop triggers: UI behavior changes, test-only fake route preservation decisions,
new preload APIs, or privilege needs.

### Package 7: Watch-List Audit And Deferred Follow-Ups

Priority rationale: the brief requires every material hotspot to be covered,
but the watch-list files are either stable public contracts, pure domain owners,
or renderer sub-owners whose first action should be audit/deferral unless
earlier packages expose blocking coupling.

Owner seam decisions:

- `src/contracts/player.ts`: avoid source change unless a future contract family
  is added. Revisit before any new public player command/event/snapshot family.
- `src/main/plex/streamResolver.ts`: avoid source change unless Package 3 or a
  future stream mode needs resolver projection split. Revisit before live
  transport or additional stream modes grow it.
- `src/main/player/streamPolicy/desktopStreamPolicy.ts`: avoid source change
  until new codec/platform/track policy branches are planned.
- `src/domain/channel/channelManager.ts`: defer source split until live channel
  editing or backup/restore would grow mutation, current-channel, or
  persistence coordination.
- `src/domain/channel/channelRepository.ts`: defer source split until persisted
  channel editing, migration, or import normalization grows it.
- `src/renderer/epg.ts`: avoid source change unless Package 6 needs a guide
  state/polling/view boundary.
- `src/renderer/routeDom.ts`: avoid source change unless Package 6 exposes
  route render registration coupling.

Acceptance: final program closeout records a reviewed keep/defer/follow-up
decision for each watch-list owner, including current line count, tests
protecting it, and revisit trigger.

Package 7 closeout decisions, recorded 2026-06-11 after Packages 1-6:

| Watch-list owner | Current lines | Decision | Protecting verification | Revisit trigger |
| --- | ---: | --- | --- | --- |
| `src/contracts/player.ts` | 703 | Keep centralized. This is stable public renderer-safe contract vocabulary; splitting it without a new contract family would add churn without reducing runtime coupling. | `npm run verify`; `src/__tests__/contracts/contracts.test.ts` player contract/event/guard coverage. | Revisit before adding a new public player command, event, snapshot, error, or capability-profile family. |
| `src/main/plex/streamResolver.ts` | 660 | Defer split. Packages 3 and 5 did not require resolver projection changes, and the resolver remains a main-only private descriptor mapper. | `npm run verify`; `src/__tests__/main/plexStreamResolver.test.ts`; player/Plex playback runtime tests. | Revisit before adding additional stream modes, resolver policy branches, or playback descriptor variants. |
| `src/main/player/streamPolicy/desktopStreamPolicy.ts` | 624 | Defer split. The policy remains a deterministic fixture-proven decision owner, and no package added codec/platform/track policy behavior. | `npm run verify`; `src/__tests__/main/player/desktopStreamPolicy.test.ts`. | Revisit before adding codec families, platform capability matrices, subtitle/audio branches, or preferred-language policy. |
| `src/domain/channel/channelManager.ts` | 1022 | Defer split. It is a pure domain mutation/current-channel/persistence coordination owner; no repair package expanded channel domain behavior. | `npm run verify`; `src/__tests__/domain/channelManager.test.ts`; domain boundary verifier. | Revisit before live channel editing, backup/restore, or another persisted mutation workflow grows the owner. |
| `src/domain/channel/channelRepository.ts` | 770 | Defer split. It remains a pure domain import/source-resolution/cache owner; no package expanded import normalization or persistence schema behavior. | `npm run verify`; `src/__tests__/domain/channelRepository.test.ts`; domain boundary verifier. | Revisit before persisted channel editing, migrations, or import normalization grows this owner. |
| `src/renderer/epg.ts` | 725 | Defer split. Package 6 moved guide polling freshness out of the renderer root without changing EPG state/view math, so splitting EPG now would be unrelated behavior-neutral churn. | `npm run verify`; `src/__tests__/renderer/epg.test.ts`; `src/__tests__/renderer/epgStateUpdate.test.ts`; Electron smoke guide assertions. | Revisit before adding scheduler-backed guide state families, new guide route interactions, or additional presentation normalization behavior. |
| `src/renderer/routeDom.ts` | 511 | Defer split. Package 6 moved action registration and runtime subscriptions out of the root; route rendering remains only slightly over the guardrail and stable under existing route DOM tests. | `npm run verify`; `src/__tests__/renderer/routeDom.test.ts`; Electron smoke route assertions. | Revisit before adding route families, guide-specific render branches, or more route interaction rendering. |

## NEXT_SESSION_HANDOFF

NEXT_SESSION_LAUNCHER: `lineup-desktop-feature-quality-loop`

TASK: Architecture repair hotspot stabilization before next feature growth.

TASK_FAMILY: feature/design

TIER: Tier 3

PLAN: `docs/plans/architecture-repair-hotspot-stabilization.md`

ARTIFACT: `docs/plans/architecture-repair-hotspot-stabilization.md`

FILES: Packages 1-7 are implemented. If this handoff is resumed before final
closeout, inspect the latest git status, rerun final verification, adjudicate any
review findings, and then close/archive the plan per `docs/plans/README.md`
after durable conclusions are reflected in architecture and guardrail docs.

BLOCKERS: Do not restart completed packages. Replan only if final verification
or read-only closeout review finds a material ownership, behavior, security, or
documentation regression.

MESSAGE: This plan is in final closeout state. Verify the completed architecture
repair program rather than selecting a new implementation package.
