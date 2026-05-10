**Plan Status:** active

**Task family:** feature/design

**Tier:** Tier 3

**Controller phase:** implementation closeout

**Verification classification:** new regression/contract test required

## Goal

Continue RD-07 Desktop VideoPlayer Adapter after the reviewed
`desktop-player-adapter-boundary-core` baseline.

Completed baseline to preserve:

- `src/main/player/desktopPlayerAdapter.ts` owns the main-process adapter core.
- `src/main/player/nativePlayerHostPort.ts` defines the private fakeable native
  host port.
- `src/__tests__/desktopPlayerAdapter.test.ts` covers command mapping,
  renderer-intent validation, host-event validation, renderer-safe errors,
  request cleanup, helper crash normalization, stale-event quarantine, and
  forbidden-field exclusion.

RD-07 continuation work is split into two bounded units:

1. `desktop-player-runtime-ipc-preload-delivery`: implemented and read-only
   implementation re-reviewed clean on 2026-05-10. This Mac-verifiable unit
   wires narrow runtime main/preload player IPC against the existing
   `DesktopPlayerAdapter` and a development/smoke fake host seam, with
   production unsupported/noop behavior.
2. `desktop-player-windows-native-host-proof`: a later Windows-only native host
   integration/proof unit against the RD-06 app-owned native presentation
   direction. This must be reviewed separately and must not be implemented by
   the Mac first pass except through handoff/testing instructions.

The next remaining RD-07 gate is a separate reviewed plan or execution packet
for `desktop-player-windows-native-host-proof`.

## Non-Goals

- Do not edit product source in this planning pass.
- Do not begin runtime IPC/preload implementation until read-only plan review
  reports no blockers.
- Do not reopen the completed adapter boundary core except for narrow changes
  directly required by the reviewed runtime IPC/preload unit.
- Do not implement a real native helper, native binary, native addon, libmpv
  binding, helper process manager, Windows presentation host, package script,
  dependency, or lockfile change in the Mac runtime IPC/preload unit.
- Do not contact Plex, import Plex modules, implement stream policy, resolve
  media URLs, move tokens, add secure storage, import scheduler/channel code,
  import renderer UI, or add packaging/signing/update work.
- Do not expose raw media URLs, tokenized URLs, auth headers, Plex payloads,
  stream keys, part keys, native handles, libmpv objects, engine ids, Electron
  APIs, Node APIs, broad IPC, arbitrary channel strings, filesystem access, or
  secret diagnostics to renderer-facing contracts, preload APIs, tests, logs,
  docs, or Codex output.
- Do not make Windows proof claims from macOS. Windows native-host proof remains
  a later targeted lane with its own commands and redacted evidence.
- Do not update unrelated dirty files. Existing unrelated dirty/untracked plan
  files from `git status --short --branch` are not RD-07 evidence.

## Parent Architecture Alignment

Current architecture records a secure Electron shell, renderer-safe player
contracts, shell/window preload bridge, and the completed RD-07 adapter core.
It also records that production Plex integration, runtime player IPC/preload
delivery, real native helper integration, scheduler, secure storage, and
packaging are not implemented.

RD-03 owns renderer-safe player contracts in `src/contracts/player.ts` and
`src/contracts/ipc.ts`. RD-07 must keep these contracts closed and
renderer-safe. Additions may define narrow player IPC channel/result/event
vocabulary only when needed for the runtime delivery unit.

RD-06 routes native playback toward app-owned native presentation. The WID and
helper-owned render API spike directions remain closed unless a later reviewed
plan reopens them. The Mac runtime IPC/preload unit may instantiate
`DesktopPlayerAdapter` with a fake host only; it must not create production
native playback.

Ownership alignment:

- Renderer owns UI consumption of renderer-safe player state only. No renderer
  UI import is in the next unit.
- Preload owns a narrow `window.lineupDesktop.player` bridge if reviewed. It
  must validate method inputs enough to avoid broad RPC and must not expose raw
  `ipcRenderer` or arbitrary channels.
- Electron main owns player IPC authorization, adapter lifetime, event/result
  translation, and cleanup registration. Within main, the player IPC owner in
  `src/main/player/playerIpc.ts` owns fake-host activation policy and adapter
  factory selection from a plain shell mode option.
- `src/main/index.ts` remains a composition root. It may call a player IPC
  registrar and pass plain data/callbacks, but it must not absorb fake-host
  activation policy, native process policy, or adapter business rules.
- Future native-host code owns app-owned native presentation only in the later
  Windows proof unit after separate review.

## Required Reading

