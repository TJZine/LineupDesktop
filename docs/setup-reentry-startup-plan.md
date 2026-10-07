# Saved-Lineup Startup and Setup Re-Entry Fix Plan

**Status:** approved for implementation on October 7, 2026.

**Source:** `codex/desktop-ui-second-pass` at `c5fccffe` (pushed).

**Inputs:**

- The Windows acceptance controller handoff for `6977a0b8`, which reported
  findings **LIB-01** and **LIB-02**.
- A startup failure the user observed at `c5fccffe` during the collaborative
  Windows session.

Every cause below was confirmed on `c5fccffe`, using source reading and a
temporary real-controller probe that was not kept.

Read first:

- [AGENTS.md](../AGENTS.md);
- the relevant sections of [.agents/project.md](../.agents/project.md),
  especially architecture owners, async contracts, UI changes, and verification;
- [docs/architecture.md](architecture.md), sections "Accepted ownership" and
  "Changing asynchronous and persisted state";
- [the second-pass decision log](desktop-ui-second-pass.md) and
  [.interface-design/system.md](../.interface-design/system.md), for the
  visual system.

## Problems (confirmed)

### P1. Saved-lineup startup shows the Channel Setup library screen during its scan

`selectServer()` sets `stage = SetupStage.channelSetup`
(`lib/app/lineup_controller.dart:754`) **before** it runs `_loadLibraries()`
for the saved lineup (`:761-773`). The shell renders `UpstreamChannelSetupView`
whenever the stage is `channelSetup` (`lib/app/lineup_shell.dart:660`).

For the whole launch scan, the user therefore sees the "choose libraries" step,
with a scanning state and a **Cancel scan** button.

The probe confirmed it: during the launch scan, the stage is `channelSetup` and
the status is `scanning`. When the scan completes, the app moves to Ready.

Three things make it worse:

- **Longer scans.** The collection-membership and show-genre phases (B1 in
  [the previous plan](osd-autohide-and-collection-membership-plan.md)) make the
  launch scan much longer on Kometa-sized servers.
- **Stalled-looking progress.** Item progress does not advance during those
  phases, so the screen looks frozen.
- **A dead end.** Pressing **Cancel scan** leaves the user on setup with a
  cancelled scan. Continuing from there then hits P2.

### P2 (LIB-01, blocker). Restored libraries are shown as ready but cannot be committed

1. Startup's `_loadLibraries()` fills in the scan facts, so
   `libraryScanReadyIds` contains the restored libraries. It does **not**
   create the `_pendingScan`/`_pendingScanEpoch` that
   `_commitScannedLibraries()` (`:840`) requires.
2. `enterChannelSetup()` (`:1270`) only changes the stage.
3. `_libraryStep()` (`lib/app/channel_setup_view.dart:380`) offers
   **Continue with N libraries** whenever the settled ready IDs exist. That
   branch hides the scan action.
4. `commitLibraryScan()` returns false, and the UI shows "The ready libraries
   could not be saved."

The probe confirmed this. After startup reaches Ready with ready IDs
`{movies}`, `enterChannelSetup()` followed by `commitLibraryScan(readyIds)`
returns **false**. The positive control was in the original report: a fresh
`scanLibraries()` followed by a commit succeeds.

### P3 (LIB-02). The library step has no route back to server selection

The setup view has no server-return control. **Cancel** exists only when setup
was entered from Ready (`channelSetupCanCancel`). `showServers()` (`:1308`)
allows returning from the picker only when it was opened from Ready.

## Decisions

