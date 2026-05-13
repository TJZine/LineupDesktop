# RD-15 UI Over Native Video Integration Plan

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3
**Tracked path:** `docs/plans/2026-05-13-rd-15-ui-over-native-video-integration-plan.md`
**Created:** 2026-05-13

## Goal

Complete RD-15 by making the renderer EPG, OSD, mini guide, channel badge,
settings, channel setup, and player overlay surfaces behave as UI over the
reviewed app-owned native playback presentation boundary.

The finished item must prove stable renderer z-order and focus in both windowed
and fullscreen modes while preserving the current architecture fact that
production native-helper playback, live Plex transport, and package/release work
are not implemented in RD-15.

RD-15 may split implementation into bounded units, but the plan owns the whole
roadmap item through plan review, implementation review, automated verification,
and Windows platform proof.

## Non-Goals

- Do not reopen RD-14 unless implementation or proof finds a concrete
  contradiction in the completed RD-14 fullscreen, focus, input, cursor, or
  Windows evidence.
- Do not implement production native-helper playback, ship or package a native
  helper binary, bind libmpv in product runtime code, or turn production player
  commands into real native playback.
- Do not add live Plex transport, renderer Plex APIs, tokenized playback URLs,
  raw Plex payloads, auth headers, persistent credentials, or selected-server
  runtime wiring.
- Do not add preload APIs, IPC channels, player contract shapes, package
  dependencies, lockfile changes, installer/signing/update behavior, or app-path
  persistence unless read-only review accepts a replan first.
- Do not copy or adapt upstream Lineup product source in RD-15 unless the
  implementation unit first updates `docs/architecture/import-ledger.md` with a
  reviewed import row.

## Parent Architecture Alignment

RD-14 is complete and is treated as closed. RD-15 builds on RD-13 renderer UI,
ARCH-01 renderer hotspot preparation, and RD-14 window/input/fullscreen proof.

The renderer remains the owner of UI composition, route state, focus projection,
overlay view models, fake-backed EPG/settings/channel-setup state, and CSS
presentation. Renderer code stays unprivileged and may consume only renderer-safe
player snapshots or fake view models already available through the existing
contract vocabulary.

The app-owned native presentation path from RD-06 remains the reviewed native
surface direction. RD-15 may use or extend the existing dev-only
native-presentation proof harness to demonstrate native video, composition,
fullscreen, focus, cleanup, and redaction behavior. Existing RD-06 harness proof
is not decision-complete for RD-15 if it only renders hard-coded RD06 overlay
HTML; Unit 3 owns a dev-only RD-15 proof extension when needed so the proof
loads or mirrors the built product renderer UI surfaces sufficiently to show
EPG, OSD, mini guide, channel badge, settings, channel setup, and overlays over
active native video in both windowed and fullscreen modes. That proof does not
promote the harness into production playback architecture.

The production player adapter, Plex playback runtime, stream resolver, preload
bridge, player contracts, packaging, and live Plex transport stay outside RD-15
unless a reviewed replan changes the boundary.

## Required Reading

Read these in order before editing:

- `AGENTS.md`
- `docs/AGENTIC_DEV_WORKFLOW.md`
- `docs/agentic/session-prompts/feature-plan.md`
- `docs/agentic/session-prompts/feature-review.md`
- `docs/agentic/session-prompts/feature-implement.md`
- `docs/agentic/plan-authoring-standard.md`
- `docs/architecture/CURRENT_STATE.md`
- `docs/roadmap/desktop-port-roadmap.md`
- `docs/architecture/file-shape-guardrails.md`
- `docs/architecture/renderer-architecture.md`
- `docs/architecture/playback-architecture.md`
- this plan

Freshness gate: before implementation, run `git status --short --branch` and
directly reread any in-scope source file that changed after this plan was
written. If renderer ownership, player/preload contracts, native-presentation
proof semantics, file-shape guardrails, or RD-14 closeout facts changed
materially, stop and re-review or replan before editing.

## Required Skills

- `lineup-desktop-feature-plan`: owns this tracked feature/design plan.
- `execution-plan-authoring`: keeps scope, ownership, verification, acceptance,
  rollback, and stop conditions decision-complete.
- `architecture-boundaries`: applies because RD-15 depends on renderer/native
  presentation ownership and must not leak privileged playback concerns.
