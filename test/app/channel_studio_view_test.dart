import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_air_check.dart';
import 'package:lineup_desktop/app/channel_studio_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/content_resolver.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';

import '../support/ui_fixture.dart';

void main() {
  test(
    'source summaries retain titles, filters, manual counts, and mix shape',
    () {
      final controller = FixtureController()
        ..libraries = const [
          PlexLibrary(
            id: 'shows',
            title: 'TV Shows',
            type: PlexLibraryType.show,
          ),
        ];
      addTearDown(controller.dispose);
      expect(
        channelSourceLabel(
          const LibrarySource(
            libraryId: 'shows',
            libraryType: PlexLibraryType.show,
            includeWatched: false,
            filters: {
              'collection': 'Prestige',
              'genre': 'Drama',
              'studio': 'Lineup',
              'actor': 'Ada Actor',
              'director': 'Dee Director',
              'decade': '2020s',
              'sort': 'added:desc',
            },
          ),
          controller,
        ),
        'Library: TV Shows • Collection: Prestige • Genre: Drama • Studio: Lineup • Actor: Ada Actor • Director: Dee Director • Decade: 2020s • Newest first • unwatched only',
      );
      expect(
        channelSourceLabel(const ManualSource([]), controller),
        '0 hand-picked programs',
      );
      expect(
        channelSourceLabel(
          const MixedSource(
            sources: [PlaylistSource('one'), PlaylistSource('two')],
            interleave: true,
          ),
          controller,
        ),
        '2-source mix • interleaved',
      );
    },
  );

  testWidgets(
    'Channels orders rows and exposes ownership, source, rhythm, and actions',
    (tester) async {
      final fixture = UiFixture()
        ..controller.stage = SetupStage.ready
        ..controller.libraries = const [
          PlexLibrary(
            id: 'movies',
            title: 'Movie Library',
            type: PlexLibraryType.movie,
          ),
        ]
        ..controller.availablePlaylists = const [
          PlexPlaylist(id: 'playlist', title: 'Favorites', items: []),
        ]
        ..controller.channels = [
          _channel(id: 'later', number: 20, name: 'Later'),
          _channel(
            id: 'first',
            number: 2,
            name: 'First',
            builderKey: 'generated:first',
            source: const PlaylistSource('playlist'),
            mode: PlaybackMode.block,
            blockSize: 3,
          ),
        ];
      addTearDown(fixture.controller.dispose);
      await tester.pumpWidget(fixture.build());
      await tester.pump();
      await tester.pump();
      await openDestination(tester, 'Channels');

      final rows = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      expect((rows.first.leading! as CircleAvatar).child, isA<Text>());
      expect(
        find.text('Generated • Playlist: Favorites • Mini-marathons of 3'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Custom • Library: Movie Library • includes watched • In order',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Open First'), findsOneWidget);
      expect(find.byTooltip('Delete First'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete First'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('refresh may propose it again'),
        findsOneWidget,
      );
    },
  );

  testWidgets('removed row focus moves to a surviving row', (tester) async {
    final first = _channel(id: 'first', number: 1, name: 'First');
    final second = _channel(id: 'second', number: 2, name: 'Second');
    final fixture = UiFixture()
      ..controller.stage = SetupStage.ready
      ..controller.channels = [first, second];
    addTearDown(fixture.controller.dispose);
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await tester.pump();
    await openDestination(tester, 'Channels');
    tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Delete First'),
            matching: find.byType(IconButton),
          ),
        )
        .focusNode!
        .requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Delete First');

    fixture.controller.channels = [second];
    fixture.controller.notifyListeners();
    await tester.pump();
    await tester.pump();

    final surviving = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Open Second'),
        matching: find.byType(IconButton),
      ),
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      surviving.focusNode?.debugLabel,
    );
  });

  testWidgets('new, edit, inspect, and duplicate are full-page Studio modes', (
    tester,
  ) async {
    final custom = _channel(id: 'custom', number: 4, name: 'Custom four');
    final generated = _channel(
      id: 'generated',
      number: 8,
      name: 'Generated eight',
      builderKey: 'builder:eight',
      source: const PlaylistSource('playlist'),
      mode: PlaybackMode.block,
      blockSize: 4,
    );
    final fixture = UiFixture()
      ..controller.stage = SetupStage.ready
      ..controller.channels = [custom, generated];
    addTearDown(fixture.controller.dispose);
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await tester.pump();
    await openDestination(tester, 'Channels');

    await tester.tap(find.text('New channel'));
    await tester.pumpAndSettle();
    expect(find.text('Create custom channel'), findsOneWidget);
    expect(find.text('Air Check'), findsOneWidget);
    expect(find.text('New channel'), findsWidgets);
    expect(find.text('1'), findsWidgets);
    await tester.tap(find.text('Back to Channels'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open Custom four'));
    await tester.pumpAndSettle();
    expect(find.text('Edit custom channel'), findsOneWidget);
    expect(find.text('Air Check'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.text('Back to Channels'));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Open Custom four');

    await tester.tap(find.byTooltip('Open Generated eight'));
    await tester.pumpAndSettle();
    expect(find.text('Inspect generated channel'), findsOneWidget);
    expect(find.text('Air Check'), findsOneWidget);
    expect(
      find.text('Programming is read-only and will be preserved exactly.'),
      findsOneWidget,
    );
    expect(find.text('Mini-marathons of 4'), findsOneWidget);
    await tester.tap(find.text('Duplicate as custom'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate as custom'), findsWidgets);
    expect(find.text('Air Check'), findsOneWidget);
    expect(find.text('Duplicate as custom'), findsWidgets);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('studio-name')))
          .controller!
          .text,
      'Generated eight copy',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('studio-number')))
          .controller!
          .text,
      '1',
    );
    expect(fixture.controller.channels.map((channel) => channel.toJson()), [
      custom.toJson(),
      generated.toJson(),
    ]);
  });

  testWidgets('saved Studio restores focus to its lineup row', (tester) async {
    final fixture = UiFixture(controller: _ShellTuneController())
      ..controller.stage = SetupStage.ready
      ..controller.channels = [
        _channel(
          id: 'custom',
          number: 4,
          name: 'Custom',
          source: ManualSource([
            ChannelItem(
              id: 'program',
              title: 'Program',
              duration: const Duration(hours: 1),
            ),
          ]),
        ),
      ];
    addTearDown(fixture.controller.dispose);
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await tester.pump();
    await openDestination(tester, 'Channels');
    await tester.tap(find.byTooltip('Open Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Renamed');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to Channels'));
    await tester.pumpAndSettle();

    final open = find.byTooltip('Open Renamed');
    expect(open, findsOneWidget);
    expect(Focus.of(tester.element(open)).hasFocus, isTrue);
  });

  testWidgets('duplicate and generated saves preserve the complete recipe', (
    tester,
  ) async {
    final original = _channel(
      id: 'source-id',
      number: 7,
      name: 'Source',
      builderKey: 'builder:source',
      source: const PlaylistSource('playlist-7'),
      mode: PlaybackMode.shuffle,
      blockSize: 11,
    );
    final controller = _RecordingSaveController()
      ..channels = [original]
      ..availablePlaylists = [_playlist('playlist-7')];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.duplicateCustom, channel: original),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();
    final duplicate = controller.saved!;
    expect(duplicate.id, isNot(original.id));
    expect(duplicate.number, 1);
    expect(duplicate.name, 'Source copy');
    expect(duplicate.builderKey, isNull);
    expect(duplicate.source.toJson(), original.source.toJson());
    expect(duplicate.playbackMode, original.playbackMode);
    expect(duplicate.blockSize, original.blockSize);
    expect(duplicate.anchor, original.anchor);
    expect(duplicate.shuffleSeed, original.shuffleSeed);
    expect(controller.expectedBase, isNull);
    expect(controller.channels.single.toJson(), original.toJson());

    final custom = _channel(
      id: 'custom-id',
      number: 9,
      name: 'Custom source',
      source: const PlaylistSource('custom-playlist'),
      mode: PlaybackMode.block,
      blockSize: 5,
    );
    controller
      ..channels = [custom]
      ..availablePlaylists = [_playlist('custom-playlist')]
      ..saved = null;
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: custom),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Edited');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(controller.saved!.id, custom.id);
    expect(controller.saved!.number, custom.number);
    expect(controller.saved!.builderKey, isNull);
    expect(controller.saved!.source.toJson(), custom.source.toJson());
    expect(controller.saved!.playbackMode, custom.playbackMode);
    expect(controller.saved!.blockSize, custom.blockSize);
    expect(controller.saved!.anchor, custom.anchor);
    expect(controller.saved!.shuffleSeed, custom.shuffleSeed);
    expect(controller.expectedBase?.toJson(), custom.toJson());

    controller.channels = [original];
    controller.availablePlaylists = [_playlist('playlist-7')];
    controller.saved = null;
    await tester.pumpWidget(
      _studio(
        controller,
        ChannelStudioMode.inspectGenerated,
        channel: original,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Renamed');
    await tester.pump();
    expect(find.text('Unsaved changes'), findsOneWidget);
    tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Save identity'),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(controller.saved!.id, original.id);
    expect(controller.saved!.builderKey, original.builderKey);
    expect(controller.saved!.source.toJson(), original.source.toJson());
    expect(controller.saved!.playbackMode, original.playbackMode);
    expect(controller.saved!.blockSize, original.blockSize);
    expect(controller.saved!.anchor, original.anchor);
    expect(controller.saved!.shuffleSeed, original.shuffleSeed);
    expect(controller.expectedBase?.toJson(), original.toJson());
  });

  testWidgets('all occupied numbers produce an explicit unsaveable draft', (
    tester,
  ) async {
    final controller = FixtureController()
      ..stage = SetupStage.ready
      ..channels = [
        for (var number = 1; number <= 1000; number++)
          _channel(
            id: 'channel-$number',
            number: number,
            name: 'Channel $number',
          ),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(UiFixture(controller: controller).build());
    await tester.pump();
    await tester.pump();
    await openDestination(tester, 'Channels');
    await tester.tap(find.text('New channel'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No channel numbers are available'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save channel'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('studio-number')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('exhausted duplicate stays exact while edit reuses its number', (
    tester,
  ) async {
    final channels = [
      for (var number = 1; number <= 1000; number++)
        _channel(
          id: 'channel-$number',
          number: number,
          name: 'Channel $number',
          source: number == 500
              ? const PlaylistSource('kept-playlist')
              : const LibrarySource(
                  libraryId: 'movies',
                  libraryType: PlexLibraryType.movie,
                ),
          mode: number == 500 ? PlaybackMode.shuffle : PlaybackMode.sequential,
          blockSize: number == 500 ? 13 : null,
        ),
    ];
    final controller = FixtureController()..channels = channels;
    addTearDown(controller.dispose);
    final original = channels[499];

    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.duplicateCustom, channel: original),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No channel numbers are available'),
      findsOneWidget,
    );
    expect(_fieldText(tester, 'studio-number'), isEmpty);
    expect(find.text('Playlist: kept-playlist'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save channel'),
          )
          .onPressed,
      isNull,
    );

    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();
    expect(_fieldText(tester, 'studio-number'), '500');
    expect(
      find.textContaining('No channel numbers are available'),
      findsNothing,
    );
  });

  testWidgets(
    'identity validation names conflicts and focuses the first error',
    (tester) async {
      final controller = FixtureController()
        ..channels = [_channel(id: 'taken', number: 7, name: 'The Seven')]
        ..libraries = const [
          PlexLibrary(
            id: 'movies',
            title: 'Movies',
            type: PlexLibraryType.movie,
          ),
        ]
        ..selectedLibraryIds = {'movies'}
        ..availableMedia = [_media('valid', libraryId: 'movies')];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.createCustom),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('studio-name')), '');
      await tester.enterText(find.byKey(const Key('studio-number')), '7');
      await tester.tap(find.text('Save channel'));
      await tester.pump();

      expect(find.text('Enter a channel name.'), findsOneWidget);
      expect(
        find.text('Channel 7 is already used by The Seven.'),
        findsOneWidget,
      );
      expect(find.text('Use next available'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Channel name');
      await tester.ensureVisible(find.text('Use next available'));
      await tester.tap(find.text('Use next available'));
      await tester.pump();
      expect(_fieldText(tester, 'studio-number'), '1');
    },
  );

  testWidgets('dirty shortcut navigation uses the shared leave confirmation', (
    tester,
  ) async {
    final fixture = UiFixture()
      ..controller.stage = SetupStage.ready
      ..controller.channels = [
        _channel(id: 'custom', number: 1, name: 'Custom'),
      ];
    addTearDown(fixture.controller.dispose);
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await tester.pump();
    await openDestination(tester, 'Channels');
    await tester.tap(find.byTooltip('Open Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Changed');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Edit custom channel'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Edit custom channel'), findsNothing);

    await tester.tap(find.byTooltip('Open Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('studio-name')),
      'Changed again',
    );
    await tester.tap(find.byIcon(Icons.monitor_heart_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to Channels'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsNothing);
    await tester.tap(find.text('Back to Channels'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('Channels'), findsWidgets);
  });

  testWidgets('failed save preserves the draft and announces rollback', (
    tester,
  ) async {
    final original = _channel(
      id: 'custom',
      number: 3,
      name: 'Original',
      source: const PlaylistSource('playlist'),
    );
    final controller = _FailingSaveController()
      ..channels = [original]
      ..availablePlaylists = [_playlist('playlist')];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('studio-name')),
      'Complete draft',
    );
    await tester.pump();
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save changes'))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(controller.channels.single.toJson(), original.toJson());
    expect(find.textContaining('No lineup changes were saved'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('studio-name')))
          .controller!
          .text,
      'Complete draft',
    );
  });

  testWidgets('save progress is live and failure restores the save action', (
    tester,
  ) async {
    final original = _channel(
      id: 'custom',
      number: 3,
      name: 'Original',
      source: const PlaylistSource('playlist'),
    );
    final controller = _BlockingSaveController()
      ..channels = [original]
      ..availablePlaylists = [_playlist('playlist')];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Draft');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pump();

    final savingText = find.text('Saving channel…');
    expect(savingText, findsOneWidget);
    final savingSemantics = tester.widget<Semantics>(
      find.ancestor(of: savingText, matching: find.byType(Semantics)).first,
    );
    expect(savingSemantics.properties.liveRegion, isTrue);
    expect(savingSemantics.properties.label, 'Saving channel');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('studio-name')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Back to Channels'),
          )
          .onPressed,
      isNull,
    );
    controller.release.complete();
    await tester.pumpAndSettle();

    expect(controller.channels.single.toJson(), original.toJson());
    expect(_fieldText(tester, 'studio-name'), 'Draft');
    expect(find.textContaining('No lineup changes were saved'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Save channel');
  });

  testWidgets('saving Studio blocks shortcut and app Back navigation', (
    tester,
  ) async {
    final original = _channel(
      id: 'custom',
      number: 3,
      name: 'Original',
      source: const ManualSource([
        ChannelItem(
          id: 'first',
          title: 'First program',
          duration: Duration(minutes: 30),
        ),
        ChannelItem(
          id: 'second',
          title: 'Second program',
          duration: Duration(minutes: 30),
        ),
      ]),
    );
    final controller = _BlockingSaveController()
      ..stage = SetupStage.ready
      ..channels = [original];
    final fixture = UiFixture(controller: controller);
    addTearDown(controller.dispose);
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await tester.pump();
    await openDestination(tester, 'Channels');
    await tester.tap(find.byTooltip('Open Original'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Draft');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('studio-rundown-second')));
    await tester.tap(find.byKey(const Key('studio-rundown-second')));
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pump();

    tester
        .widget<Focus>(
          find
              .ancestor(
                of: find.byKey(const Key('studio-rundown-second')),
                matching: find.byType(Focus),
              )
              .first,
        )
        .focusNode!
        .requestFocus();
    await tester.pump();
    void expectOriginalOrder() {
      expect(find.byKey(const Key('studio-rundown-first')), findsOneWidget);
      expect(find.byKey(const Key('studio-rundown-second')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('studio-rundown-first'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('studio-rundown-second'))).dy,
        ),
      );
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expectOriginalOrder();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expectOriginalOrder();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expectOriginalOrder();
    expect(
      (controller.attempted!.source as ManualSource).items.map(
        (item) => item.id,
      ),
      ['first', 'second'],
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.byIcon(Icons.monitor_heart_outlined));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Draft'), findsWidgets);
    expect(find.text('Discard changes?'), findsNothing);

    controller.release.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('successful save becomes clean and failed tune stays in Studio', (
    tester,
  ) async {
    final controller = _RecordingSaveController()
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..selectedLibraryIds = {'movies'}
      ..availableMedia = [_media('movie', libraryId: 'movies')];
    var tuneCalls = 0;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChannelStudioView(
            controller: controller,
            mode: ChannelStudioMode.createCustom,
            onBack: (_) async {},
            onSaved: (_) {},
            onDuplicate: (_) {},
            onOpenGenerateLineup: () async {},
            onTune: (_) async {
              tuneCalls++;
              return false;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('studio-name')),
      'Saved station',
    );
    await tester.pump();
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();

    expect(find.text('Channel saved.'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Tune in'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNull,
    );
    final saved = controller.saved!;
    expect(saved.id, isNotEmpty);
    expect(saved.number, 1);
    expect(saved.name, 'Saved station');
    expect(saved.builderKey, isNull);
    expect(
      saved.source.toJson(),
      const LibrarySource(
        libraryId: 'movies',
        libraryType: PlexLibraryType.movie,
      ).toJson(),
    );
    expect(saved.playbackMode, PlaybackMode.shuffle);
    expect(saved.blockSize, isNull);
    expect(saved.anchor.isUtc, isTrue);
    expect(saved.shuffleSeed, saved.id.hashCode);
    expect(controller.expectedBase, isNull);
    await tester.tap(find.text('Tune in'));
    await tester.pumpAndSettle();
    expect(tuneCalls, 1);
    expect(find.text('Saved station'), findsWidgets);
    expect(find.textContaining('could not be tuned'), findsOneWidget);
    expect(controller.saved?.name, 'Saved station');

    await tester.enterText(
      find.byKey(const Key('studio-name')),
      'Unsaved station',
    );
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Tune in'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('empty manual save retains the draft and reports validation', (
    tester,
  ) async {
    final controller = _RecordingSaveController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChannelStudioView(
            controller: controller,
            mode: ChannelStudioMode.createCustom,
            onBack: (_) async {},
            onSaved: (_) {},
            onDuplicate: (_) {},
            onOpenGenerateLineup: () async {},
            onTune: (_) async => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Empty draft');
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();

    expect(controller.saved, isNull);
    expect(find.text('Select at least one program.'), findsOneWidget);
    expect(_fieldText(tester, 'studio-name'), 'Empty draft');
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('successful Studio tune opens Player', (tester) async {
    final item = PlexMediaItem(
      id: 'program',
      title: 'Program',
      type: 'movie',
      duration: const Duration(hours: 24),
      parts: [PlexMediaPart(path: '/program')],
    );
    final controller = _ShellTuneController()
      ..stage = SetupStage.ready
      ..channels = [
        _channel(
          id: 'custom',
          number: 3,
          name: 'Custom',
          source: const ManualSource([
            ChannelItem(
              id: 'program',
              title: 'Program',
              duration: Duration(hours: 24),
            ),
          ]),
        ),
      ]
      ..availableMedia = [item];
    final player = FixturePlayer();
    final fixture = UiFixture(controller: controller, player: player);
    addTearDown(controller.dispose);
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await tester.pump();
    await openDestination(tester, 'Channels');
    await tester.tap(find.byTooltip('Open Custom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tune in'));
    for (var index = 0; index < 10; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(player.generation, 1);
    expect(find.text('Inspect generated channel'), findsNothing);
    expect(find.text('Edit custom channel'), findsNothing);
  });

  testWidgets('saved Air Check agrees with Guide and Player boundaries', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1, 0, 10);
    final channel = _channel(
      id: 'agreement',
      number: 7,
      name: 'Agreement',
      source: ManualSource([_itemForHealth(1), _itemForHealth(2)]),
    );
    final controller = _AgreementController()
      ..stage = SetupStage.ready
      ..channels = [channel];
    final player = _AgreementPlayer();
    final fixture = UiFixture(
      controller: controller,
      player: player,
      guideClock: () => now,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await tester.pump();
    await openDestination(tester, 'Channels');
    await tester.tap(find.byTooltip('Open Agreement'));
    await tester.pumpAndSettle();
    final expected = programAt(
      now,
      channel.anchor,
      await controller.loadScheduleFor(channel),
    );
    expect(
      find.bySemanticsLabel(
        RegExp(
          'Channel 7 Agreement, ${expected.item.title}, ${_testTime(expected.start.toLocal())} to ${_testTime(expected.end.toLocal())}, current',
        ),
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('studio-name')),
      'Saved agreement',
    );
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    final saved = controller.channels.single;
    final savedProgram = programAt(
      now,
      saved.anchor,
      await controller.loadScheduleFor(saved),
    );
    expect(savedProgram.item.id, expected.item.id);
    expect(savedProgram.start, expected.start);
    expect(savedProgram.end, expected.end);

    await tester.tap(find.text('Back to Channels'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        RegExp(
          '${savedProgram.item.title}, ${_testTime(savedProgram.start.toLocal())} to ${_testTime(savedProgram.end.toLocal())}, currently airing',
        ),
      ),
      findsOneWidget,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Saved agreement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tune in'));
    for (var index = 0; index < 10; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(player.loaded?.path, '/${savedProgram.item.id}');
  });

  testWidgets(
    'changed and deleted bases never overwrite or recreate silently',
    (tester) async {
      final original = _channel(
        id: 'custom',
        number: 3,
        name: 'Original',
        source: const PlaylistSource('playlist'),
      );
      final changed = _channel(
        id: 'custom',
        number: 3,
        name: 'External',
        source: const PlaylistSource('playlist'),
      );
      final controller = _ExpectedBaseController()
        ..channels = [original]
        ..availablePlaylists = [_playlist('playlist')];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.editCustom, channel: original),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('studio-name')), 'Mine');
      await tester.pump();
      controller.channels = [changed];
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Use saved version…'), findsOneWidget);
      expect(find.text('Replace saved version with my draft…'), findsOneWidget);
      expect(controller.channels.single.name, 'External');
      final useSavedButton = find.widgetWithText(
        OutlinedButton,
        'Use saved version…',
      );
      final useSaved = tester.widget<OutlinedButton>(useSavedButton);
      expect(FocusManager.instance.primaryFocus, same(useSaved.focusNode));
      expect(tester.getTopLeft(useSavedButton).dy, greaterThanOrEqualTo(0));
      final roles = LineupTheme.of(tester.element(useSavedButton));
      final focusedSide = useSaved.style!.side!.resolve({WidgetState.focused})!;
      expect(focusedSide.color, roles.focusBorder);
      expect(focusedSide.width, roles.focusBorderWidth);

      await tester.ensureVisible(find.text('Use saved version…'));
      await tester.tap(find.text('Use saved version…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use saved version'));
      await tester.pumpAndSettle();
      expect(_fieldText(tester, 'studio-name'), 'External');
      await tester.enterText(find.byKey(const Key('studio-name')), 'Mine');
      await tester.pump();
      final changedAgain = _channel(
        id: 'custom',
        number: 3,
        name: 'External again',
        source: const PlaylistSource('playlist'),
      );
      controller.channels = [changedAgain];
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.text('Replace saved version with my draft…'),
      );
      await tester.tap(find.text('Replace saved version with my draft…'));
      await tester.pumpAndSettle();
      controller.channels = [
        _channel(
          id: 'custom',
          number: 3,
          name: 'Intervening',
          source: const PlaylistSource('playlist'),
        ),
      ];
      await tester.tap(find.text('Replace saved version'));
      await tester.pumpAndSettle();
      expect(controller.channels.single.name, 'Intervening');
      expect(find.text('Replace saved version with my draft…'), findsOneWidget);

      await tester.ensureVisible(
        find.text('Replace saved version with my draft…'),
      );
      await tester.tap(find.text('Replace saved version with my draft…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace saved version'));
      await tester.pumpAndSettle();
      expect(controller.channels.single.name, 'Mine');

      await tester.enterText(find.byKey(const Key('studio-name')), 'Again');
      await tester.pump();
      controller.channels = const [];
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('This channel was deleted'), findsOneWidget);
      expect(find.text('Replace saved version with my draft…'), findsNothing);
      expect(controller.channels, isEmpty);
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Return to Channels'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(controller.channels, isEmpty);
    },
  );

  testWidgets('conflict reload refreshes visible recipe fields', (
    tester,
  ) async {
    final original = _channel(
      id: 'custom',
      number: 3,
      name: 'Original',
      source: const PlaylistSource('original'),
      mode: PlaybackMode.block,
      blockSize: 2,
    );
    final external = _channel(
      id: 'custom',
      number: 3,
      name: 'External',
      source: const PlaylistSource('external'),
      mode: PlaybackMode.block,
      blockSize: 4,
    );
    final controller = _ExpectedBaseController()
      ..channels = [original]
      ..availablePlaylists = [
        _playlist('original'),
        _playlist('draft'),
        _playlist('external'),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();

    await _chooseDropdown(tester, 'studio-playlist', 'Playlist draft');
    await _chooseDropdown(tester, 'studio-block-size', '5');
    controller.channels = [external];
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use saved version…'));
    await tester.tap(find.text('Use saved version…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use saved version'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<String>>(
            find.descendant(
              of: find.byKey(const Key('studio-playlist')),
              matching: find.byType(DropdownButton<String>),
            ),
          )
          .value,
      'external',
    );
    expect(
      tester
          .widget<DropdownButton<int>>(
            find.descendant(
              of: find.byKey(const Key('studio-block-size')),
              matching: find.byType(DropdownButton<int>),
            ),
          )
          .value,
      4,
    );

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNull,
    );
    final saved = controller.channels.single;
    expect(saved.source.toJson(), external.source.toJson());
    expect(saved.blockSize, external.blockSize);
    expect(find.text('Playlist: Playlist external'), findsOneWidget);
    expect(find.text('Mini-marathons of 4'), findsOneWidget);
  });

  testWidgets('offers exactly four source choices and retains draft values', (
    tester,
  ) async {
    final controller = _RecordingSaveController()
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
        PlexLibrary(id: 'shows', title: 'Shows', type: PlexLibraryType.show),
      ]
      ..selectedLibraryIds = {'movies', 'shows'}
      ..availableMedia = [
        _media('movie', libraryId: 'movies'),
        _media(
          'episode',
          libraryId: 'shows',
          type: 'episode',
          showTitle: 'Show',
        ),
      ]
      ..availablePlaylists = [_playlist('favorites'), _playlist('later')];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom),
    );
    await tester.pumpAndSettle();

    for (final label in const [
      'Library',
      'Playlist',
      'Collection or filter',
      'Hand-picked',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.ensureVisible(find.text('Include watched items'));
    await tester.tap(find.text('Include watched items'));
    await tester.pump();
    await tester.ensureVisible(find.text('Playlist'));
    await tester.tap(find.text('Playlist'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('studio-playlist')));
    await tester.tap(find.byKey(const Key('studio-playlist')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playlist later').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Library'));
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.ensureVisible(find.text('Playlist'));
    await tester.tap(find.text('Playlist'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('studio-playlist')),
          )
          .initialValue,
      'later',
    );
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('studio-name')),
      'Library pick',
    );
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();
    final saved = controller.saved!.source as LibrarySource;
    expect(saved.libraryId, 'movies');
    expect(saved.libraryType, PlexLibraryType.movie);
    expect(saved.includeWatched, isFalse);
  });

  testWidgets('custom mixed sources stay lossless until explicitly replaced', (
    tester,
  ) async {
    final source = MixedSource(
      interleave: true,
      sources: [
        ManualSource([
          ChannelItem(
            id: 'one',
            title: 'One retained',
            duration: const Duration(minutes: 30),
          ),
        ]),
        const LibrarySource(
          libraryId: 'movies',
          libraryType: PlexLibraryType.movie,
        ),
      ],
    );
    final original = _channel(
      id: 'mixed',
      number: 6,
      name: 'Mixed',
      source: source,
    );
    final controller = _RecordingSaveController()
      ..channels = [original]
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..selectedLibraryIds = {'movies'}
      ..availableMedia = [_media('movie', libraryId: 'movies')];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('mixed source is preserved exactly'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('studio-name')),
      'Mixed renamed',
    );
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(controller.saved!.source.toJson(), source.toJson());
    expect(controller.saved!.builderKey, isNull);
  });

  testWidgets(
    'nested retained mixed source permits identity-only off-air save',
    (tester) async {
      const source = MixedSource(
        sources: [
          ManualSource([
            ChannelItem(
              id: 'unavailable',
              title: 'Unavailable retained program',
              duration: Duration(minutes: 30),
            ),
          ]),
        ],
      );
      final original = _channel(
        id: 'mixed-off-air',
        number: 16,
        name: 'Mixed off air',
        source: source,
      );
      final controller = _RecordingSaveController()..channels = [original];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.editCustom, channel: original),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('explicitly off air'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('studio-name')),
        'Mixed off air renamed',
      );
      await tester.pump();
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save changes'),
      );
      expect(save.onPressed, isNotNull);
      save.onPressed!();
      await tester.pumpAndSettle();
      expect(controller.saved!.source.toJson(), source.toJson());
      expect(controller.saved!.name, 'Mixed off air renamed');
    },
  );

  testWidgets('playlist editor saves the selected live playlist', (
    tester,
  ) async {
    final controller = _RecordingSaveController()
      ..availablePlaylists = [_playlist('playlist')];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Playlist'));
    await tester.tap(find.text('Playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Playlist');
    await tester.ensureVisible(find.text('Save channel'));
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();
    expect(
      controller.saved!.source.toJson(),
      const PlaylistSource('playlist').toJson(),
    );
    expect(controller.saved!.builderKey, isNull);
  });

  testWidgets(
    'reverting programming restores clean without hiding other edits',
    (tester) async {
      final key = GlobalKey<ChannelStudioViewState>();
      final original = _channel(id: 'revert', number: 7, name: 'Revert');
      final controller = FixtureController()
        ..channels = [original]
        ..libraries = const [
          PlexLibrary(
            id: 'movies',
            title: 'Movies',
            type: PlexLibraryType.movie,
          ),
        ]
        ..selectedLibraryIds = {'movies'}
        ..availableMedia = [_media('movie', libraryId: 'movies')]
        ..availablePlaylists = [_playlist('playlist')];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChannelStudioView(
              key: key,
              controller: controller,
              mode: ChannelStudioMode.editCustom,
              channel: original,
              onBack: (_) async {},
              onSaved: (_) {},
              onDuplicate: (_) {},
              onOpenGenerateLineup: () async {},
              onTune: (_) async => false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Playlist'));
      await tester.tap(find.text('Playlist'));
      await tester.pumpAndSettle();
      expect(key.currentState!.dirty, isTrue);
      await tester.ensureVisible(find.text('Library'));
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(key.currentState!.dirty, isFalse);

      await tester.enterText(find.byKey(const Key('studio-name')), 'Changed');
      await tester.ensureVisible(find.text('Playlist'));
      await tester.tap(find.text('Playlist'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Library'));
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(key.currentState!.dirty, isTrue);
    },
  );

  testWidgets('different invalid active sources remain dirty', (tester) async {
    final key = GlobalKey<ChannelStudioViewState>();
    final original = _channel(
      id: 'invalid-revert',
      number: 14,
      name: 'Invalid source',
      source: const LibrarySource(
        libraryId: 'missing',
        libraryType: PlexLibraryType.movie,
      ),
    );
    final controller = FixtureController()..channels = [original];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChannelStudioView(
            key: key,
            controller: controller,
            mode: ChannelStudioMode.editCustom,
            channel: original,
            onBack: (_) async {},
            onSaved: (_) {},
            onDuplicate: (_) {},
            onOpenGenerateLineup: () async {},
            onTune: (_) async => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.dirty, isFalse);
    await tester.ensureVisible(find.text('Collection or filter'));
    await tester.tap(find.text('Collection or filter'));
    await tester.pumpAndSettle();
    expect(key.currentState!.dirty, isTrue);
  });

  testWidgets('inventory metadata refresh does not prevent a clean revert', (
    tester,
  ) async {
    final key = GlobalKey<ChannelStudioViewState>();
    final original = _channel(
      id: 'metadata-revert',
      number: 15,
      name: 'Metadata',
      source: const ManualSource([
        ChannelItem(
          id: 'item',
          title: 'Stored title',
          duration: Duration(minutes: 30),
        ),
      ]),
    );
    final controller = FixtureController()
      ..channels = [original]
      ..availableMedia = [_media('item', title: 'First live title')];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChannelStudioView(
            key: key,
            controller: controller,
            mode: ChannelStudioMode.editCustom,
            channel: original,
            onBack: (_) async {},
            onSaved: (_) {},
            onDuplicate: (_) {},
            onOpenGenerateLineup: () async {},
            onTune: (_) async => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectStudioStage(tester, 'studio-manual-browse-stage');
    tester
        .widget<CheckboxListTile>(find.byKey(const Key('studio-result-item')))
        .onChanged!(false);
    await tester.pump();
    expect(key.currentState!.dirty, isTrue);
    tester
        .widget<CheckboxListTile>(find.byKey(const Key('studio-result-item')))
        .onChanged!(true);
    await tester.pump();
    expect(key.currentState!.dirty, isFalse);

    controller.availableMedia = [_media('item', title: 'Refreshed title')];
    await tester.enterText(find.byKey(const Key('studio-name')), 'Changed');
    expect(key.currentState!.dirty, isTrue);
    await tester.enterText(find.byKey(const Key('studio-name')), 'Metadata');
    expect(key.currentState!.dirty, isFalse);
  });

  testWidgets('mixed live children must remain controller-valid', (
    tester,
  ) async {
    final original = _channel(
      id: 'mixed-invalid',
      number: 8,
      name: 'Mixed invalid',
      source: const MixedSource(
        sources: [
          ManualSource([
            ChannelItem(
              id: 'retained',
              title: 'Retained',
              duration: Duration(minutes: 30),
            ),
          ]),
          LibrarySource(
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
          ),
        ],
      ),
    );
    final controller = FixtureController()
      ..channels = [original]
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..selectedLibraryIds = {'movies'}
      ..libraryScanStatus = LibraryScanStatus.scanning;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Loading programming'), findsOneWidget);
    expect(
      find.textContaining('match no playable programs. Choose a replacement'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNull,
    );
    await expectLater(
      controller.saveChannel(original, expectedBase: original),
      throwsFormatException,
    );
    for (final state in [
      LibraryScanStatus.idle,
      LibraryScanStatus.cancelled,
      LibraryScanStatus.transientFailure,
    ]) {
      controller.libraryScanStatus = state;
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.editCustom, channel: original),
      );
      await tester.pumpAndSettle();
      expect(
        state == LibraryScanStatus.idle
            ? find.textContaining('No usable programming is loaded')
            : find.textContaining('last usable programming'),
        findsOneWidget,
      );
    }

    final unsupported = _channel(
      id: 'mixed-unsupported',
      number: 9,
      name: 'Mixed unsupported',
      source: const MixedSource(
        sources: [
          ManualSource([
            ChannelItem(
              id: 'retained',
              title: 'Retained',
              duration: Duration(minutes: 30),
            ),
          ]),
          LibrarySource(
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
            filters: {'future': 'value'},
          ),
        ],
      ),
    );
    controller
      ..channels = [unsupported]
      ..availableMedia = [_media('movie', libraryId: 'movies')]
      ..libraryScanStatus = LibraryScanStatus.idle;
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: unsupported),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('unsupported filter'), findsOneWidget);

    final emptyPlaylist = _channel(
      id: 'mixed-empty-playlist',
      number: 10,
      name: 'Mixed empty playlist',
      source: const MixedSource(
        sources: [
          ManualSource([
            ChannelItem(
              id: 'retained',
              title: 'Retained',
              duration: Duration(minutes: 30),
            ),
          ]),
          PlaylistSource('empty'),
        ],
      ),
    );
    controller
      ..channels = [emptyPlaylist]
      ..availablePlaylists = const [
        PlexPlaylist(id: 'empty', title: 'Empty', items: []),
      ];
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: emptyPlaylist),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('playlist has no playable programs'),
      findsOneWidget,
    );
  });

  testWidgets('filter facets AND locally and newest-first saves exactly', (
    tester,
  ) async {
    final controller = _RecordingSaveController()
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..selectedLibraryIds = {'movies'}
      ..availableMedia = [
        _media(
          'older',
          libraryId: 'movies',
          genres: ['Comedy'],
          collections: ['Favorites'],
          studio: 'Studio A',
          actors: ['Actor A'],
          directors: ['Director A'],
          year: 1994,
          addedAt: DateTime.utc(2020),
        ),
        _media(
          'newer',
          libraryId: 'movies',
          genres: ['Comedy'],
          collections: ['Favorites'],
          studio: 'Studio B',
          year: 1998,
          addedAt: DateTime.utc(2022),
        ),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Filtered');
    await tester.ensureVisible(find.text('Collection or filter'));
    await tester.tap(find.text('Collection or filter'));
    await tester.pumpAndSettle();
    await _chooseDropdown(tester, 'studio-facet-genre', 'Comedy');
    await _chooseDropdown(tester, 'studio-facet-studio', 'Studio A');
    expect(find.text('1 matching programs'), findsOneWidget);
    await tester.ensureVisible(find.text('Newest first'));
    await tester.tap(find.text('Newest first'));
    await _settleAirCheck(tester);
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();

    final source = controller.saved!.source as LibrarySource;
    expect(source.libraryId, 'movies');
    expect(source.libraryType, PlexLibraryType.movie);
    expect(source.filters, {
      'genre': 'Comedy',
      'studio': 'Studio A',
      'sort': 'added:desc',
    });
    expect(
      resolveContent(source, controller.availableMedia).map((item) => item.id),
      ['older'],
    );
    expect(find.textContaining('same-key'), findsNothing);
  });

  testWidgets('changing filter library resets displayed and saved facets', (
    tester,
  ) async {
    final controller = _RecordingSaveController()
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
        PlexLibrary(id: 'shows', title: 'Shows', type: PlexLibraryType.show),
      ]
      ..selectedLibraryIds = {'movies', 'shows'}
      ..availableMedia = [
        _media('comedy', libraryId: 'movies', genres: ['Comedy']),
        _media('drama', libraryId: 'shows', genres: ['Drama']),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Collection or filter'));
    await tester.tap(find.text('Collection or filter'));
    await tester.pumpAndSettle();
    await _chooseDropdown(tester, 'studio-facet-genre', 'Comedy');

    await _chooseDropdown(tester, 'studio-filter-library', 'Shows');

    final genre = find.descendant(
      of: find.byKey(const Key('studio-facet-genre')),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    expect(
      tester.widget<DropdownButtonFormField<String>>(genre).initialValue,
      '',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('studio-facet-genre')),
        matching: find.text('Any'),
      ),
      findsOneWidget,
    );
    expect(find.text('1 matching programs'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('studio-name')),
      'Filtered shows',
    );
    await _settleAirCheck(tester);
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();
    final savedSource = controller.saved!.source as LibrarySource;
    expect(savedSource.libraryId, 'shows');
    expect(savedSource.filters, isEmpty);
  });

  testWidgets(
    'manual search, bulk actions, unavailable retention, order, and focus agree',
    (tester) async {
      final original = _channel(
        id: 'manual',
        number: 9,
        name: 'Manual',
        source: const ManualSource([
          ChannelItem(
            id: 'missing',
            title: 'Missing favorite',
            duration: Duration(minutes: 30),
          ),
        ]),
      );
      final controller = _RecordingSaveController()
        ..channels = [original]
        ..libraries = const [
          PlexLibrary(id: 'shows', title: 'Shows', type: PlexLibraryType.show),
        ]
        ..selectedLibraryIds = {'shows'}
        ..availableMedia = [
          _media(
            'one',
            title: 'Pilot',
            libraryId: 'shows',
            type: 'episode',
            showTitle: 'Alpha Show',
            genres: ['Comedy'],
          ),
          _media(
            'two',
            title: 'Finale',
            libraryId: 'shows',
            type: 'episode',
            showTitle: 'Beta Show',
            genres: ['Drama'],
          ),
        ];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.editCustom, channel: original),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unavailable — retained until removed'), findsOneWidget);

      await _selectStudioStage(tester, 'studio-manual-browse-stage');
      await tester.enterText(find.byKey(const Key('studio-search')), 'alpha');
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('1 matching, 1 selected'), findsOneWidget);
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Select visible'))
          .onPressed!();
      await tester.pump();
      expect(find.text('1 matching, 2 selected'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('studio-search')), 'beta');
      await tester.pump(const Duration(milliseconds: 350));
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Select visible'))
          .onPressed!();
      await tester.pump();
      await _selectStudioStage(tester, 'studio-manual-rundown-stage');
      expect(find.byKey(const Key('studio-rundown-missing')), findsOneWidget);
      expect(find.byKey(const Key('studio-search')), findsNothing);
      await _selectStudioStage(tester, 'studio-manual-browse-stage');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('studio-search')))
            .controller!
            .text,
        'beta',
      );
      await _selectStudioStage(tester, 'studio-manual-rundown-stage');

      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Move Pilot later in channel Manual'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed!();
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Selected program Pilot',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Selected program Finale',
      );
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Move Finale earlier in channel Manual'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed!();
      await tester.pump();
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Remove Missing favorite from channel Manual'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed!();
      await tester.pump();
      await tester.ensureVisible(find.text('Save changes'));
      await _settleAirCheck(tester);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        (controller.saved!.source as ManualSource).items.map((item) => item.id),
        ['two'],
      );
    },
  );

  testWidgets('clear visible preserves hidden manual selections', (
    tester,
  ) async {
    final controller = _RecordingSaveController()
      ..availableMedia = [
        _media('alpha', title: 'Alpha'),
        _media('beta', title: 'Beta'),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Select visible'))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Clear visible'))
          .onPressed,
      isNull,
    );
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Select visible'))
        .onPressed!();
    await tester.pump();
    await tester.enterText(find.byKey(const Key('studio-search')), 'alpha');
    await tester.pump(const Duration(milliseconds: 350));
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Clear visible'))
        .onPressed!();
    await tester.pump();
    await _selectStudioStage(tester, 'studio-manual-rundown-stage');
    expect(find.byKey(const Key('studio-rundown-alpha')), findsNothing);
    expect(find.byKey(const Key('studio-rundown-beta')), findsOneWidget);
  });

  testWidgets('mini-marathons require grouping and expose sizes 2 through 5', (
    tester,
  ) async {
    final controller = _RecordingSaveController()
      ..availableMedia = [_media('movie')];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom),
    );
    await tester.pumpAndSettle();
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Select visible'))
        .onPressed!();
    await tester.pump();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Ungrouped');
    await tester.pump();
    await tester.ensureVisible(find.text('Mini-marathons'));
    await tester.tap(find.text('Mini-marathons'));
    await tester.pump();
    expect(
      find.textContaining('grouped by show title or show artwork'),
      findsWidgets,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save channel'),
          )
          .onPressed,
      isNull,
    );

    controller.availableMedia = [
      for (final show in ['a', 'b'])
        for (var episode = 1; episode <= 5; episode++)
          _media('$show$episode', type: 'episode', showThumb: '/show/$show'),
    ];
    const expectedOrders = {
      2: ['a1', 'a2', 'b1', 'b2', 'a3', 'a4', 'b3', 'b4', 'a5', 'b5'],
      3: ['a1', 'a2', 'a3', 'b1', 'b2', 'b3', 'a4', 'a5', 'b4', 'b5'],
      4: ['a1', 'a2', 'a3', 'a4', 'b1', 'b2', 'b3', 'b4', 'a5', 'b5'],
      5: ['a1', 'a2', 'a3', 'a4', 'a5', 'b1', 'b2', 'b3', 'b4', 'b5'],
    };
    for (var size = 2; size <= 5; size++) {
      controller.saved = null;
      final original = _channel(
        id: 'blocks-$size',
        number: 1,
        name: 'Blocks',
        source: ManualSource(
          controller.availableMedia.map(channelItemFor).toList(),
        ),
      );
      controller.channels = [original];
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.editCustom, channel: original),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Mini-marathons'));
      await tester.tap(find.text('Mini-marathons'));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('studio-block-size')));
      await tester.tap(find.byKey(const Key('studio-block-size')));
      await tester.pumpAndSettle();
      for (var option = 2; option <= 5; option++) {
        expect(find.text('$option'), findsWidgets);
      }
      await tester.tap(find.text('$size').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final saved = controller.saved!;
      expect(saved.playbackMode, PlaybackMode.block);
      expect(saved.blockSize, size);
      final source = saved.source as ManualSource;
      expect(
        buildSchedule(
          source.items,
          mode: saved.playbackMode,
          seed: saved.shuffleSeed,
          blockSize: saved.blockSize!,
        ).items.map((item) => item.id),
        expectedOrders[size],
      );
    }
  });

  testWidgets(
    'inventory states preserve draft and use Generate lineup recovery',
    (tester) async {
      final retained = _channel(
        id: 'retained',
        number: 4,
        name: 'Retained',
        source: const PlaylistSource('gone'),
      );
      final controller = FixtureController()
        ..channels = [retained]
        ..libraryScanStatus = LibraryScanStatus.transientFailure;
      var left = 0;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _RecoveryHarness(
          controller: controller,
          channel: retained,
          onLeft: () => left++,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Playlist gone is unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('last usable programming'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry in Generate lineup'));
      await tester.tap(find.text('Retry in Generate lineup'));
      await tester.pump();
      expect(left, 1);
      expect(controller.stage, SetupStage.channelSetup);
    },
  );

  testWidgets('large inventories keep a bounded deterministic result window', (
    tester,
  ) async {
    final controller = FixtureController()
      ..availableMedia = [for (var i = 0; i < 1200; i++) _media('item-$i')];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('first 100 of 1200'), findsOneWidget);
    expect(find.byType(CheckboxListTile).evaluate().length, lessThan(30));
    await tester.enterText(find.byKey(const Key('studio-search')), 'item-1199');
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const Key('studio-result-item-1199')), findsOneWidget);
  });

  testWidgets('filtered edits preserve includeWatched false exactly', (
    tester,
  ) async {
    const source = LibrarySource(
      libraryId: 'movies',
      libraryType: PlexLibraryType.movie,
      includeWatched: false,
      filters: {'genre': 'Comedy', 'sort': 'added:desc'},
    );
    final original = _channel(
      id: 'filtered',
      number: 12,
      name: 'Filtered',
      source: source,
    );
    final controller = _RecordingSaveController()
      ..channels = [original]
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..selectedLibraryIds = {'movies'}
      ..availableMedia = [
        _media(
          'comedy',
          title: 'Fresh comedy',
          libraryId: 'movies',
          genres: ['Comedy'],
        ),
        _media(
          'watched-comedy',
          title: 'Watched comedy',
          libraryId: 'movies',
          genres: ['Comedy'],
          viewed: true,
        ),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 matching programs'), findsOneWidget);
    expect(find.text('Fresh comedy'), findsWidgets);
    expect(find.text('Watched comedy'), findsNothing);
    await tester.ensureVisible(
      find.byKey(const Key('studio-filter-include-watched')),
    );
    await tester.tap(find.byKey(const Key('studio-filter-include-watched')));
    await tester.pump();
    expect(find.text('2 matching programs'), findsOneWidget);
    expect(find.text('Watched comedy'), findsOneWidget);
    await tester.tap(find.byKey(const Key('studio-filter-include-watched')));
    await tester.pump();
    expect(find.text('1 matching programs'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('studio-name')), 'Renamed');
    await _settleAirCheck(tester);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(controller.saved!.source.toJson(), source.toJson());
    expect(controller.saved!.builderKey, isNull);
  });

  testWidgets('retained unavailable filter facet is explicit and replaceable', (
    tester,
  ) async {
    final original = _channel(
      id: 'retained-filter',
      number: 13,
      name: 'Retained filter',
      source: const LibrarySource(
        libraryId: 'movies',
        libraryType: PlexLibraryType.movie,
        filters: {'genre': 'Gone'},
      ),
    );
    final controller = _RecordingSaveController()
      ..channels = [original]
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..selectedLibraryIds = {'movies'}
      ..availableMedia = [
        _media('comedy', libraryId: 'movies', genres: ['Comedy']),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gone (unavailable — retained)'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNull,
    );

    await _chooseDropdown(tester, 'studio-facet-genre', 'Any');
    expect(find.text('1 matching programs'), findsOneWidget);
    await _chooseDropdown(tester, 'studio-facet-genre', 'Comedy');
    await tester.enterText(find.byKey(const Key('studio-name')), 'Recovered');
    await tester.ensureVisible(find.text('Save changes'));
    await _settleAirCheck(tester);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect((controller.saved!.source as LibrarySource).filters, {
      'genre': 'Comedy',
    });
  });

  testWidgets('filter editor renders a bounded deterministic match sample', (
    tester,
  ) async {
    final controller = FixtureController()
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..selectedLibraryIds = {'movies'}
      ..availableMedia = [
        for (var index = 0; index < 7; index++)
          _media('sample-$index', title: 'Sample $index', libraryId: 'movies'),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collection or filter'));
    await tester.pumpAndSettle();
    for (var index = 0; index < 5; index++) {
      expect(find.text('Sample $index'), findsOneWidget);
    }
    expect(find.text('Sample 5'), findsNothing);
    expect(find.text('Showing 5 of 7 matching programs.'), findsOneWidget);
  });

  testWidgets('missing live sources and zero matches remain actionable', (
    tester,
  ) async {
    final controller = FixtureController()
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..selectedLibraryIds = {'movies'}
      ..availableMedia = [
        _media('drama', libraryId: 'movies', genres: ['Drama']),
      ];
    addTearDown(controller.dispose);
    for (final channel in [
      _channel(
        id: 'missing-library',
        number: 30,
        name: 'Missing library',
        source: const LibrarySource(
          libraryId: 'gone',
          libraryType: PlexLibraryType.movie,
        ),
      ),
      _channel(
        id: 'missing-playlist',
        number: 31,
        name: 'Missing playlist',
        source: const PlaylistSource('gone'),
      ),
      _channel(
        id: 'zero-match',
        number: 32,
        name: 'Zero match',
        source: const LibrarySource(
          libraryId: 'movies',
          libraryType: PlexLibraryType.movie,
          filters: {'genre': 'Comedy'},
        ),
      ),
    ]) {
      controller.channels = [channel];
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.editCustom, channel: channel),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save changes'),
            )
            .onPressed,
        isNull,
      );
    }
    expect(find.textContaining('match no playable programs'), findsOneWidget);
  });

  testWidgets('no inventory and scan states preserve retained programming', (
    tester,
  ) async {
    final retained = _channel(
      id: 'scan-retained',
      number: 33,
      name: 'Scan retained',
      source: const ManualSource([
        ChannelItem(
          id: 'retained',
          title: 'Retained',
          duration: Duration(minutes: 30),
        ),
      ]),
    );
    final controller = FixtureController()..channels = [retained];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: retained),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No usable programming is loaded'),
      findsOneWidget,
    );
    expect(find.text('Unavailable — retained until removed'), findsOneWidget);

    controller
      ..libraryScanStatus = LibraryScanStatus.scanning
      ..libraryScanCompletedItems = 4
      ..libraryScanTotalItems = 10;
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: retained),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('4 of 10 items loaded'), findsOneWidget);
    var statusSemantics = tester.widget<Semantics>(
      find.byKey(const Key('studio-inventory-status')),
    );
    expect(statusSemantics.properties.liveRegion, isTrue);

    for (final state in [
      LibraryScanStatus.cancelled,
      LibraryScanStatus.transientFailure,
    ]) {
      controller.libraryScanStatus = LibraryScanStatus.scanning;
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.editCustom, channel: retained),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('studio-inventory-status')), findsOneWidget);
      controller.libraryScanStatus = state;
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.editCustom, channel: retained),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('last usable programming'), findsOneWidget);
      expect(find.text('Retry in Generate lineup'), findsOneWidget);
      expect(find.text('Unavailable — retained until removed'), findsOneWidget);
      expect(find.byKey(const Key('studio-inventory-status')), findsOneWidget);
      statusSemantics = tester.widget<Semantics>(
        find.byKey(const Key('studio-inventory-status')),
      );
      expect(statusSemantics.properties.liveRegion, isTrue);
    }
  });

  testWidgets('picker browsing is ephemeral and count announcements settle', (
    tester,
  ) async {
    final key = GlobalKey<ChannelStudioViewState>();
    final original = _channel(
      id: 'browse',
      number: 40,
      name: 'Browse',
      source: const ManualSource([
        ChannelItem(
          id: 'episode',
          title: 'Pilot',
          duration: Duration(minutes: 30),
          showTitle: 'Alpha Show',
        ),
      ]),
    );
    final controller = FixtureController()
      ..channels = [original]
      ..libraries = const [
        PlexLibrary(id: 'shows', title: 'Shows', type: PlexLibraryType.show),
      ]
      ..selectedLibraryIds = {'shows'}
      ..availableMedia = [
        _media(
          'episode',
          title: 'Pilot',
          libraryId: 'shows',
          type: 'episode',
          showTitle: 'Alpha Show',
          genres: ['Comedy'],
        ),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChannelStudioView(
            key: key,
            controller: controller,
            mode: ChannelStudioMode.editCustom,
            channel: original,
            onBack: (_) async {},
            onSaved: (_) {},
            onDuplicate: (_) {},
            onOpenGenerateLineup: () async {},
            onTune: (_) async => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.dirty, isFalse);
    await _selectStudioStage(tester, 'studio-manual-browse-stage');
    await tester.enterText(find.byKey(const Key('studio-search')), 'alpha');
    await _chooseDropdown(tester, 'studio-manual-library', 'Shows');
    await _chooseDropdown(tester, 'studio-media-type', 'episode');
    await _chooseDropdown(tester, 'studio-facet-genre', 'Comedy');
    expect(key.currentState!.dirty, isFalse);
    await tester.enterText(find.byKey(const Key('studio-search')), 'none');
    await tester.pump(const Duration(milliseconds: 299));
    expect(
      tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((widget) => widget.properties.liveRegion == true)
          .map((widget) => widget.properties.label),
      isNot(contains('0 matching, 1 selected')),
    );
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((widget) => widget.properties.liveRegion == true)
          .map((widget) => widget.properties.label),
      contains('0 matching, 1 selected'),
    );
  });

  testWidgets('bounded bulk preserves matches outside the rendered window', (
    tester,
  ) async {
    final inventory = [for (var i = 0; i < 1200; i++) _media('item-$i')];
    final original = _channel(
      id: 'bounded',
      number: 20,
      name: 'Bounded',
      source: ManualSource([channelItemFor(inventory[150])]),
    );
    final controller = _RecordingSaveController()
      ..channels = [original]
      ..availableMedia = inventory;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();
    await _selectStudioStage(tester, 'studio-manual-browse-stage');
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Clear visible'))
          .onPressed,
      isNull,
    );
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Select visible'))
        .onPressed!();
    await tester.pump();
    expect(find.text('1200 matching, 101 selected'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Select visible'))
          .onPressed,
      isNull,
    );
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Clear visible'))
        .onPressed!();
    await tester.pump();
    expect(find.text('1200 matching, 1 selected'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('studio-name')),
      'Bounded kept',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save changes'));
    await _settleAirCheck(tester);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    final saved = controller.saved!;
    expect((saved.source as ManualSource).items.single.id, 'item-150');
    expect(
      (Channel.fromJson(saved.toJson()).source as ManualSource).items.single.id,
      'item-150',
    );
  });

  testWidgets('selection captures metadata across inventory loss', (
    tester,
  ) async {
    final controller = _RecordingSaveController()
      ..availableMedia = [_media('chosen', title: 'Fresh title')];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom),
    );
    await tester.pumpAndSettle();
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Select visible'))
        .onPressed!();
    await tester.pump();
    controller.availableMedia = const [];
    await tester.enterText(find.byKey(const Key('studio-search')), 'reload');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Captured');
    await _settleAirCheck(tester);
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();
    final item = (controller.saved!.source as ManualSource).items.single;
    expect(item.id, 'chosen');
    expect(item.title, 'Fresh title');
  });

  testWidgets(
    'rendered callbacks refresh inventory before selection and save across inventory changes',
    (tester) async {
      final selectionController = FixtureController()
        ..availableMedia = [_media('candidate-a', title: 'Candidate A')];
      addTearDown(selectionController.dispose);
      await tester.pumpWidget(
        _studio(selectionController, ChannelStudioMode.createCustom),
      );
      await tester.pumpAndSettle();
      final renderedSelection = tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('studio-result-candidate-a')),
          )
          .onChanged!;
      final renderedSelectVisible = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Select visible'))
          .onPressed!;

      selectionController
        ..connection = PlexConnection(
          uri: Uri.parse('https://replacement.invalid'),
          local: true,
          relay: false,
        )
        ..availableMedia = [_media('candidate-b', title: 'Candidate B')]
        ..notifyListeners();
      renderedSelection(true);
      renderedSelectVisible();
      await tester.pump();

      expect(find.text('1 matching, 0 selected'), findsOneWidget);
      expect(find.byKey(const Key('studio-result-candidate-a')), findsNothing);
      expect(
        find.byKey(const Key('studio-result-candidate-b')),
        findsOneWidget,
      );

      const retained = ChannelItem(
        id: 'retained',
        title: 'Retained snapshot',
        duration: Duration(minutes: 30),
      );
      final original = _channel(
        id: 'save-refresh',
        number: 47,
        name: 'Save refresh',
        source: const ManualSource([retained]),
      );
      final saveController = _RealSaveController()
        ..channels = [original]
        ..availableMedia = [_media('retained', title: 'Stale projection')];
      addTearDown(saveController.dispose);
      await tester.pumpWidget(
        _studio(
          saveController,
          ChannelStudioMode.editCustom,
          channel: original,
          studioKey: const ValueKey('save-refresh-studio'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('studio-name')),
        'Save refresh changed',
      );
      await _settleAirCheck(tester);
      final renderedSave = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed!;

      saveController
        ..connection = PlexConnection(
          uri: Uri.parse('https://empty.invalid'),
          local: true,
          relay: false,
        )
        ..availableMedia = const []
        ..notifyListeners();
      renderedSave();
      await tester.pump();

      expect(saveController.channels.single.name, 'Save refresh');
      expect(
        find.text(
          'Air Check must verify this schedule before the channel can be saved.',
        ),
        findsOneWidget,
      );

      await _settleAirCheck(tester);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      final saved = saveController.channels.single;
      expect(saved.name, 'Save refresh changed');
      expect(
        (saved.source as ManualSource).items.single.toJson(),
        retained.toJson(),
      );
    },
  );

  testWidgets(
    'rendered Save waits for Air Check after content generation changes',
    (tester) async {
      final original = _channel(
        id: 'generation-save',
        number: 48,
        name: 'Generation save',
        source: ManualSource([_itemForHealth(1)]),
      );
      final controller = _RecordingSaveController()
        ..channels = [original]
        ..availableMedia = [_media('program-1', title: 'First metadata')];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.editCustom, channel: original),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('studio-name')),
        'Generation save changed',
      );
      await _settleAirCheck(tester);
      final renderedSave = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed!;

      controller.availableMedia = [
        _media(
          'program-1',
          title: 'Replacement metadata',
          duration: const Duration(minutes: 45),
        ),
      ];
      controller.generation++;
      controller.notifyListeners();
      renderedSave();

      expect(controller.saved, isNull);
      await tester.pump();
      expect(
        find.text(
          'Air Check must verify this schedule before the channel can be saved.',
        ),
        findsOneWidget,
      );
      await _settleAirCheck(tester);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      final saved = (controller.saved!.source as ManualSource).items.single;
      expect(saved.title, 'Replacement metadata');
      expect(saved.duration, const Duration(minutes: 45));
    },
  );

  testWidgets('duplicate IDs render once and save media-first metadata', (
    tester,
  ) async {
    final controller = _RecordingSaveController()
      ..availableMedia = [_media('shared', title: 'Library winner')]
      ..availablePlaylists = [
        PlexPlaylist(
          id: 'playlist',
          title: 'Playlist',
          items: [_media('shared', title: 'Playlist duplicate')],
        ),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('studio-result-shared')), findsOneWidget);
    expect(find.text('Library winner'), findsOneWidget);
    expect(find.text('Playlist duplicate'), findsNothing);
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Select visible'))
        .onPressed!();
    await tester.pump();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Winner');
    await _settleAirCheck(tester);
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();
    expect(
      (controller.saved!.source as ManualSource).items.single.title,
      'Library winner',
    );
  });

  testWidgets('Studio offers only the real public playable projection', (
    tester,
  ) async {
    final valid = PlexMediaItem(
      id: 'multipart',
      title: 'Multipart',
      type: 'movie',
      duration: const Duration(minutes: 2),
      parts: [
        PlexMediaPart(path: '/one'),
        PlexMediaPart(path: '/two', duration: const Duration(minutes: 1)),
      ],
    );
    final controller = FixtureController()
      ..availableMedia = [
        valid,
        _media('shared', title: 'Media winner'),
        const PlexMediaItem(
          id: 'no-parts',
          title: 'No parts',
          type: 'movie',
          duration: Duration(minutes: 1),
        ),
        PlexMediaItem(
          id: 'zero',
          title: 'Zero',
          type: 'movie',
          duration: Duration.zero,
          parts: [PlexMediaPart(path: '/zero')],
        ),
        PlexMediaItem(
          id: 'empty-path',
          title: 'Empty path',
          type: 'movie',
          duration: const Duration(minutes: 1),
          parts: [PlexMediaPart(path: '')],
        ),
        PlexMediaItem(
          id: 'hostile',
          title: 'Hostile',
          type: 'movie',
          duration: const Duration(minutes: 1),
          parts: [
            PlexMediaPart(path: '/safe'),
            PlexMediaPart(path: 'https://hostile.invalid/later'),
          ],
        ),
      ]
      ..availablePlaylists = [
        PlexPlaylist(
          id: 'playlist',
          title: 'Playlist',
          items: [_media('shared', title: 'Playlist duplicate')],
        ),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('studio-result-multipart')), findsOneWidget);
    expect(
      controller.playableInventory.media.first.parts.first.duration,
      isNull,
    );
    expect(find.byKey(const Key('studio-result-shared')), findsOneWidget);
    expect(find.text('Media winner'), findsOneWidget);
    for (final id in ['no-parts', 'zero', 'empty-path', 'hostile']) {
      expect(find.byKey(Key('studio-result-$id')), findsNothing);
    }

    controller.connection = null;
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.textContaining('No usable programming'), findsOneWidget);
  });

  testWidgets('unavailable manual records persist but do not schedule', (
    tester,
  ) async {
    final original = _channel(
      id: 'retained-order',
      number: 22,
      name: 'Retained order',
      source: const ManualSource([
        ChannelItem(
          id: 'missing',
          title: 'Missing',
          duration: Duration(minutes: 30),
        ),
        ChannelItem(
          id: 'available',
          title: 'Old title',
          duration: Duration(minutes: 30),
        ),
      ]),
    );
    final controller = _RecordingSaveController()
      ..channels = [original]
      ..availableMedia = [_media('available', title: 'Fresh title')];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Retained');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    final source = controller.saved!.source as ManualSource;
    expect(source.items.map((item) => item.id), ['missing', 'available']);
    expect(source.items.last.title, 'Fresh title');
    expect(
      resolveContent(source, controller.availableMedia).map((item) => item.id),
      ['available'],
    );
  });

  testWidgets(
    'repeated persisted manual IDs keep occurrence focus and snapshots',
    (tester) async {
      final studioKey = GlobalKey<ChannelStudioViewState>();
      const first = ChannelItem(
        id: 'repeat',
        title: 'First snapshot',
        duration: Duration(minutes: 20),
        summary: 'first metadata',
      );
      const second = ChannelItem(
        id: 'repeat',
        title: 'Second snapshot',
        duration: Duration(minutes: 30),
        summary: 'second metadata',
      );
      const third = ChannelItem(
        id: 'repeat',
        title: 'Third snapshot',
        duration: Duration(minutes: 40),
        summary: 'third metadata',
      );
      final original = _channel(
        id: 'repeated-manual',
        number: 24,
        name: 'Repeated manual',
        source: const ManualSource([first, second, third]),
      );
      final controller = _RecordingSaveController()..channels = [original];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _studio(
          controller,
          ChannelStudioMode.editCustom,
          channel: original,
          studioKey: studioKey,
        ),
      );
      await tester.pumpAndSettle();

      final firstRow = find.byKey(const Key('studio-rundown-repeat'));
      final secondRow = find.ancestor(
        of: find.text('Second snapshot'),
        matching: find.byType(ListTile),
      );
      final thirdRow = find.ancestor(
        of: find.text('Third snapshot'),
        matching: find.byType(ListTile),
      );
      expect(firstRow, findsOneWidget);
      expect(secondRow, findsOneWidget);
      expect(thirdRow, findsOneWidget);
      expect(
        tester.widget<ListTile>(secondRow).key,
        isNot(tester.widget<ListTile>(thirdRow).key),
      );
      final firstFocus = tester
          .widget<Focus>(
            find.ancestor(of: firstRow, matching: find.byType(Focus)).first,
          )
          .focusNode!;
      final thirdFocus = tester
          .widget<Focus>(
            find.ancestor(of: thirdRow, matching: find.byType(Focus)).first,
          )
          .focusNode!;
      expect(identical(firstFocus, thirdFocus), isFalse);

      thirdFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(thirdFocus));
      expect(studioKey.currentState!.dirty, isTrue);
      expect(
        tester.getTopLeft(thirdRow).dy,
        lessThan(tester.getTopLeft(secondRow).dy),
      );

      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip(
                'Remove Second snapshot from channel Repeated manual',
              ),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed!();
      await tester.pump();
      expect(secondRow, findsNothing);
      expect(firstRow, findsOneWidget);
      expect(thirdRow, findsOneWidget);
      expect(FocusManager.instance.primaryFocus, same(thirdFocus));

      await tester.enterText(
        find.byKey(const Key('studio-name')),
        'Repeated manual saved',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Save changes'));
      await _settleAirCheck(tester);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final saved = controller.saved!;
      final savedItems = (saved.source as ManualSource).items;
      expect(savedItems.map((item) => item.toJson()), [
        first.toJson(),
        third.toJson(),
      ]);

      controller
        ..channels = [saved]
        ..saved = null;
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.editCustom, channel: saved),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('studio-name')),
        'Repeated manual reloaded',
      );
      await tester.pump();
      await _settleAirCheck(tester);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        (controller.saved!.source as ManualSource).items.map(
          (item) => item.toJson(),
        ),
        [first.toJson(), third.toJson()],
      );
    },
  );

  testWidgets(
    'identical unavailable occurrences expose distinct labels and actions',
    (tester) async {
      const item = ChannelItem(
        id: 'same-id',
        title: 'Same title',
        duration: Duration(minutes: 30),
      );
      final original = _channel(
        id: 'same-occurrences',
        number: 25,
        name: 'Same occurrences',
        source: const ManualSource([item, item]),
      );
      final controller = _RecordingSaveController()..channels = [original];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.editCustom, channel: original),
      );
      await tester.pumpAndSettle();

      final rows = find.descendant(
        of: find.byKey(const Key('studio-rundown')),
        matching: find.byType(ListTile),
      );
      expect(rows, findsNWidgets(2));
      final firstRow = rows.at(0);
      final secondRow = rows.at(1);
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(of: firstRow, matching: find.byType(Semantics))
                  .first,
            )
            .properties
            .label,
        'Same title, item 1 of 2, unavailable — retained until removed',
      );
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(of: secondRow, matching: find.byType(Semantics))
                  .first,
            )
            .properties
            .label,
        'Same title, item 2 of 2, unavailable — retained until removed',
      );
      expect(
        find.text('Unavailable — retained until removed'),
        findsNWidgets(2),
      );
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.text('2 of 2'), findsOneWidget);
      expect(
        find.byTooltip(
          'Move Same title, item 1 of 2 later in channel Same occurrences',
        ),
        findsOneWidget,
      );
      expect(
        find.byTooltip(
          'Remove Same title, item 2 of 2 from channel Same occurrences',
        ),
        findsOneWidget,
      );

      final secondKey = tester.widget<ListTile>(secondRow).key!;
      final secondFocus = tester
          .widget<Focus>(
            find.ancestor(of: secondRow, matching: find.byType(Focus)).first,
          )
          .focusNode!;
      secondFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      final movedSecond = find.byKey(secondKey);
      expect(FocusManager.instance.primaryFocus, same(secondFocus));
      expect(
        secondFocus.debugLabel,
        'Selected program Same title, item 1 of 2',
      );
      expect(
        tester.getTopLeft(movedSecond).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('studio-rundown-same-id'))).dy,
        ),
      );

      tester
          .widget<IconButton>(
            find.descendant(
              of: movedSecond,
              matching: find.ancestor(
                of: find.byTooltip(
                  'Move Same title, item 1 of 2 later in channel Same occurrences',
                ),
                matching: find.byType(IconButton),
              ),
            ),
          )
          .onPressed!();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(secondFocus));
      expect(
        tester.getTopLeft(movedSecond).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('studio-rundown-same-id'))).dy,
        ),
      );
    },
  );

  testWidgets('successful save refreshes every retained occurrence snapshot', (
    tester,
  ) async {
    const stored = ChannelItem(
      id: 'repeat-refresh',
      title: 'Stored title',
      duration: Duration(minutes: 20),
    );
    final original = _channel(
      id: 'refresh-occurrences',
      number: 26,
      name: 'Refresh occurrences',
      source: const ManualSource([stored, stored]),
    );
    final controller = _RecordingSaveController()
      ..channels = [original]
      ..availableMedia = [
        _media(
          'repeat-refresh',
          title: 'Fresh title',
          duration: const Duration(minutes: 45),
        ),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();
    final oldRows = find.descendant(
      of: find.byKey(const Key('studio-rundown')),
      matching: find.byType(ListTile),
    );
    final occurrenceFocus = tester
        .widget<Focus>(
          find.ancestor(of: oldRows.at(1), matching: find.byType(Focus)).first,
        )
        .focusNode!;

    await tester.enterText(
      find.byKey(const Key('studio-name')),
      'Refresh occurrences saved',
    );
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(
      (controller.saved!.source as ManualSource).items.map(
        (item) => item.title,
      ),
      ['Fresh title', 'Fresh title'],
    );

    controller.availableMedia = [];
    controller.generation++;
    controller.saved = null;
    await tester.enterText(
      find.byKey(const Key('studio-name')),
      'Refresh occurrences saved again',
    );
    await tester.pump();
    await _settleAirCheck(tester);
    final newRows = find.descendant(
      of: find.byKey(const Key('studio-rundown')),
      matching: find.byType(ListTile),
    );
    expect(
      tester
          .widget<Focus>(
            find
                .ancestor(of: newRows.at(1), matching: find.byType(Focus))
                .first,
          )
          .focusNode,
      same(occurrenceFocus),
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    final savedAgain = (controller.saved!.source as ManualSource).items;
    expect(savedAgain.map((item) => item.title), [
      'Fresh title',
      'Fresh title',
    ]);
    expect(savedAgain.map((item) => item.duration), [
      const Duration(minutes: 45),
      const Duration(minutes: 45),
    ]);
  });

  testWidgets('conflict reload retires repeated occurrence focus ownership', (
    tester,
  ) async {
    const oldItem = ChannelItem(
      id: 'reload-repeat',
      title: 'Old repeated title',
      duration: Duration(minutes: 30),
    );
    const newItem = ChannelItem(
      id: 'reload-repeat',
      title: 'Reloaded repeated title',
      duration: Duration(minutes: 40),
    );
    final original = _channel(
      id: 'reload-occurrences',
      number: 27,
      name: 'Reload occurrences',
      source: const ManualSource([oldItem, oldItem]),
    );
    final external = _channel(
      id: original.id,
      number: original.number,
      name: 'External occurrences',
      source: const ManualSource([newItem, newItem]),
    );
    final controller = _ExpectedBaseController()..channels = [original];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();
    final oldRows = find.descendant(
      of: find.byKey(const Key('studio-rundown')),
      matching: find.byType(ListTile),
    );
    final oldFirst = tester
        .widget<Focus>(
          find.ancestor(of: oldRows.at(0), matching: find.byType(Focus)).first,
        )
        .focusNode!;
    final oldSecond = tester
        .widget<Focus>(
          find.ancestor(of: oldRows.at(1), matching: find.byType(Focus)).first,
        )
        .focusNode!;

    controller.channels = [external];
    await tester.enterText(find.byKey(const Key('studio-name')), 'My conflict');
    await _settleAirCheck(tester);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use saved version…'));
    await tester.tap(find.text('Use saved version…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use saved version'));
    await tester.pump();
    expect(() => oldFirst.addListener(() {}), throwsFlutterError);
    expect(() => oldSecond.addListener(() {}), throwsFlutterError);

    final newRows = find.descendant(
      of: find.byKey(const Key('studio-rundown')),
      matching: find.byType(ListTile),
    );
    expect(newRows, findsNWidgets(2));
    final newFirst = tester
        .widget<Focus>(
          find.ancestor(of: newRows.at(0), matching: find.byType(Focus)).first,
        )
        .focusNode!;
    final newSecond = tester
        .widget<Focus>(
          find.ancestor(of: newRows.at(1), matching: find.byType(Focus)).first,
        )
        .focusNode!;
    expect(identical(newFirst, newSecond), isFalse);
    newFirst.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(newFirst));
    newSecond.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(newSecond));
  });

  testWidgets('new preview anchor and seed persist exactly through reload', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 27, 13, 45);
    final controller = _RecordingSaveController()
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..selectedLibraryIds = {'movies'}
      ..availableMedia = [_media('movie', libraryId: 'movies')];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom, clock: () => now),
    );
    await tester.pumpAndSettle();
    final previewed = controller.loaded!;
    await tester.enterText(find.byKey(const Key('studio-name')), 'Persisted');
    await tester.pump();
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();
    final first = controller.saved!;
    expect(first.anchor, previewed.anchor);
    expect(first.shuffleSeed, previewed.shuffleSeed);
    expect(first.anchor, now);

    controller
      ..channels = [first]
      ..saved = null;
    await tester.pumpWidget(
      _studio(
        controller,
        ChannelStudioMode.editCustom,
        channel: first,
        clock: () => now.add(const Duration(days: 10)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Reloaded');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(controller.saved!.anchor, first.anchor);
    expect(controller.saved!.shuffleSeed, first.shuffleSeed);
  });

  testWidgets(
    'new schedule identity starts when its source first becomes valid',
    (tester) async {
      var now = DateTime.utc(2026, 8, 27, 9);
      final validAt = now.add(const Duration(hours: 4));
      final controller = _RecordingSaveController()
        ..availableMedia = [_media('movie')];
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.createCustom, clock: () => now),
      );
      await tester.pumpAndSettle();
      expect(controller.loaded, isNull);

      now = validAt;
      await tester.ensureVisible(find.byKey(const Key('studio-result-movie')));
      await tester.tap(find.byKey(const Key('studio-result-movie')));
      await _settleAirCheck(tester);
      final previewed = controller.loaded!;
      expect(previewed.anchor, validAt);
      expect(previewed.shuffleSeed, previewed.id.hashCode);
      expect(previewed.shuffleSeed, isNot(0));

      await tester.enterText(
        find.byKey(const Key('studio-name')),
        'Valid later',
      );
      await tester.pump();
      await tester.tap(find.text('Save channel'));
      await tester.pumpAndSettle();
      final saved = controller.saved!;
      expect(saved.anchor, previewed.anchor);
      expect(saved.shuffleSeed, previewed.shuffleSeed);

      controller
        ..channels = [saved]
        ..saved = null;
      now = validAt.add(const Duration(days: 3));
      await tester.pumpWidget(
        _studio(
          controller,
          ChannelStudioMode.editCustom,
          channel: saved,
          clock: () => now,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('studio-name')), 'Reloaded');
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(controller.saved!.anchor, validAt);
      expect(controller.saved!.shuffleSeed, saved.shuffleSeed);
    },
  );

  testWidgets('stale valid Air Check cannot commit a changed draft identity', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 27, 14);
    final controller = _ControlledStudioController()
      ..availableMedia = [_media('first'), _media('second')];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom, clock: () => now),
    );
    await tester.pumpAndSettle();
    tester
        .widget<CheckboxListTile>(find.byKey(const Key('studio-result-first')))
        .onChanged!(true);
    await tester.pump();
    await tester.pump(channelAirCheckDebounce);
    expect(controller.pending, hasLength(1));
    final firstRequest = controller.pending.single.channel;
    final addSecond = tester
        .widget<CheckboxListTile>(find.byKey(const Key('studio-result-second')))
        .onChanged!;

    addSecond(true);
    await tester.runAsync(() async {
      controller.completeNext();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('studio-name')),
      'Current valid',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save channel'),
          )
          .onPressed,
      isNull,
    );
    await tester.pump(channelAirCheckDebounce);

    expect(controller.pending, hasLength(1));
    final currentRequest = controller.pending.single.channel;
    expect((firstRequest.source as ManualSource).items.map((item) => item.id), [
      'first',
    ]);
    expect(
      (currentRequest.source as ManualSource).items.map((item) => item.id),
      ['first', 'second'],
    );
    await tester.runAsync(() async {
      controller.completeNext();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();

    expect(controller.saved!.anchor, currentRequest.anchor);
    expect(controller.saved!.shuffleSeed, currentRequest.shuffleSeed);
  });

  testWidgets(
    'stale retained-off-air Air Check cannot commit a changed draft identity',
    (tester) async {
      final now = DateTime.utc(2026, 8, 27, 15);
      final controller = _ControlledStudioController()
        ..availableMedia = [_media('first'), _media('second')];
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.createCustom, clock: () => now),
      );
      await tester.pumpAndSettle();
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('studio-result-first')),
          )
          .onChanged!(true);
      await tester.pump();
      await tester.pump(channelAirCheckDebounce);
      expect(controller.pending, hasLength(1));
      final addSecond = tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('studio-result-second')),
          )
          .onChanged!;

      addSecond(true);
      await tester.runAsync(() async {
        controller.completeNext(noContent: true);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('studio-name')),
        'Current after retained',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save channel'),
            )
            .onPressed,
        isNull,
      );
      await tester.pump(channelAirCheckDebounce);

      expect(controller.pending, hasLength(1));
      final currentRequest = controller.pending.single.channel;
      await tester.runAsync(() async {
        controller.completeNext();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Save channel'));
      await tester.pumpAndSettle();

      expect(controller.saved!.anchor, currentRequest.anchor);
      expect(controller.saved!.shuffleSeed, currentRequest.shuffleSeed);
    },
  );

  testWidgets(
    'large selected rundown snapshots playable inventory once per build',
    (tester) async {
      final retained = List.generate(
        1200,
        (index) => ChannelItem(
          id: 'selected-$index',
          title: 'Selected $index',
          duration: const Duration(minutes: 30),
        ),
      );
      final original = _channel(
        id: 'large-rundown',
        number: 25,
        name: 'Large rundown',
        source: ManualSource(retained),
      );
      final controller = _CountingInventoryController()
        ..channels = [original]
        ..availableMedia = List.generate(
          1199,
          (index) => _media('selected-${index + 1}'),
        );
      addTearDown(controller.dispose);
      controller.playableInventoryReads = 0;

      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.editCustom, channel: original),
      );
      await tester.pumpAndSettle();

      expect(find.text('1199 matching, 1200 selected'), findsOneWidget);
      expect(find.text('Unavailable — retained until removed'), findsOneWidget);
      expect(controller.playableInventoryReads, lessThanOrEqualTo(4));

      final readsBeforeSearch = controller.playableInventoryReads;
      await _selectStudioStage(tester, 'studio-manual-browse-stage');
      await tester.enterText(find.byKey(const Key('studio-search')), '1198');
      await tester.pump();
      expect(
        controller.playableInventoryReads - readsBeforeSearch,
        lessThanOrEqualTo(2),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        controller.playableInventoryReads - readsBeforeSearch,
        lessThanOrEqualTo(3),
      );

      await _selectStudioStage(tester, 'studio-manual-rundown-stage');
      await tester.ensureVisible(find.byKey(const Key('studio-rundown')));
      await tester.pump();
      final readsBeforeScrolling = controller.playableInventoryReads;
      final rundownScrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('studio-rundown')),
          matching: find.byType(Scrollable),
        ),
      );
      final maximum = rundownScrollable.position.maxScrollExtent;
      for (final fraction in [0.2, 0.4, 0.6, 0.8, 1.0]) {
        rundownScrollable.position.jumpTo(maximum * fraction);
        await tester.pump();
      }
      expect(controller.playableInventoryReads, readsBeforeScrolling);
    },
  );

  testWidgets('Channels schedule health remains lazy for 1000 rows', (
    tester,
  ) async {
    final controller = _HealthController()
      ..stage = SetupStage.ready
      ..channels = [
        for (var index = 1; index <= 1000; index++)
          _channel(
            id: 'health-$index',
            number: index,
            name: 'Health $index',
            source: ManualSource([_itemForHealth(index)]),
          ),
      ];
    final fixture = UiFixture(controller: controller);
    addTearDown(controller.dispose);
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await openDestination(tester, 'Channels');
    await tester.pumpAndSettle();

    expect(controller.requests, greaterThan(0));
    expect(controller.requests, lessThanOrEqualTo(32));
    expect(find.byKey(const ValueKey('channel-row-health-1000')), findsNothing);
  });

  testWidgets('large Channels viewport reaches a quiescent bounded cache', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 5000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = _ControlledHealthController()
      ..stage = SetupStage.ready
      ..channels = [
        for (var index = 1; index <= 1000; index++)
          _channel(
            id: 'viewport-$index',
            number: index,
            name: 'Viewport $index',
            source: ManualSource([_itemForHealth(index)]),
          ),
      ];
    final fixture = UiFixture(controller: controller);
    addTearDown(controller.dispose);
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    controller.completePending();
    await tester.pump();
    controller.resetMeasurements();
    await openDestination(tester, 'Channels');
    await tester.pump();

    var stablePasses = 0;
    var previousRequests = -1;
    for (var pass = 0; pass < 100 && stablePasses < 2; pass++) {
      controller.completePending();
      await tester.pump();
      if (controller.pending.isEmpty &&
          controller.requests == previousRequests) {
        stablePasses++;
      } else {
        stablePasses = 0;
      }
      previousRequests = controller.requests;
    }
    expect(controller.requests, greaterThan(32));
    expect(controller.requests, lessThan(1000));
    expect(controller.pending, isEmpty);
    expect(controller.maximumActive, lessThanOrEqualTo(2));

    final settledRequests = controller.requests;
    await tester.pump();
    await tester.pump();
    expect(controller.requests, settledRequests);
    expect(
      find.byKey(const ValueKey('channel-row-viewport-40')),
      findsOneWidget,
    );
  });

  testWidgets('Channels health supersedes stale work and recovers issues', (
    tester,
  ) async {
    final controller = _ControlledHealthController()
      ..stage = SetupStage.ready
      ..channels = [
        for (var index = 1; index <= 2; index++)
          _channel(
            id: 'controlled-$index',
            number: index,
            name: 'Controlled $index',
            source: ManualSource([_itemForHealth(index)]),
          ),
      ];
    final fixture = UiFixture(controller: controller);
    addTearDown(controller.dispose);
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    controller.completePending();
    await tester.pump();
    controller.resetMeasurements();
    await openDestination(tester, 'Channels');
    await tester.pump();
    expect(controller.pending, hasLength(2));
    expect(controller.maximumActive, lessThanOrEqualTo(2));

    controller.channels = [
      Channel.fromJson({
        ...controller.channels[0].toJson(),
        'name': 'Controlled 1 latest',
      }),
      controller.channels[1],
    ];
    controller.notifyListeners();
    await tester.pump();
    expect(
      controller.pending.where((call) => call.channel.id == 'controlled-1'),
      hasLength(1),
    );
    controller.complete('controlled-1', error: StateError('stale failure'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(
      controller.pending
          .singleWhere((call) => call.channel.id == 'controlled-1')
          .channel
          .name,
      'Controlled 1 latest',
    );
    expect(find.textContaining('Schedule issue'), findsNothing);

    controller.complete('controlled-2');
    controller.complete('controlled-1');
    await tester.pump();
    controller.channels = [
      ...controller.channels,
      for (var index = 3; index <= 4; index++)
        _channel(
          id: 'controlled-$index',
          number: index,
          name: 'Controlled $index',
          source: ManualSource([_itemForHealth(index)]),
        ),
    ];
    controller.generation++;
    controller.notifyListeners();
    await tester.pump();
    expect(controller.pending, hasLength(2));

    controller.channels = [
      controller.channels[0],
      controller.channels[1],
      controller.channels[2],
      Channel.fromJson({
        ...controller.channels[3].toJson(),
        'name': 'Controlled 4 middle',
      }),
    ];
    controller.notifyListeners();
    await tester.pump();
    controller.channels = [
      controller.channels[0],
      controller.channels[1],
      controller.channels[2],
      Channel.fromJson({
        ...controller.channels[3].toJson(),
        'name': 'Controlled 4 latest',
      }),
    ];
    controller.notifyListeners();
    await tester.pump();
    controller.complete('controlled-1');
    await tester.pump();
    await tester.pump();
    controller.complete('controlled-2');
    await tester.pump();
    await tester.pump();
    expect(
      controller.pending
          .singleWhere((call) => call.channel.id == 'controlled-4')
          .channel
          .name,
      'Controlled 4 latest',
    );
    controller.complete('controlled-4', error: StateError('health failure'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining('Schedule issue — open this channel to recover'),
      findsOneWidget,
    );

    controller.generation++;
    controller.notifyListeners();
    await tester.pump();
    for (var pass = 0; pass < 6 && controller.pending.isNotEmpty; pass++) {
      controller.completePending();
      await tester.pump();
    }
    expect(controller.pending, isEmpty);
    expect(find.textContaining('Schedule issue'), findsNothing);
    expect(controller.maximumActive, lessThanOrEqualTo(2));
  });

  testWidgets('generic unavailable worker failure keeps Save disabled', (
    tester,
  ) async {
    final original = _channel(
      id: 'generic-failure',
      number: 31,
      name: 'Generic failure',
      source: ManualSource([_itemForHealth(1)]),
    );
    final controller = _ScheduleFailureController(
      StateError('Schedule worker is unavailable'),
    )..channels = [original];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('could not verify'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('failed saved-schedule comparison blocks Save until retry', (
    tester,
  ) async {
    final original = _channel(
      id: 'comparison-failure',
      number: 34,
      name: 'Comparison failure',
      source: ManualSource([_itemForHealth(1), _itemForHealth(2)]),
    );
    final controller = _RecordingSaveController()
      ..channels = [original]
      ..availableMedia = [
        _media('program-1', title: 'Program 1'),
        _media('program-2', title: 'Program 2'),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();

    controller.nextScheduleFailure = StateError('baseline worker unavailable');
    controller.generation++;
    controller.notifyListeners();
    tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip(
              'Move Program 2 earlier in channel Comparison failure',
            ),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!();
    await _settleAirCheck(tester);

    expect(find.text('2 playable'), findsOneWidget);
    expect(find.textContaining('could not compare this draft'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNull,
    );

    await tester.ensureVisible(find.text('Retry comparison'));
    await tester.tap(find.text('Retry comparison'));
    await _settleAirCheck(tester);
    expect(find.textContaining('could not compare this draft'), findsNothing);
    expect(find.byKey(const Key('air-check-on-now-warning')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('off-air saved programming can be repaired and saved', (
    tester,
  ) async {
    final original = _channel(
      id: 'off-air-repair',
      number: 35,
      name: 'Off-air repair',
      source: ManualSource([_itemForHealth(1), _itemForHealth(2)]),
    );
    final controller = _RecordingSaveController()
      ..channels = [original]
      ..availableMedia = [
        _media('program-1', title: 'Program 1'),
        _media('program-2', title: 'Program 2'),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();

    controller.nextScheduleFailure = const ScheduleBuildException(
      ScheduleFailureReason.noContent,
    );
    controller.generation++;
    controller.notifyListeners();
    tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip(
              'Move Program 2 earlier in channel Off-air repair',
            ),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!();
    await _settleAirCheck(tester);

    expect(find.byKey(const Key('air-check-on-now-warning')), findsOneWidget);
    expect(find.textContaining('could not compare this draft'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('retained empty manual resolution remains explicitly saveable', (
    tester,
  ) async {
    final original = _channel(
      id: 'retained-off-air',
      number: 32,
      name: 'Retained off air',
      source: ManualSource([_itemForHealth(1)]),
    );
    final controller = _RecordingSaveController()
      ..scheduleFailure = const ScheduleBuildException(
        ScheduleFailureReason.noContent,
      )
      ..channels = [original];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('explicitly off air'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('studio-name')), 'Retained');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(controller.saved?.name, 'Retained');
  });

  testWidgets('successful save becomes the next warning baseline', (
    tester,
  ) async {
    final original = _channel(
      id: 'warning-baseline',
      number: 33,
      name: 'Warning baseline',
      source: ManualSource([_itemForHealth(1), _itemForHealth(2)]),
    );
    final controller = _RecordingSaveController()
      ..channels = [original]
      ..availableMedia = [
        _media('program-1', title: 'Program 1'),
        _media('program-2', title: 'Program 2'),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();

    tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip(
              'Move Program 2 earlier in channel Warning baseline',
            ),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!();
    await _settleAirCheck(tester);
    expect(find.byKey(const Key('air-check-on-now-warning')), findsOneWidget);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('air-check-on-now-warning')), findsNothing);

    tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip(
              'Move Program 1 earlier in channel Warning baseline',
            ),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!();
    await _settleAirCheck(tester);
    expect(find.byKey(const Key('air-check-on-now-warning')), findsOneWidget);
  });

  testWidgets('Studio reflows across the locked viewport and DPR matrix', (
    tester,
  ) async {
    final controller = _RecordingSaveController()
      ..availableMedia = [_media('one'), _media('two')];
    addTearDown(controller.dispose);
    for (final size in const [
      Size(800, 600),
      Size(1280, 720),
      Size(1360, 840),
      Size(1600, 900),
      Size(1920, 1080),
      Size(3840, 2160),
    ]) {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.createCustom),
      );
      await _settleAirCheck(tester);
      expect(tester.takeException(), isNull, reason: 'viewport $size');
      expect(find.text('Air Check'), findsOneWidget);
      expect(find.byKey(const Key('studio-programming')), findsOneWidget);
      expect(find.byKey(const Key('studio-station')), findsOneWidget);
      expect(find.text('Save channel'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('lineup-page-content'))).width,
        lessThanOrEqualTo(1120),
      );
      final programmingTop = tester.getTopLeft(
        find.byKey(const Key('studio-programming')),
      );
      final stationTop = tester.getTopLeft(
        find.byKey(const Key('studio-station')),
      );
      if (size.width < 900) {
        expect(programmingTop.dy, lessThan(stationTop.dy));
        expect(_studioScrollOffset(tester), 0);
        for (final finder in [
          find.text('Draft'),
          find.byKey(const Key('channel-air-check')),
          find.text('Programming'),
          find.text('Save channel'),
        ]) {
          _expectIntersectsViewport(tester, finder, size);
        }
        await tester.ensureVisible(find.byKey(const Key('studio-name')));
        await tester.pump();
        _expectIntersectsViewport(
          tester,
          find.byKey(const Key('studio-name')),
          size,
        );
        _expectIntersectsViewport(tester, find.text('Save channel'), size);
      } else {
        expect(programmingTop.dy, stationTop.dy);
      }
    }
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(3840, 2160);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.createCustom),
    );
    await _settleAirCheck(tester);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('lineup-page-content'))).width,
      lessThanOrEqualTo(1120),
    );
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  });

  testWidgets('200 percent text keeps Studio fields and actions unclipped', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = _RecordingSaveController()
      ..availableMedia = [_media('one'), _media('two')]
      ..libraryScanStatus = LibraryScanStatus.transientFailure;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(
        controller,
        ChannelStudioMode.createCustom,
        textScaler: const TextScaler.linear(2),
      ),
    );
    await _settleAirCheck(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('channel-air-check')), findsOneWidget);
    for (final finder in [
      find.text('Back to Channels'),
      find.text('Save channel'),
    ]) {
      _expectFitsHorizontally(tester, finder, const Size(800, 600));
    }
    for (final finder in [
      find.textContaining('Library loading failed'),
      find.text('Retry in Generate lineup'),
      find.byKey(const Key('studio-name')),
      find.byKey(const Key('studio-number')),
    ]) {
      await tester.ensureVisible(finder);
      await tester.pump();
      _expectIntersectsViewport(tester, finder, const Size(800, 600));
      _expectFitsHorizontally(tester, finder, const Size(800, 600));
      expect(tester.takeException(), isNull);
    }
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save channel'))
        .onPressed!();
    await tester.pump();
    _expectFitsHorizontally(
      tester,
      find.text('Enter a channel name.'),
      const Size(800, 600),
    );
  });

  testWidgets('Air Check program focus uses the configured focus border', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final duration in const [
      Duration(minutes: 30),
      Duration(minutes: 1),
    ]) {
      final widths = <double>[];
      for (final largeFocus in [false, true]) {
        final program = ChannelItem(
          id: 'focus-program',
          title: 'Focus program',
          duration: duration,
        );
        final channel = _channel(
          id: 'focus-channel',
          number: 42,
          name: 'Focus channel',
          source: ManualSource([program]),
        );
        final controller = _RecordingSaveController()
          ..channels = [channel]
          ..availableMedia = [_media('focus-program', duration: duration)];
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _studio(
            controller,
            ChannelStudioMode.editCustom,
            channel: channel,
            clock: () => DateTime.utc(2026, 1, 1, 1),
            theme: LineupTheme.forName(
              LineupThemeName.emberSteel,
              largeFocusIndicators: largeFocus,
            ),
          ),
        );
        await _settleAirCheck(tester);
        final backFocus = tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Back to Channels'),
            )
            .focusNode!;
        backFocus.requestFocus();
        await tester.pump();
        final buttonFinder = find.descendant(
          of: find.byKey(const Key('channel-air-check')),
          matching: find.byType(OutlinedButton),
        );
        final inspectedButton = buttonFinder.first;
        for (var step = 0; step < 20; step++) {
          final focus = FocusManager.instance.primaryFocus!;
          if (_focusNodeIsInside(focus, inspectedButton)) break;
          focus.nextFocus();
          await tester.pump();
        }
        expect(
          _focusNodeIsInside(
            FocusManager.instance.primaryFocus!,
            inspectedButton,
          ),
          isTrue,
        );
        var button = tester.widget<OutlinedButton>(inspectedButton);
        if (duration == const Duration(minutes: 1)) {
          expect(button.style!.minimumSize!.resolve({}), Size.zero);
          final child = button.child! as SizedBox;
          expect(child.width, double.infinity);
          expect(child.height, double.infinity);
        } else {
          expect(button.style!.alignment, Alignment.centerLeft);
          expect(button.child, isA<ExcludeSemantics>());
        }
        button.onPressed!();
        await tester.pump();
        button = tester.widget<OutlinedButton>(inspectedButton);
        final roles = LineupTheme.of(tester.element(inspectedButton));
        final selectedSide = button.style!.side!.resolve({})!;
        expect(selectedSide.color, roles.progressFill);
        expect(selectedSide.width, 2);
        final side = button.style!.side!.resolve({WidgetState.focused})!;
        expect(side.color, roles.focusBorder);
        expect(side.width, roles.focusBorderWidth);
        widths.add(side.width);
      }
      expect(widths, [3, 5]);
    }
  });

  testWidgets(
    'ordered traversal follows Air Check and workbench before actions',
    (tester) async {
      final original = _channel(
        id: 'focus-order',
        number: 42,
        name: 'Focus order',
        source: const ManualSource([
          ChannelItem(id: 'one', title: 'One', duration: Duration(minutes: 30)),
          ChannelItem(id: 'two', title: 'Two', duration: Duration(minutes: 30)),
        ]),
      );
      final controller = _RecordingSaveController()
        ..channels = [original]
        ..availableMedia = [_media('one'), _media('two')];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.editCustom, channel: original),
      );
      await _settleAirCheck(tester);

      final backFocus = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Back to Channels'),
          )
          .focusNode!;
      expect(FocusManager.instance.primaryFocus, same(backFocus));
      backFocus.requestFocus();
      await tester.pump();
      backFocus.nextFocus();
      await tester.pump();
      expect(
        _focusNodeIsInside(
          FocusManager.instance.primaryFocus!,
          find.byKey(const Key('channel-air-check')),
        ),
        isTrue,
      );
      for (var step = 0; step < 80; step++) {
        final focus = FocusManager.instance.primaryFocus!;
        if (_focusNodeIsInside(
          focus,
          find.byKey(const Key('studio-programming')),
        )) {
          break;
        }
        expect(
          _focusNodeIsInside(focus, find.byKey(const Key('studio-station'))),
          isFalse,
        );
        focus.nextFocus();
        await tester.pump();
      }
      expect(
        _focusNodeIsInside(
          FocusManager.instance.primaryFocus!,
          find.byKey(const Key('studio-programming')),
        ),
        isTrue,
      );
      for (var step = 0; step < 80; step++) {
        final focus = FocusManager.instance.primaryFocus!;
        if (_focusNodeIsInside(
          focus,
          find.byKey(const Key('studio-station')),
        )) {
          break;
        }
        expect(
          _focusNodeIsInside(
            focus,
            find.widgetWithText(FilledButton, 'Tune in'),
          ),
          isFalse,
        );
        focus.nextFocus();
        await tester.pump();
      }
      expect(
        _focusNodeIsInside(
          FocusManager.instance.primaryFocus!,
          find.byKey(const Key('studio-station')),
        ),
        isTrue,
      );
      final tune = find.widgetWithText(FilledButton, 'Tune in');
      for (var step = 0; step < 40; step++) {
        final focus = FocusManager.instance.primaryFocus!;
        if (_focusNodeIsInside(focus, tune)) break;
        focus.nextFocus();
        await tester.pump();
      }
      expect(
        _focusNodeIsInside(FocusManager.instance.primaryFocus!, tune),
        isTrue,
      );
    },
  );

  testWidgets(
    'Studio consumes every theme with motion and large focus settings',
    (tester) async {
      final controller = _RecordingSaveController()
        ..availableMedia = [_media('one'), _media('two')];
      addTearDown(controller.dispose);
      for (final name in LineupThemeName.values) {
        final theme = LineupTheme.forName(name, largeFocusIndicators: true);
        await tester.pumpWidget(
          _studio(
            controller,
            ChannelStudioMode.createCustom,
            theme: theme,
            disableAnimations: true,
          ),
        );
        await _settleAirCheck(tester);
        final context = tester.element(find.text('Air Check'));
        expect(MediaQuery.disableAnimationsOf(context), isTrue);
        expect(
          Theme.of(context).extension<LineupThemeRoles>()!.focusBorderWidth,
          theme.extension<LineupThemeRoles>()!.focusBorderWidth,
        );
        expect(tester.takeException(), isNull, reason: name.label);
      }
    },
  );
}

