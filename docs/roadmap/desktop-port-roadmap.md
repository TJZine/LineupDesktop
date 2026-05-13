# Desktop Port Roadmap

This is the durable checklist for the Windows-first Lineup Desktop port. It
turns the GPT Pro handoff report and the accepted repo-genesis decisions into an
ordered path for future plans.

This is not an implementation plan for any single slice. Each serious in-flight
slice still needs its own active tracked plan under
[`docs/plans/`](../plans/README.md) that follows
[`docs/agentic/plan-authoring-standard.md`](../agentic/plan-authoring-standard.md).
Completed full plan bodies are local archive material; this roadmap keeps the
durable completion summary.

## Current Position

- [x] Separate Desktop repo created.
- [x] Electron shell direction accepted.
- [x] Helper-hosted native libmpv production hypothesis accepted.
- [x] External `mpv` allowed only as a disposable private POC.
- [x] Single-package repo shape accepted for the initial port.
- [x] Workflow, skills, launchers, role config, docs verifier, redaction
  verifier, and architecture lint scaffolded.
- [x] First active implementation plan created for the Electron shell security
  foundation, then closed and archived locally after completion.
- [x] First active implementation plan reviewed.
- [x] Secure Electron shell foundation implemented at `b8fb948`; `npm run
  smoke:electron` and `npm run verify` passed on 2026-05-08.
- [x] Secure Electron shell foundation implementation reviewed and clean after
  one blocker fix, per RD-01 agent closeout report provided on 2026-05-08.
- [x] Product reuse/import sequence formalized through the RD-02 source
  reuse/import strategy and archived locally after completion.
- [x] Player contract and capability model completed through RD-03 quality loop:
  `src/contracts/player.ts`, `src/contracts/ipc.ts`, and
  `src/__tests__/contracts.test.ts`; `npm run verify` passed and
  implementation review was clean on 2026-05-08.
- [x] RD-04 upstream behavior guardrails completed through
  `docs/architecture/upstream-behavior-guardrails.md`; `npm run verify` passed
  and scoped implementation review was clean on 2026-05-08.
- [x] RD-05 external `mpv` POC completed through its reviewed plan;
  `tools/mpv-poc/rd-05-external-mpv-poc.mjs` remains a dev-only disposable
  script, ignored redacted run evidence exists under
  `docs/runs/rd-05-external-mpv-poc/`, `npm run verify` passed, and
  implementation review was clean on 2026-05-08.
- [x] RD-06 Windows native libmpv WID and render API smokes have partial local
  redacted proof through
  `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`, but both fail
  fullscreen video-surface proof. The revised app-owned native presentation
  probe now records passing Windows proof under the stricter fullscreen,
  cleanup, and render-thread semantics. Clean implementation re-review reported
  no material blockers, so RD-06 can route RD-07.
- [x] RD-07 Desktop VideoPlayer Adapter boundary core implemented through
  `src/main/player/desktopPlayerAdapter.ts`,
  `src/main/player/nativePlayerHostPort.ts`, and
  `src/__tests__/desktopPlayerAdapter.test.ts`; `npm run verify` passed and
  read-only implementation re-review was clean on 2026-05-10. Runtime
  main/preload player IPC delivery is also implemented through
  `src/main/player/playerIpc.ts` and `window.lineupDesktop.player`, backed only
  by a development/smoke fake host with production unsupported/noop behavior.
  A native-host process seam exists at
  `src/main/player/nativePlayerHostProcess.ts` with lifecycle, cleanup/reap,
  failure-normalization, stale/late output, real spawned helper test-double
  proof, and redaction tests. RD-07 closeout reran the RD-06 app-owned
  native-presentation preflight/smoke on Windows and observed passing redacted
  native surface proof. Renderer UI wiring, Plex stream setup, and a production
  native helper remain future RD-12/RD-13 work.
- [x] RD-08 Desktop Stream Policy fixture core implemented through
  `src/main/player/streamPolicy/desktopStreamPolicy.ts`,
  `src/main/player/streamPolicy/types.ts`, and
  `src/__tests__/desktopStreamPolicy.test.ts`; `npm run verify` passed and
  read-only implementation review was clean on 2026-05-10. Windows closeout
  added a conservative RD-06/RD-07 capability/sample matrix that preserves
  unknowns instead of claiming exact Windows codec/container/audio support, and
  fixed unsupported fallback reason preservation. The unit is deterministic and
  fixture-driven only: no live Plex contact, secure storage, renderer UI,
  native helper, package/dependency change, runtime IPC wiring, Plex HTPC parity
  claim, or copied/adapted upstream source landed.
- [x] RD-09 Secure Storage And Persistence Boundary implemented through
  `src/contracts/persistence.ts`, `src/main/persistence/*`, and
  `src/__tests__/persistenceBoundary.test.ts`; `npm run verify` passed on
  2026-05-10. The unit adds main-owned app-data path resolution, an injected
  Electron safeStorage codec seam, encrypted Plex credential records,
  selected-server state, unavailable/corrupt classification, fail-closed
  no-plaintext fallback, renderer-safe snapshots, and forbidden-field tests.
  It does not wire Plex auth/discovery/library runtime, preload/renderer APIs,
  network transport, scheduler/channel persistence, backup/restore
  implementation, package/dependency changes, or copied/adapted upstream
  source.
- [x] RD-10 Plex Auth, Discovery, And Library Import implemented through
  `src/contracts/plex.ts`, `src/main/plex/library/*`,
  `src/main/plex/auth/*`, `src/main/plex/discovery/*`,
  `src/__tests__/plexLibrary.test.ts`, `src/__tests__/plexAuth.test.ts`, and
  `src/__tests__/plexDiscovery.test.ts`; `npm run verify` passed on
  2026-05-10 with 113 contract tests and 69 harness-doc tests. The unit adds
  imported/adapted main-owned Plex library parsers/domain helpers, auth
  parsers/service/storage seam, discovery/selected-server domain, recursive
  renderer-safe forbidden-field checks, and import-ledger rows. All runtime
  Plex behavior remains behind injected fakes/seams; no live Plex transport,
  preload/renderer Plex API, `src/main/index.ts` composition, real Electron
  safeStorage/app-path runtime wiring, package/dependency change, stream
  resolver/runtime playback URL setup, scheduler/channel persistence, or
  backup/restore implementation landed. Platform proof remained Mac/local
  automated only, and no Windows gate was triggered.

