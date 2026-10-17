import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/display_matching.dart';
import 'package:lineup_desktop/playback/native_player.dart';

void main() {
  test('eligibility distinguishes startup from a continuing Guide session', () {
    bool eligible({
      bool active = false,
      bool enabled = true,
      bool fullscreen = true,
      bool intent = true,
      bool visible = true,
      bool guide = false,
      bool error = false,
    }) => displayMatchingSession(
      active: active,
      enabled: enabled,
      fullscreen: fullscreen,
      intent: intent,
      playerVisible: visible,
      fullGuide: guide,
      error: error,
    );
    expect(eligible(), isTrue);
    expect(eligible(guide: true), isFalse);
    expect(eligible(visible: false), isFalse);
    expect(eligible(active: true, guide: true, visible: false), isTrue);
    expect(eligible(active: true, enabled: false), isFalse);
    expect(eligible(active: true, fullscreen: false), isFalse);
    expect(eligible(active: true, intent: false), isFalse);
    expect(eligible(active: true, error: true), isFalse);
    expect(
      decodedDisplayState(const PlayerTelemetry(targetGamma: 'pq')),
      DisplayMatchingState.unknown,
    );
    for (final gamma in ['pq', 'hlg']) {
      expect(
        decodedDisplayState(PlayerTelemetry(gamma: gamma)),
        DisplayMatchingState.hdr,
      );
    }
    expect(
      decodedDisplayState(const PlayerTelemetry(gamma: 'bt.1886')),
      DisplayMatchingState.sdr,
    );
  });

  testWidgets('write settles once; repeated reports do not restart it', (
    tester,
  ) async {
    final f = _Fixture();
    f.start();
    f.decode();
    f.report(outcome: DisplayMatchingOutcome.matched, wrote: true);
    await f.elapse(tester, const Duration(seconds: 1));
    f.report(outcome: DisplayMatchingOutcome.matched, wrote: true);
    expect(f.player.plays, 0);
    await f.elapse(tester, const Duration(milliseconds: 500));
    expect(f.player.plays, 1);
    f.report(outcome: DisplayMatchingOutcome.matched, wrote: true);
    expect(f.policy.holdActive, isFalse);
    expect(f.player.plays, 1);
    f.close();
  });

  testWidgets('identical reports do not notify or disturb hold settlement', (
    tester,
  ) async {
    final f = _Fixture();
    f.start();
    f.decode();
    f.report();
    final changed = f.changes;
    f.report();
    expect(f.changes, changed);
    expect(f.policy.holdActive, isTrue);
    f.report(outcome: DisplayMatchingOutcome.matched, wrote: true);
    expect(f.changes, changed + 1);
    await f.elapse(tester, const Duration(seconds: 1));
    f.report(outcome: DisplayMatchingOutcome.matched, wrote: true);
    expect(f.changes, changed + 1);
    await f.elapse(tester, const Duration(milliseconds: 500));
    expect(f.player.plays, 1);
    expect(f.policy.holdActive, isFalse);
    f.close();
  });

  for (final exit in [
    'matched',
    'failed',
    'inactive',
    'unavailable',
    'suspended',
    'deadline',
    'end',
  ]) {
    testWidgets('$exit releases exactly once', (tester) async {
      final f = _Fixture();
      f.start();
      f.decode();
      switch (exit) {
        case 'matched':
          f.report(outcome: DisplayMatchingOutcome.matched);
        case 'failed':
          f.report(outcome: DisplayMatchingOutcome.failed);
        case 'inactive':
          f.report(session: DisplayMatchingSessionState.inactive);
        case 'unavailable':
          f.report(session: DisplayMatchingSessionState.unavailable);
        case 'suspended':
          f.report(session: DisplayMatchingSessionState.suspended);
        case 'deadline':
          await f.elapse(tester, const Duration(seconds: 4));
        case 'end':
          f.policy.updateSession(false, userPaused: true);
      }
      expect(f.player.plays, 1);
      expect(f.policy.holdActive, isFalse);
      await f.elapse(tester, const Duration(seconds: 6));
      expect(f.player.plays, 1);
      f.close();
    });
  }

  for (final fallback in [
    'no target',
    'target reached',
    'readiness cap',
    'audio',
  ]) {
    testWidgets('unknown fallback: $fallback', (tester) async {
      final f = _Fixture();
      f.start(
        target: fallback == 'no target' || fallback == 'audio'
            ? null
            : const Duration(seconds: 20),
      );
      f.policy.ready(1);
      if (fallback == 'audio') f.policy.tracksUpdated(1, noVideo: true);
      if (fallback == 'target reached') {
        f.policy.observe(
          1,
          const PlayerTelemetry(),
          const Duration(seconds: 19),
        );
        await f.elapse(tester, const Duration(seconds: 1));
        expect(f.player.plays, 0);
        f.policy.observe(
          1,
          const PlayerTelemetry(),
          const Duration(seconds: 20),
        );
      }
      if (fallback != 'audio') {
        final delay = fallback == 'readiness cap' ? 6 : 2;
        await f.elapse(tester, Duration(milliseconds: delay * 1000 - 1));
        expect(f.player.plays, 0);
        await f.elapse(tester, const Duration(milliseconds: 1));
      }
      expect(f.player.plays, 1);
      expect(f.policy.desired, DisplayMatchingState.unknown);
      f.close();
    });
  }

  for (final userPaused in [false, true]) {
    testWidgets('admission failure releases hold, userPaused=$userPaused', (
      tester,
    ) async {
      final f = _Fixture();
      addTearDown(f.close);
      f.start();
      f.decode();
      final revision = f.policy.revision;
      f.policy.receive(
        DisplayMatchingReport.unavailable(
          revision: revision - 1,
          reason: DisplayMatchingReason.guardianUnavailable,
        ),
      );
      expect(f.policy.holdActive, isTrue);
      expect(f.player.plays, 0);
      if (userPaused) f.policy.userPause();
      final failure = DisplayMatchingReport.unavailable(
        revision: revision,
        reason: DisplayMatchingReason.guardianUnavailable,
      );
      f.policy.receive(failure);
      expect(f.policy.holdActive, isFalse);
      expect(f.player.plays, userPaused ? 0 : 1);
      f.policy.receive(failure);
      await f.elapse(tester, const Duration(seconds: 6));
      expect(f.player.plays, userPaused ? 0 : 1);
      expect(f.policy.beginLoad(2, null), isFalse);
    });
  }

  for (final action in ['play', 'pause', 'supersede']) {
    testWidgets('$action cancels automatic resume', (tester) async {
      final f = _Fixture();
      f.start();
      f.decode();
      if (action == 'play') {
        f.policy.userPlay();
        await f.player.play();
      }
      if (action == 'pause') f.policy.userPause();
      if (action == 'supersede') f.policy.cancelLoad();
      f.report(outcome: DisplayMatchingOutcome.matched, wrote: true);
      await f.elapse(tester, const Duration(seconds: 8));
      expect(f.player.plays, action == 'play' ? 1 : 0);
      f.close();
    });
  }

  for (final paused in [false, true]) {
    for (final matching in [false, true]) {
      testWidgets('post-load session paused=$paused matching=$matching', (
        tester,
      ) async {
        final f = _Fixture();
        expect(f.policy.beginLoad(1, null), isFalse);
        f.decode();
        f.policy.updateSession(true, userPaused: paused);
        f.report(
          observed: matching
              ? DisplayMatchingState.hdr
              : DisplayMatchingState.sdr,
        );
        expect(f.player.pauses, !paused && !matching ? 1 : 0);
        f.report(
          outcome: DisplayMatchingOutcome.matched,
          wrote: !matching,
          observed: DisplayMatchingState.hdr,
        );
        await f.elapse(tester, const Duration(milliseconds: 1500));
        expect(f.player.plays, !paused && !matching ? 1 : 0);
        f.close();
      });
    }
  }

  for (final state in [
    DisplayMatchingSessionState.unavailable,
    DisplayMatchingSessionState.suspended,
  ]) {
    testWidgets('$state skips paused start until a new session', (
      tester,
    ) async {
      final f = _Fixture();
      f.policy.updateSession(true, userPaused: false);
      f.report(session: state);
      expect(f.policy.beginLoad(1, null), isFalse);
      f.policy.updateSession(false, userPaused: false);
      f.policy.updateSession(true, userPaused: false);
      expect(f.policy.beginLoad(2, null), isTrue);
      f.close();
    });
  }

  testWidgets(
    'readiness waits for video transfer or an actual no-video update',
    (tester) async {
      final f = _Fixture();
      f.start();
      f.policy.ready(1);
      expect(f.policy.holdActive, isTrue);
      expect(f.player.plays, 0);
      f.policy.tracksUpdated(0, noVideo: true);
      expect(f.policy.holdActive, isTrue);
      f.policy.tracksUpdated(1, noVideo: true);
      expect(f.policy.holdActive, isFalse);
      expect(f.player.plays, 1);
      f.close();
    },
  );

  testWidgets('late first transfer updates matching after hold fallback', (
    tester,
  ) async {
    final f = _Fixture();
    f.start();
    f.policy.ready(1);
    await f.elapse(tester, const Duration(seconds: 2));
    expect(f.player.plays, 1);
    f.decode();
    expect(f.policy.desired, DisplayMatchingState.hdr);
    expect(f.player.requests.last.desired, DisplayMatchingState.hdr);
    expect(f.policy.holdActive, isFalse);
    f.report(outcome: DisplayMatchingOutcome.matched, wrote: true);
    await f.elapse(tester, const Duration(seconds: 2));
    expect(f.player.plays, 1);
    f.close();
  });

  testWidgets('late pause failure cannot release superseding hold', (
    tester,
  ) async {
    final f = _Fixture();
    f.policy.beginLoad(1, null);
    f.decode();
    f.player.pendingPause = Completer<void>();
    f.policy.updateSession(true, userPaused: false);
    f.report();
    final old = f.player.pendingPause!;
    f.player.pendingPause = null;
    f.policy.beginLoad(2, null);
    f.policy.observe(2, const PlayerTelemetry(gamma: 'pq'), Duration.zero);
    old.completeError(StateError('synthetic pause failure'));
    await tester.pump();
    expect(f.policy.holdActive, isTrue);
    expect(f.player.plays, 0);
    f.close();
  });

  testWidgets(
    'old request failure cannot finish same-revision returning target hold',
    (tester) async {
      final f = _Fixture();
      f.start();
      f.player.pendingRequest = Completer<void>();
      f.decode();
      final old = f.player.pendingRequest!;
      f.player.pendingRequest = null;
      final revision = f.policy.revision;
      f.report(session: DisplayMatchingSessionState.inactive);
      f.report(observed: DisplayMatchingState.sdr);
      expect(f.player.plays, 1);
      expect(f.player.pauses, 1);
      old.completeError(StateError('synthetic old target request failure'));
      await tester.pump();
      expect(f.policy.revision, revision);
      expect(f.policy.holdActive, isTrue);
      expect(f.player.plays, 1);
      f.close();
    },
  );

  testWidgets('user pause survives native target retirement and reappearance', (
    tester,
  ) async {
    final f = _Fixture();
    f.start();
    f.decode();
    f.policy.userPause();
    f.report(session: DisplayMatchingSessionState.unavailable);
    f.report(observed: DisplayMatchingState.sdr);
    f.report(
      outcome: DisplayMatchingOutcome.matched,
      wrote: true,
      observed: DisplayMatchingState.hdr,
    );
    await f.elapse(tester, const Duration(milliseconds: 1500));
    expect(f.player.pauses, 0);
    expect(f.player.plays, 0);
    f.close();
  });

  testWidgets('rapid session restart retains explicit play intent', (
    tester,
  ) async {
    final f = _Fixture();
    f.start();
    f.decode();
    // The coordinator now supplies user intent independently of native
    // pause observations caused by the hold.
    f.policy.updateSession(false, userPaused: false);
    expect(f.player.plays, 1);
    f.policy.updateSession(true, userPaused: false);
    f.report(observed: DisplayMatchingState.sdr);
    f.report(outcome: DisplayMatchingOutcome.matched);
    expect(f.player.pauses, 1);
    expect(f.player.plays, 2);
    f.close();
  });

  testWidgets('first transfer only; no extra revisions for polls', (
    tester,
  ) async {
    final f = _Fixture();
    f.start();
    f.decode();
    final revision = f.policy.revision;
    f.policy.observe(1, const PlayerTelemetry(gamma: 'bt.1886'), Duration.zero);
    f.report();
    f.report();
    expect(f.policy.revision, revision);
    expect(f.policy.desired, DisplayMatchingState.hdr);
    f.close();
  });

  for (final state in [
    DisplayMatchingSessionState.inactive,
    DisplayMatchingSessionState.unavailable,
  ]) {
    testWidgets('same-revision $state to active rearms once', (tester) async {
      final f = _Fixture();
      f.start();
      f.decode();
      f.report(outcome: DisplayMatchingOutcome.matched);
      final revision = f.policy.revision;
      f.report(session: state);
      f.report(observed: DisplayMatchingState.sdr);
      expect(f.policy.holdActive, isTrue);
      expect(f.player.pauses, 1);
      f.report(
        outcome: DisplayMatchingOutcome.matched,
        wrote: true,
        observed: DisplayMatchingState.hdr,
      );
      await f.elapse(tester, const Duration(milliseconds: 1500));
      expect(f.player.plays, 2);
      f.report(
        outcome: DisplayMatchingOutcome.matched,
        observed: DisplayMatchingState.hdr,
      );
      expect(f.policy.holdActive, isFalse);
      expect(f.policy.revision, revision);
      f.close();
    });
  }

  testWidgets(
    'late request and pause failures cannot release replacement hold',
    (tester) async {
      final f = _Fixture();
      f.player.pendingRequest = Completer<void>();
      f.start();
      f.decode();
      final old = f.player.pendingRequest!;
      f.player.pendingRequest = null;
      expect(f.policy.beginLoad(2, null), isTrue);
      f.policy.observe(2, const PlayerTelemetry(gamma: 'pq'), Duration.zero);
      old.completeError(StateError('synthetic request failure'));
      await tester.pump();
      expect(f.policy.holdActive, isTrue);
      expect(f.player.plays, 0);
      f.policy.userPause();
      await f.elapse(tester, const Duration(seconds: 5));
      expect(f.player.plays, 0);
      f.close();
    },
  );
}

