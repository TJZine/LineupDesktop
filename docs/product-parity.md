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

**Owner feedback re-adjudication:** 2026-08-23. Product-completeness priority
now precedes public-release engineering. The owner reports successful surface
use of the Windows native Player, Classic PiP/Overlay video, and fullscreen;
the exact commit, machine, package, and deeper scenario matrix were not captured
as durable evidence.

**Core-remediation update:** 2026-08-23. Commits after the audit-start baseline
deterministically close the PMS credential, large-library scan, generated-edit,
state transaction/recovery, structured diagnostics, sequential multi-part, and
Player focus/motion findings described below. The original audit date, host,
source census, command results, CI evidence, and physical-evidence limits remain
the evidence boundaries of the audit rather than evidence for these later
commits.

This is the authoritative current product-parity record. The classifications
in [Portable UI Parity](ui-parity.md) remain historical evidence for their
named campaigns; they do not override this audit. Current source and observed
evidence outrank older documentation.

## Executive conclusion

- **Replatform:** **PROVISIONAL, WITH OWNER-OBSERVED WINDOWS SURFACE SMOKE**.
  The Flutter product spine, responsive Guide, native boundary, and ordinary
  product-completeness findings in this remediation batch are implemented and
  deterministically tested. The owner has personally observed native Player,
  PiP/Overlay, and fullscreen working at a surface level. Deeper exact-commit
  Windows/package acceptance remains unrecorded.
- **Core daily-use Lineup parity:** source-level workflow coverage is broad.
  Separate runtime PMS credentials, generated-channel edits, bounded library
  scans, state recovery/transactions, sequential parts, structured diagnostics,
  and Player focus/motion behavior are now closed in deterministic tests.
  Alternate media versions, profile-token compensation, and compatibility-depth
  evidence remain P2.
- **Private beta:** **NOT YET CLAIMED**. This batch's audited P0/P1 application
  findings are implemented and deterministically tested. Physical and package
  acceptance remain separately gated while the product is still pre-MVP.
- **First public Windows release:** **NOT READY**. Physical acceptance, package
  engine attestation, package CI coverage, native notice/legal review,
  project-controlled runtime mirroring, signing/trust, and a release channel
  remain open.
- **Dominant next mode:** useful parity and Desktop product closure first;
  representative Windows media-depth validation second; package/public-release
  hardening last.

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

Priority now means implementation sequence for the owner's current objective:

- **P0:** blocks ordinary product use or crosses a live credential/data-safety
  boundary now.
- **P1:** materially incomplete correctness, reliability, UX, or accessibility
  in ordinary Desktop use.
- **P2:** advanced workflow, compatibility-depth proof, or a product decision
  that does not justify delaying core completion.
- **P3:** optional polish or deliberately deferred packaging, legal, signing,
  publication, and other public-release engineering.

Release gates remain explicit in the evidence register and public-release
conclusion even when their current implementation priority is P3. Priority is
therefore not a claim that release work is unnecessary; it records when the
owner wants it done. Matrix counts are capability rows, not counts of
independent root blockers.

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
| Per-server PMS credential | `/resources` supplies a distinct private `accessToken` for each PMS and all PMS requests use it | The separate PMS-issued credential remains in private runtime server scope and is used for probes, libraries, artwork, playback, and one bounded same-server authorization refresh; Plex.tv/Home credentials remain cloud-only | PARITY | — | HIGH | `lib/plex/plex_client.dart`; `lib/app/lineup_controller.dart`; distinct-token transport/controller/coordinator tests | Live disposable managed/shared smoke remains P2 evidence |
| Local HTTP server reachability | Allows local HTTP only where platform policy permits it; otherwise prefers HTTPS/relay | A secure-only policy rejects every non-HTTPS resource connection, including HTTP-only LAN servers | BLOCKED BY DECISION | P2 | HIGH | Upstream mixed-content/discovery policy; `lib/plex/plex_client.dart` | Decide whether local-HTTP compatibility belongs in supported scope |
| Connection facts and warnings | Auth/access/unreachable, relay/local HTTP, slow/very slow | Direct local/remote/relay and measured latency are shown; rich health/warning taxonomy is narrower | PARTIAL | P2 | HIGH | Upstream `ServerSelectListView.ts`; `lib/app/onboarding_view.dart` | Server UI |
| Audio onboarding | Receiver/TV choice, DTS intent, direct-play fallback | Truthfully confirms OS-selected output; libmpv decodes supported tracks to the system output without making passthrough a playback prerequisite | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | Upstream `AudioSetupScreen.ts`; native options; `docs/architecture.md`; `docs/user-guide.md` | Preserve decode-to-PCM default; expose output/passthrough only for a proven user need |

**PMS credential ownership:** linking and Plex Home selection produce a Plex.tv
account/profile credential used only with Plex.tv. Resource discovery returns a
separate opaque credential for each PMS. Desktop retains it only in private
runtime server scope and routes that server's probes, libraries, artwork,
and playback headers through it. A recognized PMS authorization
failure coalesces one current-profile resource refresh and retries the same
server once; stale, cancelled, logged-out, or superseded work cannot install the
result. Distinct synthetic credentials deterministically cover the full boundary
without placing credentials in public facts, durable state, URLs, or diagnostics.

### Channel Setup, authoring, persistence, and scheduling

