# Windows acceptance handoff for the desktop UI second pass

Status: prepared on macOS; Windows acceptance has not run. Portable checks
(format, analyze, the full Dart/widget suite, the tracked design-review capture
harness and the F8 1080p→2160p geometry probe) passed on macOS. They establish
layout and contract facts only; none substitutes for the physical observations
below.

## Target

Test the current tip of `codex/desktop-ui-second-pass` at the time the run
starts, unless the user names a different full SHA. Review fixes may add
commits after this handoff was written, so do not assume any SHA recorded
here. Resolve the target once, set `$TargetCommit` to that full SHA, keep the
checkout fixed for the whole run, and record it. If the branch moves during the
run, finish or stop on the recorded SHA and report which scenarios a newer
commit would need repeated.

The branch is based on `codex/libmpv-reference-security-report`, whose own
[Windows handoff](../workflow-remediation-2026-10-04/WINDOWS_HANDOFF.md) has
also not run. Ask the user whether this run should also cover that handoff's
changed scenarios on the same target; they share the build, campaign and report.

## Authority and procedure

Follow, in order:

1. [Windows native acceptance](../../windows-native-validation.md): sections 1–5
   (paths, clean exact baseline, deterministic checks, pinned runtime/patched
   engine, local SDR smoke), then the Plex and media campaign as the user
   requests.
2. [Development](../../DEVELOPMENT.md) for prerequisites and commands.
3. This handoff for the second-pass scenarios.

What the second pass changed and why is in
[the decision log](../../desktop-ui-second-pass.md) (F1–F8, families,
"Implementation contracts"). Use it to judge expected behaviour; do not reopen
design decisions. Report a mismatch as a finding.

Rules carried from the campaign: the operator supplies Plex credentials,
protected-profile PINs, media, HDR and visual judgments, and approves
fullscreen, high-DPI, multi-monitor and gamepad testing. Keep credentials,
tokenized URLs, private media details and personal paths out of shared
evidence; redact every log and screenshot before sharing. No product edits,
push, merge or publication are authorized by this handoff; a needed fix is a
separate task.

Before launching the new build against an existing install, back up the
current app state directory so persistence results are reversible.

## Display configurations

Run the scenarios marked "matrix" on as many of these as the hardware allows;
record each monitor's model, resolution, Windows scale, HDR state and refresh
rate. Mark unavailable configurations Blocked/not run.

| ID | Configuration |
| --- | --- |
| D1 | 1920×1080 at 100% |
| D2 | 2560×1440 at 100% (and 125% if available) |
| D3 | 3840×2160 at 100% |
| D4 | 3840×2160 at 150% (same structure as D2 is expected) |
| D5 | A window resized to about 1280×720, and about 1366×768 |
| D6 | 16:10 (1920×1200 or 2560×1600) and ultrawide (3440×1440) if available |
| D7 | Two monitors with different scale factors, moving the window between them |
| D8 | Windows text size at 150% (Accessibility › Text size), on D1 |

## Scenarios

### A. Root scaling and native video geometry (F8, phase 1) — matrix

| Scenario | Distinguishing observation |
| --- | --- |
| Player windowed and fullscreen | Video fills exactly its intended area: no half-size, offset or doubled-scale picture; OSD and overlays sit on the picture edges; the progress lane meets the bottom edge |
| Guide PiP | The live picture fills the PiP aperture exactly, including after scrolling the Guide and changing focus |
| Video behind Settings | Opening Settings during playback keeps the picture aligned with its area |
| Resize, maximize, restore, minimize | Video and UI stay aligned through each change and after restore; no stale rectangle |
| Cross-monitor move (D7) | After moving between scale factors, video, overlays and the Lineup menu anchor stay aligned |
| Structure across sizes | Same layout structure at D1–D4 (D4 matches D2); below 1536×864 the canvas reflows rather than shrinking text further; 16:10 extends backgrounds and the Guide information area, not the five Guide rows; Guide alone shows more time when wider |
| Lineup menu anchor | The menu opens directly under its top-left button on every surface at every configuration |

### B. Artwork, text input and typography (phases 1–2) — matrix

