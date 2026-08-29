# Lineup Desktop User Guide

**Status:** Pre-release guidance for private Windows testers and portable
Flutter UI evaluation.

Lineup Desktop builds scheduled virtual television channels from a Plex library
and presents them through a desktop Guide and Player. This guide describes the
current Flutter-native application. It does not apply to the historical
Electron implementation preserved on `electron-ui`.

## Before you start

| Requirement | Current expectation |
| --- | --- |
| Operating system | Windows 10 or Windows 11, x64, for native playback and packaged testing |
| Graphics runtime | A current GPU driver or Vulkan Runtime that provides `vulkan-1.dll` |
| Plex | A Plex account and a reachable Plex Media Server with accessible movie or TV libraries |
| Build | A complete private portable package supplied by the maintainer; no public release is available yet |
| Network | Access to Plex authentication and to the selected Plex server, directly or through an available remote/relay connection |

macOS 12 or newer can run the portable Flutter application for UI and workflow
development, but media playback is intentionally reported as unsupported.

## Install a private Windows build

1. Obtain the package and its SHA-256 hash directly from the maintainer.
2. Verify the archive hash before extracting it.
3. Extract the entire archive to a normal user-writable directory.
4. Read `SYSTEM-REQUIREMENTS.txt` and `BUILD-INFO.txt` in the package.
5. Launch `lineup_desktop.exe`.

Do not move only `lineup_desktop.exe`; the adjacent DLLs and `data` directory
are part of the application. Do not run Lineup Desktop as Administrator.

A private pre-release build may be unsigned. Proceed past an operating-system
warning only when the package came through the expected private testing channel
and its hash matches the maintainer-provided value.

## First-run setup

### 1. Link Plex

Select **Sign in to Plex**. Scan the displayed QR code or visit `plex.tv/link`
on another device and enter the four-character code. The screen shows the
remaining expiration time.

When a code expires or Plex rejects or cannot complete the current link
attempt, Lineup stops waiting and presents **Request a new code**. If secure
credential storage cannot be confirmed, use **Retry secure cancellation**
before starting another attempt. Cancelling sign-in removes the pending
credential state before returning to the welcome screen.

### 2. Choose a Plex Home profile

Select the person who is watching. Protected profiles open a four-digit PIN
keypad and also accept number-row or numpad input.

Profile cards show `PIN`, `Admin`, and `Restricted` only when the current Plex
Home response establishes those facts. `Active` identifies the currently
selected profile when the picker is reopened; it is not a focus indicator.

The profile determines the secure credential scope, selected server, saved
lineup, and related persisted state. Switching profiles does not intentionally
reuse another profile's server or lineup.

### 3. Select a Plex Media Server

Choose a discovered server. Lineup prioritizes usable direct connections before
relay connections. Each card distinguishes an owned server from a shared one
and lists the secure direct-local, direct-remote, and relay connection types
currently available. Only the selected server shows its measured path and
latency; 100–499 ms is labeled **Slow**, 500 ms or more is **Very slow**, and a
relay is labeled **Limited** rather than failed.

Plex supplies each discovered server with its own PMS credential, separate from
the Plex.tv account or Home-profile credential. Lineup keeps that server
credential only for the running session and uses it only to contact that PMS;
it is not saved in application state or shown in the interface.

When no server appears:

- confirm Plex Media Server is running and reachable;
- select **Retry discovery**;
- switch profiles when the expected server belongs to another profile; or
- clear the saved server when a previous selection is no longer valid.

### 4. Confirm audio behavior

The current Desktop audio step confirms that Lineup uses the
system-selected output. On Windows, libmpv/FFmpeg decodes supported audio tracks,
including TrueHD and DTS-family formats, to that output, normally as PCM;
bitstream passthrough is not required for playback. Device selection and
passthrough controls remain hidden because the application does not yet own a
truthful native device/bitstream contract.

### 5. Build the initial lineup

Channel Setup has three stages:

1. Select the movie and TV libraries Lineup may use.
2. Configure channel strategies, ordering, build mode, and limits.
3. Review the proposed changes before applying them.