| Capability | Upstream behavior/reference | Current Desktop behavior | Classification | Priority | Confidence | Evidence | Owner / next action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Library discovery/selection | Movie/show selection with counts and recovery | Responsive cards, Select All/Clear All, cancel/server recovery, and validation, but no item counts or per-library recovery detail | PARTIAL | P2 | HIGH | `lib/app/channel_setup_view.dart`; UI tests; screenshots `00-16-12` | Channel Setup: restore decision-useful counts/recovery detail |
| Library scan/planning scale and cancellation | Bounded facet/planning snapshots, explicit recovery, progress, and cancellation | Up to four selected libraries page concurrently with one page per library in flight and a 1,000-page bound while preserving deterministic order; page/item progress, active cancellation, stale rejection, retry, and distinct empty/unsupported/transient states are tested | PARITY | — | HIGH | `lib/app/lineup_controller.dart`; `lib/plex/plex_client.dart`; transport/controller/UI scale tests | Live PMS scale remains P2 evidence |
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
| Editing generated channels | Upstream does not expose the hidden CRUD service as normal UI | Generated, filtered-library, playlist, and mixed sources are read-only; metadata-only edits preserve exact source, generated identity, and scheduling fields | DESKTOP-ENHANCED | — | HIGH | `lib/app/lineup_shell.dart`; UI and persistence round-trip tests | No conversion workflow is needed |
| Delete channel | No normal upstream editor | Confirmed deletion, rollback, and focus restoration | DESKTOP-ENHANCED | — | HIGH | `lib/app/lineup_shell.dart`; UI tests | Channels |
| Whole-state save transactions | Serialized persistence and scoped state owners | One controller queue serializes mutation, snapshot, save, commit, and rollback across state domains; delayed/failing cross-domain races are deterministic | DESKTOP-ENHANCED | — | HIGH | `lib/app/lineup_controller.dart`; cross-domain controller tests | Persistence |
| Corrupt/transient state recovery | Startup distinguishes invalid/quarantined state | Malformed or schema-invalid JSON is moved aside and starts empty with a dismissible banner; missing state starts empty, while transient reads and quarantine failures stop startup without replacing data | PARITY | — | HIGH | `lib/persistence/app_store.dart`; store/controller/app tests | Physical app-data smoke remains P2 evidence |
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
| Native PiP/overlay video | Real upstream video visible in supplied capture | Flutter apertures and rectangle forwarding are implemented; owner reports Player/PiP/Overlay working at surface level, without a durable exact-commit capture | NEEDS EVIDENCE | P2 | MEDIUM | Owner report 2026-08-23; `lib/playback/native_video_surface.dart`; transparent goldens; `docs/windows-native-validation.md` | Later acceptance: record moving frame, resize, overlay, and teardown at the target commit |

### Player, streaming, tracks, OSD, and input

