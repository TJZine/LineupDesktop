# Lineup Product Parity Matrix

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

These rows cover the minimum RD-21 parity areas. Unit 2 fills current Desktop
evidence only; Unit 3 fills upstream evidence from relative source paths and
sanitized workflow summaries. No row below is complete because
the current repo proof is fake-backed, injected, domain-only, harness/dev-only,
docs/provenance, missing live runtime, or missing Windows product proof for the
claim.

| Feature/workflow | Original Lineup source or UI evidence | Desktop evidence path | Classification | Evidence level | Platform proof label | Current Desktop owner | Required next roadmap slice | Blocker type | Confidence/freshness date | Replan trigger |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Launch/shell Windows package and local dev | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `package.json`; `vite.config.ts`; `src/index.ts`; `src/platform/webosPlatformServices.ts`; `tools/verify-bundle.mjs`; upstream is a Vite/webOS app with `package:webos`, not a Windows Electron package/install flow. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/packaging-release-gates.md`; `docs/development/rd-19-internal-validation-checklist.md`; `src/main/index.ts`; `src/preload/index.cts`; `src/main/shellSecurity.ts`; `src/__tests__/main/shellSecurity.test.ts`; `tools/package-windows-internal.mjs`; `tools/verify-windows-internal-package.mjs`; `tools/__tests__/package-windows-internal.test.mjs` | harness/dev-only proof | harness/dev-only proof | Windows proof deferred to RD-28 | shell main/preload/window owners plus packaging/provenance tooling owner | RD-28 Internal Package Install/Delete MVP Proof | packaging/release | 2026-05-14 | Installer, signing, update, public package, or package-output proof scope is reviewed. |
| Navigation, focus, keyboard, and remote-like parity | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/navigation/**`; `src/platform/webosPlatformServices.ts`; `src/core/orchestrator/AppOrchestrator.ts`; TV remote key mapping, focus management, guide/settings/channel-number events, and route/screen effects. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/renderer-architecture.md`; `docs/development/rd-19-internal-validation-checklist.md`; `src/renderer/navigation.ts`; `src/renderer/desktopInput.ts`; `src/renderer/desktopCursor.ts`; `src/renderer/focusDom.ts`; `src/main/window/shellAppCommandController.ts`; `src/main/window/shellWindowController.ts`; `src/__tests__/renderer/navigation.test.ts`; `src/__tests__/renderer/desktopInput.test.ts`; `src/__tests__/renderer/desktopCursor.test.ts`; `src/__tests__/renderer/focusDom.test.ts`; `src/__tests__/main/shellAppCommandController.test.ts`; `src/__tests__/main/shellWindowController.test.ts` | fake-backed UI only | fake-backed UI | Windows proof required before closeout | renderer navigation/input/cursor owners plus main window/app-command owners | RD-27 Windows MVP UI Proof And Operational Soak | Windows proof | 2026-05-14 | Observed Windows UI proof finds focus, keyboard, fullscreen, app-command, route, or cursor mismatch. |
| Plex sign-in, PIN, auth, profile, and Plex Home UI | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/plex/auth/**`; `src/modules/ui/auth/AuthScreen.ts`; `src/modules/ui/profile-select/**`; `src/core/orchestrator/runtime/OrchestratorPlexAuthRuntime.ts`; PIN request/poll/cancel, Plex Home profile/switch payload parsing, QR/link UI, and profile selection. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/security-and-secret-flow.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M02; `src/main/plex/auth/desktopPlexAuthService.ts`; `src/main/plex/auth/desktopPlexCredentialStore.ts`; `src/main/plex/auth/plexAuthPayloadParsers.ts`; `src/main/plex/auth/plexHomeUsersPayloadParser.ts`; `src/contracts/plex.ts`; `src/__tests__/main/plexAuth.test.ts` | blocked | injected transport test | blocked: live Plex sign-in, renderer-safe auth UI, and live transport composition absent | main Plex auth owner plus future preload/renderer Plex API owner | RD-22 Live Plex Auth, Discovery, And Library Runtime UI | live Plex/runtime | 2026-05-14 | Reviewed live auth transport, profile/Plex Home UI, and renderer-safe auth API scope exists. |
| Server discovery and restore UI | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/plex/discovery/**`; `src/core/server-selection/**`; `src/modules/ui/server-select/**`; `src/core/orchestrator/runtime/OrchestratorServerSelectionRuntime.ts`; resource discovery, selected-server persistence, saved-server auto-connect, refresh, clear, and setup rerun UI. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/security-and-secret-flow.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M03; `src/main/plex/discovery/desktopPlexServerDiscovery.ts`; `src/main/plex/discovery/desktopPlexSelectedServerStore.ts`; `src/main/plex/discovery/discoveryDomain.ts`; `src/contracts/plex.ts`; `src/__tests__/main/plexDiscovery.test.ts` | blocked | injected transport test | blocked: live discovery, restore runtime, and server-picker UI proof absent | main Plex discovery and selected-server owner plus future renderer server-picker owner | RD-22 Live Plex Auth, Discovery, And Library Runtime UI | live Plex/runtime | 2026-05-14 | Reviewed live discovery, selected-server restore, and server-picker UI scope exists. |
| Library browsing, search, and metadata | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/plex/library/**`; `src/modules/ui/channel-setup/steps/LibraryStepController.ts`; `src/modules/ui/epg/view/EPGLibraryTabs.ts`; library sections, listings, item metadata/details, media file/stream parsing, tag-directory policy, and library-driven setup/guide surfaces. | `docs/architecture/CURRENT_STATE.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M01; `src/main/plex/library/libraryDomain.ts`; `src/main/plex/library/parsing/libraryListingParser.ts`; `src/main/plex/library/parsing/mediaItemDetailsParser.ts`; `src/main/plex/library/parsing/streamParser.ts`; `src/contracts/plex.ts`; `src/__tests__/main/plexLibrary.test.ts` | blocked | injected transport test | blocked: live library browse/search UI proof absent | main Plex library owner plus future renderer library browse/search owner | RD-22 Live Plex Auth, Discovery, And Library Runtime UI | live Plex/runtime | 2026-05-14 | Reviewed live library transport and renderer-safe browse/search UI scope exists. |
| Channel setup from real Plex library data | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/core/channel-setup/**`; `src/modules/ui/channel-setup/**`; `src/modules/scheduler/channel-manager/**`; setup wizard loads real libraries, builds strategy/config, previews warnings, commits channels, and supports rerun. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/renderer-architecture.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M05; `src/domain/channel/channelAuthoringService.ts`; `src/domain/channel/channelManager.ts`; `src/renderer/settingsSetup.ts`; `src/renderer/workflow.ts`; `src/__tests__/domain/channelDomain.test.ts`; `src/__tests__/renderer/workflow.test.ts`; `src/__tests__/renderer/routeDom.test.ts` | blocked | fake-backed UI | blocked: real Plex library-backed setup and live channel authoring absent | channel domain owner plus renderer channel setup owner plus future renderer Plex API owner | RD-23 Live Channel Setup And Runtime Persistence | live Plex/runtime | 2026-05-14 | Reviewed live library-backed channel creation and persistence handoff scope exists. |
| Channel/settings persistence through runtime | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/scheduler/channel-manager/ChannelPersistence*.ts`; `src/modules/scheduler/channel-manager/ChannelRepository.ts`; `src/modules/scheduler/channel-manager/StoredChannelDataCodec.ts`; `src/modules/settings/**`; `src/core/orchestrator/storage/OrchestratorStorageContext.ts`; local storage-backed channel, profile, EPG, playback, audio, subtitle, theme, developer, and now-playing preferences. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/security-and-secret-flow.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M06; `src/domain/channel/channelPersistenceCoordinator.ts`; `src/domain/channel/channelPersistenceSaveQueue.ts`; `src/domain/channel/channelRepository.ts`; `src/domain/channel/storedChannelDataCodec.ts`; `src/main/persistence/desktopChannelPersistenceStore.ts`; `src/contracts/persistence.ts`; `src/__tests__/domain/channelPersistence.test.ts`; `src/__tests__/main/channelPersistenceAdapter.test.ts`; `src/__tests__/main/persistenceBoundary.test.ts` | blocked | domain test | blocked: renderer/runtime persistence IPC and settings recovery proof absent | main persistence owner plus channel persistence owner plus future preload/renderer persistence API owner | RD-23 Live Channel Setup And Runtime Persistence | persistence | 2026-05-14 | Reviewed preload/renderer persistence IPC, settings recovery, and restart validation scope exists. |
| Scheduler-backed guide/EPG from persisted channels | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/scheduler/scheduler/**`; `src/modules/scheduler/shared/playbackOrdering.ts`; `src/modules/ui/epg/**`; `src/core/orchestrator/controllers/ScheduleDayRolloverController.ts`; persisted channels feed schedule calculation, EPG grid virtualization, guide focus, schedule refresh, library tabs, and info panel. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/renderer-architecture.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M04; `src/domain/scheduler/channelScheduler.ts`; `src/domain/scheduler/scheduleCalculator.ts`; `src/domain/scheduler/shared/playbackOrdering.ts`; `src/renderer/epg.ts`; `src/renderer/routeDom.ts`; `src/__tests__/domain/schedulerDomain.test.ts`; `src/__tests__/renderer/epg.test.ts`; `src/__tests__/renderer/routeDom.test.ts` | blocked | fake-backed UI | blocked: persisted-channel runtime guide proof absent | scheduler domain owner plus renderer guide owner plus future runtime composition owner | RD-24 Scheduler-Backed Guide And MVP Channel Runtime | live Plex/runtime | 2026-05-14 | Reviewed persisted-channel guide and runtime schedule composition scope exists. |
| Player route, now-playing, OSD, mini-guide, and channel badge | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/ui/player-osd/**`; `src/modules/ui/mini-guide/**`; `src/modules/ui/now-playing-info/**`; `src/modules/ui/channel-badge/**`; `src/modules/ui/channel-number-overlay/**`; `src/modules/ui/channel-transition/**`; `src/core/orchestrator/priority-one/**`; route overlays show now-playing, progress, audio/subtitle labels, mini-guide, channel badge/number, and transitions. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/renderer-architecture.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M09; `src/renderer/overlays.ts`; `src/renderer/overlayViewModels.ts`; `src/renderer/routeDom.ts`; `src/renderer/workflow.ts`; `src/renderer/staticDom.ts`; `src/__tests__/renderer/overlays.test.ts`; `src/__tests__/renderer/routeDom.test.ts`; `src/__tests__/renderer/workflow.test.ts` | fake-backed UI only | fake-backed UI | Windows proof required before closeout | renderer player overlay and workflow owners | RD-24 Scheduler-Backed Guide And MVP Channel Runtime, then RD-27 Windows MVP UI Proof And Operational Soak | Windows proof | 2026-05-14 | Observed Windows UI proof contradicts overlay stack, route transitions, focus, now-playing, mini-guide, or badge behavior. |
| Production playback direct play/direct stream/transcode/switching/stop/fullscreen/crash recovery | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/player/**`; `src/modules/plex/stream/**`; `src/core/orchestrator/priority-one/**`; `src/core/orchestrator/runtime/OrchestratorChannelSwitchRuntime.ts`; `src/types/channelSwitch.ts`; browser/video-element playback with Plex stream decisions, direct play/transcode URL policy, channel switching, retry/keepalive, stop/unload, and recovery managers. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/playback-architecture.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M08; `src/main/player/desktopPlayerAdapter.ts`; `src/main/player/nativePlayerHostProcess.ts`; `src/main/player/plexPlaybackRuntime.ts`; `src/main/player/plexPlaybackBridge.ts`; `src/main/player/plexPlaybackComposition.ts`; `src/main/plex/streamResolver.ts`; `src/__tests__/main/player/desktopPlayerAdapter.test.ts`; `src/__tests__/main/player/nativePlayerHostProcess.test.ts`; `src/__tests__/main/player/plexPlaybackRuntime.test.ts`; `src/__tests__/main/player/plexPlaybackBridge.test.ts`; `src/__tests__/main/player/plexPlaybackComposition.test.ts`; `src/__tests__/main/playerIpc.test.ts`; `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`; `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs`; `tools/rd17-diagnostics-smoke.mjs` | blocked | harness/dev-only proof | blocked: production native playback, live Plex transport, and production helper proof absent | main player/runtime owner plus native-helper owner | RD-25 Production Native Playback MVP | native playback | 2026-05-14 | Reviewed production native helper and Plex-to-helper playback setup scope exists. |
| Subtitles, audio, and HDR runtime vs fixture proof | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/modules/player/SubtitleManager.ts`; `src/modules/player/AudioTrackManager.ts`; `src/modules/player/subtitleFallbackPipeline.ts`; `src/modules/plex/stream/policy/**`; `src/modules/plex/stream/diagnostics/**`; `src/modules/settings/PlaybackSettingsStore.ts`; subtitle fallback/conversion, audio track selection, HDR/Dolby Vision fallback policy, media selection, and debug probes. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/playback-architecture.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M08; `src/main/player/streamPolicy/desktopStreamPolicy.ts`; `src/main/player/streamPolicy/types.ts`; `src/main/plex/streamResolver.ts`; `src/contracts/player.ts`; `src/__tests__/main/player/desktopStreamPolicy.test.ts`; `src/__tests__/main/plexStreamResolver.test.ts`; `src/__tests__/contracts/contracts.test.ts` | blocked | domain test | blocked: real runtime track switching, subtitle/audio selection, and HDR playback proof absent | stream policy owner plus Plex resolver owner plus native-helper owner | RD-26 Runtime Media Options And Playback Quality | native playback | 2026-05-14 | Reviewed runtime subtitle, audio, HDR, and track switching proof scope exists. |
| Diagnostics/support bundle export and redaction actual UI | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/core/app-shell/diagnostics/**`; `src/modules/debug/**`; `src/modules/ui/settings/**`; `src/utils/redact.ts`; `tools/verify-docs.mjs`; diagnostics dev menu/playback/setup summaries and best-effort token/URL redaction in logging helpers. | `docs/architecture/CURRENT_STATE.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md` RD20-M10; `src/contracts/diagnostics.ts`; `src/contracts/redaction.ts`; `src/main/diagnostics/diagnosticEventStore.ts`; `src/main/diagnostics/supportBundleExporter.ts`; `src/main/redactedDiagnostics.ts`; `src/renderer/supportBundleExport.ts`; `src/__tests__/renderer/supportBundleExport.test.ts`; `tools/rd17-diagnostics-smoke.mjs`; `tools/verify-redaction.mjs`; `tools/__tests__/rd17-diagnostics-smoke.test.mjs`; `tools/__tests__/verify-redaction.test.mjs` | harness/dev-only proof | harness/dev-only proof | Windows proof deferred to RD-27 | diagnostics and redaction owners plus renderer settings export owner | RD-27 Windows MVP UI Proof And Operational Soak | redaction/security | 2026-05-14 | Diagnostics contract, export UI, support-bundle scanner, or redaction policy changes. |
| Packaging, install, and delete internal Windows flow | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `package.json`; `vite.config.ts`; `tools/verify-bundle.mjs`; `tools/generate-placeholder-webos-assets.mjs`; upstream packaging targets webOS bundle/package proof and has no Windows installer/delete flow. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/packaging-release-gates.md`; `docs/development/rd-19-internal-validation-checklist.md`; `tools/package-windows-internal.mjs`; `tools/verify-windows-internal-package.mjs`; `tools/__tests__/package-windows-internal.test.mjs` | harness/dev-only proof | Windows observed proof | Windows proof deferred to RD-28 | packaging/provenance tooling owner | RD-28 Internal Package Install/Delete MVP Proof | packaging/release | 2026-05-14 | Reviewed installer, signing, update, public distribution, or package-output retention scope exists. |
| Sleep/wake, long playback, multi-monitor, fullscreen, and UI over video | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: `src/platform/webosPlatformServices.ts`; `src/modules/player/KeepAliveManager.ts`; `src/modules/player/PlaybackRecoveryManager.ts`; `src/styles/video.css`; `src/styles/shell.player-runtime-chrome.css`; webOS-oriented keepalive/recovery and browser video-plane styling, not Windows sleep/wake, multi-monitor, or native video-surface proof. | `docs/architecture/CURRENT_STATE.md`; `docs/architecture/playback-architecture.md`; `docs/development/rd-19-internal-validation-checklist.md`; `docs/development/windows-ui-proof-plan.md`; `src/main/window/shellWindowController.ts`; `src/__tests__/main/shellWindowController.test.ts`; `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`; `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs` | blocked | blocked/missing | blocked: production playback, forced sleep/wake, long-playback soak, and production video multi-monitor proof absent | window/platform UX owner plus native playback owner plus diagnostics owner | RD-27 Windows MVP UI Proof And Operational Soak | Windows proof | 2026-05-14 | Reviewed Windows sleep/wake, long-playback, multi-monitor, fullscreen, and UI-over-video validation scope exists. |
| Intentional divergence from original Lineup | Upstream baseline `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`: divergence anchors are the same upstream families audited by RD20-D01 through RD20-D10, including `src/modules/plex/library/**`, `src/modules/plex/auth/**`, `src/modules/plex/discovery/**`, `src/core/server-selection/**`, `src/modules/scheduler/**`, `src/modules/scheduler/channel-manager/**`, `src/modules/player/**`, `src/modules/plex/stream/**`, `src/platform/**`, `src/modules/ui/**`, `src/core/channel-setup/**`, `src/styles/**`, `src/types/channelSwitch.ts`, and `src/utils/redact.ts`; sanitized divergence themes include browser/webOS storage, webOS playback/platform assumptions, renderer-adjacent secrets, upstream UI/runtime coupling, and less strict diagnostic redaction compared with Desktop boundaries. | `docs/architecture/original-lineup-divergence-register.md`; `docs/architecture/original-lineup-reference-compatibility-matrix.md`; `docs/architecture/CURRENT_STATE.md`; `docs/architecture/renderer-architecture.md`; `docs/architecture/playback-architecture.md`; `docs/architecture/security-and-secret-flow.md` | docs/provenance proof | docs/provenance | Mac/local automated proof sufficient | architecture/product parity docs plus source owners named by each RD-20 divergence row | RD-22 through RD-28 as applicable if a divergence weakens MVP parity | none | 2026-05-14 | A divergence weakens MVP value, adds runtime scope, or contradicts upstream product parity evidence. |

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