bool _focusNodeIsInside(FocusNode node, Finder target) {
  final targetElements = target.evaluate().toSet();
  Element? element = node.context as Element?;
  while (element != null) {
    if (targetElements.contains(element)) return true;
    Element? parent;
    element.visitAncestorElements((ancestor) {
      parent = ancestor;
      return false;
    });
    element = parent;
  }
  return false;
}

double _studioScrollOffset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('studio-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position
    .pixels;

void _expectIntersectsViewport(
  WidgetTester tester,
  Finder finder,
  Size viewport,
) {
  expect((Offset.zero & viewport).overlaps(tester.getRect(finder)), isTrue);
}

void _expectFitsHorizontally(
  WidgetTester tester,
  Finder finder,
  Size viewport,
) {
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
}

Future<void> _chooseDropdown(
  WidgetTester tester,
  String key,
  String value,
) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> _selectStudioStage(WidgetTester tester, String key) async {
  final stage = find.byKey(Key(key));
  await tester.ensureVisible(stage);
  await tester.tap(stage);
  await tester.pump();
}

Future<void> _settleAirCheck(WidgetTester tester) async {
  await tester.pump(channelAirCheckDebounce);
  await tester.pumpAndSettle();
}

Widget _studio(
  FixtureController controller,
  ChannelStudioMode mode, {
  Channel? channel,
  Key? studioKey,
  DateTime Function()? clock,
  TextScaler? textScaler,
  ThemeData? theme,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: theme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: textScaler, disableAnimations: disableAnimations),
    child: child!,
  ),
  home: Scaffold(
    body: ChannelStudioView(
      key: studioKey ?? UniqueKey(),
      controller: controller,
      mode: mode,
      channel: channel,
      onBack: (_) async {},
      onSaved: (_) {},
      onDuplicate: (_) {},
      onOpenGenerateLineup: () async {},
      onTune: (_) async => false,
      clock: clock,
    ),
  ),
);

