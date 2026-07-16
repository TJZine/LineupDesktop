# Complete WebOS UI Parity Reopen Plan

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3
**Current execution unit:** Package 8 — Integrated proof and closeout. Package
7 renderer implementation, exact-viewport/media/fullscreen proof, review
remediation, fresh independent re-review, and final verification are complete.
Package 6 production correction, focused coverage, harness calibration,
implementation review, and the reviewed platform-proof exception remain
complete. Its three physical-click rows are still a fresh, mandatory RD-27
Windows manual audit; no completed 29-row Mac manifest or platform-complete
claim exists. Package 8 may close renderer parity and local automated proof
only while retaining that binding Windows-proof nonclaim. Package 5 —
Scheduler-backed Guide parity remains closed with full verification,
exact-viewport evidence, and clean read-only adversarial re-review. The
source-proven pre–Package 5 remediation and the 2026-07-15 suggestion-reviewed
correction remain closed. Packages 0–4 remain closed at their corrected
checkpoints; RD-27 remains blocked until Package 8 closes and a fresh RD-27
plan owns the deferred Windows audit.

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
`src/main/smokeGuideAssertions.ts`,
`src/renderer/guidePresentation.ts`,
`src/renderer/guidePresentationPolling.ts`,
`src/renderer/guideTuneController.ts`,
`src/renderer/epg/guideDom.ts`, `src/renderer/focusDom.ts`,
`src/renderer/routeDom.ts`, `src/renderer/workflow.ts`,
`src/renderer/staticDom.ts`, `src/renderer/rendererActionRegistration.ts`,
`src/renderer/shell/navigationLifecycle.ts`,
`src/renderer/index.ts` for composition wiring only,
`src/renderer/styles/guide-epg.css`, the Package 5 tests named below, and
ignored Package 5 plan/evidence artifacts under
`docs/runs/complete-webos-ui-parity-reopen/`. The added static-markup and
delegated-action owners are the source-proven correction needed to remove the
reachable proxy Guide buttons and make rendered program/state controls own
pointer/OK behavior. The main-owned smoke assertion is proof code only: update
its stale six-proxy-button assertion to inspect the dynamic ready or authorized
empty/error Guide controls; it must not change product main/runtime behavior.
Package 6 may change only `src/renderer/navigation.ts`,
`src/renderer/desktopInput.ts`, `src/renderer/shell/navigationLifecycle.ts`,
`src/renderer/overlays.ts`, `src/renderer/overlayViewModels.ts`,
`src/renderer/overlayViewModelHelpers.ts`,
`src/renderer/presentationFixtures.ts` (delete),
`src/renderer/playerOverlayPresentation.ts` (new),
`src/renderer/playerOverlayController.ts` (new),
`src/renderer/playerOverlayActions.ts` (retire),
`src/renderer/playerBridgeSubscription.ts`,
`src/renderer/guidePresentationPolling.ts`, `src/renderer/staticDom.ts`,
`src/renderer/domBindings.ts`, `src/renderer/routeDom.ts`,
`src/renderer/focusDom.ts`, `src/renderer/rendererActionRegistration.ts`,
`src/renderer/workflow.ts`, `src/renderer/index.ts` for composition wiring only,
and `src/renderer/styles/player-overlays.css` for behavior-essential visibility,
focus, reduced-motion, and forced-colors rules only. Proof-only smoke changes
are limited to `src/main/smokeAssertions.ts` and
`src/main/smokeFullscreenAssertions.ts`; they must replace stale fixture/quick-
action assertions and cannot change main/runtime behavior. Tests are limited to
the Package 6 files named below. The focused Package 6 focus-custody correction
may change only `src/renderer/staticDom.ts`, `src/renderer/routeDom.ts`,
`src/renderer/focusDom.ts`, `src/renderer/rendererActionRegistration.ts`, and
the four corresponding focused renderer tests named in its correction section.
Its local packet and refreshed semantic/fullscreen proof remain ignored under
`docs/runs/complete-webos-ui-parity-reopen/`. Local execution/evidence
artifacts stay under that ignored bundle. Package 7 may
change only `src/renderer/staticDom.ts`, `src/renderer/routeDom.ts`, new
`src/renderer/playerOverlayDom.ts`, `src/renderer/styles.css`,
`src/renderer/styles/player-overlays.css`, new
`src/renderer/styles/player-overlay-information.css`, new
`src/renderer/styles/player-overlay-menus.css`,
`src/renderer/styles/shell.css`,
`src/renderer/styles/responsive-accessibility.css`,
`docs/architecture/import-ledger.md`, and the five focused renderer tests named
in the Package 7 section below. Local Package 7 execution/capture evidence stays
under the ignored `docs/runs/complete-webos-ui-parity-reopen/` bundle. Package
8 changes evidence and tracked memory unless it routes a defect back to its
owning package.

The closed 2026-07-15 correction was the reviewed source-proven exception to
the Package 5 file boundary. Its exact production and workflow checkpoints are
recorded below; it does not widen Package 5 scope.

## Files Out Of Scope

- native/helper, packaging, signing, updater, installer, and release files
- dependencies and lockfiles
- credential/channel persistence and token-bearing Plex transport
- new scheduler, channel, Plex, player, or media contracts unless a reviewed
  replan proves an existing renderer-safe seam is insufficient
- unrelated renderer CSS or completed Packages 0–4 owners outside the recorded
  source-proven correction checkpoints
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
- The 2026-07-15 suggestion-reviewed correction synchronized fullscreen state
  before conflict-rebased Settings persistence, hardened public-seam and
  cleanup tests, and corrected workflow/provenance truth in commits `a2f6bb3`
  and `6115366` plus the adjacent parity-doc checkpoint.
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

### Post–Package 4 — 2026-07-15 suggestion-reviewed correction

**Role:** controller-local implementation followed by read-only feature and
workflow-harness review.

The accepted review findings proved a narrow launch-mode conflict-rebase defect,
test cleanup/public-contract weaknesses, stale skill-policy duplication, weak
verifier self-proof, and provenance/parity vocabulary drift. Commit `a2f6bb3`
synchronizes the rebased native launch mode before retrying Settings persistence
and hardens the focused Settings/Plex tests. Commit `6115366` aligns project
skills with tracked authority while preserving unique boundary checklists,
strengthens structural launcher and active-plan validation, gives verifier tests
an independent canon, and teaches CodeRabbit to distinguish launcher wrappers
from substantive project boundary/workflow skills. The adjacent parity-doc
checkpoint separates reference-only RD20-M09 from copied/adapted RD20-M12 and
uses the declared blocked/evidence/blocker vocabularies.

No dependency, contract, IPC method, persistence schema, Plex transport,
native/helper behavior, copied source, or Package 5 Guide behavior changed.
Focused owner tests, typecheck, harness/docs verification, redaction, diff
checks, and the repository-wide `npm run verify` gate passed before commit
closeout. Read-only feature and workflow-harness review found no remaining
blocker.

### Package 5 — Scheduler-backed Guide parity

**Role:** `worker` only. `worker_sol_low` and `worker_luna` are ineligible
because this unit changes a named composition root and coordinates dynamic
focus, stale async state, and tune failure behavior across renderer owners.

Use existing Guide presentation and persisted channels. The reviewed-ready
execution packet is
`docs/runs/complete-webos-ui-parity-reopen/package-5-execution-packet.md`.
It supersedes only the contradicted Guide rows in the ignored Package 0
focus/interaction matrix until Package 5 regenerates those rows and proof.

The frozen behavior is: loading has Back; zero channels has Setup and Back;
channels with no visible programs has Refresh, Setup, and Back; failure has
Retry and Back; ready renders the actual visible cells as the focus graph and
focused detail owner. Every cell is focusable and navigable, but only a cell
whose program contains the presentation `nowMs` is playable. OK/pointer on a
current cell tunes its channel through the existing channel-only bridge;
past/future activation remains focused detail and dispatches no tune. Tune
failure remains in ready Guide with sanitized inline failure and exact cell
focus; it must not replace the whole schedule with the Guide-load error state.
Back returns to Player and restores the recorded Player invoker when it still
exists (`player-guide` only when that button invoked Guide); accepted tune
returns to an unfocused Player. Loading/empty/error owners never register or
name program-cell focus. PageUp/PageDown remain unmapped and ignored.

Remove production use and ownership of deterministic Guide fixtures, retire the
reachable proxy Guide navigation/Watch controls, distinguish no-channel from
no-program state, keep stale request rejection/poll cleanup, and prove loading,
ready, both empty states, failure/retry, refresh, time-window refresh, current
marker, clipped cells, detail, current-only tune/back, dynamic channel/program
navigation, invoker-aware focus restoration, and cleanup at both target sizes.
No new scheduler/channel/main/preload contract is approved.

Focused tests:

`node --import tsx --test src/__tests__/main/guideRuntime.test.ts src/__tests__/renderer/epg.test.ts src/__tests__/renderer/epgStateUpdate.test.ts src/__tests__/renderer/epg/guideDom.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/workflow.test.ts src/__tests__/renderer/rendererRuntimeOwners.test.ts src/__tests__/renderer/guideTuneController.test.ts src/__tests__/renderer/rendererActionRegistration.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/navigationLifecycle.test.ts`

Architecture dispositions:

- **Owner:** `src/renderer/epg.ts`. **Existing responsibility:** renderer-safe
  Guide state, selection/window navigation, time-grid projection, and their
  shared view-model vocabulary. **New behavior:** project existing runtime
  loading/ready/empty/error data without changing that state owner. **Decision:
  cohesive growth.** The changed behavior shares the same selection, time-window,
  and projection invariants; adding another production owner would split one
  state machine. Retire product use of deterministic defaults where Package 5
  reaches it, and move deterministic schedules to test-local data rather than
  creating a production fixture service.
- **Owner:** `src/renderer/styles/guide-epg.css`. **Existing responsibility:**
  Guide shell, state panels, time grid, channel/program cells, detail, focus,
  density, and viewport treatment. **New behavior:** upstream-shaped runtime
  states and both target viewport layouts. **Decision: cohesive growth.** The
  selectors share the Guide layout variables and one screen lifecycle; no
  independent component family or consumer justifies another stylesheet.
- **Owner:** `src/renderer/guidePresentationPolling.ts`. **Existing
  responsibility:** route-gated Guide presentation refresh, interval ownership,
  stale result rejection, and cleanup. **New behavior:** explicit loading/retry/
  refresh generations for the corrected Guide states. **Decision: cohesive
  growth.** Presentation polling remains one async lifecycle and does not absorb
  player tune custody.
- **Owner:** `src/renderer/guideTuneController.ts`. **Existing responsibility:**
  new focused renderer-safe Guide tune lifecycle owner extracted from the
  current tune policy embedded in `index.ts`. **New behavior:** validate a
  current cell, suppress duplicate tune, invalidate stale completion on Guide
  close/unload, preserve ready state on sanitized failure, and report accepted
  success through injected callbacks. **Decision: extraction required.** Tune
  request custody is a distinct present async lifecycle; leaving it in the
  named composition root would violate the composition-only invariant, while
  merging it into presentation polling would couple different bridge
  operations and failure states. Its public seam is proved by
  `guideTuneController.test.ts`.
- **Owner:** `src/renderer/shell/navigationLifecycle.ts`. **Existing
  responsibility:** renderer keyboard/gamepad dispatch, generic focus movement,
  route focus memory, Back, and cleanup. **New behavior:** while Guide is active,
  give an injected Guide directional handler first refusal before generic focus
  movement. **Decision: cohesive growth.** This owner already arbitrates input;
  it must expose the blocked edge direction without learning schedule/window
  policy. `epg.ts` decides adjacent-cell versus window intent, `index.ts` wires
  the callback, and `navigationLifecycle.test.ts` proves Guide interception plus
  unchanged generic fallback.
- **Owner:** `src/main/smokeGuideAssertions.ts`. **Existing responsibility:**
  production-build Electron smoke assertions for safe reachable Guide content.
  **New behavior:** replace the obsolete exact-six `[data-epg-action]` proxy
  count with semantic proof of the dynamic program controls or the authorized
  loading/empty/error action set. **Decision: cohesive proof update.** This file
  remains assertion source only and adds no product main-process behavior or
  renderer privilege.

`index.ts` remains composition wiring only and requires a fresh `reviewer`
architecture/YAGNI pass if touched. Stop if another production file, a new
renderer-safe contract, or a new scheduler/channel/main/preload behavior is
required.

