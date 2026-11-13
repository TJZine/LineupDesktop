# Desktop session alignment matrix

The driver calls the production macOS and Windows adapters through the Flutter
method codec. The authenticated-reference executables use null video and audio
outputs and a disposable CA for synthetic loopback HTTPS. The player loads the
original variant through its private stream callback and follows the same
alignment decision and exact-seek formula as Dart. The tests read the
correlated restart clocks. Presentation and real Plex acceptance require a
physical pass.

The seven original target/GOP cells include a segment-zero no-seek control.
The other cells use a two-second GOP, perform a running seek and exercise
session → Direct Play → session on the same client. These cases must stay
within 0.5 s. A separate 12-second GOP with four-second fragments exercises an
expected imprecise landing. The keyframe before the 11-second request is in
segment 0, outside the retained view starting at segment 1. The two fragments
leading up to the next keyframe carry real inter frames. This case must receive
a correlated landing over 0.5 s from the target while meeting the same command,
pause and stop checks. The driver checks through stop for late failures,
duplicate results and pause changes.

The JSON includes the long-GOP original playlist, ffprobe packet geometry,
fixture HTTP and bytes, the clocks and option readbacks, and input, source and
runtime hashes. The synthetic server only binds
loopback, uses temporary keys and serves generated media. It makes zero Plex
requests.

On Windows the CI job builds `authenticated_reference_test`, puts the same
checksum-verified fixture generators used by `authenticated_reference` on
PATH, and invokes the matrix with CTest. The JSON is saved in the Windows
build directory and uploaded with the job.

```powershell
ctest --test-dir build/windows/x64 -C Release -R '^desktop_session_alignment$' --output-on-failure --no-tests=error
```

On macOS use the prepared pinned runtime and Flutter installation. Build the
harness without rebuilding the media runtime.

```sh
cmake -S tool/macos/authenticated-reference -B build/alignment-harness \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DLINEUP_MPV_RUNTIME="$LINEUP_MPV_RUNTIME" \
  -DFLUTTER_ROOT="$FLUTTER_ROOT"
cmake --build build/alignment-harness
python3 -B tool/native/session-alignment/run.py \
  --harness build/alignment-harness/authenticated-reference \
  --runtime "$LINEUP_MPV_RUNTIME" --flutter-root "$FLUTTER_ROOT" \
  --output build/desktop-session-alignment.json
```

By default the checker generates the original timing grids with FFmpeg and
independently checks sample packets with ffprobe. To rerun with the previously
frozen synthetic template bytes, pass their media directory with
`--frozen-media`. Both additional GOPs are generated in either case.
