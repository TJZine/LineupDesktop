---
name: verify-scan-deadlines
description: Recheck Plex scan deadline ownership when changing budget expiry, HTTP headers, body cancellation or transport timeout classification.
---

# Verify Plex scan deadlines

An expired scan budget must stop the complete attempt. A transport or per-request timeout while scan time remains must leave the aggregate budget available to other requests.

With the repository's pinned Flutter SDK, run `flutter test test/plex/plex_deadline_model_test.dart` from the root. The standard CI Flutter suite discovers this file. Keep it separate from loopback socket tests because the widget binding replaces the process HTTP client.

The model drives one real `PlexClient.playlists` request inside `runScan` with a synthetic HTTP transport and Flutter's virtual timer queue. Its twelve schedules cover waiting for headers or streaming the body, a scan deadline before, after or equal to the request deadline, and a transport timeout just before the first deadline or a stalled transport across it. It checks the public error, whether the containing budget can continue, request abortion and cancellation of any body delivered after the deadline. A failure names the schedule. Follow it through budget expiry, the header watchdog, or the body's cancellation listener before changing the model. Real sockets, sibling cancellation and cleanup delays retain their separate coverage in `test/plex/plex_io_transport_test.dart`.

## Historical replay

In a disposable worktree at `19213bef0`, copy only `test/plex/plex_deadline_model_test.dart` from the candidate. Run `flutter pub get` and the model command there. Expect four stale classifications on stalled requests when the scan limit is shorter or equal. The old header and body timers emitted a network timeout before the aggregate timer recorded elapsed time. The remaining eight schedules should pass. Repeat the command in the candidate worktree and require all twelve schedules to pass.

## Coverage record

Production sync revision `b62a786926153fa474c9b6324c071b9720cc1e4a`. Compare [PlexScanBudget](../../../lib/plex/plex_scan_budget.dart) (`check`, `expireElapsed`, `stopped`) and [PlexClient](../../../lib/plex/plex_client.dart) (`runScan`, `_send`, `_sendUnpooled`, `_readBounded`) with the [deadline model](../../../test/plex/plex_deadline_model_test.dart). Advance the sync revision only after rechecking the represented orders and replaying a failing implementation.