- **D1. Startup screen.** A saved-lineup startup shows a dedicated **loading
  screen**, not the setup library step. The user chose (October 7) to reuse
  the fluid lineup-creation atmosphere instead of a progress bar.
  - **Visual:** reuse `SetupResultAtmosphere` (`lib/app/setup_result_atmosphere.dart`)
    in its applying (moving) state, the same way the "Creating your lineup…"
    screen uses it. Reduce Motion must keep working.
  - **Content:**
    - a centered headline in the creation screen's style;
    - **one** quiet status line for the current phase;
    - a single text action, **Switch server**.
  - **Not shown:** no progress bar, library list, checkboxes, Continue, or
    Cancel scan.
  - **Proposed copy** (needs the user's approval at the render gate):

    | Element | Copy |
    | --- | --- |
    | Headline | "Loading your lineup…" |
    | Status: items | "Checking items · 1,200 of 5,000" (the total, if known; otherwise "Checking items · 1,200") |
    | Status: collections | "Loading collections" |
    | Status: TV genres | "Loading show details" |
    | Action | "Switch server" |

  - **Accessibility:** the status line is a polite live region. It must not
    announce every count change; announce phase changes only.
  - **Multiple libraries:** they scan concurrently. Show aggregate item
    progress while any library is in its item phase, then the enrichment phase
    of whichever library is still working.
- **D2. Startup outcomes are unchanged** apart from the screen:
  - a complete scan reaches Ready;
  - a non-complete status (empty, unsupported, partial) falls back to the
    Channel Setup library step, as today;
  - a failure falls back to server selection with the error, as today. This
    includes the existing playlist and collection-unavailable rules.
- **D3. Readiness and commit eligibility agree (LIB-01).** A library the setup
  step shows as ready must be committable.
  - **Readiness sources:** readiness comes from either a staged setup scan or
    the **committed inventory** that startup or restore loaded for the same
    profile, server, and scope.
  - **Committing from committed inventory:** continuing with any subset of the
    committed libraries must commit without rescanning. Use the committed
    media, playlist catalog, and failure facts. Apply the same
    `_requireAvailablePlaylists`/`_requireAvailableCollections` checks.
  - **Libraries outside committed inventory** still require a scan.
  - **Choose one owner, not two paths.** For example, have restoration produce
    the same staged-result shape that setup scans produce, keyed to the scan
    scope rather than a transient operation number. Alternatively, have
    `_commitScannedLibraries` accept committed inventory explicitly.
  - **Keep the protections:** do not weaken stale-result or scope protection.
    Do not clear saved state.
- **D4. An explicit rescan is always available.** When the library step is
  settled, show **Scan again** alongside **Continue**, not instead of it, so
  committed or staged libraries can be refreshed. A rescan replaces readiness
  only when it succeeds. Existing channels and preferences stay untouched until
  a reviewed plan is applied.
- **D5. Switch server (LIB-02).**
  - **Where it appears:**
    - on the library step during first setup;
    - on the library step during regeneration;
    - on the D1 loading screen;
    - when no usable libraries are found.
  - **What it does:**
    - it cancels or invalidates any running scan or restore;
    - it opens server selection;
    - it never modifies the committed lineup.
  - **Picker cancellation returns to its origin:**
    - **library step:** setup on the same server, keeping its cancelability;
    - **loading screen:** restart the restore;
    - **first setup without a lineup:** the library step.
  - **Choosing a server** uses the normal `selectServer()` flow. A late result
    from the old server must never publish into the new scope.
- **D6. Scan phase is visible in setup scans too.** The setup library step's
  scanning state shows the same phase line ("Loading collections" or "Loading
  show details") once items finish. Item progress then no longer looks frozen.

## Work units

The two units run in sequence. U2 consumes U1's controller API. The
orchestrator owns Git, the full checks, and the approval gate.

| Unit | Executor | Writes (exclusive) |
| --- | --- | --- |
| U1 Controller: restore state, LIB-01 commit eligibility, server-switch transitions, scan phase reporting | `worker` | `lib/app/lineup_controller.dart`, `lib/plex/plex_client.dart` (phase callback only), `lib/plex/plex_models.dart` if needed, `test/app/lineup_controller_test.dart`, `test/plex/plex_library_scan_test.dart`, the controller fakes in `test/app/product_spine_test.dart` and `test/support/ui_fixture.dart` |
| U2 Surfaces: loading screen, library-step actions, shell routing | `worker` | `lib/app/lineup_shell.dart`, `lib/app/channel_setup_view.dart`, a new `lib/app/lineup_restore_view.dart` (or similar), `lib/app/setup_result_atmosphere.dart` only if reuse needs a parameter, `test/app/*` widget tests, design-review captures |

### U1: Controller

1. **Restore state.** Expose a distinct, testable state for "restoring a
   saved lineup". This can be a new `SetupStage` value or an explicit flag.
   - **Lifetime:** it starts where `selectServer` currently sets
     `channelSetup` before `_loadLibraries`. It ends at Ready, at the
     channelSetup fallback, or at the servers fallback.
   - **Phase information:** include the current scan phase and aggregate item
     progress, so U2 can render D1 and D6.
   - **Exhaustiveness:** if you add an enum value, update every exhaustive
     `switch` and every stage check across `lib/` and `test/`.
2. **Scan phases.** Add a phase notification to `PlexClient.scanLibrary`
   (items → collections → show genres) next to `onProgress`. Record the phase
   per library in `LibraryScanFact` (`lineup_controller.dart:55`). Keep the
   item counters monotonic. Update the fakes.
3. **LIB-01 (D3/D4).** Make `libraryScanReadyIds`, `enterChannelSetup()`, and
   `commitLibraryScan()` agree, as D3 requires.
   - **Committed-subset commit:** committing a subset of committed libraries
     must save that selection, and must not alter channels except through the
     existing migration path.
   - **Rescan still works:** `scanLibraries` still replaces the staged result
     for an explicit rescan.
4. **Server switch (D5).**
   - Add a controller transition from setup or restore to server selection.
     It cancels scan work through `cancelLibraryScan` /
     `_invalidateOperation` and records the picker origin.
   - Cancelling the picker returns to that origin.
   - Fix `showServers`/`cancelServerSelection` so the origins are coherent.
     Today cancellation is allowed only from Ready.

**Required tests** (real `LineupController`, synthetic Plex):

- **Restore state:**
  - A saved-lineup startup is in the restore state, not `channelSetup`, while
    the scan is gated, with a phase sequence of items → collections → (TV)
    show genres.
  - It reaches Ready on success.
  - It falls back to `channelSetup` on an empty or unsupported result.
  - It falls back to `servers` on failure, including `collection-unavailable`.
- **LIB-01 regression:** the exact report sequence, `initialize` → Ready →
  `enterChannelSetup` → `commitLibraryScan(readyIds)`, returns true, keeps the
  channels, and needs no network.
- **Committed subset:**
  - Committing a subset selection saves exactly that subset.
  - Adding an unscanned library requires a scan; commit is false until one
    runs.
- **Rescan:**
  - An explicit rescan after re-entry replaces readiness.
  - A failed rescan leaves the committed lineup and saved state untouched.
- **Server switch:**
  - From the restore state, the library step during first setup, and
    regeneration: the switch cancels the scan, and a late scan result cannot
    publish.
  - Picker cancellation returns to each origin.
  - Choosing another server goes through `selectServer` with the correct
    saved state.
- **Persistence and late results:** a persistence failure during a
  committed-subset commit leaves the prior state. A logout or profile change
  during restore cannot publish.
- The existing currentness, persistence-ordering, and collection/playlist
  availability tests stay green.

### U2: Surfaces

1. **Shell routing.** Render the D1 loading screen for the restore state,
   keeping the global keys behavior that onboarding uses.
2. **Loading screen (D1).**
   - `SetupResultAtmosphere`, a headline, and a phase status line driven by
     U1's facts.
   - **Switch server** wired to U1's transition.
   - It uses the system's typography and theme roles across all four themes
     and the resolution matrix in the second-pass log. Reduce Motion gives a
     static atmosphere.
3. **Library step (D4/D5/D6).**
   - **Scan again** is visible alongside **Continue** when settled.
   - **Switch server** sits in the footer's leading area. It keeps **Cancel**
     where it exists today and does not add negative space, per the
     second-pass density rule.
   - The scanning summary shows the phase line once items finish.
4. **No-libraries state.** Its message already says "Choose another Plex
   server…". Add the **Switch server** action there.

**Required tests:**

- **Widget tests:**
  - The loading screen shows during restore and has no library list.
  - Phase text updates, and the live region announces only phase changes.
  - **Switch server** works from the loading screen and the library step.
  - **Scan again** and **Continue** are both present when settled.
  - The no-libraries state offers Switch server.
- **Real-controller wiring test:** saved-lineup startup → Generate lineup →
  **Continue** → configure, with no storage reset. The report asks for this
  because existing widget tests use setup-controller fakes.
- **Renders:** matched before/after renders at 1920×1080 and 960×720 of:
  - the restore state (each phase);
  - the library step (settled with Continue, Scan again, and Switch server);
  - the no-libraries state.

  Include one theme other than Ember & Steel. Do not update goldens without
  approval.

## Approval gate (orchestrator stops and asks the user)

Show the D1 copy, the library-step action layout, and the renders, and wait
for approval before committing U2. A golden update is not approval.

## Out of scope

- **Opening straight into the Guide** with stale data and refreshing in the
  background. Considered and not chosen.
- **Speeding up the scan itself.** The B1 launch-scan budget still applies.
  If live measurement fails it, the conditional fallback in the previous plan
  (load membership only for libraries with saved collection channels at
  launch) remains the proposal.
- **Windows 11 host provisioning** (from the report). That is the user's task.

## Verification commands (orchestrator, after integration)

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
TZ=America/New_York flutter test
```

**Windows acceptance after the fixes:**

- **First,** run the full deterministic suite on Windows. The report's two
  Windows quarantine-path fixture failures at `6977a0b8` must be shown fixed on
  the new commit.
- **Then** run the startup, LIB-01, and LIB-02 flows physically:
  - saved-lineup startup shows the loading screen, then the Guide;
  - Generate lineup → Continue → configure → review, with no storage reset;
  - Scan again, and changing the library subset;
  - Switch server from the loading screen, from the library step during first
    setup and during regeneration, during a scan, and with no libraries;
  - relaunch, confirming the lineup is intact.
- **Last,** resume the collaborative session in
  [windows-collaborative-acceptance-handoff.md](windows-collaborative-acceptance-handoff.md)
  on the new commit.

---

## Copy-ready Codex orchestrator prompt

Paste this into a new Codex chat in the LineupDesktop project at high
reasoning or above:

```text
Use orchestrate-implementation-chats to implement docs/setup-reentry-startup-plan.md.
Dispatch U1, then U2 after U1 is accepted and integrated, each to a separate
implementation chat using the `worker` preset (read .codex/agents/worker.toml and
map its model/effort onto create_thread). Each child sends its terminal
completion or blocked report back to this orchestrator chat. I authorize
creating those child chats and their callbacks to this chat, for this task only.

Source: local checkout /Users/tristan/Software/LineupDesktop, branch
codex/desktop-ui-second-pass, base c5fccffe. Local execution, no worktrees.
Preserve the existing untracked files (.claude/launch.json,
docs/design/desktop-ui/review-packets/lineup-1080p-cbf3dbd5/,
docs/reviews/test-slimming-2026-10-02/, tool/windows/__pycache__/).
Commit this plan file as a docs commit before dispatch.

Read AGENTS.md, the relevant .agents/project.md sections, docs/architecture.md
(accepted ownership; asynchronous and persisted state), and the whole plan
before dispatch. Each child packet contains the plan path, its unit section,
decisions D1–D6, source identity, write ownership and exclusions, required
tests, targeted commands (TZ=America/New_York flutter test <paths>,
dart format <changed paths>, flutter analyze), an instruction not to commit,
push or edit outside its ownership, and the callback route.

Git and integration are yours: inspect each diff against its unit contract,
adjudicate deviations, commit each accepted unit locally on
codex/desktop-ui-second-pass with a conventional message, then run
dart format --output=none --set-exit-if-changed ., flutter analyze and
TZ=America/New_York flutter test on the integrated tree. Do not push, open a
PR or merge.

Approval gate: before committing U2, show me the D1 loading-screen copy, the
library-step action layout and matched 1920×1080 and 960×720 before/after
renders (restore phases, settled library step, no-libraries state, one
non-default theme). Wait for my approval. Stop and ask me for any decision the
plan does not settle (persisted-shape change, new user-visible behavior beyond
D1–D6, removing existing protection).

After both units, run one independent read-only review of the full diff from
c5fccffe against the plan (reviewer preset or code_reviewer), adjudicate,
apply accepted findings and rerun the full checks.

Final report to me: units, executors and commits; check results; adjudicated
review findings; and the plan's Windows acceptance list as remaining work.
Do not claim Windows behavior as verified.
```
