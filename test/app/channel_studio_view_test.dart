import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_studio_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

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
    expect(find.textContaining('New channel • Channel 1 •'), findsOneWidget);
    await tester.tap(find.text('Back to Channels'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open Custom four'));
    await tester.pumpAndSettle();
    expect(find.text('Edit custom channel'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.text('Back to Channels'));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Open Custom four');

    await tester.tap(find.byTooltip('Open Generated eight'));
    await tester.pumpAndSettle();
    expect(find.text('Inspect generated channel'), findsOneWidget);
    expect(
      find.text('Programming is read-only and will be preserved exactly.'),
      findsOneWidget,
    );
    expect(find.text('Mini-marathons of 4'), findsOneWidget);
    await tester.tap(find.text('Duplicate as custom'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate as custom'), findsWidgets);
    expect(find.text('Custom'), findsWidgets);
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
    final fixture = UiFixture()
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
    final controller = _RecordingSaveController()..channels = [original];
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
      ..saved = null;
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: custom),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Edited');
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
        ..channels = [_channel(id: 'taken', number: 7, name: 'The Seven')];
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
    await tester.tap(find.text('Cancel'));
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
    final controller = _FailingSaveController()..channels = [original];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('studio-name')),
      'Complete draft',
    );
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
    final controller = _BlockingSaveController()..channels = [original];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _studio(controller, ChannelStudioMode.editCustom, channel: original),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Draft');
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
          id: 'retained',
          title: 'Retained program',
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
    await tester.tap(find.text('Save changes'));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.byIcon(Icons.monitor_heart_outlined));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.textContaining('Draft • Channel 3 •'), findsOneWidget);
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
      ..selectedLibraryIds = {'movies'};
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
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();

    expect(find.text('Channel saved.'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Tune in'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
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
    expect(find.textContaining('Saved station • Channel 1 •'), findsOneWidget);
    expect(find.textContaining('could not be tuned'), findsOneWidget);
    expect(controller.saved?.name, 'Saved station');
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
      final controller = _ExpectedBaseController()..channels = [original];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _studio(controller, ChannelStudioMode.editCustom, channel: original),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('studio-name')), 'Mine');
      controller.channels = [changed];
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Reload channel'), findsOneWidget);
      expect(find.text('Reapply my changes'), findsOneWidget);
      expect(controller.channels.single.name, 'External');

      await tester.ensureVisible(find.text('Reload channel'));
      await tester.tap(find.text('Reload channel'));
      await tester.pumpAndSettle();
      expect(_fieldText(tester, 'studio-name'), 'External');
      await tester.enterText(find.byKey(const Key('studio-name')), 'Mine');
      final changedAgain = _channel(
        id: 'custom',
        number: 3,
        name: 'External again',
        source: const PlaylistSource('playlist'),
      );
      controller.channels = [changedAgain];
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Reapply my changes'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      controller.channels = [
        _channel(
          id: 'custom',
          number: 3,
          name: 'Intervening',
          source: const PlaylistSource('playlist'),
        ),
      ];
      await tester.tap(find.text('Reapply changes'));
      await tester.pumpAndSettle();
      expect(controller.channels.single.name, 'Intervening');
      expect(find.text('Reapply my changes'), findsOneWidget);

      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Reapply my changes'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reapply changes'));
      await tester.pumpAndSettle();
      expect(controller.channels.single.name, 'Mine');

      await tester.enterText(find.byKey(const Key('studio-name')), 'Again');
      controller.channels = const [];
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('deleted while you were editing'),
        findsOneWidget,
      );
      expect(find.text('Reapply my changes'), findsNothing);
      expect(controller.channels, isEmpty);
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Reload lineup'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(controller.channels, isEmpty);
    },
  );
}

Widget _studio(
  FixtureController controller,
  ChannelStudioMode mode, {
  Channel? channel,
}) => MaterialApp(
  home: Scaffold(
    body: ChannelStudioView(
      key: UniqueKey(),
      controller: controller,
      mode: mode,
      channel: channel,
      onBack: (_) async {},
      onSaved: (_) {},
      onDuplicate: (_) {},
      onTune: (_) async => false,
    ),
  ),
);

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

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
  Future<void> saveChannel(Channel channel, {required Channel? expectedBase}) =>
      Future.error(StateError('synthetic save failure'));
}

class _BlockingSaveController extends FixtureController {
  final release = Completer<void>();

  @override
  Future<void> saveChannel(
    Channel channel, {
    required Channel? expectedBase,
  }) async {
    await release.future;
    throw StateError('synthetic save failure');
  }
}

class _RecordingSaveController extends FixtureController {
  Channel? saved;
  Channel? expectedBase;

  @override
  Future<void> saveChannel(
    Channel channel, {
    required Channel? expectedBase,
  }) async {
    saved = channel;
    this.expectedBase = expectedBase;
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

class _ExpectedBaseController extends FixtureController {
  @override
  Future<void> saveChannel(
    Channel channel, {
    required Channel? expectedBase,
  }) async {
    final current = channels.where((item) => item.id == channel.id).firstOrNull;
    if (current == null ||
        expectedBase == null ||
        current.toJson().toString() != expectedBase.toJson().toString()) {
      throw const FormatException('Channel has changed');
    }
    channels = [channel];
    notifyListeners();
  }
}
