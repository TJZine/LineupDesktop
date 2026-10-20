# M-04 accessibility recovery implementation handoff

Prepared 2026-10-20 for a new orchestrator chat. This is an implementation
assignment proposal, not a record of executed changes or completed acceptance.
The human should send the launch message below to adopt it. This preparation
chat has not dispatched workers, changed product/engine code, or run new native
acceptance.

## Launch message for the new chat

> Execute `docs/handoffs/macos-m04-recovery-implementation-handoff.md` in
> `/Users/tristan/Software/LineupDesktop` using
> `$orchestrate-implementation-chats`. I authorize separate implementation,
> investigation and review chats within this scope, selection among the current
> repository worker, worker_luna and reviewer presets, and their completion or
> meaningful-blocker messages back to this orchestrator. Read the actual presets
> and use supported model/effort settings. I authorize local implementation and
> verification of the desktop accessibility engine repair, necessary reproducible
> build integration, and fixes for demonstrated related application defects.
> Preserve the approved Player UI and Slider group/order. Complete all feasible
> engineering work and coordinate the existing human acceptance checklist with
> me; do not infer human passes. Keep one integration/resource owner and follow
> this handoff's publication and runtime limits.

This launch message, when actually sent by the human, is the authorization
source. The document alone is not proof of permission for cross-chat callbacks.
The new controller must resolve its own actual thread ID/host and retain a
retrievable reference to that human turn. Do not reuse historical controller IDs.

## Outcome and boundaries

Repair the demonstrated common-desktop accessibility bridge failure and recovery
mechanisms, establish reproducible candidate builds, investigate remaining
discriminating scenarios, and complete the human checks when the human is
available. Account for every open issue below without manufacturing fixes for
unproved application defects.

The last review found **no new concrete application defect** in product
`829547b4`. The existing containment, Slider interactivity and Player focus fixes
are accepted within their evidence limits. Keep them while repairing the engine;
removing a mitigation is a separate change requiring a demonstrated benefit and
equivalent behavioral/native evidence.

The adopted assignment expands the previous read-only packet to local engine
repair and necessary build integration. It does not authorize a Player redesign,
platform migration, unrelated workflow maintenance, main merge, signing or
distribution, upstream issue/PR publication, or person-directed external messages.
No further synthetic VoiceOver commands or global modifier manipulation.
HDR/Dolby Vision picture quality is already accepted and excluded from repetition.
If the new engine changes composition/media behavior, investigate that regression
and identify the exact affected acceptance requirement rather than silently
invalidating or rerunning the entire prior campaign.

Local development builds and tests are in scope. Remote CI dispatch, a verification
branch push, or other publication must use actual human authorization available
in the new chat; this document does not imply it. Prepare the concrete candidate
and verification configuration before requesting any missing external-action
authorization. Do not let an unavailable platform or human check prevent useful
independent local work.

## Starting source and required context

At preparation, the checkout is clean on `platform/macos` at
`e30b02b2f4f5e3c402521a32416b330204af58c7`, eight commits ahead of its tracking
branch. This HEAD changes documentation only over product
`829547b48859ab9654190c2b9d785b1e1446fdc9`. Re-resolve branch, HEAD, staged,
unstaged and untracked work before editing; preserve subsequent user changes.
Do not reset to a historical branch or assume origin has stayed unchanged.

Read applicable `AGENTS.md`, `.agents/project.md`, and:

- `docs/handoffs/macos-post-audit-continuation.md`
- `docs/handoffs/macos-post-audit-fix-report.md`
- `docs/handoffs/macos-ax-update-investigation.md`
- `docs/handoffs/macos-m04-opus-review-handoff.md`
- `docs/architecture.md`, for boundary/ownership changes
- `docs/DEVELOPMENT.md` and `tool/flutter_engine/README.md`
- `tool/macos/ax-tooltip-repro/README.md`

Use shared `develop-code` for implementation, `design-code` for the engine
recovery decision, `verify-code` for discriminating evidence, and `review-code`
for independent review/adjudication. Load deeper guidance only when needed.
Do not activate workflow maintenance.

