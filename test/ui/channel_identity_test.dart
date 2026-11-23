import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/ui/channel_identity.dart';

void main() {
  testWidgets('number and kind icon use the same gap as icon and name', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ChannelIdentity(
          channel: channel('tv', 3, 'Drama', ChannelKind.tv, 'TV'),
          nameStyle: const TextStyle(fontSize: 20),
        ),
      ),
    );
    final number = tester.getRect(find.text('3'));
    final icon = tester.getRect(find.byIcon(Icons.tv_outlined));
    final name = tester.getRect(find.text('Drama'));
    expect(find.text('•'), findsNothing);
    expect(icon.left - number.right, closeTo(name.left - icon.right, .01));
  });

  testWidgets('one accessible label carries the full channel identity', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    final tv = channel('tv', 3, 'Drama', ChannelKind.tv, 'TV Shows');
    final film = channel('films', 7, 'Drama', ChannelKind.film, 'Films');
    final tag = ChannelIdentity.libraryTagFor(tv, [tv, film]);
    expect(tag, 'TV Shows');
    expect(ChannelIdentity.libraryTagFor(film, [tv, film]), 'Films');
    expect(ChannelIdentity.libraryTagFor(tv, [tv]), isNull);
    await tester.pumpWidget(
      host(ChannelIdentity(channel: tv, libraryTag: tag)),
    );

    expect(
      find.bySemanticsLabel('Channel 3, Drama, TV, TV Shows library'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Drama'), findsNothing);
    expect(find.text('· TV Shows'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('long name truncates while the number, icon and tag fit', (
    tester,
  ) async {
    const name =
        'A very long channel name for this narrow television rail with too much text';
    final row = channel('tv', 1000, name, ChannelKind.tv, 'TV');
    await tester.pumpWidget(
      host(
        ChannelIdentity(
          channel: row,
          libraryTag: 'TV',
          nameStyle: const TextStyle(fontSize: 18),
        ),
        width: 280,
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
    expect(paragraph.didExceedMaxLines, isTrue);
    expect(
      tester.renderObject<RenderParagraph>(find.text('1000')).didExceedMaxLines,
      isFalse,
    );
    expect(
      tester.renderObject<RenderParagraph>(find.text('· TV')).didExceedMaxLines,
      isFalse,
    );
    expect(find.byIcon(Icons.tv_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('name wraps at spaces until a word exceeds the name column', (
    tester,
  ) async {
    const name = 'Documentaries Across the World';
    final row = channel('tv', 1000, name, ChannelKind.tv, 'TV');
    Future<void> pump(double width) => tester.pumpWidget(
      host(
        ChannelIdentity(
          channel: row,
          numberWidth: 52,
          nameStyle: const TextStyle(fontSize: 18),
          maxLines: 2,
        ),
        width: width,
      ),
    );

    await pump(415);
    expect(tester.widget<Text>(find.text(name)).maxLines, 2);
    expect(
      tester.renderObject<RenderParagraph>(find.text(name)).didExceedMaxLines,
      isFalse,
    );
    await pump(250);
    expect(tester.widget<Text>(find.text(name)).maxLines, 1);
    expect(
      tester.renderObject<RenderParagraph>(find.text(name)).didExceedMaxLines,
      isTrue,
    );
  });

  testWidgets(
    'unlimited names wrap and supporting text starts under the name',
    (tester) async {
      const name = 'Documentaries Across the World';
      await tester.pumpWidget(
        host(
          ChannelIdentity(
            channel: channel('tv', 2, name, ChannelKind.tv, 'TV'),
            nameStyle: const TextStyle(fontSize: 18),
            maxLines: null,
            secondary: const Text('Watching'),
          ),
          width: 350,
        ),
      );

      final title = find.text(name);
      final secondary = find.text('Watching');
      final paragraph = tester.renderObject<RenderParagraph>(title);
      expect(paragraph.size.height, greaterThan(36));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        tester.getTopLeft(secondary).dx,
        closeTo(tester.getTopLeft(title).dx, .01),
      );
    },
  );

  testWidgets('library tag moves below the name when it cannot fit beside it', (
    tester,
  ) async {
    final row = channel('tv', 2, 'Drama', ChannelKind.tv, 'A Film Library');
    await tester.pumpWidget(
      host(
        ChannelIdentity(
          channel: row,
          libraryTag: row.libraryTitle,
          allowTagBelow: true,
          nameStyle: const TextStyle(fontSize: 18),
        ),
        width: 250,
      ),
    );

    final name = tester.getTopLeft(find.text('Drama'));
    final tag = tester.getTopLeft(find.text('A Film Library'));
    expect(tag.dx, closeTo(name.dx, .01));
    expect(tag.dy, greaterThan(name.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the supporting line gives a fitting library tag more than half',
    (tester) async {
      final row = channel('tv', 2, 'Drama', ChannelKind.tv, 'Film Library');
      await tester.pumpWidget(
        host(
          ChannelIdentity(
            channel: row,
            libraryTag: row.libraryTitle,
            allowTagBelow: true,
            nameStyle: const TextStyle(fontSize: 18),
            supportStyle: const TextStyle(fontSize: 10),
            secondary: const Text(
              'Watching',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          width: 239,
        ),
      );

      final tag = tester.renderObject<RenderParagraph>(
        find.text('· Film Library'),
      );
      expect(tag.didExceedMaxLines, isFalse);
      expect(
        tester.getTopLeft(find.text('Watching')).dx,
        closeTo(tester.getTopLeft(find.text('Drama')).dx, .01),
      );
      expect(
        tester.getTopLeft(find.text('· Film Library')).dy,
        greaterThan(tester.getTopLeft(find.text('Drama')).dy),
      );
    },
  );
}

Widget host(Widget child, {double width = 400}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

Channel channel(
  String id,
  int number,
  String name,
  ChannelKind kind,
  String library,
) => Channel(
  id: id,
  number: number,
  name: name,
  source: const ManualSource([]),
  kind: kind,
  sourceLibraries: {id: library},
  playbackMode: PlaybackMode.shuffle,
  anchor: DateTime.utc(2026),
  shuffleSeed: 1,
);
