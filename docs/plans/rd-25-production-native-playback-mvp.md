# RD-25 Production Native Playback MVP — Code-First Implementation Plan

**Plan Status:** active

**Task family:** feature/design

**Verification classification:** broader integration/manual proof required

**Branch target:** `initial-build`

**Current posture:** Code-first implementation is allowed for RD-25. Automated code verification remains in scope throughout implementation. Manual UI/program proof of the running app is intentionally deferred to the later full-MVP QA pass; therefore RD-25 must not be marked complete solely from this coding pass.

## TL;DR

Implement RD-25 by replacing the fake playback bootstrap with a production-shaped, main/helper-owned native playback path for live Plex-backed scheduled media. The renderer must continue to see only safe player snapshots/events/intents. The main process must keep raw Plex URLs, auth headers, playback descriptors, selected connection details, PMS leases, helper internals, native handles, helper stderr/stdout, process data, and app paths out of renderer-facing contracts, docs, diagnostics, and proof artifacts.

The best production-practice path is:

1. Preserve public `src/contracts/player.ts` shape unless a renderer-safe event/control addition is strictly necessary.
2. Add a main-only privileged load context from `PlexStreamResolver` → `PlexPlaybackBridge` → `PlexPlaybackRuntime` → `DesktopPlayerAdapter` → `NativePlayerHostProcess`.
3. Promote the RD-06 helper-hosted libmpv concept into a product native-helper source owner, while keeping native/media binaries untracked and package redistribution blocked.
4. Wire live Plex stream resolution through the existing `DesktopPlexRuntime` and `LivePlexTransport` custody seams instead of the `src/main/index.ts` fake resolver.
5. Preserve RD-24 runtime-backed guide/player UI; RD-25 supplies real playback state over the existing overlay/player surfaces, not a new renderer app.
6. Defer Windows/manual proof to the later MVP QA pass, but keep TypeScript, architecture, unit/integration, docs, redaction, and maintainability checks active.

## Goal

Implement the first production native-helper playback path for live Plex-backed scheduled media:

- direct play/direct stream/transcode decision handoff from `src/main/plex/streamResolver.ts`
- main-owned private playback setup handoff to a native helper
- helper-backed load, stop, switch, fullscreen/native-presentation coordination, crash recovery, and cleanup
- PMS session start/release custody behind main-owned ports
- renderer-safe playback controls and playback-state presentation over native video
- no privileged playback material exposed to renderer/preload/public contracts/tracked docs
- no public package, signing, update, installer, or native-media redistribution claim

This plan treats code completion and proof completion as separate milestones:

- **RD-25 code-complete:** source compiles, automated checks pass, helper protocol is wired, fake playback bootstrap is removed from production composition, and injected/helper-double tests prove the main/helper seam.
- **RD-25 proof-complete:** later manual QA observes live Windows playback, switching, stop, fullscreen, crash recovery, cleanup, and redaction. Do not mark RD-25 complete before this proof exists.

## Non-Goals

Do not implement or claim:

- RD-26 runtime subtitle/audio/HDR option UI, beyond preserving existing safe track ids and initial preferred-track handoff.
- Public package release, signing, update, installer, or native/media binary redistribution.
- Any renderer access to Plex credentials, tokens, headers, tokenized URLs, raw playback URLs, raw Plex payloads, app paths, helper process details, native handles, libmpv objects, or private diagnostics.
- A broad preload RPC bridge or arbitrary player/helper IPC from renderer.
- External `mpv` IPC as product architecture.
- Upstream webOS/browser playback architecture as Desktop truth.
- Manual UI/program proof during code implementation; that proof is deferred to the later full-MVP QA pass.
- Tracked screenshots, raw logs, raw helper output, private account/server/library/media names, local filesystem paths, endpoint URLs, tokens, headers, payloads, native handles, package trees, or private proof.

## Parent Architecture Alignment

Use these repo facts as the controlling alignment:

- `docs/roadmap/desktop-port-roadmap.md` marks RD-24 complete and RD-25 not started. RD-25 owns live Plex-backed native playback, switching, stop, fullscreen, helper crash recovery, and PMS cleanup, while keeping native handles, raw URLs, headers, playback descriptors, helper internals, and native logs out of renderer-facing contracts and tracked docs.
- `docs/architecture/playback-architecture.md` accepts the helper-hosted native libmpv hypothesis and explicitly rejects external `mpv` IPC as product architecture.
- `docs/architecture/security-and-secret-flow.md` requires token-bearing headers/URLs to stay only inside privileged main/helper setup, with renderer receiving safe state and typed intents only.
- `docs/architecture/file-shape-guardrails.md` names several RD-25 hot spots:
  - `src/main/player/desktopPlayerAdapter.ts`
  - `src/main/player/plexPlaybackRuntime.ts`
  - `src/main/plex/streamResolver.ts`
  - `src/main/index.ts`
  - `src/preload/index.cts`
- `docs/product/lineup-product-parity-matrix.md` classifies production playback as blocked until RD-25 because production native playback, live Plex transport, and production helper proof are absent.

## Required Reading

