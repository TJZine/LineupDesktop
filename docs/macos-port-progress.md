# macOS port execution record

Controller takeover: 2026-10-17. Scope is the existing
[port plan](macos-port-plan.md), implemented in bounded slices with an
independent adversarial review before integration. This record distinguishes
source integration, automated evidence, and physical/product acceptance.

## Authorization and coordination

The human requested takeover using `orchestrate-implementation-chats` and
review of each slice before integration in parent chat
`01a14bbc-51cd-76e0-8274-37c69f04cf17` on `local`, turn
`01a14bbd-70f9-7943-b707-1f8a7e70a35c`, user message
`01a14bbd-7325-7ba1-b51b-fa68dc1c5b44`. The following human-supplied skill
authorizes child completion/blocker callbacks within this scope. Children
must verify that human source through `read_thread` before messaging the
parent; otherwise leave a final report for retrieval. The controller owns Git
integration and acceptance. No publication, submission, or external messaging
is authorized by this engineering assignment.

The human confirmed that the previous Claude agents are stopped and the Mac
is available for visible checks. They confirmed that the plan's open product
decisions still need decisions and requested all independent engineering work
first. Existing development behavior is not product approval: supported-platform
status, minimum OS/architectures, command/menu/fullscreen conventions, bundle
identity, monetization, and the purchase UI remain unresolved as listed in D0.
Do not infer those decisions from existing prototype code. B1/B2 and final
distribution remain gated by the relevant decisions and approvals.

## Reconciled source state

- Integration checkout: `/Users/tristan/Software/LineupDesktop`, clean
  `platform/macos` at `61d475c4` at takeover.
- S1 is recorded in the plan. U1 through `e5f4171b` and K1 through `900f006b`
  are already integrated. U1's fullscreen reconciliation depends on M3.
- S2 through `bb53a3aa` is integrated by `61d475c4`, including the accepted
  FFmpeg GPL-file exclusions and generated license notices.
- M1/M2 through `0857c906`, plus the independently approved M12-R5 correction
  `2b422e3e`, is integrated by `99788431`. Its source checkout remains
  `.claude/worktrees/agent-ac696b17224d2358a` on `macos/m1-m2-adapter`.
  Previous review was conditional on the core fixes; takeover review verified
  them and corrected the remaining fullscreen contract mismatch.
- K2 is integrated by `6ba61427` (separate macOS core-contract CI job).
- M3a asynchronous native shutdown is integrated by `77469eeb` after
  independent approval of its exact manifest and evidence.
- R1a runtime embedding recovery and signing timestamps are integrated by
  `f3217d87` after correction and independent approval of the exact three files.
  A subsequent actual bundle-signing failure was corrected in `104eb220` after
  independent approval and real Debug/Release build/signature checks.
- C1a full portable/native macOS CI and runtime provisioning are integrated by
  `80bb7d34` after independent approval. Hosted execution is outstanding.
- R1b real-runtime authenticated-reference proof is integrated by `9f766d33`
  after all 26 cases passed and the exact corrected manifest was independently
  approved. C1b adds its required CI entry point in `0d7e195e`, also independently
  approved. Hosted execution remains outstanding.
- R1c native runtime licenses/notices, patches and provenance resources are
  integrated by `48e93064` after exact-manifest independent approval and actual
  Release app resource/signature checks.

## Evidence and acceptance

- Accepted S2 runtime exists at `build/macos-runtime/dist/arm64` in the
  integration checkout. Controller reran `tool/macos/build-mpv.sh verify`:
  **passed**. Pin SHA-256 in `BUILD-INFO.txt`:
  `7df202602cc5a0276a7ac8762b0b4289e33e2db4a01d8adc352ca438ab9e842c`.
  This is runtime verification, not visible HDR or signed-distribution proof.