| Capability | Upstream behavior/reference | Current Desktop behavior | Classification | Priority | Confidence | Evidence | Owner / next action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Single playback owner | HTML5 player/recovery owners | One `PlayerCoordinator`, one native player, generations and serialized tune operations | PARITY | — | HIGH | `lib/playback/player_coordinator.dart`; coordinator tests | Playback |
| Format-open original-stream playback | Browser/webOS scores codecs, containers, audio, subtitles, and HDR before playback | Production sends the original PMS part to pinned libmpv with no application codec/container/HDR allowlist; libmpv/FFmpeg owns demux, video/audio decode, PCM conversion, rendering, hardware-decode attempts, and tone mapping | DESKTOP-ENHANCED | — | HIGH | `lib/app/lineup_controller.dart`; `windows/runner/native_player.cpp`; `docs/architecture.md` | Preserve native-first ownership; never promise literally every file without bounded evidence |
| Multi-part media playback | Plays every sequential part of a Plex media item | The selected first media version retains every ordered part and continues them under one Flutter-owned tune and distinct native-load generations | PARITY | — | HIGH | Plex parser/transport and Player coordinator tests cover known/unknown timing, seek, natural completion, stale events, and replacement | Playback |
| Multiple media-version selection | Scores/selects among alternate Plex `Media` versions | Parser retains only the first `Media`; libmpv openness lowers codec urgency, but users cannot choose edition/quality/version | MISSING | P2 | HIGH | `lib/plex/plex_client.dart`; no multi-version model/UI fixture | Define default/chooser behavior before implementing a version inventory |
| Server remux/transcode fallback | HLS when browser/container/codec/resolution/subtitle/HDR policy requires it | Production intentionally uses unrestricted native Direct Play and has no remux/transcode implementation or remote-quality consumer | INTENTIONALLY OMITTED | — | HIGH | `lib/app/lineup_controller.dart`; `docs/architecture.md` | Add only for an accepted bandwidth policy or demonstrated libmpv failure; do not recreate browser fallback by default |
| Remote quality selection | User transcode tiers applied to Plex resolver | No production transcode/quality consumer | MISSING | P2 | HIGH | Upstream `transcodeQuality.ts`; no Desktop consumer | Add only with real transcode path |
| Native HDR decode/output/tone mapping | Browser policy chooses Direct/HDR10/HLS fallback | libmpv accepts original HDR-family streams and owns decode/render/tone mapping; owner reports surface playback working, but representative HDR-output evidence is not recorded | NEEDS EVIDENCE | P2 | MEDIUM | Owner report 2026-08-23; native telemetry/options; `docs/architecture.md`; Windows acceptance plan | Later representative HDR/DV display matrix; add server fallback only for an observed failure class |
| Load/retry surface and resource cleanup | Typed retry/reload and diagnostics | Recoverable error overlay, same-path retry, stale-load rejection, and native stop ownership | PARITY | — | HIGH | `lib/playback/player_coordinator.dart`; tests | Compatibility fallback is classified separately above |
| Tune/replacement lifetime | Stale-operation/currentness ownership | Tune generations, serialized operations, and native stop on scope change | PARITY | — | HIGH | coordinator/native source and tests | Physical replacement stress still required |
| OSD hierarchy | Title/status, progress/buffer, up-next, tracks, sleep | Clean bottom gradient with channel/program/status/telemetry/progress/actions | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | `lib/playback/player_view.dart`; OSD golden; screenshot `00-25-11` | Player UI |
| OSD accessibility-focus timeout | Upstream overlay policy preserves usable focus | Keyboard descendant focus suspends OSD dismissal; valid departure restarts the full timeout and presentation identity rejects stale callbacks | PARITY | — | HIGH | `lib/playback/player_coordinator.dart`; coordinator and widget focus/timer tests | Physical Windows AT remains P2 evidence |
| Reduce Motion in player overlays | Upstream/CSS honor reduced motion | The effective Flutter Reduce Motion setting makes Player switcher duration and reverse duration zero; normal motion remains 350 ms | PARITY | — | HIGH | `lib/playback/player_view.dart`; root propagation and Player widget tests | Player UI |
| Mini Guide | Five centered rows, wrap/page/tune/full Guide | Five-row full-width responsive shelf with progress/next/tuned/focus and short-window scrolling | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | coordinator/view tests; mini-guide golden; screenshot `00-27-07` | Player UI |
| Mini Guide accessibility timeout | Timed upstream overlay | Keyboard descendant focus suspends the eight-second timer; departure restarts it and stale replaced-overlay focus callbacks are ignored | PARITY | — | HIGH | coordinator and real widget traversal/timer tests | Physical Windows AT remains P2 evidence |
| Audio track selection | Immediate track switch and selected state | Truthful native audio rail and immediate selection | PARITY | — | HIGH | native track model; `lib/playback/player_view.dart`; tests | Playback |
| Subtitle track selection/off | Grouped delivery modes and immediate selection | Native subtitle list plus Off; no false delivery mode | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | `lib/playback/player_view.dart`; long-list tests; screenshot `00-25-21` | Playback |
| Track selector initial focus | Selected entry is the highlighted primary row | Audio and subtitle rails initially focus the selected track; subtitle Off receives focus only when none is selected | PARITY | — | HIGH | `lib/playback/player_view.dart`; widget focus tests | Player UI |
| Native subtitle format/delivery breadth | Off/Direct/Standard/Full, browser extraction/burn-in and recovery | libmpv-visible embedded tracks are selected natively and require no browser burn-in mode; Plex-managed external sidecars and representative text/image subtitle breadth are not yet explicitly proved | NEEDS EVIDENCE | P2 | MEDIUM | `lib/plex/plex_client.dart`; native `track-list`/`sid`; Player tests; owner broad-compatibility feedback | Validate SRT/ASS/PGS/VobSub and Plex external sidecars; implement explicit sidecar loading only if the evidence exposes a gap |
| Preferred/forced subtitle autoselection | Stored language and forced policy affect selection | Native tracks expose current runtime state only; Desktop does not parse or retain preferred/forced Plex facts and has no autoselection consumer | MISSING | P2 | HIGH | upstream settings; native track model | Define the required native facts, then add epoch-safe selection |
| Lossless/surround audio decode | Settings drive passthrough or alternate browser-compatible track | Native playback does not gate decode on passthrough; pinned libmpv/FFmpeg decodes supported DTS-family, TrueHD, and other tracks and sends the result through the system-selected output, normally as PCM | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | native libmpv options; `docs/windows-runtime.md`; `docs/architecture.md` | Validate representative TrueHD/DTS/DTS-HD tracks; add passthrough only as a separate optional feature |
| Sleep timer | Off/15/30/60/120 and one-minute warning | Off/30/60/90 cycle; stop failure surfaces safely | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | `lib/playback/player_coordinator.dart`; tests | Optional duration/warning parity P3 |
| Rich Now Playing details | Standard/cinematic details, synopsis, art, cast, badges | Guide carries rich details; Player has compact OSD only | MISSING | P2 | HIGH | upstream Now Playing coordinator; no Desktop surface; screenshot `00-26-12` | Product decision: dedicated player details or Guide-as-replacement |
| Fullscreen | Player toggle and platform placement | F/F11/button and native window-placement snapshot/rollback/restore; owner reports surface behavior working | NEEDS EVIDENCE | P2 | MEDIUM | Owner report 2026-08-23; Dart/C++ source and tests; no durable exact-commit report | Later DPI/move/minimize/repetition campaign |
| Channel entry/CH navigation | Digits and CH± remote behaviors | Digit buffer, PageUp/PageDown channels, explicit error, mini Guide paging | DESKTOP-ENHANCED | — | HIGH | player source/tests | Input |
| Keyboard/media keys | TV remote/playback key map | Desktop keys, numpad, media transport, Guide/settings shortcuts | DESKTOP-ENHANCED | — | HIGH | `lib/app/lineup_shell.dart`; `lib/playback/player_view.dart`; tests | Input |
| Cursor auto-hide and pointer wake | Timed pointer hiding over immersive playback | Desktop schedules cursor hiding while playing and restores it on pointer activity | PARITY | — | HIGH | `lib/playback/player_coordinator.dart`; `lib/playback/player_view.dart`; tests | Player input |
| Gamepad | webOS/browser remote mapping | No current Flutter/Windows gamepad owner or physical evidence | INTENTIONALLY OMITTED | — | HIGH | upstream navigation; current tree census | Re-establish only from a supported Desktop input contract |

