# Lineup Product Parity Matrix

**Current gate:** Packages 0–8 renderer parity implementation and local
automated verification are complete; RD-27 is the next Tier 3 planning target.
Every Windows-required row remains blocked until observed Windows proof, and
Package 6's mandatory fresh three-row operator-assisted fullscreen audit remains
an RD-27 gate. No UI row may advance to platform-complete by substituting Mac
diagnostics or local automated proof for that audit.

## Purpose

This matrix is the RD-21 product parity artifact for comparing original Lineup
product workflows with the Desktop repo's current proof. It is a conservative
MVP planning surface, not a readiness claim. Unit 2 fills current Desktop
evidence from tracked docs, source, tests, and tools. Unit 3 fills upstream
comparison evidence from the pinned original Lineup baseline.

RD-21 Unit 2 classifies only current Desktop proof. It does not implement
product runtime, import upstream source, revise the roadmap, add renderer Plex
APIs, add persistence IPC, enable production native playback, or make public
release claims.

## Redaction Policy

Tracked rows may include:

- upstream commit hashes and relative upstream paths
- relative Desktop paths, symbol names, sanitized behavior summaries, and
  verifier command names
- proof labels, owner surfaces, blocker types, and roadmap-slice placeholders

Tracked rows must not include:

- Plex tokens, auth headers, credential values, or secret-bearing request data
- raw Plex payloads, raw IPC frames, native handles, process identifiers, logs,
  dumps, support-bundle contents, or screenshots
- absolute local paths, private account names, server names, media titles,
  private workspace details, local package output details, or private network
  details
- signing credentials, certificate material, raw installer output, or raw
  native/media binary evidence

If evidence contains forbidden material, record only a redacted summary and a
relative evidence pointer, then rerun the redaction verifier before closeout.

## Source-Evidence Rules

- Treat upstream Lineup as read-only evidence.
- Record only relative upstream paths and the reviewed upstream commit.
- Default upstream baseline:
  `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`.
- A row seeded before source audit must use `TBD` rather than inferred upstream
  detail.
- Desktop evidence must be a relative path, verifier command, test area,
  sanitized proof note, or `TBD`.
- Existing Desktop fake, domain, injected, harness, package, diagnostics, and
  docs/provenance proof must be classified by proof type rather than promoted
  to product completion.
- If upstream discovery changes the baseline commit or materially changes a
  workflow definition, stop and replan before broadening classification.

## Upstream Baseline Handling

The baseline for RD-21 rows is upstream commit
`76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`. Unit 1 does not claim that every
row has been audited against that baseline. Unit 2 keeps upstream evidence as
`TBD` unless an RD-20 tracked architecture artifact already supplies provenance
evidence. Unit 3 must replace remaining `TBD` upstream evidence with relative
upstream paths and confirm the commit before a row can be used as original
Lineup product parity evidence.

## Required Columns

| Column | Meaning |
| --- | --- |
| Feature/workflow | Stable product workflow or capability being classified. |
| Original Lineup source or UI evidence | Relative upstream paths, source symbols, docs, sanitized UI observation, or `TBD`; no local paths or raw private evidence. |
| Desktop evidence path | Relative Desktop docs, source, tests, verifier, or proof artifact path. |
| Classification | One value from the RD-21 classification vocabulary. |
| Evidence level | One value from the RD-21 evidence-level vocabulary. |
| Platform proof label | One value from the platform proof label vocabulary, or a specific blocked proof note. |
| Current Desktop owner | Existing owner surface or `none yet`. |
| Required next roadmap slice | Specific next slice needed to reach MVP, `TBD`, or `none`. |
| Blocker type | One RD-21 blocker type or `none`. |
| Confidence/freshness date | Date evidence was last checked, or `TBD`. |
| Replan trigger | Concrete condition requiring reclassification or plan update. |

## Classification Vocabulary

