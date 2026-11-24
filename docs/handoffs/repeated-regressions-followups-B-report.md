# B. Reclaim superseded native playback entries

Branch `followup/native-start-ownership` started at `76419674e0a7723651234a4865186a3a14e4c095`. The tested source commit is `b05b6ebc4d3f1fa9511ff42e0a490dfde34793fc`. The PR description carries hosted check receipts and the current head. [PR #100](https://github.com/TJZine/LineupDesktop/pull/100)

## Premises and decision

The Dart transport increments an instance-local counter and sends that integer as `loadId`. Windows permits a Dart hot restart while the native player survives. Initializing an already accepting core reuses its client and playback state. A fresh transport can therefore send 1 after an earlier transport sent 7. A public command and worker probe on the base initialized the same core twice, observed one fake mpv client and received the expected loading events for 7 and 1, in that order. The probe simulated the two Dart callers at the native boundary. [Dart transport](../../lib/playback/method_channel_native_player.dart) · [Hot restart contract](../fullscreen-hdr-implementation-plan.md) · [Windows adapter](../../windows/runner/native_player.cpp)

Both desktop adapters delegate load commands to the shared core. It runs queued commands in order and passes `replace` in both the plain and node-form `loadfile` calls. It accepts a load into the playback state only after successful mpv execution. [macOS adapter](../../macos/Runner/NativePlayer/LineupNativePlayer.mm) · [PlayerCore](../../native/player_core/player_core.cpp)

Implementation paused on the failed monotonicity premise. The designated decision judge approved a native acceptance sequence paired with the wire ID. A correlated start now reclaims strictly earlier unstarted keyed and fallback entries before testing capacity. The same ordering prevents a late redirect from recreating obsolete children. Started entries keep their original owners through END. An explicitly keyed END with no mapping cannot clear the current load. A late END sharing the most recent wire ID cannot publish a terminal state under that ID, including after the replacement ends. Previously queued Dart events are outside this guarantee. [State transitions](../../native/player_core/native_playback_state.h) · [Protocol](../native-player-protocol.md#correlation-and-lifetime-rules)

## Regression evidence

| Case | Red observation | Green observation |
| --- | --- | --- |
| FU1. Fallback 1, start and retire keyed 2, then start fallback 3 | Base published 1 for the third load | Candidate published 3 |
| FU2. Redirect child 15 remains unstarted when replacement 20 starts | Base admitted 1,022 fresh keyed loads | Candidate admitted all 1,023, leaving one started slot |
| Started predecessor reuses the replacement's wire ID | With the candidate's `FreshSessionClock` fixture on a disposable base source tree, `player_core_contract_test` exited 1 at “late and unknown keyed END must not publish or revoke the reused ID's session” | Private cookie stayed readable, no stale terminal event arrived and the current clock returned 19.25 |
| Replacement's terminal event arrives first | Limiting alias suppression to an active replacement failed “an older duplicate END must not overwrite the replacement's terminal state” | The late predecessor was consumed without publishing a second terminal state |
| Bounded model | The documented pre-PR-66 header failed after accept 0, accept 1, start 1. Separately, returning the correct occurrence with the wrong wire ID from END failed after accept 0, start 0, end 0 | The same candidate checker verified 20,989 prefixes |

To replay FU1 and FU2 independently, compile the exact candidate state-test cases against both headers. The two invocations of `old-cases` each exit 1.

```sh
scratch=$(mktemp -d)
mkdir -p "$scratch/old/player_core"
git show 76419674e:native/player_core/native_playback_state.h > "$scratch/old/player_core/native_playback_state.h"
python3 - "$scratch/cases.cpp" <<'PY'
from pathlib import Path
import sys
tests = Path('native/player_core/native_playback_state_test.cpp').read_text()
prefix = tests[:tests.index('void ReplacementAndRetirement()')]
cases = tests[tests.index('void SkippedFallback('):tests.index('void CapacityAndReset()')]
main = '}\nint main(int argc, char**) { if (argc == 1) SkippedFallback(1, 2, 3); else SkippedRedirect(); }\n'
Path(sys.argv[1]).write_text(prefix + cases + main)
PY
c++ -std=c++17 -I"$scratch/old" "$scratch/cases.cpp" -o "$scratch/old-cases"
"$scratch/old-cases"
"$scratch/old-cases" FU2
c++ -std=c++17 -Inative "$scratch/cases.cpp" -o "$scratch/current-cases"
"$scratch/current-cases"
"$scratch/current-cases" FU2
```

The complete portable native suite passed all six CTests, including the threaded public stop rejection and 801→802 retry, private-session failure and revocation checks, and the bounded model. The pressure fixtures now distinguish a table full of reclaimable unstarted entries from one full of started entries awaiting END. Verification used fake mpv operations on macOS. Physical media playback was outside this bookkeeping acceptance.

```sh
cmake -S native/player_core -B build/followup-b/core -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build/followup-b/core --parallel 4
ctest --test-dir build/followup-b/core --output-on-failure
build/followup-b/core/playback_lifecycle_model
```
