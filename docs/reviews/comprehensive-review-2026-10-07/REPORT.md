# Comprehensive Lineup Desktop Review — 2026-10-07

## Scope and source identity

- Repository: the requested local LineupDesktop checkout.
- Branch: `codex/desktop-ui-second-pass`.
- Frozen review SHA: **`0382c131713174d9f8bced9d5b942855a99a6414`**.
- Review date: October 7, 2026, America/New_York.
- Mode: read-only review. No implementation, commits, pushes, PRs, packaging, or external person-directed messages.
- Authorized output: this report and REMEDIATION.md beside it; disposable synthetic probes and sanitized logs under ignored `build/review-probes/`.
- The two prerequisite plans have landed: setup controller/readiness and surfaces are in `f2eda950` / `b0175efb`; Player/Guide polish is in `74b82b36`, `a66f9724`, `d28a2f33`, and `c2e8bc41`; the tip records approved behavior. The plans' older “approved for implementation” headings are not evidence that the implementations are absent.
- Initial tracked worktree was clean. Existing unrelated untracked local configuration, design-review packets, test-slimming material, and Python cache were excluded and preserved.

**Concurrent-work qualification:** after the baseline gate, changes appeared in `lib/playback/player_view.dart` and `test/playback/player_view_test.dart`, adding Sleep-picker keyboard handling. None was authored by this review. They were left untouched and excluded. The independent reviewer inspected committed Player shortcut code while HEAD still identified the frozen SHA; the reviewed key paths are unchanged by that delta. Other probe owners' production inputs remained unchanged. At artifact completion, the concurrent work had been committed as `01bda7960431ba8d7448a69cceabfaeb9cf686d4` (`fix: keep sleep picker keyboard actions local`), advancing the checkout. This does not change the frozen review SHA. The full gate is evidence for the initial frozen tree, not a gate for that later commit. Sleep-picker keyboard work already underway is not a new remediation finding. Any approved implementation must reconcile against its actual starting tip.

### Read first and review inputs

The controller and bounded packets read AGENTS.md, all applicable .agents/project.md sections, docs/architecture.md, docs/user-guide.md, docs/desktop-ui-second-pass.md, .interface-design/system.md, docs/product-parity.md, docs/setup-reentry-startup-plan.md, docs/player-guide-polish-plan.md, docs/osd-autohide-and-collection-membership-plan.md, docs/guide-freshness-collection-investigation.md, and docs/windows-native-validation.md before evaluating their affected contracts. Deeper reads included docs/DEVELOPMENT.md, docs/windows-runtime.md, docs/windows-collaborative-acceptance-handoff.md, the relevant desktop design specification, README/documentation index, privacy/security guidance, and build/runtime notices.

Skills used: repo-production-review as the backbone; review-code and verify-code; the architecture, correctness, maintainability/AI-debt, tests/CI, security/privacy, build/release/supply-chain, ops/config, performance/concurrency/reliability, and docs/DX specialist rubrics; repo-review-evidence-calibration; repo-production-remediation-plan.

Read-only sidecars: setup; player/native; Plex/persistence/security; Studio/settings/shared controls; release/quality/docs; scheduler/builder; independent calibration. No nested delegation or implementation agents. The controller owned the census, integration of evidence, findings, and final artifacts. Sidecar execution evidence was inspected and calibrated; the calibration reviewer did not rerun probes.

Upstream Lineup was used only for response-order expectations and related behavioral context, including its `9eaf10b8` shuffle-order correction. It is not a compatibility or migration target.

## Repo profile and census

The census preceded delegation: **419 tracked files**, including 40 production Dart files, 51 tracked test/support files, 24 tool files, 24 Windows files, 28 macOS files, and 207 documentation files. Counts include support/assets in their directories; they are not test-case counts.

| Surface | Owners and boundaries reviewed |
| --- | --- |
| Composition | lib/main.dart and lib/app/lineup_app.dart compose store, Plex client, controller, native backend, shell, Guide and Player. Flutter/Dart owns all application and interaction policy. |
| Application/state | LineupController owns profile/server scopes, discovery, staged inventory, mutation eligibility, queued snapshot/save/publication, settings and credential ordering. Request, authorization, content, mutation and native-load identities have different obligations. |
| Authoring/schedules | lib/channels model, builder, resolver, scheduler and isolate worker; shared by Setup, Studio/Air Check, Guide and Player. |
| UI | Onboarding, restore, Setup, Channels/Studio, Guide, Player, Settings, Diagnostics; shared theme, controls, canvas and focus owners. |
| Network | PlexClient transport, JSON/XML parsers, pagination, membership/show enrichment, playlist discovery, authenticated media and artwork descriptors. Cloud credentials remain separate from per-server PMS credentials. |
| Durable state | FileAppStore, secure credential store, strict shapes, legacy schedule/settings reads, backups, quarantine and queued replacement writes. |
| Native/platform | Windows MethodChannel adapter, libmpv worker/event queues, runner message/lifetime, DirectComposition child aperture, DPI/fullscreen/window handling. macOS explicitly has unsupported native playback. |
| Diagnostics | Opt-in bounded structured producers, storage filtering, manually refreshed reading state, independently allowlisted support report. |
| Tests/CI | Unit/controller/widget tests, fake Plex/native product spine, optional macOS visual suites; pinned CI portable gate, alpha/macOS build, Windows widgets/stock compile, policy and conditional patched-engine/package jobs. |
| Release/dependencies | pubspec/lockfile, platform manifests/entitlements, CMake, pinned build metadata, mpv preparation, engine patch, clean-source/build provenance, package containment/hashes/licenses. |

High-risk and largest deep samples included Studio (3,720 lines), Player view (3,760), Setup (3,683), LineupController (2,715), PlexClient (2,105), PlayerCoordinator (1,814), shell (1,820), Guide view/controller, persistence, native_player.cpp and release scripts. File size was an investigation clue, not a quality finding.

Excluded from qualitative review: unrelated dirty/untracked work, build/cache output except authorized probes, compiled/vendor binaries, opaque artwork/font assets, historical campaigns as standing instructions, and local secret/configuration values. Lockfile and bundled runtime provenance were included where release-relevant. Direct inventory/source searches were used; no code index was assumed complete or fresh.

## Commands and evidence quality

### Deterministic gate — run once on the initial frozen tree

| Command | Result | Evidence |
| --- | --- | --- |
| `dart format --output=none --set-exit-if-changed .` | Exit 0 | “Formatted 146 files (0 changed) in 2.97 seconds.” |
| `flutter analyze` | Exit 0 | “No issues found!”; approximately 1.7 seconds. |
| `TZ=America/New_York flutter test` | Exit 0 | **1,204 tests passed**, approximately 49 seconds. |
| `flutter --version` | Inspected | Flutter 3.47.6; framework 5fc346839b; engine revision 692136cb65; Dart 3.13.5. |

Sanitized logs: `build/review-probes/gate/format.log`, `analyze.log`, `test.log`. Tool execution can create ignored Flutter caches/build outputs; no source was formatted or repaired. No second full gate was run after unrelated Player work appeared.

### Diagnostic probes

Every probe command used **`TZ=America/New_York flutter test --no-pub <probe path>`**. Fixtures use synthetic identities/media and fake external IO, with the actual policy controllers, widgets, resolver/scheduler or native adapter seams named below. No real Plex account or physical Windows backend was used.