Pinned framework is Flutter 3.47.7,
`abaf9c523780a608bd46686fd5e53740a07077f8`; engine is
`deb287481e3ce9468f3434937ced4240a70539ca`, Dart 3.13.5. Confirm repository pins.
The inspected pinned SDK is
`/Users/tristan/.cache/lineup-flutter/3.47.7/flutter`.
At preparation, bare `flutter` on PATH resolves to **3.47.6**; select the verified
pinned executable explicitly or use a command-local PATH. Do not change global
shell configuration or overwrite the stock SDK cache.

Current source SHA-256:

| File | SHA-256 |
| --- | --- |
| `lib/playback/player_view.dart` | `22c8dc49da08d25b85375c4e7eeececc06d58cdf7741a2542cf63952595e769f` |
| `test/app/player_overlay_focus_test.dart` | `b0d20d7036e6039486c71d6efe3d18ef39502a1c46a0b6192802c0a48aac5f59` |
| `test/playback/player_slider_semantics_update_test.dart` | `0112b233bc4d5a3da18e73a86dd770165694d4159d4d43526e2bbf4914fb2aae` |

Keep raw logs, media labels, URLs, screenshots, AX captures and diagnostics under
`/tmp/lineup-audit/`, in a new clearly named campaign directory. Sanitize anything
placed in the repository or cross-chat messages.

## Accepted behavior and evidence to carry forward

The approved unlabeled enabled Slider group follows the OSD controls. Gate A is
resolved. Preserve appearance, tooltips, interaction and order. `Overlay.wrap`
contains only SliderTheme/Slider within the existing 40-pixel progress Stack;
the visible four-pixel indicator and progress Semantics remain. The overlay key
matches `onChanged` interactivity, remounting on flips while value/max/menu changes
retain State.

Player proactively transfers owned OSD/NowPlaying focus before retirement and
coalesces post-frame recovery from empty/ancestor-scope focus, including resume.
Preserve active/current-route/requestable-root guards, full Guide exclusion,
menu/modal ownership, surviving controls and unrelated scopes. No global focus
reset is justified by the review.

Retained evidence, audited during preparation but not newly executed:

- Identical final focus test source: baseline `17c81c72` passes 3/fails 7;
  fixed product passes 10/10. The Mini Guide baseline stops at its first Escape
  failure; only the passing candidate executes both Escape and F2 iterations.
- Affected suites pass 198, including 22 unchanged Slider semantics tests;
  local full suite passes 1,862, formatting 160 files/0 changes, analysis clean.
- CI run `39383128215`: Linux 1,860, Windows 749, stock Windows build and eight
  individually passing native/reference CTests. Commit
  `ed42ccd780aec2fbc4ebfbcfe731869d060a7be8` is the product's direct child with
  only `.github/workflows/ci.yml` changed.
- Native recorded baseline/fix comparison preserves the second digit (8 → 89)
  and subsequent F2 on the fix. Separate candidate resets verify Mini Guide
  Escape/F2 and genuine inactive timed-hide → resume/Enter. These are automated
  native observations, not physical input or a direct fixed FocusManager trace.
- Earlier healthy native value callbacks retain their original source identity;
  they establish neither current-candidate delivery nor post-rejection recovery.

Raw prior evidence is at `/tmp/lineup-audit/m04-focus-followup/{controller,worker}/`.
The final baseline archive and retained test match their declared sources;
all 28 hashed files in `native-fixed-observations.json` matched at preparation.
Use existing manifests for exact old binary identities. A new engine invalidates
affected native conclusions for the new candidate; never relabel an old run.

## Work units and dependency boundaries

### A. Choose and implement a coherent desktop bridge repair

Use `design-code` before committing to an algorithm, then continue implementation
through `develop-code`. This is cross-boundary diagnosis/implementation suitable
for the current `worker` preset, with the orchestrator owning the decision.

Inspect pinned source:

- `engine/src/flutter/shell/platform/common/accessibility_bridge.cc`:
  `CommitUpdates`, `CreateRemoveReparentedNodesUpdate`, `GetSubTreeList`,
  node conversion and event dispatch.
- `engine/src/flutter/third_party/accessibility/ax/ax_tree.cc`:
  `Unserialize`, `ComputePendingChangesToNode`, recursive destruction and
  `ValidatePendingChangesComplete`.
