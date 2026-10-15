# Code-quality implementation execution

Implementation assignment authorized October 15, 2026. Revision 3 of
`docs/code-quality-implementation-plan.md` remains the complete scope, including
CQ-01 through CQ-09 and every additional package. This record tracks actual
dispatch, acceptance, and integration; it does not replace package contracts.

## Authority and source

- Parent chat: `01a13ea7-726e-7c82-b3b4-c5172b401867`, host `local`.
- Original human authorization: turn
  `01a13ea8-939b-7330-80fe-f305fd68c51d`, user message
  `01a13ea8-956f-7ad3-8286-cfff04890bcd`. Retrieve with `read_thread` and verify
  human origin and scope before a child callback. A copied prompt is not consent.
- Actual accessible project: `local-8c633241263023433fa4ceaef19f114e`,
  `/Users/tristan/Software/LineupDesktop`, local host.
- Inspected starting branch: `codex/desktop-ui-second-pass`;
  HEAD `8c824420cad48d9af9aa01eb29cef200d1030121`.
- Reviewed existing CI diff committed without rewriting:
  `52ca6a67` (`ci: retry pinned engine dependency downloads`).
- Existing feature findings and index entry committed without rewriting:
  `97dae32b` (`docs: record feature validation findings`).
- Planning baseline commit and **BASE_SHA**:
  `14ac167be4d0007cf61ce85f9ed4879ca6d5c3b1`.
- Integration branch created from BASE_SHA: `codex/code-quality-2026-10`.
- No pre-existing `cq/*` or integration branch was found. Existing unrelated
  worktrees and branches were left untouched, including prunable registrations.

All behavior corrections in plan §2.2a–h are accepted, subject to their required
confirming tests. No push, PR, default-branch changes, publication, persisted or
wire changes, committed goldens, macOS media implementation, or additional
features are authorized. Only fully integrated task branches may be deleted.

## Dispatch and resource ownership

Preset files were read from the actual checkout. `worker_luna` resolves to
`gpt-5.6-luna` / `xhigh`; `worker` to `gpt-6.1-sol` / `medium`; `reviewer` to
`gpt-6.1-sol` / `high`. Every dispatched chat receives the selected responsibility
text and explicit model/effort. At most four implementation children run together.
The parent owns integration and worktree cleanup. Children cannot delegate.

| Unit | Actual child / host | Executor | Source / worktree | State |
| --- | --- | --- | --- | --- |
| P0 | `01a13eaa-0f77-7ef1-a805-cbad67a3714a` / local | worker_luna, gpt-5.6-luna, xhigh | BASE_SHA; main checkout baseline, then `/Users/tristan/Software/LineupDesktop-preflight`, `cq/preflight` | Accepted: baseline and capability checks green |
| A | `01a13ead-8f1e-70d3-a864-0592b60f5c58` / local | worker_luna, gpt-5.6-luna, xhigh | `056ffbeb7ed71dcd58f9f63ae0a3f2c6442d9654`; `/Users/tristan/Software/LineupDesktop-A`, `cq/A` | Accepted and integrated at `5990c0217b33d6d690b663f177fbe62e2635b557`; combined format/analyze/1,583 tests passed |
| H | `01a13ead-952d-7c01-87ef-22c7c8704d20` / local | worker_luna, gpt-5.6-luna, xhigh | `056ffbeb7ed71dcd58f9f63ae0a3f2c6442d9654`; former `/Users/tristan/Software/LineupDesktop-H`, `cq/H` | Accepted/integrated at `2a785c456c7238fc1221202f6be5930681d02711`; main format/analyze/1,588 tests passed; task worktree/branch removed |
| Wave-zero review | `01a13ebb-ce39-7302-b966-ebab5c36b4d6` / local | reviewer, gpt-6.1-sol, high | H `1d6520b4`; corrected A `77fb3607`, both versus `056ffbeb` | Complete: no unresolved material findings; A-R1 closed |
| T | `01a13ec4-fc5f-7372-b500-e8d5a1a8b4b3` / local | worker_luna, gpt-5.6-luna, xhigh | `2a785c456c7238fc1221202f6be5930681d02711`; `/Users/tristan/Software/LineupDesktop-T`, `cq/T` | Source reviewed/integrated at `dbc4dea073cea9f4eec0eba500306f195c7b7f8c`; main gate failed one logo-widget case; original child diagnosing |
| M | `01a13ed3-6660-72d0-b27d-4d813a55d6bc` / local | worker_luna, gpt-5.6-luna, xhigh | `dbc4dea073cea9f4eec0eba500306f195c7b7f8c`; `/Users/tristan/Software/LineupDesktop-M`, `cq/M` | Candidate `b97df2cf33d9df0ec9c5ea13296f0beaf317d127`, 1,593 tests/macOS build reported green; independent review running; unintegrated |