Package 5 closeout:

- The configured `worker` (`.codex/agents/worker.toml`, `gpt-5.6-sol`, medium
  reasoning) implemented the bounded source and proof surface. No dependency,
  contract, IPC, persistence, native/helper, packaging, or fixture fallback was
  added.
- Guide presentation now comes from the existing scheduler-backed runtime and
  exposes distinct loading, no-channel, no-program, failure, and ready states.
  Dynamic program cells own schedule-aware focus and pointer behavior; only the
  current half-open program interval may tune through the existing channel-only
  bridge.
- Tune duplicate suppression, stale completion rejection, pending-state
  projection, inline sanitized failure, accepted unfocused Player return,
  invoker-aware Back restoration, polling cleanup, and exact one-slot window
  intent are covered at their owning seams.
- The configured fresh `reviewer` (`.codex/agents/reviewer.toml`,
  `gpt-5.6-sol`, high reasoning) accepted two implementation findings: bounded
  schedule responses incorrectly clamped window-edge intent, and presentation
  replacement could separate program focus from normalized selection. The
  worker corrected both in the existing EPG/composition owners; targeted
  re-review found no remaining blocker and reconfirmed `index.ts` as acceptable
  composition-only coordination.
- The exact 11-file focused suite passes 109/109. Typecheck, architecture/lint/
  maintainability, redaction, documentation, full repository verification, and
  diff checks pass. Electron smoke passed on immediate rerun after an observed
  unrelated fullscreen-state timing race; Package 5 does not change the
  fullscreen owner.
- The ignored sanitized proof bundle contains 12/12 semantic captures for six
  Guide states at exact CSS viewports `1280x720` and `1920x1080`, including
  reduced-motion and forced-colors checks, with no semantic failure. Package 5
  changes no copied or adapted upstream source, so the import ledger remains
  unchanged.

### Package 6 — Runtime player and overlay state machine

**Role:** `worker` only.

**Status:** production implementation and focused correction are complete and
reviewed under the Package 6 platform-proof exception. Operator-assisted
fullscreen platform proof remains the mandatory three-row RD-27 Windows audit.

**Architecture boundary:** renderer-only. Existing
`window.lineupDesktop.player`, `window.lineupDesktop.guide`, and
`window.lineupDesktop.channelSetup` APIs are sufficient. No new contract, IPC,
preload, main, native/helper, persistence, protocol, dependency, or player-
command surface is approved. Stop and replan if implementation cannot be
completed through those safe bridges.

Delete the production dependency on `presentationFixtures.ts`; keep test data in
tests. `playerOverlayPresentation.ts` becomes the pure translation boundary from
the latest safe player snapshot, channel-status summary, and scheduler-backed
Guide presentation into honest player/overlay view models. It must omit missing
data instead of inventing channels, tracks, programs, descriptions, badges, or
artwork. `overlays.ts` remains the deterministic state/precedence reducer.
`playerOverlayController.ts` owns timers, bridge effects, async generations,
route/snapshot reconciliation, focus-return intents, and cleanup; retire the
module-global timeout/effect ownership in `playerOverlayActions.ts`.
`playerBridgeSubscription.ts` owns event projection and unsubscribe cleanup.
Only `state.changed` authoritatively replaces the snapshot or creates terminal
Player error UI. `time.updated`, `buffer.updated`, `media.loaded`,
`tracks.changed`, `track.selection.changed`, `quality.changed`, and `ended`
apply only when their non-null request id equals the current snapshot request.
`command.settled` is instead correlated to the controller-issued pending command
request/generation, never snapshot-request filtered; a matching failure delegates
to the command's frozen failure owner (options inline for track selection,
diagnostic-only for Space), while a matching success does not fabricate snapshot
state. `warning`, null-request `error`, and unmatched request-scoped
`error` are sanitized diagnostics only. A matching request-scoped `error` may
fail its pending command inline but cannot create terminal Player error without
`state.changed`. Late initial `getSnapshot()` applies only if the subscription
is still active and no newer event/snapshot generation has won; post-unsubscribe
callbacks and all stale events are inert.

`guidePresentationPolling.ts` shares its existing scheduler presentation across
Guide and Player; Player refresh failure retains the last valid presentation or
omits schedule-dependent overlays and must not take over the route with Guide
loading/error UI.

The Player route has no default card, quick-action dashboard, or visible default
overlay. Baseline Player-status presentation is exhaustive:

| `PlayerStatus` | Presentation without an active manual transition |
| --- | --- |
| `idle` | native presentation only; normal overlays closed |
| `loading` | generic semantic loading owner |
| `ready` | native presentation only |
| `buffering` | generic semantic loading owner |
| `playing` | native presentation; eligible requested overlays may open |
| `paused` | native presentation; eligible requested overlays may open |
| `seeking` | an already-open OSD may remain; otherwise generic loading |
| `stalled` | generic semantic loading owner |
| `ended` | native presentation only; normal overlays closed |
| `error` | safe terminal Player error; normal overlays closed |
| `destroyed` | safe unavailable Player error; normal overlays closed and no Retry |

Retry is rendered only for `status === 'error'`,
`snapshot.lastError.retryable === true`, and a renderer-safe current or last
tune channel id. Guide is rendered only when real Guide/channel state can open
it. A later authoritative non-error `state.changed` closes the error owner and
projects that status. Validation failure, track membership failure, bridge
reject/throw, `command.settled` failure, warning, or standalone error event does
not enter terminal Player error.

Freeze these input/state rules:

- With no active overlay and status `ready`, `playing`, or `paused`,
  Down or OK requests OSD; pointer activation of the native presentation invokes
  that same action. Space dispatches play/pause from the current snapshot without
  inventing a toggle contract. Audio is eligible only when at least one available
  audio track differs from the selected id. Subtitles are eligible when an
  available subtitle exists or a subtitle is selected; its options always include
  Off, which is the only eligible row when disabling a selected-but-no-longer-
  listed subtitle. With zero eligible controls, the OSD request is consumed but
  refuses open, remains focusless/native, and starts no timer. With exactly one,
  it opens and focuses that control; with two, horizontal focus connects them.
  It auto-hides after 3,000 ms while playing and remains while paused/seeking.
  Loading, buffering, stalled, idle, error, destroyed, ended, route leave, or a
  higher owner closes it. Back closes an open OSD; with refused/closed OSD Back
  follows normal route behavior. Pointer and keyboard obey the identical zero/
  one/two-control eligibility and timer rules.
- Space uses status as the intent selector and `snapshot.playing` only as a
  consistency gate: `playing` plus `playing === true` dispatches existing
  `player.pause`; `ready` or `paused` plus `playing === false` dispatches
  existing `player.play`. Inconsistent pairs and `idle`, `loading`, `buffering`,
  `seeking`, `stalled`, `ended`, `error`, or `destroyed` consume/ignore Space and
  dispatch nothing. Only one Space command generation may be pending; duplicates
  are ignored. Matching `command.settled` success ends it, while rejected
  dispatch, matching settled failure, throw, or an inconsistent authoritative
  update records a sanitized renderer diagnostic and shows no overlay/inline
  failure. Only a later authoritative terminal `state.changed` owns Player error
  UI. Route leave, superseding playback request id, and dispose invalidate the
  pending Space generation; late result/events cannot mutate Player UI.
- `i` opens persistent, focusless now-playing only when real current-program
  data exists. Shell blocking owners and playback options refuse Info. Otherwise
  Info closes/replaces a lower mini-guide, OSD, or number owner rather than
  suspending it; Back closes now-playing to native presentation and does not
  restore the replaced owner. This is an evidenced Desktop divergence from
  upstream, which refuses Info while any modal is open; Package 8 must record it
  in durable divergence memory. Channel badge is a passive derived companion to
  visible OSD or now-playing when a real current channel exists; it has no timer
  or focus and is hidden by Guide or transition.
- Up opens mini-guide only with real channels. It renders exactly five circular
  rows centered on selection; Up/Down moves one, PageUp/PageDown jumps five,
  Right opens full Guide, OK tunes, and Back closes. Its 8,000 ms inactivity
  timer resets on movement/page and is cleared on every exit/cleanup.
- Digit input accepts at most three digits from the real channel catalog. It
  commits after 2,000 ms inactivity or immediately at three digits. Exact match
  tunes; invalid input remains as a safe error for 2,000 ms; completed input
  hides after 650 ms. There are no production digit, Tune, or Clear proxy
  buttons.
- Every tune invoker arms transition immediately and delays its visible channel-
  specific spinner/prefix for 175 ms. Same-target duplicate activation is
  ignored. A different target supersedes the current tune generation, moves the
  pending target, rearms both delay and presentation, and makes the older result
  inert. Bridge rejection/throw ends only that current transition generation;
  bridge success alone is not playback-ready. After arm, authoritative
  `state.changed` `loading`, `buffering`, `seeking`, or `stalled` retains the
  transition; `idle`, `ready`, `playing`, `paused`, or `ended` ends it to the
  baseline row above; `error` or `destroyed` ends it to terminal error. Route
  leave/rearm/cleanup also ends it. Upstream
  `src/modules/ui/channel-transition/ChannelTransitionCoordinator.ts` at the
  pinned `4bdb0e1b3370e7893a582ec80226557727832d0b` (unchanged in the scoped
  freshness read at `a1a7ea7dcb1cfc8aee7cfcf88cf5a1dac718bf30`) has only the
  175 ms show timer and no maximum fallback. Desktop deliberately adds `ready`,
  pre-visible `idle`, and `destroyed` terminals to prevent stranded activity
  and adds no arbitrary timeout while an authoritative load-like status remains
  active.
- Mini-guide tune keeps the guide visible with only the target row busy. On
  current-generation bridge success it closes mini-guide and lets transition
  own progress; failure keeps mini-guide open with safe inline error and exact
  row focus. Movement remains available; OK on a different row supersedes and
  moves busy state, while OK on the same row is ignored. Number commit is
  focusless and locks further digits while pending; success shows completed
  number state for 650 ms before exposing any still-active transition, while
  failure shows safe invalid/failure state for 2,000 ms then returns native.
  Error Retry keeps the error owner and exact Retry focus busy while pending;
  bridge success or an authoritative load-like `state.changed` closes it in
  favor of transition, bridge failure keeps it focused with safe error, and a
  terminal authoritative state ends transition back at Player error.
- Current-generation tune bridge success triggers both existing reconciliation
  owners with no Guide loading takeover: guarded
  `channelRuntimeController.loadStatus()` through
  `window.lineupDesktop.channelSetup.getStatus()` and guarded
  `guidePresentationPolling.refresh('player-tune-success', { showLoading: false
  })` through `window.lineupDesktop.guide.getPresentation()`. The controller
  rechecks the tune generation immediately before invoking each existing refresh
  callback; the existing status and presentation owners retain their own latest-
  request/route apply policy. A same-generation refresh failure records only its
  existing sanitized/last-valid-data policy. A rejected, thrown, superseded,
  route-stale, or disposed tune result never starts reconciliation or directly
  publishes channel/Guide data. This adds no new owner, bridge, or public API.
- Playback options contain only real available audio tracks and subtitle Off
  plus real available subtitle tracks. Selection validates current snapshot
  request/membership, is single-flight, and exposes a busy row. Validation/
  membership failure, IPC reject/throw, rejected dispatch, or matching
  `command.settled` failure keeps options open with safe inline error and exact
  row focus. Matching `command.settled` success is the accepted completion
  signal; dispatch `accepted === false` is handled locally as failure. A same-
  playback-request `track.selection.changed` or non-terminal `state.changed`
  updates the view but does not invalidate or complete the pending command,
  regardless of arriving before settlement. Only playback request-id
  replacement, target membership loss, options/route cleanup, or authoritative
  terminal status invalidates it. Membership loss keeps options with safe inline
  error and the first current row when that family remains eligible; otherwise
  it closes through the return chain. On accepted completion or Back, recompute
  OSD eligibility: restore the exact invoking control if present, otherwise the
  remaining audio/subtitle control, otherwise close OSD and programmatically
  focus the native Player presentation surface (`tabindex="-1"`, not a roving or
  tab-stop control). This is the exact fallback when subtitle Off removes the
  subtitle OSD control. An authoritative `state.changed` to `error`/`destroyed`
  instead closes options and OSD and shows Player error, with no invoker
  restoration. Remove fixture volume/mute/cycle, sleep-timer, and fabricated
  track controls.
