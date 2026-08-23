import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
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

      await coordinator.tune('channel-b');

      expect(
        player.loads.single,
        Uri.parse('https://media.test/program?quality=original'),
      );
      expect(player.loadPlexTokens.single, 'test-token');
      expect(player.seeks.single, greaterThanOrEqualTo(Duration.zero));
      expect(lineup.currentChannelId, 'channel-b');
      expect(coordinator.overlay, PlayerOverlay.osd);
      expect(lineup.releases, 0);
      await coordinator.stop();
      await coordinator.stop();
      expect(lineup.releases, 1);
    },
  );

  test('scope change stops playback and releases its lease once', () async {
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
    coordinator.cycleSleepTimer();
    lineup.changeContentScope();
    await Future<void>.delayed(Duration.zero);

    expect(nativePlayer.stops, 1);
    expect(lineup.releases, 1);
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

    expect(lineup.releases, 1);
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

    coordinator.cycleSleepTimer();
    await tester.pump(const Duration(minutes: 30));
    await player.stopStarted.future;

    coordinator.cycleSleepTimer();
    expect(coordinator.sleepDuration, const Duration(minutes: 60));
    player.releaseStop.complete();
    await tester.pump();

    expect(coordinator.sleepDuration, const Duration(minutes: 60));
    await tester.pump(const Duration(minutes: 60));
    await tester.pump();

    expect(player.stops, 2);
    expect(coordinator.sleepDuration, isNull);
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

    coordinator.cycleSleepTimer();
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

    coordinator.cycleSleepTimer();
    await tester.pump(const Duration(minutes: 30));
    await tester.pump();

    expect(coordinator.sleepDuration, isNull);
    expect(coordinator.overlay, PlayerOverlay.error);
    expect(
      coordinator.error,
      'Playback could not be stopped when the sleep timer expired.',
    );
    expect(
      lineup.diagnostics.entries.single.message,
      'Playback request failed',
    );
  });

  test(
    'removing the active channel stops playback and releases its lease',
    () async {
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
      expect(lineup.releases, 1);
    },
  );

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
      expect(lineup.releases, 0);
      expect(await coordinator.logout(), isTrue);
      expect(nativePlayer.stops, 1);
      expect(lineup.releases, 1);
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

  testWidgets('OSD timeout reads the persisted setting consumer', (
    tester,
  ) async {
    final lineup = _TestLineup();
    lineup.settings = lineup.settings.copyWith(osdAutoHideSeconds: 2);
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

      player.emitStatus(PlayerState.paused, generation: generation + 1);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.status.state, PlayerState.playing);

      player.emitStatus(PlayerState.buffering, generation: generation);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.status.state, PlayerState.buffering);
      expect(coordinator.overlay, PlayerOverlay.osd);
    },
  );

  test('superseded tune cannot seek or release the winning request', () async {
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
    await Future.wait([first, second]);

    expect(lineup.currentChannelId, 'channel-b');
    expect(player.loads, hasLength(2));
    expect(player.seeks, hasLength(1));
    expect(lineup.releases, 1);
    await coordinator.stop();
    expect(lineup.releases, 2);
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
        greaterThan(player.loadGenerations.first! + 1),
      );
    },
  );

  test('stop cancels a pending tune and releases its request', () async {
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
    expect(lineup.releases, 1);
  });

  test(
    'replacement failure stops superseded media before releasing its lease',
    () async {
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
      expect(lineup.releases, 1);
      expect(lineup.currentChannelId, 'channel-0');
      expect(coordinator.status.state, PlayerState.stopped);
      expect(coordinator.hasPlaybackIntent, isFalse);
      expect(coordinator.overlay, PlayerOverlay.error);
    },
  );

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
    expect(lineup.releases, 1);
  });

  test(
    'terminal player errors and failed stops still release leases',
    () async {
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
      player.emitError();
      await Future<void>.delayed(Duration.zero);
      expect(lineup.releases, 1);

      await coordinator.tune('channel-0');
      player.failStop = true;
      await expectLater(coordinator.stop(), throwsStateError);
      expect(lineup.releases, 2);
    },
  );

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
      audioCodec: 'truehd',
      failureCode: 'http_error',
      httpStatus: 401,
    );
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.canRetry, isTrue);
    expect(coordinator.overlay, PlayerOverlay.error);
    expect(coordinator.status.failureCode, 'http_error');
    expect(coordinator.status.httpStatus, 401);
    expect(lineup.diagnostics.entries.single.message, 'Native playback failed');
    expect(lineup.diagnostics.entries.single.context['reason'], 'Failed');
    expect(lineup.diagnostics.entries.single.context['audioCodec'], 'truehd');
  });

  test(
    'synchronous native authorization failure loads one replacement',
    () async {
      final lineup = _TestLineup(recoverAuthorization: true);
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
      expect(lineup.releases, 1);
      expect(coordinator.error, isNull);

      await coordinator.stop();
      expect(lineup.releases, 2);
    },
  );

  test(
    'a second native authorization failure is terminal without a loop',
    () async {
      final lineup = _TestLineup(recoverAuthorization: true);
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
      expect(lineup.releasedTokens, ['test-token-1', 'test-token-2']);
      expect(coordinator.overlay, PlayerOverlay.error);
      expect(coordinator.status.failureCode, 'http_error');
      expect(coordinator.status.httpStatus, 401);
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
      expect(lineup.releasedTokens, ['test-token-1']);
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
      expect(lineup.releasedTokens, ['test-token-1', 'test-token-2']);
      expect(lineup.currentChannelId, 'channel-0');
      expect(coordinator.error, isNull);

      await coordinator.stop();
      expect(lineup.releasedTokens, [
        'test-token-1',
        'test-token-2',
        'test-token-1',
      ]);
    },
  );

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

    await coordinator.tune('channel-b');

    expect(player.loads, hasLength(1));
    expect(player.stops, 1);
    expect(lineup.releases, 1);
    expect(lineup.currentChannelId, 'channel-0');
    expect(coordinator.overlay, PlayerOverlay.error);
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
    player.emitError();
    await Future<void>.delayed(Duration.zero);
    player.releaseSeek.complete();
    await tune;

    expect(lineup.currentChannelId, 'channel-0');
    expect(lineup.releases, 1);
    expect(coordinator.overlay, PlayerOverlay.error);
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
      player.emitError();
      await Future<void>.delayed(Duration.zero);
      lineup.releasePersistence.complete();
      await tune;

      expect(lineup.currentChannelId, 'channel-0');
      expect(lineup.releases, 1);
      expect(coordinator.overlay, PlayerOverlay.error);
    },
  );

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

