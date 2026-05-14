# RD-19 Internal Validation Checklist

This checklist is the docs-only execution artifact for RD-19 Unit A. It records
private internal alpha/beta validation summaries without changing runtime
behavior, package scripts, generated outputs, source, tools, package metadata,
roadmap, current-state, packaging-release gates, or `docs/runs/**`.

RD-19 validation does not claim live Plex or production native playback
readiness. Missing runtime behavior must be classified as a blocker or deferred
item, not worked around in this checklist.

## Evidence Rules

Tracked material is limited to redacted summaries:

- scenario id and matrix area
- platform family and architecture, such as `win32 x64`
- package or build identity without absolute paths
- command name or app route used
- status: `passed`, `failed`, `blocked`, or `not run`
- blocker classification: `release blocker`, `beta blocker`, or `deferred`
- sanitized counts, such as display count, scenario count, or scan count
- redaction scan status and verifier status
- current validation command name, exit status, and test file or test area when
  an injected/domain proof row is marked `passed`
- short human summary with no secrets, local paths, raw logs, or media detail

Raw evidence must never be tracked in this file or any tracked doc:

- Plex tokens, tokenized URLs, raw auth headers, or credential values
- raw Plex payloads, raw IPC frames, native handles, process ids, or helper logs
- crash dumps, stack dumps, or support bundles containing secret-bearing state
- absolute local paths, usernames, machine-specific directories, or local media
  sample names
- screenshots that expose local paths, account names, media libraries, tokens,
  or private server details
- signing credentials, certificate material, package output trees, or generated
  artifacts

Raw local evidence, when a later approved validation run creates it, must stay
ignored under `docs/runs/**` or `out/**`. A readiness summary can be tracked
only after the redaction gate passes.

## Redaction Gate

Before any validation result can be summarized as readiness evidence:

- Confirm the summary contains only allowed tracked fields.
- Confirm every support bundle or diagnostics-derived result passed
  `tools/verify-redaction.mjs` or the RD-17 support-bundle scanner.
- Confirm package proof references command outcomes and package identity only,
  not generated file listings, absolute paths, or raw manifest contents.
- Confirm manual notes remove local account, server, library, path, media,
  token, URL, process, native-handle, and crash-dump details.
- If forbidden material appears anywhere in a tracked draft, stop, remove it,
  rerun the relevant redaction check, and route the issue as a release blocker.

## Blocker Classifications

- `release blocker`: prevents any public release. Security, credential leakage,
  unredacted diagnostics, package integrity failures, public signing/update
  misrepresentation, native/media binary provenance gaps, and production
  playback claims without production playback ownership are release blockers by
  default.
- `beta blocker`: prevents broader private beta but may allow maintainer-only
  alpha evidence when the limitation is documented, redacted, and not security
  critical.
- `deferred`: acceptable for private beta only when documented with owner,
  rationale, user impact, and revisit trigger. Deferred items cannot hide
  security, data-loss, credential, installer integrity, or redaction issues.

## Stop Conditions

Stop validation and route back to RD-19 controller or a reviewed enabling plan
if any condition occurs:

- Validation requires live Plex auth, live discovery, live library browsing, or
  real Plex credentials before those runtime surfaces exist.
- Validation requires production native helper playback, Plex-to-native-helper
  setup, new preload APIs, new renderer Plex APIs, persistence IPC, package
  script changes, dependencies, signing/update behavior, or source edits.
- A support bundle, log, screenshot, package note, tester note, or summary
  contains forbidden material or fails redaction scanning.
- RD-18 package verification fails or package proof is attempted off Windows
  x64 while claiming Windows x64 package readiness.
- RD-17 diagnostics smoke fails when crash recovery or diagnostics export
  readiness is being claimed.
- Sleep/wake, fullscreen, multi-monitor, or long playback observations reveal
  reproducible state corruption, resource leak, crash, focus trap, unusable
  display placement, or unredacted diagnostics output.