- `ui-composition-patterns`: applies because RD-15 changes renderer layout,
  focus, keyboard/remote behavior, overlays, and media-surface presentation.
- `verification-strategy`: applies because automated renderer proof must be
  paired with Windows native video/manual proof.
- `review-request`: next gate is read-only adversarial plan review through
  `lineup-desktop-feature-review`.
- `closeout-verification`: required before calling RD-15 done, staging,
  committing, or handing off after implementation.

## Evidence And Discovery

- `semantic_search_with_context`: Codanna index exists with 3775 symbols across
  137 files, but semantic search failed with `No embeddings available for
  search`. Direct reads and `rg` are the authoritative fallback for this plan.
- `semantic_search_docs`: also failed with `No embeddings available for search`;
  repo-doc discovery used direct reads and `rg`.
- impact analysis: Codanna symbol lookup was stale/noisy for renderer functions
  that direct reads located, so impact was bounded by exact file reads and
  roadmap/architecture docs instead of Codanna relationship output.
- direct reads / `rg`: read all required workflow and architecture docs, RD-15
  roadmap text, file-shape guardrails, renderer/playback architecture, current
  renderer modules, renderer tests, smoke assertions, package scripts, and the
  RD-06 native-presentation harness CLI.
- official docs: no external framework, Electron API, dependency, packaging,
  signing, native-player, or API behavior is changed by this plan. If an
  implementation unit needs new Electron/native behavior beyond existing
  repo-reviewed APIs, stop and add an official-docs check to the reviewed replan.

Observed source facts:

- RD-13/ARCH-01 prepared `src/renderer/overlays.ts` and
  `src/renderer/overlayViewModels.ts` before RD-15.
- Current renderer UI is fake-backed and local: EPG data lives in
  `src/renderer/epg.ts`; settings/channel setup draft state lives in
  `src/renderer/settingsSetup.ts`; route/workflow rendering lives in
  `src/renderer/routeDom.ts`; static player/guide/settings/setup markup lives
  in `src/renderer/staticDom.ts`.
- `src/main/smokeAssertions.ts` already proves renderer boot, secure bridge
  containment, route reachability, EPG fake data, overlay reachability, player
  IPC fake-host delivery, and fullscreen IPC smoke.
- The RD-06 native-presentation harness accepts `--mode
  native-presentation-preflight` and `--mode native-presentation-smoke
  --fullscreen-mode native-presentation-host`, writes redacted evidence through
  `--out`, and already owns dev-only native video, overlay/composition,
  fullscreen, focus, helper cleanup, and redaction proof.
- Current RD-06 native-presentation smoke uses hard-coded RD06 overlay HTML for
  part of the overlay proof. That evidence is useful for the reviewed native
  boundary but is not enough by itself to close RD-15 product UI composition.

## Impact Snapshot

Expected implementation impact:

- Renderer-owned UI composition, focus, view-model, and CSS behavior may change
  for player overlays, EPG, settings, and channel setup.
- Electron smoke assertions may change to verify RD-15 route, overlay, z-order,
  focus, and style invariants in product Electron.
- Dev-only RD-06 native-presentation harness may change only if existing harness
  proof cannot demonstrate the RD-15 UI surfaces over native playback. Any such
  change remains tooling/evidence-only and must be a dev-only RD-15 proof
  extension that loads or mirrors product renderer UI surfaces, not production
  playback wiring.
- Architecture docs and roadmap may change only during RD-15 closeout to record
  observed completion facts.

Expected non-impact:

- Public preload, IPC, player, Plex, persistence, redaction, and shell contracts
  should not change.
- `src/renderer/desktopInput.ts` and `src/renderer/desktopCursor.ts` are not
  product-edit scope for RD-15 unless read-only review accepts a replan for
  behavior changes. Their existing tests may be used as test-only/read-only
  proof that RD-15 preserves input and cursor expectations.
- No dependency, build-tool, configuration, package, or lockfile change is
  expected.
- Production main/player, Plex runtime, persistence, native-helper, and
  packaging code should not change.
- Raw local evidence under `docs/runs/rd-15-ui-over-native-video-integration/`
  is local-only and must stay untracked except for any reviewed durable summary
  promoted into tracked docs at closeout.

