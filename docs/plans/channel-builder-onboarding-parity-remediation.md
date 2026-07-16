# Channel Builder Onboarding Parity Remediation

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3

## Goal

Make first-run, Guide, Settings, and empty-player entry reach a real Desktop-safe
channel builder whose choices, planning results, build semantics, recovery, and
focus behavior match the current upstream Lineup channel-setup workflow closely
enough to unblock meaningful manual visual and product QA.

The supported builder is a three-step journey:

1. choose eligible movie/show libraries;
2. configure and preview strategies; and
3. review when rerunning, build with observable progress/cancel behavior, then
   show the committed result.

The strategy surface is not decorative. It must drive the main-owned plan and
persisted channels for collections, playlists, recently added, genres,
directors, decades, studios, and actors; per-library or mixed scope where the
upstream strategy supports it; replace, append, and merge; actor/studio combine;
alternate lineups; base and variant series ordering; maximum/minimum limits;
and strategy priority as generated Guide order.

## Non-Goals

- Do not port the upstream browser/WebOS application shell, storage, transport,
  scheduler composition root, or module paths.
- Do not expose Plex tokens, server connections, raw payloads, endpoint URLs,
  app paths, persisted records, or transport retry policy to preload or the
  renderer.
- Do not add fake-backed, display-only, or disabled controls for unsupported
  behavior. A visible control must affect preview, review, and commit.
- Do not redesign custom-channel editing, player playback, the EPG scheduler,
  installers, signing, updates, native-helper packaging, or RD-27's broader
  Windows playback audit.
- Do not claim full visual parity or release readiness from local screenshots;
  this plan supplies the builder needed to begin the later manual audit.
- Do not add dependencies, compatibility barrels, old upstream path shims,
  browser storage, or a generic RPC/service framework.

## Architecture And Invariants

### Evidence and selected adaptation

Direct reads and `rg` were used because no useful Codanna index was available in
this Windows checkout. The current Desktop owners inspected were
`src/contracts/channel.ts`, `src/main/channel/channelRuntime.ts`,
`src/main/channel/channelComposition.ts`, `src/main/channel/channelIpc.ts`,
`src/main/channel/plexLibraryMinimalAdapter.ts`, `src/main/plex/livePlexTransport.ts`,
`src/domain/channel/**`, `src/preload/channelSetupBridge.cts`,
`src/renderer/setup/**`, `src/renderer/settingsSetup.ts`,
`src/renderer/rendererActionRegistration.ts`, and `src/renderer/index.ts`.

Upstream evidence was read at commit
`a1a7ea7dcb1cfc8aee7cfcf88cf5a1dac718bf30`; the scoped upstream
`src/core/channel-setup/**`, `src/modules/ui/channel-setup/**`, and
`src/styles/shell.onboarding.setup.css` paths were clean. The controlling
behavior is in upstream `ChannelSetupConfig`, `normalizeChannelSetupConfig`,
`ChannelSetupPlanningService`, `ChannelSetupPlanner`,
`ChannelSetupBuildCommitter`, the facet snapshot owners, and the channel-setup
session/step/focus owners.

Desktop already models library, collection, playlist, show, mixed, filter,
sort, block, replica, and playback-variant channels in
`src/domain/channel/types.ts`, and `ChannelRepository.saveStoredChannelData`
already persists one complete `StoredChannelData` snapshot through the atomic
Desktop file adapter. Therefore adapt the upstream normalization, planning,
identity/diff, allocation, and commit policies into focused Desktop owners.
Do not import the upstream workflow facade or UI runtime wholesale. The Desktop
implementation must depend on its existing injected Plex/domain/persistence
seams and renderer focus/navigation model.

### Process and owner boundaries

- `src/contracts/channel.ts` owns renderer-safe setup vocabulary: normalized
  config inputs, preview estimates/warnings/status, review diff summaries,
  progress/result/cancel states, setup record summary, errors, and IPC results.
  Config values are selected library ids, enums, booleans, bounded numbers, and
  priorities only. Unlike upstream's internal config, the renderer-facing
  `ChannelSetupConfig` contains no server/profile id; main binds it to the
  currently active context and persists those context ids outside `config`.
- Pure deterministic normalization, strategy candidate construction,
  identity/diff, priority-balanced allocation, alternate-lineup expansion, and
  series-variant expansion live under `src/domain/channel/setupPlanning/**`.
  They accept typed facet snapshots and existing `ChannelConfig` values; they
  import no Electron, Node, main, preload, renderer, transport, persistence, or
  browser owner.
- A focused main-owned `src/main/channel/setup/**` workflow owns active Plex
  context validation, facet loading, snapshot invalidation, preview/review,
  build cancellation/generation custody, content validation, atomic commit,
  setup-record persistence, sanitized errors, and progress publication.
- `src/main/plex/livePlexTransport.ts` and a focused setup facet adapter own the
  privileged Plex calls needed for video playlists, per-library collections,
  tag directories/counts, and bounded item scans. These values never cross IPC
  as raw Plex objects.
- `src/main/channel/channelComposition.ts` and `channelIpc.ts` wire the focused
  setup owner. They do not absorb planning policy. Electron main continues to
  supply app-owned paths and lifecycle cleanup.
- Preload exposes explicit validated methods (`getStatus`, `getRecord`,
  `preview`, `review`, `build(input, onProgress)`, and `cancelBuild`) and no
  broad invoke passthrough. Runtime guards reject mismatched request ids,
  unknown states, unsafe ids/numbers, and forbidden keys before renderer
  delivery.