The GPT Pro report was written against the original Lineup app shape. This repo
is a separate Desktop repo with no production runtime yet, so the first local
slice is the secure Electron shell foundation. Product-port work starts only
after that shell proves the main/preload/renderer boundary.

## How To Use This Roadmap

1. Read this roadmap after `AGENTS.md`, the workflow runbook, current
   architecture state, and the active plan.
2. Finish the current active plan first. Active plans own the current execution
   unit; this roadmap owns sequencing between plans.
3. Pick the next unchecked roadmap slice whose `Depends on` gates are complete.
4. Route Tier 3 roadmap slices through the feature-quality-loop controller so
   the next session owns the whole roadmap item: planning, plan review, bounded
   execution-unit selection, implementation, implementation review, verification,
   closeout, and platform proof unless a blocker stops the loop.
5. Create or update one active tracked plan for that roadmap item in
   `docs/plans/`. The plan should cover the whole item and split implementation
   into bounded execution units only when that improves reviewability.
6. Keep implementation limited to the plan's current approved execution unit.
7. On closeout, update this roadmap only for observed status changes. Archive
   completed full plan bodies locally after durable conclusions are reflected in
   tracked docs.
8. End the session with the workflow runbook's `NEXT_SESSION_HANDOFF` shape,
   routing the next session to the next roadmap slice's plan, review, or
   implementation step.

Do not use this roadmap to batch multiple product slices into one broad
implementation. Its purpose is sequencing and dependency clarity.

## Platform Proof Convention

Each roadmap item should make platform proof explicit in its tracked plan and,
when useful, in this checklist. Use one of these labels:

- `Mac/local automated proof sufficient`: local typecheck, lint, contract,
  verifier, and source-audit proof can close the item.
- `Windows proof required before closeout`: the item cannot be marked complete
  until a Windows run observes the named behavior.
- `Windows proof deferred to <RD item>`: the item may close without Windows
  proof only because a later-named roadmap item owns that platform evidence.

If a roadmap item touches Electron OS behavior, native playback, Windows app
paths, credential availability, packaging, signing, installer behavior, or
live Plex/network behavior that cannot be proven by injected seams, assume
Windows proof is required unless the tracked plan records a narrower reviewed
reason.

## Next-Handoff Rule

When a roadmap slice reaches its exit gates:

- update `Status` only when the evidence was observed in this repo or explicitly
  recorded as unavailable
- update architecture docs or the import ledger when the slice changes ownership
  or imports/adapts upstream Lineup source
- emit one pasteable `NEXT_SESSION_HANDOFF`
- route to `lineup-desktop-feature-quality-loop` when the next roadmap slice is
  Tier 3 and should be carried through whole-item planning, review, bounded
  implementation units, implementation review, verification, platform proof,
  and closeout in one orchestrated workflow
- route to `lineup-desktop-feature-plan` when the next slice does not yet have a
  tracked plan
- route to `lineup-desktop-feature-review` when a plan or implementation needs
  adversarial review
- route to `lineup-desktop-feature-implement` only after the relevant plan
  review is clean

RD-01 through ARCH-01 are complete enough to route the next Tier 3 session to
RD-14 Window, Input, And Fullscreen UX through the quality loop. Do not import
additional original Lineup product code until a reviewed product slice plan
explicitly authorizes a bounded import.

## Roadmap Checklist

### RD-00 Repo Genesis And Control Plane

Status: complete.

Depends on:

- none

Objective:

- Establish the separate Desktop repo, control plane, architecture docs, import
  ledger, role config, verifier scripts, baseline contracts, and active first
  plan.

Exit gates:

- `npm run verify` passed for the control-plane scaffold before product
  implementation.

### RD-01 Secure Electron Shell Foundation

Status: complete. Implemented at `b8fb948`; `npm run smoke:electron` and
`npm run verify` passed on 2026-05-08; implementation review was clean after one
blocker fix, per RD-01 agent closeout report provided on 2026-05-08.

Depends on:

- RD-00 complete.
- Active plan review was clean before implementation.

Objective:

- Create the first secure Electron process skeleton: main owns lifecycle and
  privileged IPC, preload exposes a narrow typed bridge, renderer remains
  unprivileged, and smoke verification proves renderer privilege denial.

Exit gates:

- Electron main/preload/renderer shell implemented inside the active plan scope.
- Architecture lint covers new directories.
- Contract/redaction tests cover renderer-safe API and forbidden privileged
  fields.
- `smoke:electron` proves boot, bridge availability, renderer privilege denial,
  navigation containment, new-window denial, permission denial, CSP containment,
  and clean exit.
- If the local environment cannot run `smoke:electron`, the slice is not
  complete; record the blocker and hand off to resolve the smoke environment or
  rerun proof in a capable environment.
- `npm run verify` passes.
- Implementation review is clean.

Next handoff:

- Mark RD-01 complete only after the smoke proof and implementation review are
  complete.
- Create the RD-02 tracked plan before importing product code.

### RD-02 Source Reuse Inventory And Import Strategy

Status: complete. Tracked plan exists, plan review is clean, and docs-only
implementation review is clean.

Depends on:

- RD-01 complete.

Objective:

- Convert the original Lineup codebase into a concrete Desktop import map:
  direct reuse, adapted reuse, example-only reference, and do-not-import.

Likely source references:

- Original Lineup Plex auth/discovery/library/stream modules.
- Original Lineup scheduler/channel/content modules.
- Original Lineup player, platform, navigation, EPG, OSD, settings, storage, and
  redaction modules.
- Original Lineup tests that protect stable behavior.
- GPT Pro handoff report sections on reusable slices, risk register, phase
  table, and first-task recommendations.

Exit gates:

