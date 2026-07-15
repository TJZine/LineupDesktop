# Complete WebOS UI Parity Reopen Plan

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3
**Current execution unit:** Package 7 — Player overlay visual surfaces planning
and review is next and unstarted. Package 6 — Runtime player and overlay state
machine is implemented, controller-verified, and independently clean-reviewed.
Package 5 — Scheduler-backed Guide parity remains closed with full verification,
exact-viewport evidence, and clean read-only adversarial re-review. The
source-proven pre–Package 5 remediation and the 2026-07-15 suggestion-reviewed
correction remain closed. Packages 0–4 remain closed at their corrected
checkpoints; RD-27 remains blocked until Packages 7–8 close.

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
the Package 6 files named below. Local execution/evidence artifacts stay under
the ignored `docs/runs/complete-webos-ui-parity-reopen/` bundle. Package 7 must
be promoted to the same exact-file standard before it becomes current. Package
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
parity/divergence/import-ledger docs, including the Package 6 Info replacement
divergence. Archive this plan and unblock a fresh RD-27
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
TASK: Plan and review Package 7 — Player overlay visual surfaces
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-07-10-complete-webos-ui-parity-reopen-plan.md
BLOCKERS: Package 7 implementation is blocked on a fresh exact-file plan and
clean independent plan review; RD-27 remains blocked pending Packages 7–8.
MESSAGE: Load the active plan and current Package 6 checkpoint, run the bounded
Desktop/upstream freshness and architecture-health audit, then route Package 7
through the configured planner and a fresh read-only reviewer. Promote only
Package 7 to exact files, supported visual behavior, proof, and stop conditions;
do not implement until that refreshed scope receives clean plan review.