- Renderer setup session/controller/presenters own ephemeral draft state,
  three-step composition, focus, keyboard/remote/pointer behavior, preview
  debounce, visible progress, cancel intent, return custody, and safe copy.
  Renderer code never plans channels, calls Plex directly, or persists config.
- The setup record is a separate versioned main-owned app-data file at
  `<userData>/persistence/lineup-desktop-channel-setup.json`, resolved by
  `src/main/persistence/appDataPaths.ts`. Schema version 1 is exactly
  `{ schemaVersion: 1, records: Array<{ profileId: string, serverId: string,
  config: ChannelSetupConfig, createdAtMs: number, updatedAtMs: number }> }`.
  Records are unique by active profile id plus selected server id; neither id is
  returned to the renderer. The selected record is projected to a renderer-safe
  config summary only after the active main-owned context matches. Writes use
  the existing temp-file/rename/mode-`0o600` pattern and a serialized mutation
  queue. Missing means no prior record. Invalid JSON/schema is `corrupt`; a
  numeric schema greater than 1 is `unsupported-version`. Neither state is
  overwritten automatically. There is no browser-storage migration and no
  plaintext secret fallback.

### IPC and build-operation protocol

The channel literals added to `src/contracts/ipc.ts` are exact:

- `lineup:channelSetup:getRecord`
- `lineup:channelSetup:preview`
- `lineup:channelSetup:review`
- `lineup:channelSetup:build`
- `lineup:channelSetup:cancelBuild`
- `lineup:channelSetup:progress`

`lineup:channelSetup:getStatus` remains. The former
`lineup:channelSetup:commit` path is removed after P4 has no caller; it must not
remain as a second build policy. Every invoke request is
`{ requestId, payload }`, and every invoke reply is the existing
`{ ok, requestId, value | error }` result envelope. `getRecord` has an empty
payload and returns exactly one of `missing`, `ready`, `corrupt`,
`unsupported-version`, or `unavailable`; only `ready` carries the safe selected
config. `preview` and `review` carry `{ config }`. `build` carries
`{ buildId, config, confirmReplace }`; the unprivileged renderer creates the
bounded `buildId`. Preload's `build(input, onProgress)` creates and locally
retains `buildRequestId`, attaches the per-build progress listener before
invoking main, invokes `build` with that same value as `requestId`, and removes
the listener in `finally`. `cancelBuild` carries
`{ buildId }` and returns `{ buildId, status }`, where status is `accepted`,
`too-late`, or `not-active`.

Main permits one active build per authorized sender `webContents.id` and holds
`{ senderId, buildId, buildRequestId, phase, abortController, sequence }` until
terminal cleanup. A second build from that sender fails with
`CHANNEL_BUILD_ACTIVE`. Each sender also owns a lifetime set of accepted build
ids. Reuse of an active or completed id fails with `CHANNEL_BUILD_ID_REUSED`;
after 1,024 unique ids, further builds fail with `CHANNEL_BUILD_ID_CAPACITY`
until that sender is destroyed, rather than evicting ids and accepting a stale
reuse. Cancel is accepted and idempotently sets abort only for
the same sender/build before `apply_channels`; the build promise later resolves
`canceled`. Cancel is `too-late` from the start of `apply_channels` until the
terminal build reply, and `not-active` for a wrong id or a cleared/terminal
operation. A cancel reply is never itself presented as the terminal build
result.

Progress is sent only to the initiating authorized sender as
`{ buildId, buildRequestId, sequence, progress }`. Sequence starts at 1 and is
strictly increasing; progress carries the frozen task/current/total/label/detail
shape and never carries terminal state. The per-build preload listener validates
the complete envelope and invokes the supplied renderer callback only when both
`buildId` and `buildRequestId` exactly equal its locally held values. Reused-id,
wrong-request, late, and stale events are ignored. Route leave marks the
renderer generation stale and requests pre-apply cancel for its build id; the
preload listener remains owned by the build promise and is removed in its
`finally`, even if the callback is no longer rendered. Sender destruction,
profile/server change, sign-out, main teardown, and app shutdown abort pre-apply
work and remove sender/build custody; no progress is sent to destroyed contents.
The terminal `build` invoke reply clears the active entry in `finally` and is
the only terminal source for renderer state.

### Product semantics frozen for implementation

- Strategies and default order are playlists, collections, recently added,
  genres, studios, actors, decades, directors. All start enabled. Collections,
  recently added, and decades are per-library only. Genres, directors, studios,
  and actors may toggle between per-library and cross-library/mixed scope.
  Playlists are selected-server/global video
  playlists: each eligible playlist contributes at most one candidate and is
  not duplicated per selected library or offered a scope toggle.
- Planning order is exact and shared by preview, review, and build: construct
  the ordered base strategy candidates with their known/unknown eligible-item
  counts; normalize base series playback; expand alternate replicas; expand
  series playback variants; apply `minItemsPerChannel` to every expanded
  candidate using its inherited base eligibility; then run priority-balanced
  allocation and the global `maxChannels` generated-plan cap. Expansions
  therefore consume the cap and are represented in min/cap drop counts. Tests
  must cover a small cap with both alternates and variants enabled and prove the
  same selected identities/order across preview, review, and build.
- Alternate lineup expansion emits the base at replica index 0 followed by 1-3
  deterministic copies only for non-sequential candidates other than actor and
  director strategies. Series variant expansion runs over that expanded list,
  emits no duplicate when base mode/block already matches, restricts sequential
  variants to replica index 0, and may emit block variants for eligible replica
  rows. Series base mode is shuffle, sequential, or block (size 2-5); variant is
  none, sequential, or block (size 2-5). These map to existing replica,
  playback, seed, block, and variant fields.