P0 exclusively owns Flutter checks while running. It first runs pinned
`flutter --version`, `flutter pub get`, `dart tool/format.dart --check`,
`flutter analyze`, and `TZ=America/New_York flutter test` on BASE_SHA in the main
checkout. Only after a green baseline may it commit a harmless probe file in
the preflight worktree and run pinned version/pub-get/`flutter test test/tool`.
P0 is complete. A and H now run in isolated worktrees, with full-suite
concurrency capped at two per child. Neither runs application/native builds.
Both received their full exact package contract and matching TRACES section,
ownership row, preset responsibility, actual source identities, human callback
retrieval reference, exclusions, and complete return contract. A's broad lint
ownership applies only to mechanical fixes; H is rebased/rechecked after A.

Remaining dispatch follows plan dependencies: accept A then H, T, M, then B/C/D/F first
in wave 1, followed by L/E/S/V/W as slots free; C4 returns to the same C chat
after B; K/U/Y follow their owners; required scoped reviews and final composition
review precede G. Required full gates run against stable integration inputs.

## Review and completion contract

The maintainer additionally required that all changes be properly reviewed for
adherence to the plan and goals before this assignment is considered finished.
Use the shared `review-code` skill for acceptance and finding adjudication.
Tests passing or a child declaring completion does not satisfy this requirement.
Subsequent human steering (turn `01a13eba-ca40-7261-ae58-b6c8e3c36056`, message
`01a13eba-cab6-77c3-b35a-2fc7abf9b44b`) requires delegated reviewer work so
the controller retains orchestration context. Delegate substantive diff review
to read-only reviewer chats/agents; the controller owns scope, adjudication,
acceptance decisions, integration, and stable gates. H/T/G controller inspection
may use reviewer assistance and does not replace other required reviews.

- Inspect every actual package diff against its complete §7 contract, matching
  TRACES, revision-3 final-review corrections, approved behavior, and exclusions.
  Record exact reviewed base/head and the evidence for every required step.
- Independent reviewer chats are required before integrating B, C (after C4),
  D, F, L, and U. Independently review A, E, M, S, V, W, K, and Y together after
  their merges. The controller inspects H, T, and G, as specified by §8.2.
- Run the independent whole-branch code review before G. Check composition,
  including B/C supersession, M/C telemetry, B/L authorization, K producers,
  U coordinator getters, and the complete agreed scope. Inspect G's subsequent
  documentation diff and repair any contradictions with actual delivery.
- Adjudicate each finding against current source: accepted, rejected with
  evidence, or needs evidence. Send focused corrections to the original child;
  verify and, where necessary, re-review the changed contract. No unresolved
  material correctness, scope, privacy, or verification finding may silently
  become an accepted package.
- Require old-obligation → retained-evidence maps for test moves/removals and
  classification of material literal changes. Counts and dead strings are not
  substitutes for behavioral proof or visible-behavior preservation.
- Complete stable combined format/analyze/full-test gates after each integration,
  the specified macOS builds, and required platform gates. Record implemented,
  tested, reviewed, integrated, and physically accepted as separate facts.
- F remaining unmerged or missing its required Windows CTests means the plan is
  not fully complete. Physical Windows acceptance remains separately pending
  until actually observed, even when deterministic checks pass.