ScheduleIndex _schedule(Channel channel) => buildSchedule(
  (channel.source as ManualSource).items,
  mode: channel.playbackMode,
  seed: channel.shuffleSeed,
);

class _TestLineup extends LineupController {
  _TestLineup({
    int count = 2,
    this.failSecondPlaybackRequest = false,
    this.recoverAuthorization = false,
    this.blockAuthorizationRecovery = false,
  }) : super(
         store: _MemoryStore(),
         credentials: _Credentials(),
         plex: PlexClient(
           clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
         ),
       ) {
    channels = List.generate(count, (index) {
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
    currentChannelId = channels.first.id;
    stage = SetupStage.ready;
  }

  int releases = 0;
  final bool failSecondPlaybackRequest;
  final bool recoverAuthorization;
  final bool blockAuthorizationRecovery;
  int playbackRequests = 0;
  int recoveryCalls = 0;
  final releasedTokens = <String>[];
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
    channels = List.unmodifiable(value);
    notifyListeners();
  }

  void setSettings(LineupSettings value) {
    settings = value;
    notifyListeners();
  }

  @override
  LineupPlaybackRequest playbackFor(String itemId) {
    playbackRequests++;
    if (failSecondPlaybackRequest && playbackRequests == 2) {
      throw StateError('Replacement playback request is unavailable.');
    }
    return _request(
      recoverAuthorization ? 'test-token-1' : 'test-token',
      recoverable: recoverAuthorization,
    );
  }

  LineupPlaybackRequest _request(String token, {bool recoverable = false}) {
    return LineupPlaybackRequest(
      Uri.parse(
        'https://media.test/program?x-PLEX-token=must-not-leak&quality=original',
      ),
      () async {
        releases++;
        releasedTokens.add(token);
      },
      plexToken: token,
      authorizationRecovery: recoverable
          ? () async {
              recoveryCalls++;
              if (blockAuthorizationRecovery) {
                recoveryStarted.complete();
                await finishRecovery.future;
              }
              return _request('test-token-2');
            }
          : null,
    );
  }

  @override
  Future<void> setCurrentChannel(String? id) async {
    currentChannelId = id;
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

class _BlockingLineup extends _TestLineup {
  final persistenceStarted = Completer<void>();
  final releasePersistence = Completer<void>();
  bool _blocked = false;

  @override
  Future<void> setCurrentChannel(String? id) async {
    currentChannelId = id;
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
  final selectedTracks = <(PlayerTrackType, int?)>[];
  int stops = 0;

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
  Future<void> initialize() async {}
  @override
  Future<void> load(Uri media, {String? plexToken, int? generation}) async {
    loads.add(media);
    loadPlexTokens.add(plexToken);
    loadGenerations.add(generation);
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration value) async => seeks.add(value);
  @override
  Future<void> setVideoRect(PlayerVideoRect rect) async {}
  @override
  Future<void> setFullscreen(bool fullscreen) async {}
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

mixin _BlocksFirstLoad on _Player {
  final firstLoadStarted = Completer<void>();
  final releaseFirstLoad = Completer<void>();

  @override
  Future<void> load(Uri media, {String? plexToken, int? generation}) async {
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

class _LoadFailurePlayer extends _Player {
  @override
  Future<void> load(Uri media, {String? plexToken, int? generation}) async {
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
    String? audioCodec,
    String? failureCode,
    int? httpStatus,
  }) {
    _events.add(
      PlayerEvent(
        status: PlayerStatus(
          state: PlayerState.error,
          message: 'Failed',
          recoverable: recoverable,
          failureCode: failureCode,
          httpStatus: httpStatus,
        ),
        position: Duration.zero,
        duration: Duration.zero,
        telemetry: const PlayerTelemetry(),
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

  void emitStatus(PlayerState state, {int? generation}) {
    _events.add(
      PlayerEvent(
        status: PlayerStatus(state: state, message: state.name),
        position: position,
        duration: duration,
        telemetry: telemetry,
        tracks: tracks,
        generation: generation,
      ),
    );
  }

  @override
  Future<void> stop() async {
    await super.stop();
    if (failStop) throw StateError('stop failed');
  }

  Future<void> close() => _events.close();
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
  Future<void> load(Uri media, {String? plexToken, int? generation}) async {
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

class _MemoryStore implements AppStore {
  @override
  Future<String> clientIdentifier() async => 'test';
  @override
  Future<PersistedState> load() async => const PersistedState();
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