- `maxChannels` is the upstream cap on the post-expansion, post-min generated
  candidates selected by priority-balanced round robin; it is not a cap on the
  final persisted lineup. Preview reports `eligibleGeneratedCount`,
  `selectedGeneratedCount`, and `droppedByPlanCapCount`, with
  `reachedMaxChannels` true exactly when `droppedByPlanCapCount > 0`. Replace
  therefore finishes with at most `maxChannels` generated channels. Append and
  merge may finish above `maxChannels` because existing channels are preserved;
  creation is additionally bounded by currently free channel numbers. Build
  results separately report `plannedGeneratedCount`, `createdCount`,
  `updatedCount`, `preservedCount`, `removedCount`, `skippedCount`,
  `reachedMaxChannels`, and `channelNumberCapacityExhausted`; number exhaustion
  is true only when an unmatched selected candidate cannot receive a free valid
  channel number.
- Actor/studio `separate` creates eligible sources independently. `combined`
  groups the same actor/studio across all available selected-library sources
  and creates one mixed source even when only one media family or one selected
  source contributes; it never requires both movie and show input. Combined +
  per-library scope uses sequential mixing, while cross-library scope uses
  interleaving, matching the upstream planner.
- Preview returns estimates and warnings without mutation. Existing-setup
  reruns additionally require review containing created/removed/unchanged
  counts and bounded safe-name samples. Preview/review results are keyed to the
  normalized draft; stale completions may not replace a newer draft.
- Canonical setup identity is a stable serialization of normalized
  `contentSource`, sorted `contentFilters`, `sortOrder`, `lineupReplicaIndex`
  (default 0), `isPlaybackModeVariant`, and—only for a playback variant—the
  variant playback mode plus block size when block. It intentionally ignores
  channel id, name, and base-channel playback mode. Existing generated channels
  are indexed by identity in current lineup order as FIFO queues; planned rows
  consume at most one queued match apiece, so duplicates match one-for-one and
  never collapse. Append skips consumed planned matches and leaves the existing
  generated row unchanged. Merge preserves each matched generated row's id and
  number while updating its current generated name/content/playback/filter/sort/
  replica/variant policy; a generated rename therefore matches rather than
  duplicating. Custom channels are excluded before queues are built. Tests must
  cover rename, duplicate FIFO consumption, replica distinction, variant mode/
  block distinction, base-playback-mode ignorance, and custom non-matching.
- Replace plans a fresh generated lineup and, after explicit confirmation,
  removes every existing channel including custom channels before committing
  the generated result. Append preserves every existing channel and adds only
  unmatched planned identities. Merge preserves every unmatched channel,
  updates matched generated channel policy in place, and adds unmatched planned
  identities. Append/merge identity matching excludes
  `isAutoGenerated !== true`, so custom channels are never matched, renamed, or
  updated by setup. Existing current-channel custody is preserved when its id
  survives; otherwise select the lowest resulting number.
- No build mutates persisted channels before `apply_channels`. The authoritative
  commit is one complete `StoredChannelData` write through
  `ChannelRepository.saveStoredChannelData`; the existing
  `DesktopChannelPersistenceStore.writeStoredChannelData` updates the snapshot
  and current-channel pointer in the same temp-file/rename mutation. The setup
  workflow must not follow it with a separate `saveCurrentChannelId` write.
  Cancel before
  that boundary yields `canceled` and no channel/config-record mutation. Once
  atomic apply begins, cancel is acknowledged as too late and the renderer must
  await the terminal committed/failed result; it must not falsely show a
  canceled build. A channel-snapshot write failure is a pre-commit failure and
  leaves the prior on-disk channel snapshot authoritative. After a successful
  channel snapshot commit, write the setup record. Record-write failure does
  not roll back channels across files: return `committed-with-record-warning`,
  leave the prior/missing record intact, and allow a recoverable rerun using the
  committed channels plus defaults. Guide refresh runs after that record-write
  attempt and is independently represented in the terminal summary.
- Post-commit Guide work uses a new
  `GuideRuntime.refreshAfterChannelSetupCommit()` method in
  `src/main/channel/guideRuntime.ts`. It clears the Guide content resolver cache,
  loads the already-committed snapshot once, selects the committed current
  visible channel (or an in-memory visible fallback), resolves its content, and
  directly reloads or unloads `activeChannelScheduler`. It is refresh-only: it
  must not call `tuneChannel`, `saveStoredChannelData`, `saveCurrentChannelId`,
  or `onChannelTuned`, and it must not start playback. A failure becomes the
  nested Guide refresh warning after the authoritative channel result. Focused
  repository/store call-count tests must prove one `writeStoredChannelData` and
  zero `writeCurrentChannelId` calls for the entire successful setup commit plus
  Guide refresh; the Guide-only test must prove zero repository writes. Existing
  user-initiated `tuneChannel` persistence behavior remains unchanged.
- Progress uses the upstream task vocabulary: fetch playlists, fetch
  collections/facets, scan library items, build pending, create channels, apply
  channels, refresh Guide, done. Progress is monotonic within a task and bound
  to one build id. A terminal result records created, skipped, cap reached,
  error count, cancellation, commit state, safe warnings, and Guide-refresh
  outcome. The terminal build kind is `canceled`, `failed`, `committed`, or
  `committed-with-record-warning`; Guide refresh is a nested completed/failed/
  interrupted result and does not rewrite the commit kind. Guide refresh
  failure/interruption is reported after a committed
  lineup and is not mislabeled as a rolled-back channel build.