- Semantics retention/traversal contracts in `engine/src/flutter/lib/ui/semantics.dart`
  and the framework's semantics/OverlayPortal implementation.
- Native delegate, event-generator and macOS/Windows bridge lifecycle consumers.

Recommended direction: reconcile Flutter's retained semantics model with AXTree
in the common bridge, so valid reachable data and full moved subtrees survive,
unreachable records obey Flutter's discard contract, and a failed native commit
cannot silently poison all later tree/event updates. Prefer a coherent bridge
state/commit boundary over more application widget workarounds.

Compare a validated candidate snapshot/commit approach with an incremental
normalization approach that has complete resynchronization on failure. Select
using actual pinned APIs and delegate/event lifetime constraints. This handoff
does **not** establish that tree replacement is safe or prescribe a new generic
transaction framework. Explain normal-path cost, retained state, ownership,
recovery behavior and discarded alternatives briefly in the existing investigation.

Required contracts:

- Use actual `Unserialize` success/failure, not retained error text, for control
  flow. Correct stale diagnostics without disguising failed commits.
- Preserve valid updates supplied alongside a formerly unreachable record when
  Flutter's contract permits that batch. Keep a complete authoritative basis for
  reconstruction; unmodified descendants are not necessarily resent.
- Account for the removal prepass separately. It may already destroy a subtree
  before the main update fails; a failed prepass may also be nonmutating.
- Distinguish invalid input from valid Flutter topology needing adaptation.
  Malformed graphs must fail deterministically without publishing a partial
  tree as healthy. Document what state is retained and how a later valid update
  recovers; do not loop forever retrying an unrecoverable batch.
- Deliver appropriate events for the committed native state. Failed/stale events
  must not reference destroyed delegates or leak into a later commit. Coordinate
  event clearing, pending updates, custom actions, focus and delegate caches.
- Demonstrate recovery within a surviving bridge instance after a controlled
  rejection. A fresh process/tree baseline alone is not recovery.
- Preserve AX identity/focus where required; assess native reference lifetimes
  before adopting any reconstruction strategy. No speculative tree reset.

Do not stop after replacing two error checks. That addresses one symptom without
proving lost-data recovery, prepass consistency or notification recovery.

### B. Add discriminating engine regressions

Prefer the existing engine bridge/tree test targets and synthetic fixtures over
expanding the Dart replay into a second native implementation. Run identical
final tests against the pinned baseline and candidate where feasible.

Cover distinct obligations:

1. Healthy update and notification control.
2. Unknown unreachable leaf plus a valid reachable change in the same batch.
3. Move of a retained subtree with descendants omitted from the delta.
4. Rejection before structural mutation, and failure after a successful removal
   prepass or after node updates; assert actual resulting state, not just errors.
5. Subsequent valid updates in the same bridge: complete reachable data, usable
   actions/focus, event delivery and clearing without stale events.
6. Destruction/recreation cleanup and pending custom-action consistency where
   touched by the implementation.

Some malformed/failure cases may need a narrowly scoped engine test seam; prefer
existing targets and real failure paths. Keep diagnostic injection out of the
canonical application. Include real native notification observation later;
engine fixtures do not establish assistive-technology acceptance.

Keep `test/support/semantics_update_recorder.dart` explicitly bounded. It forwards
the pinned API but samples only two ordering choices and stops after rejection.
It does not model native roles, caches, events or partial-mutation recovery.
Update it only when a demonstrated changed obligation requires it.

A and B share engine contracts and often files. One writer should own both
unless the controller defines stable, disjoint ownership.

### C. Integrate reproducible engine selection

After A's design is settled, implement a reviewable patch series and the necessary
build/provenance integration. Use `tool/flutter_engine/` and existing platform
build owners; inspect their current contracts before choosing precise filenames.

The existing engine patch infrastructure is Windows DirectComposition-specific.
It does not already provide a macOS accessibility engine pipeline. Preserve the
Windows patch, marker checks and exact-source integrity. Add explicit macOS
local-engine selection and identity verification where required; do not pretend
stock `build_app.dart` execution includes the repair.