The first execution unit remains renderer-owned. Cross-boundary proof is
deferred to a later dev-tool/Windows proof unit so the worker does not mix
product UI behavior with native harness changes unless review accepts that the
existing harness is insufficient.

## Architecture Health

Current file-shape evidence from `docs/architecture/file-shape-guardrails.md`
shows existing production allowlist rows including `src/preload/index.cts` at
575 lines and `src/contracts/player.ts` at 695 lines. The likely RD-15 renderer
files are below the 500-line guardrail at plan time:

- `src/renderer/staticDom.ts`: 162 lines
- `src/renderer/routeDom.ts`: 365 lines
- `src/renderer/focusDom.ts`: 126 lines
- `src/renderer/epg.ts`: 324 lines
- `src/renderer/overlays.ts`: 258 lines
- `src/renderer/overlayViewModels.ts`: 293 lines
- `src/renderer/settingsSetup.ts`: 292 lines
- `src/renderer/desktopInput.ts`: 386 lines
- `src/renderer/desktopCursor.ts`: 119 lines
- `src/renderer/styles/player-overlays.css`: 247 lines
- `src/renderer/styles/workflow-screens.css`: 309 lines

Decision: avoid allowlisted preload/player contract growth entirely; split or
extract renderer/CSS owners before any touched production file crosses 500
lines; use the existing `src/renderer/styles/*` split instead of growing
`styles.css`; keep native proof harness changes dev-only if needed; treat
`src/renderer/desktopInput.ts` and `src/renderer/desktopCursor.ts` as
out-of-scope production behavior owners for RD-15 except through a reviewed
replan.

Maintainability verification route: run `npm run verify:maintainability`
directly for any source-shape-sensitive unit and `npm run verify` before
implementation closeout. Do not add or raise a file-shape allowlist row for
RD-15 unless plan review accepts a replan explaining why decomposition is not
the better move.

## Files In Scope

Product renderer source, only as needed for RD-15:

- `src/renderer/index.ts`
- `src/renderer/staticDom.ts`
- `src/renderer/domBindings.ts`
- `src/renderer/routeDom.ts`
- `src/renderer/focusDom.ts`
- `src/renderer/navigation.ts`
- `src/renderer/workflow.ts`
- `src/renderer/epg.ts`
- `src/renderer/overlays.ts`
- `src/renderer/overlayViewModels.ts`
- `src/renderer/settingsSetup.ts`
- `src/renderer/styles.css`
- `src/renderer/styles/base.css`
- `src/renderer/styles/player-overlays.css`
- `src/renderer/styles/responsive-accessibility.css`
- `src/renderer/styles/workflow-screens.css`

Tests and smoke proof:

- `src/__tests__/renderer/navigation.test.ts`
- `src/__tests__/renderer/workflow.test.ts`
- `src/__tests__/renderer/epg.test.ts`
- `src/__tests__/renderer/overlays.test.ts`
- `src/__tests__/renderer/desktopInput.test.ts` as test-only/read-only proof
  surface; do not expand production `desktopInput.ts` behavior without replan
- `src/__tests__/renderer/desktopCursor.test.ts` as test-only/read-only proof
  surface; do not expand production `desktopCursor.ts` behavior without replan
- `src/main/smokeAssertions.ts`

Dev-only Windows proof tooling, only if existing proof is insufficient:

- `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`
- `tools/libmpv-spike/rd-06-native-libmpv-host-spike-helper.cs`
- `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs`

Closeout docs, only after implementation and review evidence exists:

- `docs/architecture/CURRENT_STATE.md`
- `docs/architecture/renderer-architecture.md`
- `docs/architecture/playback-architecture.md`
- `docs/roadmap/desktop-port-roadmap.md`
- `docs/architecture/import-ledger.md` only if copied/adapted upstream source
  is introduced by reviewed replan

## Files Out Of Scope

