# Lineup WebOS to Desktop Master Parity Matrix

Last audited: 2026-07-28

This is the single authoritative feature and UI parity ledger for the Windows
Desktop port. It replaces the former 14-row RD-21 summary, which was too coarse
to prevent whole subfeatures from being hidden inside umbrella claims. Roadmap,
architecture, provenance, and proof documents remain evidence sources; this
file owns the one-by-one parity disposition.

## Audit baseline and claim boundary

- Upstream product baseline: Lineup commit
  `0258dbe15b04d2d141d0a4a44575fecb5bb72d41` (2026-07-22). Uncommitted
  upstream documents were excluded.
- Desktop WS2 implementation-gate baseline:
  `d2f1e97` (2026-07-28), with reviewed plan checkpoints `9a66dd6` and
  `60c68f4`, Package 2A at `8dc1057`, and Package 2B at `d2f1e97`. The upstream
  audited code pin remains
  `0258dbe15b04d2d141d0a4a44575fecb5bb72d41`.
- The existing visual bundle was initially captured against upstream
  `6ef20801019e1d1aae2a0158128eba9142d0d008`. Later target/freshness evidence
  used `196a54765c0c6f782ef78c52382de92f1ca1bfd2` for Package 1,
  `5a96aaf52680107a8090db88d5bd8268bbea1c61` for Package 2,
  `cbdeaf57b3f59e52330e843005fcf02b3fbd586d` for Package 3,
  `4bdb0e1b3370e7893a582ec80226557727832d0b` for the Packages 1–3 fidelity
  target, `6c496d0549853278bcec6da9e9962ace0ebfb85d` for Package 4, and
  `a1a7ea7dcb1cfc8aee7cfcf88cf5a1dac718bf30` for Packages 5–7. Its 138
  screenshots remain useful local regression evidence, but the mixed pins all
  predate the current upstream baseline and are not Windows product-completion
  proof.
- Implementation-state labels are distinct from closure and evidence
  classifications. No row is `complete` today, and landed WS1 implementation
  does not advance any WS1 stable-ID closure. `local-match` means a locally
  automated visual target passed; it does not mean current-upstream, live-data,
  native-video, Windows parity, or workstream closure.
- Codanna was available but returned no useful project status for this
  cross-repository audit, so discovery fell back to `rg`, direct source reads,
  tests, tracked proof manifests, and Git commit/diff evidence.

## Status vocabulary

| Status | Meaning |
| --- | --- |
| `live-local` | A real product runtime path exists locally; required Windows/live-environment proof may still be open. |
| `partial` | Some implementation exists, but an upstream capability, state, control, or production path is absent or materially narrower. |
| `missing` | No product implementation was found. Contracts, tests, screenshots, or fake/dev harnesses do not change this status. |
| `proof-only` | Evidence exists only in a fixture, contract, test, screenshot harness, spike, or packaging harness. |
| `desktop-addition` | Useful Desktop functionality with no direct upstream UI equivalent. It cannot substitute for an upstream parity row. |
| `intentional-divergence` | A deliberate platform/security difference with a recorded rationale. Product-value reductions still require explicit approval. |

Visual status uses `local-match`, `partial`, `missing`, `proof-only`,
`desktop-specific`, or `not-a-visual-row`. `proof-only` means visual/platform
evidence exists without a completed product surface. Priority uses `P0` (core
journey blocker), `P1` (major parity gap), `P2` (important follow-up), and `P3`
(polish/platform opportunity).

## Executive verdict

The Desktop app has a credible Electron/Plex/channel/scheduler/native-player
foundation and unusually strong local UI regression evidence. It is not yet a
feature-complete port of current upstream Lineup. The most consequential gaps
are:

1. **P0 — Channel Builder implementation has landed, but parity closure remains
   open.** WS1 now owns deterministic strategies/planning, Plex facets,
   review/apply operations, atomic persistence/startup, cancellation, the
   five-operation preload bridge, and renderer configuration/review/progress/
   result/recovery. Current paired visual manifests, broader live facet/filter
   and append/replace proof, named Windows/manual states, packaged ACL proof,
   and `WS1-PERF-01` remain open, so no stable ID advances to complete.
2. **P0 — Production playback enables far less than the UI/contracts suggest.**
   The production capability profile permits MP4/H.264/AAC direct play with no
   subtitles and declares track switching, HDR, direct stream, and transcode
   unsupported, even though policy/tests and parts of the native helper model
   richer behavior. Windows observation is necessary, but it cannot close this
   code-level capability gap by itself.
3. **P1 — Settings parity is substantially incomplete.** Upstream exposes more
   than twenty playback, audio, subtitle, guide, appearance, account, and
   developer preferences. Desktop persists four values: launch mode, one guide
   density choice, preview badges, and setup reminder, plus a support-bundle
   action.
4. **P1 — Input/player-control parity is incomplete.** Desktop handles
   navigation, Guide, Settings, Info, digits, fullscreen, and Space play/pause,
   but does not route upstream-style media play/pause, rewind, fast-forward, or
   stop keys. Sleep timer is absent.
5. **P1 — The visual parity claim is stale and narrower than it sounds.** The
   54-surface matrix and 138 captures are valuable, but 18 surface dispositions
   are Desktop divergences, several captures represent omitted controls, and
   the reference commit predates the current upstream baseline.
6. **P2 — Desktop adds a useful Custom Channels workspace**, including safe
   media picking, create/duplicate/delete/hide/reorder operations. It is not a
   replacement for the upstream bulk Channel Builder, and direct edit of a
   persisted channel plus advanced draft controls remain incomplete.

## 1. Startup, authentication, profiles, and server selection

Evidence: upstream `src/core/initialization/**`, `src/modules/plex/auth/**`,
`src/modules/plex/discovery/**`, `src/modules/ui/auth/**`,
`src/modules/ui/profile-select/**`, `src/modules/ui/server-select/**`, and
`src/modules/ui/audio-setup/**`; Desktop `src/main/plex/**`,
`src/renderer/onboarding/**`, `src/renderer/plexRuntime*.ts`,
`src/renderer/profilePinModal.ts`, and focused Plex/renderer tests.