Keep stock and patched engine artifacts distinct. Record framework/engine source,
patch hashes, build configuration, architecture, actual loaded engine hash and
application identity. Existing integrity checks must reject missing/stale or
wrong-platform candidates. Do not silently edit a shared SDK checkout, copy over
its binary cache, weaken clean-source checks, or reuse a stock-engine identity
for a modified engine.

Check common-bridge compatibility on both macOS and Windows. Build and run the
applicable engine targets; ordinary stock Windows application CI cannot prove
this engine repair. If a build host is unavailable, finish the patch/integration
and runnable verification instructions, identify the exact unexecuted target,
and keep that acceptance gate open. Do not classify an unbuilt patch as integrated.

### D. Resolve remaining runtime uncertainties

The orchestrator exclusively owns live apps, AX observers, builds and shared
generated output. Use existing repros and passive diagnostics; no new VoiceOver
synthesis. Before changing temporary app settings, record their current values
and restore them. Preserve preexisting apps/windows and user VoiceOver state.

- **First-fade timing:** open the menu during the initial 350-ms OSD fade with
  measured timing and recorded preconditions. The prior 989-ms attempt is not
  this case. Pair native continuity observations with bounded frame tests; state
  whether actual native timing was achieved.
- **Production interactivity flip:** observe an actual enabled/disabled transition
  where feasible and verify later useful Slider interaction. Stock keyed/unkeyed
  controls already discriminate the mechanism. Do not fabricate a production
  flip or add a permanent product control solely to force one.
- **Post-rejection recovery:** use the engine regressions and a controlled native
  reproducer to observe a later reachable value/action update and actual native
  notification after failure in the same bridge. A populated AX snapshot alone
  is insufficient.
- **Historical node 866:** replay the recorded Settings → DVR On → Guide → tune
  route with healthy-start instrumentation if it reproduces. Capture the first
  delta, portal/origin inventory and native failure. A fresh failure has its own
  identity; no successful run or matching error string retroactively attributes
  866. If original evidence is insufficient, record historical attribution as
  unresolved, with bounded attempts and the exact missing evidence.
- **Player focus:** retain the real-shell regression paths and verify the new
  engine candidate's affected menu/zoom/collapse, digit, Mini Guide and inactive
  resume behavior. Add an application fix only for a demonstrated defect, with
  a distinguishing before/after test and preserved ownership guards.

### E. Complete human acceptance and close out honestly

Use only the existing checklist in
`docs/handoffs/macos-post-audit-fix-report.md`. It includes physical media/input,
Guide search/Clear, left/right modifiers and focus restoration, spoken VoiceOver
names/states/order, sustained audio/rollover, and window/Spaces/sleep-wake checks.
Coordinate short sessions against the exact candidate with the human.
Do not create a duplicate checklist or mark boxes from automation.

Spoken usefulness of the approved unlabeled Slider group is an acceptance
question. If the human finds it unusable, record the concrete result and obtain
agreement on any material UI departure before implementing it. Do not reopen
Gate A solely because engine work is underway.

If the human or required platform is unavailable, explicitly leave the relevant
items open. Historical attribution may remain unknowable; distinguish that from
a demonstrated current failure. Do not label all issues resolved or close M-04
globally while required acceptance remains outstanding.

## Orchestration and integration

Use `orchestrate-implementation-chats` and its actual tool schemas. Resolve the
project with `list_projects`; provide accessible source/plan paths and an exact
unit in every child prompt. Read current `.codex/agents/*.toml`, inspect supported
models, and pass authorized model/effort explicitly. Do not inherit expensive
defaults accidentally or silently substitute an unavailable preset.

Keep technical ambiguity and engine recovery design with the orchestrator and
`worker`. Use `worker_luna` for a genuinely decision-complete integration or
fixture unit. Use `reviewer` for independent read-only inspection of a stable
candidate. This is not a required roster or one-chat-per-heading plan.

Parallelize read-only evidence investigation with engine work, and disjoint
integration preparation when contracts are stable. Serialize engine writers,
shared builds, mutable test inputs and native sessions. Default separate chats
to local execution; use disjoint scopes or controller-managed isolated source
copies as appropriate. A worktree-backed chat requires the human's explicit
worktree request under the creation tool's rules.

