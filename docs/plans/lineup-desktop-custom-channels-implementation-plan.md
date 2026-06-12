# Lineup Desktop User-Created Custom Channels Implementation Plan

**Plan Status:** active

**Task family:** feature/design

**Branch:** `initial-build`

**Prepared:** 2026-06-12, America/New_York

**Route:** Tier 3 feature-quality loop. This feature crosses renderer UI, preload/IPC contracts, main-owned channel runtime, channel persistence, Plex library selection, scheduler/guide refresh behavior, and redaction-sensitive artwork handling.

**Controller note:** This file is intended as an implementation-ready durable plan. Before source edits, place it under `docs/plans/` or use it as the reviewed handoff artifact, run the required freshness checks, and send it through read-only plan review.

**Plan review note, 2026-06-12:** Package 0 review found this tracked plan
needed docs-verifier shape fixes before source edits. The revised plan keeps
Package 1 source scope to renderer-safe contracts and pure domain/persistence
modeling; `LineupDesktopPreloadApi`, IPC constants, and preload/main bridge
exposure move to Package 4 so each committed checkpoint remains buildable.

## Goal

Implement user-created custom channels for Lineup Desktop as a full desktop-first channel authoring workspace that builds on the existing RD-23/RD-24 channel setup, scheduler, and Plex runtime seams without weakening Electron security, renderer privilege limits, redaction policy, or maintainability guardrails.

The feature must let a user create, edit, duplicate, delete, hide/unhide, reorder, and review custom channels using Plex library content through a Plex-client-style media picker. The media picker must support library browsing, search, poster-card presentation, metadata preview, multi-select/selection-cart behavior, duplicate membership indication, and channel-specific scheduling options. It must feel appropriate for a desktop app rather than a TV remote-only flow, while preserving the existing keyboard/back/focus conventions already used by Lineup Desktop.

The implementation target is a full product feature, not another fake-backed setup screen. The implementation may land in multiple reviewed packages, but the package sequence must converge on this complete product shape:

1. **Custom channel workspace:** a reachable route/surface for saved channel management and authoring.
2. **Plex-client-style media picker:** safe browse/search/metadata/poster browsing for eligible Plex media.
3. **Selection cart and channel contents editor:** add/remove/reorder selected media and sources with inline duplicate status.
4. **Channel metadata editor:** number, name, description, color/icon/logo strategy, hidden status, and validation.
5. **Scheduling/order editor:** sequential, shuffle, random, block, sort/filter options, include-watched behavior, and start-anchor policy.
6. **Persistence and scheduler integration:** saved custom channels immediately feed guide/player scheduler state through existing main-owned channel persistence and guide runtime seams.
7. **Safe artwork handling:** poster UX without exposing Plex tokens, raw image keys, raw URLs, filesystem paths, or tokenized media/image URLs to renderer contracts, logs, diagnostics, tests, or tracked docs.
8. **Import/export and logo/customization roadmap:** production-safe design for later backup/import/logo work that avoids file path and secret leakage.

The primary user experience must address the specific pain points observed in comparable apps: keep add/remove actions near media results, show whether an item is already in the channel being edited, avoid bottom-corner-only actions for high-frequency tasks, keep selected-channel context visible while browsing/searching, and make save/replace/delete consequences explicit.

## Non-Goals

The first implementation packages must not add these behaviors unless a reviewed replan explicitly narrows and authorizes them:

- No cloud sync, cloud backup, telemetry, analytics, or Lineup-hosted backend.
- No external service support beyond the current Plex runtime. Emby/Jellyfin-style UX research is reference only.
- No native-helper, libmpv, stream resolver, or playback engine changes except for existing guide/player refresh hooks that respond to channel mutations.
- No raw Plex tokens, raw auth headers, tokenized URLs, selected connection URIs, raw Plex payloads, raw image keys, native handles, Electron APIs, Node APIs, or filesystem paths in renderer-facing contracts.
- No custom user logo file import in the first authoring package. Logo import requires a later main-owned file import/cache plan with app-path, redaction, and backup semantics. The first package may provide built-in color/icon/initials choices and a future-ready contract field that does not expose a path.
- No broad dependency addition. Use existing DOM, TypeScript, CSS, Electron protocol, and repo test tooling unless a reviewed dependency request names owner, reason, lockfile impact, license/provenance risk, security posture, rollback trigger, and verification.
- No copying code from QuasiTV, NostalgiaTV, Jellyfin, Plex, ErsatzTV, PlexKodiConnect, or other reference projects. Treat them as UX/product research unless a separate import-ledger and license review authorizes specific copied/adapted code.
- No compatibility barrels, old upstream path mirrors, broad RPC bridges, untyped arbitrary IPC channel names, renderer filesystem/browser-storage ownership, or temporary adapters without a named owner and removal trigger.
- No public release/signing/update/installer work.

## Parent Architecture Alignment

This work must preserve the current Lineup Desktop architecture boundaries:

- **Renderer remains unprivileged.** It owns presentation, ephemeral draft state, selection affordances, focus, keyboard/mouse behavior, and renderer-safe view models only. It must not import Electron, Node, main, preload, native-helper, Plex transport, persistence adapters, or token-bearing values.
- **Preload remains a narrow validated bridge.** Add only named, typed, operation-specific custom-channel bridge methods. Do not expose a generic RPC method, arbitrary channel strings, raw payload passthrough, or unvalidated event listeners.
- **Electron main owns privileged channel operations.** Main owns persistence, app paths, selected-server/Plex runtime custody, custom-channel mutation serialization, artwork proxy/cache, diagnostics redaction, scheduler refresh triggers, and IPC authorization.
- **Domain owners remain pure.** `src/domain/channel/**` and `src/domain/scheduler/**` must stay free of Electron, Node, browser globals, raw Plex transport, raw Plex payloads, tokenized URLs, renderer state, and native playback details.
- **Contracts own renderer-safe public shapes.** Custom-channel contracts must contain one public shape per operation, explicit literal unions, bounded strings/counts, safe opaque IDs, and recursive forbidden-field tests.
- **Plex runtime remains main-owned.** Custom channel media picking may reuse existing main-owned Plex library operations, but renderer-facing data must stay sanitized and must not introduce transport policy into renderer code.
- **Artwork requires a privileged proxy seam.** Normal Plex-client-style poster UX is allowed only through a main-owned safe artwork reference/protocol/cache. Renderer must never receive Plex image keys, remote image URLs, tokenized image URLs, filesystem paths, or auth-bearing request data.
- **Local-first product invariant remains unchanged.** Custom channels are local persisted configuration for the selected Plex account/server/profile. No cloud dependency is introduced.

The feature advances the existing channel setup route from “build channels from selected library sections” into a proper authoring workspace. It must not preserve fake setup controls in reachable product paths once their real replacement is implemented.

## Required Reading

