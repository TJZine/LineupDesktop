# MVP release acceptance

This is the maintainer's final pass for one exact released asset per platform.
Use the downloaded signed APK or CI-produced Windows ZIP selected by
[release security](release-security.md), not a rebuild. Record the source SHA,
asset SHA-256, version, signer or unsigned status, device/host identity, row
result, and blocker or limitation. Do not record tokens, server addresses,
private media titles, or unredacted diagnostics. See [Android runtime](android-runtime.md),
[Windows native acceptance](windows-native-validation.md), and the [platform support page](reference/platforms.md)
for detailed platform context.

## Android TV, Google TV and Fire TV

Use a Fire TV Stick 4K Max on Fire OS 8 with 32-bit userland and one Google
TV/Android TV device. The exact signed APK must already have passed independent
identity, alignment, and certificate verification.

| ID | Class | One-pass observation |
| --- | --- | --- |
| A-01 | blocker · automated | Verify the exact APK's package, version, alignment, and signer with the command in [release security](release-security.md). |
| A-02 | blocker · device | Before upgrading, record the installed production `versionCode` and signer: `adb shell dumpsys package com.tjzine.lineup \| grep -E "versionCode\|signatures"`. |
| A-03 | blocker · device | On Fire TV, upgrade over the existing install with `adb install -r` without `-d`. Confirm lineup and sign-in remain. |
| A-04 | blocker · device | On Google TV or Android TV without Lineup, install the APK and complete code sign-in, protected-profile PIN, server selection, channel setup, Guide, representative Direct Play playback, channel up/down, Back/Home, and resume. Use Downloader to reinstall the same APK without uninstalling. Confirm lineup and sign-in remain. |
| A-05 | blocker · device | On Fire TV, time the largest real library scan and confirm it finishes without an app-not-responding dialog. Enable diagnostics and record **Library scan budget usage** with numeric `bytes`, `entries`, `requests`, and `elapsedMs`, plus `adb shell dumpsys meminfo com.tjzine.lineup`. Confirm at least 3× headroom against the defaults (1 GiB, 1,500,000 entries, 20,000 requests, 30 minutes). Report shortfalls before changing a limit. |
| A-06 | blocker · device | While playing media, switch profile. Repeat with sign-out as a separate scenario. Audio and video must stop before the next screen appears in both cases. |
| A-07 | blocker · device | With an active sign-in and a saved lineup, force-stop and relaunch. Confirm profile, server, and lineup restore without re-login. |
| A-08 | polish · device | Try media expected not to play, such as DTS-only audio on a device without that decoder. The error must be clear and recoverable. |

For A-04 through A-08, record only the facts needed to reproduce the result.
The scan budget summary measures scan work. Use the separate memory reading
to record heap and process memory.

## Windows clean host

Use a new local standard user on the laptop, or the assigned media PC. The
Windows MVP package is unsigned. Preserve the exact downloaded ZIP and its
whole-asset digest.

| ID | Class | One-pass observation |
| --- | --- | --- |
| W-01 | blocker · device | Record Smart App Control state and Windows version. If Smart App Control is on, record the block, leave it on, and run W-02 through W-08 on a host where it is off. |
| W-02 | blocker · device | Download the exact draft ZIP in Edge while signed in to GitHub. Verify `Get-FileHash -Algorithm SHA256 .\FILE.zip` against the release `.sha256` asset and notes; inspect the ZIP's `Zone.Identifier`. |
| W-03 | blocker · device | Use Explorer **Extract All**. Confirm the extracted EXE has `Zone.Identifier`, record the SmartScreen dialog and **Run anyway** path, and confirm Defender does not quarantine a file. Smart App Control blocks unknown unsigned code by default and has no per-app exception. |
| W-04 | blocker · device | Complete first run, including browser sign-in at `plex.tv/link`, protected-profile PIN, server selection, library scan, channel setup, and Guide. |
| W-05 | blocker · device | Play representative SDR media and HDR media on the assigned PC, use fullscreen, and test sign-out and profile switch separately during playback. Confirm playback stops before navigation in both cases. |
| W-06 | blocker · device | Relaunch and confirm data and sign-in are kept. Extract the update into a new folder, delete the old application folder, and confirm data remains. |
| W-07 | polish · device | Extract once with 7-Zip and record the result. The app should run even when Mark of the Web is not propagated by default. |
| W-08 | polish · device | On Windows Pro, optionally use Windows Sandbox to observe the missing-`vulkan-1.dll` guidance. Do not copy a DLL from another machine into the package. |

## Results template

```text
Source commit:
Asset name and SHA-256:
Version / versionCode:
Signer or unsigned status:
Device or host identity:
OS and relevant runtime state:

Rows:
- A-01/W-01: pass | fail | not run — blocker or polish — redacted note

Failures and limitations:
Maintainer disposition:
```

An unrun blocker is not a pass. Classify a failed row as a blocker or a
limitation, preserve the exact asset identity, and do not publish until every
required blocker has an explicit disposition.