| Classification | Meaning |
| --- | --- |
| `complete` | Product-scope Desktop behavior is proven at the required platform depth for this row. |
| `fake-backed UI only` | Renderer or shell workflow exists only through fake/local view models or fake data. |
| `domain-only` | Pure domain or injected unit proof exists, but no product runtime behavior is proven. |
| `harness/dev-only proof` | Dev harness, smoke, package, or local validation proof exists but is not production product behavior. |
| `docs/provenance proof` | Documentation, source audit, import ledger, or provenance evidence exists only. |
| `missing` | Required workflow or capability is not present or has not been proven. |
| `blocked` | Required workflow is blocked by a named product, architecture, platform, runtime, packaging, playback, persistence, or security dependency. |
| `intentionally divergent` | Desktop deliberately differs from original Lineup with a product rationale and owner. |

## Evidence-Level Vocabulary

| Evidence level | Meaning |
| --- | --- |
| `source audit` | Read-only upstream or Desktop source inspection. |
| `docs/provenance` | Architecture, import-ledger, roadmap, package provenance, or validation docs. |
| `domain test` | Pure domain or contract tests without product runtime wiring. |
| `injected transport test` | Main-owned behavior proven with injected transport, fixtures, or fake ports. |
| `fake-backed UI` | Renderer or shell workflow proven with fake data or local-only state. |
| `harness/dev-only proof` | Dev harness, smoke, internal package, or local validation proof. |
| `Windows observed proof` | Redacted observed Windows proof for the exact product/platform claim. |
| `blocked/missing` | No acceptable proof yet, or proof is blocked by a named dependency. |

## Platform Proof Labels

| Label | Meaning |
| --- | --- |
| `Mac/local automated proof sufficient` | Acceptable only for docs, source-audit, provenance, pure domain, or local automated proof that does not make Windows runtime claims. |
| `Windows proof required before closeout` | Row cannot be product-complete until observed Windows proof exists. |
| `Windows proof deferred to <RD item>` | Windows proof is required, but the proof owner belongs to a later reviewed roadmap slice. |
| `implemented and automated locally; Windows operator-assisted proof pending` | Production behavior and local automated proof exist, but the named Windows operator-assisted audit is still required before platform completion. |
| `blocked: <reason>` | Required proof is blocked by a named dependency or missing reviewed scope. |

## Blocker Taxonomy

| Blocker type | Meaning |
| --- | --- |
| `product decision` | Product behavior or MVP acceptance is not decided. |
| `architecture decision` | Ownership, process boundary, IPC, contract, or module direction is not decided. |
| `Windows proof` | Required observed Windows proof is absent. |
| `live Plex/runtime` | Live Plex transport, runtime composition, or real server/library data is absent. |
| `native playback` | Production native playback, track switching, recovery, or video-surface proof is absent. |
| `persistence` | Required persisted settings, selected state, or channel/runtime recovery is absent. |
| `packaging/release` | Installer, signing, update, public release, or package proof is absent. |
| `redaction/security` | Redaction, secret custody, diagnostics, or privileged data safety is unresolved. |
| `unknown` | Temporary value only for a future row whose blocker cannot yet be classified; do not use for Unit 2 filled Desktop evidence. |
| `none` | No blocker is currently assigned. |

## Classification Rules

- `complete` requires product-scope Desktop behavior, not only local helper
  proof, docs proof, fake UI, or injected seams.
- Domain tests cannot be marked `complete`.
- Fake-backed UI cannot be marked `complete`.
- Harness/dev-only proof cannot be marked `complete`.
- Injected transport tests cannot be marked `complete`.
- Docs/provenance proof cannot be marked `complete`.
- Missing Windows UI evidence cannot be marked `complete`.
- Every `missing` row must name a current owner or `none yet` plus a required
  next roadmap slice.
- Every `blocked` row must name exactly one blocker type from the RD-21 blocker
  vocabulary, plus a replan trigger.
- `intentionally divergent` requires a product rationale and an owner; if the
  divergence weakens MVP value, it also needs a next roadmap slice.
- Live Plex, production native playback, persistence IPC, package/release,
  signing/update, installer, or native/media redistribution gaps remain blocked
  until reviewed implementation work proves them.

## Seeded Parity Rows

These rows cover the minimum RD-21 parity areas. Packages 0–8 now supply the
current renderer implementation and local automated evidence. Rows remain
blocked only where their claim still requires Windows product, native playback,
packaging, or operational-soak proof owned by RD-27 or RD-28.