- Settings rerun enters from `settings-open-channel-setup`; Guide rerun enters
  from `guide-state-setup`; empty Player enters from `player-setup-reminder`.
  Entry first resolves the current Plex target: signed-out/auth-failed goes to
  account link, signed-in without an active profile goes to profile selection,
  active profile without a selected server goes to server selection, and only
  signed-in + profile + selected server enters the staged library lifecycle.
  This target resolution is independent of configured-channel count for a
  Settings/Guide rerun. Every target synchronously increments the generation,
  resets stale staged/runtime state, and captures origin route/focus before
  activating/rendering `channelSetup`. Only the library target additionally
  sets library stage/owner/loading before activation and then awaits the load;
  ready/empty/error plus focus apply only when its generation and server still
  match. A null server must never produce an idle visible workspace. Rerun entry
  uses `enteredFromServer=false`; advancing account/profile/server to library
  preserves that flag and the original custody. Server-origin first-run entry
  uses `enteredFromServer=true` and library Back returns to server selection.
  No route-only transition may leave a stale or uninitialized owner.
- Rerun Back custody is exact. From library, Back closes directly to the
  captured origin/focus. From server, Back moves to profile while retaining
  origin custody; the next profile Back closes to origin. From profile, Back
  closes to origin. Auth waiting/error first returns to the auth-link owner;
  Back from auth-link closes to origin. Required first-run account/profile
  owners remain contained rather than exposing Player; server Back still moves
  to profile. Done always restores Settings/Guide/Player and respectively
  `settings-open-channel-setup`, `guide-state-setup`, or
  `player-setup-reminder` after the destination DOM is active.
- Focus graphs are explicit per step/category/dropdown/review/progress/result.
  Hidden/inert/disabled controls are excluded; modal/dropdown focus is trapped
  and restored; subscriptions, timers, abort controllers, and progress
  listeners are disposed on route leave, server/profile change, sign-out, and
  window unload. Reduced-motion and forced-colors behavior stays supported.

### Architecture health disposition

`src/main/channel/channelRuntime.ts` is 450 lines and would exceed the attention
threshold if planning were added. Decision: **extract** the distinct setup
planning/build lifecycle into `src/main/channel/setup/**`; retain the existing
repository/status role and avoid a forwarding-only service.

`src/main/channel/channelIpc.ts` is 408 lines. Decision: **extract** setup IPC
registration/validation into `src/main/channel/channelSetupIpc.ts`; keep guide
and existing channel wiring separate.

`src/preload/index.cts` is 1,854 lines and is a composition root constrained by
sandboxed preload bundling. Decision: **cohesive composition only**; add channel
constants/bridge wiring there while all validation/method behavior stays in
`channelSetupBridge.cts` and `channelBridgeGuards.cts`. It requires fresh
architecture review.

`src/renderer/index.ts` is 800 lines and a named composition root. Decision:
**extract** the entry/return lifecycle and setup session composition into
focused renderer owners; `index.ts` only wires them. It requires fresh
architecture review.

No production owner may be split merely to reduce line count. Any touched owner
over 500 lines, all named composition roots, and any new owner that combines
unrelated UI, transport, planning, and persistence responsibilities require a
fresh architecture disposition and independent review.

## Files In Scope

Current exact first package (P0):

- `src/renderer/index.ts`
- `src/renderer/startupRouting.ts`
- `src/renderer/plexRuntimeDom.ts`
- `src/renderer/plexRuntimeState.ts`
- `src/renderer/plexRuntimeActions.ts`
- `src/renderer/setup/setupComposition.ts`
- new `src/renderer/setup/setupEntryLifecycle.ts`
- `src/main/smokeAssertions.ts`
- new `src/main/smokeSetupAssertions.ts`
- new `src/__tests__/renderer/setupEntryLifecycle.test.ts`
- `src/__tests__/renderer/startupRouting.test.ts`
- `src/__tests__/renderer/setupRuntimeCoordinator.test.ts`
- `src/__tests__/renderer/rendererActionRegistration.test.ts`
- `src/__tests__/renderer/rendererRuntimeOwners.test.ts`
- `src/__tests__/renderer/plexRuntime.test.ts`
- new `src/__tests__/main/smokeSetupAssertions.test.ts`

Approved later-package owners, to be reconfirmed against source before each
package:

- `src/contracts/channel.ts`, `src/contracts/ipc.ts`, `src/contracts/shell.ts`
- `src/domain/channel/setupPlanning/**`, `src/domain/channel/types.ts`,
  `src/domain/channel/index.ts`
- `src/main/plex/livePlexTransport.ts`,
  `src/main/plex/desktopPlexRuntime.ts`,
  `src/main/plex/library/**`, and new focused
  `src/main/channel/setup/desktopPlexSetupFacetSource.ts`
- `src/main/channel/channelRuntime.ts`, `channelComposition.ts`,
  `channelSetupIpc.ts`, `guideRuntime.ts`, and `setup/**`
- `src/main/persistence/appDataPaths.ts`, new
  `src/main/persistence/desktopChannelSetupRecordStore.ts`, and path/runtime
  wiring in `src/main/channel/channelComposition.ts`
- `src/preload/channels.cts`, `channelSetupBridge.cts`,
  `channelBridgeGuards.cts`, `index.cts`
- `src/renderer/channelRuntimeActions.ts`, `channelRuntimeState.ts`,
  `setup/**`, `staticDom.ts`, `domBindings.ts`,
  `rendererActionRegistration.ts`, `index.ts`, and
  `styles/setup-workflow.css`