Review status: P0 accepted; corrected A and H independently reviewed, no unresolved
material finding established. A integrated with combined gate green; corrected
H independently closed and integrated, main combined gate green. T independently
reviewed and integrated, main gate failed one logo-widget case; original T child
diagnosing. M candidate review in flight, integration held. Final whole-branch review
remains pending. Last nonblocking retrieval cursors: A `7a625c8f-d873-43ca-a476-3b06e68f099e:3`;
H `34f64ba8-fcf2-4b68-8753-676d07b6c59b:3`.
Wave-zero reviewer cursor: `f8719467-752a-4168-b924-2b678e14ed88:4`.
T retrieval cursor: `f42cb099-62a0-4bc8-a48c-6e4332c0926f:2`.

### H candidate inspection

Reviewed exact range `056ffbeb7ed71dcd58f9f63ae0a3f2c6442d9654` to
`1d6520b4c252d345572aa01ed8711977c100b252`; worktree was clean. Seven files
match H's ownership, including all four CI setup checks, explicit fixture
opt-out, checked pin, and the one PowerShell consistency assertion. Existing
CI dependency retries remain unchanged. No golden diff or whitespace errors.
No material finding established in this candidate. This is controller review
per §8.2, not a claim that combined strict-analysis checks have run.

Child reported clean analysis/format (106 files), five new toolchain tests,
all ten retained formatter tests, and **1,572** full-suite passes (+5 from its
actual base). Parent inspected full-suite log tail and both actual 3.47.6
rejection diagnostics. No tests moved/removed; existing formatter assertions
remain intact, with the explicit fixture flag the only change. Pre-change
absence of a guard is source evidence; a new pre-fix wrong-SDK run was not
observed. Serialized 3.47.6 fixture tests passed after an initial concurrent
native-asset startup race; no SDK mutation was made. PowerShell was unavailable:
the policy assertion is source-inspected and still requires execution on a
PowerShell host; future CI has not run and is not a pass.

H remains unintegrated until A is accepted and H is rebased and checked under
the resulting strict analyzer. Proposed sentence for G's DEVELOPMENT.md:
“Run `dart tool/check_toolchain.dart` before repository checks; it verifies that
the Flutter SDK on PATH matches `tool/flutter_version.json`.” Full suite and
wrong-SDK logs are in `/tmp/lineup-cq-H/`. The callback header mistyped the child
ID; the dispatch identity above is confirmed by supported thread retrieval.

### A candidate inspection and focused correction

Inspected exact original candidate range `056ffbeb` to
`24691ac05fb866c64ccf1467226b7cb9c8376388`, clean worktree. All 23 changed files
fit A ownership; non-Plex/version changes are mechanical lint fixes or narrow
documented boundary-fixture ignores. Parent inspected the actual test diffs and
pre-fix logs confirming structural type errors, TLS, invalid date, and empty-token
failures. Child reported clean analysis/format, 214 Plex tests, and 1,579 full
tests (+12: eleven Plex cases and one version-consistency case). No old tests
were removed/moved or goldens changed. These are original-candidate results,
not acceptance of the outstanding correction.

Review finding A-R1: `_streamCodecs` is lazy; `_dynamicRange` returns immediately
for explicit Dolby Vision fields, so a malformed first-selected-part `Stream`
container can escape §7.A's typed structural failure rule. Disposition: source
mechanism confirmed; same A child must reproduce before correction and validate
the selected first container before the early return, preserving unused
Media/Part selection behavior. Also requested explicit selected Part/Stream
missing/null controls if not already covered. Do not integrate A until this
focused correction and required evidence are inspected. Follow-up dispatched
to the original child with unchanged model/effort and write ownership.

A correction returned at `77fb36075bdd75f82432753f856e6753eab16438`:
child reports the two Dolby Vision parser controls and scan fixture failed
before the fix, then passed with eager validation of only the first selected
Stream container. Four added cases yield 218 Plex and 1,583 full-suite passes;
format106/analyze/diff checks reported clean. No moves/removals/goldens.
Independent reviewer now owns full A candidate review and focused A-R1 closure,
alongside H's stable candidate. Neither package is integrated pending verdicts.
The reviewer received full exact A/H package contracts, respective T6/T5 traces,
fixed source identities, observed evidence, ownership, and callback verification
references. No repeated broad suite or source writes are authorized for review.

