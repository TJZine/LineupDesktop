# Desktop Port Roadmap

This is the durable checklist for the Windows-first Lineup Desktop port. It
turns the GPT Pro handoff report and the accepted repo-genesis decisions into an
ordered path for future plans.

This is not an implementation plan for any single slice. Each serious slice
still needs its own tracked plan under [`docs/plans/`](../plans/README.md) that
follows [`docs/agentic/plan-authoring-standard.md`](../agentic/plan-authoring-standard.md).

## Current Position

- [x] Separate Desktop repo created.
- [x] Electron shell direction accepted.
- [x] Helper-hosted native libmpv production hypothesis accepted.
- [x] External `mpv` allowed only as a disposable private POC.
- [x] Single-package repo shape accepted for the initial port.
- [x] Workflow, skills, launchers, role config, docs verifier, redaction
  verifier, and architecture lint scaffolded.
- [x] First active implementation plan created:
  `docs/plans/2026-05-07-electron-shell-security-foundation-plan.md`.
- [x] First active implementation plan reviewed.
- [x] Secure Electron shell foundation implemented at `b8fb948`; `npm run
  smoke:electron` and `npm run verify` passed on 2026-05-08.
- [x] Secure Electron shell foundation implementation reviewed and clean after
  one blocker fix, per RD-01 agent closeout report provided on 2026-05-08.
- [x] Product reuse/import sequence formalized through follow-up tracked plan
  `docs/plans/2026-05-08-rd-02-source-reuse-inventory-import-strategy-plan.md`.
- [x] Player contract and capability model completed through RD-03 quality loop:
  `src/contracts/player.ts`, `src/contracts/ipc.ts`, and
  `src/__tests__/contracts.test.ts`; `npm run verify` passed and
  implementation review was clean on 2026-05-08.
- [x] RD-04 upstream behavior guardrails completed through
  `docs/architecture/upstream-behavior-guardrails.md`; `npm run verify` passed
  and scoped implementation review was clean on 2026-05-08.
- [x] RD-05 external `mpv` POC completed through
  `docs/plans/2026-05-08-rd-05-external-mpv-poc-plan.md`;
  `tools/mpv-poc/rd-05-external-mpv-poc.mjs` remains a dev-only disposable
  script, ignored redacted run evidence exists under
  `docs/runs/rd-05-external-mpv-poc/`, `npm run verify` passed, and
  implementation review was clean on 2026-05-08.
- [ ] RD-06 Windows native libmpv WID smoke has partial local redacted proof
  through `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`, but the
  revised smoke currently fails fullscreen video-surface proof and requires
  replan before RD-07.

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
   the next session owns planning, plan review, bounded implementation,
   implementation review, and closeout unless a blocker stops the loop.
5. Create or update one tracked plan for that slice in `docs/plans/`.
6. Keep implementation limited to that plan's current unit.
7. On closeout, update this roadmap only for observed status changes.
8. End the session with the workflow runbook's `NEXT_SESSION_HANDOFF` shape,
   routing the next session to the next roadmap slice's plan, review, or
   implementation step.

Do not use this roadmap to batch multiple product slices into one broad
implementation. Its purpose is sequencing and dependency clarity.

## Next-Handoff Rule

When a roadmap slice reaches its exit gates:

- update `Status` only when the evidence was observed in this repo or explicitly
  recorded as unavailable
- update architecture docs or the import ledger when the slice changes ownership
  or imports/adapts upstream Lineup source
- emit one pasteable `NEXT_SESSION_HANDOFF`
- route to `lineup-desktop-feature-quality-loop` when the next roadmap slice is
  Tier 3 and should be carried through planning, review, bounded
  implementation, implementation review, and closeout in one orchestrated
  workflow
- route to `lineup-desktop-feature-plan` when the next slice does not yet have a
  tracked plan
- route to `lineup-desktop-feature-review` when a plan or implementation needs
  adversarial review
- route to `lineup-desktop-feature-implement` only after the relevant plan
  review is clean

RD-01 through RD-05 are complete enough to route the next Tier 3 quality-loop
session to RD-06. Do not import original Lineup product code until a reviewed
product slice plan explicitly authorizes a bounded import.

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
- Active plan review clean for
  `docs/plans/2026-05-07-electron-shell-security-foundation-plan.md`.

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

Status: complete. Implemented through
`docs/plans/2026-05-08-rd-03-player-contract-capability-model-plan.md`;
`npm run verify` passed and read-only implementation review was clean on
2026-05-08.

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
`docs/plans/2026-05-08-rd-04-upstream-behavior-guardrails-plan.md` and
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
`docs/plans/2026-05-08-rd-05-external-mpv-poc-plan.md`,
`tools/mpv-poc/rd-05-external-mpv-poc.mjs`, and
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

Status: blocked/replan. Revised Windows WID smoke proves windowed active video,
overlay pixels, focus, dummy HTTP, helper crash detection, redaction, and
libmpv API evidence, but fails the required fullscreen video-surface proof.

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

- Helper-vs-addon decision recorded from evidence. The current WID smoke does
  not prove enough to route directly to RD-07; render API or addon exploration
  should be considered in a reviewed replan.
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
- The same evidence records fullscreen video-surface proof as not captured, so
  the WID smoke exits failed instead of overclaiming RD-06 completion.
- Track selection and subtitle behavior are not proven by the tiny dummy visual
  input.
- DPI and multi-monitor behavior still need a stronger manual matrix before
  packaging or UI-over-video hardening.

### RD-07 Desktop VideoPlayer Adapter

Status: not started.

Depends on:

- RD-03 complete.
- RD-06 complete.

Objective:

- Implement the Desktop player adapter against the approved player contract and
  bridge/native-host boundary.

Exit gates:

- Adapter tests cover command mapping, state, events, errors, stale request
  handling, diagnostics, helper crash behavior, and request cleanup.
- Renderer receives only renderer-safe player state.
- `App.ts` and orchestration owners do not absorb native process policy.

### RD-08 Desktop Stream Policy

Status: not started.

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

Status: not started.

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

- Credential/store interfaces are typed and tested.
- Renderer-facing contracts cannot carry credential-like secret material.
- Backup/restore, unavailable secure-storage behavior, and redacted diagnostics
  expectations are documented.

### RD-10 Plex Auth, Discovery, And Library Import

Status: not started.

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

### RD-11 Scheduler, Channel, And Content Domain Import

Status: not started.

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

### RD-12 Plex To Player Integration

Status: not started.

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

- Stop, switch, error, logout, server change, profile change, and helper crash
  paths clean up transcode sessions and stale events.
- Orchestration wiring remains a thin factory/platform seam.
- Tokens do not reach renderer or logs.

### RD-13 Renderer UI And Navigation Import

Status: not started.

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

### RD-14 Window, Input, And Fullscreen UX

Status: not started.

Depends on:

- RD-01 complete.
- RD-06 complete for native surface constraints.
- RD-13 complete enough to exercise renderer navigation.

Objective:

- Implement Desktop keyboard/gamepad/media-key handling, cursor behavior,
  display selection, and borderless fullscreen/window behavior.

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
  and channel persistence owner patterns.
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
