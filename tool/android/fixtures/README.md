# Synthetic Android player fixtures

These tools use generated media and one public synthetic token. They never read
Lineup state or Plex credentials. Obtain a device assignment before running adb,
and reserve ports 18443/18444 before starting the server. The server binds only
`127.0.0.1`; use adb reverse. No LAN/firewall or device-setting changes are needed.

Use pinned Flutter 3.47.7 and JDK 17 as documented in
[Android runtime](../../../docs/android-runtime.md). FFmpeg/FFprobe need x264,
x265, SVT-AV1, AC3/EAC3, TrueHD and DCA encoders. Generated media and Python
caches are ignored. PGS has no installed encoder and remains a separate fixture
exception; basic ASS fidelity and receiver/Dolby Vision checks remain target/human
acceptance. Structural unknown sample entries are explicitly negative controls,
not claims about encoded codec support.

```sh
sh tool/android/fixtures/create-ca.sh
python3 tool/android/fixtures/generate.py
python3 tool/android/fixtures/server.py --audit /absolute/private/evidence/server-audit.jsonl
```

`create-ca.sh` creates/reuses private keys under
`~/.config/lineup-android/fixture-ca` and copies only the public CA certificate to
`android/app/src/debug/res/raw/fixture_ca.crt`. Never copy keys or trust settings
into main/profile/release. The checked-in public certificate matches the local
fixture CA used during development; another developer must run this command and
rebuild debug to trust their own CA. `server.py --root /absolute/fixtures` can
reuse an identified generated corpus; no address/port override exists.

On a separately assigned terminal, using the assigned serial:

```sh
adb -s ASSIGNED_SERIAL reverse tcp:18443 tcp:18443
adb -s ASSIGNED_SERIAL reverse tcp:18444 tcp:18444
python3 tool/android/fixtures/server_check.py
```

Authentication is header-only under `https://localhost:18443/auth/`.
Routes `same`, `cross-host`, `cross-port`, `downgrade`, `loop`, and `nested.m3u8`
exercise redirect/reference restrictions. Port 18444 is the forbidden origin-port
control. Audit entries retain known synthetic route names and booleans only,
never request headers, unknown raw paths, query strings or token values.
`server_check.py` checks status/range/redirect routes without following redirects.

## Production adapter runtime check

`player_contract.dart` is a disposable emulator entrypoint. It uses the real
Dart `MethodChannelNativePlayer`, production Kotlin adapter, actual Media3 engine
and synthetic server. Its small transparent Flutter overlay is a fixture UI,
not product UI acceptance. It reads no saved data and does not authorize running
on a signed-in device. Do not use this alternate entrypoint on a physical target
without an explicit assignment. Rebuild normal `lib/main.dart` after testing.

```sh
tool/android/with-signing.sh flutter build apk --debug --target-platform android-arm,android-arm64 --target tool/android/fixtures/player_contract.dart
adb -s ASSIGNED_SERIAL install -r -d build/app/outputs/flutter-apk/app-debug.apk
adb -s ASSIGNED_SERIAL shell am force-stop com.tjzine.lineup
adb -s ASSIGNED_SERIAL shell am start -n com.tjzine.lineup/.MainActivity --esal dart_entrypoint_args "'--case=contract'"
```

Read current-process logcat for `U3_CONTRACT` records. A run passes only on its
explicit `PASS` record, with no later `FAIL`. Cases:

- `contract`: paused initial readiness, position progress, play/pause, exact and
  previous-sync seeks, arbitrary/zero rectangles without stopping media, two
  observed audio/text selections, subtitles off/on, stop/successor, EOF/successor.
- `negative`: forbidden redirects/nested manifest, typed malformed/omitted-track
  failures, then same-origin authenticated success.
- `lifetime`: continuous repeated fragmented initialization progresses into
  segment two with explicit revision-2 and frame-timestamp evidence; omitted
  second-moov video fails after buffered content drains. The original U2 repeated
  initialization controls remain generated, but their timestamps reset: FFmpeg's
  `empty_moov` muxer ignored `output_ts_offset`. `continuous_fragments.py` shifts
  generated second-segment `tfdt` times without changing initialization/track
  declarations; FFprobe and native rendered-frame metadata check continuity.
- `seek-lifetime`: indexed fragmented MP4 seeks to a nonzero `moof`, then reaches
  a later initialization. The valid control must render segment-two frames and
  the omitted-video control must fail precisely. Native byte-position,
  initialization-revision and frame-timestamp evidence are all required.
- `formats`: actual MP4/MKV audio-only, video-only, supported alternatives,
  late-moov, fragmented, chapters and MP4 internal-text progress and seeks.