ChannelItem _itemForHealth(int index) => ChannelItem(
  id: 'program-$index',
  title: 'Program $index',
  duration: const Duration(minutes: 30),
);

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

String _testTime(DateTime value) =>
    const DefaultMaterialLocalizations().formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: false,
    );

PlexMediaItem _media(
  String id, {
  String? title,
  String? libraryId,
  String type = 'movie',
  String? showTitle,
  String? showThumb,
  List<String> genres = const [],
  List<String> collections = const [],
  List<String> actors = const [],
  List<String> directors = const [],
  String? studio,
  int? year,
  DateTime? addedAt,
  bool viewed = false,
  Duration duration = const Duration(minutes: 30),
}) => PlexMediaItem(
  id: id,
  title: title ?? id,
  type: type,
  duration: duration,
  libraryId: libraryId,
  grandparentTitle: showTitle,
  grandparentThumbPath: showThumb,
  parts: [PlexMediaPart(path: '/$id')],
  genres: genres,
  collections: collections,
  actors: actors,
  directors: directors,
  studio: studio,
  year: year,
  addedAt: addedAt,
  viewed: viewed,
);

PlexPlaylist _playlist(String id) => PlexPlaylist(
  id: id,
  title: 'Playlist $id',
  items: [_media('$id-item', type: 'episode', showTitle: 'Playlist show')],
);

