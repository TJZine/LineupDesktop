import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/native_player.dart';

import 'ui_fixture.dart';

void main() {
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
