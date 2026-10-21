# Open obligations and historical evidence

Reconciled **October 20, 2026**, against `platform/macos` at
`ac4c3a1724796314cc7a721bf54b0b2f0f94ff22`. This is the **single current
unfinished-work register**. Detailed plans own behavior, decisions and test
procedures; dated reviews remain attributed history. A later documentation commit
does not change a tested app's identity. No new tests or runtime observations were
performed for this reconciliation. October 21 execution updates below retain their
actual source and artifact identities; the October 20 baseline is historical.

[The Opus 5.5 handoff](handoffs/opus-5-5-core-readiness-handoff.md) explains the
current product, evidence and proposed order of work. It references this register
instead of maintaining another backlog. Read current source and later execution
records before reviving any old finding.

## Classification and priority

- **Confirmed bug:** a demonstrated failing behavior with an established current
  mechanism. A repair can be implemented while its rollout/acceptance stays open.
- **Verification gap:** implementation exists, but the specific candidate, platform
  or scenario has not been established. Absence of proof is not a fresh bug.
- **Investigation:** an observation, hypothesis or unresolved policy needs evidence
  before choosing a repair.
- **Feature:** missing product capability requiring its own scope/decisions.
- **Release engineering:** missing integration, packaging or distribution work.

Suggested priority is core correctness/recovery and candidate verification, then
safe delivery/data protection, then deliberately selected features and TV spikes.
These priorities are recommendations, not permission to publish, change approved
UI, operate accounts/devices or launch every listed project.

**Current release scope (maintainer, October 20, 2026):** the next deliverable is a
macOS Direct Play private beta on Apple Silicon. Transcoding (F-01), the other F rows,
TV work and Windows physical/package acceptance are outside it; Windows engine-script
integration (R-01) and CI-executable engine tests (V-02) are inside it. The macOS
deployment target stays 12.0 and the promised floor is set from an older-macOS check
(V-06). Signing and distribution (R-02) are excluded for now; the beta candidate is the
verified ad-hoc-signed build using the repaired engine (B-01). On October 21 the
maintainer selected the V-05 beta subset: local PMS Direct Play with the owner
account and available Home profiles, saved-lineup restore, scan/retry/cancel,
current catalog selection, authorized playback and graceful shutdown. Protected
profile/server failures and 401/403 remain deterministic-test evidence. Remote/
relay, alternate PMS shapes, large/partial catalogs, smart collections and live
membership/portrait probes remain beta limitations. R-03 implementation must land
before the candidate after design approval; V-07 remains deferred until the
maintainer chooses the existing checklist or a limited candidate.

## Confirmed bugs and repair status

**No additional unrepaired macOS application-policy defect is established by the
reconciled audit records.** That is a bounded statement about known findings,
not a guarantee that the app has no bugs. The desktop engine defect below remains
an open delivery/acceptance item; do not erase it merely because its local tests pass.

| ID | Finding | Current status | What actually remains |
| --- | --- | --- | --- |
| B-01 | Desktop Flutter AX bridge rejects unreachable/moved updates and cannot safely recover from failed mutations | Repair implemented in `831c28fc`; historical canonical app integration verified through source `0208982e`. October 21 durable Release engine verification and fresh focused Debug/Release recovery tests pass (12 cases per mode); candidate built at `ddefaa4e`, with live acceptance pending. Stock SDK/cache remain unchanged and the repaired engine is opt-in. | R-01 Windows integration, V-01/V-02 bounded runtime evidence and V-07 human acceptance. M-04 overall remains open. [Current report](handoffs/macos-post-audit-fix-report.md), [engine investigation](handoffs/macos-ax-update-investigation.md). |

Do not promote the ancestor-junction risk, buffering/EOF hypotheses, timestamp
warning or historical node 866 into confirmed current application defects without
the discriminating evidence in the investigation rows below.

## Verification gaps

