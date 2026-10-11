# Windows Collaborative Acceptance: Player Timing and Collections

**Purpose:** a copy-ready Codex prompt for a guided, human-in-the-loop
acceptance session on the physical Windows 10 test machine. It covers the
changes from `docs/osd-autohide-and-collection-membership-plan.md`.

Codex screen capture and computer use do not work on this machine. The human
is the eyes and hands: Codex runs commands, reads console output, gives one
precise step at a time, and records results. The human performs each action
and reports what they saw in short text.

Paste everything below the line into a new Codex chat on the Windows machine.
Fill in the commit SHA first.

---

You are running a guided manual acceptance session for Lineup Desktop on a
physical Windows 10 machine. Computer use and screenshots are **not**
available here, so you cannot see the screen. I am your eyes and hands. You:

- run commands in your own terminal;
- read the app's console output;
- give me one step at a time;
- record what I report.

This is acceptance, not implementation. Do not change product source. If a
step fails, diagnose it read-only (source, console output, diagnostics), then
report the likely owner and a proposed fix. A source fix needs a separate
authorized task.

## Target and setup

- **Repository:** `TJZine/LineupDesktop`.
- **Branch:** `codex/desktop-ui-second-pass`.
- **Target commit:** `<full-40-character-sha>`. Fetch it, check it out, and
  confirm `git rev-parse HEAD` matches before anything else. Do not test
  any other commit. Keep HEAD fixed for the whole session. If the checkout has
  unrelated local work, stop and ask me.
- **Read first:**
  - `AGENTS.md`;
  - the relevant parts of `.agents/project.md`;
  - `docs/osd-autohide-and-collection-membership-plan.md`: decisions D1–D4,
    "B1 implemented bounds and approved live measurement budget", and
    "Acceptance outside this checkout";
  - `docs/windows-native-validation.md`, sections 1–6 and 9, plus its safety
    rules;
  - `docs/user-guide.md` for keys and settings.
- **Build and run:** use the pinned environment and the debug local-engine
  `flutter run -d windows ...` command from `docs/windows-native-validation.md`
  §6. Reuse the existing patched engine and libmpv only if they are still
  current per `docs/DEVELOPMENT.md`. Run the app from **your** terminal so you
  can read its console, including the `[lineup-player]` lines. Tell me when
  the window should appear.
- **Evidence:** keep local evidence in
  `build/native-acceptance/<sha>/REPORT.md` (untracked). Update it after every
  step, using the report template in `docs/windows-native-validation.md`.

## Safety

- Never ask me for, display, or store a Plex token, auth header, tokenized
  URL, server address, or credential-store content.
- Record no collection names, media titles, or library names. Record only
  counts, timings, Pass/Fail, and short neutral descriptions.
- If anything sensitive appears in console output or something I paste, stop.
  Tell me what to redact, and do not copy it into the report.

## How we work

For each step, send:

1. the **ID**;
2. the **setup**;
3. the exact **action**, including key names;
4. the **expected result**;
5. **exactly what I should reply with**, for example
   `2.1 pass ~4s` or `2.1 fail: OSD stayed visible`.

You may send two or three independent steps together. Wait for my reply
before anything that depends on it.

When I report something unexpected:

- ask at most two targeted follow-up questions;
- check the console output yourself;
- classify the step as **Pass**, **Fail — blocker**, **Fail — non-blocking**,
  or **Blocked/not run**.

Never mark a step Pass from code reading or tests.

Timing: I'll count seconds or use a phone stopwatch. Treat about ±1 s as
matching for OSD and cursor timeouts.

## Steps

### 0. Preparation

- 0.1 Confirm HEAD, then build and launch. I sign in and select the server
  myself.
- 0.2 In **Settings > Support**, I enable **Record redacted diagnostics**.
  In **Settings > Playback**, I set the auto-hide to **4 seconds** and turn
  **DVR playback controls** on (needed for pause and seek steps).
- 0.3 Record the Windows version, GPU, display scaling, and windowed or
  fullscreen mode in the report. Ask me for these values.

### 1. OSD and cursor timing (unit A1)

- **1.1** Tune a channel from the Guide.
  - **Do:** keep hands off the mouse and keyboard.
  - **Expected:** the OSD appears after the load and hides about 4 s later.
- **1.2** In Settings, set the auto-hide to 8 s, return to the Player
  (`Ctrl+5`), and press `Enter` to show the OSD.
  - **Expected:** it hides after about 8 s.
  - **Afterwards:** set the auto-hide back to 4 s.
- **1.3** While playing, move the mouse over the video, then stop.
  - **Expected:** the OSD shows and hides about 4 s after the last movement.
    The cursor disappears when the OSD hides, or within about 3 s of the
    mouse stopping, whichever is later.
- **1.4** Keep moving the mouse slowly for about 10 s, then stop.
  - **Expected:** the OSD stays up while the mouse moves and hides about 4 s
    after it stops.
