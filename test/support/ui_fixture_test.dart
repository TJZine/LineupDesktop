import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/native_player.dart';

import 'ui_fixture.dart';

void main() {
  test('fixture player events support multiple listeners', () async {
    final player = FixturePlayer();
    addTearDown(player.dispose);
    final first = player.events.first;
    final second = player.events.first;

    player.emit(
      const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
    );

    final events = await Future.wait([first, second]);
    expect(
      events.map((event) => event.status.state),
      everyElement(PlayerState.playing),
    );
  });

  test('fixture player ignores events after disposal', () async {
    final player = FixturePlayer();
    final status = player.status;
    final done = player.events.drain<void>();

    await player.dispose();
    player.emit(
      const PlayerStatus(state: PlayerState.playing, message: 'Late event'),
    );

    expect(player.status, same(status));
    await done;
  });
}
