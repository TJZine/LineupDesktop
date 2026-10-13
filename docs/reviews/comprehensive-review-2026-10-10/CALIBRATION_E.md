**D-F02: retain as a confirmed S2 finding, high confidence.** Public timing and seek interpretation use different coordinate systems when a later part is active and metadata remains incomplete.

With part 0 known as 60 seconds and part 1 unknown, a native update for part 1 at position 10 seconds/duration 90 seconds exposes **10/90** through the local fallback in [player_coordinator.dart:350](/Users/tristan/Software/LineupDesktop/lib/playback/player_coordinator.dart:350). That update does not fill the duration map; native duration is recorded there only on natural completion. `seekBy(30)` therefore requests 40 seconds, but [seekTo:1171](/Users/tristan/Software/LineupDesktop/lib/playback/player_coordinator.dart:1171) passes it into the aggregate mapper, which selects **part 0 at 40 seconds** and reloads it.

This reaches actual Player interactions: keyboard/remote skip calls and the DVR slider both use those public coordinates. Missing part durations are accepted Plex input. The documented [current-part fallback](/Users/tristan/Software/LineupDesktop/docs/user-guide.md:281) supports treating this as a contract violation.

Existing tests cover unknown timing on the first part and aggregate timing after all boundaries become known, but omit seeking on a later part while metadata is incomplete. The correction should keep local presentation and local seeks aligned, while retaining aggregate seeking when aggregate timing is presented. Initial live-join mapping is a separate consumer and should remain independently considered.

**D-C03: keep parked as a hypothesis; native reachability is not established.** The conditional coordinator weakness exists: an accepted EOF before the initial tune commits can be lost because advancement requires `_activePlayback`, while `_completePartLoad` later returns without replaying that terminal event. See [EOF handling:474](/Users/tristan/Software/LineupDesktop/lib/playback/player_coordinator.dart:474) and [load completion:855](/Users/tristan/Software/LineupDesktop/lib/playback/player_coordinator.dart:855).

The ordering counterpoints matter:

- `WindowsNativePlayer.load` waits for both the native command reply and playing readiness. Playing completes an ordinary asynchronous completer after synchronous event delivery.
- Native load handling acknowledges the queued command immediately. `DrainEvents` sends separate platform messages for each event; it does not deliver one synchronous Dart batch.
- Dart normally drains microtasks before subsequent asynchronous events. [Completer documentation](https://api.dart.dev/dart-async/Completer/Completer.html), [microtask documentation](https://api.dart.dev/dart-async/scheduleMicrotask.html). MethodChannel’s documented FIFO guarantee does not establish a cross-direction reply/event barrier. [MethodChannel documentation](https://api.flutter.dev/flutter/services/MethodChannel-class.html).

A coordinator probe that delivers playing and EOF before a delayed load return would establish susceptibility to that sequence, **not that normal Windows transport produces it**. Promotion requires adapter-level ordering evidence or controlled Windows reproduction, particularly with a delayed load/seek acknowledgement.

This calibration was read-only at `4fb7758`; I executed no tests or probes and changed no files.
