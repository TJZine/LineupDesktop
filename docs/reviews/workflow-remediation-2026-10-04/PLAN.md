# Lineup Desktop implementation plan

Date: October 4, 2026. Prepared for the human and the implementation orchestrator.

This plan groups the preceding read-only assessment into executable units using
the personal `orchestrate-implementation-chats` skill. The existing chat can remain
the orchestrator; another chat can use this document as a handoff. This is a task
plan, not a new engineering workflow or testing policy.

Status: portable implementation, review, combined checks and conventional commits
completed October 4, 2026. Physical Windows acceptance remains open, as selected
by the human. See [the completion report](REPORT.md) and
[Windows handoff](WINDOWS_HANDOFF.md). The preceding planning turn created only
this document; subsequent authorization, actual dispatch and results are recorded
below. The unit contracts below retain their original planning rationale.

## Source and assessment reconciliation

- Repository: `TJZine/LineupDesktop`.
- Branch: `codex/libmpv-reference-security-report`.
- Planning HEAD: `52157d539f61103ff2966f2727a5fe51d50f2aab`.
- Earlier assessment HEAD: `658be09545291c7d39536e2c44b8806b3cd9c6b2`.
- The intervening changes are documentation and optional role configuration;
  application source and tests are unchanged.
- Before this plan, there were no tracked edits. Preserve the existing untracked
  launch configuration, desktop UI review packet, test-slimming report, and Python
  cache. Do not stage, delete, or reinterpret them as implementation work.
- The earlier P1 dependency inconsistency is resolved by `52157d53`. Do not assign
  another fix for it. Reconcile source again before every actual dispatch.

The earlier correctness findings were established by source traces, not new
runtime reproductions. Workers must validate their applicability and obtain the
missing behavioral observations before claiming resolution. Optional removal
candidates are conditional on preserving their distinct proof obligations.

## Authority and protected contracts

Every implementation child reads the applicable `AGENTS.md`, relevant sections of
[the project profile](../../../.agents/project.md), and shared `develop-code`.
Use `design-code` for consequential ownership decisions, `verify-code` for faithful
evidence, and `review-code` for review and adjudication. These are responsibilities,
not four agents or compulsory sequential phases. Read shared references only for
the work that needs them.

Preserve the obligations in [Architecture](../../architecture.md), including
async/persistence, credential ordering, redaction, and native ownership. Preserve
[the interface system](../../../.interface-design/system.md), current Player and
Now Playing decisions, accessible focus, and Guide alpha. Read
[the reference investigation](../../libmpv-authenticated-reference-investigation.md)
for native/authentication work and
[the transcoding plan](../../plex-transcoding-implementation-plan.md) where playback
ownership is affected.

This remediation does not implement transcoding, change quality defaults, perform
P0b server writes, relax reference restrictions, redesign UI, introduce a general
state/event framework, rewrite CI, or reopen completed test-slimming deletions.
Existing native interfaces and valid-data migrations have current obligations.
No credentials, token-bearing URLs, private media, personal paths, or raw private
diagnostics belong in handoffs or evidence.

## Executors and integration

The orchestrator remains responsible for scope, consequential decisions, source
identity, Git integration, review adjudication, and acceptance. Use the current
orchestrator at high reasoning or above; do not claim to have changed its setting
through a chat-creation tool.

The inspected project presets resolve as follows. Re-read them at dispatch;
these values are recorded selections, not a permanent model roster.

| Preset | Model | Reasoning | Use in this plan |
| --- | --- | --- | --- |
| `worker` | `gpt-6.1-sol` | `medium` | Controller identity/transaction work and playback consolidation |
| `worker_luna` | `gpt-5.6-luna` | `xhigh` | Specified quarantine correction and bounded cleanup |
| `reviewer` | `gpt-6.1-sol` | `high` | Focused independent read-only review when its question earns a separate chat |

Sources: [worker](../../../.codex/agents/worker.toml),
[worker_luna](../../../.codex/agents/worker-luna.toml), and
[reviewer](../../../.codex/agents/reviewer.toml). Copy the selected preset's brief
responsibility instructions into the child packet. Explicitly pass model and
reasoning to `create_thread`; a role name does not configure a separate chat.
Preset sandbox configuration is not an override of actual chat permissions.