The controller owns Git integration. Children receive explicit write boundaries
and must not commit, switch branches, push, launch native apps or mutate the shared
SDK unless specifically delegated. Local commits, if made by the controller,
use conventional messages; new branches use `dev/` unless directed otherwise.

Each child packet includes the actual parent thread/host, retrievable original
human authorization, exact source and dirty-state context, owned paths,
dependencies, runnable checks, evidence limits, resource exclusions and return
contract. Children verify human callback authority before messaging. If it cannot
be verified, leave the final report in the child for parent retrieval.

Report meaningful blockers and completion, including after corrections. Use
nonblocking collection on callbacks or the parent's next activation; do not keep
an idle orchestrator alive with polling. The controller continues independent
work, then ends its turn when only child completion or human action remains.
Inspect returned diffs and evidence before acceptance; reuse the same child for
focused corrections where appropriate.

## Verification and delivery

Run focused engine/bridge and affected Dart tests on stable inputs first. Retain
distinct before/after failures and native controls. For changed application or
build inputs, run the repository's applicable canonical formatting, analysis,
full tests and build/provenance checks once before completion; broaden only for
new failures or unresolved risk. A documentation-only edit does not warrant
another full product run. Run `git diff --check` and validate affected links.

Independent review must inspect recovery/data consistency, prepass partial
mutation, event/delegate lifetime, cross-platform integration and claims against
the final exact source. Adjudicate findings and fix demonstrated issues; reviewer
agreement alone is not proof.

Update the existing continuation, investigation and closing report with concise
final-state evidence. This handoff can carry the compact dispatch/status map.
Preserve historical identities and the single human checklist; avoid duplicating
the entire campaign in every document.

Final delivery must identify:

- Actual application and engine source/patch/artifact identities and changed files.
- Selected child presets/model/effort, accepted units and any unresolved blockers.
- Before/after results and the obligations each test or native observation proves.
- macOS/Windows build and runtime evidence separately, including unexecuted gates.
- Every open issue's disposition: repaired and verified, investigated without a
  new defect, historically unattributed, or awaiting explicit human/platform proof.
- Rollback to the previous explicitly selected application/engine pair, preserving
  old artifacts and avoiding cache replacement.
- Whether M-04 and overall accessibility acceptance can actually close. Do not
  equate a passing engine suite or a successful build with complete acceptance.

## Execution record — 2026-10-20

The human adopted this assignment in orchestrator chat
`01a15836-5fa7-7e53-9f92-0afa5eb7c12c` (host `local`), turn
`01a15836-664a-7440-bb6b-42648f3a8db3`, user message
`01a15836-6866-7521-a8b0-54b33c5e43b9`. That original human turn
authorizes scoped child creation, preset selection and completion/meaningful-
blocker callbacks. Children must verify it before messaging the parent.

Initial source: `platform/macos`, HEAD
`e30b02b2f4f5e3c402521a32416b330204af58c7`, eight ahead of origin;
only this supplied handoff was untracked. Preserve the starting product and all
existing acceptance limits. The orchestrator owns Git, integration, builds,
generated output, live applications and observers. No publication is authorized.

| Unit | Chat | Preset / model / effort | Ownership and state |
| --- | --- | --- | --- |
| A/B design | `01a15837-5ae0-72c2-b396-ca5da142ba75` | worker / gpt-6.1-sol / medium | Staged retained-model/private-AXTree design selected; engine implementation authorized in source-only candidate-source clone; controller builds separate baseline |
| D evidence investigation | `01a15837-5fac-74f2-b2ee-6ddaa492d6d5` | reviewer / gpt-6.1-sol / high | Evidence investigation returned; no new concrete app defect; runtime plan available in child report; no builds or live resources |

The actual `.codex/agents/worker.toml`, `worker-luna.toml` and
`reviewer.toml` were read. `worker_luna` resolves to gpt-5.6-luna/xhigh
and is reserved for a decision-complete unit. All selected settings are supported
by the current thread tool. These are actual chat dispatches, not simulated
orchestration. The parent callback route is the orchestrator above.

