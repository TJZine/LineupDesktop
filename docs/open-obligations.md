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
| B-01 | Desktop Flutter AX bridge rejects unreachable/moved updates and cannot safely recover from failed mutations | Repair implemented in `831c28fc`; historical canonical app integration verified through source `0208982e`. October 21 durable canonical Release engine independently verified; current app `8c98fb80` passed clean artifact gates and bounded live playback/reader/rollover/quit observations. Actual Windows Debug/Release recovery suites passed at `4f2e2429` (V-02). Historical Mac focused Debug/Release recovery tests retain their original engine attribution. Stock SDK/cache remain unchanged and the repaired engine is opt-in. | V-01 remaining timing/runtime evidence, V-06 support-floor disposition and V-07 human acceptance. M-04 overall remains open. [Current report](handoffs/macos-post-audit-fix-report.md), [engine investigation](handoffs/macos-ax-update-investigation.md). |

Do not promote the ancestor-junction risk, buffering/EOF hypotheses, timestamp
warning or historical node 866 into confirmed current application defects without
the discriminating evidence in the investigation rows below.

## Verification gaps

| ID | Obligation | Evidence already available | Exact unfinished gate |
| --- | --- | --- | --- |
| V-01 | Initial OSD fade/menu continuity and natural Slider interactivity transition | Retained frame/widget regressions, stock keyed/unkeyed reductions, canonical native continuity and useful diagnostic seek. Four automatic first-fade attempts plus a bounded manual probe do not qualify; three natural routes mount already-interactive Sliders. | Actual menu opening within the initial 350-ms fade with recorded animation/timing; a same-presenter enabled/disabled transition where naturally feasible. Do not add a product control to force it or repeat an unbounded campaign. [Recovery assignment](handoffs/macos-m04-recovery-implementation-handoff.md#d-resolve-remaining-runtime-uncertainties). |
| V-02 | Repaired Windows engine | Actual [CI run 39572081886](https://github.com/TJZine/LineupDesktop/actions/runs/39572081886), source `4f2e2429`, passed canonical DC/AX/fixture Debug and Release full suites. Controller inspected retained XML/log hashes, normal execution records and diagnostic summaries: Debug 242 common / 396 Windows passes; Release 240 / 395. All twelve required recovery cases passed per mode; each Windows suite retains only existing disabled `MockWindow.DISABLED_GetObjectUia`. No DC-baseline exclusions. Six representative cases passed per mode; Release missing-AOT red/restored-green and exact fixture restoration passed. Earlier failed Release run 39548870477 remains historical evidence below. | CI-executable engine-test gate passed at the attributed source. Physical Windows media, composition, input and runnable-package acceptance remain outside this macOS beta and route to V-03; none follows from hosted tests. [Engine instructions](../tool/flutter_engine/README.md). |
| V-03 | Windows native lifecycle, physical media and exact package | Later recorded CI run [39383128215](https://github.com/TJZine/LineupDesktop/actions/runs/39383128215) passed stock Windows build and eight explicit CTests: encoder, playback state, core, codec, display dynamic range, guardian, player contract and authenticated reference. Earlier L2 Windows auth/package gates also passed at their recorded identities. | `runner_lifecycle` is still outside current CI and lacks recorded execution here. Run it with its actual patched-engine prerequisites. Physical playback/parts/EOF, HDR/restoration, tracks, input, monitor/DPI and clean-system package remain distinct. Revalidate changed inputs; do not repeat all earlier tests solely because an old handoff says pending. [Development tiers](DEVELOPMENT.md#current-test-tiers-and-gaps), [physical/package procedure](windows-native-validation.md). |
| V-04 | macOS real-app reliability beyond recorded scenarios | Current canonical app `8c98fb80` passed clean artifact verification and loaded-engine hash checks. After maintainer Keychain approval, owner local-PMS current playback reached native readiness and displayed video; Guide/Settings/native notices/source-reader navigation returned to continuing video. Native menu Settings, fullscreen exit, minimize and Window-menu restore were observed. This build reached natural EOF with mpv error 0, then a successor accepted/opening/ready session and visible video; normal native-menu Quit exited 0. Earlier `ddefaa4e` source-open failures remain attributed and their original cause unproven; they did not reproduce on this build. | Sustained listening/audio drift, true live resize/minimum size, multi-display/Spaces/Stage Manager and sleep/wake remain in the existing human checklist. Automated actions establish bounded observations, not physical acceptance. |
| V-05 | Real Plex scope, catalog and recovery edge cases | Current app `8c98fb80`: saved owner lineup restored; an available unprotected Home profile connected to the same PMS and completed three selected library scans without applying a generated lineup. Maintainer locally unlocked owner restoration; the renewed owner connection labeled Direct local and current authorized playback displayed actual video. Initial Direct remote playback is separately attributed. | Unambiguous live scan cancel/retry evidence remains pending; fast scans and changing UI prevented isolated attribution. On October 21 the maintainer explicitly retained these live checks as pending; deterministic tests do not close this beta gate. Protected-profile/server failures and 401/403 retain deterministic evidence. Remote/relay, alternate PMS shapes, large/partial catalogs, smart collections and live membership/portrait probes remain beta limitations. No account/server configuration or credentials were changed by the controller. |
| V-06 | macOS declared minimum version | Controller tested exact `8c98fb80` in approved macOS 12.6 (21G115), 13.0 (22A380) and 14.6.1 (23G93) Apple Virtualization VMs, each four cores / 8 GiB. The macOS 14 controlled renderer comparison and authenticated/media observations are recorded below. Candidate hashes and deep strict signatures matched; quarantine was preserved and separately approved one-app Finder Open exceptions applied. Cold native notices, authenticated PMS access, five selected library scans, guest-local lineup creation, saved-account/lineup restoration and normal menu Quit were observed in the macOS 12/13 guests. | Default current-program activation aborts in guest Metal/IOGPU argument-encoder creation during MoltenVK initialization in all three guests. Intermittent glyph corruption also remains; these VM-only failures do not establish physical-hardware failure. A process-only `MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0` diagnostic reached actual changing video and native readiness in macOS 13, then normal Quit; macOS 12 still aborted later in libplacebo. This diagnostic does not establish unchanged default-candidate support. Native media TLS/CA was not separately established. The promised older-OS support floor remains unresolved: establish it on suitable hardware/default runtime or obtain an explicit narrower tested-support decision. Host default playback remains attributed to macOS 27.0.1 (26A434). Intel/universal is outside the approved first target. [Runtime risks](macos-runtime.md#remaining-work-and-risks). |
| V-07 | Existing physical/spoken acceptance | Automated semantics/native evidence is recorded separately. On October 21 the maintainer explicitly chose **Leave V-07 unverified** for the later limited-candidate decision. | All six boxes remain unchecked; this disposition does not accept the beta or establish physical/listening behavior. Do not start synthetic VoiceOver/modifier work or infer passes from unlock/authentication assistance. [Checklist](handoffs/macos-post-audit-fix-report.md#one-final-human-checklist). Windows Narrator/physical checks retain their separate platform scope. |

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
| R-01 | Repaired-engine integration across intended build flows | Repository `worker` (gpt-6.1-sol, medium) implemented the canonical authority, checked Windows consumers, schema-2 receipts, no automatic Ninja refresh, per-mode CI and the approved fixture migration (`bbb45768`). Independent `reviewer` (gpt-6.1-sol, high) cleared inspected corrections; controller portable integration checks passed 34 with one physical-Windows-path skip. Original frozen macOS verification was identical before/after initial tooling integration. Actual CI run 39572081886 at `4f2e2429` passed all jobs, including both engine modes and combined engine/app/package execution. Controller matched all 44 packaged artifact hashes, embedded receipt, DLL identity and ordered recipe inputs; rejection controls executed in the successful package job. Fresh canonical Mac engine built and independently verified with the approved changed manifest; clean `8c98fb80` app build/verification passed. Existing verified pairs and stock caches are preserved. | CI-executable integration gates passed at `4f2e2429`; current Mac artifact gates passed at `8c98fb80`. Physical Windows package acceptance remains V-03; Mac support-floor/human acceptance remain V-06/V-07. [Engine README](../tool/flutter_engine/README.md), [build instructions](DEVELOPMENT.md#macos-development-app). |
| R-02 | macOS signed archive, sandbox and distribution | Development embedding/ad-hoc signing exists. Team-identity signing/provisioning, hardened-runtime/sandbox loading, data-protection Keychain continuity, browser link/network/CA behavior and TestFlight installation are not accepted. [Runtime signed-sandbox checks](macos-runtime.md#signed-sandbox-checks-still-pending-r1), [port distribution](macos-port-plan.md#48-app-store-distribution-sandbox-and-credentials). |
| R-03 | Notices and source delivery | Approved themed reader implemented by repository `worker` (gpt-6.1-sol, medium), independently reviewed by `reviewer` (gpt-6.1-sol, high), integrated before the candidate. Controller attributed focused/full tests, actual prepared-resource reads and renders below. Current canonical app `8c98fb80` passes actual cold in-app native list/file/text loading before any native Settings, correcting the former missing-plugin registration failure (`5e05ac0b`). Actual video continued through native offline notices, Sources/rebuilding, Escape/scroll/invoker restoration and return to Player. Its bound source companion verified locally: 109 inputs / 140 delivered files, including exact canonical recipe, complete vendor source/delta and current candidate/engine/runtime bindings. | Delivery remains local; no sending/publication authorized. V-07 spoken/physical behavior and remaining candidate gates are separate. Independent legal/Plex/trademark/patent/App Store review remains a pre-submission gate; no legal conclusion is made here. [Approved design](handoffs/licenses-design-2026-10-21.md), [runtime distribution notes](macos-runtime.md#distribution-notes-for-the-legal-review). |
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
CI run 39548870477 at `c767d79d`; the combined engine/app/package job subsequently passed, Release engine tests failed and Debug subsequently passed. No engine job is now active. The existing Python
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
packaging and Debug engine tests passed at `c767d79d`; Release engine tests
failed. The workflow is complete, and no engine job remains active. Later prose-only commits do not change this
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
The controller opened UTM and created `Lineup V-06 macOS 12.6`, with four cores,
8192 MiB memory, a new 64-GiB drive and no shared directory. After the maintainer
foregrounded UTM, a fresh sheet-only screenshot supplied the correct coordinate
mapping for Browse; the verified image was selected. UTM accepted it, installed
onto the new empty drive and booted to Monterey Setup Assistant. The controller
selected US locale and skipped data migration and optional Apple ID sign-in.
The maintainer completed the license/account setup and reported the guest desktop
ready; the controller observed Monterey's desktop in UTM. No agreement was
accepted or credential entered by the controller. No existing application/engine pair, stock SDK cache,
host security setting or entitlement was changed. The candidate has not yet been
transferred or executed in the guest; no runtime support floor follows from this
preparation.

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


Debug completion (controller inspected October 21): run 39548870477 is complete.
Actual `common_cpp_unittests.xml` has 242 passes; Windows XML has 396 passes and
one preexisting disabled case, `MockWindow.DISABLED_GetObjectUia`. All ten bridge
and two Windows recovery cases were individually checked as run/completed with
no failure/skip. Summary records no DC-only exclusions. Debug engine binary
SHA-256 `d77d70b8509d62695af31e45275dd69d1f795f8d87435d1c7704fb25fe7f2c70`;
provenance `cec9a6936804b23006cb701b26d7feb219d7b86804980d9dd01bda5d18cfd254`.
Sanitized independent inspection is saved as `debug-inspection.json` beside the
private downloaded artifacts. This does not substitute for failed Release.

V-04 diagnosis completion: the repository worker (gpt-6.1-sol, medium) changed no
files. The controller confirmed the returned report hash and all 54 synthetic
case outcomes. All 18 candidate-loaded media dylibs equal the prepared runtime;
BUILD-INFO is unchanged. Candidate sandbox/network-client entitlements are
present; safe environment-name inspection found no relevant proxy/TLS/DYLD
variables. A bounded retained-log search found no genuine sandbox denial, which
is limited absence evidence. The synthetic harness supplies a private test CA,
clean environment and null audio/video; it does not prove default trust, actual
PMS part/range/redirect behavior or sandboxed physical playback. Source tracing
also explains how subsequent cancellation can produce the generic
`player_unavailable` after the initial native failure; that trace does not prove
the source-open cause or authorize a playback-order change.

A new controller-authorized worker unit implements a small disabled-by-default
first-open developer probe: only allowlisted module/cause categories, bounded
native END_FILE error integers and already-observed HTTP status, with per-load
bounds and privacy controls. No URL/path/header/token/raw native text, public
protocol/UI/Dart change, security relaxation or playback-policy repair is in
scope. The controller will inspect/test the returned diff and owns any diagnostic
app commit/build/launch under a new exact identity. It is not a beta acceptance or
source-open fix. Results stay private under the existing stabilization cache.

The separate [Windows Release fixture design](handoffs/windows-release-fixture-design-2026-10-21.md)
records the reviewed source evidence and both migration choices. The controller
recommends one canonical recipe plus fresh engine/candidate identities to avoid
maintaining a second test-source authority; the worker's isolated-overlay option
preserves the current Mac pair at the cost of that extra authority. This is a
consequential change to the frozen-identity plan. The maintainer approved
“canonical recipe and rebuild” on October 21. Before migration, the controller's
macOS Release verification passed again with unchanged binary/provenance hashes
(`8daffe99…`, `4226268a…`). The existing pair is preserved. Disk check reports
184 GiB available; fresh provisioning must account for that bound without deleting
existing data. Native fixture/recipe implementation and rebuilt acceptance remain
pending.

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

October 21 approved migration execution: the repository worker (gpt-6.1-sol,
medium) prepared a Windows-only fixture patch across the seven approved test
files. Scratch application/reverse controls pass for combined and DC-only source;
no Windows execution is claimed. After the controller completed the separately
identified first-open diagnostic build with the preserved recipe, the worker completed canonical metadata/consumer
edits. Integrated checks and independent review are in progress; Windows execution
remains pending. A fresh isolated engine checkout finished provisioning
at `~/.cache/lineup-flutter-ax-fixtures/3.47.7`; disk check before starting was
184.8 GiB free. Its log/status are under the private stabilization cache's
`canonical-fixture-engine` directory. Existing verified engine trees are intact.

The native first-open probe worker returned four scoped source/document paths.
Controller rebuilt the existing portable native targets in a fresh output and
all three CTests passed (encoder, playback state, player core contract). Independent
read-only review found no material actionable defect. These fake-libmpv contracts
establish default-off
silence, bounded privacy and event behavior, not the live source-open cause.

V-04 diagnostic integration: independent repository reviewer (gpt-6.1-sol, high)
inspected the exact four returned file hashes and found no material actionable
defect. Controller rebuilt from those sources and all three native CTests passed.
The default-off bounded stderr probe is integrated for a separate diagnostic
build; its categories remain hints and successful live playback is still pending.

October 21 additional controller observations: the separate diagnostic build at
`efb02676` passed canonical bundle/receipt verification and deep strict signature
verification on a clean source tree, with no intervening commit. The pinned stock
`flutter pub get` ran afterward. Its compiled Dart SHA-256 is
`ead442f899b94aa5c74430f19a0ec2642f15482d636a0ef6b0efebe5449bcf1d`;
the build receipt SHA-256 is
`23d31aa9083b40894954438cd07b96bf2002063f4f641af542466a6f2c65a3e9`.
It uses the preserved verified engine (bundled SHA-256
`30a29606b5fa7686512d4e3ecf98ea8c419763fde014d3652fd46996a8381219`),
independently matched to the loaded process. This is a diagnostic identity, not
a replacement candidate. Startup initially waited while macOS SecurityAgent
was running; Computer Use explicitly refused that app, and the maintainer then
handled the Keychain prompt locally before the observation below.

V-06 actual old-candidate observation: Monterey 12.6 (21G115) launched the
verified `ddefaa4e` app only after the maintainer explicitly approved a one-app
Gatekeeper exception in the disposable test VM. No global security setting or
quarantine-removal command was used. Native guest text remains readable while
Flutter glyph textures are corrupted; native Licenses reports that its documents
could not be loaded, while the Flutter dependency list is present. Repository
worker (gpt-6.1-sol, medium) is investigating the exact bundled compatibility and
resource paths read-only. No account sign-in, successful playback, TLS/CA or
Keychain pass is inferred. The new canonical candidate still needs affected
retesting. The existing host candidate shut down through its normal Quit menu,
and its detached launcher recorded exit code 0.

V-04/R-03 diagnostic observation at `efb02676`: after the maintainer handled
the host Keychain prompt locally, the controller tuned one current authorized
local selection. The finite native probe recorded `accepted`, `opening`, then
`ready`; actual video was observed before and after navigating Settings → Support
→ Licenses → package list → offline text, then Back/Esc to Guide and Player.
No source-open failure occurred in this observation. This does not establish
its earlier cause, audible continuity, physical input or final-candidate
acceptance. Native notices failed on this host diagnostic too, with Retry
unchanged, while packaged Flutter license text opened. Both candidate and
diagnostic contain 53 regular native resource files, no symlinks, hidden
entries or empty files. A bounded default-off failure-stage probe is assigned
to the repository worker (gpt-6.1-sol, medium); no speculative resource fallback
or security change is approved.

V-06 compatibility source finding (same worker, read-only): all inspected
runner/engine/compiled-Dart/media outputs target macOS 12, but bundled
`objective_c.framework` declares macOS 13. The pinned Flutter native-assets
tool passes a hardcoded 13 into that package's hook; the framework participates
in path_provider startup. This is a concrete target-consistency gap, not proof
that it causes the observed resource or glyph failure. Preserving the approved
12 target needs a reproducible native-asset correction and actual guest
reverification; no support-floor change is inferred. The guest auto-locked
before the next resource check; its password entry remains with the maintainer.

R-01 migration integration gate: controller portable checks ran 32 tests in
91.993 seconds: 31 passed, one physical-Windows-path test skipped. Independent
reviewer (gpt-6.1-sol, high) established an abnormal-exit attribution gap: valid
failure XML could mark a crashed process complete. The worker repaired normal
exit enforcement (only 0/1), demonstrated red before/green after, and reported
33 fixture tests: 32 passed, one Windows-only skip. Controller is also requiring
the approved representative and missing-AOT/restored-green checks to be wired
into the hosted execution before dispatch. Those changes and target execution
remain pending; no new Windows pass is claimed.

Canonical fixture migration ready for integration: controller confirmed the
reviewed manifest/runner/test/patch hashes, byte-identical original pins and
three existing patches, and `git diff --check`. Final controller EngineFixture
run: 35 tests in 88.557 seconds, 34 passed and one physical-Windows-path skip.
Independent reviewer accepted the abnormal-exit correction and found no new
material issue in the six-case diagnostic and missing-AOT/restored-green wiring.
PowerShell execution remains unavailable locally and actual Windows proof
remains pending. The provisioned isolated Mac engine root is ready for the
approved fresh build; the preserved engine and application pairs are intact.

V-06 guest resource check after maintainer unlock: controller observed 53
regular native resource files, zero symlinks and zero empty files in the
Safari-downloaded app. Guest SHA-256 values for BUILD-INFO, NOTICES-SUMMARY and
mpv LICENSE.LGPL match the verified host candidate. Terminal readability and
these sampled hashes do not establish sandboxed application access or explain
the native-notice failure. No guest security or permission setting changed.

The finite Licenses probe is complete in six paths, implemented by repository
worker (gpt-6.1-sol, medium) and independently reviewed (gpt-6.1-sol, high)
without material findings. Controller matched all six handoff hashes, ran ten
focused Dart repository/view tests with exact opt-in (passed), compiled and ran
the native resource contracts plus exact text reads of all 53 preserved bundle
documents (passed). Controller parenthesized three test-only Swift casts to
avoid optional-argument compiler warnings, then recompiled without warnings
and reran successfully. Child default/invalid-opt-in, format and analysis checks
retain their attribution. The diagnostic remains default-off and has not yet
observed the live failure stage; it makes no root-cause correction or acceptance
claim.

R-01/V-02 resumed execution: canonical migration integrated as `bbb45768`;
finite Licenses probe integrated as `4f2e2429`. Both are pushed to
`origin/platform/macos`. [CI run 39572081886](https://github.com/TJZine/LineupDesktop/actions/runs/39572081886)
is executing at exact source `4f2e2429`; no further push is permitted while its
engine jobs run. Controller snapshot after the Mac build: Dart, Windows release
policy, stock
Windows player/native, macOS portable/native and shared-core jobs passed;
Combined Debug completed: controller inspected all retained XML/log hashes and
normal full-suite execution records. Common passed 242; Windows passed 396,
with only existing `MockWindow.DISABLED_GetObjectUia` disabled. All twelve
required recovery cases and six representative diagnostic cases passed, with
no DC-baseline exclusions. Release and engine/app/package jobs are still
running; their acceptance remains pending. The fresh canonical Mac Release engine
completed in the isolated fixture root,
starting with 166.7 GiB free, using the approved manifest and unchanged original
Mac patch bytes. Controller independently reran canonical verification and
matched the job identity exactly: binary SHA-256
`561618376ec90a1746a764a9b78fc1c4338969cedf9dbeb2dc4a9c8f1886b213`,
provenance SHA-256
`88446f7136bbaffdd0c9dbaf826e79c872eb6a431081c928af259ae0b6d940b7`.
Output is `lineup_ax_release_arm64` under
`~/.cache/lineup-flutter-ax-fixtures/3.47.7`. This verifies the engine artifact;
its app candidate is not yet built. Earlier focused Debug/Release recovery tests
retain their old-root attribution. Old pairs and stock SDK caches are preserved.

V-04 follow-up on repaired-engine diagnostic `efb02676`: while the controller
performed independent VM checks, the native probe recorded natural EOF, stop,
then a second accepted/opening/ready sequence. Guide identified the next
scheduled program. Normal Quit then exited with code 0. These are attributed
diagnostic observations, not audible or final-candidate acceptance.

R-03 live cause discrimination: a separate clean-source stock-engine diagnostic
at `4f2e2429` passed deep strict signature and source/hash checks; pinned stock
pub-get ran after its build. The loaded stock engine matched the recorded
diagnostic hash. Before any native Settings action, the in-app Licenses route
failed with the single finite Dart category `missing_plugin` and no native
resource failure record. In that same process, invoking macOS app-menu Settings
and reopening Licenses made the native component/file lists and curl COPYING
text load. At that diagnostic revision, source discovery traversed the Flutter
view tree once at launch, before container children were guaranteed ready, then
retried from native Settings. The repository worker repaired registration at the window's
explicit Flutter-engine initialization point (integrated as `5e05ac0b`); no
filesystem fallback or permission change is justified. Cold in-app first-open proof remains required.

V-06 lower-target native compilation (repository worker, gpt-6.1-sol, medium):
the official locked objective_c 9.6.2 archive matched its original lock SHA-256
before extraction; all 204 published files match the installed cache. All eight
required unchanged C/ObjC sources compiled and linked for arm64 macOS 12 with
both unguarded-availability warning classes treated as errors, using existing
clang/SDK. The real output declares minimum OS 12 and matches the original
helper's 188 exported and 73 undefined symbol names plus dependency set. This
is compilation/interface evidence only: no app binary was replaced, no signing
or cache patch occurred, and guest runtime behavior is still required after a
repository-owned hook correction.

R-03/V-06 registration correction integrated as `5e05ac0b`: repository worker
(gpt-6.1-sol, medium) moved both app channels into a small window-owned owner
created from the exact Flutter engine messenger before container loading.
AppDelegate only forwards native Settings; discovery and late registration are
removed. Controller inspected all four matching source hashes, passed project
plist lint and arm64 macOS-12 Swift typechecking against pinned Flutter headers.
Independent reviewer (gpt-6.1-sol, high) verified pinned engine handler lifetime,
window ownership and unchanged menu/resource/quit behavior, with no material
findings. Actual fixed cold in-app first-open and repeated native Settings/quit
remain required on an identified build.

R-03 source-material refresh `a6b6aef2` includes the canonical verifier's
DirectComposition and Windows fixture authority inputs and refreshes readable
recipe assets after R-01. Controller passed all eight existing Python source
material tests plus exact generated-asset freshness. The full source companion
still needs regeneration/binding for the final canonical candidate.

V-06 native-asset correction (repository worker, gpt-6.1-sol, medium): full
locked objective_c 9.6.2 is vendored; independent reviewer matched all 204
upstream manifest hashes to the verified published archive. Only its owned hook
and analysis settings change upstream files. The hook selects macOS 12 for
compile/link; the build wrapper checks actual Mach-O deployment minima, native
asset identity, contained dependencies and producing-hook evidence. Parent
integration checks passed eight Python fixtures and 70 focused Dart tests.
Independent reviewer (gpt-6.1-sol, high) found two P2 gaps: negated repeated
config-only flags could bypass the gate, and cached outputs lacked producing-time
toolchain-byte binding. Controller accepted both findings; the same worker corrected final flag
precedence and schema-2 producing-time source/config/toolchain/artifact binding.
Controller matched all 231 returned file hashes and exact write scope, reran
eight native-asset fixtures, 16 wrapper tests, eight source-material fixtures
and generated-asset freshness successfully. Independent focused rereview closed both findings and passed its retained
mutation/restoration control. The controller combined full Dart suite passed all 1,894 tests before
integration. No app build was started on the dirty tree. The integrated change
will use the verified canonical engine for a clean identified build. This source work establishes no current-hook
app build or Monterey runtime pass.

V-06 staged source inspection retains the complete published vendor tree.
The staged whitespace check reports only five known files: three byte-preserved
upstream native/generated files and the two exact copies of LOCAL.patch whose
blank context lines contain the required patch prefix. The check passes for all
other staged files; upstream bytes and applyable patch context are preserved.

R-01/V-02 final hosted outcome (controller inspection): run 39572081886 at
`4f2e2429` completed successfully; no engine job remains active on the ref.
Release execution records show normal exit 0, complete full-suite selection and
matching retained XML/log hashes. All twelve required cases executed without
skips; the only disabled Windows case is named in V-02. The expected missing-AOT
RunHeadless failure completed normally with exit 1, then restored-green exited
0 with the exact original fixture SHA-256. Controller checked all 44 actual ZIP
artifact digests, embedded receipt and DLL identity, and matched ordered recipe
patches/manifest/pins against source, accounting for Windows CRLF bytes. ZIP
SHA-256 `1df9f8a817dfbfc423e34c723f0be63e6d9d8db4af4429b430bc6b7003bd7918`.
No physical Windows acceptance is claimed.

V-06 real build at `fd4d49c9`: clean app compilation succeeded, then the native
asset gate rejected the result; no successful app receipt or verified candidate
was produced. Pinned stock pub-get ran afterward and source stayed clean.
Read-only diagnosis found actual hook configuration workspace_pubspec.base_path
is the root pubspec **file**, with recorded/current content hashes identical,
while the verifier expected the repository directory. The same worker corrected the exact file-origin comparison and faithful
fixtures, including alternate-file/directory rejection and restored-valid
controls. Parent inspected the three-file diff and matched its handoff hashes;
source-material fixtures/freshness pass. Read-only verification of the prior
compiled app now passes all 22 bundled Mach-O entries and its producing proof,
but that build is not relabeled as a current candidate. A fresh clean build
is required after integration; no provenance requirement is waived.
Existing app/engine pairs remain preserved.

Current canonical app (controller, October 21): clean source
`8c98fb8079553af7f4b7be728c832366827681bb` built and passed the producing-hook,
22-binary deployment/dependency closure, successful-build receipt, bundled-engine
and deep strict signature gates. No commit intervened before verification;
pinned stock Flutter 3.47.7 pub-get ran afterward and the tree stayed clean.
Identities: compiled Dart
`4112026f325aba216aa611b9e5c93b757086e4c39ec44c3483956aa58a2152b6`;
bundled signed engine
`6616bf4514a7d1fb5a5378293de9c46478f3e81b776eaff5c338d3f06442a0a9`;
raw engine `561618376ec90a1746a764a9b78fc1c4338969cedf9dbeb2dc4a9c8f1886b213`;
runtime BUILD-INFO
`b6b0f67b9d7c3e74e1089db05621c65d1aec850a3326e22f9172515ed2018899`;
app receipt `5ced1ba740af752a756289e157a00d7a5867add8aa1a0ab96eb855861e5965ed`;
bundle provenance
`fc4ffaaadef196761b5df35af5debae753a87cec82860e8b530654a565f0c7ce`.
Bundled objective_c native asset
`b33df9789c54972a446457df24e4d91cc5b901d6425ccda948c43561115c25b8`.
Controller independently matched the running engine and objective_c image hashes
to this exact app. The exact local ZIP and source companion verified: 109 source
inputs, 140 delivered files, manifest SHA-256
`ace813caeeb0e4aa1a66d24a0ed676867c45ba1bb634ad67d22353d061b09bfe`;
ZIP SHA-256 `0a41ab84f730592d33e1008154898adad943162c88e922ece78f8c8df87ae977`.
No sending/publication or beta acceptance occurred.

R-03 current-app observation: after the maintainer handled Keychain locally,
saved Guide restored. Before any native Settings action, in-app Support opened
the native component/file lists and bundled curl COPYING text. During actual
video, native mpv LGPL text and exact Sources/rebuilding materials (including
new objective_c provenance) loaded; Esc restored the scrolled list and Return
reopened its prior invoker. Returning to Player showed continuing video. Native
Settings subsequently forwarded into the same session with Back to Player.
This establishes the cold registration repair and bounded reader continuity;
spoken/physical acceptance remains V-07. Source companion remains local.

V-04/V-05 current-app observation: initial existing PMS connection labeled
Direct remote and its playback is attributed separately. The controller selected
an available unprotected Home profile, connected to the same existing PMS, and
completed all three selected library scans. No generated lineup was applied.
The maintainer entered the owner profile PIN locally to restore it; the renewed
owner connection reported Direct local (18 ms). A current catalog selection
reached native accepted/opening/ready with actual video and OSD progress; the
local route continued through Licenses and Back to Player. Scan/rescan completion
is observed, but fast-changing UI prevented unambiguous isolation of cancel/retry
effects, so those live claims remain pending. No server/account configuration
or credential value was changed by the controller. Later current-candidate VM
checks and final host shutdown are attributed below.

V-04/V-05 final host observation (controller, same `8c98fb80` app): natural EOF
reported mpv error 0, followed by stop acceptance and a new accepted/opening/ready
load. Successor video was visible after native fullscreen exit, minimize and
Window-menu restoration. Brief Preparing playback around EOF is recorded without
an unsupported failure attribution. Native-menu Quit ended the identified process
normally with exit code 0. No sustained listening/audio-drift or physical acceptance
is inferred. Unambiguous live scan cancel/retry remains pending.

V-06 current-candidate observation (controller): after maintainer unlock, Safari
downloaded the exact 35,659,476-byte ZIP into the macOS 12.6 guest, retaining the
old app separately. Guest shasum matched compiled Dart `4112026f…`, engine
`6616bf45…` and objective_c `b33df978…` against this record's exact full identities;
deep strict codesign verification passed. Default launch was blocked. The
maintainer separately approved this build's one-app Finder Open exception;
the controller applied that path without removing quarantine or changing global
security settings. Cold in-app Settings/Support loaded native lists and curl
COPYING, and Esc returned to Support. Normal guest menu Quit closed the app;
Finder relaunched it to onboarding. No guest process exit-code claim is made.
Initial text rendered clearly, but intermittent stippled glyph corruption returned
on component/file/text screens. Native resource loading now succeeds; presentation
and the support floor remain unresolved. The private transfer server was stopped
after download. Maintainer-local Plex sign-in is requested for PMS/TLS/CA,
Keychain and playback; a separate macOS 13 download/VM approval and the V-07
checklist/limited-candidate choice are pending. No beta acceptance occurred.

V-06 authenticated macOS 12 observation (controller, unchanged `8c98fb80` app):
the maintainer completed Plex sign-in locally. An existing owned PMS connected,
five selected libraries scanned, and an 81-channel guest-local lineup saved.
The UI labeled this route Direct remote / Very slow (2259 ms); it does not
establish local-PMS beta-route acceptance. No host lineup or server/account
configuration changed. Current-program activation caused an unexpected quit.
A bounded extraction of the guest crash report identified EXC_CRASH/SIGABRT,
IOGPUMetalDevice argument-encoder creation, MoltenVK initMetalFeatures and
vkCreateInstance, then libplacebo/mpv initialization. Raw diagnostics remain in the
guest and were not sent. The report does not establish physical-hardware failure
or a media network/authentication cause. Relaunch restored the saved Guide/account
without credential entry or a new prompt; subsequent normal menu Quit closed it.
No guest process exit code or playback success is inferred. A process-only
LaunchServices diagnostic with `MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0` restored
the Guide and got past the original argument-encoder stack, but current-tile
activation still aborted: the bounded report identifies libplacebo
`vk_malloc_slice`, texture creation/upload and mpv frame mapping. No successful
video or native TLS/CA result is inferred. An earlier direct-executable attempt
had no front window and was stopped by the controller (shell exit 143); a
separate default Finder launch was not attributed to that diagnostic. All crash
dialogs were dismissed with Ignore, without sending reports. No candidate,
entitlement, system/security setting or runtime bytes were changed.

The maintainer approved downloading Apple's macOS 13.0 (22A380) restore image and
creating a separate test VM. Controller disk preflight found 142 GiB free and
started a detached download from Apple's CDN with expected 12,197,669,257 bytes,
SHA-256 `537008900fe34eeb703d928ce613708bfbd6bf445289948058fc617be4f2d090`
and SHA-1 `348f49da377d8c394672d1b2800d23452a1d6215`, matching CDN digest metadata.
The completed download matched exact size and both hashes. BuildManifest
identifies macOS 13.0 / 22A380 and VirtualMac2,1. Post-download disk free space was
126.7 GiB. The controller created the separate `Lineup V-06 macOS 13.0` VM using
Apple Virtualization, four cores, 8 GiB RAM and a new 64 GiB disk; UTM accepted
the image and installation started. Installation completion, setup and runtime
execution remain pending. The existing macOS 12 VM and verified application/
engine pairs are preserved; input capture was restored to off on the macOS 12
console.
The maintainer explicitly chose to leave V-07 unverified; all existing checklist
boxes remain unchecked. Live scan cancel/retry proof remains pending, with an
explicit deterministic-evidence/limitation scope decision requested at that time.

V-06 macOS 13.0 / 22A380 observation (controller, same `8c98fb80` app):
the maintainer finished legal/account setup locally and suspended UTM. On resume,
the controller continued the final Location Services screen with its checkbox
left off and reached the desktop without entering credentials. Guest `sw_vers`
confirmed the installed OS/build. Safari downloaded the exact 35,659,476-byte ZIP
over the private VM network; compiled Dart, engine and objective_c hashes matched
the recorded candidate. Deep strict signature verification passed. Safari
quarantine remained present. Default launch was blocked; the maintainer separately
approved a one-app Finder Open exception in this macOS 13 VM and the controller
applied it. The private transfer server was stopped after download.

Cold in-app Settings/Support loaded the native runtime index, curl file list and
bundled COPYING before any native Settings menu use. Three Escape actions returned
to Support. Initial windowed onboarding/Support showed corrupted glyphs; expanded
Support/index/file/text pages were clear during this bounded observation. This
does not establish physical-hardware failure or a support-floor pass. The maintainer subsequently completed Plex sign-in locally, and the controller
observed the existing owned-PMS chooser. A connection click could not be verified:
Computer Use returned the UTM library, then subsequent UTM accessibility, screenshot
and rebind requests timed out, including after a control-session reset. The
controller requested the macOS 13 console be brought forward, without restarting
the VM or forcing any process to quit. Authenticated PMS/native media TLS/CA,
Keychain continuity, playback and normal shutdown/relaunch remain unverified in
this guest. Input capture was restored off before the local sign-in handoff.
The maintainer explicitly retained live scan Cancel/Retry as pending; no change
to V-05 proof scope or beta acceptance follows.

V-06 macOS 13 authenticated follow-up (controller, unchanged `8c98fb80`):
after the maintainer brought the console forward, Computer Use recovered without
restarting UTM or the guest. Connecting the existing PMS succeeded. Five selected
libraries scanned and setup advanced to Configure/Review with 81 generated
channels; the controller saved this guest-local lineup and opened Guide. Navigation
labeled the connection Direct remote / Very slow (634 ms), separately from the
host's Direct local observation. No host lineup or Plex account/server setting
changed. Scans completed between observations, so no isolated live Cancel/Retry
pass follows.

Double-clicking the current Guide program caused an unexpected quit before video.
Bounded extraction from `Lineup Desktop-2026-10-21-162346.ips` showed
EXC_CRASH/SIGABRT, `IOGPUMetalDevice newIndirectArgumentEncoderWithLayout`,
`_MTLDevice newArgumentEncoderWithArguments:structType`, MoltenVK
`MVKPhysicalDevice::initMetalFeatures` / `vkCreateInstance`, then libplacebo/mpv
initialization. This matches the default macOS 12 guest failure boundary; it does
not establish physical-hardware failure or a media authentication/network cause.
The crash dialog was dismissed with Ignore; no report was sent. Normal relaunch
restored Guide and the saved account without credential entry or another prompt;
normal menu Quit closed the app. This is bounded same-build development Keychain
and saved-lineup continuity, without a captured guest process exit code.

A separate process-only LaunchServices diagnostic used
`MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0` and the existing finite first-open probe,
with stdout/stderr retained privately in the guest. It restored Guide, tuned the
current program and displayed changing actual video across successive observations
before the session ended at approximately 16:28. The sanitized probe recorded core accepted/opening,
two FFmpeg unknown categories and core ready. No later crash/rejection was observed
before normal menu Quit closed the app. No audio/listening, exact media TLS/CA,
physical display, default-candidate support or beta acceptance claim follows.
Unlike the macOS 12 diagnostic's later libplacebo abort, this macOS 13 diagnostic
reached video; the default launch remains failed. The candidate, bundled runtime,
entitlements and system/security settings were not changed, and the environment
was confined to that diagnostic process. VM input capture was restored to off.

V-06 still needs a support commitment: default playback has passed on the physical
macOS 27.0.1 (26A434) host, while these two older VMs cannot establish an older
floor. The controller has not narrowed the promise or changed the 12.0 deployment
target. V-05 live Cancel/Retry remains pending by the maintainer's explicit
choice; V-07 remains unverified. The local-only plans remain until actual closeout.

V-06 compatibility clarification (controller, October 21): the maintainer did
not approve narrowing support to macOS 27. Reinspection of all 22 Mach-O images
in the unchanged candidate found `LC_BUILD_VERSION minos 12.0`, including the
app, compiled Dart, Flutter, objective_c and all bundled media libraries. Flutter
3.47's official [support matrix](https://docs.flutter.dev/reference/supported-platforms)
lists macOS 12 through 27, with macOS 15 CI-tested upstream. This gives a concrete
compatibility basis for recent macOS on Apple Silicon; it does not substitute
for this app's runtime proof. No inspected dependency imposes a macOS 27 floor.

The exact pinned MoltenVK source (`db66022459ffb663aa2b50f6b018bc2e124f5edf`)
queries Metal argument-buffer sizes during physical-device initialization when
that feature is enabled; the guest crash reaches this query. Disabling it only
for the macOS 13 diagnostic bypassed that crash and reached changing video. A
virtual-GPU capability/driver interaction is therefore a supported hypothesis,
not an established physical-Mac or entire-OS-version defect. The tested Ventura
image was 13.0, not an observation of later Ventura updates. The prior binary
choice between physical older hardware and latest-host-only beta support was
too narrow: a newer macOS VM remains a useful next check, starting with macOS 14
under the approved step-up sequence. Its image download/installation still needs
maintainer approval; no new download or support-policy change is implied here.

V-06 macOS 14 preparation and retired-VM cleanup (controller, October 21):
the maintainer explicitly approved the macOS 14 image/VM and requested clearing
the macOS 12/13 test VMs. The macOS 12 VM was stopped. A guest shutdown request
for the locked macOS 13 VM did not stop it; UTM's VM-only power-off then stopped
it. Both stopped bundles received same-volume recoverable APFS clones in Trash
(relative paths/types/sizes and configuration bytes matched) before the originals
were removed and unregistered through UTM's CLI. The two old IPSWs were moved
to Trash. The small private evidence records and repository observations remain.
Trash was not emptied, so this retirement does not claim reclaimed disk space.
No verified host candidate/engine pair, stock cache or unrelated user data changed.

The detached Apple CDN download for Sonoma 14.6.1 / 23G93 completed and matched
14,790,601,661 bytes, SHA-256
`e387251e63387150ba76cf784bdb97d2016e5d43c6f809c90a115eb067a097b8`
and SHA-1 `eb53bb5843675c4ab86765353322841941926c90`, both supplied by Apple's
CDN metadata. BuildManifest confirms the OS/build and VirtualMac2,1 support.
Disk preflight was 112 GiB free before download. The Apple Virtualization wizard
was configured for four cores / 8 GiB and reached the IPSW selection step.
Computer Use then captured only a tiny background thumbnail despite a native
Raise action; the maintainer was asked to foreground the wizard. Installation,
legal/account setup and candidate runtime checks remain pending. Approval does
not narrow the support promise or establish a macOS 14 pass.

After the maintainer foregrounded UTM, the controller selected the verified
14.6.1 image and created `Lineup V-06 macOS 14.6.1`: Apple Virtualization, four
cores, 8 GiB RAM, a new 64 GiB disk and shared directory off. UTM accepted
installation onto that empty disk and displayed Installation: 0%; input capture
remained off. The earlier foreground blocker is resolved. Installation completion,
maintainer-local legal/account setup and exact-candidate runtime checks remain
pending. The macOS 12/13 retirement is recoverable in Trash, not a permanent
purge or a claim that physical Macs on those versions cannot run the app.


V-06 macOS 14 installation and exact-candidate transfer (controller, October 21):
the maintainer completed the guest's legal/account setup locally. The controller
observed its desktop and `sw_vers` confirmed macOS 14.6.1 / 23G93. Safari received
the unchanged `8c98fb80` candidate from a VM-host-only server restricted to the
specific guest; the server recorded the complete 35,659,476-byte transfer and was
stopped afterwards. Compiled Dart, bundled Flutter engine and `objective_c`
SHA-256 identities matched the verified candidate, and `codesign --verify --deep
--strict` returned zero. Safari quarantine remains present. Default first launch
was blocked by Gatekeeper; a separate one-app Finder Open exception for this VM
was requested. Native Licenses, authenticated PMS and playback checks in this
guest remain unexecuted. This is artifact verification, not a macOS 14 runtime
pass or a support-policy decision.

Retired-VM permanent cleanup (controller, October 21): following the maintainer's
explicit request, only the two retired macOS 12.6/13.0 VM bundles and their two
restore images were permanently deleted from Trash. Their exact identities were
checked before deletion, and all four paths were confirmed absent afterwards.
The bounded private observations, copied VM configurations and repository evidence
were preserved. Free disk space increased from approximately 78.7 to 151.4 GiB.
The macOS 14 VM/image, verified host app/engine pairs, stock caches and unrelated
user data were retained. This supersedes the earlier recoverable-retirement state;
it does not change the interpretation of the older guests' graphics failures.


V-06 macOS 14 cold-start follow-up (controller, unchanged `8c98fb80` candidate):
after the maintainer's explicit approval for this guest, the controller applied
the one-app Finder Open exception. The application reached signed-out setup.
On that first process, in-app Settings → Support → Licenses loaded native runtime
entries, the curl file list and readable `COPYING` text before any native Settings
menu use. Four Esc actions returned to setup. Normal application-menu Quit closed
the app; no process exit code was observed. Finder double-click relaunched it to
setup without another Gatekeeper prompt. Initial setup/Support/reader text was
clear, but some setup glyphs were visibly corrupted after relaunch, so the guest
rendering concern remains open. No global security setting or quarantine attribute
was changed. Input capture was released for maintainer-local Plex sign-in;
authenticated PMS access, saved-session continuity, default playback and native
media TLS/CA in macOS 14 remain unexecuted. These bounded launch/reader observations
do not yet establish the V-06 support floor or beta acceptance.


V-06 renderer diagnosis (controller, October 21): the maintainer confirmed the
macOS 14 signed-out glyph corruption and requested diagnosis before more sign-in
work. Source inspection identifies Impeller/Metal as the candidate's default
Flutter UI renderer: pinned `FlutterDartProject` returns enabled absent
`FLTEnableImpeller`, and this candidate has no override. This pre-media UI failure
is distinct evidence from the earlier MoltenVK playback initialization crashes;
a shared graphics cause remains a hypothesis. A disposable diagnostic copy sets
only `FLTEnableImpeller=false` and refreshes its outer ad-hoc signature. Compiled
Dart, engine and `objective_c` hashes and signing entitlements remain unchanged;
deep strict verification passed. The original candidate is preserved.
After the maintainer approved the separate Skia diagnostic exception, the
controller observed one Lineup process (PID 1863) and its captured startup log
confirmed `Using the Skia rendering backend (Metal).` Setup, Settings/Support,
the native license index, curl file list and top/lower `COPYING` text remained
clear through navigation and scrolling. Four Esc actions returned to setup;
resizing also left its text clear. Normal menu Quit closed the app and `pgrep`
returned no match (status 1) before relaunch; no process exit code was observed.
The relaunched process (PID 1974) again logged Skia and displayed clear setup.
For the reverse comparison, the unchanged original candidate was launched from
Finder. Its first launch, Support navigation and resize were clear, but another
normal Quit/Finder relaunch reproduced corruption in the LINEUP wordmark,
Settings and first heading glyphs. A final Skia control (PID 2007, renderer log
confirmed) displayed clear setup again. The private evidence retains paired
full-guest captures. An attempted Terminal launch of the original requested
Downloads access; that unnecessary access was declined and the failed attempt
was replaced by the successful Finder launch.
This bounded comparison supports the Impeller versus Skia configuration
distinction in this VM; it does not identify the exact glyph shader/atlas/driver
defect or establish a sustained/performance pass. The fallback also changes
Flutter's wide-gamut eligibility. No playback result or production renderer
change is implied, no OS support version is discarded or accepted, and the
original verified candidate remains unchanged.

Authenticated renderer/media comparison (controller, unchanged `8c98fb80` binaries,
macOS 14.6.1 / 23G93): after maintainer-local Plex sign-in, Skia connected the
selected owned PMS (Direct local), completed a two-library scan and saved 186
channels. Setup and Guide text remained clear. Default current-program activation
then aborted with `EXC_CRASH` / `SIGABRT` in Metal argument-encoder creation →
`MVKPhysicalDevice::initMetalFeatures()` → `vkCreateInstance`, matching the earlier
guests' initialization failure. The unchanged original candidate reproduced that
same crash after the maintainer handled its Keychain prompt locally. Guest reports
are `Lineup Desktop-2026-10-21-230528.ips` (Skia) and
`Lineup Desktop-2026-10-21-231257.ips` (original); raw reports remain guest-local.

The process-only `MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0` comparison bypassed that
abort in both configurations, but the picture stayed black: Skia reached native
accepted/opening/ready with `gpu-next`, software decode and a seek landing; the
original reached those stages on two different current programs. A further
original-candidate run using the existing presentation logger showed a visible,
unhidden 1600×1200 drawable at scale 2, BT.709 parameters/colorspace and EDR off,
while the picture remained black. Readiness and a configured visible layer are
not visible playback. These observations rule out Skia as the sole cause of this
black picture; they do not establish whether decoded frames, GPU submission,
presentation or guest capture is responsible. No listening or media TLS/CA pass
follows. All environment overrides were confined to the test processes.

For controlled relaunches, Finder moved the guest's original app from Downloads
to Applications; deep strict verification returned zero and compiled Dart/engine
hashes still matched. The original app was not modified or re-signed, and its
quarantine was not removed.
Normal menu Quit after the instrumented runs logged completed native shutdown;
`pgrep` returned no match (status 1), without an observed process exit code. A final
relaunch without diagnostic environment restored the signed-in saved Guide with
no new credential prompt. Skia had also restored it after its crash and a normal
Quit. The missing guest Command Line Tools prompt from an attempted Python crash
parser was cancelled; no tools were installed. VM input capture was released.
V-06 remains open; neither the diagnostic fallback nor an OS support narrowing
is approved. V-05 live Cancel/Retry remains pending and V-07 stays unverified.

The source investigation by `worker` (`gpt-6.1-sol` / medium, child
`01a161a7-e346-7cc0-834f-d344f9d54404`) traced the initialization exception to
MoltenVK 1.4.2's argument-buffer size queries. Its advertised-capability branch
calls Metal's argument encoder during physical-device initialization; disabling
argument buffers bypasses that branch. Upstream [issue 2373](https://github.com/KhronosGroup/MoltenVK/issues/2373)
corroborates a paravirtual-device failure in that API family, without proving
the exact Lineup exception or a fix. VM failures do not establish failure on
physical Macs running those OS versions.

The controller then ran one bounded original-candidate Vulkan trace in macOS
14 with process-only argument buffers disabled. The picture remained black
after the spinner cleared. Entry/exit counts matched: swapchain creation 2/2,
image acquisition 966/966, `vkQueueSubmit2` 2896/2896 and presentation 966/966.
Legacy submit and acquire-next-image-2 counts were zero. Accepted/opening/ready
each appeared once; four presentation-configuration records appeared, with no
seek-landing record in this run. Normal Quit completed native shutdown and
process search returned no match (status 1). Input capture was released.
These are whole-run call counts, not a performance measurement. The trace
establishes repeated returned Vulkan presentation calls, without return codes,
GPU completion or pixel contents; visible playback remains unverified. The next
bounded diagnostic separates software-frame availability, GPU readback and
presentation/composition while preserving the canonical candidate.

October 22: the same `worker` prepared the native readback diagnostic entirely
in private source copies. Controller inspection found and corrected its option
restoration reply event (`MPV_EVENT_SET_PROPERTY_REPLY`); the focused negative
control failed before correction and passed afterward. Two synthetic ASan/UBSan
executables (readback contracts and existing core plus wiring) and libmpv API-hook
syntax passed. The controller then compiled three native objects and linked a
separate diagnostic executable successfully, without an engine/runtime/Dart
rebuild. Ad-hoc assembly verified exact canonical component bytes, effective
entitlements and deep strict signatures; only the native executable differed
(`091e8fcf2b04836c7f9ba9c4365b1e9b24cbe9eaf82f6ce1f37fe541b62810be`).
The canonical pair remains preserved. Guest execution is **unexecuted**, awaiting
maintainer-local unlock of macOS 14. The bounded readback can distinguish frame
availability from useful GPU rendering, but not prove older physical-Mac support.
An in-flight GPU screenshot cannot be forcibly interrupted by the unchanged mpv
runtime; the existing shutdown watchdog remains unchanged. No further OS trial,
production fallback or support narrowing follows from this preparation.