| ID | Capability/state | Desktop status | Visual status | Gap / acceptance needed | Priority |
| --- | --- | --- | --- | --- | --- |
| ON-01 | Splash and blocking startup ownership | `live-local` | `local-match` | Revalidate against current upstream and on packaged Windows startup. | P2 |
| ON-02 | Request Plex PIN and show link code/QR | `live-local` | `local-match` | Live Windows auth proof remains required. | P1 |
| ON-03 | PIN polling, waiting, expiry, retry, and cancel | `live-local` | `local-match` | Prove expiry/cancel/race behavior against a real account on Windows. | P1 |
| ON-04 | Auth errors are safe and recoverable | `live-local` | `local-match` | Recheck current upstream copy/focus and redaction under live failure. | P1 |
| ON-05 | Restore encrypted credentials on relaunch | `live-local` | `partial` | Windows safeStorage/relaunch observation remains required. | P1 |
| ON-06 | List Plex Home profiles | `live-local` | `local-match` | Current-upstream and live Windows list/focus proof required. | P1 |
| ON-07 | Protected profile PIN entry and failure | `live-local` | `local-match` | Prove keypad/text input, failure recovery, and stale completion on Windows. | P1 |
| ON-08 | Switch Plex Home profile | `live-local` | `partial` | Runtime exists; upstream Settings exposes a persistent Switch Profile affordance that Desktop Settings lacks. | P1 |
| ON-09 | Discover and refresh Plex servers | `live-local` | `local-match` | Live LAN/remote/empty/error Windows matrix required. | P1 |
| ON-10 | Select server and persist/restore selection | `live-local` | `local-match` | Prove relaunch, unavailable saved server, and recovery on Windows. | P1 |
| ON-11 | Clear/forget selected server and rerun selection | `partial` | `partial` | Renderer can clear selected state, but no equivalent persisted Forget Server product operation was found. | P1 |
| ON-12 | First-run audio output setup | `missing` | `missing` | Replace Web Audio sink selection with a Windows/libmpv audio-device design; do not silently omit the journey. | P2 |
| ON-13 | First-run automatically proceeds into Channel Builder | `live-local` | `partial` | First-run navigation reaches the implemented builder; current paired visual, live-breadth, manual Windows, packaged ACL, and other WS1 closure proof remain open. | P0 |
| ON-14 | Initialization cancellation/currentness and stale-result containment | `live-local` | `not-a-visual-row` | Local tests exist; prove visible recovery under live network churn. | P2 |
| ON-15 | Distinct account and selected-server resource credentials | `partial` | `not-a-visual-row` | Desktop securely stores an account credential and a selected-server summary, but no separate refreshable resource-credential owner was found. | P1 |
| ON-16 | Endpoint-aware unauthorized versus access-denied recovery | `partial` | `partial` | Desktop classifies 401/403 and server health, but does not implement the current upstream endpoint/resource-credential recovery policy. | P1 |
| ON-17 | Stale selected-server credential recovery without losing account auth | `missing` | `missing` | Add a main-owned recovery path that preserves account custody and safely re-resolves the selected resource. | P1 |
| ON-18 | One-time resource-token refresh and failed-request retry | `missing` | `not-a-visual-row` | Add bounded refresh-and-retry with cancellation, currentness, redaction, and no retry loop. | P1 |

## 2. Plex library browsing and metadata

Evidence: upstream `src/modules/plex/library/**` and Channel Setup/EPG consumers;
Desktop `src/main/plex/library/**`, `src/main/plex/desktopPlexRuntime.ts`,
`src/renderer/plexRuntime*.ts`, `src/renderer/setup/**`, and focused tests.

| ID | Capability/state | Desktop status | Visual status | Gap / acceptance needed | Priority |
| --- | --- | --- | --- | --- | --- |
| LIB-01 | List eligible movie/show library sections | `live-local` | `local-match` | Live Windows proof with multiple/empty/inaccessible sections. | P1 |
| LIB-02 | Browse library items | `live-local` | `partial` | Prove pagination/large libraries and current-upstream presentation. | P1 |
| LIB-03 | Search library content | `live-local` | `partial` | Prove cancel/stale/error/empty behavior on live Windows data. | P1 |
| LIB-04 | Load item metadata/details | `live-local` | `partial` | Desktop summary is narrower than upstream metadata/artwork presentation. | P2 |
| LIB-05 | Parse media files, parts, streams, language, HDR, and tracks | `live-local` | `not-a-visual-row` | WS2's local implementation gate is complete; representative native media samples remain `WS2-POST-VALIDATION-01`. | P1 |
| LIB-06 | Collections, playlists, genres, people, studio, and tag-directory discovery for builder planning | `live-local` | `partial` | WS1 facet discovery/materialization is wired; live proof across multiple eligible libraries and the complete supported filter surface remains open. | P0 |
| LIB-07 | Request scoping, abort, and identity change containment | `live-local` | `not-a-visual-row` | Maintain local tests and prove visible recovery under live account/server switches. | P2 |

## 3. Bulk Channel Builder / Channel Setup

This section is intentionally granular. “Channel setup exists” is not an
acceptable proxy for these rows.

Evidence: upstream `src/core/channel-setup/**`,
`src/modules/ui/channel-setup/**`, and `docs/user-guide/channels.md`; Desktop
`src/domain/channelBuilder/**`, `src/main/plex/channelBuilderFacet*.ts`,
`src/main/channel/channelBuilder*.ts`, atomic channel mutation/persistence and
startup owners, `src/preload/channelSetupBridge.cts`,
`src/renderer/channelSetup/builderConfigState.ts`, renderer workflow/DOM/style
owners, and focused Channel Builder tests. Implementation state below records
landed code; it does not close the stable IDs or their still-open proof gates.