- focused tests under `src/__tests__/contracts/**`,
  `src/__tests__/domain/**`, `src/__tests__/main/**`,
  `src/__tests__/preload/**`, and `src/__tests__/renderer/**`
- `tools/smoke-electron.mjs` and its test only if the existing injected/safe
  smoke route cannot exercise a signed-in selected-server builder journey
- `docs/architecture/import-ledger.md`, `CURRENT_STATE.md`,
  `original-lineup-reference-compatibility-matrix.md`, and
  `original-lineup-divergence-register.md`

## Files Out Of Scope

- `C:/Software/Lineup/**` (read-only evidence; never edit)
- `src/main/player/**`, `src/native-helper/**`, and playback contracts
- custom-channel product behavior outside integration with the setup result
- `src/domain/scheduler/**` except invoking its existing Guide refresh seam
- settings fields unrelated to the builder entry
- packaging, installer, signing, update, dependency, and lockfile files
- generated `dist/**`, `out/**`, raw screenshots, raw Plex payloads, tokens,
  support bundles, local app-data files, or other private evidence
- historical completed plan bodies or unrelated roadmap work

## Execution Packages

### P0 — Repair rerun entry and focus custody (first package)

`IMPLEMENTER_ROLE_ELIGIBILITY: worker`

Use the exact P0 files listed above. Add one renderer entry owner that accepts
origin route, invoker focus id, and server-origin flag. Before choosing a DOM
owner it resolves the Plex snapshot to account, profile, server, or library
using the exact rules above. Its common synchronous prefix increments the
generation, resets staged/runtime state, and captures return custody. Account,
profile, and server targets set their onboarding stage/focus and visibly
activate/render `channelSetup` without starting `enterLibrary`; profile/server
may then start their existing generation-safe profile/discovery work. Only the
fully eligible library target sets library stage/owner/loading, starts the
library request, activates/renders immediately, and awaits the generation-gated
completion. Route Settings, Guide, and empty-Player actions through it. Preserve
the same resolution/order for confirmed-empty startup. On Back/Done, apply the
frozen rerun/first-run hierarchy and restore the captured route/exact invoker
focus only after the destination DOM is active. Ignore stale completions after a
second entry, route leave, profile/server change, or teardown.

`createRendererRoutingCoordinator` in `src/renderer/startupRouting.ts` must
receive and invoke this same entry lifecycle as its only setup target. For
confirmed-empty startup and `openPlayerSetupReminder`, the coordinator passes
the current Plex snapshot and exact custody to the lifecycle; it does not assume
library eligibility. The lifecycle performs common reset/custody, resolves the
target, and activates the correct account/profile/server owner or performs the
library loading prefix before route render and generation-gated await. The
coordinator must not set the setup route directly, call the old async setup
entry in parallel, or own a second target/focus/default policy.

`readPlexOnboardingState` in `src/renderer/plexRuntimeDom.ts` must share the
same auth-failure classification used by setup-target resolution. At account
stage, a signed-in snapshot whose `lastError.code` is `PLEX_AUTH_REQUIRED`,
`PLEX_AUTH_INVALID`, `PLEX_UNAUTHORIZED`, `PLEX_PIN_EXPIRED`, or
`PLEX_PIN_TIMEOUT` renders the
`auth-error` owner, never `profile-select`. The visible error uses the existing
renderer-safe `errorText` or fixed generic sign-in-attention copy when that is
null; it never projects a raw `lastError` message or payload. A normal signed-in
snapshot without an auth-failure code continues to render `profile-select` at
account/profile stage, and server/library projection remains unchanged. Keep
one shared predicate/target classifier within the approved P0 renderer files so
routing and visible-owner behavior cannot drift.

Update the existing `channel setup plex flow content` assertion in
`src/main/smokeAssertions.ts`; do not change `tools/smoke-electron.mjs` in P0.
Replace the retired `.channel-setup-commit`, `.setup-rail`,
`[data-setup-section]`, legacy commit-action-count, and legacy setup copy checks
with current semantic owners. Evaluate the final DOM after the smoke clicks
Settings -> Channel setup. The normal signed-out smoke fixture passes only when
the visible
`[data-onboarding-host]` exposes the auth-link owner and request-PIN control.
A staged authenticated/selected-server state passes only when
`[data-setup-workspace]` is visible, the document owner is `library`, the
visible/non-inert `[data-staged-owner="library"]` is active, the library status
is loading or a non-error ready/empty state (never idle),
`[data-plex-sections]` exists, and
the Select All, Clear All, Next, and Back flow controls exist. Continue rejecting
the already-retired `[data-setup-steps]`, `[data-channel-draft-list]`, and
`[data-setup-validation]` owners. Do not require future P1-P4 strategy controls,
inject product fake state, or broaden acceptance to a recovery/error owner.

Keep one dependency-free projection/evaluator for those semantics in new
`src/main/smokeSetupAssertions.ts`. `src/main/smokeAssertions.ts` imports it for
the injected browser assertion, while the focused test imports the pure owner
directly without loading Electron or `src/main/protocol.ts`; do not maintain a
second test-only selector policy and do not refactor protocol ownership. The new
`src/__tests__/main/smokeSetupAssertions.test.ts` must cover signed-out auth,
staged library loading, staged library ready/empty, hidden/inert/wrong owner,
idle/error/recovery, missing current flow controls, and obsolete-selector
rejection. The real standalone Electron smoke, not this pure projection test,
owns proof that the post-click signed-out fixture reaches the auth owner.