- `src/preload/index.cts`
- `src/contracts/player.ts`
- `src/contracts/ipc.ts`
- `src/contracts/plex.ts`
- `src/contracts/persistence.ts`
- `src/main/index.ts`
- `src/main/player/desktopPlayerAdapter.ts`
- `src/main/player/nativePlayerHostPort.ts`
- `src/main/player/nativePlayerHostProcess.ts`
- `src/main/player/playerIpc.ts`
- `src/main/player/plexPlaybackRuntime.ts`
- `src/main/player/plexPlaybackBridge.ts`
- `src/main/player/plexPlaybackComposition.ts`
- `src/main/plex/streamResolver.ts`
- `src/main/plex/**`
- `src/main/persistence/**`
- `src/domain/**`
- `src/renderer/desktopInput.ts` for product behavior changes unless a reviewed
  replan accepts input behavior scope
- `src/renderer/desktopCursor.ts` for product behavior changes unless a
  reviewed replan accepts cursor behavior scope
- `src/native-helper/**` or any new native-helper production path
- `package.json`, package manager lockfiles, installer, signing, updater, and
  release configuration
- `docs/runs/archive/**`

If an implementation unit appears to require any out-of-scope file, stop and
route a reviewed replan before editing it.

## Planner Self-Check

1. Product, architecture, ownership, dependency, and verification decisions are
   resolved at plan level: renderer owns UI behavior; dev-only harness owns
   platform proof; production playback, Plex, preload, contracts, and packaging
   are excluded.
2. The plan does not depend on hidden adjacent contract or type changes. Public
   player/preload/IPC shapes stay unchanged.
3. Files out of scope are not relied on for hidden wiring. Existing player
   snapshot and fullscreen bridge behavior may be consumed but not expanded.
4. Evidence path and Codanna fallback are recorded.
5. The work is assigned to the existing renderer owner and avoids known
   preload/player contract hotspots.
6. Tier 3 Architecture Health evidence is included with avoidance and split
   decisions for touched hotspots.
7. A fresh implementer should not need to invent security, IPC, playback,
   persistence, packaging, import, or verification policy.
8. Verification commands, expected outcomes, Windows proof policy, rollback,
   and replan triggers are explicit.

## Architecture Seam Decision Gate

Chosen seam: RD-15 is a renderer composition and presentation integration over
an already-reviewed dev-only native presentation proof boundary. Product UI
state remains renderer-local and renderer-safe. Product input/cursor behavior
owners are preserved: `desktopInput.ts` and `desktopCursor.ts` may be observed by
tests but not edited for behavior in RD-15 without replan. Native video proof
remains in the RD-06 tooling boundary unless a reviewed replan creates a new
tooling owner.

Allowed implementation units:

1. Renderer surface layering and route presentation: make player/guide/settings
   and channel setup compose predictably over the player surface without
   privileged renderer access.
2. Overlay and focus behavior: harden OSD, mini guide, channel badge, channel
   number, playback options, route focus, and fullscreen focus expectations with
   public renderer tests.
3. Smoke and style proof: extend Electron smoke assertions for RD-15 z-order,
   route reachability, style, focus, and overlay stack behavior.
4. Windows native-presentation proof: run or minimally extend the dev-only
   native-presentation harness so actual RD-15 UI surfaces, or a proof mirror
   built from product renderer output, are proven over active native video in
   windowed and fullscreen modes with redacted evidence.
5. Closeout docs: after clean implementation review and verification, update
   durable roadmap/architecture facts and archive this plan locally.

Forbidden shortcuts:

- No broad preload RPC, new arbitrary IPC channel, raw Electron object, Node API,
  native handle, token-bearing URL, auth header, raw Plex payload, or privileged
  diagnostic in renderer-facing code.
- No production native-helper playback implementation, package/dependency
  expansion, or packaging/release bypass.
- No compatibility barrels, old upstream path mirrors, fake fallback API
  variants, or broad helpers that obscure owner boundaries.
- No plan-closeout claim based only on CSS or unit tests; RD-15 needs observed
  smoke and Windows native-surface proof.

Stop at this gate if the implementer cannot keep the first product unit
renderer-owned or if native proof requires production playback.

## Verification Commands

Verification classification: broader integration/manual proof required.

Automated local proof, expected to pass before implementation closeout:

- `npm run typecheck`
  - Expected: TypeScript completes without errors.
- `npm run test:contracts`
  - Expected: renderer, contract, main, preload, and harness-facing tests pass;
    new RD-15 tests cover stable renderer behavior rather than private helper
    internals.
