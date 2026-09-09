import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets('shell keeps the deliberate destination inventory and focus', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(
      tester
          .widget<ExcludeSemantics>(
            find.byKey(const Key('immersive-route-semantics')),
          )
          .excluding,
      isFalse,
    );
    await tester.tap(find.byKey(const Key('guide-app-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
    expect(
      tester
          .widget<ExcludeSemantics>(
            find.byKey(const Key('immersive-route-semantics')),
          )
          .excluding,
      isTrue,
    );
    await tester.tap(find.text('Guide').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('immersive-app-menu')), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide Lineup menu');

    await tester.tap(find.byKey(const Key('guide-app-menu')));
    await tester.pumpAndSettle();
    for (var index = 0; index < 12; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<Card>()
            ?.key,
        const Key('immersive-app-menu'),
      );
    }
    for (final label in [
      'Guide',
      'Player',
      'Channels',
      'Settings',
      'Account',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('Channels').last);
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Channels');
    expect(find.byType(NavigationRail), findsNothing);

    await openDestination(tester, 'Settings');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Settings');
    await tester.tap(find.widgetWithText(TextButton, 'Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Diagnostics'));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Diagnostics');
  });

  testWidgets('channel deletion requires explicit destructive confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = UiFixture()
      ..controller.stage = SetupStage.ready
      ..controller.channels = [_channel()];
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await tester.pump();
    await openDestination(tester, 'Channels');

    await tester.tap(find.byTooltip('Actions for Newsroom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Newsroom?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fixture.controller.channels, hasLength(1));
    expect(find.byTooltip('Actions for Newsroom'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Open Newsroom');

    await tester.tap(find.byTooltip('Actions for Newsroom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete channel'));
    await tester.pumpAndSettle();
    expect(fixture.controller.channels, isEmpty);
  });

  testWidgets('channel deletion cancellation tolerates a removed opener', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = UiFixture()
      ..controller.stage = SetupStage.ready
      ..controller.channels = [_channel()];
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await tester.pump();
    await openDestination(tester, 'Channels');

    await tester.tap(find.byTooltip('Actions for Newsroom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    fixture.controller
      ..channels = const []
      ..notifyListeners();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

Channel _channel() => Channel(
  id: 'newsroom',
  number: 7,
  name: 'Newsroom',
  source: const LibrarySource(
    libraryId: 'movies',
    libraryType: PlexLibraryType.movie,
  ),
  playbackMode: PlaybackMode.shuffle,
  anchor: DateTime.utc(2026),
  shuffleSeed: 7,
);
