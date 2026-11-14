import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/ui/channel_identity.dart';

void main() {
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
