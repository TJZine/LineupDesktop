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

P0 exclusively owns Flutter checks while running. It first runs pinned
`flutter --version`, `flutter pub get`, `dart tool/format.dart --check`,
`flutter analyze`, and `TZ=America/New_York flutter test` on BASE_SHA in the main
checkout. Only after a green baseline may it commit a harmless probe file in
the preflight worktree and run pinned version/pub-get/`flutter test test/tool`.
Product packages are not yet dispatched. The parent may edit this Markdown
record while baseline checks run; no Dart/product/check inputs change.

Remaining dispatch follows plan dependencies: A/H, T, M, then B/C/D/F first
in wave 1, followed by L/E/S/V/W as slots free; C4 returns to the same C chat
after B; K/U/Y follow their owners; required scoped reviews and final composition
review precede G. Required full gates run against stable integration inputs.

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
The throwaway preflight worktree can now be removed; retain `cq/preflight`
because its marker commit was deliberately never integrated and the human
allowed branch deletion only for fully integrated task branches.
The current host is macOS; no suitable Windows execution
host has been established. Package F must remain recoverable and unmerged
until all required Windows CTests pass: `display_dynamic_range`,
`display_guardian`, `native_player_contract`, and `runner_lifecycle`.
Physical Windows checklist W1–W12 remains a separate acceptance obligation.

With P0 running, completion/blocker callbacks are authorized only to the verified
parent. On the next activation, collect reports with nonblocking `wait_threads`
(`timeoutMs: 0`) or bounded `read_thread`; retain returned cursors. Do not poll
idly or treat child completion as acceptance without inspecting source/evidence.