| ID | Obligation | Evidence already available | Exact unfinished gate |
| --- | --- | --- | --- |
| V-01 | Initial OSD fade/menu continuity and natural Slider interactivity transition | Retained frame/widget regressions, stock keyed/unkeyed reductions, canonical native continuity and useful diagnostic seek. Four automatic first-fade attempts plus a bounded manual probe do not qualify; three natural routes mount already-interactive Sliders. | Actual menu opening within the initial 350-ms fade with recorded animation/timing; a same-presenter enabled/disabled transition where naturally feasible. Do not add a product control to force it or repeat an unbounded campaign. [Recovery assignment](handoffs/macos-m04-recovery-implementation-handoff.md#d-resolve-remaining-runtime-uncertainties). |
| V-02 | Repaired Windows engine | Historical macOS common tests 242 Debug / 240 Release retain their attribution. October 21 fresh focused native tests pass all 12 recovery cases per mode on the durable macOS checkout; this is not Windows evidence. October 21 Windows per-mode full-suite/recovery/DC-baseline attribution jobs are implemented; [CI dispatch 39548870477](https://github.com/TJZine/LineupDesktop/actions/runs/39548870477) is running at `c767d79d`; Windows release policy and combined engine/app/package job passed. Actual Release common suite passed all 240 cases, including the ten bridge recovery cases; the Windows suite failed its native recovery case amid AOT-fixture errors, then aborted at a 300-second test timeout without XML or summary. Debug is still running. Required per-mode acceptance and baseline attribution have not passed. | Execute Debug and Release `common_cpp_unittests` and `flutter_windows_unittests` against both patches, require all 12 named recovery cases, attribute other failures against same-mode DC-only output, and verify intended app/package. No configured-job or portable-fixture result closes V-02. [Engine instructions](../tool/flutter_engine/README.md). |
| V-03 | Windows native lifecycle, physical media and exact package | Later recorded CI run [39383128215](https://github.com/TJZine/LineupDesktop/actions/runs/39383128215) passed stock Windows build and eight explicit CTests: encoder, playback state, core, codec, display dynamic range, guardian, player contract and authenticated reference. Earlier L2 Windows auth/package gates also passed at their recorded identities. | `runner_lifecycle` is still outside current CI and lacks recorded execution here. Run it with its actual patched-engine prerequisites. Physical playback/parts/EOF, HDR/restoration, tracks, input, monitor/DPI and clean-system package remain distinct. Revalidate changed inputs; do not repeat all earlier tests solely because an old handoff says pending. [Development tiers](DEVELOPMENT.md#current-test-tiers-and-gaps), [physical/package procedure](windows-native-validation.md). |
| V-04 | macOS real-app reliability beyond recorded scenarios | Historical actual Plex playback, tracks, timer expiry, recovery, natural rollovers and bounded native focus/seek/quit observations exist. The October 21 candidate at `ddefaa4e` is built and artifact-verified. It was started with maintainer availability approved; the loaded Flutter engine was independently matched to the bundled SHA-256. After capture recovered, two current local selections failed immediately with native `source_open_error`; the first redacted report then records `player_unavailable`. Saved Guide and running Licenses routes were observed, but successful playback is unverified. A bounded read-only worker diagnosis is active. Later native capture failed with error -3812; no physical/live-playback pass is inferred. Accepted H1 HDR/L1 seek evidence and L2 real-coordinator/auth cases retain their exact sources. | Sustained audio/rollover, true live resize/minimum size, minimize/restore, multi-display/Spaces/Stage Manager and sleep/wake coverage on the selected final candidate; exact remaining physical steps stay in the existing checklist. No new claim follows from automated AX actions. |
| V-05 | Real Plex scope, catalog and recovery edge cases | Pagination/parser/currentness tests; real macOS scan and selected local playback flows; authenticated synthetic reference matrices. | On candidate `ddefaa4e`, saved-lineup/current Guide restoration and completed launch library scans were observed; the redacted report identifies a verified Plex connection. Two available local current selections failed with `source_open_error`. Continue the approved owner/available Home profile, explicit scan/retry/cancel, catalog, successful authorized playback and shutdown routes once diagnosed. Protected-profile/server failures and 401/403 retain deterministic evidence. Remote/relay, alternate PMS shapes, large/partial catalogs, smart collections and live membership/portrait probes are documented beta limitations. Do not alter accounts/servers or credentials to manufacture a case. [October 10 Windows procedures](reviews/comprehensive-review-2026-10-10/WINDOWS_HANDOFF.md), [collection plan](osd-autohide-and-collection-membership-plan.md), [Player/Guide plan](player-guide-polish-plan.md). |
| V-06 | macOS declared minimum version | App/runtime target macOS 12 arm64; actual recorded host is macOS 27. | Runtime, TLS/CA, Keychain, presentation and app launch on the older versions actually promised, or explicit agreement to narrow the support range. The maintainer allowed a VM route starting with macOS 12 and stepping up on failure; the maintainer approved installing UTM and downloading the macOS 12 image. Official UTM 5.0.8 is installed with matching release checksum and valid deep signature; Apple CDN macOS 12.6 (21G115) IPSW is downloaded and checksum-verified. The standalone compatibility helper was inconclusive because it lacks the virtualization entitlement; use UTM’s existing entitlement for the actual image check. Guest installation and runtime checks remain unexecuted. Intel/universal is outside the approved first target. [Runtime risks](macos-runtime.md#remaining-work-and-risks). |
| V-07 | Existing physical/spoken acceptance | Automated semantics/native evidence is recorded separately. | User explicitly deferred the **one existing six-item checklist** on October 20, then confirmed readiness on October 21 and requested maximum autonomous work. Actual physical/listening results remain pending and all boxes remain unchecked. Do not start synthetic VoiceOver/modifier work or infer passes from unlock/authentication assistance. [Checklist](handoffs/macos-post-audit-fix-report.md#one-final-human-checklist). Windows Narrator/physical checks retain their separate platform scope. |

## Investigations and unresolved observations

These are not an implementation queue until reproduction or a decision establishes
what should change.

| ID | Observation / question | Current disposition and next discriminant |
| --- | --- | --- |
| I-01 | Historical AX node 866 | Original first-error delta/portal-origin inventory unavailable. Three current Settings→DVR On→Guide→tune attempts do not reproduce. Historically unattributed; capture the first delta only if a fresh failure occurs. No retrospective attribution from a matching string or a healthy run. |
| I-02 | Resize timeouts / backward frame timestamps | Canonical repaired-engine session has six resize warnings; final diagnostic has one 875 µs frame-time clamp. Exact stock-engine runs contain each warning class. Cause/indirect scheduling effects unresolved; no new demonstrated app defect or performance comparison. Investigate with matched traces if reproducible visible symptoms emerge. [Final report](handoffs/macos-post-audit-fix-report.md). |
| I-03 | Windows ancestor-junction containment, October 10 F-008/P-007 | **Likely conditional tooling risk**, explicitly deferred; descendant rejection exists. Establish ancestor-build-junction effects using owned disposable paths and resolve intended physical containment before fixing. Not demonstrated arbitrary overwrite or provenance bypass. [P-007](reviews/comprehensive-review-2026-10-10/REMEDIATION.md#p-007--buildpackage-ancestor-containment-gated), [W-012](reviews/comprehensive-review-2026-10-10/WINDOWS_HANDOFF.md#w-012--ancestor-junction-evidence-and-link-policy-decision). |
| I-04 | Buffer starvation versus user Pause; precommit EOF ordering | Historical buffering and CAND-009 are hypotheses, not confirmed new defects. Recent M-01 stale pause/readiness bug is fixed and is not proof of starvation behavior. Use actual native event ordering/cache starvation on an authorized fixture before changing coordinator policy. [W-004/W-005](reviews/comprehensive-review-2026-10-10/WINDOWS_HANDOFF.md#w-004--precommit-eof-ordering). |
| I-05 | Artwork refresh reachability, aggregate playlist scale and original artwork-test failure | CAND-010/011 need a reachable live scenario/scale result. Package T's original loaded-logo failure remains unexplained; subsequent serialized passes do not prove its cause or flakiness. [October 10 handoff](reviews/comprehensive-review-2026-10-10/WINDOWS_HANDOFF.md), [code-quality evidence](reviews/code-quality-2026-10-15/EXECUTION.md). |
| I-06 | L2 performance | Production initial-load start and correctness gates implemented/reviewed; final protected Plex measurement is **inconclusive**, not a speedup or regression. No benchmark redesign/retry is owed by the old task. Measure again only for a concrete performance decision. [Final L2 addendum](handoffs/macos-l2-controller-status-handoff.md#final-controller-addendum--october-18-2026). |
| I-07 | Optional visual baselines / reported Guide lines | Six optional golden failures reproduced identically on original and final maintainability sources; output images match. Historical expectations need an explicitly scoped visual-baseline decision, not an unreviewed update. An unintended Guide line needs its exact reproduction; intended grid separators are not a bug. [Maintainability record](reviews/maintainability-remediation-2026-10-12/EXECUTION.md), [UX audit](ux-functionality-audit.md). |
| I-08 | Older builds discard newer saved state | Guard implemented October 21 by repository `worker_luna` (gpt-5.6-luna, xhigh), against integration base `dd2b0146`. Integer `formatVersion > 1` raises typed refusal before strict parsing/recovery; startup explains the too-old build without restoring credentials or writing state. Current unversioned writer is unchanged. Store/startup fixtures prove original state/backup preservation and malformed-marker recovery. Controller integration checks pass; independent repository reviewer (gpt-6.1-sol, high) found no material actionable defects. Candidate runtime remains unexecuted. [Forward-format rule](architecture.md#changing-asynchronous-and-persisted-state). Pre-guard binaries remain unprotected and must not be distributed as beta candidates. |

I-08 execution evidence (October 21): the child reported 87 focused persistence/
startup tests, canonical format (160 files unchanged), clean analysis and all
1,872 tests passing with pinned Flutter 3.47.7 / Dart 3.13.5 and
`TZ=America/New_York`. The controller independently reran the 87 focused tests on
the integrated working tree successfully. Full-suite evidence remains attributed
to the child's unchanged Dart inputs; it is deterministic application coverage,
not final-candidate or physical acceptance. No user data was used. Controller canonical format (160 files unchanged), analysis and scoped whitespace
checks also pass. Independent repository reviewer (gpt-6.1-sol, high) found no
material actionable defects in the unchanged four-file diff. The bootstrap
fixture uses prepared file loading and a fake native player; platform-media and
packaged-runtime acceptance remain separate.

## Product plans and earlier campaigns

These are **new or deferred capabilities**, not unfixed regressions. No feature
below is automatically a prerequisite to a stable Direct Play desktop beta.
Choose a release scope explicitly rather than calling every idea core-blocking.

| ID | Capability | Current state / decision needed | Detailed owner |
| --- | --- | --- | --- |
| F-01 | Plex transcoding / Direct Stream and Home/Remote quality | Production pending. P0b selection/subtitle/master/remote evidence and Settings agreement remain; P1 foundation can be assigned independently within the plan's boundary. Original Direct Play remains supported behavior. | [Transcoding plan](plex-transcoding-implementation-plan.md), [project profile](../.agents/project.md#current-planning-and-verification-status) |
| F-02 | Versioned lineup backup, snapshots and reviewed restore | No user-facing workflow; strict current state format/quarantine is not backup/restore. Decide same-server scope, replace/merge, settings inclusion, retention and approved UI; preserve secrets and schedule identity. | [Validated F1](feature-validation-findings.md#f1-lineup-backupexport-and-reviewed-restore--proceed-refined) |
| F-03 | Dynamic whole-show sources and mixed-source Studio authoring | Source types remain Library/Playlist/Manual/Mixed; per-item series metadata is not a dynamic series source. Mixed resolution exists, editable mixed authoring does not. Decide whole-show/subset/overlap and rhythm/order semantics together. | [Validated F2](feature-validation-findings.md), [UX finding3](ux-functionality-audit.md#finding-3-a-whole-show-is-a-source-not-a-bulk-episode-selection) |
| F-04 | Preferred audio/subtitle/accessibility tracks | Current per-load selection exists; persistent policy not implemented. Resolve Plex versus local preference authority and transcoding's persistent server-write conflict before UI/implementation. | [Validated F4](feature-validation-findings.md#f4-preferred-language-and-accessibility-tracks--investigate-first) |
| F-05 | In-session catalog/collection refresh | Restart/Setup rescan exists; a general current-session refresh and actual membership-change timing/rebinding policy are deferred. No fuzzy cross-library/title rebinding. | [Freshness investigation](guide-freshness-collection-investigation.md), [feature validation](feature-validation-findings.md) |
| F-06 | Last-successful-channel recall and favorites | Neighbor stepping exists; recall history/favorites do not. Decide scoped history, shortcut/remote entry and persistence separately; preserve current OSD approval. | [Feature validation](feature-validation-findings.md), [opportunities](feature-opportunity-report.md) |
| F-07 | Broad command discoverability / first-use polish | Now Playing menu entry and named controls implemented; app-wide command inventory and pointer/remote-first walkthrough incomplete. Add controls only for demonstrated missing task paths with design agreement. | [UX finding6](ux-functionality-audit.md#finding-6-now-playing-addressed-broader-discoverability-remains-open) |
| F-08 | Other retained product candidates | Media-version selection, audio passthrough Settings, weighted/time-of-day programming, TV studio/network/actor channels and Recently Added policy changes are separate decisions. Existing source/resolver behavior must not be silently replaced. | [Feature opportunities](feature-opportunity-report.md), [OSD/collection plan](osd-autohide-and-collection-membership-plan.md), [parity history](product-parity.md) |
| F-09 | Android TV / Google TV and Android-based Fire TV | **No platform target, native adapter or acceptance exists in this checkout.** Define a bounded device/media/remote spike after shared core stabilization. Fire OS (Android) is the requested Fire TV scope; Vega is separate. | [Opus platform brief](handoffs/opus-5-5-core-readiness-handoff.md#tv-expansion-feasibility) |
| F-10 | Apple TV | Feasibility only. No tvOS target/adapter; no assumption that the macOS runner or Flutter desktop patches port. Compare a maintained community embedder versus a native tvOS client with explicit shared-domain strategy. | [Opus platform brief](handoffs/opus-5-5-core-readiness-handoff.md#tv-expansion-feasibility) |
| F-11 | Purchases, entitlement, free-tier limits and store business model | Explicitly deferred until playback is finished. Model/limit/upsell/source-visibility decisions are not approved by this handoff. Not a core correctness fix. | [Port decisions](macos-port-plan.md#3-decisions), [monetization](macos-port-plan.md#49-monetization-separate-workstream) |

## Delivery and tooling

| ID | Engineering obligation | Current state / next action |
| --- | --- | --- |
| R-01 | Repaired-engine integration across intended build flows | October 21 source implementation by repository `worker` (gpt-6.1-sol, medium): canonical combined Python authority, fixed Windows outputs, checked consumers without Ninja refresh, schema-2 release/package receipts and separate mode CI jobs. Controller portable checks pass (26 passed, one Windows-only skip), YAML parses, frozen inputs are unchanged, and existing macOS verification succeeds with identical JSON before/after. Independent review found native Windows fixture path and inherited GoogleTest selection issues; the same worker fixed both, and controller source/fixture checks pass. Windows newline/shim fixture assumptions were corrected too. Hosted Windows release-policy and ordinary stock Windows app/native checks passed in CI run 39548870477 at `c767d79d`; combined engine/app/package execution passed at that exact source, including the configured rejection probes. Controller inspected the actual ZIP: all 18 recorded artifact hashes and embedded/build receipts agree. Release engine tests failed as recorded in V-02; Debug remains active. R-01 target-host acceptance and V-02 remain open. Stock caches unchanged. [Engine README](../tool/flutter_engine/README.md), [build instructions](DEVELOPMENT.md#macos-development-app). |
| R-02 | macOS signed archive, sandbox and distribution | Development embedding/ad-hoc signing exists. Team-identity signing/provisioning, hardened-runtime/sandbox loading, data-protection Keychain continuity, browser link/network/CA behavior and TestFlight installation are not accepted. [Runtime signed-sandbox checks](macos-runtime.md#signed-sandbox-checks-still-pending-r1), [port distribution](macos-port-plan.md#48-app-store-distribution-sandbox-and-credentials). |
| R-03 | Notices and source delivery | October 21 design gate completed by repository `worker` (gpt-6.1-sol, medium): [themed in-app Licenses design](handoffs/licenses-design-2026-10-21.md), approved by the maintainer October 21. The same worker returned the 41-file reader/native-resource/source-tooling implementation against `c767d79d`, with exclusive Dart ownership released. Controller verified its content manifest, 13 focused Dart tests, six Python fixtures, all 53 actual prepared resource texts, generated-asset freshness, format/analysis and project lint; independent review established three P2 corrections (all ZIP/companion entry types, completed engine-verification sidecar binding, prior Player return destination). The same worker fixed all three; controller source/negative-control inspection, 17 focused Dart tests, eight Python tests, asset freshness, format and analysis pass. Child full suite passed 1,889 tests after the product fixes. Controller inspected real Flutter fixture renders (normal/large text/small window/partial failure); actual running-app/physical behavior remains unexecuted. Controller integrated the implementation as `ddefaa4e` before candidate build. The candidate-bound source companion was prepared and verified locally (109 source inputs, 129 delivered files), including exact app/ZIP/receipt/engine/runtime bindings. The native adapter also read all 53 documents from the completed candidate bundle with exact text. On the running candidate, the controller opened native component/file lists and offline text plus Sources and rebuilding inventory, then verified Esc restores the same scrolled index and Return reopens its prior invoker at index and Support levels. Actual playback continuity remains unverified because tuning failed; physical/spoken behavior remains separate. R-03 stays open for that final running-playback check and delivery disposition. No sending/publication authorized. Independent legal/Plex/trademark/patent/App Store review remains a pre-submission gate; no legal conclusion is made here. [Runtime distribution notes](macos-runtime.md#distribution-notes-for-the-legal-review). |
| R-04 | Runtime/toolchain upkeep and exact package provenance | Keep pins, dynamic libraries, CA handling and artifact receipts. libmpv/HarfBuzz cross-directory byte identity has documented limits, separate from validated consumed-artifact provenance; do not claim fully byte-reproducible runtime builds. Recheck hosted execution/current package only when required by changed inputs or release. [Runtime risks](macos-runtime.md#remaining-work-and-risks). |
| R-05 | Repository defaults/history | Default branch and optional stale-branch/tag cleanup remain maintainer proposals, not app defects or authorized cleanup. The current local branch is ahead of its last fetched tracking ref; this reconciliation performs no fetch/push/PR/merge/tag changes. |

R-01 controller evidence (October 21): after review corrections, the non-signing
`EngineFixture` selection ran 27 cases, 26 passed and the physical Windows
path-normalization case skipped. Process controls prove full-run selection clears
inherited GoogleTest/TESTBRIDGE filters, sharding, repeat and fail-fast settings,
while exact-name baseline filtering is retained. Path/newline/shim fixtures cover
the source-established Windows assumptions; actual Windows execution is pending. Workflow
YAML syntax parsed with Ruby Psych, and whitespace checks passed. Existing
macOS engine verification before/after returned identical JSON, binary SHA-256
`6a2a93f01e014168d4ea2728fc6fda587d992fde413441129d8d8fb3633a53d0` and
provenance SHA-256
`5609d81f75ab863bbca8b03566fabadec7406806ca8d4af8f3b239c44e65b7c0`.
PowerShell remains unavailable locally. Hosted Windows release policy passed in
CI run 39548870477 at `c767d79d`; the combined engine/app/package job subsequently passed, Release engine tests failed and Debug remains running. The existing Python
suite also ad-hoc signed disposable test binaries before the controller noticed
the blanket signing restriction; no application/candidate was signed. The two
native signing fixtures were not selected in the corrected rerun. The maintainer subsequently authorized ad-hoc identity `-` for new build outputs,
disposable fixtures and existing CI, with existing entitlements/signing settings
unchanged and no re-signing of preserved verified pairs. Disk space was cleared
to 259 GiB; the controller started a fresh durable engine checkout/build at
`~/.cache/lineup-flutter-ax/3.47.7`, using pinned Ninja 1.13.2 with two jobs and
detached logs. No user data was deleted. No push may occur while the dispatched
engine jobs are active. The final candidate build and offline verification subsequently completed as recorded below.

Durable engine outcome (October 21): the fresh Release output
`lineup_ax_release_arm64` under `~/.cache/lineup-flutter-ax/3.47.7` built and
verified. Binary SHA-256
`8daffe9911b489adc26f021034a893c57c54ad84b946bbacfb422ce8c657b09a`;
provenance SHA-256
`4226268a0fa6d4b2bd41e38229d1ea49254191c7e4620561f85203521d7e606c`.
Comparison with the preserved engine matched source/dependency/toolchain/Metal/
Ninja identities. GN content-hash metadata and generated Swift-tool mtime fields
differ, so native-test carry-forward was not claimed. The controller instead built
and ran fresh focused bridge/delegate tests: all 10 common bridge and two macOS
delegate cases passed in both Debug and Release, none failed or skipped. The
controller independently parsed all four XML files and confirmed those outcomes.
Selected Release engine verification remained unchanged after the test runs.
Existing app/engine pairs and stock caches remain untouched.

### October 21 candidate artifact evidence

Controller-owned durable provisioning, native recovery tests and candidate build
completed successfully. I-08 (`f2ff07cd`) and approved R-03 (`ddefaa4e`) are included;
R-01 tooling (`c767d79d`) precedes both the candidate and the active Windows CI
run. Executors: I-08 `worker_luna` (gpt-5.6-luna, xhigh); R-01/R-03 `worker`
(gpt-6.1-sol, medium); independent read-only review `reviewer` (gpt-6.1-sol, high).
The controller owns the actual build and artifact checks. File scopes and
implementation verification are attributed in the corresponding rows above.

The candidate was built from clean committed source, copied with both receipt
sidecars, and canonically verified before any subsequent commit. The pinned
stock `flutter pub get` was run afterward. The controller independently repeated
bundle verification, strict deep signature verification, source-companion
verification and artifact hash comparisons. All passed. The standalone native
resource adapter compiled from the candidate source and read all 53 bundled
notice/patch/build documents exactly; this is an offline bundle-bound check,
not a running UI or playback observation.

Candidate directory: `~/.cache/lineup-candidates/direct-play-2026-10-21-ddefaa4e`.
It contains `Lineup Desktop.app`, its build receipt and final engine-provenance
sidecar, `Lineup-Desktop-direct-play-ddefaa4e.zip` and `source-companion/`.
Private logs/results remain under
`~/.cache/lineup-stabilization/2026-10-21/{durable-native-tests,beta-candidate-ddefaa4e}`.
These artifacts are prepared locally; none has been sent or published.

| Candidate identity | Value (SHA-256 unless stated) |
| --- | --- |
| Source commit | `ddefaa4eb36934d54a57f26c645c9d078b9731b5` |
| Compiled Dart | `b2974c66b9dec2594bca6fe7cd51b9b4e43c46c8ce1a05d3bbf80ce249907b80` |
| Selected raw engine | `8daffe9911b489adc26f021034a893c57c54ad84b946bbacfb422ce8c657b09a` |
| Bundled engine | `30a29606b5fa7686512d4e3ecf98ea8c419763fde014d3652fd46996a8381219` |
| Runtime BUILD-INFO | `b6b0f67b9d7c3e74e1089db05621c65d1aec850a3326e22f9172515ed2018899` |
| App build receipt | `c02cd13a4bb061b312e00d56a483cabd49748496f599ff8fc65f0cc75e3e01fd` |
| Final app engine-provenance | `92c9cb75ada89e200943937ba1560f4af2b15cfee395a30a2eae2c62604cfe8d` |
| Candidate ZIP | `2c8ee209c49d714d808f873c1d6a921882cbfc2c529f0764a70f1a8a5d4fcda3` |
| Source-companion manifest | `a10d6416e46d63f4ffd31edebaf08c2dd01742cc1377eb53ab6e08f377e6baa3` |

**Not accepted.** The controller started the candidate after the maintainer
confirmed availability. `lsof` identified the loaded Flutter image inside the
durable candidate bundle; its SHA-256 matches the bundled engine value above.
Initial Computer Use capture failed with -3811. After the maintainer confirmed
wake/unlock, the controller observed saved Guide/current catalog restoration,
verified Plex connection and two immediate native source-open playback failures.
The first redacted report is stored privately as
`candidate-live/candidate-first-tune.rtf`; source commit and failure codes are
attributed above. Themed Licenses native documents and source inventory opened;
Back/Esc/Return observations establish the specific scroll/focus returns described
in R-03. No physical keyboard, spoken, listening or successful-playback pass is
inferred from automation. Later capture failed -3812 across app bindings; the
maintainer was asked only to foreground UTM while independent work continued.
No credentials were entered. Candidate process/log evidence stays private in
`candidate-live/`; no graceful-quit result has yet been claimed.

Selected V-04/V-05 live routes, running Licenses playback continuity, graceful
quit, V-06 and actual V-07 human results remain open. The existing six-item human
checklist owns physical/spoken acceptance; zero boxes are inferred. Windows
packaging passed at `c767d79d`, Release engine tests failed and Debug is active;
no push is permitted while it runs. Later prose-only commits do not change this
candidate's source/artifact identity.

V-06 preparation (controller, October 21): after the maintainer's explicit UTM/
image approval, disk inspection showed 224 GiB free. UTM 5.0.8/build 128 was
installed at `~/Applications/UTM.app` from the
[official release](https://github.com/utmapp/UTM/releases/tag/v5.0.8), with DMG
SHA-256 `7b2d7b2e2a02b3de1757ef19a8f36573e6d9cceae8c8cca0abcbcaa4a852019a`
matching GitHub's release asset and deep strict app signature verification passing.
The macOS 12.6/build 21G115 restore image was downloaded from Apple's CDN; size
14,081,739,387 bytes and indexed SHA-1 match, locally recorded SHA-256
`5113f8d3c77fd725ea6357ced5764bc57183d2d388492c58c46ff2729d0658e5`.
Download/source metadata and detached inspection logs remain private under
`~/.cache/lineup-stabilization/2026-10-21/v06-vm/`. The older image's third-party
index marks it unsigned; successful download is not an installation/compatibility
pass. The standalone read-only Apple Virtualization helper returned image-load
error 10004; the API requires `com.apple.security.virtualization`, which the
helper lacks. That result is inconclusive about the image or OS support. Use
UTM’s existing signed entitlement for the next check; no helper/application
entitlements were added or changed. UTM’s CLI exposes no guest-create command.
The controller opened UTM, selected Apple virtualization/macOS 12+, and entered
four cores/8192 MiB. The IPSW Browse button is omitted from its accessible tree;
coordinate capture returned a tiny background thumbnail, then -3812 despite a
fresh binding/session. The maintainer was asked to foreground UTM. No image has
yet been selected in UTM, and guest creation remains unexecuted. No existing
application/engine pair, stock SDK cache, host security setting, entitlement, or
credential has been changed. No VM runtime support
floor is established by this preparation.

Windows package/result inspection (controller, October 21): actual hosted job
119053306743 passed the combined-engine app build and package step, including
tracked symlink, reparse point, dirty source, stale marker/engine identity,
schema-1/reordered/missing-patch/manifest/provenance/DLL and altered/missing
artifact/runtime-license rejection probes. Downloaded package ZIP SHA-256
`a8946784faecb7727b552cb7fa7412f0702b2b04c5f80a80b92bfccb1df25671`;
engine DLL `9433e46c523933a768ff0bb0fc8e8996ce060e823868a1b98b7b9f475064c206`;
engine provenance `f88c572619c555856be30c162392cc7a042925846e1bb326cff1f1a67d94b1d7`.
Controller streamed all 18 receipt-listed artifacts from the ZIP and matched
hashes; the embedded receipt equals the build's combined-engine record. Ordered
patch bytes match this repository. Pin/manifest byte hashes match the Windows
CRLF checkout representation rather than macOS LF bytes; all three exact CRLF
comparisons agree. No Windows application launch/physical package acceptance
was performed. Private downloaded artifacts and sanitized inspection JSON are in
`~/.cache/lineup-stabilization/2026-10-21/windows-ci-39548870477/`.

Release result: 240 common cases passed without failures/skips. The Windows log
started 395 cases, failed the new native recovery case and multiple upstream
cases on missing AOT/VM fixtures, then aborted on the 300-second
`FlutterWindowsEngineTest.MergedUIThread` timeout. Its XML and `summary.json` are
absent; no DC-only attribution result is available. Existing R-01 `worker`
(gpt-6.1-sol, medium) owns a focused Python/CI investigation against integration
base `23dd5856`, excluding frozen macOS recipe/pins/patches and product sources.
It returned no source changes: pinned Windows tests hardcode dummy/omitted AOT
properties and contain JIT mocks, while upstream runs this suite in Debug only.
The failure cannot be corrected by an invocation/cwd/file-copy change alone.
A read-only follow-up is preparing a concrete native fixture/provenance proposal;
implementation awaits the resulting scope/identity decision. Debug/optimized-JIT
substitution, skipping cases and waiving required recovery cases are not approved.
The R-03 `worker` (same model/effort) separately owns read-only V-04 source-open
diagnosis with isolated synthetic checks; it may not touch the live app/PMS,
credentials, user data, Dart tools, repository files or Git. Controller retains
all integration and UI ownership. Any source/entitlement/strategy change outside
those boundaries must return with evidence before implementation.

H's PowerShell pin assertion was source-only in its original code-quality campaign;
later Windows policy/CI evidence exists. Do not perpetually label all PowerShell
work unexecuted, or infer a fresh run of every old assertion. Select the actual
assertion needed for the current candidate. Maintainability M07/M09 and October 10
P005 are implemented; their native/package limits route to V-03/R-01 rather than
separate duplicate fix packages.

## Code-quality physical checklist

W1–W12 remain scenario references in the [code-quality plan](code-quality-implementation-plan.md#10-windows-physical-acceptance-checklist-batched),
with V-03 tracking their unresolved exact-platform proof. W4–W6 depend on actual
native restoration/lifecycle gates, not a new source merge. F was historically merged
at `4f3b144a7989a0ba9f0096bf88bb265dd817bf7f`. That commit is **not** an
ancestor of this branch, but all nine restoration/admission/guardian/recovery/
handle source and test files match it byte for byte. The player/encoder later
moved to the shared core; do not infer identical whole-native trees from that
file comparison. Later CI exercised display dynamic range, guardian
and player-contract tests; `runner_lifecycle` remains unobserved here. Old review
statements that F is unmerged or that none of its suites ever ran are superseded.
Do not create another physical checklist; retain the existing per-platform owners.

## macOS media backlog

Native macOS playback is **implemented**, not merely proposed. The shared C++
core, Objective-C++ adapter, MoltenVK/CAMetalLayer presentation, native fullscreen,
Mac shortcuts, runtime embedding/notices, authenticated-reference checker and CI
recipes exist. H1 HDR publication and L1 join/user-seek behavior have attributed
physical/target-runtime acceptance; L2 is implemented and its correctness gates
are complete, with inconclusive performance measurement. See [port progress](macos-port-progress.md),
[HDR/seek verification](handoffs/macos-hdr-and-seek-verification-report.md) and
[final L2 addendum](handoffs/macos-l2-controller-status-handoff.md#final-controller-addendum--october-18-2026).

The first target remains Apple Silicon; macOS 12 is a declared deployment target,
not an observed support matrix. This is a working development/pre-release player,
**not an accepted signed public release**. Current unfinished work is V-01/V-04/
V-06/V-07 and R-01–R-04, with features selected separately. Accepted HDR/Dolby Vision
picture quality is not reopened for the same configuration. The six-item human
checklist is deferred at the user's request, with no inferred passes.

## Completed or superseded audit items

| Earlier finding / package | Reconciled disposition and evidence |
| --- | --- |
| October 10 confirmed F001–F007 / P001–P006 | Implemented: accepted-profile/PIN recovery, Guide activation/search ownership, worker disposal readiness, temporal/persisted-duration validation, reference-harness natural completion and multipart seek coordinates. [Implementation](reviews/comprehensive-review-2026-10-10/IMPLEMENTATION.md). Windows runtime proof retains V-03; F008/P007 is I-03. |
| October 12 audit follow-up seven findings and maintainability nine packages | Implemented/reviewed: track-label reuse, image lifetime, stale publication, build/formatter/SDK authority, setup projection and ownership/native lifetime repairs. [Follow-up](reviews/audit-followup-2026-10-12/IMPLEMENTATION.md), [maintainability](reviews/maintainability-remediation-2026-10-12/EXECUTION.md). Optional baseline issue is I-07; native delivery limits V-03/R-01. |
| October 15 code-quality packages including F | Portable composition accepted; F merged for testing, later partial native CI evidence exists. No missing merge to repeat. Remaining exact gates V-03. [Final review](reviews/code-quality-2026-10-15/IMPLEMENTATION_FINAL_REVIEW.md), [Windows handoff](reviews/code-quality-2026-10-15/WINDOWS_HANDOFF.md). |
| macOS audit M01/M02/M03/M05 and Q01/Q02/Q03 | Corrections implemented and independently reviewed: truthful observed pause, directory semantics, icon names, Settings return, build identity, accumulated step requests and current error identity. Native and regression scopes are in the [closing report](handoffs/macos-post-audit-fix-report.md). Spoken acceptance stays V-07. |
| Subsequent Pro-review/focus/tooltip/Slider defects | Demonstrated application triggers corrected; Player group/order approved and preserved; focus recovery `829547b4` has before/after and native checks. Engine repair is B-01, not another unimplemented application workaround. [Current report](handoffs/macos-post-audit-fix-report.md). |
| Old macOS unsupported/backend-not-implemented claims and pending H1/L1/L2 production proposals | Superseded by implemented source and later accepted evidence. No need to redo the media-engine/presentation choice or original HDR loop. |

## Archive recovery and preservation map

Every command below resolves at the full immutable pre-G commit. Run from the
repository root; it recovers the entire original document including attributed
results, rationale and source/build identities. It does not reactivate its old
workflow or make its dated claims current. Retained review files may still link
to these removed paths as historical citations.

| Historical source | Recovery command | Sections and retained owner | Reason / evidence boundary |
| --- | --- | --- | --- |
| `desktop-ui-implementation-plan.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/desktop-ui-implementation-plan.md` | §§P0–P8, Data and operation gates, Input and state acceptance matrix; current owner: Architecture async/persistence contracts; Desktop UI design specification; Windows native validation. | Completed delivery procedure; preserve frozen source/schedule decisions and extended acceptance above. |
| `desktop-ui-execution.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/desktop-ui-execution.md` | §§Baseline and evidence, P0 operation/recovery, P0 source/schedule, R1 adjudication, September 9 closeout; current owner: Architecture; Desktop UI design/specification, surface approvals and second-pass decisions. | Dated implementation and attributed review history, not a new execution mandate. |
| `desktop-ui-readiness-review.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/desktop-ui-readiness-review.md` | §§Findings and adjudication, Follow-up verdict; current owner: Desktop UI design specification; Architecture. | September 8 planning review passed after corrections; not production or hardware proof. |
| `desktop-ui-scaling-progress.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/desktop-ui-scaling-progress.md` | §§Settled implementation direction, Groups 1–6, Scaling campaign closeout, Settings follow-up; current owner: Desktop UI design specification; surface approvals; second-pass F8; Windows native validation. | Portable presentation evidence; September component scaling is historical and later second-pass F8 owns the approved root scaling rule. Per-group identities/capture qualifications remain in the snapshot. |
| `ui-parity.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/ui-parity.md` | §§Provenance and authority, Prompt 3B–4E, VPP-7 physical result, August 27/30 closeouts; current owner: Architecture; Desktop UI design and decision records; dated Product Parity audit. | Historical campaign classifications, source identities and synthetic evidence are recoverable, not current support claims. |
| `fullscreen-hdr-discovery-plan.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/fullscreen-hdr-discovery-plan.md` | §§Discovery result (October 9, 2026), Pinned-source pre-analysis, Completion criteria; current owner: Fullscreen HDR specification and implementation plan; discovery summary in this register. | Completed Win10 feasibility discovery; preserve exact build identities, predictions versus observations and untested cases below. |
| `windows-collaborative-acceptance-handoff.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/windows-collaborative-acceptance-handoff.md` | §§0–7, Target and setup, Safety, Finish; current owner: OSD/collection plan; startup/reentry and Player/Guide decisions; Windows native validation. | Old copy-ready prompt archived; its scenario, measurement and probe obligations remain open above. |
| `code-quality-refactor-planning-handoff.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/code-quality-refactor-planning-handoff.md` | §§2–3, CQ-01–09, 6–8, 10, 12; current owner: Code-quality implementation plan §§3–4, 7–10; Architecture; native-player protocol. | Assessment rationale and confidence limits retained in full; F remains governed by the active implementation plan, not closed by this archive. |

The startup/reentry and Player/Guide polish plans are **retained**: their
October 7 decisions and approved render refinements uniquely record live product
contracts and supersessions. Their stale status headings are corrected rather
than deleting approval authority. Desktop design specification, surface approvals,
second-pass decisions, fullscreen HDR spec, the interface system, feature inputs
and validation findings are retained. The code-quality plan stays active for F.

The desktop execution snapshot preserves baseline
`d221efbb0aaaa7846be2d8666254fbd78bddc738`, Flutter 3.47.0
`4cf24164269a5ebf0c16a028a00727d0e77bbb05` / Dart 3.13.0,
737 baseline tests, R1/R2/R3 adjudications and successive checkpoint results.
Its backup-before-migration, strict legacy reads, canonical source semantics,
cycle boundary, atomic stale-base checks and privacy contracts now live in
Architecture and the retained Desktop UI specification. Later approvals live in
surface approvals, second-pass and Player/Guide records; obsolete intermediate
review statuses do not override their later corrections. Scaling/parity snapshots
retain each capture/source identity and qualification in full, rather than
promoting all intermediate claims into a new baseline.

The HDR snapshot preserves target
`50c4e9d345209a1e504b2d9b8190ee4fe2a152b0`, trace
`a1dd26933d58aae8fd8cdbd4ec6a9e8ec9578768` (discovery-only, do not merge),
Windows SDK 10.0.26100.0, Windows 10 Home 10.0.19045,
NVIDIA RTX 5080 / driver 32.0.16.1714, Sony A90K HDMI 3840×2160/120 Hz.
Baseline EXE SHA-256
`A04B5A7BE5D8062FB7DCC81CCC47D59AECFEDBF442FBDC9D48E35570577E7389`,
trace EXE `02B1DB441E0FC3ACB8AC794158879B8866CB44DF54AD5DEB03BEDFC8D953A1F5`,
and probe `1C770E4FDBDAA2D981E1510B69FC9A8F858156D06429644E6883EA19AC88C907`
identify that run only. Existing composition qualitatively passed SDR/static HDR10;
no explicit renderer refresh or FP16 was needed. API route and timing tables,
operator observations versus pinned-source predictions, and omitted cases remain
recoverable in the full snapshot. Current identities come from build metadata and
runtime provenance, never these old pins.

The code-quality assessment snapshot preserves its inspected source, confidence
limits, CQ-01–09 mechanisms and rejected alternatives. Architecture and the active
implementation plan carry its distinct request/authorization/content/native
lifetimes, observed-versus-requested track state, persistence/publication/credential
ordering, manual occurrence identity and display late-write liability. The archive
adds no generic framework, schema migration, native rewrite or feature scope.