- Any result would require describing the current app as public distributable,
  live-Plex ready, or production-playback ready.

## Required Windows x64 Proof Commands

Run these only in a later approved Windows x64 validation run when package,
diagnostics, or platform proof is in scope. Record only command names, exit
status, expected-outcome status, platform family, and redacted summary.

```sh
git status --short --branch
npm run verify:docs
npm run verify:redaction
npm run build:electron
node tools/package-windows-internal.mjs --out out/rd-18-windows-internal
node tools/verify-windows-internal-package.mjs --package out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64 --manifest out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/resources/lineup-desktop-provenance.json
node tools/rd17-diagnostics-smoke.mjs --out docs/runs/rd-17-diagnostics-crash-recovery-support-bundle/windows-smoke-rd19
```

Expected proof:

- `git status --short --branch`: no unrelated tracked changes are included in
  the validation unit.
- `npm run verify:docs`: docs and active-plan shape pass.
- `npm run verify:redaction`: forbidden tracked material is absent.
- `npm run build:electron`: Electron build completes before package or
  diagnostics smoke proof.
- Package command: on Windows x64, creates the internal unpacked package under
  ignored `out/**`.
- Package verifier: passes with blocked native-helper/media markers, checksums,
  provenance, redaction-safe evidence, and no signing or forbidden native/media
  material.
- RD-17 diagnostics smoke: passes with ignored local evidence, helper crash
  detected, main process alive, safe failed request state, helper cleanup/reap,
  replacement helper use, renderer-visible support-bundle result limited to
  bundle identity, completed bundle scan passed, and forbidden material absent.

## Validation Matrix

Use one checklist row per scenario. Status may be `passed`, `failed`,
`blocked`, or `not run`.

| Area | Checklist | Status | Classification rule |
| --- | --- | --- | --- |
| Auth | Confirm injected/fake auth proof remains green. Do not attempt real Plex sign-in. | passed | Live sign-in absence is a beta blocker; token leakage is a release blocker. |
| Server selection | Confirm injected selected-server restore/probe proof or fake UI summary. Do not claim real server picker. | passed | Real server selection absence is a beta blocker. |
| Channel creation | Validate fake channel setup flow and domain-level channel creation summary only. | passed | Live library-backed channel creation absence is a beta blocker. |
| Playback | Validate fake-backed player route, injected runtime proof, or dev-only native-presentation summary. | passed | Production native playback absence is a release blocker for public release and beta blocker for real media beta. |
| Switching | Validate injected switch cleanup proof and fake UI switching only. | passed | Real Plex media switching absence is a beta blocker. |
| Subtitles/audio | Validate deterministic policy/resolver proof. Do not claim real runtime track switching. | passed | Unsafe track leakage is a release blocker; missing real switching is a beta blocker. |
| EPG | Validate fake EPG route, focus, formatting, and UI-over-video summary where available. | passed | Real Plex/scheduler-backed EPG absence is a beta blocker when required for private MVP. |
| Settings | Validate fake settings route and diagnostics export action only. Do not claim persisted settings. | passed | Persistence IPC absence is deferred for fake alpha and beta blocker for real settings beta. |
| Sleep/wake | Record Windows shell/package observation only. Do not claim playback or network recovery. | blocked | Runtime playback or credential recovery gaps are beta blockers until owned. |
| Fullscreen | Validate shell/fake UI fullscreen and Windows native-presentation summary where available. | passed | Shell fullscreen failure is a beta blocker; production native fullscreen gap remains release blocker for public playback. |
| Multi-monitor | Record display count/DPI and shell placement only. Do not claim native playback multi-monitor support. | passed | Shell placement failure is a beta blocker; production video gap is deferred until playback unit unless severe. |
| Crash recovery | Validate RD-17 diagnostics smoke summary on Windows when claiming recovery. | passed | Unredacted or unrecovered helper crash is a release blocker. |
| Diagnostics export | Validate RD-17 support-bundle export through smoke or approved package flow. | passed | Redaction failure or absolute path exposure is a release blocker. |
| Install/delete of unpacked package | Validate RD-18 package creation/verifier and manual launch/delete of unpacked artifact only. | passed | Installer absence is deferred for maintainer alpha and release blocker for public release. |
| Long playback | Do not run a soak in Unit D or claim real long playback. Record real long playback as blocked unless a separate reviewed validation scope defines a fixed fake/native soak. | blocked | Real long playback absence is a beta blocker until production playback exists. |