| ID | Upstream builder capability | Desktop status | Visual status | Gap / acceptance needed | Priority |
| --- | --- | --- | --- | --- | --- |
| CB-01 | Multi-library selection | `live-local` | `partial` | Implementation landed; current UI-17 paired visual plus multi-library live-data/focus proof remains open. | P1 |
| CB-02 | Select all, clear all, eligible/disabled states, selection limit | `live-local` | `partial` | Implementation landed; current UI-17 paired visual and manual boundary-state proof remains open. | P1 |
| CB-03 | Collections strategy | `live-local` | `partial` | Deterministic facet/planner/runtime/UI code landed; paired visual and broader live-facet proof remains open. | P0 |
| CB-04 | Playlists strategy | `live-local` | `partial` | Deterministic facet/planner/runtime/UI code landed; paired visual and broader live-facet proof remains open. | P0 |
| CB-05 | Genres strategy | `live-local` | `partial` | Deterministic facet/planner/runtime/UI code landed; complete live filter-surface proof remains open. | P0 |
| CB-06 | Directors strategy | `live-local` | `partial` | Director planning/materialization landed; paired visual and broader live eligibility/warning proof remains open. | P0 |
| CB-07 | Decades strategy | `live-local` | `partial` | Exact-year decade planning and UI landed; paired visual/live breadth proof remains open. | P0 |
| CB-08 | Recently Added strategy | `live-local` | `partial` | Deterministic planning/runtime/UI landed; paired visual/live breadth proof remains open. | P0 |
| CB-09 | Studios strategy | `live-local` | `partial` | Studio planning/materialization landed; paired visual/live eligibility proof remains open. | P0 |
| CB-10 | Actors strategy | `live-local` | `partial` | Actor planning/materialization landed; paired visual/live TV-parent breadth proof remains open. | P0 |
| CB-11 | Enable/disable each strategy | `live-local` | `partial` | Reachable configuration controls landed; paired visual manifests remain open. | P0 |
| CB-12 | Strategy priority ordering | `live-local` | `partial` | Deterministic priority/cap planning and controls landed; paired visual proof remains open. | P0 |
| CB-13 | Per-library versus mixed scope | `live-local` | `partial` | Supported scope planning landed; multi-library facet/filter live proof remains open. | P0 |
| CB-14 | Alternate lineup copies and deterministic seeds | `live-local` | `partial` | Deterministic replicas/seeds, persistence, review, and controls landed; closure proof remains open. | P0 |
| CB-15 | Sequential companion channels | `live-local` | `partial` | Companion planning/runtime/UI landed; live breadth and paired visual proof remains open. | P0 |
| CB-16 | Actor/studio combine policy | `live-local` | `partial` | Deterministic combine policy and controls landed; paired visual/live breadth proof remains open. | P1 |
| CB-17 | Maximum channels control, default 200, cap 500 | `live-local` | `partial` | Validated cap, planning, and reachable control landed; paired visual/manual proof remains open. | P0 |
| CB-18 | Minimum items per channel control, default 5 | `live-local` | `partial` | Eligibility threshold and reachable control landed; paired visual/manual proof remains open. | P0 |
| CB-19 | Expand Lineup quick action (500 / 1) | `live-local` | `partial` | Reachable quick action landed; paired visual/manual proof remains open. | P1 |
| CB-20 | Estimated channel counts and estimate details | `live-local` | `partial` | Deterministic estimates and review presentation landed; paired visual manifests remain open. | P0 |
| CB-21 | Planner warnings and capped warning presentation | `live-local` | `partial` | Safe warnings/skips/cap presentation landed; paired visual and slow/blocked manual proof remains open. | P0 |
| CB-22 | Append existing lineup | `live-local` | `partial` | Atomic append implementation landed; current exact-HEAD live evidence covers merge only, so live append proof remains open. | P1 |
| CB-23 | Replace lineup with explicit confirmation | `live-local` | `partial` | Atomic replace/confirmation implementation landed; current exact-HEAD live evidence covers merge only, so live replace/rollback proof remains open. | P1 |
| CB-24 | Multi-stage build progress | `live-local` | `partial` | Review/apply/materialize/persist/refresh progress landed; UI-22 paired manifests and slow/blocked manual states remain open. | P1 |
| CB-25 | Result summary, warnings, counts, and watch-built-channel action | `live-local` | `partial` | Safe result/warning/count presentation landed; UI-23 paired manifests remain open. | P1 |
| CB-26 | Rerun setup from Settings/Guide and restore prior config | `live-local` | `partial` | Recovery and persisted normalized builder configuration landed; UI-24 paired manifests remain open. | P0 |
| CB-27 | Persist setup completion/config and recover after relaunch | `live-local` | `partial` | Atomic aggregate persistence/startup landed and merge restart was observed; packaged ACL and remaining closure proof stay open. | P1 |
| CB-28 | Merge build mode | `live-local` | `partial` | Atomic merge landed; live pre-barrier cancel and post-barrier apply/restart were observed, without closing other modes or proof gates. | P0 |
| CB-29 | Base series ordering: shuffle/sequential/block plus block size | `live-local` | `partial` | Deterministic planning, validation, persistence, controls, and materialization landed; paired visual/live breadth proof remains open. | P0 |
| CB-30 | Variant type: none/sequential/block plus variant block size | `live-local` | `partial` | Deterministic variant planning, validation, persistence, controls, and materialization landed; closure proof remains open. | P0 |
| CB-31 | Pre-build review diff: created/removed/unchanged/blocked/slow | `live-local` | `partial` | Pre-build safe diff landed; UI-18/UI-19 and manual slow/blocked proof remain open. | P0 |
| CB-32 | Genuine in-flight build cancellation | `live-local` | `partial` | Atomic cancellation landed: live merge cancel passed before the barrier and post-barrier cancel was rejected `commit-started`; broader/manual proof remains open. | P0 |

WS1 implementation/review preserves commits `027e674` and `e9da53d`.
Focused main/preload contracts passed 42/42 and the visual-evidence contract
passed 94/94. Live evidence is deliberately narrower: it covers merge
pre-barrier cancellation and post-barrier apply/restart only. It does not prove
live append or replace, multiple-library facet/filter breadth, or the complete
supported filter surface. Current paired manifests for UI-17, UI-18, UI-19,
UI-21, UI-22, UI-23, and UI-24 remain open, as do manual scale/zoom,
contrast/reduced-motion, D-pad/gamepad, slow/blocked-state, and packaged ACL
proof. `WS1-PERF-01` remains open: workflow `30074270895`, job `89421508431`,
head `335a13acfcee3f5450c104ed3fc48e45e461264a` measured 2,690.61 ms against
the unchanged 2,000 ms cap.

## 4. Custom channel authoring (Desktop addition)

Evidence: Desktop `src/contracts/customChannels.ts`,
`src/domain/channel/customChannelDraft.ts`, `src/main/channel/customChannel*.ts`,
`src/renderer/customChannels/**`, and Custom Channels tests. Upstream has domain
authoring/import-export owners but no equivalent standalone product screen at
the audited baseline.

| ID | Capability | Desktop status | Visual status | Gap / acceptance needed | Priority |
| --- | --- | --- | --- | --- | --- |
| CC-01 | List saved custom channels | `desktop-addition` | `desktop-specific` | Keep separate from bulk-builder scoring. | P2 |
| CC-02 | Create blank channel with name/number/manual media | `desktop-addition` | `desktop-specific` | Windows live proof required. | P2 |
| CC-03 | Browse/search media and load metadata safely | `desktop-addition` | `desktop-specific` | Prove large lists, stale source, artwork, and live errors. | P2 |
| CC-04 | Duplicate a saved channel into a draft | `desktop-addition` | `desktop-specific` | Preserve expected-revision conflict behavior. | P2 |
| CC-05 | Directly edit an existing persisted channel | `missing` | `missing` | Add reviewed edit-draft API returning full content and `expectedRevision`. | P1 |
| CC-06 | Delete with confirmation | `desktop-addition` | `desktop-specific` | Windows persistence/guide refresh proof. | P2 |
| CC-07 | Hide/show and reorder channels | `desktop-addition` | `desktop-specific` | Windows persistence/guide refresh proof. | P2 |
| CC-08 | Choose playback mode, sort order, block size, watched policy, intro/credit behavior | `partial` | `missing` | Contracts/domain support fields, but the reachable editor exposes only name, number, hidden, filters, and manual media selection. | P1 |
| CC-09 | Library/show/collection/playlist source authoring | `partial` | `partial` | Contracts support source types; reachable UI primarily adds manual items from browse/search. | P1 |
| CC-10 | Import/export channel definitions | `missing` | `missing` | Upstream domain support exists; no Desktop product workflow found. | P2 |

## 5. Scheduler and Guide / EPG

Evidence: upstream `src/modules/scheduler/**`, `src/modules/ui/epg/**`, and
`docs/user-guide/epg.md`; Desktop `src/domain/scheduler/**`,
`src/main/channel/guideRuntime.ts`, `src/renderer/epg*.ts`,
`src/renderer/epg/**`, and focused tests.

