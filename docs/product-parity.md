# Definitive product-parity and release audit

**Audit date:** 2026-08-23

**Audit-start Desktop commit:** `acb49e492fa8a1e2deba0726d4027cb313c54067`
on `flutter-mvp`

**Authoritative upstream:** `TJZine/Lineup` `origin/code-health` at
`b30e27c0025d254b7c3c8fb7a9335070542362bd`

**Historical Electron reference:**
`bfaee636748f2a0d442f3690b7ba5262d32ff17c`

**Host evidence:** macOS 26.6.1 arm64, Flutter 3.47.0 revision `4cf2416426`,
Dart 3.13.0

This is the authoritative current product-parity record. The classifications
in [Portable UI Parity](ui-parity.md) remain historical evidence for their
named campaigns; they do not override this audit. Current source and observed
evidence outrank older documentation.

## Executive conclusion

- **Replatform:** **PROVISIONAL**. The Flutter product spine, responsive Guide,
  native boundary, and most daily-use workflows are implemented and strongly
  tested, but a core Plex Media Server credential is discarded and Windows
  playback/package behavior has not been physically accepted at this commit.
- **Core daily-use Lineup parity:** source-level workflow coverage is broad, but
  actual daily-use parity is not established until PMS authorization and
  physical Windows playback are proven. Generated-channel editing, large-library
  planning, media-version choice, and some persistence/error paths are partial.
- **Private beta:** **READY AFTER NAMED P0 ITEMS**. A tightly controlled evidence
  cohort may begin after the per-server PMS token fix. A supported private beta
  additionally requires an exact patched package and physical Windows
  startup/auth/playback/overlay/fullscreen smoke at that commit.
- **First public Windows release:** **NOT READY**. Physical acceptance, package
  engine attestation, package CI coverage, native notice/legal review,
  project-controlled runtime mirroring, signing/trust, and a release channel
  remain open.
- **Dominant next mode:** parity closure followed by Windows media/package
  acceptance and release hardening.

## Method, scope, and evidence calibration

The audit independently inventoried current upstream and current Desktop before
reconciling them in both directions. It covered all tracked product source,
tests and configuration by census, with deep reads of every workflow owner,
all 23 visible upstream settings and all Desktop settings, Guide/player/native
owners, CI/package scripts, and the bounded historical Electron product seams.
The Desktop repository contained 161 tracked files; all 29 production Dart
files and all test paths were included in the census. The upstream ref contained
1,171 tracked files and approximately 362 tests; every major product domain was
deep-read, while repetitive unit files, archived plans, and assets were covered
by tree and symbol scans.

Evidence is stated at its actual level:

- **Implemented** means current source owns the behavior.
- **Deterministically tested** means a test exercises the relevant contract.
- **CI-compiled** is not physical platform acceptance.
- **Platform validated** requires durable evidence from the named machine and
  exact commit.
- **Supported** additionally requires package, recovery, documentation, and
  release ownership.

The classification vocabulary is fixed: **PARITY**, **DESKTOP-ENHANCED**,
**INTENTIONAL DESKTOP ADAPTATION**, **PARTIAL**, **MISSING**,
**INTENTIONALLY OMITTED**, **NOT APPLICABLE**, **NEEDS EVIDENCE**, and
**BLOCKED BY DECISION**. Priorities appear only on **PARTIAL**, **MISSING**,
**NEEDS EVIDENCE**, and **BLOCKED BY DECISION** rows. Medium/Low confidence
rows name the proof needed in the evidence-gap register.

P0 is phase-scoped: it marks a blocker to the beta or public-release phase named
by the row/register, not an assertion that every P0 blocks a controlled evidence
cohort. P1 is required for the first public Windows release. Matrix counts are
capability rows, not counts of independent root blockers; several native P0 rows
collapse into one exact-package physical acceptance campaign.

## Product matrix

### Startup, account, profiles, server, and first run