Channel _channel({
  required String id,
  required int number,
  required String name,
  String? builderKey,
  ContentSource source = const LibrarySource(
    libraryId: 'movies',
    libraryType: PlexLibraryType.movie,
  ),
  PlaybackMode mode = PlaybackMode.sequential,
  int? blockSize,
}) => Channel(
  id: id,
  number: number,
  name: name,
  source: source,
  playbackMode: mode,
  anchor: DateTime.utc(2026),
  shuffleSeed: number,
  blockSize: blockSize,
  builderKey: builderKey,
);

class _FailingSaveController extends FixtureController {
  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async =>
      _testSchedule(channel, this);

  @override
  Future<void> saveChannel(Channel channel, {required Channel? expectedBase}) =>
      Future.error(StateError('synthetic save failure'));
}

class _BlockingSaveController extends FixtureController {
  final release = Completer<void>();
  Channel? attempted;

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async =>
      _testSchedule(channel, this);

  @override
  Future<void> saveChannel(
    Channel channel, {
    required Channel? expectedBase,
  }) async {
    attempted = channel;
    await release.future;
    throw StateError('synthetic save failure');
  }
}

class _RecordingSaveController extends FixtureController {
  Channel? saved;
  Channel? expectedBase;
  Channel? loaded;
  Object? scheduleFailure;
  Object? nextScheduleFailure;
  int generation = 0;

