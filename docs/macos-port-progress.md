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

The human confirmed phase E remains normally bright after returning from Guide
to Player on the same clip. The physical baseline is therefore C dim → D
restored → E still restored. The native worker is proceeding with the authorized
isolated real-Flutter diagnostic copy, keeping production source and accepted
runtime immutable. Initial diagnostic launches were invalid: reading a
Metal-specific property from Core Animation's presentation-layer copy crashed
the added instrumentation. The crash report identifies that probe-only read;
the worker removed it before rebuilding. Those attempts establish no product
regression or presentation result. Model-layer facts, generic presentation
geometry and mpv swapchain logs remain the intended diagnostic evidence.

The corrected instrumented run did not reproduce the dim output: the human
judged held HDR phase C normally bright. Logs showed PQ/bt2020 target selection,
actual HDR swapchain recreation at unchanged 1600×1200 extent, and model-layer
PQ/EDR/metadata enabled. These facts apply to the successful diagnostic run and
do not explain the original failing process. A reduced-logging variant also
received a normally-bright physical judgment. It removed polling,
presentation-layer reads and mpv debug options, and reused the original
`App.framework`; engine and runtime hashes matched. Event logging could still
perturb timing. The worker is next comparing a fresh launch of the unchanged
original binary with the same endpoint sequence. No production correction,
causal conclusion or HDR acceptance follows from these non-reproductions.

The unchanged original binary's fresh comparison was confounded by Stage
Manager: the human saw dimmer output in its miniature and correct output after
both focusing and entering fullscreen. Activation and extent changes were not
separated, so this does not explain the original failing process. The controller
requested one human-driven, fixed-size windowed SDR/HDR sequence with Lineup
remaining foreground until brightness is judged. That answer remains pending;
automated scene changes and runtime-proof processes are paused meanwhile.

Hosted macOS runtime provisioning and identity validation passed in run
`39079367554`, but its required authenticated-reference proof failed with
`invalid_harness_outcome`, exit 2, before any case outcome. Investigation found
a definite fixture defect introduced by the expanded fullscreen observation
path: successful initialization now reads the window's `styleMask`, while the
headless `ReferenceWindow` double implemented no such selector. The exact hosted
exception remains inferred because child status/output were not exposed.

The independent reviewer approved the exact three-file fixture/diagnostic patch
SHA-256 `f9aea51deabf8a73db289d4da72cd065bf958e6553525a8406c9c9c6d51ab348`.
The fake reports a truthful borderless/windowed style; malformed harness outcomes
now expose only safe case/status/signal/validation fields while retaining exit 2.
Pure parser/control-flow checks pass, including malformed/non-ASCII/missing
fields and private-sentinel exclusion. Production adapter/core/runtime inputs
remain unchanged. Actual isolated 26-case proof and hosted recovery remain
pending; no prior passing matrix is relabeled as proof of this combination.

The human completed the fixed-size foreground sequence and judged final HDR
normally bright. They further identified rapid back-and-forth switching as the
trigger: it fails when switching faster than the suggested 8-second waits.
Slow-switch success does not close the defect. The native worker now focuses on
rapid switching, with the accepted product/runtime inputs still immutable.

After independent approval, actual isolated authenticated-reference verification
on clean commit `4f4a80d4` exited 0 with all 26 required cases passing. Evidence:
`/tmp/lineup-reference-window-style-after/report.json` and `identity.json`;
report SHA-256 `e6b7b59db241e575a26e3356fe88475108f76a027557523c7fb3b378644c924d`;
built harness `b8f50333519988b4a2e203f6f4db9aab309be84d7d8437e890c0e20eda92b885`.
The accepted local runtime's lock, BUILD-INFO and libmpv identities match those
recorded above. This is current local headless adapter/codec/core/runtime proof,
including the matrix's negative controls; it does not establish hosted runtime
or physical HDR acceptance. No production source, accepted runtime or primary
generated output changed. The proof resource was released to the native worker
for rapid-switch diagnosis. Hosted recovery remains required.