- Precedence is shell blocking/inline errors and exit confirmation, terminal
  Player error, playback options, now-playing, mini-guide, OSD, number entry,
  transition, generic loading, then native surface. Only one modal owner is
  active. Options alone suspends its invoking OSD for exact return; now-playing
  replaces lower owners; other higher owners close lower owners. Back closes the
  top owner before route navigation and restores the exact valid invoker when
  that owner defines one, otherwise the deterministic Player fallback. Hidden
  owners are inert and absent from focus graphs.
- Guide/Settings shortcuts close Player owners, clear timers, invalidate async
  generations, and preserve the existing route-return contract. Fullscreen uses
  the existing coordinator only and never replaces the native presentation or
  invents window/player state.

`navigationLifecycle.ts` arbitrates Player first refusal before generic route
navigation. `desktopInput.ts`/`navigation.ts` add only renderer-local Info,
digits, and page-button vocabulary. `staticDom.ts`, `domBindings.ts`,
`routeDom.ts`, `focusDom.ts`, and `rendererActionRegistration.ts` expose only
the semantic owners, delegated actions, roving focus graphs, and pointer/OK
equivalence described above. Package 6 may add only behavior-essential CSS; all
upstream hierarchy, density, spacing, typography, motion polish, and final
visual parity remain Package 7.

File-shape dispositions are frozen: the approximately 749-line
`src/renderer/index.ts` remains a named composition root and may receive wiring
only, so its diff requires fresh architecture/YAGNI review; the approximately
717-line overlay stylesheet remains the cohesive overlay-state stylesheet and
receives no Package 7 visual work; `workflow.ts` retains route/presentation
projection but receives no overlay state machine; the new pure presentation and
effectful controller files split distinct current responsibilities rather than
forwarding. No touched owner may cross 800 lines without stop/replan.

Worker eligibility is `worker` only. Low-cost worker roles are ineligible
because this slice coordinates the named composition root, multiple timer and
async generations, renderer bridge events, route arbitration, and focus
restoration. After implementation and controller verification, request a fresh
independent `reviewer`; include explicit architecture/YAGNI review of
`index.ts`, failure/stale/cleanup review, and Package 7 boundary review.

No upstream source is planned to be copied or adapted: the inspected upstream
overlay families are reference-only, so the import ledger remains unchanged.
If a worker copies/adapts source, stop, record the exact upstream commit/path and
Desktop destination in the import ledger, and re-review scope. The ignored
execution packet is
`docs/runs/complete-webos-ui-parity-reopen/package-6-execution-packet.md`.

Focused tests:

`node --import tsx --test src/__tests__/renderer/overlays.test.ts src/__tests__/renderer/playerOverlayPresentation.test.ts src/__tests__/renderer/playerOverlayController.test.ts src/__tests__/renderer/desktopInput.test.ts src/__tests__/renderer/navigationLifecycle.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/rendererActionRegistration.test.ts src/__tests__/renderer/rendererRuntimeOwners.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/workflow.test.ts`

The focused proof must cover all eleven `PlayerStatus` baseline and active-
transition branches; ready/idle/destroyed transition termination; zero/one/two-
control OSD and subtitle-Off eligibility; Info refusal/replacement divergence;
each mini-guide/number/Retry tune pending, same-target, different-target,
accepted, rejected, thrown, authoritative-error, and stale generation; options
validation/membership/IPC/settled/authoritative-terminal splits; current-request
incremental events before/after matching track settlement, playback request-id
replacement, membership loss, subtitle-Off invoker removal and native-surface
fallback; every Space status/playing pair, intent, duplicate, failure, route/
request/dispose invalidation; tune-success dual refresh, refresh failure, and
stale/failed tune-result no-refresh guards; command-generation settlement; diagnostic-
only warning/null-request error; late initialization/post-unsubscribe inertness; every
precedence edge; exact timer boundaries with fake clocks; route/dispose cleanup;
all focus-entry/return paths; keyboard/gamepad-like/pointer equivalence; and
Guide/Settings/fullscreen continuity. Then run the repository commands below,
including `npm run build:electron`, followed by sanitized semantic captures at
`1280x720` and `1920x1080` for idle, loading, transition, error/retry, OSD,
now-playing, mini-guide, number-valid/invalid, and playback-options behavior.
These captures prove reachability, visibility, semantics, and focus only;
Package 7 owns visual-parity approval and recapture. Exact transient states may
be reached only through an ignored harness/test-only injection at existing
renderer-safe public seams; no production fixture/injection seam is allowed,
and the two main smoke files remain assertion-only.

Package 6 closeout:

- The configured `worker` implemented the bounded renderer behavior and proof
  surface. Production presentation fixtures and module-global overlay effect
  ownership are retired in favor of the pure presentation boundary and the
  effectful controller, while the existing renderer-safe player, Guide, and
  channel-setup bridges remain the only runtime seams.
- The configured independent `reviewer` raised material timer, event-bubbling,
  terminal-action, pending-command, transition, error-projection, polling, and
  proof findings. The worker corrected them inside the approved Package 6
  boundary, and targeted read-only re-review found no remaining blocker,
  including no architecture/YAGNI or Package 7 boundary finding.
- Controller-observed verification passes the frozen focused suite at 118/118
  and full `npm run verify` at 820/820 source-and-contract tests plus 135/135
  harness-and-doc tests. Fresh Electron smoke, typecheck, architecture, lint,
  maintainability, documentation, redaction, and diff checks also pass.
- The regenerated ignored sanitized proof manifest records 20/20 semantic
  captures and 240/240 assertions across exact CSS viewports `1280x720` and
  `1920x1080`. Final observed line counts are 782 for the composition-only
  `src/renderer/index.ts`, 664 for
  `src/renderer/playerOverlayController.ts`, and 735 for the cohesive
  `src/renderer/styles/player-overlays.css`; all remain below the 800-line
  stop/replan threshold.
- Package 6 adds no contract, IPC, preload, main runtime, native/helper,
  persistence, protocol, dependency, or process-boundary widening. Upstream
  remained reference-only, so the import ledger remains unchanged. Package 7
  still owns visual hierarchy, density, spacing, typography, motion polish,
  visual-parity approval, and fresh parity captures.

### Package 6 correction — Player overlay focus reachability and busy custody

**Status:** correction plan review, implementation, focused coverage,
ignored-harness calibration, and production implementation review are clean.
The Mac physical-click limitation is closed as external proof-tool evidence,
not a product defect; all three acceptance rows remain mandatory in RD-27 on
Windows. **Role:** `worker` only. Low-cost workers are
ineligible because the unit corrects production DOM ancestry, focus
registration, pointer/OK activation, accessibility state, and actual fullscreen
proof as one invariant.
No parallel implementation is allowed across these coupled owners.

**Contradiction and frozen boundary:** post-closeout Package 7 plan review
proved that `[data-overlay-stack]` is a sibling before
`[data-screen="player"]`, not a descendant. Therefore
`readClosestRouteId()` returns `null` for terminal Guide and dynamic mini-guide/
option controls; the production registry cannot establish the Player-route
focus custody claimed by Package 6. Busy Retry, mini-guide, and option rows are
also native HTML `disabled`, while `isElementHiddenFromFocus()` rejects both
native disabled and `aria-disabled`, so none can retain exact busy focus.
The appended ignored adjudication accepts this as a Package 6 blocker.

Correct only the reachability/custody seam. Move the complete overlay stack,
unchanged in internal hierarchy, out of the native presentation element and
into `#screen-player`. Keep `[data-player-presentation-surface]` and its
`.player-surface` as the existing sibling native click target. This is the
smallest semantically correct ownership repair: every overlay focus target now
inherits the Player route's `hidden`, `inert`, and `aria-hidden` lifecycle, and
the existing route lookup works without a route-less overlay exception.

The stacking and pointer consequences are frozen. `#screen-player` remains the
positioned full-screen route layer; its absolute overlay stack therefore keeps
the same inset and overlay z-index above the native presentation. The Player
screen's `pointer-events: none` continues to pass unused pixels through to the
native presentation, while the existing `.player-overlay { pointer-events:
auto; }` and `.player-error button { pointer-events: auto; }` rules keep visible
overlay controls interactive. Because overlay controls and the native
presentation become siblings, overlay clicks can no longer bubble into the
native `openOsd` listener. That structural repair does not change the real query
shape: `playerPresentationElement` still carries `data-overlay-action="openOsd"`
and therefore remains present in `overlayActionButtons` as well as the dedicated
presentation binding. Do not change `domBindings.ts` or remove that semantic
attribute. `registerRendererActions()` must explicitly exclude the exact
`playerPresentationElement` identity from its generic overlay-action loop; the
dedicated presentation listener is the single owner of native-surface
`openOsd` activation and retains its existing `[data-overlay]` descendant guard
as defense in depth. No CSS change is approved unless actual mounted proof
contradicts one of these existing rules; such a contradiction requires replan
rather than a speculative style edit.

Busy custody is opt-in and activation-guarded, not a global focus-policy
change. Retry, the pending mini-guide row, and the pending playback-option row
must remain native-enabled (`disabled === false`) while busy, expose both
`aria-disabled="true"` and `aria-busy="true"`, and carry one explicit
overlay-only `data-overlay-busy-focus-custody="true"` marker. Nonbusy rows
expose false ARIA state, omit that marker, and have normal activation.
`focusDom.ts` may treat an otherwise visible `aria-disabled` element as
focusable only when that exact marker and
`aria-busy="true"` are both present; native disabled controls and every other
`aria-disabled` control remain excluded. This forbids a broad onboarding,
Settings, Guide, or shell policy change.

Busy focus does not mean busy activation. `clickFocusedRendererElement()`
continues to reject `aria-disabled`; delegated mini-guide and option pointer
handlers continue to use `isEligibleDelegatedAction()`; and the direct overlay-
action listener must use that same eligibility guard before dispatch so busy
Retry cannot run by pointer, synthetic click, Enter, or OK. Every direct route-
action listener must also apply `isEligibleDelegatedAction()` before dispatch;
this includes terminal Guide and preserves all currently eligible route actions
while suppressing synthetic activation of hidden, inert, native-disabled, or
ARIA-disabled route controls. The general
focusable-element pass skips elements carrying `data-overlay-action`, and the
dedicated overlay-action pass registers each once at its existing order after
those controls gain real Player ancestry. Terminal Guide
registers through its existing route-action path; dynamic mini-guide/options
register through the normal current-focusable-element path. No new route id,
focus id, action id, public helper, compatibility path, or controller callback
is approved.

Exact production files:

- `src/renderer/staticDom.ts`: move only the existing overlay-stack subtree
  under `#screen-player`; keep native presentation and overlay contents intact.
- `src/renderer/routeDom.ts`: project native-enabled, ARIA-disabled/busy,
  explicitly marked custody for busy Retry/mini/options and clear it outside
  those exact pending states.
- `src/renderer/focusDom.ts`: admit only the explicit visible busy-custody
  target, retain every other hidden/inert/disabled exclusion, and prevent
  duplicate overlay-action registration after route ancestry is repaired.
- `src/renderer/rendererActionRegistration.ts`: apply the existing delegated
  eligibility predicate to direct overlay-action and route-action clicks;
  exclude the exact presentation identity from the generic overlay-action loop
  so its dedicated listener is the sole native `openOsd` owner.

Exact tests:

- `src/__tests__/renderer/routeDom.test.ts`
- `src/__tests__/renderer/focusDom.test.ts`
- `src/__tests__/renderer/rendererActionRegistration.test.ts`
- `src/__tests__/renderer/rendererRuntimeOwners.test.ts`

The focused command is:

`node --import tsx --test src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/rendererActionRegistration.test.ts src/__tests__/renderer/rendererRuntimeOwners.test.ts`

Public-seam regression proof must cover: overlay-stack Player ancestry and
native-presentation sibling custody; `readClosestRouteId()` resolving `player`
for terminal Guide, selected mini rows, and option rows; registry acceptance,
exact DOM focus, and removal when the owner becomes hidden/inert; Retry, mini,
and options busy focus remaining exact with native `disabled === false`,
`aria-disabled="true"`, and `aria-busy="true"`; pointer, synthetic click,
Enter/OK suppression while busy; re-enabled activation after settlement; no
double dispatch/registration; and unchanged bare-native click behavior. The
action-registration regression must use the production query shape with the
same presentation element present in both `overlayActionButtons` and
`playerPresentationElement`: one bare presentation click dispatches exactly one
`openOsd`, while clicks within overlay owners dispatch none through the
presentation listener. It must also prove eligible terminal Guide dispatches
exactly once and hidden, inert, native-disabled, and ARIA-disabled terminal
Guide synthetic clicks dispatch zero. Node tests use real ancestor
relationships and the production registry/action seams, not arbitrary accepted
focus strings or private-state probes.

