import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/manual_rundown.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

ChannelItem snapshot(String id, [String? title]) => ChannelItem(
  id: id,
  title: title ?? id,
  duration: const Duration(minutes: 30),
);
PlexMediaItem media(String id, [String? title]) => PlexMediaItem(
  id: id,
  title: title ?? id,
  type: 'movie',
  libraryId: 'movies',
  duration: const Duration(minutes: 30),
  parts: [PlexMediaPart(path: '/$id')],
);

void main() {
  test(
    'repeated IDs keep distinct identity and snapshots across saves and moves',
    () {
      final rundown = ManualRundown()
        ..replaceFrom([snapshot('one', 'First'), snapshot('one', 'Second')]);
      final first = rundown.occurrences.first;
      final second = rundown.occurrences.last;
      expect(first, isNot(same(second)));
      expect([first.occurrence, second.occurrence], [1, 2]);
      rundown.move(second, -1);
      expect(rundown.snapshotItems.map((item) => item.title), [
        'Second',
        'First',
      ]);
      rundown.acceptSaved([
        snapshot('one', 'Saved second'),
        snapshot('one', 'Saved first'),
      ]);
      expect(rundown.occurrences.first, same(second));
      expect(rundown.resolvedItems({}).first.title, 'Saved second');
      expect(
        rundown
            .resolvedItems({'one': media('one', 'Live')})
            .map((item) => item.title),
        ['Live', 'Live'],
      );
      rundown.acceptSaved([]);
      expect(rundown.snapshotItems.first.title, 'Saved second');
    },
  );

  test('single add requires fresh inventory; batch deduplicates with captured fallback', () {
    final rundown = ManualRundown()..replaceFrom([snapshot('one')]);
    rundown.addCurrent('missing', {});
    expect(rundown.occurrences, hasLength(1));
    rundown.addBatch(
      ['one', 'two', 'three', 'two'],
      {'two': media('two', 'Fresh')},
      {'two': media('two', 'Captured'), 'three': media('three')},
    );
    expect(rundown.snapshotItems.map((item) => item.title), [
      'one',
      'Fresh',
      'three',
    ]);
    rundown.remove(rundown.occurrences[1]);
    expect(rundown.canUndo, isTrue);
    rundown.undoLastAddition();
    expect(rundown.snapshotItems.map((item) => item.id), ['one']);
  });

  test(
    'replacement and last removal clear undo; move, reorder and save retain it',
    () {
      final rundown = ManualRundown()..replaceFrom([snapshot('one')]);
      rundown.addCurrent('two', {'two': media('two')});
      final addition = rundown.occurrences.last;
      rundown.moveTo(addition, 0, after: false);
      rundown.reorder(0, 1);
      rundown.acceptSaved([snapshot('one'), snapshot('two', 'Saved')]);
      expect(rundown.canUndo, isTrue);
      rundown.undoLastAddition();
      expect(rundown.snapshotItems.map((item) => item.id), ['one']);
      rundown.addCurrent('two', {'two': media('two')});
      rundown.remove(rundown.occurrences.last);
      expect(rundown.canUndo, isFalse);
      rundown.addCurrent('two', {'two': media('two')});
      rundown.replaceFrom([snapshot('two')]);
      expect(rundown.canUndo, isFalse);
      expect(rundown.occurrences.single.occurrence, 1);
    },
  );
}
