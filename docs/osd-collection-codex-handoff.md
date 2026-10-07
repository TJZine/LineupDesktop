# Codex Orchestrator Handoff: Player Timing and Channel Creation Fixes

Paste the prompt below into a new Codex chat in the LineupDesktop project. Use
high reasoning or above for that orchestrator chat. Pasting it is the human
instruction that authorizes child chats and their callbacks.

---

Use `orchestrate-implementation-chats` to implement the approved plan in
`docs/osd-autohide-and-collection-membership-plan.md`. Dispatch its six units
to separate implementation chats. Use the plan's suggested preset for each
unit (`worker_luna` or `worker`), or choose between those two presets when
you find a reason to. Each child sends its terminal completion or blocked
report back to this orchestrator chat. I authorize creating those child chats
and their callbacks to this chat, for this task only.

**Source.**

- Local checkout `/Users/tristan/Software/LineupDesktop`, branch
  `codex/desktop-ui-second-pass`, base `97cf093a`.
- Use local execution. Do not create worktrees.
- Preserve the existing untracked files. Do not modify or commit them:
  - `.claude/launch.json`
  - `docs/design/desktop-ui/review-packets/lineup-1080p-cbf3dbd5/`
  - `docs/reviews/test-slimming-2026-10-02/`
  - `tool/windows/__pycache__/`
- Before dispatch, commit the plan and this handoff file as one docs commit.

**Read before dispatch.**

- `AGENTS.md`.
- The relevant sections of `.agents/project.md`.
- `docs/DEVELOPMENT.md`.
- The whole plan.
- The current preset files `.codex/agents/worker.toml` and
  `.codex/agents/worker-luna.toml`. Map their `model` and
  `model_reasoning_effort` onto `create_thread`, and include their
  responsibility instructions in each child packet.

**Sequencing.**

- **Wave 1, in parallel:** A1, A2, B1, B2. Their write ownership is disjoint,
  as listed in the plan's unit table. Shared `flutter test` runs serialize on
  Flutter's own lock.
- **Wave 2:** A3 after A1 and A2 are accepted and integrated. B3 after B1
  and B2 are accepted and integrated.
- Children may read any file. Each child writes only the files the plan
  assigns to its unit. If a unit needs a file it does not own, the child
  returns to you rather than editing it.

**Every child packet contains:**

- the plan path;
- its exact unit section;
- the user decisions D1–D4;
- the source identity and its ownership exclusions;
- the required tests;
- the targeted test commands for its area
  (`TZ=America/New_York flutter test <paths>`, `dart format <changed paths>`,
  and `flutter analyze`);
- an instruction not to commit, push, or edit files outside its ownership;
- the callback route.

**Git and integration (orchestrator only).**

- Inspect each returned diff against its unit contract and the plan's
  decisions.
- Adjudicate any deviation, then commit each accepted unit locally on
  `codex/desktop-ui-second-pass`, one commit per unit, with a conventional
  message.
- Do not push, open a PR, or merge.
- After each wave, run
  `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, and
  `TZ=America/New_York flutter test` on the integrated tree. Fix composition
  failures, or route them to the owning child.

**Approval gates (stop and ask me).**

- **B3 copy and visuals.** This covers:
  - the Playlists and Collections unavailable or partial states;
  - the append skipped count;
  - the "Source not found" review section.
  Show me the exact copy and matched before/after screenshots or goldens.
  Do not merge B3 surfaces or update goldens until I approve.
- **Decisions the plan does not settle.** Anything consequential outside D1–D4
  or the plan's contracts, such as a change to persisted data shape, a new
  user-visible behavior, or removing existing protection.
- **Proof a child cannot provide.** Any required proof a child cannot produce
  must be reported as outstanding, not claimed.

**Final review.** After both waves, run one independent read-only review of
the full diff from `97cf093a`, using the `reviewer` preset or
`code_reviewer`, against the plan. Adjudicate its findings, apply the
accepted ones, and rerun the full checks.

**Final report to me.**

- The units, executors, and commits.
- The check results.
- Adjudicated review findings.
- Docs updated: the `product-parity.md` rows and the freshness note.
- The plan's "Acceptance outside this checkout" list, stating which items
  remain for me: Windows Player behavior, the Windows profile timeline, live
  Plex collection counts and scan time, and the live probes.

Do not claim Windows playback, Windows performance, or live Plex behavior as
verified. Portable tests do not establish them.