### Settings

| Capability | Upstream behavior/reference | Current Desktop behavior | Classification | Priority | Confidence | Evidence | Owner / next action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DTS Passthrough setting | Consumed by capability/audio policy | Hidden because native decode-to-system-output works without passthrough; passthrough is not a compatibility prerequisite | INTENTIONALLY OMITTED | — | HIGH | upstream settings/resolver; Desktop native options and architecture | Optional only after a concrete bitstream-output requirement and native device contract |
| Direct Play Audio Fallback setting | Consumed by browser-compatible resolver | Hidden because libmpv native decode is the default compatibility path; no demonstrated input requires automatic alternate-track selection | INTENTIONALLY OMITTED | — | HIGH | upstream resolver; Desktop playback wiring/native architecture | Revisit only for a reproducible decode/output failure class |
| Subtitle Mode setting | Controls browser/server extraction, burn-in, and transcode | Hidden because native libmpv track selection is the default Desktop model | INTENTIONALLY OMITTED | — | HIGH | upstream settings; Desktop track rail/native seam | Add a narrower fallback control only for a demonstrated sidecar/rendering failure |
| Preferred Subtitle Language | Applied automatically | Manual track selection only | MISSING | P2 | HIGH | upstream settings; Desktop native track projection | Add with autoselection owner |
| Prefer Forced Subtitles | Applied by descriptor/recovery | No forced preference or parsed/retained forced fact exists; native tracks report current runtime state only | MISSING | P2 | HIGH | upstream settings; Desktop native track seam | Add with the autoselection capability, not as dead preference state |
| Keep Playback Running in Settings | Optional on webOS | Desktop coordinator always persists across management routes | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | `lib/app/lineup_shell.dart` | Fixed Desktop behavior |
| HDR Fallback setting | Controls browser/server compatibility/transcode | Hidden because native libmpv decode/tone mapping is primary; no observed class currently justifies a user fallback switch | INTENTIONALLY OMITTED | — | HIGH | upstream settings/resolver; native architecture; Windows plan | Revisit only from representative HDR evidence |
| Transcode Quality setting | Applies bitrate/resolution tier | No production transcode consumer | MISSING | P2 | HIGH | upstream config; Desktop playback wiring | Add with transcode path |
| Transcode Compat Mode | Changes browser/server transcode parameters | No equivalent consumer because native Direct Play is primary | INTENTIONALLY OMITTED | — | HIGH | upstream settings/resolver; native architecture | Add only with an accepted server-transcode capability and demonstrated need |
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
| Reduce Motion | Upstream honors platform preference broadly | The explicit Desktop setting flows through root, Guide, management, and Player transition owners | PARITY | — | HIGH | settings/app/Guide/Player source and deterministic tests | Accessibility |
| Large Focus Indicators | No equivalent visible upstream preference | Desktop-wide semantic focus-border role | DESKTOP-ENHANCED | — | HIGH | theme/settings tests | Accessibility |
| Record Redacted Diagnostics | Upstream raw developer logging | Desktop opt-in bounded session support log | DESKTOP-ENHANCED | — | HIGH | diagnostics/settings tests | Support |
| Switch profile/server actions | Separate TV routes | Direct Settings actions with scoped state retention | DESKTOP-ENHANCED | — | HIGH | `lib/app/lineup_shell.dart`; controller tests | Settings |

### Desktop platform, diagnostics, packaging, and release