| ID | Capability/state | Desktop status | Visual status | Gap / acceptance needed | Priority |
| --- | --- | --- | --- | --- | --- |
| EPG-01 | Schedule persisted channels and handle day rollover | `live-local` | `not-a-visual-row` | Windows long-running/day-boundary proof required. | P1 |
| EPG-02 | Channel rows sorted by channel number | `live-local` | `local-match` | Live large-lineup proof. | P1 |
| EPG-03 | Time grid, program spans, past/current/upcoming, and now line | `live-local` | `local-match` | Revalidate time-zone/DST/day-boundary and current upstream geometry. | P1 |
| EPG-04 | Focused program detail, art/metadata, and live indicator | `partial` | `local-match` | Desktop detail/art metadata is narrower; prove missing-image and long-copy states. | P2 |
| EPG-05 | Arrow navigation and OK tune current program | `live-local` | `local-match` | Package 6 Windows focus audit and live tune proof remain. | P1 |
| EPG-06 | Horizontal time movement and return focus to now | `partial` | `partial` | Window shifting exists; upstream Play-to-now behavior was not found in Desktop input mapping. | P1 |
| EPG-07 | Channel page up/down | `live-local` | `partial` | Prove exact paging/focus continuity on Windows. | P2 |
| EPG-08 | Library filter tabs with persisted selection | `missing` | `missing` | Upstream has a focused tab owner and persistence; Desktop guide has no equivalent control. | P1 |
| EPG-09 | Now Watching banner preference | `partial` | `local-match` | Banner renders, but upstream enable/disable preference is missing. | P1 |
| EPG-10 | Overlay and Classic/PIP guide layouts | `partial` | `partial` | Desktop presentation is fixed to `classic`; upstream layout choice is missing. | P1 |
| EPG-11 | Detailed 2h versus Wide 3h density | `partial` | `partial` | Desktop comfortable/compact row density is not the same capability. | P1 |
| EPG-12 | Past-items window policy | `missing` | `missing` | Add Auto/explicit policy and schedule-window consumption. | P2 |
| EPG-13 | Large-guide row/cell virtualization and aggressive preload option | `missing` | `missing` | Desktop renders a simpler bounded guide; upstream virtualization/preload owners are absent. | P1 |
| EPG-14 | Loading, empty channels, empty programs, retryable error | `live-local` | `local-match` | Local variants exist; prove live recovery on Windows. | P1 |
| EPG-15 | Automatic refresh/polling and currentness cancellation | `live-local` | `not-a-visual-row` | Local tests exist; soak with server/profile/channel changes. | P2 |

## 6. Player, tuning, overlays, and media options

Evidence: upstream `src/modules/player/**`, `src/modules/plex/stream/**`,
`src/core/channel-tuning/**`, `src/modules/ui/player-osd/**`, overlay families,
and remote routing; Desktop `src/main/player/**`, `src/main/plex/streamResolver*`,
`src/native-helper/Lineup.NativePlayerHost/**`, `src/renderer/playerOverlay*.ts`,
player contracts/tests, and Windows spike evidence.

| ID | Capability/state | Desktop status | Visual status | Gap / acceptance needed | Priority |
| --- | --- | --- | --- | --- | --- |
| PB-01 | Tune current Guide program into player | `live-local` | `local-match` | Local tune/runtime gate is complete; production Windows media observation remains `WS2-POST-VALIDATION-01`. | P0 |
| PB-02 | Channel up/down and mini-guide tune | `live-local` | `local-match` | Local transition/focus gate is complete; Windows native-video/focus observation remains `WS2-POST-VALIDATION-01`. | P1 |
| PB-03 | Numeric channel entry, timeout, invalid result, tune | `live-local` | `local-match` | Local numeric input/runtime gate is complete; Windows keyboard/numpad observation remains `WS2-POST-VALIDATION-01`. | P1 |
| PB-04 | Direct Play | `partial` | `not-a-visual-row` | The conservative MP4/H.264/AAC Direct Play profile is unchanged; broader proof or promotion remains `WS2-POST-VALIDATION-01`. | P0 |
| PB-05 | Direct Stream/remux | `partial` | `not-a-visual-row` | Remux and audio conversion remain unsupported; observation or promotion remains `WS2-POST-VALIDATION-01`. | P0 |
| PB-06 | Plex transcode session start/stop | `partial` | `not-a-visual-row` | PMS lifecycle exists, but transcode families remain unsupported; observation or promotion remains `WS2-POST-VALIDATION-01`. | P0 |
| PB-07 | Native libmpv helper discovery, spawn, load, render, cleanup | `partial` | `proof-only` | WS2 source/non-packaged-helper contribution is locally complete; native build/live proof remains `WS2-POST-VALIDATION-01`, while packaged helper/libmpv proof remains WS9/RD-28. | P0 |
| PB-08 | Windowed/fullscreen native video with renderer UI over it | `partial` | `local-match` | Local presentation gate is complete; Windows production video and the three-row audit remain `WS2-POST-VALIDATION-01`/RD-27 as applicable. | P0 |
| PB-09 | Play/pause | `partial` | `partial` | Space dispatch exists; upstream remote media play/pause key mapping is absent. The upstream OSD action strip does not add a separate play/pause button. | P1 |
| PB-10 | Seek/rewind/fast-forward | `partial` | `missing` | Main/helper contracts support relative/absolute seek, but renderer remote/media-key routing does not expose upstream behavior; upstream has no separate OSD seek action. | P1 |
| PB-11 | Stop playback | `partial` | `missing` | Main runtime supports stop/cleanup; renderer remote/media-key routing lacks upstream Stop behavior, not an OSD button. | P1 |
| PB-12 | Loading, buffering, seeking, stalled, ended, and error states | `live-local` | `local-match` | Local state/error gate is complete; real-media/network Windows states remain `WS2-POST-VALIDATION-01`. | P1 |
| PB-13 | Retry/recovery after media failure | `partial` | `local-match` | Bounded 1/2/4 recovery plus explicit Retry/Skip/Guide fallback is implemented and reviewed; live ERROR/EOF/recovery observation remains `WS2-POST-VALIDATION-01`, so status does not advance. | P1 |
| PB-14 | Helper crash detection, cleanup, and restart | `live-local` | `not-a-visual-row` | Local crash/cleanup/restart gate is complete; native media and soak remain `WS2-POST-VALIDATION-01`. | P1 |
| PB-15 | OSD program info, progress, timecode, buffer, ends-at | `live-local` | `local-match` | Current-upstream freshness and Windows native-video proof. | P1 |
| PB-16 | Now Playing information, progress, up-next | `live-local` | `local-match` | Metadata/art richness and Windows proof remain. | P2 |
| PB-17 | Mini Guide | `live-local` | `local-match` | Windows focus/paging/tune proof. | P1 |
| PB-18 | Channel badge and transition overlay | `live-local` | `local-match` | Windows timing/native-video proof. | P2 |
| PB-19 | Audio track list and selection | `partial` | `local-match` | UI/helper paths remain, but switching is unsupported; observation or promotion remains `WS2-POST-VALIDATION-01`. | P0 |
| PB-20 | Subtitle off/list/selection | `partial` | `local-match` | Delivery remains `none` and switching unsupported; observation or promotion remains `WS2-POST-VALIDATION-01`. | P0 |
| PB-21 | Subtitle direct/extract/burn-in fallback pipeline | `partial` | `partial` | Policy paths remain, but conversion/transcode are unsupported; representative native samples remain `WS2-POST-VALIDATION-01`. | P0 |
| PB-22 | Forced/default/preferred-language subtitle auto-selection | `partial` | `partial` | WS2's policy contribution remains; preferred-language Settings/control integration remains WS3, with native proof in `WS2-POST-VALIDATION-01`. | P1 |
| PB-23 | Audio fallback and DTS passthrough | `partial` | `missing` | WS2's fallback contribution remains; DTS/user controls remain WS3, with native proof in `WS2-POST-VALIDATION-01`. | P1 |
| PB-24 | HDR10/HLG/Dolby Vision detection and fallback | `partial` | `partial` | WS2's metadata/policy/helper contribution remains; HDR/Dolby Vision controls remain WS3, with native proof in `WS2-POST-VALIDATION-01`. | P0 |
| PB-25 | Sleep timer cycles, countdown, expiry, and stop | `missing` | `missing` | Implement or explicitly obtain product approval to diverge. | P1 |
| PB-26 | Keepalive and long-playback continuity | `proof-only` | `not-a-visual-row` | Real long-playback soak remains missing. | P1 |
| PB-27 | Sleep/wake recovery | `missing` | `not-a-visual-row` | Add Windows power lifecycle design and proof. | P1 |
| PB-28 | Multi-monitor, DPI, move-between-display, fullscreen restore | `partial` | `proof-only` | Window controller exists; production video/product soak remains. | P1 |