  @override
  int get contentGeneration => generation;

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async {
    loaded = channel;
    if (scheduleFailure case final failure?) throw failure;
    if (nextScheduleFailure case final failure?) {
      nextScheduleFailure = null;
      throw failure;
    }
    return _testSchedule(channel, this);
  }

  @override
  Future<void> saveChannel(
    Channel channel, {
    required Channel? expectedBase,
  }) async {
    saved = channel;
    this.expectedBase = expectedBase;
  }
}

class _ControlledStudioController extends FixtureController {
  final pending = <_StudioScheduleCall>[];
  Channel? saved;

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) {
    final completer = Completer<ScheduleIndex>();
    pending.add(_StudioScheduleCall(channel, completer));
    return completer.future;
  }

  void completeNext({bool noContent = false}) {
    final call = pending.removeAt(0);
    if (noContent) {
      call.completer.completeError(
        const ScheduleBuildException(ScheduleFailureReason.noContent),
      );
      return;
    }
    call.completer.complete(
      buildSchedule(
        (call.channel.source as ManualSource).items,
        mode: call.channel.playbackMode,
        seed: call.channel.shuffleSeed,
        blockSize: call.channel.blockSize ?? 3,
      ),
    );
  }

  @override
  Future<void> saveChannel(
    Channel channel, {
    required Channel? expectedBase,
  }) async {
    saved = channel;
  }
}