- A tracked plan or architecture note names the first product import order and
  this roadmap is updated if that order differs from the current sequence.
- Import-ledger obligations are explicit for every copied or adapted slice.
- Original Lineup behavior used as a functionality target is separated from code
  that will actually be copied.
- Any upstream verification relied on is observed and recorded, or explicitly
  marked unavailable.

Stop and replan if:

- A proposed import requires renderer custody of credentials, raw auth headers,
  tokenized media URLs, native handles, Node APIs, Electron APIs, or raw IPC.
- The import would force broad compatibility shims, root barrels, or old path
  mirrors.
- The import would make Desktop architecture depend on webOS playback constants
  as capability truth.

### RD-03 Player Contract And Capability Model

Status: complete. `npm run verify` passed and read-only implementation review
was clean on 2026-05-08.

Depends on:

- RD-01 complete.
- RD-02 complete enough to identify reusable player and stream concepts.

Objective:

- Define platform-neutral player contracts before real desktop playback work:
  commands, state, events, request ids, capability profiles, track ids, error
  taxonomy, and renderer-safe diagnostics.

Reuse target:

- Original Lineup player interfaces, descriptor builder behavior, stream
  metadata mapping, and current UI expectations.

New Desktop design:

- Opaque renderer-facing track ids.
- No raw media URLs, headers, engine ids, native handles, or libmpv-specific
  objects in renderer-facing state.
- Capability-driven stream policy surface that can support webOS reference
  behavior, external POC behavior, and native libmpv without conflating them.

Exit gates:

- Contract tests cover player state, event staleness, request ids, diagnostics,
  and forbidden privileged fields.
- No Electron, libmpv, Node, or webOS constants leak into shared contract truth.

### RD-04 Upstream Behavior Guardrails

Status: complete. Implemented through
`docs/architecture/upstream-behavior-guardrails.md`; `npm run verify` passed
and scoped implementation review was clean on 2026-05-08.

Depends on:

- RD-02 complete.
- RD-03 complete for player-facing contracts.

Objective:

- Lock behavior that Desktop must preserve or intentionally diverge from before
  shared Plex, scheduler, player, or UI imports begin.

Reuse target:

- Original Lineup tests and behavior around stream decisions, subtitle/audio
  fallback, deterministic scheduling, channel persistence, navigation focus,
  EPG virtualization, settings state, and redaction.

Exit gates:

- For each planned imported product slice, Desktop has a test, fixture, source
  audit, or explicit rationale showing how preserved behavior will be protected.
- Any intentional Desktop divergence is documented before implementation.
- Original Lineup behavior is treated as reference evidence, not automatic
  Desktop architecture truth.
- `docs/architecture/upstream-behavior-guardrails.md` exists and docs
  verification fails if required slice coverage is removed.

### RD-05 External mpv POC

Status: complete. Implemented through
`tools/mpv-poc/rd-05-external-mpv-poc.mjs` and
`tools/__tests__/rd-05-mpv-poc.test.mjs`; `npm run verify` passed and
read-only implementation review was clean on 2026-05-08.

Depends on:

- RD-03 complete.
- RD-04 complete enough to know which playback behaviors need proof.

Objective:

- Run a short, disposable, dev-only external `mpv` IPC POC to learn media facts:
  stream loading, safe header handling, start offsets, channel-switch timing,
  subtitle/audio track enumeration, command/event loop behavior, and cleanup
  behavior.

Non-goals:

- No production architecture commitment.
- No installer/package changes.
- No UI redesign.
- No broad Plex, scheduler, or renderer UI import.

Exit gates:

- POC results are documented with what was proven, what failed, and whether the
  POC is deleted or quarantined behind a dev-only flag. RD-05 quarantines the
  script as dev-only with no package script and keeps run evidence ignored.
- Stop/channel-switch behavior is documented from redacted evidence: `stop`
  succeeded and cleanup completed, while four sanitized post-stop events before
  quit remain an RD-06/RD-07 stale-event follow-up risk rather than accepted
  production behavior.
- No tokenized URLs or raw auth headers appear in process args, logs, crash
  output, IPC traces, fixtures, docs, or Codex output.

### RD-06 Native libmpv Host Spike

Status: complete. Revised Windows WID and render API
smokes prove windowed active video, overlay pixels, focus, dummy HTTP, helper
crash detection, redaction, and libmpv API evidence, but both fail the required
fullscreen video-surface proof. The amended render API helper-owned Win32
screen-pixel fallback was scoped to the render child surface and gated on
BrowserWindow fullscreen, but it also reported fullscreen pixels as not
captured. The render API smoke also records render-thread discipline and
composition proof as not proven by this helper loop. The revised app-owned
native presentation probe records passing Windows smoke proof under stricter
fullscreen, cleanup, and render-thread semantics, and clean implementation
re-review reported no material blockers. RD-07 can rely on the app-owned native
presentation boundary as its native surface direction.

Depends on:

- RD-05 complete, unless a reviewed plan explains why the POC is unnecessary.

Objective:

- Prove the production playback path on Windows before broad product imports:
  helper-hosted native libmpv first, with addon exploration only if the helper
  path cannot meet overlay or surface requirements.

Required proof:

- Local dummy visual file playback.
- Plex-like dummy HTTP playback using only the approved non-secret dummy header.
- Windowed and borderless fullscreen rendering.
- Overlay visibility above video.
- Renderer focus/input continuity.
- Audio/subtitle track observation and selection.
- Command/event loop behavior, including stop and channel-switch ordering.
- Helper crash detection without killing the Electron UI.
- Stale native events cannot corrupt the current playback request.
- DPI and multi-monitor behavior acceptable for MVP.
- Redacted native logs.
- libmpv client API/version evidence.

Exit gates:

- Helper-vs-addon/native-surface decision recorded from evidence. The current
  WID and helper-owned render API smokes do not prove enough to route directly
  to RD-07; the next reviewed proof must decide whether an app-owned native
  presentation boundary is viable or whether RD-06 needs another blocked
  conclusion/replan.