| Scenario | Distinguishing observation |
| --- | --- |
| Artwork decode | At D3 and D4, Guide backdrop/bleed, Now Playing poster, title art and cast photos are sharp, not upscaled from a lower-resolution decode |
| IME and caret | In Guide search, Channels search and a Studio name field, the Windows IME candidate window and emoji panel (Win+.) open at the caret at D1, D3 and D4; typed text lands where expected |
| Instrument Sans width | Titles render narrowed (Guide cells and OSD about 90%, page titles 92%, program title 88%) and match the macOS captures' proportions; no fallback to a system font for Latin titles |
| Non-Latin fallback | Rename a custom channel in Studio to Cyrillic, Greek, Vietnamese and Japanese test names: titles fall back to Inter (first three) and a system font (Japanese) with no missing-glyph boxes; restore names afterwards |
| Text size 150% (D8) | Guide cells ellipsize within their bounds; the time line drops before the title shortens; the now-line draws beneath text; toolbars and the Player action group wrap as whole groups rather than truncating |

If the width axis renders poorly on Windows, record it with a redacted crop;
the locked fallback is static font instances (a separate fix task).

### C. Player overlays and transparency (phase 9)

Use bright SDR content (daylight or white backgrounds), dark content, and HDR
content on an HDR display with Windows HDR on and off. Test each overlay at all
three Settings › Appearance › Player overlays levels (More transparent,
Standard, Reduce transparency).

| Overlay | Distinguishing observation |
| --- | --- |
| Collapsed OSD | Title, status, time, actions and Up next are readable over bright footage at Standard and Reduce; More transparent is lighter and may be harder to read (expected; record the judgment) |
| Expanded Now Playing | `I` or `Down` expands the same bottom panel upward; `I`, `Enter`, Close or Esc/Back collapses it; the video picture does not move or resize while expanding or collapsing; poster, metadata, chips (including HEVC), synopsis and cast with roles are readable |
| Mini Guide, track drawers, sleep popover | Readable at each level; the subtitle list scrolls below its header and the focused row is fully visible |
| Channel bug notices | Typed channel numbers show in the bug with the target channel; an unknown number reads "Not in this lineup" and fades without interrupting playback; buffering text appears in the bug after about two seconds |
| Playback-stopped slate | Fully opaque at every level; Retry, Browse channels and Close work |
| HDR | No overlay looks washed out, crushed or shifted in colour with HDR on; record the display and any tone-mapping observations |
| Setting persistence | The chosen level survives relaunch |

### D. Input and focus

| Scenario | Distinguishing observation |
| --- | --- |
| Focus visible | Mouse use shows hover fills and no focus ring (including drawers opened by click); the first arrow or Tab key shows the ring; moving the mouse hides it while keeping position. The Guide's focused cell stays visible for both |
| Large focus indicators | Thicker rings when enabled, keyboard only |
| Remote/gamepad and assistive technology | If available: navigation reaches every OSD action, drawer row, menu item and slate action; Narrator announces the expanded panel, notices and slate |

### E. Persistence and upgrade

| Scenario | Distinguishing observation |
| --- | --- |
| Upgrade from the previous build's state | Existing settings, channels and profile load without quarantine; Player overlays reads Standard and Show channel sources is off |
| Retired theme | A state file whose theme is `glass` (from an earlier build, or a backed-up copy edited only in the disposable test state directory) loads as Ember & Steel with all other preferences kept |
| Theme renames | Settings lists Ember & Steel, Slate & Pine, Mint Noir and Satellite Blue; a saved Satellite Blue or Mint Noir choice survives relaunch; Satellite Blue's focused Guide cell is solid gold with dark text |
| Show channel sources | Off by default; turning it on restores each channel's source line in the Guide and survives relaunch |

## Evidence and report

Store local evidence under `build/native-acceptance/<tested SHA>/` and use the
campaign's report template. Classify every scenario as Pass, Fail — blocker,
Fail — non-blocking, or Blocked/not run, with the display configuration and the
mechanism used. Attach only redacted crops where a visual judgment matters
(alignment, sharpness, legibility). Share a sanitized summary that names the
tested SHA, machine, displays and any scenarios a later commit must repeat.