- **1.5** Press `Space` to pause.
  - **Expected:** the OSD shows and hides after about 4 s. The cursor stays
    visible while paused.
  - **Do:** move the mouse continuously for about 8 s while paused.
  - **Expected:** the OSD stays visible until about 4 s after you stop.
- **1.6** While paused, press `C` (subtitles) or `A` (audio) and choose a
  different track.
  - **Expected:** the track panel does not suddenly change into the OSD while
    you are choosing.
  - **Report:** what happens after choosing.
- **1.7** While paused, press `Up` (Mini Guide) and wait 20 s.
  - **Expected:** the Mini Guide stays open and is not replaced by the OSD.
  - Press `Esc`, then `Space` to resume.

### 2. Keyboard-only focus hold (unit A2, decision D1)

- **2.1 Mouse, Sleep timer.** Move the mouse to show the OSD, click the
  Sleep control, and click **30 minutes**. Then leave the mouse still.
  - **Expected:** the OSD hides about 4 s later.
  - **Afterwards:** set Sleep back to **Off**.
- **2.2 Mouse, app menu.** Move the mouse, open the OSD's app menu, then
  dismiss it by clicking empty video or pressing `Esc`. Leave the mouse
  still.
  - **Expected:** the OSD hides about 4 s later.
- **2.3 Keyboard hold.** Press `Enter` to show the OSD, then press `Tab` until
  an OSD control is focused. Wait 10 s.
  - **Expected:** the OSD stays visible.
  - **Then:** move focus out of the OSD with `Esc` or `Tab`.
  - **Expected:** the OSD hides about 4 s later.
- **2.4 Keyboard Sleep.** Press `S`, choose a preset with the arrow keys and
  `Enter`, and wait 10 s.
  - **Expected:** focus returns to the Sleep control, and the OSD stays
    visible.
  - **Afterwards:** set Sleep back to **Off**.
- **2.5 Keyboard hold, then mouse.** Repeat 2.3 up to the hold, then move the
  mouse once and leave it still.
  - **Expected:** the OSD hides about 4 s after that movement.

### 3. Pause during loading (unit A2)

- **3.1** DVR playback controls are on. Tune a channel and press `Space`
  while "Preparing playback" is showing.
  - **Expected:** once the load finishes, the Player shows **paused** and the
    picture is not moving under a "playing" indicator.
  - **Then:** press `Space` again.
  - **Expected:** playback resumes.
  - Ask me to report the indicator state and whether audio played. Check the
    console for errors.

### 4. Display refresh after the redraw change (unit A3)

- **4.1** Pause, open the Mini Guide (`Up`), and watch its clock and progress
  bars for 70 s.
  - **Expected:** they still advance while paused.
- **4.2** Resume and show the OSD.
  - **Expected:** the elapsed time ticks at least once per second, and the
    progress bar moves smoothly with no flicker.
- **4.3 (optional, rough performance).** With the OSD hidden during playback
  for 60 s, I read `lineup_desktop.exe` CPU and GPU % from Task Manager.
  Repeat in the Guide with picture-in-picture.
  - Record the numbers.
  - A DevTools profile timeline needs a profile local engine. If none is
    built, mark the timeline **Blocked/not run** and say so.

### 5. Collections and channel creation (units B1–B3)

- **5.1** Before scanning, I note from Plex Web the number of collections in
  my largest movie library and my largest TV library. Numbers only.
- **5.2** Open **Channels**, start Channel Setup, select both libraries, and
  scan.
  - **Report:** the counts shown in the **Collections** and **Genres** rows,
    and any "unavailable" text.
  - **Expected:** Collections is close to the number of collections that have
    at least the minimum number of items. TV collections count episodes, so
    they can exceed upstream's show-based counts. Genres is non-zero for the
    TV library.
- **5.3** Continue to Review in **Update and add** mode.
  - **Report:** whether the TV **Recently Added** channel's Playback column
    says sequential or newest-first, rather than shuffle, and whether it has
    no "Alt" copies.
  - **Then:** apply.
- **5.4** From the Guide, tune one TV-collection channel and one channel I
  know comes from a smart collection.
  - **Expected:** each plays content belonging to that collection.
  - **Report:** pass or fail only, with no titles.
- **5.5** Run Channel Setup again in **Add as new channels** mode.
  - **Expected:** the review shows "N already in your lineup" and adds no
    duplicate channels.
- **5.6 Kometa.** After my next Kometa run, or after I trigger one, fully quit
  and relaunch.
  - **Expected:** the app reaches Ready. Collection channels still play, and
    their Guide rows aren't unavailable.
  - If startup stops with "A collection used by this lineup could not be
    loaded. Retry setup.", record it as a finding. Ask me whether a retry
    succeeds.
