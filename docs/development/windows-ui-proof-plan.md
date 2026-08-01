# Windows UI Proof Plan

Packages 0–8 renderer parity implementation and local automated verification
remain historical regression evidence. The accepted 2026-07-22 audit now
drives ordered WS1–WS9 correction work: WS1 implementation/review landed with
proof debt, WS2's local implementation gate closed with
`WS2-POST-VALIDATION-01`, and WS3's final product source is Unit 3C-F
checkpoint `87662b5`. Prior Unit 3C-D `5f368d4` and viewport repair `77d09ad`
close their local diagnostic/audio-fallback and Recovery/Switch Profile
obligations. Those are local behavior and DOM/layout/focus proof only, not
deferred Windows or paired-current-upstream proof. Test-only checkpoint `f0e2817`
restores full verification of shared production-host wiring without changing
product behavior or any platform claim. Unit 3C-D locally proves injected
missing-output presentation and production fixed-schema ST-24/ST-25 producers;
real Windows audio disappearance/relaunch/application, subtitle behavior, and
support-bundle observation remain open. Unit 3D is accepted and WS3's local
gate is closed. WS4 targeted scope-load/planning is active; no
product/test/package/config edit starts before its own decision-complete plan
and fresh approval of an exact first unit. RD-27
is not the next implementation target. It begins one consolidated
Windows proof campaign after WS3–WS8 and WS9 prerequisite implementation/
hardening. Windows-required matrix rows remain blocked until observed proof.

## Purpose

This document defines the RD-21 proof shell for Windows UI, Windows package,
fullscreen, native playback, install/delete, sleep/wake, long playback,
multi-monitor, and UI-over-video claims. It is paired with
`docs/product/lineup-product-parity-matrix.md` and exists to prevent seeded
parity rows from becoming product-readiness claims without observed,
redaction-safe Windows evidence.

The consolidated campaign includes accumulated WS1 proof debt,
`WS2-POST-VALIDATION-01`, later workstream Windows/native/manual/live
obligations, RD-27 operational observation/soak, RD-28 package lifecycle, and
the final 227-row program audit. Deferral to that campaign is sequencing, not a
waiver or evidence claim.

Unit 1 creates the proof rules only. It does not run Windows proof, change
runtime behavior, add preload or renderer APIs, implement production playback,
or change packaging/release behavior.

## Redaction-Safe Proof Rules

Tracked proof summaries may include:

- platform family and architecture
- build or package identity without local output details
- command names, route names, verifier names, and exit status
- sanitized counts such as display count, scenario count, or scan count
- pass/fail/blocked status and blocker classification
- short behavior summaries with no private data

Tracked proof summaries must not include:

- local paths, usernames, machine names, workspace details, server names,
  account names, media titles, private library details, or screenshots
- tokens, auth headers, credential values, token-bearing request data, raw Plex
  payloads, raw IPC frames, native handles, process identifiers, raw logs,
  dumps, or support-bundle contents
- raw package output trees, signing credentials, certificate details, raw
  native/media binary evidence, or private network details

Raw proof, screenshots, logs, support bundles, package output, and manual notes
must remain ignored/local. A tracked summary is allowed only after the redaction
gate passes.

## Proof Surfaces

| Proof surface | Allowed tracked summary | Notes |
| --- | --- | --- |
| Automated docs/redaction verification | Command name, exit status, and sanitized failure summary if any | Required for tracked proof-plan or matrix edits. |
| Electron smoke or renderer route proof | Route/screen area, status, and sanitized behavior summary | Local renderer proof establishes its named seam only and cannot replace Windows operational or production-native-video proof. |
| Windows package proof | Package identity, command names, status, verifier status, and blocker summary | Internal unpacked package proof does not prove public release readiness. |
| Windows UI observation | Platform family, scenario id, display count, route area, pass/fail/blocked status | No screenshots or private visible content in tracked docs. |
| Native presentation or playback harness | Harness name, scenario area, status, and sanitized capability limits | Dev-only harness proof cannot prove production native playback. |
| Diagnostics/support-bundle proof | Smoke/verifier name, status, scanner status, and renderer-visible summary shape | No support-bundle contents, logs, paths, or raw diagnostics. |
| Manual install/delete observation | Scenario id, package identity, status, and sanitized user-action summary | No local output tree, user path, machine, or account detail. |
| Sleep/wake and long-playback observation | Scenario id, duration bucket if approved, status, and sanitized recovery summary | Requires reviewed scope before any tracked readiness claim. |

## Forbidden Evidence

Do not store or summarize the following in tracked docs:

- raw screenshots or video captures
- raw logs, dumps, stack traces, IPC frames, support bundles, or package
  manifests
- local package paths or generated output listings
- server, account, media, path, token, request, process, native-handle, or
  private network details
