import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';

void main() {
  test('manual programming compares ordered occurrence IDs', () {
    ChannelItem item(String id) =>
        ChannelItem(id: id, title: id, duration: const Duration(minutes: 1));
    final a = item('a');
    final b = item('b');
    const refreshed = ChannelItem(
      id: 'a',
      title: 'Refreshed',
      duration: Duration(minutes: 2),
    );
    final original = ManualSource([a, b, a]);
    expect(
      scheduleProgrammingSourceEquals(
        original,
        ManualSource([refreshed, b, a]),
      ),
      isTrue,
    );
    for (final edited in [
      [b, a, a],
      [a, b, a, a],
      [a, b],
      [a, b, b],
    ]) {
      expect(
        scheduleProgrammingSourceEquals(original, ManualSource(edited)),
        isFalse,
      );
    }
  });

  test('mixed programming compares interleave and children recursively', () {
    MixedSource mixed(String title, {bool interleave = false}) => MixedSource(
      interleave: interleave,
      sources: [
        MixedSource(
          sources: [
            ManualSource([
              ChannelItem(
                id: 'a',
                title: title,
                duration: const Duration(minutes: 1),
              ),
            ]),
          ],
        ),
        const PlaylistSource('playlist'),
      ],
    );
    final original = mixed('Stored');
    expect(
      scheduleProgrammingSourceEquals(original, mixed('Refreshed')),
      isTrue,
    );
    expect(
      scheduleProgrammingSourceEquals(
        original,
        mixed('Stored', interleave: true),
      ),
      isFalse,
    );
    expect(
      scheduleProgrammingSourceEquals(
        original,
        MixedSource(sources: [original.sources.first]),
      ),
      isFalse,
    );
  });
}