| Capability | Upstream behavior/reference | Current Desktop behavior | Classification | Priority | Confidence | Evidence | Owner / next action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Branded startup progress | Structured initialization and recoverable routing | Flutter initializes player/controller behind one semantic progress surface | PARITY | — | HIGH | `lib/app/lineup_app.dart`; `test/app/lineup_app_test.dart` | Flutter app |
| Fatal startup surface | Blocking sanitized startup error | Later player/controller failures render safe guidance | PARITY | — | HIGH | `lib/app/lineup_app.dart`; `test/app/lineup_app_test.dart` | Flutter app |
| Pre-widget composition failure | Bootstrap failures are routed through initialized UI owners | Store/client-identity failures occur before `runApp`, so no window can explain recovery | PARTIAL | P2 | HIGH | `lib/main.dart`; `lib/persistence/app_store.dart` | Flutter app: add a minimal composition-failure surface |
| Plex PIN request and QR | Request, QR/code, expiry, cancel, retry | Equivalent fixed-link QR/code flow with countdown and cancellation | PARITY | — | HIGH | Upstream `AuthScreen.ts`; `lib/app/onboarding_view.dart`; `test/app/lineup_app_test.dart` | Auth |
| PIN polling failure recovery | Retries transient failures and surfaces terminal/retry state | Poll/account/Home errors are diagnostics-only until PIN expiry | PARTIAL | P2 | HIGH | Upstream `AuthScreen.ts`; `lib/app/lineup_controller.dart`; `test/app/lineup_controller_test.dart` | Auth: distinguish transient from terminal failure |
| Replacement PIN cancellation | Replaced operations are cancelled and stale work rejected | New-code action invalidates local epoch but does not cancel the old server PIN | PARTIAL | P3 | HIGH | `lib/app/onboarding_view.dart`; `lib/app/lineup_controller.dart` | Auth: best-effort cancel superseded PIN |
| Account validation | Token validated before durable authenticated state | Token validated against Plex account before secure persistence | PARITY | — | HIGH | `lib/plex/plex_client.dart`; `lib/app/lineup_controller.dart` | Auth |
| Plex Home profile inventory | Avatars/fallbacks, Admin/Restricted/PIN/Active facts | Responsive cards provide avatar/fallback, PIN, sign-out, busy/cancel, but omit role/active context | PARTIAL | P3 | HIGH | Upstream `ProfileSelectScreen.ts`; `lib/app/onboarding_view.dart`; profile golden | Profiles: decide whether the simplified facts are intentional |
| Protected-profile PIN | Focused PIN modal, wrong-PIN recovery | Four digits, numpad, Backspace, pointer keypad, semantic progress, auto-submit | DESKTOP-ENHANCED | — | HIGH | `lib/app/onboarding_view.dart`; `test/app/lineup_app_test.dart`; screenshot `00-15-25` | Profiles |
| Profile authorization error taxonomy | Distinguishes wrong PIN from expired/invalid account credential | Every switch 401/403 is reported as incorrect PIN | PARTIAL | P2 | HIGH | Upstream `plexHomeProfileClient.ts`; `lib/plex/plex_client.dart` | Plex auth: revalidate account on ambiguous failure |
| Profile-scoped credential/state | Account and Home profile credentials remain distinct | Secure account/profile tokens and profile/server-scoped lineups | PARITY | — | HIGH | `lib/persistence/app_store.dart`; `lib/app/lineup_controller.dart`; controller tests | Profiles/persistence |
| Logout and credential cleanup | Rejects stale work and exposes cleanup failure before returning to linking | Equivalent behavior adapted to OS secure storage, with coalesced logout and retryable cleanup failure | PARITY | — | HIGH | Upstream auth/orchestrator; `lib/app/lineup_controller.dart`; focused logout/cancellation tests | Auth/credentials |
| Failed/cancelled profile-token compensation | Cancellation-safe profile-switch ownership | A newly written profile token is not deleted/restored if cancellation lands during write or state save fails | PARTIAL | P2 | HIGH | `lib/app/lineup_controller.dart`; `lib/persistence/app_store.dart` | Credentials: delete/restore scoped residue |
| Server discovery and selection | Resource inventory, health, saved-server restore, retries | Owned/shared cards, tiered bounded probes, latency, retry/switch/clear, transactional selection | PARITY | — | HIGH | Upstream `PlexServerDiscovery.ts`; `lib/plex/plex_client.dart`; transport tests | Server selection |
| Per-server PMS credential | `/resources` supplies a distinct private `accessToken` for each PMS and all PMS requests use it | Parser discards `accessToken`; probes, libraries, artwork, playback, and release use the Plex.tv/Home token | MISSING | P0 | HIGH | [Plex PMS auth](https://developer.plex.tv/pms/); upstream discovery/types and managed-profile test; `lib/plex/plex_models.dart`; `lib/plex/plex_client.dart` | Plex transport: retain privately, refresh once, route to every PMS consumer |
| Local HTTP server reachability | Allows local HTTP only where platform policy permits it; otherwise prefers HTTPS/relay | A secure-only policy rejects every non-HTTPS resource connection, including HTTP-only LAN servers | BLOCKED BY DECISION | P2 | HIGH | Upstream mixed-content/discovery policy; `lib/plex/plex_client.dart` | Decide whether local-HTTP compatibility belongs in supported scope |
| Connection facts and warnings | Auth/access/unreachable, relay/local HTTP, slow/very slow | Direct local/remote/relay and measured latency are shown; rich health/warning taxonomy is narrower | PARTIAL | P2 | HIGH | Upstream `ServerSelectListView.ts`; `lib/app/onboarding_view.dart` | Server UI |
| Audio onboarding | Receiver/TV choice, DTS intent, direct-play fallback | Truthfully confirms OS-selected audio and hides controls with no native consumer | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | Upstream `AudioSetupScreen.ts`; `lib/app/onboarding_view.dart`; `docs/user-guide.md` | Keep omitted until native facts and commands exist |

### Channel Setup, authoring, persistence, and scheduling

| Capability | Upstream behavior/reference | Current Desktop behavior | Classification | Priority | Confidence | Evidence | Owner / next action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Library discovery/selection | Movie/show selection with counts and recovery | Responsive cards, Select All/Clear All, cancel/server recovery, and validation, but no item counts or per-library recovery detail | PARTIAL | P2 | HIGH | `lib/app/channel_setup_view.dart`; UI tests; screenshots `00-16-12` | Channel Setup: restore decision-useful counts/recovery detail |
| Library scan/planning scale and cancellation | Bounded facet/planning snapshots, explicit recovery, progress, and cancellation | Sequentially downloads all paginated selected-library media before setup; no per-page progress/cancel and empty/error can converge | PARTIAL | P1 | HIGH | `lib/app/lineup_controller.dart`; `lib/plex/plex_client.dart`; upstream planning owners | Bound/concurrently plan, surface progress/error, and cancel large scans |
| Eight strategy families | Playlist, collection, recent, genre, studio, actor, decade, director | All eight produce real deterministic proposals | PARITY | — | HIGH | Upstream setup types; `lib/channels/channel_builder.dart`; builder tests | Builder |
| Per-library/cross-library scope | Eligible strategies can aggregate across libraries | Genre/studio/actor/director support cross-library scope; appropriate families remain per-library | PARITY | — | HIGH | `lib/app/channel_setup_view.dart`; builder tests | Builder |
| Strategy priority/reordering | Accessible strategy priority | Ordered strategies with reorder controls and deterministic priority | PARITY | — | HIGH | `lib/app/channel_setup_view.dart`; `lib/channels/channel_builder.dart` | Builder |
| Minimum items and people breadth | Per-channel threshold; actor/director series breadth | Minimum configurable; TV people require at least three distinct series | PARITY | — | HIGH | `lib/channels/channel_builder.dart`; builder tests | Builder |
| Actor/studio combine mode | Separate or combined treatment | No combined actor/studio mode | MISSING | P3 | HIGH | Upstream setup types; no Desktop model/control | Product decision before implementation |
| Base ordering and blocks | Sequential/shuffle/block with block size | Equivalent modes and sizes | PARITY | — | HIGH | `lib/app/channel_setup_view.dart`; `lib/channels/channel_builder.dart` | Builder |
| Alternate channel variants | Sequential/block variants and copies | Sequential/block plus additional shuffle variants; cap applies after expansion | DESKTOP-ENHANCED | — | HIGH | `lib/app/channel_setup_view.dart`; builder tests | Builder |
| Build modes | Replace/append/merge with stable generated identity | Equivalent modes and stable `builderKey` merge | PARITY | — | HIGH | `lib/channels/channel_builder.dart`; `lib/app/lineup_controller.dart`; tests | Builder/persistence |
| Channel limits | Normalized 1–500, default 200 | Explicit 50–1,000 options and fair round-robin allocation | DESKTOP-ENHANCED | — | HIGH | Upstream setup constants; Desktop setup/builder tests | Builder |
| Strategy preview | Per-strategy estimate, blocked/slow/error/warning states | Proposal/media/cap summary only; slow/failure cannot be distinguished from empty | PARTIAL | P2 | HIGH | Upstream setup planning types; `lib/app/channel_setup_view.dart` | Channel Setup: structured preview state |
| Review diff | Stay/leave/new counts and samples | Create-or-update/remove/final counts and sample; merge unchanged vs updated is not separated | PARTIAL | P2 | HIGH | Upstream review controller; `lib/app/channel_setup_view.dart`; review golden | Channel Setup |
| Replace confirmation | Explicit destructive acknowledgement | Checkbox gate and disabled confirm until acknowledged | DESKTOP-ENHANCED | — | HIGH | `lib/app/channel_setup_view.dart`; review golden | Channel Setup |
| Final build progress/cancellation | Stage-specific progress and active cancellation through planning/build | Final local lineup commit is atomic and normally fast, so its indeterminate noncancelable state is a scoped adaptation; library inventory is the separate long-running gap above | INTENTIONAL DESKTOP ADAPTATION | — | MEDIUM | Upstream progress controller; `lib/app/channel_setup_view.dart` | Measure a 1,000-channel final commit; add cancellation only if materially long |
| Atomic lineup apply/rollback | Scratch build then atomic commit | Validates full next lineup, one state save, in-memory rollback on failure | PARITY | — | MEDIUM | `lib/app/lineup_controller.dart`; `lib/persistence/app_store.dart` | Add focused delayed/failing apply persistence test |
| Saved setup configuration | Normalized setup record; explicit rerun resets it | Libraries persist, but strategy/mode/limits reset with view construction | BLOCKED BY DECISION | P2 | HIGH | Upstream setup record/rerun; `lib/app/channel_setup_view.dart` | Define “edit setup” versus “start over” contract |
| Custom channel creation | Upstream reachable product UI is setup-driven; CRUD service is hidden | Entire-library or hand-picked channels with validation and unavailable-item retention | DESKTOP-ENHANCED | — | HIGH | `lib/app/lineup_shell.dart`; UI regression tests | Channels |
| Editing generated channels | Upstream does not expose the hidden CRUD service as normal UI | Universal Edit silently converts filtered/playlist/mixed sources to unfiltered library/manual and drops `builderKey` | PARTIAL | P1 | HIGH | `lib/app/lineup_shell.dart`; `lib/channels/channel_builder.dart`; tests omit this round trip | Channels: preserve source/identity or explicitly confirm conversion |
| Delete channel | No normal upstream editor | Confirmed deletion, rollback, and focus restoration | DESKTOP-ENHANCED | — | HIGH | `lib/app/lineup_shell.dart`; UI tests | Channels |
| Whole-state save transactions | Serialized persistence and scoped state owners | File writes serialize, but concurrent controller operations can persist another operation's optimistic state after rollback | PARTIAL | P1 | HIGH | `lib/app/lineup_controller.dart`; `lib/persistence/app_store.dart`; missing cross-domain race test | Persistence: serialize mutation/snapshot/commit/rollback |
| Corrupt/transient state recovery | Startup distinguishes invalid/quarantined state | Every non-missing read/decode/I/O error quarantines best-effort and returns empty state without user notice | PARTIAL | P1 | HIGH | `lib/persistence/app_store.dart`; store tests cover malformed JSON only | Separate corruption from transient I/O and surface recovery |
| Deterministic scheduling | Anchored sequential/shuffle/block schedule with past/current/future | Equivalent exact-boundary scheduling and isolate-backed Guide construction | PARITY | — | HIGH | `lib/channels/scheduler.dart`; schedule worker; scheduler tests | Scheduler |
| 1,000-channel product spine | Upstream caps at 500 | Desktop applies/persists/restores 1,000 and vertically bounds Guide work | DESKTOP-ENHANCED | — | HIGH | product-spine and Guide cardinality tests | Add dense-horizontal profile before performance claims broaden |

### Guide and information presentation

| Capability | Upstream behavior/reference | Current Desktop behavior | Classification | Priority | Confidence | Evidence | Owner / next action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Guide shell/hierarchy | Header, showcase/PiP, channel rail, ruler, grid, Now line | Recognizable responsive composition with dedicated Desktop geometry | PARITY | — | HIGH | `lib/guide/guide_view.dart`; Guide goldens; screenshot `00-23-36` | Guide |
| Classic PiP and Overlay Guide | Classic video box or full-video overlay | Both modes share one Flutter/native `PlayerSurface` geometry | PARITY | — | HIGH | `lib/app/lineup_shell.dart`; Guide tests/goldens | Native visibility remains separate evidence |
| Focus/selection/tuned/airing/past states | Distinct browse and playback identities | Distinct state roles, pointer hover, browse without accidental retune | DESKTOP-ENHANCED | — | HIGH | `lib/guide/guide_controller.dart`; `lib/guide/guide_view.dart`; tests | Guide |
| Time and vertical navigation | Remote/pointer row and program movement, page by five, jump Now | Keyboard/pointer movement preserves focus time, viewport-sized paging, jump Now | PARITY | — | HIGH | Guide controller/view tests | Guide |
| Current/future/past tuning policy | Only currently airing real programs tune | Same gate; future/past remain browsable for detail | PARITY | — | HIGH | `lib/guide/guide_controller.dart`; tests | Guide |
| Guide loading/empty/error/retry and stale work | Communicates row state and recovers without applying obsolete results | Per-row loading/error/retry semantics, empty state, and generation-safe schedule/artwork replacement | PARITY | — | HIGH | `lib/guide/guide_controller.dart`; `lib/guide/guide_view.dart`; direct stale/retry tests | Guide |
| Guide context restoration | Retains focused channel/program/time state | Persistent controller retains focus/window/offset across routes | PARITY | — | HIGH | `lib/guide/guide_controller.dart`; route tests | Guide |
| Time-range settings | Detailed 2h or wide 3h | 2/3h parity plus 4/6/8/12h Desktop ranges | DESKTOP-ENHANCED | — | HIGH | `lib/settings/lineup_settings.dart`; Guide tests | Guide |
| Row density | Five-row upstream target | Separate comfortable/compact physical density | DESKTOP-ENHANCED | — | HIGH | `lib/settings/lineup_settings.dart`; Guide tests | Guide |
| Past window | Auto/0/15/30 | Explicit 0/15/30/60/120/180 global window | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | upstream settings; Desktop settings/controller | Guide |
| Library filter | Persisted source-library tabs | Optional selector and safe hidden-filter clearing; selected library is not persisted across restart | PARTIAL | P2 | HIGH | `lib/guide/guide_view.dart`; `lib/guide/guide_controller.dart`; no persisted field | Guide: persist selection if restart continuity remains desired |
| Now Watching context | Optional tuned-channel banner | Optional Now Playing context in header | PARITY | — | HIGH | `lib/guide/guide_view.dart`; tests | Guide |
| Program details/artwork | Metadata, poster/backdrop/logo, badges, three backgrounds | Rich details, artwork/clear logo, badges, three backgrounds | PARITY | — | HIGH | `lib/guide/guide_view.dart`; artwork tests | Guide |
| Vertical virtualization/cache bounds | DOM window and bounded caches | Lazy fixed-extent rows, overscan, bounded row/artwork caches and concurrency | DESKTOP-ENHANCED | — | HIGH | `lib/guide/guide_controller.dart`; 1,000-channel tests | Guide |
| Dense horizontal program bounds | Upstream uses fixed slots/virtualization policy | One visible row may synchronously project/build up to 1,000 program and semantic cells; 480 is tested | NEEDS EVIDENCE | P2 | MEDIUM | `lib/channels/scheduler.dart`; `lib/guide/guide_view.dart`; dense-row controller test | Profile 5–7 shortest-slot rows at 12h in release mode and measure frames/semantics |
| Responsive Guide geometry | Fixed 1920×1080 TV reference | Tested logical 600/720/900/1080/4K regimes and DPR2 allocation | DESKTOP-ENHANCED | — | HIGH | `test/guide/guide_view_test.dart`; Guide goldens | Physical DPI/resize still Windows evidence |
| Native PiP/overlay video | Real upstream video visible in supplied capture | Flutter apertures and rectangle forwarding implemented; no exact-commit physical Windows capture | NEEDS EVIDENCE | P0 | LOW | `lib/playback/native_video_surface.dart`; transparent goldens; `docs/windows-native-validation.md` | Physical Windows: real moving frame, resize, overlay, teardown |

### Player, streaming, tracks, OSD, and input

| Capability | Upstream behavior/reference | Current Desktop behavior | Classification | Priority | Confidence | Evidence | Owner / next action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Single playback owner | HTML5 player/recovery owners | One `PlayerCoordinator`, one native player, generations and serialized tune operations | PARITY | — | HIGH | `lib/playback/player_coordinator.dart`; coordinator tests | Playback |
| Original-stream playback | Direct-play-first playback when an appropriate media version is compatible | Production sends one original Plex part to libmpv, which owns native decode | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | Upstream stream resolver; `lib/app/lineup_controller.dart`; native player | Physical Direct Play proof remains part of Windows acceptance |
| Capability-aware media version/part selection | Scores available media versions/parts against runtime compatibility | Desktop chooses the first `Media` and first `Part` while production advertises unrestricted capability | PARTIAL | P1 | HIGH | `lib/plex/plex_client.dart`; `lib/app/lineup_controller.dart`; no multi-version production fixture | Select a compatible version/part and test alternates deterministically |
| Direct Stream/transcode fallback | HLS when container/codec/resolution/subtitles/HDR policy requires it | Policy code can model direct-stream/transcode, but production unrestricted capabilities make those paths unreachable | MISSING | P1 | HIGH | `lib/playback/stream_policy.dart`; `lib/app/lineup_controller.dart`; stream-policy tests are not production wiring | Streaming: wire real compatibility/fallback owner and integration tests |
| Remote quality selection | User transcode tiers applied to Plex resolver | No production transcode/quality consumer | MISSING | P2 | HIGH | Upstream `transcodeQuality.ts`; no Desktop consumer | Add only with real transcode path |
| HDR compatibility/fallback | Direct/HDR10/HLS fallback policy | libmpv delegates decode/tone mapping; native facts exist, but no fallback policy or physical HDR acceptance | NEEDS EVIDENCE | P1 | LOW | upstream resolver; native telemetry; Windows acceptance plan | Windows HDR display plus stream-policy decision |
| Load/retry surface and resource cleanup | Typed retry/reload and diagnostics | Recoverable error overlay, same-path retry, stale-load rejection, and lease release | PARITY | — | HIGH | `lib/playback/player_coordinator.dart`; tests | Compatibility fallback is classified separately above |
| Tune/replacement lifetime | Stale-operation/currentness ownership | Tune generations, serialized operations, stop/release on scope change | PARITY | — | HIGH | coordinator/native source and tests | Physical replacement stress still required |
| OSD hierarchy | Title/status, progress/buffer, up-next, tracks, sleep | Clean bottom gradient with channel/program/status/telemetry/progress/actions | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | `lib/playback/player_view.dart`; OSD golden; screenshot `00-25-11` | Player UI |
| OSD accessibility-focus timeout | Upstream overlay policy preserves usable focus | Timer hides the whole OSD while a keyboard/AT user may still focus its controls | PARTIAL | P1 | HIGH | `lib/playback/player_coordinator.dart`; no focus hook/test | Suspend timer while focus is inside controls |
| Reduce Motion in player overlays | Upstream/CSS honor reduced motion | Root/Guide honor it, but every player overlay still fades and OSD slides for 350 ms | PARTIAL | P1 | HIGH | `lib/playback/player_view.dart`; animation tests | Player UI: zero/near-zero transition when enabled |
| Mini Guide | Five centered rows, wrap/page/tune/full Guide | Five-row full-width responsive shelf with progress/next/tuned/focus and short-window scrolling | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | coordinator/view tests; mini-guide golden; screenshot `00-27-07` | Player UI |
| Mini Guide accessibility timeout | Timed upstream overlay | Eight-second timer resets on movement but does not suspend for reading/AT focus | PARTIAL | P2 | MEDIUM | `lib/playback/player_coordinator.dart` | Focus/AT timeout acceptance test |
| Audio track selection | Immediate track switch and selected state | Truthful native audio rail and immediate selection | PARITY | — | HIGH | native track model; `lib/playback/player_view.dart`; tests | Playback |
| Subtitle track selection/off | Grouped delivery modes and immediate selection | Native subtitle list plus Off; no false delivery mode | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | `lib/playback/player_view.dart`; long-list tests; screenshot `00-25-21` | Playback |
| Track selector initial focus | Selected entry is the highlighted primary row | Subtitle always starts at Off; audio starts at first row, not selected entry | PARTIAL | P2 | HIGH | `lib/playback/player_view.dart`; tests omit selected-focus assertion | Focus current selected track |
| Subtitle mode/delivery/recovery | Off/Direct/Standard/Full, extract/burn-in and recovery | Native track selection and Off exist, but delivery compatibility, extraction/burn-in, and recovery policy do not | PARTIAL | P1 | HIGH | upstream playback options/resolver; Desktop native seam | Add only the delivery/fallback modes backed by production consumers |
| Preferred/forced subtitle autoselection | Stored language and forced policy affect selection | Plex parses some facts, but no complete native projection/autoselection consumer exists | MISSING | P2 | HIGH | upstream settings; `lib/plex/plex_models.dart`; native track model | Add epoch-safe selection after track facts are complete |
| DTS/direct-play audio fallback | Settings drive resolver and alternate track | No passthrough/capability/fallback command; current UI is honest | INTENTIONALLY OMITTED | — | HIGH | upstream resolver; Desktop `NativePlayer`; user guide | Native capability owner required first |
| Sleep timer | Off/15/30/60/120 and one-minute warning | Off/30/60/90 cycle; stop failure surfaces safely | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | `lib/playback/player_coordinator.dart`; tests | Optional duration/warning parity P3 |
| Rich Now Playing details | Standard/cinematic details, synopsis, art, cast, badges | Guide carries rich details; Player has compact OSD only | MISSING | P2 | HIGH | upstream Now Playing coordinator; no Desktop surface; screenshot `00-26-12` | Product decision: dedicated player details or Guide-as-replacement |
| Fullscreen | Player toggle and platform placement | F/F11/button, native window-placement snapshot/rollback/restore | NEEDS EVIDENCE | P0 | MEDIUM | Dart/C++ source and tests; no physical Windows report | Physical Windows DPI/move/minimize/fullscreen campaign |
| Channel entry/CH navigation | Digits and CH± remote behaviors | Digit buffer, PageUp/PageDown channels, explicit error, mini Guide paging | DESKTOP-ENHANCED | — | HIGH | player source/tests | Input |
| Keyboard/media keys | TV remote/playback key map | Desktop keys, numpad, media transport, Guide/settings shortcuts | DESKTOP-ENHANCED | — | HIGH | `lib/app/lineup_shell.dart`; `lib/playback/player_view.dart`; tests | Input |
| Cursor auto-hide and pointer wake | Timed pointer hiding over immersive playback | Desktop schedules cursor hiding while playing and restores it on pointer activity | PARITY | — | HIGH | `lib/playback/player_coordinator.dart`; `lib/playback/player_view.dart`; tests | Player input |
| Gamepad | webOS/browser remote mapping | No current Flutter/Windows gamepad owner or physical evidence | INTENTIONALLY OMITTED | — | HIGH | upstream navigation; current tree census | Re-establish only from a supported Desktop input contract |

### Settings

| Capability | Upstream behavior/reference | Current Desktop behavior | Classification | Priority | Confidence | Evidence | Owner / next action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DTS Passthrough setting | Consumed by capability/audio policy | Hidden; no native passthrough consumer | INTENTIONALLY OMITTED | — | HIGH | upstream settings/resolver; Desktop `NativePlayer` | Windows media prerequisite |
| Direct Play Audio Fallback setting | Consumed by resolver | Hidden; no alternate-track fallback owner | INTENTIONALLY OMITTED | — | HIGH | upstream resolver; Desktop playback wiring | Streaming prerequisite |
| Subtitle Mode setting | Controls delivery/recovery/transcode | Hidden; no delivery policy consumer | INTENTIONALLY OMITTED | — | HIGH | upstream settings; Desktop track rail | Streaming prerequisite |
| Preferred Subtitle Language | Applied automatically | Manual track selection only | MISSING | P2 | HIGH | upstream settings; Desktop native track projection | Add with autoselection owner |
| Prefer Forced Subtitles | Applied by descriptor/recovery | Forced fact does not reach a complete native consumer | MISSING | P2 | HIGH | upstream settings; Desktop models/native seam | Add with the autoselection capability, not as dead preference state |
| Keep Playback Running in Settings | Optional on webOS | Desktop coordinator always persists across management routes | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | `lib/app/lineup_shell.dart` | Fixed Desktop behavior |
| HDR Fallback setting | Controls compatibility/transcode | Hidden pending supported HDR policy and evidence | INTENTIONALLY OMITTED | — | HIGH | upstream settings/resolver; Windows plan | Windows prerequisite |
| Transcode Quality setting | Applies bitrate/resolution tier | No production transcode consumer | MISSING | P2 | HIGH | upstream config; Desktop playback wiring | Add with transcode path |
| Transcode Compat Mode | Changes transcode parameters | No equivalent consumer | INTENTIONALLY OMITTED | — | HIGH | upstream settings/resolver | Streaming prerequisite |
| Library Tabs | Optional Guide filter | `Library filters` directly controls Guide and clears hidden filter | PARITY | — | HIGH | settings/shell/Guide tests | Settings |
| Now Watching Banner | Optional tuned context | `Now Playing context` directly controls Guide banner | PARITY | — | HIGH | settings/shell/Guide tests | Settings |
| OSD auto-hide duration | Upstream uses its own fixed/timed overlay policy | User selects 2/4/6/8/10/15 seconds; the active coordinator updates its timer | DESKTOP-ENHANCED | — | HIGH | `lib/settings/lineup_settings.dart`; `lib/playback/player_coordinator.dart`; coordinator tests | Settings/Player |
| Aggressive Guide Preload | Experimental resource-policy toggle | Bounded caches/concurrency are product policy, not user tuning | NOT APPLICABLE | — | HIGH | upstream settings; Desktop Guide owners | Keep internal |
| Guide Density/time range | 2h/3h visible range | 2h/3h parity plus extended hours and separate row density | DESKTOP-ENHANCED | — | HIGH | settings/controller/tests | Settings |
| Guide Layout | Classic PiP/Overlay | Equivalent | PARITY | — | HIGH | settings/shell/tests | Settings |
| Past Items | Auto/0/15/30 | Explicit 0–180-minute global choices | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | settings/controller/tests | Settings |
| Info Box Background | Bleed/artwork/theme | Equivalent with real consumers | PARITY | — | HIGH | settings/Guide tests | Settings |
| Theme | Five named themes | Same five themes, immediate durable apply | PARITY | — | HIGH | theme/settings tests | Settings |
| Cinematic Now Playing | Enables rich player detail presentation | No rich Player details surface | MISSING | P2 | HIGH | upstream setting/surface; Desktop tree | Feature first, setting second |
| Use Clear Logos | Guide/Now Playing/OSD | Desktop applies narrowly to Guide details | PARTIAL | P3 | HIGH | settings/Guide source | Optional Player expansion |
| Now Playing Auto-Hide | Controls distinct details overlay, including persistent | Desktop OSD auto-hide is a different control | MISSING | P2 | HIGH | upstream settings; Desktop settings/coordinator | Add only with rich details surface |
| Show Profile Picker on Startup | Startup routing preference | Equivalent durable preference | PARITY | — | HIGH | controller/settings tests | Settings |
| Debug Logging | Developer surface | Replaced with bounded opt-in redacted diagnostics | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | upstream diagnostics; Desktop diagnostics | Support |
| Subtitle Debug Logging | Browser/text-track developer surface | No user-facing equivalent | NOT APPLICABLE | — | HIGH | upstream settings; platform mismatch | Developer-only |
| Reduce Motion | Upstream honors platform preference broadly | Explicit Desktop setting; root/Guide consume it, Player overlays do not | PARTIAL | P1 | HIGH | settings/app/Guide/player source | Complete Player consumer coverage |
| Large Focus Indicators | No equivalent visible upstream preference | Desktop-wide semantic focus-border role | DESKTOP-ENHANCED | — | HIGH | theme/settings tests | Accessibility |
| Record Redacted Diagnostics | Upstream raw developer logging | Desktop opt-in bounded session support log | DESKTOP-ENHANCED | — | HIGH | diagnostics/settings tests | Support |
| Switch profile/server actions | Separate TV routes | Direct Settings actions with scoped state retention | DESKTOP-ENHANCED | — | HIGH | `lib/app/lineup_shell.dart`; controller tests | Settings |

### Desktop platform, diagnostics, packaging, and release

| Capability | Upstream behavior/reference | Current Desktop behavior | Classification | Priority | Confidence | Evidence | Owner / next action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Responsive management shell | Fixed 1920×1080 TV composition | Pointer/Tab NavigationRail and category layouts across compact to 4K | DESKTOP-ENHANCED | — | HIGH | shell/UI tests; settings golden | Flutter UI |
| Five theme system | Same named theme intent | Semantic role-based themes with contrast tests | PARITY | — | HIGH | `lib/ui/app_theme.dart`; theme tests | UI |
| Accessibility semantics | ARIA/modal/live/focus behaviors | Flutter semantics, focus restoration, live errors/progress, reduced-motion/focus prefs | PARTIAL | P1 | HIGH | UI/Guide/player source/tests; OSD focus/motion gaps | Accessibility |
| Credential-safe diagnostics claim | Redacted logging/diagnostic tooling | Arbitrary `error.toString()` values enter an `error` context key that regex redaction cannot guarantee safe | PARTIAL | P1 | HIGH | `lib/diagnostics/diagnostics.dart`; producer calls; tests omit opaque-secret boundary | Record structured error codes, not opaque exception text |
| Durable support-bundle export | Not a normal upstream product surface | Historical Electron exported double-scanned bounded artifacts; Flutter only displays session entries | MISSING | P2 | HIGH | Electron support exporter/tests; Desktop diagnostics/shell | Support: safe export without Electron architecture |
| State file atomicity | Local client storage | Unique temp, flushed write, rename, serialized physical writes | DESKTOP-ENHANCED | — | HIGH | `lib/persistence/app_store.dart`; tests | Persistence |
| Local media-metadata privacy | Browser-local channel state contains library facts | Desktop writes channel titles, summaries, ratings, genres, artwork paths, and codec facts to plaintext `state.json`; tokens remain separate in secure storage | PARTIAL | P2 | HIGH | `lib/channels/channel.dart`; `lib/persistence/app_store.dart` | Document location/deletion/threat model and decide whether to minimize/protect metadata |
| Secure credentials | Client-side tokens | Platform secure storage, separate account/profile keys, no token in JSON | DESKTOP-ENHANCED | — | HIGH | `lib/persistence/app_store.dart`; controller tests | Credentials |
| macOS UI development | Not applicable to webOS | Exact toolchain analysis/tests/build pass; playback explicitly unsupported | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | local 2026-08-23 commands; macOS backend tests | Supported only as UI development |
| Windows native player implementation | Not applicable to webOS HTML5 | Narrow C++/libmpv owner, generation filtering, DComp marker, bounds/fullscreen | NEEDS EVIDENCE | P0 | MEDIUM | `windows/runner/native_player.cpp`; Dart tests; CI compile | Physical Windows acceptance |
| Native rectangle contract | Browser owns video element | Flutter calculates global bounds/DPR and zeroes on dispose; fakes do not assert values | NEEDS EVIDENCE | P1 | MEDIUM | `lib/playback/native_video_surface.dart`; no recording fake | Add Dart geometry-contract test plus physical proof |
| Exact-HEAD CI | Upstream webOS CI is comprehensive for its platform | Platform-adapted exact source checks passed Dart, macOS build/goldens, Windows UI and stock-engine compile | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | GitHub run `32589006254`; local 278-test pass; patched job skipped | CI |
| Patched-engine CI artifact | Not applicable upstream | Exact-HEAD expensive engine job skipped and run produced zero artifacts | NEEDS EVIDENCE | P0 | HIGH | `.github/workflows/ci.yml`; run/job/artifact metadata | Force manual exact-commit engine/package build |
| Package engine provenance | Not applicable upstream | Package validates source/libmpv but unconditionally attests patched engine without verifying built `flutter_windows.dll` | PARTIAL | P1 | HIGH | `tool/windows/package.ps1`; native marker enforcement | Packaging: bind attestation to actual engine artifact |
| Package CI ownership | Not applicable upstream | Package tests/upload run only under narrow engine-input detector; package-only changes can stay green without package proof | PARTIAL | P1 | HIGH | `.github/workflows/ci.yml` | Split cheap package verification from engine rebuild |
| Portable runtime provenance | No comparable webOS product capability | Windows distribution pins Flutter/engine/depot_tools/libmpv inputs and hashes and checks source/runtime facts | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | development/runtime docs; build metadata; scripts | Desktop release engineering strength |
| Native notice completeness | Not applicable upstream | Package verifies four media-runtime license inputs and includes app/engine provenance texts, but lacks a complete transitive dependency/source-notice manifest for monolithic libmpv | BLOCKED BY DECISION | P0 | HIGH | `docs/windows-runtime.md`; `tool/windows/package.ps1`; `third_party/libmpv` | Legal/release: complete manifest and independent review |
| Runtime mirror | Not applicable upstream | Third-party binary source is hash-pinned, but project-controlled immutable mirror is required by current release policy | BLOCKED BY DECISION | P0 | HIGH | `docs/windows-runtime.md`; build metadata | Release owner |
| Signing/public release channel | Not applicable upstream | No signing, supported channel, installer, updater, or release automation | BLOCKED BY DECISION | P0 | HIGH | README/user guide; repo census | Decide portable-only scope, signing and publication owner |
| Installer/updater | webOS sideload/package model | Deliberately absent; a portable first release could omit both with recovery guidance | BLOCKED BY DECISION | P2 | HIGH | README/user guide; repo census | Product/release decision, not automatic blocker |
| Network and application-lifecycle recovery | webOS observes connectivity, visibility, memory pressure, and relaunch | Desktop has request-level retries, bounded caches, stale-result rejection, and metric updates, but no general sleep/resume or reconnect campaign | PARTIAL | P2 | MEDIUM | Plex/Guide/player owners and tests; `lib/playback/native_video_surface.dart` | Exercise network loss, sleep/resume, minimize/restore, and server reappearance before broader support |

### Historical Electron product-value check

Electron is provenance only, never a compatibility target. The table records
end-user value; browser/process/IPC mechanics are excluded.

| Capability | Upstream behavior/reference | Current Desktop behavior | Classification | Priority | Confidence | Evidence | Owner / next action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Runtime fullscreen | Upstream player fullscreen | Reimplemented in Flutter/C++ with placement rollback | PARITY | — | HIGH | Electron shell window; Desktop player/native source/tests | Physical proof pending above |
| Persisted launch fullscreen | No material upstream equivalent | Historical setting is absent | MISSING | P3 | HIGH | Electron settings/runtime; Desktop settings census | Optional preference |
| Single-instance restore/focus | No material upstream equivalent | Historical Electron restored/focused existing instance; Flutter has no owner | BLOCKED BY DECISION | P2 | HIGH | Electron `singleInstanceOwner.ts`; Desktop census | Decide multi-instance policy before implementing |
| Windows audio device selection | Upstream asks audio intent, not device enumeration | Historical Electron picker intentionally replaced by OS-selected output | INTENTIONALLY OMITTED | — | HIGH | Electron audio owner; Desktop onboarding/user guide | Require physical native device contract before revisiting |
| Bounded diagnostics | Upstream developer diagnostics | Reimplemented as bounded opt-in Flutter session log | PARITY | — | HIGH | Electron/Flutter diagnostics source/tests | Support |
| Safe support-bundle export | No normal upstream product equivalent | Valuable historical capability is lost | MISSING | P2 | HIGH | Electron exporter/tests; Desktop diagnostics census | Recreate only the user capability |
| Channel import/export | Upstream service is hidden; Electron service had no reachable UI | No current workflow | NOT APPLICABLE | — | HIGH | Electron domain/call-site census; upstream hidden CRUD | Do not promote latent code |
| Runtime updater | No historical Electron updater | No current updater | NOT APPLICABLE | — | HIGH | Electron/Desktop manifest and source census | None |
| OS deep links | Electron custom scheme was internal Chromium delivery | No user-facing deep links | NOT APPLICABLE | — | HIGH | Electron protocol/second-instance source | Obsolete infrastructure |
| Keyboard/media shortcuts | Upstream remote behavior | Reimplemented and expanded through Flutter focus events | DESKTOP-ENHANCED | — | HIGH | Electron/Flutter input source/tests | Input |
| Browser Gamepad polling | WebOS/browser-style input | Intentionally not ported; no supported Flutter/Windows contract | INTENTIONALLY OMITTED | — | HIGH | Electron input; Desktop census | Re-establish only with new evidence |
| Global OS shortcuts | No historical global-hotkey registration | App-focused shortcuts only | NOT APPLICABLE | — | HIGH | Electron/Desktop census | None |

## UX/UI findings

### Onboarding and account

The supplied profile/PIN references preserve a clear, remote-first hierarchy.
Desktop is generally better for pointer, Tab, numpad, compact-window, and
semantic input, but it omits upstream role/active badges. That omission is
informational; the material regression is failure feedback: terminal PIN poll
and account-validation errors can appear as a stalled “Waiting for sign-in”.

### Channel Setup

Desktop's responsive library grid, category rail, explicit limits, and replace
confirmation are effective improvements, but library cards omit counts and the
pre-setup scan pages all selected media without progress or cancellation.
Preview/review communicate less source-specific status. Final commit progress is
deliberately indeterminate because that save is atomic and expected to be short;
the network inventory phase is not covered by that rationale. The dangerous UI
defect outside the wizard is the generic editor silently changing generated
source semantics.

### Guide

The current Guide preserves the upstream hierarchy while distinguishing focus,
selection, tuned channel, airing state, and past state more clearly. Committed
1280×720 goldens and responsive tests are strong Flutter evidence. They do not
prove a real Windows video layer. Vertical work is bounded; worst-case dense
horizontal program and semantics work is not yet profiled.

### Player, OSD, and mini Guide

The compact bottom OSD and five-row top mini Guide are coherent Desktop
adaptations, with direct goldens and strong input tests. The OSD can disappear
while its controls retain keyboard/assistive focus, and player transitions
ignore Reduce Motion. Playback-options rails truthfully expose native tracks,
but initial focus does not follow the selection and subtitle delivery/recovery
depth is absent. A cinematic rich-details Player surface is genuinely absent
but P2.

### Settings

The category rail/detail layout, extended Guide choices, accessibility controls,
account actions, and redacted-diagnostics preference are Desktop value. Every
visible Desktop preference is persisted and has a current consumer. Missing
upstream media settings are not superficial Settings gaps; they depend on
absent compatibility, transcode, subtitle-delivery, or native capability
owners.

All preference changes apply immediately through one optimistic controller
save. The Settings UI disables further edits during that save and reports a
failure while retaining the previous value; stale same-domain failures cannot
roll back a newer setting. The cross-domain save-isolation defect recorded in
the matrix still applies. Restore normalizes invalid enum/numeric values.

| Desktop preference/state | Default and choices | Persistence and runtime consumer |
| --- | --- | --- |
| Theme | Ember & Steel; five named themes | Durable; root `ThemeData` and semantic roles update immediately |
| Guide presentation | Classic PiP; PiP/Overlay | Durable; shell chooses native-video/Guide composition |
| Visible time range | 2h; 2/3/4/6/8/12h | Durable; Guide window, ruler, schedule projection |
| Past window | 30m; 0/15/30/60/120/180m | Durable; Guide request and browse bounds |
| Row density | Comfortable; Comfortable/Compact | Durable; responsive Guide row geometry |
| Info background | Artwork bleed; Bleed/Theme/Artwork | Durable; focused-program background renderer |
| Prefer clear logos | On; Boolean | Durable; Guide detail artwork selection |
| Library filters | On; Boolean | Durable; Guide toolbar availability and stale-filter clearing |
| Now Playing context | On; Boolean | Durable; tuned-program Guide banner |
| Player controls auto-hide | 4s; 2/4/6/8/10/15s | Durable; active Player coordinator timer |
| Reduce motion | Off; Boolean | Durable; root and Guide transitions; Player coverage is partial |
| Large focus indicators | Off; Boolean | Durable; app-wide semantic focus-border width |
| Profile picker on startup | Off; Boolean | Durable; authenticated startup routing |
| Record redacted diagnostics | Off; Boolean | Durable; bounded session diagnostic recorder |
| First-run audio completion | Incomplete; Boolean, onboarding-owned | Durable; first-run routing suppresses completed audio explanation |

### Themes

Ember & Steel, Slate & Pine, Swiss Minimal, DirecTV Classic, and Glassmorphism
all flow through the same semantic roles across management, Guide, Player, OSD,
mini Guide, Settings, focus, tuned/current states, and scrims. All five have
programmatic text/focus contrast checks; Ember & Steel has most accepted pixels
and Slate & Pine has one Settings golden. The other three lack per-screen pixel
acceptance, so source/token consistency is stronger evidence than their visual
regression coverage.

### Responsive design

Management, Guide, OSD, mini Guide, and track lists have meaningful structural
coverage from 800×600 through logical 4K, with Guide breakpoint/DPR2 tests.
Only 1280×720 has accepted pixels. The principal remaining responsive risk is
not clipping but dense 12-hour horizontal Guide/semantics work and physical
Windows video alignment during DPI/resize changes.

### Focus and input

Keyboard, numpad, pointer, media-key, paging, and logical remote navigation are
strong, with explicit focus restoration between management, Guide, Player,
dialogs, and track rails. Selected-track initial focus is wrong, and timed
Player overlays do not preserve focused operation. Browser-style gamepad input
is intentionally outside scope; no physical Windows controller claim exists.

### Accessibility

Flutter semantics, modal/live-state labels, focus visibility, the large-focus
preference, and bounded vertical Guide construction are meaningful improvements.
Accessibility is incomplete until timed overlays respect focused/assistive
reading, Player honors Reduce Motion, dense horizontal semantics are measured,
and a physical Windows keyboard/screen-reader pass supplies platform evidence.

## Screenshot evidence inventory

All 12 supplied files were inspected at original pixels and are treated, per
the audit request, as upstream reference evidence. Exact upstream version,
logical viewport, scale factor, and DPI are unknown, so each is supplemental
visual evidence rather than exact-commit acceptance. They contain potentially
private profile, library, or media facts; this record reproduces none of them.

| Screenshot | Date / source provenance | Pixels; logical/DPI | State | Privacy / confidence | Evidence use |
| --- | --- | --- | --- | --- | --- |
| `Screenshot 2026-08-14 at 00-15-02 Lineup.png` | 2026-08-14; supplied as upstream Lineup, commit unknown | 3840×2160; unknown | Profile picker | Private facts present; LOW | Account hierarchy/reference only |
| `Screenshot 2026-08-14 at 00-15-25 Lineup.png` | 2026-08-14; supplied as upstream Lineup, commit unknown | 3840×2160; unknown | Protected-profile PIN | Private facts present; LOW | Modal/keypad reference |
| `Screenshot 2026-08-14 at 00-16-12 Lineup.png` | 2026-08-14; supplied as upstream Lineup, commit unknown | 3840×2160; unknown | Setup libraries | Private facts present; LOW | Selection/bulk-action reference |
| `Screenshot 2026-08-14 at 00-16-32 Lineup.png` | 2026-08-14; supplied as upstream Lineup, commit unknown | 3840×2160; unknown | Setup strategies | Private facts may be present; LOW | Category/toggle/reference state |
| `Screenshot 2026-08-14 at 00-16-52 Lineup.png` | 2026-08-14; supplied as upstream Lineup, commit unknown | 3840×2160; unknown | Setup review | Private lineup facts present; LOW | Impact/confirmation reference |
| `Screenshot 2026-08-14 at 00-17-06 Lineup.png` | 2026-08-14; supplied as upstream Lineup, commit unknown | 3840×2160; unknown | Setup progress | Private lineup facts may be present; LOW | Progress/cancel reference |
| `Screenshot 2026-08-14 at 00-23-36 Lineup.png` | 2026-08-14; supplied as upstream Lineup, commit unknown | 3456×1942; unknown | Guide with PiP | Private media facts present; LOW | Guide composition reference |
| `Screenshot 2026-08-14 at 00-25-11 Lineup.png` | 2026-08-14; supplied as upstream Lineup, commit unknown | 3456×1942; unknown | Player OSD | Private media facts present; LOW | Bottom OSD hierarchy reference |
| `Screenshot 2026-08-14 at 00-25-21 Lineup.png` | 2026-08-14; supplied as upstream Lineup, commit unknown | 3456×1942; unknown | Playback options | Private media facts present; LOW | Track/delivery reference |
| `Screenshot 2026-08-14 at 00-26-12 Lineup.png` | 2026-08-14; supplied as upstream Lineup, commit unknown | 3456×1942; unknown | Rich Now Playing | Private media facts present; LOW | Missing Player-details reference |
| `Screenshot 2026-08-14 at 00-26-52 Lineup.png` | 2026-08-14; supplied as upstream Lineup, commit unknown | 3456×1942; unknown | Settings over video | Private profile/media facts present; LOW | Settings/media-policy reference |
| `Screenshot 2026-08-14 at 00-27-07 Lineup.png` | 2026-08-14; supplied as upstream Lineup, commit unknown | 3456×1942; unknown | Mini Guide | Private media facts present; LOW | Top-shelf reference |

Current Desktop visual evidence consists of eight committed 1280×720 macOS
goldens: profiles, Channel Setup review, Guide without playback, Guide PiP,
Overlay Guide, OSD, mini Guide, and one alternate-theme Settings state.

## Mechanical summary

The matrix contains **146 capabilities**:

- 37 **PARITY**;
- 23 **DESKTOP-ENHANCED**;
- 14 **INTENTIONAL DESKTOP ADAPTATION**;
- 29 **PARTIAL**;
- 14 **MISSING**;
- 9 **INTENTIONALLY OMITTED**;
- 6 **NOT APPLICABLE**;
- 7 **NEEDS EVIDENCE**; and
- 7 **BLOCKED BY DECISION**.

The actionable/decision rows contain 8 P0, 16 P1, 28 P2, and 5 P3
dispositions. These are row counts; the eight remediation groups below
consolidate related P0/P1 rows into owned work.

Counts are literal matrix-row counts, not a quality-weighted percentage.
Separate conclusions:

- **Core daily-use parity:** broad but provisional because PMS authorization
  can fail before libraries/playback, and physical Windows media is unproven.
- **Total upstream coverage:** every material workflow and every visible
  setting has a disposition; webOS/developer-only behavior is separated.
- **Desktop-only value:** responsive management, custom channels, extended
  Guide ranges/density, focused state separation, accessibility preferences,
  secure storage, and bounded support diagnostics are material additions.
- **Private beta:** a controlled evidence cohort can follow the PMS credential
  fix; a supported beta additionally needs the exact-package Windows smoke.
- **Public release:** not ready; package, native, notice/legal, mirror, signing,
  and release-channel gates remain.

## Intentional adaptations and omissions

### Intentional Desktop adaptations

- OS-selected audio replaces unproven receiver/device/passthrough controls.
- The player remains alive across management routes, so the upstream
  keep-playing toggle is unnecessary.
- Guide geometry, row density, past windows, OSD, mini Guide, Settings, and
  navigation adapt TV intent to resizable pointer/keyboard windows.
- Native track rails expose only facts the current player can consume.
- macOS is a UI-development platform with an explicit unsupported player.

### Intentionally omitted upstream behavior

- DTS/passthrough, direct-play audio fallback, HDR fallback, transcode
  compatibility, and gamepad are hidden until a truthful native/stream consumer
  and evidence exist. Subtitle selection is visible, but its missing delivery,
  recovery, preferred-language, and forced-selection depth is classified as
  partial/missing rather than intentionally omitted.
- Aggressive preload and raw/subtitle debug logging are resource/developer
  policy, not normal Desktop settings.

### WebOS/browser-only or developer-only behavior

HTML5 video/Media Session, webOS relaunch/keepalive, visibility memory budgets,
raw remote-key aliases, internal debug globals, EPG storage debug flags, and
browser subtitle extraction are not Desktop requirements. Desktop independently
implements playback cursor auto-hide as a normal pointer behavior.
Upstream's hidden channel CRUD/import/export services and stale route tokens are
not counted as reachable product capability.

### Obsolete Electron behavior intentionally removed

Chromium protocol delivery, renderer/main/preload/IPC ownership, browser
Gamepad polling, window-process workarounds, and latent channel import/export
code are not compatibility targets. Audio-device enumeration remains omitted
because its historical physical validation was incomplete.

### Desktop enhancements not present upstream

Custom channel management, extended 1,000-channel limits, additional variants,
large focus indicators, explicit reduced motion, bounded user-visible support
diagnostics, responsive management navigation, secure credential storage, and
native Windows presentation are Desktop-specific value.

## Evidence-gap register

| Unknown | Why evidence is insufficient | Smallest proof | Environment | Private beta | Public release |
| --- | --- | --- | --- | --- | --- |
| Real PMS authorization across owner, managed Home, and shared server | Current tests use one token and omit resource `accessToken` | Distinct cloud/Home/PMS token integration fixture plus a live disposable managed/shared profile smoke | Mac for deterministic test; Windows for live playback | Blocks | Blocks |
| Large-library inventory/planning | Current tests do not measure paging, memory, cancellation, or empty/error recovery on representative large PMS libraries | Synthetic multi-page library with forced slow/error pages; record memory/time, progress, cancellation, and retry | Mac/CI; live disposable server follow-up | Blocks broad-library beta | Blocks |
| Final atomic apply duration/failure | Source rolls memory back, but no focused delayed/failing persistence fixture proves UX and durable state | Force delayed then failed save during a 1,000-channel apply; verify progress, prior memory/disk state, and retry | Mac/CI | No if measured fast | Blocks atomicity claim |
| State read-failure taxonomy | Malformed JSON is tested, but permission denial, truncation, short/transient read, and quarantine failure are not | Inject each failure and verify corruption versus retry/recovery without silent overwrite | Mac/CI; Windows app-data smoke | Blocks affected beta recovery | Blocks |
| Direct Stream/transcode fallback | Policy unit tests are disconnected from production's unrestricted capability input | Production integration fixture that forces original incompatibility, verifies resolver choice/cleanup, and plays the result | Mac/CI for policy; physical Windows codec cases | No if beta media is constrained | Blocks general media claim |
| Real Windows video/audio and DirectComposition stacking | C++ compiles and Flutter apertures are tested; no physical exact-commit report exists | Visible moving SDR video in Player/PiP/Overlay, audio, replacement tune, close/reopen | Physical Windows 10/11 x64 | Blocks supported beta | Blocks |
| Native rectangle DPR/resize/dispose forwarding | Test fakes ignore `setVideoRect` | Recording fake asserts initial/resize/DPR/zero-on-dispose; physical resize validates frame alignment | Mac test plus physical Windows | No after basic smoke | Blocks broad support |
| HDR/tone mapping/hardware decode | Source/telemetry do not prove display output | Pinned HDR media on an HDR display with expected telemetry and visual judgment | Physical Windows HDR system | No if excluded | Blocks HDR claim |
| Patched engine and portable package at exact commit | Exact-head CI skipped expensive job and emitted no artifact | Forced clean engine build, package, manifest/hash inspection and launch outside repo | Clean Windows build/test machines | Blocks supported package | Blocks |
| Clean-system Vulkan prerequisite/recovery | No disposable-system evidence | Launch with/without Vulkan loader only in disposable VM/snapshot; verify guidance | Disposable Windows VM | No if cohort is provisioned | Blocks broad package claim |
| Package engine attestation | Script does not bind claim to actual built engine | Stock-engine negative test plus patched-engine identity/hash positive test | Windows | Blocks supported package | Blocks |
| Dense 12-hour Guide semantics/performance | Vertical cardinality fixtures use long programs | Profile 5–7 visible rows of one-minute items; record nodes/frame timings and traversal | Mac profile; confirm Windows | No unless observed slow | Blocks 12h/1,000 claim |
| Keyboard/AT timed-overlay usability | Widget tests do not keep focus inside OSD/mini Guide past timeout | Focus/semantics tests and one screen-reader/keyboard session | Mac test plus physical Windows AT | Blocks accessibility claim | Blocks support claim |
| Mini Guide reading/focus timeout | Browse input resets the timer, but a paused keyboard/AT reading interval is not exercised | Keep focus/semantics interaction inside the shelf beyond eight seconds and verify it remains operable | Mac test plus Windows AT | No if documented | Blocks accessibility support claim |
| Network loss and OS suspend/resume | Request-level recovery tests do not prove a live session reconnects cleanly across adapter/server loss or sleep | Redacted tune/Guide session through network loss/recovery, server disappearance/reappearance, sleep/resume, minimize/restore | Physical Windows plus controlled network | Advisable | Blocks broad reliability claim |
| Physical gamepad | No current owner or device evidence | Product decision followed by supported-controller mapping/evidence | Physical Windows | No, omitted | No unless claimed |
| Screenshot provenance | Pixels do not establish exact commit/logical DPI | Sanitized capture manifest naming commit, logical size, DPR and platform | Source capture environment | No | No |
| Long-duration playback/replacement soak | Unit currentness tests are not a native soak | Repeated tune/stop/fullscreen/track cycles with redacted resource and leak observations | Physical Windows | Advisable | Blocks reliability claim |
| Native notice/legal completeness | Top-level texts do not prove transitive obligations | Generated dependency/license manifest, vendored hashes, independent legal approval | Release/legal review | No for tightly controlled private test | Blocks |
| Signing and publication trust | No selected signing/release channel | Documented signing identity, reproducible publication workflow, verification/revocation guidance | Windows/release infrastructure | No for direct cohort | Blocks |

## P0/P1 remediation groups

### 1. Correct Plex credential ownership end to end

- **Classifications / priority:** MISSING, P0.
- **Evidence:** `PlexServer` drops resource `accessToken`; every PMS consumer
  receives the Plex.tv/Home token.
- **Owner:** Flutter Plex models/client/controller and transport integration tests.
- **Consequence:** managed Home/shared servers can discover but fail probes,
  libraries, artwork, or playback with misleading authorization errors.
- **Acceptance:** keep the PMS token private/non-persisted, use it for every PMS
  request, refresh once on bounded authorization failure, and test distinct
  cloud/Home/PMS credentials through playback request construction.
- **Why P0:** the discarded credential can prevent the first authenticated PMS
  request for ordinary managed/shared-profile users.
- **Machine:** Mac/CI deterministic; Windows live managed/shared profile smoke.
- **Suggested implementation model:** Sol High.
- **Independent review:** yes; credential ownership crosses a remote trust
  boundary and every PMS consumer.

### 2. Bound and cancel large-library setup planning

- **Classifications / priority:** PARTIAL, P1.
- **Evidence:** selected libraries are paged sequentially into memory before
  setup, without per-page progress/cancellation or a structured empty/error state.
- **Owner:** Flutter Plex pagination and Channel Setup planning UI/controller.
- **Consequence:** an ordinary large library can leave first-run setup looking
  stalled, consume excessive memory, or make failure indistinguishable from no content.
- **Acceptance:** bound/concurrently schedule pagination, expose real progress,
  cancel stale/abandoned scans, preserve successfully loaded libraries where safe,
  distinguish empty/unsupported/transient failure, and test representative scale.
- **Why P1:** large Plex libraries are normal public-release input, while a
  controlled beta can constrain library size and observe the current path.
- **Machine:** Mac/CI deterministic; live disposable PMS follow-up on Windows.
- **Suggested implementation model:** Sol High.
- **Independent review:** yes; network cancellation, memory bounds, and setup
  state ownership cross several async boundaries.

### 3. Make channel and state edits transaction-safe

- **Classifications / priority:** PARTIAL, P1.
- **Evidence:** generated Edit rewrites source/identity; concurrent saves can
  persist rolled-back optimistic state; unreadable state becomes silent defaults.
- **Owner:** Flutter Channels/controller/persistence.
- **Consequence:** user-visible channel content or restart state can differ from
  the action reported by the UI.
- **Acceptance:** metadata-only generated edits preserve source and
  `builderKey` or explicitly confirm conversion; controller mutations commit
  atomically across domains; corruption and transient I/O have distinct,
  tested recovery without silent overwrite.
- **Why P1:** these are credible data-integrity/restart defects in ordinary
  channel-management actions, but do not block a controlled read-heavy beta.
- **Machine:** Mac/CI.
- **Suggested implementation model:** Sol High.
- **Independent review:** yes; async lifetime, persistence, and product semantics
  span multiple owners.

### 4. Close credential and diagnostic safety boundaries

- **Classifications / priority:** PARTIAL, P1 for diagnostic safety; related P2
  credential-hygiene residue.
- **Evidence:** failed/cancelled profile switch can retain an unused secure
  token; arbitrary exception strings can bypass regex guarantees.
- **Owner:** Credential store/controller/diagnostics.
- **Consequence:** stale credential retention and possible secret text in a
  visible support log.
- **Acceptance:** scoped token restore/delete compensation across cancellation
  and save failure; diagnostics record structured safe codes/classes, with an
  opaque-secret sentinel test at every producer boundary.
- **Why P1:** ordinary failure paths can retain a credential or display opaque
  secret-bearing text, creating a support/security boundary before release.
- **Machine:** Mac/CI; physical Windows secure-store smoke before support claim.
- **Suggested implementation model:** Sol High.
- **Independent review:** yes; security-sensitive compensation and redaction
  need adversarial validation.

### 5. Complete streaming compatibility ownership

- **Classifications / priority:** PARTIAL/MISSING/NEEDS EVIDENCE, P1.
- **Evidence:** production always supplies unrestricted capabilities, selects the
  first media version/part, and lacks subtitle-delivery fallback; direct
  stream/transcode tests do not prove reachable runtime wiring; HDR is untested.
- **Owner:** Flutter Plex stream policy plus native capability projection.
- **Consequence:** original streams that libmpv cannot safely play and
  constrained remote playback lack an owned fallback.
- **Acceptance:** define actual supported capabilities; choose among multiple
  versions/parts; exercise Direct Play, Direct Stream/transcode, subtitle
  delivery/recovery, and cleanup with deterministic fixtures; scope first-release
  media claims to physically accepted combinations.
- **Why P1:** a controlled beta can constrain known-good media, while a public
  player needs a truthful fallback for common incompatible/remote streams.
- **Machine:** Mac/CI policy tests; physical Windows codec/HDR matrix.
- **Suggested implementation model:** Sol High.
- **Independent review:** yes; Plex policy, native capability, and media evidence
  must agree.

### 6. Fix timed-overlay accessibility and motion

- **Classifications / priority:** PARTIAL/NEEDS EVIDENCE, P1.
- **Evidence:** OSD auto-hide ignores focused controls; Player always animates;
  native rectangle and dense semantics proof is incomplete.
- **Owner:** Flutter Player/Guide/accessibility tests.
- **Consequence:** keyboard/assistive users can lose controls mid-operation and
  Reduce Motion does not do what it says.
- **Acceptance:** suspend timed dismissal while focus/AT interaction is inside,
  honor reduced motion for every Player overlay, add selected-track focus and
  rectangle/dense-semantics tests.
- **Why P1:** timed loss of focused controls and an ineffective advertised
  motion preference affect core Player accessibility in normal use.
- **Machine:** Mac/CI; Windows keyboard/screen-reader confirmation.
- **Suggested implementation model:** Sol Medium.
- **Independent review:** yes; focus/timer behavior needs an accessibility-aware
  regression review.

### 7. Bind packaging claims to verified artifacts

- **Classifications / priority:** PARTIAL, P1.
- **Evidence:** package can attest the patched engine without inspecting the
  built engine; package checks run only inside the narrow engine rebuild gate.
- **Owner:** Windows package script and CI.
- **Consequence:** a green or apparently well-proven package can fail the DComp
  marker at launch and carry false build provenance.
- **Acceptance:** deterministic engine identity checked before BUILD-INFO,
  stock-engine negative test, package-only CI ownership, successful exact-head
  artifact with manifest and hash.
- **Why P1:** public packages must not carry false runtime provenance or bypass
  their own package verification when only packaging changes.
- **Machine:** Windows CI.
- **Suggested implementation model:** Sol High.
- **Independent review:** yes; build provenance and CI gating are release trust
  boundaries.

### 8. Execute exact-commit Windows and public-release gates

- **Classifications / priority:** NEEDS EVIDENCE/BLOCKED BY DECISION, P0.
- **Evidence:** no physical acceptance, exact-head patched artifact, complete
  notice manifest, project mirror, signing, or release channel.
- **Owner:** Windows acceptance operator, release engineering, project owner,
  and independent legal reviewer.
- **Consequence:** support, compatibility, package trust, and redistribution
  claims cannot be made safely.
- **Acceptance:** complete the authoritative physical campaign at the target
  commit; clean-system package launch; complete applicable notices and approval;
  immutable project mirror; signing/publication/recovery policy.
- **Why P0:** supported beta/public claims require a working exact package;
  redistribution and trust decisions cannot be inferred from source compilation.
- **Machine:** physical/clean/disposable Windows plus release infrastructure;
  legal review.
- **Suggested implementation model:** Sol High for engineering; named human
  release/legal owners for decisions and approval.
- **Independent review:** yes; physical evidence, dependency obligations, and
  publication trust require independent sign-off.

## Verification and CI/package evidence

Commands run from the clean `flutter-mvp` worktree:

```text
git fetch origin --prune
git switch flutter-mvp
git pull --ff-only
git status --short --branch
git rev-parse HEAD
git log --oneline --decorate -40
<pinned-flutter>/bin/dart format --output=none --set-exit-if-changed .
<pinned-flutter>/bin/flutter analyze
<pinned-flutter>/bin/flutter test
<pinned-flutter>/bin/flutter build macos
git diff --check
```

Results against the unchanged audit-start source/test tree:

- formatting: 61 files, 0 changed;
- analysis: no issues;
- tests: 278 passed;
- macOS release build: succeeded (50.3 MB application bundle);
- exact-head public CI run `32589006254`: Dart, macOS/goldens, Windows UI,
  pinned-libmpv stock-engine C++/CMake build succeeded;
- exact-head patched-engine job: skipped;
- exact-head artifacts: zero;
- physical Windows evidence directory: absent and acceptance document stated
  “not yet executed”.

The local build proves macOS UI feasibility, not playback. The live CI proves
the exact source tree compiles on Windows, not that patched-engine native video,
HDR, audio, fullscreen, or packaging works on physical hardware.

## Audit limitations

- No Plex credential, real account, private server, or media was used.
- No physical Windows, HDR display, gamepad, screen reader, clean package host,
  disposable Vulkan VM, or long soak was available.
- Upstream was inspected from the immutable ref; its dirty local worktree was
  not modified or trusted.
- The screenshots are version/viewport uncertain and private-data-bearing, so
  only state/composition was used.
- Legal obligations were not interpreted; the engineering notice mismatch is
  a release gate requiring independent review.
- The review-context cache was stale and was not refreshed because the allowed
  write scope was limited to audit documentation.

An independent adversarial review of this audit was completed and adjudicated.
Independent review remains specifically recommended for implementation of the
PMS token boundary, transaction/credential safety, package provenance, native
notice inventory, and the final physical Windows acceptance record.
