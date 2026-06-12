# RD-26 Runtime Media Options And Playback Quality Plan

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3
**Repository:** `TJZine/LineupDesktop`
**Branch:** `initial-build`
**Roadmap item:** `RD-26 Runtime Media Options And Playback Quality`
**Intended tracked path:** `docs/plans/2026-06-11-rd-26-runtime-media-options-playback-quality-plan.md`
**Created:** 2026-06-11 America/New_York

## Goal

Implement RD-26 as the first production-path runtime media-options slice after RD-25: runtime audio-track selection, subtitle selection/off/default/forced behavior, audio fallback presentation, HDR/playback-quality status, and renderer-safe media-option UI over the production native playback path.

RD-26 must close the roadmap exit gates for runtime subtitle/audio/HDR behavior beyond fixtures and policy tests, with Windows proof for live runtime media-option selection, fallback behavior, and video/UI composition.

The implementation must make one product decision up front and carry it through every unit:

- Renderer owns presentation, focus, and user intent only.
- Preload continues to expose the existing narrow `window.lineupDesktop.player.dispatch`, `getSnapshot`, `cleanup`, `tuneChannel`, and `onEvent` bridge unless a reviewed contract gap makes a smaller typed addition unavoidable.
- Main/player owns renderer-originating command validation, request custody, stale-event quarantine, public contract projection, diagnostics redaction, and helper lifecycle normalization.
- Main/Plex resolver and stream-policy owners own Plex media facts, policy decisions, public track IDs, and private Plex stream ID mapping.
- The native helper owns libmpv state, effective mpv track IDs, runtime track observation, track switching, HDR/video-parameter observation, and conversion of private setup into renderer-safe player events.
- Public renderer IDs stay opaque. Plex stream IDs, mpv track IDs, URLs, headers, native handles, raw payloads, and helper logs never enter renderer/preload contracts, tracked docs, diagnostics, or proof summaries.

Preflight assumption: the user states RD-25 has just finished. Some repository docs observed during plan authoring still described RD-25 as code-complete/manual-proof-pending. Before implementation starts, reconcile `docs/roadmap/desktop-port-roadmap.md`, `docs/architecture/CURRENT_STATE.md`, and `docs/architecture/playback-architecture.md` with the actual RD-25 closeout evidence. If RD-25 is not complete and reviewed, stop and route back to RD-25 proof/closeout.

## Non-Goals

- Do not implement public packaging, signing, update channels, installer behavior, package lifecycle proof, or native/media binary redistribution.
- Do not add package dependencies, lockfile changes, or package scripts for RD-26. Use existing TypeScript, Electron, Node, C#/.NET, and libmpv seams.
- Do not broaden Plex browsing, auth, profile, server, library, scheduler, channel-authoring, or persistence APIs.
- Do not persist preferred language, preferred subtitle, HDR preference, audio preference, or playback-quality settings. RD-26 selections are per active playback request only.
- Do not add renderer-owned browser storage, filesystem access, Electron APIs, Node APIs, native handles, Plex transport policy, or secure-storage policy.
- Do not expose raw Plex stream IDs, raw Plex part keys, raw stream keys, tokenized URLs, auth headers, selected connection URI/address/port, mpv track IDs, libmpv objects, native handles, raw helper stdout/stderr, crash dumps, process IDs, local paths, or private media titles in renderer-facing state, diagnostics, tests, plans, proof docs, or Codex output.
- Do not claim codec, container, HDR passthrough, Dolby Vision, subtitle rendering, or Plex HTPC parity beyond the exact Windows sample matrix observed during RD-26.
- Do not backfill missing RD-22A through RD-25 parity work except for media-option UI behavior owned by RD-26. Route missing upstream UI parity outside media options back to the owning slice or a reviewed follow-up.
- Do not use the RD-05 external `mpv` POC as production architecture. Any external `mpv` use remains private disposable evidence only.
- Do not preserve static/fake playback-option controls in the reachable product player route after RD-26 owns that surface. Fake data may remain in tests or explicit dev-only fixtures only.

## Parent Architecture Alignment

RD-26 is Tier 3 work because it crosses renderer UI, preload/player IPC validation, main/player adapter and runtime, Plex stream resolution, native helper/libmpv behavior, diagnostics/redaction, and Windows manual proof.

Architecture alignment decisions:

1. **Renderer/preload boundary**
   - Keep renderer unprivileged.
   - Reuse the existing player bridge when possible: `dispatch`, `getSnapshot`, `cleanup`, `tuneChannel`, `onEvent`.
   - Renderer actions for media options must dispatch existing player intents: `player.selectAudio`, `player.selectSubtitle`, `player.setVolume`, and `player.setMute` only when their behavior is already in the player contract.
   - Do not add a broad `mediaOptions` RPC namespace, arbitrary channel strings, or a preload method that accepts raw option names.

2. **Public player contract**
   - `PlayerTrackId` remains the only renderer-facing track identity.
   - `PlayerTrackSummary` remains renderer-safe and may be extended only with stable display-safe fields needed for upstream media-option parity.
   - If HDR/playback-quality status requires a new contract family, add a small renderer-safe `PlayerPlaybackQualitySummary` family and wire it through `PlayerSnapshot`/events. Do not put private setup or engine details into this family.
   - Split stable quality helpers out of `src/contracts/player.ts` if adding the new family would meaningfully grow the already allowlisted player contract file.

3. **Main/player ownership**
   - `DesktopPlayerAdapter` must validate renderer-originating track selections against the current renderer-safe snapshot before calling the helper. Unknown, stale, wrong-kind, unavailable, or cross-request track IDs fail safely with a renderer-safe `track-failure` or `validation-failure` error.
   - Do not add another command-dispatch owner. If validation logic is non-trivial, extract it to a small same-owner helper such as `src/main/player/playerTrackSelectionValidation.ts` rather than growing `desktopPlayerAdapter.ts`.
   - Main may hold public track IDs and request IDs. Main must not need raw mpv IDs to validate renderer commands.

4. **Plex resolver/private setup ownership**
   - Keep public and private track identity separate.
   - Extend only private setup types, if needed, to carry request-scoped public-to-private track mapping from the selected Plex part into the helper. This mapping is private main/helper material and must not appear in `PlayerSnapshot`, `PlayerEvent`, diagnostics, preload guards, renderer view models, tests, proof docs, or support bundles.
   - Stream policy remains the authority for default, forced, fallback, unsupported, and burn-in/conversion decisions before load. RD-26 proves the runtime path honors those decisions after production playback starts.

5. **Native helper/libmpv ownership**
   - The helper owns effective mpv track IDs and maps them back to public `PlayerTrackId` values before emitting events.
   - On load, the helper must set initial audio/subtitle selection using private IDs from the privileged setup. Subtitle off maps to mpv `sid=no`. Audio off is not an MVP option unless policy explicitly supports it; do not expose it in renderer UI.
   - The helper must observe enough libmpv properties to produce safe runtime track state and quality state. At minimum: effective audio selection, effective subtitle selection, track list or equivalent track facts, video parameters needed for HDR status, time, duration, pause/core-idle as currently observed.
   - The helper must use libmpv command/property APIs with separate arguments, not command-string concatenation.
   - Helper stdout must contain only NDJSON protocol results/events. Helper stderr remains dropped/redacted.

6. **HDR/playback-quality posture**
   - RD-26 may display renderer-safe HDR/playback-quality status such as `SDR`, `HDR10 observed`, `Dolby Vision source observed`, `tone-mapped/unknown/unproven`, `direct play`, `direct stream`, `transcode`, codec labels, and fallback reasons.
   - RD-26 must not claim true HDR passthrough, display HDR mode, Dolby Vision rendering, or Windows compositor correctness unless the Windows proof matrix observes that exact behavior with an approved redaction-safe sample and records the scope.
   - If helper/libmpv cannot prove HDR output status reliably, expose `unknown` or `unproven` in renderer-safe UI instead of inventing a positive status.

7. **Review and closeout**
   - Plan review must be clean before implementation.
   - Each execution unit must receive read-only implementation review before the next unit starts unless the quality-loop controller records a reviewed reason to combine units.
   - Windows proof is required before RD-26 closeout.

## Required Reading