Available strategy families include Plex playlists, collections, recently added
content, genres, decades, studios, actors, and directors. Depending on the
strategy, channels can be generated per library or across selected libraries.

The review step applies the accepted plan atomically. Cancelling or a failed
save preserves the previous lineup.

Scanning selected libraries reports completed pages and items on each library
card, including the Plex total when supplied, and can be cancelled while it is
running. Each card distinguishes not scanned, scanning, complete, empty,
unsupported, failed, and cancelled outcomes. Cancellation or failure preserves
the previous selection and media; retry repeats the one atomic selected-library
scan. Playable media requires both a positive duration and a usable media part.

The strategy step reports the accepted proposal count or **No matches** for
each enabled source family and **Off** for disabled families. The review step
separates **Create**, **Update**, **Unchanged**, **Remove**, and **Final** counts
using the selected replace, append, or merge behavior. It presents the current
lineup changing to the final lineup, a proportional composition bar, and sample
channels. Replace mode requires an explicit confirmation before building. A
limit warning appears only when ideas were actually omitted by the channel cap
or available channel numbers.

## Main destinations

| Destination | Purpose |
| --- | --- |
| Guide | Browse the schedule, inspect focused programs, filter by library, jump to now, tune current programs, and open the Player |
| Channels | Generate a lineup or create, inspect, duplicate, edit, and delete individual channels |
| Settings | Configure themes, Guide behavior, accessibility, Plex profile/server selection, and diagnostics |
| Diagnostics | Review bounded, redacted support events from the current session |
| Player | Watch the tuned channel and use playback, track, channel, sleep, and fullscreen controls |

**Windows playback acceptance:** the owner reports that native Player, Classic
PiP/Overlay, and fullscreen work at a surface level. The complete exact-commit
physical matrix is still pending, so broad format/HDR/device/package wording
remains provisional rather than unsupported-by-design.

Guide and Player use an immersive layout. Open the **Lineup** menu from either
surface to reach the other destinations. Channels and Diagnostics use the
persistent management rail. Settings uses one immersive category rail and,
when playback is active, keeps the same Player surface behind it.

## Guide

Lineup distinguishes four identities that may be visible at the same time:

- **Focused**: the program currently being inspected with the keyboard, remote,
  or pointer.
- **Selected**: the explicit program selection.
- **Tuned**: the channel currently playing.
- **Airing**: the program whose schedule includes the current time.

Moving focus does not retune playback. Activating a currently airing program
tunes its channel and closes the Guide to the Player.

The default **Classic with PiP** layout keeps the schedule primary and displays
the active video in a responsive picture-in-picture area. The optional
**Overlay** layout keeps the Guide over full video. Both layouts retain a
single Player and playback session.

Use the library selector in the Guide toolbar when **Library filters** are
enabled. **Jump to now** returns the time window and focus to the current
schedule.

The default Guide uses a detailed two-hour window and comfortable rows so its
visual scale stays close to the webOS Guide. A three-hour **Wide** option and
the preserved 4, 6, 8, and 12-hour desktop ranges are available when more of
the schedule matters than cell detail. Compact rows remain available as a
desktop override.

Focused program cells reveal long titles with a slow ticker; unfocused cells
remain stable and ellipsized. Reduce Motion disables the ticker. The program
information area can use artwork-derived color bleed, the current theme, or a
Plex backdrop, and can prefer Plex clear title logos when available. Missing
logos and artwork fall back to text and themed surfaces.

## Player

Move the pointer or click/tap the Player to show the on-screen controls. The OSD
uses a responsive shallow broadcast layout at 1280×720 and 1920×1080. The
channel bug is in the top-right. When **Prefer official title artwork** is
enabled, the lower-left/lower band uses official Plex title artwork when
available. When the preference is disabled, or the artwork is missing or fails
to load, it falls back to text. Secondary actions sit in the lower-right. The
timeline tier immediately above the edge-to-edge progress line shows
`current / total • time left` on the left when duration is known and
`Up next • scheduled start • title` on the right. Metadata and actions are
restrained, and the progress line is anchored to the absolute bottom. By
default, the **DVR playback controls** setting is off: transport buttons are
hidden and Player-local pause/play, seek, stop, rewind, and fast-forward
keyboard/media shortcuts are blocked. Page Up/Page Down channel surfing,
number entry, Guide/Mini Guide tuning, tracks, sleep, menu, and fullscreen
remain available. Enabling **DVR playback controls** restores the transport UI
and those shortcuts; it changes Flutter presentation/input policy only, not
native or libmpv behavior. It provides:

- current channel and program information;
- playback position; seeking when DVR playback controls are enabled;
- previous channel, play/pause, and next channel when DVR playback controls are enabled;
- available audio and subtitle tracks;
- sleep timer state;
- fullscreen entry and exit.

Unavailable tracks or unsupported native actions remain disabled rather than
showing controls that cannot work. The Guide retains the catalog media facts it
displays, including resolution, dynamic range, and audio facts. Rich Now
Playing retains detailed source/runtime resolution, video codec, HDR, and
hardware-decoder facts when available rather than repeating those facts in the
default OSD.

Press `I` for persistent rich Now Playing details without leaving playback.
The details surface keeps the shared top-right channel bug, then uses the
current scheduled program for title/episode identity, synopsis, year and
genres, concise rating/resolution/dynamic-range/audio badges, poster, and
official title artwork. When **Prefer official title artwork** is enabled, an
available Plex
clear logo leads the identity and text remains the fallback when the logo is
missing, disabled, or fails. Its playback line is shown only for facts that are
available: source/runtime details are separate, and actual native playback
position/duration are preferred, with schedule timing used when native duration
is unavailable. When Plex supplies cast facts, actor portraits appear between
the synopsis and progress, with names and roles available to accessibility.
Missing or failed headshots use a neutral person silhouette, never fabricated
initials, and no cast space is reserved when cast facts are absent. Up Next and
secondary actions remain owned by the OSD. Pointer movement leaves this reading
surface open. Press `I` or Back
to close it; `Down`, `Enter`, click/tap, or a successful enabled transport
action replaces it with the OSD, while a failed action retains the safe error
surface. `A` or `C` opens the requested track list directly when that track type
is available.

The mini Guide displays a bounded group of nearby channels without leaving
playback. Selecting a row replaces the current tune through the same Player
owner.

When one Plex item contains sequential media parts, Lineup continues through
them under the same tune. When DVR playback controls are enabled, progress and
cross-part seeking use aggregate timing only when the required part durations
are known; otherwise the Player shows the current part's timing rather than
estimating missing boundaries.

The timed OSD and mini Guide remain open while keyboard focus is inside their
controls. Leaving the active overlay restarts its full timeout. Reduce Motion
removes Player overlay transition time, and audio/subtitle panels initially
focus the selected track (or **Off** when no subtitle is selected). These
behaviors are deterministically tested in Flutter; physical Windows
screen-reader and assistive-technology validation remains pending.

The committed 1280×720 macOS goldens cover Flutter composition, including the
rich Now Playing surface and its synthetic artwork. They do not prove Windows
native video layering, DPI/fullscreen behavior, keyboard or screen-reader
support, media compatibility, or package readiness; those remain physical
Windows acceptance work at the exact tested commit.

## Keyboard and remote controls

Media and remote keys depend on what the operating system and input device
report to Flutter.