Refresh the ignored Package 6 target through the actual browser DOM. The target
must call `mountStaticRendererDom()`, `queryRendererDom()`, production route/
workflow rendering, `syncRendererFocusTargets()`, `focusRendererTarget()`, and
`renderRendererFocus()`; manual `.is-focused` or `tabindex` injection is
forbidden. Capture the existing ten sanitized states plus Retry pending,
mini-guide busy, and option busy at exact CSS viewports `1280x720` and
`1920x1080`, DPR 1: 26/26 screenshots and a refreshed contact sheet. Every row
asserts the overlay stack is inside the visible Player screen and outside the
native presentation, correct route ancestry, exact owner/focus or focusless
state, hidden/inert-owner exclusion, and no private material. Busy rows also
assert the exact ARIA/native-enabled custody and guarded activation state.

Observed proof-environment evidence is explicit. While the Mac session was
locked, Computer Use could not unlock it and a fresh visible `BrowserWindow`
remained unfocused, so `enter-full-screen` never fired. After the user unlocked
the session, the first row acquired foreground from a controller title-bar
click and passed; a later row automatically acquired foreground after the
prior proof child exited and passed without a controller click. All exercised
fullscreen event/state, focus, DPR, and restoration assertions otherwise
passed. That unlocked run is still not acceptance proof: a focus transition
cannot by itself attribute foreground acquisition to the required operator
action. The same run also reached contact-sheet generation and failed because
ImageMagick could not resolve a default font; an explicit
`/System/Library/Fonts/Helvetica.ttc` made the same montage succeed.

Run the three semantic-only actual `BrowserWindow` fullscreen rows for OSD,
mini-guide, and playback options in bounded
`operator-assisted-foreground` activation mode. The user leaves the unlocked
desktop session available; Codex/Computer Use does not request, receive, store,
or enter the user's unlock credential. Each row uses one fresh framed child
window and one fresh, cryptographically random, row-scoped acknowledgement
token. The child mounts the state, establishes exact DOM focus through the
production registry path, calls `showInactive()`, and fails unless the window
is visible but both `BrowserWindow.isFocused()` and `document.hasFocus()` are
false while the exact overlay element remains active. It then emits exactly one
control frame containing the unique row, unique window title, one-time token,
and the single 30,000 ms activation deadline. The token is terminal control
state only: it must never appear in a manifest, result JSON, filename, contact
sheet, or error payload.

The parent command must run in the existing controller PTY and fail before row
1 unless `process.stdin.isTTY === true` and stdin is readable, open, and not
destroyed. The sole external acknowledgement source is that parent TTY stdin.
Environment variables, argv, files, result files, clipboard state, sockets,
Electron IPC, child stdout/stderr, and any alternate pipe or channel may not
supply an acknowledgement. The sole allowed internal transport is the
parent-to-current-child private stdin pipe. One line-delimited reader owns the
same parent stdin through all three rows; the parent must not pause, replace,
destroy, or close it between children. Each fresh fullscreen child receives a
new private stdin pipe belonging only to that row. The parent keeps the child
pipe open through acknowledgement and successful row completion/child exit;
only then may it close or release that pipe. Parent TTY closure before all
three rows complete, or child stdin closure before its row completes, fails the
whole command.

Tokens are 32 cryptographically random bytes encoded as exactly 43 unpadded
base64url characters matching `[A-Za-z0-9_-]{43}`. Whitespace, padding, line
breaks, and control characters are forbidden. The child emits one newline-
terminated control frame with this exact grammar:

`PACKAGE6_OPERATOR_ACK_REQUIRED {"row":"<1-based>/3","state":"<expected-state>","title":"<exact-window-title>","token":"<43-char-base64url>","deadlineMs":30000}`

The JSON object contains those five keys in that order and no others. Child
stderr may be fragmented or interleaved with unrelated diagnostics, so the
parent owns per-child line framing. It validates the exact current row,
expected state, exact title, token encoding, deadline, and one-prompt state
before accepting the frame. A noncurrent, duplicate, malformed, or token-
bearing unrelated frame fails without emitting a prompt. Unrelated complete stderr lines remain
ordinary relayed diagnostics and fragments remain buffered until newline;
neither can emit or arm the operator prompt. After validation, the parent
serializes the same canonical grammar as exactly one newline-terminated prompt
to its own stderr. It calls the broker clock only after `writePrompt()` returns
successfully and records that value as `promptEmittedAtMs`; the 30,000 ms row
deadline is exactly `promptEmittedAtMs + 30_000`. Only then does the current-row
canonical parent prompt arm TTY token input, so prompt content and deadline are
independent of child chunk boundaries and unrelated stderr.

The executable operator order is exact. First, after reading the canonical
prompt, the controller sends the exact token plus one newline through the
parent TTY; it does not click yet. The broker validates and consumes that row's
one acknowledgement capability, then forwards exactly one newline-terminated
child acknowledgement line through the current private stdin pipe:

`PACKAGE6_OPERATOR_ACK {"token":"<43-char-base64url>","promptEmittedAtMs":<integer-ms>}`

The object contains exactly those two keys in that order. No raw token line,
duplicate acknowledgement, or parent-emitted copy of the child control frame
is authorized. The child validates the exact token and broker timestamp while
window/document focus remain false and the exact overlay target remains active,
then emits exactly one token-free newline-terminated readiness frame:

`PACKAGE6_OPERATOR_CLICK_READY {"row":"<1-based>/3","state":"<expected-state>","title":"<exact-window-title>","promptEmittedAtMs":<integer-ms>,"deadlineRemainingMs":<positive-integer-ms>}`

The parent validates the current row, exact state, exact title, original prompt timestamp,
positive remaining time derived from the original deadline, and one-ready-only
state. It forwards that canonical frame exactly once to controller stderr.
Malformed, duplicate, noncurrent, late, or pre-ack readiness fails. No other
parent-emitted child control line is authorized at this stage. Only after the
controller observes the canonical `CLICK_READY` frame does it use Computer Use
exactly once to click that proof window's title-bar container.

After the Computer Use tool call returns, the controller sends exactly one
token-free newline-terminated confirmation through the parent TTY:

`PACKAGE6_OPERATOR_CLICK_CONFIRMED {"row":"<1-based>/3","state":"<expected-state>","title":"<exact-window-title>","attestation":"computer-use-titlebar-click-returned"}`

The broker validates current row, exact state, exact title, exact attestation label,
ready-observed state, and one-confirmation-only state; records
`controllerClickConfirmedAtMs` at receipt; and forwards the same canonical line
exactly once to the current child. The child validates current row/state/title
and the remaining schema. This readiness and
confirmation exchange is the only second parent-to-child control line after
the token-bearing acknowledgement; no duplicate or alternate control line is
authorized.

The row requires the `CLICK_READY` observation, exactly one controller click
confirmation, and the first post-ready false-to-true transition of the complete
accepted foreground-focus condition inside the original prompt-based deadline:
`BrowserWindow.isFocused() === true`, `document.hasFocus() === true`, and the
unchanged exact active overlay element. Automatic focus before readiness fails.
Focus after readiness without controller confirmation is recorded but cannot
pass. Confirmation before readiness, wrong-row or wrong-state confirmation,
wrong-state or duplicate ready,
duplicate/second confirmation, missing confirmation, confirmation without an
accepted transition, wrong/missing/replayed/already-consumed/out-of-row token,
carry-over input, or deadline expiry fails token-free. The parent never
broadcasts or queues a control line for a later row. It keeps the child pipe
open through successful row completion/child exit, then disarms and releases
the row before creating the next child. Only the ready-plus-confirmed post-ready
transition may record pre-entry bounds, content bounds, CSS viewport, and DPR
and request fullscreen. A second assist, content click, DOM focus injection,
`app.focus()`/`window.focus()`, AppleScript, or synthetic activation is
forbidden. Each row
still requires the actual
`enter-full-screen` event plus
`isFullScreen() === true` within 5,000 ms, exact owner/route ancestry/DOM focus
and window/document focus while fullscreen, the actual `leave-full-screen`
event plus `isFullScreen() === false` within 5,000 ms, exact focus continuity,
and exact restoration of window bounds, content bounds, CSS viewport, and DPR.
No second operator assist is permitted before, during, or after fullscreen.

The three manifest rows retain `activationMode:
"operator-assisted-foreground"` and record the row/window title,
`controllerAcknowledgementAccepted: true`, `clickReadyObserved: true`, and
`controllerClickConfirmed: true` (never the raw token), activation elapsed
milliseconds from prompt emission through the ready/confirmation/focus
conjunction, the initial-unfocused-to-accepted-focus transition, and pre-entry/
during/post-exit window/document focus results. Each row also records a token-
free tool-call attestation object with label
`computer-use-titlebar-click-returned` and the broker-recorded
`controllerClickConfirmedAtMs` timestamp. The exact-one-click claim is explicit
operator/controller attestation backed by that Computer Use tool call; the
automated claim is limited to protocol ordering, focus transition, fullscreen
events/state, continuity, and restoration. Locked session, unavailable
operator foregrounding, wrong/missing/replayed/out-of-row acknowledgement,
automatic focus before readiness, focus without controller confirmation,
confirmation before readiness, duplicate/wrong-row/wrong-state/second
confirmation, duplicate/wrong-state readiness, second assist, stdin closure, activation timeout,
unsupported fullscreen, missing
event, wrong fullscreen state, focus loss, restoration mismatch, manual focus
injection, cleanup failure, or retained window fails the row and command; none
may be converted to pass, skip, or deferred. The refreshed manifest remains 29
result rows: 26 screenshots and three fullscreen semantic rows. This is
Mac/local operator-assisted foreground activation with explicit controller
acknowledgement and automated renderer/fullscreen assertions only; RD-27
retains Windows/native operational proof.

Contact-sheet generation must preflight the exact Mac system font
`/System/Library/Fonts/Helvetica.ttc`, fail if it is absent or unreadable, and
pass that exact path to ImageMagick's `montage` invocation with `-font`. No
default-font lookup or substitute font is allowed. Preserve the existing fixed
file order, thumbnail, tile, geometry, output path, timeout, stderr capture,
exit-code check, 26-capture requirement, manifest write-after-contact-sheet
ordering, and generated-output cleanup.

This acknowledgement/font subunit may change only the ignored
`docs/runs/complete-webos-ui-parity-reopen/capture-package-6.mjs` and regenerate
the ignored Package 6 captures, manifest, and contact sheet. The ignored
correction packet may record verification/review results. All tracked product
and test files, the Package 6 browser target, main smoke assertions, CSS,
Package 7 artifacts, contracts, dependencies, and public/process boundaries are
frozen. Preserve sequential row execution, the existing screenshot/fullscreen
semantic assertions and deadlines, stderr propagation without token-bearing
error echo, per-child result/temp cleanup, listener/window cleanup, Vite
teardown, manifest row/count checks, private-material scan posture, and the rule
that no partial or failed proof becomes an acceptance artifact. Any required
change outside this exact ignored seam is a stop/replan trigger.

Failure cleanup is ordered and observable. On any activation timeout, broker
failure, protocol failure, fullscreen timeout, or parent exception, the parent
first disarms TTY input and prevents further result acceptance, then terminates
the current child. It awaits observed child `exit` and `close` before deleting
that row's temp result, any partial output, or shared generated output and
before completing Vite teardown. A bounded terminate-to-kill escalation may be
used, but timeout rejection alone may never start deletion while a child can
still write. Failure to observe child close is itself a token-free command
failure and preserves the evidence path for adjudication; it cannot be reported
as clean cleanup.

Before live capture, the same ignored harness must expose one exclusive,
bounded broker self-test mode:

`node docs/runs/complete-webos-ui-parity-reopen/capture-package-6.mjs --self-test-ack-broker`