Use local project chats by default. Parallel source writers below have disjoint
ownership. All application runs, Flutter checks, generated output, global
formatting, dependency resolution, and Git operations have one orchestrator-owned
resource slot. Children request that slot before checks; do not test a moving
combined source state. Read-only inspection can overlap other work with an exact
source attribution. If unexpected file overlap appears, serialize it or return
the boundary decision; do not silently edit another unit's files.

## Group A Application transactions and authorization identity

Executor: `worker`. Findings 1 and 2 belong together because they share the
controller's queues, saved-state construction, scope ownership, and controller
tests. Use one child with two inspectable milestones, retaining its context.

Write ownership: `lib/app/lineup_controller.dart`, settings types only if needed,
`lib/app/lineup_shell.dart`, `lib/guide/guide_controller.dart`,
`test/app/lineup_controller_test.dart`, and affected settings/Guide widget tests
and fixtures. Coordinate any additional test file with the orchestrator first.
Do not edit persistence implementation, the player coordinator, native code,
workflow configuration, or shared documentation.

### A1 Settings derive inside the owner

Source trace: controller `updateSettings` at line 1714 assigns public state before
awaiting persistence; Settings `_update` at line 1495 derives a complete value
outside that queue and maintains its own save tail/merge switch; Guide hours at
line 504 derives another complete value directly.

Chosen interface direction: the controller accepts a pure settings transformation
evaluated against committed settings inside its queue. A field-specific immutable
change is also acceptable if it simplifies real callers; do not build a generic
patch framework. The view can track pending keys and optimistic display values,
but must not own persistence ordering or a second field-merging policy.

Build a proposed persisted snapshot without publishing tentative controller
settings. Publish committed settings, diagnostics enablement, and notifications
only after a successful save. Failed saves leave committed state unchanged and
continue through the existing UI error/focus behavior. Global settings updates
must not be silently discarded by an unrelated server-list refresh. Keep their
ordering coherent with scope mutations and logout's persistence barrier.

Migrate all real callers and affected test overrides in the same milestone. Do
not leave a full-value compatibility API without a real consumer. Preserve UI
layout, save affordances, and per-field error behavior; this is no design departure.

Required observations:

- Block a failing settings save, request a different field from another caller,
  release the first failure, and observe both committed controller and saved
  state. The failed field stays unchanged; the second requested field commits.
- Queue changes to different fields from the same committed starting state;
  neither successful change is lost.
- Controller observers never see uncommitted settings as committed state.
- Existing save-failure focus and settings propagation checks remain meaningful.

Use the existing controlled stores and settings widget fixtures. Do not replace
them with a demonstration harness.

### A2 Currentness follows the affected scope

Source trace: `refreshServers` at line 603 invalidates the general epoch while
`_discover(reconnectSaved: false)` retains the working connection. `playbackFor`
at line 1538 and its recovery closure at line 1646 capture that epoch.
`_commitChannelList` at line 1296 persists then declines publication if the same
epoch became obsolete. The queue guard at line 1891 can also finish obsolete
work without an explicit mutation outcome.

Chosen boundary: distinguish discovery/request cancellation from committed
authorization scope and mutation ownership. Retain cancellation epochs for the
network operations they actually govern. Playback authorization recovery belongs
to the account/profile/server scope of that playback request, not a server-list
query. Preserve the public playback-request contract used by Group C.

An unrelated discovery operation must not retire a still-valid playback scope or
prevent a successfully persisted channel mutation from publishing to that same
scope. Actual logout, disposal, profile/server retirement, and replaced playback
must still reject obsolete work. Capture scope identity rather than accepting an
old operation simply because it uses the same server ID after leaving and
re-entering a scope. Keep pending server selection distinct from active playback
authorization. Preserve credential write/clear ordering and logout failure rules.

Use a small owner-specific identity/result representation where it eliminates
confusion. Do not replace distinct tune/load/control identities with one counter.
Do not make every mutation return success when it was skipped. If a mutation is
retired before it can commit, callers receive an explicit failure or result they
already handle. Once a write succeeds, reconcile its persisted and live effect
according to the captured scope and serialized transition ordering.

Required observations:

- Capture playback, refresh the server list without changing the active scope,
  then invoke authorization recovery. It can refresh and return the same-scope
  request; existing logout/profile/server replacement cases still deny it.