Read these in order before source edits:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/plan-authoring-standard.md`
4. `docs/architecture/CURRENT_STATE.md`
5. `docs/architecture/renderer-architecture.md`
6. `docs/architecture/security-and-secret-flow.md`
7. `docs/architecture/file-shape-guardrails.md`
8. `docs/architecture/import-ledger.md`
9. `docs/roadmap/desktop-port-roadmap.md`
10. Current source owners:
    - `src/contracts/channel.ts`
    - `src/contracts/plex.ts`
    - `src/contracts/ipc.ts`
    - `src/contracts/shell.ts`
    - `src/domain/channel/**`
    - `src/domain/scheduler/**`
    - `src/main/channel/**`
    - `src/main/persistence/desktopChannelPersistenceStore.ts`
    - `src/preload/channelSetupBridge.cts`
    - `src/preload/channelBridgeGuards.cts`
    - `src/preload/channels.cts`
    - `src/preload/index.cts`
    - `src/renderer/channelSetup/**`
    - `src/renderer/plexRuntime*.ts`
    - `src/renderer/staticDom.ts`
    - `src/renderer/domBindings.ts`
    - `src/renderer/focusDom.ts`
    - `src/renderer/routeDom.ts`
    - `src/renderer/workflow.ts`
    - `src/renderer/styles/*`
11. Existing tests that protect the surface:
    - `src/__tests__/contracts/**`
    - `src/__tests__/domain/channelDomain.test.ts`
    - `src/__tests__/domain/channelPersistence.test.ts`
    - `src/__tests__/domain/schedulerDomain.test.ts`
    - `src/__tests__/main/channelRuntimeIpc.test.ts`
    - `src/__tests__/main/channelComposition.test.ts`
    - `src/__tests__/main/guideRuntime.test.ts`
    - `src/__tests__/renderer/channelSetupLiveSelection.test.ts`
    - `src/__tests__/renderer/plexRuntime.test.ts`
    - `src/__tests__/renderer/rendererRuntimeOwners.test.ts`
    - `src/__tests__/integration/preloadContractVocabulary.test.ts`

Freshness gate: if any of the listed files materially changed after this plan was written, update this plan or send it back through review before editing. Do not continue through contradicted assumptions.

## Required Skills

Use these project skills and make their constraints visible during implementation:

- `lineup-desktop-feature-quality-loop`: this is Tier 3 cross-boundary feature work and needs plan review, bounded implementation units, implementation review, verification, and closeout.
- `execution-plan-authoring`: the implementation must follow this plan’s seam, scope, verification, acceptance, rollback, and replan decisions.
- `architecture-boundaries`: the feature changes contracts, preload, main, renderer, persistence, and scheduler integration. Keep one owner per concern and reject broad RPC/renderer privilege shortcuts.
- `persistence-boundaries`: custom channel data is persisted local app state. Main owns app paths/files, schema migration, temp-file writes, corruption recovery, and renderer-safe summaries.
- `plex-integration-boundaries`: media browsing, metadata, and artwork originate in Plex, but Plex transport, tokens, selected connections, raw payloads, and image keys stay in main custody.
- `ui-composition-patterns`: renderer authoring UI must keep focus, keyboard/mouse/back behavior, reduced-motion, accessibility, timers, subscriptions, and cleanup explicit.
- `verification-strategy`: use new public-seam tests where behavior/contracts change and add manual/visual proof for layout/focus/artwork interactions.
- `review-request` and `review-adjudication`: use read-only review before implementation and before closeout; adjudicate findings before editing.
- `closeout-verification`: no completion claim without observed command output and recorded manual/visual proof where automation cannot prove the behavior.

## Evidence And Discovery

### Repo evidence

- `README.md` states the repo is a Windows-first Electron version of Lineup and directs future work to `AGENTS.md` and `docs/AGENTIC_DEV_WORKFLOW.md` before changes.
- `AGENTS.md` and the workflow runbook require serious feature/design work to use the feature-quality loop, exact verification routing, read-only adversarial review for Tier 3 boundaries, and observed evidence before closeout.
- `docs/agentic/plan-authoring-standard.md` requires active serious plans to declare task family, include exact required sections, include Architecture Health for Tier 3 work, and be decision-complete at seam/scope/verification level.
- `docs/architecture/CURRENT_STATE.md` records RD-23 live channel setup/runtime persistence and RD-24 scheduler-backed guide/player channel runtime as current completed code surfaces. Existing channel setup can already commit selected movie/show library sections into persisted channels; this plan extends that surface into full custom channel authoring instead of replacing the channel/scheduler foundation.
- `src/contracts/channel.ts` currently exposes only `getStatus` and `commit` for section-based channel setup. Its commit payload is intentionally narrow: mode, section IDs, and replacement confirmation.
- `src/domain/channel/types.ts` already contains a richer channel model than the current UI exposes: playback modes, build strategies, library/show/collection/playlist/manual/mixed content sources, channel numbers, names, descriptions, colors/icons, content filters, sort orders, block sizes, and persisted stored channel data.
- `src/main/channel/channelRuntime.ts` currently serializes channel commits, validates selected library sections from the Plex snapshot, probes initial content counts through the main-owned Plex runtime, writes through the channel repository, and summarizes persisted state for renderer.
- `src/preload/channelBridgeGuards.cts` validates channel setup requests/results and blocks forbidden fields and secret-shaped strings. Custom-channel APIs must provide equivalent or stronger guards.
- `src/renderer/plexRuntimeRows.ts` already renders Plex library sections, item rows, and metadata preview, but it is text-list oriented and intentionally lacks poster/image support.
- `src/contracts/plex.ts` currently forbids image-key material such as `thumb`, `art`, `banner`, `clearLogo`, `url`, and `uri` in renderer summaries. Poster UX therefore requires a new safe artwork proxy design rather than simply exposing Plex image fields.
- `src/renderer/channelSetup/viewModel.ts` explicitly tells users that individual media items only open metadata preview and do not create channels. This must change for custom channels: selected media items must be addable to the channel draft and show duplicate membership state.

### External product and UX research

- QuasiTV positions itself as a Plex/Emby/Jellyfin-backed “live TV” app for Android TV/Fire TV. Its public image gallery shows separate surfaces for channel guide, player view, channel creator, and search. The channel creator screenshot shows a persistent channel list plus action row and content tiles, which supports the decision to keep channel context visible while browsing.
- QuasiTV’s backup/restore post notes that channels are effectively lists of show/movie IDs and warns that restored channels only match the same server identity state. Production implication: Lineup Desktop custom-channel persistence must treat Plex rating keys as server/profile-scoped identifiers, handle missing/stale content, and document import/backup caveats before exposing backup/restore as a user-facing feature.
- NostalgiaTV’s public Reddit release thread describes a Plex-backed virtual cable lineup with automatic channels, EPG/channel surfing, and optional power-user features including custom channel config, logos, sorting methods, commercials, import/export, and web interface control. Production implication: those are useful feature targets, but advanced customization should be staged behind the safe core authoring workflow.
- The same Reddit thread contains a user critique of QuasiTV custom-channel editing: the add button being far from the title/search area creates friction, and the UI should show whether a title is already in the channel being edited. Production implication: Lineup Desktop must put add/remove controls inline on media result cards and maintain visible membership badges/counts.
- Open-source media-client repository searches found public media browsing references such as `jellyfin/jellyfin-web`, `jellyfin/jellyfin-vue`, `plexinc/plex-media-player` (archived), and `croneter/PlexKodiConnect`. Treat these as reference points for media browsing patterns, not as import targets. The implementation should prefer repo-native DOM/CSS and existing Plex runtime contracts over adopting another client’s architecture.

### Discovery fallback notes

- Original plan discovery recorded Codanna as unavailable and used direct GitHub connector reads, repository file search, branch/file reads, and external web research.
- Package 0 refresh on 2026-06-12 found Codanna available with an index created and updated the same day. Codanna semantic search was too noisy for the new custom-channel concepts, so implementation discovery fell back to direct reads and `rg` for the exact source owners named by this plan.
- GitHub repository search results for some external projects were metadata-level only. Do not claim detailed implementation patterns from those repositories without a later direct source read and license/provenance review.
- The user’s prose mentioned branch `ininital-build`, but the repo field and actual accessible branch are `initial-build`. Use `initial-build` unless the user explicitly corrects this.

## Impact Snapshot

### Owners expected to change

- `src/contracts/*`: custom-channel and artwork-safe renderer contracts, IPC constants, shell bridge shape, channel setup result vocabulary.
- `src/domain/channel/**`: channel draft-to-domain mapping, optional manual item metadata expansion, content source validation, update/delete/duplicate/reorder/hide behavior if not already covered.
- `src/main/channel/**`: custom-channel runtime, media picker projection, channel mutation serialization, scheduler refresh hooks, diagnostics redaction, and IPC handlers.
- `src/main/persistence/desktopChannelPersistenceStore.ts`: only if persisted schema versioning/migration needs updates for new fields. Prefer domain codec/schema changes before adapter changes.
- `src/main/plex/**`: only focused additions needed for artwork proxy source mapping or media-card projection; do not alter auth/discovery transport policy unless re-reviewed.
- `src/main/artwork/**` or `src/main/channel/artworkProxy*`: new main-owned safe artwork proxy/cache owner if poster cards are implemented.
- `src/preload/**`: new narrow custom-channel bridge and guards, channel constants, single `window.lineupDesktop` exposure extension.
- `src/renderer/customChannels/**`: new renderer-owned authoring workspace modules.
- Existing renderer wiring files: `staticDom.ts`, `domBindings.ts`, `routeDom.ts`, `workflow.ts`, `rendererActionRegistration.ts`, `focusDom.ts`, `styles.css` or focused CSS modules. These should receive only wiring/host changes, not feature policy.
- Tests under `src/__tests__/**`, tools tests only if verifier/architecture rules need updates.
- Docs: active plan, `CURRENT_STATE.md`, `renderer-architecture.md`, `desktop-port-roadmap.md` if this becomes a roadmap item, and `import-ledger.md` only if source is copied/adapted.

### Public contracts expected to change

Add a new renderer-safe custom-channel contract instead of overloading the existing section-only `ChannelSetupCommitRequest`:

- `src/contracts/customChannels.ts` should own:
  - operation literals
  - request/result envelopes
  - draft input shapes
  - channel mutation payloads
  - media picker query payloads
  - media card summaries
  - membership and validation summaries
  - safe error taxonomy
  - forbidden-field checks
- `src/contracts/artwork.ts` should own safe opaque artwork references if poster UX is included in the package.
- `src/contracts/ipc.ts` should add only named channel constants for each operation. Do not add arbitrary dynamic channel names.
- `src/contracts/shell.ts` should expose `window.lineupDesktop.customChannels` or a focused `channelSetup.custom` namespace with typed methods. Prefer a separate `customChannels` namespace to keep legacy section setup from becoming a broad mixed owner.

### Persistence and schema impact

The existing domain `StoredChannelData` stores `ChannelConfig[]`, channel order, current channel ID, and saved time. Custom channels should persist through this same store when possible. Required persistence decisions:

- Keep persisted content source data renderer-safe and server/profile-scoped.
- Store Plex rating keys only as opaque Plex item identifiers; do not store image keys, image URLs, server URLs, connection URIs, tokens, headers, raw payloads, or file paths.
- For manual item selections, persist the minimum scheduler-required snapshot: `ratingKey`, title, duration, and only additional renderer-safe metadata if required for stable scheduling or recovery. Do not persist poster references.
- Add a schema migration only if new persisted fields cannot be represented by current `ChannelConfig`/`ChannelContentSource` shapes. If a migration is needed, add deterministic tests for old version load, corrupt data, unsupported schema, and repair/fallback behavior.
- Hidden channel state can be represented as a safe channel field only after the domain and scheduler decide whether hidden means “not shown in guide but still persisted” or “excluded from schedule.” This plan chooses **hidden means excluded from guide/channel surfing by default but preserved in persisted channel data**. The scheduler/guide must not schedule hidden channels unless an explicit future setting says otherwise.

### Dependency, build-tool, configuration, and lockfile impact

- No dependency, build tool, or package script change is expected for the core feature.
- Poster rendering must use native DOM/CSS and main-owned protocol/cache support, not a new image library, virtualized-list dependency, drag/drop dependency, or state-management framework.
- If an implementation package proves a dependency is necessary, stop and replan with dependency owner, reason, alternatives, lockfile impact, license/provenance, security posture, rollback trigger, and verification.

### User-visible behavior that must not regress

- Existing Plex sign-in, profile switching, server restore/selection, library browse/search/metadata preview, and sanitized failure states.
- Existing channel setup status recovery, append/replace confirmation semantics, guide presentation, player channel tuning, now-playing, mini-guide, channel badge, and player overlay state.
- Existing renderer focus/back behavior, text-entry bypass, desktop input handling, cursor behavior, fullscreen bridge behavior, reduced-motion and forced-colors policies.
- Existing secret redaction and support bundle behavior.
- Existing `npm run verify` and `smoke:electron` surfaces.

### Local-only artifacts that must stay untracked

- `docs/runs/custom-channels-*` manual proof, screenshots, smoke logs, private library names, private server names, account data, and visual evidence.
- Any generated poster/artwork caches under app data or temporary directories.
- Generated Electron build output, packaged output, and local caches.

## Files In Scope

The exact files may be refined during Package 0 plan review, but implementation must stay within these owners unless a replan expands scope.

### Plan and docs

- `docs/plans/<date>-custom-channels-plan.md` or this downloaded file as the reviewed artifact
- `docs/architecture/CURRENT_STATE.md`
- `docs/architecture/renderer-architecture.md`
- `docs/architecture/file-shape-guardrails.md` only if owner hotspots or allowlist notes change
- `docs/architecture/import-ledger.md` only when copied/adapted source lands
- `docs/roadmap/desktop-port-roadmap.md` if this is promoted into the tracked roadmap sequence
- `docs/development/windows-ui-proof-plan.md` only if a new reusable manual proof matrix is added

### Contracts

- `src/contracts/customChannels.ts` new
- `src/contracts/artwork.ts` new, if poster-card artwork lands in the package
- `src/contracts/channel.ts` focused additions only if shared channel summary vocabulary should remain there
- `src/contracts/plex.ts` focused additions only for safe media-card/artwork-reference projection, not raw image fields
- `src/contracts/ipc.ts`
- `src/contracts/shell.ts`
- `src/contracts/redaction.ts` only if new safe/forbidden vocabulary requires a shared update

### Domain

- `src/domain/channel/types.ts`
- `src/domain/channel/channelAuthoringService.ts`
- `src/domain/channel/channelContentSourceValidator.ts`
- `src/domain/channel/channelValueValidators.ts`
- `src/domain/channel/storedChannelDataCodec.ts`
- `src/domain/channel/channelRepository.ts`
- New focused files under `src/domain/channel/`, for example:
  - `customChannelDraft.ts`
  - `customChannelMutation.ts`
  - `channelVisibility.ts`
  - `customChannelContentMapping.ts`
- `src/domain/scheduler/**` only for hidden-channel exclusion or schedule invalidation semantics that cannot be handled in main guide runtime

### Main

- `src/main/channel/channelRuntime.ts` only for compatibility or delegation to the new runtime
- `src/main/channel/channelIpc.ts` only if shared setup registration remains there; prefer splitting custom-channel IPC into a focused file
- `src/main/channel/channelComposition.ts`
- New focused files under `src/main/channel/`, for example:
  - `customChannelRuntime.ts`
  - `customChannelIpc.ts`
  - `customChannelRequestValidation.ts`
  - `customChannelMediaPicker.ts`
  - `customChannelMutationMapper.ts`
  - `customChannelDiagnostics.ts`
  - `customChannelSchedulerRefresh.ts`
- `src/main/channel/plexLibraryMinimalAdapter.ts` only if existing library adapter needs safe custom-channel item resolution
- `src/main/persistence/desktopChannelPersistenceStore.ts` only if schema storage behavior changes
- New focused files under `src/main/artwork/` or `src/main/channel/artwork/`, for example:
  - `artworkProxy.ts`
  - `artworkCache.ts`
  - `artworkProtocol.ts`
  - `plexArtworkResolver.ts`
- `src/main/protocol.ts` only if registering the safe app-origin artwork route there is the repo-preferred owner
- `src/main/index.ts` only for composition wiring

### Preload

- `src/preload/channels.cts`
- `src/preload/index.cts`
- `src/preload/channelBridgeGuards.cts` only if shared helpers are reused
- New focused files:
  - `src/preload/customChannelBridge.cts`
  - `src/preload/customChannelBridgeGuards.cts`
  - `src/preload/artworkBridge.cts` only if an explicit bridge method is needed beyond app-origin image loading

### Renderer

- New focused directory `src/renderer/customChannels/**`, for example:
  - `state.ts`
  - `actions.ts`
  - `viewModel.ts`
  - `dom.ts`
  - `mediaPickerState.ts`
  - `mediaPickerViewModel.ts`
  - `selectionCart.ts`
  - `channelList.ts`
  - `channelEditor.ts`
  - `focus.ts`
  - `validation.ts`
- Existing wiring files:
  - `src/renderer/staticDom.ts`
  - `src/renderer/domBindings.ts`
  - `src/renderer/routeDom.ts`
  - `src/renderer/workflow.ts`
  - `src/renderer/settingsSetup.ts` only if existing route wrapper delegates to custom workspace
  - `src/renderer/rendererActionRegistration.ts`
  - `src/renderer/focusDom.ts`
  - `src/renderer/navigation.ts`
  - `src/renderer/plexRuntimeActionDispatch.ts` only if custom media picker reuses existing Plex actions
  - `src/renderer/styles/custom-channels.css` new
  - `src/renderer/styles/workflow-screens.css` and `src/renderer/styles/responsive-accessibility.css` focused additions only

### Tests

- `src/__tests__/contracts/customChannelContracts.test.ts` new
- `src/__tests__/contracts/artworkContracts.test.ts` new if artwork contract lands
- `src/__tests__/domain/customChannelAuthoring.test.ts` new
- `src/__tests__/domain/channelPersistence.test.ts` updates for schema/visibility/mutations
- `src/__tests__/main/customChannelRuntime.test.ts` new
- `src/__tests__/main/customChannelIpc.test.ts` new
- `src/__tests__/main/artworkProxy.test.ts` new if artwork proxy lands
- `src/__tests__/main/channelComposition.test.ts` focused composition updates
- `src/__tests__/preload/customChannelBridge.test.ts` new if preload tests exist by pattern; otherwise include in integration parity test
- `src/__tests__/integration/preloadContractVocabulary.test.ts` update for new channels/guards/bridge exposure
- `src/__tests__/renderer/customChannels*.test.ts` new view-model/action/focus tests
- `src/__tests__/renderer/rendererRuntimeOwners.test.ts` update if renderer ownership assertions need new allowed files
- `tools/__tests__/verify-redaction.test.mjs` only if redaction scanner vocabulary is intentionally updated for safe app-origin artwork IDs
- `tools/__tests__/verify-maintainability.test.mjs` only if file-shape rules need a new owner rule

## Files Out Of Scope

These files and surfaces must remain out of scope unless a reviewed replan changes the architecture seam:

- `src/native-helper/**`
- `src/main/player/desktopPlayerAdapter.ts`
- `src/main/player/nativePlayerHostProcess.ts`
- `src/main/player/nativeHelperProtocol*.ts`
- `src/main/player/productionNativeHostFactory.ts`
- `src/main/player/streamPolicy/**` except read-only reference
- `src/main/plex/auth/**` except read-only reference
- `src/main/plex/discovery/**` except read-only reference
- `src/main/plex/livePlexTransport.ts` except read-only reference
- Packaging, signing, installer, update, release, and native media redistribution files
- `package.json` and `package-lock.json`, unless a reviewed dependency/build-tool replan authorizes the change
- Existing diagnostics support-bundle internals except focused redaction event vocabulary if new safe operations must be reported
- Electron security shell policy files except a focused safe artwork protocol registration if explicitly approved
- Any unrelated cleanup, formatting sweeps, route redesign, or broad CSS rewrite

## Planner Self-Check

1. **Is any product, architecture, ownership, dependency, or verification decision still unresolved?**  
   No for the core implementation path. The plan chooses a main-owned custom-channel runtime, separate custom-channel contract, narrow preload bridge, unprivileged renderer workspace, no new dependency, and public-seam tests plus manual/visual proof. Optional later file-based logo import and import/export are intentionally staged and require their own package gates.

2. **Does the plan depend on adjacent files needing contract or type changes that are not in scope?**  
   No. The scope includes the required contract, preload, main, renderer, domain, persistence, and test owners. Player/native-helper changes are explicitly out of scope.

3. **Did the plan freeze any file out of scope while still relying on hidden wiring inside it?**  
   No. The plan relies on existing guide/player refresh seams through channel composition and guide runtime, which are in scope. Native playback internals are not needed for authoring.

4. **Did the plan record the evidence path and fallback reads?**  
   Yes. Discovery used direct repo reads, GitHub repository search metadata, QuasiTV official pages, and the NostalgiaTV Reddit release thread as community/product context. The Package 0 refresh also records that Codanna was available but too noisy for this new custom-channel surface, so direct source reads and `rg` remained the implementation evidence path.

5. **Is the work assigned to the repo-preferred owner, or is it growing a hotspot?**  
   The plan assigns new behavior to focused custom-channel and artwork owners instead of growing `index.ts`, `staticDom.ts`, `channelRuntime.ts`, `channelIpc.ts`, or broad CSS files into hotspots. Composition roots receive wiring only.

6. **Did Tier 3 work include Architecture Health evidence and a decomposition/avoidance decision for owner hotspots?**  
   Yes. See `## Architecture Health`. The plan avoids existing hotspots through new focused files, maintainability verification, and replan triggers for file-shape threshold violations.

7. **Would a fresh implementer need to invent security, IPC, playback, persistence, packaging, import, or verification policy?**  
   No. The seam, forbidden shortcuts, data-contract rules, redaction rules, persistence owner, verification commands, and review gates are explicit. Playback and packaging are excluded.

8. **Did the plan record exact verification commands, expected outcomes, and explicit stop/replan triggers?**  
   Yes. See `## Verification Commands` and `## Replan Triggers`.

## Architecture Health

This feature is high risk for hotspot growth because it can tempt implementers to keep adding UI, validation, browse/search state, mutation logic, and result rendering into existing composition owners. The required decomposition is:

File-shape evidence comes from `docs/architecture/file-shape-guardrails.md`.
Package 1 may touch allowlisted `src/domain/channel/channelAuthoringService.ts`
and `src/domain/channel/channelRepository.ts`; it must avoid growing those
owners with custom-channel policy beyond narrow field preservation and existing
validation hooks. Package 1 must prefer new focused files such as
`src/contracts/customChannels.ts` and `src/domain/channel/customChannelDraft.ts`
for authoring vocabulary and mapping. Later packages must keep allowlisted
`src/preload/index.cts`, `src/renderer/index.ts`, `src/renderer/routeDom.ts`,
and existing CSS hotspots to wiring/imports only.

Decision: avoid hotspot growth in Package 1 by adding new focused contract and
domain files, splitting draft mapping out of existing channel owners, and
keeping any changes to allowlisted files to explicit type/export/field
preservation only. No new allowlist row is approved by this plan.

- Keep `src/renderer/index.ts` as orchestration only. It may instantiate the custom-channel controller and pass state into render functions, but it must not own media picker policy, cart mutation policy, save validation, artwork policy, or channel mutation mapping.
- Keep `src/renderer/staticDom.ts` and `src/renderer/domBindings.ts` as static host/binding owners only. Add semantic containers and selectors, not feature logic.
- Keep `src/renderer/styles.css` as an import/composition stylesheet. Add `src/renderer/styles/custom-channels.css` for custom channel rules instead of placing a large rule block in the root stylesheet.
- Keep `src/main/index.ts` as composition wiring. It may register the new main runtime/IPC/artwork service but must not contain channel authoring logic.
- Keep `src/main/channel/channelRuntime.ts` compatible with current section-based setup, but move full custom-channel mutation policy into `customChannelRuntime.ts` or another focused owner.
- Keep `src/main/channel/channelIpc.ts` from becoming a broad multipurpose IPC owner. Add `customChannelIpc.ts` unless review finds a tiny extension safer.
- Keep `src/preload/index.cts` single-exposure compatible. It should import/build a new focused custom-channel bridge and expose it under the existing `window.lineupDesktop` object.
- Keep `src/contracts/channel.ts` from becoming a catch-all. Prefer `src/contracts/customChannels.ts` for authoring vocabulary and `src/contracts/artwork.ts` for safe artwork references.
- Keep `src/domain/channel/types.ts` changes minimal. If new type expansion becomes large, add focused domain files and re-export them from `src/domain/channel/index.ts`.

Before the first source package, run or inspect the current maintainability baseline:

```sh
git status --short --branch
npm run verify:maintainability
```

Expected outcome: worktree state is understood before edits, and maintainability either passes or the failure is recorded as a blocker before implementation. Do not raise file-shape baselines to pre-authorize feature growth. If any touched production file crosses the repo’s guardrail threshold, split the owner before continuing or record a reviewed temporary allowlist with owner, reason, verification, and removal trigger.

## Architecture Seam Decision Gate

### Chosen seam

Implement custom channels as a new **main-owned custom channel authoring runtime** behind a **narrow preload bridge** and **renderer-safe custom-channel contracts**. Renderer owns the authoring UI and ephemeral draft state; main owns validation, persistence mutation, Plex-backed item verification, artwork proxy/cache, scheduler refresh, and redacted diagnostics.

Use these public seams:

- `window.lineupDesktop.customChannels.getSnapshot()` returns saved channel summaries, editable channel detail for the selected channel, draft validation state, and safe capability flags.
- `window.lineupDesktop.customChannels.listMedia(input)` returns paginated safe media cards for a library/search/source query.
- `window.lineupDesktop.customChannels.getMediaMetadata(input)` returns safe metadata preview for a rating key.
- `window.lineupDesktop.customChannels.createDraft(input)` or renderer-local draft initialization creates an unsaved draft from a source selection. Prefer renderer-local draft creation when no main data is needed.
- `window.lineupDesktop.customChannels.validateDraft(input)` validates a draft in main against persisted channel numbers, source access, max counts, and content-source rules without saving.
- `window.lineupDesktop.customChannels.saveDraft(input)` creates or updates one channel through the main runtime and returns updated summary/snapshot.
- `window.lineupDesktop.customChannels.duplicateChannel(input)` duplicates an existing channel into a new draft or persisted copy, depending on UX decision. This plan chooses **duplicate into draft first**, then require Save.
- `window.lineupDesktop.customChannels.deleteChannel(input)` deletes after explicit confirmation.
- `window.lineupDesktop.customChannels.reorderChannels(input)` persists channel order.
- `window.lineupDesktop.customChannels.setChannelVisibility(input)` hides/unhides without deleting.

Do not overload the existing `channelSetup.commit({ mode, sectionIds })` for arbitrary media, delete, reorder, visibility, or editor state. Keep that API for the initial section-based setup path until a later cleanup/replacement plan deprecates it.

### Safe artwork seam

Poster-card UX requires one of these approved safe designs:

1. **Preferred:** Main registers a safe app-origin artwork protocol route, for example `lineup://artwork/<opaqueArtworkId>`, where `opaqueArtworkId` maps in main memory/cache to a Plex image request. Renderer receives an `ArtworkRef` with an opaque ID and alt text, then renderer-local view-model code constructs the app-origin image source. Main enforces authorization, token/header custody, response size limits, content-type allowlist, cache TTL, and redacted diagnostics.
2. **Allowed fallback:** If protocol routing proves too risky in the current shell, renderer uses placeholder poster cards and text metadata while the artwork proxy is deferred to a separately reviewed package. Do not expose raw Plex `thumb`, `art`, image keys, or URLs as a shortcut.

The preferred design must include cache invalidation on sign-out, server switch, profile switch, and app shutdown where appropriate. Artwork cache paths must stay main-owned and must never appear in renderer results, diagnostics, tests, tracked docs, or support bundles.

### Forbidden shortcuts

Stop immediately and replan if implementation appears to require any of the following:

- Renderer receives or stores raw Plex tokens, auth headers, tokenized URLs, selected connection URIs, image keys, raw payloads, app paths, file paths, native handles, Electron APIs, Node APIs, or arbitrary IPC channel names.
- Preload exposes a generic `invoke(channel, payload)` or accepts arbitrary user-provided channel strings.
- Main returns raw Plex library items where policy is undecided instead of renderer-safe media cards.
- Poster support bypasses the artwork proxy by sending Plex `thumb`, `art`, `url`, `uri`, or tokenized image strings to renderer.
- Draft state is persisted in browser storage or renderer-owned files.
- Custom logo import reads local files from renderer or returns local paths to renderer.
- Mutation APIs write partial channel data outside the serialized main runtime path.
- Hidden channels are silently dropped instead of preserved with explicit visibility semantics.
- Deleting/replacing channels occurs without explicit confirmation and an undo/rollback story.
- The implementation adds broad CSS/DOM rewrites, compatibility shims, or unrelated cleanup.

## Verification Commands

Verification classification: `new regression/contract test required`

Run these commands with the Node version pinned by `.nvmrc`. Record observed output before claiming completion.

### Before implementation

```sh
git status --short --branch
npm ci
npm run verify:maintainability
```

Expected outcome: branch and pre-existing changes are known; dependencies install from the lockfile; maintainability baseline passes or a blocker is recorded before edits.

### After contract/domain packages

```sh
npm run typecheck
node --import tsx --test src/__tests__/contracts/customChannelContracts.test.ts
node --import tsx --test src/__tests__/domain/customChannelAuthoring.test.ts
npm run test:contracts
npm run verify:redaction
npm run verify:architecture
```

Expected outcome: new public contracts compile, forbidden-field checks reject secret/path/url/native fields, domain draft mapping and persisted mutation behavior are covered, architecture rules still pass, and redaction scanner still passes.

### After main/preload IPC packages

```sh
npm run typecheck
node --import tsx --test src/__tests__/main/customChannelRuntime.test.ts
node --import tsx --test src/__tests__/main/customChannelIpc.test.ts
node --import tsx --test src/__tests__/integration/preloadContractVocabulary.test.ts
npm run test:contracts
npm run verify:redaction
npm run verify:architecture
```

Expected outcome: main runtime serializes mutations, validates access and stale IDs, returns renderer-safe results only, preload guards reject malformed payloads/results, channel constants and bridge exposure match, and no forbidden material crosses process boundaries.

### After artwork proxy package

```sh
npm run typecheck
node --import tsx --test src/__tests__/contracts/artworkContracts.test.ts
node --import tsx --test src/__tests__/main/artworkProxy.test.ts
npm run verify:redaction
npm run verify:architecture
```

Expected outcome: artwork references are opaque and safe, main rejects unauthorized/stale artwork IDs, cache/protocol behavior does not expose Plex keys/tokens/URLs/paths, and redaction recognizes only approved safe app-origin artwork identifiers.

### After renderer UI packages

```sh
npm run typecheck
node --import tsx --test src/__tests__/renderer/customChannels.test.ts
node --import tsx --test src/__tests__/renderer/customChannelMediaPicker.test.ts
node --import tsx --test src/__tests__/renderer/customChannelFocus.test.ts
npm run smoke:electron
npm run verify:redaction
npm run verify:architecture
```

Expected outcome: renderer view models and action controllers handle browse/search/add/remove/reorder/duplicate/delete/save/confirm/cancel states, focus/back behavior is deterministic, Electron smoke reaches the route without privileged renderer access, and redaction/architecture still pass.

### Full closeout

```sh
npm run verify
npm run smoke:electron
git diff --check
```

Expected outcome: full repo verification passes, Electron smoke passes, and diff whitespace check reports no blocking issues. If `git diff --check` reports only pre-existing CRLF warnings, record them exactly and do not hide new whitespace errors.

### Manual/visual proof required before product closeout

Record redaction-safe local proof under ignored `docs/runs/custom-channels-authoring/` or another reviewed ignored run path. The proof must include only sanitized category/count/pass-fail facts and sanitized screenshots if screenshots are needed.

Manual proof script:

1. Start from a signed-in Plex profile/server with at least one movie or show library.
2. Open the custom channel workspace from the reachable product route.
3. Observe saved channel list recovery state and no raw private account/server/library values in tracked evidence.
4. Create a new channel from selected library items using poster grid/list, metadata preview, and selection cart.
5. Confirm inline Add/Remove actions are near each result card and membership badge changes immediately after adding.
6. Search within a library, add search results, clear search, and verify selected cart remains visible.
7. Try adding an existing selected item and verify duplicate prevention or explicit duplicate-allowed setting behaves as designed.
8. Set channel name, channel number, ordering mode, and color/icon.
9. Save the draft and verify guide/player channel list refreshes without app restart.
10. Edit the saved channel, remove an item, reorder items, save again, and verify guide changes.
11. Duplicate the saved channel into a draft, change number/name, save, and verify both channels exist.
12. Hide a channel and verify it is preserved in management UI but excluded from guide/channel surfing.
13. Delete a channel after explicit confirmation and verify current channel fallback behavior is safe.
14. Trigger expected validation failures: duplicate number, empty content, stale media item, storage unavailable/corrupt fixture if available.
15. Test keyboard-only operation: Tab/Shift+Tab, arrow navigation where supported, Enter/Space activation, Escape/back semantics, text entry bypass, and focus restoration after dialogs.
16. Test reduced-motion and forced-colors/high-contrast behavior where available.
17. Verify support bundle/redaction scan does not include tokens, raw URLs, image keys, file paths, raw Plex payloads, or private screenshots/logs.

## Acceptance Criteria

### Product behavior

- A user can open a channel management/authoring workspace from the existing Desktop navigation without using dev-only surfaces.
- The workspace shows saved channels with number, name, item count, visibility state, and current-channel marker when available.
- A first-run user can still build starter channels from library sections, but the path clearly offers custom channel creation and no longer presents fake setup controls as product behavior.
- A user can create a custom channel from one or more eligible Plex media selections and save it to persisted channel data.
- A user can edit an existing channel’s name, number, description, color/icon, content selections, order mode, block size where applicable, filters/sort options, include-watched behavior, skip-intro/credits flags if still relevant, and visibility.
- A user can duplicate an existing channel into an editable draft without immediately persisting accidental duplicate data.
- A user can delete a channel only after explicit confirmation; current-channel fallback is deterministic.
- A user can reorder channels and see guide/channel surfing order reflect the change after save.
- A hidden channel remains in management UI and persisted storage but is excluded from guide/channel surfing by default.
- Saving a channel refreshes scheduler-backed guide/player state without app restart.
- Existing channel setup append/replace behavior remains functional until deliberately deprecated by a later plan.

### Media picker behavior

- The media picker supports library browsing and search using existing main-owned Plex library operations or a focused main-owned custom media picker wrapper.
- Eligible media cards include safe title/type/year/duration/show/season/episode metadata and poster artwork when the safe artwork proxy package is included.
- Poster failures fall back to stable placeholders without blocking channel authoring.
- Search results and browse results show inline Add/Remove controls near each item, not only in a distant global action area.
- Items already in the current draft show an “Added” or equivalent membership state directly on the card.
- The selection cart remains visible while browsing/searching and shows item count, estimated total duration, duplicate status, and validation warnings.
- Metadata preview is available without losing the current draft/cart.
- Selection actions are keyboard-accessible and mouse-friendly.
- Large libraries are paginated or incrementally loaded; the renderer must not request or render unbounded full-library result sets.

### Data and scheduler behavior

- Custom channel drafts map to existing domain `ChannelConfig` and `ChannelContentSource` shapes where safe. If the current domain shape is insufficient, new fields are explicitly validated, persisted, tested, and documented.
- Manual item selections persist only safe identifiers and scheduler-required metadata. No poster keys, URLs, paths, headers, tokens, or raw Plex payloads are persisted.
- Duplicate channel numbers are rejected with safe validation copy.
- Duplicate media items are prevented by default. If an advanced setting allows duplicates, the UX must make it explicit and tests must prove deterministic ordering.
- Missing/stale Plex items are represented as recoverable validation or stale-content states, not crashes or raw errors.
- Scheduler/guide exclude hidden channels and handle deleted-current-channel fallback deterministically.

### Security and redaction behavior

- Renderer-facing custom-channel and artwork contracts reject forbidden field names recursively.
- Preload validates every request and response envelope and returns safe validation failures when main returns malformed data.
- Main authorizes every custom-channel IPC request using the existing shell authorization pattern.
- Renderer never receives raw Plex tokens, auth headers, tokenized URLs, selected connection URIs, image keys, raw payloads, file paths, native handles, Electron APIs, Node APIs, or arbitrary IPC channel names.
- Diagnostics and support bundles contain only redacted operation/category/count/status data for custom-channel and artwork operations.
- `npm run verify:redaction` passes after every package that touches contracts, main diagnostics, preload guards, artwork, or renderer error copy.

### UI, accessibility, and desktop UX behavior

- The layout is desktop-first and efficient with mouse and keyboard: channel list, media browser, and selection cart/editor are visible together at typical desktop widths.
- The UI remains usable at narrower widths through responsive stacking without losing Save/Cancel/selection context.
- Focus movement is deterministic after opening metadata, adding/removing items, saving, validation failure, delete confirmation, and route/back navigation.
- Text inputs preserve the existing desktop input bypass behavior so typing does not trigger global navigation shortcuts.
- Buttons use accessible names and state (`aria-pressed`, `aria-selected`, `aria-disabled`, or appropriate roles) where state is not obvious from text.
- Reduced-motion and forced-colors policies are preserved.
- No broad screenshots, private library names, private server names, or private poster art are committed.

## Replan Triggers

Stop and replan before continuing if any of these occur:

- Current branch is not `initial-build` or the relevant source owners differ materially from this plan.
- `git status --short --branch` shows unrelated pre-existing changes in files this feature needs to edit and ownership cannot be separated.
- A reviewer finds a material plan blocker in IPC, persistence, Plex, artwork, or UI boundaries.
- Poster-card UX appears to require exposing raw Plex image keys, URLs, tokenized URLs, headers, or file paths to renderer.
- Existing Plex contracts’ forbidden-field policy blocks safe artwork references and the solution requires weakening redaction rather than adding an opaque main-owned proxy.
- Custom-channel persistence requires storing raw Plex payloads or raw image data in channel config.
- Renderer must use browser storage, direct filesystem access, or raw app paths to preserve drafts.
- Main custom-channel runtime needs to mutate scheduler/player/native-helper internals directly instead of using channel repository/guide runtime seams.
- Hidden-channel semantics cannot be implemented without ambiguous scheduler behavior.
- Large-library performance requires a new virtualization or state-management dependency.
- Any touched production file crosses maintainability guardrails and cannot be split within the package.
- `npm run verify:redaction`, `npm run verify:architecture`, `npm run smoke:electron`, or `npm run verify` fails for a feature-caused reason.
- External code copying becomes desirable. Stop for license/provenance/import-ledger review before copying or adapting code.

## Rollback Notes

- Keep each package reversible. Prefer one focused commit per reviewed implementation package.
- Contract changes should land with tests and no renderer/main callers until the next package only if the repo still verifies at that checkpoint. If unused public APIs trigger review objections, combine the contract and first caller in one package.
- Main runtime changes should preserve the existing `channelSetup.getStatus` and `channelSetup.commit` behavior until the custom workspace fully replaces or delegates the old route.
- Renderer workspace packages should be gated behind a route/action that can fall back to the existing channel setup surface during review if needed.
- Artwork proxy package should be independently removable. If it fails security review, remove poster-specific rendering and keep placeholder cards rather than weakening redaction.
- Schema migrations must be backward-compatible. If a migration fails, main should classify storage as unavailable/corrupt with existing safe error semantics; do not write partial repaired data without tests.
- Do not delete old persisted channel files during migration. Use temp-file write/replace semantics already expected by the channel persistence adapter.
- On rollback, remove new IPC constants, preload methods, shell contract fields, main handlers, renderer actions, and tests for that package together to avoid orphan public API.

## Commit Checkpoints

Use conventional commits. Do not stage unrelated local changes.

Recommended checkpoint sequence:

1. `docs(custom-channels): add reviewed custom channel implementation plan`  
   Docs-only if this plan is committed under `docs/plans/`. Run `npm run verify:docs`.

2. `feat(custom-channels): add renderer-safe authoring contracts`  
   Contracts/domain skeleton plus tests. Run typecheck, focused contract/domain tests, redaction, architecture.

3. `feat(custom-channels): add main custom channel runtime`  
   Main mutation validation/persistence/scheduler refresh with tests. Run focused main tests plus architecture/redaction.

4. `feat(custom-channels): add safe media picker and artwork proxy`  
   Main-owned media card projection/artwork refs/protocol/cache with tests. Run focused tests, redaction, architecture.

5. `feat(custom-channels): expose custom channel preload bridge`  
   Preload guards/bridge/channel constants/integration vocabulary tests. Run typecheck, integration parity, redaction.

6. `feat(custom-channels): add desktop channel authoring workspace`  
   Renderer state/actions/view models/DOM/styles/focus tests. Run focused renderer tests, smoke, redaction, architecture.

7. `feat(custom-channels): wire guide refresh and saved channel management`  
   End-to-end mutation to guide/player channel state with tests. Run `npm run test:contracts`, `npm run smoke:electron`, `npm run verify`.

8. `test(custom-channels): add manual proof and closeout docs`  
   Redaction-safe proof summary only, no private media/account screenshots. Run `npm run verify:docs`, `npm run verify:redaction`, `npm run verify`.

Do not merge packages 2 through 7 without read-only implementation review if the package touches IPC/security, persistence, Plex, artwork, or scheduler boundaries.

## Product UX Specification

### Primary route and workspace layout

Use a three-pane desktop workspace at medium and large widths:

1. **Left pane: Channel lineup**
   - Shows saved channels sorted by channel order.
   - Each row shows channel number, name, visibility, item/source count, and current-channel marker if applicable.
   - Actions near the list: New Channel, Edit, Duplicate, Hide/Unhide, Delete, Move Up/Down or drag handle if later implemented safely.
   - Search/filter saved channels if channel count exceeds a small threshold, but do not add global fuzzy search dependency.

2. **Center pane: Media picker**
   - Tabs or segmented controls: Libraries, Search, Collections, Playlists, Shows, Selected Source.
   - Top search/filter controls remain close to results.
   - Results render as poster cards when artwork proxy is available; otherwise stable placeholder cards with title/type/year/duration.
   - Every card has inline Add/Remove control and an “Added” state if the item/source is already in the draft.
   - Metadata preview opens in-place or in the right inspector without losing cart context.
   - Pagination/incremental loading is explicit: Load More button or sentinel with deterministic state; no unbounded render.

3. **Right pane: Draft editor and selection cart**
   - Shows draft channel name, number, description, color/icon, visibility, ordering mode, block size if applicable, filters, and start-anchor policy.
   - Shows selected content entries in order with remove/reorder controls.
   - Shows validation summary: missing name, duplicate number, empty content, stale/inaccessible media, max channel/item limits, hidden state, unsaved changes.
   - Save, Cancel, Delete, and Duplicate actions live here and remain visible.

At narrow widths, stack panes as steps but preserve persistent draft/cart context through a sticky summary. Do not hide Save/Cancel behind only keyboard shortcuts.

### First-run experience

When no persisted channels exist:

- Primary call to action: “Create a custom channel.”
- Secondary call to action: “Auto-build starter channels from Plex libraries,” delegating to the current section-based channel setup behavior.
- Explain in one sentence that channels are local to this Desktop app and based on the selected Plex server/profile.
- If Plex profile/server/library is missing, show the existing Plex onboarding/server/library steps before channel authoring controls.

### Saved-channel management

- **New:** opens empty draft with next available channel number and default order mode based on content type once content is added.
- **Edit:** loads persisted channel into draft. If source contains unsupported legacy fields, show safe read-only warning and require migration/rebuild before saving.
- **Duplicate:** creates a draft copy with next available number, name suffix “Copy,” hidden false by default, and new deterministic seeds. It must not immediately persist until Save.
- **Delete:** requires confirmation with channel number/name and consequence. After delete, current channel fallback chooses the next visible channel by order, previous visible channel if no next, or null if none.
- **Hide/Unhide:** toggles visibility without deleting. Hidden channels remain visible in management pane and excluded from guide/channel surfing by default.
- **Reorder:** support button-based Move Up/Move Down in MVP. Drag-and-drop may be added later only if keyboard-accessible and tested.

### Media picker and selection cart behavior

- Library sections, collections, playlists, shows, and manual items must be represented as explicit source entry types in the draft.
- Default duplicate policy: one rating key/source entry per channel draft. Cards already in the draft display “Added” and their Add button becomes Remove or disabled depending on UX. The cart provides the authoritative selected list.
- Add actions must be near each result card. Avoid a single Add button far from the results grid.
- Search results should preserve current selected cart and selected channel context.
- Search should debounce user input and ignore stale results. A 250–350 ms debounce is appropriate unless tests show existing controller patterns prefer manual submit only.
- Item metadata preview should not add the item automatically. Preview Enter/Click opens details; Add control or Space/explicit button adds.
- For TV shows, support adding a whole show as a source and, later, season-level filters. MVP can expose whole show and selected episodes if domain mapping is explicit.
- For playlists/collections, support adding the whole source if the current Plex runtime can safely list/resolve them. If current runtime cannot resolve them safely, show them as disabled with “planned” copy only after a reviewed product decision, or omit until supported. Do not show fake actionable controls.

### Scheduling and order options

Expose only options that domain/scheduler can honor now:

- Sequential
- Shuffle
- Random
- Block shuffle using `blockSize` when valid
- Sort order when source type supports it
- Include watched toggle for library-based sources
- Skip intros/credits toggles only if existing playback path honors them or they are already persisted harmlessly; otherwise hide until runtime support exists

Stage advanced options after core authoring works:

- Cyclic shuffle and block cyclic shuffle
- Daypart/weekend schedules
- Rating-based time windows
- Marathon blocks
- Interstitial/commercial blocks
- Smart channels based on actor/director/genre/decade/studio filters
- Channel logos from imported files
- Import/export/backup/restore

Do not expose advanced controls as fake disabled clutter unless the copy clearly says they are not available in this build.

### Poster/artwork UX

- Card aspect ratio should be stable before image load.
- Missing images show deterministic placeholders based on media type and title initial.
- Image loading must be lazy and bounded by visible cards/page size.
- App-origin artwork source must not reveal Plex server identity, item rating key, image key, filesystem path, token, or query parameters to renderer-visible logs or DOM attributes. Opaque IDs are acceptable.
- On sign-out/profile/server switch, stale artwork IDs must stop resolving or resolve to placeholders.

### Validation copy

Use direct, actionable, safe copy:

- Empty draft: “Add at least one movie, show, episode, playlist, collection, or library source before saving.”
- Duplicate number: “Channel number 12 is already used by Movies. Choose another number.”
- Stale item: “One selected item is no longer available from the selected Plex server.”
- Storage unavailable: “Channel storage is unavailable. Try again after restarting Lineup Desktop.”
- Replace/delete confirmation: “This changes saved channels on this device only.”

Never include raw server URL, account token, file path, raw payload detail, or tokenized image/media URL in validation copy.

## Data And Contract Design

### Contract namespace

Create `src/contracts/customChannels.ts` with these core concepts. Names are suggestions; implementers may refine names if the public shape stays equivalent and reviewed.

```ts
export const CUSTOM_CHANNEL_OPERATIONS = [
  'getSnapshot',
  'listMedia',
  'getMediaMetadata',
  'validateDraft',
  'saveDraft',
  'deleteChannel',
  'duplicateChannelDraft',
  'reorderChannels',
  'setChannelVisibility',
] as const;
```

Use result envelopes like existing contracts:

```ts
export type CustomChannelIpcResult<TValue> =
  | { ok: true; requestId: string; value: TValue }
  | { ok: false; requestId: string; error: CustomChannelRuntimeError };
```

Error codes must be explicit and renderer-safe:

- `CUSTOM_CHANNEL_UNAUTHORIZED`
- `CUSTOM_CHANNEL_VALIDATION_FAILED`
- `CUSTOM_CHANNEL_PLEX_REQUIRED`
- `CUSTOM_CHANNEL_STORAGE_UNAVAILABLE`
- `CUSTOM_CHANNEL_STORAGE_CORRUPT`
- `CUSTOM_CHANNEL_NOT_FOUND`
- `CUSTOM_CHANNEL_STALE_MEDIA`
- `CUSTOM_CHANNEL_ARTWORK_UNAVAILABLE`
- `CUSTOM_CHANNEL_CONFLICT`
- `CUSTOM_CHANNEL_UNKNOWN`

### Snapshot shape

Snapshot should include only safe data:

```ts
export interface CustomChannelSnapshot {
  channels: readonly CustomChannelSummary[];
  currentChannelId: string | null;
  visibleChannelCount: number;
  hiddenChannelCount: number;
  maxChannels: number;
  nextAvailableNumber: number | null;
  updatedAtMs: number;
  storage: {
    status: 'ready' | 'not-configured' | 'unavailable' | 'corrupt';
    repaired: boolean;
  };
}
```

`CustomChannelSummary` should include:

- id
- number
- name
- description if safe/bounded
- item/source count
- estimated duration
- source summary label
- playback mode
- hidden/visible state
- updatedAtMs
- current marker if useful

It must not include persisted raw channel data, raw content source details with private keys, Plex raw payloads, image URLs, image keys, server IDs beyond safe selected server references already exposed elsewhere, paths, tokens, or headers.

### Draft input shape

Drafts sent to main should be bounded and exact:

```ts
export interface CustomChannelDraftInput {
  id?: string;
  expectedRevision?: string;
  number: number;
  name: string;
  description?: string;
  color?: string;
  icon?: string;
  hidden: boolean;
  content: readonly CustomChannelContentEntryInput[];
  playbackMode: 'sequential' | 'shuffle' | 'random' | 'block';
  blockSize?: number;
  sortOrder?: SafeChannelSortOrder;
  includeWatched?: boolean;
  startTimeAnchor?: number;
  skipIntros?: boolean;
  skipCredits?: boolean;
}
```

Use `expectedRevision` or `updatedAtMs` to detect stale edits when two operations overlap. If the existing store cannot support revisions, use `updatedAtMs` plus serialized main mutation queue and return `CUSTOM_CHANNEL_CONFLICT` when stale enough to matter.

### Content entries

Represent content explicitly and map into existing domain `ChannelContentSource`:

- `library`: selected library section
- `show`: whole show by rating key
- `collection`: collection rating key/name
- `playlist`: playlist rating key/name
- `manualItem`: selected movie/episode item
- `mixed`: main-created source from multiple entries

Do not expose raw source payloads. For each content entry, include only:

- stable safe ID/rating key
- source type
- display title
- duration for manual items when known
- media type when needed for scheduling and UI
- safe metadata such as year/season/episode only if contract tests prove no forbidden fields

If `ManualContentItem` must be expanded beyond `ratingKey`, `title`, and `durationMs`, add optional safe fields in `src/domain/channel/types.ts` with validator updates and tests. Do not add artwork fields to persisted manual items.

### Media card shape

Use a separate media-card result for browsing/searching:

```ts
export interface CustomChannelMediaCard {
  mediaId: string;
  ratingKey: string;
  type: 'movie' | 'show' | 'episode' | 'collection' | 'playlist';
  title: string;
  subtitle: string;
  year: number | null;
  durationMs: number | null;
  parentTitle?: string;
  seasonNumber?: number;
  episodeNumber?: number;
  contentRating?: string;
  source: CustomChannelSourceRef;
  artwork?: ArtworkRef;
  availability: 'available' | 'stale' | 'unsupported';
}
```

If `mediaId` and `ratingKey` would be identical, keep one public identifier and document the choice. Avoid keeping duplicate identifiers if they confuse validation.

### Artwork reference shape

Create `src/contracts/artwork.ts` only if poster UX lands:

```ts
export interface ArtworkRef {
  artworkId: string;
  kind: 'poster' | 'background' | 'logo';
  altText: string;
  placeholder: string;
  updatedAtMs: number;
}
```

`artworkId` must be opaque, bounded, non-URL-like, and safe for DOM dataset use after encoding. It must not be a Plex rating key, image key, path, URL, token, or hash that can be reversed to private server data. If the renderer constructs a local `lineup://artwork/<id>` source, that source must live in renderer-local view-model code, not be persisted or returned as a contract field named URL/URI/path.

### Mutation semantics

- `validateDraft` checks shape, number conflicts, name length, content count, unsupported source types, stale IDs, max channel count, max manual items, and hidden/deleted conflict.
- `saveDraft` always re-validates server-side and persists atomically.
- `deleteChannel` requires `confirm: true` and channel ID. Main verifies current existence and chooses fallback current channel.
- `reorderChannels` requires the complete ordered list of persisted channel IDs, not a partial arbitrary mutation. Main rejects missing/unknown/duplicate IDs.
- `setChannelVisibility` requires existing ID and boolean hidden. Main persists and refreshes guide state.
- All mutation operations serialize through one main-owned queue so saves/deletes/reorders cannot interleave corruptly.

## Implementation Packages

### Package 0: Plan review and fresh evidence refresh

**Objective:** Convert this artifact into the current tracked plan/handoff and review it before code changes.

**Tasks:**

- Confirm branch with `git status --short --branch`.
- Read required docs and source owners listed above.
- Run `npm run verify:maintainability` for file-shape baseline.
- If promoted to `docs/plans/`, ensure this plan keeps the active marker and exact required headings.
- Send to read-only `lineup-desktop-feature-review` or reviewer role.
- Adjudicate review findings before implementation.

**Stop if:** branch/source owners differ, reviewer finds unresolved seam/security issues, or maintainability baseline is already failing for relevant owners.

### Package 1: Contracts and domain authoring model

**Objective:** Add renderer-safe custom-channel public contracts and domain mapping for custom drafts without touching UI or main IPC wiring yet.

**Files:** `src/contracts/customChannels.ts`, focused domain files under `src/domain/channel/**`, focused persistence preservation updates under `src/domain/channel/**`, tests under `src/__tests__/contracts/**` and `src/__tests__/domain/**`. Do not change `src/contracts/ipc.ts`, `src/contracts/shell.ts`, preload, main IPC, renderer, or artwork files in Package 1.

**Required decisions:**

- Reserve a separate future `customChannels` namespace for `LineupDesktopPreloadApi`, but do not add it in Package 1. The required `LineupDesktopPreloadApi` extension lands with Package 4 bridge wiring so `npm run typecheck` remains green at the Package 1 checkpoint.
- Keep existing `channelSetup` contract intact.
- Define exact operation literals and request/result envelopes.
- Define forbidden-field arrays and recursive forbidden-field checks.
- Define draft input, media card summary, snapshot, validation summary, and mutation result shapes.
- Map draft content entries to existing `ChannelContentSource` types where possible.
- Decide whether `ManualContentItem` needs safe optional metadata. If it does, update validators and persistence tests in the same package.
- Define hidden-channel semantics in domain with an explicit persisted field name. Package 1 chooses `ChannelConfig.hidden?: boolean`, defaulting to `false` when omitted. The field is preserved by clone/validation/repository normalization and encoded in stored channel data; guide/channel-surfing exclusion is implemented in Package 6.

**Tests:**

- Contract tests for every success/failure envelope and forbidden-field rejection.
- Domain tests for draft-to-channel mapping: library, show, manual item, mixed source, duplicate number, max channel count, invalid block size, hidden state, duplicate media policy.
- Persistence/repository tests for `hidden` preservation, omitted-field defaulting, malformed hidden repair, and no forbidden field exposure.

**Stop if:** domain cannot represent needed custom content without raw Plex payloads, artwork references need forbidden raw fields, or hidden-channel semantics require scheduler redesign not included in this package.

### Package 2: Main custom-channel runtime and mutation serialization

**Objective:** Add main-owned runtime for snapshots, validation, save, delete, duplicate-draft support, reorder, and visibility without renderer UI.

**Files:** new `src/main/channel/customChannelRuntime.ts`, `customChannelMutationMapper.ts`, `customChannelDiagnostics.ts`, `customChannelSchedulerRefresh.ts`, focused changes to `channelComposition.ts`, domain/persistence tests.

**Required behavior:**

- Load persisted channels through existing `ChannelRepository`/store.
- Return safe snapshots only.
- Serialize all mutations through one queue.
- Validate every draft server-side.
- Preserve current channel when possible; choose deterministic fallback after delete/hide/reorder.
- Refresh guide/scheduler state through existing `GuideRuntime` or a focused refresh hook.
- Emit redacted diagnostics only: operation, status, counts, safe error code.
- Keep current section-based `ChannelRuntime.commit` behavior unchanged.

**Tests:**

- Save new custom channel.
- Edit existing channel.
- Duplicate into draft or duplicate save path, depending on API choice.
- Delete with and without confirmation.
- Reorder complete list with invalid/missing/duplicate IDs.
- Hide/unhide and guide exclusion.
- Stale edit conflict.
- Storage unavailable/corrupt classification.
- No forbidden fields in snapshots/errors.

**Stop if:** custom runtime needs direct player/native-helper mutation, raw Plex transport policy, or persistent browser/renderer state.

### Package 3: Main media picker projection and safe artwork proxy

**Objective:** Provide Plex-client-style browse/search/media-card data and poster artwork without exposing Plex image secrets.

**Files:** new `src/main/channel/customChannelMediaPicker.ts`, `src/main/artwork/**` or `src/main/channel/artwork/**`, focused `src/main/protocol.ts` registration if needed, optional `src/contracts/artwork.ts`, tests.

**Required behavior:**

- Use existing main-owned Plex runtime/library operations to list sections/items/search/metadata.
- Project raw Plex data into safe `CustomChannelMediaCard` values.
- Page results; default 24 or current UI page size, never unbounded.
- Include membership-relevant IDs but no raw image keys/URLs.
- Create opaque `ArtworkRef` values for poster-capable cards.
- Main artwork proxy resolves opaque IDs to Plex artwork using main-owned token/header custody.
- Enforce content type, byte size, timeout, cache TTL, and authorization.
- Invalidate stale artwork on sign-out/profile/server change.
- Return safe placeholder state when artwork fails.

**Tests:**

- Media listing/search returns only safe fields.
- Pagination bounds are enforced.
- Stale section/item IDs return safe recoverable errors.
- Artwork ID is opaque and non-URL-like.
- Artwork proxy rejects unknown/expired/unauthorized IDs.
- Redaction scan fixtures catch raw Plex image key/URL/header/path attempts.

**Stop if:** artwork cannot be implemented without weakening forbidden-field rules. Use placeholders and replan artwork instead.

### Package 4: Custom-channel preload bridge and IPC handlers

**Objective:** Expose the main runtime through a narrow, typed, validated preload/API seam.

**Files:** `src/preload/customChannelBridge.cts`, `src/preload/customChannelBridgeGuards.cts`, `src/preload/channels.cts`, `src/preload/index.cts`, `src/main/channel/customChannelIpc.ts`, `src/contracts/ipc.ts`, `src/contracts/shell.ts`, integration tests.

**Required behavior:**

- Add named IPC constants per operation.
- Add the `customChannels` namespace to `LineupDesktopPreloadApi` in `src/contracts/shell.ts` only in this package, together with the actual preload bridge implementation.
- Main `customChannelIpc` authorizes every event using existing shell authorization.
- Main request readers validate exact payload keys, bounded strings/numbers/arrays, confirmation booleans, and operation-specific constraints.
- Preload request builders reject malformed renderer input locally.
- Preload result guards validate main results recursively and return safe validation failure on malformed result/rejection.
- `window.lineupDesktop` remains the single exposed object; no raw `ipcRenderer` or Electron API exposure.

**Tests:**

- Malformed renderer request rejected in preload.
- Unauthorized main event returns safe unauthorized error.
- Main malformed payload returns safe validation error.
- Preload rejects forbidden fields in successful and failed results.
- Integration parity test covers constants, guard vocabulary, single exposure, and approved `ipcRenderer` method/channel pairs.

**Stop if:** API pressure suggests a generic bridge. Add named methods instead or replan.

### Package 5: Renderer custom-channel workspace

**Objective:** Build the desktop-first authoring UI using renderer-safe state, view models, DOM, CSS, focus, and existing navigation patterns.

**Files:** `src/renderer/customChannels/**`, focused wiring in `staticDom.ts`, `domBindings.ts`, `routeDom.ts`, `workflow.ts`, `rendererActionRegistration.ts`, `focusDom.ts`, styles under `src/renderer/styles/custom-channels.css`, renderer tests.

**Required behavior:**

- Three-pane layout at desktop widths: channel list, media picker, draft/cart editor.
- Responsive stacked layout at narrow widths with persistent draft/cart summary.
- Search input, filters, and Add/Remove controls remain near result cards.
- Cards show membership state and poster/placeholder.
- Selection cart remains visible while browsing/searching.
- Draft validation renders safe actionable messages.
- Save/delete/duplicate/hide/reorder flows use explicit confirmation where destructive.
- Keyboard-only operation works for major flows.
- Escape/back semantics unwind metadata, search, media picker, draft dialogs, then route navigation in that order.
- Text entry bypass remains intact.
- Reduced-motion/forced-colors policies preserved.

**Tests:**

- View-model tests for empty state, saved channels, draft validation, media card membership, cart counts, destructive confirmations, hidden state.
- Action-controller tests for stale browse/search results, add/remove/reorder, save success/failure, delete confirmation, keyboard/back behavior.
- DOM tests for safe text rendering, dataset IDs, aria state, disabled buttons, and focus IDs. Avoid broad snapshots.
- Smoke route reachability.

**Stop if:** renderer needs raw Plex data, image URLs, browser storage, direct file access, or broad route rewrites.

### Package 6: Scheduler/guide/player channel refresh integration

**Objective:** Ensure saved custom channel changes take effect in the runtime guide/player channel state without app restart.

**Files:** focused changes to `src/main/channel/guideRuntime.ts`, `src/main/channel/channelComposition.ts`, scheduler domain only if hidden-channel semantics demand pure-domain support, renderer guide polling state tests.

**Required behavior:**

- After save/delete/reorder/hide/unhide, guide presentation refreshes against the new channel set.
- Current channel remains stable when edited/reordered and still visible.
- If current channel is deleted/hidden, fallback is deterministic and renderer/player snapshot does not reference missing channel.
- EPG/mini-guide/channel badge reflect new channel number/name/order.
- Runtime does not start playback automatically after authoring save unless that was already current behavior.

**Tests:**

- Save custom channel then guide includes it.
- Hide channel then guide excludes it but management snapshot keeps it.
- Delete current channel then fallback current channel is safe.
- Reorder channels then guide order changes.
- Stale guide polling result cannot resurrect deleted/hidden channel.

**Stop if:** integration needs native playback or player adapter changes.

### Package 7: Advanced customization follow-up packages

These are part of the full feature plan but should not block the core authoring launch unless the user explicitly prioritizes them first.

#### 7A: Import/export and backup/restore

- Main owns file picker/path/import/export behavior.
- Renderer receives only result summaries, not paths.
- Export includes app/version/schema and warns that Plex item IDs are server/profile scoped.
- Import validates schema, server/profile compatibility, missing items, duplicate numbers, and preview diff before writing.
- Tests cover corrupt import, wrong schema, missing items, redaction, and no raw paths in renderer.

#### 7B: Custom logos

- Main imports user-selected image file into app-owned cache; renderer never sees original path.
- Validate file type/size/dimensions and strip metadata where feasible.
- Persist only opaque logo ID and safe display metadata.
- Support built-in icon/color/initials before file import.

#### 7C: Advanced scheduling

- Add cyclic shuffle, block cyclic, daypart/weekend schedules, rating time windows, and marathon blocks only after domain scheduler supports them with deterministic tests.
- UI must explain schedule effects in preview and avoid fake disabled controls.

#### 7D: Interstitials/commercials

- Treat as a separate content-source/scheduler feature with explicit source selection, opt-in behavior, and playback-proof gates.
- Do not mix with core custom channel authoring unless reviewed.

### Package 8: Proof, review, docs, and closeout

**Objective:** Close the feature with observed automated/manual evidence and durable docs updates.

**Tasks:**

- Run full verification and smoke.
- Execute manual/visual proof script with redaction-safe evidence.
- Request read-only implementation review.
- Adjudicate findings.
- Update `CURRENT_STATE.md`, `renderer-architecture.md`, roadmap/product docs if applicable, and import ledger if code was copied/adapted.
- Archive local run evidence under ignored paths only.
- Emit next-session handoff or no-further-session note.

**Stop if:** review finds material security, boundary, verification, or UX blockers.

## Test Matrix

| Surface | Required proof | Notes |
| --- | --- | --- |
| Custom contracts | Contract tests and forbidden-field tests | Reject URL/path/token/header/native/raw payload fields recursively. |
| Domain draft mapping | Domain tests | Cover library/show/manual/mixed, playback modes, duplicate numbers, hidden state, max limits. |
| Persistence | Domain/main tests | Cover schema version, atomic save, corrupt/unavailable, no raw private fields. |
| Main runtime | Main tests | Mutations serialize; stale conflicts; save/delete/reorder/hide fallback. |
| Plex media picker | Main tests with injected Plex runtime | Browse/search/page/stale/empty/error with safe projection. |
| Artwork proxy | Contract/main/redaction tests | Opaque IDs only; no raw image keys/URLs/paths/tokens. |
| IPC/main auth | Main IPC tests | Unauthorized, malformed payload, unknown IDs, safe errors. |
| Preload guards | Integration parity and focused guard tests | Request/result validation, approved channels only. |
| Renderer state/actions | Renderer tests | Add/remove/reorder/save/search/stale/back/focus. |
| Renderer DOM | Renderer tests plus smoke | Safe text rendering, aria state, disabled controls, no broad snapshots. |
| Guide/player integration | Main/renderer tests | Refresh after save/delete/hide/reorder; current fallback. |
| Visual/manual UX | Redaction-safe manual proof | Poster placeholders/artwork, layout, keyboard, reduced motion, forced colors. |
| Full repo | `npm run verify`, `npm run smoke:electron`, `git diff --check` | Required closeout. |

## Manual QA Script

Use sanitized fixture names when recording proof. Do not record private account names, server names, library names, posters, paths, endpoints, tokens, headers, or raw payloads in tracked docs.

1. Launch the app and verify custom channel workspace is reachable.
2. With no channels, verify first-run copy and create/custom starter options.
3. Sign in/restore Plex profile/server if needed.
4. Browse a movie library with at least one page of results.
5. Add one media item from a card inline Add button.
6. Verify card shows Added state and selection cart count increments.
7. Preview metadata for a different item; close preview; verify cart persists.
8. Search within the library; add a result; clear search; verify cart persists.
9. Attempt to add the first item again; verify duplicate behavior is explicit.
10. Set channel name/number/order mode/color/icon and save.
11. Verify guide shows the new channel after refresh.
12. Edit channel; remove an item; reorder content; save; verify guide/current state remains safe.
13. Duplicate channel into draft; save under a different number/name.
14. Hide duplicated channel; verify management shows it and guide excludes it.
15. Unhide duplicated channel; verify guide includes it again.
16. Delete duplicated channel with confirmation; verify fallback current channel.
17. Test validation failures: duplicate number, empty content, invalid block size, stale item fixture if available.
18. Keyboard-only pass: navigate cards, add/remove, open/close metadata, edit fields, save/cancel, confirm delete.
19. Accessibility pass: focus visible, button labels, high contrast/forced colors, reduced motion.
20. Redaction pass: export support bundle or run redaction verifier; verify no forbidden material.

## Adversarial Review And Adjudication

### Finding 1: Poster UX conflicts with current Plex forbidden image-key policy

**Risk:** The existing Plex contract forbids renderer image-key material. A naive implementation would expose Plex `thumb`, `art`, URLs, or tokenized image routes to make poster cards work.

**Adjudication:** Do not expose raw Plex image keys or URLs. Implement poster support only through a main-owned opaque artwork proxy/protocol/cache. Renderer sees safe `ArtworkRef` values and app-origin image sources only. If this cannot be implemented safely in the package, ship placeholder cards and replan artwork.

### Finding 2: The current channel setup API is too narrow for custom channels

**Risk:** Overloading `channelSetup.commit({ sectionIds })` for arbitrary media would create ambiguous payloads, weak validation, and compatibility residue.

**Adjudication:** Keep existing section-based setup intact. Add a separate `customChannels` API namespace with exact operations and tests. Deprecation or unification can be a later cleanup plan after the real workflow is proven.

### Finding 3: This feature can become a single massive renderer/main patch

**Risk:** A less disciplined implementation could grow `index.ts`, `staticDom.ts`, `channelRuntime.ts`, `channelIpc.ts`, and root CSS into hotspots.

**Adjudication:** Split into packages and focused owners. Composition files get wiring only. Feature policy belongs in `src/renderer/customChannels/**`, `src/main/channel/customChannel*.ts`, `src/contracts/customChannels.ts`, and focused domain files. Run maintainability verification before and after relevant packages.

### Finding 4: Media selection persistence may become stale or server-specific

**Risk:** Plex rating keys are only meaningful in the selected server/profile context. Backup/restore or server rescans can make saved channels stale.

**Adjudication:** Persist rating keys as server/profile-scoped opaque identifiers, add stale/missing validation and recovery states, and document import/export caveats before shipping backup/restore. Do not promise portable channel backups in core authoring.

### Finding 5: Custom logo import can leak filesystem paths

**Risk:** File imports often expose local paths in renderer, logs, diagnostics, support bundles, or persisted config.

**Adjudication:** Do not implement file logo import in the core package. Use built-in icons/colors/initials first. File import requires a later main-owned package with copied app-cache files, opaque logo IDs, metadata stripping, path redaction, and import/export semantics.

### Finding 6: Normal Plex-client browsing can be performance-heavy

**Risk:** Large libraries may cause unbounded Plex requests, renderer memory growth, slow DOM rendering, or stale results overwriting current state.

**Adjudication:** Enforce pagination, result limits, stale operation epochs, lazy artwork loading, and incremental “Load more” behavior. Do not render unbounded full-library grids. Keep selection state in maps keyed by safe rating key/source ID.

### Finding 7: Advanced scheduling may outpace scheduler proof

**Risk:** Exposing cyclic/daypart/rating windows/commercials before deterministic scheduler support creates fake UI and user confusion.

**Adjudication:** Core UI exposes only scheduling options the existing domain/scheduler can honor. Advanced modes are Package 7 follow-ups with domain tests and guide/player proof.

### Finding 8: UI might repeat QuasiTV friction

**Risk:** If Add buttons are detached from results or duplicate membership is hidden, channel editing becomes frustrating.

**Adjudication:** Inline Add/Remove controls and card membership badges are non-negotiable acceptance criteria. The selection cart must remain visible while browsing/searching.

### Finding 9: Contract tests could become too implementation-specific

**Risk:** Broad DOM snapshots or private helper probes will make refactors painful without improving safety.

**Adjudication:** Test public seams, contract guards, view-model outputs, action-controller behavior, focus/back semantics, and safe DOM properties. Avoid broad snapshots and private helper assertions unless no public seam exists.

### Finding 10: Full feature scope may delay any user value

**Risk:** Trying to ship every advanced feature at once can block the core custom channel workspace.

**Adjudication:** Use reviewed packages. The first user-visible milestone is create/edit/delete/duplicate/hide/reorder plus media picker/cart and guide refresh. Import/export, custom file logos, daypart schedules, cyclic shuffle, and interstitials follow once the core feature is verified.

## Implementation Handoff

```text
MODEL_SUGGESTION
PLANNER: gpt-5.5
IMPLEMENTER: gpt-5.5
REVIEWER: gpt-5.5
WHY: Tier 3 cross-boundary work touches contracts, IPC/preload, persistence, Plex/artwork redaction, renderer UI, scheduler refresh, and multiple hotspot owners.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop
TASK: Implement User-Created Custom Channels Through Quality Loop
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: /mnt/data/lineup-desktop-custom-channels-implementation-plan.md or docs/plans/<date>-custom-channels-plan.md after promotion
ARTIFACT: reviewed custom channels implementation plan
FILES:
- src/contracts/customChannels.ts
- src/contracts/artwork.ts
- src/contracts/ipc.ts
- src/contracts/shell.ts
- src/domain/channel/**
- src/main/channel/customChannel*.ts
- src/main/artwork/**
- src/preload/customChannel*.cts
- src/renderer/customChannels/**
- src/renderer/styles/custom-channels.css
- src/__tests__/**/customChannel*.test.ts
BLOCKERS: Plan requires read-only review before source edits.
MESSAGE:
Start with Package 0. Confirm branch initial-build with git status, read the required docs/source owners, run npm run verify:maintainability for baseline, promote or reference this plan as the active durable handoff, request read-only plan review, adjudicate findings, then implement Package 1 only. Do not modify renderer, preload, main, persistence, or artwork code before the plan review is clean. Keep renderer unprivileged, add no generic IPC, expose no raw Plex image keys/URLs/tokens/headers/paths, and split each package into a focused commit with observed verification.
```

## Source Notes

This plan used these reference surfaces:

- Lineup Desktop repository docs and source on branch `initial-build`, especially `AGENTS.md`, `docs/AGENTIC_DEV_WORKFLOW.md`, `docs/agentic/plan-authoring-standard.md`, `docs/architecture/CURRENT_STATE.md`, `docs/architecture/renderer-architecture.md`, and the current channel/Plex/renderer source owners.
- QuasiTV official site and image gallery, checked 2026-06-12, as product/UX reference for virtual live-TV channel creation, guide/player/search/channel-creator surfaces, and backup/restore caveats.
- NostalgiaTV public Reddit release thread, checked 2026-06-12, as product/community context for Plex-backed virtual channel expectations, custom channel configuration, logos, sorting methods, import/export, and the specific QuasiTV UI friction around distant Add controls and missing duplicate membership status.
- Public GitHub repository search metadata, checked 2026-06-12, for open-source media-client references including Jellyfin web clients, archived Plex Media Player, PlexKodiConnect, and ErsatzTV-related repositories. These are reference-only and not import targets.