- [CI run 39064924906](https://github.com/TJZine/LineupDesktop/actions/runs/39064924906)
  targets exact M1/M2 head `0857c906`: Windows player build/native contracts,
  portable Windows UI, Dart, and Windows release policy passed. The macOS
  alpha test passed but its app build failed because CI did not provision
  `LINEUP_MPV_RUNTIME`; R1/C1 own that missing provisioning. The patched
  Windows engine/package job was still running when inspected. This is not
  an overall green run or physical Windows acceptance.
- M12-R2 passed a real-adapter/runtime SDR-visible → hidden HDR load →
  same-rectangle show probe after the user unlocked the Mac. The layer became
  PQ/EDR without another load or clip switch. This supports first-visible-frame
  configuration; no forced reconfiguration fix is justified for this case.
  Full Flutter composition, fullscreen sources, Guide transparency, live resize,
  and user HDR/color judgment remain acceptance work. M3b fullscreen/Dart
  synchronization remains gated by P6; M3a shutdown source is integrated.
- One 12-second stop timeout was reported in four earlier harness runs on
  a loaded machine. Preserve as an unresolved observation; investigate if
  reproduced on the accepted runtime, without declaring a cause from load.

### Controller observations after takeover

The M1/M2 harness at `0857c906` built with the pinned Flutter 3.47.7 SDK
and `LINEUP_MPV_RUNTIME` pointing at the accepted S2 output above. Its
real-protocol synthetic app rendered a long HDR10 ramp and a long SDR gray
fixture in the Player and Guide aperture. Visible HDR→SDR→HDR switching
reported `kCGColorSpaceITUR_709` / `edr=0`, then
`kCGColorSpaceITUR_2100_PQ` / `edr=1`, with VideoToolbox for HEVC.
Green-button fullscreen entry and View-menu exit completed and rendering
resumed. These are mechanism observations, not user HDR/color acceptance.

Fullscreen transitions produced transient blank capture and four Flutter
`Resize timed out` messages across entry/exit. Rendering resumed, but live
resize and transition quality are not accepted from this run. The attempted
Control-Command-F did not exit fullscreen; native shortcut/menu wiring and
state synchronization remain unresolved M3/P6 work. A Settings round-trip
resumed the existing HDR clip; it did not establish the distinct R2 case of
loading HDR while hidden, so it did not settle R2. The later dedicated probe below settles the tested
mechanism. Guide aperture visibility was
observed; exact Guide alpha comparison was not performed. Command-Q completed
the worker shutdown and exited the instrumented process; bounded asynchronous
termination was subsequently implemented and reviewed in M3a. No fixture media identities or raw diagnostics
are part of shared evidence.

M12 targeted re-review completed: the shared-core latch, faithful hang proof,
shared validation/Windows equivalence, and `osc`/`ytdl` changes passed. The
reviewer ran all three portable core suites and showed that removing the
latch reset fails both the stale-wakeup assertion and the restart watchdog.
It requested changes for M12-R5: the immediate fullscreen-success guard still
excludes active/pending transitions and the protocol text narrowed the agreed
requirement. The controller accepted this finding. The correction and two
real-adapter request-path XCTest cases are complete in the candidate checkout;
all 10 native tests pass. Restoring only the old guard fails both new cases.
The expanded native test wiring and correction were independently approved
before integration. The reviewer verified real request-path coverage, preservation
of all eight earlier tests, the negative control, and unchanged Runner app target.

Combined source `99788431` was then checked in the primary checkout with the
accepted S2 runtime: `flutter build macos --debug` passed; all three portable
Debug core CTests passed; the new native XCTest scheme passed all 10 tests;
and the affected Guide alpha, unsupported-player, and Setup retry Dart suites
passed all 12 tests. Flutter 3.47.7 was selected explicitly. These combined
checks establish build/contract/alpha consistency, not a signed release or
physical Windows/minimum-macOS acceptance.

K2's separate macOS core-contract CI job was independently approved. It fetches
only mpv headers at the runtime lock's exact commit, configures Debug, and
requires each named suite to run successfully with a bounded serial CTest
invocation. The implementation's exact local acquisition/build/test flow passed
all three suites. The reviewer verified that the existing workflow jobs are
structurally unchanged, parsed YAML, checked all new shell blocks, and showed
that an empty test selection fails. Hosted execution remains outstanding.

## Dispatch map

| Unit | Child chat | Executor | Source / ownership | State |
| --- | --- | --- | --- | --- |
| M12 targeted adversarial re-review | `01a14bbe-5fce-7320-b217-e131e586574a` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Immutable `0857c906`; read-only source, isolated portable test output; no app/runtime builds | Complete: requests M12-R5 correction; other reviewed fixes pass |
| M12-R5 correction | `01a14bc0-ab3f-7c73-bb93-75341fdc3420` (`local`) | `worker`: `gpt-6.1-sol`, medium | M1/M2 checkout above; adapter guard, protocol text, focused production-path regression proof and minimal test wiring; no Git integration | Complete, reviewed and integrated via `2b422e3e` / `99788431` |
| K2 macOS core-contract CI | `01a14bc1-7787-75f2-841a-48b715f3b209` (`local`) | `worker_luna`: `gpt-5.6-luna`, xhigh | Primary checkout; only `.github/workflows/ci.yml`, one new job | Complete and independently approved; controller integrates |
| K2 adversarial review | `01a14bbe-5fce-7320-b217-e131e586574a` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Frozen workflow diff against `61d475c4`; unrelated controller docs excluded | Complete: approved; hosted execution still outstanding |
| M12-R5 targeted re-review | `01a14bbe-5fce-7320-b217-e131e586574a` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Frozen six-file candidate working diff at `0857c906`, including new scheme/config | Complete: approved; reviewed aggregate SHA-256 `49054e38cfb471d1e60315dc4aa40411bfddad87f4c1c302be979c894ade6ec0` |
| M3a asynchronous termination | `01a14bc0-ab3f-7c73-bb93-75341fdc3420` (`local`) | `worker`: `gpt-6.1-sol`, medium | Primary checkout at `a93aefe35391a90897fbbdb5b86564e6ef1b9e9c`; macOS lifecycle source/tests and focused existing docs; no core/Windows/Git changes | Complete, reviewed and accepted; frozen 12-file aggregate `4f3a88a7128fdcce3579a07f3e488b53aeae890ea7a6662e7aba3ceaabac9561` |
| M3a adversarial review | `01a14bbe-5fce-7320-b217-e131e586574a` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Frozen M3a manifest; excludes controller record and disjoint R1a script work | Complete: approved; controller integrates exact reviewed files |
| R1a embed cleanup and timestamps | `01a14bc1-7787-75f2-841a-48b715f3b209` (`local`) | `worker_luna`: `gpt-5.6-luna`, xhigh | Only runtime embed script, isolated production-script integration tests, and runtime documentation; no shared app builds or signing services | Complete: `f3217d87` plus independently approved Resources correction `104eb220`; Debug/Release ad-hoc app signing passes |
| R1a adversarial review | `01a14bbe-5fce-7320-b217-e131e586574a` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Frozen initial R1a script/test/runtime-doc diff; excludes parent record and R1b tooling | Complete: requests one confirmed P2 recovery correction; targeted re-review required |
| R1a final boundary re-review | `01a14bde-efcf-7360-be74-9d2bc2668ea8` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Frozen script `fb6aa2341188f935aabb9ac379914843c2deb8f6508c16e360e9c80d7acc8b50`, updated actual-script regression fixture and runtime doc; excludes other slices | Complete: approved original recovery correction and exact Resources follow-up; all four ownership records and publication/cleanup failure retries verified |
| R1b authenticated-reference parity | `01a14bc0-ab3f-7c73-bb93-75341fdc3420` (`local`) | `worker`: `gpt-6.1-sol`, medium | New macOS native test tooling and Development command; actual accepted runtime, isolated HTTPS fixtures; no core/Windows/app changes | Complete, independently approved and integrated as `9f766d33`; 26 actual-runtime cases pass |
| R1b adversarial review | `01a14bbe-5fce-7320-b217-e131e586574a` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Frozen four-file authenticated-reference unit; moving R1a/C1a and parent record excluded | Complete: both corrections independently approved; exact source, artifacts, runtime and focused classifier checks verified |
| C1a macOS development CI | `01a14bdd-a2a0-7ba0-bcb5-c06320493487` (`local`) | `worker_luna`: `gpt-5.6-luna`, xhigh | Only existing `build-macos` workflow job: full portable suite, source runtime provisioning, app build and existing native tests | Complete, independently approved and integrated as `80bb7d34`; hosted evidence outstanding |
| C1a adversarial review | `01a14bde-efcf-7360-be74-9d2bc2668ea8` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Frozen workflow only; moving R1b and parent record excluded | Complete: approved with YAML/Bash, structural and controlled failure-path checks; no hosted execution |
| C1b authenticated-reference CI | `01a14bdd-a2a0-7ba0-bcb5-c06320493487` (`local`) | `worker_luna`: `gpt-5.6-luna`, xhigh | Existing build-macos workflow only: fixture prerequisites and no-skip real-runtime runner before app build | Complete, independently approved and integrated as `0d7e195e`; exact workflow SHA-256 `c1120a3d0c8c55c8694e0410d9d942263e49527447b8e905391b5acf1b77a682` |
| C1b adversarial review | `01a14bbe-5fce-7320-b217-e131e586574a` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Frozen workflow only | Complete: approved; exact Bash failure propagation/path probes and actual system-OpenSSL fixture certificate generation passed |
| R1c native runtime resource packaging | `01a14bc0-ab3f-7c73-bb93-75341fdc3420` (`local`) | `worker`: `gpt-6.1-sol`, medium | Existing embed script/fixture and runtime/Development docs; package existing licenses, notices, patches and BUILD-INFO under owned Resources subtree; no UI/API | Complete, independently approved and integrated as `48e93064`; actual Release bundle/resource/signature checks pass |
| R1c adversarial review | `01a14bde-efcf-7360-be74-9d2bc2668ea8` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Frozen four-file packaging source; isolated fixtures/read-only app evidence | Complete: approved exact four files; independent real-runtime fixture and additional recovery/path probes passed |
| M3b fullscreen observation/reconciliation | `01a14bc0-ab3f-7c73-bb93-75341fdc3420` (`local`) | `worker`: `gpt-6.1-sol`, medium | Native adapter player-scoped events, Dart playback interface/transport/coordinator, affected fakes/tests and protocol docs; no app/menu files | Complete, independently approved and locally integrated as `e0f1b638`; final text-corrected aggregate `403853facc7368ca1a9999d336da6d47db954a623de0b3ae15457f0c395b4667`; Windows/physical gates open |
| M3b adversarial review | `01a14bbe-5fce-7320-b217-e131e586574a` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Frozen 18-file native/transport/coordinator/protocol diff; excludes parent record and disjoint workflow | Complete: approved implementation and final rationale correction; no material correctness/ownership finding; Windows/physical gates retained |
| C1c Windows adapter-contract CI | `01a14bdd-a2a0-7ba0-bcb5-c06320493487` (`local`) | `worker_luna`: `gpt-5.6-luna`, xhigh | Existing build-windows workflow only: explicitly build/run native_player_contract_test with no skip | Complete, independently approved and integrated as `ee379d3d`; Windows execution remains open |
| C1c adversarial review | `01a14bde-efcf-7360-be74-9d2bc2668ea8` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Frozen two-line Windows job change only; M3b excluded except prerequisite context | Complete: approved exact workflow; target dependencies, failure/no-skip semantics and unrelated structural equality verified |
| U1 native command delivery | `01a14bfd-7a31-7e50-9de6-e6318b5c1aac` (`local`) | `worker`: `gpt-6.1-sol`, medium | App/Guide keyboard routing, Mac app/window/menu files and focused test/app coverage only; excludes M3b playback/native-player files | Complete, independently approved and integrated as `38426fb4`; 106 affected tests pass and old code fails the new assertion |
| U1 shortcut adversarial review | `01a14bbe-5fce-7320-b217-e131e586574a` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Frozen Guide source/test only; M3b and parent record excluded | Complete: approved exact two-file patch; source, platform behavior, focus propagation and negative-control attribution verified |

M3a is the lifecycle portion of M3, independent of the unresolved P6
fullscreen product decision. It must preserve the pinned Flutter superclass's
quit approval (including cancellation), then keep the main loop and native
presentation owners alive while the worker disposes asynchronously. Repeated
quit/close, concurrent Dart disposal, and timeout/completion races need
faithful evidence. The exact timeout behavior and any acceptance limits must
be returned for review. Synchronous `Shutdown()` is an emergency ownership
fallback, not the normal quit/close path. Fullscreen events/Dart synchronization
remain a separate M3b slice.

M3a's approved timeout policy uses a fixed five-second
deadline reports failed shutdown and exits the process without destructors or
live-layer teardown if disposal is still incomplete. The implementer reports
16 native test passes plus one intentionally skipped destructive probe, a
separate real timeout subprocess exiting with failure, a meaningful early-reply
negative control, and synthetic playback quit/close observations exiting
successfully. The independent reviewer inspected those checks, the manifest,
production ownership and pinned Flutter handshake; it approved without a
material finding. The controller accepted that exact source. The deadline
requires a functioning main queue; it does not claim to recover a pre-existing
main-thread freeze. R1a addresses only the accepted stale-dylib and timestamp issues;
full provisioning, signing-account inputs, notices UI, and C1 remain open.

R2 controller experiment: a disposable `/tmp` native probe compiles the actual
production adapter/core against the accepted runtime. Two earlier attempts
remained occluded while the Mac was locked; they are invalid visibility
evidence. After the user unlocked it, the controller raised the real window
and observed SDR with a visible layer, loaded HDR while the layer was hidden,
then showed the exact same rectangle without another load or clip switch.
The layer retained Rec.709 while hidden and changed to
`kCGColorSpaceITUR_2100_PQ`, EDR enabled and HDR metadata present after showing.
The probe passed and disposed successfully. Local log:
`/tmp/lineup-hidden-hdr-probe/unlocked-sdr-hidden-hdr.log`.
This establishes the actual adapter/runtime mechanism on this Mac, not full
Flutter composition, visible highlight brightness, or final signed A1 acceptance.
Probe code remains outside the repository.

R1a review caught two concrete failure boundaries before integration: a
partial runtime B installation could leave B-only names untracked after a
later different C, and `mv -f` could follow a current-name directory symlink.
The final correction stages/signs before publishing, records pending ownership
for retries, validates both manifests before deletion, rejects real directories,
and safely replaces exact-name symlinks. Its production-script fixture covers
signing/install failures, changed-runtime recovery, malformed manifests,
legacy migration, outside-write sentinels, and timestamp selection. Independent
review approved the exact script/test/doc hashes and additionally verified
pending/completed-manifest publication failures and stale-cleanup failures.
The controller integrated those files as `f3217d87`. This is local embed/recovery
evidence, not real team-identity signing or App Store submission.

R1b's initial 25-case actual-runtime matrix passed, but review found two
inherited checker weaknesses: the HTTP redirect target used a TLS listener
that could hide plaintext attempts, and ordinary negative cases did not reject
progress followed by a later error. These findings do not establish a production
token leak. Correction is authorized only in the new macOS tooling: use an
actual plaintext listener/audit with a sensitivity control, require no progress
for ordinary negatives, and retain the explicit unsupported-SDP limit. The
same gaps exist in the Windows fixture; its old results do not establish these
stronger claims, and Windows source changes are outside this round's authority.

The R1b correction now uses a real plaintext listener and combines its audit
with the secondary HTTPS audit. A deliberate synthetic plaintext-token control
receives HTTP 200 and is rejected by the ordinary-negative classifier. The
existing actual-codec progress-then-error control is rejected by both positive
and negative classifiers. The complete real-runtime matrix passes all 26 cases,
with no new production policy changes. Exact four-file aggregate:
`0d01ad9246b01d79bc75f4184319f511d3cdddfcfc2499ce344b6d4668af518f`.
The independent re-review approved both concrete corrections, checked the exact
manifest/source/artifact/runtime binding and the recorded matrix, and directly
exercised both classifiers. The controller integrated the exact files as
`9f766d33`. C1b is adding the explicit CI entry point and fixture prerequisites.

The controller's actual Debug app build with the integrated R1a script then
failed at bundle signing: `Contents/Frameworks/.lineup-mpv-runtime-manifest`
was treated as unsigned code. The earlier fake-signer fixture did not establish
whole-bundle signing. A focused follow-up must put metadata in Resources,
safely migrate completed/pending ownership from incremental Frameworks output,
and exercise real ad-hoc bundle signing without excluding resource validation.
No signed-app success is claimed for `f3217d87` alone. The corrected frozen
Resources implementation (script SHA-256
`f341407caeac221e2cb7784e66ba6366d80c4cb81119a0c0beb77f944e3f85df`)
then passed the actual incremental Debug build without cleaning the prior failed
output. The default Release build also passed. Both complete app bundles and
all 18 embedded runtime libraries pass deep/strict ad-hoc signature checks,
the Resources manifest exactly covers the runtime, and pending/legacy metadata
is absent. Local logs: `/tmp/lineup-r1a-resources-app-build.log`,
`/tmp/lineup-r1a-resources-app-signature.log`,
`/tmp/lineup-macos-integrated-release-build.log`, and
`/tmp/lineup-macos-integrated-release-signature.log`. This establishes local
development signing/build integration, not team-identity signing or App Store
acceptance. The independent reviewer additionally exercised all four active/legacy
ownership records, failure/retry at each publication/removal boundary, invalid
record tails and symlinks, and relative/absolute/fallback Resources paths. It
approved the exact three-file follow-up; the controller integrated `104eb220`.

The controller ran the complete portable macOS suite with pinned Flutter 3.47.7
and `TZ=America/New_York`: all 1,728 tests passed. Local log:
`/tmp/lineup-c1a-macos-portable-full.log`. This includes the exact Guide alpha
checks and Dart contracts; it does not establish physical composition or HDR.
The pinned-SDK formatter check passed all 147 Dart files with no changes, and
`flutter analyze` reported no issues (logs `/tmp/lineup-macos-final-format.log`
and `/tmp/lineup-macos-final-analyze.log`).

The controller rebuilt the existing credential-free real-protocol harness on
these inputs. It rendered the synthetic HDR ramp in Player and the rounded
Guide video aperture, entered fullscreen using the native green button and
exited through View. Command-Q retired the playback process. The initial
window capture was a Stage Manager thumbnail; after fullscreen the full
window was observable. Two pointer drags did not establish a window geometry
change, so they are not live-resize evidence. Exact Guide pixel alpha, human
HDR color/brightness, continuous resize quality, all-source fullscreen and
final signed-package acceptance remain open. No extra source instrumentation
or product UI changes were made for this observation.

R1c's frozen implementation packages the complete selected runtime's license
and patch trees plus raw BUILD-INFO in `Contents/Resources/LineupNativeRuntime`.
The extended production-script fixture retains the earlier signing/recovery
checks and exercises resource completeness, obsolete-file removal, staging and
rollback failures, symlink/special-file rejection and boundary sentinels. Its
isolated real Mach-O app also embeds/signs all 18 accepted runtime libraries
and compares all 53 resource files without mutating the prepared runtime.
Four-file source aggregate:
`31f38f4fdc0e9e000a3f05f3dee28b179c8318b198516f6fe45da0d183b67b12`.
The controller's actual default Release build passed; its app resource file
set/hashes and full hierarchy match the selected runtime, permissions are
0755/0644, no stages/backups remain, and deep/strict ad-hoc bundle verification
passed. Logs: `/tmp/lineup-r1c-integrated-app-build.log` and
`/tmp/lineup-r1c-integrated-app-resources.json`. Independent review approved the exact four-file manifest and both correctness
and maintainability. It ran the actual real-runtime signing fixture and extra
backup/publication/rollback/cleanup fault probes, verified byte-complete retries
(including optional Unicode/binary files and empty directories), and rejected
nested links/FIFOs before library publication. The controller integrated the
approved files as `48e93064`. No new visible UI, user-accessible
license presentation, source hosting or legal approval is established.

The independent engineering slices completed so far are integrated. R1c
resource packaging is required regardless of Licenses-screen design; it does
not approve a screen or establish legal compliance. Distinguish the
prepared runtime's BUILD-INFO hashes from later signed binary/package hashes. M3b fullscreen events/Dart synchronization, remaining
U1 command/menu behavior, R1 signed distribution and notices UI, and B1/B2
remain gated by the relevant open product/design/account decisions. Resolve
dependencies against current source rather than treating the package list as
a serial pipeline.
Do not change approved Player layout. A new Licenses surface needs design
agreement if an existing suitable surface cannot carry it. Signing/account
inputs, legal review, product decisions, and physical hardware limits must
remain explicit instead of being silently treated as complete.

## Next decisions

The controller has asked the human for the next bounded choices, without
assuming answers: supported macOS release target (Apple Silicon/current bundle
ID/current 12.0 deployment target with untested older-OS acceptance still
required), native command/menu/fullscreen interactions, and whether to defer
purchase design until playback is finished. These are pending, not approvals.
No further child implementation is active. The next slice depends on those
answers; Licenses UI design/wording, signing accounts, legal/source distribution,
hosted CI and physical acceptance remain open as described above.

## Approved playback target (2026-10-17)

The human accepted the proposed first-release target: supported macOS playback
once acceptance passes, Apple Silicon only, existing bundle ID
`com.tjzine.lineupDesktop`, and current macOS 12.0 deployment target. Only macOS
27 has been tested; older-OS compatibility remains a release gate. They explicitly
approved native Mac interactions: command shortcuts, Settings via Command-comma,
and synchronized native fullscreen from the Player button, green button, View
menu and Control-Command-F. The approved Player layout remains unchanged.
They chose to finish playback before purchase design; no purchase model, free
channel limit or upsell UI is approved. These answers supersede the corresponding
pending decisions above and are recorded in the plan's resolved table.

The next M3b slice implements player-scoped observed fullscreen events and Dart
reconciliation, preserving native transition error/lifetime bounds and the M12-R5
immediate-current-state contract. Windows must emit the same additive event
without changing its fullscreen mechanism; Windows CI remains required. Existing
U1 command/Settings implementation is verified against the now-approved behavior
before making further changes. Parent owns plan/progress and Git integration.

U1 controller check on the already-built credential-free Debug harness:
Command-comma opened Settings, Escape returned to Guide, and F3 opened Settings.
Command-3 in Guide and Command-1 in Settings did not navigate. Control-3 also
had no effect. This is an observed input-path gap, not an established production
cause: CUA synthesis/focus/window context and AppKit/Flutter routing need to be
distinguished. All 44 existing focused shortcut/navigation tests pass with the
pinned SDK (`/tmp/lineup-u1-approved-shortcuts-tests.log`); those tests do not
establish actual macOS chord delivery. U1 owns exclusive CUA use and may use
isolated, source-bound experiments; M3b has isolated native test resources and
neither may build changing shared app inputs. The parent quit the harness
before handing off UI access.

The controller has proposed the required Licenses surface at Settings → Support
with the existing theme and a standard Flutter component list/text viewer for
Dart dependencies plus native resources. The human's direction choice is pending;
no UI implementation is assigned. Legal wording, source hosting and signed
release gates remain separate. Purchase work stays deferred.

U1's source-bound isolated probe at `980e5319` establishes the automation limit:
CUA's Command/Control chords send generic modifier flags with a key-code-0
flags-changed event and no device-side modifier bits; pinned Flutter therefore
observes the digit key with `isMetaPressed`/`isControlPressed` false. This does
not justify a native navigation workaround or establish broken physical keys.
U1 separately traced a real app conflict: Guide Find accepts extra Control with
Command-F and consumes Control-Command-F before native fullscreen redispatch.
The worker is adding a meaningful failing-before test and a narrow correction.
Physical-key navigation remains an acceptance step distinct from CUA results.

U1 is complete and frozen at patch SHA-256
`2e3d22a8c2e53712bf86bd5ccddbc84039047c42db569eab0cf6dc34aee02a26`:
only `lib/guide/guide_view.dart` and `test/guide/guide_view_test.dart`. Its
extended existing Find test proves Mac Command-F still focuses search while
Control-Command-F reaches the parent unhandled, and preserves Windows cases.
The old code fails that assertion; all 106 affected Guide/navigation tests pass
after correction and focused analysis/format checks pass. No native keyboard
routing workaround or pinned-engine modification was made. Source-bound CUA
probe instrumentation remains outside the repo. Independent review is running;
physical keyboard and stable combined fullscreen acceptance remain open.

The independent U1 reviewer approved the exact frozen two-file correction,
confirmed propagation through both Guide key handlers and preservation of Mac
Command-F and non-Mac behavior, and verified the attributed 106-test evidence.
No extra tests were run against moving M3b interface/fake inputs. The controller
integrated the exact files as `38426fb4`. Combined M3b/U1 build and native/physical
keyboard acceptance remain outstanding until the fullscreen source is frozen.

M3b implementation returned an exact 18-file frozen source aggregate
`cb2c8edfefbe9a28eb119f9e4fa7cdacf0f3cab6b660cd2fd0370ab443d35201`.
Its affected Dart suites pass 468 tests plus three unsupported-backend cases.
Actual isolated macOS native tests pass 19 cases with one pre-existing intentional
destructive-probe skip. Removing coordinator stale-completion protection or
native fullscreen emission fails the added distinguishing tests; final source
was restored before its passing checks. Independent review is in progress.

The controller's combined default Release build with integrated U1 and frozen
M3b passed, as did full analysis. Strict/deep ad-hoc app signature and packaged
runtime resource comparisons pass; frozen M3b source hashes are unchanged.
The full Dart suite passed all 1,737 tests and the Debug real-protocol harness
build passed. Full analysis reports no issues. These are provisional candidate
results until review accepts the exact source; all 18 file hashes remained
unchanged after the runs. Logs: `/tmp/lineup-m3b-u1-combined-full-tests.log`,
`/tmp/lineup-m3b-u1-combined-analyze.log`, and
`/tmp/lineup-m3b-u1-combined-harness-build.log`.

C1c will explicitly select the existing Windows adapter contract target because
M3b changes its actual HWND/codec fullscreen assertions. Merely modifying an
EXCLUDE_FROM_ALL target does not execute it in normal CI. Current local evidence
cannot establish Windows runtime prerequisites or a hosted pass; failures must
remain visible and no unverified installer/skip may be substituted.

The controller attempted to expose the combined M3b/U1 harness for a native
fullscreen → Player-button reversal check. CUA reported that the Mac was locked
and automatic unlock was unavailable. No visible result is claimed. The human
has been asked to unlock it or defer visible checks; reviews continue. Physical
Command-modifier checks remain distinct because of the proven CUA limitation.

C1c exact reviewed workflow is integrated as `ee379d3d`. The independent reviewer
verified the target's actual adapter/codec/runtime entry, exact CTest name,
configuration/dependency flow, preserved PowerShell failure handling and no-test
error, and unchanged unrelated workflow. This is source-wiring acceptance only;
no Windows/hosted pass is claimed. The CMake per-test 45-second timeout still
applies despite the CLI's 60-second default.

M3b independent review approved implementation/correctness/ownership with a
nonblocking P3 factual correction: a media load does not advance the native
lifecycle generation. The controller corrected only the rationale in three
source/test comments and the protocol paragraph: synchronous publication makes
observations precede replies so the next serialized Dart toggle sees actual
state. Initialize/dispose are the native generation boundaries. The final
18-file manifest aggregate is
`403853facc7368ca1a9999d336da6d47db954a623de0b3ae15457f0c395b4667`.
The independent reviewer confirmed that only those four rationale texts
changed and approved the final manifest; original execution evidence remains
explicitly attributed to the preceding aggregate,
with unchanged execution paths. Windows and physical acceptance remain gates.

The controller integrated the exact final M3b manifest locally as `e0f1b638`.
The required Windows native adapter contract is now selected in CI by
`ee379d3d`, but no hosted run on these commits has been dispatched or passed.
The next external action would be publishing the reviewed `platform/macos`
branch to `origin` on GitHub to obtain actual Windows/macOS CI evidence; human
authorization is being requested for that concrete action. No main-branch merge,
release publication, account/signing setup or App Store submission is included.
Mac unlock and Licenses UI direction questions remain pending. Physical-key
acceptance is still needed because of the established CUA modifier limitation.

## Authorized hosted CI and combined visible check

The human explicitly authorized publishing the reviewed `platform/macos` branch
and running CI. The controller pushed `feb453cb` to `origin/platform/macos`.
The workflow's push trigger covers only `main`/`flutter-mvp`, so the controller
used its existing `workflow_dispatch` on this branch. Actual run:
[39079367554](https://github.com/TJZine/LineupDesktop/actions/runs/39079367554),
head `feb453cbec0f89b86d6977a0d101b57f6908abab`. Initial observed passes:
macOS shared-core contracts, Windows release policy and release-input detection.
Mac portable/native, Windows player/contracts, Dart and engine/package remain
in progress. Child `01a14bdd-a2a0-7ba0-bcb5-c06320493487` (worker_luna) owns
read-only single-run verification and meaningful failure/completion callbacks;
it may not dispatch/push/fix/cancel or interfere with physical checks.

After the user unlocked the Mac, the combined real-protocol Debug harness
passed these cross-source fullscreen observations with real synthetic playback:
green-button entry → Player-button exit; Player-button entry → View-menu exit;
Player-button entry after that native exit; and View-menu entry → Player-button
exit. Native menu labels/window chrome confirmed state. Reversing the native
entry through Player and entering after native exit distinguishes synchronized
Dart state from a stale boolean. The synthetic HDR ramp also rendered after
switching from the SDR fixture and appeared in the Guide aperture. This is
observed presentation/control behavior, not human HDR color or exact alpha
acceptance. Debug dylib SHA-256:
`9b68e82ea613a14cef992edbff97984ec9b23de2cace52de2eb83d9257150305`.
The build is attributed to the original executable M3b aggregate with the
subsequent comment-only rationale correction recorded above.

The controller left the app windowed in Guide playing the HDR fixture, then
handed exclusive UI access to the human for actual Command key, text selection,
Control-Command-F, live-resize/alignment and switching/transparency checks.
Those answers remain pending. No automation or child may interfere with that
human check. Licenses-screen direction remains pending; purchase work deferred.

## Physical input results and visible HDR failure

The human confirmed all requested physical keyboard checks pass: Command-3
opens Settings, Command-1 opens Guide, Command-F focuses search, Command-A
selects entered search text, Command-comma opens Settings, and
Control-Command-F toggles fullscreen from Guide, its search field and Player.
This supplies the physical modifier-key evidence unavailable through CUA.

The same human check found a visible HDR switching defect in the combined
Debug harness: switching to SDR channel 1 looks correct, but switching back to
HDR channel 2 while in Player produces substantially dimmer output. Opening
Guide restores brightness for that same clip; returning to Player preserves the
correct appearance. The human explicitly clarified that screenshots cannot
capture the brightness difference. Their direct observation establishes failure;
layer flags or screenshots must not be substituted for physical HDR acceptance.
Live-resize/alignment and exact transparency acceptance are not inferred from
this response. The prior hidden-load probe does not settle this visible-switch
scenario.

Native worker `01a14bc0-ab3f-7c73-bb93-75341fdc3420` owns diagnosis and exclusive
app/UI resources. It first preserves the current app/logs, then compares the
visible HDR → SDR → HDR sequence with the same-clip Guide/Player transition.
Source inspection shows that content color-space changes already request
swapchain recreation; missing recreation is therefore not yet an established
cause. Layer transaction publication and drawable/presentation state are
distinct hypotheses. Temporary isolated-copy diagnostics are authorized if
existing logs cannot distinguish them; production edits and accepted-runtime
mutation are not. The controller coordinates any further human brightness
observations. Experiment plan: `/tmp/lineup-visible-hdr-investigation/experiment.md`.

## Hosted Windows contract startup failure

Run `39079367554` passed Dart, shared-core contracts and Windows release policy.
The Windows application and native contract executable built successfully, and
the existing selected native suites passed. The newly selected
`native_player_contract` failed at process startup with `0xc0000135` in 0.04
seconds; no contract assertion ran. Its failure was propagated, not skipped.
Mac portable/native and patched-engine/package jobs were still running at this
observation.

Windows worker `01a14bfd-7a31-7e50-9de6-e6318b5c1aac` owns the bounded CI
diagnosis. Hash-verified PE imports confirm that the pinned libmpv imports
`vulkan-1.dll`; the hosted image inventory does not list Vulkan, but the actual
runner's missing DLL is not yet proven. The worker is preparing a minimal hosted
dependency probe, preserving the real test and its failure status. Any workflow
or focused CI-helper change requires independent review before controller
integration and an authorized branch push/rerun. Runtime pins, production
adapters and package policy remain outside this unit. CI observer
`01a14bdd-a2a0-7ba0-bcb5-c06320493487` follows the remaining jobs read-only and
reports a new failure or completion.

The held existing-app baseline physically reproduced the defect: the human
reported phase C (SDR → HDR in Player) as dim, then phase D (same clip opened in
Guide) as restored brightness. Phase E returns to Player without changing media
and remains pending. Original process PID 51721, executable SHA-256
`c4d72ca2837686cfe372b639947238176af3195c7efb92191bc3fe4f6d025efa`,
Debug dylib identity as above. Existing stdout/stderr were `/dev/null` and no
presentation records were available in unified logs, so this baseline cannot
settle layer/swapchain/headroom hypotheses. The worker preserves the phase log
under `/tmp/lineup-visible-hdr-investigation/` before isolated instrumentation.

The independent CI reviewer approved the exact three-file startup diagnostic
patch, SHA-256
`37f5d1b86081e200b7da6bba5314117bed30501b672768e317e1ca6083fb15bc`.
It wraps the unchanged real contract invocation, runs the focused helper on
failure, and rethrows the original CTest failure even if diagnostics fail.
AST/YAML and real PowerShell control-flow probes passed; actual Windows loader
execution remains a hosted gate. The helper's process can identify failed DLL
loads, but a failure may also reflect a dependency of that named DLL, and a
successful load does not itself prove the original test can start. No runtime
acquisition or presumed Vulkan remedy was added. The current workflow cancels
older runs on the same branch, so the controller will preserve the still-running
macOS/package jobs before dispatching this diagnostic revision.