- Licensing/provenance questions captured before public packaging work.
- Native video/overlay/focus risk is either accepted with evidence or triggers a
  replan before broad renderer UI, Plex/player integration, or packaging work.

Observed RD-06 proof:

- Dev-only source-controlled spike tooling exists under `tools/libmpv-spike/`
  with a focused harness test under `tools/__tests__/`.
- Ignored redacted evidence under
  `docs/runs/rd-06-native-libmpv-host-spike/` records local dummy visual media,
  dummy HTTP visual media with the approved non-secret header, windowed
  active-playback video pixels, overlay pixels, focus, helper crash detection,
  temp cleanup, libmpv client API/version evidence, and no forbidden header
  observation.
- Render API evidence additionally records render API symbol availability,
  render-context creation, app-owned input simulation, render-frame proof, and
  the failed helper-owned Win32 screen-pixel fallback scoped to the render child
  surface.
- Render API evidence does not prove render-thread discipline or composition
  because this helper loop mixes blocking libmpv/event calls with render API
  work and merged capture sources are not sufficient z-order proof.
- The same evidence records fullscreen video-surface proof as not captured,
  including through the amended native fallback, so the WID and render API
  smokes exit failed instead of overclaiming RD-06 completion.
- Revised app-owned native presentation evidence records fullscreen active
  video pixels and fullscreen-composition only after native fullscreen entry and
  settle, fresh bounded render-loop progress, helper cleanup/reap evidence after
  child exit, and no forbidden persisted fields.
- Track selection and subtitle behavior are not proven by the tiny dummy visual
  input.
- DPI and multi-monitor behavior still need a stronger manual matrix before
  packaging or UI-over-video hardening.

### RD-07 Desktop VideoPlayer Adapter

Status: complete. The `desktop-player-adapter-boundary-core` unit is implemented
and reviewed clean. The `desktop-player-runtime-ipc-preload-delivery` unit is
implemented and reviewed clean with development/smoke fake-host delivery and
production unsupported/noop behavior. The
`desktop-player-native-host-process-seam` unit adds fakeable process
lifecycle plumbing, cleanup/reap behavior, safe failure normalization, stale/late
output handling, and redaction tests. The Windows closeout unit adds real
spawned helper process proof for the RD-07 process seam and reruns the RD-06
app-owned native-presentation preflight/smoke as passing redacted native surface
proof. The real production native helper, Plex stream setup, and renderer UI
remain unimplemented.

Depends on:

- RD-03 complete.
- RD-06 complete.

Objective:

- Implement the Desktop player adapter against the approved player contract and
  bridge/native-host boundary.

Exit gates:

- Adapter boundary tests cover command mapping, state, events, errors, stale
  request handling, diagnostics, helper crash behavior, request cleanup,
  renderer intent validation, fake-host event validation, and renderer-safe
  validation failures for the core fake-host seam.
- Renderer receives only renderer-safe player state through the contract-bound
  adapter core and narrow runtime player preload bridge. The bridge remains
  fake-host-backed only in development/smoke until real native host integration
  lands.
- Process-seam tests cover native-host lifecycle, cleanup/reap, real spawned
  helper startup/exit, failure normalization, malformed output, stale/late
  output, and forbidden-field exclusion.
- Windows native surface proof is observed through the existing RD-06 app-owned
  native-presentation preflight/smoke without reopening WID, helper-owned render
  API, product native helper, Plex, renderer, package, or dependency scope.
- `App.ts` and orchestration owners do not absorb native process policy.

### RD-08 Desktop Stream Policy

Status: complete. The deterministic `desktop-stream-policy-fixture-core` unit is
implemented and reviewed clean. It adds a main/player-owned pure policy module
plus focused fixtures/tests for direct play, direct stream, transcode,
unsupported decisions, audio fallback, subtitle fallback, HDR/Dolby Vision
handling, stable reason codes, explicit unknowns, and recursive forbidden-field
invariants. Windows closeout adds a conservative RD-06/RD-07 capability/sample
matrix that preserves unknowns instead of claiming exact Windows
codec/container/audio, direct stream, transcode, track switching, subtitle,
HDR, Dolby Vision, or Plex HTPC parity support. No Plex runtime, secure storage,
renderer UI, native helper, package/dependency change, runtime IPC wiring, Plex
HTPC parity claim, or copied/adapted upstream source was introduced.

Depends on:

- RD-03 complete.
- RD-04 complete.
- RD-07 complete enough to define player capability facts.

Objective:

- Add Desktop capability-driven Plex stream decisions while preserving the
  original webOS/browser behavior as a separate capability profile or upstream
  reference.

Exit gates:

- Desktop decisions are driven by capability profile, not webOS constants.
- Direct play, direct stream, transcode, subtitle fallback, audio fallback, and
  HDR decisions have tested reasons or explicit unknowns.
- No Plex HTPC parity claim exists without sample-matrix evidence.

### RD-09 Secure Storage And Persistence Boundary

Status: complete. `npm run verify` passed on 2026-05-10.

Depends on:

- RD-01 complete.
- RD-02 complete enough to identify credential and storage owners.

Objective:

- Establish Desktop credential and app-data ownership before real Plex auth
  import reaches production behavior.

Reuse target:

- Original Lineup storage owner patterns, validation, channel/settings
  repositories, and redaction conventions.

New Desktop design:

- Electron main owns persistent credential storage and app data paths.
- Renderer receives safe auth/profile/server state only.
- UI modules never call Electron secure-storage APIs directly.

Exit gates:

- Credential/store interfaces are typed and tested through
  `src/contracts/persistence.ts`, `src/main/persistence/*`, and
  `src/__tests__/persistenceBoundary.test.ts`.
- Renderer-facing contracts cannot carry credential-like secret material; tests
  recursively reject forbidden persistence fields.
- Backup/restore, unavailable secure-storage behavior, fail-closed
  no-plaintext fallback, corruption handling, and redacted diagnostics
  expectations are documented.

### RD-10 Plex Auth, Discovery, And Library Import

