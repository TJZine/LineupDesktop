# Codex Handoff: Comprehensive-Review Remediation (October 8, 2026)

This handoff implements the remediation plan from the comprehensive review:

- [REPORT.md](reviews/comprehensive-review-2026-10-07/REPORT.md);
- [REMEDIATION.md](reviews/comprehensive-review-2026-10-07/REMEDIATION.md).

The review's findings were made at `0382c131`. The branch tip is now
`01bda796`. Formatting, analysis, and all 1,208 tests pass at that tip,
re-run independently on October 8.

## User decisions (October 8, 2026)

| Finding | Decision |
| --- | --- |
| **F03:** no account exit during first run | Add a quiet **Sign out** text action on the server picker and on the no-usable-libraries state, next to Switch server. It uses the existing Account sign-out flow, including any confirmation it already has. Credential policy is unchanged. |
| **F18:** shuffle order follows Plex's response order | Fix it by shuffling from a canonical stable identity order. **Accept a one-time schedule shift** for existing shuffled channels on the first launch after the update. Sequential and block rules are unchanged. |
| **D3:** a long-open Guide goes stale | **Follow live, keep browsing:**<br>• If the user is at Now (the window wasn't browsed away from the current time), the Guide rolls forward automatically as time passes.<br>• If the user browsed earlier or later, keep their position and make the existing Now control clearly available to jump back.<br>• Don't discard focus the user is actively inspecting. |

**Deferred:**

- **P8 (native buffering, F15):** native C++ that only builds and tests on
  Windows. It moves to the Windows session (see the end of this file).
- **H1 and H2:** live observations.
- **Live-collection refresh and the other already-deferred decisions** listed
  in the report.

## Copy-ready Codex orchestrator prompt

```text
Use orchestrate-implementation-chats to implement the comprehensive-review
remediation in this checkout: docs/reviews/comprehensive-review-2026-10-07/
REMEDIATION.md packages P1–P7, P9, P10, plus three new packages defined below
(P11 F03, P12 F18, P13 D3). P8 is excluded (Windows-only native work).
Dispatch each package to a separate implementation chat with the executor the
plan suggests (`worker` or `worker_luna`; new packages as listed below). Read
the current .codex/agents/worker.toml and worker-luna.toml and map model/effort
onto create_thread. Each child sends its terminal completion or blocked report
back to this orchestrator chat. I authorize creating those child chats and
their callbacks to this chat, for this task only.

SOURCE
Local checkout /Users/tristan/Software/LineupDesktop, branch
codex/desktop-ui-second-pass, starting tip 01bda796 (verify). Local execution,
no worktrees. Preserve the untracked protected paths (.claude/launch.json,
docs/design/desktop-ui/review-packets/lineup-1080p-cbf3dbd5/,
docs/reviews/test-slimming-2026-10-02/, tool/windows/__pycache__/).
Before dispatch, make one docs commit containing
docs/reviews/comprehensive-review-2026-10-07/REPORT.md, REMEDIATION.md and
this handoff file. Record the user decisions below in REMEDIATION.md's parking
lot in that same commit.

STARTING-STATE GATE
The findings were made at 0382c131; 01bda796 adds the Sleep-picker keyboard fix.
For each package, re-verify its finding's mechanism at the starting tip first;
drop or narrow a package if the tip already resolves it, and report that.

READ BEFORE DISPATCH
AGENTS.md; relevant .agents/project.md sections; docs/architecture.md
(accepted ownership; async and persisted state); REPORT.md and REMEDIATION.md
in full; docs/desktop-ui-second-pass.md and .interface-design/system.md for any
visible change; docs/guide-freshness-collection-investigation.md for P12.

USER DECISIONS (binding; record in REMEDIATION.md)
F03 Sign out on Servers; F18 fix with a one-time shift; D3 follow live while at
Now, keep browsed positions. Full text is in docs/codex-handoff-2026-10-08-remediation.md.

NEW PACKAGES
P11 — F03 first-run account exit (worker_luna).
  Add a quiet "Sign out" text action on the server picker
  (lib/app/onboarding_view.dart) and on the setup no-usable-libraries state
  (lib/app/channel_setup_view.dart), placed with Switch server. Reuse the
  existing sign-out flow, including its confirmation and credential cleanup.
  After sign-out the app returns to Welcome/link, as it does today.
  Tests: a zero/one-profile account with no usable PMS can sign out from both
  places; a failed cleanup stays retryable as today; no change to credential
  policy. Render gate: show matched 1920×1080 and 960×720 before/after renders
  of both states, and wait for my approval.
P12 — F18 canonical shuffle input (worker).
  In the single scheduling owner (lib/channels/scheduler.dart, plus
  content_resolver.dart only if canonical identity belongs there), order
  resolved content by a stable unique media identity before the seeded
  shuffle. First prove identity uniqueness for multipart and mixed sources,
  per the freshness investigation. Sequential and block semantics are
  unchanged. Existing shuffled schedules shift once (accepted); no migration
  flag. Tests: every meaningful permutation of the same IDs and durations
  yields identical ordered IDs, offsets, program-at-time and Guide window;
  sequential and block are unaffected; a real membership change is not masked.
  Update the freshness investigation doc (scenario A resolved) and
  user-visible release notes if the repo keeps them.
P13 — D3 Guide follows live (worker; folded into P6's chat, after P6's own
  items, since P6 owns lib/guide/*).
  Track whether the Guide is in "live" mode: the window was set by Now or
  initial open, and the user hasn't moved the time window. In live mode, roll
  the window forward as time passes, keeping focus on the same channel's
  current program. If the user browsed in time, keep their position and focus;
  when Now is off-screen, give the existing Now control a clear "return to
  live" emphasis within existing styling (render-gated). Tests: live mode rolls
  across a window boundary and midnight; browsed mode preserves its position;
  Now restores live mode; both DST folds with P6's instant fix. Render gate for
  the Now emphasis.

SCHEDULE (from REMEDIATION.md's ownership overlaps; overlap everything else)
Wave 1, in parallel: P1, P5, P6 (+P13 after P6's items), P7, P9, P10 (doc
  research only; final reconciliation waits for the end).
Controller chain (shared lib/app/lineup_controller.dart and its tests),
  serialized:
  P1 → P2 → P3 → P4 → P11.
P12 starts after P2 is integrated (P2 may touch scheduling seams).
P11 also waits for P3 (both touch channel_setup_view.dart).
P10 final reconciliation of docs runs last, against integrated behavior.
Children write only the files their package owns; anything else comes back to
you.

CHILD PACKETS
Package section from REMEDIATION.md (or the definition above), the finding
detail from REPORT.md, the starting-state gate, decisions, write ownership and
exclusions, required tests, targeted commands
(TZ=America/New_York flutter test --no-pub <paths>, dart format <changed paths>,
flutter analyze), no commit/push/edits outside ownership, callback route. Probe
recipes under build/review-probes/ are diagnostic only; express accepted
behavior in the repo's real tests, not by copying probe scaffolding.

GIT AND INTEGRATION (you own them)
Inspect each diff against its package goal and the "do not weaken guards,
rollback, privacy or ordering" constraints; commit each accepted package
locally on codex/desktop-ui-second-pass with a conventional message referencing
its finding IDs. After each wave, run dart format --output=none
--set-exit-if-changed ., flutter analyze and TZ=America/New_York flutter test.
No push, PR or merge.

APPROVAL GATES (stop, show me, wait)
- P11: Sign out renders (both states).
- P13: the Now "return to live" emphasis renders.
- Any other visible copy or layout change beyond REMEDIATION.md's stated
  direction, including P3's playlist phase line: show it before committing.
  Routine copy within the existing status line can be batched into one review.
- Ask me for any decision the plan doesn't settle (persisted-shape change,
  new behavior, removing protection).

FINISH
After all packages: one independent read-only review of the full diff from
01bda796 against REPORT.md/REMEDIATION.md and the decisions (reviewer preset or
code_reviewer); adjudicate; apply accepted findings; rerun the full checks.
Update REPORT.md's findings with their resolution commits. Final report: packages,
executors and commits; dropped/narrowed findings; check results; review
findings; remaining Windows items (P8, and the report's L1–L13 as applicable).
Do not claim Windows behavior as verified.
```

## Later: Windows session items

Run these on the Windows machine, with Codex guiding and the user observing, as
in [windows-collaborative-acceptance-handoff.md](windows-collaborative-acceptance-handoff.md):

- **P8 (F15) native buffering:** implement and compile on Windows, with the
  native tests and observation L1.
- **This round's acceptance:** the items listed in the two earlier plans plus
  the report's L1–L13. They should be merged into one updated collaborative
  session on the final commit once the remediation above lands.