Campaign evidence and isolated engine provisioning are under
`/tmp/lineup-audit/m04-engine-recovery/`. The stock SDK is read-only to this
campaign; no binary-cache replacement is permitted. Engine dependencies were
absent initially. The host initially had about 31 GiB free; provisioning/build
feasibility remains to be established. No new build, native or human acceptance
result is claimed by this dispatch record.

Baseline local checks: pinned Flutter passed 38 tests across
`test/tool/macos_build_app_test.dart`,
`test/playback/player_slider_semantics_update_test.dart` and
`test/app/player_overlay_focus_test.dart`. This establishes unchanged portable
wrapper/widget behavior only, not native recovery. Log:
`/tmp/lineup-audit/m04-engine-recovery/controller/baseline-focused-tests.log`.

The evidence investigator confirmed historical node 866 has no recorded first
outgoing delta/origin inventory/native activation history; node 378 belongs to
a different run. Native first-fade timing remains unachieved (the prior attempt
was beyond 350 ms); existing S6 observes one fake-time frame. A production tune
can expose a duration/interactivity transition but does not guarantee a mounted
Slider flip. Reuse the retained passive PID-scoped observer only after successful
registration on the current Slider, and require an actual post-rejection
`AXValueChanged` callback in the surviving bridge. Full plan and sanitized
identity pointers are in child `01a15837-5fac-74f2-b2ee-6ddaa492d6d5`.
No human check has passed; the original six-item checklist remains the sole list.

Controller selected staged retained semantics/AXTree publication after inspecting
AXTree's documented fatal-failure contract. Failed stages must never mutate live
delegates/events; surviving native identities are rebound, not reinitialized.
An optional explicit initial-root hint supports platform callers with an established
root contract; unique nonzero roots remain supported, and ambiguous unhinted
initial batches reject deterministically. No unordered/minimum-ID heuristic.
See the engine child's design report for the compared incremental/resync alternative.

Integration chat `01a1583f-7591-7c11-b44c-dd19a91941e0` uses worker /
gpt-6.1-sol / medium for cross-platform source/artifact provenance and explicit
macOS selection. It owns only repository tooling and focused tooling tests;
the controller owns engine patch export, final metadata, docs and all shared
builds. The selected algorithm settles the engine contract; source/artifact
integrity still needs implementation judgment, so this unit is not yet a bounded
worker_luna assignment. No worker_luna chat has been dispatched.

Isolated gclient provisioning completed (exit 0, 115.1 seconds); debug arm64
GN configuration succeeded. Clean baseline common_cpp_unittests compilation
is running in `flutter-source`, while engine edits use a separate source-only
`candidate-source` clone. Neither changes the stock SDK. Completion of these
builds and actual candidate integration remains pending.

Build feasibility update: clean pinned baseline GN succeeded, but Ninja failed
while linking flatc because pinned LLVM ld64.lld cannot parse SDK 27.0's
`arm64e.x1` TAPI entry. An exact-command diagnostic using Xcode's explicit
linker succeeded. The controller added a separate, opt-in
`0003-macos-apple-linker.patch` (macOS host toolchains only; defaults/iOS
unchanged), with `mac_use_apple_linker=true`, and resumed the baseline target.
The baseline is now explicitly pinned accessibility code plus this necessary
build-only patch; it must never be described as a successful stock-default build.
Actual Xcode/compiler/linker/SDK identities and ordered patch hashes must appear
in candidate provenance. Default failure, diagnostic and resumed logs are in
`/tmp/lineup-audit/m04-engine-recovery/controller/`. No target pass is claimed yet.

Current owned pending work: A/B engine source-ready callback from
`01a15837-5ae0-72c2-b396-ca5da142ba75`; C source/provenance callback from
`01a1583f-7591-7c11-b44c-dd19a91941e0`; controller-supervised baseline build
(session/logs retained), then exact patch export, stable combined engine/tooling
checks, independent candidate review, native observations and the original human
checklist. Source-only candidate edits and repository tooling edits are disjoint.

