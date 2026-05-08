# Desktop Port Roadmap

This is the durable checklist for the Windows-first Lineup Desktop port. It
turns the GPT Pro handoff report and the accepted repo-genesis decisions into an
ordered path for future plans.

This is not an implementation plan for any single slice. Each serious slice
still needs its own tracked plan under `docs/plans/` that follows
`docs/agentic/plan-authoring-standard.md`.

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
- [ ] First active implementation plan reviewed.
- [ ] Secure Electron shell foundation implemented and reviewed.
- [ ] Product reuse/import sequence formalized through this roadmap and
  follow-up tracked plans.

The GPT Pro report was written against the original Lineup app shape. This repo
is a separate Desktop repo with no production runtime yet, so the first local
slice is the secure Electron shell foundation. The report's product-port phases
begin after the Desktop shell has a proven main/preload/renderer boundary.

## How To Use This Roadmap

1. Before starting a new major slice, read this roadmap after `AGENTS.md`, the
   workflow runbook, current architecture state, and the active plan.
2. Pick the next unchecked roadmap slice whose dependencies are satisfied.
3. Create or update one tracked plan for that slice in `docs/plans/`.
4. Keep implementation limited to that plan's current unit.
5. On closeout, update this roadmap only for observed status changes.

Do not use this roadmap to batch multiple product slices into one broad
implementation. Its purpose is sequencing and dependency clarity.

## Roadmap Checklist

### RD-00 Repo Genesis And Control Plane

Status: complete.

Scope:

- Separate repo, Desktop-specific architecture docs, import ledger, workflow
  runbook, project skills, Codex role config, verifier scripts, baseline
  contracts, and active first plan.

Exit evidence:

- `npm run verify` passed for the control-plane scaffold before product
  implementation.

### RD-01 Secure Electron Shell Foundation

Status: active plan exists; implementation is blocked until plan review is
clean.

Plan:

- `docs/plans/2026-05-07-electron-shell-security-foundation-plan.md`

Objective:

- Create the first secure Electron process skeleton: main owns lifecycle and
  privileged IPC, preload exposes a narrow typed bridge, renderer remains
  unprivileged, and smoke verification proves renderer privilege denial.

Exit gates:

- Plan review clean.
- Electron main/preload/renderer shell implemented.
- Architecture lint covers new directories.
- Contract/redaction tests cover renderer-safe API and forbidden privileged
  fields.
- Electron smoke proof passes or records a real environment blocker.
- `npm run verify` passes.

Next action after completion:

- Update `docs/architecture/CURRENT_STATE.md`.
- Mark this roadmap slice complete.
- Create the RD-02 tracked plan before importing product code.

### RD-02 Source Reuse Inventory And Import Strategy

Status: not started.

Objective:

- Convert the original Lineup codebase into a concrete Desktop import map:
  direct reuse, adapted reuse, example-only reference, and do-not-import.

Likely source references:

- Original Lineup Plex auth/discovery/library/stream modules.
- Original Lineup scheduler/channel/content modules.
- Original Lineup player, platform, navigation, EPG, OSD, settings, storage, and
  redaction modules.
- Original Lineup tests that protect stable behavior.
- GPT Pro handoff report sections on reusable slices, risk register, and phase
  table.

Exit gates:

- A tracked plan or architecture note names the first product import order.
- Import-ledger obligations are explicit for every copied or adapted slice.
- Original Lineup behavior used as a functionality target is separated from code
  that will actually be copied.
- Any upstream verification relied on is observed and recorded, or explicitly
  marked unavailable.

Stop and replan if:

- A proposed import requires renderer custody of credentials, raw auth headers,
  tokenized media URLs, native handles, Node APIs, or Electron APIs.
- The import would force broad compatibility shims, root barrels, or old path
  mirrors.
- The import would make Desktop architecture depend on webOS playback constants
  as capability truth.

### RD-03 Player Contract And Capability Model

Status: not started.

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
- Capability-driven stream policy surface that can support webOS, external POC,
  and native libmpv without conflating them.

Exit gates:

- Contract tests cover player state, event staleness, request ids, diagnostics,
  and forbidden privileged fields.
- No Electron, libmpv, Node, or webOS constants leak into shared contract truth.

### RD-04 Upstream Behavior Guardrails

Status: not started.

Objective:

- Lock behavior that Desktop must preserve or intentionally diverge from before
  shared Plex, scheduler, player, or UI imports begin.

Reuse target:

- Original Lineup tests and behavior around stream decisions, subtitle/audio
  fallback, deterministic scheduling, channel persistence, navigation focus,
  EPG virtualization, settings state, and redaction.

Exit gates:

- For each imported product slice, Desktop has a test, fixture, source audit, or
  explicit rationale showing how preserved behavior will be protected.
- Any intentional Desktop divergence is documented before implementation.

### RD-05 Secure Storage And Persistence Boundary

Status: not started.

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

### RD-06 Plex Auth, Discovery, And Library Import

Status: not started.

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

### RD-07 Scheduler, Channel, And Content Domain Import

Status: not started.

Objective:

- Import deterministic scheduling, channel management, content resolution,
  channel persistence shape, and lineup state behind Desktop storage owners.

Reuse target:

- Original Lineup `ChannelManager`, `ChannelScheduler`, content resolver,
  channel repository/store patterns, and tests.

Exit gates:

- Deterministic schedule behavior is protected by tests.
- Channel persistence is behind typed owners.
- No scheduler or channel logic enters Electron main/preload.

### RD-08 Renderer UI And Navigation Import

Status: not started.

Objective:

- Bring over the existing DOM TV UI as the Desktop renderer experience without
  redesigning it: app shell, navigation, EPG, OSD, mini guide, settings, channel
  setup, overlays, and relevant assets/styles.

Reuse target:

- Original Lineup DOM UI modules, navigation/focus model, EPG virtualization,
  settings state controllers, and UI design language.

New Desktop design:

- Desktop platform adapters for keyboard, gamepad, media keys, window commands,
  and app lifecycle.
- Renderer remains unprivileged.

Exit gates:

- Renderer smoke verifies primary UI routes/workflows reachable in Electron.
- Focus/navigation tests cover Desktop input mapping where feasible.
- WebOS-only UI copy or settings are gated or renamed before they become
  Desktop product truth.

### RD-09 External mpv POC

Status: not started.

Objective:

- Run a short, disposable, dev-only external `mpv` IPC POC to learn media facts:
  stream loading, header handling, start offsets, channel-switch timing,
  subtitle/audio track enumeration, and cleanup behavior.

Non-goals:

- No production architecture commitment.
- No installer/package changes.
- No UI redesign.

Exit gates:

- POC results are documented with what was proven, what failed, and whether the
  POC is deleted or quarantined behind a dev-only flag.
- No tokenized URLs or raw auth headers appear in process args, logs, crash
  output, IPC traces, fixtures, docs, or Codex output.

### RD-10 Native libmpv Host Spike

Status: not started.

Objective:

- Prove the production playback path on Windows: helper-hosted native libmpv
  first, with addon exploration only if the helper path cannot meet overlay or
  surface requirements.

Required proof:

- Local file playback.
- Plex-like HTTP playback using safe dummy credentials.
- Windowed and borderless fullscreen rendering.
- Overlay visibility above video.
- Renderer focus/input continuity.
- Audio/subtitle track observation and selection.
- Helper crash detection without killing the Electron UI.
- DPI and multi-monitor behavior acceptable for MVP.
- Redacted native logs.

Exit gates:

- Helper-vs-addon decision recorded from evidence.
- Licensing/provenance questions captured before public packaging work.

### RD-11 Desktop VideoPlayer Adapter

Status: not started.

Objective:

- Implement the Desktop player adapter against the approved player contract and
  bridge/native-host boundary.

Exit gates:

- Adapter tests cover command mapping, state, events, errors, stale request
  handling, diagnostics, and helper crash behavior.
- Renderer receives only renderer-safe player state.
- `App.ts` and orchestration owners do not absorb native process policy.

### RD-12 Desktop Stream Policy

Status: not started.

Objective:

- Add Desktop capability-driven Plex stream decisions while preserving the
  original webOS/browser behavior as a separate capability profile or upstream
  reference.

Exit gates:

- Desktop decisions are driven by capability profile, not webOS constants.
- Direct play, direct stream, transcode, subtitle fallback, audio fallback, and
  HDR decisions have tested reasons or explicit unknowns.
- No Plex HTPC parity claim exists without sample-matrix evidence.

### RD-13 Plex To Player Integration

Status: not started.

Objective:

- Wire Plex stream decisions, playback descriptors, player adapter, channel
  switching, and PMS cleanup into Desktop runtime without bloating composition
  roots.

Exit gates:

- Stop, switch, error, logout, server change, profile change, and helper crash
  paths clean up transcode sessions and stale events.
- Orchestration wiring remains a thin factory/platform seam.
- Tokens do not reach renderer or logs.

### RD-14 Window, Input, And Fullscreen UX

Status: not started.

Objective:

- Implement Desktop keyboard/gamepad/media-key handling, cursor behavior,
  display selection, and borderless fullscreen/window behavior.

Exit gates:

- Manual matrix covers focus over video, multi-monitor, DPI, fullscreen restore,
  text input behavior, and app quit/back behavior.
- Existing navigation domain remains intact.

### RD-15 UI Over Native Video Integration

Status: not started.

Objective:

- Ensure EPG, OSD, mini guide, channel badge, settings, channel setup, and
  overlays work over the native playback surface.

Exit gates:

- Overlay z-order and focus are stable in windowed and fullscreen modes.
- EPG virtualization remains performant.
- Desktop settings expose Desktop capability truth, not webOS labels.

### RD-16 Subtitle, Audio, And HDR Hardening

Status: not started.

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

### RD-20 Compatibility And Future Platform Review

Status: not started.

Objective:

- After Windows MVP stabilizes, review what remains coupled to Windows and what
  needs to change before macOS/Linux work.

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
- Shared policy changes unexpectedly alter upstream webOS behavior.
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