| Evidence ID | Probe path | Result and distinguishing output |
| --- | --- | --- |
| E01 | build/review-probes/plex_persistence/library_inventory_probe_test.dart | Exit 0, +3 characterization cases. “malformed inventory accepted; saved library selection cleared; no error”; explicit zero-size inventory accepted; portrait failure recorded but omitted from copied report. |
| E02 | build/review-probes/schedule_builder/domain_probe_test.dart | Exit 0, +3. Real controller applied/persisted generated channel; production schedule worker rejects noContent. Include specials on schedules all five. Library/playlist input permutation replaces on-now identity. UTC contiguous-window controls pass across DST and midnight. |
| E03 | build/review-probes/setup/nested_picker_probe_test.dart | Exit 0, +2. Direct profile picker returns; nested server→profile picker has no Back and Escape stays Profiles. Single-profile/no-server first run exposes Refresh only. Multiple-profile Sign out route is a positive control. |
| E04 | build/review-probes/setup/scan_phase_retry_probe_test.dart | Exit 0, +2. Complete library facts with outstanding playlist request still display “Loading collections”. Ready library's collection guard rejects Continue; Retry makes zero library requests; full Scan again recovers and commits. |
| E05 | build/review-probes/player/shortcut_probe_test.dart | Exit 1, three intended-contract assertions fail after controls pass: Mini Guide Space loads 0 instead of 1; error Page Down loads 0 instead of 1; G in audio drawer opens no Guide. Enter, normal OSD Page Down and normal G work. |
| E06 | build/review-probes/guide/guide_probe_test.dart | Exit 1, five distinguishing assertions fail. Search G: closes=1, searchFocused=true. Second DST fold rounds to 05:30Z instead of 06:30Z; first-fold control passes. Ultrawide cell width=2000 versus viewport=2279. Hours save failure: previous value 2, visibleErrors=0, controllerError=false. Open Guide after three hours: expired=true, nowLine=0 (policy observation, not an automatic-roll defect). |
| E07 | build/review-probes/studio_settings/source_switch_probe_test.dart | Exit 0, +2. Valid playlist chosen but Save disabled, filter Cancel/Done absent; switching back and cancelling restores Save. Settings selected during native load; late successful tune replaces Settings with Player. |

There are **20 diagnostic cases**, including controls and one policy observation. Green characterization probes assert defective behavior; they are not acceptance passes. Red probes fail deliberately on the intended behavior, not due to a product build failure. The first Guide attempt had a missing probe import; it was repaired under the ignored probe path before the cited successful compilation/execution. Its compilation failure is not a product finding.

Sanitized packet logs: E03 `build/review-probes/setup/nested-picker-output.log`; E04 `build/review-probes/setup/scan-phase-retry-output.log`; E05 `build/review-probes/player/shortcut-probe.log`; E06 `build/review-probes/guide/output.log`. E01/E02/E07 output above is transcribed from their executed tool results. Probes remain ignored and disposable and were never moved into test/.

### Evidence rules and limits

CONFIRMED means a probe or complete deterministic source/contract trace establishes the stated mechanism. LIKELY means strong source and external API evidence, with the user-visible runtime manifestation not observed. HYPOTHESIS observations are separated below and excluded from implementation packages.

The gate proves the existing deterministic obligations, not all journey permutations or physical support. Native CTests, optional pixel suites, current application E2E, Windows builds/packages, live Plex requests, HDR, monitor/DPI, physical remotes, screen readers, and shutdown with real libmpv were **not run**. Optional goldens retain their dated evidence boundaries; no new current-code pixel claim is made.