| Context | Action | Keys |
| --- | --- | --- |
| Management screens | Move between controls | `Tab` / `Shift+Tab` |
| Management screens | Activate focused control | `Enter` or `Space` |
| Anywhere in the ready app | Open Guide / Player / Settings | `Ctrl+G` / `Ctrl+P` / `Ctrl+,` |
| Anywhere in the ready app | Open destination 1-5 | `Ctrl+1` Guide, `Ctrl+2` Channels, `Ctrl+3` Settings, `Ctrl+4` Diagnostics, `Ctrl+5` Player |
| Anywhere in the ready app | Open Settings directly | `F3` |
| Guide | Move between channels | `Up` / `Down` |
| Guide | Move between scheduled programs | `Left` / `Right` |
| Guide | Move by a visible page | `Page Up` / `Page Down` |
| Guide | Jump to the current time | `Home`, `P`, or Media Play |
| Guide | Select/tune a currently airing program and open Player | `Enter`, numpad `Enter`, `Space`, or Select |
| Guide | Close Guide to Player when playback exists; otherwise open the Lineup menu | `Esc`, `Backspace`, Back, `G`, or `F2` |
| Player | Open full Guide | `G` or `F2` |
| Player | Show mini Guide | `Up` |
| Player | Show OSD / rich Now Playing | `Down` or `Enter` shows OSD; `I` toggles rich Now Playing details |
| Player | Seek backward/forward | `Left` or `J` = 10 seconds back; `Right` or `L` = 30 seconds forward (DVR playback controls on) |
| Player | Play or pause | `Space`, `K`, or Media Play/Pause (DVR playback controls on) |
| Player | Previous/next channel | `Page Up` / `Page Down` |
| Player | Enter a channel number | Number keys; confirm with `Enter` while the entry overlay is open |
| Player | Audio / subtitle tracks | `A` / `C` |
| Player | Sleep timer | `S` |
| Player | Toggle fullscreen | `F` or `F11` |
| Player | Close the active overlay; otherwise return to Guide | `Esc`, `Backspace`, or Back |
| Mini Guide | Browse nearby channels | `Up` / `Down` |
| Mini Guide | Move seven channels | `Page Up` / `Page Down` |
| Mini Guide | Tune focused channel | `Enter`, `Space`, or Select |
| Mini Guide | Open full Guide | `Right` |
| Mini Guide | Close | `Esc`, `Backspace`, or Back |

Dedicated media transport keys are context-sensitive. In the Player, Media
Play, Pause, Stop, Rewind, and Fast Forward are handled when available only with
**DVR playback controls** enabled. In the Guide, Media Play jumps to the current
time regardless of that setting. Page Up/Page Down, number entry, Guide/Mini
Guide tuning, tracks, sleep, menu, and fullscreen also do not depend on the
setting. The timed OSD follows the configured 2–15 second auto-hide duration.

## Channels

**Generate lineup** is the bulk workflow. It proposes generator-owned channels,
then lets you replace generated channels, add generated channels, or refresh
matching generated channels after review. All three modes preserve every custom
channel. Refresh also preserves a matching generated channel's number, visible
name, schedule anchor, and shuffle identity while updating its generated
programming recipe. Completion offers **View lineup** or the separate **Add a
custom channel** action.

**New channel** opens the full-page Channel Studio for one custom channel.
Studio also opens when you edit a custom channel, inspect a generated channel,
or choose **Duplicate as custom** from generated inspection. Generated
programming remains read-only, but its name and number can be saved with **Save
identity**. Duplication creates a separate custom draft with a new identity and
the lowest available channel number; it does not alter the generated source.

Custom Studio programming can use one selected library, one Plex video
playlist, a collection or supported metadata filter, or an explicitly ordered
hand-picked list. Search, local facets, visible-result bulk selection, and Move
earlier/Move later controls keep large hand-picked lists usable without a
network request per edit. A previously saved hand-picked item that is not in
the current playable inventory remains labeled **Unavailable — retained until
removed**; it is not scheduled, but Studio does not silently delete it.

Playback rhythms are **In order**, **Mix it up**, and **Mini-marathons**.
Mini-marathons uses blocks of 2 through 5 episodes and requires usable show
grouping. **Air Check** uses the same content resolver and deterministic
scheduler as Guide and Player to show what is on now, what follows, cycle and
timing facts, why content was included, and actionable unavailable or invalid
states. A new channel saves the same schedule anchor and shuffle identity that
Air Check previewed.

Saving and tuning are separate. A successful save leaves Studio in a clean
saved state and enables **Tune in**. A tune failure does not undo the saved
channel. A save failure preserves both the prior lineup and the complete draft;
retry after correcting the reported source, schedule, number, or storage issue.
If the underlying channel changed while Studio was open, reload it or
deliberately reapply the draft rather than overwriting newer state. Leaving a
dirty draft asks whether to discard changes or keep editing.

Deletion requires confirmation and cannot be undone. Deleting a generated
channel also warns that a later Generate lineup refresh may propose it again.