class _StudioScheduleCall {
  const _StudioScheduleCall(this.channel, this.completer);

  final Channel channel;
  final Completer<ScheduleIndex> completer;
}

class _RealSaveController extends FixtureController {
  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async =>
      _testSchedule(channel, this);
}

class _CountingInventoryController extends _RecordingSaveController {
  int playableInventoryReads = 0;

  @override
  ({
    List<PlexMediaItem> media,
    List<PlexPlaylist> playlists,
    Map<String, PlexMediaItem> byId,
  })
  get playableInventory {
    playableInventoryReads++;
    return super.playableInventory;
  }
}

class _ShellTuneController extends FixtureController {
  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async => buildSchedule(
    (channel.source as ManualSource).items,
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
  );

  @override
  LineupPlaybackRequest playbackFor(String itemId) =>
      LineupPlaybackRequest.parts([
        LineupPlaybackPart(
          uri: Uri.parse('https://media.test/$itemId'),
          duration: const Duration(hours: 24),
        ),
      ]);
}

class _AgreementController extends FixtureController {
  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async => buildSchedule(
    (channel.source as ManualSource).items,
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
    blockSize: channel.blockSize ?? 3,
  );

  @override
  Future<void> saveChannel(
    Channel channel, {
    required Channel? expectedBase,
  }) async {
    channels = [channel];
    notifyListeners();
  }

