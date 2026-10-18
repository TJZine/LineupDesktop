# macOS app audit plan (computer use)

Prepared 2026-10-18 by Claude Opus 5.5 for a Codex controller. The goal is
to exercise the real macOS app end to end through computer use and **list**
every issue worth investigating. This is a discovery task. Do not fix
anything during the audit; fixes are planned with the user afterward from the
ledger.

Read `AGENTS.md` and `.agents/project.md` first.

## 1. Inputs and expected behavior

- **Build:** the real app (`lib/main.dart`, not the test harness) from the
  current `platform/macos` HEAD (`fa176087` or later; record the exact SHA).
  Use the pinned Flutter at `/Users/tristan/.cache/lineup-flutter/3.47.7/flutter`
  and the accepted runtime `build/macos-runtime/dist/arm64`.
  - Prefer `flutter build macos --release`. If Release fails to build or
    launch, record that as an audit finding and fall back to Debug.
  - Build once, record the bundle hashes, and use that one bundle for the
    whole audit.
- **Where expected behavior comes from:**
  - `docs/user-guide.md` for intended user behavior;
  - `.interface-design/system.md` and the approved design records, including
    the Player OSD and Now Playing layout restrictions;
  - the Windows app's behavior where the platforms should match;
  - the approved macOS decisions:
    - ⌘ shortcuts and Settings via ⌘,;
    - one synchronized native fullscreen state;
    - the "Managed by macOS" HDR copy in Diagnostics, with the HDR setting
      hidden.

  If behavior differs from these sources, it is a finding. If no source
  defines the behavior, record it as a **question**, not a bug.
- **Already accepted; do not re-test:**
  - HDR and Dolby Vision brightness, flash and profile handling, verified
    physically on this laptop;
  - channel-switch latency benchmarking.

  HDR and Dolby Vision content still appears in normal flows (switching,
  tracks, seeking, fullscreen). Report only *functional* problems there:
  failures, stalls, wrong tracks, errors, wrong state.

## 2. Rules

- **Discovery only.** Don't edit product code, tests or the runtime. Small
  disposable diagnostics are fine if needed to understand a finding; keep
  them outside the tree and never merge them.
- **Accounts.** The user performs Plex sign-in and answers keychain or
  SecurityAgent prompts; pause and ask. Never change Plex account, server or
  library settings.
- **Lineups and channels are disposable.** Create, edit and delete them
  freely, with no confirmation needed for those deletions.
- **Input:**
  - Use real key events (`key` actions). Computer-use `type` proved
    unreliable for Flutter key handling; use it only for genuine text fields,
    and verify the result.
  - ⌘Q needs the system-combo grant; the app menu's Quit works without it.
- **Foreground and one copy.** Keep the app frontmost and visible while
  testing. Run exactly one Lineup copy; several bundles share the bundle ID,
  so verify the PID and executable path, and quit leftovers first.
- **Cost.** Prefer logs and short key-driven sequences, and take screenshots
  at 0.3–0.5 scale. Zoom only when you need detail.
- **Logs.**
  - Launch the binary from a shell with stdout and stderr captured to
    `/tmp/lineup-audit/app.log`.
  - Enable the in-app **Diagnostics** setting.
  - `LINEUP_PRESENTATION_LOG=1` is optional.
  - Useful lines include `[lineup-player]` (shutdown, seek landings) and
    Flutter errors or exceptions.
- **Privacy.** Screenshots and logs contain private titles, so keep raw
  evidence in `/tmp/lineup-audit/`. The committed report describes issues
  without media titles, IDs, URLs, tokens or server names, using generic
  labels such as "4K HDR movie" or "multi-part episode".
- **Robustness.**
  - On a crash or hang, record it (check `~/Library/Logs/DiagnosticReports`),
    relaunch and continue.
  - Don't retry one failing step more than twice; record it and move on.
  - Don't build new test infrastructure.

## 3. Coverage

Work through the areas in order. Within each area, try the normal path,
keyboard-only use, cancellation or Back mid-operation, and repeated or rapid
actions.

**A. First run, sign-in, profiles.**
- Launch from a clean state, if the user approves resetting it; otherwise
  test from the existing state and say so.
- Onboarding copy and flow, and the Plex sign-in handoff (link opening).
- Server and profile selection, profile picker on startup, lineup restore,
  sign-out and sign-in again.

**B. Channel setup and studio.**
- The setup steps: library, configure, review, result.
- Studio functions:
  - filters and facets (OR within, AND across);
  - inventory, playlist, manual rundown, programming, station, style and
    title;
  - recovery and air-check verification.
- Create, rename, reorder and delete channels and lineups.
- Large libraries: scan progress, cancellation, empty and failed states.
- Check that edits persist across relaunch and that a cancelled edit leaves
  no partial state.