- Block a delete/reorder/save write, refresh the same server list, then complete
  the write. Saved state and live channels agree, and the caller's result matches
  the actual commit. A subsequent save cannot resurrect the discarded live list.
- An actual scope transition during pending work cannot publish old data or use
  old credentials in the new scope. Include leave-and-return identity coverage
  when the chosen representation requires it.
- Preserve existing credential-cleanup, rollback, and queued mutation evidence.

The worker resolves internal representation and routine migration details under
`design-code`. Return any proposed change to product-level save, logout, scope,
or recovery semantics to the orchestrator before implementing it.

## Group B Preserve quarantine bytes

Executor: `worker_luna`. Finding 3 is bounded after the storage direction below
is fixed; it does not need an application-state redesign.

Write ownership: `lib/persistence/app_store.dart` and
`test/persistence/app_store_test.dart` only.

Source trace: `_quarantineState` at line 196 renames to a millisecond-derived flat
filename. A regular-file collision is replaceable by `File.rename`; the existing
collision test at line 610 uses a directory instead.

Chosen direction: reserve a unique quarantine container in the same application
state directory using the runtime's exclusive unique-directory facility, then
rename the source into that newly owned container. Its name retains the
`state.json.corrupt-` prefix; the original byte file has a stable name inside.
The rename target starts absent inside a container owned by this operation.
Existing flat recovery files and directories remain untouched. No old-state
schema migration or deletion is needed. This changes private recovery artifact
layout, not persisted-state content or startup's recovery semantics.

The serious alternative is an exclusively created flat file plus copy-before-
delete. It adds copying and partial-copy cleanup to preserve the existing flat
layout, whose callers found in this assessment are tests. The unique container
keeps the original-byte move and avoids clock uniqueness or check-then-rename
claims. The child must validate the chosen directory API on the pinned SDK.

Reservation or move failure must propagate and preserve source bytes. Clean up
only an empty container owned by this failed operation, without masking the
original error or recursively deleting recovery content. Report any inability to
faithfully establish a failure case; do not add a filesystem framework merely
for test injection or pretend a permission simulation is Windows acceptance.

Required observations with real temporary filesystem fixtures:

- A pre-existing regular-file artifact with different bytes survives recovery.
- A pre-existing directory survives recovery unchanged.
- Two corrupt states recovered with the same injected clock retain both original
  byte sequences in separate artifacts.
- Invalid UTF-8 remains byte-for-byte preserved; saving and restarting afterward
  does not remove recovery bytes.
- Existing missing-state, transient-read, valid-data migration/backup, and failed
  persistence obligations remain intact. Adapt assertions about artifact layout
  without dropping their behavioral obligations.

Windows filesystem acceptance remains separate from host filesystem tests.

## Group C One playback load at position

Executor: `worker`. Finding 4 crosses tune, multipart, seek, authorization,
native readiness, and replacement identity; a bounded mechanical extraction
would risk preserving the scattered coordination rather than removing it.

Write ownership: `lib/playback/player_coordinator.dart` and
`test/playback/player_coordinator_test.dart`. Any adjacent helper must remain
within this ownership and have a current consumer. Keep `NativePlayer`, the
application playback request, Dart/native payloads, and native implementation
compatible; return proposed public-contract changes to the orchestrator.

Trace the four existing operations: `_loadPlayback` at line 607,
`_recoverAuthorization` at line 666, `_advancePart` at line 824, and `seekTo` at
line 1023. Consolidate their shared part-load ordering, readiness, currentness,
position target, and recovery association into one complete operation. Use
cohesive per-load state to replace correlated fields where it actually removes
invalid associations. Keep meaningful tune, seek, load, and track distinctions.

This implements only the Direct Play consolidation already described in the
transcoding plan's P3 design. It does not implement P3 sessions or satisfy P1/P2/
P0b prerequisites. Do not add unused load-kind/session APIs for future work.

Required retained observations:

- Tune/current-program initial offset waits for the correct native readiness.
- Multipart end advances exactly once and final end behaves as before.
- Cross-part and repeated seeks apply the latest requested position; superseded
  seeks cannot affect replacement media.
- Authorization refresh/reload retains the intended part and position and its
  one-retry ceiling; failed and obsolete recovery cannot publish a new active
  request or position.
- Stop, tune replacement, disposal, and failures retain cleanup obligations.
- Track command acceptance remains distinct from observed track confirmation.

