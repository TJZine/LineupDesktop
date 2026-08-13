import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/player_view.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets('zero-length mini Guide programs render zero progress', (
    tester,
  ) async {
    final lineup = _Lineup();
    final guide = _ZeroDurationGuide(lineup);
    final player = FixturePlayer()
      ..emit(
        const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
      );
    final coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      await player.dispose();
      guide.dispose();
      lineup.dispose();
    });
    coordinator.showMiniGuide();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: coordinator, openGuide: () {}),
      ),
    );
    await tester.pump();

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.0);
    expect(tester.takeException(), isNull);

    coordinator.closeOverlay();
    await tester.pump();
  });
}

class _Lineup extends FixtureController {
  _Lineup() {
    channels = [
      Channel(
        id: 'channel',
        number: 7,
        name: 'Channel',
        source: const ManualSource([
          ChannelItem(
            id: 'program',
            title: 'Program',
            duration: Duration(hours: 1),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.utc(2026, 1, 1, 12),
        shuffleSeed: 7,
      ),
    ];
    currentChannelId = 'channel';
    stage = SetupStage.ready;
  }
}

class _ZeroDurationGuide extends GuideController {
  _ZeroDurationGuide(LineupController lineup)
    : super(
        lineup: lineup,
        loadSchedule: (_) => Future.error(StateError('Schedule load not used')),
      );

  static final _time = DateTime.utc(2026, 1, 1, 12);
  static final _program = GuideProgram(
    channelId: 'channel',
    scheduled: ScheduledProgram(
      item: const ChannelItem(
        id: 'zero-duration',
        title: 'Zero duration',
        duration: Duration.zero,
      ),
      start: _time,
      end: _time,
      elapsed: Duration.zero,
      index: 0,
      loop: 0,
    ),
  );

  @override
  DateTime get now => _time;

  @override
  GuideProgram? currentProgram(String channelId, [DateTime? at]) => _program;

  @override
  GuideProgram? nextProgram(String channelId, [DateTime? at]) => null;

  @override
  void requestChannels(Iterable<Channel> channels) {}
}