## Unit D Scenario Summaries

### Scenario RD19-auth-001

- Area: Auth
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: `npm run verify`; `npm run smoke:electron`
- Test file or test area, if command-backed: Plex auth domain tests; renderer-safe contract tests; Electron smoke
- Status: passed
- Blocker classification: beta blocker for live Plex sign-in absence
- Redaction gate status: passed
- Safe evidence summary: Current injected/fake auth proof passed. No real Plex sign-in was attempted.
- Owner for next enabling plan, if blocked: Main Plex runtime plus preload/renderer Plex API plan
- Revisit trigger: reviewed live Plex auth transport and renderer API scope exists

### Scenario RD19-server-selection-001

- Area: Server selection
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: `npm run verify`; `npm run smoke:electron`
- Test file or test area, if command-backed: Plex discovery and selected-server domain tests; Electron smoke
- Status: passed
- Blocker classification: beta blocker for real server picker absence
- Redaction gate status: passed
- Safe evidence summary: Current injected selected-server and fake shell proof passed. No live discovery or real server selection was attempted.
- Owner for next enabling plan, if blocked: Main Plex runtime plus preload/renderer Plex API plan
- Revisit trigger: reviewed live discovery and server-picker scope exists

### Scenario RD19-channel-creation-001

- Area: Channel creation
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: `npm run verify`; `npm run smoke:electron`
- Test file or test area, if command-backed: channel domain tests; fake channel setup renderer route through Electron smoke
- Status: passed
- Blocker classification: beta blocker for live library-backed channel creation absence
- Redaction gate status: passed
- Safe evidence summary: Current fake channel setup and injected domain proof passed. No live Plex library-backed channel creation was attempted.
- Owner for next enabling plan, if blocked: Renderer Plex APIs plus live library/channel creation plan
- Revisit trigger: reviewed live library browse and channel-authoring scope exists

### Scenario RD19-playback-001

- Area: Playback
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: `npm run verify`; `npm run smoke:electron`
- Test file or test area, if command-backed: player contract tests; desktop player adapter tests; Plex playback runtime tests; dev-only native-presentation harness tests; Electron smoke
- Status: passed
- Blocker classification: release blocker for public production playback; beta blocker for real media beta
- Redaction gate status: passed
- Safe evidence summary: Current fake-backed player route, injected runtime, and dev-only harness tests passed. No production native playback or real Plex media playback was claimed.
- Owner for next enabling plan, if blocked: Native helper/playback plan
- Revisit trigger: reviewed production native helper and Plex-to-helper playback setup exists

### Scenario RD19-switching-001

- Area: Switching
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: `npm run verify`; `npm run smoke:electron`
- Test file or test area, if command-backed: Plex playback runtime cleanup/stale-event tests; channel domain switching tests; Electron smoke
- Status: passed
- Blocker classification: beta blocker for real Plex media switching absence
- Redaction gate status: passed
- Safe evidence summary: Current injected cleanup and fake switching proof passed. No real Plex media channel switch was attempted.
- Owner for next enabling plan, if blocked: Main/helper playback setup plan
- Revisit trigger: reviewed live playback and real channel switching scope exists

### Scenario RD19-subtitles-audio-001

- Area: Subtitles/audio
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: `npm run verify`
- Test file or test area, if command-backed: desktop stream policy tests; Plex stream resolver tests; RD-16 media matrix harness tests
- Status: passed
- Blocker classification: beta blocker for missing real runtime track switching
- Redaction gate status: passed
- Safe evidence summary: Deterministic policy and resolver proof passed. No real runtime subtitle or audio track switching was claimed.
- Owner for next enabling plan, if blocked: Native helper/playback plan
- Revisit trigger: reviewed runtime track switching scope exists

