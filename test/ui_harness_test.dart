import 'package:flutter_test/flutter_test.dart';

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
}