## Settings

| Category | Current controls |
| --- | --- |
| Appearance | Ember & Steel, Slate & Pine, Swiss Minimal, DirecTV Classic, and Glassmorphism themes |
| Guide | Classic with PiP or Overlay presentation; detailed 2-hour, wide 3-hour, or desktop-extended 4/6/8/12-hour windows; 0-180 minute past window; comfortable or compact rows; color-bleed/theme/artwork information backgrounds; official title artwork preference; library filters; Now Playing context; 2-15 second OSD auto-hide; optional DVR playback controls |
| Accessibility | Reduce motion across management, Guide, and Player transitions; larger keyboard/controller focus indicators |
| Account | Switch Plex Home profile, switch or clear Plex server selection, and optionally show the profile picker at startup |
| Support | Enable or disable bounded redacted diagnostic recording |

Settings save immediately. When persistence fails, the previous value remains
active and the screen shows an error.

## Diagnostics and safe support reports

Diagnostics are disabled by default. Enable **Record redacted diagnostics** in
**Settings > Support** before reproducing a problem that needs support context.

The application stores diagnostic context only from a small allowlist of
bounded structured facts; arbitrary exception and native message text is not
recorded. It also redacts known credentials, authorization headers,
token-bearing URLs, and private paths as defense in depth. Diagnostics may
still describe private activity, so review them before sharing anything:

1. Inspect every line and screenshot.
2. Remove private media titles or account details that are not needed.
3. Never include a Plex token, authentication header, tokenized URL, or
   credential-store content.
4. Include the source commit or package `BUILD-INFO.txt`, Windows version, GPU
   and driver, display resolution/scaling, connection type, and exact
   reproduction steps.

Use the repository bug-report template for ordinary issues. Report
vulnerabilities only through the private process in
[SECURITY.md](../SECURITY.md).

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Plex link code expired | Select **Request a new code** and complete linking before the new timer expires. |
| No Plex servers found | Confirm the server is online and reachable, retry discovery, switch profile, or clear a stale saved server. |
| The app reports playback unsupported on macOS | This is expected. macOS currently supports portable UI development, not native playback. |
| Windows reports that `vulkan-1.dll` is missing | Install or update the GPU vendor's current driver or an appropriate Vulkan Runtime. Do not copy a driver DLL from another machine into the package. |
| Audio plays but video is black or hidden | Record the exact window size, display scaling, fullscreen state, Guide layout, whether audio continues, and whether the problem follows a resize/minimize/restore transition. Treat this as a native-composition failure and report it with the current commit. |
| A replacement channel leaves stale audio/video | Stop testing that scenario, record both channel transitions and timestamps, and report it as a native playback-lifetime failure. |
| A setting or lineup change fails | The previous state should remain. Retry after confirming the Plex server and local storage are available. |
| A banner says saved app data was corrupt | Lineup moved malformed or schema-invalid state aside and started with empty state. Dismiss the banner after reviewing the resulting setup. Other storage read failures stop startup instead of resetting data. |
| A private portable package does not launch | Verify the complete package was extracted, `SYSTEM-REQUIREMENTS.txt` is satisfied, the archive hash matches, and the GPU driver supplies `vulkan-1.dll`. |

## Known limitations

- There is no supported public installer, updater, or release channel.
- Windows native playback and packaging have not yet completed the full
  physical acceptance matrix on the current branch.
- macOS playback is intentionally unsupported.
- Audio-output selection and passthrough controls are not exposed.
- The native player deliberately has no application codec/container/HDR
  allowlist. Representative codec, HDR, TrueHD/DTS-to-PCM, text/image subtitle,
  multi-monitor, and high-DPI coverage remains deeper validation work rather
  than a reason to force browser-style transcode, subtitle burn-in, or a
  passthrough decode gate.
- Alternate Plex media-version selection and failed/cancelled Home-profile token
  compensation remain later work. Sequential parts of the selected version are
  implemented and deterministically tested.
- Gamepad, signing, and clean-system package coverage remain later release work.
- Pre-release behavior and persisted state may change before the first public
  version.
