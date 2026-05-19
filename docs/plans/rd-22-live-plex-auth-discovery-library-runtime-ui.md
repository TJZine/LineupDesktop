# RD-22A Upstream Lineup UI Skeleton And Body Parity Foundation

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3

Path note: this plan keeps the historical RD-22 filename for handoff continuity.
The active execution target is now RD-22A. Live Plex runtime closeout moves to
RD-22B after the upstream-shaped Desktop app body exists.

## Goal

Stop letting live Plex discovery and rate limiting define whether the Desktop
app can become recognizable. The next blocking product foundation is the
upstream Lineup app body: route structure, onboarding, channel setup shell,
Settings, Guide/EPG, OSD, now-playing information, mini guide, channel badge,
player chrome, focus/back behavior, loading/empty/error states, and visual
hierarchy.

RD-22A imports or adapts the upstream Lineup UI skeleton and body into the
Desktop renderer using fixture or injected renderer-safe data where runtime
owners are not ready. Live Plex, channel creation, scheduler runtime, and
playback must later wire into that body instead of forcing the body to be built
around partial runtime proof.

The intended result is a Desktop app that looks and navigates like a coherent
Lineup product skeleton before live integrations are retried. RD-22A is
fixture-only for incomplete runtime surfaces, but the fixture path must still
use product-like UI, not RD-13 scaffold panels or smoke/debug controls.

## Non-Goals

- Do not retry live Plex proof, make live Plex calls, or require a Plex account
  for RD-22A closeout.
- Do not change main-owned Plex auth, discovery, library, selected-server,
  credential, transport, retry, or persistence behavior.
- Do not change preload contracts, IPC vocabulary, persistence schemas, player
  contracts, native helper behavior, package scripts, dependencies, lockfiles,
  signing, update, installer, or release behavior.
- Do not implement RD-22B live Plex runtime wiring, RD-23 channel creation,
  RD-24 scheduler-backed guide runtime, RD-25 playback, RD-26 media options, or
  RD-27 soak proof.
- Do not preserve reachable fake/debug/draft controls in product routes once an
  upstream-equivalent body surface replaces them.
- Do not copy raw screenshots, logs, account names, server names, library
  titles, media titles, raw paths, endpoint URLs, tokens, headers, raw Plex
  payloads, native handles, process ids, or support bundles into tracked docs,
  tests, diagnostics, or chat.

## Parent Architecture Alignment

The renderer remains unprivileged and owns composition, route display, focus,
keyboard/remote-like interaction, local view state, CSS, and sanitized product
copy. Main, preload, persistence, Plex runtime, player runtime, and native
helper boundaries do not change in RD-22A.

RD-22A may add or refactor renderer-owned screens, route shells, components,
view models, fixture adapters, CSS, focus maps, and renderer tests. It may copy
or adapt upstream UI source, CSS, copy, assets, and tests only with an
import-ledger row before or in the same change. Exact upstream DOM sharing is
not required when upstream browser/webOS assumptions conflict with Desktop
security, process, accessibility, or platform boundaries.

Fixture-backed UI is allowed only to prove the product body and interaction
model. It must not introduce renderer custody of credentials, auth headers,
tokenized URLs, raw Plex payloads, raw media descriptors, native handles,
filesystem paths, Electron APIs, Node APIs, or broad IPC/RPC escape hatches.