Tests must assert the ordering (loading + stage set, route rendered before the
library promise settles), pointer/focused activation from all three rerun
entries, account/profile/server target selection, null-server never entering an
idle library workspace, server-origin behavior, repeated entry reset, stale
async completion, hierarchical Back, and exact return focus.
`src/__tests__/renderer/startupRouting.test.ts` must
exercise the real coordinator dependency path for both confirmed-empty startup
and player reminder/rerun across all four Plex targets, asserting non-library
targets render the correct onboarding owner without a library call and the
eligible library prefix occurs before route activation/render with completion
afterward. `src/__tests__/renderer/plexRuntime.test.ts` must prove a signed-in
auth-failure snapshot at account stage selects and renders `auth-error` with
sanitized/generic copy and no raw failure material, while a normal signed-in
snapshot still selects `profile-select`; retain the existing server/library
projection cases. Do not add strategy controls or cross-process behavior in P0.

Back from a recognized `auth-error`/`auth-waiting` owner must invoke one
explicit renderer-local auth-link transition owned by
`src/renderer/plexRuntimeState.ts` and exposed through the existing controller
in `src/renderer/plexRuntimeActions.ts`. It invalidates pending renderer PIN
work, cancels an active PIN when present, clears renderer `lastError` and safe
error text, and projects the renderer snapshot to the signed-out auth-link
owner without changing persisted main-process credentials. It must not consume
selected-library or selected-server Back layers. The next rerun Back closes to
the captured origin; first-run remains contained. Integrated controller
coverage must prove that hierarchy and the absence of server/section clearing.

P0 is accepted only when the focused renderer tests, the focused setup-smoke
projection test, `npm run verify`, and a separately invoked
`npm run smoke:electron` all exit zero. A later successful build does not erase
or waive a standalone smoke failure. P0 smoke proves current signed-out
post-click auth routing or current server-backed staged library loading/ready
semantics only, alongside the smoke's existing shell security, containment,
navigation, fullscreen, and cleanup guards. It rejects idle/obsolete/error
setup shapes but makes no channel-strategy or builder-parity claim. It does not
replace P5's dedicated signed-in library/preview/review/build/progress/result/
rerun journey.

Checkpoint: focused renderer tests, typecheck, maintainability report, diff
inspection, then independent review. Commit intent after a clean review:
`fix(renderer): initialize channel setup rerun entry`.

Stop if the entry cannot be fixed without changing Plex or IPC contracts; that
contradicts P0 and requires plan review before expansion.

### P1 — Freeze renderer-safe contracts and pure planning core

`IMPLEMENTER_ROLE_ELIGIBILITY: worker`

Extend the channel setup contract with normalized draft, record, preview,
review, progress, result, cancel, error, and operation vocabulary. Adapt the
upstream pure normalization/strategy/identity/diff/allocation policies into
`src/domain/channel/setupPlanning/**` using existing Desktop `ChannelConfig`
shapes. Cover every visible option, normalization bounds, mixed-scope
eligibility, global playlist uniqueness, actor/studio combination with one or
many available selected sources, the exact base -> alternate -> variant -> min
-> priority/allocation/cap order, append/replace/merge diff with the frozen
canonical FIFO identity and custom-channel exclusion, replicas, and series
variants with public-seam tests. Include the both-expansions/small-cap and all
identity edge cases required above.

No IPC, transport, filesystem, or renderer edits belong in P1. Update the
import ledger before or with adapted source. Checkpoint commit intent:
`feat(channel-setup): add typed planning model`.

### P2 — Implement privileged facets, planning/build runtime, persistence, and IPC

`IMPLEMENTER_ROLE_ELIGIBILITY: worker`

Add the minimum live Plex transport/facet calls required by P1, parse/narrow
responses once in main, and keep the facet snapshot private. Implement preview,
review, monotonic progress, cancel/too-late behavior, atomic build commit,
Guide-refresh reporting, setup-record load/save, profile/server scoping,
snapshot invalidation, stale completion, sanitized errors, and shutdown cleanup.
Wire the exact IPC protocol above and main app-data path composition. Reuse the
existing `ChannelRepository`: prepare the complete final `StoredChannelData`,
call `saveStoredChannelData` exactly once as the authoritative channel commit,
do not call `saveCurrentChannelId`, then attempt the separate setup-record write
and finally call only `GuideRuntime.refreshAfterChannelSetupCommit`. Do not
route post-commit work through `tuneChannel` or
`refreshActiveChannelSelection`. Do not create a second channel store,
`ChannelManager.replaceAllChannels` composition, renderer-facing Plex facet API,
or cross-file rollback claim.

Tests use injected Plex and persistence boundaries to prove each strategy
creates materially different persisted channel configurations/content sources,
all three build modes and exact custom-channel policy, no snapshot write on
pre-commit cancel/failure, one complete snapshot write on commit, too-late
cancel, committed-with-record-warning after a forced record-write failure,
record missing/corrupt/unsupported/unavailable behavior, profile/server
isolation, generated cap versus channel-number exhaustion, sender-bound
one-active-build/progress/cancel ordering, listener/operation cleanup, and
forbidden-field absence. `src/__tests__/main/guideRuntime.test.ts` and the setup
integration test must also prove the frozen one-write/zero-current-id-write
post-commit refresh seam. Checkpoint commit intent:
`feat(channel-setup): execute and persist channel plans`.

### P3 — Expose the narrow preload bridge

`IMPLEMENTER_ROLE_ELIGIBILITY: worker_sol_low`