## 7. Settings, one control at a time

Evidence: upstream `src/modules/ui/settings/SettingsScreenStateController.ts`,
`src/modules/settings/**`, and `docs/user-guide/settings.md`; Desktop
`src/contracts/settings.ts`, `src/main/settings/**`,
`src/renderer/settings/**`, `src/renderer/settingsSetup*.ts`, and tests.

| ID | Upstream setting/capability | Desktop status | Visual status | Gap / acceptance needed | Priority |
| --- | --- | --- | --- | --- | --- |
| ST-01 | Two-pane category rail/detail navigation | `partial` | `local-match` | Desktop has three different categories, not upstream's five-category product surface. | P1 |
| ST-02 | DTS Passthrough | `missing` | `missing` | Add only with proven native audio path/capability. | P1 |
| ST-03 | Direct Play Audio Fallback | `missing` | `missing` | Connect to stream policy and persistence. | P1 |
| ST-04 | Subtitle Mode: Off/Direct/Standard/Full | `missing` | `missing` | Required to make PB-21 user-controllable. | P0 |
| ST-05 | Preferred Subtitle Language | `missing` | `missing` | Auth metadata exists, but no Desktop preference or selection consumer. | P1 |
| ST-06 | Prefer Forced Subtitles | `missing` | `missing` | Policy has forced behavior but no user preference. | P1 |
| ST-07 | Keep Playback Running in Settings | `missing` | `missing` | Define native-video/overlay behavior and persist it. | P2 |
| ST-08 | HDR Fallback: Off/Prefer HDR10/Force HLS | `missing` | `missing` | Required to expose PB-24 behavior safely. | P0 |
| ST-09 | Transcode Quality | `missing` | `missing` | Add resolver/transcode parameter consumption and persistence. | P1 |
| ST-10 | Transcode Compatibility Mode | `missing` | `missing` | Add only with live Plex proof and safe diagnostics. | P2 |
| ST-11 | Library Tabs | `missing` | `missing` | Required for EPG-08. | P1 |
| ST-12 | Now Watching Banner | `missing` | `missing` | Banner exists; preference is absent. | P1 |
| ST-13 | Aggressive Guide Preload | `missing` | `missing` | Requires EPG virtualization/preload design. | P2 |
| ST-14 | Guide Density: Detailed 2h/Wide 3h | `partial` | `local-match` | Desktop comfortable/compact controls row density, not the upstream time window. | P1 |
| ST-15 | Guide Layout: Overlay/Classic PIP | `missing` | `missing` | Required for EPG-10. | P1 |
| ST-16 | Past Items window | `missing` | `missing` | Required for EPG-12. | P2 |
| ST-17 | Info Box Background | `missing` | `missing` | Add with artwork-safe presentation design. | P2 |
| ST-18 | Theme selection | `missing` | `partial` | Desktop has fixed styling/theme hooks, not a persisted user choice. | P2 |
| ST-19 | Cinematic Now Playing | `missing` | `missing` | Add only with safe artwork and current player metadata. | P2 |
| ST-20 | Use Clear Logos | `missing` | `missing` | Requires safe logo artwork projection. | P2 |
| ST-21 | Now Playing Auto-Hide / Persistent | `missing` | `missing` | Desktop timers are fixed rather than user-configurable. | P2 |
| ST-22 | Show Profile Picker on Startup | `missing` | `missing` | Profile switching exists, but preference/startup consumption is absent. | P1 |
| ST-23 | Switch Profile action below category rail | `missing` | `missing` | Route to existing safe profile flow. | P1 |
| ST-24 | Debug Logging | `missing` | `missing` | Desktop diagnostics exist, but not this user preference. | P2 |
| ST-25 | Subtitle Debug Logging | `missing` | `missing` | Add only with redacted logs and track diagnostics. | P2 |
| ST-26 | Desktop launch mode: windowed/fullscreen | `desktop-addition` | `desktop-specific` | Persisted and consumed; Windows proof remains. | P2 |
| ST-27 | Preview badges | `desktop-addition` | `desktop-specific` | Verify every claimed consumer; do not count as upstream Appearance parity. | P3 |
| ST-28 | Setup reminder and recovery summary | `desktop-addition` | `desktop-specific` | Useful Desktop recovery affordance. | P2 |
| ST-29 | Support bundle export | `desktop-addition` | `desktop-specific` | Windows UI/export/redaction proof remains. | P1 |
| ST-30 | Persistence failure, revision conflict, corrupt/unsupported recovery | `live-local` | `partial` | Local tests/relaunch proof exist; Windows product observation remains. | P1 |

## 8. Navigation, focus, lifecycle, accessibility, and packaging

Evidence: upstream `src/modules/navigation/**`, `src/modules/lifecycle/**`,
`src/platform/webosPlatformServices.ts`, and `docs/user-guide/remote-keys.md`;
Desktop `src/renderer/desktopInput.ts`, `src/renderer/navigation.ts`,
`src/renderer/focusDom.ts`, `src/main/window/**`, shell tests, proof bundle, and
packaging tools.