### Scenario RD19-epg-001

- Area: EPG
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: `npm run verify`; `npm run smoke:electron`
- Test file or test area, if command-backed: scheduler domain tests; RD-15 native-presentation UI proof tests; Electron smoke
- Status: passed
- Blocker classification: beta blocker if real Plex/scheduler-backed EPG is required for private MVP
- Redaction gate status: passed
- Safe evidence summary: Current fake EPG and scheduler proof passed. No real Plex/scheduler-backed EPG was claimed.
- Owner for next enabling plan, if blocked: Renderer Plex/scheduler integration plan
- Revisit trigger: reviewed real Plex-backed EPG scope exists

### Scenario RD19-settings-001

- Area: Settings
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: `npm run verify`; `node tools/rd17-diagnostics-smoke.mjs --out <ignored RD-19 smoke evidence>`; `npm run smoke:electron`
- Test file or test area, if command-backed: diagnostics contract tests; RD-17 diagnostics smoke; Electron smoke
- Status: passed
- Blocker classification: deferred for fake alpha; beta blocker for real persisted settings beta
- Redaction gate status: passed
- Safe evidence summary: Fake settings route and diagnostics export proof passed. No persisted settings UX was claimed.
- Owner for next enabling plan, if blocked: Persistence/recovery plan
- Revisit trigger: reviewed preload/renderer persistence IPC scope exists

### Scenario RD19-sleep-wake-001

- Area: Sleep/wake
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: not run
- Test file or test area, if command-backed: none
- Status: blocked
- Blocker classification: beta blocker for runtime playback or credential recovery claims
- Redaction gate status: passed
- Safe evidence summary: Unit D did not force system sleep/wake. No playback, network, credential, or package recovery claim was made.
- Owner for next enabling plan, if blocked: Window/platform UX plan
- Revisit trigger: reviewed Windows sleep/wake observation scope with safe manual steps exists

### Scenario RD19-fullscreen-001

- Area: Fullscreen
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: `npm run verify`; `npm run smoke:electron`
- Test file or test area, if command-backed: shell window controller tests; RD-15 native-presentation UI proof tests; Electron smoke
- Status: passed
- Blocker classification: release blocker for public production native fullscreen playback gap
- Redaction gate status: passed
- Safe evidence summary: Current shell/fake fullscreen proof passed. No production native fullscreen playback claim was made.
- Owner for next enabling plan, if blocked: Native helper/playback plan
- Revisit trigger: reviewed production native fullscreen playback scope exists

### Scenario RD19-multi-monitor-001

- Area: Multi-monitor
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: `npm run verify`; sanitized display observation
- Test file or test area, if command-backed: shell window controller display-fit tests
- Status: passed
- Blocker classification: deferred for production video multi-monitor proof until playback unit
- Redaction gate status: passed
- Safe evidence summary: Display count 2 and primary display count 1 were observed. Current shell display-fit proof passed. No native playback multi-monitor claim was made.
- Owner for next enabling plan, if blocked: Native helper/playback plan
- Revisit trigger: reviewed production playback multi-monitor scope exists

### Scenario RD19-crash-recovery-001

- Area: Crash recovery
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: `node tools/rd17-diagnostics-smoke.mjs --out <ignored RD-19 smoke evidence>`; `npm run verify`
- Test file or test area, if command-backed: RD-17 diagnostics smoke; desktop player adapter diagnostics tests; Plex playback runtime helper-crash cleanup tests
- Status: passed
- Blocker classification: none
- Redaction gate status: passed
- Safe evidence summary: RD-17 smoke passed with helper crash detected, main process alive, safe failed request state, cleanup/reap, replacement helper use, and redaction-safe support bundle result.
- Owner for next enabling plan, if blocked: n/a
- Revisit trigger: any diagnostics or helper crash recovery contract change

