// MethodCall.arguments is intentionally dynamic in these protocol fixtures.
// ignore_for_file: avoid_dynamic_calls
// The cancellation fixtures own stream closure through their teardown path.
// ignore_for_file: close_sinks

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/windows_native_player.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'disposal observes both delayed subscription cleanup failures',
    () async {
      final failures = <FlutterErrorDetails>[];
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = failures.add;
      addTearDown(() => FlutterError.onError = previousErrorHandler);
      final lineup = _TestLineup();
      final guide = GuideController(lineup: lineup);
      final player = _CancellingPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      coordinator.dispose();
      expect(player.eventStream.hasListener, isFalse);
      expect(player.displayStream.hasListener, isFalse);
      expect(failures, isEmpty);
      for (final cancellation in [
        player.eventCancellation,
        player.displayCancellation,
      ]) {
        cancellation.completeError(
          StateError('https://private.test/media?X-Plex-Token=secret-sentinel'),
        );
        await Future<void>.delayed(Duration.zero);
      }
      expect(failures, hasLength(2));
      for (final failure in failures) {
        expect(failure.exception, isA<StateError>());
        expect(
          failure.exceptionAsString(),
          contains('subscription cleanup failed'),
        );
        expect(failure.toString(), isNot(contains('secret-sentinel')));
      }
      await player.eventStream.close();
      await player.displayStream.close();
    },
  );

  testWidgets(
    'display hold local load projects busy without changing overlay or status',
    (tester) async {
      final f = _ContinuationFixture(player: _DisplayPlayer());
      final p = f.player as _DisplayPlayer;
      addTearDown(f.close);
      await f.coordinator.toggleFullscreen();
      await f.coordinator.loadInitialMedia(
        Uri.parse('https://synthetic.test/local'),
      );
      expect(p.pausedStarts, [true]);
      expect(f.coordinator.displayHoldActive, isTrue);
      expect(f.coordinator.status.state, PlayerState.paused);
      f.coordinator.showMiniGuide();
      final presentation = f.coordinator.overlayPresentationGeneration;
      p.decode();
      await tester.pump();
      p.report(DisplayMatchingOutcome.pending);
      await tester.pump();
      f.now = f.now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(f.coordinator.busyLabel, 'Starting playback…');
      p.report(DisplayMatchingOutcome.matched, wrote: true);
      await tester.pump();
      f.now = f.now.add(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(p.plays, 1);
      expect(f.coordinator.displayHoldActive, isFalse);
      expect(f.coordinator.overlay, PlayerOverlay.miniGuide);
      expect(f.coordinator.overlayPresentationGeneration, presentation);
      expect(
        f.coordinator.diagnosticPlaybackSnapshot.displayReport,
        p.displayReport,
      );
    },
  );

  for (final userPaused in [false, true]) {
    testWidgets('admission fallback preserves playback intent: $userPaused', (
      tester,
    ) async {
      final f = _ContinuationFixture(player: _DisplayPlayer());
      final p = f.player as _DisplayPlayer;
      addTearDown(f.close);
      await f.coordinator.toggleFullscreen();
      await f.coordinator.loadInitialMedia(
        Uri.parse('https://synthetic.test/local'),
      );
      p.decode();
      await tester.pump();
      f.coordinator.showMiniGuide();
      p.admissionUnavailable(revision: p.requests.last.revision - 1);
      await tester.pump();
      expect(f.coordinator.displayHoldActive, isTrue);
      expect(p.plays, 0);
      if (userPaused) await f.coordinator.pause();
      final overlay = f.coordinator.overlay;
      final presentation = f.coordinator.overlayPresentationGeneration;
      p.admissionUnavailable();
      await tester.pump();
      expect(f.coordinator.displayHoldActive, isFalse);
      expect(p.plays, userPaused ? 0 : 1);
      expect(f.coordinator.overlay, overlay);
      expect(f.coordinator.overlayPresentationGeneration, presentation);
      expect(f.coordinator.error, isNull);
      expect(
        f.coordinator.diagnosticPlaybackSnapshot.displayReport.reason,
        DisplayMatchingReason.guardianUnavailable,
      );
      p.admissionUnavailable();
      await tester.pump(const Duration(seconds: 6));
      expect(p.plays, userPaused ? 0 : 1);
      f.coordinator.dispose();
    });
  }

  for (final finish in ['settle', 'failed', 'deadline', 'no video']) {
    testWidgets('readiness before track-list keeps display hold: $finish', (
      tester,
    ) async {
      final f = _ContinuationFixture(player: _DisplayPlayer(deferTracks: true));
      final p = f.player as _DisplayPlayer;
      addTearDown(f.close);
      await f.coordinator.toggleFullscreen();
      await f.coordinator.loadInitialMedia(
        Uri.parse('https://synthetic.test/local'),
      );
      expect(p.tracks, isEmpty);
      expect(f.coordinator.displayHoldActive, isTrue);
      expect(p.plays, 0);
      if (finish == 'no video') {
        p.emitStatus(
          PlayerState.paused,
          generation: p.loadGenerations.last,
          tracksUpdated: true,
        );
        await tester.pump();
        expect(p.requests.last.desired, DisplayMatchingState.unknown);
      } else {
        p.decode();
        await tester.pump();
        expect(p.requests.last.desired, DisplayMatchingState.hdr);
        expect(f.coordinator.displayHoldActive, isTrue);
        expect(p.plays, 0);
        if (finish == 'settle') {
          p.report(DisplayMatchingOutcome.matched, wrote: true);
          await tester.pump();
          f.now = f.now.add(const Duration(milliseconds: 1499));
          await tester.pump(const Duration(milliseconds: 1499));
          expect(p.plays, 0);
          f.now = f.now.add(const Duration(milliseconds: 1));
          await tester.pump(const Duration(milliseconds: 1));
        } else if (finish == 'failed') {
          p.report(DisplayMatchingOutcome.failed);
          await tester.pump();
        } else {
          f.now = f.now.add(const Duration(seconds: 4));
          await tester.pump(const Duration(seconds: 4));
        }
      }
      expect(f.coordinator.displayHoldActive, isFalse);
      expect(p.plays, 1);
      f.coordinator.dispose();
    });
  }

  for (final trigger in [
    'fullscreen',
    'Guide close',
    'Player destination',
    'setting',
  ]) {
    testWidgets('post-load $trigger pauses only for the new desired change', (
      tester,
    ) async {
      final f = _ContinuationFixture(player: _DisplayPlayer());
      final p = f.player as _DisplayPlayer;
      addTearDown(f.close);
      if (trigger == 'Guide close') f.coordinator.showFullGuide();
      if (trigger == 'Player destination') {
        f.coordinator.setPlayerDestinationVisible(false);
      }
      if (trigger == 'setting') {
        f.lineup.setSettings(
          f.lineup.settings.copyWith(matchDisplayHdr: false),
        );
      }
      if (trigger != 'fullscreen') await f.coordinator.toggleFullscreen();
      await f.coordinator.loadInitialMedia(
        Uri.parse('https://synthetic.test/local'),
      );
      expect(p.pausedStarts, [false]);
      p.decode();
      await tester.pump();
      if (trigger == 'fullscreen') await f.coordinator.toggleFullscreen();
      if (trigger == 'Guide close') f.coordinator.closeOverlay();
      if (trigger == 'Player destination') {
        f.coordinator.setPlayerDestinationVisible(true);
      }
      if (trigger == 'setting') {
        f.lineup.setSettings(f.lineup.settings.copyWith(matchDisplayHdr: true));
      }
      expect(p.pauses, 0);
      p.report(DisplayMatchingOutcome.pending);
      await tester.pump();
      expect(p.pauses, 1);
      p.report(DisplayMatchingOutcome.matched);
      await tester.pump();
      expect(p.plays, 1);
      f.coordinator.dispose();
    });
  }

  testWidgets('continuation holds preserve presentation and carry lateness', (
    tester,
  ) async {
    final f = _ContinuationFixture(player: _DisplayPlayer());
    final p = f.player as _DisplayPlayer;
    addTearDown(f.close);
    await f.coordinator.toggleFullscreen();
    await f.coordinator.tune('channel-b');
    p.decode();
    await tester.pump();
    p.report(DisplayMatchingOutcome.matched);
    await tester.pump();
    f.coordinator.showFullGuide();
    final presentation = f.coordinator.overlayPresentationGeneration;
    f.now = f.now.add(const Duration(seconds: 120));
    f.endNaturally();
    await tester.pump();
    expect(p.pausedStarts, [true, true]);
    expect(f.coordinator.currentProgram!.scheduled.item.id, 'short-1');
    expect(f.coordinator.displayHoldActive, isTrue);
    expect(f.coordinator.overlay, PlayerOverlay.fullGuide);
    p.decode();
    await tester.pump();
    p.report(DisplayMatchingOutcome.matched, wrote: true);
    await tester.pump();
    f.now = f.now.add(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(f.coordinator.overlayPresentationGeneration, presentation);
    expect(p.plays, 2);
    f.now = f.now.add(const Duration(seconds: 118));
    f.endNaturally();
    await tester.pump();
    expect(f.coordinator.currentProgram!.scheduled.item.id, 'short-2');
    expect(p.seeks, isEmpty);
    expect(p.pausedStarts, [true, true, true]);
    f.coordinator.dispose();
  });

  for (final path in [
    'part',
    'recovery',
    'audio',
    'Stop',
    'error',
    'scope',
    'sleep',
    'tune',
    'dispose',
  ]) {
    testWidgets('active display session $path path', (tester) async {
      final p = _DisplayPlayer(audioOnly: path == 'audio');
      final lineup = _TestLineup(
        recoverAuthorization: path == 'recovery',
        playbackParts: path == 'part'
            ? [
                LineupPlaybackPart(
                  uri: Uri.parse('https://synthetic.test/part1'),
                  duration: const Duration(hours: 2),
                ),
                LineupPlaybackPart(
                  uri: Uri.parse('https://synthetic.test/part2'),
                  duration: const Duration(hours: 2),
                ),
              ]
            : null,
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final c = PlayerCoordinator(player: p, lineup: lineup, guide: guide);
      addTearDown(c.dispose);
      addTearDown(guide.dispose);
      addTearDown(lineup.dispose);
      addTearDown(p.close);
      await c.toggleFullscreen();
      await c.tune('channel-b');
      if (path == 'audio') {
        expect(p.pausedStarts, [true]);
        expect(p.plays, 1);
        expect(c.displayHoldActive, isFalse);
        c.dispose();
        return;
      }
      if (path == 'Stop') await c.stop();
      if (path == 'sleep') {
        c.setSleepTimer(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
      if (path == 'tune') await c.tune('channel-0');
      if (path == 'dispose') c.dispose();
      if (path == 'scope') lineup.changeContentScope();
      if (path == 'error') p.emitError(generation: p.loadGenerations.last);
      if (path == 'part') {
        p.decode();
        await tester.pump();
        p.report(DisplayMatchingOutcome.matched);
        await tester.pump();
        p.position = const Duration(hours: 2);
        p.duration = const Duration(hours: 2);
        p.emitStatus(PlayerState.ended, generation: p.loadGenerations.last);
      }
      if (path == 'recovery') {
        p.emitError(
          generation: p.loadGenerations.last,
          failureCode: 'http_error',
          httpStatus: 401,
        );
      }
      await tester.pump();
      if (path == 'part' || path == 'recovery' || path == 'tune') {
        expect(p.pausedStarts, [true, true]);
        expect(c.displayHoldActive, isTrue);
        if (path == 'tune') expect(p.plays, 0);
      } else {
        expect(c.displayHoldActive, isFalse);
        expect(p.plays, 0);
        expect(p.requests.last.session, isFalse);
      }
      c.dispose();
    });
  }

  testWidgets(
    'authorization error cancels rejected hold while recovery waits',
    (tester) async {
      final p = _DisplayPlayer();
      final lineup = _TestLineup(
        recoverAuthorization: true,
        blockAuthorizationRecovery: true,
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final c = PlayerCoordinator(player: p, lineup: lineup, guide: guide);
      addTearDown(c.dispose);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(p.close);
      await c.toggleFullscreen();
      await c.tune('channel-b');
      p.decode();
      await tester.pump();
      p.emitError(
        generation: p.loadGenerations.last,
        failureCode: 'http_error',
        httpStatus: 401,
      );
      await tester.pump();
      expect(c.displayHoldActive, isFalse);
      await tester.pump(const Duration(seconds: 5));
      expect(p.plays, 0);
      expect(p.loads, hasLength(1));
      lineup.finishRecovery.complete();
      await tester.pump();
      expect(p.pausedStarts, [true, true]);
      expect(c.displayHoldActive, isTrue);
      c.dispose();
    },
  );

  testWidgets('replacement error before readiness cancels its paused hold', (
    tester,
  ) async {
    final p = _DisplayPlayer(failReplacementBeforeReady: true);
    final lineup = _TestLineup(recoverAuthorization: true);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final c = PlayerCoordinator(player: p, lineup: lineup, guide: guide);
    addTearDown(c.dispose);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(p.close);
    await c.toggleFullscreen();
    await c.tune('channel-b');
    p.emitError(
      generation: p.loadGenerations.last,
      failureCode: 'http_error',
      httpStatus: 401,
    );
    await tester.pump();
    expect(p.pausedStarts, [true, true]);
    expect(c.displayHoldActive, isFalse);
    await tester.pump(const Duration(seconds: 6));
    expect(p.plays, 0);
    expect(c.overlay, PlayerOverlay.error);
    c.dispose();
  });

  for (final action in ['Play', 'Pause']) {
    testWidgets('user $action during coordinator hold cancels automatic play', (
      tester,
    ) async {
      final f = _ContinuationFixture(player: _DisplayPlayer());
      final p = f.player as _DisplayPlayer;
      addTearDown(f.close);
      await f.coordinator.toggleFullscreen();
      await f.coordinator.loadInitialMedia(
        Uri.parse('https://synthetic.test/local'),
      );
      p.decode();
      await tester.pump();
      if (action == 'Play') {
        await f.coordinator.play();
      } else {
        await f.coordinator.pause();
      }
      p.report(DisplayMatchingOutcome.matched, wrote: true);
      f.now = f.now.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(f.coordinator.displayHoldActive, isFalse);
      expect(p.plays, action == 'Play' ? 1 : 0);
      f.coordinator.dispose();
    });
  }

  for (final firstReady in [PlayerState.ready, PlayerState.playing]) {
    for (final overlay in [
      PlayerOverlay.none,
      PlayerOverlay.osd,
      PlayerOverlay.fullGuide,
      PlayerOverlay.miniGuide,
      PlayerOverlay.nowPlaying,
    ]) {
      test(
        'automatic continuation preserves $overlay through first $firstReady',
        () async {
          final fixture = _ContinuationFixture(
            player: _ContinuationStatePlayer(firstReady),
          );
          addTearDown(fixture.close);
          await fixture.coordinator.tune('channel-b');
          await fixture.coordinator.toggleFullscreen();
          _showPresentation(fixture.coordinator, overlay);
          final presentation =
              fixture.coordinator.overlayPresentationGeneration;
          final observed = <PlayerOverlay>[];
          fixture.coordinator.addListener(
            () => observed.add(fixture.coordinator.overlay),
          );
          fixture.endNaturally();
          await pumpEventQueue(times: 8);
          expect(fixture.player.loads, hasLength(2));
          expect(observed, isNotEmpty);
          expect(observed.every((value) => value == overlay), isTrue);
          expect(fixture.coordinator.overlay, overlay);
          expect(
            fixture.coordinator.overlayPresentationGeneration,
            presentation,
          );
          expect(fixture.coordinator.fullscreen, isTrue);
          expect(fixture.player.fullscreenValues, [true]);
          expect(
            fixture.coordinator.currentProgram!.scheduled.item.id,
            'short-1',
          );
        },
      );
    }
  }

  for (final overlay in [PlayerOverlay.fullGuide, PlayerOverlay.miniGuide]) {
    for (final change in ['open', 'close']) {
      test(
        '$overlay $change during continuation survives readiness and commit',
        () async {
          final player = _BlockingSecondLoadPlayer();
          final fixture = _ContinuationFixture(player: player);
          addTearDown(fixture.close);
          await fixture.coordinator.tune('channel-b');
          await fixture.coordinator.toggleFullscreen();
          if (change == 'close') {
            _showPresentation(fixture.coordinator, overlay);
          }
          fixture.endNaturally();
          await player.secondLoadStarted.future;
          if (change == 'open') {
            _showPresentation(fixture.coordinator, overlay);
          } else {
            fixture.coordinator.closeOverlay();
          }
          final expected = change == 'open' ? overlay : PlayerOverlay.none;
          final presentation =
              fixture.coordinator.overlayPresentationGeneration;
          final observed = <PlayerOverlay>[];
          fixture.coordinator.addListener(
            () => observed.add(fixture.coordinator.overlay),
          );
          for (final state in [
            PlayerState.loading,
            PlayerState.paused,
            PlayerState.buffering,
            PlayerState.seeking,
            PlayerState.playing,
          ]) {
            player.emitStatus(state, generation: player.loadGenerations.last);
          }
          await pumpEventQueue(times: 5);
          player.releaseSecondLoad.complete();
          await pumpEventQueue(times: 8);
          expect(observed.every((value) => value == expected), isTrue);
          expect(fixture.coordinator.overlay, expected);
          expect(
            fixture.coordinator.overlayPresentationGeneration,
            presentation,
          );
          expect(fixture.coordinator.fullscreen, isTrue);
          expect(player.fullscreenValues, [true]);
        },
      );
    }
  }

  for (final firstReady in [PlayerState.ready, PlayerState.playing]) {
    for (final laterState in [PlayerState.loading, PlayerState.paused]) {
      test(
        'continued program resumes manual overlay handling after $firstReady for $laterState',
        () async {
          final manual = _ContinuationFixture();
          final continued = _ContinuationFixture();
          addTearDown(manual.close);
          addTearDown(continued.close);
          await manual.coordinator.tune('channel-b');
          await continued.coordinator.tune('channel-b');
          continued.coordinator.showMiniGuide();
          continued.endNaturally();
          await pumpEventQueue(times: 8);
          for (final fixture in [manual, continued]) {
            fixture.player.emitStatus(
              firstReady,
              generation: fixture.player.loadGenerations.last,
            );
          }
          await pumpEventQueue(times: 2);
          expect(continued.coordinator.overlay, PlayerOverlay.miniGuide);
          for (final fixture in [manual, continued]) {
            if (laterState == PlayerState.loading) {
              fixture.coordinator.showOsd();
            } else {
              fixture.coordinator.showMiniGuide();
            }
            fixture.player.emitStatus(
              laterState,
              generation: fixture.player.loadGenerations.last,
            );
          }
          await pumpEventQueue(times: 2);
          final expected = laterState == PlayerState.loading
              ? PlayerOverlay.none
              : PlayerOverlay.osd;
          expect(manual.coordinator.overlay, expected);
          expect(continued.coordinator.overlay, manual.coordinator.overlay);
        },
      );
    }
  }

  test('manual tune still presents OSD after a presentation-preserving continuation', () async {
    final fixture = _ContinuationFixture();
    addTearDown(fixture.close);
    await fixture.coordinator.tune('channel-b');
    fixture.coordinator.showMiniGuide();
    fixture.endNaturally();
    await pumpEventQueue(times: 8);
    expect(fixture.coordinator.overlay, PlayerOverlay.miniGuide);
    await fixture.coordinator.tune('channel-0');
    expect(fixture.coordinator.overlay, PlayerOverlay.osd);
    fixture.player.emitStatus(
      PlayerState.loading,
      generation: fixture.player.loadGenerations.last,
    );
    await pumpEventQueue(times: 2);
    expect(fixture.coordinator.overlay, PlayerOverlay.none);
    fixture.player.emitStatus(
      PlayerState.ready,
      generation: fixture.player.loadGenerations.last,
    );
    await pumpEventQueue(times: 2);
    expect(fixture.coordinator.overlay, PlayerOverlay.osd);
  });

  test(
    'continuation failure replaces an open Guide with the Retry overlay',
    () async {
      final fixture = _ContinuationFixture(player: _SecondLoadFailurePlayer());
      addTearDown(fixture.close);
      await fixture.coordinator.tune('channel-b');
      fixture.coordinator.showFullGuide();
      fixture.endNaturally();
      await pumpEventQueue(times: 8);
      expect(fixture.coordinator.overlay, PlayerOverlay.error);
      expect(fixture.coordinator.canRetry, isTrue);
    },
  );

  for (final startSeconds in [10, 60, 90]) {
    test(
      'live join at $startSeconds seconds classifies EOF without position telemetry',
      () async {
        final fixture = _ContinuationFixture(
          parts: [
            LineupPlaybackPart(
              uri: Uri.parse('https://media.test/only.mkv'),
              duration: const Duration(seconds: 120),
            ),
          ],
        );
        addTearDown(fixture.close);
        fixture.now = fixture.now.add(Duration(seconds: startSeconds));
        await fixture.coordinator.tune('channel-b');
        expect(fixture.player.seeks, [Duration(seconds: startSeconds)]);
        final loaded = fixture.coordinator.currentProgram!;
        fixture.player.position = Duration.zero;
        fixture.player.duration = const Duration(seconds: 60);
        fixture.player.emitStatus(
          PlayerState.ended,
          generation: fixture.player.loadGenerations.last,
        );
        await pumpEventQueue(times: 8);
        if (startSeconds >= 60) {
          expect(fixture.player.loads, hasLength(2));
          expect(fixture.coordinator.currentProgram!.id, isNot(loaded.id));
          expect(
            fixture.coordinator.currentProgram!.scheduled.item.id,
            'short-1',
          );
          expect(fixture.coordinator.error, isNull);
          expect(fixture.coordinator.hasPlaybackIntent, isTrue);
          expect(fixture.player.seeks, [Duration(seconds: startSeconds)]);
        } else {
          expect(fixture.player.loads, hasLength(1));
          expect(fixture.coordinator.hasPlaybackIntent, isFalse);
          expect(
            fixture.coordinator.error,
            'Playback ended before the program finished.',
          );
          expect(fixture.coordinator.overlay, PlayerOverlay.error);
          expect(fixture.coordinator.canRetry, isTrue);
          expect(fixture.coordinator.status.failureCode, 'premature_end');
        }
      },
    );
  }

  test(
    'positive position after a backward seek replaces live join fallback',
    () async {
      final fixture = _ContinuationFixture();
      addTearDown(fixture.close);
      fixture.now = fixture.now.add(const Duration(seconds: 90));
      await fixture.coordinator.tune('channel-b');
      await fixture.coordinator.seekTo(const Duration(seconds: 10));
      fixture.player.position = const Duration(seconds: 10);
      fixture.player.duration = const Duration(seconds: 60);
      fixture.player.emitStatus(
        PlayerState.playing,
        generation: fixture.player.loadGenerations.last,
      );
      fixture.player.position = Duration.zero;
      fixture.player.emitStatus(
        PlayerState.ended,
        generation: fixture.player.loadGenerations.last,
      );
      await pumpEventQueue(times: 8);
      expect(fixture.player.loads, hasLength(1));
      expect(
        fixture.coordinator.error,
        'Playback ended before the program finished.',
      );
      expect(fixture.coordinator.overlay, PlayerOverlay.error);
      expect(fixture.coordinator.canRetry, isTrue);
    },
  );

  for (final lateness in [-10, 0, 30, 31, 130]) {
    test('continuation at successor lateness $lateness seconds', () async {
      final fixture = _ContinuationFixture();
      addTearDown(fixture.close);
      await fixture.coordinator.tune('channel-b');
      final ended = fixture.coordinator.currentProgram!;
      fixture.now = ended.scheduled.end.add(Duration(seconds: lateness));
      fixture.endNaturally();
      await pumpEventQueue(times: 8);
      final expected = lateness <= 30
          ? 'short-1'
          : lateness < 120
          ? 'short-1'
          : 'short-2';
      expect(fixture.lineup.lastPlaybackItemId, expected);
      expect(fixture.coordinator.currentProgram!.scheduled.item.id, expected);
      expect(fixture.coordinator.currentProgram!.id, isNot(ended.id));
      expect(fixture.player.loads, hasLength(2));
      expect(
        fixture.player.seeks,
        lateness <= 30 ? isEmpty : [Duration(seconds: lateness % 120)],
      );
    });
  }

  test(
    'loaded program and Up next stay with media across the Guide boundary',
    () async {
      final fixture = _ContinuationFixture();
      addTearDown(fixture.close);
      await fixture.coordinator.tune('channel-b');
      final loaded = fixture.coordinator.currentProgram!;
      final successor = fixture.coordinator.nextProgram!;
      fixture.now = loaded.scheduled.end.add(const Duration(seconds: 10));
      expect(fixture.guide.currentProgram('channel-b')!.id, successor.id);
      expect(fixture.coordinator.currentProgram!.id, loaded.id);
      expect(fixture.coordinator.nextProgram!.id, successor.id);
      fixture.endNaturally();
      await pumpEventQueue(times: 8);
      expect(fixture.coordinator.currentProgram!.id, successor.id);
      expect(fixture.coordinator.nextProgram!.scheduled.item.id, 'short-2');
    },
  );

  test(
    'early media completion immediately loads the future successor',
    () async {
      final fixture = _ContinuationFixture();
      addTearDown(fixture.close);
      await fixture.coordinator.tune('channel-b');
      fixture.now = fixture.now.add(const Duration(seconds: 60));
      fixture.endNaturally();
      await pumpEventQueue(times: 8);
      expect(fixture.lineup.lastPlaybackItemId, 'short-1');
      expect(fixture.player.seeks, isEmpty);
    },
  );

  for (final multipart in [false, true]) {
    for (final nativeDuration in [false, true]) {
      test(
        'premature end multipart=$multipart nativeDuration=$nativeDuration retries live',
        () async {
          final fixture = _ContinuationFixture(
            parts: multipart
                ? _parts(
                    first: const Duration(seconds: 120),
                    second: const Duration(seconds: 120),
                  )
                : [
                    LineupPlaybackPart(
                      uri: Uri.parse('https://media.test/only.mkv'),
                      duration: const Duration(seconds: 120),
                    ),
                  ],
          );
          fixture.lineup.diagnostics.enabled = true;
          addTearDown(fixture.close);
          await fixture.coordinator.tune('channel-b');
          fixture.player.position = const Duration(seconds: 20);
          fixture.player.duration = nativeDuration
              ? const Duration(seconds: 60)
              : Duration.zero;
          fixture.player.emitStatus(
            PlayerState.playing,
            generation: fixture.player.loadGenerations.last,
          );
          await pumpEventQueue(times: 2);
          fixture.player.position = Duration.zero;
          fixture.player.duration = Duration.zero;
          fixture.player.emitStatus(
            PlayerState.ended,
            generation: fixture.player.loadGenerations.last,
          );
          await pumpEventQueue(times: 8);
          expect(fixture.player.loads, hasLength(1));
          expect(fixture.coordinator.hasPlaybackIntent, isFalse);
          expect(
            fixture.coordinator.error,
            'Playback ended before the program finished.',
          );
          expect(fixture.coordinator.overlay, PlayerOverlay.error);
          expect(fixture.coordinator.canRetry, isTrue);
          expect(fixture.coordinator.status.failureCode, 'premature_end');
          expect(
            fixture.lineup.diagnostics.entries.single.context['code'],
            'premature_end',
          );
          fixture.now = fixture.now.add(const Duration(seconds: 160));
          await fixture.coordinator.retry();
          expect(fixture.lineup.lastPlaybackItemId, 'short-1');
          expect(fixture.player.seeks.last, const Duration(seconds: 40));
        },
      );
    }
  }

  test(
    'zero terminal values retain native near-end facts and duration preference',
    () async {
      final fixture = _ContinuationFixture(
        parts: [
          LineupPlaybackPart(
            uri: Uri.parse('https://media.test/only.mkv'),
            duration: const Duration(seconds: 120),
          ),
        ],
      );
      addTearDown(fixture.close);
      await fixture.coordinator.tune('channel-b');
      fixture.player.position = const Duration(seconds: 30);
      fixture.player.duration = const Duration(seconds: 60);
      fixture.player.emitStatus(
        PlayerState.playing,
        generation: fixture.player.loadGenerations.last,
      );
      await pumpEventQueue(times: 2);
      fixture.player.position = Duration.zero;
      fixture.player.duration = Duration.zero;
      fixture.player.emitStatus(
        PlayerState.ended,
        generation: fixture.player.loadGenerations.last,
      );
      await pumpEventQueue(times: 8);
      expect(fixture.player.loads, hasLength(2));
      expect(fixture.coordinator.error, isNull);
    },
  );

  test(
    'unknown duration is natural and active stopped retires without advancing',
    () async {
      final fixture = _ContinuationFixture(parts: _parts());
      addTearDown(fixture.close);
      await fixture.coordinator.tune('channel-b');
      fixture.player.duration = Duration.zero;
      fixture.player.position = Duration.zero;
      fixture.player.emitStatus(
        PlayerState.ended,
        generation: fixture.player.loadGenerations.last,
      );
      await pumpEventQueue(times: 5);
      expect(fixture.player.loads, hasLength(2));
      fixture.player.emitStatus(
        PlayerState.playing,
        generation: fixture.player.loadGenerations.last,
      );
      fixture.player.emitStatus(
        PlayerState.stopped,
        generation: fixture.player.loadGenerations.last,
      );
      await pumpEventQueue(times: 5);
      expect(fixture.player.loads, hasLength(2));
      expect(fixture.coordinator.hasPlaybackIntent, isFalse);
      expect(fixture.coordinator.error, isNull);
      fixture.now = fixture.now.add(const Duration(seconds: 130));
      expect(fixture.coordinator.currentProgram!.scheduled.item.id, 'short-1');
    },
  );

  test(
    'part progress resets and premature second part never continues',
    () async {
      final fixture = _ContinuationFixture(
        parts: _parts(
          first: const Duration(seconds: 120),
          second: const Duration(seconds: 120),
        ),
      );
      addTearDown(fixture.close);
      await fixture.coordinator.tune('channel-b');
      fixture.player.position = const Duration(seconds: 120);
      fixture.player.duration = const Duration(seconds: 120);
      fixture.player.emitStatus(
        PlayerState.ended,
        generation: fixture.player.loadGenerations.last,
      );
      await pumpEventQueue(times: 5);
      expect(fixture.player.loads, hasLength(2));
      fixture.player.position = const Duration(seconds: 20);
      fixture.player.duration = Duration.zero;
      fixture.player.emitStatus(
        PlayerState.playing,
        generation: fixture.player.loadGenerations.last,
      );
      fixture.player.emitStatus(
        PlayerState.ended,
        generation: fixture.player.loadGenerations.last,
      );
      await pumpEventQueue(times: 8);
      expect(fixture.player.loads, hasLength(2));
      expect(
        fixture.coordinator.error,
        'Playback ended before the program finished.',
      );
      expect(fixture.coordinator.canRetry, isTrue);
    },
  );

  test('ended during replacing part load cannot advance', () async {
    final player = _BlockingSecondLoadPlayer();
    final fixture = _ContinuationFixture(
      player: player,
      parts: _parts(
        first: const Duration(seconds: 60),
        second: const Duration(seconds: 60),
      ),
    );
    addTearDown(fixture.close);
    await fixture.coordinator.tune('channel-b');
    final seek = fixture.coordinator.seekTo(const Duration(seconds: 65));
    await player.secondLoadStarted.future;
    fixture.endNaturally();
    await pumpEventQueue(times: 5);
    expect(player.loads, hasLength(2));
    player.releaseSecondLoad.complete();
    await seek;
    expect(fixture.coordinator.error, isNull);
    expect(fixture.coordinator.currentProgram!.scheduled.item.id, 'short-0');
    expect(player.seeks.last, const Duration(seconds: 5));
  });

  test(
    'incomplete multipart timing keeps interactive seeks in the active part',
    () async {
      final fixture = _ContinuationFixture(
        parts: [
          LineupPlaybackPart(
            uri: Uri.parse('https://media.test/part-1.mkv'),
            duration: const Duration(seconds: 60),
          ),
          LineupPlaybackPart(uri: Uri.parse('https://media.test/part-2.mkv')),
          LineupPlaybackPart(
            uri: Uri.parse('https://media.test/part-3.mkv'),
            duration: const Duration(seconds: 60),
          ),
        ],
      );
      addTearDown(fixture.close);

      await fixture.coordinator.tune('channel-b');
      fixture.endNaturally();
      await pumpEventQueue(times: 5);
      expect(fixture.player.loads, hasLength(2));

      fixture.player.position = const Duration(seconds: 10);
      fixture.player.duration = const Duration(seconds: 90);
      fixture.player.emitStatus(
        PlayerState.playing,
        generation: fixture.player.loadGenerations.last,
      );
      await pumpEventQueue(times: 2);
      expect(fixture.coordinator.position, const Duration(seconds: 10));
      expect(fixture.coordinator.duration, const Duration(seconds: 90));

      await fixture.coordinator.seekBy(const Duration(seconds: 30));
      expect(fixture.player.loads, hasLength(2));
      expect(fixture.player.seeks.last, const Duration(seconds: 40));

      fixture.player.position = const Duration(seconds: 40);
      fixture.player.emitStatus(
        PlayerState.playing,
        generation: fixture.player.loadGenerations.last,
      );
      await pumpEventQueue(times: 2);
      await fixture.coordinator.seekBy(const Duration(seconds: -30));
      expect(fixture.player.loads, hasLength(2));
      expect(fixture.player.seeks.last, const Duration(seconds: 10));

      await fixture.coordinator.seekTo(const Duration(seconds: 70));
      expect(fixture.player.loads, hasLength(2));
      expect(fixture.player.seeks.last, const Duration(seconds: 70));

      fixture.player.position = const Duration(seconds: 90);
      fixture.player.duration = const Duration(seconds: 90);
      fixture.player.emitStatus(
        PlayerState.ended,
        generation: fixture.player.loadGenerations.last,
      );
      await pumpEventQueue(times: 5);
      expect(fixture.player.loads, hasLength(3));

      fixture.player.position = const Duration(seconds: 7);
      fixture.player.duration = const Duration(seconds: 60);
      fixture.player.emitStatus(
        PlayerState.playing,
        generation: fixture.player.loadGenerations.last,
      );
      await pumpEventQueue(times: 2);
      expect(fixture.coordinator.position, const Duration(seconds: 157));
      expect(fixture.coordinator.duration, const Duration(seconds: 210));
    },
  );

  test(
    'later multipart parts stay local when an earlier boundary is unknown',
    () async {
      final fixture = _ContinuationFixture(
        parts: [
          LineupPlaybackPart(uri: Uri.parse('https://media.test/part-1.mkv')),
          LineupPlaybackPart(
            uri: Uri.parse('https://media.test/part-2.mkv'),
            duration: const Duration(seconds: 90),
          ),
          LineupPlaybackPart(
            uri: Uri.parse('https://media.test/part-3.mkv'),
            duration: const Duration(seconds: 60),
          ),
        ],
      );
      addTearDown(fixture.close);

      await fixture.coordinator.tune('channel-b');
      fixture.player.position = Duration.zero;
      fixture.player.duration = Duration.zero;
      fixture.player.emitStatus(
        PlayerState.ended,
        generation: fixture.player.loadGenerations.last,
      );
      await pumpEventQueue(times: 5);
      expect(fixture.player.loads, hasLength(2));

      fixture.player.position = const Duration(seconds: 10);
      fixture.player.duration = const Duration(seconds: 90);
      fixture.player.emitStatus(
        PlayerState.playing,
        generation: fixture.player.loadGenerations.last,
      );
      await pumpEventQueue(times: 2);
      expect(fixture.coordinator.position, const Duration(seconds: 10));
      expect(fixture.coordinator.duration, const Duration(seconds: 90));

      await fixture.coordinator.seekBy(const Duration(seconds: 30));
      expect(fixture.player.loads, hasLength(2));
      expect(fixture.player.seeks.last, const Duration(seconds: 40));
    },
  );

  test('complete multipart timing keeps aggregate seek coordinates', () async {
    final fixture = _ContinuationFixture(
      parts: _parts(
        first: const Duration(seconds: 60),
        second: const Duration(seconds: 90),
      ),
    );
    addTearDown(fixture.close);

    await fixture.coordinator.tune('channel-b');
    fixture.endNaturally();
    await pumpEventQueue(times: 5);
    fixture.player.position = const Duration(seconds: 10);
    fixture.player.duration = const Duration(seconds: 90);
    fixture.player.emitStatus(
      PlayerState.playing,
      generation: fixture.player.loadGenerations.last,
    );
    await pumpEventQueue(times: 2);

    expect(fixture.coordinator.position, const Duration(seconds: 70));
    expect(fixture.coordinator.duration, const Duration(seconds: 150));
    await fixture.coordinator.seekBy(const Duration(seconds: 30));
    expect(fixture.player.loads, hasLength(2));
    expect(fixture.player.seeks.last, const Duration(seconds: 40));

    await fixture.coordinator.seekTo(const Duration(seconds: 30));
    await pumpEventQueue(times: 2);
    expect(fixture.player.loads, hasLength(3));
    expect(fixture.player.loads.last.path, '/part-1.mkv');
    expect(fixture.player.seeks.last, const Duration(seconds: 30));
  });

  test(
    'incomplete multipart pending readiness keeps only the latest local target',
    () async {
      final player = _BlockingSecondLoadPlayer();
      final fixture = _ContinuationFixture(
        player: player,
        parts: _parts(first: const Duration(seconds: 60), second: null),
      );
      addTearDown(fixture.close);

      await fixture.coordinator.tune('channel-b');
      fixture.endNaturally();
      await player.secondLoadStarted.future;

      final first = fixture.coordinator.seekTo(const Duration(seconds: 20));
      final latest = fixture.coordinator.seekTo(const Duration(seconds: 40));
      player.releaseSecondLoad.complete();
      await Future.wait([first, latest]);

      expect(fixture.player.loads.map((uri) => uri.path), [
        '/part-1.mkv',
        '/part-2.mkv',
      ]);
      expect(fixture.player.seeks, [const Duration(seconds: 40)]);
    },
  );

  test(
    'incomplete multipart local targets survive authorization replacement',
    () async {
      final player = _BlockingFailingPartAuthorizationRetryPlayer(fail: false);
      final fixture = _ContinuationFixture(
        player: player,
        recoverAuthorization: true,
        parts: _parts(first: const Duration(seconds: 60), second: null),
      );
      addTearDown(fixture.close);

      await fixture.coordinator.tune('channel-b');
      fixture.endNaturally();
      await player.retryLoadStarted.future;

      final first = fixture.coordinator.seekTo(const Duration(seconds: 20));
      final latest = fixture.coordinator.seekTo(const Duration(seconds: 40));
      player.releaseRetryLoad.complete();
      await Future.wait([first, latest]);

      expect(fixture.player.loads.map((uri) => uri.path), [
        '/part-1.mkv',
        '/part-2.mkv',
        '/part-2.mkv',
      ]);
      expect(fixture.player.loadPlexTokens, [
        'test-token-1',
        'test-token-1',
        'test-token-2',
      ]);
      expect(fixture.player.seeks, [const Duration(seconds: 40)]);
      expect(fixture.coordinator.error, isNull);

      await fixture.coordinator.seekTo(const Duration(seconds: 10));
      expect(fixture.player.loads, hasLength(3));
      expect(fixture.player.seeks, [
        const Duration(seconds: 40),
        const Duration(seconds: 10),
      ]);
    },
  );

  for (final action in ['tune', 'stop']) {
    test('incomplete multipart continuation is stale after $action', () async {
      final player = _BlockingSecondLoadPlayer();
      final fixture = _ContinuationFixture(
        player: player,
        parts: _parts(first: const Duration(seconds: 60), second: null),
      );
      addTearDown(fixture.close);

      await fixture.coordinator.tune('channel-b');
      fixture.endNaturally();
      await player.secondLoadStarted.future;
      final staleGeneration = player.loadGenerations.last;
      final replacement = action == 'tune'
          ? fixture.coordinator.tune('channel-0')
          : fixture.coordinator.stop();
      player.releaseSecondLoad.complete();
      await replacement;
      await pumpEventQueue(times: 8);

      player.emitStatus(PlayerState.ended, generation: staleGeneration);
      await pumpEventQueue(times: 2);
      expect(fixture.player.loads, hasLength(action == 'tune' ? 3 : 2));
      expect(fixture.coordinator.error, isNull);
      expect(fixture.coordinator.hasPlaybackIntent, action == 'tune');
      expect(
        fixture.lineup.currentChannelId,
        action == 'tune' ? 'channel-0' : 'channel-b',
      );
    });
  }

  test(
    'active final-part stopped retires loaded info without continuation',
    () async {
      final fixture = _ContinuationFixture();
      addTearDown(fixture.close);
      await fixture.coordinator.tune('channel-b');
      fixture.player.emitStatus(
        PlayerState.stopped,
        generation: fixture.player.loadGenerations.last,
      );
      await pumpEventQueue(times: 5);
      fixture.now = fixture.now.add(const Duration(seconds: 130));
      expect(fixture.player.loads, hasLength(1));
      expect(fixture.coordinator.hasPlaybackIntent, isFalse);
      expect(fixture.coordinator.currentProgram!.scheduled.item.id, 'short-1');
      expect(fixture.coordinator.nextProgram!.scheduled.item.id, 'short-2');
      expect(fixture.coordinator.error, isNull);
    },
  );

  for (final action in ['tune', 'stop', 'content', 'dispose', 'sleep']) {
    test('$action supersedes a pending continuation load', () async {
      final player = _BlockingSecondLoadPlayer();
      final fixture = _ContinuationFixture(player: player);
      addTearDown(fixture.close);
      await fixture.coordinator.tune('channel-b');
      fixture.endNaturally();
      await player.secondLoadStarted.future;
      expect(fixture.coordinator.currentProgram!.scheduled.item.id, 'short-1');
      Future<void>? pending;
      switch (action) {
        case 'tune':
          pending = fixture.coordinator.tune('channel-0');
        case 'stop':
          pending = fixture.coordinator.stop();
        case 'content':
          fixture.lineup.changeContentScope();
        case 'dispose':
          fixture.coordinator.dispose();
          fixture.disposed = true;
        case 'sleep':
          fixture.coordinator.setSleepTimer(const Duration(seconds: 1));
          fixture.now = fixture.now.add(const Duration(seconds: 2));
          pending = fixture.coordinator.checkSleepDeadline();
      }
      player.releaseSecondLoad.complete();
      await pending;
      await pumpEventQueue(times: 8);
      expect(fixture.coordinator.hasPlaybackIntent, action == 'tune');
      expect(fixture.coordinator.error, isNull);
      if (action == 'tune') {
        expect(fixture.lineup.currentChannelId, 'channel-0');
        expect(player.loads, hasLength(3));
      } else {
        expect(player.loads, hasLength(2));
      }
    });
  }

  test('expired sleep deadline wins at the boundary', () async {
    final fixture = _ContinuationFixture();
    addTearDown(fixture.close);
    await fixture.coordinator.tune('channel-b');
    fixture.coordinator.setSleepTimer(const Duration(seconds: 120));
    expect(fixture.coordinator.sleepRemaining, const Duration(seconds: 120));
    expect(
      fixture.coordinator.sleepDeadline,
      fixture.now.add(const Duration(seconds: 120)),
    );
    fixture.now = fixture.now.add(const Duration(seconds: 120));
    fixture.endNaturally();
    await pumpEventQueue(times: 8);
    expect(fixture.player.loads, hasLength(1));
    expect(fixture.coordinator.hasPlaybackIntent, isFalse);
    expect(fixture.coordinator.status.message, 'Playback stopped by timer');
  });

  test(
    'failed continuation does not retry until ordinary live Retry',
    () async {
      final fixture = _ContinuationFixture(player: _SecondLoadFailurePlayer());
      addTearDown(fixture.close);
      await fixture.coordinator.tune('channel-b');
      fixture.endNaturally();
      await pumpEventQueue(times: 10);
      expect(fixture.player.loads, hasLength(2));
      expect(fixture.coordinator.overlay, PlayerOverlay.error);
      expect(fixture.coordinator.canRetry, isTrue);
      await pumpEventQueue(times: 10);
      expect(fixture.player.loads, hasLength(2));
      fixture.now = fixture.now.add(const Duration(seconds: 160));
      await fixture.coordinator.retry();
      expect(fixture.player.loads, hasLength(3));
      expect(fixture.player.seeks.last, const Duration(seconds: 40));
    },
  );

  for (final resolution in ['null', 'missing successor', 'same successor']) {
    test(
      'continuation resolution $resolution retires or falls back safely',
      () async {
        final fixture = _ContinuationFixture();
        addTearDown(fixture.close);
        await fixture.coordinator.tune('channel-b');
        fixture.guide.resolution = resolution;
        if (resolution == 'missing successor') {
          fixture.now = fixture.now.add(const Duration(seconds: 160));
        }
        fixture.endNaturally();
        await pumpEventQueue(times: 8);
        expect(fixture.coordinator.error, isNull);
        if (resolution == 'missing successor') {
          expect(fixture.player.loads, hasLength(2));
          expect(fixture.player.seeks.last, const Duration(seconds: 40));
        } else {
          expect(fixture.player.loads, hasLength(1));
          expect(fixture.coordinator.hasPlaybackIntent, isFalse);
          expect(fixture.coordinator.canRetry, isFalse);
        }
      },
    );
  }

  testWidgets(
    'position publication is bucketed while seek and recovery stay exact',
    (tester) async {
      final lineup = _TestLineup(recoverAuthorization: true);
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final player = _EventPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);
      await coordinator.tune('channel-b');
      final generation = player.loadGenerations.single;
      player.position = const Duration(minutes: 10);
      player.emitStatus(PlayerState.playing, generation: generation);
      await tester.pump();
      var notifications = 0;
      coordinator.addListener(() => notifications++);
      for (var frame = 1; frame <= 60; frame++) {
        player.position = Duration(milliseconds: 600000 + frame * 1000 ~/ 60);
        player.emitStatus(PlayerState.playing, generation: generation);
        await tester.pump();
      }
      expect(notifications, 4);
      player.position = const Duration(milliseconds: 601007);
      player.emitStatus(PlayerState.playing, generation: generation);
      await tester.pump();
      expect(notifications, 4);
      expect(coordinator.position, player.position);
      player.emitError(
        recoverable: true,
        generation: generation,
        failureCode: 'http_error',
        httpStatus: 401,
      );
      await tester.pump();
      await tester.pump();
      expect(lineup.recoveryCalls, 1);
      expect(player.seeks.last, const Duration(milliseconds: 601007));
      final replacement = player.loadGenerations.last;
      player.emitStatus(PlayerState.playing, generation: replacement);
      await tester.pump();
      await coordinator.seekBy(const Duration(seconds: 5));
      expect(player.seeks.last, const Duration(milliseconds: 606007));
      final beforeStatus = notifications;
      player.emitStatus(PlayerState.paused, generation: replacement);
      await tester.pump();
      expect(notifications, greaterThan(beforeStatus));
      final beforeTracks = notifications;
      player.tracks = const [
        PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: true),
      ];
      player.emitStatus(PlayerState.paused, generation: replacement);
      await tester.pump();
      expect(notifications, beforeTracks + 1);
      final beforeTelemetry = notifications;
      player.telemetry = const PlayerTelemetry(videoCodec: 'h264');
      player.emitStatus(PlayerState.paused, generation: replacement);
      await tester.pump();
      expect(notifications, beforeTelemetry + 1);
      final beforeDuration = notifications;
      player.duration = const Duration(hours: 2);
      player.emitStatus(PlayerState.paused, generation: replacement);
      await tester.pump();
      expect(notifications, beforeDuration + 1);
      final beforeOverlay = notifications;
      coordinator.showMiniGuide();
      expect(notifications, beforeOverlay + 1);
    },
  );

  testWidgets('number notices expire and newer input and tunes replace them', (
    tester,
  ) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _Player();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(coordinator.dispose);
    addTearDown(guide.dispose);
    addTearDown(lineup.dispose);
    coordinator.appendChannelDigit('9');
    expect(coordinator.channelNumberLabel, '9 · Channel 1');
    await tester.pump(const Duration(milliseconds: 1999));
    expect(lineup.currentChannelId, 'channel-0');
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(lineup.currentChannelId, 'channel-b');
    coordinator.appendChannelDigit('7');
    await tester.pump(const Duration(seconds: 2));
    expect(coordinator.notice, 'Not in this lineup');
    expect(coordinator.error, isNull);
    expect(coordinator.status.state, PlayerState.playing);
    await tester.pump(const Duration(milliseconds: 2999));
    expect(coordinator.notice, isNotNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(coordinator.notice, isNull);
    coordinator.appendChannelDigit('7');
    await coordinator.commitChannelNumber();
    await tester.pump(const Duration(seconds: 1));
    coordinator.appendChannelDigit('9');
    expect(coordinator.notice, isNull);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(lineup.currentChannelId, 'channel-b');
    expect(coordinator.notice, isNull);
    coordinator.appendChannelDigit('9');
    await coordinator.tune('channel-0');
    await tester.pump(const Duration(seconds: 3));
    expect(lineup.currentChannelId, 'channel-0');
    expect(coordinator.channelNumber, isEmpty);
    coordinator.appendChannelDigit('9');
    coordinator.closeOverlay();
    await tester.pump(const Duration(seconds: 3));
    expect(lineup.currentChannelId, 'channel-0');
    coordinator.closeOverlay();
  });

  testWidgets(
    'busy labels wait two seconds and reject obsolete native and scope state',
    (tester) async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final player = _EventPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(coordinator.dispose);
      addTearDown(player.close);
      addTearDown(guide.dispose);
      addTearDown(lineup.dispose);
      await coordinator.tune('channel-b');
      final generation = player.loadGenerations.last;
      player.emitStatus(PlayerState.loading, generation: generation);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1999));
      expect(coordinator.busyLabel, isNull);
      await tester.pump(const Duration(milliseconds: 1));
      expect(coordinator.busyLabel, 'Starting playback…');
      player.emitStatus(PlayerState.ready, generation: generation);
      await tester.pump();
      expect(coordinator.busyLabel, isNull);
      player.emitStatus(PlayerState.buffering, generation: generation);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      player.emitStatus(PlayerState.playing, generation: generation);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(coordinator.busyLabel, isNull);
      player.emitStatus(PlayerState.buffering, generation: generation);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(coordinator.busyLabel, 'Buffering…');
      lineup.changeContentScope();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(coordinator.busyLabel, isNull);
      player.emitStatus(PlayerState.buffering, generation: generation);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(coordinator.busyLabel, isNull);
      player.emitStatus(PlayerState.loading);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      var lateNotifications = 0;
      coordinator.addListener(() => lateNotifications++);
      coordinator.dispose();
      await tester.pump(const Duration(seconds: 3));
      expect(lateNotifications, 0);
    },
  );

  for (final state in [PlayerState.loading, PlayerState.buffering]) {
    for (final delay in [
      const Duration(seconds: 1),
      const Duration(seconds: 3),
    ]) {
      testWidgets(
        '${state.name} stop publishes completion after ${delay.inSeconds}s',
        (tester) async {
          final lineup = _TestLineup();
          final guide = GuideController(
            lineup: lineup,
            loadSchedule: (channel) async => _schedule(channel),
          );
          final player = _BlockingStopEventPlayer();
          final coordinator = PlayerCoordinator(
            player: player,
            lineup: lineup,
            guide: guide,
            overlayTimeout: const Duration(minutes: 1),
          );
          addTearDown(coordinator.dispose);
          addTearDown(player.close);
          addTearDown(guide.dispose);
          addTearDown(lineup.dispose);
          await coordinator.tune('channel-b');
          player.emitStatus(state, generation: player.loadGenerations.last);
          await tester.pump();

          final stop = coordinator.stop();
          await tester.pump();
          expect(player.stopStarted.isCompleted, isTrue);
          await tester.pump(delay);
          expect(coordinator.status.state, state);
          expect(
            coordinator.busyLabel,
            delay.inSeconds < 2
                ? isNull
                : state == PlayerState.buffering
                ? 'Buffering…'
                : 'Starting playback…',
          );
          final publications = <(PlayerState, String?)>[];
          coordinator.addListener(
            () => publications.add((
              coordinator.status.state,
              coordinator.busyLabel,
            )),
          );
          player.releaseStop.complete();
          await tester.pump();
          await stop;
          expect(coordinator.status.state, PlayerState.stopped);
          expect(coordinator.busyLabel, isNull);
          expect(publications, [(PlayerState.stopped, null)]);
          await tester.pump(const Duration(seconds: 3));
          expect(coordinator.busyLabel, isNull);
          expect(publications, [(PlayerState.stopped, null)]);
          coordinator.dispose();
        },
      );
    }
  }

  for (final supersededBy in ['disposal', 'tune']) {
    testWidgets('pending stop rejects final publication after $supersededBy', (
      tester,
    ) async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final player = _BlockingStopEventPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
        overlayTimeout: const Duration(minutes: 1),
      );
      addTearDown(coordinator.dispose);
      addTearDown(player.close);
      addTearDown(guide.dispose);
      addTearDown(lineup.dispose);
      await coordinator.tune('channel-b');
      await guide.ensureCurrentProgram('channel-0');
      player.emitStatus(
        PlayerState.loading,
        generation: player.loadGenerations.last,
      );
      await tester.pump();
      final stop = coordinator.stop();
      await tester.pump();
      expect(player.stopStarted.isCompleted, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(coordinator.busyLabel, 'Starting playback…');
      final publications = <PlayerState>[];
      coordinator.addListener(() => publications.add(coordinator.status.state));
      Future<bool>? replacement;
      if (supersededBy == 'disposal') {
        coordinator.dispose();
      } else {
        replacement = coordinator.tune('channel-0');
      }
      publications.clear();
      player.releaseStop.complete();
      await tester.pump();
      await stop;
      if (replacement != null) {
        expect(await replacement, isTrue);
        expect(lineup.currentChannelId, 'channel-0');
        expect(coordinator.status.state, PlayerState.playing);
        expect(publications, isNot(contains(PlayerState.stopped)));
      } else {
        expect(publications, isEmpty);
      }
      expect(coordinator.busyLabel, isNull);
      await tester.pump(const Duration(seconds: 3));
      expect(coordinator.busyLabel, isNull);
      coordinator.dispose();
    });
  }

  testWidgets(
    'control notices expire after six seconds without a blocking error',
    (tester) async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final coordinator = PlayerCoordinator(
        player: _FailingControlPlayer(),
        lineup: lineup,
        guide: guide,
      );
      addTearDown(coordinator.dispose);
      addTearDown(guide.dispose);
      addTearDown(lineup.dispose);
      await coordinator.pause();
      await tester.pump(const Duration(milliseconds: 5999));
      expect(coordinator.notice, isNotNull);
      expect(coordinator.error, isNull);
      await tester.pump(const Duration(milliseconds: 1));
      expect(coordinator.notice, isNull);
      await coordinator.pause();
      lineup.changeContentScope();
      await tester.pump(const Duration(seconds: 6));
      expect(coordinator.notice, isNull);
    },
  );

  for (final failure in ['timeout', 'command_error', 'private-native-code']) {
    test(
      'native $failure retains cleanup through failed stop and logout',
      () async {
        const channel = MethodChannel('lineup/native_player');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final lineup = _LogoutLineup()..diagnostics.enabled = true;
        final guide = GuideController(
          lineup: lineup,
          loadSchedule: (channel) async => _schedule(channel),
        );
        final player = WindowsNativePlayer(
          loadTimeout: failure == 'timeout' ? Duration.zero : null,
        );
        await player.initialize();
        final coordinator = PlayerCoordinator(
          player: player,
          lineup: lineup,
          guide: guide,
        );
        addTearDown(lineup.dispose);
        addTearDown(guide.dispose);
        addTearDown(player.dispose);
        addTearDown(coordinator.dispose);
        final tune = coordinator.tune('channel-b');
        while (!calls.any((call) => call.method == 'load')) {
          await Future<void>.delayed(Duration.zero);
        }
        final loadId = calls
            .firstWhere((call) => call.method == 'load')
            .arguments['loadId'];
        if (failure != 'timeout') {
          await _nativeEvent({
            'type': 'state',
            'loadId': loadId,
            'state': 'playing',
          });
          expect(await tune, isTrue);
          await _nativeEvent({
            'type': 'state',
            'loadId': loadId,
            'state': 'error',
            'failureCode': failure,
          });
        }
        if (failure != 'timeout') {
          await pumpEventQueue(times: 2);
          final category = failure == 'command_error'
              ? failure
              : 'native_error';
          expect(coordinator.status.failureCode, category);
          final report = _supportReport(lineup, coordinator);
          expect(report, contains('failureCode=$category'));
          expect(report, isNot(contains('private-native-code')));
        }
        while (!calls.any((call) => call.method == 'stop')) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        final firstStop = calls.last.arguments['stopId'];
        await _nativeEvent({
          'type': 'state',
          'loadId': loadId,
          'state': 'playing',
        });
        expect(coordinator.status.state, isNot(PlayerState.playing));
        await _nativeEvent({
          'type': 'stopResult',
          'stopId': firstStop,
          'success': false,
        });
        await tune;
        await pumpEventQueue(times: 2);
        expect(calls.where((call) => call.method == 'stop'), hasLength(1));
        expect(await coordinator.logout(), isFalse);
        final logout = coordinator.logout();
        await pumpEventQueue(times: 2);
        final stops = calls.where((call) => call.method == 'stop').toList();
        expect(stops, hasLength(2));
        final secondStop = stops.last.arguments['stopId'];
        expect(secondStop, isNot(firstStop));
        await _nativeEvent({
          'type': 'stopResult',
          'stopId': firstStop,
          'success': true,
        });
        await _nativeEvent({
          'type': 'stopResult',
          'stopId': secondStop,
          'success': true,
        });
        expect(await logout, isTrue);
        expect(coordinator.hasPlaybackIntent, isFalse);
        expect(player.status.state, PlayerState.stopped);
      },
    );
  }

  test(
    'native replacement waits for failure cleanup and ignores retired events',
    () async {
      const channel = MethodChannel('lineup/native_player');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final player = WindowsNativePlayer();
      await player.initialize();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(player.dispose);
      addTearDown(coordinator.dispose);
      final tune = coordinator.tune('channel-b');
      await pumpEventQueue(times: 2);
      final firstId = calls.last.arguments['loadId'];
      await _nativeEvent({
        'type': 'state',
        'loadId': firstId,
        'state': 'playing',
      });
      expect(await tune, isTrue);
      await _nativeEvent({
        'type': 'state',
        'loadId': firstId,
        'state': 'error',
        'failureCode': 'command_error',
      });
      final replacement = coordinator.tune('channel-0');
      await pumpEventQueue(times: 2);
      expect(calls.where((call) => call.method == 'stop'), hasLength(1));
      expect(calls.where((call) => call.method == 'load'), hasLength(1));
      final stopId = calls.last.arguments['stopId'];
      await _nativeEvent({
        'type': 'stopResult',
        'stopId': stopId,
        'success': true,
      });
      await pumpEventQueue(times: 2);
      final replacementId = calls.last.arguments['loadId'];
      expect(replacementId, isNot(firstId));
      await _nativeEvent({
        'type': 'state',
        'loadId': firstId,
        'state': 'error',
        'failureCode': 'command_error',
      });
      await _nativeEvent({
        'type': 'state',
        'loadId': replacementId,
        'state': 'playing',
      });
      expect(await replacement, isTrue);
      expect(calls.where((call) => call.method == 'stop'), hasLength(1));
      expect(coordinator.error, isNull);
    },
  );

  test(
    'Player tunes the current projection of retained manual content',
    () async {
      final lineup = _TestLineup(count: 1);
      final original = lineup.channels.single;
      lineup
        ..fixtureActor.publishInventory(
          media: [
            PlexMediaItem(
              id: 'current',
              title: 'Current title',
              type: 'movie',
              duration: const Duration(hours: 24),
              parts: [PlexMediaPart(path: '/current')],
            ),
          ],
        )
        ..fixtureActor.replaceChannels([
          Channel(
            id: original.id,
            number: original.number,
            name: original.name,
            source: const ManualSource([
              ChannelItem(
                id: 'current',
                title: 'Stored title',
                duration: Duration(hours: 24),
              ),
              ChannelItem(
                id: 'missing',
                title: 'Missing',
                duration: Duration(hours: 24),
              ),
            ]),
            playbackMode: PlaybackMode.sequential,
            anchor: DateTime.now().subtract(const Duration(hours: 1)),
            shuffleSeed: 1,
          ),
        ])
        ..fixtureActor.replaceConnection(
          PlexConnection(
            uri: Uri.parse('https://player.example:32400'),
            local: true,
            relay: false,
          ),
        );
      final guide = GuideController(lineup: lineup)..requestViewport(0, 1);
      final player = _Player();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);
      expect(await guide.ensureCurrentProgram(original.id), isNotNull);

      await coordinator.tune(original.id);

      expect(lineup.lastPlaybackItemId, 'current');
      expect(
        guide.currentProgram(original.id)?.scheduled.item.title,
        'Current title',
      );
    },
  );

  test(
    'tune dispatches load, wall-clock seek, and stable current identity',
    () async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      guide.requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _Player();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      final tuned = await coordinator.tune('channel-b');

      expect(
        player.loads.single,
        Uri.parse('https://media.test/program?quality=original'),
      );
      expect(player.loadPlexTokens.single, 'test-token');
      expect(player.seeks.single, greaterThanOrEqualTo(Duration.zero));
      expect(lineup.currentChannelId, 'channel-b');
      expect(coordinator.overlay, PlayerOverlay.osd);
      expect(tuned, isTrue);
      await coordinator.stop();
    },
  );

  test('missing Guide program reports tune failure', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (_) async => throw TimeoutException('missing'),
    );
    final coordinator = PlayerCoordinator(
      player: _Player(),
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    expect(await coordinator.tune('channel-b'), isFalse);
    expect(coordinator.error, 'The current program could not be loaded.');
  });

  test('native stop failure reports replacement tune failure', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _FailingStopPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    expect(await coordinator.tune('channel-b'), isTrue);
    expect(await coordinator.tune('channel-0'), isFalse);
    expect(lineup.currentChannelId, 'channel-b');
  });

  test('current-channel persistence failure reports tune failure', () async {
    final lineup = _FailingPersistenceLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final coordinator = PlayerCoordinator(
      player: _Player(),
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    expect(await coordinator.tune('channel-b'), isFalse);
    expect(lineup.currentChannelId, 'channel-0');
    expect(coordinator.overlay, PlayerOverlay.error);
  });

  test('scope change stops playback and clears its intent', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final nativePlayer = _Player();
    final coordinator = PlayerCoordinator(
      player: nativePlayer,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');
    coordinator.showMiniGuide();
    coordinator.setSleepTimer(const Duration(minutes: 30));
    lineup.changeContentScope();
    await Future<void>.delayed(Duration.zero);

    expect(nativePlayer.stops, 1);
    expect(coordinator.hasPlaybackIntent, isFalse);
    expect(coordinator.overlay, PlayerOverlay.none);
    expect(coordinator.sleepDuration, isNull);
  });

  test('scope cleanup does not notify after disposal', () async {
    final lineup = _TestLineup()..diagnostics.enabled = true;
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final nativePlayer = _BlockingFullscreenPlayer(blockOn: false);
    final coordinator = PlayerCoordinator(
      player: nativePlayer,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');
    await coordinator.toggleFullscreen();
    lineup.changeContentScope();
    await nativePlayer.fullscreenStarted.future;
    coordinator.dispose();
    nativePlayer.releaseFullscreen.complete();
    await Future<void>.delayed(Duration.zero);

    expect(lineup.diagnostics.entries, isEmpty);
  });

  test('pending fullscreen changes do not notify after disposal', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final nativePlayer = _BlockingFullscreenPlayer(blockOn: true);
    final coordinator = PlayerCoordinator(
      player: nativePlayer,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final fullscreen = coordinator.toggleFullscreen();
    await nativePlayer.fullscreenStarted.future;
    coordinator.dispose();
    nativePlayer.releaseFullscreen.complete();

    await fullscreen;
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.fullscreen, isFalse);
    expect(nativePlayer.fullscreenValues, [true, false]);
  });

  test(
    'rapid fullscreen toggles execute from committed native state',
    () async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final nativePlayer = _Player();
      final coordinator = PlayerCoordinator(
        player: nativePlayer,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      await Future.wait([
        coordinator.toggleFullscreen(),
        coordinator.toggleFullscreen(),
      ]);

      expect(nativePlayer.fullscreenValues, [true, false]);
      expect(coordinator.fullscreen, isFalse);
    },
  );

  test('scope cleanup exits after a pending fullscreen enter', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final nativePlayer = _BlockingFullscreenPlayer(blockOn: true);
    final coordinator = PlayerCoordinator(
      player: nativePlayer,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    await coordinator.tune('channel-b');

    final enter = coordinator.toggleFullscreen();
    await nativePlayer.fullscreenStarted.future;
    lineup.changeContentScope();
    nativePlayer.releaseFullscreen.complete();
    await enter;
    await pumpEventQueue(times: 3);

    expect(nativePlayer.fullscreenValues, [true, false]);
    expect(coordinator.fullscreen, isFalse);
  });

  test('pending seek does not notify after disposal', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _BlockingControlPlayer();
    addTearDown(player.close);
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final seek = coordinator.seekTo(const Duration(seconds: 1));
    await player.seekStarted.future;
    coordinator.dispose();
    player.releaseSeek.complete();

    await seek;
    expect(coordinator.overlay, PlayerOverlay.none);
  });

  test('pending track selection does not notify after disposal', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _BlockingControlPlayer();
    addTearDown(player.close);
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final select = coordinator.selectTrack(PlayerTrackType.audio, 1);
    await player.selectStarted.future;
    coordinator.dispose();
    player.releaseSelect.complete();

    await select;
    expect(coordinator.overlay, PlayerOverlay.none);
  });

  test('rapid track intent waits for the latest native confirmation', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _BlockingControlPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(player.close);
    addTearDown(coordinator.dispose);

    final first = coordinator.selectTrack(PlayerTrackType.audio, 1);
    await player.selectStarted.future;
    final second = coordinator.selectTrack(PlayerTrackType.audio, 2);
    expect(coordinator.pendingTrackId, 2);
    player.releaseSelect.complete();
    await Future.wait([first, second]);
    expect(player.selectedTracks, [
      (PlayerTrackType.audio, 1),
      (PlayerTrackType.audio, 2),
    ]);

    player.tracks = const [
      PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: true),
      PlayerTrack(id: 2, type: PlayerTrackType.audio, selected: false),
    ];
    player.emitStatus(PlayerState.playing);
    await pumpEventQueue();
    expect(coordinator.pendingTrackId, 2);

    player.tracks = const [
      PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: false),
      PlayerTrack(id: 2, type: PlayerTrackType.audio, selected: true),
    ];
    player.emitStatus(PlayerState.playing);
    await pumpEventQueue();
    expect(coordinator.pendingTrackType, isNull);
  });

  testWidgets('track selection fails when native confirmation never arrives', (
    tester,
  ) async {
    final lineup = _TestLineup()..diagnostics.enabled = true;
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _Player();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.selectTrack(PlayerTrackType.audio, 2);
    expect(coordinator.pendingTrackId, 2);

    await tester.pump(const Duration(seconds: 5));

    expect(coordinator.pendingTrackType, isNull);
    expect(coordinator.pendingTrackId, isNull);
    expect(
      coordinator.trackSelectionError,
      'Could not change this track. Try again.',
    );
    expect(lineup.diagnostics.entries.single.context, {
      'operation': 'audio_track',
      'code': 'wait_timeout',
    });
  });

  testWidgets('confirmed selection cancels its failure deadline', (
    tester,
  ) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _EventPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(player.close);
    addTearDown(coordinator.dispose);

    await coordinator.selectTrack(PlayerTrackType.audio, 1);
    player.tracks = const [
      PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: true),
    ];
    player.emitStatus(PlayerState.playing);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    expect(coordinator.pendingTrackType, isNull);
    expect(coordinator.trackSelectionError, isNull);
  });

  testWidgets('new track selection receives a fresh confirmation deadline', (
    tester,
  ) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final coordinator = PlayerCoordinator(
      player: _Player(),
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.selectTrack(PlayerTrackType.audio, 1);
    await tester.pump(const Duration(seconds: 4));
    await coordinator.selectTrack(PlayerTrackType.audio, 2);
    await tester.pump(const Duration(seconds: 1));

    expect(coordinator.pendingTrackId, 2);
    expect(coordinator.trackSelectionError, isNull);

    await tester.pump(const Duration(seconds: 4));
    expect(coordinator.pendingTrackType, isNull);
    expect(
      coordinator.trackSelectionError,
      'Could not change this track. Try again.',
    );
  });

  test('unrelated control does not strand a pending track failure', () async {
    final lineup = _TestLineup()..diagnostics.enabled = true;
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _BlockingFailingTrackPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final selection = coordinator.selectTrack(PlayerTrackType.audio, 2);
    await player.selectStarted.future;
    await coordinator.play();
    player.releaseSelect.complete();
    await selection;

    expect(coordinator.pendingTrackType, isNull);
    expect(coordinator.pendingTrackId, isNull);
    expect(
      coordinator.trackSelectionError,
      'Could not change this track. Try again.',
    );
    expect(player.plays, 1);
    expect(lineup.diagnostics.entries.single.context, {
      'operation': 'audio_track',
      'code': 'command_error',
    });
    final report = lineup.diagnostics.buildSupportReport(
      lineup.diagnostics.snapshot(
        reportTime: DateTime.utc(2026, 10, 12),
        timeZone: 'UTC',
        appVersion: '1',
        appBuild: '42@e83778169ea6e00217140981213425c3ecae5358',
        platform: 'windows',
        plexServerSelected: false,
        plexConnectionVerified: false,
        playback: coordinator.diagnosticPlaybackSnapshot,
      ),
    );
    expect(report, contains('operation=audio_track, code=command_error'));
  });

  for (final failure in const {
    'command_queue_full': 'command_queue_full',
    'safe-looking-private-sentinel': 'unexpected',
  }.entries) {
    test('native control ${failure.key} publishes safe notices', () async {
      final lineup = _TestLineup()..diagnostics.enabled = true;
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final player = _FailingControlPlayer(failureCode: failure.key);
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      await coordinator.play();
      await coordinator.pause();
      await coordinator.seekTo(const Duration(seconds: 12));
      await coordinator.selectTrack(PlayerTrackType.audio, 2);
      await coordinator.toggleFullscreen();

      expect(
        coordinator.notice,
        'Playback controls are temporarily unavailable. Try again.',
      );
      expect(coordinator.error, isNull);
      expect(coordinator.overlay, isNot(PlayerOverlay.error));
      expect(coordinator.canRetry, isFalse);
      expect(lineup.diagnostics.entries.map((entry) => entry.context), [
        {'operation': 'play', 'code': failure.value},
        {'operation': 'pause', 'code': failure.value},
        {'operation': 'seek', 'code': failure.value},
        {'operation': 'audio_track', 'code': failure.value},
        {'operation': 'fullscreen', 'code': failure.value},
      ]);
    });
  }

  test('stale control failure cannot replace a scope reset', () async {
    final lineup = _TestLineup()..diagnostics.enabled = true;
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _BlockingFailingControlPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final seek = coordinator.seekTo(const Duration(seconds: 12));
    await player.seekStarted.future;
    lineup.changeContentScope();
    player.releaseSeek.complete();
    await seek;
    await pumpEventQueue(times: 2);

    expect(coordinator.error, isNull);
    expect(coordinator.overlay, PlayerOverlay.none);
    expect(lineup.diagnostics.entries, isEmpty);
  });

  testWidgets('stale sleep completion preserves a replacement timer', (
    tester,
  ) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _BlockingStopPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    coordinator.setSleepTimer(const Duration(minutes: 30));
    await tester.pump(const Duration(minutes: 30));
    await player.stopStarted.future;

    coordinator.setSleepTimer(const Duration(minutes: 60));
    expect(coordinator.sleepDuration, const Duration(minutes: 60));
    player.releaseStop.complete();
    await tester.pump();

    expect(coordinator.sleepDuration, const Duration(minutes: 60));
    await tester.pump(const Duration(minutes: 60));
    await tester.pump();

    expect(player.stops, 2);
    expect(coordinator.sleepDuration, isNull);
  });

  testWidgets('stale sleep completion cannot dismiss a newer tune', (
    tester,
  ) async {
    final lineup = _TestLineup();
    final scheduleStarted = Completer<void>();
    final releaseSchedule = Completer<void>();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async {
        if (!scheduleStarted.isCompleted) scheduleStarted.complete();
        await releaseSchedule.future;
        return _schedule(channel);
      },
    );
    final player = _BlockingStopPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    coordinator.setSleepTimer(const Duration(minutes: 30));
    await tester.pump(const Duration(minutes: 30));
    await player.stopStarted.future;

    final tune = coordinator.tune('channel-b');
    expect(coordinator.overlay, PlayerOverlay.osd);
    player.releaseStop.complete();
    await scheduleStarted.future;
    await tester.pump();

    expect(coordinator.overlay, PlayerOverlay.osd);
    expect(coordinator.tuning, isTrue);
    expect(coordinator.error, isNull);

    releaseSchedule.complete();
    expect(await tune, isTrue);
    expect(lineup.currentChannelId, 'channel-b');
    coordinator.closeOverlay();
    await coordinator.stop();
  });

  testWidgets('sleep completion does not notify after disposal', (
    tester,
  ) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _BlockingStopPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    coordinator.setSleepTimer(const Duration(minutes: 30));
    await tester.pump(const Duration(minutes: 30));
    await player.stopStarted.future;

    coordinator.dispose();
    player.releaseStop.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('sleep stop failure is reported and clears the timer', (
    tester,
  ) async {
    final lineup = _TestLineup()..diagnostics.enabled = true;
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _EventPlayer()..failStop = true;
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(player.close);
    addTearDown(coordinator.dispose);

    coordinator.setSleepTimer(const Duration(minutes: 30));
    await tester.pump(const Duration(minutes: 30));
    await tester.pump();

    expect(coordinator.sleepDuration, isNull);
    expect(coordinator.overlay, isNot(PlayerOverlay.error));
    expect(coordinator.error, isNull);
    expect(
      coordinator.notice,
      'Playback could not be stopped when the sleep timer expired.',
    );
    expect(
      lineup.diagnostics.entries.single.message,
      'Playback request failed',
    );
    expect(lineup.diagnostics.entries.single.context, {'code': 'unexpected'});
    expect(
      '${lineup.diagnostics.entries.single.message}'
      '${lineup.diagnostics.entries.single.context}',
      isNot(contains('opaque-secret-sentinel')),
    );
    await tester.pump(const Duration(seconds: 6));
    expect(coordinator.notice, isNull);
  });

  test('an expired deadline stops before a resume command can play', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _Player();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    coordinator.setSleepTimer(Duration.zero);
    await coordinator.play();

    expect(player.plays, 0);
    expect(player.stops, 1);
    expect(coordinator.sleepDuration, isNull);
    expect(coordinator.status.state, PlayerState.stopped);
    expect(coordinator.status.message, 'Playback stopped by timer');
  });

  test('removing the active channel stops playback', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final nativePlayer = _Player();
    final coordinator = PlayerCoordinator(
      player: nativePlayer,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');
    lineup.replaceChannels(
      lineup.channels.where((channel) => channel.id != 'channel-b').toList(),
    );
    await Future<void>.delayed(Duration.zero);

    expect(nativePlayer.stops, 1);
    expect(coordinator.hasPlaybackIntent, isFalse);
  });

  test(
    'reorder and renumber preserve unchanged active playback scope',
    () async {
      final lineup = _TestLineup(count: 3);
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 3);
      await Future<void>.delayed(Duration.zero);
      final nativePlayer = _Player();
      final coordinator = PlayerCoordinator(
        player: nativePlayer,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      await coordinator.tune('channel-b');
      coordinator.showMiniGuide();
      coordinator.setSleepTimer(const Duration(minutes: 30));
      await coordinator.toggleFullscreen();
      final loads = nativePlayer.loads.length;
      final seeks = nativePlayer.seeks.length;
      final overlay = coordinator.overlay;

      await lineup.reorderChannels(
        expectedLineup: lineup.channels,
        orderedChannelIds: const ['channel-2', 'channel-0', 'channel-b'],
      );
      await lineup.reorderChannels(
        expectedLineup: lineup.channels,
        orderedChannelIds: const ['channel-b', 'channel-2', 'channel-0'],
      );
      await Future<void>.delayed(Duration.zero);

      expect(nativePlayer.stops, 0);
      expect(nativePlayer.loads, hasLength(loads));
      expect(nativePlayer.seeks, hasLength(seeks));
      expect(nativePlayer.fullscreenValues, [true]);
      expect(coordinator.fullscreen, isTrue);
      expect(coordinator.sleepDuration, const Duration(minutes: 30));
      expect(coordinator.overlay, overlay);
      expect(coordinator.hasPlaybackIntent, isTrue);
    },
  );

  test('active programming replacement stops playback', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final nativePlayer = _Player();
    final coordinator = PlayerCoordinator(
      player: nativePlayer,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');
    final active = lineup.channels.singleWhere(
      (channel) => channel.id == 'channel-b',
    );
    lineup.replaceChannels([
      for (final channel in lineup.channels)
        if (channel.id == active.id)
          Channel.fromJson({...active.toJson(), 'shuffleSeed': 99})
        else
          channel,
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(nativePlayer.stops, 1);
    expect(coordinator.hasPlaybackIntent, isFalse);
  });

  test(
    'coordinated logout preserves playback on failure and drains on retry',
    () async {
      final lineup = _LogoutLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final nativePlayer = _Player();
      final coordinator = PlayerCoordinator(
        player: nativePlayer,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);
      await coordinator.tune('channel-b');

      expect(await coordinator.logout(), isFalse);
      expect(nativePlayer.stops, 0);
      expect(await coordinator.logout(), isTrue);
      expect(nativePlayer.stops, 1);
      expect(coordinator.hasPlaybackIntent, isFalse);
    },
  );

  test(
    'one overlay owner enforces track back-stack and direct number tune',
    () async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      guide.requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final coordinator = PlayerCoordinator(
        player: _Player()
          ..tracks = const [
            PlayerTrack(id: 1, type: PlayerTrackType.subtitle, selected: false),
          ],
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      coordinator.showOsd();
      coordinator.showTracks(PlayerTrackType.subtitle);
      expect(coordinator.overlay, PlayerOverlay.subtitleTracks);
      coordinator.closeOverlay();
      expect(coordinator.overlay, PlayerOverlay.osd);

      coordinator.appendChannelDigit('9');
      expect(coordinator.overlay, PlayerOverlay.channelNumber);
      await coordinator.commitChannelNumber();
      expect(lineup.currentChannelId, 'channel-b');
    },
  );

  testWidgets(
    'Now Playing is persistent, exclusive, and opens tracks directly',
    (tester) async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await tester.pump();
      final coordinator = PlayerCoordinator(
        player: _Player()
          ..tracks = const [
            PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: true),
          ],
        lineup: lineup,
        guide: guide,
        overlayTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      coordinator.showNowPlaying();
      expect(coordinator.overlay, PlayerOverlay.nowPlaying);
      await tester.pump(const Duration(minutes: 1));
      expect(coordinator.overlay, PlayerOverlay.nowPlaying);

      coordinator.showTracks(PlayerTrackType.audio);
      expect(coordinator.overlay, PlayerOverlay.audioTracks);
      coordinator.closeOverlay();
      expect(coordinator.overlay, PlayerOverlay.osd);

      lineup.clearCurrentChannel();
      coordinator.showNowPlaying();
      expect(coordinator.overlay, PlayerOverlay.osd);
      coordinator.closeOverlay();
    },
  );

  test('successful Media Stop replaces Now Playing with the OSD', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _Player();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune(lineup.currentChannelId!);
    coordinator.showNowPlaying();
    await coordinator.requestStop();

    expect(player.stops, 1);
    expect(coordinator.overlay, PlayerOverlay.osd);
  });

  test(
    'Media Stop completion does not replace a superseding overlay',
    () async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _BlockingStopPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(() {
        if (!player.releaseStop.isCompleted) player.releaseStop.complete();
      });
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      await coordinator.tune(lineup.currentChannelId!);
      coordinator.showNowPlaying();
      final stop = coordinator.requestStop();
      await player.stopStarted.future;

      coordinator.showFullGuide();
      player.releaseStop.complete();
      await stop;

      expect(coordinator.overlay, PlayerOverlay.fullGuide);
    },
  );

  test('native telemetry updates do not dismiss Now Playing', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _EventPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune(lineup.currentChannelId!);
    coordinator.showNowPlaying();
    player.emitStatus(
      PlayerState.paused,
      generation: player.loadGenerations.single,
    );
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.status.state, PlayerState.paused);
    expect(coordinator.overlay, PlayerOverlay.nowPlaying);
  });

  testWidgets('failed Media Stop keeps the untimed safe error surface', (
    tester,
  ) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await tester.pump();
    final player = _EventPlayer()..failStop = true;
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
      overlayTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune(lineup.currentChannelId!);
    coordinator.showNowPlaying();
    await coordinator.requestStop();

    expect(coordinator.overlay, PlayerOverlay.error);
    expect(
      coordinator.error,
      'Playback could not be stopped. Retry or choose another channel.',
    );
    await tester.pump(const Duration(minutes: 1));
    expect(coordinator.overlay, PlayerOverlay.error);
  });

  test(
    'mini Guide pages by logical identity without mounting all channels',
    () async {
      final lineup = _TestLineup(count: 1000);
      var loads = 0;
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async {
          loads++;
          return _schedule(channel);
        },
      );
      final coordinator = PlayerCoordinator(
        player: _Player(),
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      coordinator.showMiniGuide();
      coordinator.moveMiniGuide(500);
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.miniGuideChannelId, 'channel-500');
      expect(loads, greaterThanOrEqualTo(5));
      expect(guide.cachedRowCount, lessThanOrEqualTo(14));
    },
  );

  test('mini Guide preserves lineup order when every channel fits', () {
    for (var count = 1; count <= 5; count++) {
      final lineup = _TestLineup(count: count);
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final coordinator = PlayerCoordinator(
        player: _Player(),
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      coordinator.moveMiniGuide(count - 1);

      expect(
        coordinator.miniGuideChannels.map((channel) => channel.id),
        lineup.channels.map((channel) => channel.id),
      );
    }
  });

  test('larger mini Guides wrap around the centered selection', () {
    final lineup = _TestLineup(count: 6);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final coordinator = PlayerCoordinator(
      player: _Player(),
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    expect(coordinator.miniGuideChannels.map((channel) => channel.id), [
      'channel-4',
      'channel-5',
      'channel-0',
      'channel-b',
      'channel-2',
    ]);
  });

  testWidgets('OSD timeout resets and rejects stale timers', (tester) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final coordinator = PlayerCoordinator(
      player: _Player(),
      lineup: lineup,
      guide: guide,
      overlayTimeout: const Duration(seconds: 4),
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    coordinator.showOsd();
    await tester.pump(const Duration(seconds: 3));
    coordinator.showOsd();
    await tester.pump(const Duration(seconds: 2));
    expect(coordinator.overlay, PlayerOverlay.osd);
    await tester.pump(const Duration(seconds: 3));
    expect(coordinator.overlay, PlayerOverlay.none);
  });

  testWidgets('steady playing events do not postpone the OSD timeout', (
    tester,
  ) async {
    for (final timeout in [
      const Duration(seconds: 4),
      const Duration(seconds: 2),
    ]) {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final player = _EventPlayer()
        ..status = const PlayerStatus(
          state: PlayerState.loading,
          message: 'Loading',
        );
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
        overlayTimeout: timeout,
      );

      player.emitStatus(PlayerState.loading);
      await tester.pump();
      player.emitStatus(PlayerState.playing);
      await tester.pump();
      coordinator.showOsd();

      final eventCount = timeout.inMilliseconds ~/ 250 - 1;
      for (var index = 0; index < eventCount; index++) {
        player.position = Duration(milliseconds: index * 250);
        player.emitStatus(PlayerState.playing);
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.pump(const Duration(milliseconds: 249));
      expect(coordinator.overlay, PlayerOverlay.osd);
      await tester.pump(const Duration(milliseconds: 1));
      expect(coordinator.overlay, PlayerOverlay.none);
      coordinator.dispose();
      await player.close();
      guide.dispose();
      lineup.dispose();
    }
  });

  testWidgets('loading to playing arms the OSD hide timer', (tester) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _EventPlayer()
      ..status = const PlayerStatus(
        state: PlayerState.loading,
        message: 'Loading',
      );
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
      overlayTimeout: const Duration(seconds: 1),
    );
    addTearDown(player.close);
    addTearDown(coordinator.dispose);
    addTearDown(guide.dispose);
    addTearDown(lineup.dispose);

    player.emitStatus(PlayerState.loading);
    await tester.pump();
    coordinator.showOsd();
    player.position = const Duration(seconds: 1);
    player.emitStatus(PlayerState.playing);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 999));
    expect(coordinator.overlay, PlayerOverlay.osd);
    await tester.pump(const Duration(milliseconds: 1));
    expect(coordinator.overlay, PlayerOverlay.none);
  });

  testWidgets('playing, paused, and playing transitions re-arm the OSD timer', (
    tester,
  ) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _EventPlayer()
      ..status = const PlayerStatus(
        state: PlayerState.loading,
        message: 'Loading',
      );
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
      overlayTimeout: const Duration(seconds: 1),
    );
    addTearDown(player.close);
    addTearDown(coordinator.dispose);
    addTearDown(guide.dispose);
    addTearDown(lineup.dispose);

    player.emitStatus(PlayerState.loading);
    await tester.pump();
    coordinator.showOsd();
    player.position = const Duration(seconds: 1);
    player.emitStatus(PlayerState.playing);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    player.position = const Duration(seconds: 2);
    player.emitStatus(PlayerState.paused);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(coordinator.overlay, PlayerOverlay.osd);

    player.position = const Duration(seconds: 3);
    player.emitStatus(PlayerState.playing);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 999));
    expect(coordinator.overlay, PlayerOverlay.osd);
    await tester.pump(const Duration(milliseconds: 1));
    expect(coordinator.overlay, PlayerOverlay.none);
  });

  testWidgets('repeated paused events do not postpone the OSD timeout', (
    tester,
  ) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _EventPlayer()
      ..status = const PlayerStatus(
        state: PlayerState.loading,
        message: 'Loading',
      );
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
      overlayTimeout: const Duration(seconds: 1),
    );
    addTearDown(player.close);
    addTearDown(coordinator.dispose);
    addTearDown(guide.dispose);
    addTearDown(lineup.dispose);

    player.emitStatus(PlayerState.loading);
    await tester.pump();
    coordinator.showOsd();
    player.position = const Duration(seconds: 1);
    player.emitStatus(PlayerState.paused);
    await tester.pump();
    for (var index = 0; index < 4; index++) {
      player.position = Duration(seconds: index + 2);
      player.emitStatus(PlayerState.paused);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(coordinator.overlay, PlayerOverlay.osd);
    await tester.pump(const Duration(milliseconds: 100));
    expect(coordinator.overlay, PlayerOverlay.none);
  });

  testWidgets('repeated paused events do not replace persistent overlays', (
    tester,
  ) async {
    final cases = <(PlayerOverlay, void Function(PlayerCoordinator))>[
      (
        PlayerOverlay.audioTracks,
        (coordinator) {
          coordinator.showTracks(PlayerTrackType.audio);
        },
      ),
      (
        PlayerOverlay.subtitleTracks,
        (coordinator) {
          coordinator.showTracks(PlayerTrackType.subtitle);
        },
      ),
      (
        PlayerOverlay.miniGuide,
        (coordinator) {
          coordinator.showMiniGuide();
        },
      ),
      (
        PlayerOverlay.channelNumber,
        (coordinator) {
          coordinator.appendChannelDigit('9');
        },
      ),
    ];

    for (final (expected, open) in cases) {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final player = _EventPlayer()
        ..status = const PlayerStatus(
          state: PlayerState.loading,
          message: 'Loading',
        )
        ..tracks = const [
          PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: true),
        ];
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
        overlayTimeout: const Duration(seconds: 1),
      );

      player.emitStatus(PlayerState.loading);
      await tester.pump();
      player.position = const Duration(seconds: 1);
      player.emitStatus(PlayerState.paused);
      await tester.pump();
      open(coordinator);
      expect(coordinator.overlay, expected);

      player.position = const Duration(seconds: 2);
      player.emitStatus(PlayerState.paused);
      await tester.pump();
      expect(coordinator.overlay, expected);

      coordinator.dispose();
      await player.close();
      guide.dispose();
      lineup.dispose();
    }
  });

  testWidgets(
    'pointer activity re-arms the OSD while playing during repeated events',
    (tester) async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final player = _EventPlayer()
        ..status = const PlayerStatus(
          state: PlayerState.loading,
          message: 'Loading',
        );
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
        overlayTimeout: const Duration(seconds: 1),
      );
      addTearDown(player.close);
      addTearDown(coordinator.dispose);
      addTearDown(guide.dispose);
      addTearDown(lineup.dispose);

      player.emitStatus(PlayerState.loading);
      await tester.pump();
      coordinator.showOsd();
      player.position = const Duration(seconds: 1);
      player.emitStatus(PlayerState.playing);
      await tester.pump();
      for (var index = 0; index < 3; index++) {
        player.position = Duration(seconds: index + 2);
        player.emitStatus(PlayerState.playing);
        await tester.pump(const Duration(milliseconds: 250));
        if (index == 1) coordinator.handlePointerActivity();
      }
      await tester.pump(const Duration(milliseconds: 749));
      expect(coordinator.overlay, PlayerOverlay.osd);
      await tester.pump(const Duration(milliseconds: 1));
      expect(coordinator.overlay, PlayerOverlay.none);
      coordinator.dispose();
    },
  );

  testWidgets(
    'pointer activity re-arms the OSD while paused during repeated events',
    (tester) async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final player = _EventPlayer()
        ..status = const PlayerStatus(
          state: PlayerState.loading,
          message: 'Loading',
        );
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
        overlayTimeout: const Duration(seconds: 1),
      );
      addTearDown(player.close);
      addTearDown(coordinator.dispose);
      addTearDown(guide.dispose);
      addTearDown(lineup.dispose);

      player.emitStatus(PlayerState.loading);
      await tester.pump();
      coordinator.showOsd();
      player.position = const Duration(seconds: 1);
      player.emitStatus(PlayerState.paused);
      await tester.pump();
      for (var index = 0; index < 3; index++) {
        player.position = Duration(seconds: index + 2);
        player.emitStatus(PlayerState.paused);
        await tester.pump(const Duration(milliseconds: 250));
        if (index == 1) coordinator.handlePointerActivity();
      }
      await tester.pump(const Duration(milliseconds: 749));
      expect(coordinator.overlay, PlayerOverlay.osd);
      await tester.pump(const Duration(milliseconds: 1));
      expect(coordinator.overlay, PlayerOverlay.none);
      coordinator.dispose();
    },
  );

  testWidgets('pointer activity ends OSD focus suspension', (tester) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _EventPlayer()
      ..status = const PlayerStatus(
        state: PlayerState.loading,
        message: 'Loading',
      );
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
      overlayTimeout: const Duration(seconds: 1),
    );
    addTearDown(player.close);
    addTearDown(coordinator.dispose);
    addTearDown(guide.dispose);
    addTearDown(lineup.dispose);

    player.emitStatus(PlayerState.loading);
    await tester.pump();
    coordinator.showOsd();
    player.position = const Duration(seconds: 1);
    player.emitStatus(PlayerState.paused);
    await tester.pump();
    final generation = coordinator.overlayPresentationGeneration;
    coordinator.overlayFocusChanged(PlayerOverlay.osd, generation, true);
    coordinator.handlePointerActivity();
    await tester.pump(const Duration(seconds: 3, milliseconds: 1));
    expect(coordinator.overlay, PlayerOverlay.none);
  });

  testWidgets('cursor hides with the OSD after three seconds of idle playing', (
    tester,
  ) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _EventPlayer()
      ..status = const PlayerStatus(
        state: PlayerState.loading,
        message: 'Loading',
      );
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(coordinator.dispose);
    addTearDown(guide.dispose);
    addTearDown(lineup.dispose);

    player.emitStatus(PlayerState.loading);
    await tester.pump();
    player.position = const Duration(seconds: 1);
    player.emitStatus(PlayerState.playing);
    await tester.pump();
    coordinator.handlePointerActivity();
    await tester.pump(const Duration(seconds: 3, milliseconds: 999));
    expect(coordinator.overlay, PlayerOverlay.osd);
    expect(coordinator.cursorVisible, isTrue);
    await tester.pump(const Duration(milliseconds: 1));
    expect(coordinator.overlay, PlayerOverlay.none);
    expect(coordinator.cursorVisible, isFalse);

    coordinator.handlePointerActivity();
    expect(coordinator.cursorVisible, isTrue);
    coordinator.dispose();
  });

  testWidgets('cursor stays visible while paused', (tester) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _EventPlayer()
      ..status = const PlayerStatus(
        state: PlayerState.loading,
        message: 'Loading',
      );
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(coordinator.dispose);
    addTearDown(guide.dispose);
    addTearDown(lineup.dispose);

    player.emitStatus(PlayerState.loading);
    await tester.pump();
    player.position = const Duration(seconds: 1);
    player.emitStatus(PlayerState.paused);
    await tester.pump();
    coordinator.handlePointerActivity();
    await tester.pump(const Duration(seconds: 4));
    expect(coordinator.overlay, PlayerOverlay.none);
    expect(coordinator.cursorVisible, isTrue);
  });

  testWidgets('OSD focus suspends timeout while Mini Guide never times out', (
    tester,
  ) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final coordinator = PlayerCoordinator(
      player: _Player(),
      lineup: lineup,
      guide: guide,
      overlayTimeout: const Duration(seconds: 4),
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    coordinator.showOsd();
    final osdGeneration = coordinator.overlayPresentationGeneration;
    coordinator.overlayFocusChanged(PlayerOverlay.osd, osdGeneration, true);
    await tester.pump(const Duration(seconds: 5));
    expect(coordinator.overlay, PlayerOverlay.osd);

    coordinator.overlayFocusChanged(PlayerOverlay.osd, osdGeneration, false);
    await tester.pump(const Duration(milliseconds: 3999));
    expect(coordinator.overlay, PlayerOverlay.osd);
    await tester.pump(const Duration(milliseconds: 2));
    expect(coordinator.overlay, PlayerOverlay.none);

    coordinator.showMiniGuide();
    final guideGeneration = coordinator.overlayPresentationGeneration;
    coordinator.overlayFocusChanged(
      PlayerOverlay.miniGuide,
      guideGeneration,
      true,
    );
    await tester.pump(const Duration(seconds: 9));
    expect(coordinator.overlay, PlayerOverlay.miniGuide);

    coordinator.overlayFocusChanged(
      PlayerOverlay.miniGuide,
      guideGeneration,
      false,
    );
    await tester.pump(const Duration(minutes: 5));
    expect(coordinator.overlay, PlayerOverlay.miniGuide);
  });

  testWidgets(
    'stale overlay focus callbacks cannot affect a new presentation',
    (tester) async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final coordinator = PlayerCoordinator(
        player: _Player(),
        lineup: lineup,
        guide: guide,
        overlayTimeout: const Duration(seconds: 1),
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      coordinator.showOsd();
      final staleGeneration = coordinator.overlayPresentationGeneration;
      coordinator.overlayFocusChanged(PlayerOverlay.osd, staleGeneration, true);
      coordinator.showMiniGuide();
      final guideGeneration = coordinator.overlayPresentationGeneration;
      coordinator.overlayFocusChanged(
        PlayerOverlay.miniGuide,
        guideGeneration,
        true,
      );
      coordinator.overlayFocusChanged(
        PlayerOverlay.osd,
        staleGeneration,
        false,
      );
      await tester.pump(const Duration(seconds: 9));
      expect(coordinator.overlay, PlayerOverlay.miniGuide);

      coordinator.closeOverlay();
      coordinator.showOsd();
      final reopenedGeneration = coordinator.overlayPresentationGeneration;
      coordinator.overlayFocusChanged(
        PlayerOverlay.osd,
        reopenedGeneration,
        true,
      );
      coordinator.overlayFocusChanged(
        PlayerOverlay.osd,
        staleGeneration,
        false,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(coordinator.overlay, PlayerOverlay.osd);
    },
  );

  testWidgets('OSD timeout reads the persisted setting consumer', (
    tester,
  ) async {
    final lineup = _TestLineup();
    lineup.fixtureActor.publishSettings(
      lineup.settings.copyWith(osdAutoHideSeconds: 2),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final coordinator = PlayerCoordinator(
      player: _Player(),
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    coordinator.showOsd();
    await tester.pump(const Duration(milliseconds: 1999));
    expect(coordinator.overlay, PlayerOverlay.osd);
    await tester.pump(const Duration(milliseconds: 2));
    expect(coordinator.overlay, PlayerOverlay.none);
  });

  testWidgets('paused events use an updated OSD auto-hide setting', (
    tester,
  ) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _EventPlayer();
    addTearDown(player.close);
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    player.emitStatus(PlayerState.paused);
    await tester.pump();
    expect(coordinator.overlay, PlayerOverlay.osd);

    await tester.pump(const Duration(seconds: 1));
    lineup.setSettings(lineup.settings.copyWith(osdAutoHideSeconds: 2));
    await tester.pump(const Duration(milliseconds: 1999));
    expect(coordinator.overlay, PlayerOverlay.osd);
    await tester.pump(const Duration(milliseconds: 2));

    expect(coordinator.overlay, PlayerOverlay.none);
  });

  test(
    'stale generated native events are rejected at the Dart owner',
    () async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final player = _EventPlayer();
      addTearDown(player.close);
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      await coordinator.loadInitialMedia(Uri.parse('lineup-test://generation'));
      final generation = player.loadGenerations.single!;

      player.emitStatus(PlayerState.paused);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.status.state, PlayerState.playing);

      player.emitStatus(PlayerState.paused, generation: generation + 1);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.status.state, PlayerState.playing);

      player.emitStatus(PlayerState.buffering, generation: generation);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.status.state, PlayerState.buffering);
      expect(coordinator.overlay, PlayerOverlay.osd);
    },
  );

  test('superseded tune cannot seek or replace the winning request', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _ControlledPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final first = coordinator.tune('channel-0');
    await player.firstLoadStarted.future;
    final second = coordinator.tune('channel-b');
    player.releaseFirstLoad.complete();
    final results = await Future.wait([first, second]);

    expect(lineup.currentChannelId, 'channel-b');
    expect(player.loads, hasLength(2));
    expect(player.seeks, hasLength(1));
    expect(results, [isFalse, isTrue]);
    await coordinator.stop();
    expect(player.stops, 2);
  });

  test(
    'load generation follows dispatch when an intermediate tune is skipped',
    () async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _ControlledPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      final first = coordinator.tune('channel-0');
      await player.firstLoadStarted.future;
      final skipped = coordinator.tune('channel-b');
      final winning = coordinator.tune('channel-0');
      player.releaseFirstLoad.complete();
      await Future.wait([first, skipped, winning]);

      expect(player.loads, hasLength(2));
      expect(player.loadGenerations, hasLength(2));
      expect(player.loadGenerations.every((value) => value != null), isTrue);
      expect(
        player.loadGenerations.last!,
        greaterThan(player.loadGenerations.first!),
      );
    },
  );

  test('stop cancels a pending tune and clears its request', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _ControlledPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final tune = coordinator.tune('channel-b');
    await player.firstLoadStarted.future;
    final stop = coordinator.stop();
    player.releaseFirstLoad.complete();
    await Future.wait([tune, stop]);

    expect(lineup.currentChannelId, 'channel-0');
    expect(player.stops, 1);
    expect(coordinator.hasPlaybackIntent, isFalse);
  });

  test('replacement tune preempts a never-settling load before dispatching its load', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _PreemptibleLoadPlayer(blockStop: true);
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final first = coordinator.tune('channel-0');
    await player.loadStarted.future;
    final replacement = coordinator.tune('channel-b');
    await player.stopStarted.future;
    await Future<void>.delayed(Duration.zero);

    expect(player.loadSettled, isTrue);
    expect(player.loads, hasLength(1));
    expect(player.calls, ['load', 'stop']);

    player.releaseStop.complete();
    await Future.wait([first, replacement]);
    expect(player.calls, ['load', 'stop', 'load']);
    expect(lineup.currentChannelId, 'channel-b');
  });

  testWidgets('native stop timeout releases a replacement retry', (
    tester,
  ) async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await tester.pump();
    final player = _PreemptibleLoadPlayer(blockStop: true);
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(() {
      if (!player.releaseStop.isCompleted) player.releaseStop.complete();
    });
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final first = coordinator.tune('channel-0');
    await player.loadStarted.future;
    final replacement = coordinator.tune('channel-b');
    await player.stopStarted.future;

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    await Future.wait([first, replacement]);

    expect(player.calls, ['load', 'stop']);
    expect(coordinator.overlay, PlayerOverlay.error);
    expect(coordinator.canRetry, isTrue);

    final retry = coordinator.retry();
    await tester.pump();
    expect(player.calls, ['load', 'stop', 'stop']);
    player.releaseStop.complete();
    await tester.pump();
    await retry;
    expect(player.calls, ['load', 'stop', 'stop', 'load']);
    expect(lineup.currentChannelId, 'channel-b');
    coordinator.closeOverlay();
    await tester.pump();
  });

  test('explicit Stop preempts a never-settling load immediately', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _PreemptibleLoadPlayer(blockStop: true);
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final tune = coordinator.tune('channel-b');
    await player.loadStarted.future;
    final stop = coordinator.stop();
    await player.stopStarted.future;
    await Future<void>.delayed(Duration.zero);

    expect(player.loadSettled, isTrue);
    expect(player.stops, 1);
    player.releaseStop.complete();
    await Future.wait([tune, stop]);
    expect(coordinator.hasPlaybackIntent, isFalse);
  });

  test('content-scope invalidation preempts a never-settling load', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _PreemptibleLoadPlayer(blockStop: true);
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final tune = coordinator.tune('channel-b');
    await player.loadStarted.future;
    lineup.changeContentScope();
    await player.stopStarted.future;
    await Future<void>.delayed(Duration.zero);

    expect(player.loadSettled, isTrue);
    player.releaseStop.complete();
    final tuned = await tune;
    await Future<void>.delayed(Duration.zero);
    expect(player.stops, 1);
    expect(coordinator.hasPlaybackIntent, isFalse);
    expect(tuned, isFalse);
  });

  test(
    'successful logout preempts a pending load but failed logout preserves it',
    () async {
      final lineup = _LogoutLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _PreemptibleLoadPlayer(blockStop: true);
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      final tune = coordinator.tune('channel-b');
      await player.loadStarted.future;
      expect(await coordinator.logout(), isFalse);
      expect(player.stops, 0);
      expect(player.loadSettled, isFalse);

      final logout = coordinator.logout();
      await player.stopStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(player.loadSettled, isTrue);
      player.releaseStop.complete();
      expect(await logout, isTrue);
      await tune;
      expect(player.stops, 1);
    },
  );

  test(
    'rapid replacement Stop and scope invalidation coalesce preemption',
    () async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _PreemptibleLoadPlayer(blockStop: true);
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      final first = coordinator.tune('channel-0');
      await player.loadStarted.future;
      final replacement = coordinator.tune('channel-b');
      final stop = coordinator.stop();
      lineup.changeContentScope();
      await player.stopStarted.future;
      await Future<void>.delayed(Duration.zero);

      expect(player.stops, 1);
      expect(player.loads, hasLength(1));
      player.releaseStop.complete();
      await Future.wait([first, replacement, stop]);
      await Future<void>.delayed(Duration.zero);
      expect(player.stops, 1);
      expect(player.loads, hasLength(1));
    },
  );

  test('replacement failure stops superseded media before settling', () async {
    final lineup = _TestLineup(failSecondPlaybackRequest: true);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _BlockingEventPlayer();
    addTearDown(player.close);
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final first = coordinator.tune('channel-0');
    await player.firstLoadStarted.future;
    final replacement = coordinator.tune('channel-b');
    player.releaseFirstLoad.complete();
    await Future.wait([first, replacement]);
    player.emitStatus(
      PlayerState.stopped,
      generation: player.loadGenerations.single,
    );
    await Future<void>.delayed(Duration.zero);

    expect(player.loads, hasLength(1));
    expect(player.stops, 1);
    expect(lineup.currentChannelId, 'channel-0');
    expect(coordinator.status.state, PlayerState.stopped);
    expect(coordinator.hasPlaybackIntent, isFalse);
    expect(coordinator.overlay, PlayerOverlay.error);
  });

  test('generated stopped event settles coordinator playback state', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _EventPlayer();
    addTearDown(player.close);
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');
    expect(coordinator.hasPlaybackIntent, isTrue);

    await coordinator.stop();
    player.emitStatus(
      PlayerState.stopped,
      generation: player.loadGenerations.single,
    );
    await Future<void>.delayed(Duration.zero);

    expect(player.stops, 1);
    expect(coordinator.status.state, PlayerState.stopped);
    expect(coordinator.hasPlaybackIntent, isFalse);
  });

  test('terminal player errors settle and failed stops propagate', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _EventPlayer();
    addTearDown(player.close);
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');
    player.emitError(generation: player.loadGenerations.single);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.overlay, PlayerOverlay.error);

    await coordinator.tune('channel-0');
    player.failStop = true;
    await expectLater(coordinator.stop(), throwsStateError);
    expect(player.stops, 2);
  });

  test('recoverable player errors retain the retry action', () async {
    final lineup = _TestLineup();
    lineup.diagnostics.enabled = true;
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _EventPlayer();
    addTearDown(player.close);
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');
    player.emitError(
      recoverable: true,
      generation: player.loadGenerations.single,
      message: 'opaque-secret-sentinel',
      audioCodec: 'truehd',
      failureCode: 'http_error',
      httpStatus: 401,
      videoCodec: 'hevc',
      videoOutput: 'gpu-next',
      hardwareDecoder: 'd3d11va',
    );
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.canRetry, isTrue);
    expect(coordinator.overlay, PlayerOverlay.error);
    expect(coordinator.status.failureCode, 'http_error');
    expect(coordinator.status.httpStatus, 401);
    expect(lineup.diagnostics.entries.single.message, 'Native playback failed');
    expect(lineup.diagnostics.entries.single.context, {
      'failureCode': 'http_error',
      'httpStatus': 401,
      'videoCodec': 'hevc',
      'audioCodec': 'truehd',
      'videoOutput': 'gpu-next',
      'hardwareDecoder': 'd3d11va',
    });
    expect(
      '${lineup.diagnostics.entries.single.message}'
      '${lineup.diagnostics.entries.single.context}',
      isNot(contains('opaque-secret-sentinel')),
    );
  });

  test(
    'synchronous native authorization failure loads one replacement',
    () async {
      final lineup = _TestLineup(
        recoverAuthorization: true,
        replacementRecoverable: true,
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _SynchronousAuthorizationPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      await coordinator.tune('channel-b');

      expect(player.loads, hasLength(2));
      expect(player.loadPlexTokens, ['test-token-1', 'test-token-2']);
      expect(lineup.recoveryCalls, 1);
      expect(coordinator.error, isNull);

      await coordinator.stop();
      expect(player.stops, 1);
    },
  );

  test(
    'missing playback session preserves its category in the report',
    () async {
      final lineup = _TestLineup(useRealPlaybackRequest: true)
        ..diagnostics.enabled = true;
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final coordinator = PlayerCoordinator(
        player: _Player(),
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      expect(await coordinator.tune('channel-b'), isFalse);
      expect(
        lineup.diagnostics.entries.single.context['code'],
        'playback-unavailable',
      );
      expect(
        _supportReport(lineup, coordinator),
        contains('code=playback-unavailable'),
      );
    },
  );

  test('synchronous authorization recovery failure is terminal', () async {
    final lineup = _TestLineup(
      recoverAuthorization: true,
      throwAuthorizationRecoverySynchronously: true,
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _EventPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');
    player.emitError(
      recoverable: true,
      generation: player.loadGenerations.single,
      failureCode: 'http_error',
      httpStatus: 401,
    );
    await pumpEventQueue(times: 5);

    expect(lineup.recoveryCalls, 1);
    expect(player.loads, hasLength(1));
    expect(player.stops, 1);
    expect(coordinator.canRetry, isTrue);
    expect(coordinator.overlay, PlayerOverlay.error);
    expect(
      coordinator.error,
      'Playback could not start. Retry or choose another channel.',
    );
  });

  for (final domainFailure in [false, true]) {
    test(
      'failed authorization recovery is terminal (domain=$domainFailure)',
      () async {
        final lineup = _TestLineup(
          recoverAuthorization: true,
          failAuthorizationRecovery: true,
          authorizationRecoveryFailure: domainFailure
              ? const PlexException(
                  'authorization-unavailable',
                  'Plex server authorization is unavailable.',
                )
              : null,
        )..diagnostics.enabled = true;
        final guide = GuideController(
          lineup: lineup,
          loadSchedule: (channel) async => _schedule(channel),
        )..requestViewport(0, 2);
        await Future<void>.delayed(Duration.zero);
        final player = _EventPlayer();
        final coordinator = PlayerCoordinator(
          player: player,
          lineup: lineup,
          guide: guide,
        );
        addTearDown(player.close);
        addTearDown(lineup.dispose);
        addTearDown(guide.dispose);
        addTearDown(coordinator.dispose);

        await coordinator.tune('channel-b');
        player.emitError(
          recoverable: true,
          generation: player.loadGenerations.single,
          failureCode: 'http_error',
          httpStatus: 401,
        );
        await pumpEventQueue(times: 5);

        expect(lineup.recoveryCalls, 1);
        expect(player.loads, hasLength(1));
        expect(player.stops, 1);
        expect(coordinator.canRetry, isTrue);
        expect(coordinator.overlay, PlayerOverlay.error);
        expect(
          coordinator.error,
          domainFailure
              ? 'Plex server authorization is unavailable.'
              : 'Playback could not start. Retry or choose another channel.',
        );
        if (domainFailure) {
          expect(
            _supportReport(lineup, coordinator),
            contains('code=authorization-unavailable'),
          );
        }
      },
    );
  }

  test(
    'a second native authorization failure is terminal without a loop',
    () async {
      final lineup = _TestLineup(
        recoverAuthorization: true,
        replacementRecoverable: true,
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _SynchronousAuthorizationPlayer(failures: 2);
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      await coordinator.tune('channel-b');

      expect(player.loads, hasLength(2));
      expect(lineup.recoveryCalls, 1);
      expect(coordinator.overlay, PlayerOverlay.error);
      expect(coordinator.status.failureCode, 'http_error');
      expect(coordinator.status.httpStatus, 401);
    },
  );

  test('replacement retry ceiling survives newer tune dispatch', () async {
    final lineup = _TestLineup(
      recoverAuthorization: true,
      replacementRecoverable: true,
    );
    final nextGuideStarted = Completer<void>();
    final releaseNextGuide = Completer<void>();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async {
        if (channel.id == 'channel-0') {
          nextGuideStarted.complete();
          await releaseNextGuide.future;
        }
        return _schedule(channel);
      },
    );
    final player = _EventPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');
    player.emitError(
      recoverable: true,
      generation: player.loadGenerations.single,
      failureCode: 'http_error',
      httpStatus: 401,
    );
    await pumpEventQueue(times: 5);

    final winningTune = coordinator.tune('channel-0');
    await nextGuideStarted.future;
    player.emitError(
      recoverable: true,
      generation: player.loadGenerations.last,
      failureCode: 'http_error',
      httpStatus: 401,
    );
    await Future<void>.delayed(Duration.zero);
    expect(lineup.recoveryCalls, 1);
    expect(player.loads, hasLength(2));

    releaseNextGuide.complete();
    await winningTune;
    expect(lineup.currentChannelId, 'channel-0');
    expect(coordinator.error, isNull);
    await coordinator.stop();
  });

  test('pending recovery ceiling survives tune dispatch', () async {
    final lineup = _TestLineup(
      recoverAuthorization: true,
      replacementRecoverable: true,
      blockAuthorizationRecovery: true,
    );
    final nextGuideStarted = Completer<void>();
    final releaseNextGuide = Completer<void>();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async {
        if (channel.id == 'channel-0') {
          nextGuideStarted.complete();
          await releaseNextGuide.future;
        }
        return _schedule(channel);
      },
    );
    final player = _EventPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');
    final rejectedGeneration = player.loadGenerations.single;
    player.emitError(
      recoverable: true,
      generation: rejectedGeneration,
      failureCode: 'http_error',
      httpStatus: 401,
    );
    await lineup.recoveryStarted.future;

    final winningTune = coordinator.tune('channel-0');
    await nextGuideStarted.future;
    player.emitError(
      recoverable: true,
      generation: rejectedGeneration,
      failureCode: 'http_error',
      httpStatus: 401,
    );
    await Future<void>.delayed(Duration.zero);
    expect(lineup.recoveryCalls, 1);

    releaseNextGuide.complete();
    await winningTune;
    lineup.finishRecovery.complete();
    await pumpEventQueue(times: 5);

    expect(lineup.currentChannelId, 'channel-0');
    expect(coordinator.error, isNull);
    expect(lineup.recoveryCalls, 1);
    await coordinator.stop();
  });

  test(
    'failed pre-load replacement retires prior recovery ownership',
    () async {
      final lineup = _TestLineup(
        failSecondPlaybackRequest: true,
        recoverAuthorization: true,
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _EventPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      await coordinator.tune('channel-0');
      await coordinator.tune('channel-b');
      player.emitError(
        recoverable: true,
        generation: player.loadGenerations.single,
        failureCode: 'http_error',
        httpStatus: 401,
      );
      await pumpEventQueue(times: 5);

      expect(player.loads, hasLength(1));
      expect(lineup.recoveryCalls, 0);
      await coordinator.stop();
      expect(player.stops, 2);
    },
  );

  test(
    'non-authorization native failure never invokes token recovery',
    () async {
      final lineup = _TestLineup(recoverAuthorization: true);
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _SynchronousAuthorizationPlayer(
        failureCode: 'decoder_error',
        httpStatus: null,
      );
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      await coordinator.tune('channel-b');

      expect(player.loads, hasLength(1));
      expect(lineup.recoveryCalls, 0);
      expect(coordinator.overlay, PlayerOverlay.error);
      expect(coordinator.status.failureCode, 'decoder_error');
    },
  );

  test(
    'tune supersession owns and drains pending authorization recovery',
    () async {
      final lineup = _TestLineup(
        recoverAuthorization: true,
        blockAuthorizationRecovery: true,
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _SynchronousAuthorizationPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      final staleTune = coordinator.tune('channel-b');
      await lineup.recoveryStarted.future;
      final winningTune = coordinator.tune('channel-0');
      lineup.finishRecovery.complete();
      await Future.wait([staleTune, winningTune]);

      expect(player.loadPlexTokens, ['test-token-1', 'test-token-1']);
      expect(lineup.recoveryCalls, 1);
      expect(lineup.currentChannelId, 'channel-0');
      expect(coordinator.error, isNull);

      await coordinator.stop();
    },
  );

  test('superseded active recovery cannot fail the winning tune', () async {
    final lineup = _TestLineup(
      recoverAuthorization: true,
      blockAuthorizationRecovery: true,
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _BlockingSecondLoadPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');
    player.emitError(
      recoverable: true,
      generation: player.loadGenerations.single,
      failureCode: 'http_error',
      httpStatus: 401,
    );
    await lineup.recoveryStarted.future;
    final winningTune = coordinator.tune('channel-0');
    await player.secondLoadStarted.future;
    lineup.finishRecovery.complete();
    await pumpEventQueue(times: 5);
    player.releaseSecondLoad.complete();
    await winningTune;

    expect(lineup.currentChannelId, 'channel-0');
    expect(coordinator.error, isNull);
    expect(coordinator.overlay, isNot(PlayerOverlay.error));
    await coordinator.stop();
  });

  test('load side effects roll back when load later fails', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _LoadFailurePlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final tuned = await coordinator.tune('channel-b');

    expect(player.loads, hasLength(1));
    expect(player.stops, 1);
    expect(lineup.currentChannelId, 'channel-0');
    expect(coordinator.overlay, PlayerOverlay.error);
    expect(tuned, isFalse);
  });

  test('initial media is loaded once and exposes failures', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _LoadFailurePlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final media = Uri.parse('lineup-test://initial');
    await coordinator.loadInitialMedia(media);
    await coordinator.loadInitialMedia(media);

    expect(player.loads, [media]);
    expect(
      coordinator.error,
      'Playback could not start. Retry or choose another channel.',
    );
    expect(coordinator.error, isNot(contains('load failed after dispatch')));
    expect(coordinator.overlay, PlayerOverlay.error);
  });

  for (final terminal in [PlayerState.ended, PlayerState.stopped]) {
    test(
      'standalone initial media $terminal clears its native scope',
      () async {
        final lineup = _TestLineup();
        final guide = GuideController(
          lineup: lineup,
          loadSchedule: (channel) async => _schedule(channel),
        );
        final player = _EventPlayer();
        final coordinator = PlayerCoordinator(
          player: player,
          lineup: lineup,
          guide: guide,
        );
        addTearDown(player.close);
        addTearDown(lineup.dispose);
        addTearDown(guide.dispose);
        addTearDown(coordinator.dispose);

        await coordinator.loadInitialMedia(Uri.parse('lineup-test://initial'));
        final generation = player.loadGenerations.single;
        player.emitStatus(terminal, generation: generation);
        await Future<void>.delayed(Duration.zero);
        player.emitStatus(PlayerState.playing, generation: generation);
        await Future<void>.delayed(Duration.zero);

        expect(coordinator.status.state, terminal);
        expect(coordinator.overlay, PlayerOverlay.none);
      },
    );
  }

  test('sleep picker is a sub-state of the OSD presentation', () {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final coordinator = PlayerCoordinator(
      player: _Player(),
      lineup: lineup,
      guide: guide,
    );
    addTearDown(coordinator.dispose);
    addTearDown(guide.dispose);
    addTearDown(lineup.dispose);

    coordinator.showOsd();
    final generation = coordinator.overlayPresentationGeneration;
    coordinator.showSleepTimer();
    expect(coordinator.overlay, PlayerOverlay.osd);
    expect(coordinator.sleepPickerOpen, isTrue);
    expect(coordinator.overlayPresentationGeneration, generation);

    coordinator.closeOverlay();
    expect(coordinator.overlay, PlayerOverlay.osd);
    expect(coordinator.sleepPickerOpen, isFalse);
    expect(coordinator.overlayPresentationGeneration, generation);
  });

  test('a tune supersedes a pending initial media load', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _ControlledPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final initial = coordinator.loadInitialMedia(
      Uri.parse('lineup-test://initial'),
    );
    await player.firstLoadStarted.future;
    await coordinator.tune('channel-b');
    player.releaseFirstLoad.complete();
    await initial;

    expect(lineup.currentChannelId, 'channel-b');
    expect(coordinator.error, isNull);
  });

  test('terminal error during seek cannot settle tune as successful', () async {
    final lineup = _TestLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _BlockingControlPlayer();
    addTearDown(player.close);
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    final tune = coordinator.tune('channel-b');
    await player.seekStarted.future;
    player.emitError(generation: player.loadGenerations.single);
    await Future<void>.delayed(Duration.zero);
    player.releaseSeek.complete();
    final tuned = await tune;

    expect(lineup.currentChannelId, 'channel-0');
    expect(coordinator.overlay, PlayerOverlay.error);
    expect(tuned, isFalse);
  });

  test(
    'terminal error during persistence restores the previous channel',
    () async {
      final lineup = _BlockingLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _EventPlayer();
      addTearDown(player.close);
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      final tune = coordinator.tune('channel-b');
      await lineup.persistenceStarted.future;
      player.emitError(generation: player.loadGenerations.single);
      await Future<void>.delayed(Duration.zero);
      lineup.releasePersistence.complete();
      final tuned = await tune;

      expect(lineup.currentChannelId, 'channel-0');
      expect(coordinator.overlay, PlayerOverlay.error);
      expect(tuned, isFalse);
    },
  );

  test('known schedule elapsed starts directly in the matching part', () async {
    final lineup = _TestLineup(
      playbackParts: _parts(first: const Duration(minutes: 30)),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _EventPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');

    expect(player.loads.single.path, '/part-2.mkv');
    expect(
      player.seeks.single,
      allOf(
        greaterThanOrEqualTo(const Duration(minutes: 29)),
        lessThanOrEqualTo(const Duration(minutes: 31)),
      ),
    );
  });

  test('initial known part target survives authorization recovery', () async {
    final lineup = _TestLineup(
      recoverAuthorization: true,
      playbackParts: _parts(first: const Duration(minutes: 30)),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _AsyncInitialAuthorizationPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');

    expect(player.loads.map((uri) => uri.path), ['/part-2.mkv', '/part-2.mkv']);
    expect(player.loadPlexTokens, ['test-token-1', 'test-token-2']);
    expect(
      player.seeks.where(
        (value) =>
            value >= const Duration(minutes: 29) &&
            value <= const Duration(minutes: 31),
      ),
      hasLength(1),
    );
    await coordinator.stop();
    expect(player.stops, 1);
  });

  test(
    'authorization during initial seek settles the replacement tune',
    () async {
      final lineup = _TestLineup(
        recoverAuthorization: true,
        playbackParts: _parts(first: const Duration(minutes: 30)),
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final player = _BlockingControlPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      final tune = coordinator.tune('channel-b');
      await player.seekStarted.future;
      final target = player.seeks.single;
      player.emitError(
        recoverable: true,
        generation: player.loadGenerations.single,
        failureCode: 'http_error',
        httpStatus: 401,
      );
      await pumpEventQueue(times: 5);
      expect(player.loads.map((uri) => uri.path), [
        '/part-2.mkv',
        '/part-2.mkv',
      ]);
      expect(player.loadPlexTokens, ['test-token-1', 'test-token-2']);
      expect(coordinator.tuning, isTrue);
      player.releaseSeek.complete();

      expect(await tune, isTrue);
      expect(player.seeks, [target, target]);
      expect(lineup.currentChannelId, 'channel-b');
      expect(coordinator.error, isNull);
      expect(lineup.recoveryCalls, 1);
    },
  );

  test('known cross-part seek loads a fresh native generation', () async {
    final lineup = _TestLineup(
      playbackParts: _parts(
        first: const Duration(hours: 2),
        second: const Duration(hours: 1),
      ),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _EventPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    await coordinator.tune('channel-b');

    await coordinator.seekTo(const Duration(hours: 2, minutes: 5));

    expect(player.loads.map((uri) => uri.path), ['/part-1.mkv', '/part-2.mkv']);
    expect(player.seeks.last, const Duration(minutes: 5));
    expect(
      player.loadGenerations.last!,
      greaterThan(player.loadGenerations.first!),
    );
  });

  test(
    'unrelated controls do not supersede a pending cross-part seek',
    () async {
      final lineup = _TestLineup(
        playbackParts: _parts(
          first: const Duration(hours: 2),
          second: const Duration(hours: 1),
        ),
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _BlockingSecondLoadPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);
      await coordinator.tune('channel-b');

      final seek = coordinator.seekTo(const Duration(hours: 2, minutes: 5));
      await player.secondLoadStarted.future;
      await coordinator.pause();
      player.releaseSecondLoad.complete();
      await seek;

      expect(player.seeks.last, const Duration(minutes: 5));
      expect(coordinator.error, isNull);
    },
  );

  test('known cross-part target survives authorization recovery', () async {
    final lineup = _TestLineup(
      recoverAuthorization: true,
      playbackParts: _parts(
        first: const Duration(hours: 2),
        second: const Duration(hours: 1),
      ),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _PartAuthorizationFailurePlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    await coordinator.tune('channel-b');

    await coordinator.seekTo(const Duration(hours: 2, minutes: 5));

    expect(player.loads.map((uri) => uri.path), [
      '/part-1.mkv',
      '/part-2.mkv',
      '/part-2.mkv',
    ]);
    expect(player.loadPlexTokens, [
      'test-token-1',
      'test-token-1',
      'test-token-2',
    ]);
    expect(
      player.seeks.where((value) => value == const Duration(minutes: 5)),
      hasLength(1),
    );
    await coordinator.stop();
  });

  test('cross-part authorization retry load failure is terminal', () async {
    final lineup = _TestLineup(
      recoverAuthorization: true,
      playbackParts: _parts(
        first: const Duration(hours: 2),
        second: const Duration(hours: 1),
      ),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _FailingPartAuthorizationRetryPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    await coordinator.tune('channel-b');

    await coordinator.seekTo(const Duration(hours: 2, minutes: 5));

    expect(player.loads.map((uri) => uri.path), [
      '/part-1.mkv',
      '/part-2.mkv',
      '/part-2.mkv',
    ]);
    expect(lineup.recoveryCalls, 1);
    expect(player.stops, 1);
    expect(coordinator.overlay, PlayerOverlay.error);
    expect(coordinator.error, isNotNull);
  });

  test(
    'same-tune cross seek supersedes a failing authorization retry load',
    () async {
      final lineup = _TestLineup(
        recoverAuthorization: true,
        playbackParts: _parts(
          first: const Duration(hours: 2),
          second: const Duration(hours: 1),
        ),
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _BlockingFailingPartAuthorizationRetryPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);
      await coordinator.tune('channel-b');

      final staleSeek = coordinator.seekTo(
        const Duration(hours: 2, minutes: 5),
      );
      await player.retryLoadStarted.future;
      await coordinator.seekTo(const Duration(minutes: 30));
      player.releaseRetryLoad.complete();
      await staleSeek;

      expect(player.loads.map((uri) => uri.path), [
        '/part-1.mkv',
        '/part-2.mkv',
        '/part-2.mkv',
        '/part-1.mkv',
      ]);
      expect(player.seeks.last, const Duration(minutes: 30));
      expect(lineup.recoveryCalls, 1);
      expect(coordinator.error, isNull);
      expect(coordinator.overlay, isNot(PlayerOverlay.error));
    },
  );

  test('blocked successful cross seek is inert after tune dispatch', () async {
    final lineup = _TestLineup(
      playbackParts: _parts(
        first: const Duration(hours: 2),
        second: const Duration(hours: 1),
      ),
    );
    final nextGuideStarted = Completer<void>();
    final releaseNextGuide = Completer<void>();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async {
        if (channel.id == 'channel-0') {
          nextGuideStarted.complete();
          await releaseNextGuide.future;
        }
        return _schedule(channel);
      },
    );
    final player = _BlockingSecondLoadPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    await coordinator.tune('channel-b');

    final stale = coordinator.seekTo(const Duration(hours: 2, minutes: 5));
    await player.secondLoadStarted.future;
    final winningTune = coordinator.tune('channel-0');
    await nextGuideStarted.future;
    coordinator.closeOverlay();
    player.releaseSecondLoad.complete();
    await stale;

    expect(player.seeks, isNot(contains(const Duration(minutes: 5))));
    expect(coordinator.overlay, PlayerOverlay.none);

    releaseNextGuide.complete();
    await winningTune;
    expect(lineup.currentChannelId, 'channel-0');
    expect(coordinator.error, isNull);
  });

  test('blocked recovery seek is inert after a newer tune', () async {
    final lineup = _TestLineup(recoverAuthorization: true);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _BlockingSecondSeekPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    await coordinator.tune('channel-b');
    player.position = const Duration(minutes: 12);
    player.emitError(
      recoverable: true,
      generation: player.loadGenerations.single,
      failureCode: 'http_error',
      httpStatus: 401,
    );
    await player.secondSeekStarted.future;

    await coordinator.tune('channel-0');
    player.releaseSecondSeek.complete();
    await pumpEventQueue(times: 5);

    expect(lineup.currentChannelId, 'channel-0');
    expect(coordinator.error, isNull);
    await coordinator.stop();
  });

  for (final operation in ['cross seek', 'part advance']) {
    test('$operation recovery cannot fail a newer tune', () async {
      final lineup = _TestLineup(
        recoverAuthorization: true,
        blockAuthorizationRecovery: true,
        playbackParts: _parts(
          first: const Duration(hours: 2),
          second: const Duration(hours: 1),
        ),
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _PartAuthorizationFailurePlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);
      await coordinator.tune('channel-b');

      Future<void>? pending;
      if (operation == 'cross seek') {
        pending = coordinator.seekTo(const Duration(hours: 2, minutes: 5));
      } else {
        player.position = player.duration;
        player.emitStatus(
          PlayerState.ended,
          generation: player.loadGenerations.single,
        );
      }
      await lineup.recoveryStarted.future;
      await coordinator.tune('channel-0');
      lineup.finishRecovery.complete();
      await pending;
      await pumpEventQueue(times: 5);

      expect(lineup.currentChannelId, 'channel-0');
      expect(coordinator.error, isNull);
      expect(coordinator.overlay, isNot(PlayerOverlay.error));
      await coordinator.stop();
    });
  }

  for (final operation in ['cross seek', 'part advance']) {
    test('stale $operation failure cannot mutate a newer load', () async {
      final lineup = _TestLineup(
        playbackParts: _parts(
          first: const Duration(hours: 2),
          second: const Duration(hours: 1),
        ),
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _BlockingFailingSecondLoadPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);
      await coordinator.tune('channel-b');

      Future<void>? stale;
      if (operation == 'cross seek') {
        stale = coordinator.seekTo(const Duration(hours: 2, minutes: 5));
      } else {
        player.position = player.duration;
        player.emitStatus(
          PlayerState.ended,
          generation: player.loadGenerations.single,
        );
      }
      await player.secondLoadStarted.future;
      await coordinator.seekTo(const Duration(hours: 1));
      player.releaseSecondLoad.complete();
      await stale;
      await Future<void>.delayed(Duration.zero);

      expect(player.loads.map((uri) => uri.path), [
        '/part-1.mkv',
        '/part-2.mkv',
        '/part-1.mkv',
      ]);
      expect(coordinator.error, isNull);
      expect(coordinator.overlay, isNot(PlayerOverlay.error));
      await coordinator.stop();
    });
  }

  test(
    'same-part seeks wait for readiness and apply only the latest target',
    () async {
      final lineup = _TestLineup(
        playbackParts: _parts(
          first: const Duration(hours: 2),
          second: const Duration(hours: 1),
        ),
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final player = _BlockingSecondLoadPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);
      await coordinator.tune('channel-b');
      player.seeks.clear();
      final first = coordinator.seekTo(const Duration(hours: 2, minutes: 5));
      await player.secondLoadStarted.future;
      final second = coordinator.seekTo(const Duration(hours: 2, minutes: 10));
      await pumpEventQueue(times: 2);
      expect(player.seeks, isEmpty);
      expect(player.loads, hasLength(2));
      player.releaseSecondLoad.complete();
      await Future.wait([first, second]);
      expect(player.seeks, [const Duration(minutes: 10)]);
      expect(coordinator.error, isNull);
    },
  );

  test(
    'latest same-part target survives pending authorization recovery',
    () async {
      final lineup = _TestLineup(
        recoverAuthorization: true,
        blockAuthorizationRecovery: true,
        playbackParts: _parts(
          first: const Duration(hours: 2),
          second: const Duration(hours: 1),
        ),
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      final player = _SuccessfulPartAuthorizationPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);
      await coordinator.tune('channel-b');
      player.seeks.clear();
      final first = coordinator.seekTo(const Duration(hours: 2, minutes: 5));
      await lineup.recoveryStarted.future;
      final second = coordinator.seekTo(const Duration(hours: 2, minutes: 10));
      await pumpEventQueue(times: 2);
      expect(player.seeks, isEmpty);
      lineup.finishRecovery.complete();
      await Future.wait([first, second]);
      expect(player.seeks, [const Duration(minutes: 10)]);
      expect(coordinator.error, isNull);
    },
  );

  for (final fail in [false, true]) {
    test(
      'latest target awaits authorization replacement load (fails: $fail)',
      () async {
        final lineup = _TestLineup(
          recoverAuthorization: true,
          playbackParts: _parts(
            first: const Duration(hours: 2),
            second: const Duration(hours: 1),
          ),
        );
        final guide = GuideController(
          lineup: lineup,
          loadSchedule: (channel) async => _schedule(channel),
        );
        final player = _BlockingFailingPartAuthorizationRetryPlayer(fail: fail);
        final coordinator = PlayerCoordinator(
          player: player,
          lineup: lineup,
          guide: guide,
        );
        addTearDown(player.close);
        addTearDown(lineup.dispose);
        addTearDown(guide.dispose);
        addTearDown(coordinator.dispose);
        await coordinator.tune('channel-b');
        player.seeks.clear();
        final first = coordinator.seekTo(const Duration(hours: 2, minutes: 5));
        await player.retryLoadStarted.future;
        final second = coordinator.seekTo(
          const Duration(hours: 2, minutes: 10),
        );
        await pumpEventQueue(times: 2);
        expect(player.seeks, isEmpty);
        player.releaseRetryLoad.complete();
        await Future.wait([first, second]);
        expect(player.seeks, fail ? isEmpty : [const Duration(minutes: 10)]);
        expect(coordinator.error, fail ? isNotNull : isNull);
        expect(player.stops, fail ? 1 : 0);
      },
    );
  }

  test('latest target can return to zero during a pending part seek', () async {
    final lineup = _TestLineup(
      playbackParts: _parts(
        first: const Duration(hours: 2),
        second: const Duration(hours: 1),
      ),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    final player = _BlockingSecondSeekPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    await coordinator.tune('channel-b');

    final first = coordinator.seekTo(const Duration(hours: 2, minutes: 5));
    await player.secondSeekStarted.future;
    final latest = coordinator.seekTo(const Duration(hours: 2));
    player.releaseSecondSeek.complete();
    await Future.wait([first, latest]);

    expect(player.loads.map((uri) => uri.path), ['/part-1.mkv', '/part-2.mkv']);
    expect(player.seeks.sublist(1), [
      const Duration(minutes: 5),
      Duration.zero,
    ]);
    expect(coordinator.error, isNull);
  });

  test('same-part seek preserves its pending cross-part failure', () async {
    final lineup = _TestLineup(
      playbackParts: _parts(
        first: const Duration(hours: 2),
        second: const Duration(hours: 1),
      ),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _BlockingFailingSecondLoadPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    await coordinator.tune('channel-b');

    final stale = coordinator.seekTo(const Duration(hours: 2, minutes: 5));
    await player.secondLoadStarted.future;
    final latest = coordinator.seekTo(const Duration(hours: 2, minutes: 10));
    await Future<void>.delayed(Duration.zero);
    expect(player.seeks, isNot(contains(const Duration(minutes: 10))));
    player.releaseSecondLoad.complete();
    await Future.wait([stale, latest]);

    expect(player.seeks, isNot(contains(const Duration(minutes: 10))));
    expect(player.seeks, isNot(contains(const Duration(minutes: 5))));
    expect(player.stops, 1);
    expect(coordinator.error, isNotNull);
    expect(coordinator.overlay, PlayerOverlay.error);
  });

  test('unknown boundaries stay on and report the current part', () async {
    final lineup = _TestLineup(playbackParts: _parts());
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _EventPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    await coordinator.tune('channel-b');
    player
      ..position = const Duration(seconds: 7)
      ..duration = const Duration(seconds: 20)
      ..emitStatus(
        PlayerState.playing,
        generation: player.loadGenerations.single,
      );
    await Future<void>.delayed(Duration.zero);

    expect(player.loads.single.path, '/part-1.mkv');
    expect(player.seeks, isEmpty);
    expect(coordinator.position, const Duration(seconds: 7));
    expect(coordinator.duration, const Duration(seconds: 20));
  });

  test('completed native duration establishes aggregate projection', () async {
    final lineup = _TestLineup(
      playbackParts: _parts(second: const Duration(hours: 1)),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _EventPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    await coordinator.tune('channel-b');
    player.duration = const Duration(hours: 2);
    player.position = player.duration;
    player.emitStatus(
      PlayerState.ended,
      generation: player.loadGenerations.single,
    );
    await pumpEventQueue(times: 2);
    player
      ..position = const Duration(minutes: 5)
      ..duration = const Duration(hours: 1)
      ..tracks = const [
        PlayerTrack(
          id: 22,
          type: PlayerTrackType.audio,
          selected: true,
          codec: 'aac',
        ),
      ]
      ..emitStatus(
        PlayerState.playing,
        generation: player.loadGenerations.last,
      );
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.position, const Duration(hours: 2, minutes: 5));
    expect(coordinator.duration, const Duration(hours: 3));
    expect(coordinator.tracks.single.id, 22);
    await coordinator.seekBy(const Duration(minutes: 5));
    expect(player.seeks.last, const Duration(minutes: 10));
  });

  test('natural multipart completion advances once then continues', () async {
    final fixture = _ContinuationFixture(
      parts: _parts(
        first: const Duration(seconds: 60),
        second: const Duration(seconds: 60),
      ),
    );
    addTearDown(fixture.close);
    await fixture.coordinator.tune('channel-b');
    final generation = fixture.player.loadGenerations.single;
    fixture.player.position = const Duration(seconds: 60);
    fixture.player.duration = const Duration(seconds: 60);
    fixture.player.emitStatus(PlayerState.ended, generation: generation);
    fixture.player.emitStatus(PlayerState.ended, generation: generation);
    await pumpEventQueue(times: 5);
    expect(fixture.player.loads, hasLength(2));
    expect(fixture.player.loads.last.path, '/part-2.mkv');
    fixture.player.emitStatus(
      PlayerState.playing,
      generation: fixture.player.loadGenerations.last,
    );
    fixture.player.emitStatus(
      PlayerState.ended,
      generation: fixture.player.loadGenerations.last,
    );
    await pumpEventQueue(times: 5);
    expect(fixture.player.loads, hasLength(3));
    expect(fixture.coordinator.currentProgram!.scheduled.item.id, 'short-1');
    expect(fixture.coordinator.hasPlaybackIntent, isTrue);
  });

  test('explicit stop and stale completion never advance parts', () async {
    final lineup = _TestLineup(
      playbackParts: _parts(
        first: const Duration(hours: 2),
        second: const Duration(hours: 1),
      ),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _EventPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    await coordinator.tune('channel-b');
    final generation = player.loadGenerations.single;
    player.position = player.duration;
    player.emitStatus(PlayerState.ended, generation: generation! + 1);
    await Future<void>.delayed(Duration.zero);
    await coordinator.stop();
    player.emitStatus(PlayerState.stopped, generation: generation);
    await Future<void>.delayed(Duration.zero);

    expect(player.loads, hasLength(1));
    expect(coordinator.hasPlaybackIntent, isFalse);
  });

  test(
    'current stopped during cross-part replacement does not advance',
    () async {
      final lineup = _TestLineup(
        playbackParts: _parts(
          first: const Duration(hours: 2),
          second: const Duration(hours: 1),
        ),
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _BlockingSecondLoadPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);
      await coordinator.tune('channel-b');

      final seek = coordinator.seekTo(const Duration(hours: 2, minutes: 5));
      await player.secondLoadStarted.future;
      player.emitStatus(
        PlayerState.stopped,
        generation: player.loadGenerations.last,
      );
      await Future<void>.delayed(Duration.zero);
      player.releaseSecondLoad.complete();
      await seek;

      expect(player.loads, hasLength(2));
      expect(player.seeks.last, const Duration(minutes: 5));
      expect(coordinator.error, isNull);
    },
  );

  test('queued stopped after part load settlement is cleanup', () async {
    final lineup = _TestLineup(
      playbackParts: _parts(
        first: const Duration(hours: 2),
        second: const Duration(hours: 1),
      ),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _EventPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');
    player.position = player.duration;
    player.emitStatus(
      PlayerState.ended,
      generation: player.loadGenerations.single,
    );
    await pumpEventQueue(times: 2);
    final secondGeneration = player.loadGenerations.last;

    player.emitStatus(PlayerState.stopped, generation: secondGeneration);
    await Future<void>.delayed(Duration.zero);
    expect(player.loads, hasLength(2));

    player.position = player.duration;

    player.emitStatus(PlayerState.ended, generation: secondGeneration);
    await pumpEventQueue(times: 2);
    expect(player.loads, hasLength(3));
    expect(coordinator.hasPlaybackIntent, isTrue);
  });

  test('credential retry on part two reloads only that logical part', () async {
    final lineup = _TestLineup(
      recoverAuthorization: true,
      playbackParts: _parts(
        first: const Duration(minutes: 30),
        second: const Duration(hours: 2),
      ),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _EventPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    await coordinator.tune('channel-b');
    player.position = const Duration(minutes: 12);
    player.emitStatus(
      PlayerState.playing,
      generation: player.loadGenerations.single,
    );
    await Future<void>.delayed(Duration.zero);
    player.emitError(
      recoverable: true,
      generation: player.loadGenerations.single,
      failureCode: 'http_error',
      httpStatus: 401,
    );
    await pumpEventQueue(times: 5);

    expect(player.loads.map((uri) => uri.path), ['/part-2.mkv', '/part-2.mkv']);
    expect(player.loadPlexTokens, ['test-token-1', 'test-token-2']);
    expect(player.seeks.last, const Duration(minutes: 12));
    await coordinator.stop();
  });

  test(
    'synchronous part transition authorization failure replaces active request',
    () async {
      final lineup = _TestLineup(
        recoverAuthorization: true,
        playbackParts: _parts(
          first: const Duration(hours: 2),
          second: const Duration(hours: 1),
        ),
      );
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      )..requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _SuccessfulPartAuthorizationPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(player.close);
      addTearDown(lineup.dispose);
      addTearDown(guide.dispose);
      addTearDown(coordinator.dispose);

      await coordinator.tune('channel-b');
      player.position = player.duration;
      player.emitStatus(
        PlayerState.ended,
        generation: player.loadGenerations.single,
      );
      for (var index = 0; index < 10 && player.loads.length < 3; index++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(player.loads.map((uri) => uri.path), [
        '/part-1.mkv',
        '/part-2.mkv',
        '/part-2.mkv',
      ]);
      expect(player.loadPlexTokens, [
        'test-token-1',
        'test-token-1',
        'test-token-2',
      ]);
      expect(player.seeks.last, const Duration(minutes: 7));
      expect(lineup.recoveryCalls, 1);
      expect(coordinator.error, isNull);

      player.position = player.duration;
      player.emitStatus(
        PlayerState.playing,
        generation: player.loadGenerations.last,
      );
      player.emitStatus(
        PlayerState.ended,
        generation: player.loadGenerations.last,
      );
      await pumpEventQueue(times: 2);
      expect(player.loads, hasLength(4));
      expect(coordinator.hasPlaybackIntent, isTrue);
      await coordinator.stop();
    },
  );

  test('async no-throw part authorization recovery is awaited', () async {
    final lineup = _TestLineup(
      recoverAuthorization: true,
      playbackParts: _parts(
        first: const Duration(hours: 2),
        second: const Duration(hours: 1),
      ),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _SuccessfulPartAuthorizationPlayer(sync: false);
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');
    player.position = player.duration;
    player.emitStatus(
      PlayerState.ended,
      generation: player.loadGenerations.single,
    );
    for (var index = 0; index < 10 && player.loads.length < 3; index++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(player.loadPlexTokens, [
      'test-token-1',
      'test-token-1',
      'test-token-2',
    ]);
    expect(player.seeks.last, const Duration(minutes: 7));
    await coordinator.stop();
  });

  test('part transition authorization recovery failure is terminal', () async {
    final lineup = _TestLineup(
      recoverAuthorization: true,
      failAuthorizationRecovery: true,
      playbackParts: _parts(
        first: const Duration(hours: 2),
        second: const Duration(hours: 1),
      ),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _SuccessfulPartAuthorizationPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-b');
    player.position = player.duration;
    player.emitStatus(
      PlayerState.ended,
      generation: player.loadGenerations.single,
    );
    await pumpEventQueue(times: 5);

    expect(lineup.recoveryCalls, 1);
    expect(player.loads, hasLength(2));
    expect(player.stops, 1);
    expect(coordinator.canRetry, isTrue);
    expect(coordinator.overlay, PlayerOverlay.error);
    expect(
      coordinator.error,
      'Playback could not start. Retry or choose another channel.',
    );
  });

  test('part transition failure stops and settles playback', () async {
    final lineup = _TestLineup(
      playbackParts: _parts(
        first: const Duration(hours: 2),
        second: const Duration(hours: 1),
      ),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _SecondLoadFailurePlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    await coordinator.tune('channel-b');
    player.position = player.duration;
    player.emitStatus(
      PlayerState.ended,
      generation: player.loadGenerations.single,
    );
    await pumpEventQueue(times: 2);

    expect(player.loads, hasLength(2));
    expect(player.stops, 1);
    expect(coordinator.overlay, PlayerOverlay.error);
  });

  test('superseded transition cleanup cannot publish a stale error', () async {
    final lineup = _TestLineup(
      playbackParts: _parts(
        first: const Duration(hours: 2),
        second: const Duration(hours: 1),
      ),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _BlockingTransitionFailurePlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    await coordinator.tune('channel-b');
    player.position = player.duration;
    player.emitStatus(
      PlayerState.ended,
      generation: player.loadGenerations.single,
    );
    await player.stopStarted.future;

    final winningTune = coordinator.tune('channel-0');
    await Future<void>.delayed(Duration.zero);
    expect(player.loads, hasLength(2));
    player.releaseStop.complete();
    await winningTune;
    await pumpEventQueue(times: 5);

    expect(lineup.currentChannelId, 'channel-0');
    expect(coordinator.error, isNull);
    expect(coordinator.canRetry, isFalse);
    expect(coordinator.overlay, isNot(PlayerOverlay.error));
    await coordinator.stop();
    expect(player.stops, 2);
  });

  test('failed channel replacement retains the prior channel', () async {
    final lineup = _TestLineup(
      playbackParts: _parts(
        first: const Duration(hours: 2),
        second: const Duration(hours: 1),
      ),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _SecondLoadFailurePlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    expect(await coordinator.tune('channel-0'), isTrue);
    expect(await coordinator.tune('channel-b'), isFalse);

    expect(player.loads, hasLength(2));
    expect(player.stops, 2);
    expect(lineup.currentChannelId, 'channel-0');
    expect(coordinator.overlay, PlayerOverlay.error);
    await coordinator.stop();
    expect(player.stops, 3);
  });

  test('failed tune cleanup stopped cannot advance attempted media', () async {
    final lineup = _TestLineup(
      playbackParts: _parts(
        first: const Duration(hours: 2),
        second: const Duration(hours: 1),
      ),
    );
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    await Future<void>.delayed(Duration.zero);
    final player = _QueuedStopSecondLoadFailurePlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(player.close);
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.tune('channel-0');
    await coordinator.tune('channel-b');
    await Future<void>.delayed(Duration.zero);

    expect(player.loads, hasLength(2));
    expect(player.stops, 2);
    expect(coordinator.overlay, PlayerOverlay.error);
  });

  test('mini Guide reconciles deletion and reloads its visible rows', () async {
    final lineup = _TestLineup(count: 1000);
    var loads = 0;
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async {
        loads++;
        return _schedule(channel);
      },
    );
    final coordinator = PlayerCoordinator(
      player: _Player(),
      lineup: lineup,
      guide: guide,
    );
    addTearDown(lineup.dispose);
    addTearDown(guide.dispose);
    addTearDown(coordinator.dispose);
    coordinator.showMiniGuide();
    coordinator.moveMiniGuide(500);
    await Future<void>.delayed(Duration.zero);
    final removed = coordinator.miniGuideChannelId;
    final before = loads;

    lineup.replaceChannels(
      lineup.channels.where((channel) => channel.id != removed).toList(),
    );
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.miniGuideChannelId, isNot(removed));
    expect(coordinator.miniGuideChannelIndex, 500);
    expect(loads, greaterThan(before));
  });
}

void _showPresentation(PlayerCoordinator coordinator, PlayerOverlay overlay) {
  switch (overlay) {
    case PlayerOverlay.none:
      coordinator.closeOverlay();
    case PlayerOverlay.osd:
      coordinator.showOsd();
    case PlayerOverlay.fullGuide:
      coordinator.showFullGuide();
    case PlayerOverlay.miniGuide:
      coordinator.showMiniGuide();
    case PlayerOverlay.nowPlaying:
      coordinator.showNowPlaying();
    default:
      throw ArgumentError.value(overlay);
  }
}

class _ContinuationStatePlayer extends _EventPlayer {
  _ContinuationStatePlayer(this.firstReady) : super(sync: true);

  final PlayerState firstReady;

  @override
  Future<void> stop() async {
    await super.stop();
    emitStatus(PlayerState.stopped);
  }

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    if (loads.length != 2) return;
    for (final state in [
      PlayerState.loading,
      PlayerState.paused,
      PlayerState.buffering,
      PlayerState.seeking,
      firstReady,
    ]) {
      emitStatus(state, generation: generation);
    }
  }
}

class _ContinuationFixture {
  _ContinuationFixture({
    List<LineupPlaybackPart>? parts,
    _EventPlayer? player,
    bool recoverAuthorization = false,
  }) : lineup = _TestLineup(
         playbackParts: parts,
         recoverAuthorization: recoverAuthorization,
       ),
       player = player ?? _EventPlayer() {
    lineup.replaceChannels([
      for (final channel in lineup.channels)
        Channel(
          id: channel.id,
          number: channel.number,
          name: channel.name,
          source: ManualSource([
            for (var i = 0; i < 3; i++)
              ChannelItem(
                id: 'short-$i',
                title: 'Short $i',
                duration: const Duration(seconds: 120),
              ),
          ]),
          playbackMode: PlaybackMode.sequential,
          anchor: now,
          shuffleSeed: 0,
        ),
    ]);
    guide = _ContinuationGuide(lineup: lineup, clock: () => now);
    coordinator = PlayerCoordinator(
      player: this.player,
      lineup: lineup,
      guide: guide,
      clock: () => now,
    );
  }
  DateTime now = DateTime(2026, 10, 10, 12);
  final _TestLineup lineup;
  final _EventPlayer player;
  late final _ContinuationGuide guide;
  late final PlayerCoordinator coordinator;
  bool disposed = false;

  void endNaturally() {
    player.position = const Duration(seconds: 60);
    player.duration = const Duration(seconds: 60);
    player.emitStatus(
      PlayerState.ended,
      generation: player.loadGenerations.last,
    );
  }

  Future<void> close() async {
    if (!disposed) coordinator.dispose();
    guide.dispose();
    lineup.dispose();
    await player.close();
  }
}

class _ContinuationGuide extends GuideController {
  _ContinuationGuide({required super.lineup, required super.clock})
    : super(loadSchedule: (channel) async => _schedule(channel));
  String? resolution;

  @override
  Future<GuideProgram?> ensureCurrentProgram(String channelId) async {
    if (resolution == 'null') return null;
    return super.ensureCurrentProgram(channelId);
  }

  @override
  GuideProgram? currentProgram(String channelId, [DateTime? at]) {
    if (at != null && resolution == 'missing successor') return null;
    if (at != null && resolution == 'same successor') {
      return super.currentProgram(channelId);
    }
    return super.currentProgram(channelId, at);
  }
}

ScheduleIndex _schedule(Channel channel) => buildSchedule(
  (channel.source as ManualSource).items,
  mode: channel.playbackMode,
  seed: channel.shuffleSeed,
);

List<LineupPlaybackPart> _parts({Duration? first, Duration? second}) => [
  LineupPlaybackPart(
    uri: Uri.parse('https://media.test/part-1.mkv'),
    duration: first,
  ),
  LineupPlaybackPart(
    uri: Uri.parse('https://media.test/part-2.mkv'),
    duration: second,
  ),
];

class _TestLineup extends LineupController {
  _TestLineup({
    LineupScenario? scenario,
    int count = 2,
    this.failSecondPlaybackRequest = false,
    this.recoverAuthorization = false,
    this.replacementRecoverable = false,
    this.blockAuthorizationRecovery = false,
    this.throwAuthorizationRecoverySynchronously = false,
    this.failAuthorizationRecovery = false,
    this.authorizationRecoveryFailure,
    this.useRealPlaybackRequest = false,
    this.playbackParts,
  }) : super(
         store: _MemoryStore(),
         credentials: _Credentials(),
         plex: PlexClient(
           clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
         ),
       ) {
    final initialChannels = List.generate(count, (index) {
      final id = index == 1 ? 'channel-b' : 'channel-$index';
      return Channel(
        id: id,
        number: index == 1 ? 9 : index + 1,
        name: 'Channel $index',
        source: ManualSource([
          ChannelItem(
            id: 'program-$index',
            title: 'Program $index',
            duration: const Duration(hours: 24),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.now().subtract(const Duration(hours: 1)),
        shuffleSeed: index,
      );
    });

    installScenario(
      (scenario ?? const LineupScenario()).withDefaults(
        LineupScenario(
          channels: initialChannels,
          currentChannelId: initialChannels.first.id,
          stage: SetupStage.ready,
        ),
      ),
    );
  }

  final bool failSecondPlaybackRequest;
  final bool recoverAuthorization;
  final bool replacementRecoverable;
  final bool blockAuthorizationRecovery;
  final bool throwAuthorizationRecoverySynchronously;
  final bool failAuthorizationRecovery;
  final Object? authorizationRecoveryFailure;
  final bool useRealPlaybackRequest;
  final List<LineupPlaybackPart>? playbackParts;
  int playbackRequests = 0;
  String? lastPlaybackItemId;
  int recoveryCalls = 0;
  final recoveryStarted = Completer<void>();
  final finishRecovery = Completer<void>();
  int _testContentGeneration = 0;

  @override
  int get contentGeneration => _testContentGeneration;

  void changeContentScope() {
    _testContentGeneration++;
    notifyListeners();
  }

  void replaceChannels(List<Channel> value) {
    fixtureActor.replaceChannels(List.unmodifiable(value));
    notifyListeners();
  }

  void setSettings(LineupSettings value) {
    fixtureActor.publishSettings(value);
    notifyListeners();
  }

  void clearCurrentChannel() {
    fixtureActor.selectChannel(null);
    notifyListeners();
  }

  @override
  LineupPlaybackRequest playbackFor(String itemId) {
    playbackRequests++;
    lastPlaybackItemId = itemId;
    if (useRealPlaybackRequest) return super.playbackFor(itemId);
    if (failSecondPlaybackRequest && playbackRequests == 2) {
      throw StateError('Replacement playback request is unavailable.');
    }
    return _request(
      recoverAuthorization ? 'test-token-1' : 'test-token',
      recoverable: recoverAuthorization,
    );
  }

  LineupPlaybackRequest _request(String token, {bool recoverable = false}) {
    final parts =
        playbackParts ??
        [
          LineupPlaybackPart(
            uri: Uri.parse(
              'https://media.test/program?x-PLEX-token=must-not-leak&quality=original',
            ),
          ),
        ];
    Future<LineupPlaybackRequest> completeRecovery() async {
      if (blockAuthorizationRecovery) {
        recoveryStarted.complete();
        await finishRecovery.future;
      }
      return _request('test-token-2', recoverable: replacementRecoverable);
    }

    Future<LineupPlaybackRequest> recover() {
      recoveryCalls++;
      if (throwAuthorizationRecoverySynchronously) {
        throw StateError('authorization recovery failed synchronously');
      }
      if (failAuthorizationRecovery) {
        return Future.error(
          authorizationRecoveryFailure ??
              StateError('authorization recovery failed'),
        );
      }
      return completeRecovery();
    }

    return LineupPlaybackRequest.parts(
      parts,
      plexToken: token,
      authorizationRecovery: recoverable ? recover : null,
    );
  }

  @override
  Future<void> setCurrentChannel(String? id) async {
    fixtureActor.selectChannel(id);
    notifyListeners();
  }
}

class _LogoutLineup extends _TestLineup {
  var logoutCalls = 0;

  @override
  Future<bool> logout() async {
    logoutCalls++;
    if (logoutCalls == 1) return false;
    changeContentScope();
    return true;
  }
}

class _FailingPersistenceLineup extends _TestLineup {
  @override
  Future<void> setCurrentChannel(String? id) async {
    if (id == 'channel-b') throw StateError('persistence failed');
    await super.setCurrentChannel(id);
  }
}

class _BlockingLineup extends _TestLineup {
  final persistenceStarted = Completer<void>();
  final releasePersistence = Completer<void>();
  bool _blocked = false;

  @override
  Future<void> setCurrentChannel(String? id) async {
    fixtureActor.selectChannel(id);
    notifyListeners();
    if (!_blocked) {
      _blocked = true;
      persistenceStarted.complete();
      await releasePersistence.future;
    }
  }
}

class _Player implements NativePlayer {
  final loads = <Uri>[];
  final loadPlexTokens = <String?>[];
  final loadGenerations = <int?>[];
  final seeks = <Duration>[];
  final fullscreenValues = <bool>[];
  final selectedTracks = <(PlayerTrackType, int?)>[];
  int stops = 0;
  int plays = 0;

  @override
  PlayerStatus status = const PlayerStatus(
    state: PlayerState.playing,
    message: 'Playing',
  );
  @override
  Duration position = const Duration(minutes: 10);
  @override
  Duration duration = const Duration(hours: 1);
  @override
  PlayerTelemetry telemetry = const PlayerTelemetry();
  @override
  List<PlayerTrack> tracks = const [];
  @override
  Stream<PlayerEvent> get events => const Stream.empty();
  @override
  DisplayMatchingReport get displayReport =>
      const DisplayMatchingReport.initial();
  @override
  Stream<DisplayMatchingReport> get displayReports => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    loads.add(media);
    loadPlexTokens.add(plexToken);
    loadGenerations.add(generation);
  }

  @override
  Future<void> setDisplayMatching(DisplayMatchingRequest request) async {}

  @override
  Future<void> play() async {
    plays++;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration value) async => seeks.add(value);
  @override
  Future<void> setVideoRect(PlayerVideoRect rect) async {}
  @override
  Future<void> setFullscreen(bool fullscreen) async {
    fullscreenValues.add(fullscreen);
  }

  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async =>
      selectedTracks.add((type, id));
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {}
}

class _CancellingPlayer extends _Player {
  final eventCancellation = Completer<void>();
  final displayCancellation = Completer<void>();
  late final eventStream = StreamController<PlayerEvent>(
    onCancel: () => eventCancellation.future,
  );
  late final displayStream = StreamController<DisplayMatchingReport>(
    onCancel: () => displayCancellation.future,
  );

  @override
  Stream<PlayerEvent> get events => eventStream.stream;

  @override
  Stream<DisplayMatchingReport> get displayReports => displayStream.stream;
}

class _FailingStopPlayer extends _Player {
  @override
  Future<void> stop() async => throw StateError('native stop failed');
}

mixin _BlocksFirstLoad on _Player {
  final firstLoadStarted = Completer<void>();
  final releaseFirstLoad = Completer<void>();

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    if (loads.length == 1) {
      firstLoadStarted.complete();
      await releaseFirstLoad.future;
    }
  }
}

class _ControlledPlayer extends _Player with _BlocksFirstLoad {}

class _BlockingFullscreenPlayer extends _Player {
  _BlockingFullscreenPlayer({required this.blockOn});

  final bool blockOn;
  final fullscreenStarted = Completer<void>();
  final releaseFullscreen = Completer<void>();

  @override
  Future<void> setFullscreen(bool fullscreen) async {
    await super.setFullscreen(fullscreen);
    if (fullscreen != blockOn) return;
    if (!fullscreenStarted.isCompleted) fullscreenStarted.complete();
    await releaseFullscreen.future;
  }
}

class _BlockingStopPlayer extends _Player {
  final stopStarted = Completer<void>();
  final releaseStop = Completer<void>();

  @override
  Future<void> stop() async {
    await super.stop();
    if (!stopStarted.isCompleted) stopStarted.complete();
    await releaseStop.future;
  }
}

class _BlockingStopEventPlayer extends _EventPlayer {
  final stopStarted = Completer<void>();
  final releaseStop = Completer<void>();

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    emitStatus(PlayerState.playing, generation: generation);
  }

  @override
  Future<void> stop() async {
    await super.stop();
    if (!stopStarted.isCompleted) stopStarted.complete();
    await releaseStop.future;
  }
}

class _PreemptibleLoadPlayer extends _EventPlayer {
  _PreemptibleLoadPlayer({required this.blockStop});

  final bool blockStop;
  final loadStarted = Completer<void>();
  final stopStarted = Completer<void>();
  final releaseStop = Completer<void>();
  final calls = <String>[];
  Completer<void>? _pendingLoad;
  bool loadSettled = false;

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    calls.add('load');
    if (loads.length != 1) return;
    final pending = _pendingLoad = Completer<void>();
    loadStarted.complete();
    try {
      await pending.future;
    } finally {
      loadSettled = true;
    }
  }

  @override
  Future<void> stop() async {
    await super.stop();
    calls.add('stop');
    final pending = _pendingLoad;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const PlayerUnavailable('Load stopped.'));
    }
    if (!stopStarted.isCompleted) stopStarted.complete();
    if (blockStop) await releaseStop.future;
  }
}

class _LoadFailurePlayer extends _Player {
  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    throw StateError('load failed after dispatch');
  }
}

class _EventPlayer extends _Player {
  _EventPlayer({bool sync = false})
    : _events = StreamController<PlayerEvent>.broadcast(sync: sync);

  final StreamController<PlayerEvent> _events;
  bool failStop = false;

  @override
  Stream<PlayerEvent> get events => _events.stream;

  void emitError({
    bool recoverable = false,
    int? generation,
    String message = 'Failed',
    String? audioCodec,
    String? failureCode,
    int? httpStatus,
    String? videoCodec,
    String? videoOutput,
    String? hardwareDecoder,
  }) {
    _events.add(
      PlayerEvent(
        status: PlayerStatus(
          state: PlayerState.error,
          message: message,
          recoverable: recoverable,
          failureCode: failureCode,
          httpStatus: httpStatus,
        ),
        position: Duration.zero,
        duration: Duration.zero,
        telemetry: PlayerTelemetry(
          videoCodec: videoCodec,
          videoOutput: videoOutput,
          hardwareDecoder: hardwareDecoder,
        ),
        tracks: audioCodec == null
            ? const []
            : [
                PlayerTrack(
                  id: 1,
                  type: PlayerTrackType.audio,
                  selected: true,
                  codec: audioCodec,
                ),
              ],
        generation: generation,
      ),
    );
  }

  void emitStatus(
    PlayerState state, {
    int? generation,
    bool tracksUpdated = false,
  }) {
    _events.add(
      PlayerEvent(
        status: PlayerStatus(state: state, message: state.name),
        position: position,
        duration: duration,
        telemetry: telemetry,
        tracks: tracks,
        generation: generation,
        tracksUpdated: tracksUpdated,
      ),
    );
  }

  @override
  Future<void> stop() async {
    await super.stop();
    if (failStop) throw StateError('opaque-secret-sentinel');
  }

  Future<void> close() => _events.close();
}

class _SecondLoadFailurePlayer extends _EventPlayer {
  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    if (loads.length == 2) throw StateError('part transition failed');
  }
}

class _BlockingSecondLoadPlayer extends _EventPlayer {
  @override
  Future<void> seek(Duration position) async {
    if (secondLoadStarted.isCompleted && !releaseSecondLoad.isCompleted) {
      throw StateError('Destination part is not ready.');
    }
    await super.seek(position);
  }

  final secondLoadStarted = Completer<void>();
  final releaseSecondLoad = Completer<void>();

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    if (loads.length != 2) return;
    secondLoadStarted.complete();
    await releaseSecondLoad.future;
  }
}

class _BlockingFailingSecondLoadPlayer extends _EventPlayer {
  final secondLoadStarted = Completer<void>();
  final releaseSecondLoad = Completer<void>();

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    if (loads.length != 2) return;
    secondLoadStarted.complete();
    await releaseSecondLoad.future;
    throw StateError('stale load failed');
  }
}

class _SynchronousAuthorizationPlayer extends _EventPlayer {
  _SynchronousAuthorizationPlayer({
    this.failures = 1,
    this.failureCode = 'http_error',
    this.httpStatus = 401,
  }) : super(sync: true);

  final int failures;
  final String failureCode;
  final int? httpStatus;

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    if (loads.length > failures) return;
    emitError(
      recoverable: true,
      generation: generation,
      failureCode: failureCode,
      httpStatus: httpStatus,
    );
    throw StateError('native load failed');
  }
}

class _AsyncInitialAuthorizationPlayer extends _EventPlayer {
  _AsyncInitialAuthorizationPlayer() : super(sync: false);

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    if (loads.length != 1) return;
    emitError(
      recoverable: true,
      generation: generation,
      failureCode: 'http_error',
      httpStatus: 401,
    );
    await Future<void>.delayed(Duration.zero);
  }
}

class _SuccessfulPartAuthorizationPlayer extends _EventPlayer {
  _SuccessfulPartAuthorizationPlayer({super.sync = true});

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    if (loads.length != 2) return;
    position = const Duration(minutes: 7);
    _events.add(
      PlayerEvent(
        status: const PlayerStatus(
          state: PlayerState.error,
          message: 'Unauthorized',
          recoverable: true,
          failureCode: 'http_error',
          httpStatus: 401,
        ),
        position: position,
        duration: duration,
        telemetry: telemetry,
        tracks: tracks,
        generation: generation,
      ),
    );
  }
}

class _PartAuthorizationFailurePlayer extends _EventPlayer {
  _PartAuthorizationFailurePlayer() : super(sync: true);

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    if (loads.length != 2) return;
    emitError(
      recoverable: true,
      generation: generation,
      failureCode: 'http_error',
      httpStatus: 401,
    );
    throw StateError('native load rejected');
  }
}

class _FailingPartAuthorizationRetryPlayer
    extends _PartAuthorizationFailurePlayer {
  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    if (loads.length == 3) throw StateError('authorization retry failed');
  }
}

class _BlockingFailingPartAuthorizationRetryPlayer
    extends _PartAuthorizationFailurePlayer {
  _BlockingFailingPartAuthorizationRetryPlayer({this.fail = true});
  final bool fail;
  final retryLoadStarted = Completer<void>();
  final releaseRetryLoad = Completer<void>();

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    if (loads.length != 3) return;
    retryLoadStarted.complete();
    await releaseRetryLoad.future;
    if (fail) throw StateError('authorization retry failed');
  }
}

class _BlockingTransitionFailurePlayer extends _SecondLoadFailurePlayer {
  final stopStarted = Completer<void>();
  final releaseStop = Completer<void>();

  @override
  Future<void> stop() async {
    await super.stop();
    if (!stopStarted.isCompleted) stopStarted.complete();
    await releaseStop.future;
  }
}

class _QueuedStopSecondLoadFailurePlayer extends _SecondLoadFailurePlayer {
  @override
  Future<void> stop() async {
    await super.stop();
    scheduleMicrotask(
      () => emitStatus(PlayerState.stopped, generation: loadGenerations.last),
    );
  }
}

class _BlockingEventPlayer extends _EventPlayer with _BlocksFirstLoad {}

class _BlockingControlPlayer extends _EventPlayer {
  final seekStarted = Completer<void>();
  final releaseSeek = Completer<void>();
  final selectStarted = Completer<void>();
  final releaseSelect = Completer<void>();

  @override
  Future<void> seek(Duration value) async {
    seeks.add(value);
    if (!seekStarted.isCompleted) seekStarted.complete();
    await releaseSeek.future;
  }

  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async {
    selectedTracks.add((type, id));
    if (!selectStarted.isCompleted) selectStarted.complete();
    await releaseSelect.future;
  }
}

class _FailingControlPlayer extends _Player {
  _FailingControlPlayer({String failureCode = 'command_queue_full'})
    : _failure = PlayerUnavailable(
        'opaque native control detail',
        failureCode: failureCode,
      );

  final PlayerUnavailable _failure;

  @override
  Future<void> play() async => throw _failure;

  @override
  Future<void> pause() async => throw _failure;

  @override
  Future<void> seek(Duration value) async => throw _failure;

  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async =>
      throw _failure;

  @override
  Future<void> setFullscreen(bool fullscreen) async => throw _failure;
}

class _BlockingFailingControlPlayer extends _Player {
  final seekStarted = Completer<void>();
  final releaseSeek = Completer<void>();

  @override
  Future<void> seek(Duration value) async {
    seekStarted.complete();
    await releaseSeek.future;
    throw const PlayerUnavailable(
      'opaque stale detail',
      failureCode: 'command_error',
    );
  }
}

class _BlockingFailingTrackPlayer extends _Player {
  final selectStarted = Completer<void>();
  final releaseSelect = Completer<void>();

  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async {
    selectedTracks.add((type, id));
    selectStarted.complete();
    await releaseSelect.future;
    throw const PlayerUnavailable(
      'opaque stale detail',
      failureCode: 'command_error',
    );
  }
}

class _BlockingSecondSeekPlayer extends _EventPlayer {
  final secondSeekStarted = Completer<void>();
  final releaseSecondSeek = Completer<void>();

  @override
  Future<void> seek(Duration value) async {
    seeks.add(value);
    if (seeks.length != 2) return;
    secondSeekStarted.complete();
    await releaseSecondSeek.future;
  }
}

class _MemoryStore implements AppStore {
  @override
  Future<String> clientIdentifier() async => 'test';
  @override
  Future<AppStoreLoadResult> load() async =>
      const AppStoreLoadResult(PersistedState());
  @override
  Future<void> save(PersistedState state) async {}
}

class _Credentials implements CredentialStore {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> readAccountToken() async => null;
  @override
  Future<String?> readProfileToken(String profileId) async => null;
  @override
  Future<void> writeAccountToken(String token) async {}
  @override
  Future<void> writeProfileToken(String profileId, String token) async {}
}

String _supportReport(LineupController lineup, PlayerCoordinator coordinator) =>
    lineup.diagnostics.buildSupportReport(
      lineup.diagnostics.snapshot(
        reportTime: DateTime.utc(2026, 10, 12),
        timeZone: 'UTC',
        appVersion: '1',
        appBuild: '1',
        platform: 'windows',
        plexServerSelected: false,
        plexConnectionVerified: false,
        playback: coordinator.diagnosticPlaybackSnapshot,
      ),
    );

Future<void> _nativeEvent(Map<String, Object?> event) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'lineup/native_player',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('event', event),
          ),
          null,
        );