A/B source-ready checkpoint received: 10 engine files, 9 new common regressions,
and native Mac/Windows identity regressions. Candidate source is frozen in
`candidate-source`; exact hashes/test names are in
`bridge-design/source-ready.json` under the campaign directory. Controller
exported `0002-desktop-accessibility.patch`, SHA-256
`d816b3d331ec4bcdf0bce67477745329fe011b7b35ae0cd8307bb3ae018a6a67`.
This is a review candidate, not an accepted or integrated engine. Syntax-only
checks using actual generated compile commands passed bridge, common delegate
and common bridge tests; no linked C++ test pass is inferred.

Independent engine review is running in existing reviewer chat
`01a15837-5fac-74f2-b2ee-6ddaa492d6d5` against the exact frozen diff.
Baseline compilation remains in progress; candidate source has not been applied
to that checkout. Six API-compatible final regressions are available for
separate-process baseline comparison; seam-dependent tests are explicitly separate.
Unit C has the actual patch inputs for metadata finalization and is running
focused wrapper checks in its isolated copy, with controller permission.

Initial independent engine review established three concrete issues; controller
validated and accepted all three for repair: Windows production initial-root
hint omission; a borrowed GetAXTreeData reference invalidated by tree replacement;
and a held Mac text field's frame query after delegate detachment. Worker is
correcting the owning paths and adding focused regressions in candidate-source.
The original frozen verdict applies only to the first source manifest; revised
source must receive focused review. No new application UI defect was inferred.

A bounded fixture preparation chat,
`01a1584c-2e2e-7f92-9e16-1bf1cc89ec01`, uses worker_luna /
gpt-5.6-luna / xhigh from the actual worker-luna preset. It owns only
`/tmp/lineup-audit/m04-engine-recovery/native-harness/`: an explicitly selected,
disabled engine gtest addition for a disposable native observer fixture. The
settled plan uses real Mac bridge notifications, real controlled AXTree failures
and a later externally invoked synthetic button/value update in one surviving
bridge. It may not edit canonical source, build/link, launch apps or observers.
Controller owns integration and actual observation; fixture preparation is not
compiled/runtime proof or human acceptance. Callback authorization and parent
route are the same verified original human turn above.

Baseline build reached native shader compilation, then failed on missing Xcode
Metal Toolchain (`metal_library.py`, modern.metallib). Resumed build log/result
records 540.5 seconds and no C++ test execution. Controller started supported
`xcodebuild -downloadComponent MetalToolchain`; result remains pending. This
is an environment prerequisite, not an engine repair regression. Keep its
actual tool/component identity with build evidence and preserve disk reserve.

Next controller steps on a callback: inspect download/build state; resume baseline
with the same explicit linker configuration; after original baseline suite,
install the six identical API-compatible final tests and collect each failing
baseline test in a separate bounded subprocess; restore the baseline test source
before applying the revised, reviewed AX patch. Preserve original binaries/logs.
Do not apply a candidate while the baseline build owns its source. Final metadata
currently describes the first patch and must be refreshed after worker fixes.

Revised engine checkpoint focused-repairs-1 (14 files) passed focused independent
review: all three findings addressed, no further concrete issue established.
AX patch SHA-256 is now
`2c843a56499dbdebcbbabd6f178b17bc84d13d0192b1e039318caf13cf18f89a`;
manifest was refreshed from real pinned blobs. Seven revised source syntax checks
(common bridge/delegate/tests plus affected Mac sources/tests) pass.
No linked native test result is inferred. Windows callback preserves both
framework root0 and existing nonzero multiview fixtures; the explicit root0
convention cannot disambiguate arbitrary custom nonzero-root+orphan0 forests.

Controller verification: full Dart suite 1,866 passed, canonical formatter
160 files/0 changes, Python integration tests 14 passed. Analysis reported one
brace style issue in the new wrapper; controller fixed it, analysis rerun pending.
Tooling review accepted three exact-provenance gaps for focused repair: compiled
Dart/build-recipe attribution, omitted shader_lib inputs, and nested gclient Git
source identities/cleanliness. Worker owns those corrections; final source checks
and focused review must use the resulting frozen source.