Independent reviewer subsequently returned no unresolved material findings in
either fixed candidate. A-R1 is accepted as closed, supported by source and
targeted before/after observations; H's future strict rebase and PowerShell
execution limits remain explicit. Corrected A results (1,583/218) are in child
turn `01a13eb8-273b-7e43-99c8-98aed03c73fc`; original named temporary
`full-suite.log`/`plex-suite.log` still contain 1,579/214 and must not be relabeled.

### Integration observations

A was rebased without conflict onto `943f39f36ba9fe46bab0eb10a80fd2812b13f00f`
and fast-forwarded into the task branch at
`5990c0217b33d6d690b663f177fbe62e2635b557`. Original commits `24691ac0` and
`77fb3607` became `6ecc37c3` and `5990c021`. Product/test/analyzer content diff
between the independently reviewed original A head and rebased head was empty.
Combined gate at that product head passed: pinned canonical format106 with zero
changes, strict analysis no issues, Eastern-timezone full suite **1,583 passed**
at concurrency2. Logs are `/tmp/lineup-cq-integration/A/{format,analyze,full-test}.log`.
A is accepted; no actual Windows/Plex/media/physical acceptance is implied.

A task worktree and fully integrated `cq/A` branch were removed after accepted
work was recoverable on the integration branch. No pre-existing branch changed.
H was rebased conflict-free onto docs-only follow-up `971a0aea`; range-diff of
its one original commit versus replayed commit `9e2ea64a` was identical. Pinned
premerge canonical format passed108 files with zero changes. Strict analysis
then found exactly one `unnecessary_lambdas` info at
`tool/check_toolchain.dart:198:37`, exiting1. The chained tool suite was not run.
Logs: `/tmp/lineup-cq-integration/H/premerge-{format,analyze}.log`.

H-R1 disposition: mechanical integration failure under A's new required lint;
accepted correction request, returned to original H child at `9e2ea64a` with
unchanged ownership/preset. Requested format/analyze/tool/full checks on its
corrected stable A+H snapshot; no rule/assertion weakening. H stays unintegrated
pending correction evidence, focused reviewer closure, and main combined gate.

H correction returned as `885c4d5861006beb5b41810c1f82627ce7de2595`, with a
behavior-neutral typed `MapEntry` constructor tear-off replacing the flagged
closure. Child reported corrected pinned check/format108/analyze clean, all15
tool tests and **1,588** full tests passed (1,567 +16 A +5 H); no tests or
assertions changed. Parent observed clean candidate and log tails for analysis,
tool/full passes. Logs: `/tmp/lineup-cq-H/rebased-{check,format,analyze,
tool-tests,full-tests}.log`. Actual H source chat remains the dispatch identity;
its completion prose repeated the earlier mistyped child ID. Same independent
reviewer received focused H-R1 closure and evidence, with no redundant broad
suite or source writes requested. H remains unintegrated until that verdict.

The independent reviewer closed H-R1 at `885c4d58`: exact one-line diff is
behavior-neutral, original patch range-diff is identical, and inspected corrected
logs support strict analysis/15 tools/1,588 full passes. No new material finding.
Parent accepted the closure. H was rebased without conflict onto docs-only
`b84d9eb34631fba31288f23901abb74a593860ef`; both replayed patches were identical
in range-diff (`9e2ea64a` → `5bb92ec9`, `885c4d58` → `2a785c45`). Fast-forward
integration head is `2a785c456c7238fc1221202f6be5930681d02711`. Required main
format/analyze/full gate runs with logs `/tmp/lineup-cq-integration/H/`.
Main H format108 and strict analysis have passed. The full suite is still
running in exec session `9533`, with stable product inputs at `2a785c45`.
On next activation, collect its exit status using `write_stdin` and inspect
`full-test.log`; do not claim this main full gate passed from candidate results.
Retain H worktree/branch until the combined gate is accepted. Subsequent parent
commits change this execution Markdown only, not tested product/check inputs.