Specific external checks: [Flutter focus event propagation](https://docs.flutter.dev/ui/interactivity/focus#key-events) supports F09's ancestor-key mechanism; [Dart local DateTime construction](https://api.dart.dev/dart-core/DateTime/DateTime.html) supports the timezone distinction in F12; [mpv paused-for-cache](https://mpv.io/manual/stable/#command-interface-paused-for-cache) supports F15's missing cache-wait projection. The probes/source establish the application failures; the external sources are not substitutes for execution.

## Executive assessment

The baseline gate is green and the inspected credential, transaction, stale-work and native-lifetime protections are substantial. The review nevertheless establishes ordinary interaction/recovery defects and two controller/parser or generator defects outside existing coverage. **No Blocker was established.** Three findings are Major; native buffering is LIKELY; the rest are bounded interaction or quality findings.

The highest-impact corrections are malformed inventory handling (F01), schedule-effective generation eligibility (F02), and first-run account recovery (F03). Fixing these does not establish Windows/package readiness. No new demonstrated credential leak, channel deletion, state-byte loss, or exploitable release-boundary defect was found in the inspected surfaces.

## Findings table

Severity: Blocker = makes the accepted product unusable or unsafe without credible recovery; Major = material ordinary workflow/data/recovery failure; Minor = bounded defect with recovery or narrower trigger; Quality = material evidence, maintenance or support-quality problem. These labels follow user impact rather than file size or test count.

| ID / title | Journey / class | Severity | Status | Evidence | User-visible effect | Root cause | Remediation direction | Product/UI decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **F01 Malformed inventory erases saved library selection** | J2/J4/J10; 7 | Major | CONFIRMED | plex_client.dart:349,1869; lineup_controller.dart:749,773; E01 | Saved-lineup restore falls into setup without an error; previously selected libraries are no longer saved. Channels remain. | Permissive container helper converts malformed success into authoritative empty inventory before save. | Reject malformed inventories before selection filtering/persistence; retain valid explicit-empty semantics. | No |
| **F02 Generator saves an unairable Mini-marathon channel** | J1/J3; 2/7 | Major | CONFIRMED | channel_builder.dart:80,322,387; lineup_controller.dart:1600; scheduler.dart:111,389; E02 | Setup reports success, but a specials-only generated channel cannot show programs or tune with Include specials off. | Eligibility counts source items before block policy excludes all of them; apply validates source, not the resulting schedule. | Determine schedule-effective eligibility before allocation and enforce it at commit. | No |
| **F03 First-run account recovery has no exit** | J1/J2/J4; 4 | Major | CONFIRMED | onboarding_view.dart:750,843; lineup_shell.dart:213; E03 | A zero/one-profile linked account with no usable PMS cannot reach Sign out/relink; relaunch returns to the same state. | Account exit exists only on Profiles/ready Account; server picker is noncancellable and profile switch is conditional. | Supply a deliberate account recovery exit during first-run server/setup failure. | **Yes: exit placement/wording** |
| **F04 Nested profile picker loses its origin** | J3/J4; 4/9 | Minor | CONFIRMED | lineup_controller.dart:1420; onboarding_view.dart:140,753,904; E03 | Switch server→Switch profile removes Back; Escape cannot return to Account/setup. | Profile cancelability derives only from immediate Ready stage; nested origin is discarded. | Preserve profile-picker origin and its cancellation route. | No |
| **F05 Ready/Continue and collection recovery disagree** | J2/J3; 2/7 | Minor | CONFIRMED | channel_setup_view.dart:397,444,469; lineup_controller.dart:1042,1078,1157,1374; E04 | Continue is offered then rejected for collection dependencies; offered Retry scan retains the failure without making a library request. | Item-ready cache bypasses failed enrichment in retryFailedOnly; readiness omits required-source eligibility. | Retry failed enrichment and align offered continuation with its required dependency facts. Keep the availability guard. | No |
| **F06 Playlist work shows a completed scan phase** | J1/J2/J3; 11 | Minor | CONFIRMED | lineup_controller.dart:257,1175,1229; lineup_restore_view.dart:88; E04 | Long playlist discovery/content loading continues under “Loading collections/show details”, with no corresponding phase/progress. | Operation phase is inferred from library facts after those facts have completed. | Track playlist work explicitly; show its phase and bounded progress in the existing status surface. | No material direction; routine copy remains within existing design |
| **F07 Mini Guide Space fails to tune** | J7; 8/9 | Minor | CONFIRMED | player_view.dart:314,326; user-guide.md:310; E05 | Documented Space activation does nothing although Enter/Select tunes. | Activation branch omits Space; its later transport branch rejects Mini Guide. | Route Mini Guide activation consistently before Player transport policy. | No |
| **F08 Overlay guard suppresses documented Player shortcuts** | J7; 9 | Minor | CONFIRMED | player_view.dart:273; desktop-ui-second-pass.md:527; E05 | Error-slate channel surfing and G/F2 from track drawers fail. | Blanket overlay early return precedes unrelated navigation/recovery keys. | Give overlay-local controls precedence only for their keys; preserve supported global/navigation operations. | No for the documented operations |
| **F09 Search typing invokes Guide shortcuts** | J6; 8/9 | Minor | CONFIRMED | guide_view.dart:346,492,538,556; E06 | Typing G while channel search is focused closes Guide; plain P reaches Now by deterministic sibling trace. | Search lets letters bubble to an ancestor that owns unmodified Guide shortcuts without editor-focus exclusion. | Preserve text-entry ownership while retaining modified app shortcuts and explicit Escape/Enter behavior. | No |
| **F10 Ultrawide program cells stop at 2000 canvas pixels** | J6; 6/12 | Minor | CONFIRMED | guide_view.dart:2133; desktop-ui-second-pass.md:135; E06 | A long airing program leaves an empty, untunable strip in a 3440×1440 Guide despite covering the entire time window. | A hard cell-width cap overrides already bounded timeline geometry. | Use clipped projected viewport geometry; retain layout limits at the correct owner. | No |
| **F11 Guide-hours storage failure is silent** | J6/J8; 2/11 | Minor | CONFIRMED | guide_controller.dart:541; lineup_controller.dart:2143,2331; guide_view.dart:1159; E06 | Hours choice reverts without telling the user it failed. | Controller correctly persists before publication; Guide swallows the exception and renders no failure. | Show local save failure/retry feedback without weakening rollback or ordering. | No |
| **F12 DST rounding loses the repeated hour's identity** | J6; 7/10 | Minor | CONFIRMED | guide_controller.dart:1052; E06 | During the second fall-back hour, Guide opens an hour early and gives current programs too little forward coverage. | Local wall-clock reconstruction cannot retain which repeated local hour the input represents. | Floor the actual instant while preserving local/UTC presentation; test both DST folds. | No |
| **F13 Inactive Studio task blocks the selected source** | J5; 2/4/5 | Minor | CONFIRMED | channel_studio_view.dart:879,1128,3235; E07 | Choosing a valid playlist hides a pending Library filter's Cancel/Done but Save/Tune stay disabled. | Source changes retain globally pending ephemeral work belonging to an inactive source. | Cancel or scope pending tasks on source transition; preserve completed inactive drafts. | No |
| **F14 Late Studio tune overrides newer navigation** | J5/J8/J9; 3 | Minor | CONFIRMED | channels_view.dart:113,233; lineup_shell.dart:781; E07 | User opens Settings while Tune loads; successful completion sends them back to Player. | Post-await navigation does not check the originating Studio/navigation intent; Studio's later mounted check runs too late. | Retire only obsolete navigation continuation; allow valid playback to continue. | No |
| **F15 Windows native path never projects buffering** | J7/J9; 7/11 | Minor | LIKELY | native_player.cpp:639,1104; windows_native_player.dart:430; player_view.dart:640; mpv manual | Remote cache starvation can freeze playback while Flutter stays Playing and never presents the promised buffering phase. | Cache-wait is not observed and neither native emission nor Dart mapping can produce buffering. | Add bounded correlated cache-wait facts and truthful state projection, preserving user pause and load identity. | No; physical manifestation must be observed |
| **F16 Support copy omits collection/portrait failures** | J8; 7/11 | Quality | CONFIRMED | lineup_controller.dart:1282,1289,2118; diagnostics.dart:179,300,327; E01 | Recorded failures visible in Diagnostics vanish from the copied support report. | New safe producers were added without matching report event/value allowlists. | Add only exact safe event/fact vocabulary; preserve privacy filtering. | No |
| **F17 Current behavioral/evidence documents are stale** | J1/J6/J7/J8; contract/evidence | Quality | CONFIRMED | user-guide.md:83,371,378; product-parity.md:94,240,274,282,314,318; architecture.md:105 | Testers are told to find removed controls/names and can mistake superseded PARITY descriptions for current guarantees. | Current-authority text/matrices were incompletely reconciled after approved changes. | Reconcile current claims and links; retain historical dated evidence as history. | No |
| **F18 Shuffle depends on upstream response order — known deferred** | J2/J6; 7 | Minor | CONFIRMED | content_resolver.dart:17,82; scheduler.dart:99,281; freshness investigation:130,203; E02 | Same items/durations/seed/anchor can yield a different on-now program after response reordering. | Seeded shuffle consumes supplied order rather than a canonical identity order. | Decide stable-order adoption and existing-schedule transition before implementation. | **Yes; already recorded investigation decision** |

Source-path key for the table: `plex_client.dart` = lib/plex/plex_client.dart; application controller/views = lib/app/<filename>; builder/resolver/scheduler = lib/channels/<filename>; Player view/Windows adapter = lib/playback/<filename>; Guide view/controller = lib/guide/<filename>; diagnostics = lib/diagnostics/diagnostics.dart; native_player.cpp = windows/runner/native_player.cpp. Named documents are under docs/; “freshness investigation” is docs/guide-freshness-collection-investigation.md. All source line numbers refer to the frozen review SHA. No F18 implementation package is added: it is existing deferred work with fresh reproduction, not an authorization to adopt its policy.

## Finding detail and adversarial counterpoints

### F01 — library selection loss, not channel deletion

E01 runs the real library endpoint parser and inherited controller selection path. Missing/wrong-shaped successful inventory is accepted as an empty list; the controller filters saved library IDs against it and saves before restoration. The probe asserts one existing channel remains. Ordinary strict item/playlist page validation does not protect this separate endpoint. Explicit `size=0` inventory is a positive control; remediation must accept genuine empty servers. No claim is made that live PMS currently returns malformed success.

### F02 — apply success precedes schedule failure

Five playable season-zero episodes form an eligible TV collection proposal. Materialization chooses block playback and excludes specials. The real apply method returns applied and the fixture store contains the new channel; the production schedule isolate subsequently rejects noContent. Turning Include specials on produces a schedule with all five. Studio Air Check already protects a comparable custom recipe, but bulk Setup does not. Preserve deliberately retained unavailable manual items/off-air channels; do not impose a generic “all saved channels must be online” rule.

### F03/F04 — recovery and origin are separate defects

F03 is narrowed to first-run or failed startup without a retained cancel origin and at most one Home profile. Multiple profiles can reach Sign out through the profile picker; Refresh can recover an offline PMS. Neither lets a single-profile user correct a mistakenly linked account. F04 is recoverable by selecting a profile or signing out and is therefore Minor. A direct Ready→Profiles cancel works; the missing route is the nested transition. Account/profile credential compensation is already deferred and is not this finding.

### F05/F06 — retain usable data, retry the failed dependency

Collection enrichment is optional for unrelated channels but required for saved collection sources. That distinction and the commit guard are correct. After the guard rejects, Retry uses completed item data as a reason to skip the library, retaining the exact enrichment error. Full Scan again succeeds and is a mitigation. The separate configure-row explicit targeted retry works, but cannot be reached until blocked library continuation succeeds.

During F06's gated playlist IO, every library fact is complete and overall scan status remains scanning; the shared phase widget still says Loading collections. This is real ongoing work under an obsolete phase, not evidence that the task has hung. Cancel/currentness and request deadlines remain bounded. The existing one-line phase surface can express the correction without a layout redesign.

### F07/F08 — local activation versus unrelated shortcuts

The probe uses actual PlayerView, PlayerCoordinator and GuideController with synthetic native IO. It first proves Enter Mini Guide tune, ordinary Page Down tune, and normal G navigation. Each corresponding edge-context operation then fails. Native Flutter track-row traversal/activation must remain intact; removing every overlay guard indiscriminately would be wrong. Escape, Retry/Browse buttons and shell Ctrl/F3 destinations mitigate F08. Now Playing's Up/Down exception is explicitly approved and is not a bug.

### F09 — keyboard events precede text entry

Search owns focus, but its listener only handles Escape/Enter. An ordinary physical G bubbles to Guide's Focus handler, which handles it as close. Existing `tester.enterText` search coverage injects editing values and cannot prove ordinary key routing. The [Flutter focus documentation](https://docs.flutter.dev/ui/interactivity/focus#key-events) confirms that ancestor handling occurs before text entry. P→Now is a deterministic sibling trace, not an independently executed P probe. Keep Ctrl/Cmd+F, search clear/Escape/Enter and app route chords.

### F10/F11/F12 — Guide-specific correctness

F10's real widget at 3440×1440 uses the actual root canvas: timeline 2279 canvas pixels, cell 2000, a 279px canvas gap (372 painted pixels). The pure geometry owner already clips to viewport width; the view introduces the error afterward. Normal 16:9 sizing generally stays below that cap, explaining existing passing layout matrices.

F11 correctly retains the previous hours value on storage failure. Controller updateSettings does not set a global user error, and Guide catches without presenting one. Settings' own error UI does not cover the in-Guide hours control; diagnostics recording is optional and is not visible error feedback.

F12 uses America/New_York: first 01:47 corresponds to 05:47Z and rounds correctly to 05:30Z; second 01:47 corresponds to 06:47Z but also rounds to 05:30Z. This is Guide window rounding, not scheduler drift or corrupted persisted schedule. UTC scheduling and contiguous spring/fall/midnight window controls pass. Physical Windows timezone behavior still requires the actual configured Eastern timezone, not merely an environment variable.

### F13/F14 — correct operation, obsolete UI continuation

F13 uses a dirty but valid existing playlist draft with settled successful Air Check. Opening a Library filter then returning to the preserved playlist leaves Save blocked by the inactive pending task; switch back/Cancel restores Save. Keeping completed inactive choices is approved; inaccessible pending tasks blocking the active source are not.

F14's real shell selects Settings before the delayed native load returns. The Channels callback opens Player before the Studio mounted/epoch check can reject its result. The correct scope is eventual navigation, not playback cancellation or preventing the user from leaving. The Guide caller already selects Player before waiting and does not later override a newer route.

### F15/F16 — truthful native and support observations

F15's absence of a producer/mapping is directly inspected, but actual cache-starvation presentation was not observed on Windows. [mpv's cache-wait property](https://mpv.io/manual/stable/#command-interface-paused-for-cache) is distinct from user pause. A faithful correction needs both native observation and Dart projection, tests for precedence/currentness, and physical starvation/recovery. Static proof alone does not justify calling Windows behavior CONFIRMED.

F16 is a support-quality omission, not credential leakage. Exact collection/portrait producer tuples and portrait value vocabulary are missing from export. The export allowlist is an intentional privacy boundary; exporting arbitrary entries/raw contexts would introduce risk. Existing Library scan timing export is present and is not part of this finding.

### F17/F18 — respect approved direction and deferred decisions

F17 consolidates contradictory current claims: five-theme palette versus four current themes/dropdown; retired Glassmorphism and old labels; Overlay Guide/density/past-window/optional library-control claims; timed Mini Guide and old rich-details shelf; missing Player overlays/channel-source settings; global save-blocking prose; stale “Slow” warning wording; clear-saved-server action with no UI caller; generated-delete regeneration warning removed by an approved decision. product-parity.md also links absent audio-passthrough-spec.md targets. Correct documentation to approved current behavior. Do not restore removed UI or rewrite historical run results as fresh proof.

F18's input sensitivity is confirmed for both library collection and playlist sources while membership, durations, seed, anchor and queried time are fixed. “Deterministic for identical ordered input” remains true. The investigation already flags response-order continuity and a possible one-time schedule shift; this review supplies the requested proof, not a migration decision. Sequential and block semantics remain separate.

## Coverage by user journey

“Traced” below means source/caller/failure-path inspection with existing test evidence reviewed; it does not mean an interactive app journey was physically executed. Probes settle the listed uncertainties, not every Cartesian combination.

| Journey | Trace and probes | Finding / reason no additional finding was promoted | Exact remaining limits |
| --- | --- | --- | --- |
| **J1 First run** | Welcome→link PIN expiry/cancel/retry→protected-profile PIN→server→libraries complete/partial/empty/unsupported→configure→all build modes→review/apply→Guide. E02/E03/E04. | F02/F03/F06. Link polling is sequential; secure cancellation must finish before relink; PIN and discovery/save currentness have controlled failure tests. No additional wrong-screen or credential publication defect established. | Live Plex link/PIN behavior and physical keyboard/remote focus; real scan budget. |
| **J2 Saved relaunch** | Credential read/account validation, Home inventory, resource/connection selection, saved ID filtering, restore phase/outcomes, required collection/playlist failure, missing references, legacy schedule migration, logout/disposal while restore. E01/E03/E04/E02. | F01/F03/F05/F06; F18 known decision. Same-title collection recreation after scan is protected; unavailable/missing are distinguished; failed refresh does not prove source disappearance. | Actual removed/recreated collections/playlist payloads, cold-start latency, Windows shutdown/native cleanup. |
| **J3 Setup re-entry** | Restored committed subset→Continue without rescan, adding unscanned IDs, full/partial retry, Cancel origins, switch server during restore/scan, replace/append/merge, custom preservation, stale review, Source not found keep/remove, Add as new skip. E02/E03/E04. | F02/F04/F05/F06. Recent LIB-01/LIB-02 exact regressions and scope protection are present; no duplicate finding for their fixed ordinary paths. | Live collection failure recovery and large source counts. |
| **J4 Account/scope switches** | Profile/server transactional publication, pending discovery/tune authorization, refresh preservation, queued/started saves, logout barriers and cleanup failure, relink. E01/E03; controller race tests. | F01/F03/F04. No further scope/currentness race established; request retirement does not invalidate an already-started successful save, and credentials have a separate ordered barrier. | Real managed/shared account response shapes; native late audio/video after scope retirement. |
| **J5 Studio** | Create/edit/inspect/duplicate, generated identity, unavailable retained manual items, source transitions, filters/browse/rundown/bulk choice, reorder/delete confirmation, Air Check, save failure, stale base/reconfirmation, Tune. E07/E02. | F13/F14. Mixed-child preview/save concern rejected: recursive live-source validation and regression coverage already protect it. Dirty leave/save-failure preservation and stale snapshots have faithful tests. | Physical remote/editor focus, real load failure and Windows rendering. |
| **J6 Guide** | Vertical/horizontal/page/Now/tune/back/search/filter/hours/PiP; error rows and retry-all, identity/cache currentness; root scaling, 720p/16:10/ultrawide/150% text, long/empty lineups; midnight/DST. E06/E02; existing geometry/lazy/semantics tests. | F09/F10/F11/F12 and known F18. Retry includes offscreen rows; schedule/artwork caches and concurrent loads are bounded. Long-open expiry is D3 below, because no approved automatic-roll contract was found. | Actual video aperture/DPI, physical key/text input/AT, current visual approval is not inferred from old goldens. |
| **J7 Player** | Tune/replacement, surfing/digits, all overlays, track requests/confirmation/error, sleep deadline, fullscreen, DVR off/on, multipart loads/seeks/unknown boundaries, pause while load, OSD/cursor. E05; existing coordinator/adapter/widget tests. | F07/F08/F15. Repeated status events no longer rearm timers; exact seek state survives notification coalescing; sleep remains one OSD presentation. Schedule-boundary automatic next-program playback is explicitly unimplemented/decision-gated, not newly reported. | Native playback/cache starvation, HDR/tracks, pointer cursor and physical remote mappings. |
| **J8 Settings** | Every current setting and consumer: four themes, Guide background/logo/hours/context/sources, overlays, auto-hide, DVR, motion/focus, startup picker, account, diagnostics. Pending transformations/rollback/live updates with open surfaces inspected. E01/E06/E07. | F11/F14/F16/F17. Controller derives transformations inside its queue; independent pending choices are rebased over committed state; failure cannot later reappear from stale snapshots. | Physical media/control effects, typography/IME/AT and overlay legibility. |
| **J9 Lifecycle** | Dart view resume clocks/disposal; native generation/stop/dispose/window-close handshake; resize/DPI/minimize/fullscreen code; repeated actions and late async work. E07 plus native/widget tests. | F14/F15. Command/event queues are bounded; replacement awaits cleanup; failed stop remains retryable; native owner is destroyed before messenger. No new source-level native lifetime defect established. | Real minimize/restore, monitor changes, rapid loading/seek/replacement/shutdown; no portable test is native acceptance. |
| **J10 Persistence/upgrade** | Exact shapes, optional/retired settings, compatible schedule transition, original-byte migration backup, invalid UTF-8/JSON/schema quarantine, transient IO, physical write queue, controller atomicity and concurrency. E01/E02; existing store/controller tests. | F01. Original-byte recovery and IO failure separation are explicit and tested; no extra quarantine/data-corruption defect established. Early Electron/Flutter milestones are not current migration targets. | Actual Windows file locking, rename/app-support/secure-store behavior and full Windows deterministic suite. |

## Coverage of the twelve defect classes

| Class | Wide scan and deep evidence | Disposition |
| --- | --- | --- |
| **1 Event rate versus transitions** | Player native time-pos consumption/coalescing, coordinator hide/cursor timers, shell field comparisons, Guide viewport/scroll notifications, Air Check debounce/latest-pending, PIN polling, library phase/pages, focus visibility. Existing timing and quiescence tests inspected. | No new timer-reset sibling promoted. Event consumption stays exact; visible position publication is bucketed; Air Check clock tick does not restart its load debounce. Physical profile timeline remains unmeasured. |
| **2 Displayed availability versus guard** | Action ledger below covers setup, generation, Studio, Guide, Player, Settings and diagnostics. Guards traced through source/currentness/save eligibility. | F02/F05/F11/F13. Suspected mixed-source Air Check/save mismatch disproved by recursive UI protection. Unsupported native controls are disabled. |
| **3 Async surface versus intent** | Bootstrap/native barrier, restore screen, route selection, selection saves, Studio tune callback, Guide tune caller, stale results across scope changes. | F14. Saved-lineup restore uses the intended dedicated surface; no duplicate P1 startup-screen finding. |
| **4 Exits and cancel origin** | Setup/account graph, dirty Studio leave, filter/bulk/reorder/dialog cancellation, menu/barrier/Back, Player overlays, Settings/Diagnostics origin. | F03/F04/F13. Applying a started durable mutation is intentionally noncancellable; ordinary scan/picker cancellation has scope protection. |
| **5 Overlay composition** | Every production AnimatedSwitcher family and overlay/menu/dialog/popover/drawer searched; onboarding/PIN stages, Player stable OSD key, Sleep substate, outgoing focus/semantics exclusion, Lineup menu parent retention, Studio pending-filter composition deeply traced. | F13 is inaccessible inactive work, not a replacement-parent animation. No new OSD remount/replayed-entrance defect promoted; concurrent Sleep keyboard correction excluded. |
| **6 Shared controls** | All four direct DropdownButton constructions and eleven shared dropdown callers; twelve TextFields/two TextFormFields; selected closed value builders, constraints/padding, themed menu/focus primitives, root canvas. | Fixed dropdown/search-centering siblings absent in audited instances. F10 is a separate shared cell geometry cap. Physical IME and maximum text-scale behavior remain observations. |
| **7 External assumptions** | JSON/XML/control bodies, resources/credential scopes, library sections/page validation, playlist occurrences, collection relisting/membership, episode show genres, cast sources/transcoder, mpv properties/tracks/codecs. | F01/F02/F05/F15/F16; F18 known. Nonempty Plex Home shape variants and list cast/tag completeness remain H1/H2 observations. No inference that Plex currently emits malformed sections. |
| **8 Input modes** | Shared pointer/navigation modality, focus restoration after Sleep/menu, actual keyboard vs desktop traditional highlight, semantics activation, Player/Guide key roots, Studio row/editor focus. | F07/F09. Existing keyboard-only OSD suspension and pointer timeout tests support the recent fix; physical remote/AT remains open. |
| **9 Narrow key state checks** | User-guide key table compared with each Player context and Guide editor/root plus shell route chords and onboarding Back/PIN. | F04/F07/F08/F09. Current context matrix below records intentional exceptions and transient number-entry restrictions. |
| **10 Platform-only behavior** | Windows path/quarantine/rename and secure storage boundaries, native HWND lifetime, clipping/geometry/DPR, fullscreen placement, manifests/build paths/reparse containment; local Guide DateTime construction. | F12 reproduced on macOS Eastern timezone. No new static Windows filesystem/package bug proven; exact Windows suite, locking/DPI/physical observations remain necessary. |
| **11 Progress/phase truth** | Restore/setup item/collection/show phases, playlist wait, native loading/cache wait, Air Check statuses, saves/settings failures, support export. | F06/F11/F15/F16. Item counts monotonic; request/page/byte deadlines and aborts are bounded. Real launch/setup scan budget is still unmeasured. |
| **12 Unbounded cost** | Guide schedule/artwork entries/concurrency, scheduler cycle/projection bounds, directory health, Studio/build recomputation, full-size ordinary artwork, native queues/encoder/correlation, diagnostics retention. | No newly proven unbounded growth or material frame regression. F10 is an erroneous rendering cap, not memory growth. Full-size ordinary art sizing and scan-cost fallback are already recorded follow-ups; no duplicate implementation package. Setup recomputation lacks a measured harm and was not promoted from suspicion. |

## Action eligibility ledger

Local editing/selection controls act on local drafts; their terminal operations are checked below. This records the enabled-action families and authoritative guard seams, including hidden/disabled/invalid states, rather than claiming every combination was executed.

| Enabled action family | UI precondition | Authoritative operation guard / result |
| --- | --- | --- |
| Sign in / request new code | Idle/retry state; not busy; secure cancellation failure has dedicated retry | Retires prior polling, validates account before credential publication, rejects obsolete work. |
| Cancel / retry secure cancellation | Link state, not busy | Credential queue/cleanup must succeed before Welcome/new linking; failure remains visible/retryable. |
| Copy code / open browser | Valid active PIN code | Fixed Plex link destination/code; expiry/failure action replacement. |
| Profile / PIN submit | Not busy; four PIN digits | Scope/current operation and credential/state save ordering; started-save cancellation hidden. |
| Profile Back | profileSelectionCanCancel | Same flag and active server; nested origin loss F04. |
| Server Connect / reconnect | Not busy/current pending row rules | Secure connection/PMS credential/current target; selection persists before retiring scope. |
| Current server Continue | Current server, not busy | Returns captured origin without reconnecting. |
| Refresh servers | Not busy | Invalidates discovery, retains current valid scope/access. |
| Server Back / setup Switch server | serverSelectionCanCancel / canSwitchServer | Captured origin, scan abort, started setup-commit exclusion. F03 lacks first-run account exit. |
| Select libraries / select all | Available list, settled selection context | Valid library IDs; selection alone is not a durable commit. |
| Scan / Scan again / cancel scan | Nonempty selected IDs, idle / active scan | Bounded scoped IO and retained completed inventory; obsolete results cannot publish. |
| Failed-library row Retry | Failed fact, not busy | Explicit retry IDs override retained item cache. |
| Retry scan / Continue ready subset | Settled error or ready nonempty intersection, not busy | Scope/pending-ready inventory then required collection/playlist evidence. F05 exposes discrepancy. |
| Configure discovery Retry | Failed collection/playlist facts, no overlapping retry | Targeted inventory retry; failed discoveries cannot prove “Source not found”. |
| Strategies / grouping / order / limits / variants | Local configuration choices | Shared builder/allocator; F02 omits schedule-effective eligibility. |
| Review / mode changes / removal confirmation / Apply | Nonempty eligible plan; removals acknowledged; not applying | Full captured base, source/model checks and queued atomic save; stale requires fresh review. |
| View lineup / add custom after creation | Completed result | Completes setup then returns directory or opens Studio. |
| Directory new/edit/inspect/duplicate | Current channel/row; generated/custom ownership | Studio mode/source preservation; duplicate creates separate identity. |
| Directory selection/delete | Selected current targets; explicit confirmation | Confirmed target snapshots and atomic deletion; unrelated mutations do not invalidate whole selection. |
| Reorder / Move / save order | Local reordered draft/current bounds; not saving | Complete captured base and unique IDs/numbers; stale save does not overwrite new lineup. |
| Studio source/filter/browse/rundown/bulk/move/remove | Local source choices and pending editor state | Draft/source validation and local pending task ownership; F13 inactive pending task blocks terminal actions. |
| Studio Save / Save identity | Dirty valid draft, no pending task/save/tune; valid Air Check | Snapshot/base/source/schedule-currentness; persistence before publication; failure retains full draft. |
| Studio conflict Use saved / Replace | Conflict state and explicit confirmation | Captured fresh base; a second intervening change is rejected. |
| Studio Tune / save-and-tune | Clean valid saved draft, no pending editor | Player's real tune/cleanup/currentness; caller's late navigation F14. |
| Studio Back / menu destination | Not saving; dirty leave requires discard confirmation | One shared leave guard; tuning itself can continue while leaving. |
| Air Check / retry / next-hours | Valid local recipe; error/loading/current preview state | Single active/latest pending request, generation/key/currentness, bounded schedule query. |
| Guide focus/select/tune | Rendered program; tune only if airing | Select does not retune; actual tune resolves current program through one Player owner. |
| Guide search/library/Now/earlier/later/hours | Controls available; earlier clamped to live boundary; valid hours | Filters/projected rows bounded; settings queue persists first. F09 editor keys and F11 save feedback. |
| Guide retry row/all / setup empty / PiP open | Failed row(s) / empty lineup / playback surface | Real retry can include offscreen errors; setup route and Player share shell owner. |
| Player overlay/Guide/channel input | Context/native capability and DVR policy | Tune/cleanup/load identity; F07/F08 keyboard eligibility differences. |
| Player tracks | Available type, selected/current native track facts | Requested ≠ executed ≠ observed; pending/failure retains confirmed selection. |
| Sleep presets / Off | OSD picker/current playback context | Deadline persists across pause/channel/Guide, manual stop/logout/dispose cancel. |
| Player transport/fullscreen | DVR enabled for transport; native capability | Load/currentness, unknown multipart boundary rules, serialized fullscreen completion/rollback. |
| Retry playback / Browse / Close error | Recoverable/terminal error context | Stop cleanup obligation remains retryable; replacement waits; F08 promised key recovery blocked. |
| Each Settings choice | Valid option, that key not pending | Transformation computed from committed settings inside queue; persistence before live effect; local failure UI. |
| Account switch/logout | Available account controls and confirmation | Scope transition/credential/state barriers; cleanup failure preserves safe runtime context. |
| Diagnostics recording/refresh/details/copy | Recording toggle/current events; manually captured reading snapshot | Opt-in max250, clear on disable, safe report allowlist; F16 omitted safe producers. |

## Navigation and input-context graph

### Stages/routes and exits

- Welcome → Linking; Cancel → Welcome after secure cleanup. Failure/expiry → finite new-code retry; failed cleanup → secure-cancellation retry.
- Profiles → protected PIN; PIN Back returns through the applicable profile/account origin. Direct ready-app Profiles has Back/Escape to Account. Nested Servers→Profiles loses that origin (F04).
- Servers entered from Ready, Libraries, or Restore returns to its captured origin; Restore return restarts restoration. First-run Servers with ≤1 profile/no usable PMS has Refresh only (F03).
- Libraries → Configure → Review → Applying → Complete. Configure Back → Libraries; Review Back → Configure. Re-entry Libraries Cancel → Ready; scan Cancel → Libraries with retained selection/readiness. Applying is intentionally a started, noncancellable durable operation. Complete → directory or custom Studio.
- Channels ↔ Studio through one leave guard; dirty draft → discard/keep-editing dialog. Filter/bulk/reorder/Move and conflict dialogs have explicit cancellation. Inactive-source pending filter loses visible exits (F13).
- Guide ↔ Player preserves one session. Guide Back opens Player when playback exists, otherwise Lineup menu. Settings Back names its origin; Diagnostics → Settings Support returns through the original Settings destination rather than looping.
- Lineup menu keeps parent mounted, excludes underlying focus/semantics while open, and dismisses via Back/outside click. Keyboard restores invoker; pointer restores appropriate root.
- Player OSD/Now Playing share their mounted presentation; Now Playing Back collapses to OSD. Sleep is an OSD layer with Close/preset/video-click/Back. Mini Guide/tracks have Close/Back; error has Retry/Browse/Close. Number entry is bounded with confirmation/timeout/Back.
- Windows WM_CLOSE follows asynchronous native teardown before messenger destruction. Actual shutdown acceptance remains unobserved.

### Every documented key context reviewed

| Context | Contract mapped to source/tests | Disposition |
| --- | --- | --- |
| Management | Tab/Shift+Tab; Enter/Space focused control activation | Flutter focus/actions and shared modality traced; physical remote/AT unverified. |
| Ready app, including overlays | Ctrl+G/P/comma, Ctrl+1–5, F3 | Shared shell route owner/Studio leave guard; Player explicitly lets modified chords bubble. |
| Guide grid | Arrows, visible-page Page Up/Down, Home/P/Media Play, Enter/numpad Enter/Space/Select, Esc/Backspace/Back/G/F2 | Source and existing widget tests agree in grid context; search letter collision F09. |
| Guide search | Enter exits to grid without tuning; Escape clears then returns focus | Existing tests cover these; G/P wrongly bubble. Text-injection tests do not cover physical letters. |
| Ordinary Player/OSD | G/F2, Up, Enter, I/Down, Page Up/Down, digits, A/C/S/F/F11, Back; DVR optional seek/play/media keys | Recent OSD-Up contract works; DVR off intentionally blocks only transport. |
| Now Playing | I/Enter/Back/Close collapse; direct A/C; other supported Player navigation | Up/Down Mini Guide exception is approved; pointer does not dismiss reading surface. |
| Mini Guide | Up/Down, Page Up/Down ±7, Enter/Space/Select tune, Right full Guide, Back | Space fails F07; other traced paths and positive controls work. |
| Tracks/error | Track row focus/activation, Close/Back; documented unrelated navigation/recovery | F08 blanket guard; shell chords and visible controls still recover. |
| Number entry | Digits, Enter/numpad Enter/Select, Back, automatic bounded commit | Other Player keys ignored during this transient mode; recorded behavior, no broadened shortcut requirement invented. |
| Sleep/menu | Focused control activation, Back, selection/dismissal and modality-aware focus return | Parent presentation stable. Concurrent Sleep keyboard edits are outside this fixed review and not judged as landed code. |
| Native media/remote keys | DVR transport versus Guide Media Play policy | Dart contract inspected; exact OS-reported physical remote keys remain acceptance work. |

## Specialist dimension notes

| Dimension | Wide scan / deep samples | Material result and calibrated no-finding note |
| --- | --- | --- |
| Architecture/ownership | Import/constructor/owner census; bootstrap/controller queues; shared resolver/scheduler/Air Check; Dart/native seams | No new ownership violation established. Distinct lifetimes are behaviorful, not redundant counters; native interface represents a real platform boundary. F14 is a caller continuation error, not reason to replace state management. |
| Correctness/failure modes | Journey owner/guard/currentness/rollback traces and targeted probes | F01–F14 and known F18. Existing protections disprove several apparent races and mixed-child invalidity. |
| Maintainability/AI debt | Largest source files; helper/adapter/fallback/compatibility/TODO scans; representative policies/tests | No material concern promoted solely for size/style. Inspected migration, unsupported-platform, artwork and cleanup fallbacks have concrete obligations. A blanket rewrite is unsupported. |
| Test strategy/CI | Test tiers, product spine, native CTest, golden suites, CI commands and conditional jobs | Baseline passes yet raw search keys/edge overlay activation/async navigation/schedule-effective generation lacked the distinguishing combinations. These gaps accompany specific findings; no generic “add E2E” finding. |
| Security/privacy | Credential scopes, redirect/reference boundaries, input bounds, IO cancellation, diagnostics producers/report, persisted sensitive metadata | No new concrete leak/exploit proven. Native headers/reference policy and platform storage still need runtime acceptance; F16 must retain export filtering. Known plaintext media metadata/privacy and profile-token compensation are already recorded. |
| Build/release/supply chain | Locked dependencies/hashes, pinned actions/SDK/runtime, preparation/build/package scripts, provenance and path/reparse checks | No new material defect established. Clean source/artifact hashes are bound and rechecked; package-only/engine selection and exact physical package proof remain documented release work. No fresh CI execution/vulnerability/legal claim. |
| Ops/config/observability | Every setting/default/consumer, safe errors, recording lifecycle, scan/native phases and exported report | F06/F11/F15/F16. Bounded fixed-fact producers and opt-in clearing reduce risk; native Playing/Buffering truth remains incomplete. |
| Performance/concurrency/reliability | Schedule/art caches, bounded workers/queues, high-frequency event publication, currentness/cancel/timeouts, native teardown | No new unbounded growth proven. Guide row/art caches, 4 artwork loads, schedule cycle caps, native queue/encoder budgets and diagnostics250 are explicit. Ordinary full-size art/scan latency have existing follow-up decisions; no measured FPS claim. |
| Docs/DX | Requested contracts, current-authority PARITY rows, settings/shortcuts, relative links, build/acceptance instructions | F17. PARITY rows unsupported by current implementation are consolidated; qualified native/package rows are not mislabeled as proven support. Development/acceptance documents otherwise state prerequisites and evidence boundaries. |

Native resource deep samples found command count64/128KiB, event count256, correlation count1024, track rows256/optional-string64KiB bounds. Directory health uses bounded concurrency/queue/cache and existing 1000-row quiescence tests. These are source/test facts, not measured physical performance.

## Needs my decision

1. **F03 — first-run account recovery:** choose the account-exit placement/wording on Servers and no-usable-library recovery. A quiet Sign out/change-account path is one option; returning to a profile/account recovery surface is another. Scope is restoring an exit, not changing credential policy.
2. **F18 — known shuffle-order continuity:** decide whether to adopt canonical identity ordering and how already saved shuffled schedules transition without an unexplained one-time shift. Preserve sequential/block rules. The existence of input-order drift is now reproduced; migration/adoption remains your decision.
3. **D3 — expired open Guide:** E06 proves a continuously mounted Guide can outlive its time window and lose its Now line. Source only refreshes for presentation; Now/Home/P recovers. No approved contract requires automatically discarding inspected future/past focus. Decide automatic roll for live-following mode versus preserving inspection with clearer expired/live affordance. **This is a confirmed policy observation, not a promoted automatic-roll defect.**

Existing decisions already documented—schedule-boundary automatic continuation, live collection refresh/membership-change policy, local HTTP, transcode settings/fallback scope and profile-token compensation—remain outside this review's new packages. No new approval of them is implied.

## Needs live/physical observation

Use the collaborative handoff's human-as-eyes-and-hands procedure. Prepare the exact candidate on physical Windows with the pinned patched engine/libmpv, recorded Windows/GPU/display/input/timezone and clean build/package identity. Give one step at a time; wait for the operator's reply; classify Pass / Fail—blocker / Fail—non-blocking / Blocked—not run. Record only neutral counts, durations and outcomes, never source addresses, credentials, titles or private paths. Do not edit the existing handoff.

| ID | Setup → exact action | Expected distinguishing result | Operator reply |
| --- | --- | --- | --- |
| L1 Native buffering (F15) | Begin an authorized controlled stream, then deliberately withhold/throttle supply below bitrate until independently established cache-wait lasts >2s; restore supply | Buffering indicator/phase corresponds to cache waiting and returns to playing; user pause remains distinct. At reviewed SHA, missing projection is expected. | “L1 pass/fail; wait ~Ns; recovered yes/no”. No native property containing a descriptor is shared. |
| L2 Startup/re-entry | Saved lineup → quit/relaunch; Generate lineup→Continue→configure→review; subset and Scan again; Switch server during restore/scan then Back | Dedicated restore surface, preserved lineup, correct scoped commit and return origins | “L2 pass/fail; phase; return destination”. |
| L3 Account exits/origins (F03/F04) | Dedicated account with ≤1 Home profile/no usable PMS; inspect available recovery. Separately Account→Switch server→Switch profile→Back/Escape | Account can be changed; nested picker returns to its actual origin after correction | “L3 pass/fail; exit present yes/no; return destination”. |
| L4 Enrichment recovery (F05/F06) | Controlled required collection membership fails, then server succeeds; Continue→Retry scan→Continue. Separately slow playlist IO after libraries complete | Retry refetches failed enrichment; phase truth follows playlist work | “L4 pass/fail; requests increased yes/no; phase”. |
| L5 Cast/external data | On local and remote selected servers, inspect cast source classes/list-detail facts through sanitized field/type/count-only observation; open Now Playing | Sized PMS transcoder loads supported portrait shapes; absent thumbs distinguished from transport failure | “L5 counts by source class; loaded/fallback counts”. |
| L6 Scan budget | Diagnostics on; warm-up then five sequential unchanged launch samples and five setup samples, largest library and normal selection separately | Added median ≤max(20s,50% item median); each added duration ≤2× allowance, per existing approved budget | “L6 route class; itemsMs/collectionsMs/showGenresMs and counts only”. |
| L7 OSD/cursor/modality | 4s then8s hide; steady playback; mouse Sleep/menu dismissal; keyboard hold; DVR on pause during loading | No frame rearm; correct cursor idle; pointer dismissals time out, keyboard holds; final loaded state paused | “L7 pass/fail; ~Ns; paused yes/no”. |
| L8 Keyboard/remote regression | Guide search physical G/P; Mini Guide Space; error Page Down/Up; G/F2 from track panel; F3/Ctrl destinations; Sleep keyboard | Edited text owns letters; documented shortcuts work in their contexts; no unexpected pause/route | “L8 key/context pass/fail”. |
| L9 Studio async/state | Open pending filter→switch source; Tune→immediately Settings/Guide while load delayed | No invisible task blocks Save; late tune preserves latest destination while playback may continue | “L9 pass/fail; Save enabled; final route”. |
| L10 Window/geometry/AT | Player→Guide PiP→Player; minimize/restore, resize, repeated fullscreen, different-DPI monitors; 720p/16:10/ultrawide/4K100%/150%; text150% | Aperture/overlay/focus/IME/variable fonts align; no second native window; no ultrawide cell strip | “L10 configuration; pass/fail; focus/aperture correct yes/no”. |
| L11 Lifetime/media | Rapid tune replacement/loading, two same-loading-part seeks, failed part→replacement, shutdown mid-operation; representative SDR/HDR/audio/text/image subtitles | No stale output/seek/track events; stop failure retryable; native shutdown completes; actual HDR/track behavior truthful | “L11 scenario pass/fail; recovery; process exits yes/no”. |
| L12 Windows storage/tests | Actual Eastern Windows timezone; full deterministic suite; controlled temporary storage lock/rename failures and compatible/corrupt state fixtures | Windows quarantine-path tests, byte preservation, failure/rollback and app-support paths behave as documented | “L12 command result; preserved/recovered yes/no”. Do not change user's OS timezone silently. |
| L13 Native/package | Opt-in encoder/authenticated-reference CTests; clean patched release/package; validate manifest/provenance; launch outside development tree/clean user profile | Actual pinned native harness, redirect/reference containment, complete runtime/licenses, usable artifact and clean shutdown | “L13 tested artifact ID; Pass/Fail/Blocked”. Driver-loader absence only in separately authorized disposable environment. |
| H1 Plex Home shapes — HYPOTHESIS | Dedicated owner/managed/protected profiles; observe production v2 and legacy JSON response field names/types/counts only | Determine whether nonempty users/HomeUser/top-level arrays or numeric IDs actually occur and survive parsing | “H1 container shape/types/counts; parsed count”. No compatibility defect is promoted without observed contract. |
| H2 Live collection/ordering freshness | Same-title automated collection recreation, unchanged member set and relaunch; compare neutral current-item identities/counts without titles | Recreated title resolves after complete scan; establish actual response permutation frequency. In-session refresh remains intentionally deferred | “H2 pass/fail; membership equal; response order changed yes/no”. |

## Calibration ledger and exclusions

The independent reviewer retained F01–F17 at the stated scope and severity, with F15 LIKELY. F18 was retained as a **known deferred decision item**, downgraded to Minor and excluded from no-decision remediation. D3 was explicitly reclassified from an assumed automatic-roll defect to a policy observation. F09/F14 received a separate targeted independent pass after their later probes.

Rejected/merged candidates:

- A mixed-source Air Check/save mismatch: Studio recursively validates every child and existing tests cover incomplete libraries/empty playlists.
- Unsupported subtitle drawer: Off-only state is intentional and tested.
- File-length/large-controller/general framework concerns: no concrete material burden beyond owned behavior established.
- Unsorted durable list/reorder conflict: current and earliest relevant producers sort; no normal/older-build trigger established.
- Stale media-type dropdown after inventory changes: no reachable production refresh while that editor remains mounted established.
- Per-build Setup/Studio recomputation: cost not measured; bounded inputs and existing cache/lazy tests mitigate; no material performance finding promoted from a pattern.
- Automatic next scheduled-program playback, alternate media versions, profile-token compensation, live refresh, transcoding, signing/mirroring/legal/package readiness: already recorded or decision-gated; no duplicate new packages.
- Generated-delete warning absence/retired preferences: approved simplifications; documentation drift, not product regressions.
- Ordinary full-size artwork: bounded but potentially costly, already explicitly recommended as follow-up; live timing remains necessary.
- Concurrent Sleep-picker keyboard correction: outside frozen source review; no fix dispatch or conflicting write.

No-finding statements are bounded to the identified inspected surfaces and tests. No exhaustive correctness, security assurance, live Plex compatibility, fresh pixel approval, physical Windows acceptance, or release readiness is claimed.

## Remediation and stopping point

REMEDIATION.md contains planning-only packages for **F01/F02/F04–F17**, including the LIKELY native projection issue with its physical gate. F03/F18 and D3 are parked for your decisions. Packages have file ownership, faithful regression evidence, resource/dependency sequencing, rollback notes and worker/worker_luna suggestions. No implementation has been assigned or performed.

The next step is your approval of all or a subset of those packages. This review stops with the report and plan.