Map existing cases to each obligation before changing them. Retain distinguishing
regressions; do not encode the helper's private layout in new tests. Physical
multipart playback and seeks remain outstanding until Group E.

Group C can run alongside A and B because its public request/native contracts
remain unchanged. If this assumption fails, pause the affected edit and settle
the contract together; do not broaden another child's write scope.

## Group D Remove unused entry points and one duplicated assertion

Executor: `worker_luna`, after the relevant A and C interfaces are stable and
accepted. Findings 5, 6, and 7 form a bounded cleanup unit with explicit retained
obligations. Do not combine it with a new suite-wide slimming campaign.

Write ownership: the four test-only facades in `lib/app/lineup_controller.dart`,
their caller tests, `lib/playback/native_video_surface.dart`, its existing test
if an obligation requires an adjustment, and the two named timeout cases in
`test/plex/plex_transport_test.dart`. A is no longer writing these controller/test
files. Any product-spine test changes must retain its existing integration role.

1. Recheck production callers for `setLibraries`, `applyChannelPlan`,
   `scheduleFor`, and `deleteChannel`. Migrate distinct proof to scan/commit,
   reviewed-plan expected-base, asynchronous schedule, and expected-channel batch
   delete operations, respectively. Remove obsolete facades only after that map
   is satisfied. Assertions about a test-only permissive behavior do not become
   new product requirements; preserve the underlying scan facts and error cases
   at their real owner. Return consequential ambiguity instead of weakening proof.
2. Recheck that no real caller supplies `presentationEpoch`. Remove its parameter
   and dormant comparison if that remains true. Preserve player-change bounds
   invalidation, geometry/DPR reporting, deduplication, teardown, and failure retry
   behavior. If C establishes a real recreation consumer, retain and prove that
   consumer instead; do not force the original candidate.
3. Remove or consolidate only the timeout case asserting `network-timeout` if
   its stronger neighboring case retains that result plus abort and late-body
   cancellation. Establish any claimed equivalence with the retained assertions;
   do not delete boundary-time, socket, or body-deadline coverage. If a remaining
   distinct consumer/obligation is found, retain the case and report why.

Acceptance requires no remaining callers of removed APIs, retained distinct
behavioral proof, and affected focused suites passing. Search absence must be
distinguished from tool errors. No test-count target or coverage-policy change.

## Group E Windows evidence and final acceptance

Executor: `worker` on a configured Windows host, with the human supplying access
and physical/visual judgments. The current host is macOS; this group cannot
establish Windows acceptance here. Do not create a child that claims this hardware
exists or mark acceptance complete after portable tests.

The corrected reference checker changed in `d6fff072`; older positive passes do
not establish its stronger progress-without-later-rejection assertion. It can be
rerun on an available stable Windows source/runtime while portable implementation
proceeds, but attribute it to that exact source. Physical acceptance uses the final
integrated candidate. Do not relabel an earlier run as a final-package pass.

Use existing [Development commands](../../DEVELOPMENT.md) and
[Windows acceptance](../../windows-native-validation.md), rather than creating a
competing test procedure. At minimum:

- Build the gated reference target and run the documented three consecutive
  CTest runs against the pinned prepared/copied DLL. This remains headless DLL
  evidence, including positive controls, TLS, redirect and nested-reference
  containment; no physical playback claim.
- Confirm final-candidate visible/audible SDR and real Plex playback, multipart
  tune/seek/recovery, track changes, stop/replacement/logout/close/recreation.
- Verify PiP/Player composition, resize/minimize/fullscreen/DPI/monitor behavior,
  physical keyboard/remote focus, and Windows assistive technology.
- Exercise representative H.264/HEVC, multichannel audio, embedded subtitles,
  HDR/SDR displays, and approved fallback behavior.
- Repeat controlled redirect/reference containment, rejection/recovery, and no
  late output through the app. Preserve ordered-chapter fallback limits.
- Validate the exact portable artifact, runtime/build/provenance identities,
  clean-environment launch, and documented missing/restored loader case.
- For B, establish Windows recovery artifacts retain old/new corrupt bytes and
  report filesystem refusal behavior faithfully.

Record exact candidate/build/runtime identity, platform/display/input setup,
scenario, observation, pass/fail/not-run, and sanitized evidence. No native or
package source edits belong to this acceptance unit unless separately assigned.