Before editing:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/plan-authoring-standard.md`
4. `docs/architecture/CURRENT_STATE.md`
5. `docs/roadmap/desktop-port-roadmap.md`
6. `docs/architecture/playback-architecture.md`
7. `docs/architecture/security-and-secret-flow.md`
8. `docs/architecture/file-shape-guardrails.md`
9. `docs/architecture/packaging-release-gates.md`
10. `docs/architecture/import-ledger.md`
11. `docs/product/lineup-product-parity-matrix.md`
12. `docs/development/windows-ui-proof-plan.md`
13. `package.json`, `tsconfig.json`, `tsconfig.electron.json`
14. Playback source:
    - `src/contracts/player.ts`
    - `src/contracts/ipc.ts`
    - `src/contracts/shell.ts`
    - `src/main/player/nativePlayerHostPort.ts`
    - `src/main/player/nativePlayerHostProcess.ts`
    - `src/main/player/desktopPlayerAdapter.ts`
    - `src/main/player/playerIpc.ts`
    - `src/main/player/plexPlaybackRuntime.ts`
    - `src/main/player/plexPlaybackBridge.ts`
    - `src/main/player/plexPlaybackComposition.ts`
    - `src/main/player/streamPolicy/*`
    - `src/main/plex/streamResolver.ts`
    - `src/main/plex/desktopPlexRuntime.ts`
    - `src/main/plex/livePlexTransport.ts`
    - `src/main/plex/plexComposition.ts`
    - `src/main/index.ts`
15. RD-06/RD-15/RD-16 helper evidence tooling:
    - `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`
    - `tools/libmpv-spike/rd-06-native-libmpv-host-spike-helper.cs`
    - `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs`
16. RD-24 files changed in the just-finished implementation, especially channel scheduler runtime, current-channel state, guide/player route state, and overlay playback state.
17. Original Lineup as product reference only:
    - playback modules under upstream `src/modules/player/**`
    - stream modules under upstream `src/modules/plex/stream/**`
    - OSD/player chrome modules under upstream `src/modules/ui/player-osd/**`, `src/modules/ui/now-playing-info/**`, `src/modules/ui/mini-guide/**`, `src/modules/ui/channel-badge/**`, `src/modules/ui/channel-number-overlay/**`
    - channel switching runtime under upstream `src/core/orchestrator/priority-one/**` and `src/core/orchestrator/runtime/OrchestratorChannelSwitchRuntime.ts`

For external behavior checks during implementation, use official docs only. At minimum, check Electron security/process docs and current libmpv/mpv client API docs before finalizing helper process behavior. Record only a dated source summary in the plan or implementation notes; do not paste raw URLs into tracked docs unless the repo already permits that doc type.

## Required Skills

- `execution-plan-authoring`: this is Tier 3 cross-boundary work requiring a durable plan shape.
- `architecture-boundaries`: RD-25 crosses renderer/preload/main/helper/Plex/player/persistence/diagnostics boundaries.
- `plex-integration-boundaries`: stream resolution, credential custody, selected connection, raw media detail, PMS session lifecycle, and token/header handling are in scope.
- `ui-composition-patterns`: renderer playback controls and OSD/player state must preserve RD-24 body/overlay behavior over native video.
- `verification-strategy`: automated code proof and later manual QA proof are intentionally separated.
- `review-request`: implementation should receive adversarial review before manual proof.
- `closeout-verification`: RD-25 must not be called complete until the later Windows/manual proof pass records sanitized results.

## Evidence And Discovery

Current repo evidence from `initial-build`:

- RD-25 roadmap objective is explicit: production native-helper playback for live Plex-backed scheduled media, including direct play/direct stream/transcode handoff, load, stop, switch, fullscreen, helper crash recovery, and PMS cleanup.
- `src/main/player/playerIpc.ts` currently creates a `DesktopPlayerAdapter` only for `development` or `smoke`; production gets `adapter: null` and returns `PLAYER_UNSUPPORTED_CAPABILITY`.
- `src/main/index.ts` currently wires `createPlexPlaybackRuntimeComposition()` to an inline `fakePlaybackResolver` with a mock private playback descriptor and a no-op PMS port. This must not remain in production RD-25 composition.
- `src/main/plex/streamResolver.ts` already returns both:
  - renderer-safe `PlayerLoadCommandPayload`
  - main-only `PlexPrivilegedPlaybackDescriptor`
- `src/main/player/plexPlaybackBridge.ts` currently drops `privatePlayback` when mapping resolver output into `PlexPlaybackRuntimeCandidate`.
- `src/main/player/plexPlaybackRuntime.ts` currently validates/dispatches only the safe `PlayerCommand` and has no privileged helper setup path.
- `src/main/player/plexPlaybackComposition.ts` adapts runtime load commands back into renderer intent envelopes through `toRendererIntentEnvelope()`. RD-25 should stop using renderer-intent mapping for main-owned scheduled loads.
- `src/main/player/nativePlayerHostProcess.ts` already has a real spawned helper process seam, NDJSON framing, timeouts, cleanup/reap, stderr dropping, malformed-output handling, lifecycle failure reporting, and safe host event validation.
- `src/main/plex/desktopPlexRuntime.ts` already keeps selected connection and active token in main-owned memory through `getActiveConnectionAndToken()`, and exposes `getLibraryTransport()` for main-owned transport composition.
- `tools/libmpv-spike/rd-06-native-libmpv-host-spike-helper.cs` provides evidence for a C# helper-hosted libmpv path, but it is dev-only and must be converted deliberately rather than copied blindly.

Discovery fallback note: Codanna may be preferred in local implementation. If unavailable or stale, use `rg` and direct file reads. Record fallback in the tracked plan/handoff.

## Impact Snapshot

Expected owner changes:

- Main player adapter/runtime/process seams
- Main Plex stream resolver composition
- Main Plex live transport or a focused playback/PMS transport owner
- Main startup composition, preferably through extraction rather than expanding `src/main/index.ts`
- Optional native-helper source/project owner
- Renderer playback controls only where RD-24 safe player state needs final production event binding
- Docs and tests

Expected public contract changes:

- Prefer **no change** to renderer-facing `src/contracts/player.ts`.
- If a renderer-safe event/control field is unavoidable, split it into a narrowly tested contract addition and prove recursive forbidden-field guards.
- No preload expansion for raw playback setup.

Dependency/build-tool posture:

- Add **no npm dependency** unless a reviewed implementation packet proves no existing platform/repo approach can work.
- Preferred native-helper strategy: add repo-owned C#/.NET helper source and a local build path, with no lockfile impact and no tracked native/media binaries.
- External libmpv binary remains a local prerequisite for code-first playback proof and later MVP QA; public/native-media redistribution remains blocked until packaging/release work owns provenance, licensing, notices, checksums, signing, and layout.

Local-only artifacts that must remain untracked:

- built helper executable/dll outputs
- local libmpv/mpv binaries
- manual proof evidence
- screenshots/videos/raw logs
- package output trees
- private account/server/media/library details
- helper stdout/stderr/raw IPC traces
- support bundle contents

User-visible behavior that must not regress:

- RD-24 guide/player route data, channel switching, OSD, now-playing, mini guide, and channel badge state
- renderer route/focus/keyboard/fullscreen behavior
- existing diagnostics support-bundle redaction shape
- existing Plex onboarding/library behavior

## Architecture Health

RD-25 touches known hot spots. Use decomposition, not baseline growth, wherever possible.

### Hotspot decisions

1. `src/main/index.ts`
   - Current problem: startup composition already contains fake resolver, fake capability profile, and runtime wiring.
   - RD-25 decision: extract playback bootstrapping into `src/main/player/playbackRuntimeBootstrap.ts` or `src/main/player/productionPlaybackComposition.ts`.
   - Keep `src/main/index.ts` responsible only for orchestration and lifecycle registration.

2. `src/main/player/desktopPlayerAdapter.ts`
   - Current problem: over 800 lines and guardrail says decompose before production native-helper playback adds behavior.
   - RD-25 decision: do not add large command families directly here.
   - Add focused owners:
     - `src/main/player/playerCommandDispatch.ts` for shared command execution/state transition if needed
     - `src/main/player/runtimePlayerDispatchPort.ts` for main-owned scheduled-load dispatch
     - `src/main/player/rendererPlayerIntentDispatch.ts` only if renderer-intent handling must be split
   - The adapter may receive a small method addition, but implementation-heavy logic belongs in new files.

3. `src/main/player/plexPlaybackRuntime.ts`
   - Current problem: nearly hard-overage and guardrail says extract cleanup or stale-event custody before production native-helper playback grows it.
   - RD-25 decision: keep existing cleanup/stale behavior mostly stable.
   - Add a small private playback dispatch context shape; push validation/conversion to new files.

4. `src/main/plex/streamResolver.ts`
   - Current problem: already owns candidate mapping and descriptor projection; guardrail says split before live Plex transport or extra stream modes.
   - RD-25 decision: do not add live transport composition into this file.
   - Add a focused composition owner:
     - `src/main/plex/streamResolverComposition.ts`
     - `src/main/plex/playbackMediaDetailPort.ts`
     - `src/main/plex/pmsPlaybackSessionPort.ts`

5. `src/preload/index.cts`
   - RD-25 should not grow preload unless an existing player bridge guard needs a renderer-safe field update.
   - No new helper/raw playback preload namespace.

6. Native helper
   - Create a focused source owner rather than growing RD-06 spike tooling.
   - RD-06 spike files stay evidence tooling.

Maintainability route:

```bash
npm run verify:maintainability
```

Expected outcome: no new unreviewed overage; if a touched hot spot grows above guardrail, the plan must record either a decomposition commit or a reviewed temporary allowlist update with removal trigger.

## Files In Scope

Plan/docs:

- `docs/plans/rd-25-production-native-playback-mvp.md`
- `docs/architecture/CURRENT_STATE.md`
- `docs/architecture/playback-architecture.md`
- `docs/architecture/file-shape-guardrails.md`
- `docs/architecture/security-and-secret-flow.md`, only if ownership language changes
- `docs/architecture/import-ledger.md`, only if upstream source/CSS/copy/test is copied or adapted
- `docs/roadmap/desktop-port-roadmap.md`, status update only after observed proof
- `docs/product/lineup-product-parity-matrix.md`, classification update only after observed proof
- `docs/development/windows-ui-proof-plan.md`, only to add later QA proof rows without raw/private evidence

Main/player:

- `src/main/player/nativePlayerHostPort.ts`
- `src/main/player/nativePlayerHostProcess.ts`
- `src/main/player/desktopPlayerAdapter.ts`
- `src/main/player/playerIpc.ts`
- `src/main/player/plexPlaybackRuntime.ts`
- `src/main/player/plexPlaybackBridge.ts`
- `src/main/player/plexPlaybackComposition.ts`
- new `src/main/player/privilegedPlaybackDispatchContext.ts`
- new `src/main/player/nativeHelperProtocol.ts`
- new `src/main/player/nativeHelperPlaybackSetup.ts`
- new `src/main/player/productionNativeHostFactory.ts`
- new `src/main/player/playbackRuntimeBootstrap.ts` or `src/main/player/productionPlaybackComposition.ts`
- new focused tests under `src/__tests__/main/player/**`

Main/Plex:

- `src/main/plex/streamResolver.ts`, narrowly, for type extraction only
- `src/main/plex/desktopPlexRuntime.ts`
- `src/main/plex/livePlexTransport.ts`
- `src/main/plex/plexComposition.ts`
- new `src/main/plex/streamResolverComposition.ts`
- new `src/main/plex/playbackMediaDetailPort.ts`
- new `src/main/plex/pmsPlaybackSessionPort.ts`
- focused tests under `src/__tests__/main/plexStreamResolver*.test.ts` and `src/__tests__/main/plexPlayback*.test.ts`

Native helper:

- new `src/native-helper/Lineup.NativePlayerHost/**` or `native-helper/Lineup.NativePlayerHost/**`
- optional `tools/build-native-helper.mjs`
- optional `tools/verify-native-helper-layout.mjs`
- tests for build/protocol scripts if scripts are committed

Renderer, only if needed:

- `src/renderer/index.ts`
- `src/renderer/playerRuntimeState.ts` or equivalent existing player state owner
- `src/renderer/overlays.ts`
- `src/renderer/overlayViewModels.ts`
- `src/renderer/routeDom.ts`
- `src/renderer/workflow.ts`
- renderer tests that protect safe playback state and OSD controls

Main startup:

- `src/main/index.ts`, only to replace inline fake playback bootstrap with focused composition call

Package/tooling:

- `package.json`, only if adding scripts for helper source validation. No dependency or lockfile change unless explicitly approved.
- `tools/verify-redaction.mjs`, only if the scanner needs new RD-25 redaction vocabulary.
- `tools/verify-docs.mjs`, only if active plan/docs shape needs verifier coverage.

## Files Out Of Scope

- `src/domain/**`, except if RD-24 current-channel scheduler API needs a narrow typed call already approved by RD-24.
- `src/preload/index.cts`, unless an existing safe player bridge guard must accept a new renderer-safe field.
- `src/contracts/plex.ts`, unless a safe public Plex playback status is strictly needed. Prefer no change.
- `src/contracts/player.ts`, unless a renderer-safe event/control addition is strictly required and tested.
- RD-26 media options UI files except to preserve existing safe state.
- Public packaging/signing/update files.
- Native/media binary files.
- Generated helper build output.
- Any tracked run evidence containing private details.

## Planner Self-Check

1. Is any product, architecture, ownership, dependency, or verification decision still unresolved?
   No. The plan clearly outlines the private player setup pathway, the native helper NDJSON protocol over stdin/stdout, and live resolver/PMS integration.
2. Does the plan depend on adjacent files needing contract or type changes that are not in scope?
   No. Adjacent contracts/preload are either out of scope or narrowly updated to pass safe state.
3. Did the plan freeze any file out of scope while still relying on hidden wiring inside it?
   No. All wiring and files are accounted for in the scope.
4. Did the plan record the evidence path and fallback reads?
   Yes. Evidence and discovery is detailed using the required evidence trails.
5. Is the work assigned to the repo-preferred owner, or is it growing a hotspot?
   Yes. Work is decomposed out of index.ts, desktopPlayerAdapter.ts, etc., into focused helper modules.
6. Did Tier 3 work include Architecture Health evidence and a decomposition, avoidance, or allowlist decision for any touched owner hotspot?
   Yes. Hotspot decisions are detailed under Architecture Health.
7. Would a fresh implementer need to invent security, IPC, playback, persistence, packaging, import, or verification policy?
   No. All policies are clearly frozen in the plan.
8. Did the plan record exact verification commands, expected outcomes, and explicit stop/replan triggers?
   Yes. Detailed verification commands and replan triggers are provided.

## Chosen Architecture Seam

The RD-25 seam is:

```text
Scheduler/current channel
  -> PlexPlaybackBridge
  -> PlexStreamResolver live composition
  -> PlexPlaybackRuntime
  -> Runtime player dispatch port with private playback context
  -> DesktopPlayerAdapter main-owned runtime dispatch
  -> NativePlayerHostProcess private helper protocol
  -> Lineup.NativePlayerHost helper-hosted libmpv
  -> safe NativePlayerHostEvent
  -> DesktopPlayerAdapter safe PlayerEvent/Snapshot
  -> existing player IPC/preload/renderer event path
```

Key decision:

- Renderer-originated `player.load` must not become the production scheduled-media load path because renderer cannot hold the private playback descriptor.
- Main-owned scheduled playback must call a main-owned runtime dispatch method that carries `PlexPrivilegedPlaybackDescriptor` as a private context.
- Renderer controls may continue to dispatch safe play/pause/stop/seek/volume/mute intents against the current request, but renderer-originated load must be rejected in production native mode unless a reviewed safe source exists.

## Architecture Seam Decision Gate

Before implementation is locked, confirm these decisions in the active plan or implementation packet:

1. The native helper is source-owned in repo but built output remains untracked.
2. External `mpv` executable IPC is not used as production architecture.
3. The helper receives secret-bearing playback setup only through stdin/private IPC after process spawn, never argv/env/docs/renderer/preload.
4. `NativePlayerHostProcess` continues to drop helper stderr and store only sanitized diagnostics/counts.
5. `PlexPrivilegedPlaybackDescriptor` is never returned in public IPC result, player event, renderer state, support bundle, docs, or test fixtures outside main-owned redaction tests.
6. `PlexPlaybackBridge` no longer drops `privatePlayback`; it passes it only into main-owned runtime context.
7. `PlexPlaybackRuntime` validates public candidate shape separately from private descriptor custody.
8. `DesktopPlayerAdapter` gets a main-owned runtime command path rather than reusing renderer-intent mapping for scheduled loads.
9. Live Plex resolver composition uses `DesktopPlexRuntime`/`LivePlexTransport` custody and does not reconstruct tokens/connections in renderer or preload.
10. PMS start/release has a main-owned port; if live PMS endpoint behavior is uncertain, code may include injected test coverage but RD-25 remains proof-blocked until later QA verifies real cleanup.

Forbidden shortcuts:

- No renderer token/header/raw URL access.
- No arbitrary helper RPC bridge to renderer.
- No broad preload method that forwards unknown payloads.
- No native handles in renderer contracts or docs.
- No raw helper stdout/stderr in diagnostics.
- No tokenized URL in public player load payload.
- No fake resolver retained in production path.
- No compatibility fallback from production native helper to external `mpv`.
- No public package or redistribution claim.

## Implementation Units

### Unit 0 — Branch and freshness reconciliation

Purpose: ensure implementation starts from the real `initial-build` after RD-24.

Files to read:

- all Required Reading above
- `git status --short --branch`
- `git log --oneline -10`
- RD-24 closeout/handoff if present
- any active docs in `docs/plans/`

Work:

- create branch, recommended name: `rd-25-production-native-playback-code-first`
- verify RD-24 changes are merged into `initial-build`
- create or refresh `docs/plans/rd-25-production-native-playback-mvp.md` with this plan
- record code-first/manual-proof-deferred posture
- keep roadmap status as not started/in progress; do not mark complete

Acceptance:

- fresh working tree or explicit conflict inventory
- active plan file exists and passes docs verifier
- implementation scope and stop conditions are clear

Commands:

```bash
git status --short --branch
npm run verify:docs
```

Stop/replan if:

- RD-24 is not actually merged
- existing active plan contradicts this scope
- local branch contains uncommitted production playback edits that need reconciliation

Commit:

```text
docs: add RD-25 production native playback plan
```

---

### Unit 1 — Extract playback bootstrap and remove production fake resolver path

Purpose: remove RD-24/temporary fake playback bootstrap from `src/main/index.ts` without changing behavior yet.

Files to update/create:

- create `src/main/player/playbackRuntimeBootstrap.ts`
- update `src/main/index.ts`
- update or add tests for startup composition if existing patterns allow

Work:

- move inline fake resolver/capability profile/PMS no-op/player port wiring out of `src/main/index.ts`
- keep fake resolver only as dev/test fixture, not reachable production composition
- create explicit bootstrap mode:
  - `development`/`smoke`: existing inert/fake host remains allowed
  - production/native-enabled: requires production native host factory and live resolver composition
  - production/native-unavailable: safe unsupported with diagnostics
- do not wire live helper yet in this unit

Acceptance:

- `src/main/index.ts` shrinks or at least does not grow
- fake resolver is not inline in main entrypoint
- no renderer/preload/contract changes
- existing tests still pass

Commands:

```bash
npm run typecheck
npm run test -- --test-name-pattern "main|player IPC|playback composition"
npm run verify:maintainability
```

Stop/replan if:

- moving bootstrap requires broad startup lifecycle changes
- production fake resolver remains necessary for current RD-24 UI state

Commit:

```text
refactor: isolate playback runtime bootstrap
```

---

### Unit 2 — Main-only privileged playback context propagation

Purpose: carry the private RD-12 playback descriptor from resolver to native host without exposing it publicly.

Files to update/create:

- `src/main/player/plexPlaybackBridge.ts`
- `src/main/player/plexPlaybackRuntime.ts`
- `src/main/player/plexPlaybackComposition.ts`
- `src/main/player/desktopPlayerAdapter.ts`
- `src/main/player/nativePlayerHostPort.ts`
- create `src/main/player/privilegedPlaybackDispatchContext.ts`
- focused tests:
  - `src/__tests__/main/player/plexPlaybackBridge.test.ts`
  - `src/__tests__/main/player/plexPlaybackRuntime.test.ts`
  - `src/__tests__/main/player/plexPlaybackComposition.test.ts`
  - `src/__tests__/main/player/desktopPlayerAdapter.test.ts`

Work:

- extend the main-only runtime candidate with `privatePlayback`, but do not add it to public player contracts
- replace `createDesktopPlayerAdapterRuntimePort()` renderer-intent mapping for scheduled loads with a main-owned runtime dispatch path
- add a private dispatch context accepted only by main-owned runtime dispatch
- reject production renderer-originated `player.load` unless a reviewed safe source is present
- validate public candidate separately from private descriptor
- add private descriptor guard:
  - request id matches command
  - decision kind is direct-play/direct-stream/transcode
  - playback URL is non-empty and never logged/returned
  - credential header exists and remains private
  - public track ids and private track ids stay distinct
- ensure all player events/snapshots remain renderer-safe

Acceptance:

- resolver private descriptor reaches adapter/host test double for runtime load
- renderer-intent load cannot smuggle raw URL/header/private setup
- public player events/snapshots still pass `isRendererSafePlayerEvent`
- no preload changes

Commands:

```bash
npm run typecheck
npm run test -- --test-name-pattern "plex playback runtime|plex playback bridge|plex playback composition|desktop player adapter|contracts"
npm run verify:redaction
```

Stop/replan if:

- implementation requires adding private fields to `src/contracts/player.ts`
- `hasPlayerForbiddenPrivilegedField()` is weakened for renderer-facing data
- private descriptor appears in event/snapshot/diagnostic/support bundle output

Commit:

```text
feat: carry private playback context through main player runtime
```

---

### Unit 3 — Native helper protocol and helper process setup

Purpose: define a product helper protocol over the existing spawned-process seam.

Files to update/create:

- `src/main/player/nativePlayerHostProcess.ts`
- create `src/main/player/nativeHelperProtocol.ts`
- create `src/main/player/nativeHelperPlaybackSetup.ts`
- create tests:
  - `src/__tests__/main/player/nativeHelperProtocol.test.ts`
  - `src/__tests__/main/player/nativePlayerHostProcess.test.ts` updates
  - `src/__tests__/main/player/nativeHelperPlaybackSetup.test.ts`

Work:

- extend process command construction so load commands can include private helper setup when called from main runtime context
- keep process output validation strict and renderer-safe
- maintain current stderr dropping behavior
- ensure private helper setup is never passed through process argv/env
- ensure private helper setup is written only to stdin/process IPC
- add one-time or request-scoped private setup consumption so stale/replayed loads cannot reuse old descriptors
- add maximum message size checks for private setup, if not already enforced
- keep malformed output and helper failure normalized to safe `NativePlayerHostFailure`

Acceptance:

- injected process test double observes private load setup for scheduled `load`
- no private setup appears in returned `NativePlayerHostCommandResult`
- stderr/raw helper output remains dropped
- timeout/malformed-output/exit behavior still normalizes safely
- redaction tests cover setup leakage

Commands:

```bash
npm run typecheck
npm run test -- --test-name-pattern "native helper protocol|native player host process|native helper playback setup"
npm run verify:redaction
npm run verify:architecture
```

Stop/replan if:

- private setup must be passed in argv/env
- helper process framing requires exposing raw IPC to renderer
- process event validation must become broad or permissive

Commit:

```text
feat: add private native helper playback protocol
```

---

### Unit 4 — Product native helper source owner

Purpose: turn the RD-06 helper-hosted libmpv proof into a production-shaped helper source owner.

Chosen strategy:

- Add repo-owned native-helper source, preferably a focused C#/.NET project derived conceptually from RD-06 spike evidence.
- Do not commit built helper output or native media binaries.
- Do not add npm dependencies.
- Use local Windows build/proof for helper executable later.
- Keep external libmpv binary as local proof prerequisite until packaging/release owns redistribution.

Files to create:

- `src/native-helper/Lineup.NativePlayerHost/Lineup.NativePlayerHost.csproj`
- `src/native-helper/Lineup.NativePlayerHost/Program.cs`
- focused helper protocol/source files as needed under that project
- optional `tools/build-native-helper.mjs`
- optional `tools/verify-native-helper-layout.mjs`
- optional tests under `tools/__tests__/**`

Work:

- implement NDJSON stdin/stdout protocol matching `nativeHelperProtocol.ts`
- initialize libmpv through a locally supplied libmpv DLL path or approved helper layout
- use app-owned native presentation path proven by RD-06/RD-15/RD-16, not WID or external mpv IPC
- set helper options to avoid terminal/log echo
- configure header-based auth only inside helper
- load direct-play/direct-stream/transcode URLs from private setup
- emit only safe events matching `NativePlayerHostEvent`
- map time, buffering, media-loaded, tracks, selected-track, ended, and error events into safe protocol output
- handle stop/cleanup/quit deterministically
- crash/exit should be observable by `NativePlayerHostProcess`
- do not log URLs, headers, tokens, paths, native handles, raw libmpv diagnostics, process args, or env

Dependency/build-tool note:

- Owner: native-helper source owner.
- Why needed now: production native libmpv playback cannot be implemented in TypeScript alone without a native process/binding. A separate helper keeps native media crashes and secrets outside renderer/main UI.
- Lockfile impact: none if using C#/.NET and local libmpv.
- License/provenance/security: helper source is repo-owned. External libmpv binary provenance, license obligations, checksums, and redistribution rights remain blocked until packaging/release work owns them.
- Verification: `dotnet build` on Windows/local; TypeScript tests verify protocol from main side.

Acceptance:

- helper source builds locally on Windows when prerequisites exist
- helper speaks safe protocol with test fixture input
- no helper binary or media binary is tracked
- helper output is sanitized by design
- app can detect helper unavailable and fail safely

Commands:

```bash
dotnet build src/native-helper/Lineup.NativePlayerHost/Lineup.NativePlayerHost.csproj -c Release
npm run typecheck
npm run test -- --test-name-pattern "native helper|native player host process"
npm run verify:redaction
```

Stop/replan if:

- C#/.NET helper source is rejected as production direction
- libmpv requires redistribution or license commitments before code can compile
- helper needs raw logs/native handles in diagnostics
- helper needs renderer-provided handles/secrets

Commit:

```text
feat: add product native helper source owner
```

---

### Unit 5 — Production native host factory and lifecycle wiring

Purpose: instantiate the real helper host from main when available, with safe fallback when unavailable.

Files to update/create:

- create `src/main/player/productionNativeHostFactory.ts`
- update `src/main/player/playerIpc.ts`
- update `src/main/player/playbackRuntimeBootstrap.ts`
- update `src/main/index.ts`
- focused tests:
  - `src/__tests__/main/player/productionNativeHostFactory.test.ts`
  - `src/__tests__/main/player/playerIpc.test.ts`

Work:

- create a main-owned resolver for helper executable/libmpv prerequisite availability
- keep raw helper/libmpv paths main-only
- production mode should create `DesktopPlayerAdapter` only when a real host factory is available
- safe unsupported behavior remains when helper is unavailable
- renderer-safe diagnostics can say helper unavailable without paths or process details
- cleanup on app quit must stop runtime, release PMS, cleanup helper, and tear down IPC handlers in deterministic order
- helper lifecycle failure should notify runtime cleanup and renderer-safe state

Acceptance:

- production adapter can be created with injected host factory
- no helper path is exposed to renderer
- unavailable helper returns `PLAYER_UNSUPPORTED_CAPABILITY` or a more specific safe code
- helper crash triggers runtime cleanup through existing event/callback path
- app quit cleanup sequence remains safe and tested

Commands:

```bash
npm run typecheck
npm run test -- --test-name-pattern "production native host factory|player IPC|playback runtime bootstrap|main cleanup"
npm run verify:redaction
npm run verify:architecture
```

Stop/replan if:

- helper location/provisioning becomes hidden config
- startup composition needs broad package/release changes
- helper lifecycle requires storing raw process output

Commit:

```text
feat: wire production native host factory
```

---

### Unit 6 — Live Plex stream resolver composition

Purpose: replace fake playback resolution with live main-owned Plex stream resolution.

Files to update/create:

- create `src/main/plex/streamResolverComposition.ts`
- create `src/main/plex/playbackMediaDetailPort.ts`
- create `src/main/plex/pmsPlaybackSessionPort.ts`
- update `src/main/plex/desktopPlexRuntime.ts`
- update `src/main/plex/livePlexTransport.ts`
- update `src/main/player/playbackRuntimeBootstrap.ts`
- update `src/main/index.ts`
- tests:
  - `src/__tests__/main/plexStreamResolverComposition.test.ts`
  - `src/__tests__/main/plexPlaybackMediaDetailPort.test.ts`
  - `src/__tests__/main/plexPmsPlaybackSessionPort.test.ts`
  - existing stream resolver/runtime tests

Work:

- create selected-connection port from `DesktopPlexRuntime.getActiveConnectionAndToken().connection`
- create active credential header port from `DesktopPlexRuntime.getActiveConnectionAndToken().token`
- create raw media detail port that calls main-owned library transport and parses raw metadata into `PlexMediaItem` without committing raw payloads to renderer snapshots
- create PMS session start/release port with request-scoped leases
- update live transport with narrowly named PMS/session methods rather than arbitrary endpoint forwarding
- ensure failures become safe `PlayerError`/diagnostic summaries
- remove inline `fakePlaybackResolver` from production runtime wiring
- use existing stream policy capability profile; refine only if Windows proof later requires it

Acceptance:

- playback runtime receives real resolver composition when Plex runtime is signed in with selected server/current channel
- missing credential/selected connection/media detail fails safely
- PMS lease start/release is request-scoped
- no raw Plex payload, token, header, connection URI, playback URL, endpoint URL, or media path leaves main/Plex/player owners
- fake resolver remains only in tests/dev fixtures

Commands:

```bash
npm run typecheck
npm run test -- --test-name-pattern "plex stream resolver|stream resolver composition|plex playback bridge|plex playback runtime|PMS"
npm run verify:redaction
npm run verify:architecture
```

Stop/replan if:

- raw media detail cannot be read without renderer/preload broadening
- PMS session behavior requires unreviewed endpoint/persistence/package policy
- resolver needs tokenized public URLs rather than header-based helper setup

Commit:

```text
feat: wire live Plex stream resolver into playback runtime
```

---

### Unit 7 — Playback control, switch, fullscreen, and cleanup behavior

Purpose: make scheduled playback, manual channel switch, stop, fullscreen, and cleanup behave through the production path.

Files to update:

- `src/main/player/plexPlaybackRuntime.ts`
- `src/main/player/plexPlaybackComposition.ts`
- `src/main/player/desktopPlayerAdapter.ts`
- `src/main/player/nativePlayerHostProcess.ts`
- `src/main/window/shellWindowController.ts`, only if helper native presentation needs safe fullscreen/bounds coordination
- renderer player/overlay owners only if safe event state is not already reflected

Work:

- startup playback: current persisted channel/program starts after guide runtime initializes
- schedule tick playback: program start triggers switch
- manual switch playback: current channel selection triggers switch
- stop: renderer stop intent or runtime stop releases PMS and cleans helper
- fullscreen: existing shell fullscreen continues; helper native presentation receives only main/helper-owned geometry/fullscreen commands if needed
- helper crash: runtime cleanup and renderer-safe error/warning state
- stale events: late helper events after switch/cleanup remain quarantined
- RD-24 UI remains the presentation surface

Acceptance:

- injected tests prove start/switch/stop/crash/cleanup sequencing
- helper cleanup and PMS release happen for stop/switch/error/logout/server-change/profile-change/helper-crash/teardown
- renderer sees safe playback state transitions only
- fullscreen bridge is not expanded with native handles
- no direct renderer-native coordination is introduced

Commands:

```bash
npm run typecheck
npm run test -- --test-name-pattern "playback runtime|channel switch|helper crash|fullscreen|cleanup|overlay|workflow"
npm run verify:redaction
npm run verify:architecture
```

Stop/replan if:

- fullscreen/native presentation requires renderer native handles
- current-channel runtime from RD-24 lacks a stable main-owned playback selection seam
- crash recovery needs raw helper logs/process dumps

Commit:

```text
feat: connect scheduled playback lifecycle to native helper
```

---

### Unit 8 — Renderer-safe player presentation polish

Purpose: ensure the existing RD-24 player UI reflects production playback state without introducing privileged data.

Files to update only if needed:

- `src/renderer/playerRuntimeState.ts` or current equivalent
- `src/renderer/overlays.ts`
- `src/renderer/overlayViewModels.ts`
- `src/renderer/routeDom.ts`
- `src/renderer/workflow.ts`
- `src/renderer/index.ts`
- renderer tests

Work:

- keep player controls and OSD fed by safe `PlayerSnapshot`/`PlayerEvent`
- show playback loading/error/unsupported states safely
- preserve current route/focus/back behavior
- no renderer imports from main/preload/native-helper/Plex transport
- no raw URLs/headers/native handles/helper internals in state or DOM
- no fake product playback copy in reachable player route once production playback owns it

Acceptance:

- renderer route/player/overlay view models show safe production playback status
- unsupported helper state has useful product copy
- redaction tests serialize renderer state and find no forbidden fields
- no new preload APIs unless strictly renderer-safe and reviewed

Commands:

```bash
npm run typecheck
npm run test -- --test-name-pattern "renderer.*player|overlay|route DOM|workflow|redaction"
npm run verify:redaction
npm run verify:architecture
```

Stop/replan if:

- renderer needs private playback metadata to show desired UI
- RD-26 media options become necessary to make RD-25 usable
- player route still depends on fake data after production state wiring

Commit:

```text
feat: bind renderer playback surfaces to production player state
```

---

### Unit 9 — Automated verification and docs reconciliation

Purpose: finish the coding pass with automated proof and explicit manual-proof deferral.

Files to update:

- `docs/architecture/CURRENT_STATE.md`
- `docs/architecture/playback-architecture.md`
- `docs/architecture/file-shape-guardrails.md`, only if required by file shape
- `docs/architecture/import-ledger.md`, only if upstream code/copy/CSS/tests were copied or adapted
- `docs/roadmap/desktop-port-roadmap.md`, mark only `in progress / code implemented / manual proof pending`, not complete
- `docs/product/lineup-product-parity-matrix.md`, do not mark complete until proof
- `docs/development/windows-ui-proof-plan.md`, add later QA checklist rows if useful

Work:

- record RD-25 code-first implementation status
- keep RD-25 completion proof pending
- update architecture owner docs for new helper/production playback seams
- document no binary redistribution
- document redaction constraints
- add import-ledger rows for any copied/adapted upstream Lineup playback UI/source/copy/test

Acceptance:

- docs reflect implementation without making proof claims
- no raw private evidence in tracked docs
- all verifiers pass

Commands:

```bash
npm run typecheck
npm run verify:architecture
npm run test
npm run verify:docs
npm run verify:redaction
npm run verify:maintainability
git diff --check
npm run verify
```

Stop/replan if:

- docs verifier rejects active plan shape
- redaction verifier flags source/docs/tests
- docs would need to include private proof details

Commit:

```text
docs: record RD-25 code implementation status
```

---

## Verification Commands

### Per-unit minimum

Run the focused commands named in each unit.

### Full code-complete verification

```bash
git status --short --branch
npm run typecheck
npm run verify:architecture
npm run test
npm run verify:docs
npm run verify:redaction
npm run verify:maintainability
git diff --check
npm run verify
```

### Native helper local build verification

Run only where the local helper prerequisites exist:

```bash
dotnet build src/native-helper/Lineup.NativePlayerHost/Lineup.NativePlayerHost.csproj -c Release
```

### Optional app smoke

Allowed during coding, but not a substitute for the later manual QA pass:

```bash
npm run smoke:electron
```

Expected automated outcomes:

- TypeScript compiles.
- Architecture verifier confirms renderer/preload/main/helper/domain boundaries.
- Player/native/Plex tests pass.
- Redaction verifier finds no raw secrets/paths/private logs/native handles in tracked files.
- Maintainability verifier either passes or points to documented decomposition/allowlist updates.
- Docs verifier accepts active plan/current-state/roadmap/import-ledger changes.
- `npm run verify` passes before code-complete handoff.

## Acceptance Criteria

### RD-25 code-complete criteria

- Production playback bootstrap no longer uses inline fake resolver/no-op PMS port in reachable production composition.
- A production native host factory exists and is main-owned.
- Native helper protocol is explicit, typed, guarded, and private to main/helper.
- Private Plex playback descriptor reaches helper setup only through main-owned runtime dispatch.
- Renderer/preload contracts do not expose raw playback descriptors, URLs, headers, tokens, selected connection details, PMS leases, helper internals, native handles, native logs, or app paths.
- Live Plex stream resolver composition uses main-owned selected connection, active token, raw media detail, stream policy, and PMS session ports.
- Start/switch/stop/crash/cleanup behavior is covered by injected tests.
- Renderer OSD/player surfaces consume safe player state and do not preserve fake product playback in reachable routes.
- Helper source/build path is present or explicitly unavailable with safe product behavior.
- No native/media binary, generated helper output, screenshots, raw logs, private account/server/library/media names, local paths, endpoint URLs, tokens, headers, payloads, native handles, or private proof are tracked.
- Automated verification commands pass.

### RD-25 proof-complete criteria, deferred to later manual QA

- Live Plex-backed playback observed on Windows for the MVP media modes named in final QA matrix.
- Direct play/direct stream/transcode handoff observed or safely blocked with explicit reason.
- Channel switching, stop, fullscreen, helper crash recovery, and cleanup observed.
- PMS cleanup behavior observed or explicitly classified.
- Redaction-safe proof records only category/count/status facts.
- Implementation/proof review is clean.
- Roadmap can then mark RD-25 complete.

## Replan Triggers

Stop and replan if any of these occur:

- Need to add raw playback URL/header/token/native handle to renderer/preload/public contract.
- Need arbitrary helper RPC or broad preload bridge.
- Need external `mpv` IPC as production path.
- Need to commit native/media binaries or generated helper output.
- Need public package/signing/update/installer changes.
- Need unreviewed dependency or lockfile changes.
- Native helper source cannot be built without introducing package/release obligations.
- PMS start/release cannot be implemented behind a main-owned safe port.
- `DesktopPlayerAdapter`, `PlexPlaybackRuntime`, `streamResolver`, `main/index`, or `preload/index.cts` grows past guardrail without decomposition or reviewed allowlist update.
- Redaction verifier flags private playback material.
- RD-24 current-channel scheduler runtime does not expose a stable main-owned selection seam.
- Manual QA later requires raw/private evidence to diagnose playback failures.

## Rollback Notes

- Unit 0 rollback: remove active plan file and restore docs.
- Unit 1 rollback: restore previous main bootstrap and fake resolver location.
- Unit 2 rollback: revert private context propagation; runtime returns to safe load-only behavior.
- Unit 3 rollback: restore `NativePlayerHostProcess` command framing to safe public command only.
- Unit 4 rollback: remove native helper source/project and build scripts; no package impact if binaries were untracked.
- Unit 5 rollback: production IPC returns unsupported/noop again.
- Unit 6 rollback: restore fake/test resolver composition only; live Plex stream resolver remains isolated.
- Unit 7 rollback: disable production lifecycle start/switch hooks while preserving RD-24 guide state.
- Unit 8 rollback: restore renderer playback UI to safe RD-24 state.
- Unit 9 rollback: revert docs status to code-not-complete.

Any rollback must preserve renderer privilege boundaries and must not delete unrelated RD-24 state.

## Commit Checkpoints

Preferred commits:

1. `docs: add RD-25 production native playback plan`
2. `refactor: isolate playback runtime bootstrap`
3. `feat: carry private playback context through main player runtime`
4. `feat: add private native helper playback protocol`
5. `feat: add product native helper source owner`
6. `feat: wire production native host factory`
7. `feat: wire live Plex stream resolver into playback runtime`
8. `feat: connect scheduled playback lifecycle to native helper`
9. `feat: bind renderer playback surfaces to production player state`
10. `docs: record RD-25 code implementation status`

Keep each commit buildable and reversible. Do not mix docs-only status changes with source behavior unless the commit is an explicit active-plan update.

## Code Review Checklist

Before asking for implementation review:

- No new renderer imports from Electron, Node, main, preload, native-helper, Plex transport, persistence, raw secrets, or diagnostics.
- No renderer-facing contract contains raw URL/header/token/path/native/helper/Plex payload fields.
- `PlayerLoadCommandPayload` remains renderer-safe.
- Runtime private context is main-only.
- Helper protocol output is validated before adapter mutation.
- Helper stderr/stdout raw data is dropped or reduced to safe counts.
- Helper process cleanup is deterministic.
- PMS lease start/release is request-scoped.
- Stale helper events after switch/cleanup are quarantined.
- Production startup does not use fake resolver.
- No generated binaries or local proof artifacts are tracked.
- Redaction verifier passes.
- File-shape guardrails are respected.
- Upstream-adapted playback UI/source/copy/test is recorded in import ledger before or with the import.

## Later Manual QA / Program Proof Plan

This section is intentionally deferred until the MVP coding pass is complete.

Manual QA should cover, on Windows:

- app launch with persisted channels/current channel
- live Plex credential restore and selected server availability
- startup playback of current scheduled program
- channel switch playback
- schedule tick transition
- stop and restart
- fullscreen enter/exit while playing
- OSD/player controls over native video
- now-playing/mini-guide/channel badge state while playing
- helper crash/restart recovery
- PMS cleanup/release behavior
- app quit cleanup
- no raw/private evidence in support bundle or tracked docs
- unsupported media mode safe error behavior

Record only sanitized categories, counts, pass/fail/blocker labels, and relative evidence pointers. Do not track screenshots, raw logs, account/server/library/media names, paths, endpoint URLs, tokens, headers, payloads, native handles, package trees, or private proof.

## Suggested Codex Handoff Prompt

```md
You are Codex working in `TJZine/LineupDesktop` on branch `initial-build`.

Goal: implement RD-25 Production Native Playback MVP as a code-first pass. Manual/UI proof of the running app is deferred until the full MVP coding pass is complete, but automated code verification remains required.

Read first:
- AGENTS.md
- docs/AGENTIC_DEV_WORKFLOW.md
- docs/agentic/plan-authoring-standard.md
- docs/roadmap/desktop-port-roadmap.md
- docs/architecture/CURRENT_STATE.md
- docs/architecture/playback-architecture.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/file-shape-guardrails.md
- docs/architecture/packaging-release-gates.md
- docs/product/lineup-product-parity-matrix.md
- docs/development/windows-ui-proof-plan.md
- src/contracts/player.ts
- src/main/player/nativePlayerHostPort.ts
- src/main/player/nativePlayerHostProcess.ts
- src/main/player/desktopPlayerAdapter.ts
- src/main/player/playerIpc.ts
- src/main/player/plexPlaybackRuntime.ts
- src/main/player/plexPlaybackBridge.ts
- src/main/player/plexPlaybackComposition.ts
- src/main/plex/streamResolver.ts
- src/main/plex/desktopPlexRuntime.ts
- src/main/plex/livePlexTransport.ts
- src/main/index.ts
- RD-24 closeout/handoff if present

Start with:
git status --short --branch

Use the RD-25 code-first plan as the active plan. Do not mark RD-25 complete. Do not start RD-26. Do not add public package/signing/update/native-media redistribution behavior.

Implementation priority:
1. active plan/docs and branch freshness
2. isolate playback runtime bootstrap and remove production fake resolver path
3. propagate private playback descriptor through main-only runtime dispatch
4. add private native helper protocol over existing process seam
5. add product helper source owner without tracked binaries
6. wire production native host factory
7. wire live Plex stream resolver/PMS ports
8. connect start/switch/stop/fullscreen/crash/cleanup behavior
9. bind renderer playback surfaces only through safe player state
10. docs/status update as code implemented/proof pending

Architecture constraints:
- renderer remains unprivileged
- preload remains narrow
- main owns Plex transport, credentials, selected connection details, app paths, persistence, diagnostics, and native playback custody
- helper receives minimum secret-bearing playback setup only from main
- no raw URLs, headers, tokenized URLs, paths, raw Plex payloads, native handles, helper internals, or raw logs in renderer contracts/docs/diagnostics
- no external mpv IPC as production architecture
- no dependency/lockfile/native-media redistribution unless explicitly reviewed

Automated verification before code-complete handoff:
npm run typecheck
npm run verify:architecture
npm run test
npm run verify:docs
npm run verify:redaction
npm run verify:maintainability
git diff --check
npm run verify

End with NEXT_SESSION_HANDOFF:
- Branch:
- Working tree status:
- Implemented units:
- Files changed:
- Verification observed:
- Verification failed/blocked:
- Native helper build status:
- Redaction/private-evidence status:
- RD-25 code status:
- RD-25 manual proof status:
- RD-26 gate:
- Risks:
- Next recommended action:
```

## Status Language To Use During Code-First Work

Use:

- `RD-25 code implementation in progress`
- `RD-25 code-complete, manual proof pending`
- `production native playback proof pending`
- `Windows/manual QA deferred to MVP proof pass`

Do not use until later proof exists:

- `RD-25 complete`
- `production playback proven`
- `Windows playback proof passed`
- `MVP playback ready`
- `package-ready native helper`
- `public release ready`