## Required Reading

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-quality-loop.md`
4. `docs/agentic/session-prompts/feature-plan.md`
5. `docs/agentic/plan-authoring-standard.md`
6. `docs/architecture/CURRENT_STATE.md`
7. `docs/architecture/file-shape-guardrails.md`
8. `docs/architecture/import-ledger.md`
9. `docs/roadmap/desktop-port-roadmap.md`
10. `docs/product/lineup-product-parity-matrix.md`
11. `docs/development/windows-ui-proof-plan.md`
12. Upstream Lineup UI source under the resolved upstream root:
    `src/modules/ui/**`, `src/styles/**`, route/app shell owners, and adjacent
    tests for onboarding, channel setup, guide, overlays, Settings, and player
    chrome.

Freshness gate: before implementation, run `git status --short --branch`,
`git diff --stat`, resolve the upstream Lineup checkout, then run
`git -C <upstream-root> status --short --branch` and
`git -C <upstream-root> rev-parse HEAD`. If upstream UI paths moved, Desktop
renderer ownership changed materially, the active branch changed, or this plan
conflicts with the roadmap, update and re-review the plan before editing source.

## Required Skills

- `execution-plan-authoring`: this is a Tier 3 re-slice of the active product
  plan and must remain decision-complete.
- `lineup-desktop-feature-quality-loop`: RD-22A requires plan, review,
  implementation, verification, implementation review, and closeout gates.
- `lineup-desktop-feature-review`: required for this replan and each
  implementation unit before closeout.
- `ui-composition-patterns`: renderer route/body/focus/overlay composition is
  the central scope.
- `architecture-boundaries`: required to keep renderer work from changing
  preload/main/Plex/player ownership.
- `verification-strategy`: required because RD-22A is fixture-only but still
  needs visual, focus, smoke, and automated proof.
- `review-request` and `review-adjudication`: required for adversarial review
  and finding resolution.
- `closeout-verification`: required before staging, committing, or calling any
  RD-22A unit complete.

## Evidence And Discovery

- `semantic_search_with_context`: not used for this docs-only replan; previous
  RD-22 attempts found Codanna unavailable or unhelpful for UI parity evidence.
- `semantic_search_docs` or repo-doc search: not used; the active roadmap,
  workflow, and plan files were known and read directly.
- impact analysis: not run for this docs-only replan. Implementation units must
  derive impact from direct renderer and upstream UI reads before editing.
- direct reads / `rg`: read the active roadmap, active RD-22 plan, workflow
  runbook, plan-authoring standard, recent git history, and planner sidecar
  output recommending an RD-22A/RD-22B split.
- official docs: not required because this replan does not change Electron,
  dependency, packaging, signing, API, or external framework behavior.
- observed project evidence: prior commits adapted the RD-22 onboarding route,
  but live proof remains blocked by Plex public rate limiting and the broader
  Desktop app still lacks the complete upstream-shaped body the user expects.
- superseded artifact: `docs/plans/rd-22-upstream-parity-audit-matrix.md`
  remains historical RD-22 runtime evidence, but it is not RD-22A authority
  because it predates the UI-body-first pivot and live-runtime deferral.

## Impact Snapshot

RD-22A implementation may change renderer UI owners and tests:

- `src/renderer/staticDom.ts`
- `src/renderer/routeDom.ts`
- `src/renderer/workflow.ts`
- `src/renderer/navigation.ts`
- `src/renderer/desktopInput.ts`
- `src/renderer/index.ts`
- `src/renderer/plexRuntimeDom.ts`
- `src/renderer/plexRuntimeState.ts`
- `src/renderer/plexRuntimeActions.ts`
- `src/renderer/styles/**`
- `src/__tests__/renderer/**`
- `docs/architecture/import-ledger.md`
- upstream UI source/tests/CSS/copy read-only under the resolved upstream root

Public contracts, preload, Electron main, persistence, Plex runtime, player
runtime, native helper, packaging, dependencies, and lockfiles are out of scope.

Expected user-visible change: the app should present an upstream-shaped Desktop
body for onboarding, setup, guide, overlays, settings, and player chrome even
where data is fixture-backed. Existing fake smoke fixtures may remain in tests
and dev-only harnesses, but not as the primary product route presentation.

Local-only visual proof and run notes remain ignored under `docs/runs/**`.

## Files In Scope

Docs-only replan scope:

- `docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md`
- `docs/roadmap/desktop-port-roadmap.md`

RD-22A implementation scope after review:

- `docs/architecture/import-ledger.md`
- `src/renderer/staticDom.ts`
- `src/renderer/routeDom.ts`
- `src/renderer/workflow.ts`
- `src/renderer/navigation.ts`
- `src/renderer/desktopInput.ts`
- `src/renderer/index.ts`
- `src/renderer/plexRuntimeDom.ts`
- `src/renderer/plexRuntimeState.ts`
- `src/renderer/plexRuntimeActions.ts`
- `src/renderer/styles/**`
- `src/__tests__/renderer/**`
- read-only upstream UI source, CSS, assets, copy, and tests under the resolved
  upstream Lineup checkout

## Files Out Of Scope

- `src/contracts/**`
- `src/preload/**`
- `src/main/**`
- `src/domain/**`
- `src/native/**`
- `src/main/player/**`
- package manifests and lockfiles
- package, signing, update, installer, release, and CI configuration
- tracked raw proof artifacts, screenshots, logs, support bundles, raw Plex
  payloads, endpoint URLs, connection details, tokens, headers, account/server
  names, library/media names, local paths, and native handles

## Planner Self-Check

1. No product architecture decision is unresolved for RD-22A: renderer owns the
   UI body; runtime owners are explicitly out of scope.
2. The plan does not depend on contract, preload, main, persistence, player, or
   package changes.
3. Files out of scope are not hidden wiring for RD-22A; fixture/injected
   renderer-safe data is allowed until runtime slices wire in.
4. Evidence path is recorded as direct reads plus planner sidecar output.
5. Work is assigned to renderer owners and must decompose hotspots rather than
   inflate existing broad files.
6. Tier 3 Architecture Health evidence is included below.
7. A fresh implementer should not need to invent security, IPC, playback,
   persistence, packaging, import, or verification policy.
8. Verification commands, expected outcomes, and stop/replan triggers are named.

## Architecture Seam Decision Gate

Chosen seam: renderer-only upstream UI body parity with fixture/injected
renderer-safe data. Runtime slices wire into this seam later.

Forbidden shortcuts:

- no renderer Plex fetches or network transport
- no renderer storage of credentials, raw server connections, raw media
  descriptors, native handles, or token-bearing values
- no broad preload bridge or arbitrary IPC channel strings
- no dependency or lockfile change
- no upstream path shim or compatibility barrel
- no reachable fake/debug/draft controls in product routes after replacement
- no tracked raw visual proof

Stop before implementation if the upstream UI body cannot be adapted without
main/preload/runtime changes, new dependencies, raw private data in renderer, or
large unreviewable renderer hotspots.

## Verification Commands

Verification classification: `broader integration/manual proof required`.

Docs-only replan:

- `npm run verify:docs` should pass.
- `npm run verify:redaction` should pass.
- `git diff --check` should pass.

RD-22A implementation after review:

- `node --import tsx --test src/__tests__/renderer/workflow.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/navigation.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/desktopInput.test.ts src/__tests__/renderer/epg.test.ts src/__tests__/renderer/overlays.test.ts src/__tests__/renderer/plexRuntime.test.ts` should pass.
- `npm run verify` should pass.
- `npm run smoke:electron` should pass.
- Sanitized visual/focus/manual proof should show the fixture-backed,
  upstream-shaped app body
  across onboarding, channel setup shell, Settings, Guide/EPG, OSD,
  now-playing information, mini guide, channel badge, and player chrome without
  raw/private evidence or any claim of live Plex, channel creation, scheduler,
  playback, or media-option runtime completion.
- Read-only implementation review should report no material blockers.

## Acceptance Criteria

- The reachable Desktop app body no longer reads as the RD-13 scaffold with
  isolated real controls dropped into it.
- Upstream Lineup UI structure, hierarchy, copy, focus/back behavior,
  loading/empty/error treatment, and screen relationships are imported or
  adapted for the skeleton/body surfaces named by RD-22A.
- Fixture-backed surfaces are clearly product-shaped and renderer-safe, and the
  proof packet explicitly distinguishes fixture/demo state from live Plex,
  channel creation, scheduler, playback, and media-option runtime completion.
- Fake/debug/smoke/draft controls are isolated from product routes or removed
  where RD-22A owns the visible body.
- Any copied/adapted upstream UI source, CSS, copy, assets, or tests are
  recorded in `docs/architecture/import-ledger.md`.
- No live Plex, channel creation, scheduler runtime, playback, native helper,
  package, dependency, lockfile, or release behavior changes land in RD-22A.
- Verification and adversarial review pass before closeout.

## Replan Triggers

- Upstream UI parity requires contract, preload, main, persistence, player, or
  native-helper changes.
- The renderer would need raw credentials, auth headers, tokenized URLs, raw
  Plex payloads, raw media descriptors, native handles, Electron APIs, Node
  APIs, or broad IPC.
- The work requires a new dependency, package change, lockfile change, or build
  tool change.
- Renderer hotspots would grow past file-shape guardrails without a reviewed
  decomposition or temporary allowlist decision.
- Visual proof would require tracked raw screenshots, logs, paths, private Plex
  names, media names, tokens, URLs, payloads, or native handles.
- Reviewer finds material scope, architecture, verification, import-ledger, or
  fake-surface gaps.

## Rollback Notes

- The docs-only replan can be reverted by reverting this plan and the roadmap
  changes.
- RD-22A implementation should commit in focused units: source inventory/matrix,
  renderer body adaptation, tests, import ledger, and proof summaries when
  needed.
- If RD-22A implementation fails, keep RD-22A active and do not route to RD-22B.
- Ignored local proof notes under `docs/runs/**` may be deleted without
  affecting source.
- Do not roll back unrelated user changes or prior committed runtime fixes
  unless explicitly requested.

## Commit Checkpoints

- Commit 1: `docs(roadmap): split UI body parity from live Plex wiring` after
  this replan passes docs verification and read-only review.
- Later RD-22A implementation commits should stay renderer-focused, for
  example `feat(renderer): adapt upstream Lineup app body skeleton`.
- RD-22B live-runtime commits should be separate from RD-22A UI-body commits.
- Do not stage unrelated changes.

## Architecture Health

RD-22A implementation is expected to touch renderer hotspots near or past the
maintainability threshold. The preferred direction is decomposition, not growth:

- Keep `src/renderer/index.ts`, `src/renderer/plexRuntimeDom.ts`,
  `src/renderer/plexRuntimeActions.ts`, and existing broad CSS files from
  absorbing the whole app body.
- Add focused renderer UI owners only when they map to real upstream body
  surfaces, route shells, focus maps, or view models.
- Avoid increasing `src/preload/index.cts`, main Plex runtime owners, player
  owners, persistence owners, or package owners because they are out of RD-22A.
- Run `npm run verify:maintainability` directly or through `npm run verify`
  after source changes.

Decision: decompose renderer UI body work into focused owners and avoid
pre-authorizing hotspot growth. No temporary allowlist row is approved by this
plan.

Do not add a file-shape allowlist row to pre-authorize growth. If a later unit
cannot avoid crossing a guardrail, replan or record a reviewed temporary
allowlist decision in the implementation packet.

## Execution Units

### Unit 1: Roadmap And Active Plan Pivot

Type: docs/control-plane.

Scope:

- Split RD-22 into RD-22A UI body parity and RD-22B live Plex runtime wiring.
- Update the active plan and roadmap so the next implementation targets the
  upstream-shaped Desktop app body.

Verification:

- `npm run verify:docs`
- `npm run verify:redaction`
- `git diff --check`
- read-only adversarial review

### Unit 2: Upstream UI Body Inventory And Parity Matrix

Type: source-audit/docs after Unit 1 review.

Scope:

- Reconfirm upstream branch and HEAD.
- Inventory upstream app shell, route structure, onboarding, profile/server
  setup, channel setup, Settings, Guide/EPG shell, OSD shell, now-playing
  shell, mini guide shell, channel badge shell, player chrome shell, CSS, copy,
  assets, and tests.
- Map upstream surfaces to Desktop renderer owners, test owners, import-ledger
  obligations, fixture needs, and Desktop divergence reasons.
- Mark every guide/player surface as RD-22A fixture shell/body work or RD-24
  runtime-backed guide/player work so the matrix cannot over-claim future
  runtime parity.

Verification:

- `npm run verify:docs`
- `npm run verify:redaction`
- `git diff --check`
- read-only review of the matrix before implementation

### Unit 3: Renderer UI Body Adaptation

Type: renderer implementation after Unit 2 review.

Scope:

- Adapt upstream-shaped app body surfaces using renderer-safe fixture/injected
  data where runtime behavior is not ready.
- Isolate or remove fake/debug/draft controls from product routes.
- Add or update renderer tests for structure, focus/back, scroll, text-entry
  bypass, loading/empty/error states, and route isolation.
- Update the import ledger for copied/adapted upstream UI/CSS/copy/tests.

Verification:

- focused renderer tests named by the unit
- `node --import tsx --test src/__tests__/renderer/workflow.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/navigation.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/desktopInput.test.ts src/__tests__/renderer/epg.test.ts src/__tests__/renderer/overlays.test.ts src/__tests__/renderer/plexRuntime.test.ts`
- `npm run verify`
- `npm run smoke:electron`
- sanitized visual/focus/manual proof that labels fixture/demo state explicitly
- read-only implementation review

### Unit 4: RD-22A Closeout And RD-22B Handoff

Type: proof/review/docs.

Scope:

- Confirm fixture-only UI body parity evidence is clean and explicitly labels
  live Plex, channel creation, scheduler, playback, and media-option runtime as
  not proven by RD-22A.
- Do not retry live Plex proof.
- Produce the next handoff to RD-22B live Plex onboarding runtime wiring into
  the established UI body.

Verification:

- `npm run verify:docs`
- `npm run verify:redaction`
- `git diff --check`
- closeout review

## RD-22B Deferred Runtime Scope

RD-22B will own live Plex auth/profile/discovery/library wiring into the
RD-22A body after RD-22A closes. RD-22B remains responsible for redaction-safe
Windows proof of live sign-in, profile/Plex Home, server discovery/restore,
server selection, library sections, browse, search, metadata, sanitized failure
states, and relaunch restore. RD-22B must not reshape the app body except for
small data-binding adjustments reviewed against the RD-22A surfaces.

MODEL_SUGGESTION
PLANNER: gpt-5 high reasoning
IMPLEMENTER: gpt-5 high reasoning
REVIEWER: gpt-5 high reasoning
WHY: Tier 3 UI body parity spans broad upstream UI adaptation, renderer route/focus/CSS ownership, import provenance, visual proof, and future live-runtime handoff boundaries.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop
TASK: Complete RD-22A Upstream Lineup UI Skeleton And Body Parity Foundation
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md
ARTIFACT: Unit 2 upstream UI body inventory and parity matrix
FILES:
- docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md
- docs/roadmap/desktop-port-roadmap.md
- docs/architecture/import-ledger.md
- src/renderer/staticDom.ts
- src/renderer/routeDom.ts
- src/renderer/workflow.ts
- src/renderer/navigation.ts
- src/renderer/desktopInput.ts
- src/renderer/index.ts
- src/renderer/plexRuntimeDom.ts
- src/renderer/plexRuntimeState.ts
- src/renderer/plexRuntimeActions.ts
- src/renderer/styles/**
- src/__tests__/renderer/**
- <upstream-root>/src/modules/ui/**
- <upstream-root>/src/styles/**
BLOCKERS: RD-22B live Plex proof remains blocked until Plex rate limiting clears; RD-22A must not retry live Plex or change main/preload/runtime owners.
MESSAGE:
Start with Unit 2. Reconfirm the upstream Lineup branch and HEAD, inventory the upstream app shell/body surfaces, route structure, onboarding/profile/server setup, channel setup, Settings, Guide/EPG shell, OSD shell, now-playing shell, mini guide shell, channel badge shell, player chrome shell, CSS, copy, assets, and tests. Produce a parity matrix mapping each upstream body surface to Desktop renderer owners, fixture/injected data needs, import-ledger obligations, tests, visual/focus proof, and Desktop divergence reasons. Mark every guide/player surface as RD-22A fixture shell/body work or RD-24 runtime-backed guide/player work so RD-22A cannot over-claim runtime parity. Keep this unit docs/source-audit only; do not edit source, do not make live Plex calls, and do not change main/preload/contracts/runtime/persistence/player/package behavior. Send the matrix to read-only adversarial review before implementation.