class _Fixture {
  _Fixture() {
    policy = DisplayMatching(
      player: player,
      clock: () => now,
      changed: () {
        changes++;
      },
    );
  }
  int changes = 0;
  final player = _Player();
  late final DisplayMatching policy;
  DateTime now = DateTime.utc(2026);
  void start({Duration? target}) {
    policy.updateSession(true, userPaused: false);
    expect(policy.beginLoad(1, target), isTrue);
  }

  void decode() =>
      policy.observe(1, const PlayerTelemetry(gamma: 'pq'), Duration.zero);
  void report({
    DisplayMatchingSessionState session = DisplayMatchingSessionState.active,
    DisplayMatchingOutcome outcome = DisplayMatchingOutcome.pending,
    bool wrote = false,
    DisplayMatchingState observed = DisplayMatchingState.sdr,
  }) => policy.receive(
    DisplayMatchingReport(
      revision: policy.revision,
      session: session,
      observed: observed,
      outcome: outcome,
      wrote: wrote,
      owned: wrote,
      reason: null,
      route: DisplayMatchingRoute.advancedColor,
      activeColorMode: null,
    ),
  );
  Future<void> elapse(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
  }

  void close() => policy.dispose();
}

class _Player implements NativePlayer {
  int plays = 0;
  int pauses = 0;
  Completer<void>? pendingRequest;
  Completer<void>? pendingPause;
  final requests = <DisplayMatchingRequest>[];
  @override
  DisplayMatchingReport get displayReport =>
      const DisplayMatchingReport.initial();
  @override
  Future<void> setDisplayMatching(DisplayMatchingRequest request) {
    requests.add(request);
    return pendingRequest?.future ?? Future.value();
  }

  @override
  Future<void> play() async {
    plays++;
  }

  @override
  Future<void> pause() {
    pauses++;
    return pendingPause?.future ?? Future.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