  @override
  LineupPlaybackRequest playbackFor(String itemId) =>
      LineupPlaybackRequest.parts([
        LineupPlaybackPart(
          uri: Uri.parse('https://media.test/$itemId'),
          duration: const Duration(minutes: 30),
        ),
      ]);
}

class _AgreementPlayer extends FixturePlayer {
  Uri? loaded;

  @override
  Future<void> load(Uri media, {String? plexToken, int? generation}) async {
    loaded = media;
    await super.load(media, plexToken: plexToken, generation: generation);
  }
}

class _ExpectedBaseController extends FixtureController {
  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async =>
      _testSchedule(channel, this);

  @override
  Future<void> saveChannel(
    Channel channel, {
    required Channel? expectedBase,
  }) async {
    final current = channels.where((item) => item.id == channel.id).firstOrNull;
    if (current == null ||
        expectedBase == null ||
        !canonicalChannelValueEquals(current.toJson(), expectedBase.toJson())) {
      throw const FormatException('Channel has changed');
    }
    channels = [channel];
    notifyListeners();
  }
}

class _HealthController extends FixtureController {
  int requests = 0;

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async {
    requests++;
    return buildSchedule(
      (channel.source as ManualSource).items,
      mode: channel.playbackMode,
      seed: channel.shuffleSeed,
      blockSize: channel.blockSize ?? 3,
    );
  }
}

