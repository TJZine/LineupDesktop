import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_setup_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets('shell keeps the deliberate destination inventory and focus', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    final labels = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(labels, ['Guide', 'Channels', 'Settings', 'Diagnostics', 'Player']);

    for (final target in [
      (Icons.view_list_outlined, 'Channels'),
      (Icons.settings_outlined, 'Settings'),
      (Icons.monitor_heart_outlined, 'Diagnostics'),
    ]) {
      await tester.tap(find.byIcon(target.$1));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, target.$2);
    }
  });

  testWidgets('management pages and settings reflow at desktop regimes', (
    tester,
  ) async {
    for (final size in const [
      Size(800, 600),
      Size(1280, 720),
      Size(1600, 900),
      Size(1920, 1080),
    ]) {
      await tester.binding.setSurfaceSize(size);
      final fixture = UiFixture()..controller.stage = SetupStage.ready;
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.view_list_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Open Channel builder'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Channels at $size');

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Subtitles and access'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Settings at $size');
      if (size == const Size(800, 600)) {
        for (final category in [
          'Playback',
          'Subtitles and access',
          'Account',
          'Support',
        ]) {
          await tester.ensureVisible(find.text(category).first);
          await tester.tap(find.text(category).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$category at $size');
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
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
    await tester.tap(find.byIcon(Icons.view_list_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete Newsroom'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Newsroom?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fixture.controller.channels, hasLength(1));

    await tester.tap(find.byTooltip('Delete Newsroom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete channel'));
    await tester.pumpAndSettle();
    expect(fixture.controller.channels, isEmpty);
  });

  testWidgets('custom channel validation stays local to the form', (
    tester,
  ) async {
    final fixture = UiFixture()
      ..controller.stage = SetupStage.ready
      ..controller.libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..controller.selectedLibraryIds = const {'movies'};
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.view_list_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create channel'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.enterText(find.byType(TextFormField).at(1), 'not a number');
    await tester.tap(find.text('Save channel'));
    await tester.pump();
    expect(find.text('Enter a channel name.'), findsOneWidget);
    expect(find.text('Enter a number from 1 to 1000.'), findsOneWidget);
  });

  testWidgets('protected profile accepts physical digits and backspace', (
    tester,
  ) async {
    const profile = PlexHomeUser(id: 'child', name: 'Child', protected: true);
    final controller = _ProfileFixtureController()
      ..stage = SetupStage.profiles
      ..profiles = const [profile];
    await tester.pumpWidget(UiFixture(controller: controller).build());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Child'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pumpAndSettle();
    expect(controller.pin, '1345');
  });

  testWidgets('Channel Setup remains reachable at the practical minimum', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    final controller = FixtureController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
        PlexLibrary(id: 'shows', title: 'Shows', type: PlexLibraryType.show),
      ];
    await tester.pumpWidget(
      MaterialApp(home: UpstreamChannelSetupView(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Configure channels'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Channel Setup retains its three-stage product structure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _SetupFixtureController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ];
    await tester.pumpWidget(
      MaterialApp(home: UpstreamChannelSetupView(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select Plex libraries'), findsOneWidget);
    await tester.tap(find.text('Configure channels'));
    await tester.pumpAndSettle();
    expect(find.text('Configure the lineup'), findsOneWidget);
    expect(find.text('Content Sources'), findsWidgets);
    expect(find.text('Guide Order'), findsOneWidget);

    await tester.tap(find.text('Build Channels'));
    await tester.pumpAndSettle();
    expect(find.text('Review expected changes'), findsOneWidget);
    expect(find.text('Confirm & Replace'), findsOneWidget);
  });
}

class _ProfileFixtureController extends FixtureController {
  String? pin;

  @override
  Future<void> selectProfile(PlexHomeUser selected, {String? pin}) async {
    this.pin = pin;
  }
}

class _SetupFixtureController extends FixtureController {
  @override
  Future<bool> setLibraries(Set<String> ids) async {
    selectedLibraryIds = Set.unmodifiable(ids);
    availableMedia = [
      for (var index = 0; index < 6; index++)
        PlexMediaItem(
          id: 'movie-$index',
          key: '/library/metadata/$index',
          title: 'Movie $index',
          type: 'movie',
          duration: const Duration(minutes: 90),
          libraryId: 'movies',
          genres: const ['Drama'],
          addedAt: DateTime.utc(2026, 1, index + 1),
        ),
    ];
    return true;
  }
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
