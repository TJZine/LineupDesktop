import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/native_player.dart';

import '../test_driver/ui_harness.dart';

void main() {
  test(
    'synthetic player does not resume load emissions after disposal',
    () async {
      final player = HarnessPlayer();
      addTearDown(player.dispose);
      var events = 0;
      player.events.listen((_) => events++);

      final load = player.load(
        Uri.parse('lineup-test://disposed'),
        generation: 7,
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, 1);

      await player.dispose();
      await load;
      expect(events, 1);
    },
  );

  test('synthetic player ignores superseded load completion', () async {
    final player = HarnessPlayer();
    addTearDown(player.dispose);
    final events = <PlayerEvent>[];
    final subscription = player.events.listen(events.add);
    addTearDown(subscription.cancel);

    final first = player.load(Uri.parse('lineup-test://first'), generation: 1);
    final second = player.load(
      Uri.parse('lineup-test://second'),
      generation: 2,
    );
    await Future.wait([first, second]);
    await Future<void>.delayed(Duration.zero);

    expect(
      events
          .where((event) => event.status.state == PlayerState.playing)
          .map((event) => event.generation),
      [2],
    );
  });
}