Read in this order before review or implementation:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-plan.md`
4. `docs/agentic/plan-authoring-standard.md`
5. `docs/architecture/CURRENT_STATE.md`
6. `docs/roadmap/desktop-port-roadmap.md`
7. `docs/architecture/playback-architecture.md`
8. `docs/architecture/security-and-secret-flow.md`
9. `docs/architecture/upstream-behavior-guardrails.md`
10. This plan
11. `src/contracts/player.ts`
12. `src/contracts/ipc.ts`
13. `src/contracts/shell.ts`
14. `src/main/player/desktopPlayerAdapter.ts`
15. `src/main/player/nativePlayerHostPort.ts`
16. `src/preload/index.cts`
17. `src/main/index.ts`
18. `src/__tests__/desktopPlayerAdapter.test.ts`
19. `src/__tests__/contracts.test.ts`
20. `package.json`

Freshness gate: before review or implementation, rerun
`git status --short --branch` and reread the files above if architecture docs,
contracts, roadmap status, verifier behavior, package scripts, runtime source,
or this plan changed materially after 2026-05-10. Stop for plan update or
re-review if any assumption is contradicted.

## Required Skills

- `lineup-desktop-feature-plan`: required launcher for this Tier 3 planner
  refresh.
- `execution-plan-authoring`: required for durable scope, ownership,
  invariants, verification, rollback, and stop conditions.
- `architecture-boundaries`: required because the next unit touches contracts,
  preload, Electron main composition, player IPC ownership, and the future
  native-helper seam.
- `verification-strategy`: required because the next unit needs contract tests,
  IPC/preload tests, Electron smoke proof, and explicit Windows proof limits.
- `plex-integration-boundaries`: required as a constraint because future player
  setup will receive Plex-derived stream material, while this unit must keep
  Plex, tokens, URLs, headers, and stream policy out of scope.
- `review-request`: the next gate is read-only adversarial plan review through
  `lineup-desktop-feature-review`.
- `closeout-verification`: required before calling the refreshed plan ready or
  later calling implementation complete.

## Evidence And Discovery

- `semantic_search_with_context`: not used as authoritative evidence. The
  controller reported Codanna results were invalid/noisy because Codanna was
  pointed at the wrong repo or had no useful embeddings for this checkout.
- `semantic_search_docs` or repo-doc search: not used as authoritative
  evidence for the same reason.
- Impact analysis: not used because noisy Codanna ownership results would risk
  misrouting the plan. Ownership was determined from direct reads.
- Direct reads / `rg`: the required workflow docs, plan standard, current
  architecture, roadmap, playback/security/upstream guardrail docs, active
  RD-07 plan, contracts, adapter core, fake host port, preload, main
  composition root, adapter tests, contract tests, `package.json`, and
  `git status --short --branch` were read directly. This direct-read fallback
  is the evidence path for this plan refresh.
- Official docs: no new external Electron, native, packaging, signing, or
  dependency behavior is frozen by this planner pass. If implementation needs
  new Electron behavior beyond existing `ipcMain`, `ipcRenderer`, and
  `contextBridge` patterns already present in the repo, stop for a bounded
  official-doc check or reviewed replan.

Observed local baseline provided by the controller before this refresh:

- `npm run typecheck` passed.
- `npm run test:contracts` passed with 25 tests.
- `npm run verify:docs` passed.
- `npm run verify:redaction` passed.

Direct evidence summary:

- `docs/roadmap/desktop-port-roadmap.md` marks RD-07 in progress: the boundary
  core is implemented and reviewed clean; runtime player IPC wiring and real
  native host integration remain unimplemented.
- `docs/architecture/CURRENT_STATE.md` and
  `docs/architecture/playback-architecture.md` record the completed adapter
  core and explicitly list runtime preload/main player IPC and real native
  helper work as not implemented.
- `docs/architecture/security-and-secret-flow.md` requires renderer/preload
  APIs to stay narrow and token-bearing playback setup to remain inside
  privileged main/helper ownership.
- `docs/architecture/upstream-behavior-guardrails.md` requires RD-07/RD-08
  player and stream work to preserve command/state/event, stale-load, track,
  error, diagnostic, teardown, and cleanup lessons without leaking raw URLs,
  headers, native handles, engine ids, libmpv objects, or webOS constants.
- `src/contracts/player.ts` already defines renderer-safe command, snapshot,
  event, error, diagnostic, capability, opaque track, and forbidden privileged
  field vocabulary.
- `src/contracts/ipc.ts` defines closed player renderer intents and shell/window
  channels, but no player runtime IPC channels yet.
- `src/contracts/shell.ts` currently defines `LineupDesktopPreloadApi` with
  only `shell` and `window` APIs.
- `src/preload/index.cts` exposes only shell/window methods and validates shell
  status events and fullscreen arguments locally.
- `src/main/index.ts` owns shell lifecycle, shell/window IPC authorization, and
  smoke assertions. It has no player IPC registrar and should remain thin.
- Fresh direct reads on 2026-05-10 found no existing local pattern that should
  replace the accepted review decisions below. The runtime IPC/preload unit must
  add the concrete player contract, registrar, and fake-host activation policy
  frozen in this plan.
- `src/main/player/desktopPlayerAdapter.ts` accepts
  `RendererIntentEnvelope<unknown>`, maps closed player intents, validates
  renderer payloads and host events, normalizes failures, sanitizes
  diagnostics, handles cleanup, and quarantines stale request ids.
- `src/main/player/nativePlayerHostPort.ts` is a private fakeable host port, not
  a production native process owner.
- `src/__tests__/desktopPlayerAdapter.test.ts` covers the completed boundary
  core with fakes and forbidden-field assertions.
- `src/__tests__/contracts.test.ts` currently asserts the preload API exposes
  only shell/window methods; the runtime IPC/preload unit must update this
  public contract expectation if `player` is added.
- `package.json` already has `typecheck`, `test:contracts`,
  `smoke:electron`, `verify:docs`, `verify:redaction`, and `verify` scripts.
  No package, dependency, script, or lockfile change is authorized.

## Impact Snapshot

Expected blast radius for the next reviewed execution unit:

- Owners that may change: renderer-safe player/IPC/preload contract vocabulary,
  preload player bridge, a new main-owned player IPC registrar/factory, minimal
  main composition registration, and focused tests/smoke assertions.
- Owners that must not change: Plex auth/discovery/library/stream setup,
  scheduler/channel/content, renderer UI import, secure storage, native helper
  runtime, native spike tools, packaging/release, package metadata, lockfiles,
  dependencies, and copied/adapted upstream product source.
- Public contracts that may change: `src/contracts/ipc.ts` may add closed
  player IPC channel literals and result/event vocabulary exactly as frozen in
  this plan; `src/contracts/shell.ts` must add the narrow `player` member to
  `LineupDesktopPreloadApi`; `src/contracts/player.ts` or another renderer-safe
  contract owner must define or reuse `PlayerIpcResult<T>` and
  `PlayerDispatchResult`. No privileged values may be introduced.
- Runtime behavior that may change: in Electron smoke mode, the renderer may be
  able to call a fake-host-backed `window.lineupDesktop.player` API and receive
  renderer-safe command results/snapshots/events. There is no real media
  playback.
- User-visible production behavior: no real playback is claimed. Production
  player command attempts must return renderer-safe player failures using the
  existing `unsupported-capability` category with a player error code such as
  `PLAYER_UNSUPPORTED_CAPABILITY` or `PLAYER_OPERATION_UNAVAILABLE` when a
  generic player failure code is needed, until a reviewed Windows native-host unit
  replaces the factory.
- Dependency/build impact: none authorized.
- Local-only artifacts: none expected. Any accidental logs, screenshots,
  native traces, media, or run evidence must remain untracked and must not be
  required for the Mac runtime IPC/preload unit.

## Files In Scope

Planning pass write scope:

- `docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md`

After clean read-only plan review, next execution unit write scope for
`desktop-player-runtime-ipc-preload-delivery`:

- `src/contracts/ipc.ts`
- `src/contracts/player.ts`
- `src/contracts/shell.ts`
- `src/preload/index.cts`
- `src/main/player/playerIpc.ts` (new main-owned player IPC registrar/factory)
- `src/main/player/desktopPlayerAdapter.ts` only if a narrow public seam change
  is required for runtime delivery
- `src/main/player/nativePlayerHostPort.ts` only if a narrow fake-host type
  change is required for runtime delivery
- `src/main/index.ts` only for minimal composition registration and smoke
  assertions
- `src/__tests__/contracts.test.ts`
- `src/__tests__/desktopPlayerAdapter.test.ts` only if adapter public behavior
  changes
- `src/__tests__/playerIpc.test.ts` or an equivalently focused new test file

Scope limits:

- Favor `src/main/player/playerIpc.ts` as the owner of player IPC registration,
  shell-mode-based fake-host-backed adapter factory wiring, production
  unsupported/noop factory behavior, result translation, event delivery, cleanup
  registration, and handler teardown.
- Keep `src/main/index.ts` to composition only: construct/register the player
  IPC owner with the existing `shellMode` value and include smoke assertions.
  Do not place fake-host activation policy, production unsupported policy,
  native process policy, adapter rules, validation rules, or broad player
  orchestration there.
- Preload may expose explicit methods such as command dispatch, snapshot read,
  event subscription, and cleanup only if they are typed and channel-bound. It
  must not expose raw `ipcRenderer`, arbitrary channels, or a general RPC
  function.
- Fake-host activation must be development/smoke-only. Production command
  attempts must return renderer-safe player failures using
  `unsupported-capability` with a player error code such as
  `PLAYER_UNSUPPORTED_CAPABILITY` or `PLAYER_OPERATION_UNAVAILABLE` and must not report
  fake playback success.
- Tests must prove public IPC/preload contract behavior with fakes and smoke,
  not real native media.

Later `desktop-player-windows-native-host-proof` scope is intentionally not
authorized for implementation by this plan. A future reviewed execution unit
must name exact native-host files, Windows commands, redacted evidence paths,
and rollback before editing product native-host code.

## Files Out Of Scope

- Any file outside the planning-pass write scope during this planner pass.
- Any file outside the next execution unit write scope during the Mac runtime
  IPC/preload implementation.
- `package.json`, lockfiles, package manager metadata, dependency manifests,
  build tooling, installer, signing, updater, release, or packaging config.
- `src/renderer/**`, except no renderer UI import is authorized; smoke
  assertions may inspect the exposed preload API through the existing Electron
  shell only.
- `src/native-helper/**`, native helper runtime paths, native binaries, native
  addons, generated bindings, NuGet packages, mpv/libmpv headers, or checked-in
  native examples.
- RD-05/RD-06 evidence tooling under `tools/mpv-poc/**` and
  `tools/libmpv-spike/**`.
- Plex auth, discovery, selected-server state, library, stream resolution,
  subtitles, token handling, URL/header setup, secure storage, scheduler,
  channel, settings, EPG, OSD, navigation, broad UI import, or copied/adapted
  upstream Lineup source.
- `docs/architecture/import-ledger.md`; no copied/adapted upstream source is in
  scope.
- Roadmap or architecture docs during this planning pass. During later
  implementation closeout, update architecture/roadmap memory only if the
  reviewed implementation unit requires it and after product verification and
  implementation review/adjudication.
- Unrelated dirty files already present before this RD-07 planner refresh.

## Planner Self-Check

1. Product, architecture, ownership, dependency, and verification decisions for
   the next execution unit are resolved: main owns player IPC registration,
   preload exposes a narrow API, the adapter remains the player core, and the
   host remains fake on Mac.
2. The next unit does not depend on Plex, scheduler, stream policy, renderer UI,
   secure storage, native helper runtime, package changes, or Windows native
   proof.
3. Files frozen out of scope are not relied on for hidden wiring. Native-host
   integration is explicitly deferred to a later reviewed Windows unit.
4. Evidence path records the Codanna fallback and direct reads.
5. The plan avoids growing `src/main/index.ts` into a hotspot by favoring a new
   main player IPC owner.
6. A fresh implementer should not need to invent Electron IPC, preload,
   security, playback, persistence, packaging, import, native proof, or
   verification policy.
7. Exact verification commands, expected outcomes, acceptance criteria,
   rollback, and stop/replan triggers are recorded.

## Architecture Seam Decision Gate

Chosen seam for the next unit: a main-owned player IPC registrar/factory in
`src/main/player/playerIpc.ts` bridges authorized renderer player intents from
preload to the existing `DesktopPlayerAdapter`. `src/main/index.ts` passes the
existing `shellMode` value as plain data; `playerIpc.ts` owns factory selection,
instantiating an inert fake native host only for development/smoke runtime
delivery proof and using a renderer-safe unsupported/noop production path
otherwise.

Frozen decisions:

| Decision | RD-07 continuation choice |
| --- | --- |
| Completed baseline | Preserve `desktop-player-adapter-boundary-core` as implemented and reviewed clean |
| Next execution unit | `desktop-player-runtime-ipc-preload-delivery` |
| Runtime IPC owner | New `src/main/player/playerIpc.ts`, not `src/main/index.ts` |
| Main composition | `src/main/index.ts` only performs minimal registration and smoke assertions |
| Mode/policy handoff | `src/main/index.ts` passes `shellMode`; `src/main/player/playerIpc.ts` owns fake-host activation and production unsupported behavior |
| Preload boundary | Add explicit typed player methods/subscriptions only; no broad RPC |
| Adapter boundary | Reuse `DesktopPlayerAdapter` and `NativePlayerHostPort` fake seam |
| Host boundary | Fake host is development/smoke-only for contract delivery; production must not claim real playback |
| Renderer boundary | Renderer receives only `PlayerSnapshot`, `PlayerEvent`, `PlayerError`, and narrow result shapes |
| IPC vocabulary | Closed channel/result/event vocabulary only; no arbitrary channel strings |
| Plex/stream boundary | No Plex or stream policy implementation |
| Native direction | Future Windows proof targets RD-06 app-owned native presentation |
| Dependency boundary | No package, lockfile, dependency, native addon, or build-tool change |

Frozen public IPC/preload contract for `desktop-player-runtime-ipc-preload-delivery`:

- `src/contracts/ipc.ts` must add only these player runtime channel literals:
  `LINEUP_PLAYER_COMMAND_CHANNEL = 'lineup:player:command'`,
  `LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL = 'lineup:player:getSnapshot'`,
  `LINEUP_PLAYER_CLEANUP_CHANNEL = 'lineup:player:cleanup'`, and
  `LINEUP_PLAYER_EVENT_CHANNEL = 'lineup:player:event'`.
- `src/contracts/shell.ts` must extend `LineupDesktopPreloadApi` with
  `player.dispatch(envelope: RendererIntentEnvelope<unknown>) =>
  Promise<PlayerIpcResult<PlayerDispatchResult>>`,
  `player.getSnapshot() => Promise<PlayerIpcResult<PlayerSnapshot>>`,
  `player.cleanup() => Promise<PlayerIpcResult<PlayerSnapshot>>`, and
  `player.onEvent(listener: (event: PlayerEvent) => void) => () => void`.
- `PlayerIpcResult<T>` must be defined or reused from the renderer-safe
  contracts as exactly a success branch with `ok: true`, `value: T`, and
  `requestId`, or a failure branch with `ok: false`, renderer-safe `error`, and
  `requestId`. The failure branch must use renderer-safe player error
  vocabulary and must not introduce shell-only, native-only, or privileged
  error details.
- `PlayerDispatchResult` must be renderer-safe and must not include internal
  `PlayerCommand`. It must include `accepted`, `events`, and `snapshot`, where
  `events` is a readonly list of `PlayerEvent` payloads emitted or settled by
  the adapter dispatch and `snapshot` is the latest `PlayerSnapshot`.
- Request-id ownership is fixed: renderer/caller supplies `requestId` in
  command envelopes passed to `player.dispatch`; preload may generate request
  ids only for its own `cleanup` and `getSnapshot` wrapper requests if the main
  handler needs a request id for result shaping; main validates through
  `DesktopPlayerAdapter` and never trusts preload-only validation.
- Event subscription semantics are fixed: main sends only `PlayerEvent` payloads
  on `LINEUP_PLAYER_EVENT_CHANNEL` after adapter dispatch, cleanup, host, or
  crash events; preload runs a conservative runtime player-event guard before
  invoking listeners; the returned unsubscribe removes only that listener; no
  raw `IpcRendererEvent`, Electron channel, arbitrary channel, or raw IPC object
  is exposed.
- `player.cleanup()` must invoke `LINEUP_PLAYER_CLEANUP_CHANNEL`, return the
  latest `PlayerSnapshot` through `PlayerIpcResult<PlayerSnapshot>`, emit only
  renderer-safe state/error events through `LINEUP_PLAYER_EVENT_CHANNEL`, and
  must not expose host cleanup internals, native handles, engine ids, or helper
  lifecycle details.

Frozen main authorization and registrar contract:

- `src/main/player/playerIpc.ts` must own the player IPC registration and export
  `registerPlayerIpcHandlers(options)` or an equivalent single registrar owner.
  The options contract must receive `shellMode: ShellMode`,
  `isAuthorizedEvent(event): boolean`, `sendPlayerEvent(event: PlayerEvent):
  void`, and `createRequestId(prefix): string` if the registrar needs fallback
  request ids. It must not require `src/main/index.ts` to pass
  `createAdapter()` or otherwise encode development/smoke/production player host
  policy in main. The registrar returns a teardown function that unregisters the
  player handlers and cleans up only the player IPC owner resources it
  registered.
- `src/main/index.ts` only calls this registrar after shell setup and passes the
  existing `shellMode` value plus authorization and event-send callbacks. It may
  close over `shellWindow?.webContents.send(LINEUP_PLAYER_EVENT_CHANNEL, event)`
  through the callback, but it must not own adapter rules, fake-host activation
  policy, production unsupported/noop behavior, native process policy,
  command/result translation, event validation, cleanup behavior, or handler
  teardown internals.
- Authorization is checked in main for every command, snapshot, and cleanup
  handler before adapter access. Unauthorized or invalid requests return
  `PlayerIpcResult` failures with renderer-safe player error vocabulary and a
  request id chosen from the caller envelope when valid or a generated fallback
  when needed.

Frozen fake-host activation policy:

- The Mac runtime IPC/preload unit may instantiate an inert fake
  `NativePlayerHostPort` only inside `src/main/player/playerIpc.ts` and only
  when the registrar option `shellMode` is `development` or `smoke`. This is a
  contract-delivery and smoke-verification host, not production playback.
- In `production`, the player IPC path must not claim real playback. Until the
  later Windows native-host unit replaces the factory with a reviewed production
  host, `src/main/player/playerIpc.ts` must select an unsupported/noop adapter
  or factory path. Player command attempts must return renderer-safe
  `PlayerError` failures using the existing `unsupported-capability` category
  with a player error code such as `PLAYER_UNSUPPORTED_CAPABILITY` or
  `PLAYER_OPERATION_UNAVAILABLE`, and must not activate the fake host.
  Snapshot and cleanup may return renderer-safe inert state if needed, but no
  playback success may be claimed.
- Electron smoke proof may exercise the development/smoke fake host through the
  public preload API. macOS smoke success is evidence for IPC/preload contract
  delivery only, not native playback.

Forbidden shortcuts:

- No renderer privilege concession.
- No raw `ipcRenderer`, Electron, Node, filesystem, native, libmpv, graphics,
  token, URL, header, Plex, stream key, part key, or secret diagnostic values in
  renderer-facing state.
- No general `invoke(channel, payload)` or broad player RPC bridge.
- No real native helper launch hidden behind the fake-host seam.
- No production-visible fake-host playback success.
- No WID or helper-owned render API revival.
- No product Plex, scheduler, renderer UI, secure storage, package, or upstream
  import work.
- No stale event delivery without request-id gating.
- No claiming track/subtitle production support beyond opaque id delivery and
  safe error/result propagation.

Windows native-host proof gate:

- The later `desktop-player-windows-native-host-proof` unit must be reviewed
  before implementation.
- It must run on Windows and produce redacted evidence for app-owned native
  presentation against the runtime adapter/IPC seam.
- It must prove at minimum: local dummy visual playback, dummy HTTP playback
  with only approved non-secret headers, windowed and fullscreen active video
  pixels, overlay/composition behavior, renderer focus/input continuity,
  command/event ordering including stop/switch cleanup, helper crash detection,
  stale native event quarantine, helper cleanup/reap, redacted diagnostics, and
  no forbidden renderer-facing fields.
- It must name exact Windows commands and evidence paths. macOS implementation
  may only prepare handoff/testing instructions, not product native-host code.

Stop before implementation if plan review finds the seam too broad, if player
runtime delivery cannot be tested without real native playback, if preload
requires broad RPC, if `src/main/index.ts` would absorb player host-mode policy
instead of passing `shellMode` into `playerIpc.ts`, or if contracts require
privileged values.

## Verification Commands

Planner commands:

```sh
git status --short --branch
```

Expected outcome: branch state is observed before edits; unrelated dirty files
are not modified, staged, reverted, or treated as RD-07 evidence.

```sh
npm run verify:docs
```

Expected outcome: passes after this active plan is refreshed. If it fails, fix
only the RD-07 plan unless the output proves a pre-existing unrelated issue.

Next execution unit commands after clean plan review:

```sh
git status --short --branch
```

Expected outcome: dirty state is understood; unrelated files are left alone.

```sh
npm run typecheck
```

Expected outcome: TypeScript compiles with the new player IPC/preload contract
and no accidental public signature drift.

```sh
npm run test:contracts
```

Expected outcome: existing contract and adapter tests pass; new tests prove
the exact closed player IPC literals named in this plan, the
`window.lineupDesktop.player` method names and signatures, renderer/caller
request-id ownership for command envelopes, preload-generated request ids only
for wrapper snapshot/cleanup requests when needed, renderer-safe
`PlayerIpcResult<T>` and `PlayerDispatchResult` shapes, invalid payload
rejection, authorized main-only validation through `DesktopPlayerAdapter`,
development/smoke fake-host-backed adapter dispatch, production unsupported
mode policy, snapshot/event delivery, cleanup, per-listener unsubscribe, handler
teardown, forbidden-field exclusion, and no broad RPC/channel exposure.

```sh
npm run smoke:electron
```

Expected outcome: Electron smoke still proves shell containment and additionally
proves the player preload API is present, does not expose raw IPC/Electron/Node
objects, can drive a fake-host-backed player command through authorized main IPC,
can read renderer-safe state/result data, can subscribe/unsubscribe without
exposing raw event/channel objects, can cleanup through the public cleanup API,
and exits cleanly. Smoke proof is development/smoke fake-host contract evidence
only and does not claim production native playback.

```sh
npm run verify:redaction
```

Expected outcome: tracked docs, tests, and source contain no forbidden raw
secret, token, URL, header, native handle, libmpv, engine id, raw Plex, stream
key, part key, or secret diagnostic content.

```sh
npm run verify
```

Expected outcome: passes before the runtime IPC/preload unit is called
complete.

Manual/source-audit proof after implementation:

- Inspect `git diff -- src/contracts src/preload/index.cts src/main/index.ts src/main/player src/__tests__`
  and confirm only reviewed RD-07 runtime IPC/preload files changed.
- Confirm `src/main/index.ts` only performs minimal composition and smoke
  assertions, passing the existing `shellMode` value plus callbacks without
  creating adapters or encoding host-mode policy.
- Confirm `src/main/player/playerIpc.ts` owns player IPC registration/factory
  behavior, authorization handoff, result translation, event emission, cleanup,
  shell-mode-based fake-host activation policy, production unsupported/noop
  behavior, and teardown while using the existing adapter plus fake host seam
  only in development/smoke.
- Confirm preload exposes explicit typed player methods/subscriptions and no
  raw `ipcRenderer`, arbitrary channel, Electron, Node, filesystem, native, or
  secret-bearing access.
- Confirm production mode cannot activate fake-host playback success and returns
  renderer-safe player errors using the `unsupported-capability` category with
  `PLAYER_UNSUPPORTED_CAPABILITY` or `PLAYER_OPERATION_UNAVAILABLE` for command
  attempts until the reviewed Windows native-host unit replaces the factory.
- Confirm no package metadata, lockfile, Plex, scheduler, stream policy,
  renderer UI import, native helper runtime, RD-06 tooling, or copied upstream
  source changed.

Later Windows native-host proof commands must be added by that future reviewed
execution unit. They are not authorized or satisfied by this Mac plan refresh.

## Acceptance Criteria

Plan acceptance:

- This file is the only file edited by the RD-07 planner refresh.
- The plan remains active, feature/design, and Tier 3.
- The completed adapter boundary core is preserved as baseline, not replanned as
  future work.
- Remaining RD-07 work is split into Mac-verifiable runtime IPC/preload delivery
  and later Windows native-host proof.
- The next execution unit names exact files in scope and out of scope.
- The plan favors a new `src/main/player/playerIpc.ts` owner and keeps
  `src/main/index.ts` minimal.
- The plan freezes exact player IPC channel literals, `window.lineupDesktop.player`
  method names and signatures, request-id ownership, result shapes, event
  subscription semantics, cleanup behavior, registrar options/teardown,
  `shellMode` policy handoff, and fake-host activation policy for the next
  execution unit.
- The plan records direct-read fallback because Codanna results were invalid or
  noisy for this checkout.
- The plan records the observed local baseline commands provided by the
  controller without claiming fresh reruns.
- The runtime IPC/preload unit passed read-only implementation re-review; the
  next RD-07 gate is a reviewed Windows native-host proof plan or execution
  packet.
- `npm run verify:docs` passes after this refresh, or the exact failure is
  reported without a false success claim.

Next execution unit acceptance after clean plan review:

- Implementation is limited to `desktop-player-runtime-ipc-preload-delivery`.
- Source/test changes are limited to the files in scope unless a reviewed replan
  expands scope.
- A narrow player preload API is exposed under the existing
  `window.lineupDesktop` contract without raw IPC, arbitrary channels, Electron,
  Node, filesystem, native, or secret-bearing access.
- `src/contracts/ipc.ts` exports exactly the reviewed player runtime channel
  literals:
  `lineup:player:command`, `lineup:player:getSnapshot`,
  `lineup:player:cleanup`, and `lineup:player:event`.
- `LineupDesktopPreloadApi.player` exposes exactly `dispatch`, `getSnapshot`,
  `cleanup`, and `onEvent` with the result and listener semantics frozen above.
- `PlayerIpcResult<T>` and `PlayerDispatchResult` are renderer-safe, exclude
  internal `PlayerCommand`, and carry only accepted/events/snapshot result data
  plus request-id/error wrapper fields.
- Renderer/caller-owned command request ids are preserved; preload-generated
  request ids are limited to snapshot/cleanup wrapper requests when needed; main
  validates every request through the adapter path and does not rely on preload
  validation as authority.
- Main player IPC registration lives in `src/main/player/playerIpc.ts`;
  `src/main/index.ts` only wires it into the shell composition, passes the
  existing `shellMode` value and callbacks, and adds smoke checks.
- Runtime player commands flow through authorized main IPC into
  `DesktopPlayerAdapter` with a fake `NativePlayerHostPort` only in
  development/smoke.
- Production player command attempts are handled by the `playerIpc.ts`
  unsupported/noop path, do not activate fake-host playback, and return
  renderer-safe player failures using the `unsupported-capability` category with
  `PLAYER_UNSUPPORTED_CAPABILITY` or `PLAYER_OPERATION_UNAVAILABLE` until the
  Windows native-host unit replaces the factory.
- Renderer-facing results, snapshots, events, errors, and diagnostics remain
  contract-bound and forbidden-field-free.
- Invalid renderer payloads do not reach the fake host and produce
  renderer-safe validation failures.
- Event subscription/cleanup behavior sends only guarded `PlayerEvent` payloads,
  removes only the unsubscribed listener, returns the latest cleanup snapshot,
  emits state/error events through the player event channel, does not expose host
  cleanup internals, and does not leak stale listeners or corrupt adapter state
  after cleanup.
- No real native helper, Plex, stream policy, scheduler, renderer UI import,
  secure storage, package, lockfile, dependency, native smoke, or upstream import
  file changes.
- `npm run typecheck`, `npm run test:contracts`, `npm run smoke:electron`,
  `npm run verify:redaction`, and `npm run verify` pass before implementation
  closeout.
- Read-only implementation review is clean before RD-07 advances to the Windows
  native-host proof unit or is marked complete for the runtime delivery lane.

Windows native-host proof acceptance for the later unit:

- A separate reviewed plan or execution packet names exact Windows files,
  commands, evidence paths, stop conditions, and rollback.
- Proof runs on Windows against the RD-06 app-owned native presentation
  direction and the runtime adapter/IPC seam.
- Redacted evidence proves native playback, fullscreen/composition, focus,
  cleanup, crash/stale-event handling, and forbidden-field exclusion.
- macOS-only evidence is not used to claim Windows native-host completion.

## Replan Triggers

Stop and replan if any of the following occurs:

- Read-only plan review finds the runtime IPC/preload seam too broad,
  under-specified, or inconsistent with current contracts.
- Current architecture, roadmap, contract files, preload/main source, package
  scripts, verifier behavior, or baseline tests changed materially after this
  plan refresh.
- Implementation needs real native helper runtime, Windows native proof, Plex,
  stream policy, scheduler, secure storage, renderer UI import, package,
  lockfile, dependency, packaging, installer, signing, or upstream import
  changes.
- `src/main/index.ts` would need to absorb player lifecycle, fake-host
  activation policy, production unsupported/noop behavior, or native process
  policy instead of delegating to a player IPC owner with a plain `shellMode`
  option.
- Preload requires a broad RPC bridge, arbitrary channel strings, raw
  `ipcRenderer`, Electron/Node objects, filesystem access, or secret-bearing
  values.
- The implementation cannot preserve the exact player IPC channel literals,
  preload method names/signatures, request-id ownership, `PlayerIpcResult` /
  `PlayerDispatchResult` shapes, event subscription semantics, cleanup behavior,
  `shellMode` registrar handoff, or registrar options/teardown contract frozen
  above.
- Contracts appear to require raw media URLs, headers, tokens, native handles,
  libmpv objects, engine ids, raw Plex payloads, stream keys, part keys, or
  secret diagnostics.
- The fake host seam becomes a hidden production native implementation or
  production player commands would appear to succeed against the fake host.
- Smoke proof cannot exercise the player preload/main path without real native
  playback.
- Player event delivery cannot avoid stale listener/state corruption after
  cleanup.
- `npm run verify:docs`, `npm run typecheck`, `npm run test:contracts`,
  `npm run smoke:electron`, `npm run verify:redaction`, or `npm run verify`
  fails for an in-scope reason that cannot be fixed inside the reviewed scope.
- Unrelated dirty files would need to be modified, staged, reverted, or
  interpreted as RD-07 evidence.

## Rollback Notes

Rollback for this planner refresh:

- Revert only
  `docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md` to its
  previous reviewed state or replace it with a newly reviewed plan.
- Do not touch unrelated dirty files, roadmap, architecture docs, package files,
  or product source.
- Rerun `git status --short --branch` and `npm run verify:docs` after any plan
  rollback or replacement.

Rollback for the next reviewed runtime IPC/preload unit:

- Revert only reviewed RD-07 changes in the files listed for
  `desktop-player-runtime-ipc-preload-delivery`.
- Remove `src/main/player/playerIpc.ts` and any focused new test file only if
  they were created by that unit and are no longer used.
- Restore the previous `LineupDesktopPreloadApi` shape and smoke assertions if
  player preload delivery is rolled back.
- Remove the reviewed player IPC channel literals and `PlayerIpcResult` /
  `PlayerDispatchResult` additions only if no reviewed follow-up depends on
  them.
- Restore the pre-player production policy if the runtime unit is rolled back,
  ensuring no fake-host production success path remains.
- Do not revert the completed adapter boundary core unless the reviewed
  rollback explicitly identifies a regression introduced by the runtime unit.
- No package, lockfile, Plex, scheduler, renderer UI, native helper, RD-06 tool,
  import ledger, or upstream source rollback should be needed because those
  files are out of scope. If they changed, stop and adjudicate before reverting
  anything not created by the RD-07 unit.
- Delete accidental local-only scratch output or ignored run artifacts created
  during implementation. Do not stage generated artifacts.
- Rerun `git status --short --branch` and the verification commands named above
  before closeout.

Rollback for the later Windows native-host proof unit must be defined in that
future reviewed packet. Do not reuse the Mac runtime rollback notes for native
process or Windows evidence work.

## Commit Checkpoints

Checkpoint 1: RD-07 continuation plan refresh only.

- Commit only after this plan is refreshed, `npm run verify:docs` passes, and
  read-only plan review is clean.
- Suggested commit: `docs: refresh rd-07 player runtime plan`
- Include only
  `docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md`.
- Do not include unrelated dirty plans or user work.

Checkpoint 2: reviewed Mac runtime IPC/preload delivery only.

- Commit only after clean plan review, scoped implementation,
  `npm run typecheck`, `npm run test:contracts`, `npm run smoke:electron`,
  `npm run verify:redaction`, and `npm run verify` pass, and read-only
  implementation review is clean.
- Suggested commit: `feat: wire player ipc preload runtime`
- Include only reviewed RD-07 runtime IPC/preload files. Do not include package,
  lockfile, Plex, scheduler, renderer UI import, native helper, upstream import,
  generated, local-only, or unrelated dirty files.

Checkpoint 3: later Windows native-host proof.

- Do not start from this Mac implementation pass.
- A separate reviewed execution unit must define its own commit scope,
  verification, redacted evidence, rollback, and handoff.

Checkpoint 4: blocked closeout.

- If runtime IPC/preload delivery cannot stay bounded, stop without product
  implementation commits.
- Update this plan only if the controller explicitly asks for a blocked replan
  artifact, then run `npm run verify:docs`.
- Suggested commit if a blocked plan update is applied:
  `docs: mark rd-07 runtime player ipc blocked`

MODEL_SUGGESTION
PLANNER: planner with high reasoning; exact `gpt-5-codex` may be approximated by available models.
IMPLEMENTER: worker with high reasoning; exact `gpt-5-codex` may be approximated by available models.
REVIEWER: reviewer with high reasoning; exact `gpt-5-codex` may be approximated by available models.
WHY: RD-07 touches Electron IPC/security, preload API shape, main composition ownership, player contracts, native playback boundaries, redaction, and Tier 3 review gates.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-plan
TASK: Plan RD-07 Windows native-host proof
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md
ARTIFACT: reviewed RD-07 boundary core and runtime IPC/preload implementation
FILES:
- docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md
- AGENTS.md
- docs/AGENTIC_DEV_WORKFLOW.md
- docs/agentic/session-prompts/feature-plan.md
- docs/agentic/plan-authoring-standard.md
- docs/architecture/CURRENT_STATE.md
- docs/roadmap/desktop-port-roadmap.md
- docs/architecture/playback-architecture.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/upstream-behavior-guardrails.md
- src/contracts/player.ts
- src/contracts/ipc.ts
- src/contracts/shell.ts
- src/main/player/desktopPlayerAdapter.ts
- src/main/player/nativePlayerHostPort.ts
- src/main/player/playerIpc.ts
- src/preload/index.cts
- src/main/index.ts
- src/__tests__/desktopPlayerAdapter.test.ts
- src/__tests__/contracts.test.ts
- src/__tests__/playerIpc.test.ts
- package.json
BLOCKERS: none for planning; Windows native-host implementation must not begin until its plan or execution packet is reviewed clean.
MESSAGE:
Plan the remaining RD-07 `desktop-player-windows-native-host-proof` unit. Preserve the reviewed `desktop-player-adapter-boundary-core` and `desktop-player-runtime-ipc-preload-delivery` surfaces. The next unit must target the RD-06 app-owned native presentation direction on Windows, name exact native-host files, commands, redacted evidence paths, manual/proof expectations, rollback, and stop conditions, and must prove real native-host integration without exposing Plex tokens, raw URLs, auth headers, native handles, libmpv objects, engine ids, raw Plex payloads, stream keys, part keys, or secret diagnostics to renderer-facing state. It must not reopen WID or helper-owned render API without a separate reviewed replan, and it must not treat macOS IPC/preload smoke as native playback proof.