class _ScheduleFailureController extends FixtureController {
  _ScheduleFailureController(this.failure);

  final Object failure;

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) =>
      Future.error(failure);
}

class _ControlledHealthController extends FixtureController {
  final pending = <_HealthCall>[];
  final _activeById = <String, int>{};
  int generation = 0;
  int requests = 0;
  int maximumActive = 0;

  @override
  int get contentGeneration => generation;

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) {
    requests++;
    final completer = Completer<ScheduleIndex>();
    final call = _HealthCall(channel, completer);
    pending.add(call);
    _activeById.update(channel.id, (value) => value + 1, ifAbsent: () => 1);
    maximumActive = maximumActive < pending.length
        ? pending.length
        : maximumActive;
    void finished() {
      final remaining = _activeById[channel.id]! - 1;
      if (remaining == 0) {
        _activeById.remove(channel.id);
      } else {
        _activeById[channel.id] = remaining;
      }
    }

    completer.future.then((_) => finished(), onError: (_) => finished());
    return completer.future;
  }

  void complete(String id, {Object? error}) {
    final call = pending.firstWhere((item) => item.channel.id == id);
    pending.remove(call);
    if (error != null) {
      call.completer.completeError(error);
    } else {
      call.completer.complete(
        buildSchedule(
          (call.channel.source as ManualSource).items,
          mode: call.channel.playbackMode,
          seed: call.channel.shuffleSeed,
          blockSize: call.channel.blockSize ?? 3,
        ),
      );
    }
  }

  void completePending() {
    for (final call in [...pending]) {
      if (pending.contains(call)) complete(call.channel.id);
    }
  }

  void resetMeasurements() {
    pending.clear();
    requests = 0;
    maximumActive = 0;
  }
}

class _HealthCall {
  const _HealthCall(this.channel, this.completer);

  final Channel channel;
  final Completer<ScheduleIndex> completer;
}

ScheduleIndex _testSchedule(Channel channel, FixtureController controller) =>
    buildSchedule(
      resolveContent(
        channel.source,
        controller.availableMedia,
        controller.availablePlaylists,
      ),
      mode: channel.playbackMode,
      seed: channel.shuffleSeed,
      blockSize: channel.blockSize ?? 3,
    );

class _RecoveryHarness extends StatefulWidget {
  const _RecoveryHarness({
    required this.controller,
    required this.channel,
    required this.onLeft,
  });

  final FixtureController controller;
  final Channel channel;
  final VoidCallback onLeft;

  @override
  State<_RecoveryHarness> createState() => _RecoveryHarnessState();
}

class _RecoveryHarnessState extends State<_RecoveryHarness> {
  var open = true;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: open
          ? ChannelStudioView(
              controller: widget.controller,
              mode: ChannelStudioMode.editCustom,
              channel: widget.channel,
              onBack: (_) async {
                widget.onLeft();
                setState(() => open = false);
              },
              onSaved: (_) {},
              onDuplicate: (_) {},
              onOpenGenerateLineup: () async {
                widget.onLeft();
                setState(() => open = false);
                widget.controller.enterChannelSetup();
              },
              onTune: (_) async => false,
            )
          : const SizedBox.shrink(),
    ),
  );
}
