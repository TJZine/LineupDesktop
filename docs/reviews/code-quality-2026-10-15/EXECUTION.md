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
| A | `01a13ead-8f1e-70d3-a864-0592b60f5c58` / local | worker_luna, gpt-5.6-luna, xhigh | `056ffbeb7ed71dcd58f9f63ae0a3f2c6442d9654`; `/Users/tristan/Software/LineupDesktop-A`, `cq/A` | Dispatched; Plex decoding, strict analysis, version consistency |
| H | `01a13ead-952d-7c01-87ef-22c7c8704d20` / local | worker_luna, gpt-5.6-luna, xhigh | `056ffbeb7ed71dcd58f9f63ae0a3f2c6442d9654`; `/Users/tristan/Software/LineupDesktop-H`, `cq/H` | Dispatched; checked toolchain guard; integrate after A |

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

Review status: P0 evidence inspected and accepted; A/H implementation in progress.
No product package review or final whole-branch review is claimed yet.
Last nonblocking retrieval cursors: A `7a625c8f-d873-43ca-a476-3b06e68f099e:1`;
H `34f64ba8-fcf2-4b68-8753-676d07b6c59b:1`.

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