| Capability | Upstream behavior/reference | Current Desktop behavior | Classification | Priority | Confidence | Evidence | Owner / next action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Responsive management shell | Fixed 1920×1080 TV composition | Pointer/Tab NavigationRail and category layouts across compact to 4K | DESKTOP-ENHANCED | — | HIGH | shell/UI tests; settings golden | Flutter UI |
| Five theme system | Same named theme intent | Semantic role-based themes with contrast tests | PARITY | — | HIGH | `lib/ui/app_theme.dart`; theme tests | UI |
| Accessibility semantics | ARIA/modal/live/focus behaviors | Flutter semantics, focus restoration, live errors/progress, timed-overlay focus retention, selected-track focus, and reduced-motion coverage are deterministically tested | PARITY | — | HIGH | UI/Guide/Player source and semantics/focus/motion tests | Physical Windows screen-reader/AT remains P2 evidence |
| Credential-safe diagnostics claim | Redacted logging/diagnostic tooling | Producers store only bounded structured facts from a finite allowlist; arbitrary exception/native messages are excluded and fixed messages retain defense-in-depth redaction | DESKTOP-ENHANCED | — | HIGH | `lib/diagnostics/diagnostics.dart`; opaque-sentinel tests across producers | Continue review before sharing private activity context |
| Durable support-bundle export | Not a normal upstream product surface | Historical Electron exported double-scanned bounded artifacts; Flutter only displays session entries | MISSING | P2 | HIGH | Electron support exporter/tests; Desktop diagnostics/shell | Support: safe export without Electron architecture |
| State file atomicity | Local client storage | Unique temp, flushed write, rename, serialized physical writes | DESKTOP-ENHANCED | — | HIGH | `lib/persistence/app_store.dart`; tests | Persistence |
| Local media-metadata privacy | Browser-local channel state contains library facts | Desktop writes channel titles, summaries, ratings, genres, artwork paths, and codec facts to plaintext `state.json`; tokens remain separate in secure storage | PARTIAL | P2 | HIGH | `lib/channels/channel.dart`; `lib/persistence/app_store.dart` | Document location/deletion/threat model and decide whether to minimize/protect metadata |
| Secure credentials | Client-side tokens | Platform secure storage, separate account/profile keys, no token in JSON | DESKTOP-ENHANCED | — | HIGH | `lib/persistence/app_store.dart`; controller tests | Credentials |
| macOS UI development | Not applicable to webOS | Exact toolchain analysis/tests/build pass; playback explicitly unsupported | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | local 2026-08-23 commands; macOS backend tests | Supported only as UI development |
| Windows native player implementation | Not applicable to webOS HTML5 | Narrow C++/libmpv owner, generation filtering, DComp marker, bounds/fullscreen; owner reports successful surface playback | NEEDS EVIDENCE | P2 | MEDIUM | Owner report 2026-08-23; `windows/runner/native_player.cpp`; Dart tests; CI compile | Preserve as implemented; run deeper exact-commit acceptance after core completeness |
| Native rectangle contract | Browser owns video element | Flutter calculates global bounds/DPR and zeroes on dispose; owner-observed PiP/Overlay works, while fakes still do not assert exact values | NEEDS EVIDENCE | P2 | MEDIUM | Owner report 2026-08-23; `lib/playback/native_video_surface.dart`; no recording fake | Add cheap Dart geometry-contract regression; defer broad physical geometry matrix |
| Exact-HEAD CI | Upstream webOS CI is comprehensive for its platform | Platform-adapted exact source checks passed Dart, macOS build/goldens, Windows UI and stock-engine compile | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | GitHub run `32589006254`; local 278-test pass; patched job skipped | CI |
| Patched-engine CI artifact | Not applicable upstream | Exact-HEAD expensive engine job skipped and run produced zero artifacts | NEEDS EVIDENCE | P3 | HIGH | `.github/workflows/ci.yml`; run/job/artifact metadata | Deferred release engineering: force a manual exact-commit engine/package build when packaging becomes the active phase |
| Package engine provenance | Not applicable upstream | Package validates source/libmpv but unconditionally attests patched engine without verifying built `flutter_windows.dll` | PARTIAL | P3 | HIGH | `tool/windows/package.ps1`; native marker enforcement | Deferred packaging: bind attestation to the actual engine artifact |
| Package CI ownership | Not applicable upstream | Package tests/upload run only under narrow engine-input detector; package-only changes can stay green without package proof | PARTIAL | P3 | HIGH | `.github/workflows/ci.yml` | Deferred packaging: split cheap package verification from engine rebuild |
| Portable runtime provenance | No comparable webOS product capability | Windows distribution pins Flutter/engine/depot_tools/libmpv inputs and hashes and checks source/runtime facts | INTENTIONAL DESKTOP ADAPTATION | — | HIGH | development/runtime docs; build metadata; scripts | Desktop release engineering strength |
| Native notice completeness | Not applicable upstream | Package verifies four media-runtime license inputs and includes app/engine provenance texts, but lacks a complete transitive dependency/source-notice manifest for monolithic libmpv | BLOCKED BY DECISION | P3 | HIGH | `docs/windows-runtime.md`; `tool/windows/package.ps1`; `third_party/libmpv` | Deferred legal/release phase: complete manifest and independent review |
| Runtime mirror | Not applicable upstream | Third-party binary source is hash-pinned, but project-controlled immutable mirror is required by current release policy | BLOCKED BY DECISION | P3 | HIGH | `docs/windows-runtime.md`; build metadata | Deferred release owner |
| Signing/public release channel | Not applicable upstream | No signing, supported channel, installer, updater, or release automation | BLOCKED BY DECISION | P3 | HIGH | README/user guide; repo census | Deferred release decision: portable-only scope, signing, and publication owner |
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
confirmation are effective improvements. The pre-setup inventory now bounds and
concurrently pages selected libraries, reports page/item progress, supports
cancellation, and distinguishes empty, unsupported, and transient failure.
Library cards still omit counts, and preview/review communicate less
source-specific status. Final commit progress remains deliberately indeterminate
because that save is atomic and expected to be short. The editor now keeps
generated and otherwise non-lossless sources read-only while allowing metadata
changes without changing provenance.

### Guide

The current Guide preserves the upstream hierarchy while distinguishing focus,
selection, tuned channel, airing state, and past state more clearly. Committed
1280×720 goldens and responsive tests are strong Flutter evidence. They do not
prove a real Windows video layer. Vertical work is bounded; worst-case dense
horizontal program and semantics work is not yet profiled.

### Player, OSD, and mini Guide

The compact bottom OSD and five-row top mini Guide are coherent Desktop
adaptations, with direct goldens and strong input tests. Timed OSD and mini Guide
dismissal now suspends for keyboard descendant focus and rejects stale overlay
callbacks; Player transitions honor Reduce Motion, and playback-options rails
initially focus the selected native track. These are deterministic Flutter
claims, not physical screen-reader support. Browser subtitle delivery modes are
not a Desktop requirement; the remaining P2 question is whether representative
native text/image formats and Plex-managed external sidecars all reach libmpv.
A cinematic rich-details Player surface is genuinely absent but P2.

### Settings