The flag branches before output cleanup, Vite, Electron, font preflight,
screenshots, fullscreen, manifest, contact-sheet, or result-file work. It uses
a deterministic fake clock and in-memory current-child endpoints, has a 10,000
ms whole-process timeout with no real waits, and runs exactly 23 named cases:
one positive `broker-framing-fragmentation` case plus rejection of
`wrong-token`, `missing-token`, `replayed-token`, `out-of-row-token`,
`duplicate-token`, `buffered-no-current-row-input`,
`automatic-focus-before-click-ready`, `focus-after-ready-without-confirmation`,
`confirmation-without-focus`, `click-before-ack`, `missing-click-ready`,
`duplicate-click-ready`, `wrong-state-click-ready`,
`confirmation-before-ready`, `wrong-row-confirmation`,
`wrong-state-confirmation`, `second-click-confirmation`, `parent-stdin-close`,
`child-stdin-close-before-row-completion`, `activation-deadline-expiry`,
`late-writer-after-failure`, and `token-leakage`.

The positive case fragments the valid child control frame and TTY token line
across multiple chunks, surrounds the control frame with unrelated complete
and fragmented child stderr, proves only the exact current canonical prompt
arms input, forwards the reassembled token exactly once to the current fake
child as the canonical acknowledgement JSON line, proves the prompt timestamp
is sampled only after prompt write completion, accepts exactly one canonical
`CLICK_READY`, accepts exactly one controller `CLICK_CONFIRMED`, and gates the
post-ready focus transition on confirmation. It keeps the simulated parent TTY
and child pipe open through row completion, disarms the row, and accepts a
fresh next-row token without carry-over. Every rejection case fails closed with
its stable case id and cannot advance fullscreen. It separately proves pre-
ready focus, post-ready focus without confirmation, confirmation without focus,
missing/duplicate/wrong-state ready, early/wrong-row/wrong-state/second
confirmation, and pre-ack click.
Closure cases distinguish the all-three-row
parent TTY lifecycle from the current-row child-pipe lifecycle. The late-writer
case makes a failed child attempt a result write after timeout and proves the
parent kills and observes both exit/close before deleting temp or output state,
so the late writer cannot recreate an acceptance artifact.

The public self-test orchestrator must run broker-positive and fault cases in
bounded internal subprocesses and capture each process's complete stdout and
stderr plus artifact payloads. It may use the private exclusive flag
`--self-test-ack-broker-child=<case-id>` only from the public self-test mode;
that private flag is mutually exclusive with live mode and cannot create Vite,
Electron, font, capture, fullscreen, manifest, contact-sheet, or live result
work. The `token-leakage` case uses a sentinel token and permits its raw value
exactly once across captured process stdout/stderr and artifact payloads: in
the authorized canonical parent prompt. The controller's TTY input and the
private parent-to-child acknowledgement transport necessarily carry the token
ephemerally, but neither may echo, log, persist, or enter the captured-output/
artifact surface. The intercepted child control frame is private broker input
and is never relayed into captured stdout/stderr or artifacts. Broker errors,
rejection details, fake results, and artifact payloads must otherwise remain
token-free. The mode snapshots any pre-existing real Package
6 manifest and contact sheet by existence, byte hash, and metadata and proves
them unchanged. It uses
a unique temporary sandbox for fake result paths, proves no manifest, contact
sheet, screenshot, fullscreen result, partial result, or other acceptance
artifact was created, and removes the sandbox in `finally`.

Success exits zero and emits exactly one token-free stdout line with empty
stderr:

`Package 6 acknowledgement broker self-test: 23/23 passed`

Any missing case, unexpected result, timeout, forbidden token occurrence,
artifact mutation/creation, or cleanup failure exits nonzero with token-free
diagnostics. The live capture command is not authorized until this exact self-
test passes; the self-test cannot replace the 29-row live proof.

An unavailable session or acknowledgement transport does not authorize
production/test edits or a weaker proof. Rerun the complete command so all
three fullscreen rows use fresh row-scoped tokens and the same recorded
activation mode. If an acknowledged, title-bar-foregrounded window satisfies
all focus predicates but an enter/leave event, fullscreen state,
focus-continuity, or restoration assertion still fails, preserve the failure
and return to controller/reviewer adjudication; do not substitute a screenshot
or simulated fullscreen state.

**Reviewed single-PID fullscreen proof correction:** keep all 26 screenshot
captures unchanged, but run the three fullscreen rows in one Electron child,
one stdin/stderr session, and one `BrowserWindow`. The child calls
`app.whenReady()` once and processes OSD, mini-guide, then options in frozen
order. After a successful row it removes row-local listeners, marks and
disposes the row gate, hides the window, calls macOS `app.hide()`, and has at
most 2,000 ms to observe `app.isHidden()`, invisible/unfocused window state.
For the next row it loads the new URL while hidden, sets the exact unique title,
calls `app.show()` followed by `window.showInactive()`, settles for the existing
50 ms, and fails before ACK unless the app, window, and document are all
unfocused while the exact production overlay target retains focus custody.
No programmatic focus, content click, second assist, or synthetic activation is
allowed. Failure to re-establish this prompt state is a stop/replan trigger.

The broker owns the ordered three row/state/title identities and the same child
pipe for the whole session; no new protocol frame is added. A next-row exact
`ACK_REQUIRED` is accepted only after the prior row reached `click-confirmed`;
its receipt atomically archives the prior metadata and arms the next expected
identity. Any early, duplicate, stale, or out-of-order identity fails closed.
The parent clears the current activation timer immediately after it validates
and forwards an on-time `CLICK_CONFIRMED`; the child retains the original
prompt-derived 30,000 ms deadline through accepted focus/readiness. Each
`enter-full-screen` and `leave-full-screen` event keeps its existing 5,000 ms
bound, for 10,000 ms total per row. The one-child session has an exact 165,000
ms lifecycle bound. The child retains results in memory and writes one
three-row JSON array only after row three, final hide/window destruction proof,
then quits. Parent acceptance requires exit zero plus observed close and exact
index-for-index result/metadata validation; no partial row may reach the
manifest.

Keep exactly the existing 23 self-test names and success line. Adapt
`broker-framing-fragmentation` to prove two-row rollover through the same fake
child/pipe and fresh tokens; map cross-row replay/order coverage through
`replayed-token`, `out-of-row-token`, `duplicate-click-ready`, and
`second-click-confirmation`; make the parent/child closure, activation deadline,
late-writer, and token-leakage cases session-scoped. Each remains an independent
subprocess so one failure cannot mask another. Multi-PID retry, client reset,
registry refresh, display name, bundle id, and full app-path variants are
rejected by observed evidence. This replan received clean independent plan
review on 2026-07-15.

The first live single-PID attempt passed row one but hit its explicit replan
trigger before row-two ACK: the native app/window were unfocused while the
reused `WebContents` still reported `document.hasFocus() === true`. Therefore
retain the one Electron PID, pipe, broker, ordered identities, protocol,
deadlines, cleanup ordering, and one final result array, but create a fresh
`BrowserWindow`/`WebContents` for each fullscreen row. Do not use
`app.hide()`, `app.show()`, `app.focus()`, or reuse prior content. Each row must
begin with zero Electron windows; create/load the existing hidden framed proof
window, set its exact title, call `showInactive()` once, and require it is the
sole visible window while app/window/document remain unfocused, nonfullscreen,
DPR 1, and exact overlay semantics pass before ACK. After restored fullscreen
proof, remove row-owned listeners, destroy the window, prove both window and
WebContents destruction and zero remaining windows, then mark/dispose the gate
and append the in-memory row. Only then may the next window/prompt exist. A
failure performs the same bounded fullscreen exit and destruction proof, never
appends or writes the session result, and exits the single child nonzero. After
row three require three results and zero windows before the one array write and
`app.quit()`. No broker/self-test name or frame changes are required. This
narrow live-evidence replan received clean independent plan review on
2026-07-15.

A second live attempt proved the fresh row-two `WebContents` correctly reports
document/window focus false, but the no-window Electron app remains active.
The final clean reviewed lifecycle therefore combines both proven halves.
Before row one and after every destroyed row, require zero windows, call
`app.hide()` once, and within 2,000 ms prove hidden, inactive app state with no
focused or retained window. Create/load the fresh next-row window while hidden;
pre-show focus/semantics/DPR/geometry must pass, then call `app.show()` once
(which does not automatically focus on macOS) and `showInactive()` once. Before
ACK require the app is shown but inactive and every existing fresh-window
predicate passes. Accepted post-click foreground must additionally prove the
app became active only after readiness/confirmation. After fullscreen,
destruction and the same hide/inactive reset precede gate completion, disposal,
and row append. Final output is authorized only from three rows, zero windows,
and hidden/inactive app state. The whole-session watchdog is exactly 173,000 ms
to add four bounded reset allowances; row activation and fullscreen event
deadlines remain unchanged. This final combined lifecycle received clean
independent plan review on 2026-07-15.

A third live attempt reached row-two ACK with every fresh-window predicate
passing, but Computer Use returned `AXError.noValue` when the native
`BrowserWindow` identity changed. The final AX-compatible clean reviewed
lifecycle therefore supersedes per-row window replacement: retain one
BrowserWindow/WebContents identity for the session and set proof-only
`focusOnNavigation: false`. Initial and post-row reset uses `window.hide()` then
`app.hide()` and the existing 2,000 ms hidden/inactive conjunction, including
document focus false and sole retained live identities. Hidden navigation must
preserve that false document focus; then one `app.show()` plus one
`showInactive()` exposes the same AX window inactive before ACK. Post-row facts
prove the same window/WebContents are retained and inactive. Only after row
three are session listeners removed and the window/WebContents destroyed once;
exact final cleanup facts prove zero windows and hidden/inactive app before
guard release, result write, and quit. Parent validation requires both exact
row cleanup and final cleanup schemas. The 173,000 ms session bound, row/event
deadlines, protocol, clicks, and 23 self-test names remain unchanged. This
superseding lifecycle received clean independent plan review on 2026-07-15.

The unlocked token-safe diagnostic then proved the remaining contradiction is
semantic, not behavioral: on macOS the retained WebContents remains the
window's first responder and reports `document.hasFocus() === true` while
`app.isActive()`, `window.isFocused()`, and `BrowserWindow.getFocusedWindow()`
all prove native inactivity. Electron documents WebContents focus on macOS as
first-responder state that is not cleared by switching native windows. The
evidence-calibrated final plan therefore requires retained document/semantic
focus as renderer custody and removes it from native-foreground preconditions.
Operator foregrounding is proved exclusively by the first post-ready
BrowserWindow focus transition, inactive-to-active app/window state, exact
focused native window, controller-confirmation ordering, and the one physical
titlebar click. Exact manifest vocabulary is
`native-app-window-transition-with-retained-first-responder`; new semantic
checks and cleanup facts distinguish native activation from retained renderer
custody. Early native app/window activation, native focus without confirmation,
or confirmation without native focus still fail closed. No synthetic blur or
focus, extra view/window/process, click, frame, or tracked edit is authorized.
This final calibration received clean independent plan review on 2026-07-15.

The next unlocked live run failed closed before row-one acknowledgement and
proved one final row-indexed distinction. A freshly created hidden WebContents
has the exact semantic active target but does not report document focus before
its first genuine native activation. After row one receives the accepted
operator titlebar click, the retained WebContents keeps first-responder custody
through the inactive resets for rows two and three. The final row-indexed proof
contract therefore requires row one to use
`semantic-active-target-without-first-responder` with document focus false,
while rows two and three use `retained-first-responder` with document focus
true. All rows require exact semantic focus before native activation and
document plus semantic focus after native activation. Native foreground proof
remains exclusively the ordered post-ready BrowserWindow focus event, active
app/window state, exact focused native window, controller confirmation, and one
physical titlebar click. The exact foreground evidence mode is
`native-app-window-transition-with-semantic-focus-custody`.

