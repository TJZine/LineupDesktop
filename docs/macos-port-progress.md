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
- M1/M2 candidate: `macos/m1-m2-adapter` at
  `0857c9060a67c5f4aee538ecb2849be4cb041bd5`, clean checkout
  `.claude/worktrees/agent-ac696b17224d2358a`; merge base `bde729a1`.
  Not integrated yet. Previous review was conditional on the core fixes;
  takeover review targets those accepted changes and their proof.

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
- Pending visible checks on the accepted runtime: HDR loaded while hidden
  and then shown (M12-R2), fullscreen sources, Guide transparency, live
  resize, HDR/SDR switching. Native fullscreen/Dart state synchronization
  and graceful termination remain M3 work. User HDR/color judgment and the
  full signed A1 acceptance matrix remain distinct from screenshots/logs.
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
loading HDR while hidden, so R2 is still open. Guide aperture visibility was
observed; exact Guide alpha comparison was not performed. Command-Q completed
the worker shutdown and exited the instrumented process; bounded asynchronous
termination remains M3 work. No fixture media identities or raw diagnostics
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
The expanded native test wiring and correction are under independent review
before integration.

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
| M12-R5 correction | `01a14bc0-ab3f-7c73-bb93-75341fdc3420` (`local`) | `worker`: `gpt-6.1-sol`, medium | M1/M2 checkout above; adapter guard, protocol text, focused production-path regression proof and minimal test wiring; no Git integration | Implementation complete, awaiting review; 10 native tests pass and old-guard negative control fails |
| K2 macOS core-contract CI | `01a14bc1-7787-75f2-841a-48b715f3b209` (`local`) | `worker_luna`: `gpt-5.6-luna`, xhigh | Primary checkout; only `.github/workflows/ci.yml`, one new job | Complete and independently approved; controller integrates |
| K2 adversarial review | `01a14bbe-5fce-7320-b217-e131e586574a` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Frozen workflow diff against `61d475c4`; unrelated controller docs excluded | Complete: approved; hosted execution still outstanding |
| M12-R5 targeted re-review | `01a14bbe-5fce-7320-b217-e131e586574a` (`local`) | `reviewer`: `gpt-6.1-sol`, high | Frozen six-file candidate working diff at `0857c906`, including new scheme/config | Running; completion/blocker callback to parent |

Next engineering slices are M3 (termination and fullscreen contract), the
remaining U1 wiring, R1 (provisioning, embed/sign correctness, notices), and
K2/C1 (native/portable CI and runtime provisioning). Resolve dependencies
against current source rather than interpreting this list as a serial pipeline.
Do not change approved Player layout. A new Licenses surface needs design
agreement if an existing suitable surface cannot carry it. Signing/account
inputs, legal review, product decisions, and physical hardware limits must
remain explicit instead of being silently treated as complete.