## Dependency and resource schedule

| Work | Start condition | Allowed overlap | Executor |
| --- | --- | --- | --- |
| A1 then A2 | Execution authorized; current scope/branch reconciled | B and C source work | One `worker` chat, two milestones |
| B | Quarantine direction above accepted for execution | A and C source work | `worker_luna` |
| C | Direct Play consolidation scope accepted; public contracts held stable | A and B source work | `worker` |
| D | Accepted A/C contracts and no overlapping writer | Independent read-only review; nonconflicting Windows work | `worker_luna` |
| E headless reference rerun | Windows runtime/tools available; stable identified source | Portable source work on a separately stable checkout | `worker` on Windows |
| E final physical/package acceptance | Integrated reviewed candidate and required tools/hardware | No mutation of acceptance source or exclusive runtime | `worker` plus human operator |

Independent source implementation is parallel; checks and shared generated output
are serialized. In a local shared checkout, freeze writers before combined review
or tests. Use no worktree environment unless the human explicitly requests it;
the skill's isolation advice does not itself authorize `create_thread` worktrees.

The orchestrator reviews each returned unit against its owned diff, can obtain
one focused independent review covering requirements/correctness and
design/standards for A and C, and adjudicates findings before requesting fixes.
There is no fixed panel or review per tiny cleanup. Supply a reviewer actual
source/diff and contracts rather than an expected answer. Reuse a child for a
focused correction; avoid fresh-chat churn.

The orchestrator owns shared architecture/user-facing documentation changes
after accepted implementation, avoiding parallel document conflicts. Update only
actual changed contracts and acceptance facts; do not rewrite workflow owners.

## Verification and completion

Use the pinned toolchain and commands in Development. Each unit first runs the
meaningful affected suites with stable inputs, including controller/store,
coordinator/adapter, affected settings/Guide focus and surface cases as relevant.
The orchestrator then runs the required format/analyze/portable acceptance checks
on the integrated candidate, with the documented Eastern timezone handling.
Do not repeat them without a changed input, failure, or unresolved risk. Apply
the required Guide alpha check when changes reach its rendered surface; optional
visual suites are selected for a real visual claim, not automatically regenerated.

Every completed implementation group includes its requested correction, caller
migration, removal of displaced code where authorized, relevant regression proof,
repair of caused failures, and a faithful report of unavailable acceptance. A
group can be implemented and portable-tested while physical acceptance remains
open. The overall report must distinguish those states.

Do not commit, stage, push, merge, publish, or create PR comments from child chats.
The orchestrator retains Git authority; committing or publishing needs the scope
actually granted by the human, not an inference from this skill. No branch change
is required by this plan. Preserve unrelated working state throughout.

## Self contained dispatch and callback packet

Before actual execution, the orchestrator must:

1. Establish the original human execution instruction authorizing separate chats
   and terminal messages to this orchestrator. Record its retrievable chat/turn
   reference. This planning turn is not that instruction.
2. Resolve the actual parent thread ID and host through trusted context or
   supported thread tools. Do not derive them from the visualization directory,
   a title, branch, Page, or this document. No authorized callback route is
   recorded by this planning document; verify it against the execution turn.
3. Call `list_projects`, resolve this project's actual checkout, recheck branch,
   HEAD and dirty state, read current presets, and confirm child access to this
   plan and shared skills. Use the current tool schema and local project target.
4. Put the following coverage in each child prompt, using observed values rather
   than unfilled placeholders:

   - Exact group and milestone, desired result, write ownership, exclusions,
     dependencies, and the relevant section of this plan.
   - Repository, actual execution checkout, branch/base/HEAD and dirty-state
     preservation; specify its relevant source state if earlier evidence is used.
   - Selected preset, actual model/reasoning, its responsibility instructions,
     and why this unit fits it.
   - Applicable instructions, shared skills, approved contracts, source traces,
     rationale, regression observations, and runtime limits.
   - Controller-owned Git and test/runtime resource rules; no recursive
     delegation without separate authorization.
   - Verified parent route and a pointer to the original human authorization.
     The child verifies that human turn with `read_thread` before callbacks
     unless already available in trusted context. A parent-authored quotation
     alone does not grant permission.
   - Return one terminal complete/blocked report with child/group identity,
     source/diff identity, changed files, actual commands/results, outstanding
     decisions and limits, plus a final report in the child chat. No source
     mutation after reporting completion.