The category rail/detail layout, extended Guide choices, accessibility controls,
account actions, and redacted-diagnostics preference are Desktop value. Every
visible Desktop preference is persisted and has a current consumer. Missing
upstream media settings are not superficial Settings gaps: most encode
browser/webOS compatibility policy that native libmpv does not need. Transcode
quality, preferred/forced subtitle selection, and optional passthrough should
appear only with concrete product requirements and working consumers.

All preference changes apply immediately through one controller-owned state
transaction. The Settings UI disables further edits during that save and
reports a failure while retaining the previous value. One queue serializes
snapshot, save, commit, and rollback across state domains. Restore normalizes
invalid enum/numeric values.

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
| Reduce motion | Off; Boolean | Durable; root, management, Guide, and Player transitions |
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
dialogs, and track rails. Selected-track initial focus and timed Player-overlay
focus retention are deterministically covered. Browser-style gamepad input is
intentionally outside scope; no physical Windows controller claim exists.

### Accessibility

Flutter semantics, modal/live-state labels, focus visibility, the large-focus
preference, timed-overlay keyboard focus retention, selected-track focus,
Player Reduce Motion, and bounded vertical Guide construction are meaningful
and deterministically tested. Dense horizontal semantics still need measurement,
and a physical Windows keyboard/screen-reader pass is required before any
assistive-technology support claim.

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

The matrix contains **147 capabilities**:

- 47 **PARITY**;
- 27 **DESKTOP-ENHANCED**;
- 14 **INTENTIONAL DESKTOP ADAPTATION**;
- 16 **PARTIAL**;
- 13 **MISSING**;
- 9 **INTENTIONALLY OMITTED**;
- 6 **NOT APPLICABLE**;
- 8 **NEEDS EVIDENCE**; and
- 7 **BLOCKED BY DECISION**.

The actionable/decision rows contain 0 P0, 0 P1, 33 P2, and 11 P3
dispositions. Counts are literal matrix rows, not a quality-weighted percentage.

- **Core daily-use parity:** the audited P0/P1 application gaps are implemented
  and deterministically tested. Owner-observed native playback substantially
  improves confidence in the surface implementation, while exact-commit
  physical and live-PMS evidence remain separate P2 work.
- **Total upstream coverage:** every material workflow and visible setting has
  a disposition; browser/webOS workarounds are not assumed to be Desktop needs.
- **Desktop media value:** original-stream, format-open libmpv playback and
  decode-to-system-output replace browser allowlists, burn-in defaults, and
  passthrough-as-compatibility logic.
- **Private beta:** not yet claimed. This batch's audited P0/P1 application
  findings are implemented and deterministically tested; physical and package
  acceptance remain separately gated while the product is still pre-MVP.
- **Public release:** not ready; exact-package evidence, notices/legal, mirror,
  signing, and release-channel decisions remain deliberately deferred.

## Former P1 re-adjudication

Every row that was P1 before the owner's Desktop/media feedback was re-read
against current Dart/C++ ownership:

| Former P1 finding | Current disposition | Reason |
| --- | --- | --- |
| Library scan/planning scale and cancellation | Closed deterministically | Bounded paging, concurrency, progress, cancellation, stale rejection, and distinct recovery states are tested; live scale remains P2 evidence. |
| Editing generated channels | Closed deterministically | Non-lossless sources are read-only and metadata saves preserve exact source and generated identity. |
| Whole-state save transactions | Closed deterministically | One controller queue covers cross-domain snapshot/save/commit/rollback races. |
| Corrupt/transient state recovery | Closed deterministically | Malformed or schema-invalid JSON is quarantined; transient and quarantine failures stop startup, while recovery is visible. |
| Media-version/part selection | Split; multi-part closed | Ordered parts of the selected first version continue deterministically; alternate-version choice remains P2. |
| Direct Stream/transcode fallback | Intentionally omitted | Native libmpv Direct Play is intentionally format-open. Add server fallback only for an accepted bandwidth policy or demonstrated failures. |
| HDR compatibility/fallback | Move to P2 evidence | Native decode/tone mapping is the primary design; prove representative output instead of importing browser fallback policy. |
| OSD accessibility-focus timeout | Closed deterministically | OSD and mini Guide timers suspend for keyboard descendant focus and reject stale callbacks. |
| Reduce Motion in Player overlays | Closed deterministically | Effective Reduce Motion makes Player transition durations zero. |
| Subtitle mode/delivery/recovery | Move to P2 evidence | Browser extract/burn-in modes are not native parity; explicitly validate native text/image tracks and Plex sidecars. |
| Reduce Motion setting coverage | Closed deterministically | Root propagation and Player widget tests cover the setting's current consumers. |
| Accessibility semantics | Closed deterministically | Timed focus retention, selected-track focus, live semantics, and reduced transitions are tested; physical AT remains P2. |
| Credential-safe diagnostics | Closed deterministically | A finite bounded context allowlist replaces arbitrary producer strings, with opaque-sentinel tests. |
| Native rectangle contract | Move to P2 evidence | Owner-observed PiP/Overlay works; a cheap deterministic geometry test remains useful, while broad physical proof can wait. |
| Package engine provenance | Move to P3 release work | Important before distribution, not before product feature completion. |
| Package CI ownership | Move to P3 release work | Important before distribution, not before product feature completion. |

## Intentional adaptations and omissions

### Intentional Desktop adaptations

- The Windows player is native-first and format-open: it sends the original PMS
  part to libmpv without an application codec/container/HDR allowlist.
- Supported audio tracks are decoded through libmpv/FFmpeg to the
  system-selected output, normally PCM. Bitstream passthrough is optional, not
  a prerequisite for TrueHD or DTS-family playback.