- `npm run smoke:electron`
  - Expected: secure shell smoke still passes and additionally proves RD-15
    route/overlay reachability, z-order/style invariants, fullscreen bridge
    continuity, and focused DOM control behavior.
- `npm run verify:maintainability`
  - Expected: no touched production source file violates file-shape guardrails
    and no allowlist row is raised without reviewed replan.
- `npm run verify:redaction`
  - Expected: no secret-bearing, raw Plex, native-handle, raw URL, raw path, or
    raw process evidence leaks into tracked output.
- `npm run verify`
  - Expected: full local verification passes before closeout.

Windows/platform proof policy:

- RD-15 cannot close without Windows proof unless read-only review accepts a
  replan deferring an explicit proof gap to another named roadmap item.
- On Windows, run:
  - `node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode native-presentation-preflight --out docs/runs/rd-15-ui-over-native-video-integration`
  - `node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode native-presentation-smoke --fullscreen-mode native-presentation-host --out docs/runs/rd-15-ui-over-native-video-integration`
- Expected Windows proof: active dummy native video pixels; RD-15 EPG, OSD,
  mini guide, channel badge, settings, channel setup, and overlay surfaces
  visibly composed above the native surface; distinct windowed and fullscreen
  overlay/composition evidence; focused renderer controls over native playback;
  app-owned input/focus continuity; helper crash/cleanup evidence; temp cleanup;
  no forbidden header observation; and redacted evidence scan success.
- If current RD-06 tooling cannot prove actual RD-15 product UI surfaces,
  implement only a dev-only harness extension inside the in-scope tool files and
  cover that extension with `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs`.
  The extension must load the built product renderer when practical, or mirror
  product renderer output from in-scope renderer DOM/CSS enough to prove the
  named RD-15 surfaces. Evidence must identify each named surface, windowed
  native-video composition, fullscreen native-video composition, renderer focus,
  and redaction result without recording raw URLs, headers, native handles,
  local paths, or process diagnostics.

Manual inspection, expected before closeout:

- Windowed product Electron smoke shows player, OSD, mini guide, channel badge,
  guide/EPG, settings, and channel setup controls above the player surface with
  no incoherent overlap.
- Fullscreen Windows proof shows the same classes of UI over active native video
  and preserves keyboard/remote-style focus.
- Settings copy exposes Desktop capability truth and does not introduce webOS
  labels as product truth.

## Acceptance Criteria

- Player overlay stack renders above the player/native surface, with channel
  badge and now-playing passive overlays plus OSD, mini guide, channel number,
  and playback options modal focus behavior preserved.
- EPG, settings, and channel setup routes remain reachable and usable while the
  player surface remains the visual background/presentation context.
- DOM focus remains on renderer controls during overlay, EPG, settings,
  channel-setup, and fullscreen interactions; focus restoration is deterministic
  after closing modal overlays.
- Z-order is stable in windowed and fullscreen modes and is proven by Electron
  smoke plus Windows native-presentation evidence.
- EPG rendering remains bounded to the current fake visible rows and slots;
  implementation does not introduce unbounded DOM growth, polling, or listener
  churn.
- Renderer stays unprivileged and no forbidden Plex/player/native fields appear
  in renderer view models, smoke output, tracked docs, or redacted evidence.
- Desktop settings/channel setup copy remains Desktop-accurate and local/fake
  where runtime persistence and live Plex are not yet wired.
- No production native-helper playback, live Plex transport, preload method,
  public contract, dependency, package, lockfile, or packaging behavior lands in
  RD-15.
- Plan review and implementation review are clean before closeout.

## Replan Triggers

- RD-15 requires editing any out-of-scope preload, contract, production
  main/player, Plex, persistence, domain, native-helper, package, or packaging
  file.
- RD-15 requires product behavior edits to `src/renderer/desktopInput.ts` or
  `src/renderer/desktopCursor.ts` instead of proving preservation through
  existing public tests/smoke.
- Existing RD-06/RD-14 native-presentation proof is contradicted by fresh
  Windows evidence or cannot prove RD-15 UI surfaces without production native
  playback.
- The RD-15 native-presentation proof cannot load or mirror product renderer UI
  surfaces well enough to identify EPG, OSD, mini guide, channel badge,
  settings, channel setup, and overlays in both windowed and fullscreen modes.
