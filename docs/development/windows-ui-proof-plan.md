# Windows UI Proof Plan

## Purpose

This document defines the RD-21 proof shell for Windows UI, Windows package,
fullscreen, native playback, install/delete, sleep/wake, long playback,
multi-monitor, and UI-over-video claims. It is paired with
`docs/product/lineup-product-parity-matrix.md` and exists to prevent seeded
parity rows from becoming product-readiness claims without observed,
redaction-safe Windows evidence.

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
| Electron smoke or renderer route proof | Route/screen area, status, and sanitized behavior summary | Fake-backed UI remains fake-backed and cannot prove live product parity. |
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

Future RD-21 proof units should define scenario ids, pass/fail criteria, and
redacted summaries for these areas before making claims:

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
| Production playback | Direct play, direct stream, transcode, switching, stop, fullscreen, and crash recovery are proven through the production playback owner. |
| Subtitles/audio/HDR | Runtime track selection and HDR behavior are proven beyond fixture or policy tests. |
| Diagnostics/support bundle | UI export path and completed bundle scanner prove redaction without tracking raw bundle contents. |
| Package install/delete | Internal or public package flow is observed at the scope claimed, with installer/signing/update gaps classified separately. |
| Sleep/wake and long playback | Reviewed Windows sleep/wake and soak scenarios prove recovery, cleanup, resource behavior, and redaction-safe evidence handling. |
| Multi-monitor/fullscreen/UI over video | Display placement, fullscreen transitions, video composition, and overlays are observed on Windows for the claimed playback mode. |

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

If a future proof run needs new runtime behavior, IPC, preload APIs, renderer
Plex APIs, persistence IPC, native playback, packaging/release behavior, or raw
evidence handling, stop and route the work through a reviewed implementation
plan before editing source or broadening claims.
