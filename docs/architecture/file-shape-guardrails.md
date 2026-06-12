# File Shape Guardrails

Lineup Desktop treats file shape as an architecture surface. Large files are not
forbidden, but unreviewed growth in composition roots, runtime owners, contracts,
and CSS makes later feature work harder to review and easier to couple.

## Policy

- Production files under `src/**` over 500 lines require a temporary row in the
  allowlist below. The row records a reviewed baseline line count. Current line
  count may shrink below that baseline, but it must not grow above it without a
  reviewed update to this file.
- Files over 800 lines are hard-overage files. They need an explicit
  decomposition trigger before further feature behavior grows that owner.
- Rows are not permanent exceptions. Remove a row when the file drops to 500
  lines or below.
- Row updates are review decisions, not bulk bookkeeping. Do not raise a
  baseline to pre-authorize future growth; raise it only with the source change
  that needs the additional size and record why decomposition is not the better
  move yet.
- New Tier 3 plans must include an `## Architecture Health` section with current
  large-file evidence, affected owner hotspots, and decomposition, avoidance, or
  allowlist decisions before implementation unit selection.
- Run `npm run verify:maintainability` after changing production source shape or
  this guardrail.

## Current Allowlist

| Path | Baseline lines | Rationale | Growth/decomposition trigger |
| --- | ---: | --- | --- |
| src/main/player/desktopPlayerAdapter.ts | 553 | The adapter remains the main-owned player command/snapshot/event boundary after ARCH-02 moved request custody to `src/main/player/playerAdapterRequestCustody.ts` and native-helper process/protocol framing to focused owners. | Split adapter state projection or event mapping before adding new player command families, helper capabilities, or renderer-facing diagnostics. |
| src/domain/channel/channelManager.ts | 1022 | RD-11 channel manager currently owns transactional channel mutation, persistence coordination, current-channel custody, and event emission invariants in one pure domain owner; comment-only seam documentation clarifies mutation serialization and current-channel persistence limits. | Split mutation queue, current-channel selection, and persistence coordination before adding live channel editing workflows or backup/restore behavior. |
| src/main/player/plexPlaybackRuntime.ts | 550 | The playback runtime remains the main-owned scheduler/channel-to-player orchestration owner after ARCH-02 moved cleanup sequencing to `src/main/player/plexPlaybackRuntimeCleanup.ts` and `src/main/player/plexPlaybackCleanupWiring.ts`. | Split runtime transition handling or player dispatch coordination before new scheduler playback transitions, helper lifecycle behaviors, or Plex transport modes grow this file. |
| src/domain/channel/channelRepository.ts | 770 | RD-11 repository owns channel import normalization, source resolution, cache behavior, and stale fallback semantics in a pure domain owner; comment-only seam documentation records the normalization/repair mutation signal. | Split cache/source resolution from import normalization before live library browsing or persisted channel editing expands the repository. |
| src/contracts/player.ts | 724 | RD-07/RD-12 player contract vocabulary is intentionally centralized to keep renderer-safe command, event, snapshot, error, and guard vocabulary aligned; comment-only seam documentation clarifies forbidden-field guard limits. | Split stable sub-vocabularies only when a new public player contract family is added and parity tests can protect each module. |
| src/main/plex/streamResolver.ts | 663 | RD-12/RD-25 stream resolver maps injected Plex media details into private playback descriptors and renderer-safe load payloads while keeping privileged setup private. | Split candidate mapping from descriptor projection before additional stream modes, playback descriptor variants, or resolver policy branches are introduced. |
| src/main/player/streamPolicy/desktopStreamPolicy.ts | 624 | RD-08/RD-16 stream policy keeps capability-driven direct play, direct stream, transcode, fallback, and unsupported decision logic together for deterministic fixture proof; comment-only seam documentation states the explicit-reason/unknown contract. | Split decision phases before adding new codec families, platform capability matrices, subtitle/audio policy branches, or preferred-language policy. |
| src/preload/index.cts | 1767 | The sandbox-compatible preload entrypoint still owns the single `lineupDesktop` exposure and `ipcRenderer` calls, while ARCH-02 moved channel constants to `src/preload/channels.cts` and diagnostics guard families to `src/preload/diagnosticsBridgeGuards.cts`. | Split additional bridge guard families before any next growth in validation families, new bridge namespaces, or additional renderer-safe RPC arguments. |
| src/contracts/diagnostics.ts | 553 | RD-17 centralizes diagnostics schema, renderer event envelopes, support-bundle result vocabulary, renderer-safe request-id and context-value shape, redaction labels, and sanitizer helpers while the diagnostics/support boundary is still being frozen across main, preload, player, and renderer seams. | Split sanitizer helpers from renderer-safe public vocabulary before adding another diagnostics schema version, export artifact family, scanner taxonomy, or non-RD-17 diagnostics surface. |
| src/main/persistence/desktopPersistenceStore.ts | 625 | RD-22 Unit 2C keeps encrypted credential persistence, legacy selected-server compatibility, active-profile scoped selected-server summary persistence, and exact-shape selected-server sanitization in the RD-09 main-owned store while no separate schema/migration owner exists yet. | Split selected-server persistence records or schema parsing helpers out before adding another persisted state family, migration path, backup/restore behavior, or renderer-visible persistence snapshot expansion. |
| src/main/plex/desktopPlexRuntime.ts | 551 | The Plex runtime remains the main-owned auth/discovery/selection coordinator after ARCH-02 moved operation stale/cancel/error custody to `src/main/plex/plexRuntimeOperationOwner.ts` and library browse/search/metadata execution to `src/main/plex/desktopPlexLibraryOperationExecutor.ts`. | Split server-selection/profile-switch orchestration from remaining runtime coordination before adding renderer onboarding, broader Plex runtime APIs, playback selection flows, another profile-scoped runtime behavior, or another library operation family. |
| src/domain/channel/channelAuthoringService.ts | 521 | Channel authoring keeps validation, draft normalization, and safe update shaping together while channel workflows remain pure and runtime-free. | Extract validation helpers before adding richer channel setup persistence or live library-driven authoring. |
| src/renderer/epg.ts | 725 | Renderer EPG currently keeps injected-presentation normalization, deterministic slot math, guide rendering view-model projection, and local action/selection behavior together in one renderer-only owner so the injected-schedule hardening remains reviewable in a single seam. The 2026-06-11 growth is limited to a no-selectable-program empty-state guard and focused regression proof. | Split presentation normalization/bounds from cell projection before adding live scheduler-backed guide data, another guide state family, or more renderer route-specific EPG behavior. |
| src/renderer/routeDom.ts | 518 | Route-level DOM orchestration currently carries a compact set of route-specific render branches and guide shell composition paths together while parity polish and static binding coverage are in one place for this milestone. | Extract guide-dedicated rendering into dedicated route helpers before adding additional route families, guide interaction families, or further parity-driven template branches. |
| src/renderer/index.ts | 511 | Main entrypoint of the renderer orchestration. Keeps route activation, action handling, gamepad, keyboard bindings, and lifecycle listeners in one place. | Extract gamepad, keyboard listeners, or action routing helpers before adding more route families or onboarding steps. |


### Preload Bridge Allowlist Note

ARCH-01 keeps guard vocabulary in the sandbox-compatible preload entrypoint while
the parity/shape harness checks channel constants, the single `lineupDesktop`
exposure, and approved `ipcRenderer` method/channel pairs against renderer-safe
IPC contracts without importing or executing preload.