### Scenario RD19-diagnostics-export-001

- Area: Diagnostics export
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: `node tools/rd17-diagnostics-smoke.mjs --out <ignored RD-19 smoke evidence>`; `npm run verify:redaction`; `npm run verify`
- Test file or test area, if command-backed: RD-17 diagnostics smoke; diagnostics contract tests; redaction verifier
- Status: passed
- Blocker classification: none
- Redaction gate status: passed
- Safe evidence summary: Diagnostics export proof passed and renderer-visible support-bundle result remained limited to bundle identity.
- Owner for next enabling plan, if blocked: n/a
- Revisit trigger: any diagnostics, support-bundle, or redaction policy change

### Scenario RD19-install-delete-001

- Area: Install/delete of unpacked package
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: `npm run build:electron`; `node tools/package-windows-internal.mjs --out <ignored internal package output>`; `node tools/verify-windows-internal-package.mjs --package <ignored package identity> --manifest <ignored package provenance>`; manual launch/delete observation
- Test file or test area, if command-backed: RD-18 package verifier; package launch/delete observation
- Status: passed
- Blocker classification: deferred for maintainer alpha; release blocker for public installer/release absence
- Redaction gate status: passed
- Safe evidence summary: Internal package generation and verification passed. Packaged executable started and stopped, and an ignored unpacked package copy was removable after launch stop.
- Owner for next enabling plan, if blocked: Packaging/release plan
- Revisit trigger: reviewed installer, signing, update, or public distribution scope exists

### Scenario RD19-long-playback-001

- Area: Long playback
- Platform: win32 x64
- Build/package identity: lineup-desktop-0.0.0-win32-x64
- Command or route: not run
- Test file or test area, if command-backed: none
- Status: blocked
- Blocker classification: beta blocker until production playback exists
- Redaction gate status: passed
- Safe evidence summary: Unit D did not run a fake/native soak and did not claim real long playback.
- Owner for next enabling plan, if blocked: Runtime/window/diagnostics plan or production playback plan
- Revisit trigger: reviewed long-playback validation scope with fixed duration, harness, resource checks, pass/fail threshold, and redacted evidence fields exists

## Scenario Summary Template

```md
### Scenario RD19-<area>-<nn>

- Area:
- Platform:
- Build/package identity:
- Command or route:
- Test file or test area, if command-backed:
- Status:
- Blocker classification:
- Redaction gate status:
- Safe evidence summary:
- Owner for next enabling plan, if blocked:
- Revisit trigger:
```

## Blocker Log Template

```md
| ID | Date | Area | Summary | Classification | Stop condition hit | Safe evidence | Owner for next enabling plan | Revisit trigger | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RD19-BLOCK-001 | YYYY-MM-DD | <area> | <redacted summary only> | release blocker/beta blocker/deferred | <stop condition or none> | <command/status/counts only> | <owner or plan needed> | <specific trigger> | open |
```

Blocker log rules:

- Use sequential `RD19-BLOCK-###` ids.
- Do not store raw evidence, absolute paths, credentials, media names, server
  names, account names, process ids, native handles, or raw logs.
- A release blocker cannot be downgraded without RD-19 controller adjudication
  and a reviewed enabling plan or reviewed scope change.
- A deferred item must name user impact, owner, and revisit trigger.

## Unit D Blocker Log