- **5.7 (optional, disposable data only).** If I have a throwaway test
  collection with a channel, I delete it in Plex and run **Update and add**.
  - **Expected:** a **Source not found** section lists that channel with
    **Keep** selected.
  - Choosing **Remove** needs the "I understand" confirmation.
  - Skip this step unless I confirm the collection is disposable.

### 6. Scan-time budget (live measurement)

The approved budget is in the plan's B1 budget section:

- **Budget:** the median added time must be at most
  `max(20 s, 50% of the item-only median)`.
- **Single-run limit:** no single run may add more than twice that allowance.
- **Paths:** measure launch and setup separately.

Each successful library scan records a Diagnostics event,
`plex-library: Library scan timing`. Its fields are:

- `scanPath` (`launch` or `setup`);
- `libraryType`;
- `itemsMs` (the item-only baseline);
- `collectionsMs` and `showGenresMs` (added time = their sum);
- the counts `items`, `collections`, `members`, and `shows`.

Steps:

- **6.1 Setup path.**
  - Select only the largest library and run the Channel Setup scan 6 times;
    discard the first as a warm-up.
  - Each time, I open **Diagnostics** (`Ctrl+4`) and read you that
    library's latest timing values. I can also use the copied support report,
    but I'll paste only the `Library scan timing` lines.
  - Check that `items` is identical across samples.
- **6.2 Launch path.**
  - I fully quit and relaunch 6 times (the first is a warm-up). Saved
    channels must exist, so the launch scan runs.
  - Each time, I read the `scanPath=launch` values for the largest library.
- **6.3 Concurrent.** Repeat 6.1 once with my normal selection of libraries.
  Report it separately; it shows contention for the shared collection
  request cap.

Compute per-path medians and maximums, give a pass/fail verdict against the
budget, and record the route class (local or remote) if I know it. If either
path exceeds the budget, stop and report it. Do not change the launch policy.
The plan names a conditional fallback for the user to approve.

### 7. Live Plex probes

These settle open hypotheses. Write a PowerShell script at
`build/native-acceptance/<sha>/plex-probes.ps1` for **me** to review and run
in **my own** PowerShell window.

- It reads `$env:LINEUP_PROBE_SERVER` and `$env:LINEUP_PROBE_TOKEN`, which I
  set myself.
- It sends the token only in the `X-Plex-Token` header, never in a URL, and
  requests `Accept: application/json`.
- It never echoes either value.
- It prints **only counts and booleans**: no titles, keys, URLs, or paths.
- I paste you its output.

Probes:

- **7.1 Movie tags.** For 20 movies from the largest movie library, compare
  the lengths of `Role`, `Genre`, `Director`, and `Collection` in
  `/library/sections/{id}/all?type=1` against `/library/metadata/{key}`.
  - **Print:** per tag, how many items have a shorter list in `/all`.
- **7.2 Episodes.** For 20 episodes from the largest TV library
  (`/all?type=4`), count how many carry `Genre`, `Role`, `Director`,
  `studio`, and `Collection`.
- **7.3 Children paging.** For the largest collection (by `childCount`
  from `/all?type=18`), request `/library/collections/{key}/children`
  with `X-Plex-Container-Start=0` and `Size=50`, then `Start=50`.
  - **Print:** the returned `size`, `offset`, and `totalSize`, and whether
    the server honored the requested size.
- **7.4 Smart collections.** From `/all?type=18`, print the total count, the
  count with `smart=1`, and how many of the smart ones carry `childCount`.
- **7.5 Cast portraits.** Sample 20 movies (`/all?type=1`) and 20 episodes
  (`/all?type=4`), and fetch the same items from `/library/metadata/{key}`.
  For each response, count `Role` entries by `thumb` class using exactly
  these labels:
  - missing;
  - PMS metadata path (a path under `/library/metadata/`);
  - metadata-static host (`https://metadata-static.plex.tv`);
  - other HTTPS;
  - HTTP;
  - other.

  Print counts for every class for each sample type (movies and episodes) and
  each endpoint (`/all` and `/library/metadata`). For `other HTTPS`, print
  only the aggregate count within each sample/endpoint bucket; do not group by
  or print any host name. Do not print the source `thumb` values themselves,
  names, URLs, or paths. This preserves the `/all` versus metadata comparison
  while settling why Now Playing cast portraits show the fallback (see P5 in
  `docs/player-guide-polish-plan.md`).

Show me the script before I run it, and point out where the token is used.

## Finish

1. Complete `REPORT.md`:
   - every step ID with its classification;
   - the scan-budget table and verdict;
   - the probe results;
   - findings, each with its likely owner (file or unit) and a proposed fix.
2. Read the whole report for redaction.
3. Give me a short, redacted summary to paste back to my other assistant:
   - the commit tested;
   - each step's result;
   - any failures, each with its owner and a proposed fix;
   - the budget verdict per path;
   - the probe answers;
   - anything Blocked/not run and why.
4. Do not commit, push, open a PR, or merge.