- claims that fake-backed UI, domain tests, injected transport tests,
  dev-harness proof, or docs/provenance proof are product-complete

## Blocked-Classification Guidance

Use `blocked` in the parity matrix when a Windows proof area needs observed
runtime or platform behavior and that proof is absent. Use exactly one blocker
type from the RD-21 matrix taxonomy.

Default blocked classifications:

- Live sign-in, server picker, live library browse, and live channel creation:
  `live Plex/runtime`.
- Runtime settings/channel persistence and recovery: `persistence`.
- Direct play, direct stream, transcode, real switching, fullscreen production
  playback, runtime subtitle/audio/HDR switching, long playback, and crash
  recovery tied to playback: `native playback`.
- Windows install/delete beyond internal unpacked package proof, signing,
  update, and public distribution: `packaging/release`.
- Redaction failures, raw support-bundle exposure, or secret-custody gaps:
  `redaction/security`.
- Missing observed Windows UI/platform proof for focus, overlays,
  multi-monitor, sleep/wake, or UI over video: `Windows proof`.

Rows may use `harness/dev-only proof`, `fake-backed UI only`, `domain-only`, or
`docs/provenance proof` when those are the best current evidence labels, but
those labels must not be upgraded to `complete` without product-scope proof at
the required platform depth.

## Expected Windows Proof Areas

Future consolidated-campaign proof units should define scenario ids, pass/fail
criteria, and redacted summaries for these areas before making claims:

| Area | Minimum expected proof before product-complete claim |
| --- | --- |
| Shell launch and local dev | Windows shell opens the intended route, remains sandboxed, and records only sanitized command/status proof. |
| Navigation/focus/keyboard/remote-like input | Primary routes, focus recovery, text-entry bypass, fullscreen input, app-command input, and remote-like navigation are observed on Windows. |
| Plex auth/profile UI | Live sign-in and profile/Plex Home flows are observed through reviewed main-owned transport and renderer-safe UI. |
| Server discovery/restore UI | Real server selection and restore behavior are observed without exposing connection details. |
| Library browse/search/metadata | Live library browsing and search are observed with renderer-safe metadata only. |
| Channel setup from real library data | Channel creation uses live library data and persists only through reviewed owners. |
| Settings/channel persistence | Runtime restart/recovery proves settings and channels persist through reviewed persistence IPC and main-owned storage. |
| Guide/EPG from persisted channels | Guide data reflects persisted channels and scheduler runtime composition, not fake data. |
| Player overlays and route UI | Now-playing, OSD, mini-guide, channel badge, route transitions, and focus behavior are observed on Windows. |
| Package 6 operator-assisted fullscreen focus audit | Fresh OSD, mini-guide, and options rows each receive exactly one real operator title bar click and prove ordered native/semantic focus, fullscreen, restoration, and cleanup under the blocking protocol below. |
| Production playback | Direct play, direct stream, transcode, switching, stop, fullscreen, and crash recovery are proven through the production playback owner. |
| Subtitles/audio/HDR | Runtime track selection and HDR behavior are proven beyond fixture or policy tests. |
| Diagnostics/support bundle | UI export path and completed bundle scanner prove redaction without tracking raw bundle contents. |
| Package install/delete | Internal or public package flow is observed at the scope claimed, with installer/signing/update gaps classified separately. |
| Sleep/wake and long playback | Reviewed Windows sleep/wake and soak scenarios prove recovery, cleanup, resource behavior, and redaction-safe evidence handling. |
| Multi-monitor/fullscreen/UI over video | Display placement, fullscreen transitions, video composition, and overlays are observed on Windows for the claimed playback mode. |

## WS3 Consolidated-Proof Packet

The ignored local packet under `docs/runs/ws3-settings-quality-loop/` carries
the full prerequisite, entry-action, expected/forbidden-result,
capability-before/after, evidence/hash, redaction, closure-owner, and
failure-routing fields. Its source product checkpoint is `87662b5`. None of
these entries automatically promotes a capability or closes a matrix row:

| Debt / contribution id | Stable ids | Missing scenario and final owner |
| --- | --- | --- |
| `WS3-PROOF-01` | `ON-12`, `WIN-02`, `UI-14` | Real Windows production-helper audio enumeration, stable opaque selection, disappearance/relaunch, playback application, and fallback observation. Injected missing-row presentation, retained saved-id behavior, and explicit System Default completion are locally proved at `5f368d4`. Final closure: consolidated Windows/native campaign under WS9/RD-27 with WS3 authority reconciliation after reviewed proof. |
| `WS3-PROOF-02` | `ST-02`–`ST-10`, `UI-28`, `UI-29`; contribution ids `PB-22`–`PB-24` | Representative native/live audio, subtitle, HDR, Direct Stream/transcode, capability-disabled, and redacted-diagnostic behavior. Final closure: consolidated native/live campaign; `PB-22`–`PB-24` remain WS2-owned and `WS2-POST-VALIDATION-01` stays separate. |
| `WS3-PROOF-03` | `ST-17`, `ST-19`, `ST-20`, `UI-30` | Live-safe artwork availability and honest disabled/enabled Appearance behavior without renderer tokenized URLs. Final closure: later safe-artwork implementation owner plus consolidated live/paired proof. |
| `WS3-PROOF-04` | `ST-25`, `ST-29`, `UI-32` | Windows subtitle-debug and support-bundle export with fixed-schema diagnostics and successful redaction scan. Final closure: consolidated Windows diagnostics proof. |
| `WS3-PROOF-05` | `ST-26`, `ST-30`, `UI-34` | Windows launch mode, version-1 migration/relaunch, corruption/unsupported/revision/save-failure recovery, ACL/temp cleanup, and visible recovery. Final closure: consolidated Windows persistence/recovery proof. |
| `WS3-PROOF-06` | `ST-01`, `UI-28`–`UI-34` | Current-upstream paired Settings visuals/interactions at approved viewports, reduced motion, forced colors, keyboard/D-pad, narrow viewport, and native-video continuity where applicable. Final closure: WS7 current-upstream comparison plus consolidated Windows/native-video proof. Reviewed `77d09ad` closes the local ~900×700 reachability defect and `87662b5` closes enabled-detail category entry, but neither supplies paired/Windows/native proof. |
| `WS3-CONTRIBUTION-WS5` | `ST-11`–`ST-16`, `UI-33` | Persisted values and controls await real WS5 Guide consumers. Final closure: WS5 contribution review and matrix update; registry ownership remains WS3. |
| `WS3-CONTRIBUTION-WS8` | `ST-22`, `ST-23`; contribution target `ON-08` | Startup-picker and persistent Switch Profile implementation plus reviewed local viewport repair are complete, then await WS8 live/profile-switch lifecycle proof. Final closure: WS8 contributes to `ON-08` without taking `ST-23` ownership. |

The packet preserves WS1 proof debt, `WS1-PERF-01`,
`WS2-POST-VALIDATION-01`, conservative production capabilities, later
contribution gates, RD-27, and RD-28. A packet failure routes to the smallest
reviewed implementation owner; the proof run never implements a fix.

## Blocking Package 6 Three-Row Protocol

RD-27 cannot close without a fresh three-pass Windows manifest for all three
rows below:

| State | Exact focus id | Exact owner |
| --- | --- | --- |
| `player-osd` | `overlay-osd-audio` | `playerOsd` |
| `player-mini-guide` | `overlay-mini-channel-sample-channel-1` | `miniGuide` |
| `player-options` | `overlay-subtitle-track-off` | `playbackOptions` |

Each row starts visible but natively inactive with exact production focus
registration, observes readiness, receives exactly one real operator title bar
click, and proves the native transition occurs after readiness and before
confirmation without semantic focus change. It then observes actual fullscreen
enter/leave with native and semantic focus continuity, restores window bounds,
content bounds, CSS viewport, and DPR exactly, cleans up, and emits only
token-free redacted evidence. The Mac diagnostic row satisfies none of these
Windows rows. The active implementation-first sequence defers them only to the
final consolidated campaign; deferral beyond that campaign requires another
explicit reviewed replan.

## Relationship To The Parity Matrix

`docs/product/lineup-product-parity-matrix.md` is the classification owner.
This proof plan is the rulebook for when a seeded row may use a Windows proof
label or remain blocked.

Matrix updates must:

- link each Windows claim to an allowed proof surface or leave it blocked
- keep proof summaries redaction-safe
- preserve `missing` or `blocked` classifications for unobserved runtime/live
  behavior
- use `Windows proof required before closeout` when the row needs observed
  Windows UI/platform behavior before completion
- use `Windows proof deferred to <RD item>` only when the future roadmap slice
  is explicit
- rerun `npm run verify:docs`, `npm run verify:redaction`, and
  `git diff --check` after tracked edits

Before leaving any implementation workstream, its deferred-proof packet must
name the affected stable IDs, required machine/environment, exact scenario,
expected result, source checkpoint, allowed redacted summary, and final
campaign owner. Do not rerun the full 227-row audit at workstream entry; use the
accepted matrix baseline and reconcile only the active workstream's assigned
rows and direct dependencies. The complete one-by-one audit runs once at final
program closeout.

If a future proof run needs new runtime behavior, IPC, preload APIs, renderer
Plex APIs, persistence IPC, native playback, packaging/release behavior, or raw
evidence handling, stop and route the work through a reviewed implementation
plan before editing source or broadening claims.
