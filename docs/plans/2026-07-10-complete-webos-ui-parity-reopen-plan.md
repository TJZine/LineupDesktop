# Complete WebOS UI Parity Reopen Plan

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3
**Current execution unit:** Package 5 — Scheduler-backed Guide parity is next
and unstarted. The source-proven pre–Package 5 remediation is closed with full
verification, adjudicated fresh review, and a clean targeted re-review.
Packages 0–4 otherwise remain closed; RD-27 remains blocked until Packages 5–8
close.

## Goal

Finish observed WebOS-informed visual and interaction parity for the reachable
Lineup Desktop MVP before RD-27. The remaining work must:

- render Guide content from existing scheduler/channel state with honest empty
  and failure states;
- bind player presentation and overlay choreography to real renderer-safe
  runtime state instead of production fixtures;
- align supported overlay surfaces with the upstream hierarchy while preserving
  Desktop security, native playback, accessibility, and platform divergences;
- prove every reachable state at exact CSS viewports `1280x720` and `1920x1080`;
  and
- make tracked product, architecture, parity, and roadmap claims match the
  observed application.

## Non-Goals

- Do not begin RD-27 soak or public release work.
- Do not copy WebOS storage, direct Plex fetches, token-bearing URLs, raw media
  payloads, player custody, lifecycle, or packaging behavior.
- Do not expose Electron, Node, paths, credentials, handles, or private playback
  descriptors to the renderer.
- Do not add dependencies, change native-helper behavior, or change
  signing/update/release policy.
- Do not add fake controls or data for unsupported upstream features.
- Do not reopen Packages 0–4 without a source-proven contradiction and reviewed
  replan.
- Do not treat snapshots or pixel equality as the sole behavior proof.

## Architecture And Invariants

- Renderer owns DOM/CSS, screen/overlay state, focus/input, safe view models,
  timers/listeners, and cleanup.
- Contracts contain renderer-safe public shapes only.
- Preload validates and exposes narrow namespaces; it is not a generic RPC or
  persistence owner.
- Main owns privileged IPC, app paths, versioned persistence, and sanitized
  failures.
- Existing player, Guide, channel, and Plex owners remain runtime truth. Native
  and helper custody does not move.
- Upstream is presentation/interaction authority, not process-architecture
  authority. Every intentional visible divergence needs evidence and an owner.
- Keep cohesive behavior together. Extract only a distinct current
  responsibility, lifecycle, trust boundary, policy, or consumer into a module
  that owns meaningful behavior; never split for line count alone.
- Product code must not import deterministic presentation fixtures.
- Hidden screens and overlays are inert; modal precedence, focus restoration,
  stale-result rejection, and timer/listener cleanup are explicit.
- Local captures and runtime material stay under the ignored
  `docs/runs/complete-webos-ui-parity-reopen/` bundle and remain sanitized.

Before each package, record current Desktop/upstream commits and scoped status.
Stop for plan refresh when scoped UI, ownership, contracts, dependencies, or
this plan changed materially.

Required skills are `lineup-desktop-feature-quality-loop`,
`architecture-boundaries`, `typescript-quality-boundaries`,
`typescript-test-design`, the matching UI/Plex/persistence boundary skills,
`verification-strategy`, `review-request`, and `closeout-verification`.

## Files In Scope

Package 5 may change only `src/renderer/epg.ts`,
`src/renderer/guidePresentation.ts`,
`src/renderer/guidePresentationPolling.ts`,
`src/renderer/epg/guideDom.ts`, `src/renderer/focusDom.ts`,
`src/renderer/routeDom.ts`, `src/renderer/workflow.ts`,
`src/renderer/index.ts` for composition wiring only,
`src/renderer/styles/guide-epg.css`, and the six focused tests named in its
package. Packages 6–7 must be promoted to the same exact-file standard before
they become current. Package 8 changes evidence and tracked memory unless it
routes a defect back to its owning package.

## Files Out Of Scope

- native/helper, packaging, signing, updater, installer, and release files
- dependencies and lockfiles
- credential/channel persistence and token-bearing Plex transport
- new scheduler, channel, Plex, player, or media contracts unless a reviewed
  replan proves an existing renderer-safe seam is insufficient
- unrelated renderer CSS or completed Packages 0–4 owners
- tracked captures, logs, account/server/library/media names, private paths,
  URLs, headers, tokens, handles, or playback descriptors

## Completed Baseline

- Package 0 corrected the parity authority, target matrix, and baseline evidence.
- Packages 1–3 completed full-screen shell/lifecycle, Plex onboarding/profile/
  server/PIN flows, staged channel setup/custom channels, and their consolidated
  upstream visual-fidelity correction.
- Consolidated checkpoint: `1f61b30d35847baf374bdb00ef0b38fbf9f0394d`.
- Final correction proof recorded 68/68 captures for 34 states, full focused and
  repository verification, and a clean adversarial re-review.