T was created from that exact current integration head and given full package
contract, T5 trace, owner row, selected preset text, original human callback
reference, and exact return/proof map. It may investigate/implement in its isolated
tree while H's stable main gate runs; H's reviewed product snapshot already has
observed 1,588 passes and A's main gate is green. No main check observes T edits.
T full checks are capped at concurrency2; no app/native build resources assigned.

### Accepted H main gate and T review

Main H gate session9533 completed with exit0. Canonical formatter checked108
files with zero changes, strict analysis clean, Eastern full suite **1,588
passed** (elapsed1:50). Logs `/tmp/lineup-cq-integration/H/{format,analyze,
full-test}.log` establish this main gate, separately from candidate results.
H is accepted and its integrated task worktree/branch may be removed. Its
PowerShell assertion remains source-checked only; no CI execution is implied.

T candidate `548b7ec3` returned clean: only15 owned test/support files, net−313
lines (377 added/690 removed), no production/golden changes. Child reported
format109/analyze clean, focused799 and full1,588 passes, matching actual base.
Parent collected supported completion and inspected source identity/status,
diff stat and final full-suite log tail. No source acceptance claimed yet.
Same read-only reviewer received complete exact T contract/T5 and full candidate
scope to inspect fake behavior/state, IDs, special-fake exclusions, migrated
obligations and assertions. The one reported `loads == 1` → `hasLength(1)`
adaptation (recorder now a list) is explicitly under review for equivalent
count proof and adherence to T's preservation intent. T stays unintegrated
pending verdict/adjudication; no new implementation package dispatched yet.

### T acceptance and M dispatch

Independent reviewer inspected T's complete15-file diff and caller/subclass
behavior at `548b7ec3`: no material finding established. Controller accepts
representation-only load-list length and `rects` → `videoRects` assertions as
equivalent count/value proof, explicitly recording the textual departure from
“assertions unchanged.” Do not claim the assertion text was literally untouched.
The five Plex-helper consumers meet the ≥3 rule. All28 actual coordinator
subclasses are retained; historical plan26 is not the actual source inventory.
Reported fake state/emission/disposal/ID obligations and focused799/full1,588
results were inspected by the reviewer, with no coverage loss established.

T rebased conflict-free onto `46a45355bb1ba7d4ae4e60509104d354b9f0c695`.
An initially mistyped original revision stopped the first range-diff/merge
command before integration. Resolving original `548b7ec3` to its actual full SHA
corrected the check; range-diff showed identical patch at
`dbc4dea073cea9f4eec0eba500306f195c7b7f8c`, then fast-forward integration succeeded.
An accidentally started prior-head check is not T evidence. The actual postmerge
gate is exec session `31563` with logs `/tmp/lineup-cq-integration/T/
integrated-{format,analyze,full-test}.log`; collect exit status on next activation.
Keep T worktree/branch until that gate is accepted. Main product inputs remain
stable; parent may update execution Markdown only.

M was created from that exact integrated T head and dispatched with complete
§7.M/T4, ownership, chosen interfaces, original human callback reference,
responsibility text and return map. `worker_luna` remains suitable because the
platform factory, unchanged wire/messages, malformed-value handling and protocol
requirements are specified; unresolved cross-boundary decisions must return to
the controller. It alone owns the assigned macOS build in its isolated tree;
no native code/Windows/macOS media implementation is authorized. Parent retains
the required main macOS build after M integration. M tests use the current
shared doubles; source baselines/counts come from the actual T head.

### T main failure and M candidate

Session31563 completed exit1: actual T main format109/strict-analysis passed,
full suite ended **1,587 passed / 1 failed**. Failure: existing
`test/playback/player_view_test.dart` “OSD uses official title artwork with a
text fallback”, line2438, expected one `player-osd-logo`, found0 (“loaded logo”).
Exact log `/tmp/lineup-cq-integration/T/integrated-full-test.log`. This is a
failed main gate despite the previously green candidate. Do not count T as
fully accepted or advance integration based only on its candidate pass.
Original T child received bounded verify-code diagnosis on stable `dbc4dea0`,
comparison against actual preT base, no blind pump/retry/assertion weakening,
and authority for a demonstrated fixture synchronization correction if needed.
Production/cross-owner fixes must return evidence first. M's simultaneous
isolated workload is a possible scheduling factor, not an established cause.