- Native subtitle selection replaces browser text-track extraction and burn-in
  as the default path. Explicit sidecar loading is added only if evidence shows
  Plex-managed external tracks are missing.
- The player remains alive across management routes, so the upstream
  keep-playing toggle is unnecessary.
- Guide geometry, row density, past windows, OSD, mini Guide, Settings, and
  navigation adapt TV intent to resizable pointer/keyboard windows.
- macOS is a UI-development platform with an explicit unsupported player.

### Intentionally omitted upstream behavior

- DTS passthrough and direct-play audio fallback settings are hidden because
  decode-to-system-output is the working compatibility path.
- HDR fallback, transcode compatibility, and subtitle delivery-mode settings
  are hidden unless a representative failure or remote-quality requirement
  establishes a real consumer.
- Gamepad remains omitted without a supported Windows input contract.
- Aggressive preload and raw/subtitle debug logging are internal/developer
  policy, not normal Desktop settings.

### WebOS/browser-only or developer-only behavior

HTML5 video/Media Session, webOS relaunch/keepalive, visibility memory budgets,
raw remote-key aliases, browser codec allowlists, internal debug globals, EPG
storage debug flags, and browser subtitle extraction are not Desktop
requirements. Desktop independently implements cursor auto-hide as ordinary
pointer behavior. Upstream hidden channel CRUD/import/export services and stale
route tokens are not counted as reachable product capability.

### Obsolete Electron behavior intentionally removed

Chromium protocol delivery, renderer/main/preload/IPC ownership, browser
Gamepad polling, window-process workarounds, and latent channel import/export
code are not compatibility targets. Audio-device enumeration remains omitted
because system output is the current product contract.

### Desktop enhancements not present upstream

Custom channel management, 1,000-channel limits, additional variants, large
focus indicators, reduced motion, bounded user-visible diagnostics, responsive
management, secure credential storage, native Windows presentation, and
format-open libmpv playback are Desktop-specific value.

## Evidence-gap register

| Unknown | Why evidence is insufficient | Smallest proof | Environment | Product completeness | Public release |
| --- | --- | --- | --- | --- | --- |
| Live PMS authorization across owner, managed Home, and shared server | Separate runtime credentials and bounded refresh are covered with distinct synthetic sentinels, not a real disposable account/server matrix | Redacted live owner/managed/shared smoke at the exact tested commit | Mac/CI; Windows follow-up | P2 evidence | Blocks only a live-PMS support claim |
| Live large-library inventory/planning | Deterministic slow/error/scale fixtures cover bounds, progress, cancellation, retry, ordering, and recovery, but not a representative live PMS | Redacted live large-library scan with observed page/item progress, cancellation, retry, time, and memory | Live PMS; confirm Windows | P2 evidence | Blocks a broad live-library claim |
| Alternate media versions | Sequential parts of the selected first version are implemented and tested; no version inventory or chooser policy exists | Decide default/chooser behavior, then add a multi-version fixture and UI contract | Mac/CI | P2 | Blocks only version-selection claims |
| Physical state-file recovery | Malformed, transient, permission-shaped, and quarantine failures are deterministic tests, not app-data behavior on Windows | Exact-commit Windows app-data corruption and access-failure smoke without private state capture | Physical Windows | P2 evidence | Blocks a platform recovery claim |
| Native media breadth | Format-open source design and owner smoke do not establish every input; Plex external sidecars are not explicitly owned | Representative containers/video plus TrueHD, DTS/DTS-HD-to-PCM, SRT/ASS, PGS/VobSub, and Plex sidecar cases | Physical Windows | P2 after core work | Blocks only named compatibility claims |
| Server remux/transcode | No active consumer because native playback is unrestricted | Product decision; if accepted, one forced bandwidth/failure fixture proving resolver, cleanup, and playback | Mac/CI plus Windows | No unless requirement accepted | Blocks only a transcode/remote-quality claim |
| Native Player/PiP/Overlay/fullscreen depth | Owner reports surface success, but exact commit/machine/media/transition facts are not durably recorded | Record target commit and repeat resize, overlay, replacement, minimize, DPI, fullscreen, teardown | Physical Windows 10/11 | P2 after core work | Blocks a supported native claim |
| HDR/tone mapping/hardware decode | Native path and owner smoke exist, but output telemetry/visual result is not captured | Representative HDR10 plus DV/HLG when claimed, on named displays | Physical Windows HDR system | P2 | Blocks only named HDR claims |
| Native rectangle DPR/resize/dispose forwarding | Owner smoke supports viability; fakes ignore exact values | Recording fake plus one target-commit physical resize/DPI check | Mac test; Windows | P2 | Blocks broad geometry support claim |
| Physical keyboard/AT Player usability | Flutter focus/semantics tests keep OSD and mini Guide controls operable beyond timeouts, suppress reduced-motion transitions, and focus selected tracks; no physical AT session exists | Exact-commit Windows keyboard and screen-reader session across OSD, mini Guide, tracks, progress, loading, and errors | Physical Windows AT | P2 evidence | Blocks accessibility support claim |
| Dense 12-hour Guide semantics/performance | Vertical cardinality fixtures use long programs | Profile short-slot visible rows and record nodes/frame timings | Mac profile; confirm Windows | P2 unless slow | Blocks 12h/1,000 performance claim |
| Network loss and OS suspend/resume | Request recovery tests do not prove live-session recovery | Redacted tune/Guide session across network/server/sleep/minimize transitions | Physical Windows | P2 | Blocks broad reliability claim |
| Patched package and engine attestation | Exact-head expensive CI job skipped; package claim is not bound to built engine | Forced clean engine/package build, identity negative/positive test, launch, manifest, hash | Clean Windows systems | Deferred P3 | Blocks distribution |
| Native notice/legal completeness | Top-level texts do not prove transitive obligations | Dependency/license manifest, vendored hashes, independent legal approval | Release/legal review | Deferred P3 | Blocks distribution |
| Signing and publication trust | No selected signing/release channel | Signing identity and reproducible publication/recovery workflow | Release infrastructure | Deferred P3 | Blocks supported public release |