- Upstream correction pin: `4bdb0e1b3370e7893a582ec80226557727832d0b`.
- Package 4 completed main-owned schema-1 settings persistence, total guarded
  IPC/preload behavior, real renderer consumers, relaunch/failure proof, full
  verification, and clean independent review in commit `106412a`.
- Detailed operational evidence remains in the ignored run bundle and repository
  history. It is consulted only when a current contradiction needs provenance.

## Execution Packages

Execute strictly in order. One controller integrates and verifies each package;
pause after each package for independent review and adjudication.

### Pre–Package 5 — Review-adjudicated baseline remediation

**Role:** controller-local implementation followed by a fresh `reviewer`.

The 2026-07-14 suggestion adjudication proved narrow contradictions in completed
shell, onboarding, setup, workflow, and verification owners. Correct those
defects before Package 5 without reopening product scope: harden protocol and
smoke failure behavior; serialize fullscreen reconciliation; make shell focus
and modal semantics consistent; prevent stale PIN/setup/custom-channel async
state; align Plex busy projection; consolidate staged action vocabulary; and
strengthen public-seam asset/markup proof. Workflow/authority corrections remain
a separate commit from production changes.

No new dependency, contract, IPC method, persistence schema, Plex transport,
native/helper behavior, copied upstream source, or Package 5 Guide behavior is
approved. Existing large owners retain their current cohesive responsibilities;
this gate removes failure modes inside those state machines rather than adding
new responsibilities or extracting forwarding layers. Run focused owner tests,
`npm run verify:docs`, and the full source closeout gates, then obtain a fresh
read-only adversarial review before returning the current unit to Package 5.

Implementation checkpoints:

- `fd35af8` aligns workflow authority, role mapping, architectural truth, and
  review dispositions.
- `1c83d6d` hardens shell lifecycle, protocol failure mapping, fullscreen
  serialization, global focus, toast timing, and modal error behavior.
- `c4b7b89` hardens Plex busy, dismissal, and profile-PIN generation ownership.
- `21ca2d8` stabilizes setup/custom-channel async state, focus, action
  vocabulary, semantic tests, and renderer asset-copy proof.
- `544d9a5` removes the obsolete parallel setup-stage projection so the staged
  workflow is the sole presentation and lifecycle owner.
- `76bd98d` closes the repository-wide lint findings exposed by the final gate.
- Fresh configured `reviewer` review found one material cross-owner fullscreen
  transport defect and one semantic-proof quality defect. Both were accepted.
- `5636cba` centralizes the real fullscreen bridge behind one serialized,
  reconciling renderer coordinator, removes the dead third transport path, adds
  cross-owner race proof, and replaces serialized-markup assertions with
  owner-scoped mounted Electron DOM checks.

Focused owner tests, typecheck, architecture/lint/maintainability, build,
Electron smoke, documentation and redaction checks, and the repository-wide
`npm run verify` gate pass at closeout. The targeted read-only re-review of
`7d64ee1..5636cba` was clean with no material or actionable findings.

### Package 5 — Scheduler-backed Guide parity

**Role:** `worker` only.

Use existing Guide presentation and persisted channels. Prove loading, ready,
actionable no-channel, no-program, failure, stale result, refresh, time window,
current marker, clipped cells, detail, tune/back, channel/program navigation,
focus restoration, and cleanup at both target sizes. No production fixture
fallback and no new scheduler/channel/main/preload contract is approved.

Focused tests:

`node --import tsx --test src/__tests__/main/guideRuntime.test.ts src/__tests__/renderer/epg.test.ts src/__tests__/renderer/epgStateUpdate.test.ts src/__tests__/renderer/epg/guideDom.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/workflow.test.ts`

Architecture dispositions:

- **Owner:** `src/renderer/epg.ts`. **Existing responsibility:** renderer-safe
  Guide state, selection/window navigation, time-grid projection, and their
  shared view-model vocabulary. **New behavior:** project existing runtime
  loading/ready/empty/error data without changing that state owner. **Decision:
  cohesive growth.** The changed behavior shares the same selection, time-window,
  and projection invariants; adding another production owner would split one
  state machine. Retire product use of deterministic defaults where Package 5
  reaches it, but keep test data local rather than creating a fixture service.
- **Owner:** `src/renderer/styles/guide-epg.css`. **Existing responsibility:**
  Guide shell, state panels, time grid, channel/program cells, detail, focus,
  density, and viewport treatment. **New behavior:** upstream-shaped runtime
  states and both target viewport layouts. **Decision: cohesive growth.** The
  selectors share the Guide layout variables and one screen lifecycle; no
  independent component family or consumer justifies another stylesheet.

`index.ts` remains composition wiring only and requires a fresh `reviewer`
architecture/YAGNI pass if touched. Stop if another production file, a new
renderer-safe contract, or a new scheduler/channel/main/preload behavior is
required.

### Package 6 — Runtime player and overlay state machine

**Role:** `worker` only.

Remove production fixture presentation. Derive safe channel/program/overlay
state from existing player plus Guide/channel runtime state. Idle shows the
native presentation surface with no default route card or overlay stack. Enforce
the reviewed precedence/actions for OSD, now playing, mini guide, options, badge,
number input, transition/loading/error, fullscreen, tune, and Back. Real events
own transients and cleanup; modal owners contain and restore focus.