| ID | Capability/state | Desktop status | Visual status | Gap / acceptance needed | Priority |
| --- | --- | --- | --- | --- | --- |
| NAV-01 | D-pad/arrows and OK/Enter | `live-local` | `local-match` | Windows keyboard/gamepad focus proof remains. | P1 |
| NAV-02 | Back/Escape closes topmost owner and long-back returns Player | `partial` | `local-match` | Topmost close exists; upstream long-press Back semantics are not proven. | P1 |
| NAV-03 | Guide shortcut (`G`, remote Guide/Green fallback) | `partial` | `partial` | `G`/Guide exists; upstream F2/Green mapping is absent. | P2 |
| NAV-04 | Settings shortcut (Yellow/F3) | `partial` | `partial` | Desktop maps `S`/`,`; upstream F3/Yellow parity is absent. | P2 |
| NAV-05 | Now Playing shortcut (Red/F1) | `missing` | `missing` | Desktop has Info behavior, but no upstream F1/Red mapping. | P2 |
| NAV-06 | Info/Blue opens server selection or sign-in recovery | `partial` | `partial` | `I` exists; F4/Blue mapping is absent and Desktop overlay policy diverges. | P2 |
| NAV-07 | CH+/CH- and PageUp/PageDown context routing | `live-local` | `partial` | Prove player/mini-guide/EPG context behavior on Windows. | P1 |
| NAV-08 | Media play/pause, rewind, fast-forward, stop keys | `missing` | `missing` | Add renderer/main mapping to existing player intents with eligibility/focus rules. | P1 |
| NAV-09 | Gamepad D-pad/OK/Back/Settings/Guide/fullscreen | `live-local` | `not-a-visual-row` | Windows device proof and repeat behavior remain. | P2 |
| NAV-10 | Pointer/mouse click equivalence and cursor auto-hide | `live-local` | `local-match` | Windows native-video overlay proof remains. | P2 |
| NAV-11 | Editable-control shortcut bypass | `live-local` | `not-a-visual-row` | Maintain focused tests as settings/builder controls expand. | P1 |
| NAV-12 | Focus restore, modal trapping, hidden-owner inertness | `live-local` | `local-match` | Mandatory Package 6 Windows audit remains. | P0 |
| NAV-13 | Reduced motion | `live-local` | `local-match` | Eight local rows; revalidate new/current-upstream surfaces. | P2 |
| NAV-14 | Forced colors / high contrast | `live-local` | `local-match` | Twelve local rows; Windows high-contrast product proof remains. | P2 |
| NAV-15 | 1280x720 and 1920x1080 responsive layout | `proof-only` | `local-match` | 69 captures at each viewport; current-upstream freshness and real window-resize states remain. | P1 |
| NAV-16 | Exit confirmation and window close | `live-local` | `local-match` | Packaged Windows behavior proof. | P2 |
| PKG-01 | Internal unpacked Windows x64 package | `proof-only` | `not-a-visual-row` | Tooling proof exists; helper/media binaries are deliberately blocked from artifact. | P1 |
| PKG-02 | Native helper and libmpv included with provenance/licenses | `missing` | `not-a-visual-row` | Required for a usable packaged native player. | P0 |
| PKG-03 | Installer, install/uninstall/delete, signing, updates | `missing` | `not-a-visual-row` | RD-28 must not be treated as mere proof if implementation is absent. | P1 |

## 9. Lifecycle and operational resilience

Evidence: upstream `src/modules/lifecycle/AppLifecycle.ts`, lifecycle monitors,
and `src/core/orchestrator/priority-one/PlaybackRuntimeController.ts`; Desktop
main/renderer lifecycle searches, scheduler interfaces, persistence owners, and
window/player runtime composition.

| ID | Capability/state | Desktop status | Visual status | Gap / acceptance needed | Priority |
| --- | --- | --- | --- | --- | --- |
| LC-01 | Background/visibility transition pauses or safely contains playback | `missing` | `not-a-visual-row` | Define Electron window/app visibility semantics separately from user pause and prove native-helper behavior. | P1 |
| LC-02 | Flush pending persisted state before background/final shutdown | `partial` | `not-a-visual-row` | Channel persistence can flush, but no app-lifecycle coordinator guarantees the upstream transition/shutdown contract. | P1 |
| LC-03 | Foreground resume and scheduler/playback resynchronization | `partial` | `not-a-visual-row` | Scheduler has a resume timer seam, but no complete app lifecycle owner and recovery proof were found. | P1 |
| LC-04 | Connectivity transition monitoring and recovery | `missing` | `not-a-visual-row` | Add main-owned online/offline transition policy, visible recovery, cancellation, and live proof. | P1 |
| LC-05 | Memory-pressure cleanup and bounded cache/player recovery | `missing` | `not-a-visual-row` | Add an Electron/Windows-appropriate policy; do not copy browser/WebOS lifecycle APIs literally. | P2 |

## 10. UI/look parity surface register

The existing proof bundle has 54 canonical surface rows: 8 shell, 8
onboarding, 14 setup, 7 settings, 6 guide, 3 player, and 8 player-overlay rows.
It produced 138 final screenshots (69 each at 1280x720 and 1920x1080), 8
reduced-motion rows, 12 forced-colors rows, and 3 local-fullscreen rows.

| Family | Locally adapted surfaces | Known missing/divergent surfaces | Current disposition |
| --- | --- | --- | --- |
| Shell | splash, loading, blocking/inline error, toast, exit confirmation | separate Home route intentionally omitted; blank-fullscreen is a forbidden symptom | `partial`: strong local proof, stale upstream reference, Windows pending |
| Onboarding | auth link/wait/error, profile select/PIN, server select/error | audio setup missing | `partial` |
| Setup | library, pre-build review, build configuration, replace confirmation, progress, result, recovery | account/server are remapped stages; custom list/edit/delete are Desktop additions; WS1 builder views landed but current paired manifests UI-17/18/19/21/22/23/24 remain open | `partial`; existing captures do not prove full Channel Builder parity |
| Settings | Desktop Appearance and Guide rows | upstream Audio/Subtitles, Playback/HDR, Account, and Developer controls are missing; Desktop Recovery is additive | `partial`; screenshots of category shells must not imply control parity |
| Guide | ready, empty channels/programs, focused detail | loading/error are additive honest states; library tabs and alternate layouts are not captured because they are missing | `partial` |
| Player | idle, loading, error | production video behavior is not proven by renderer capture | `partial` |
| Overlays | OSD, now playing, mini guide, options, badge, number, transition | sleep timer missing | `partial`; Package 6 Windows audit pending |

### One-by-one canonical visual states

Each row below adopts the stable state ID from `states.mjs`; `UI-01` through
`UI-54` are stable master-ledger IDs. `reference:<state>` means the upstream
reference in `reference-manifest.json`; `capture:<state>` means the integrated
Desktop capture in `capture-manifest.json`/Package 8. The feature links prevent
a matching shell screenshot from closing missing controls or runtime behavior.