| Feature/workflow | Original Lineup source or UI evidence | Desktop evidence path | Classification | Evidence level | Platform proof label | Current Desktop owner | Required next roadmap slice | Blocker type | Confidence/freshness date | Replan trigger |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Launch/shell Windows package and local dev | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `package.json`; `vite.config.ts`; `src/index.ts`; `src/platform/webosPlatformServices.ts`; `tools/verify-bundle.mjs`; upstream is a Vite/webOS app with `package:webos`, not a Windows Electron package/install flow. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/packaging-release-gates.md`; `docs/development/rd-19-internal-validation-checklist.md`; `src/main/index.ts`; `src/preload/index.cts`; `src/main/shellSecurity.ts`; `src/__tests__/main/shellSecurity.test.ts`; `tools/package-windows-internal.mjs`; `tools/verify-windows-internal-package.mjs`; `tools/__tests__/package-windows-internal.test.mjs` | harness/dev-only proof | harness/dev-only proof | Windows proof deferred to RD-28 | shell main/preload/window owners plus packaging/provenance tooling owner | RD-28 Internal Package Install/Delete MVP Proof | packaging/release | 2026-05-14 | Installer, signing, update, public package, or package-output proof scope is reviewed. |
| Navigation, focus, keyboard, and remote-like parity | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/navigation/**`; `src/platform/webosPlatformServices.ts`; `src/core/orchestrator/AppOrchestrator.ts`; TV remote key mapping, focus management, guide/settings/channel-number events, and route/screen effects. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/renderer-architecture.md`; Package 8 138-capture and 54-row interaction proof; `src/renderer/navigation.ts`; `src/renderer/desktopInput.ts`; `src/renderer/desktopCursor.ts`; `src/renderer/focusDom.ts`; `src/main/window/shellAppCommandController.ts`; `src/main/window/shellWindowController.ts`; focused renderer/main tests | blocked | local automated proof | renderer parity implementation and local automated verification complete; Windows proof pending RD-27 | renderer navigation/input/cursor owners plus main window/app-command owners | RD-27 Windows MVP UI Proof And Operational Soak | Windows proof | 2026-07-16 | Observed Windows UI proof finds focus, keyboard, fullscreen, app-command, route, or cursor mismatch. |
| Plex sign-in, PIN, auth, profile, and Plex Home UI | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/plex/auth/**`; `src/modules/ui/auth/AuthScreen.ts`; `src/modules/ui/profile-select/**`; `src/core/orchestrator/runtime/OrchestratorPlexAuthRuntime.ts`; PIN request/poll/cancel, Plex Home profile/switch payload parsing, QR/link UI, and profile selection. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/security-and-secret-flow.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M02; Package 8 Packages 1–3 capture/focus proof; `src/main/plex/auth/**`; `src/contracts/plex.ts`; renderer Plex owners and focused tests | blocked | local automated proof plus live runtime seams | renderer hierarchy/focus/exact-viewport proof complete; Windows live observation pending RD-27 | main/preload/renderer Plex auth and profile owners | RD-27 Windows MVP UI Proof And Operational Soak | Windows proof | 2026-07-16 | Live auth contracts change or Windows onboarding proof contradicts the frozen matrix. |
| Server discovery and restore UI | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/plex/discovery/**`; `src/core/server-selection/**`; `src/modules/ui/server-select/**`; `src/core/orchestrator/runtime/OrchestratorServerSelectionRuntime.ts`; resource discovery, selected-server persistence, saved-server auto-connect, refresh, clear, and setup rerun UI. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/security-and-secret-flow.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M03; Package 8 Packages 1–3 capture/focus proof; `src/main/plex/discovery/**`; `src/contracts/plex.ts`; renderer Plex runtime owners and focused tests | blocked | local automated proof plus live runtime seams | renderer-safe server focus/error/exact-viewport proof complete; Windows live observation pending RD-27 | main/preload/renderer discovery and selected-server owners | RD-27 Windows MVP UI Proof And Operational Soak | Windows proof | 2026-07-16 | Discovery contracts change or Windows server-screen proof contradicts the frozen matrix. |
| Library browsing, search, and metadata | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/plex/library/**`; `src/modules/ui/channel-setup/steps/LibraryStepController.ts`; `src/modules/ui/epg/view/EPGLibraryTabs.ts`; library sections, listings, item metadata/details, media file/stream parsing, tag-directory policy, and library-driven setup/guide surfaces. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M01; Package 8 setup/library capture proof; `src/main/plex/library/**`; `src/contracts/plex.ts`; renderer library/setup owners and focused tests | blocked | local automated proof plus live runtime seams | staged library/preview exact-viewport proof complete; Windows live observation pending RD-27 | main/preload/renderer library and staged-setup owners | RD-27 Windows MVP UI Proof And Operational Soak | Windows proof | 2026-07-16 | Library contracts change or Windows staged library/preview evidence contradicts runtime truth. |
| Channel setup from real Plex library data | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/core/channel-setup/**`; `src/modules/ui/channel-setup/**`; `src/modules/scheduler/channel-manager/**`; setup wizard loads real libraries, builds strategy/config, previews warnings, commits channels, and supports rerun. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/renderer-architecture.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M05/M12; Package 8 setup capture/focus proof; channel domain/persistence and renderer setup owners/tests | blocked | local automated proof plus live runtime seams | single-stage composition and exact focus/error/viewport proof complete; Windows live observation pending RD-27 | channel domain/persistence plus renderer staged-setup owners | RD-27 Windows MVP UI Proof And Operational Soak | Windows proof | 2026-07-16 | Live setup/build behavior changes or Windows staged proof contradicts runtime truth. |
| Channel/settings persistence through runtime | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/scheduler/channel-manager/ChannelPersistence*.ts`; `src/modules/scheduler/channel-manager/ChannelRepository.ts`; `src/modules/scheduler/channel-manager/StoredChannelDataCodec.ts`; `src/modules/settings/**`; `src/core/orchestrator/storage/OrchestratorStorageContext.ts`; local storage-backed channel, profile, EPG, playback, audio, subtitle, theme, developer, and now-playing preferences. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/security-and-secret-flow.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M06; Package 4 14-capture and two-launch relaunch proof; channel and Settings persistence owners/tests | blocked | local automated and relaunch proof | schema-1 Settings persistence, consumers, failure handling, relaunch, and exact UI proof complete; Windows observation pending RD-27 | main channel and Settings persistence owners plus preload/renderer Settings owners | RD-27 Windows MVP UI Proof And Operational Soak | Windows proof | 2026-07-16 | Settings seam changes, relaunch proof fails, or Windows persistence truth changes. |
| Scheduler-backed guide/EPG from persisted channels | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/scheduler/scheduler/**`; `src/modules/scheduler/shared/playbackOrdering.ts`; `src/modules/ui/epg/**`; `src/core/orchestrator/controllers/ScheduleDayRolloverController.ts`; persisted channels feed schedule calculation, EPG grid virtualization, guide focus, schedule refresh, library tabs, and info panel. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/renderer-architecture.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M04; Package 5 12-capture proof; scheduler domain and renderer Guide owners/tests | blocked | local automated proof plus scheduler runtime | scheduler-backed states, geometry, focus, current-only tune, empty/error handling, and exact viewport proof complete; Windows observation pending RD-27 | scheduler/channel runtime plus renderer Guide owners | RD-27 Windows MVP UI Proof And Operational Soak | Windows proof | 2026-07-16 | Scheduler/Guide contracts change or Windows schedule-state proof contradicts runtime truth. |
| Player route, now-playing, OSD, mini-guide, and channel badge | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/ui/player-osd/**`; `src/modules/ui/mini-guide/**`; `src/modules/ui/now-playing-info/**`; `src/modules/ui/channel-badge/**`; `src/modules/ui/channel-number-overlay/**`; `src/modules/ui/channel-transition/**`; `src/core/orchestrator/priority-one/**`; route overlays show now-playing, progress, audio/subtitle labels, mini-guide, channel badge/number, and transitions. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/renderer-architecture.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M13; `docs/architecture/original-lineup-divergence-register.md` RD20-D12; Package 7 67-row and Package 8 integrated proof; renderer Player/overlay owners and focused tests | blocked | local automated proof | implemented and automated locally; Windows operator-assisted proof pending | renderer player overlay and workflow owners | RD-27 mandatory `Package 6 operator-assisted fullscreen focus audit` | Windows proof | 2026-07-16 | Observed Windows UI proof contradicts overlay stack, route transitions, focus, now-playing, mini-guide, badge behavior, or the named three-row audit. |
| Production playback direct play/direct stream/transcode/switching/stop/fullscreen/crash recovery | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/player/**`; `src/modules/plex/stream/**`; `src/core/orchestrator/priority-one/**`; `src/core/orchestrator/runtime/OrchestratorChannelSwitchRuntime.ts`; `src/types/channelSwitch.ts`; browser/video-element playback with Plex stream decisions, direct play/transcode URL policy, channel switching, retry/keepalive, stop/unload, and recovery managers. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/playback-architecture.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M08/M13; Package 7 local Player/overlay proof; `src/main/player/desktopPlayerAdapter.ts`; `src/main/player/nativePlayerHostProcess.ts`; `src/main/player/plexPlaybackRuntime.ts`; `src/main/player/plexPlaybackBridge.ts`; `src/main/player/plexPlaybackComposition.ts`; `src/main/plex/streamResolver.ts`; focused player, IPC, resolver, and renderer tests; `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`; `tools/rd17-diagnostics-smoke.mjs` | blocked | local automated proof | RD-25 code and local automated renderer/runtime proof complete; Windows production native-playback observation pending RD-27 | main player/runtime owner plus native-helper and renderer Player/overlay owners | RD-27 Windows MVP UI Proof And Operational Soak | native playback | 2026-07-16 | Windows playback lifecycle, fullscreen, switching, stop, recovery, or video-surface proof contradicts the implemented owners. |
| Subtitles, audio, and HDR runtime vs fixture proof | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/player/SubtitleManager.ts`; `src/modules/player/AudioTrackManager.ts`; `src/modules/player/subtitleFallbackPipeline.ts`; `src/modules/plex/stream/policy/**`; `src/modules/plex/stream/diagnostics/**`; `src/modules/settings/PlaybackSettingsStore.ts`; subtitle fallback/conversion, audio track selection, HDR/Dolby Vision fallback policy, media selection, and debug probes. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/playback-architecture.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M08/M13; Package 7 playback-options presentation proof; `src/main/player/streamPolicy/desktopStreamPolicy.ts`; `src/main/player/streamPolicy/types.ts`; `src/main/plex/streamResolver.ts`; `src/contracts/player.ts`; focused stream-policy, resolver, contract, Player, and overlay tests | blocked | local automated proof | RD-26 code, policy/runtime seams, and local options presentation proof complete; Windows runtime track, subtitle, audio, and HDR observation pending RD-27 | stream policy owner plus Plex resolver, native-helper, and renderer playback-options owners | RD-27 Windows MVP UI Proof And Operational Soak | native playback | 2026-07-16 | Windows runtime track selection, subtitle/audio behavior, HDR policy, or playback-options proof contradicts the implemented owners. |
| Diagnostics/support bundle export and redaction actual UI | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/core/app-shell/diagnostics/**`; `src/modules/debug/**`; `src/modules/ui/settings/**`; `src/utils/redact.ts`; `tools/verify-docs.mjs`; diagnostics dev menu/playback/setup summaries and best-effort token/URL redaction in logging helpers. | `docs/architecture/CURRENT_STATE.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M10; Package 8 integrated redaction-safe evidence; `src/contracts/diagnostics.ts`; `src/contracts/redaction.ts`; `src/main/diagnostics/diagnosticEventStore.ts`; `src/main/diagnostics/supportBundleExporter.ts`; `src/main/redactedDiagnostics.ts`; `src/renderer/supportBundleExport.ts`; focused support-bundle and redaction verification | harness/dev-only proof | local automated proof | renderer parity and local redaction verification complete; Windows support-bundle UI observation deferred to RD-27 | diagnostics and redaction owners plus renderer settings export owner | RD-27 Windows MVP UI Proof And Operational Soak | redaction/security | 2026-07-16 | Diagnostics contract, export UI, support-bundle scanner, redaction policy, or Windows observation changes. |
| Packaging, install, and delete internal Windows flow | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `package.json`; `vite.config.ts`; `tools/verify-bundle.mjs`; `tools/generate-placeholder-webos-assets.mjs`; upstream packaging targets webOS bundle/package proof and has no Windows installer/delete flow. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/packaging-release-gates.md`; `docs/development/rd-19-internal-validation-checklist.md`; `tools/package-windows-internal.mjs`; `tools/verify-windows-internal-package.mjs`; `tools/__tests__/package-windows-internal.test.mjs` | harness/dev-only proof | harness/dev-only proof | Windows proof deferred to RD-28 | packaging/provenance tooling owner | RD-28 Internal Package Install/Delete MVP Proof | packaging/release | 2026-05-14 | Reviewed installer, signing, update, public distribution, or package-output retention scope exists. |
| Sleep/wake, long playback, multi-monitor, fullscreen, and UI over video | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/platform/webosPlatformServices.ts`; `src/modules/player/KeepAliveManager.ts`; `src/modules/player/PlaybackRecoveryManager.ts`; `src/styles/video.css`; `src/styles/shell.player-runtime-chrome.css`; webOS-oriented keepalive/recovery and browser video-plane styling, not Windows sleep/wake, multi-monitor, or native video-surface proof. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/playback-architecture.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/development/windows-ui-proof-plan.md`; Package 7 local fullscreen continuity proof; `src/main/window/shellWindowController.ts`; `src/__tests__/main/shellWindowController.test.ts`; `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`; `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs` | blocked | blocked/missing | renderer/local fullscreen proof complete; production playback, forced sleep/wake, long-playback soak, and production video multi-monitor proof remain for Windows RD-27 | window/platform UX owner plus native playback owner plus diagnostics owner | RD-27 Windows MVP UI Proof And Operational Soak | Windows proof | 2026-07-16 | Windows sleep/wake, long-playback, multi-monitor, fullscreen, or UI-over-video observation contradicts the implemented owners. |
| Intentional divergence from original Lineup | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: divergence anchors are the same upstream families audited by RD20-D01 through RD20-D12, including `src/modules/plex/library/**`, `src/modules/plex/auth/**`, `src/modules/plex/discovery/**`, `src/core/server-selection/**`, `src/modules/scheduler/**`, `src/modules/scheduler/channel-manager/**`, `src/modules/player/**`, `src/modules/plex/stream/**`, `src/platform/**`, `src/modules/ui/**`, `src/core/channel-setup/**`, `src/styles/**`, `src/types/channelSwitch.ts`, and `src/utils/redact.ts`; sanitized divergence themes include browser/webOS storage, webOS playback/platform assumptions, renderer-adjacent secrets, upstream UI/runtime coupling, stricter Desktop diagnostic redaction, and the documented Desktop Info/Back overlay-stack policy. | `docs/architecture/original-lineup-divergence-register.md` RD20-D01 through RD20-D12; `docs/architecture/original-lineup-reference-compatibility-matrix.md` through RD20-M13; `docs/architecture/CURRENT_STATE.md`; `docs/architecture/renderer-architecture.md`; `docs/architecture/playback-architecture.md`; `docs/architecture/security-and-secret-flow.md` | docs/provenance proof | docs/provenance | Mac/local automated proof sufficient | architecture/product parity docs plus source owners named by each RD-20 divergence row | RD-27 or RD-28 if a divergence weakens MVP parity or changes platform proof | none | 2026-07-16 | A divergence weakens MVP value, adds runtime scope, or contradicts upstream product parity evidence. |

## Unit 2/3 Fill Rules

When Unit 2 or Unit 3 replaces seeded values:

- keep every path relative
- record the upstream commit used for the row
- downgrade, never upgrade, a row when proof is ambiguous
- use `blocked` for missing Windows runtime/UI proof where the proof is
  required for the claim
- keep Unit 2 upstream evidence as `TBD` unless an existing RD-20 architecture
  artifact is the evidence source
- keep raw evidence in ignored local artifacts only
- rerun `npm run verify:docs`, `npm run verify:redaction`, and
  `git diff --check` after tracked edits