Metal Toolchain 27A266a installed successfully; metal version 32023.921
(metalfe-32023.921.6). Baseline build resumed. Earlier Metal-failure raw Ninja
log was overwritten on retry; its result metadata and a labeled controller
transcription are retained, not presented as a raw log. Default LLVM-linker
failure evidence remains intact. Ninja shim context selected 1.11.1 versus
Homebrew 1.13.2 on different invocations; future controller commands select the
actual compiled Ninja path explicitly and record its identity.

Native observer fixture preparation returned scratch source and protocol at
`native-harness/` in the campaign directory. Its Objective-C++ syntax check
passes; the fixture has not been linked or run. Source SHA-256:
`c0b601853693cf908e6699c076736b60706904b76565bcb3e2c8980ac3347f1a`.
The controller must inspect/integrate it only into a separately identified
diagnostic engine test binary, preserve canonical source, and obtain actual
registered external AXValueChanged callbacks after real rejection.

Actual common-engine before/after evidence now exists. Original pinned bridge
plus required Apple-linker-only build patch passes 232 existing tests. Seven
identical final regressions all fail independently on baseline (two SIGABRT, two
SIGSEGV, three exit-1 assertion failures), with test/binary hashes and raw logs
preserved. Initial copied-fixture mtime made Ninja skip compilation; test listing
detected this, input mtime was corrected, and real compile/link completed before
any comparison run. Baseline original source bytes were restored before applying
the revised AX patch. Candidate rebuilt six actions and passes 242/242 full common
target tests. All 14 source hashes match the reviewed checkpoint.

The native Mac target is compiling next. Missing vpython3 PATH on its first
attempt was corrected with the provisioned depot_tools path; the failed log is
preserved separately. This is not native callback, human or Windows proof.

The nested HarfBuzz mismatch was a verifier false positive: declared DEPS object
49844c32 is an annotated tag resolving to actual commit6f4c5cec. No source repair
was made; the attempted build stop did not reach its nonleader process group,
and build continued unchanged. A complete read-only scan checks81Gitroots with
zero resolved-revision/dirty/root mismatches. The new verifier handles tag peeling.

Previous exact product829547b4 and stock-engine pair was preserved by APFS clone
at `rollback/Lineup Desktop-829547b4-stock-engine.app` under campaign directory;
all106historicalbundlehashes matched before and after copying. Rollback means
explicitly selecting this preserved pair, never replacing stockSDK cache.

Focused native candidate suite passes12/12 (Mac delegate identity, held text-field
removal/destruction, role transitions and bridge notification-dispatch controls).
These native fixtures include a nonrunning-engine control; its invalid-handle
diagnostics are not a canonical app runtime result.

UnitC final focused review cleared all accepted provenance findings, including
informational-option receipt bypass. Verified builds now allow one explicit mode
and inline defines only; actual help/version/analytics negatives use fixtures,
never live setting changes. Worker reports18Python/13isolatedDart tests and clean
focused analysis. Controller still owes final combined checks and fresh engine/app
artifact build. Full-source dependency scan81roots is clean after tag peeling.

Native observer run4 succeeded in a disposable diagnostic test application: a
trusted PID-scoped AXObserver subscribed successfully to actual native Slider
tag1 before a60% healthy callback; three realAXTree rejections (seed, main after
successful removal prepass, main completion after staged mutation) left the same
bridge/live tree/native Slider and pending events intact, with no observed Slider
value callback for rejected stages. A CUA native button action reached target30;
a later80% update produced actual AXValueChanged on the same tag while native
object remained alive. External confirmation preceded teardown; gtest exited0
and finished status completed. This is one valid update after three accumulated
failures, not a separate recovery update after each.

Run1 lacked AppKit registration; run2 exposed invalid roles from diagnostic helper
stack flag lifetime; neither had a valid native Slider control. Parent fixed
AppKit registration and borrowed flag/value lifetimes. Run3 received the later
notification but teardown prevented reading its value; no full run3pass claimed.
Run4 keeps the native object alive for bounded external confirmation. Actual
source/binary/receipt hashes, raw synthetic snapshots and observer logs are in
`native-harness/run4/`; canonical engine test source was restored after diagnostic
compilation. No VoiceOver/global modifiers/user settings were changed. Canonical
Lineup runtime, physical/spoken acceptance and Windows remain separate gates.