Status: complete. Implemented through the RD-10 Tier 3 quality loop with clean
Unit 1, Unit 2, and Unit 3 implementation reviews, plus Mac/local automated
proof. No Windows proof was required because the completed scope remained pure
main-owned domain/storage-seam code with injected fake transport/storage and no
real Electron app-path/safeStorage runtime, live Plex auth/discovery, or
OS-specific credential behavior.

Depends on:

- RD-02 complete.
- RD-04 complete for Plex behavior guardrails.
- RD-09 complete.

Objective:

- Bring over Plex auth, server discovery, selected server state, library,
  metadata, collections, playlists, search, and image behavior behind Desktop
  storage and redaction boundaries.

Reuse target:

- Original Lineup Plex auth/discovery/library modules and associated tests where
  they are platform-neutral.

New Desktop design:

- Main-owned credential persistence.
- Renderer-safe server/profile/library state.
- No token-bearing logs, fixtures, IPC payloads, diagnostics, or Codex output.

Exit gates:

- Import ledger updated before or with the import.
- Auth/discovery/library tests pass.
- Redaction verifier covers imported files and new fixtures.
- No renderer credential custody.
- Platform proof: Mac/local automated proof is sufficient for pure imported
  domain/storage-seam units. Windows proof is required before closeout if the
  RD-10 plan wires real Electron safeStorage runtime, app paths, live Plex
  auth/discovery, or any OS-specific credential behavior.

Observed closeout:

- `npm run verify` passed on 2026-05-10 with 113 contract tests and 69
  harness-doc tests.
- `src/main/plex/library/*` owns library metadata parsing, pagination/search,
  collections, playlists, tag directories, and renderer-safe summaries without
  live fetch/cache/image URL or stream resolver runtime.
- `src/main/plex/auth/*` owns injected-transport PIN/profile/token validation,
  Plex Home users, profile switching, sanitized errors, and fail-closed RD-09
  credential storage behavior without live Plex transport or renderer/preload
  auth API.
- `src/main/plex/discovery/*` owns injected-transport resource discovery,
  connection probing policy, health classification, stale-context invalidation,
  and selected-server restore by server id plus fresh probing. Selected
  connection details remain main-memory only and are not persisted or returned
  through renderer-safe contracts.
- `src/contracts/plex.ts` owns renderer-safe Plex summary contracts and
  recursive forbidden-field checks.
- `docs/architecture/import-ledger.md` records the upstream Plex
  library/auth/discovery and selected-server source adaptations at the pinned
  upstream commit.

### RD-11 Scheduler, Channel, And Content Domain Import

Status: complete.

Depends on:

- RD-02 complete.
- RD-04 complete for scheduler/channel behavior guardrails.
- RD-09 complete enough to define channel/settings persistence ownership.

Objective:

- Import deterministic scheduling, channel management, content resolution,
  channel persistence shape, and lineup state behind Desktop storage owners.

Reuse target:

- Original Lineup `ChannelManager`, `ChannelScheduler`, content resolver,
  channel repository/store patterns, and tests.

Exit gates:

- Import ledger updated before or with the import.
- Deterministic schedule behavior is protected by tests.
- Channel persistence is behind typed owners.
- No scheduler or channel logic enters Electron main/preload.

Completion notes:

- Imported/adapted pure scheduler, playback ordering, channel authoring,
  content resolution, lineup navigation, cache, retry, import/export
  normalization, channel repository/store, save queue, coordinator, and separate
  main-owned channel persistence adapter under reviewed Desktop owners.
- Added `src/domain/**` architecture linting to keep domain logic free of
  Electron, Node, main/preload/renderer/native-helper imports, dynamic owner
  imports, and runtime globals.
- Protected anchor-time scheduling, loop wrapping, current/next/previous lookup,
  schedule windows, shuffle seed behavior, block validation, channel authoring
  validation, content resolution, stale fallback, import normalization,
  transactional updates, cache cloning, persistence queues, malformed storage
  recovery, and forbidden persistence fields with local automated tests and
  implementation review.
- Platform proof: Mac/local automated proof is sufficient because RD-11 did not
  wire Electron app paths, real safeStorage, preload/renderer APIs, live Plex
  network transport, native playback, packaging, installer behavior, or Windows
  runtime behavior.

### RD-12 Plex To Player Integration

Status: complete.

Depends on:

- RD-07 complete.
- RD-08 complete.
- RD-10 complete enough to resolve stream inputs.
- RD-11 complete enough to provide scheduled playback inputs.

Objective:

- Wire Plex stream decisions, playback descriptors, player adapter, channel
  switching, and PMS cleanup into Desktop runtime without bloating composition
  roots.

Exit gates:

- Stop, switch, error, logout, server change, profile change, helper crash,
  teardown, failed resolver, failed player load, stale candidate, and rejected
  lease paths are covered by the main-owned playback runtime with request/epoch
  custody and PMS cleanup.
- The Plex stream resolver applies RD-08 policy through injected selected
  connection, credential, media-detail, and PMS-session ports, then separates
  private playback setup from renderer-safe player load payloads.
- Scheduler/channel playback mapping stays behind a main/player bridge, and
  orchestration wiring is exposed as a thin injected composition seam.
- Tokens, auth headers, raw Plex payloads, tokenized URLs, runtime filesystem
  paths, Electron/Node objects, and native/helper internals do not reach
  renderer-facing contracts, fixtures, diagnostics, or docs.

Closeout:

- Implementation: `src/main/player/plexPlaybackRuntime.ts`,
  `src/main/plex/streamResolver.ts`, `src/main/player/plexPlaybackBridge.ts`,
  and `src/main/player/plexPlaybackComposition.ts`.
- Proof: `npm run verify` passed on 2026-05-11 with typecheck, architecture
  lint, 249 contract tests, 88 harness-doc tests, docs verification, and
  redaction verification.
- Platform proof label: Mac/local automated proof sufficient. RD-12 remains
  injected/fakeable and does not enable production native-helper playback, real
  Electron app-path or `safeStorage` runtime wiring, packaging, Windows-specific
  proof surfaces, preload/renderer Plex APIs, or additional upstream product
  imports.

