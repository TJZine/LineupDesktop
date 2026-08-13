import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';

import '../support/ui_fixture.dart';

void main() {
  test(
    'replacement failure stops superseded media before releasing its lease',
    () async {
      final lineup = _Lineup(failSecondPlaybackRequest: true);
      final guide = _guide(lineup);
      final player = _BlockingPlayer();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );
      addTearDown(() async {
        coordinator.dispose();
        await player.dispose();
        guide.dispose();
        lineup.dispose();
      });

      final first = coordinator.tune('channel-a');
      await player.firstLoadStarted.future;
      final replacement = coordinator.tune('channel-b');
      player.releaseFirstLoad.complete();
      await Future.wait([first, replacement]);
      player.emitStopped();
      await Future<void>.delayed(Duration.zero);

      expect(player.loads, 1);
      expect(player.stops, 1);
      expect(lineup.releases, 1);
      expect(lineup.currentChannelId, 'channel-a');
      expect(coordinator.status.state, PlayerState.stopped);
      expect(coordinator.hasPlaybackIntent, isFalse);
      expect(coordinator.overlay, PlayerOverlay.error);
    },
  );

  test('generated stopped event settles coordinator playback state', () async {
    final lineup = _Lineup();
    final guide = _guide(lineup);
    final player = _EventPlayer();
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(() async {
      coordinator.dispose();
      await player.dispose();
      guide.dispose();
      lineup.dispose();
    });

    await coordinator.tune('channel-b');
    expect(coordinator.hasPlaybackIntent, isTrue);

    await coordinator.stop();
    player.emitStopped();
    await Future<void>.delayed(Duration.zero);

    expect(player.stops, 1);
    expect(coordinator.status.state, PlayerState.stopped);
    expect(coordinator.hasPlaybackIntent, isFalse);
    expect(lineup.releases, 1);
  });
}

GuideController _guide(_Lineup lineup) => GuideController(
  lineup: lineup,
  loadSchedule: (channel) async => buildSchedule(
    (channel.source as ManualSource).items,
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
  ),
)..requestViewport(0, 2);

class _Lineup extends FixtureController {
  _Lineup({this.failSecondPlaybackRequest = false}) {
    channels = [_channel('channel-a', 1), _channel('channel-b', 2)];
    currentChannelId = 'channel-a';
    stage = SetupStage.ready;
  }

  final bool failSecondPlaybackRequest;
  int playbackRequests = 0;
  int releases = 0;

  @override
  LineupPlaybackRequest playbackFor(String itemId) {
    playbackRequests++;
    if (failSecondPlaybackRequest && playbackRequests == 2) {
      throw StateError('Replacement playback request is unavailable.');
    }
    return LineupPlaybackRequest(Uri.parse('lineup-test://$itemId'), () async {
      releases++;
    });
  }

  @override
  Future<void> setCurrentChannel(String? id) async {
    currentChannelId = id;
    notifyListeners();
  }
}

Channel _channel(String id, int number) => Channel(
  id: id,
  number: number,
  name: 'Channel $number',
  source: ManualSource([
    ChannelItem(
      id: 'program-$id',
      title: 'Program $number',
      duration: const Duration(hours: 24),
    ),
  ]),
  playbackMode: PlaybackMode.sequential,
  anchor: DateTime.now().subtract(const Duration(hours: 1)),
  shuffleSeed: number,
);

class _EventPlayer extends FixturePlayer {
  int loads = 0;
  int stops = 0;

  @override
  Future<void> load(Uri media, {int? generation}) async {
    loads++;
    await super.load(media, generation: generation);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  void emitStopped() {
    emit(
      const PlayerStatus(state: PlayerState.stopped, message: 'Stopped'),
      eventGeneration: generation,
    );
  }
}

class _BlockingPlayer extends _EventPlayer {
  final firstLoadStarted = Completer<void>();
  final releaseFirstLoad = Completer<void>();

  @override
  Future<void> load(Uri media, {int? generation}) async {
    await super.load(media, generation: generation);
    if (loads == 1) {
      firstLoadStarted.complete();
      await releaseFirstLoad.future;
    }
  }
}
