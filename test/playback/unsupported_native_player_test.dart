import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/unsupported_native_player.dart';

void main() {
  test('macOS backend never masquerades as successful playback', () async {
    final player = UnsupportedNativePlayer.macos();

    await player.initialize();
    expect(player.status.state, PlayerState.unsupported);
    expect(player.status.message, contains('not implemented'));
    await expectLater(player.play(), throwsA(isA<PlayerUnavailable>()));
    await expectLater(
      player.load(Uri.parse('https://example.invalid/media')),
      throwsA(isA<PlayerUnavailable>()),
    );
    await player.dispose();
  });
}