Each fullscreen row must emit exact `preNativeDocumentCustody` evidence with
`mode`, `expectedDocumentFocused`, `observedDocumentFocused`,
`semanticFocusAccepted`, and `activeElementFocusId`; row one uses false/false
and rows two and three true/true. Exact `postNativeDocumentCustody` evidence
uses mode `first-responder-active`, document and semantic focus true, and the
expected active focus id. Native transition evidence remains a separate exact
false-to-true app/window/focused-native-window tuple. Successful row cleanup
must prove hidden/inactive app and window, no focused native window,
`documentCustodyMode: retained-first-responder`, document and semantic focus
true, one retained BrowserWindow, and retained BrowserWindow/WebContents
identities. Hidden, prompt, and pre-ready checks derive the document expectation
from the frozen proof row rather than observation. After readiness document
focus is diagnostic until native acceptance, which requires it true. Existing
Fullscreen semantic assertions remain discrete and auditable: acknowledgement,
click-ready, confirmation, `pre-native-semantic-focus-custody`,
`pre-native-document-custody-mode-exact`, post-ready native transition,
operator native foreground, `post-native-first-responder-custody`,
`operator-focus-target-stable`, `overlay-owner-exact`, `player-route-exact`,
pre-entry/fullscreen/post-exit native focus, restoration, DPR, and geometry.
Owner and route checks cover prompt, pre-fullscreen, fullscreen, and post-exit
samples rather than relying only on a composite focus boolean. Existing 23
broker cases must model the first row without document focus and the next
row with retained document focus without changing protocol, deadlines, click
count, process/window identities, or cleanup ordering. The existing
deterministic row-evidence/validator case must also reject both
inverted row-index states: row one may not claim retained-first-responder or
observed document focus true, and rows two or three may not claim the fresh
semantic-only mode or observed document focus false. This negative coverage
must remain within the exact 23 named cases.

Synthetic focus/blur,
another input, click, frame, view, window, process, or tracked product edit
remains prohibited. This row-indexed contract supersedes the prior all-rows
retained-first-responder manifest contract.

The integrated controller then completed row one's acknowledgement, physical
click, native transition, confirmation, fullscreen cycle, and restoration, and
failed closed only during the post-row hide reset. That diagnostic proves the
cleanup phase is distinct from the next row's post-navigation custody: hiding
the app/window clears the current document's focus while preserving the exact
semantic active target. Every successful row cleanup must therefore require
document focus false and mode
`semantic-active-target-without-first-responder`. Only after that cleanup is
accepted may the same hidden retained WebContents navigate; the existing
row-indexed post-navigation contract remains row one false and rows two and
three true. A navigation-induced false-to-true document transition while the
app/window remain inactive is renderer custody only and cannot satisfy native
foreground proof.

Exact `cleanupFacts` now contain only `appHidden`, `appInactive`,
`windowHidden`, `windowInactive`, `focusedNativeWindowAbsent`, `fullscreen`,
`documentCustodyMode`, `documentFocused`, `semanticFocusAccepted`,
`activeElementFocusId`, `retainedWindowCount`, `browserWindowRetained`, and
`webContentsRetained`. Values must prove native inactivity, fullscreen false,
semantic-only custody, document focus false, the expected focus id, one
retained window, and unchanged BrowserWindow/WebContents. The exact cleanup
assertion vocabulary is
`post-row-semantic-custody-without-first-responder`. The existing 23-case
multi-row scenario must model native document focus true, post-hide document
focus false with exact semantics, next hidden navigation to the indexed
document state, and a new native transition for the next row. No deadline,
protocol, identity, click, process, or product scope changes.

Computer Use then proved a separate stable-window AX limitation: after the
reviewed hide/show cycle it can read the exact unchanged row-two window, but a
normal app-local coordinate click fails because macOS no longer exposes an AX
focused-window value. Element-targeted variants either clear renderer focus or
fail ScreenCaptureKit validation and are rejected. The final bounded diagnostic
uses Electron's macOS/Windows `setFocusable` API, whose macOS contract does not
remove focus, to re-register the already inactive visible window without
foregrounding it. Row one uses no refresh. Rows two and three perform exactly
one focusable true-to-false-to-true sequence: disable while hidden/inactive,
show the nonfocusable window with `showInactive()`, then restore focusability
before acknowledgement. Every phase must preserve app/window inactivity,
absence of a focused native window, row-indexed document and semantic custody,
window/WebContents identity, title, DPR, and geometry. Any native activation or
custody drift fails before a token is emitted.

Each fullscreen row records exact `axFocusabilityRefresh` evidence with ordered
keys `mode`, `applied`, `disabledWhileHiddenInactive`,
`shownInactiveWhileNonfocusable`, `focusableBeforePrompt`,
`nativeInactivityPreserved`, `semanticCustodyPreserved`, and
`windowIdentityPreserved`. Row one uses mode `initial-window-no-refresh`,
`applied: false`, null disabled/shown facts, and true focusable,
native-inactivity, semantic, and identity facts. Rows two and three use mode
`stable-window-visible-reregistration`, `applied: true`, and all six boolean
proof facts true. Exact assertion vocabulary is
`ax-initial-window-focusable-before-ready` for row one and
`ax-focusability-disabled-while-hidden-inactive`,
`ax-window-shown-inactive-while-nonfocusable`,
`ax-focusability-restored-before-ready`,
`ax-refresh-preserved-native-inactivity`,
`ax-refresh-preserved-semantic-custody`, and
`ax-refresh-preserved-window-identity` for rows two and three. This supersedes
the prior 13-key cleanup schema: successful `cleanupFacts` now contain exactly
14 ordered keys `appHidden`, `appInactive`, `windowHidden`, `windowInactive`,
`windowFocusable`, `focusedNativeWindowAbsent`, `fullscreen`,
`documentCustodyMode`, `documentFocused`, `semanticFocusAccepted`,
`activeElementFocusId`, `retainedWindowCount`, `browserWindowRetained`, and
`webContentsRetained`; `windowFocusable` is true. Failure cleanup restores
focusability before the existing hide/reset/destruction sequence. Protocol,
deadlines, the single app-local titlebar click, native transition ordering,
fullscreen proof, and all product scope remain frozen. Failure of the one
refresh to restore the ordinary Computer Use click is a stop trigger; no
second toggle or targeting workaround is authorized.

The existing deterministic multi-row/validator self-test case must accept row
one's exact no-refresh record and row two's single false-to-true refresh record,
and reject wrong mode, wrong `applied`, invalid row-one nullability, false or
missing preservation facts, and missing `windowFocusable`, without adding or
removing any of the exact 23 case names.

#### Reviewed Package 6 platform-proof exception

The user authorized closing the Package 6 production correction on its verified
code and bounded diagnostic evidence, deferring all three operator-assisted
fullscreen rows to a fresh mandatory RD-27 Windows manual audit, and continuing
Packages 7–8. The exception is independently reviewed and implemented in the
durable status mapping and token-free ignored artifact. It does **not** claim a
completed 29-row Mac acceptance manifest.

No further Package 6 product change is authorized. Exception closeout may
update only this plan, `docs/roadmap/desktop-port-roadmap.md`,
`docs/architecture/CURRENT_STATE.md`,
`docs/product/lineup-product-parity-matrix.md`, and
`docs/development/windows-ui-proof-plan.md`, plus the ignored correction packet
and a token-free ignored
`package-6-mac-physical-click-exception.json`. The divergence register and
import ledger remain unchanged because this is an external proof-tool limit,
not a product divergence or copied/adapted source change.

Closeout may claim the production overlay ancestry, busy focus custody,
direct-action eligibility, and single-owner native-presentation correction is
implemented; focused correction coverage passed 44/44; the previously observed
full verification passed 823 source/contract tests and 135 harness/docs tests;
production implementation review was clean; current documentation verification
is green; and Mac row one completed acknowledgement, one app-local physical
titlebar click, ordered native app/window focus, confirmation, exact semantic
custody, actual fullscreen enter/leave, focus/geometry/DPR/restoration, and
cleanup. It may state row two repeatedly reached its exact inactive semantic
state before the external Computer Use click failed with AX or ScreenCaptureKit
errors, the one reviewed focusability refresh reached its hard stop, row three
was deferred without a Mac acceptance run, and no partial acceptance artifact
or retained proof process/window remains.

Closeout must not claim 29/29 rows passed, three Mac click rows passed, completed
Mac fullscreen acceptance, a production focus/fullscreen defect inferred from
AX errors, existing Windows operational proof, or optional deferred rows. A
failed or partial `package-6-target-manifest.json` remains absent rather than
being represented as acceptance evidence.

The durable documentation mapping is exact. In `CURRENT_STATE.md`, the current
top-level state and renderer-owner summary must say the Package 6 production
correction is implemented and reviewed while operator-assisted Windows
fullscreen proof remains pending; it must identify the Mac error as an external
proof-tool limit, not product behavior. In `desktop-port-roadmap.md`, the active
reopen gate and RD-27 section must allow Packages 7–8 renderer implementation to
finish under this reviewed exception while adding a non-optional `Package 6
operator-assisted fullscreen focus audit`; RD-27 cannot close without its fresh
three-pass Windows manifest. In the `Player route, now-playing, OSD, mini-guide,
and channel badge` parity-matrix row, classification/evidence must remain short
of platform completion and the platform label must say `implemented and
automated locally; Windows operator-assisted proof pending`. In
`windows-ui-proof-plan.md`, the prerequisite/current-gate text and Windows proof
matrix must add the exact fresh three-row protocol as a blocking RD-27 gate. In
this active plan, Package 7 unblock and Package 8 closeout must retain the same
pending-platform-proof nonclaim through archive.

The ignored exception JSON is exact and contains no tokens, prompts, raw logs,
PIDs, paths, AX objects, screenshots, or private account/media data:

```json
{
  "status": "deferred-to-rd-27-windows",
  "reason": "mac-computer-use-stable-window-physical-click-targeting-unavailable",
  "requiredPhysicalClickRows": 3,
  "completedAcceptanceManifest": false,
  "diagnosticRows": {
    "player-osd": "full-live-sequence-observed",
    "player-mini-guide": "pre-input-state-observed-external-click-unavailable",
    "player-options": "deferred-without-acceptance-run"
  },
  "partialAcceptanceArtifactsRetained": false,
  "retainedProofProcesses": false,
  "nextMandatoryGate": "rd-27-windows-manual-physical-click-audit"
}
```

Before Package 7 is unblocked, rerun the four focused correction tests, the
exact ignored 23-case broker self-test, typecheck, architecture,
maintainability, redaction, Electron build and smoke, docs verification, full
verification, and `git diff --check`. The known-failing live Mac capture is
removed from closeout rather than rerun as ritual. Require fresh independent
review of the production/test diff, calibrated claims, exception redaction,
binding RD-27 placement, Package 7 behavior/visual freeze, exact scope, and
architecture/YAGNI.

Before the exception JSON may assert either cleanup boolean, validate its exact
schema and values, scan it plus the ignored run bundle for acknowledgement-token
shapes and private material, prove `package-6-target-manifest.json`,
`package-6-contact-sheet.png`, the target-capture directory, and temporary
fullscreen result files are absent, and prove no Package 6 capture/Electron
process remains. These checks are part of closeout evidence and reviewer scope,
not prose-only assurances.

If HEAD remains the current unpushed local `2eda503` Package 6 checkpoint and
verification/review are clean, amend it with only the approved production/test
correction. Commit the tracked exception and RD-27 memory separately as
`docs(roadmap): defer fullscreen click audit to rd-27`; ignored evidence is
never staged. Otherwise use a separate conventional correction commit.

Package 7 unblocks only after both commits and all gates/review are clean. Its
baseline, line counts, ancestry, busy-custody behavior, and upstream provenance
must then be refreshed from the new HEAD and independently reviewed. Package 7
remains presentation-only and may not compensate for deferred platform proof.

RD-27 must run all three rows afresh on Windows: `player-osd` focused at
`overlay-osd-audio` under `playerOsd`; `player-mini-guide` focused at
`overlay-mini-channel-sample-channel-1` under `miniGuide`; and `player-options`
focused at `overlay-subtitle-track-off` under `playbackOptions`. Each row starts
visible but natively inactive with exact production focus registration, observes
readiness, receives exactly one real operator titlebar click, proves the native
transition occurs after readiness and before confirmation without semantic
focus change, observes actual fullscreen enter/leave with native and semantic
focus continuity, restores bounds/content bounds/CSS viewport/DPR exactly,
cleans up, and emits only token-free redacted evidence. RD-27 requires a fresh
three-pass manifest; the Mac diagnostic row substitutes for none of them and no
further deferral is allowed without another explicit reviewed replan.

Package 8 may close only as: renderer parity implementation and local automated
verification complete; Package 6 operator-assisted fullscreen platform proof
remains a binding RD-27 Windows gate. It may not claim complete platform parity
or a complete Package 6 29-row proof.

**Architecture/YAGNI:** current production line counts are `staticDom.ts` 298,
`routeDom.ts` 404, `focusDom.ts` 481, and
`rendererActionRegistration.ts` 289. Each correction shares its existing DOM,
focus, or action responsibility and should remain below 500 lines. Crossing 500
requires a compact cohesion disposition and fresh architecture review;
crossing 800, touching `index.ts`, `playerOverlayController.ts`, overlays/view
models, or CSS is a stop/replan trigger. Package 6 controller/timers/state,
Package 7 visual ownership, and all contracts/process/public boundaries remain
frozen.