| ID | State ID / surface | Functional status | Visual status | Upstream / Desktop evidence | Linked feature IDs |
| --- | --- | --- | --- | --- | --- |
| UI-01 | `shell-splash` / Splash | `live-local` | `local-match` | `reference:shell-splash` / `capture:shell-splash` | ON-01 |
| UI-02 | `shell-loading` / Blocking loading | `live-local` | `local-match` | `reference:shell-loading` / `capture:shell-loading` | ON-01, PB-12 |
| UI-03 | `shell-error-blocking` / Blocking error | `live-local` | `local-match` | `reference:shell-error-blocking` / `capture:shell-error-blocking` | ON-04, PB-12 |
| UI-04 | `shell-error-inline` / Inline error | `live-local` | `local-match` | `reference:shell-error-inline` / `capture:shell-error-inline` | ON-04, EPG-14 |
| UI-05 | `shell-toast` / Toast | `live-local` | `local-match` | `reference:shell-toast` / `capture:shell-toast` | NAV-12 |
| UI-06 | `shell-blank-fullscreen` / Forbidden blank symptom | `intentional-divergence` | `local-match` | `reference:shell-blank-fullscreen` / `capture:shell-blank-fullscreen` | PB-08, NAV-12 |
| UI-07 | `auth-link-code` / Plex link code | `live-local` | `local-match` | `reference:auth-link-code` / `capture:auth-link-code` | ON-02 |
| UI-08 | `auth-waiting` / Authorization waiting | `live-local` | `local-match` | `reference:auth-waiting` / `capture:auth-waiting` | ON-03 |
| UI-09 | `auth-error` / Authorization error | `live-local` | `local-match` | `reference:auth-error` / `capture:auth-error` | ON-04 |
| UI-10 | `profile-select` / Profile selection | `live-local` | `local-match` | `reference:profile-select` / `capture:profile-select` | ON-06, ON-08 |
| UI-11 | `profile-pin` / Profile PIN modal | `live-local` | `local-match` | `reference:profile-pin` / `capture:profile-pin` | ON-07 |
| UI-12 | `server-select` / Server selection | `live-local` | `local-match` | `reference:server-select` / `capture:server-select` | ON-09, ON-10 |
| UI-13 | `server-error` / Server error | `partial` | `local-match` | `reference:server-error` / `capture:server-error` | ON-11, ON-16–ON-18 |
| UI-14 | `audio-setup` / Audio setup | `missing` | `missing` | `reference:audio-setup` / `capture:audio-setup` (omission target) | ON-12, WIN-02 |
| UI-15 | `setup-account` / Desktop account stage | `desktop-addition` | `desktop-specific` | `reference:setup-account` / `capture:setup-account` | ON-02–ON-08 |
| UI-16 | `setup-server` / Desktop server stage | `desktop-addition` | `desktop-specific` | `reference:setup-server` / `capture:setup-server` | ON-09–ON-11 |
| UI-17 | `setup-library` / Library selection | `live-local` | `partial` | WS1 UI landed; current paired visual manifest remains open. | LIB-01, CB-01–CB-02 |
| UI-18 | `setup-preview` / Pre-build review | `live-local` | `partial` | WS1 review UI landed; current paired visual manifest remains open. | LIB-02–LIB-04, CB-20, CB-31 |
| UI-19 | `setup-build` / Build configuration | `live-local` | `partial` | WS1 configuration UI landed; current paired visual manifest remains open. | CB-03–CB-21, CB-28–CB-30 |
| UI-20 | `setup-custom` / Custom channel stage | `desktop-addition` | `desktop-specific` | `reference:setup-custom` / `capture:setup-custom` | CC-01–CC-10 |
| UI-21 | `setup-confirm-replace` / Replace confirmation | `live-local` | `partial` | WS1 confirmation UI landed; current paired visual manifest remains open. | CB-23 |
| UI-22 | `setup-progress` / Build progress | `live-local` | `partial` | WS1 progress/cancel UI landed; current paired visual manifest and slow/blocked manual states remain open. | CB-24, CB-32 |
| UI-23 | `setup-result` / Build result | `live-local` | `partial` | WS1 result UI landed; current paired visual manifest remains open. | CB-25 |
| UI-24 | `setup-recovery-error` / Setup recovery error | `live-local` | `partial` | WS1 recovery UI landed; current paired visual manifest remains open. | CB-26–CB-27 |
| UI-25 | `custom-list` / Custom channel list | `desktop-addition` | `desktop-specific` | `reference:custom-list` / `capture:custom-list` | CC-01, CC-04, CC-06–CC-07 |
| UI-26 | `custom-edit` / Custom channel editor | `partial` | `desktop-specific` | `reference:custom-edit` / `capture:custom-edit` | CC-02–CC-03, CC-08–CC-09 |
| UI-27 | `custom-delete-confirm` / Delete confirmation | `desktop-addition` | `desktop-specific` | `reference:custom-delete-confirm` / `capture:custom-delete-confirm` | CC-06 |
| UI-28 | `settings-audio-subtitles` / Audio & subtitles | `missing` | `missing` | `reference:settings-audio-subtitles` / `capture:settings-audio-subtitles` (omission target) | ST-02–ST-06 |
| UI-29 | `settings-playback-hdr` / Playback & HDR | `missing` | `missing` | `reference:settings-playback-hdr` / `capture:settings-playback-hdr` (omission target) | ST-07–ST-10 |
| UI-30 | `settings-appearance` / Appearance | `partial` | `local-match` | `reference:settings-appearance` / `capture:settings-appearance` | ST-17–ST-21, ST-26–ST-27 |
| UI-31 | `settings-account` / Account | `missing` | `missing` | `reference:settings-account` / `capture:settings-account` (omission target) | ST-22–ST-23 |
| UI-32 | `settings-developer` / Developer | `partial` | `desktop-specific` | `reference:settings-developer` / `capture:settings-developer` | ST-24–ST-25, ST-29 |
| UI-33 | `settings-guide` / Guide | `partial` | `local-match` | `reference:settings-guide` / `capture:settings-guide` | ST-11–ST-16 |
| UI-34 | `settings-recovery` / Recovery | `desktop-addition` | `desktop-specific` | `reference:settings-recovery` / `capture:settings-recovery` | ST-28, ST-30 |
| UI-35 | `guide-loading` / Guide loading | `desktop-addition` | `desktop-specific` | `reference:guide-loading` / `capture:guide-loading` | EPG-14 |
| UI-36 | `guide-ready` / Guide schedule | `partial` | `local-match` | `reference:guide-ready` / `capture:guide-ready` | EPG-01–EPG-13 |
| UI-37 | `guide-empty-channels` / No channels | `live-local` | `local-match` | `reference:guide-empty-channels` / `capture:guide-empty-channels` | EPG-14 |
| UI-38 | `guide-empty-programs` / No programs | `live-local` | `local-match` | `reference:guide-empty-programs` / `capture:guide-empty-programs` | EPG-14 |
| UI-39 | `guide-error` / Guide error | `desktop-addition` | `desktop-specific` | `reference:guide-error` / `capture:guide-error` | EPG-14 |
| UI-40 | `guide-focused-detail` / Focused detail | `partial` | `local-match` | `reference:guide-focused-detail` / `capture:guide-focused-detail` | EPG-04–EPG-05 |
| UI-41 | `player-idle` / Player idle | `live-local` | `local-match` | Local idle/runtime gate complete; Windows native observation remains `WS2-POST-VALIDATION-01`. | PB-01–PB-03 |
| UI-42 | `player-loading` / Loading transition | `live-local` | `local-match` | Local loading-transition gate complete; Windows observation remains `WS2-POST-VALIDATION-01`. | PB-12 |
| UI-43 | `player-error` / Player error | `partial` | `local-match` | Reviewed Retry/Skip error actions landed; Windows live recovery remains `WS2-POST-VALIDATION-01`. | PB-12–PB-13 |
| UI-44 | `overlay-osd` / Player OSD | `partial` | `local-match` | `reference:overlay-osd` / `capture:overlay-osd` | PB-09–PB-15 |
| UI-45 | `overlay-now-playing` / Now Playing | `live-local` | `local-match` | `reference:overlay-now-playing` / `capture:overlay-now-playing` | PB-16 |
| UI-46 | `overlay-mini-guide` / Mini Guide | `live-local` | `local-match` | `reference:overlay-mini-guide` / `capture:overlay-mini-guide` | PB-02, PB-17 |
| UI-47 | `overlay-options` / Playback options | `partial` | `local-match` | `reference:overlay-options` / `capture:overlay-options` | PB-19–PB-24 |
| UI-48 | `overlay-badge` / Channel badge | `live-local` | `local-match` | `reference:overlay-badge` / `capture:overlay-badge` | PB-18 |
| UI-49 | `overlay-number` / Number entry | `live-local` | `local-match` | `reference:overlay-number` / `capture:overlay-number` | PB-03 |
| UI-50 | `overlay-transition` / Channel transition | `live-local` | `local-match` | `reference:overlay-transition` / `capture:overlay-transition` | PB-18 |
| UI-51 | `overlay-sleep-timer` / Sleep timer | `missing` | `missing` | `reference:overlay-sleep-timer` / `capture:overlay-sleep-timer` (omission target) | PB-25 |
| UI-52 | `exit-confirm` / Exit confirmation | `live-local` | `local-match` | `reference:exit-confirm` / `capture:exit-confirm` | NAV-16, LC-02 |
| UI-53 | `home` / Separate Home route | `intentional-divergence` | `desktop-specific` | `reference:home` / `capture:home` (Player mapping) | PB-01 |
| UI-54 | `channel-edit` / Persisted channel edit | `missing` | `missing` | `reference:channel-edit` / `capture:channel-edit` (additive target) | CC-05, CC-08–CC-09 |