class _DisplayPlayer extends _EventPlayer {
  _DisplayPlayer({
    this.audioOnly = false,
    this.failReplacementBeforeReady = false,
    this.deferTracks = false,
  }) : super(sync: true);
  final bool audioOnly;
  final bool deferTracks;
  final bool failReplacementBeforeReady;
  final pausedStarts = <bool>[];
  final requests = <DisplayMatchingRequest>[];
  final _reports = StreamController<DisplayMatchingReport>.broadcast(
    sync: true,
  );
  DisplayMatchingReport _report = const DisplayMatchingReport.initial();
  int pauses = 0;
  @override
  DisplayMatchingReport get displayReport => _report;
  @override
  Stream<DisplayMatchingReport> get displayReports => _reports.stream;
  @override
  Future<void> setDisplayMatching(DisplayMatchingRequest request) async {
    requests.add(request);
  }

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  }) async {
    await super.load(
      media,
      plexToken: plexToken,
      generation: generation,
      startPaused: startPaused,
    );
    pausedStarts.add(startPaused);
    if (failReplacementBeforeReady && loads.length == 2) {
      emitError(generation: generation, failureCode: 'mpv_error');
      throw const PlayerUnavailable('Synthetic replacement error');
    }
    position = Duration.zero;
    telemetry = const PlayerTelemetry();
    tracks = (audioOnly || deferTracks)
        ? const []
        : const [
            PlayerTrack(id: 1, type: PlayerTrackType.video, selected: true),
          ];
    emitStatus(PlayerState.loading, generation: generation);
    emitStatus(
      startPaused ? PlayerState.paused : PlayerState.playing,
      generation: generation,
      tracksUpdated: !deferTracks,
    );
  }

  void decode() {
    telemetry = const PlayerTelemetry(
      gamma: 'pq',
      targetGamma: 'pq',
      targetPrimaries: 'bt.2020',
      targetPixelFormat: 'rgb10a2',
    );
    emitStatus(
      pausedStarts.last ? PlayerState.paused : PlayerState.playing,
      generation: loadGenerations.last,
    );
  }

  void report(DisplayMatchingOutcome outcome, {bool wrote = false}) {
    _report = DisplayMatchingReport(
      revision: requests.last.revision,
      session: DisplayMatchingSessionState.active,
      observed: outcome == DisplayMatchingOutcome.matched
          ? DisplayMatchingState.hdr
          : DisplayMatchingState.sdr,
      outcome: outcome,
      wrote: wrote,
      owned: wrote,
      reason: null,
      route: DisplayMatchingRoute.advancedColor,
      activeColorMode: null,
    );
    _reports.add(_report);
  }

  void admissionUnavailable({int? revision}) {
    _report = DisplayMatchingReport.unavailable(
      revision: revision ?? requests.last.revision,
      reason: DisplayMatchingReason.guardianUnavailable,
    );
    _reports.add(_report);
  }

  @override
  Future<void> pause() async {
    pauses++;
    emitStatus(PlayerState.paused, generation: loadGenerations.last);
  }

  @override
  Future<void> play() async {
    await super.play();
    emitStatus(PlayerState.playing, generation: loadGenerations.last);
  }

  @override
  Future<void> close() async {
    await _reports.close();
    await super.close();
  }
}