Focused tests:

`node --import tsx --test src/__tests__/renderer/overlays.test.ts src/__tests__/renderer/desktopInput.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/rendererRuntimeOwners.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/workflow.test.ts`

### Package 7 — Player overlay visual surfaces

**Role:** `worker` only.

After Package 6 freezes behavior, move distinct overlay families to focused
DOM/CSS/view-model owners where they own meaningful behavior. Adapt upstream
hierarchy/density for supported OSD, now playing, mini guide, options, badge,
number entry, and transition states. Omit unsupported controls explicitly; do
not synthesize artwork or actions.

Focused tests:

`node --import tsx --test src/__tests__/renderer/overlays.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/rendererActionRegistration.test.ts src/__tests__/renderer/rendererRuntimeOwners.test.ts`

### Package 8 — Integrated proof and closeout

**Role:** `worker` for bounded evidence/docs; route defects back to their owner.

Recapture every required state at both viewports and player/overlay states in
fullscreen. Complete the interaction matrix with no unknown cells, scan the
local proof bundle for private material, run all final gates, obtain integrated
independent review, and correct roadmap/current-state/renderer/security/proof/
parity/divergence/import-ledger docs. Archive this plan and unblock a fresh RD-27
plan only after observed proof is complete.

## Verification Commands

**Verification classification:** broader integration/manual proof required

For every source package run its exact focused test command, then:

- `npm run typecheck`
- `npm run verify:architecture`
- `npm run verify:maintainability`
- `npm run verify:redaction`
- `npm run smoke:electron`
- `npm run verify`
- `git diff --check`

Package 8 also runs `npm run test:contracts`. Every affected surface needs
sanitized exact-viewport captures, keyboard/gamepad-like/pointer proof,
Back and focus restoration, relevant reduced-motion/forced-colors proof, and a
read-only adversarial review. Re-review only after a material finding or material
review-surface change.

## Acceptance Criteria

- No permanent dashboard chrome, route-card player shell, production fixture
  data, or simultaneous default overlays reappears.
- Approved settings survive relaunch through strict main-owned versioned atomic
  persistence; stale/failure paths cannot lose newer state or leak details.
- Guide uses real persisted-channel schedules and honest actionable empty/error
  states.
- Player and overlay state is runtime-backed, mutually coherent, focus-safe, and
  cleaned up; no native or secret material crosses the renderer boundary.
- Setup/onboarding/shell behavior and the completed visual correction remain
  frozen unless reviewed evidence proves a contradiction.
- Every upstream family has an evidenced Desktop adaptation, divergence, or
  defer disposition; unsupported features do not become fake controls.
- Architecture owners remain cohesive or transfer a distinct present-day
  responsibility; all hotspot review triggers are satisfied.
- Exact captures, interaction evidence, full verification, package reviews, and
  final integrated review are complete and tracked claims match the app.
- RD-27 remains blocked until every criterion passes.

## Replan Triggers

Stop and return to the controller when:

- scoped Desktop/upstream sources or ownership changed materially;
- a frozen target behavior is missing, contradictory, or unimplementable;
- an exact viewport/state cannot be reached or sanitized honestly;
- existing safe APIs cannot represent indispensable Guide/player/Plex/channel
  state;
- work requires a dependency, CSP/protocol expansion, raw artwork transport,
  another settings family/migration, native/helper behavior, packaging, release,
  or a new public media contract;
- an unlisted owner or distinct responsibility must change;
- a required proof/review failure cannot be fixed inside the current seam.

## Rollback Notes

Keep one reviewed conventional commit per package and never mix unrelated work.
Roll back a failing source package as a unit instead of adding compatibility
chrome, fixture fallback, broad adapters, or partial alternate paths. Preserve
truthful authority corrections and leave this plan active with the exact blocker
when closeout cannot proceed.

## Commit Checkpoints

1. `feat(renderer): complete scheduler-backed guide parity`
2. `feat(renderer): bind player overlays to runtime state`
3. `feat(renderer): complete webos overlay presentation parity`
4. `docs: close complete webos ui parity proof`

Exact model and reasoning-effort settings come only from the selected role's
`config_file` mapping in `.codex/config.toml` and its corresponding
`.codex/<config_file>` TOML. The controller uses
`lineup-desktop-feature-quality-loop`; Packages 5–8 default to `worker`; each
package uses a fresh `reviewer` when its review gate is met.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop
TASK: Execute Package 5 — Scheduler-backed Guide parity
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-07-10-complete-webos-ui-parity-reopen-plan.md
BLOCKERS: none for Package 5; RD-27 remains blocked pending Packages 5–8.
MESSAGE: Load the active plan, run the bounded freshness audit, then execute only
Package 5 through the Tier 3 quality loop. Preserve the Packages 0–4 and closed
pre–Package 5 remediation baseline. Give the worker exact files, invariants,
proof, and stop conditions; pause after clean verification and independent
review.