- Renderer implementation would grow a touched production file beyond 500 lines
  or require raising an allowlist baseline.
- EPG performance proof requires virtualization or scheduler/domain/runtime
  behavior beyond fake renderer view models.
- Settings or channel setup needs persisted preferences, selected-server state,
  live Plex data, or secure storage.
- A new Electron/native API, dependency, or packaging behavior becomes necessary
  to prove the roadmap item.
- Redaction or smoke proof finds raw URLs, auth headers, tokens, native handles,
  raw local paths, or process diagnostics in renderer-facing or tracked output.
- Plan review finds a material scope, ownership, verification, or platform-proof
  gap.

## Rollback Notes

- Product renderer changes should be reverted by execution unit: renderer
  layering/focus/style changes first, then smoke/test changes that only assert
  those behaviors.
- Dev-only native-presentation harness changes, if any, must be isolated from
  product source and can be reverted independently while preserving RD-06/RD-14
  completed proof history.
- Local redacted evidence under `docs/runs/rd-15-ui-over-native-video-integration/`
  is ignored local material and should be removed or regenerated, not committed
  as rollback state.
- If closeout docs are updated and a later review rejects completion, revert the
  RD-15 status/doc conclusion while keeping any reviewed source fixes that remain
  valid.
- Do not use rollback to reopen RD-14 unless the specific contradiction is
  documented and reviewed.

## Commit Checkpoints

Use focused conventional commits after clean review of each implemented unit:

- `feat(renderer): integrate rd-15 ui over player surface`
- `test(renderer): prove rd-15 overlay focus and smoke behavior`
- `test(playback): prove rd-15 native presentation composition`
- `docs(roadmap): close rd-15 ui over native video integration`

Do not stage unrelated local changes. Keep workflow/control-plane or verifier
changes separate from product implementation unless a reviewed replan explains
why one atomic commit is safer.

## Implementation Units

Unit 1, renderer layering and copy:

- Scope: product renderer source and renderer tests only.
- Goal: make player, guide/EPG, settings, channel setup, and overlay surfaces
  intentionally compose over the player presentation surface; ensure settings
  copy is Desktop capability truth.
- Stop if preload/contracts/main/native tooling or product behavior edits to
  `src/renderer/desktopInput.ts` or `src/renderer/desktopCursor.ts` are needed.
- Verification: `npm run typecheck`, `npm run test:contracts`,
  `npm run verify:maintainability`. If visible composition changes are made,
  also run a focused product smoke pass with `npm run smoke:electron` before
  handing off to Unit 2.

Unit 2, focus/z-order/smoke:

- Scope: renderer focus/navigation tests, overlay/EPG/workflow tests,
  `src/main/smokeAssertions.ts`, and styles.
- Goal: lock stable public behavior for z-order, route reachability, overlay
  focus fallback, fullscreen bridge continuity, and no incoherent overlap.
- Stop if proof requires private renderer implementation probes, product
  `desktopInput.ts`/`desktopCursor.ts` behavior edits, or privileged APIs instead
  of public DOM/contract behavior.
- Verification: `npm run smoke:electron`, `npm run verify`.

Unit 3, Windows native-presentation proof:

- Scope: RD-06 native-presentation harness files only if existing harness cannot
  prove RD-15 UI surfaces as-is; local ignored evidence under `docs/runs/`.
- Goal: prove windowed and fullscreen active native video with RD-15 UI
  composition and renderer focus. Existing hard-coded RD06 overlay HTML is not
  enough for this unit. If needed, add a dev-only RD-15 native-presentation proof
  extension that loads the built product renderer or mirrors product renderer
  DOM/CSS from in-scope renderer surfaces sufficiently to identify EPG, OSD,
  mini guide, channel badge, settings, channel setup, and overlays over active
  native video.
- Files: `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`,
  `tools/libmpv-spike/rd-06-native-libmpv-host-spike-helper.cs` only if helper
  proof metadata is necessary, and
  `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs`.
- Proof semantics: evidence must distinguish windowed and fullscreen native
  video pixels from renderer UI pixels, name each RD-15 surface observed, prove
  renderer focus/control ownership while native video is active, include helper
  cleanup/crash evidence, and remain redacted. It must not require product
  native-helper playback, live Plex transport, package changes, new preload or
  IPC contracts, raw URLs, auth headers, native handles, local paths, or process
  diagnostics.