- `background`: native Home teardown, decoder release and a foreground successor
  load. This fixture does not establish the shared coordinator's scheduled retune
  policy; U4/integrated acceptance owns that behavior.
- `release-isolation`: build this entrypoint with `--release`; a load against the
  debug fixture CA must fail `network_error`. Also inspect that the APK excludes
  the fixture CA and network security config. Production profile is never made
  debuggable/trusted for this check.

The native debug-only `LineupPlayer first_frame` diagnostic carries immutable
native generation/load ID and sampled position in milliseconds. It is an actual
render callback, not a first-frame PTS measurement or a wire event. No URI/token
or raw exception is logged. Bounded `frame_timestamp` samples (first frame,
backward discontinuity, then at least five seconds apart) and
`source_initialization` revisions use the same immutable correlation. They are
passive diagnostics, not wire events, seek completion or physical-HWC evidence.

JVM checks: run `:app:testDebugUnitTest` through the signing wrapper (or use the
explicit contributor debug-key mode) with the generated Gradle wrapper/pinned
Gradle. Tests cover bounds, correlation, property eviction, disposal generations,
track encoding and omitted-track observer lifetime. The two real Media3
encoding/failure suites use Robolectric for Android text helpers; the protocol
controller itself uses a deterministic fake engine.

After runtime work, stop the server and remove only the assigned device's two
reverse mappings. Preserve APK/source/cert/ABI identities with evidence.
Emulator results cannot establish physical Fire32-bit decoding, HDR, receiver
passthrough, temporal G6 or final integrated app lifecycle/remote acceptance.

For reproducible collection, after installing the identified fixture APK:

```sh
python3 tool/android/fixtures/run_contract.py --serial ASSIGNED_SERIAL --case contract --evidence /absolute/private/evidence/contract
```

The runner waits for the current process, saves PID-filtered logs and screenshots,
requires explicit PASS plus disposal completion, and rejects later FAIL records.
The lifetime cases additionally require native revision-2 facts and segment-two
frame timestamps. The collector accumulates overlapping PID-filtered snapshots
instead of overwriting them, preserving early facts even when a device's logcat
ring wraps. Subtitle snapshots are timed observations; check their pixels against
the native selection history before attributing each image to a specific codec. It never clears global logs, uninstalls or erases app data.

## Subtitle routing corpus

`python3 tool/android/fixtures/generate.py --subtitles-only` generates only the
additive `subtitle-*` corpus. Normal generation includes it too. Existing fixture
source/encoding commands are unchanged, and existing media files are never
rewritten. The new sources are synthetic test patterns with no account inputs:

- `subtitle-routing.mkv`: two-line SRT with italic spans, a top `{\an8}` cue,
  font color/alpha, and a positioned `{\pos}` cue.
- `subtitle-wide.mkv`: the same SRT on 860×360 (approximately 2.39:1) video.
- `subtitle-authored.mkv`: authored SSA with a fractional font size, color/alpha
  spans, a positioned sign and a drawing-mode event.
- `subtitle-movtext.mp4`: the SSA source encoded as mov_text, preserving text
  color/alpha spans for native suppression checks.

PGS still needs physical fixture acceptance. FFmpeg's dvdsub encoder accepts
bitmap input but cannot render SRT text directly; bitmap-source generation is
handled separately from text remuxing.

`subtitle-bitmap.mkv` contains actual VobSub bitmap packets rendered from the
synthetic two-line sample `Look out!` / `[Door creaks]`, white with a black
outline. `bitmap_subtitle.c` rasterizes through FreeType into a paletted
`AVSubtitleRect`, then uses FFmpeg's dvdsub encoder and MKV muxer; FFmpeg remuxes
that track with the synthetic video. Generation needs a C compiler, pkg-config,
FFmpeg development headers/libraries (`libavcodec`, `libavformat`, `libavutil`)
and `freetype2`. Set `LINEUP_SUBTITLE_FONT` to a TrueType font; on macOS the
default is `/System/Library/Fonts/Supplemental/Arial.ttf`. The generated
`subtitle-bitmap-font.json` records the exact font SHA256 and 24px raster size.
The font is a local fixture prerequisite and is not bundled into the app.

The SRT source includes the requested HTML alpha attribute, but the installed
FFmpeg text conversion drops that alpha (and retains RGB). It is an input
coverage case, not evidence of retained alpha. The mov_text control instead
comes from authored ASS and is verified by decoding back to ASS: its dialogue
contains explicit `\1c` color and `\1a&H40&` alpha spans.

Keep the ASS source's blank section separators. Media3 1.11.1 otherwise skips
the last PlayResY/Style rows; the real-parser JVM test checks authored fractional
size and color so a fallback-style render cannot stand in for ASS fidelity.