The reviewed user-authorized exception supersedes the prior live-capture
closeout requirement. After exception-document implementation, run the focused
command, `npm run typecheck`, `npm run verify:architecture`,
`npm run verify:maintainability`, `npm run verify:redaction`,
`npm run build:electron`, `npm run smoke:electron`, the exact ignored Package 6
acknowledgement-broker self-test command, `npm run verify:docs`, `npm run
verify`, and `git diff --check`. Do not rerun the known-failing Mac live capture
as a completion gate. Require the fresh independent exception/implementation
review defined above.

The reviewed planning artifact is
`docs/runs/complete-webos-ui-parity-reopen/package-6-focus-custody-correction-packet.md`.
Package 6 correction closeout is recorded under the exception after exact
tracked/ignored implementation, named non-live verification, and calibrated
review. Commit handling remains controller-owned; this status does not claim a
commit, push, complete Mac acceptance manifest, or completed Windows proof.

### Package 7 — Player overlay visual surfaces

**Role:** `worker` only. `worker_sol_low` and `worker_luna` are ineligible
because the unit restructures the reachable overlay DOM/CSS ownership while
preserving a reviewed cross-owner focus/accessibility contract and requires
visual judgment at two exact viewports. No parallel implementation is allowed
because the DOM and stylesheet slices share selectors and proof states.

**Post-exception baseline:** Package 7 planning may proceed without claiming
Package 6 platform completion; implementation remains blocked until this
refreshed section and ignored packet receive clean independent plan review.
Before these authorized planning edits, Desktop was clean on `initial-build` at
`26a1bbcc092cdb97acb8dd1d9dfe266978f6f581` (`73fb795` is the amended Package
6 production correction and `26a1bbc` is the separate reviewed exception/RD-27
memory checkpoint). The only current tracked diff is this active-plan refresh;
the refreshed execution packet remains ignored. Fresh direct source reads prove
`[data-overlay-stack]` is
inside `#screen-player` and outside/beside
`[data-player-presentation-surface]`. The exact four-file public-seam correction
suite passes 44/44 and proves terminal Guide, selected mini-guide rows, and
playback-option rows resolve Player-route ancestry; Retry, the pending selected
mini-guide row, and the pending option row remain native-enabled while exposing
`aria-disabled="true"`, `aria-busy="true"`, and exact busy-focus-custody;
production focus registration preserves their exact focus while pointer,
synthetic click, Enter, and OK activation remain guarded. The same suite proves
native presentation and generic overlay action registration have one dispatch
owner. This is the immutable behavior/accessibility baseline for Package 7.

**Freshness and architecture audit:** Upstream
`/Users/tristan/Software/Lineup` is on `code-health` at
`a1a7ea7dcb1cfc8aee7cfcf88cf5a1dac718bf30`; its unrelated dirty files are
preserved. The scoped `player-osd`, `now-playing-info`, `mini-guide`,
`channel-badge`, `channel-number-overlay`, `channel-transition`,
`playback-options`, and overlay-primitives paths are clean and have no delta
from pinned comparison `4bdb0e1b3370e7893a582ec80226557727832d0b` to current
HEAD. The exact upstream presentation inputs are:
`src/modules/ui/player-osd/PlayerOsdOverlay.ts`,
`src/modules/ui/player-osd/styles.surface.css`,
`src/modules/ui/player-osd/styles.content.css`,
`src/modules/ui/player-osd/styles.actions.css`,
`src/modules/ui/player-osd/styles.meta-progress.css`,
`src/modules/ui/player-osd/styles.motion.css`,
`src/modules/ui/player-osd/styles.theme.css`,
`src/modules/ui/now-playing-info/NowPlayingInfoOverlay.ts`,
`src/modules/ui/now-playing-info/styles.core.css`,
`src/modules/ui/now-playing-info/styles.content.css`,
`src/modules/ui/now-playing-info/styles.motion.css`,
`src/modules/ui/now-playing-info/styles.theme.css`,
`src/modules/ui/mini-guide/MiniGuideOverlay.ts`,
`src/modules/ui/mini-guide/styles.core.css`,
`src/modules/ui/mini-guide/styles.motion.css`,
`src/modules/ui/mini-guide/styles.theme.css`,
`src/modules/ui/channel-badge/ChannelBadgeOverlay.ts`,
`src/modules/ui/channel-badge/styles.css`,
`src/modules/ui/channel-number-overlay/ChannelNumberOverlay.ts`,
`src/modules/ui/channel-number-overlay/styles.css`,
`src/modules/ui/channel-transition/ChannelTransitionOverlay.ts`,
`src/modules/ui/channel-transition/styles.css`,
`src/modules/ui/playback-options/PlaybackOptionsModal.ts`,
`src/modules/ui/playback-options/styles.core.css`,
`src/modules/ui/playback-options/styles.motion.css`,
`src/modules/ui/playback-options/styles.theme.css`,
`src/modules/ui/common/OverlayPrimitives.ts`, and
`src/modules/ui/types/overlay-primitives.ts`. Codanna's recent index returned
no useful overlay symbols or semantic matches, so exact ownership and freshness
used the required direct-read/`rg` fallback. Fresh blob comparison proves every
enumerated scoped path is present, clean, and unchanged between the pinned and
observed-current hashes. Fresh Desktop line counts are `staticDom.ts` 298,
`routeDom.ts` 404, `focusDom.ts` 481, `rendererActionRegistration.ts` 289,
`index.ts` 782, `playerOverlayController.ts` 664, and
`styles/player-overlays.css` 735. `npm run verify:maintainability` independently
reports the same three relevant attention owners: `index.ts` 782, controller
664, and overlay stylesheet 735. Package 7 touches only the stylesheet
attention owner; `index.ts`, the controller, `focusDom.ts`, and action owners
remain frozen.

**Architecture boundary:** renderer presentation only. Package 6 behavior,
state precedence, timers, bridge effects, schedule projection, focus-return
intents, and public/process boundaries are immutable. No change is approved to
`overlays.ts`, `overlayViewModels.ts`, `playerOverlayPresentation.ts`,
`playerOverlayController.ts`, `playerBridgeSubscription.ts`,
`guidePresentationPolling.ts`, `focusDom.ts`, input/navigation/action owners,
contracts, IPC, preload, main runtime, native/helper, persistence, protocol,
dependencies, assets, or `index.ts`. Existing view models already carry all
honest channel, program, progress, status, track, error, and focus data needed
for presentation; missing artwork/metadata stays absent.

Extract the current overlay markup and rendering from `staticDom.ts` and
`routeDom.ts` into new `playerOverlayDom.ts`. That owner contains the complete
static overlay hierarchy, dynamic mini-guide and option-row DOM projection,
visibility/ARIA projection, and visual-only text formatting; `staticDom.ts`
mounts its markup inside the Player screen, as established by the Package 6
correction, and `routeDom.ts` delegates overlay rendering while retaining
route/workflow projection. The extraction must preserve the Player-screen
ancestor, native-presentation sibling, and busy-custody attributes exactly.
This is a present semantic DOM responsibility, not a forwarding wrapper.
Existing `domBindings.ts` selectors remain sufficient and unchanged.

Split the cohesive but 735-line `styles/player-overlays.css` by actual family:
it retains overlay-stack/native-surface, shared status/HUD, channel badge,
number entry, transition, loading, and terminal-error presentation; new
`player-overlay-information.css` owns OSD and now-playing; new
`player-overlay-menus.css` owns mini-guide and playback-options. `styles.css`
imports all three directly; no import-only compatibility stylesheet or old-path
shim is permitted. Move `.player-presentation .player-surface` from
`styles/shell.css` into `player-overlays.css`, and delete every obsolete
`.player-quick-actions` rule from `styles/shell.css`; retain all unrelated shell
layout, bootstrap, error, toast, exit, and responsive behavior. Move the
overlay-specific forced-color selectors for `.player-surface`,
`.now-playing-overlay`, `.mini-guide`, `.playback-options`, and
`.channel-number-overlay` out of
`styles/responsive-accessibility.css`: `.player-surface` and
`.channel-number-overlay` move to `player-overlays.css`,
`.now-playing-overlay` moves to `player-overlay-information.css`, and
`.mini-guide` plus `.playback-options` move to
`player-overlay-menus.css`; retain its global token mapping,
body/button/focus rules, and all non-overlay responsive/accessibility
selectors. Keep every selector in one owner. The
ignored capture command performs a fail-closed source ownership audit: the
native-surface selector occurs only in `player-overlays.css`, all
`.player-quick-actions` selectors are absent, and each named overlay family and
forced-color selector occurs only in its assigned owner. Each touched/new
production owner must finish below 500 lines; crossing 500 requires a compact
cohesion disposition and fresh architecture review, and crossing 800 is a
stop/replan trigger. `index.ts` receives no diff.

Adapt the unchanged upstream hierarchy and density, using Desktop-owned markup,
local tokens, and safe view models:

- OSD is a full-width bottom gradient/scrim with safe-margin information and
  right-aligned real Audio/Subtitle pill actions, a tabular metadata strip, and
  edge-to-edge played/buffered progress. It never renders Sleep, volume, mute,
  playback-rate, quality, fake track, or disabled proxy controls.
- Now-playing is a broad lower-left information shelf with title, optional
  subtitle/channel, progress/time, and up-next only. Omit poster, backdrop,
  clear-logo, badge, description, cast, actor, and summary placeholders because
  no renderer-safe runtime data exists; do not draw synthetic artwork.
- Mini-guide is the top-edge five-row shelf. Each row presents real number,
  channel name, current title/progress, optional next title, exact selected/busy
  state, and the existing input hint. Remove branding/icon placeholders.
- Playback options is a right-edge modal rail for exactly one invoking family,
  with real rows only, selected/busy/error treatment, subtitle Off when
  supplied by the frozen view model, and no duplicate inactive section or
  fabricated quality controls.
- Badge is a passive compact top-right current-channel companion; number entry
  is a compact top-right `CH` panel with editing/completed/error treatment;
  transition is a compact top-left status panel with a CSS-only spinner and
  safe channel label. Generic loading is a centered semantic status treatment;
  terminal error is a readable centered alert with only eligible Retry/Guide
  actions. Idle/ready/playing/paused/ended native baseline remains black and
  overlay-free.

Use overlay-scoped CSS custom properties for safe margins, scrim alphas, rail
width, information-shelf width/height, row density, progress thickness, and
focus treatment; do not change global base tokens. At `1280x720`, all five
mini-guide rows, the OSD metadata/actions, the full terminal panel, and the
active option rail must fit without clipping or document scroll. At
`1920x1080`, safe margins and clamped typography/panel dimensions may expand
without turning compact HUD surfaces into cards. `prefers-reduced-motion:
reduce` removes slide/entry/equalizer/spinner animation and leaves every state
visible; `forced-colors: active` supplies Canvas/CanvasText/Highlight borders,
focus, selected/busy/error, and progress differentiation without relying on
alpha, gradients, or color alone.

Preserve existing focus ids and delegated action attributes exactly. Add only
presentation semantics: active option rows expose `aria-pressed`, selected
mini-guide rows expose `aria-current`, and busy Retry/mini/options targets retain
the Package 6 native-enabled, `aria-disabled`, `aria-busy`, explicit busy-focus-
custody contract. The options rail is the single active dialog family, hidden
sections/owners are inert, and loading/transition/error/status messages retain
their live-region roles.
Keyboard, gamepad-like, pointer, Back, timer, tune, option selection, and
fullscreen behavior must remain byte-for-behavior equivalent to Package 6.

The ignored Package 7 capture harness must render these 22 distinct sanitized
Package 6 states at device scale factor 1 and exact CSS viewports `1280x720` and
`1920x1080` (44/44 screenshots): (1) native idle; (2) generic loading; (3)
buffering; (4) delayed transition; (5) retryable terminal error; (6) Retry
pending; (7) Retry inline failure; (8) destroyed/unavailable terminal error;
(9) playing OSD with two controls; (10) paused OSD with one control; (11)
now-playing with badge; (12) normal mini-guide; (13) mini-guide busy; (14)
mini-guide inline failure; (15) number editing; (16) number pending; (17) number
completed; (18) number invalid; (19) audio options selected; (20) subtitle
options with Off; (21) option busy; and (22) option inline failure. The ignored
target entry reaches them only by constructing renderer-safe
`PlayerOverlayPresentationSource`/`PlayerOverlayState` inputs and invoking the
production mount/render seams; it adds no production injection seam.