If callback authorization cannot be established, the child does not send a
cross-chat message. It finishes its local report and the parent collects it with
`wait_threads`. No callback permission extends to unrelated chats, Slack, email,
publication, or credential changes.

Record actual child IDs, model/effort, unit, source and verified callback route
in a compact dispatch map in this plan or the parent conversation. A returned
`clientThreadId` is pending; do not send to it, guess its resulting real ID, or
repeat creation because of a timeout. Use supported setup/identity retrieval.

After dispatch or a grant, yield and resume on child callbacks, as clarified by
the user. Inspect returned evidence and actual diffs before accepting. Passing
children do not by themselves prove combined behavior. The execution record below
records actual dispatch separately from the original plan.

## Execution record

The verified parent is `01a10439-a4c6-7e03-826c-27ff8caef4b6`, host `local`.
Original human execution authorization: parent turn
`01a108bf-0496-7823-9ebb-6cb53c8be0ca`, user item
`01a108bf-04e9-75d0-8ab0-cc5e2bbe92e5`, "okay you can start", in response to the
presented separate-chat plan and callback pattern. Children receive this pointer
and must verify its human origin before messaging the parent. Subsequent human
direction selects portable completion with a Windows acceptance handoff.

Project resolved through `list_projects`:
`local-8c633241263023433fa4ceaef19f114e`, local execution on the existing checkout.
All three initial chats start from planning HEAD `52157d53`, with the unrelated
untracked state preserved. Model and reasoning were passed explicitly.

| Group | Actual chat ID | Model and reasoning | Status |
| --- | --- | --- | --- |
| A | `01a108c0-354b-7b42-a456-ca3c8a32bc58` | `gpt-6.1-sol` / `medium` | Accepted, tested and committed |
| B | `01a108c0-7897-7282-ba1c-5b131636134c` | `gpt-5.6-luna` / `xhigh` | Accepted, tested and committed |
| C | `01a108c0-bc65-7c80-9bee-c6c189c3ac5d` | `gpt-6.1-sol` / `medium` | Accepted, tested and committed |
| D | `01a108d4-1679-7082-a6ab-b292a2d4d8e9` | `gpt-5.6-luna` / `xhigh` | Accepted, tested and committed |

The parent owns the shared verification slot. Children may inspect and format
owned paths; they request a slot before shared checks and stop writing while
awaiting it. Git actions were withheld at dispatch. Subsequent human authorization
permits the parent to create focused conventional commits for all remediation
changes; children still perform no Git mutations. D follows stable accepted interfaces.
E will be handed off rather than claimed as executed on this macOS host.

A2 decision adjudicated from existing logout evidence: logout initiation retires
captured playback authorization and pre-logout queued mutation eligibility. An
already-started successful write may publish to the still-active content scope
before the logout barrier retires runtime. Credential cleanup failure retains
that committed effect and session; old queued work and old authorization are not
revived. Successful logout clears runtime after the barrier. The controller
worker owns the minimal distinct identities and the controlled failure/success
contrast proving this ordering.

B ownership extended to the existing quarantine/startup fixture in
`test/app/lineup_app_test.dart`: the retired flat collision now proves preserved
legacy artifacts plus visible recovery rather than startup failure. Existing
transient-read and safe composition-failure startup evidence remains retained.
C requested the first focused verification slot; A and B are asked to reach
coherent source pauses before it is granted.

C released its verification slot after the coordinator/adapter focused command
passed all 147 tests and targeted analysis reported no issues. The initial test
run exposed failed-load handling that reopened the OSD; the worker repaired it
and reran the full focused set. New cases cover authorization during an initial
offset seek and a latest pending target of zero. The parent confirmed the reported
two-file diff hash `094f8877ab57da2ce71197dbe09bd6b2d067722d313a8e51a0b147db3aa311c9`
at unchanged HEAD `52157d53`. Physical playback is not established by these checks.
B holds the next store/startup verification slot, with A and C stopped.