## Current implementation groups

### 1. Correct Plex credential ownership end to end

- **Status:** implemented and deterministically tested; former P0 closed.
- **Ownership:** the separate PMS-issued credential remains private and
  runtime-only, serves every request to that PMS, and refreshes the same server
  at most once after a recognized authorization failure. Plex.tv/Home
  credentials remain cloud-only.
- **Evidence:** distinct synthetic credentials cover discovery, probes,
  libraries, artwork, playback, refresh, cancellation, logout, and
  profile/server supersession without entering public state or diagnostics.
- **Independent review:** specifically recommended; this crosses a remote
  credential boundary.

### 2. Bound and cancel large-library setup planning

- **Status:** implemented and deterministically tested; former P1 closed.
- **Ownership:** the controller schedules bounded concurrent pagination,
  preserves deterministic order, exposes page/item progress, cancels stale
  scans, and distinguishes empty, unsupported, transient, and cancelled states.

### 3. Make channel and state edits transaction-safe

- **Status:** implemented and deterministically tested; former P1s closed.
- **Ownership:** non-lossless channel sources are read-only during metadata
  edits; one controller queue owns state snapshot/save/commit/rollback;
  malformed or schema-invalid state is quarantined and visibly reset, while
  transient or quarantine failures stop startup.
- **Independent review:** specifically recommended for the async persistence
  boundary.

### 4. Close diagnostic and credential-cleanup boundaries

- **Status:** structured diagnostics are implemented and deterministically
  tested; failed/cancelled profile-token compensation remains P2.
- **Ownership:** diagnostics retain only bounded allowlisted facts and never
  arbitrary exception/native message text. The separate secure-store
  compensation contract is intentionally not part of this batch.
- **Independent review:** specifically recommended for secret handling.

### 5. Close actual native-media product gaps

- **Status:** sequential parts of the selected first media version are
  implemented and deterministically tested; alternate-version choice, external
  subtitle proof, representative compatibility depth, and any accepted server
  fallback remain P2.
- **Ownership:** Flutter coordinates ordered native loads, known-boundary seeks,
  stale-event rejection, credential replacement, and one tune lifetime.
  Native libmpv remains direct-play-first and format-open, owning video/HDR,
  native subtitles, and TrueHD/DTS-family decode to system output, normally PCM
  when needed.
- **Excluded:** no browser codec allowlist, compulsory transcode/remux, subtitle
  burn-in framework, or passthrough decode gate was added.

### 6. Fix timed-overlay accessibility and motion

- **Status:** implemented and deterministically tested; former aggregate P1
  closed. Physical Windows screen-reader/AT behavior remains P2 evidence.
- **Ownership:** active OSD/mini Guide keyboard focus suspends dismissal,
  presentation identity rejects stale callbacks, Reduce Motion removes Player
  transition time, and selected tracks receive initial focus.

### 7. Deferred release engineering

- **Priority:** P3 by owner sequencing, while still mandatory before the
  corresponding distribution/support claim.
- **Scope:** bind package attestation to the actual engine, give package-only
  changes CI ownership, produce an exact-commit patched artifact, finish
  notices/legal review and runtime mirroring, and decide signing/publication.
- **Trigger:** begin after the application is feature-complete enough that the
  intended package and support surface are stable.
- **Independent review:** specifically recommended for provenance, dependency
  obligations, and final exact-commit acceptance.

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
- durable physical Windows evidence directory: absent. The owner separately
  reported 2026-08-23 surface success for native Player, PiP/Overlay, and
  fullscreen, without an exact commit/machine/package manifest.

The local build proves macOS UI feasibility, not playback. The live CI proves
the exact source tree compiles on Windows. The owner report is meaningful
surface evidence that native video and fullscreen work, but does not by itself
establish broad format/HDR/subtitle/audio, transition, or package support.

## Audit limitations

- No Plex credential, real account, private server, or media was used.
- The audit operator had no physical Windows, HDR display, gamepad, screen
  reader, clean package host, disposable Vulkan VM, or long soak. The owner
  supplied separate surface-level Windows observations without a durable
  exact-commit evidence bundle.
- Upstream was inspected from the immutable ref; its dirty local worktree was
  not modified or trusted.
- The screenshots are version/viewport uncertain and private-data-bearing, so
  only state/composition was used.
- Legal obligations were not interpreted; the engineering notice mismatch is
  a release gate requiring independent review.
- The review-context cache was refreshed after its stable architecture and
  development inputs changed; current source remained authoritative.

An independent adversarial review of this audit was completed and adjudicated.
Independent review remains specifically recommended for the implemented PMS
credential, persistence transaction/recovery, structured diagnostics, and
multi-part lifetime boundaries, plus the complete remediation diff. A separate
Windows specialist review remains appropriate when physical media/package
acceptance begins.