Freeze the distinct owner/eligibility/focus expectations. States 1–4 and 15–18
are focusless; number pending is locked but remains the channel-number owner.
State 5 is `playerError` with enabled Retry and Guide and exact
`overlay-player-retry` focus. State 6 keeps `playerError`, Retry visible,
native-enabled but `aria-disabled="true"` and `aria-busy="true"`, with Package
6 Retry focus custody unchanged and activation guarded; Guide remains eligible
but inactive. State 7 re-enables and refocuses Retry and
shows only the sanitized Retry failure. State 8 omits Retry and focuses the
eligible Guide action. State 9 focuses `overlay-osd-audio`, state 10 focuses its
only eligible OSD control, and both alone permit the passive badge. State 11 is
focusless with the badge. States 12 and 14 focus the selected mini row; state 13
keeps the pending selected row as the busy focus-custody target. States 19–22
have only the invoking options family: selected/Off states focus the frozen
view-model row, the busy row is native-enabled but
`aria-disabled`/`aria-busy` and activation-guarded while retaining Package 6
focus custody, and the inline-failure row is re-enabled/focused. If the current
Package 6 DOM cannot reach any of those frozen outcomes, stop and route the
contradiction to Package 6 instead of changing behavior in Package 7.

Each screenshot row asserts exact dimensions, one active semantic/modal owner,
companion-badge rules, the expectation above, no clipping/overflow,
hidden-owner inertness, no unsupported controls/placeholders/private material,
and stable raster output. The controller and reviewer visually inspect the
44-capture contact sheet and representative full-size captures against the
existing sanitized upstream reference bundle; pixel equality is not the
acceptance criterion.

Media-query proof uses Chromium DevTools Protocol through the ignored Electron
capture process: attach `webContents.debugger`, send
`Emulation.setEmulatedMedia` with one feature, wait two animation frames, run
computed semantic assertions, then send an empty `features` array and detach in
`finally`. Each row records the relevant computed values and an explicit
pass/fail disposition. Any attach/emulation/reset failure fails the command.
Reduced-motion is eight additional semantic-only runs, not screenshots:
delayed transition, normal mini-guide, number invalid, and audio-options
selected at both viewports. Each run must match `prefers-reduced-motion:
reduce`, retain the visible final owner, report no running subtree Web
Animations, report no nonzero animation/transition duration on the animated
owner/descendants, and report `none` or an identity matrix for the visible
owner's final transform.

Forced-colors is twelve additional semantic-only runs, not screenshots:
playing OSD, normal mini-guide, mini-guide busy, number invalid, Retry failure,
and option busy at both viewports. The ignored harness creates and removes
capture-only probes for `Canvas`, `CanvasText`, `Highlight`, `HighlightText`,
and `GrayText`, compares computed values rather than literal RGB strings, and
requires `forced-colors: active`. It proves Canvas/CanvasText surface/text,
Highlight/HighlightText exact focus and selected treatment, GrayText/current-
color busy treatment, Highlight/current-color error boundary, and distinct
played/buffered/track progress. Any transparent, indistinguishable, missing, or
color-only required state fails. The manifest therefore contains 44 screenshot
rows plus 20 media-semantic rows.

Actual fullscreen proof is three further semantic-only rows. For OSD, mini-
guide, and options, a fresh ignored target page mounts a renderer-safe state
(playing/two-control OSD, normal mini-guide, or subtitle-Off options), calls the
production `FocusRegistry`, `syncRendererFocusTargets`,
`focusRendererTarget`, and `renderRendererFocus` path, and first proves exact
DOM focus `overlay-osd-audio`, the encoded selected sample-channel focus id, or
`overlay-subtitle-track-off`. The mini-guide fixture uses selected channel id
`sample/channel`, making its exact encoded focus id
`overlay-mini-channel-sample%2Fchannel`. The Electron parent shows/focuses a
fresh BrowserWindow, records pre-entry bounds/CSS viewport/DPR, rejects
immediately when `isFullScreenable()` is false, calls `setFullScreen(true)`,
and requires the `enter-full-screen` event plus `isFullScreen() === true`
within 5,000 ms.
It records actual fullscreen bounds/CSS viewport/DPR without asserting a fixed
fullscreen size, reruns owner/focus/visibility/z-order/native-non-tab-stop/
hidden-owner assertions, calls `setFullScreen(false)`, and requires the
`leave-full-screen` event plus false state within 5,000 ms before rerunning the
same assertions and requiring restored window bounds, content bounds, CSS
viewport, and DPR to equal their recorded pre-entry values. A rejected command,
missing event, timeout, unsupported fullscreen, focus loss, owner change, hidden focus,
z-order failure, dimension-read failure, or cleanup/reset failure fails closed.
Each owner uses a new window; `finally` leaves fullscreen if necessary, resets
media emulation, detaches the debugger, removes listeners, destroys the window,
and verifies no retained window. The complete manifest has 67 result rows: 44
screenshots, 20 media-semantic runs, and three fullscreen runs.

This is local Electron renderer/fullscreen continuity proof only. It supplements
`npm run smoke:electron`; it does not exercise the production bridge/native
video and cannot replace or claim RD-27 Windows proof. Package 7's platform-
proof label is `Mac/local automated proof sufficient; Windows operational proof
deferred to RD-27` because this unit changes renderer DOM/CSS only.

Focused tests:

`node --import tsx --test src/__tests__/renderer/overlays.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/rendererActionRegistration.test.ts src/__tests__/renderer/rendererRuntimeOwners.test.ts`

Update the five tests only where required to prove stable public DOM/focus
outcomes: exact semantic owner hierarchy; unsupported placeholder/control
absence; one active option family; selected/busy/error ARIA projection; dynamic
row focus ids; pointer/OK equivalence; hidden-owner exclusion; and exact
fullscreen focus continuity. Do not restate CSS declarations or private helper
order in tests. The ignored proof command is
`node docs/runs/complete-webos-ui-parity-reopen/capture-package-7.mjs`; it must
produce 44 captures, 20 media-semantic results, three fullscreen results, the
contact sheet, and the 67-row `package-7-target-manifest.json` under the ignored
run bundle.

This unit materially adapts current upstream overlay hierarchy/density/motion
patterns even though no verbatim source, tests, or assets are planned. Add a
new exact Package 7 row to `docs/architecture/import-ledger.md` using pinned
`4bdb0e1b3370e7893a582ec80226557727832d0b`, observed-current
`a1a7ea7dcb1cfc8aee7cfcf88cf5a1dac718bf30`, and every exact upstream TS/CSS
path enumerated in the freshness paragraph above. The exact Desktop
destinations are `src/renderer/playerOverlayDom.ts`,
`src/renderer/staticDom.ts`, `src/renderer/routeDom.ts`,
`src/renderer/styles.css`, `src/renderer/styles/player-overlays.css`,
`src/renderer/styles/player-overlay-information.css`,
`src/renderer/styles/player-overlay-menus.css`,
`src/renderer/styles/shell.css`, and
`src/renderer/styles/responsive-accessibility.css`. The row must also name
Apache-2.0 provenance, omitted runtime/artwork/control/theme behavior, the five
focused tests, 67-row proof, no copied tests/assets, and the revisit trigger.
Both upstream primitive sources—`src/modules/ui/common/OverlayPrimitives.ts`
and `src/modules/ui/types/overlay-primitives.ts`—are mandatory row inputs; the
worker may not collapse them into a wildcard or omit either one.
Do not rewrite the historical RD-24 row or leave path selection to the worker.
If implementation copies an asset or source outside that recorded slice, stop
and re-review scope.

After implementation, run the focused command, `npm run typecheck`,
`npm run verify:architecture`, `npm run verify:maintainability`,
`npm run verify:redaction`, `npm run build:electron`,
`npm run smoke:electron`, the ignored capture command, `npm run verify:docs`,
`npm run verify`, and `git diff --check`. Require a fresh independent
implementation `reviewer` for visual fidelity, responsive/accessibility proof,
import-ledger accuracy, Package 6 behavior preservation, owner cohesion, and
YAGNI. Stop/replan for any unlisted file, view-model/state/behavior change,
global-token or asset change, public/process-boundary change, dependency, fake
artwork/action, unreachable or unsanitizable state, scoped upstream change,
or proof failure that cannot be corrected inside this presentation seam.

The refreshed reviewed-target packet is
`docs/runs/complete-webos-ui-parity-reopen/package-7-execution-packet.md`; it
includes the corrected-HEAD baseline and both primitive paths in freshness,
provenance, and exact import-ledger planning. At planning handoff, Package 7 was
blocked only on that refreshed exact plan receiving clean independent plan
review, not on the deferred RD-27 Windows audit; that plan review passed before
implementation began.

**Closeout result (2026-07-15):** the reviewed worker implementation extracted
the complete Player overlay markup/projection into `playerOverlayDom.ts`, split
the former stylesheet hotspot into shared, information, and menu owners, and
adapted the exact 28-source upstream slice into the nine planned Desktop
destinations without changing Package 6 behavior, state, focus, action, timer,
bridge, input, or public/process ownership. The five-file focused suite passed
52/52; typecheck, architecture/lint, maintainability, redaction, build, Electron
smoke, docs, full verification, and `git diff --check` passed. Full verification
reported 823/823 source-contract tests and 135/135 harness/docs tests. The
ignored proof passed 44/44 exact-viewport screenshots, 8/8 reduced-motion rows,
12/12 forced-colors rows, and 3/3 actual BrowserWindow fullscreen rows (67/67),
with matching raster dimensions/hashes and no retained process or temporary
profile. Independent implementation review found focused/busy contrast and a
forced-colors owner-surface proof gap; both were corrected inside the approved
CSS/proof seam, the complete bundle was regenerated, and targeted independent
re-review found both resolved with no material regression. This local Mac
automated proof supplements Electron smoke only and does not replace or claim
the binding RD-27 Windows physical-click/fullscreen audit. Package 8 is
unblocked.

### Package 8 — Integrated proof and closeout

**Role:** `worker` for bounded evidence/docs; route defects back to their owner.

Recapture every required state at both viewports and player/overlay states in
fullscreen. Complete the interaction matrix with no unknown cells, scan the
local proof bundle for private material, run all final gates, obtain integrated
independent review, and correct roadmap/current-state/renderer/security/proof/
parity/divergence/import-ledger docs, including the Package 6 Info replacement
divergence. Archive this plan and unblock a fresh RD-27 plan after renderer
parity and local automated verification close. Package 8 must state that
Package 6 operator-assisted fullscreen platform proof remains a binding RD-27
Windows gate; it cannot claim complete platform parity or a complete Package 6
29-row proof.

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
2. `feat(renderer): bind player overlays to runtime state` — amend the local,
   unpushed checkpoint with the focus-custody correction only after clean review
   and current proof; otherwise use controller-adjudicated separate correction
   commit without rewriting shared history.
3. `feat(renderer): complete webos overlay presentation parity`
4. `docs: close complete webos ui parity proof`

Exact model and reasoning-effort settings come only from the selected role's
`config_file` mapping in `.codex/config.toml` and its corresponding
`.codex/<config_file>` TOML. The controller uses
`lineup-desktop-feature-quality-loop`; Packages 5–8 default to `worker`; each
package uses a fresh `reviewer` when its review gate is met.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-review
TASK: Review refreshed Package 7 under the Package 6 proof exception
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-07-10-complete-webos-ui-parity-reopen-plan.md
ARTIFACT: docs/runs/complete-webos-ui-parity-reopen/package-7-execution-packet.md
FILES:
- docs/plans/2026-07-10-complete-webos-ui-parity-reopen-plan.md
- docs/runs/complete-webos-ui-parity-reopen/package-7-execution-packet.md
BLOCKERS: Package 7's corrected-HEAD baseline/provenance refresh is complete;
clean independent plan review is still required. The deferred RD-27 Windows
audit does not block renderer implementation.
MESSAGE: Review only the refreshed Package 7 section and ignored execution
packet against corrected HEAD 26a1bbc. Prioritize exact presentation-only scope,
Package 6 ancestry/native-enabled busy-custody preservation, both upstream
overlay primitive paths, 67-row proof, import-ledger specificity, worker-only
eligibility, and the binding RD-27 Windows nonclaim. Return findings first and
do not edit files.