B released its slot after the store/startup command passed all 63 tests without
source repairs. The parent confirmed its three-file diff hash
`d7650ab43cb018b10110e44de7180c304567f9a3732cc373bf72b58386f8bec0`. Existing legacy
artifacts, repeated-clock recovery, exact invalid bytes, restart/save preservation
and live banner/dismissal are tested on the host. Reservation and post-reservation
rename failures remain source-reviewed, with no added filesystem test hook and no
Windows filesystem acceptance claimed. A now holds the controller/settings/Guide
verification slot; B and C remain stopped.

A released its slot after the final eight-file suite passed all 218 tests,
including Guide alpha, and targeted analysis reported no issues. An existing
invalidated legacy-migration case initially failed; restoring account-linking
scope retirement repaired the regression without weakening its assertion. The
parent confirmed A's seven-file diff hash
`9cd4c81159eea442af5e93e9be7bd03238c57e0e98141dd4cb44e5c58dcb7c06`.

An independent Sol/high read-only review runs in chat
`01a108cd-cf0b-76b0-a562-220981963193` against the fixed A/B/C changes plus the
parent-owned architecture update. Its tracked working-tree diff hash is
`4c223856b2c9430eb26543ccdd70487ccbe53c8c4709b97d61d1a996b8c81a15` at base/HEAD
`52157d53`. All source writers remain stopped. D and combined acceptance follow
review/adjudication. No fresh integrated-suite or physical result is claimed yet.

Human commit authorization: parent turn
`01a108ce-7c9a-7bf0-8eb8-a33d5d7d83f5`, user item
`01a108ce-7d25-7331-9749-a3fab71d89ca`, "ensure proper commits are created for all
our changaes". The parent will commit accepted implementation groups before D
changes overlapping paths, then commit the cleanup and completed planning,
evidence, and Windows handoff documents. Unrelated local artifacts stay excluded.
This authorization does not include pushing, merging, or publication.

Independent review completed against the unchanged `4c223856...` tracked diff.
It established no material blocking or worthwhile findings under requirements/
correctness or design/standards lenses. All 13 tracked changed files were
inspected, including caller migrations and the architecture update. Review was
source-only, with worker checks attributed rather than rerun.

The parent created three conventional implementation commits:

- `e3f36d00`: settings transactions and committed mutation/authorization scopes.
- `3fc568d9`: unique, byte-preserving corrupt-state quarantine.
- `5acae4d1`: one playback part-load operation and authorization recovery.

Group D was dispatched at HEAD
`5acae4d1480b74c6239d750e172db535a8c73d5e` to chat
`01a108d4-1679-7082-a6ab-b292a2d4d8e9`, `worker_luna`,
`gpt-5.6-luna` / `xhigh`. It owns only the bounded unused APIs/surface parameter/
timeout cleanup and its caller tests, plus the exclusive focused verification
slot. Other source writers are stopped; parent work is confined to documents.
The parent will inspect its terminal callback, integrate, and run combined checks.

D completed its five-file unit and released the verification slot. The parent
inspected the actual diff and proof migrations; obsolete public references are
absent from `lib`, `test`, `test_driver` and `tool/visual` (successful `rg`
execution with no matches). Private `_applyChannelPlan` remains the reviewed
implementation owner. The owned diff hash is
`784ec47d31e4f42db17f6c4259db0b52dff1c5517395760aafaf56e4010dd5d9`.
Controller tests passed 108; product-spine/surface/transport tests passed 130;
targeted analysis, formatting and diff checks passed. Scan facts remain at scan,
commits require ready IDs, reviewed plans retain expected-base checks, schedules
use the asynchronous worker, and deletion retains expected-channel targets.
The retained timeout test checks the same error plus abort/late-body cancellation;
boundary-time, socket and body-deadline tests remain. No broad slimming occurred.

Parent combined checks run on stable A/B/C plus accepted D source. Global
analysis passed. The documented repository-wide formatter command exits 1 because
20 pre-existing ignored capture scripts under `build/` would change; its
`--output=none` mode made no edits. Formatting all 80 Git-tracked Dart files
passed with zero changes. Ignored local artifacts remain untouched. The full
`TZ=America/New_York flutter test` suite completed successfully: 955 tests passed,
including the required macOS Guide alpha cases. The parent committed D as
`15c07703b302284fd80523968052d97ff2ca9ff4`; this commit contains exactly the
stable product/test inputs observed by those combined checks. Packaging, native
CTest and physical Windows acceptance did not run. The completion report and
Windows handoff accompany the final architecture/documentation commit.