### Visual acceptance rules

1. Refresh the upstream source/capture baseline from commit
   `0258dbe15b04d2d141d0a4a44575fecb5bb72d41` before another broad visual
   parity closeout.
2. Add states for every newly implemented builder strategy section, settings
   category/control family, library tabs, guide layout, media-key feedback, and
   sleep timer. A surface omitted from the catalog is not visually complete.
3. Keep exact 1280x720 and 1920x1080 captures, but also prove ordinary
   resizable-window widths and Windows display scaling because Desktop is not a
   fixed 1080p TV surface.
4. Run the three-row OSD, mini-guide, and playback-options operator-assisted
   fullscreen focus audit afresh on Windows over production native video.
5. Visual comparison must inspect typography, colors, spacing, artwork,
   clipping, focus, motion, empty/loading/error states, and pointer/keyboard/
   gamepad interaction—not screenshot presence alone.

## 11. Windows-native gains to preserve or add

These rows do not lower upstream parity requirements. They are additive Desktop
product opportunities.

| ID | Native gain | Current state | Required next proof/design |
| --- | --- | --- | --- |
| WIN-01 | libmpv codec/container breadth and hardware decoding | `partial` | Conservative profile unchanged; capability observation or promotion remains `WS2-POST-VALIDATION-01`. |
| WIN-02 | Native audio-device selection | `missing` | Use a main/helper-owned device list and replace upstream Web Audio setup with a Windows-appropriate first-run/settings flow. |
| WIN-03 | Windows media keys / System Media Transport Controls | `missing` | Route play/pause/seek/stop without global-secret or focus-boundary leakage. |
| WIN-04 | Power request while playing plus sleep/resume recovery | `missing` | Add explicit main-owned lifecycle, cleanup, diagnostics, and soak proof. |
| WIN-05 | Multi-monitor/DPI/fullscreen restore | `partial` | Existing window controller needs production native-video observation across displays/scales. |
| WIN-06 | Hardware/HDR capability diagnostics and safe fallback | `partial` | No privileged diagnostic expansion occurred; hardware/display/HDR facts remain `WS2-POST-VALIDATION-01` or require a future reviewed replan. |
| WIN-07 | Crash-isolated native playback helper and support bundle | `live-local` | WS2's crash-isolation contribution is locally complete; native observation remains `WS2-POST-VALIDATION-01`, while packaged replacement-helper proof remains WS9/RD-28. |
| WIN-08 | Windowed/fullscreen launch choice | `live-local` | Preserve as a Desktop addition and verify packaged relaunch behavior. |
| WIN-09 | Keyboard, mouse, numpad, and gamepad alongside TV-style focus | `partial` | Complete media keys and validate mixed-input focus/cursor transitions. |

## 12. Execution order

1. **WS1 — Channel Builder:** implementation and independent review landed,
   but stable-ID closure does not advance. Deferred visual/live/manual/package
   proof and `WS1-PERF-01` keep WS1 open.
2. **WS2 — Production playback capability:** the platform-neutral
   implementation gate is closed at published `d2f1e97`; Package 2D made no
   capability edit, and `WS2-POST-VALIDATION-01` carries nonblocking
   Windows/native proof without promoting support.
3. **WS3 through WS9:** not started or authorized by WS2 closeout. WS3 is only
   the next unopened freshness-planning target. Their Settings, input/overlay, Guide,
   fresh UI, credential/lifecycle, package/soak, and remaining ordered scopes
   retain their current conservative rows until separately entered.
4. **RD-27/RD-28:** remain later. RD-27 waits for WS1–WS8 plus WS9 prerequisite
   hardening and a refreshed Windows proof plan; RD-28 follows RD-27
   observation. Windows observation cannot implement or waive missing product
   behavior.

## 13. Maintenance gate

Every upstream or Desktop product change must update this matrix in the same
reviewed pass when it changes capability, UI, evidence, or divergence. A row may
advance only when its exact acceptance need has observed evidence. New upstream
features get new stable IDs; they may not be absorbed into a broad existing
row. Any copied/adapted source still requires an import-ledger entry.

Before parity-related closeout:

- compare current upstream and Desktop HEADs with the pins above;
- search upstream user guide, UI modules, settings stores, navigation routing,
  channel setup, scheduler, player, and lifecycle changes;
- update affected feature rows and UI surface catalog;
- run `npm run verify:docs`, `npm run verify:redaction`, and `git diff --check`;
- use fresh adversarial review to look specifically for omitted controls,
  states, and umbrella claims.

## Evidence index

- Current upstream product docs: `../Lineup/README.md`,
  `../Lineup/docs/user-guide/**`, `../Lineup/docs/getting-started/**`.
- Current upstream source: `../Lineup/src/core/**`,
  `../Lineup/src/modules/**`, `../Lineup/src/platform/**`.
- Desktop current architecture: `docs/architecture/CURRENT_STATE.md`.
- Historical compatibility/divergence:
  `docs/architecture/original-lineup-reference-compatibility-matrix.md` and
  `docs/architecture/original-lineup-divergence-register.md`.
- Visual evidence: `docs/runs/complete-webos-ui-parity-reopen/**`, especially
  `states.mjs`, `surface-disposition-matrix.json`,
  `focus-interaction-matrix.json`, and `package-8-integrated-manifest.json`.
- Windows proof protocol: `docs/development/windows-ui-proof-plan.md`.
- Ordered implementation history: `docs/roadmap/desktop-port-roadmap.md`.
- Copied/adapted source provenance: `docs/architecture/import-ledger.md`.