**C. Guide.**
- Navigation in all directions, paging, Now and hour stepping, guide hours
  setting, channel search, library filter, source display.
- Info panel backgrounds (artwork, theme, bleed) and clear logos.
- Focus visibility and wrap or edge behavior.
- Selecting a program to watch, and the guide's picture-in-picture preview.
- **Guide overlay alpha** over playing video against the design reference
  (SDR content is fine).
- Behavior across a program boundary while the Guide is open.

**D. Player.**
- Tuning from the Guide, number entry plus Return, the number timeout,
  invalid numbers ("Not in this lineup"), Page Up/Down, the mini guide and
  now playing.
- The OSD: show and auto-hide timing per setting, focus, Back and Escape
  behavior.
- Audio and subtitle track lists, switching and confirmation, including
  content with no subtitles and with multiple audio tracks.
- DVR controls with the setting on (pause, seek, J/K/L, media keys) and off
  (transport keys ignored).
- Multi-part items across a part boundary, and end-of-program rollover to the
  next program, including waiting through a real program end.
- Sleep timer.
- Now-watching banner.
- Error overlay and retry. Simulate failure only by non-destructive means,
  such as briefly turning off the network; never alter the server.
- Content variety, functional only: SDR, HDR10, HLG, Dolby Vision profiles 5
  and 8, 4K, and an aspect ratio other than 16:9.

**E. Window and system behavior.**
- Resize, including live resize during playback, minimum size and video
  alignment.
- Minimize and restore.
- Fullscreen via F, the green button and ⌃⌘F, plus exit paths; check the menu
  item state stays in sync. ⌃⌘F once failed to exit fullscreen in an earlier
  test, so cover it explicitly.
- Stage Manager and Spaces.
- Window close versus Quit, and relaunch restoring state.
- Sleep and wake during playback, and network loss and recovery during
  playback and during Guide loading.
- A 12 s stop timeout was seen once; watch the logs for slow stops.

**F. Menus, shortcuts, links.**
- Every menu item.
- ⌘, Settings from every screen, including while a modal is open.
- Guide and Player shortcuts.
- ⌘ combinations ignored in the Player.
- Plex link opening.
- About, Services and Hide.

**G. Settings.**
- Every option on every page (Appearance, Guide, Playback, Accessibility,
  Account, Support).
- Each option's effect, persistence across relaunch and reset paths.
- **Diagnostics view:** content, the macOS HDR copy, export, and privacy of
  exported data. Check that no tokens or URLs leak.

**H. Accessibility basics.**
- Keyboard-only navigation of every screen, focus order, focus visibility
  with the large-focus setting, and reduce motion.
- VoiceOver labels on main controls: spot-check with VoiceOver on.
- Text scaling, if supported.

**I. Stability.**
- 45–60 minutes of continuous playback, including a program rollover.
- Sample CPU and memory every 5 minutes with `ps -o rss,pcpu -p <pid>`, then
  look for growth, stalls or audio drift.
- 30 rapid channel switches, checking for errors and stuck states.
- Quit during playback and during loading; confirm clean shutdown in the log
  and no crash report.

## 4. Severity

| Level | Meaning |
|---|---|
| **S1** | Crash, data loss, credential or privacy leak, or a stuck/unusable state with no recovery. |
| **S2** | A core flow broken or wrong (tuning, playback, schedule, persistence, sign-in) with a workaround. |
| **S3** | Incorrect secondary behavior, a design or parity deviation, or an accessibility gap. |
| **S4** | Polish: copy, layout, timing feel. |
| **Q** | A question for the user, because expected behavior is undefined. |

## 5. Deliverables

1. **Evidence:** `/tmp/lineup-audit/`, uncommitted, holding logs,
   screenshots, CPU/memory samples, and a `build-identity.json` with the SHA,
   build mode and bundle hashes.
2. **Report:** `docs/handoffs/macos-app-audit-report.md`, privacy-clean. It
   contains:
   - **Summary:** counts by severity and the top risks.
   - **Issue ledger.** One row per issue: ID, area, severity, title, exact
     repro steps, expected (with its source), actual, frequency (always,
     sometimes or once), evidence path, suspected owner (Dart, native adapter,
     shared core, runtime, design) and confidence.
     - Merge duplicates.
     - Separate observed facts from hypotheses about the cause.
   - **Coverage table.** For each area (A–I): tested, partially tested or not
     tested, with the reason. A gap must never read as a pass.
   - **Questions** for the user.
   - **A physical or human checklist,** listing only what computer use
     genuinely could not observe. This may be empty.
3. Stop after the report. Don't start fixes. Commit the report as a
   docs-only commit on `platform/macos` if the user approves; don't push or
   merge to `main`.
