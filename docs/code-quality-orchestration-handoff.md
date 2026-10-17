# Code-quality plan: orchestration handoff

Prepared October 15, 2026 after the final source review of
[implementation plan revision 3](code-quality-implementation-plan.md).

The plan is ready to begin after P0 establishes its execution baseline. Native
Windows verification remains a separate gate. The review record is
[FINAL_REVIEW.md](reviews/code-quality-2026-10-15/FINAL_REVIEW.md).

Copy the following prompt into the Codex chat that should orchestrate execution.
It supplies explicit choices for preparation, Git, executor selection, callbacks,
visible corrections, and pending native work. Sending it as a human message
provides that authorization; this file alone is not evidence of human consent.
No implementation chats were created during the plan review.

```text
Use the orchestrate-implementation-chats skill to execute revision 3 of
/Users/tristan/Software/LineupDesktop/docs/code-quality-implementation-plan.md.
Use the actual accessible LineupDesktop project and current checkout. Read
AGENTS.md, .agents/project.md, the plan, its TRACES appendix, and the final
review record before dispatch. Preserve the full agreed scope, including all
nine CQ recommendations and the additional packages in the plan. This is now
an implementation assignment.

I authorize the following actions within this assignment:

1. Prepare the baseline (P0). Inspect current Git state and preserve all existing
   work. The reviewed starting HEAD was 8c824420cad48d9af9aa01eb29cef200d1030121,
   on codex/desktop-ui-second-pass; resolve the current state rather than
   resetting to it. After reviewing their current diffs, you may make separate
   local preparation commits for the already-existing .github/workflows/ci.yml,
   docs/README.md, and docs/feature-validation-findings.md changes. Do not rewrite
   that work as part of preparation. You may commit the code-quality plan,
   assessment handoff, orchestration handoff, and docs/reviews/code-quality-2026-10-15/
   as the planning baseline. Keep unrelated newly discovered changes outside
   those commits. Record the resulting actual BASE_SHA; no placeholder SHA is
   supplied. Run P0's pinned-toolchain baseline before product changes.

2. Create the plan's local integration branch codex/code-quality-2026-10 from
   BASE_SHA, and package worktrees/branches from the current integration head,
   never from historical main. I authorize the task-specific worktree model
   and paths described in §2.1/§6.2, including the P0 capability check. If a
   requested branch/path already exists, inspect it and reuse only if it is
   suitable; do not reset or delete unrelated work. Local conventional commits,
   package rebases, and fast-forward integration into this task branch are
   authorized. One orchestrator owns integration.

3. Create separate child chats for the plan's P0 check, packages A, H, T, M, B,
   C, D, E, F, L, S, V, W, K, U, Y, G, and the scoped reviews in §8.2. Choose
   worker_luna or worker according to the package contracts and the current
   .codex/agents/worker-luna.toml and worker.toml files. Read the preset, pass
   its model and reasoning explicitly, and supply its responsibility text.
   Use the current reviewer preset for read-only review. You may reassign a
   unit between the two implementation presets if demonstrated complexity
   requires it; report why. If an exact model is unavailable, do not silently
   substitute a model outside those authorized choices.

4. Children may send meaningful blocker/consequential-decision and completion
   callbacks to this orchestrator chat only. Resolve its real thread/host IDs,
   give children a retrievable reference to this original human message, and
   require authorization verification per the skill. If retrieval cannot prove
   consent, the child leaves its final report for parent retrieval. No callbacks
   to unrelated chats, Slack, or email are authorized.

5. I accept all behavior corrections in the revised §2.2 (2.2a through 2.2h),
   including pruning removed undo occurrences and treating a PIN as expired
   at its exact expiration time. Suspected findings must still be confirmed
   or refuted by their assigned tests before a repair; acceptance does not
   predetermine a confirming test result. Preserve every other approved product,
   visual, data, credential, native-lifetime, and privacy contract.

6. Package F's default route is: implement the candidate, retain it UNMERGED
   pending all required Windows CTests, and continue independent portable work.
   If a suitable Windows host is actually available, run the complete specified
   native checks there. This message authorizes no push to obtain CI. Pending F
   must remain recoverable with its branch/worktree and exact outstanding checks
   recorded. Do not call the entire plan complete while F is unintegrated.
   Physical Windows acceptance is separately recorded even after CTests pass.

7. Remove only task-created worktrees whose accepted work is recoverable and
   delete only their fully integrated task branches. Retain unmerged/pending
   candidates. Do not delete pre-existing branches or execute G's default-branch
   repair proposal.

Follow dependencies, exact write ownership, and shared-resource constraints.
Run at most four implementation children concurrently. Keep full-suite/build
resource use deliberate; do not let tests observe another child's incomplete
shared-tree edits. Give each child its exact package plus matching TRACES
sections, chosen interfaces, invariants, exclusions, checks, and return contract.
Use the same child for focused corrections, including C4 after B. Do not allow
recursive delegation without returning the need to the orchestrator.

Adjudicate review findings, inspect actual diffs, integrate accepted work, and
run the combined gates on stable inputs. Count and literal-set changes require
an evidence map, not preservation of incidental tests or dead strings. Preserve
the revised pager policies, diagnostics storage/export distinctions, restore
ownership, request lineage, Air Check identity, and meaningful Guide activity
notifications from revision 3.

With children running and no useful independent work left, end the turn and
let authorized callbacks resume you. Use supported nonblocking retrieval on
the next activation; do not maintain an idle polling loop. Resolve routine
engineering choices; return consequential decisions outside the accepted plan
with concrete evidence. Complete the authorized scope and repair failures
caused by the changes.

Not authorized: push, PR creation, merge into main, deployment/publication,
default-branch changes, deletion of unrelated branches, persisted/wire format
changes, committed golden updates, macOS media implementation, product features,
or user-visible changes beyond accepted §2.2.

Report actual executor selections, package/diff/commit identities, retained proof,
observed command results, review dispositions, integration state, and all remaining
platform limits. Distinguish implemented, tested, integrated, and physically
accepted. Keep partial native delivery explicit.
```

If the maintainer wants a different Windows route or wants to decline a §2.2
correction, edit those sentences before sending the prompt. The default prompt
has no missing BASE_SHA, Windows-route, or approval placeholders.