Read in this order before editing:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-quality-loop.md`
4. `docs/agentic/plan-authoring-standard.md`
5. `docs/architecture/CURRENT_STATE.md`
6. `docs/roadmap/desktop-port-roadmap.md`, especially RD-25, RD-26, Platform Proof Convention, MVP Build Posture, and Upstream UI Parity Distribution
7. `docs/architecture/security-and-secret-flow.md`
8. `docs/architecture/playback-architecture.md`
9. `docs/architecture/file-shape-guardrails.md`
10. `docs/architecture/import-ledger.md`
11. `docs/product/lineup-product-parity-matrix.md`
12. `docs/development/windows-ui-proof-plan.md`
13. Player contracts and bridge:
    - `src/contracts/player.ts`
    - `src/contracts/ipc.ts`
    - `src/contracts/shell.ts`
    - `src/preload/index.cts`
    - `src/__tests__/integration/preloadContractVocabulary.test.ts`
    - `src/__tests__/contracts/contracts.test.ts`
14. Main/player and Plex playback owners:
    - `src/main/player/desktopPlayerAdapter.ts`
    - `src/main/player/nativePlayerHostPort.ts`
    - `src/main/player/nativePlayerHostProcess.ts`
    - `src/main/player/nativeHelperProtocol.ts`
    - `src/main/player/nativeHelperPlaybackSetup.ts`
    - `src/main/player/productionNativeHostFactory.ts`
    - `src/main/player/privilegedPlaybackDispatchContext.ts`
    - `src/main/player/plexPlaybackRuntime.ts`
    - `src/main/player/plexPlaybackBridge.ts`
    - `src/main/player/plexPlaybackComposition.ts`
    - `src/main/player/playbackRuntimeBootstrap.ts`
    - `src/main/plex/streamResolver.ts`
    - `src/main/plex/streamResolverComposition.ts`
    - `src/main/plex/playbackMediaDetailPort.ts`
    - `src/main/plex/pmsPlaybackSessionPort.ts`
    - `src/main/player/streamPolicy/desktopStreamPolicy.ts`
    - `src/main/player/streamPolicy/types.ts`
15. Native helper:
    - `src/native-helper/Lineup.NativePlayerHost/Lineup.NativePlayerHost.csproj`
    - `src/native-helper/Lineup.NativePlayerHost/Program.cs`
    - Any RD-25 helper files added after this plan was authored
16. Renderer media-option UI owners:
    - `src/renderer/index.ts`
    - `src/renderer/overlays.ts`
    - `src/renderer/overlayViewModels.ts`
    - `src/renderer/routeDom.ts`
    - `src/renderer/staticDom.ts`
    - `src/renderer/domBindings.ts`
    - `src/renderer/styles/player-overlays.css`
    - `src/__tests__/renderer/overlays.test.ts`
    - Any RD-25 playback-control renderer tests added after this plan was authored
17. Upstream Lineup references for import/adaptation evidence:
    - `src/modules/ui/playback-options/**`
    - `src/modules/ui/player-osd/**`
    - `src/modules/ui/now-playing-info/**`
    - Any upstream tests or CSS that exercise audio/subtitle/HDR media-option menus, selected/off/default/forced states, unavailable rows, focus/back behavior, and playback-quality labels
18. Official external docs checked during plan authoring, and to recheck if local libmpv behavior differs:
    - mpv manual `master`, checked 2026-06-11, sections for `track-list`, `--aid`, `--sid`, command array APIs, observed property-change events, `video-params`, `target-colorspace-hint`, tone mapping, and HDR peak detection.
    - Treat this as implementation guidance only. The local Windows libmpv build used by RD-25/RD-26 is the runtime source of truth for proof.

## Required Skills

- `execution-plan-authoring`: required for this active Tier 3 plan shape, seam decisions, bounded execution units, replan triggers, verification, rollback, and commit checkpoints.
- `verification-strategy`: required because RD-26 cannot close from unit tests alone; it needs contract tests, runtime integration proof, redaction proof, Electron smoke, helper build/protocol proof, and Windows manual proof.
- `architecture-boundaries`: required because RD-26 touches renderer, preload, contracts, main/player, Plex resolver, helper process, and native helper ownership.
- `plex-integration-boundaries`: required because public track IDs are derived from Plex media details while private Plex stream IDs, URLs, headers, selected connections, and tokens must remain in main/helper custody.
- `ui-composition-patterns`: required because RD-26 owns media-option presentation, focus/back behavior, keyboard/remote-like interactions, overlay composition over native video, reduced-motion/accessibility-safe presentation, and retirement of fake/static option rows from the product route.
- `review-request`: required for plan review and each implementation review packet.
- `closeout-verification`: required before staging, committing, handoff, roadmap updates, architecture updates, import-ledger updates, or closeout claims.

## Evidence And Discovery

Authoring evidence captured before this plan:

- `AGENTS.md` says `docs/AGENTIC_DEV_WORKFLOW.md` is the operating runbook, active durable plans live in `docs/plans/*` only while needed, copied/adapted upstream source must be recorded in `docs/architecture/import-ledger.md`, `npm run verify:docs` is required for plan/reference doc changes, and `npm run verify` is required before implementation work is called complete unless a plan names a narrower surface.
- `docs/AGENTIC_DEV_WORKFLOW.md` classifies native playback, Electron IPC/security, persistence/secrets, packaging/release, broad imports, and cross-boundary feature work as Tier 3 by default, requires plan/review/implement/review/verify/closeout, and requires visual/browser evidence for UI work that can regress layout, focus, interaction, media surface, or accessibility behavior.
- `docs/agentic/plan-authoring-standard.md` requires this active-plan marker, exact headings, `Task family`, an evidence trail, required skills, architecture-health handling for Tier 3, exact verification commands, acceptance criteria, replan triggers, rollback notes, and commit checkpoints.
- `docs/roadmap/desktop-port-roadmap.md` defines RD-26 as dependent on RD-25 complete/reviewed plus RD-16 complete, and requires Windows proof for runtime media option selection, fallback behavior, and video/UI composition.
- `docs/roadmap/desktop-port-roadmap.md` also says RD-26 owns subtitle/audio/HDR option UI and playback-quality controls; upstream media-option presentation and interaction patterns must be imported or adapted only after runtime media-option behavior is real and renderer-safe.
- `docs/architecture/CURRENT_STATE.md` currently records RD-23 and RD-24 complete and RD-25 code implemented/manual proof pending; the user says RD-25 has just finished. This discrepancy is a preflight blocker unless reconciled before implementation.
- `docs/architecture/playback-architecture.md` records RD-16 public/private track identity hardening and RD-25 production native playback code flow: private playback descriptors pass through main-owned runtime/adapter into the C# helper over NDJSON, while renderer UI receives only safe player events.
- `src/contracts/player.ts` already has player commands for audio and subtitle selection, renderer-safe track summaries, selected audio/subtitle/video IDs in snapshots, `tracks.changed`, and `track.selection.changed` events.
- `src/contracts/ipc.ts` already has renderer intents `player.selectAudio` and `player.selectSubtitle`, and player IPC channels for command, snapshot, cleanup, and event delivery.
- `src/preload/index.cts` already exposes a narrow `window.lineupDesktop.player.dispatch` bridge, validates player events and snapshots before renderer listener delivery, and denies known privileged fields recursively.
- `src/main/player/desktopPlayerAdapter.ts` already maps renderer intents into closed player commands, validates host events, rejects renderer-originated loads in production native mode, quarantines stale request IDs, and normalizes helper failures.
- `src/main/player/nativePlayerHostProcess.ts` already serializes private setup to the helper only for load commands, validates message size, drops helper stderr as redacted diagnostics, and rejects malformed/privileged helper output.
- `src/main/player/nativeHelperPlaybackSetup.ts` currently carries selected public track IDs and selected private track IDs only for the selected tracks. RD-26 likely needs request-scoped mapping for all selectable tracks on the selected part if the helper cannot reconstruct public IDs from libmpv alone.
- `src/main/plex/streamResolver.ts` already maps Plex media parts into deterministic public track IDs such as `plex-track-audio-*` and maps selected public IDs back to private Plex stream IDs for the selected tracks.
- `src/native-helper/Lineup.NativePlayerHost/Program.cs` currently loads media, sets headers privately, observes time/duration/pause/core-idle, emits baseline playback/media events, but does not yet implement audio/subtitle selection commands or track-list/HDR event projection.
- `src/renderer/overlayViewModels.ts` and `src/renderer/overlays.ts` currently have static/fake `PLAYBACK_AUDIO_TRACKS` and `PLAYBACK_SUBTITLE_TRACKS` arrays and renderer-local cycle behavior for playback options. RD-26 must replace those product-route controls with runtime snapshot-backed tracks and dispatch-backed actions.
- `src/__tests__/renderer/overlays.test.ts` currently verifies static/fake playback option cycling; RD-26 must revise this coverage to prove runtime track rows, off/default/forced/unavailable labels, focus behavior, redaction-safe output, and dispatch intent shape.
- `docs/architecture/file-shape-guardrails.md` records multiple hotspots relevant to RD-26, including `src/main/player/desktopPlayerAdapter.ts`, `src/main/player/plexPlaybackRuntime.ts`, `src/contracts/player.ts`, `src/main/plex/streamResolver.ts`, `src/main/player/streamPolicy/desktopStreamPolicy.ts`, `src/main/player/nativePlayerHostProcess.ts`, `src/preload/index.cts`, and `src/renderer/index.ts`.

Discovery method and required implementation refresh:

- `semantic_search_with_context`: not available during this artifact authoring pass. The implementation controller must run Codanna or the repo-preferred semantic search in the local checkout before freezing Unit 1 scope. Record fallback if the index is unavailable, stale, or too noisy.
- `semantic_search_docs` or repo-doc search: GitHub connector direct reads and file searches were used for roadmap, workflow, plan standard, skills, architecture docs, contracts, preload, main/player, stream resolver, renderer overlays, native helper, and tests. Local implementation must repeat with Codanna/`rg` because branch state may have changed after this downloadable plan was generated.
- Impact analysis: not run by tool. The implementation controller must run targeted impact queries for `PlayerTrackSummary`, `PlayerSnapshot`, `PlayerEvent`, `PlayerRendererIntent`, `NativePlayerHostEvent`, `NativeHelperPlaybackSetup`, `PlexPrivilegedPlaybackDescriptor`, `createPlayerOverlayView`, `applyPlayerOverlayAction`, `Lineup.NativePlayerHost`, and any RD-25 proof tooling before editing.
- Direct reads / `rg`: direct GitHub reads were used in place of local `rg`. Local implementation must run at least:
  - `git status --short --branch`
  - `rg "PlayerTrackSummary|selectedAudioTrackId|selectedSubtitleTrackId|tracks.changed|track.selection.changed|PlayerPlayback|quality" src docs tools`
  - `rg "PLAYBACK_AUDIO_TRACKS|PLAYBACK_SUBTITLE_TRACKS|togglePlaybackOptions|cycleAudioTrack|cycleSubtitleTrack" src/renderer src/__tests__`
  - `rg "NativeHelperPlaybackSetup|selectedPrivateTrackIds|track\.audio\.select|track\.subtitle\.select|aid|sid|track-list|video-params|target-colorspace|tone" src/native-helper src/main src/__tests__ tools docs`
- Official docs: mpv manual `master` was checked on 2026-06-11 for track and HDR/property behavior. The implementer must verify the installed Windows libmpv version behavior with local proof instead of relying on manual text alone.

## Impact Snapshot

Expected owners that may change:

- `src/contracts/player.ts` and possibly a new split contract helper for renderer-safe playback quality vocabulary.
- `src/contracts/ipc.ts` only if existing player intents are insufficient. Preferred outcome: no IPC literal additions.
- `src/contracts/shell.ts` only if player bridge type signatures change. Preferred outcome: no new bridge namespace.
- `src/preload/index.cts` only if the public player event/snapshot/track/quality shape changes. Any preload change must stay narrow and guarded.
- `src/main/player/desktopPlayerAdapter.ts`, with extraction required for non-trivial track-selection validation.
- `src/main/player/nativePlayerHostPort.ts`, `nativePlayerHostProcess.ts`, `nativeHelperProtocol.ts`, and `nativeHelperPlaybackSetup.ts` for helper event/protocol/private setup changes.
- `src/main/player/privilegedPlaybackDispatchContext.ts` if private setup validation must include full track mapping.
- `src/main/plex/streamResolver.ts` and related stream-policy types if all-track public/private mapping or quality metadata projection is needed.
- `src/native-helper/Lineup.NativePlayerHost/**` for libmpv track list observation, track selection commands, HDR/video-parameter observation, and helper decomposition.
- `src/renderer/overlayViewModels.ts`, `src/renderer/overlays.ts`, `src/renderer/index.ts`, `src/renderer/domBindings.ts`, `src/renderer/routeDom.ts`, `src/renderer/staticDom.ts`, and `src/renderer/styles/player-overlays.css` for runtime-backed media-option presentation and dispatch.
- Focused tests under `src/__tests__/contracts/**`, `src/__tests__/integration/**`, `src/__tests__/main/**`, `src/__tests__/renderer/**`, and optional helper/proof tooling tests under `tools/__tests__/**`.
- `docs/architecture/import-ledger.md` if any upstream media-option UI/CSS/copy/tests are copied or adapted.
- `docs/architecture/CURRENT_STATE.md`, `docs/architecture/playback-architecture.md`, `docs/roadmap/desktop-port-roadmap.md`, and possibly `docs/development/windows-ui-proof-plan.md` during closeout only.
- Local ignored proof output under `docs/runs/rd-26-runtime-media-options-playback-quality/**`.

Expected public contract changes:

- Prefer no new IPC channels.
- Likely add renderer-safe playback quality/status vocabulary if HDR/playback-quality cannot be accurately represented by existing snapshot fields.
- Additions must be closed unions or exact object shapes with recursive forbidden-field checks.
- Event additions must update both contract guards and preload guards.

Dependency, build-tool, configuration, package, or lockfile changes:

- None allowed for RD-26.
- `.csproj` changes are allowed only for same-project source organization if needed, not new package references.

Commands/tests/docs likely to change:

- Focused player contract and redaction tests.
- Focused main/player/native-host tests for track selection, stale IDs, unsupported IDs, helper failures, and private mapping redaction.
- Focused stream resolver/policy tests if all-track mapping or quality projection changes.
- Focused renderer overlay tests for runtime rows, off/default/forced/unavailable states, HDR/quality rows, focus/back, dispatch, and no privileged fields.
- Integration/preload vocabulary parity tests if preload guards or public player contract vocabulary changes.
- Native helper build proof and local Windows manual proof.
- Docs verifier if plan, architecture, roadmap, import ledger, or proof-plan docs change.

User-visible/runtime behavior that must not regress:

- Existing RD-22B onboarding/library runtime.
- RD-23 channel setup/persistence.
- RD-24 scheduler-backed guide and tune flow.
- RD-25 playback lifecycle: load, play, pause, stop, switch/tune, fullscreen, cleanup, helper crash recovery, PMS release.
- Renderer input/focus/back/fullscreen behavior.
- Support bundle redaction.
- Safe failure behavior when no media options are available.

Local-only artifacts that must stay untracked:

- Raw Windows proof logs, screenshots, videos, local sample names, PMS server/account/media names, token-bearing URLs, raw helper stdout/stderr, crash dumps, process lists, local paths, package output, native binaries, and `docs/runs/rd-26-runtime-media-options-playback-quality/**` raw bundles.

The work crosses multiple owners and cannot be closed as a single layer-only patch. Execute it as bounded vertical units so the product route progressively moves from static/fake media-option controls to real runtime behavior without leaving scaffold UI in the reachable app.

## Architecture Health

Tier 3 architecture-health preflight is mandatory before implementation-unit selection.

Current known guardrail hotspots relevant to RD-26 from `docs/architecture/file-shape-guardrails.md`:

- `src/preload/index.cts`: hard-overage, sandbox-compatible bridge guard owner. Do not grow it unless the public player contract changes. If it grows, keep additions small, data-only, and covered by preload vocabulary tests. Do not add a new namespace or broad RPC pattern.
- `src/main/player/desktopPlayerAdapter.ts`: hard-overage adapter owner. Do not add large track-selection validation or quality projection directly here. Extract non-trivial logic to focused files under `src/main/player/`.
- `src/main/player/plexPlaybackRuntime.ts`: near hard-overage. RD-26 should not grow runtime orchestration unless media-option commands need runtime cleanup/stale handling beyond existing player dispatch. Prefer adapter/helper ownership.
- `src/contracts/player.ts`: allowlisted. If a new quality family is needed, prefer a small split such as `src/contracts/playerQuality.ts` imported by `player.ts` rather than expanding player contract with unrelated helper functions.
- `src/main/plex/streamResolver.ts`: allowlisted. If all-track public/private mapping is needed, extract mapping helpers such as `src/main/plex/streamTrackMapping.ts` rather than growing resolver policy/projection in place.
- `src/main/player/streamPolicy/desktopStreamPolicy.ts`: allowlisted. Do not add runtime proof or UI policy here; keep it deterministic policy only.
- `src/main/player/nativePlayerHostProcess.ts`: allowlisted. Keep process IO/framing ownership here; do not add track/HDR business logic. Protocol validation belongs in small helpers or the adapter/native-helper boundary.
- `src/renderer/index.ts`: allowlisted. Do not add bulky media-option orchestration here. Create a focused renderer owner such as `src/renderer/playerMediaOptionsRuntime.ts` or `src/renderer/playerMediaOptionActions.ts` for dispatch and view-state helpers, and call it from `index.ts`.
- `src/renderer/overlayViewModels.ts` and `src/renderer/overlays.ts`: currently not allowlisted, but RD-26 may grow them. Split if either crosses 500 lines or if playback-option view model logic becomes hard to review.
- `src/native-helper/Lineup.NativePlayerHost/Program.cs`: not covered by TypeScript file-shape guardrails but already monolithic. Before adding significant track/HDR logic, split helper code into focused same-project files, for example:
  - `MpvCommand.cs` or `MpvCommandExecutor.cs` for typed `mpv_command`/property wrappers.
  - `MpvTrackState.cs` for public/private track mapping and safe event projection.
  - `MpvPlaybackQualityState.cs` for video/HDR parameter observation and quality summary projection.
  - `HelperProtocolWriter.cs` for safe result/event writing if output logic grows.

Architecture-health decisions for RD-26:

- Decision: Avoid growing hard-overage TypeScript owners by decomposing logic.
- Decision: Split and extract hotspot logic into focused helpers.
- Decision: Decompose native helper monolith before growth.
- Decision: Prefer additive focused owners with explicit tests over raising guardrail baselines.
- Decision: Do not update `docs/architecture/file-shape-guardrails.md` preemptively. Update it only if a touched production file crosses 500 lines or must grow beyond an existing baseline, and include the rationale with the same implementation unit.
- Decision: Run `npm run verify:maintainability` after every unit that changes production source shape or guardrail docs.

## Files In Scope

Plan and closeout docs:

- `docs/plans/2026-06-11-rd-26-runtime-media-options-playback-quality-plan.md`
- `docs/roadmap/desktop-port-roadmap.md` closeout status only after RD-26 evidence is observed
- `docs/architecture/CURRENT_STATE.md` closeout architecture state only
- `docs/architecture/playback-architecture.md` closeout playback architecture update only
- `docs/architecture/import-ledger.md` before or with any copied/adapted upstream media-option UI/CSS/copy/test source
- `docs/architecture/file-shape-guardrails.md` only if production file-shape thresholds require a reviewed row or row update
- `docs/development/windows-ui-proof-plan.md` only if RD-26 proof taxonomy needs a small durable media-option row for RD-27 reuse

Contracts and bridge:

- `src/contracts/player.ts`
- Potential new split contract file under `src/contracts/`, for renderer-safe playback quality vocabulary only
- `src/contracts/ipc.ts` only if existing player intents are proven insufficient
- `src/contracts/shell.ts` only if the player bridge type changes
- `src/preload/index.cts` only for player guard updates matching contract changes
- `src/__tests__/contracts/**`
- `src/__tests__/integration/preloadContractVocabulary.test.ts`

Main/player and Plex runtime:

- `src/main/player/desktopPlayerAdapter.ts`
- Potential new focused files under `src/main/player/` for track-selection validation, safe quality projection, or helper event normalization
- `src/main/player/nativePlayerHostPort.ts`
- `src/main/player/nativePlayerHostProcess.ts`
- `src/main/player/nativeHelperProtocol.ts`
- `src/main/player/nativeHelperPlaybackSetup.ts`
- `src/main/player/privilegedPlaybackDispatchContext.ts`
- `src/main/player/productionNativeHostFactory.ts` only if helper launch/proof needs a path-safe same-contract adjustment
- `src/main/player/plexPlaybackRuntime.ts` only for narrowly necessary runtime selection/stale handling
- `src/main/player/plexPlaybackBridge.ts` only if media-option selections need schedule/current-program context; otherwise leave alone
- `src/main/player/plexPlaybackComposition.ts` only for injected test wiring
- `src/main/player/playbackRuntimeBootstrap.ts` only if runtime composition must wire a new focused owner
- `src/main/player/streamPolicy/desktopStreamPolicy.ts`
- `src/main/player/streamPolicy/types.ts`
- `src/main/plex/streamResolver.ts`
- Potential new focused files under `src/main/plex/` for public/private all-track mapping
- `src/main/plex/streamResolverComposition.ts`
- `src/main/plex/playbackMediaDetailPort.ts`
- `src/main/plex/pmsPlaybackSessionPort.ts`
- Focused tests under `src/__tests__/main/**`

Native helper:

- `src/native-helper/Lineup.NativePlayerHost/Lineup.NativePlayerHost.csproj` only if same-project source organization requires it
- `src/native-helper/Lineup.NativePlayerHost/Program.cs`
- Potential new `.cs` files under `src/native-helper/Lineup.NativePlayerHost/**` for mpv command/property wrappers, track mapping, quality projection, and safe protocol output

Renderer UI:

- `src/renderer/index.ts`
- Potential new focused file under `src/renderer/` for media-option dispatch/runtime helpers
- `src/renderer/overlays.ts`
- `src/renderer/overlayViewModels.ts`
- `src/renderer/domBindings.ts`
- `src/renderer/routeDom.ts`
- `src/renderer/staticDom.ts`
- `src/renderer/styles/player-overlays.css`
- Focused renderer tests under `src/__tests__/renderer/**`

Proof tooling and local evidence:

- Existing RD-25/RD-26 proof tooling if present after preflight discovery
- Potential new `tools/rd26-media-options-smoke.mjs` only if existing proof tooling cannot cover the required matrix without unreviewable manual transcription
- Potential new `tools/__tests__/rd26-media-options-smoke.test.mjs` if a new proof tool is added
- Local ignored evidence under `docs/runs/rd-26-runtime-media-options-playback-quality/**`

## Files Out Of Scope

- `package.json`, `package-lock.json`, and dependency manifests unless a reviewed replan explicitly authorizes a package/dependency change.
- `.github/**`, CI workflow changes, public release docs, signing, updater, installer, package lifecycle, and release-gate docs except for narrow proof-plan references named above.
- `tools/mpv-poc/**` and RD-05 external `mpv` POC production wiring.
- Broad `src/main/index.ts` composition refactors unrelated to wiring a focused RD-26 owner.
- Persistence files such as `src/main/persistence/**` unless a reviewed replan changes scope to persisted media preferences. Current decision: no persistence.
- Plex auth/discovery/library UI and runtime owners except the stream resolver/media-detail path needed for active playback tracks.
- Channel setup, channel persistence, scheduler, guide, and EPG domain behavior except current-player overlay data already rendered on the player route.
- Packaging output under `out/**`.
- Raw screenshots, raw logs, raw support bundles, raw helper stdout/stderr, raw crash dumps, local media samples, tokenized URLs, server/account/profile/library/media names, local filesystem paths, and native binaries in tracked files.
- Unrelated lint, formatting, naming, or architecture cleanup.

## Planner Self-Check

1. **Is any product, architecture, ownership, dependency, or verification decision still unresolved?**
   - Product/architecture decision is frozen: per-request media options over the existing player bridge, renderer-safe public track IDs, private mapping in main/helper, helper-owned libmpv track/HDR behavior, no new dependencies, Windows proof required. The only preflight uncertainty is RD-25 documentation/evidence freshness; if unresolved, implementation must stop.

2. **Does the plan depend on adjacent files needing contract or type changes that are not in scope?**
   - No. Player contract, IPC contract, shell bridge type, preload guard, adapter, resolver, helper protocol, renderer UI, and tests are all in scope when implicated.

3. **Did the plan freeze any file out of scope while still relying on hidden wiring inside it?**
   - No. Runtime composition files are in scope only where needed. Persistence, packaging, and broad Plex browsing are out of scope because RD-26 does not require them.

4. **Did the plan record the evidence path and fallback reads?**
   - Yes. Direct repository reads and official mpv manual checks are recorded. Local implementation must repeat Codanna/`rg` discovery before editing.

5. **Is the work assigned to the repo-preferred owner, or is it growing a hotspot?**
   - Preferred owners are named. Hotspot growth must be avoided through focused helper files and renderer/main/native-helper decomposition.

6. **Did Tier 3 work include Architecture Health evidence and a decomposition, avoidance, or allowlist decision for touched owner hotspots?**
   - Yes. The Architecture Health section names affected hotspots and requires decomposition before growth.

7. **Would a fresh implementer need to invent security, IPC, playback, persistence, packaging, import, or verification policy?**
   - No. Security, IPC, playback, persistence, packaging, import, and verification policy are all explicitly constrained.

8. **Did the plan record exact verification commands, expected outcomes, and explicit stop/replan triggers?**
   - Yes. Verification commands and replan triggers are below. Windows manual proof is mandatory before closeout.

## Architecture Seam Decision Gate

Chosen seam: **RD-26 extends the existing player runtime seam; it does not create a new media-options service.**

Detailed decisions the implementer must follow:

1. **Renderer action seam**
   - Playback-option UI rows must be derived from the current `PlayerSnapshot.tracks`, selected track IDs, and renderer-safe quality status.
   - Track row selection dispatches `window.lineupDesktop.player.dispatch({ intent: 'player.selectAudio' | 'player.selectSubtitle', requestId, payload })`.
   - Subtitle off dispatches `player.selectSubtitle` with `{ trackId: null }`.
   - Renderer must not optimistically mark a track selected as final. It may show a local pending affordance, but selected state comes from the next safe player snapshot/event.
   - Renderer must disable unavailable rows and show a safe unavailable/fallback/error label instead of dispatching impossible selections.

2. **Public contract seam**
   - Keep renderer-facing track IDs opaque strings.
   - Track summaries may expose safe display fields only: label, kind, language, codec/format when already renderer-safe, channel count, delivery type, forced/default flags, selected, available, and reviewed new status labels if needed.
   - If adding `PlayerPlaybackQualitySummary`, allow only stable safe fields such as playback mode, source dynamic range, output dynamic range status, HDR status, tone-mapping status, video codec label, audio codec label, subtitle mode label, fallback reason code, and `unproven`/`unknown` states.
   - Do not expose engine ID, Plex stream ID, Plex part key, stream key, URL, header, selected connection, native handle, helper stdout/stderr, or filesystem path through public contracts.

3. **Private mapping seam**
   - Preferred implementation: add a private request-scoped all-track map to `NativeHelperPlaybackSetup`, derived by `PlexStreamResolver` from the selected candidate/part. Shape example for implementation guidance only:
     - `trackMap.audio[]`: `{ publicTrackId, privateTrackId, label?, language?, codec?, channelCount?, default? }`
     - `trackMap.subtitle[]`: `{ publicTrackId, privateTrackId, label?, language?, format?, deliveryType?, forced?, default? }`
     - `trackMap.video[]`: `{ publicTrackId, privateTrackId, codec?, dynamicRange? }`
   - This is private main/helper setup, not a renderer contract.
   - If the helper can reliably match libmpv `track-list` back to public IDs without carrying all private IDs, the implementation may keep the existing setup shape only if a plan review or replan explicitly records why the smaller shape is safer.

4. **Main validation seam**
   - Before host execution, validate selection commands against the active snapshot:
     - Active request ID must exist.
     - Audio selection must target an available audio track from the active snapshot.
     - Subtitle selection must be null/off or an available subtitle track from the active snapshot.
     - Wrong-kind, unavailable, unknown, stale, and empty IDs are rejected before helper execution.
   - Rejections produce safe player errors and `command.settled` failures without leaking the rejected value if it looks privileged.
   - Do not give renderer a reason string containing raw track IDs unless they are already validated public IDs.

5. **Native helper seam**
   - On `load`, initialize mpv and the request-scoped track map before or immediately after loading media.
   - Apply initial selected audio and subtitle IDs using private IDs from setup. Use `aid=<private audio id>` for audio, `sid=<private subtitle id>` for subtitles, and `sid=no` for subtitle off. If the selected private ID is missing or rejected by mpv, emit a safe fallback event/error and use mpv/default effective state.
   - Implement `track.audio.select` and `track.subtitle.select` command handling in the helper.
   - Translate public IDs from command payload to mpv IDs using the helper's request-scoped map. Unknown IDs produce a safe command failure with category `track-failure` or `unsupported-capability`.
   - Observe effective selection and emit `track.selection.changed` after mpv accepts a change or after effective state changes.
   - Observe/generate `tracks.changed` after media load and after track-list changes. Emit public IDs only.
   - Observe or derive HDR/playback-quality state from safe mpv properties. Unknown or unproven states must remain explicit.

6. **Forbidden shortcuts**
   - No raw `ipcRenderer` exposure.
   - No broad preload RPC.
   - No arbitrary renderer-selected mpv property names or commands.
   - No public helper command passthrough.
   - No renderer-held private track map.
   - No public `engineId`, `privateTrackId`, `streamKey`, `partKey`, URL, header, native handle, or Plex payload field under any spelling.
   - No compatibility shims or old upstream path mirrors.
   - No package/dependency changes.
   - No tracked raw proof artifacts.

Stop and replan if discovery invalidates any of these seam decisions.

## Verification Commands

broader integration/manual proof required

Run and observe these commands at the named gates. Record command, platform, exit code, and concise result in the active run bundle or closeout notes. Do not claim a command passed unless fresh output was observed.

Preflight before implementation:

```bash
git status --short --branch
npm run verify:docs
npm run verify:maintainability
```

Expected outcome: branch is `initial-build`; pre-existing changes are identified and not overwritten; docs and maintainability checks pass before source edits, or blockers are recorded.

After Unit 1 contract/private setup changes:

```bash
npm run typecheck
npm run test:contracts -- --test-name-pattern "player|preload|stream resolver|stream policy|native helper"
npm run verify:redaction
npm run verify:architecture
```

Expected outcome: player/preload/stream/native setup contract tests pass; no forbidden fields appear in renderer-safe contracts, fixtures, docs, or diagnostics; architecture lint remains clean.

After Unit 2 main/helper runtime changes:

```bash
npm run typecheck
npm run test:contracts -- --test-name-pattern "desktop player adapter|native player host|plex playback|stream resolver|stream policy|track"
dotnet build src/native-helper/Lineup.NativePlayerHost/Lineup.NativePlayerHost.csproj -c Release
npm run verify:redaction
npm run verify:maintainability
```

Expected outcome: main/player and helper protocol behavior passes focused tests; C# helper builds on the implementation machine; private setup and helper diagnostics remain redaction-safe; file-shape guardrails pass or updated guardrail rows are reviewed.

After Unit 3 renderer UI changes:

```bash
npm run typecheck
npm run test:contracts -- --test-name-pattern "renderer|overlay|playback options|player"
npm run smoke:electron
npm run verify:redaction
npm run verify:maintainability
```

Expected outcome: renderer overlay/media-option tests pass; Electron smoke proves bridge and product route still boot; playback options render from runtime-safe state; redaction and maintainability pass.

Before implementation review for each unit:

```bash
git diff --check
npm run verify
```

Expected outcome: no whitespace diff issues; full repository verification passes unless a reviewed replan narrows the surface with a specific reason.

Windows RD-26 proof before closeout:

```powershell
git status --short --branch
npm run verify
npm run smoke:electron
dotnet build src/native-helper/Lineup.NativePlayerHost/Lineup.NativePlayerHost.csproj -c Release
```

Then run the approved RD-26 Windows proof procedure from this plan or from the reviewed proof tool. The proof must cover the sample matrix below without storing raw private evidence in tracked files.

Expected Windows proof observations:

- App launches on Windows x64 from the `initial-build` checkout.
- Production native playback starts from a persisted/scheduler-backed channel using the RD-25 path.
- Runtime track list appears in the player media-options UI while playback is active.
- Audio track selection changes effective playback state and the UI reflects the selected public track ID/label.
- Subtitle off changes effective playback state and the UI reflects off state.
- Subtitle default/forced behavior is visible for the approved sample and the UI labels default/forced states safely.
- Unsupported/unavailable subtitle/audio rows are visible as disabled or fail safely with renderer-safe errors.
- HDR/HDR-unavailable status is displayed safely as observed/unknown/unproven without overclaiming display passthrough.
- Windowed and fullscreen UI remains above native video; focus/back behavior remains usable.
- Helper crash/cleanup after media-option interaction remains safe.
- PMS cleanup still occurs on stop/switch/teardown.
- Redaction scan of proof summaries passes.

Closeout docs/proof gate:

```bash
npm run verify:docs
npm run verify:redaction
git diff --check
npm run verify
```

Expected outcome: durable docs reflect only observed conclusions; import ledger is current for copied/adapted upstream source; roadmap status changes only after proof and review; no raw proof evidence is tracked.

## Acceptance Criteria

RD-26 is complete only when all criteria below are met and implementation review is clean.

Preflight and planning:

- RD-25 is confirmed complete and reviewed in tracked docs or the discrepancy is resolved before RD-26 implementation starts.
- This plan is saved as the active tracked plan under `docs/plans/` with `**Plan Status:** active` and passes `npm run verify:docs`.
- A read-only plan review reports no material blockers before source edits.
- Implementation is routed through the Tier 3 quality loop.

Runtime behavior:

- Production native playback exposes a renderer-safe runtime track list for the active request.
- Runtime track list includes audio and subtitle tracks from the active media where the sample provides them, with public `PlayerTrackId` values only.
- Audio selection through the reachable media-option UI dispatches a valid player selection intent, reaches the helper, changes effective native playback selection, emits renderer-safe events, and updates the UI from the resulting snapshot/event.
- Subtitle selection through the reachable media-option UI dispatches a valid player selection intent, reaches the helper, changes effective native playback selection, emits renderer-safe events, and updates the UI from the resulting snapshot/event.
- Subtitle off is implemented as a first-class renderer-safe state using `trackId: null`, not a fake row with a magic private ID.
- Default and forced subtitle labels are visible where the active sample provides them.
- Missing, unsupported, incompatible, unavailable, stale, or wrong-kind track selections fail safely with explicit renderer-safe error/fallback states.
- Audio fallback behavior from RD-16 is reflected at runtime: when requested audio is unavailable or incompatible, the UI and event state make the fallback explicit without exposing private media details.
- HDR/playback-quality status is runtime-backed and explicit. Supported observations may be positive only for the exact sample/proof. Otherwise the UI must show `unknown`, `unproven`, `not available`, or equivalent reviewed copy.
- Existing load/play/pause/stop/seek/volume/mute/switch/fullscreen/helper crash cleanup behavior does not regress.

Renderer UI and parity:

- The reachable player route no longer uses static/fake `PLAYBACK_AUDIO_TRACKS` or `PLAYBACK_SUBTITLE_TRACKS` as the product media-option source after runtime playback is active.
- Fake/static media-option data remains only in tests, explicit presentation fixtures, or dev-only harnesses with clear isolation from the product path.
- Media-option UI imports or adapts upstream Lineup presentation and interaction patterns for menu structure, selected/off/default/forced states, unavailable/fallback/error states, focus/back behavior, and playback-quality/HDR labeling where compatible with Desktop boundaries.
- Any copied or adapted upstream UI/CSS/copy/tests are recorded in `docs/architecture/import-ledger.md` before or with the import.
- UI remains keyboard/remote-like accessible: focus enters the media-options overlay predictably, arrow/OK/back behavior is deterministic, disabled rows are not activated, and focus returns to player OSD or the previous route as expected.
- Windowed and fullscreen native-video composition remains correct with media options visible above video.
- Renderer view models and tests prove no Plex forbidden renderer fields or player privileged fields are present.

Security and redaction:

- Renderer, preload, public contracts, tests, docs, diagnostics, and proof summaries contain no raw tokens, tokenized URLs, auth headers, raw Plex payloads, private stream IDs, part keys, stream keys, selected connection details, mpv engine IDs, native handles, libmpv objects, raw helper output, process IDs, crash dumps, local filesystem paths, server/account/profile/library/media names, or private media titles.
- Main/helper private setup carries only minimum secret-bearing playback material needed by the helper.
- Helper command payloads over stdin remain private process IPC, not renderer IPC.
- Helper stdout emits only safe NDJSON protocol envelopes; helper stderr is dropped/redacted as diagnostics.
- `npm run verify:redaction` passes after each affected unit and at closeout.

Verification and proof:

- Focused tests cover public contract guards, preload guard parity if touched, adapter selection validation, helper protocol/private setup redaction, native-helper selection behavior using test doubles where possible, stream resolver public/private track mapping, renderer media-option UI, and redaction-safe view models.
- `dotnet build src/native-helper/Lineup.NativePlayerHost/Lineup.NativePlayerHost.csproj -c Release` passes on the implementation platform and on Windows proof platform if available.
- `npm run smoke:electron` passes after renderer/preload/runtime wiring.
- `npm run verify` passes before each implementation review and closeout unless a reviewed replan names a narrower command and reason.
- Windows proof under `docs/runs/rd-26-runtime-media-options-playback-quality/**` observes the RD-26 sample matrix and stores only ignored local evidence plus redaction-safe summaries.
- Implementation review is clean after every unit.

Closeout memory:

- `docs/architecture/CURRENT_STATE.md` reflects RD-26 conclusions only after implementation, verification, review, and Windows proof are complete.
- `docs/architecture/playback-architecture.md` records the final RD-26 media-option seam and limits without raw proof.
- `docs/roadmap/desktop-port-roadmap.md` marks RD-26 complete only after all exit gates are observed.
- Completed full plan body is archived locally under ignored `docs/runs/archive/plans/` after durable conclusions are reflected in tracked docs.
- Next session handoff routes to RD-27 only after RD-26 proof/review/closeout is complete.

## Replan Triggers

Stop and replan before further edits if any trigger occurs:

- RD-25 is not actually complete, reviewed, and Windows-proven at the level RD-26 depends on.
- Local discovery shows RD-25 introduced a different playback/helper seam than this plan assumes.
- Runtime media-option implementation requires package dependency, lockfile, package script, public signing/update/installer behavior, or native/media binary redistribution changes.
- Track selection requires exposing private Plex stream IDs, mpv track IDs, engine IDs, stream keys, part keys, tokenized URLs, auth headers, selected connection details, native handles, raw helper logs, raw Plex payloads, local paths, or private media names outside main/helper custody.
- Renderer needs to own persistence, preferred language, preferred tracks, browser storage, filesystem access, Electron/Node APIs, Plex transport policy, native helper control, or raw media setup.
- Existing player intents cannot safely express RD-26 actions and a new IPC/channel/bridge shape is needed. Replan before adding it.
- `src/preload/index.cts`, `src/main/player/desktopPlayerAdapter.ts`, `src/main/player/plexPlaybackRuntime.ts`, `src/contracts/player.ts`, `src/main/plex/streamResolver.ts`, or `src/renderer/index.ts` must grow substantially instead of using focused owners.
- Native helper changes become a broad rewrite, require changing libmpv distribution, or require replacing the RD-25 helper process architecture.
- Libmpv/mpv runtime behavior on Windows cannot reliably observe track list, track selection, or HDR properties for the sample matrix.
- HDR proof would require positive display/compositor/HDR passthrough claims that the Windows proof environment cannot observe safely.
- Redaction scanner flags proof summaries, tests, diagnostics, or docs and the fix is not local to the current execution unit.
- `npm run verify`, `npm run smoke:electron`, `npm run verify:redaction`, `dotnet build`, or Windows proof fails for a reason that would require changing scope, ownership, or acceptance criteria.
- Implementation review reports a material blocker.
- Upstream media-option UI adaptation requires importing browser/webOS lifecycle, router, storage, or privileged playback assumptions.

## Rollback Notes

RD-26 should be reversible by unit:

- **Plan-only rollback:** remove this plan from `docs/plans/` or mark it superseded only after a reviewed replacement plan exists. Do not alter product source.
- **Contract rollback:** revert player contract, IPC/preload guard, and associated tests together. Restore the previous snapshot/event shape and rerun `npm run typecheck`, focused contract tests, `npm run verify:redaction`, and `npm run verify:architecture`.
- **Private setup/runtime rollback:** revert `NativeHelperPlaybackSetup`, stream resolver private mapping, adapter validation, native-host protocol/process changes, and main/player tests together. Confirm production load/play/stop from RD-25 still works, then rerun focused main/player tests and `npm run verify`.
- **Native helper rollback:** revert `.cs` helper changes together with protocol changes. Delete untracked helper build output. Rerun `dotnet build` and focused native-host tests if source remains touched.
- **Renderer UI rollback:** revert runtime media-option UI changes and restore the prior overlay fixture behavior only if RD-26 is being abandoned or replanned. Do not close RD-26 with reverted fake controls still in the product path.
- **Proof tooling rollback:** remove any new proof script and tests if abandoned. Delete local ignored `docs/runs/rd-26-runtime-media-options-playback-quality/**` evidence.
- **Docs rollback:** revert roadmap/current-state/playback/import-ledger updates if proof or review invalidates closeout. Do not leave roadmap marked complete without observed evidence.
- **No migration rollback:** RD-26 must not add persisted schema, so rollback should not require user-data migration. If implementation accidentally adds persistence, stop and replan.

Always run `git status --short --branch` before rollback and avoid deleting user or pre-existing changes.

## Commit Checkpoints

Use conventional commits. Keep unrelated changes out of every commit.

Recommended checkpoints:

1. `docs(plan): add RD-26 runtime media options plan`
   - Files: this plan only.
   - Verification: `npm run verify:docs`.
   - Review: plan review required before source edits.

2. `feat(player): add renderer-safe media option contract seam`
   - Files: player contract/quality split if needed, private setup types, preload guards only if contract changed, focused contract/integration tests.
   - Verification: Unit 1 commands.
   - Review: implementation review before Unit 2.

3. `feat(player): wire runtime track selection through native helper`
   - Files: main/player adapter validation, private mapping, resolver mapping, helper protocol/process, native helper track-selection logic, focused tests.
   - Verification: Unit 2 commands plus `dotnet build`.
   - Review: implementation review before Unit 3.

4. `feat(renderer): bind media options to runtime player state`
   - Files: renderer overlay/view/action/style owners, renderer tests, optional preload parity if affected.
   - Verification: Unit 3 commands and `npm run smoke:electron`.
   - Review: implementation review before proof closeout.

5. `test(proof): add RD-26 media options proof harness`
   - Use only if a reviewed proof tool is needed.
   - Files: proof tool and tests; no raw evidence.
   - Verification: proof tool tests, `npm run verify:docs`, `npm run verify:redaction`.
   - Review: implementation/proof review.

6. `docs(roadmap): close RD-26 runtime media options`
   - Files: roadmap/current-state/playback architecture/import ledger/proof plan updates required by observed evidence.
   - Verification: closeout commands.
   - Review: closeout/proof review clean.

For Tier 3 work, prefer one commit per reviewed execution unit. If local policy says not to commit from the agent session, leave the work unstaged with an exact handoff and observed verification results.

## Execution Units

### Unit 0 — Preflight And Plan Review

Owner: controller/planner, read-only until plan review is clean.

Steps:

1. Run `git status --short --branch` and record branch, dirty files, and pre-existing changes.
2. Read the Required Reading list.
3. Reconcile RD-25 status:
   - Confirm `docs/roadmap/desktop-port-roadmap.md` says RD-25 complete and reviewed, or update it only if RD-25 closeout evidence is already observed and review-clean.
   - Confirm `docs/architecture/CURRENT_STATE.md` and `docs/architecture/playback-architecture.md` no longer say RD-25 manual proof is pending, or record the discrepancy as a blocker.
   - If RD-25 proof is unavailable, stop. Do not start RD-26 source edits.
4. Run Codanna/`rg` discovery named in Evidence And Discovery.
5. Save this plan at the intended tracked path.
6. Run `npm run verify:docs`.
7. Request read-only plan review with this packet:
   - Task: RD-26 Runtime Media Options And Playback Quality plan review.
   - Scope: this plan, roadmap RD-26, current architecture, playback/security docs, file-shape guardrails.
   - Review priorities: RD-25 dependency freshness, renderer/preload secrecy, public/private track identity, helper/native seam, HDR claims, architecture-health decomposition, verification sufficiency, Windows proof gate.
   - Expected output: findings only, ordered by severity; state when no blockers remain.
8. Do not implement until plan review is clean.

Stop/replan if plan review rejects the seam or RD-25 dependency is unresolved.

### Unit 1 — Contract, Private Setup, And Mapping Shape

Owner: contracts + main/player/Plex private setup. Keep renderer UI unchanged in this unit except tests needed for contract compilation.

Implementation decisions:

1. Prefer existing `PlayerTrackSummary`, `PlayerSnapshot.tracks`, `selectedAudioTrackId`, `selectedSubtitleTrackId`, and `track.selection.changed` for audio/subtitle UI.
2. Add a small renderer-safe playback-quality contract only if HDR/playback-quality status cannot be represented by existing safe fields. If added:
   - Put type aliases/unions in a new small file if that avoids growing `src/contracts/player.ts` materially.
   - Add exactly one field to `PlayerSnapshot` such as `quality: PlayerPlaybackQualitySummary | null` or an equivalent reviewed name.
   - Add a `quality.changed` event only if runtime updates need to arrive without a full state snapshot. Otherwise update state through `state.changed` after helper events.
   - Update `isRendererSafePlayerEvent`, snapshot guards, preload `isPlayerEvent`, preload `isPlayerSnapshot`, and contract tests.
3. Extend `NativeHelperPlaybackSetup` privately to include all-track mapping if needed. Use names that are clearly private and never renderer-facing. Validate this setup in `validatePrivilegedPlaybackDescriptor` or the closest existing private setup validator.
4. Extend `PlexStreamResolver` mapping helpers to build public/private mapping from selected part streams:
   - Public IDs remain the existing deterministic `plex-track-*` values.
   - Private IDs use Plex stream IDs only inside private setup.
   - If Plex stream ID is missing, preserve a safe `null`/unavailable mapping and let runtime mark the row unavailable rather than inventing a private ID.
5. Add focused tests:
   - Resolver maps all audio/subtitle public IDs to private IDs for the selected part.
   - Resolver omits private IDs from public load payload, diagnostics, and renderer-safe outputs.
   - Contract/preload guards accept safe quality/track shapes and reject privileged fields recursively.
   - Private setup validation rejects mismatched request IDs, missing public IDs, duplicate public IDs, and forbidden fields.

Do not implement helper track switching or renderer UI in this unit.

### Unit 2 — Main/Helper Runtime Track And Quality Behavior

Owner: main/player + native helper. Renderer product UI remains static until Unit 3, but tests may use fake dispatches.

Implementation decisions:

1. Add a focused main/player validation helper if needed:
   - Validate `track.audio.select` and `track.subtitle.select` against current snapshot before helper dispatch.
   - Accept subtitle `null` as off.
   - Reject audio `null` because the public command does not support disabling audio.
   - Reject unavailable, wrong-kind, stale, unknown, empty, or privileged-looking IDs.
   - Emit safe errors and command-settled failures.
2. Update `DesktopPlayerAdapter` minimally to call the helper. Do not grow mapping logic inline.
3. Update native helper code with decomposition before broad additions:
   - Extract typed command/property wrappers if `Program.cs` would otherwise absorb new mpv API calls.
   - Extract track mapping/projection into a focused `.cs` owner.
   - Extract playback-quality/HDR projection into a focused `.cs` owner if implemented.
4. Implement helper load-time behavior:
   - Store current request ID and request-scoped public/private track map.
   - Apply initial selected private audio/subtitle IDs from setup.
   - Emit `tracks.changed` with public IDs, selected flags, default/forced flags, language, codec/format, delivery type, channel count, available state, and safe labels.
   - Emit `track.selection.changed` reflecting effective mpv selection.
   - Emit quality/HDR status as safe `unknown`/`unproven` until concrete observed properties are available.
5. Implement helper command behavior:
   - `track.audio.select`: translate public ID to private mpv `aid`; set effective selection; emit selection update.
   - `track.subtitle.select`: translate public ID to private mpv `sid`; `null` maps to `sid=no`; emit selection update.
   - Unknown or currently unavailable public IDs return safe command failure.
   - Do not log raw IDs, URLs, headers, media names, or local paths.
6. Observe/derive quality:
   - Use libmpv properties that are safe to observe for video/HDR state.
   - Project only safe labels/unions to the public contract.
   - Treat absent or ambiguous HDR properties as `unknown` or `unproven`.
7. Add focused tests using fake helper/process where possible:
   - Adapter rejects stale/wrong-kind/unavailable track IDs before host call.
   - Helper protocol carries private mapping only on load and never in public events.
   - Native host process rejects malformed/privileged track/quality events.
   - Helper test double emits tracks and selection updates; adapter snapshots update correctly.
   - Selection command failures are safe and do not poison current playback state.
   - Cleanup and helper crash after track interaction still produce safe events and diagnostics.
8. Build helper with `dotnet build`.

Do not change renderer product UI in this unit except where needed to compile contract changes.

### Unit 3 — Renderer Runtime Media Option UI And Upstream Parity

Owner: renderer UI/focus/style + import ledger if upstream source/copy/CSS/tests are adapted.

Implementation decisions:

1. Replace product-route media-option data source:
   - Remove runtime use of static `PLAYBACK_AUDIO_TRACKS` and `PLAYBACK_SUBTITLE_TRACKS` in reachable player route.
   - Keep static data only in explicit presentation fixtures or tests.
   - Build `PlaybackOptionsViewModel` from current `PlayerSnapshot.tracks`, selected IDs, and safe quality state.
2. Renderer actions:
   - `togglePlaybackOptions` opens the menu and focuses the first enabled actionable row or the close/back control.
   - Audio row OK dispatches `player.selectAudio` with the row's public ID.
   - Subtitle row OK dispatches `player.selectSubtitle` with row public ID or `null` for Off.
   - Disabled rows do not dispatch. They show unavailable/fallback/error copy.
   - Pending rows may show `Changing...` but must clear on event, command failure, back, route change, or new playback request.
3. Focus/back behavior:
   - Back closes media options first, then OSD/player overlay according to existing overlay rules.
   - Focus remains within the media-options overlay while it is active.
   - Focus falls back deterministically if the selected row disappears after a track-list update.
4. Upstream parity:
   - Adapt upstream menu hierarchy, selected/off/default/forced labels, unavailable styling, playback quality/HDR labels, and copy where compatible.
   - Record import ledger row before or with copied/adapted upstream UI/CSS/copy/tests.
   - Record Desktop divergences for native-helper-specific behavior or unproven HDR statuses.
5. Redaction-safe UI:
   - Never render raw track IDs to visible copy unless they are intentionally opaque public IDs in test-only diagnostics. Product UI should prefer labels.
   - Do not render URLs, server names, media file paths, raw Plex titles from proof, native handles, or private setup details.
6. Tests:
   - Runtime snapshot with multiple audio tracks renders rows with selected/default/channel/language labels.
   - Subtitle Off row is selected when `selectedSubtitleTrackId` is null.
   - Forced/default subtitle rows render safe badges.
   - Unavailable tracks render disabled and do not dispatch.
   - Audio/subtitle selection dispatches exact safe player intent envelopes.
   - Command failure renders safe error/fallback state.
   - Track-list update preserves focus or moves to deterministic fallback.
   - View models contain no Plex forbidden renderer fields or player privileged fields.
   - HDR/quality rows show observed/unknown/unproven states without claims beyond snapshot input.
7. Run Electron smoke and full verify before implementation review.

### Unit 4 — Windows Runtime Proof, Docs, And Closeout

Owner: controller/closeout. No new product source unless proof exposes a blocker and implementation review routes a fix.

Windows proof matrix:

Use redaction-safe local sample labels, not raw filenames or titles:

| Sample label | Required observation | Required safe result |
| --- | --- | --- |
| `multi-audio` | Active playback exposes at least two audio options and switching changes effective selection | UI selected label changes; public track ID only; no private IDs/logs |
| `subtitle-default-forced` | Active playback exposes Off plus at least one default or forced subtitle option | Off/default/forced labels render; selecting/off updates effective selection |
| `subtitle-unavailable-or-burnin` | Unsupported, unavailable, burn-in, or conversion case from RD-16 matrix is exercised | UI shows explicit unavailable/fallback/burn-in status without claiming switchability |
| `hdr-observed` | HDR source or HDR policy case is loaded | UI shows safe HDR/source/quality state; positive output claims only if directly observed |
| `hdr-unavailable-or-unknown` | SDR or unknown HDR case is loaded | UI shows SDR/unknown/unproven safely |
| `fullscreen-composition` | Media options opened during playback in fullscreen | UI remains above native video; focus/back works |
| `cleanup-after-selection` | Stop/switch/teardown after selection changes | Helper cleanup and PMS release remain safe |
| `helper-crash-after-selection` | Helper crash or crash simulation after media-option interaction | App remains alive; safe error state; no raw helper output |
| `redaction-scan` | Proof summaries scanned | No forbidden evidence found |

Proof recording rules:

- Store raw run artifacts only under ignored `docs/runs/rd-26-runtime-media-options-playback-quality/**`.
- Tracked docs may record only category/count/status facts such as `multi-audio: observed`, `subtitle-off: observed`, `hdr: unknown`, `fullscreen-composition: passed`.
- Do not commit screenshots, videos, raw logs, support bundles, raw helper stdout/stderr, raw file paths, media titles, server/account/profile/library names, URLs, headers, tokens, or native handles.

Closeout steps:

1. Run full closeout verification commands.
2. Request read-only proof/implementation review with proof summaries and diff.
3. Adjudicate review findings.
4. Update import ledger if upstream media-option source was adapted.
5. Update `CURRENT_STATE.md` and `playback-architecture.md` with final observed RD-26 seam and limits.
6. Update roadmap RD-26 status only after proof/review are complete.
7. Archive the completed full plan body locally after durable conclusions are reflected in tracked docs.
8. Emit next-session handoff routing to RD-27 Windows MVP UI Proof And Operational Soak only after RD-26 is fully closed.

## Review Packets

### Plan review packet

```text
TASK: RD-26 Runtime Media Options And Playback Quality plan review
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-06-11-rd-26-runtime-media-options-playback-quality-plan.md
REVIEW_TARGET: plan only
PRIORITIZE:
- RD-25 dependency freshness and stop conditions
- renderer/preload/main/helper secret boundaries
- public/private track ID separation
- native helper/libmpv ownership
- HDR/playback-quality claim limits
- file-shape hotspot decomposition
- verification and Windows proof sufficiency
OUTPUT: findings ordered by severity; state explicitly when no blockers remain
```

### Implementation review packet per unit

```text
TASK: RD-26 Runtime Media Options And Playback Quality implementation review
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-06-11-rd-26-runtime-media-options-playback-quality-plan.md
UNIT: <Unit 1|Unit 2|Unit 3|Unit 4>
REVIEW_TARGET: current diff plus observed verification
FILES_IN_SCOPE:
- <exact files touched by the unit>
FILES_OUT_OF_SCOPE:
- package/dependency/release/persistence/broad Plex/channel/scheduler changes unless explicitly in the unit
PRIORITIZE:
- secret/native/Plex/private track leakage
- renderer privilege expansion
- broad preload or IPC shape drift
- stale/wrong-kind/unavailable track safety
- helper crash/cleanup/PMS release behavior
- HDR overclaiming
- fake/scaffold UI residue in reachable route
- missing tests/proof
OUTPUT: findings ordered by severity; state explicitly when no blockers remain
```

## Handoff Template

Use this if handing RD-26 to a fresh session after the plan is saved but before implementation begins:

```text
MODEL_SUGGESTION
PLANNER: n/a
IMPLEMENTER: GPT-5.5 Pro or strongest available coding/reasoning model
REVIEWER: GPT-5.5 Pro or strongest available review model
WHY: RD-26 is Tier 3 native playback + renderer/preload/main/helper + Plex/private-track + Windows proof work.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop
TASK: Complete RD-26 Runtime Media Options And Playback Quality Through Quality Loop
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-06-11-rd-26-runtime-media-options-playback-quality-plan.md
ARTIFACT: active RD-26 plan
FILES:
- docs/plans/2026-06-11-rd-26-runtime-media-options-playback-quality-plan.md
- docs/roadmap/desktop-port-roadmap.md
- docs/architecture/CURRENT_STATE.md
- docs/architecture/playback-architecture.md
- docs/architecture/file-shape-guardrails.md
- src/contracts/player.ts
- src/main/player/**
- src/main/plex/streamResolver.ts
- src/native-helper/Lineup.NativePlayerHost/**
- src/renderer/overlays.ts
- src/renderer/overlayViewModels.ts
- src/renderer/index.ts
BLOCKERS: none if RD-25 closeout docs/evidence are reconciled; otherwise resolve RD-25 complete/reviewed/manual-proof status before source edits.
MESSAGE:
Start in quality-loop phase `scope-load`. Confirm branch `initial-build`, run git status, read required docs/skills, reconcile RD-25 status, run Codanna/rg discovery, run `npm run verify:docs`, request read-only plan review, then implement only Unit 1 after plan review is clean. RD-26 requires Windows proof before closeout.
```