M completed clean at `b97df2cf33d9df0ec9c5ea13296f0beaf317d127`:11 changed files,
no native C++ changes, protocol doc and Dart rename/factory/checked decoding/
telemetry semantics included. Child reports pinned format/analyze clean,
focused532, full1,593 (+5), and successful macOS build. Parent inspected source
identity/status, diff stat, full-suite and build log tails
(`/tmp/lineup-cq-M/{full-suite,macos-build}.log`). Build is compile evidence;
macOS playback unsupported, Windows/physical acceptance absent.
Same independent reviewer received full M/T4/exact snapshots and the reported
startup error-fixture adaptation for explicit obligation/ownership adjudication.
Reviewer informed T main gate failed; it does not diagnose T in parallel.
M remains unintegrated until T gate is resolved and its review is adjudicated.
M retrieval cursor: `0af69a21-3777-4d4e-b463-f577a8f6ef98:1`.

### M independent verdict and proof correction

Independent full11-file/source/protocol review at `b97df2cf` established no
production correctness/security/ownership regression, but found M-R1[P3]:
`unsupported_native_player_test.dart` telemetry equality uses identical const
objects and variants differing in many fields, so it does not prove value
equality or independent field participation. The implementation itself compares
and hashes all15 fields correctly. Controller ACCEPTS the concrete proof gap;
returned to original M child to correct the existing test with distinct runtime
instances and one-field-at-a-time changes. Focused negative controls, format and
analysis requested; prior broad product/build proof stays attributed to its
actual candidate and parent still owns required postintegration full/build gates.

Reviewer ACCEPTS typed startup-fixture adaptation: both existing startup cases
retain guidance/redaction and pending/later-completion obligations. Correct
provenance: `_invokeNative` already normalized `required_engine_unavailable` at
the M base. M preserves it and simplifies its startup consumer, rather than
newly implementing normalization. The specific initialize/error mapping is
source-checked; the UI fake does not execute the transport, and existing generic
allowlisted transport error coverage does not claim that exact case.
All five documented Dart/native differences are preexisting according to the
review. Protocol/source, exact messages, rename references and no golden/native
changes were checked. Canonical format110/analysis and focused532/full1,593,
macOS build results remain candidate evidence; no physical/platform acceptance.
M stays unintegrated pending M-R1 closure and T gate resolution.

## Evidence and limits

Preparation `git diff --check` passed. P0's observed pinned Flutter identity was
3.47.7 / framework `abaf9c5237` / Dart 3.13.5. On BASE_SHA, dependency resolution
succeeded, the canonical formatter checked 104 files with zero changes, analysis
reported no issues, and the full Eastern-timezone suite passed **1,567 tests**.
The preflight write/commit succeeded at
`74f0fe588410336da2876c58437d0faebb478be3`; its pinned dependency resolution and
all **10** tool tests passed. The parent inspected the probe diff, clean worktree,
and log tails. Logs are `/tmp/lineup-cq-p0/{flutter-version-baseline,
pub-get-baseline,format-baseline,analyze-baseline,test-baseline,
flutter-version-preflight,pub-get-preflight,test-tool-preflight}.log`.
P0 retrieval cursor: `7195b524-37c0-4a66-bf78-950bb46ed665:1`.

Preparation commits preserve existing work and contain no product changes.
The throwaway preflight worktree was removed after acceptance; retain `cq/preflight`
because its marker commit was deliberately never integrated and the human
allowed branch deletion only for fully integrated task branches.
The current host is macOS; no suitable Windows execution
host has been established. Package F must remain recoverable and unmerged
until all required Windows CTests pass: `display_dynamic_range`,
`display_guardian`, `native_player_contract`, and `runner_lifecycle`.
Physical Windows checklist W1–W12 remains a separate acceptance obligation.

With children running, completion/blocker callbacks are authorized only to the verified
parent. On the next activation, collect reports with nonblocking `wait_threads`
(`timeoutMs: 0`) or bounded `read_thread`; retain returned cursors. Do not poll
idly or treat child completion as acceptance without inspecting source/evidence.