Run `39079367554` is now terminal: Dart, shared core, Windows release policy and
patched Flutter engine/package jobs passed; Windows contract startup and macOS
authenticated-reference jobs failed as recorded above. The controller preserved
the long-running engine/package job until completion, then dispatched
[39087575645](https://github.com/TJZine/LineupDesktop/actions/runs/39087575645)
at exact pushed head `5740cc9855724b0e473b6956fddde2c2f24b9099`.
This run includes the reviewed Windows loader diagnostics and the reviewed,
locally verified authenticated-reference fixture correction. It was queued at
dispatch; no current-run pass is inferred from the preceding run. The same
read-only CI observer owns meaningful failure/completion callbacks. Human rapid
foreground HDR reproduction remains separate and pending.

The diagnostic rerun's Windows job `117557271385` identifies unavailable Vulkan
loading: the only inspected failures are `libmpv-2.dll` and `vulkan-1.dll`, both
Win32 126; other inspected imports load successfully. This is stronger than the
original generic startup status, although 126 can also name a transitive failure.

The independent reviewer approved the CI-only prerequisite patch SHA-256
`2c32d3870bdb06c1c3d1a32d63d70efa81237c8027afa1cbdb00b81ad65d277e`.
It selectively extracts a hash-pinned official LunarG 1.4.335.0 non-installer
components ZIP into a new `RUNNER_TEMP` directory. The selected AMD64 loader
exports all ten Vulkan functions imported by the pinned mpv; archive/DLL hashes,
PE identity, license and official inventory were independently checked. Only
the required contract test and its failure diagnostics receive that temporary
PATH entry, restored in `finally`. Production runtime/package inputs, the real
test and no-skip behavior are unchanged. Static/AST and isolated PowerShell
failure-control checks pass. Full helper execution, Windows loader closure and
the actual contract remain hosted gates; a loader supplies no GPU driver or
physical playback proof. The controller will preserve the current run's ongoing
macOS/package jobs before dispatching this prerequisite revision.

Hosted run `39087575645` has now passed the complete macOS portable/native job:
required authenticated-reference proof, embed integration, app build and native
tests. This supplies hosted recovery evidence for the fixture correction at
`5740cc98`; it does not close physical HDR acceptance. Its patched-engine/package
job remains in progress, so no next dispatch has occurred yet.

The human rapid foreground sequence reproduced HDR remaining dim for at least
five seconds on the unchanged original app. No Guide/fullscreen/resize repair
was requested. The worker preserved exact process/binary/runtime identities,
then performed bounded read-only model inspection and detached. The post-reply,
post-debugger snapshot reports PQ, EDR and metadata enabled, drawable 1600×1200
matching bounds 800×600 at scale 2, windowed and visible. It is not a pristine
foreground capture: debugger pause/getters may affect scheduling, and the
bounded external trace ended before the human result. These nominal model facts
neither establish correct presentation nor explain the failure. The worker is
authorized to build an isolated, transition-only diagnostic copy for the rapid
sequence, preserving original Flutter/runtime inputs and observing actual load,
stop, playlist and color identities. No production HDR correction or speculative
resize workaround is approved.

The transition-logging candidate also physically reproduced the dim rapid-switch
result. Its frozen trace ends on coherent HDR load/playlist 9 with current source
and target PQ/bt2020, layer PQ/EDR/metadata enabled, expected drawable extent and
current/potential display headroom both 16. No later load/stop replaces it. Native
invocation timing does not establish sub-100ms switching: the last SDR→HDR gap
was about 3.64 seconds, so requested key cadence and executed loads remain
distinct. Frozen trace SHA-256
`79ccb3decc672ed1fb735cf7a1c159afd1f8da6f51bcdb0c6ea97681fdd3052d`.
These facts narrow wrong-final-load and nominal model-state explanations, without
proving framebuffer values, acquired drawable configuration or actual presentation.
An independent source review confirmed those observational gaps and found no
established root cause or justified production correction.

A proposed debugger-only control never ran: its foreground-stability gate was
not met, and no attachment, flush or app-code action occurred. The human later
reported the app was already bright when brought forward; that supplies no
causal control result. The pending controller was disarmed and stopped. The
next authorized isolated diagnostic observes actual returned Metal drawable
format/size and selected presented callbacks, preserving normal acquisition and
lifetime behavior. It requires another matched physical rapid failure before
interpretation. No production playback change or HDR workaround has landed.

The user requested an Opus 5.5 investigation handoff. Further HDR experiments are
paused; all timed controllers and external observers were stopped and the
current diagnostic app was left untouched. The latest physical endpoint is
bright after a reported same-channel HDR reselection. Frozen evidence is indexed
at `/tmp/lineup-visible-hdr-investigation/opus-freeze-index.json`.

The latest drawable trial sampled 94 acquisitions with no actual texture
format/extent mismatch; 85 of 94 selected callbacks had positive presentation
times. These do not measure pixel payload or physical luminance. Crucial
qualification: the trial contains an actual 1600×1200 → 425×239 → 1600×1200
extent roundtrip during load 10, and final HDR load 19 follows SDR load 18.
Several other HDR→HDR pairs exist. The human's same-channel repair observation
cannot yet be uniquely assigned to one native pair or separated from all geometry
history. No root cause or correction is established.

The self-contained handoff is `docs/handoffs/macos-hdr-investigation-opus.md`.
A compact, hash-manifest-verified bundle of that handoff, selected frozen traces,
diagnostic patches and relevant source snapshots is
`/tmp/lineup-opus-hdr-handoff.tar.gz`. The bundle excludes runtime binaries and
private process dumps. Existing read-only CI observation remains separate; no
new HDR probes or production changes are queued.

Run `39087575645` is now terminal: all jobs passed except the diagnosed Windows
native-loader prerequisite failure; the patched-engine/package job also passed.
The controller then dispatched the pending reviewed CI prerequisite at remote
head `b0c38b5be5546c4cf00a96ff6b61deaf30dd28dd`:
[39095353188](https://github.com/TJZine/LineupDesktop/actions/runs/39095353188).
Local handoff/progress-only commits are not published by this dispatch and have
no product-input difference. This run must establish actual loader preparation
and native-contract execution. Existing read-only CI observation continues;
HDR investigation remains paused for the requested Opus handoff.

Windows run `39095353188` successfully provisioned the pinned Vulkan loader and
loaded both Vulkan and libmpv. Its native contract then reached a real assertion
failure, `disposed owner permits immediate close`, rather than failing at
process startup. Investigation found a pre-existing ordering defect:
`BeginWindowClose` called `EndSession` (which marks display release pending)
before checking already-completed shutdown, making immediate close race with
the display worker. Independent review approved the exact three-file correction
patch SHA-256 `beacc768d2746fcbfb88e50aa4dd93c45b499b5b87bfd79cfe44256bf01c5e04`.

The completed-state guard now precedes new release work; the asynchronous tail
and three-second timeout policy remain unchanged. The existing contract fixture
waits for actual close readiness, consumes it once, separately establishes real
display release, and retains immediate/repeated close assertions. It now forwards
the actual timer parameter as production does. Source/whitespace checks pass;
no Windows compiler/runtime is available locally, so actual hosted compilation
and passing-after contract execution remain required. Only the three Windows
files and controller record are integrated; concurrent Opus artifacts and all
HDR investigation resources are excluded.

## Authorized production follow-up to Opus findings

The human explicitly resumed implementation from
`docs/handoffs/macos-hdr-root-cause-and-switch-latency.md` at source
`94b459a05c963f62efdf4ec4d0bd22344efe855d`. The Opus handoff remains an
untracked user artifact and is preserved. Its historical status paragraph is
superseded by this ledger's actual approvals and CI results.

H1: worker `01a14bc0-ab3f-7c73-bb93-75341fdc3420` (`worker`, Sol medium) owns
the production adapter-owned Metal layer flush, focused native proof and minimal
related contracts. The accepted runtime is immutable; the diagnostic patch must
never be merged. It must resolve off-main dirty-thread/mismatch semantics,
preserve acquisition/lifecycle behavior, and return a frozen candidate for
independent adversarial review. Physical arm A/B acceptance and in-app EDR
headroom evidence remain mandatory. This worker initially owns exclusive Mac
app/UI/native build resources.

L1: worker `01a14bfd-7a31-7e50-9de6-e6318b5c1aac` (`worker`, Sol medium) owns
seek intent through Dart transport/coordinator and the shared native core.
The approved policy is keyframe at or before schedule position, never after it,
for schedule/tune joins and their recovery reloads; explicit user seeks remain
exact, including overrides during pending loads. Observed landed-versus-target
offset must be logged safely, and end-of-program rollover verified. This slice
may run Dart/isolated portable core checks in parallel but may not use the Mac
app/native media resources during H1 acceptance. Shared-core changes require
Windows CI and independent adversarial review before integration.

L2 follows L1: measure per-file `loadfile start=` against the corrected join
baseline, preserving the backward-join correctness floor, identity/currentness,
token safety and comparable workloads/cache/resource conditions. Its benefit is
unmeasured; no production start-option or stop-serialization optimization is
included in L1. The benchmark-checklist skill governs the comparison. The
controller retains scope, Git integration, combined verification and completion.

H1 implementation decision: a transaction must be published on its setter
thread. A dirty-thread marker cannot make another thread flush it, and teardown
may set 1×1 without another acquisition. The controller authorized evaluating
immediate publication after each relevant off-main setter in the adapter-owned
subclass, avoiding redundant acquisition barriers when all mutations are already
published. This timing differs from Opus's physically proven drawable arm and
is not assumed equivalent: physical A/B plus teardown/black-flash acceptance
must establish it before integration. H1 builds use an isolated baseline plus
only H1 files so concurrent L1 core edits cannot contaminate their evidence.

L1 source investigation found that mpv's normal absolute/keyframe path is
backward, but its cached demuxer may return a packet after target if no better
one exists, and lavf retries without BACKWARD after backward-seek failure.
Changing flags alone therefore cannot prove strict never-past. The human has
been asked to choose fail-without-advancing versus exact-seek fallback for an
unavailable predecessor; that dependent policy remains pending. The worker
continues intent/currentness design, including a faithful correlated observed
landing rather than logging enqueue success or pre-seek time position.

The human clarified and superseded the strict L1 interpretation: exact entry
position does not matter for live-TV joins. Use plain `absolute+keyframes` for
schedule/tune/recovery joins; explicit user seeks remain exact. Do not add a
failure path, exact fallback or paused landing guard. The no-predecessor mpv
fallback is accepted; end-of-program rollover still needs verification. Landed
versus target logging must remain passive and truthful. Earlier strict
never-past/fail-closed design obligations above are withdrawn.

The human also explicitly approved H1's simple off-main setter-thread flush
without a redundant acquisition barrier. Physical acceptance must additionally
check black/wrong-color flashes between channels and switch-latency regression.
If flashes occur, the authorized fallback is the proven pre-acquisition barrier
plus setter-thread flush only for writes on threads that will not acquire again.
That fallback is conditional on evidence, not part of the initial implementation.

H1 independent adversarial review approved the frozen candidate aggregate
`e442c94974fbbd811a2a6494da1ab3792b209724470a7ce2a55a5d3d1847b500`
for physical A/B, not as physically accepted. Its isolated native run recorded
22 passes plus one pre-existing destructive-probe skip; a plain-layer negative
control failed the intended publication check. Matched arms were built from the
same fixed snapshot with identical framework inputs. Arm A was launched on SDR
channel 1, but **no human arm-A judgment was supplied**.

The human then directed: “opus will perform any verification needed. we dont
need to do that here”. New verification runs, physical prompts, measurements
and CI polling/dispatch are stopped here. Workers may finish implementation and
the explicitly requested independent code review; frozen candidate/review
artifacts and remaining acceptance/measurement protocol will be handed to Opus.
Existing test/CI observations remain attributed evidence, not a new pass. H1
physical brightness/headroom/flash/latency/resize/fullscreen/shutdown acceptance,
combined checks, L1 target-runtime/Windows CI and L2 measurement remain open.

CI observation is stopped as directed. Last observed run `39095353188` at head
`b0c38b5be5546c4cf00a96ff6b61deaf30dd28dd`: macOS portable/native job
`117580539221` passed; Windows job `117580539403` passed loader setup/loading
but failed the close-order assertion; patched-engine/package job `117580586571`
was still building. The run was not terminal at that observation. Reviewed
Windows close fix `94b459a0` has not yet received a hosted passing-after result.
Opus must establish subsequent status; no further polling is queued here.

L1 independent code review found one P2 passive-diagnostic gap: a later worker
command could publish a current-load `command_error` without invalidating an
earlier pending landing observation. The controller accepted the source finding
and requested a narrow observer invalidation plus an existing fake-operations
regression case. No new playback guard, error reclassification or wire contract
is authorized. The correction/test are to be inspected but not executed here;
Opus owns their execution. Final L1 approval and the single combined handoff
await targeted re-review of that correction.

L1 review is now closed. The production observer invalidation was approved;
targeted re-review also caught an old-load failure left in the new regression's
setup. The controller retired load 85 through the existing End-file fixture
before beginning load 86, and the reviewer approved that narrow correction.
Final L1 patch `b8b375fc5af227570681950d527981bf1ecf8045a2219332eef64c3f76eaa98e`
and `/tmp/lineup-l1/manifest-r2.json` bind the final source. Both native
corrections and the new case remain unexecuted, assigned to Opus; historical
native passes are not relabeled as final passing-after evidence.

At the human's request to finish source/review and hand over verification, the
reviewed code is saved locally as verification candidates: H1 `ce77d18d`, then
L1/combined checkpoint `8bca5171fe73bb6b7b835e415f8372d8cef93902`. No new push,
CI dispatch or verification run accompanies these checkpoints. Physical and
target-runtime acceptance remain open. The single consolidated handoff is
`docs/handoffs/macos-hdr-and-seek-opus-verification.md`; it covers both reviews,
exact evidence boundaries, physical A/B, final corrected native tests, combined
checks, Windows close-fix/core CI and the unexecuted L2 measurement proposal.

### L2 production follow-up — 2026-10-18

The human accepted H1 and L1 after Opus's verification recorded in
`docs/handoffs/macos-hdr-and-seek-verification-report.md` (`42ab5784`). That
report includes physical combined acceptance, 1750 Dart passes, portable core
3/3, Mac native 22 passes plus the existing destructive-probe skip, and Windows
native passing-after evidence for `94b459a0`. Its stated rollover, older-OS,
physical Windows and release limits remain. The earlier verification stop is
superseded by the new instruction to implement and verify L2 in this chat.

L2 source starts at clean `platform/macos` / `42ab5784`. Schedule, tune and
ordinary recovery joins will use per-file string `start` and `hr-seek=no`
options on `loadfile` at index -1, preserving URL bytes and credential,
redirect and reference policy. Dart owns the initial target explicitly;
mutable observed/resume position must not decide whether a post-load join
seek is needed. Explicit user seeks remain exact, including supersession
while loading. The native landing observer gains a matched, bounded initial
restart window. The existing <=2-second join skip and pause/display/stop
semantics remain. No diagnostic patch is integrated.

Dispatch: implementation chat `01a14bfd-7a31-7e50-9de6-e6318b5c1aac`
(worker / Sol medium) owns production load/coordinator/core contracts, related
tests and protocol documentation. Chat `01a14bc0-ab3f-7c73-bb93-75341fdc3420`
(worker / Sol medium) owns only the existing Mac/Windows authenticated-reference
harnesses and runners, extending real matrices for nonzero initial starts and
actual post-landing progression. Chat `01a14bdd-a2a0-7ba0-bcb5-c06320493487`
(worker_luna / Luna xhigh) performed bounded read-only CI status diagnosis.
The controller owns Git, progress documentation, stable combined checks,
independent adversarial review, runtime resource scheduling and the repeated
Plex ABBA measurement. No new child chats were created. Original human
orchestration/callback authorization remains parent turn
`01a14bbd-70f9-7943-b707-1f8a7e70a35c`; the new L2 instruction is parent turn
`01a14d94-87e0-7402-b184-bc3f038a73bd`.

As of 05:57 UTC, CI `39098816614` at `cc6dc2e2` is still in progress: all
other jobs passed, while patched-engine/package job `117590790547` is building.
No actual failure is visible in the available buffered log. Its terminal
result must be checked before any branch push or dispatch; a packaging failure
will be handled as a separate change. No push, cancellation or replacement
dispatch has been performed for L2.

Remaining L2 gates: freeze source, focused/combined portable checks, independent
adversarial review and remediation, real authenticated-reference matrices,
target-runtime correctness controls (including part boundaries, near-end and
rollover, exact user seeks, recovery and pause/currentness), Windows CI, then
matched Plex ABBA timing with all failed/missing samples retained. Opus's
disposable timing is feasibility evidence, not a measurement of the final
production candidate. `/tmp/lineup-l2-apps/l2-diagnostic.patch` must never be
merged.

L2 production source is frozen at aggregate
`733a150151ae02326256d6c148f9b1c3fea921b38b44ea8724bd25e8cc425ee8`
(`/tmp/lineup-l2-production/manifest.json`). At the human's explicit request,
both adversarial reviews use fresh chats: production review
`01a14d9e-a7eb-7ed2-b32c-f5f7d06cd3b7` and reference-proof review
`01a14d9d-d87e-7343-b3ca-708debeeabc1`, each reviewer / Sol high. The production
review approved all 18 owned files with no material finding; runtime acceptance
remains separate. Focused checks passed 501 playback-related plus 127 other
Dart tests and portable core 3/3. The controller's full combined suite passed
1758 tests with the pinned SDK on the Eastern-time host.

The first real Mac reference campaign passed omitted-start 26/26 and nonzero
22/26. Four alternate positive/control cases failed their landing/progress
assertion, with no authorization rejection, timeout or observed credential
leak. The fresh review independently established that a current property query
after a queued restart is consumer-delay-dependent and can misclassify landing.
An isolated diagnostic observed the alternate fixture actually restarting at
zero. These are unresolved proof/fixture questions, not established production
authentication failures. The worker is diagnosing exact command options and
fixture seekability; no production repair has been inferred from the failure.
Authorized harness corrections include a test-only stationary observation phase
followed by real advancement, a real ignored-start sensitivity control, and a
real plaintext redirect listener/control for Windows. Production pause policy
is unchanged. Targeted re-review and a fresh full matrix are required.

The controller added explicit Windows authenticated-reference build/run wiring
and Mac FFprobe preflight to CI. Fixture executables are a publisher-checksummed
versioned FFmpeg archive in `RUNNER_TEMP`, separate from all application/runtime
inputs. The downloaded archive hash and expected executable entries were
checked locally; workflow YAML parses. These checks do not execute Windows.
The fresh reference reviewer will inspect this wiring with the harness repair.
The production worker now owns the exclusive Flutter Mac app resource for
disposable real-coordinator correctness controls; the reference worker uses
separate standalone headless outputs. No L2 push or CI dispatch has occurred.

The fixture failure is now explained by an isolated same-bytes comparison:
the old HTTPS server ignored byte-range requests, reported unseekable input,
and mpv played from zero despite receiving `start=3.5` / `hr-seek=no`.
Correct single-range 206 responses produced a seek and a three-second keyframe
landing. The repaired fixture preserves authentication before every response.
Five focused real Mac checks passed, including delayed correct and deliberately
ignored starts. The fresh reference reviewer approved the corrected four harness
files plus CI/docs changes, closing both findings in source. Full corrected
Mac 54-case and Windows 48-case results remain required; the earlier failed
52-case campaign is preserved as failed evidence.

Reviewed source is saved as local verification candidates: production
`770396e1` and reference/CI proof `7cb730f8`. Source hashes match the approved
production and corrected-auth manifests. These commits do not claim completed
runtime/Windows/Plex acceptance. CI `39098816614` was still building its package
at the last check, so neither candidate has been pushed or dispatched.

The corrected real Mac reference campaign passed 54/54 (26 omitted-start,
28 nonzero-start), including delayed correct and ignored-start controls, with
no child timeout/server error. Evidence and executed-source attribution are in
`/tmp/lineup-l2-auth/macos-matrix-corrected/`; all tested product/harness hashes
match the local candidates. The original failed campaign remains preserved.

The disposable real-coordinator Mac probe passed 14 bounded cases with 22 native
loads, 9 exact seeks, two actual last-part EOF-to-successor transitions and four
authorization replacements. Two opening failures were real native TLS 401s;
two same-load timing failures were explicitly injected signals with real
replacement playback. It covered initial zero/2-second controls, a non-keyframe
join, pending same/latest exact intent, cross-part exact zero, ordinary recovery
after completed exact seeking, pause and stale tune retirement. Evidence:
`/tmp/lineup-l2-production/runtime-acceptance/report.md`. Active display holds
remain Dart proof on this unsupported Mac matching route; no physical Windows,
Plex performance, sandbox/distribution or first-frame claim follows. The probe
has exited cleanly and released app resources; its patch must never be merged.

The worker is preparing a new disposable, explicitly correlated production A/B
measurement harness. Counted timing is not released until Windows CI passes.
No timing or production change from the old L2 diagnostic patch is adopted.

The human explicitly assigned all remaining verification to the agent, using
computer use for application interactions; HDR remains accepted from the prior
Claude session and is not reopened for human brightness judgments. The
controller activated the prepared measurement app with computer use for
`development-02`. Its records confirmed foreground throughout, but three of
four development joins lacked a qualified measurement observation while video
visibly played. The app shut down cleanly. This failed smoke is preserved;
backgrounding is not a sufficient explanation, and no latency result is
accepted. The worker is tracing the disposable harness's event/observation
window before another frozen foreground smoke. Production source is unchanged.

At the human's request, the long-running benchmark worker was stopped and its
resources released. Fresh diagnostic chat `01a14dc2-e884-7700-a324-b34616408fa1`
(Sol high) takes over the single unresolved cached-failure/measurement question
in a new isolated directory. The authoritative old state is
`/tmp/lineup-l2-production/benchmark/takeover-state.json`; v1 source/app manifests
do not describe the later trace builds. Trace 04 exited normally when stopped
before producing results, so its exit 0 is explicitly **not** a passing smoke.
No counted synthetic or Plex measurement has run. Several app copies share the
same bundle ID; PID/executable identity must accompany computer-use foreground
checks. Accepted production, reviews and Mac correctness evidence remain intact.

The old CI watch was interrupted before a terminal result. An independent
controller check confirmed `39098816614` had completed the patched-engine build
and was compiling Lineup against it, with package upload still pending. Every
other job remained successful. The run is still protected: no push or new
dispatch until the controller verifies its terminal result.

The fresh diagnostic isolated the missing-sample cause: CoreAudio ChannelMap
initialization fails, then mpv successfully falls back to AVFoundation on the
same load (48 kHz stereo and advancing audio/video timestamps). The cached
`audio_output_error` is deferred detail for a later failed `END_FILE`; it does
not represent ongoing failed playback. The old observer nevertheless retired
its sample on that cache alone. Diagnostic runs remain failed timing attempts;
there is no user-facing playback or performance acceptance claim from them.

The controller authorized a narrow passive-observer correction: retain cached
terminal-error detail, but retire samples on actual command/terminal/lifecycle
failures rather than the mere presence of that detail. Regression proof must
cover initial and explicit seek observations, retained later error provenance,
and unchanged actual-error suppression. A new fresh independent review is
required before integration. No audio-backend policy, error-cache clearing,
HDR behavior or benchmark failure guard is changed to obtain timings.

The narrow correction is now local commit `d116ad7a`. Fresh independent review
chat `01a14dd0-57e4-7c53-829c-65c86d570266` found no material correctness or
design issue across the four frozen files. The revised production-handler
regression fails before the correction and all three portable native suites
pass afterward. Later terminal errors still retain and publish their cached
detail. Windows execution remains pending.

The fresh worker's final disposable foreground smoke passed all four joins
with matched landing observations, current load identities, healthy
AVFoundation output, advancing audio/video and stable SDR/PQ routes. Computer
use activated the exact running bundle through Finder; all rows recorded
foreground state and fixed geometry. Both the driver and independently rerun
standalone analyzer accepted the complete run, with no counted timing summary.
Earlier failed smokes remain failed. Evidence:
`/tmp/lineup-l2-fresh/benchmark-next/smoke03-report.md` and
`runs/foreground-03/`, manifest SHA-256
`91d14f236cd2507e4093e5e1a923b224dda9d5b28baa9ae9dbcb3c4399ed42e5`.
This build includes `d116ad7a` plus a never-merge measurement probe. No counted
synthetic or protected Plex run is released before Windows native/auth CI.
The app exited and released the shared runtime resource.

At 07:36 UTC on October 18, protected CI `39098816614` remained in progress.
Its actual logs establish that the first engine build used Ninja 1.11.1 via
depot_tools, while the next step selected Chocolatey Ninja 1.13.2. That command
reported an old build-log version and began rebuilding the same 6,049-edge
graph despite an unchanged `build.ninja`. Separate worker chat
`01a14df1-7784-7001-8a1a-744b791ee9d1` (Sol medium) owns read-only diagnosis,
a proposed repair in `/tmp/lineup-l2-ci-repair/`, and the terminal-result watch.
It cannot edit the checkout, integrate, push, dispatch, cancel CI or use the
app. Any accepted CI repair will be reviewed and committed separately from L2.
The controller still owns the no-push/no-dispatch gate and Git integration.

The CI worker prepared an eight-line workflow-only proposal to persist the
already pinned depot_tools path and existing engine toolchain environment into
later steps. Both Ninja invocations and all build/provenance checks remain.
Patch `/tmp/lineup-l2-ci-repair/ci-toolchain.patch` has SHA-256
`4aa4699acfb3f9b5064888129b983a3032d8e37b4fb082d971a1b5a436bb36ef`.
Fresh independent reviewer `01a14df4-38af-7543-ba8b-524a1ea5a63b` (Sol high)
owns source review; primary workflow has not changed. Actual local Ninja
version-switch reproduction supports the diagnosis, but is not Windows or
PowerShell execution. The protected run remained active at proposal time.

The fresh CI reviewer approved that exact proposal with no material findings,
after tracing downstream Ninja, Python, Git, Flutter and package-tool selection.
The primary workflow still matches the frozen before hash. This is source
review, not Windows execution. The controller independently confirmed the
protected run was still in progress at 07:42 UTC; integration/push/dispatch
remain held until its terminal result.

The controller independently verified the old run reached `completed` /
`cancelled` on October 18 at approximately 07:57 UTC. All six other jobs
succeeded; the package job was cancelled during the second engine build near
its three-hour limit and package upload was skipped. Neither controller nor
worker cancelled it. This is an incomplete package result, not a CI pass.
The old-run no-push/no-dispatch protection is now satisfied.

The independently reviewed eight-line repair was integrated as the separate
commit `fa43f41c` (`fix(ci): retain pinned engine toolchain across build steps`).
Its workflow hash exactly matches the approved after snapshot; patch checks,
whitespace and Ruby YAML parsing passed. Both real Ninja invocations and all
seven jobs/concurrency policy remain. New Windows execution must still verify
tool identity continuity, valid incremental work and package completion.
The combined L2 candidate is now eligible for its authorized branch push and
fresh CI dispatch. Counted synthetic/Plex measurement remains held until the
new Windows native and authenticated-reference job passes.

The old job's final annotation confirms `The job has exceeded the maximum
execution time of 3h0m0s`; its second Ninja invocation reached only
5,375/6,049 edges before cancellation. Final sanitized evidence is preserved
under `/tmp/lineup-l2-ci-repair/`. After independently checking terminal state,
the controller pushed `57f62c9422556fd1f4b1ba8d870adc228061a841` normally to
`origin/platform/macos` and dispatched CI run `39109697512` at 07:59:14 UTC.
The CI worker now owns that run's verification in
`/tmp/lineup-l2-ci-39109697512/`, including prompt notification of the actual
Windows native/auth gate and eventual full-run/package result. No subsequent
same-branch dispatch or cancellation is planned while that run executes.

The new Windows job actually ran and passed all seven native contract suites,
then failed its 48-case authenticated-reference matrix (44 passed, four
failed). Both untrusted-CA cases set `server_error`; the two later nonzero
delayed controls inherited that sticky flag despite expected landing/progress
results. No timeout or token leak was observed. Exact exception details were
swallowed, so a specific Windows disconnect exception is an inference rather
than observed evidence. The Mac fixture already distinguishes three expected
peer-disconnect types from fatal unexpected handler errors; Windows does not.
Fresh worker `01a14e0d-afa6-73b3-a65f-1415a5ad5fe7` (Sol medium) owns only the
Windows fixture repair and meaningful error-boundary controls. Root owns fresh
review and integration; counted measurement remains blocked. The current
engine/package and Mac jobs continue without cancellation.

The Windows fixture worker froze its two-file candidate under
`/tmp/lineup-l2-windows-fixture-fix/`, patch SHA-256
`b2f257f5ab0b7c9fae415e9a41dac3ec400d8fc8e950a225b848947828403832`.
Seven actual loopback/error-boundary controls passed on local Python 3.15 and
3.11; they do not identify the swallowed Windows exception or establish the
Windows matrix. Expected disconnects remain distinct from sticky unexpected
faults; bounded sanitized diagnostics will expose future attribution. Fresh
independent reviewer `01a14e12-eadf-7d43-b94d-d66d2932aec7` (Sol high) owns
the two-file review, including whether its TLS-accept handling and complexity
are justified. The human requested a candid explanation of the delays; the
controller identified the failed timing harness, duplicate CI engine build and
current fixture failure, and kept the remaining work limited to the Windows
gate and requested latency measurements. HDR remains accepted.

The fresh reviewer identified one accepted P2: the native child may exit after
a TLS socket closes but before the server records an unexpected error. A
per-case snapshot can therefore precede the fatal flag; listener teardown
waits for that path but did not reconcile the final profile result. The worker
owns a focused finalization correction and deterministic late-error control,
with no sleeps, flag resets or product changes. This is source-traced review
evidence, not a reproduced explanation of the original Windows failure.

Revision two adds the final sticky-failure check after existing listener
shutdown/join. Its eighth control uses the actual finalizer and a barrier to
publish an unexpected TLS error after a clean snapshot; the old finalization
fails that control and the correction passes. All eight controls passed on
local Python 3.15 and 3.11. Frozen patch SHA-256 is now
`d88b8bfacadb8b5ceb31c3c0cda8692373f51f283ecd6c3e2ea3cab57444d6f4`;
revision one remains preserved. The same fresh reviewer owns focused re-review
of its finding. No Windows rerun or counted measurement has yet passed.

The fresh reviewer approved revision two and closed the late-TLS P2. It
confirmed that listener completion precedes the final locked sticky-failure
check and that production finalization prevents a passing matrix return after
a late TLS fault. The original Windows exception remains unknown; the new
diagnostics and exact Windows 48-case execution must settle acceptance.

The controller is preparing a focused draft PR against `platform/macos` for
the reviewed fixture-only correction and progress notes. Existing CI change
filters can run the native/reference jobs without requesting another engine
build for these test-only changes. Its distinct head branch also preserves
the in-progress `platform/macos` engine/package run. No CI check is skipped or
weakened; package evidence remains attributed to that original run.

The fixture correction is local commit `a1875fc2`, followed by progress-only
`359afb38`. The controller pushed that exact head to
`dev/l2-windows-fixture` and opened draft PR #47 against the remote
`platform/macos` head `57f62c94`. PR CI `39111084372` was queued at 08:20:48
UTC; its fixture/doc-only diff uses the existing release-input filters. The
original `39109697512` engine/package run remains uninterrupted. The CI worker
owns both runs and will report the new actual Windows gate promptly. The
benchmark worker may only prepare supplemental source-equivalence evidence;
counted and protected Plex runs remain unreleased.


### L2 final bounded controller run — 2026-10-18

The replacement controller in chat `01a14e20-5cfd-7a61-ac19-6819dad1cd16`
explicitly took Git, CI-decision and app ownership. Live recheck found
`platform/macos` at `359afb385268bad653ec26ca37bb4646fca2a896`, two commits
ahead of its remote, with only the expected progress and handoff documents
dirty. PR #47 still targeted `platform/macos`. A GPT-6 Luna/low observer handled
read-only CI waiting with waits between queries. After the human explicitly
invoked `orchestrate-implementation-chats`, the controller stopped its
subagent and reused existing separate observer chat
`01a14df1-7784-7001-8a1a-744b791ee9d1` (GPT-6 Luna/low). The verified human
authorization is controller turn `01a14e21-3297-74e2-8f56-e27ebd2b6b53`,
message `01a14e2a-6ff2-7481-9556-f893ef3c1503`. The controller yielded, then
resumed on the observer's terminal completion callback and independently
rechecked both live runs before Git publication. No CI dispatch, rerun,
cancellation, product change, HDR recheck or verification infrastructure work
was performed in this closure. The latest human scope supersedes the old
synthetic-then-Plex instruction: skip counted synthetic, run protected Plex
once, record the result and stop.

**Windows L2 gate passed.** PR #47 run
[39111084372](https://github.com/TJZine/LineupDesktop/actions/runs/39111084372),
declared head `359afb385268bad653ec26ca37bb4646fca2a896`, genuinely executed
all seven native contract suites and the authenticated-reference CTest.
[Windows job 117627181538](https://github.com/TJZine/LineupDesktop/actions/runs/39111084372/job/117627181538)
succeeded; the authenticated CTest took 39.80 seconds with zero failures.
GitHub tested merge ref `741a2dbe2555c2551107f9a63905daba822c5778`, with
parents `57f62c94` and exact PR head `359afb38`; the fixture, native auth test
and workflow blobs match that head. The source's strict complete 48-case
all-pass return predicate establishes the matrix gate. Successful per-case
JSON/disconnect categories are absent from the public CTest output; no
specific old swallowed Windows exception is newly identified. Earlier 44/48
failure remains attributed to run `39109697512`, not relabeled as a pass.

The original run's
[macOS portable/native job 117622978001](https://github.com/TJZine/LineupDesktop/actions/runs/39109697512/job/117622978001)
passed at source `57f62c9422556fd1f4b1ba8d870adc228061a841`, including
**54/54 authenticated-reference cases**. This is exact-source hosted Mac
evidence in addition to the earlier frozen-source local matrix; it does not
change the original run's failed Windows-fixture result.

**Protected Plex performance verdict: inconclusive.** The frozen manifest
SHA-256 is `91d14f236cd2507e4093e5e1a923b224dda9d5b28baa9ae9dbcb3c4399ed42e5`,
build ID `185368181381652`, frozen production baseline `d116ad7a`. All 566
source, six script, ten fixture and 110 app regular-file hashes matched;
bundle file set/symlinks, probe patch and equivalence hashes also matched.
Supplemental `/tmp/lineup-l2-fresh/benchmark-next/final-controller-equivalence.json`
records that current tracked changes since the freeze affect only CI,
Windows fixture/control and progress documentation. Mac playback/build/runtime
inputs retain the frozen baseline plus the documented disposable probe.
The accepted foreground smoke remains its original evidence, not a new run.

After the actual Windows gate passed, the controller released only the exact
protected campaign and ran the prepared `run.py --phase counted-plex` once
as `protected-plex-final-01` (run ID `196382485489006`, start delay 45 seconds).
The read-only protected loader reached all 24 planned rows: four warmups and
20 counted trials, ten per arm, five per arm/cell. Seven rows passed and 17
failed; process exit was 1 and `accepted=false`. The frozen analyzer produced
no timing summary. No partial successful subset is used to claim gain or no
gain.

Fourteen rows failed `output_health_failed`: all 12 cell-zero rows carried
widescreen dimensions below the frozen height predicate, and cell-one trials
6/16 had unavailable initial audio PTS (`audioPtsStatus=-10`). Trial 20 failed
`late_rejection` with `foreground_interrupted`; trials 21–24 started without
foreground, and trials 22/24 failed `foreground_changed`. Controller app
activation did not maintain foreground across the full campaign. These are
recorded campaign failures, not proof of a production L2 or HDR defect. Host
load was also high (before 98.19/56.64/30.04; after 59.39/54.35/31.71 on ten
logical CPUs). The protected state and client-identity files remained
byte-identical; the app exited and no Lineup process remained. No loader or
Keychain error stopped this run.

Exact retained numeric evidence is in
`/tmp/lineup-l2-fresh/benchmark-next/runs/protected-plex-final-01/`:
`results.json`, `execution.json`, `analysis.json`, `authorization.json`,
`before.json`, `after.json`, and sanitized `controller-verdict.json` with
SHA-256 identities. Raw private logs remain local and are not copied here.
No harness predicate was changed, no synthetic campaign or retry was run,
and no latency gain is claimed. L2 production implementation/review and
correctness evidence remain valid as attributed; performance benefit is
unestablished. H1/HDR and L1 remain accepted. Overall macOS distribution,
legal, older-OS and physical Windows gates remain separate and incomplete.


**Final CI and Git closure.** PR #47 run `39111084372` is terminal
**success**: six jobs passed and its engine/package job was intentionally
skipped by fixture-only filters. Its
[Mac job 117627181574](https://github.com/TJZine/LineupDesktop/actions/runs/39111084372/job/117627181574)
directly reports **54/54** passing authentication rows (26 omitted-start,
28 nonzero-start), at actual merge source `741a2dbe`. That source's entire
tree `2f5bab3da5bf1f68e1a32c6d9f380a50b20219ad` equals `359afb38`.
Both hosted Mac runs used libmpv SHA-256
`6c92b7f0844d8e76cbc888417c974e9987d9051a7b2dd38a0ea2a158276db604`,
with lock SHA-256
`7df202602cc5a0276a7ac8762b0b4289e33e2db4a01d8adc352ca438ab9e842c`.
These remain headless real-adapter synthetic-HTTPS results. The original
NativePlayerTests reported 23 tests, one skipped and zero failures.

Original run `39109697512` is terminal **failure**, solely its preserved
original Windows fixture failure. Its
[engine/package job 117623036312](https://github.com/TJZine/LineupDesktop/actions/runs/39109697512/job/117623036312)
**passed** at exact `57f62c9422556fd1f4b1ba8d870adc228061a841`.
Actual workflow/release invocations kept the same depot_tools wrapper SHA-256
`AC37DB7974B903BB1AB1E70DA276996CCA6EAADDFD914629607E8D430F4DF846`
and Flutter Ninja child SHA-256
`9FAE00EB7F25B587573023761CFB7F7E00488D29BFCE7E347A186B4E5DF56A79`,
version 1.11.1. `build.ninja` remained unchanged; `.ninja_log` retained v5 and
SHA-256 `90ADDA6A146E921CE399FA3323E843DC3399934349B52701449CC465ED2464E2`
after the first build and through the release invocation. The second Ninja
invocation at 09:34:52 UTC reported `no work to do`, with no log-reset warning.
Application, provenance and packaging guards completed. This establishes the
separate cross-step CI-toolchain correction on actual Windows; no package
infrastructure blocker remains.

The exact `57f62c94` release marker completed at 09:36:33 UTC and the portable
ZIP was created at 09:36:42 UTC. Uploaded GitHub artifact
`LineupDesktop-windows-x64`, ID `12131893342`, is 61,822,047 bytes with artifact
digest `sha256:79ecdb41b1413d0bbcaaec81efa9b5d0287db5166df8fa608758907daae978eb`.
This identifies the uploaded GitHub artifact; the inner ZIP was not independently
downloaded or physically accepted. Exact terminal/source/toolchain evidence is
in `/tmp/lineup-l2-ci-39109697512/final-terminal-report.md` and both run
folders' `final-recheck.json`, `macos-auth-report.json` and Windows reports.
`final-evidence-manifest.json` hashes matched on controller inspection.

Only after both live runs were terminal, the controller normally pushed
`platform/macos` from `57f62c94` to `359afb38`. GitHub automatically marked
[PR #47](https://github.com/TJZine/LineupDesktop/pull/47) **merged** at
09:39:30 UTC (05:39:30 EDT), merge identity `359afb385268bad653ec26ca37bb4646fca2a896`;
no duplicate cherry-pick or extra merge commit was needed. The progress and
controller handoff are committed together as this documentation-only closure.
`main` remains `022b05aa491fe2d7397aae45a227bf024d21c5ec`; no release,
distribution publication or merge to main occurred. Documentation verification
is `git diff --check` plus evidence identities and linked source/run checks;
no product tests were rerun for these prose-only changes.

**Final L2 verdict:** production implementation/review and the corrected
Windows authenticated-reference gate are complete; both hosted Mac auth gates
and the separately attributed engine/package job passed. **Measured Plex
performance is inconclusive**, with no established gain, no accepted timing
summary and no retry. The requested bounded closure is complete. Stop here;
no further harness, HDR, design or release work is authorized by this closure.

### Post-audit M-05 — Settings return after timer expiry (2026-10-18)

The Settings button and Escape handler consumed their return origin before
`_select(player)` could reject an unavailable playback surface. Both now use
one resolved destination: Guide when the Player origin has no surface. The
label follows that destination; successful navigation owns origin consumption.
All 46 desktop-navigation tests pass on pinned Flutter 3.47.7, including four
sleep-expiry cases (before/while Settings, button/Escape), Diagnostics origins
and dirty guards. Independent fresh-chat adversarial review
`01a150a7-9075-7b52-a52a-7b8e7465da30` found no material issues and independently
ran the suite. Real Release interaction and shared-Dart Windows CI are pending
the combined candidate; widget tests do not establish physical input behavior.

### Post-audit Q-01 — canonical macOS build identity (2026-10-18)

Bare Flutter macOS commands omitted the defines consumed by Diagnostics.
`tool/macos/build_app.dart` now owns macOS build/run identity using the Windows
release contract: pubspec version and numeric build followed by full Git HEAD.
The wrapper rejects metadata overrides; active development/audit commands and
the macOS CI app build use it. There is no runtime identity fallback. Dirty
local builds are documented as carrying HEAD identity, not clean provenance.
Six focused tests and targeted analysis pass on Flutter 3.47.7, including a
subprocess invocation and failure/exit propagation. Fresh-chat adversarial review
`01a150a8-1507-7950-9c5b-592e88c70b17` independently repeated these checks and
found no material issues. Real Release Diagnostics/export inspection remains
pending the combined candidate.

### Post-audit Q-02 — accumulate channel-step intent (2026-10-18)

Page Up/Down previously used the last committed channel while tunes were
pending, dropping increments. Every press now publishes the next requested
channel immediately and supersedes older intent; a 250 ms quiet interval admits
only the final target to the existing serialized tune queue. Persistent channel
selection still commits only on successful playback. Stop, scope retirement,
sleep expiry and disposal cancel deferred work. Settled playback releases the
preview so program identity remains attached to loaded media across schedule
boundaries. Coordinator tests pass (294), including 30 presses spaced 150 ms,
pending-load supersession, lifecycle/reentrant cancellation and paused program
identity; the existing Player surfing test covers immediate preview then commit.
Fresh-chat review `01a150a9-448a-7781-ae3f-6a59104e9c52` found a program-identity
regression in the first patch; the corrected patch and added regression were
re-reviewed with no material findings. Real-app 30-press replay and Windows CI
remain pending the combined candidate. This is burst coalescing, not a latency
benchmark.

### Post-audit M-02 — directory accessibility boundary (2026-10-18)

The directory search TextField merged its text-field role into the full-page
semantics ancestor, placing management actions and rows below a native
text-field leaf. Search now owns an explicit semantics container and name.
The regression checks management/filter/row actions outside text-field ancestry;
removing only the boundary makes it fail. The affected accessibility suites pass
(274 tests, including Q-02's separate timing migration). Fresh-chat review
`01a150aa-dfa2-7221-b4dd-64711c978c50` independently ran the new semantics tests
and found no material issue with the directory repair. Native macOS AX exposure
and Windows CI remain pending the combined candidate. This does not establish
a fix for the separately observed bridge validation errors (M-04).

### Post-audit M-03 — icon control accessible names (2026-10-18)

Tooltip-only icons populated Flutter's tooltip semantics, while macOS derives
AX labels from the separate name field. Explicit icon semantic labels now match
existing tooltips/spec names for Now Playing, Guide toolbar, DVR transport,
Mini Guide arrows, directory row menus and Studio rundown actions. Existing
focus, callbacks, disabled states and Player layout are unchanged. Four focused
semantics tests and all 274 affected widget tests pass. Fresh-chat review
`01a150aa-dfa2-7221-b4dd-64711c978c50` found one adaptive-icon visual regression;
the icon was restored to `Icons.adaptive.more`, tested and re-reviewed with the
finding closed. Native AX/spoken output and Windows CI remain separate gates.

### Post-audit M-01 — observed readiness pause state (2026-10-18)

Diagnosed before changing production behavior on a real instrumented Release
build from the audit source. A fresh process, Guide, native fullscreen, then
first manual tune reproduced the mismatch. Sanitized sequence in local
`/tmp/lineup-audit/fix-diagnosis-relaunch.log`: initial native pause property
had no load identity and value false; Dart began load 1 with cached pause true;
FILE_LOADED queried actual pause false; raw playing reached Dart with cached
pause still true. No intervening pause notification was emitted. The first
incorrect reported state was Dart's readiness projection using requested
`startPaused`, not a native paused-state event. Windowed/manual tunes with
cached pause false reported correctly in the same experiment.

The start-of-load display hold and its early resume are involved: pause and
resume can coalesce before mpv emits another changed-property notification.
The cache and pause/display policy predate L1/L2. L1 keyframe seeks and L2
per-file start joins do not supply playback-state confirmation; the bug does
not justify changing their accepted join precision or adding a paused landing
barrier. The fix samples the actual pause flag at native file readiness and
carries it atomically with the readiness event. Dart consumes the typed
current-load snapshot before status projection. Raw readiness still completes
when truly paused. Toggle uses that corrected observed status; no extra toggle
heuristic, seek, display-hold or pause policy was added.

All 53 transport tests and all three portable core CTests pass. Regressions
cover a held initial join resumed without a pause notification, genuinely
paused readiness and stale-load rejection. Fresh-chat adversarial review
`01a150ad-4978-7353-8ab4-18686ac7bc61` independently repeated these checks,
verified mpv coalescing behavior/platform bool conversion and found no material
issues. Temporary state tracing was removed. Candidate Release reproduction,
actual pause/resume and shared-core Windows CI remain pending combined checks.

### Post-audit Q-03 — current error-slate identity (2026-10-18)

Failed tunes retain the committed channel, but the slate previously read that
old selection while Retry used the new request. Error presentation now derives
channel/program/Up next from the same requested channel as Retry. Surfing from
a settled error also starts from that visible target. Healthy playback keeps
its loaded-program identity. Coordinator tests pass (297), covering late old
native errors/load failures, newer failure identity, Retry and both step
directions after a failed direct tune; all 120 PlayerView tests pass. Fresh-chat
review `01a150ae-7c43-7840-b703-0f404ed44396` caught the error-surf origin
inconsistency; its correction and regressions were re-reviewed with no remaining
material findings. The earlier full Dart suite passed 1,785 tests; this final
step-origin correction was then checked by the complete coordinator suite.
Shared-Dart Windows CI and bounded real-app integration remain pending.

### Post-audit M-04 — unresolved AX update failures (2026-10-18)

The [durable investigation](handoffs/macos-ax-update-investigation.md) records
1,508 original native AXTree validation errors, exact toolchain/error sites,
and the complete attempted media-free reduction. That attempt schedules 200
transitions and its preserved log has zero AXTree failures; it is explicitly
not a successful reproducer. The initiating invalid update and Dart-versus-engine
cause remain unproved. No engine patch or speculative bridge-reset workaround
was applied. The proposed next step is a sanitized capture of the first rejected
semantics delta and reduction to a standalone upstream report; any runtime
upgrade/subtree recreation needs isolated validation first. The same fresh-chat
accessibility reviewer independently checked the durable evidence and privacy
claims with no material discrepancies. Candidate real-app results will be
recorded in the closing report; M-02/M-03 tests do not close M-04.

### Post-audit combined gates and runtime blocker — 2026-10-18

Reviewed product source `1b2f64f4eaf584807f70e668a5502ab088a54537` built cleanly
as the real Release app through the canonical identity wrapper. Bundle manifest
SHA-256: `d5417b6ae680ab203001791897321b053b6dd91c14818d71d160482eb900efce`.
Final local canonical formatting, analyzer, 1,787 Dart tests and three portable
core CTests passed. [Windows verification run 39163235848](https://github.com/TJZine/LineupDesktop/actions/runs/39163235848)
passed both jobs, including the affected Dart suites, stock-engine Windows app
build and all canonical native contract/authenticated-reference checks. Its
`685eec76645510e59bdbc9f3dc542be73e62ebb3` snapshot differs from the product only
in the narrowed CI workflow, independently checked before dispatch. It excludes
release/packaging/signing jobs. No in-progress run was cancelled.

Candidate real-app acceptance is blocked at the user-only Keychain handoff;
a process sample confirms `SecItemCopyMatching` / `SecKeychainItemCopyContent`
while startup waits. The handoff was requested; no credential bypass was used.
The required corrected first-fullscreen-tune/actual pause checks, real 30-press
sequence, Diagnostics/export identity and native AX confirmation remain open.
The [closing report](handoffs/macos-post-audit-fix-report.md) records each item,
review, evidence limits and a single consolidated human-only checklist. M-04
remains unresolved with its exact evidence and attempted reduction. No Player
layout, HDR/Dolby Vision picture-quality acceptance, main merge, distribution
release, signing policy or engine code was changed.

### Post-audit Release checks resumed after Keychain — 2026-10-18

The user completed the pending authentication handoff. The unchanged real
Release candidate `1b2f64f4` then passed its bounded checks: first-fullscreen
tune reported Playing, native K held the paused position for 10.34 seconds and
resumed advancing playback; the subsequent manual step tune retained correct
state. Thirty native Page Down presses over 3.97 seconds moved channel 1 to 31,
with native load IDs advancing only from 1 to 2. The regression separately
checks every immediate displayed increment. Diagnostics technical details and
its copied export showed the expected version and full built-source identity;
the inspected export had no observed URL/token/private-path leak.

Native AX snapshots now expose directory management/filter/row controls and
named row menus, Player transport/window actions and Guide Earlier/Later.
Studio rundown labels retain semantics-test evidence; spoken/native full-surface
acceptance remains a human check. M-04 reproduced despite these repairs: 614
bridge failures (373 pending-node, 241 removed-node), first after the initial
fullscreen tune/overlay sequence. Some route snapshots recover, so native names
appearing does not establish general AX health. The investigation now records
this short production reproduction and retains the negative media-free attempt.
No engine patch/reset workaround was applied. DVR was restored Off; native Quit
completed libmpv shutdown. The closing report replaces its former Keychain
blocker with these results and retains one consolidated human-only checklist.

The fresh-chat accessibility reviewer independently reconciled the final runtime
records, screenshots, native snapshots and report wording. It corrected the
burst duration to the key-action record (3.972 seconds; capture timing is
separate), then found no remaining material evidence or privacy discrepancies.
Product/build inputs and bundle hashes remain identical to the CI-verified
candidate; only evidence documents changed after its build.

### M-04 standalone reduction and owner diagnosis — 2026-10-18

A three-button stock Flutter app now reproduces M-04's removed-node rejection:
Show tooltip → Exclude origin → Change tooltip message. Native AX is active and
healthy before the sequence. The tooltip remains physically mounted after its
traversal subtree is discarded, then emits an update for the unreachable text
node. Flutter's common desktop accessibility bridge forwards that record to
`ui::AXTree`, which rejects it rather than applying the unreachable-node discard
rule. This is Flutter framework/bridge interoperability, not missing Lineup Dart
labels or a custom semantics configuration. It is not established as macOS-only.

The [source, instructions and sanitized delta fixture](../tool/macos/ax-tooltip-repro/README.md)
and [investigation](handoffs/macos-ax-update-investigation.md) record the exact
accepted-then-rejected sequence. Targeted analysis, formatting and Release build
passed. A freshly generated stock runner reproduced the error with only the
three-button source copied in: no tracing, native observer, media, plugins,
custom animation, custom semantics node or forced activation. The reachable-tooltip
message-change control passed. Plain exclusion without a later message change
and exclusion without a shown tooltip also passed in the traced prototype.

The animated retiring-tooltip reduction produced both logged error forms.
Investigation also found that AXTree retains its error string and the bridge
checks that string instead of the update's return value; earlier 1,508/614 totals
are log-message counts, not independent-rejection counts. A separate forced
semantics activation positive was identified as a confound and excluded.

Two instrumented real Release runs and an unchanged Release control did not
reproduce the historical short sequence during this follow-up. Thus the stock
reproducer establishes the failure mechanism and runtime owner, while the exact
first historical production delta and real-app acceptance remain open. No
application workaround or engine patch was integrated. The investigation proposes
an upstream report and a bounded, untested TooltipVisibility workaround experiment.
No upstream issue was published. Product source remains unchanged; no shared
Dart/core change or new Windows CI claim is involved. DVR and VoiceOver were
restored Off, and the real app quit normally.

Fresh independent adversarial review validated the fixture, stock-runner identity,
runtime rejection, source ownership and privacy; no material issue remained.
Its minor wording correction distinguishes the absence of custom animation from
Tooltip's built-in fade. Exact historical production causality remains unclaimed.

### M-04 tooltip transition mitigation — 2026-10-18

The user authorized the TooltipVisibility experiment and application mitigation.
The same stock Release source rejects its first tooltip message change with the
default build; `REPRO_TOOLTIP_VISIBILITY=true` passed ten message changes after
exclusion with native AX active and zero AX errors. Both shell app-menu exclusion
branches now remove their underlying tooltip overlays immediately. Retiring Player
overlays do the same, while current overlays inherit visibility. Shell scopes
preserve any outer false restriction. Existing layout, explicit accessible names,
and active-surface hover tooltips are preserved.

Five new behavioral regression cases cover ready/account-picker routes, immediate
tooltip removal, restoration/reopening and inherited false. Both affected files
passed (122 Player tests and 7 shell tests). Fresh independent adversarial review
found no blocking issue in this bounded mitigation. Required full checks, real
Release verification and Windows CI are recorded after execution below.

The restored original application source failed the new immediate-removal tests
for ready/account routes and the visible retiring OSD, establishing that the
regressions distinguish the prior behavior. Restoring the candidate passed the
full 1,792-test macOS suite. Canonical formatting and full Flutter analysis passed.

A separate native probe confirmed that showing a tooltip whose origin was excluded
from the outset can also fail. Permanently excluded cast/track details retain their
existing visual hover features and remain outside the transition mitigation.
M-04 remains open for that broader runtime path, exact historical production
linkage and human assistive-technology acceptance. The final GPT Pro review prompt
will challenge this boundary and request stronger alternatives that preserve UI
features. No engine patch, merge, distribution release or signing work is included.

The real Release candidate `296ab90588b6d1312e7a1b992142077fed1146c3` used canonical
identity `0.1.0`, `1@296ab90588b6d1312e7a1b992142077fed1146c3`. Native pointer/AX
checks passed visible Guide tooltip → menu exclusion/restoration, visible Player
OSD tooltip → audio-options retirement/restoration, and Player menu exclusion with
five seconds of continuing background updates. No AX errors occurred through those
guarded scenarios. A later Now Playing cast-name hover reproduced the unguarded
static-tooltip error (first at line 24, node 268; 55 logged messages by shutdown).
Thus transition checks passed, but general M-04 acceptance remains open with a
confirmed real-app residual. Raw evidence and identity hashes remain private in
`/tmp/lineup-audit/m04-lineup-workaround/`; the app quit normally.

Windows verification [run 39170620921](https://github.com/TJZine/LineupDesktop/actions/runs/39170620921)
passed both Dart verification and the Windows job (affected UI suites, stock-engine
app compile/link and eight selected native/authenticated-reference CTests).
Verification commit `159fd599aee9ab8c7074ca292e517116342d89b9` has product candidate
`296ab90588b6d1312e7a1b992142077fed1146c3` as its parent and differs only in the
narrowed CI workflow. The isolated `dev/macos-tooltip-verification` workflow omits
macOS runtime provisioning and all release/package jobs. Live runs were checked
before dispatch; none was in progress and none was cancelled. Windows CI establishes
portable/build/contracts evidence, not physical Windows media or assistive output.

The [fresh GPT Pro review prompt](handoffs/macos-post-audit-adversarial-review-prompt.md)
covers the entire post-audit range through the immutable mitigation candidate and
explicitly requests stronger solutions for the confirmed static-tooltip residual.
No broader M-04 acceptance is claimed. The original consolidated human checklist
remains in the closing report.

The final evidence/prompt review independently checked immutable identities,
CI-only workflow differences, successful jobs/CTests, test logs, runtime/build
summaries, privacy and relative links; no material findings remained. Product
inputs remain at `296ab905`; the closing documentation does not relabel earlier
binary evidence or claim that the static cast failure is fixed.
# 2026-10-18 — Pro review follow-up: Studio clear-search name

The conditional manual-rundown clear-search action still supplied only tooltip
semantics. Its icon now supplies the matching explicit action name while retaining
the tooltip and existing layout. The extended Studio regression enters a query,
checks label/button/tap semantics, activates Clear and verifies the query empties.
The focused test passed. A fresh adversarial read-only review
(`studio_label_review_v2`) approved the two-file change with no material findings.
Combined Release/native AX and Windows CI verification are pending below; this
entry does not claim spoken output or physical Windows acceptance.