### RD-13 Renderer UI And Navigation Import

Status: complete. Unit 1 app shell/navigation foundation completed on
2026-05-12 through the RD-13 quality loop: renderer-owned shell/routes/focus,
Node-safe navigation tests, and the narrow sandboxed-preload smoke unblocker
landed with clean implementation review. Unit 2 fake-backed route/workflow
skeleton also completed on 2026-05-12 with renderer-local fake view models,
route action transitions, Node-safe workflow tests, and clean implementation
review after one status-text fix. Unit 3 settings/channel setup details
completed on 2026-05-12 with renderer-local fake settings/setup state,
Desktop-safe copy, local-only settings/setup actions, Node-safe workflow tests,
and clean implementation review. Unit 4 fake-backed EPG completed on
2026-05-12 with renderer-local schedule state, deterministic UTC fake schedule
formatting, guide grid/detail rendering, Node-safe EPG tests, and clean
implementation re-review after fixing time-format and smoke-reachability
findings. `npm run smoke:electron`, the RD-13 renderer/domain source audit, and
`npm run verify` passed locally after Unit 4, with smoke now asserting Guide/EPG
route reachability. Unit 5 fake-backed OSD/mini-guide/overlays completed on
2026-05-12 with renderer-local overlay state, now-playing, mini guide, channel
number, channel badge, playback options, focus fallback behavior, Node-safe
overlay tests, and clean implementation re-review after two focus fixes.
`npm run smoke:electron`, the RD-13 renderer/domain source audit, and `npm run
verify` passed locally after Unit 5, with smoke asserting overlay reachability.
Unit 6 assets/styles completed on 2026-05-12 with renderer-local CSS
custom-property tokens, theme hooks, focus-visible normalization,
reduced-motion and forced-colors policy, responsive constraints, and loaded
style smoke assertions. `npm run smoke:electron`, the exact RD-13
renderer/domain source audit, `npm run verify:redaction`, and `npm run verify`
passed locally after Unit 6 with 283 contract tests and 88 harness-doc tests.
No upstream UI source or assets were copied or adapted in Units 1 through 6, so
no import-ledger row was needed. Platform proof label: Mac/local automated proof
sufficient.

Depends on:

- RD-06 complete, so native overlay/focus feasibility is known before broad UI
  import.
- RD-10 and RD-11 complete enough to support UI workflows, or a reviewed plan
  authorizes mocks/fakes for an earlier UI import.

Objective:

- Bring over the existing DOM TV UI as the Desktop renderer experience without
  redesigning it: app shell, navigation, EPG, OSD, mini guide, settings, channel
  setup, overlays, and relevant assets/styles.

Scope rule:

- RD-13 is a parent slice. It should be split into sub-plans for app shell,
  navigation/input-facing UI, settings/channel setup, EPG, OSD/overlays, and
  assets/styles whenever one tracked plan would become too broad to review.

Reuse target:

- Original Lineup DOM UI modules, navigation/focus model, EPG virtualization,
  settings state controllers, and UI design language.

New Desktop design:

- Renderer remains unprivileged.
- WebOS-only UI copy or settings are gated or renamed before they become
  Desktop product truth.

Exit gates:

- Renderer smoke verifies primary UI routes/workflows reachable in Electron.
- Focus/navigation tests cover Desktop input mapping where feasible.
- No webOS lifecycle, player, or packaging assumption becomes Desktop truth.

### ARCH-01 Architecture Health Stabilization Before RD-14

Status: complete. ARCH-01 completed through the feature-quality loop on
2026-05-12. It added a reviewed architecture-health plan with classifications
for every then-current file-shape guardrail row, remediated the renderer
composition, renderer static asset, main composition, and overlay prepare-now
hotspots through behavior-preserving same-owner splits, and hardened preload
bridge growth policy through the existing source-shape/parity harness without
adding preload APIs, preload bundling, Electron behavior, dependencies, or
runtime product behavior. `npm run verify:maintainability`,
`npm run verify:docs`, `npm run smoke:electron`, and `npm run verify` passed.
Plan review and every implementation-unit review were clean before closeout.
Remaining allowlisted hotspots have reviewed deferral or leave-alone triggers
that do not require RD-14 to grow monolithic renderer, main, preload, player,
Plex, or channel owners.

Depends on:

- RD-13 complete enough to expose current renderer, style, main, preload,
  contract, Plex, player, scheduler, and channel owner hotspots.
- File-shape guardrails are active through
  `docs/architecture/file-shape-guardrails.md` and
  `npm run verify:maintainability`.

Objective:

- Stabilize the codebase architecture shape before new RD-14 product behavior
  lands. Audit all current file-shape and owner-boundary hotspots created before
  the guardrails existed, then remediate or explicitly defer them with reviewed
  owner, rationale, verification, and revisit triggers.

Scope rule:

- Assessment is repo-wide, but implementation must be split into bounded
  execution units. The plan must classify every current row in
  `docs/architecture/file-shape-guardrails.md` as fix now, prepare now, defer
  with trigger, or leave alone with rationale.
- Classification semantics are binding for closeout. `Fix now` means the
  hotspot must be remediated in ARCH-01. `Prepare now` means ARCH-01 must land
  the owner split, extraction seam, test harness, or other enabling change
  needed to keep the next roadmap items from growing that hotspot. `Defer with
  trigger` means the hotspot remains but has a reviewed owner, reason, and
  future condition that forces action. `Leave alone with rationale` means review
  accepts the current shape as cohesive for this roadmap point. Any `fix now` or
  `prepare now` item not completed before closeout must be reclassified through
  a reviewed replan.
- Fix-now work should prioritize hard-overage or near-term roadmap pressure
  points, especially renderer composition, renderer CSS/HTML, main composition,
  preload bridge shape, and any large owner that would otherwise absorb RD-14 or
  RD-15 behavior.
- This item must not become a product rewrite, framework migration, dependency
  migration, upstream import, compatibility-shim pass, or cosmetic file shuffle.
  Keep behavior stable and preserve current Electron security, renderer
  privilege, preload narrowness, Plex secrecy, player/runtime, scheduler, and
  channel contracts unless a reviewed replan proves a boundary change is
  necessary for maintainability.

