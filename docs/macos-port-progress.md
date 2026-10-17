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
| M3b fullscreen observation/reconciliation | `01a14bc0-ab3f-7c73-bb93-75341fdc3420` (`local`) | `worker`: `gpt-6.1-sol`, medium | Native adapter player-scoped events, Dart playback interface/transport/coordinator, affected fakes/tests and protocol docs; no app/menu files | Running after P6 approval; independent review and Windows CI required |
| U1 native command delivery | `01a14bfd-7a31-7e50-9de6-e6318b5c1aac` (`local`) | `worker`: `gpt-6.1-sol`, medium | App/Guide keyboard routing, Mac app/window/menu files and focused test/app coverage only; excludes M3b playback/native-player files | Investigation running; distinguish real defect from automation/focus limits before correcting |

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