Add the explicit bridge calls and implement the frozen per-build
`build(input, onProgress)` lifecycle: renderer-supplied unique build id,
preload-created request id, listener attachment before invoke, equality
filtering on both ids, same request id for invoke, and removal in `finally`.
Align contract and IPC channel vocabulary and the preload source-parity harness.
Reject malformed/reused/stale values and forbidden keys; do not expose raw
invoke/send/on. Checkpoint commit intent:
`feat(preload): expose channel builder workflow`.

Stop and escalate if the bridge needs a generic callback/RPC shape, an
unvalidated payload, or a token/URL/path-bearing field.

### P4 — Replace the reduced setup UI with the real builder

`IMPLEMENTER_ROLE_ELIGIBILITY: worker`

Adapt upstream channel-setup session state, three-step presentation hierarchy,
strategy category controls, priority reorder behavior, dropdown semantics,
preview/review/progress/result copy, and focus concepts to Desktop renderer
owners and existing design tokens. Connect every control to the P3 bridge.
Remove the current append/replace-only preview shell from the reachable product
route; retain custom-channel navigation as a separate supported choice.

The renderer must debounce/cancel stale preview/review work, disable impossible
Next/Build actions, require replace confirmation, render slow/blocked/error and
retry states, and make replace confirmation explicitly state that all existing
channels including custom channels will be removed. It must preserve
scroll/focus and clean progress/listener state. Add DOM,
controller, action-registration, focus, lifecycle, accessibility, and reduced
motion/forced-colors tests at public seams. Checkpoint commit intent:
`feat(renderer): restore upstream channel builder flow`.

### P5 — Integrated proof, docs truth, and closeout

`IMPLEMENTER_ROLE_ELIGIBILITY: worker`

Extend the Electron smoke harness only as needed to inject renderer-safe
signed-in/profile/server/facet outcomes. Prove first run through build result,
Settings rerun, Guide rerun, append/replace/merge, preview/review, cancel before
apply, one retryable failure/recovery, relaunch record restoration, and exact
return focus. Capture exact-viewport local visual evidence for library,
strategy categories, preview, review, progress, result, error, reduced motion,
forced colors, and the supported fullscreen continuity row. Evidence stays in
the ignored run bundle and must use synthetic/non-private names.

Update stale architecture/parity claims: Package 3's unsupported strategy and
cross-process cancellation exclusions must no longer be described as current;
record the new adapted upstream paths/symbols and current commit in the import
ledger; state precisely what local proof does and does not establish.

Run full verification and a fresh independent implementation/architecture
review. Route every material finding back to the owning package and rerun its
focused plus full gates. Final conventional commit intent for proof/docs only:
`docs(channel-setup): record builder parity proof`.

### Review and rollback policy

- A fresh reviewer must approve this plan before P0.
- Review P0 before its checkpoint, P1/P2 together at the contract/main boundary,
  P3/P4 together at the trust/UI boundary, and the complete diff after P5.
- The controller adjudicates findings; workers do not waive them. A material
  finding returns to the same worker/package for correction and a new commit.
- Each checkpoint must build and preserve existing channels. Revert only the
  affected checkpoint if a later package blocks. Never commit a UI control
  before its typed backend exists in the same reachable feature sequence.
- P2 schema/version writes must occur only after validation and atomic temp-file
  replacement. The channel snapshot is authoritative once its rename succeeds;
  a later setup-record write failure is a committed warning, not rollback.
  Rolling the code back to the pre-P2 commit leaves the separate setup-record
  file unused and the existing channel file readable.

## Verification Commands

**Verification classification:** broader integration/manual proof required

Run focused commands after the owning package and require zero failures:

```powershell
node --import tsx --test src/__tests__/renderer/setupEntryLifecycle.test.ts src/__tests__/renderer/startupRouting.test.ts src/__tests__/renderer/setupRuntimeCoordinator.test.ts src/__tests__/renderer/rendererActionRegistration.test.ts src/__tests__/renderer/plexRuntime.test.ts src/__tests__/main/smokeSetupAssertions.test.ts
node --import tsx --test src/__tests__/contracts/*.test.ts src/__tests__/domain/channelSetupPlanning.test.ts
node --import tsx --test src/__tests__/main/channelSetup*.test.ts src/__tests__/main/channelRuntimeIpc.test.ts src/__tests__/main/plexRuntimeIpc.test.ts src/__tests__/main/channelSetupPersistence.test.ts src/__tests__/main/guideRuntime.test.ts
node --import tsx --test src/__tests__/preload/*.test.ts src/__tests__/integration/preloadContractVocabulary.test.ts
node --import tsx --test src/__tests__/renderer/channelSetup*.test.ts src/__tests__/renderer/setup*.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/routeDom.test.ts
npm run typecheck
npm run verify:architecture
npm run verify:redaction
```

When an exact glob names a not-yet-created test, the package must create the
named focused test or update this plan in review before delegation; do not
silently omit the proof.

Before each commit and at closeout:

```powershell
git diff --check
npm run verify:maintainability
npm run verify
npm run smoke:electron
npm run build:electron
```

The signed-in Electron journey must use synthetic fixtures or operator-observed
redacted state, not a checked-in token or private server/library data. Manual
exact-viewport proof must record pass/fail for 1280x720 and 1920x1080, keyboard
and pointer activation, focus/return behavior, progress/cancel, reduced motion,
forced colors, and fullscreen continuity. If live Plex is used for the final
operator check, record only safe counts/state labels; no raw screenshot or log
with account, server, library, title, path, URL, or token data is tracked.

Expected outcomes: every visible configuration changes the returned plan and
committed channel shape; pre-apply cancel/failure does not write the channel
snapshot; a post-commit record failure preserves channels and returns the
frozen warning; successful relaunch restores the safe record; all entry/return
focus rows pass; the
renderer/preload contain no privileged data or broad Electron access; the full
verification and smoke commands exit zero.