| ID | Date | Area | Summary | Classification | Stop condition hit | Safe evidence | Owner for next enabling plan | Revisit trigger | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RD19-BLOCK-001 | 2026-05-14 | Auth | Live Plex sign-in is absent; injected/fake auth proof passed. | beta blocker | none | `npm run verify` passed; `npm run smoke:electron` passed | Main Plex runtime plus preload/renderer Plex API plan | reviewed live Plex auth transport and renderer API scope exists | open |
| RD19-BLOCK-002 | 2026-05-14 | Server selection | Real server picker is absent; injected selected-server and fake shell proof passed. | beta blocker | none | `npm run verify` passed; `npm run smoke:electron` passed | Main Plex runtime plus preload/renderer Plex API plan | reviewed live discovery and server-picker scope exists | open |
| RD19-BLOCK-003 | 2026-05-14 | Channel creation | Live Plex library-backed channel creation is absent; fake/domain proof passed. | beta blocker | none | `npm run verify` passed; `npm run smoke:electron` passed | Renderer Plex APIs plus live library/channel creation plan | reviewed live library browse and channel-authoring scope exists | open |
| RD19-BLOCK-004 | 2026-05-14 | Playback | Production native playback is absent; fake/injected proof passed. | release blocker for public release; beta blocker for real media beta | none | `npm run verify` passed; `npm run smoke:electron` passed | Native helper/playback plan | reviewed production native helper and Plex-to-helper playback setup exists | open |
| RD19-BLOCK-005 | 2026-05-14 | Switching | Real Plex media switching is absent; injected cleanup/fake switching proof passed. | beta blocker | none | `npm run verify` passed; `npm run smoke:electron` passed | Main/helper playback setup plan | reviewed live playback and real channel switching scope exists | open |
| RD19-BLOCK-006 | 2026-05-14 | Subtitles/audio | Real runtime track switching is absent; deterministic policy/resolver proof passed. | beta blocker | none | `npm run verify` passed | Native helper/playback plan | reviewed runtime track switching scope exists | open |
| RD19-BLOCK-007 | 2026-05-14 | EPG | Real Plex/scheduler-backed EPG is absent if required for private MVP; fake/scheduler proof passed. | beta blocker | none | `npm run verify` passed; `npm run smoke:electron` passed | Renderer Plex/scheduler integration plan | reviewed real Plex-backed EPG scope exists | open |
| RD19-BLOCK-008 | 2026-05-14 | Settings | Persistence IPC is absent; fake settings and diagnostics export proof passed. | deferred for fake alpha; beta blocker for real settings beta | none | `npm run verify` passed; RD-17 diagnostics smoke passed | Persistence/recovery plan | reviewed preload/renderer persistence IPC scope exists | open |
| RD19-BLOCK-009 | 2026-05-14 | Sleep/wake | Windows sleep/wake was not forced in Unit D, so playback/network/credential recovery remains unproven. | beta blocker | sleep/wake observation scope not reviewed for forced system transition | no command evidence claimed | Window/platform UX plan | reviewed Windows sleep/wake observation scope with safe manual steps exists | open |
| RD19-BLOCK-010 | 2026-05-14 | Fullscreen | Production native fullscreen playback remains absent; shell/fake fullscreen proof passed. | release blocker for public playback | none | `npm run verify` passed; `npm run smoke:electron` passed | Native helper/playback plan | reviewed production native fullscreen playback scope exists | open |
| RD19-BLOCK-011 | 2026-05-14 | Multi-monitor | Production video multi-monitor proof remains absent; shell display-fit proof passed. | deferred until playback unit unless severe | none | display count 2; primary display count 1; `npm run verify` passed | Native helper/playback plan | reviewed production playback multi-monitor scope exists | open |
| RD19-BLOCK-012 | 2026-05-14 | Install/delete | Signed installer, update behavior, and public distribution are absent; unpacked internal package proof passed. | deferred for maintainer alpha; release blocker for public release | none | package creation passed; package verifier passed; launch/delete observation passed | Packaging/release plan | reviewed installer, signing, update, or public distribution scope exists | open |
| RD19-BLOCK-013 | 2026-05-14 | Long playback | Real long playback is absent and no Unit D soak was run. | beta blocker | long-playback soak not in reviewed Unit D scope | no soak evidence claimed | Runtime/window/diagnostics plan or production playback plan | reviewed long-playback validation scope with fixed duration, harness, resource checks, threshold, and redacted evidence fields exists | open |