Platform proof:

- Mac/local automated proof is sufficient when units are behavior-preserving
  source-shape changes. Stop and obtain a reviewed replan before touching
  Windows-specific behavior, native video/fullscreen behavior, live Plex
  transport, production native-helper playback, packaging/signing/update
  behavior, app-path or safeStorage runtime wiring, or new preload/renderer
  APIs.

Exit gates:

- Tracked plan includes an `## Architecture Health` section with current
  large-file evidence, owner-boundary risks, and a classification for every
  allowlisted file.
- Every implemented cleanup unit is behavior-preserving or has explicit
  contract/test proof for any public seam it changes.
- `docs/architecture/file-shape-guardrails.md` is updated for any remediated,
  deferred, or newly identified hotspot.
- `npm run verify:maintainability`, `npm run verify:docs`, and `npm run verify`
  pass unless the reviewed plan names a narrower proof for a docs-only unit.
- Read-only adversarial review is clean for the plan and for every implemented
  unit.
- RD-14 may start only after remaining deferred hotspots have reviewed triggers
  that will not force RD-14 to grow monolithic owners, and no `fix now` or
  `prepare now` classifications remain incomplete.

### RD-14 Window, Input, And Fullscreen UX

Status: in progress. Active plan:
`docs/plans/rd-14-window-input-fullscreen-ux.md`. Unit 1, renderer desktop
input and focus policy, is complete after clean plan review and clean
implementation review. It added a focused renderer input owner for keyboard,
text-entry bypass, browser-safe gamepad normalization/polling, and fullscreen
dispatch over existing renderer navigation/focus behavior. Unit 2, main
window/fullscreen/display owner module, is complete after clean implementation
re-review. It moved BrowserWindow creation/options, fullscreen intent
execution, normal bounds capture, display id custody, and restore/fallback
placement policy into a focused main-owned controller while preserving the
existing `window.setFullscreen(boolean)` response shape. `npm run verify`
passed on 2026-05-13 after both units. Unit 3, foreground
app-command/media-key bridge, is complete after clean implementation re-review.
It added a focused main-owned foreground app-command controller that forwards
`browser-backward` to the existing renderer back path through synthetic
`Escape` input, intentionally ignores `browser-forward`, leaves media commands
unhandled for Windows/manual proof, and adds no preload, IPC, contract,
`globalShortcut`, Plex/player, or renderer-facing OS command surface. `npm run
verify` passed on 2026-05-13 after Unit 3. Unit 4, renderer cursor and
fake-backed route/overlay integration, is complete after clean implementation
review. It added renderer-owned DOM cursor presentation that hides after
inactivity or mapped desktop input, shows on pointer/mouse activity, cleans up
listeners and timers on unload, and uses only scoped renderer CSS. `npm run
verify` passed on 2026-05-13 after Unit 4. Remaining work is the Windows
manual/native-presentation proof matrix closeout. Unit 5 is selected but
blocked in the current local workspace because the observed platform is
`darwin`; local `npm run smoke:electron` passed on 2026-05-13, but RD-14
parent closeout still requires the Windows native-presentation commands and the
redacted Windows manual matrix from the active plan.

Depends on:

- RD-01 complete.
- RD-06 complete for native surface constraints.
- RD-13 complete enough to exercise renderer navigation.
- ARCH-01 complete or explicitly deferred by a reviewed ARCH-01 replan.

Objective:

- Implement Desktop keyboard/gamepad/media-key handling, cursor behavior,
  display selection, and borderless fullscreen/window behavior.

Scope rule:

- Before implementation, the tracked RD-14 plan must include an
  `## Architecture Health` preflight using
  `docs/architecture/file-shape-guardrails.md`, and it must split work so
  window/input/fullscreen behavior does not grow renderer, main, preload, or CSS
  hotspots without a reviewed decomposition or temporary allowlist decision.

Exit gates:

- Manual matrix covers focus over video, multi-monitor, DPI, fullscreen restore,
  text input behavior, and app quit/back behavior.
- Existing navigation domain remains intact.

### RD-15 UI Over Native Video Integration

Status: not started.

Depends on:

- RD-06 complete.
- RD-13 complete enough to render overlays and EPG.
- RD-14 complete enough to test fullscreen/focus behavior.

Objective:

- Ensure EPG, OSD, mini guide, channel badge, settings, channel setup, and
  overlays work over the native playback surface.

Exit gates:

- Overlay z-order and focus are stable in windowed and fullscreen modes.
- EPG virtualization remains performant.
- Desktop settings expose Desktop capability truth, not webOS labels.

### RD-16 Subtitle, Audio, And HDR Hardening

Status: not started.

Depends on:

- RD-08 complete.
- RD-12 complete.
- RD-15 complete enough to expose media controls.

Objective:

- Stabilize subtitle/audio track mapping, forced/default/language behavior,
  fallback/burn-in decisions, and conservative HDR behavior using native track
  data and Plex metadata.

Exit gates:

- Media matrix records tested and untested containers, codecs, audio formats,
  subtitles, and HDR cases.
- Track ids cannot become ambiguous between Plex and the playback engine.
- Unsupported cases have explicit diagnostics and fallback behavior.

### RD-17 Diagnostics, Crash Recovery, And Support Bundle

Status: not started.

Depends on:

- RD-07 complete for player/helper diagnostics.
- RD-09 complete for secret boundaries.
- RD-12 complete enough to exercise stream/playback failures.

Objective:

- Add redacted local diagnostics across renderer, main, and native host; crash
  recovery; helper restart/reporting; and user-exported support bundle.

Exit gates:

- Redaction tests cover logs, fixtures, crash output, IPC traces, and exported
  bundles.
- No telemetry or cloud upload exists without a separate reviewed decision.
- Native logs cannot bypass redaction.

### RD-18 Windows Packaging And Release Pipeline

Status: not started.

Depends on:

- RD-01 complete for Electron packaging shape.
- RD-06 complete for native binary layout direction.
- RD-17 complete before public distribution.

Objective:

- Add Windows x64 packaging for internal builds first, then signed NSIS public
  release when gates are satisfied.

Exit gates:

- Artifact layout includes Electron, renderer, native helper, and media
  binaries.
- Checksums and third-party notices are generated.
- Signing plan is documented before public release.
- Auto-update remains disabled until signing, release channels, rollback, and
  native binary layout are stable.
- Public release is blocked until licensing/provenance is settled.

### RD-19 Internal Alpha/Beta Validation

Status: not started.

Depends on:

- RD-10 through RD-18 complete enough for a private MVP build.

Objective:

- Run private validation as the maintainer/tester using a structured blocker
  matrix.

Exit gates:

- Full verification passes.
- Manual smoke matrix covers auth, server selection, channel creation, playback,
  switching, subtitles/audio, EPG, settings, sleep/wake, fullscreen,
  multi-monitor, crash recovery, diagnostics export, install/uninstall, and long
  playback.
- Known issues are classified as release blocker, beta blocker, or deferred.

### RD-20 Original Lineup Reference Compatibility Pass

Status: triggered review slice; not started.

Depends on:

- Any Desktop slice that copied/adapted upstream product code or intentionally
  diverged from original Lineup behavior.

Objective:

- Check that Desktop imports preserve intended original Lineup behavior or record
  explicit Desktop divergence. Because this is a separate repo, this is a
  reference-compatibility review, not an automatic requirement to run upstream
  webOS packaging in every Desktop session.

Exit gates:

- Import ledger entries are current for every copied/adapted upstream slice.
- Preserved behavior has Desktop tests, fixtures, or source-audit evidence.
- Intentional divergences are documented in the roadmap, active plan, import
  ledger, or architecture docs.
- If a session also changes the original Lineup repo, that repo's own required
  verification is run there and recorded separately.

### RD-21 Future Platform Review

Status: not started.

Depends on:

- Windows MVP stabilized through RD-19.

Objective:

- Review what remains coupled to Windows and what needs to change before
  macOS/Linux work.

Exit gates:

- Windows-specific assumptions are documented.
- Shared contracts remain cross-platform where that does not add v1 complexity.
- No macOS/Linux release promise is made without a separate plan.

## Reuse Map

### Reuse Or Adapt From Original Lineup

- Plex auth, discovery, library, stream resolver flow, typed errors, and
  redacted diagnostics.
- Scheduler, channel manager, content resolver, deterministic schedule behavior,
  and channel persistence owner patterns already imported/adapted through RD-11;
  revisit only for upstream behavior changes or runtime composition needs.
- DOM TV UI, EPG virtualization, OSD, mini guide, settings, channel setup, and
  navigation/focus model.
- Playback descriptor-building concepts and UI-facing playback expectations.
- Settings/store validation patterns.
- Redaction utility approach, safe logging conventions, and security docs.
- Existing workflow/harness lessons already ported into Desktop docs and
  verifiers.

### Use As Functionality Target, Not Desktop Truth

- Browser/webOS player implementation.
- HTMLVideoElement track and subtitle assumptions.
- webOS codec constants and direct-play policy as universal capability truth.
- webOS platform services, lifecycle, relaunch, window close, and user-agent
  detection.
- webOS packaging and sideload release mechanics.

### Newly Design For Desktop

- Electron main/preload/renderer process boundary.
- Local app protocol and window security policy.
- Typed preload bridge and IPC authorization.
- Secure credential storage and app data path ownership.
- Desktop player contract adapter, fake host, helper-hosted native libmpv, and
  helper crash recovery.
- Desktop stream capability profile.
- Native log redaction and support bundles.
- Windows package layout, signing, binary provenance, and release gates.

## Global Gates

- No product source import without a same-change import ledger entry.
- No renderer access to credentials, raw auth headers, tokenized media URLs,
  native handles, Node APIs, Electron APIs, or raw IPC.
- No webOS media constants as Desktop capability truth.
- No external `mpv` POC as production architecture.
- No broad renderer UI, Plex/player integration, or packaging work before the
  native video/overlay/focus risk is resolved or explicitly replanned.
- No broad repo moves, root barrels, compatibility shims, or old upstream path
  mirrors unless a reviewed plan names the removal trigger.
- No new dependency, build tool, packaging tool, diagnostic surface, or logging
  sink without runtime owner, provenance, security, and verification notes.
- No public Windows release until signing, licensing/provenance, redacted
  diagnostics, native binary layout, and installer checks are complete.

## Quality Policy During The Port

Fix immediately when discovered in touched scope:

- Credential or redaction leak.
- Storage corruption.
- Deterministic scheduler regression.
- Plex auth, profile, server, library, or stream blocker.
- PMS transcode cleanup failure.
- Native helper crash that takes down the Electron UI.
- Architecture boundary violation.
- Required verifier or smoke-test failure.

Defer unless it blocks the current slice:

- Pure visual polish.
- Non-MVP codec, passthrough, HDR, or Dolby Vision edge cases.
- macOS/Linux-only behavior before those platforms are active.
- Optional settings and wishlist features.
- UI redesign requests not required for Desktop parity.

Stop and replan when:

- Native video/overlay composition cannot meet MVP requirements.
- Electron/native/storage logic starts moving into renderer or broad
  orchestration owners.
- Shared policy changes unexpectedly alter original Lineup behavior without a
  documented Desktop divergence.
- Licensing posture conflicts with intended distribution.
- Raw credential material appears in logs, IPC traces, crash output, fixtures,
  docs, or Codex output.
- A required verification gate fails in a way that invalidates the slice design.

## Roadmap Maintenance

Update this roadmap when:

- a roadmap slice completes
- a slice is intentionally reordered
- a new gate becomes a prerequisite for more than one plan
- a spike changes the playback, storage, security, or release strategy
- an import ledger entry proves a source slice should be split differently

Roadmap updates are docs/control-plane changes. Run `npm run verify:docs` before
calling them complete.