## Acceptance Criteria

- A signed-in selected-server user entering from onboarding sees eligible
  libraries, not the reduced append/replace-only shell or a frozen route.
- The standalone Electron smoke accepts the current signed-out auth owner or
  current active staged-library loading/ready DOM, rejects retired/error owner
  shapes, and exits zero independently of `npm run verify` and package build.
  This is a shell security/containment plus minimal setup-entry routing guard,
  not channel-builder parity evidence.
- Settings, Guide, and empty Player open a newly initialized builder and return
  account/profile/server onboarding when prerequisites are missing or the
  initialized library builder only when all prerequisites exist, then return to
  their exact invoker focus; repeated reruns never reuse stale server,
  selection, preview, review, or progress state.
- All eight upstream strategy families and every option named in the Goal are
  visible where applicable, keyboard/remote/pointer operable, and backed by
  typed preview/review/build behavior.
- Preview estimates and rerun diffs are renderer-safe and correspond to the
  normalized config. Strategy priority controls generated channel/Guide order;
  the generated cap and channel-number exhaustion are reported separately.
- Replace, append, and merge produce the frozen semantics: replace explicitly
  confirms deletion of all existing/custom channels, while append/merge preserve
  custom channels and never identity-match or rewrite them. Current-channel
  custody is not accidentally destroyed outside confirmed replace.
- Progress, pre-apply cancellation, too-late cancellation, success, a committed
  result with nested Guide warning, blocked, retryable failure, and recovery
  have truthful terminal UI and public-seam tests.
- Post-commit Guide refresh updates only resolver/scheduler state: the integrated
  successful setup path observes exactly one stored-channel snapshot write,
  zero current-channel-id writes, and no tune/playback callback from refresh.
- Channel changes persist through one authoritative main-owned channel snapshot.
  The profile/server-scoped setup record normally restores through relaunch;
  record-write failure leaves committed channels intact and produces a visible
  recoverable `committed-with-record-warning`. Missing, corruption,
  unsupported-version, and unavailability are classified without secrets, raw
  paths, destructive overwrite, or silent plaintext fallback.
- Renderer and preload remain unprivileged; redaction/contract tests reject raw
  Plex, token, header, URL, path, connection, native, and persisted-record
  leakage.
- Exact-viewport UI evidence shows the upstream hierarchy and flow closely
  enough for the user to begin manual parity identification; any intentional
  Desktop divergence is documented rather than hidden.
- Focused tests, `npm run verify`, `npm run smoke:electron`, package build,
  maintainability evidence, import ledger/current-state/parity updates, and
  final fresh adversarial review are all observed clean.

## Replan Triggers

- Upstream scoped source changes from the pinned commit before its behavior is
  adapted, or the import ledger cannot state exact provenance.
- The existing Desktop channel domain cannot represent a required strategy,
  mixed source, replica, variant, ordering, or merge identity without changing
  a public channel/persistence schema not frozen here.
- Plex server endpoints cannot provide a required facet/count through the
  selected-server main context, or a strategy would require renderer-owned
  transport/raw payloads.
- The complete `StoredChannelData` write cannot remain the single authoritative
  channel commit, or the implementation would need a second current-channel
  write, a cross-file transaction/journal, or rollback after rename.
- Cancellation cannot be made truthful at the frozen pre-apply/too-late seam,
  or Guide refresh cannot be separated from channel commit outcome.
- Post-commit Guide refresh would require `tuneChannel`, any repository/store
  write, or a playback callback; expansion/min/allocation order would differ
  between preview/review/build; canonical FIFO identity cannot preserve matched
  generated ids/numbers; or preload cannot attach and equality-filter the
  per-build listener before invoking main with the same request id.
- A visible upstream control cannot affect both preview/review and build. Hide
  or defer it only through reviewed replan, never as a display-only option.
- P0 needs contract/IPC changes, or a later package needs files outside its
  approved owners, dependencies/lockfile changes, browser storage, compatibility
  shims, a broad preload API, or edits in the upstream checkout.
- A touched owner over 500 lines lacks a cohesion disposition, a named hotspot
  grows without extraction/review, or implementation centralizes transport,
  planning, persistence, and UI policy in a composition root.
- Focused/full verification, signed-in Electron proof, exact-viewport evidence,
  redaction, maintainability, package build, or independent review remains
  materially failing after remediation.

## Next Session Handoff

```text
NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-review
TASK: Complete Channel Builder Onboarding Parity Remediation Through Quality Loop
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/channel-builder-onboarding-parity-remediation.md
ARTIFACT: active decision-complete plan requiring independent adversarial review
FILES:
- docs/plans/channel-builder-onboarding-parity-remediation.md
- src/renderer/index.ts
- src/renderer/startupRouting.ts
- src/renderer/plexRuntimeDom.ts
- src/renderer/setup/setupComposition.ts
- src/renderer/setup/setupEntryLifecycle.ts
- src/main/smokeAssertions.ts
- src/main/smokeSetupAssertions.ts
- src/__tests__/renderer/plexRuntime.test.ts
- src/__tests__/main/smokeSetupAssertions.test.ts
BLOCKERS: none; implementation must not start until plan review is clean
MESSAGE:
Review the active plan adversarially for upstream product fidelity, Electron/Plex/persistence custody, real strategy and commit semantics, cancellation truth, exact P0 scope, architecture health, verification depth, and hidden UI-only shortcuts. Return material findings to the planner; if clean, authorize P0 only and keep P1-P5 gated by their listed checkpoints.
```
