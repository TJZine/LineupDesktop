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
| Auth | Confirm injected/fake auth proof remains green. Do not attempt real Plex sign-in. | not run | Live sign-in absence is a beta blocker; token leakage is a release blocker. |
| Server selection | Confirm injected selected-server restore/probe proof or fake UI summary. Do not claim real server picker. | not run | Real server selection absence is a beta blocker. |
| Channel creation | Validate fake channel setup flow and domain-level channel creation summary only. | not run | Live library-backed channel creation absence is a beta blocker. |
| Playback | Validate fake-backed player route, injected runtime proof, or dev-only native-presentation summary. | not run | Production native playback absence is a release blocker for public release and beta blocker for real media beta. |
| Switching | Validate injected switch cleanup proof and fake UI switching only. | not run | Real Plex media switching absence is a beta blocker. |
| Subtitles/audio | Validate deterministic policy/resolver proof. Do not claim real runtime track switching. | not run | Unsafe track leakage is a release blocker; missing real switching is a beta blocker. |
| EPG | Validate fake EPG route, focus, formatting, and UI-over-video summary where available. | not run | Real Plex/scheduler-backed EPG absence is a beta blocker when required for private MVP. |
| Settings | Validate fake settings route and diagnostics export action only. Do not claim persisted settings. | not run | Persistence IPC absence is deferred for fake alpha and beta blocker for real settings beta. |
| Sleep/wake | Record Windows shell/package observation only. Do not claim playback or network recovery. | not run | Runtime playback or credential recovery gaps are beta blockers until owned. |
| Fullscreen | Validate shell/fake UI fullscreen and Windows native-presentation summary where available. | not run | Shell fullscreen failure is a beta blocker; production native fullscreen gap remains release blocker for public playback. |
| Multi-monitor | Record display count/DPI and shell placement only. Do not claim native playback multi-monitor support. | not run | Shell placement failure is a beta blocker; production video gap is deferred until playback unit unless severe. |
| Crash recovery | Validate RD-17 diagnostics smoke summary on Windows when claiming recovery. | not run | Unredacted or unrecovered helper crash is a release blocker. |
| Diagnostics export | Validate RD-17 support-bundle export through smoke or approved package flow. | not run | Redaction failure or absolute path exposure is a release blocker. |
| Install/delete of unpacked package | Validate RD-18 package creation/verifier and manual launch/delete of unpacked artifact only. | not run | Installer absence is deferred for maintainer alpha and release blocker for public release. |
| Long playback | Record optional bounded fake/native-presentation soak only. Do not claim real long playback. | not run | Real long playback absence is a beta blocker until production playback exists. |

## Scenario Summary Template

```md
### Scenario RD19-<area>-<nn>

- Area:
- Platform:
- Build/package identity:
- Command or route:
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