- Expected evidence: redacted manifest/events/summary under
  `docs/runs/rd-15-ui-over-native-video-integration/` showing preflight pass or
  explicit platform block, active dummy native video, RD-15 surface composition
  in windowed mode, RD-15 surface composition in fullscreen native-presentation
  host mode, focus/input continuity, cleanup, and redaction success.
- Stop/replan if the harness cannot load or mirror product renderer surfaces
  without production playback, if proving the UI needs source edits outside the
  listed harness files, if helper changes become production native-helper work,
  if product input/cursor behavior changes are needed, or if redacted evidence
  cannot identify the named RD-15 surfaces in both modes.
- Verification: Windows preflight/smoke commands listed above plus
  `npm run verify:redaction`; if the harness extension changes, also run
  `npm run test:contracts` or the narrower reviewed command that includes
  `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs`.

Unit 4, closeout memory:

- Scope: architecture/roadmap/import-ledger docs only after implementation
  review and Windows proof pass.
- Goal: record observed RD-15 completion facts, then archive this full plan body
  locally under `docs/runs/archive/plans/` and remove it from tracked active
  plans.
- Stop if any review finding remains material.
- Verification: `npm run verify:docs`, then `npm run verify`.

MODEL_SUGGESTION
PLANNER: gpt-5
IMPLEMENTER: gpt-5
REVIEWER: gpt-5
WHY: Tier 3 work touches renderer/native video composition, focus, fullscreen,
and Windows platform proof while preserving privileged playback boundaries.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop
TASK: Complete RD-15 UI Over Native Video Integration Through Quality Loop
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-05-13-rd-15-ui-over-native-video-integration-plan.md
ARTIFACT: RD-15 Units 1-3 implemented, verified, and clean-reviewed locally; Windows native-presentation proof remains.
FILES:
- docs/plans/2026-05-13-rd-15-ui-over-native-video-integration-plan.md
- src/renderer/staticDom.ts
- src/renderer/routeDom.ts
- src/renderer/focusDom.ts
- src/renderer/settingsSetup.ts
- src/renderer/styles/base.css
- src/renderer/styles/player-overlays.css
- src/main/smokeAssertions.ts
- src/__tests__/renderer/workflow.test.ts
- src/__tests__/renderer/routeDom.test.ts
- src/__tests__/renderer/focusDom.test.ts
- tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs
- tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs
- docs/architecture/CURRENT_STATE.md
- docs/roadmap/desktop-port-roadmap.md
- docs/architecture/renderer-architecture.md
- docs/architecture/playback-architecture.md
BLOCKERS: Windows native-presentation preflight/smoke cannot be observed on the current Darwin host.
MESSAGE:
Continue RD-15 at closeout pending / platform-proof phase. The tracked plan has
clean plan review; Units 1 and 2 implemented product renderer layering,
off-route overlay suppression, focus behavior, z-order/fullscreen smoke proof,
and Desktop-local settings copy; Unit 3 extended the dev-only RD-06 native
presentation harness with reviewed RD-15 windowed/fullscreen pixel proof gates
for EPG, OSD, mini guide, channel badge, settings, channel setup, overlays, and
focus. Controller-observed verification on Darwin passed `npm run
test:harness-docs`, `npm run verify:redaction`, `git diff --check`, and `npm
run verify`. A fresh read-only Unit 3 review found no blockers, but RD-15 is
not done because the roadmap requires Windows native-presentation evidence. On
Windows, run the plan's preflight and smoke commands into
`docs/runs/rd-15-ui-over-native-video-integration/`, verify the redacted
manifest/summary show RD-15 native presentation UI 16/16 observed with existing
native video/fullscreen/composition/helper cleanup gates passing, then run
`npm run verify:redaction` and `npm run verify`. If Windows proof passes, route
to Unit 4 closeout memory: update current-state/roadmap/playback or renderer
architecture docs as needed, archive this active plan body locally under
`docs/runs/archive/plans/`, remove the tracked active plan, and run
`npm run verify:docs` plus `npm run verify`. If Windows proof fails, keep RD-15
active and route the failure through implementation-review/revise without
expanding production native-helper playback, live Plex transport, preload
contracts, packaging, or product IPC.
