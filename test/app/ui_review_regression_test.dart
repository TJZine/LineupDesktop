import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_air_check.dart';
import 'package:lineup_desktop/app/channel_setup_view.dart';
import 'package:lineup_desktop/app/channel_studio_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/lineup_shell.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/channels/content_resolver.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/app_theme.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets('selection cards expose one complete semantic control', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LineupSelectionCard(
          selected: true,
          onPressed: () {},
          child: const Text('Movies'),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(LineupSelectionCard)),
      matchesSemantics(
        label: 'Movies',
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: true,
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: LineupSelectionCard(
          selected: false,
          onPressed: null,
          child: Text('Movies'),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(LineupSelectionCard)),
      matchesSemantics(
        label: 'Movies',
        hasEnabledState: true,
        isEnabled: false,
        hasSelectedState: true,
        isSelected: false,
        isButton: true,
        isFocusable: true,
        hasTapAction: false,
        hasFocusAction: true,
      ),
    );
  });

  testWidgets('Swiss panels keep shared custom surfaces square', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(LineupThemeName.swiss),
        home: const Column(
          children: [
            LineupSelectionCard(
              selected: false,
              onPressed: null,
              child: Text('Movies'),
            ),
            LineupNotice(message: 'Unavailable'),
          ],
        ),
      ),
    );

    final selectionCard = tester.widget<Card>(
      find.descendant(
        of: find.byType(LineupSelectionCard),
        matching: find.byType(Card),
      ),
    );
    expect(
      (selectionCard.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.zero,
    );
    final focusRing = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(LineupSelectionCard),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(
      (focusRing.decoration! as BoxDecoration).borderRadius,
      BorderRadius.zero,
    );
    final notice = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(LineupNotice),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (notice.decoration! as BoxDecoration).borderRadius,
      BorderRadius.zero,
    );
  });

  testWidgets('management pages use their available width for compact layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          child: SizedBox(
            width: 800,
            height: 700,
            child: LineupPage(
              title: 'Constrained page',
              actions: TextButton(
                onPressed: () {},
                child: const Text('Action'),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final contentBounds = tester.getRect(
      find.byKey(const ValueKey('lineup-page-content')),
    );
    final actionBounds = tester.getRect(find.text('Action'));
    final titleBounds = tester.getRect(find.text('Constrained page'));
    expect(contentBounds.intersect(actionBounds), actionBounds);
    expect(contentBounds.intersect(titleBounds), titleBounds);
    expect(actionBounds.top, greaterThan(titleBounds.bottom));
  });

  testWidgets('successful channel deletion clears a prior failure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = FixtureController(store: _FailNextSaveStore())
      ..stage = SetupStage.ready
      ..channels = [_channel];
    final fixture = UiFixture(controller: controller);
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await tester.pump();
    await openDestination(tester, 'Channels');

    await _confirmDelete(tester);
    expect(
      find.text(
        'The channel could not be deleted. No lineup changes were saved.',
      ),
      findsOneWidget,
    );
    expect(controller.channels, hasLength(1));
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<IconButton>()
          ?.tooltip,
      'Delete Newsroom',
    );

    await _confirmDelete(tester);
    expect(controller.channels, isEmpty);
    expect(
      find.text(
        'The channel could not be deleted. No lineup changes were saved.',
      ),
      findsNothing,
    );
  });

  testWidgets('manual channels hide the inapplicable watched-items control', (
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
    await openDestination(tester, 'Channels');
    await tester.tap(find.text('New channel'));
    await tester.pumpAndSettle();

    expect(find.text('Include watched items'), findsOneWidget);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.ensureVisible(find.text('Hand-picked'));
    await tester.tap(find.text('Hand-picked'));
    await tester.pumpAndSettle();
    expect(find.text('Include watched items'), findsNothing);

    final libraryChoice = find.descendant(
      of: find.byWidgetPredicate(
        (widget) =>
            widget.runtimeType.toString().startsWith('SegmentedButton<'),
      ),
      matching: find.text('Library'),
    );
    await tester.ensureVisible(libraryChoice);
    await tester.tap(libraryChoice);
    await tester.pumpAndSettle();
    expect(find.text('Include watched items'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });

  testWidgets('channel editor reports a library removed while it is open', (
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
    await openDestination(tester, 'Channels');
    await tester.tap(find.text('New channel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Movies');

    fixture.controller
      ..libraries = const []
      ..selectedLibraryIds = const {};
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();

    expect(find.text('Select a library.'), findsOneWidget);
  });

  testWidgets('Studio recovery honors keep editing and confirmed discard', (
    tester,
  ) async {
    final controller = _CountingSetupController()..stage = SetupStage.ready;
    addTearDown(controller.dispose);
    await tester.pumpWidget(UiFixture(controller: controller).build());
    await tester.pump();
    await tester.pump();
    await openDestination(tester, 'Channels');
    await tester.tap(find.text('New channel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('studio-name')), 'Unsaved');
    await tester.pump();

    await tester.ensureVisible(find.text('Open Generate lineup'));
    await tester.tap(find.text('Open Generate lineup'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(controller.setupEntries, 0);
    expect(find.text('Create custom channel'), findsOneWidget);

    await tester.ensureVisible(find.text('Open Generate lineup'));
    final recovery = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Open Generate lineup'),
    );
    recovery.onPressed!();
    recovery.onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(controller.setupEntries, 1);
    expect(controller.stage, SetupStage.channelSetup);
    expect(find.text('Create custom channel'), findsNothing);
  });

  testWidgets('manual channel edits retain unavailable selected items', (
    tester,
  ) async {
    const availableItem = ChannelItem(
      id: 'available',
      title: 'Available program',
      duration: Duration(minutes: 30),
    );
    const unavailableItem = ChannelItem(
      id: 'unavailable',
      title: 'Unavailable program',
      duration: Duration(minutes: 45),
    );
    final channel = Channel(
      id: 'manual',
      number: 8,
      name: 'Manual channel',
      source: const ManualSource([availableItem, unavailableItem]),
      playbackMode: PlaybackMode.sequential,
      anchor: DateTime.utc(2026),
      shuffleSeed: 8,
    );
    final controller = FixtureController()
      ..stage = SetupStage.ready
      ..channels = [channel]
      ..availableMedia = [
        PlexMediaItem(
          id: 'available',
          title: 'Available program',
          type: 'movie',
          duration: const Duration(minutes: 30),
          libraryId: 'movies',
          parts: [PlexMediaPart(path: '/parts/available')],
          addedAt: DateTime.utc(2026),
        ),
      ];

    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _studio(controller, channel),
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    expect(find.text('Unavailable — retained until removed'), findsOneWidget);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final source = controller.channels.single.source as ManualSource;
    expect(source.items.map((item) => item.id), ['available', 'unavailable']);
  });

  for (final testCase
      in <
        ({
          String name,
          ContentSource source,
          PlaybackMode initialMode,
          int? initialBlockSize,
          PlaybackMode savedMode,
          int? savedBlockSize,
        })
      >[
        (
          name: 'generated filtered library',
          source: const LibrarySource(
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
            includeWatched: false,
            filters: {'genre': 'Comedy'},
          ),
          initialMode: PlaybackMode.block,
          initialBlockSize: 5,
          savedMode: PlaybackMode.sequential,
          savedBlockSize: null,
        ),
        (
          name: 'generated playlist',
          source: const PlaylistSource('playlist-1'),
          initialMode: PlaybackMode.shuffle,
          initialBlockSize: 7,
          savedMode: PlaybackMode.block,
          savedBlockSize: 7,
        ),
        (
          name: 'generated mixed source',
          source: const MixedSource(
            interleave: true,
            sources: [
              LibrarySource(
                libraryId: 'shows',
                libraryType: PlexLibraryType.show,
                filters: {'decade': '2020s'},
              ),
              PlaylistSource('playlist-2'),
            ],
          ),
          initialMode: PlaybackMode.shuffle,
          initialBlockSize: null,
          savedMode: PlaybackMode.block,
          savedBlockSize: 3,
        ),
      ]) {
    testWidgets('${testCase.name} edits metadata without changing provenance', (
      tester,
    ) async {
      final original = Channel(
        id: 'generated',
        number: 10,
        name: 'Original',
        source: testCase.source,
        playbackMode: testCase.initialMode,
        anchor: DateTime.utc(2026, 8, 23, 12),
        shuffleSeed: 8675309,
        blockSize: testCase.initialBlockSize,
        builderKey: 'builder:${testCase.name}',
      );
      final controller = _ReviewStudioController()
        ..stage = SetupStage.ready
        ..connection = _studioConnection
        ..channels = [original]
        ..availableMedia = [_studioMovie, _studioEpisode]
        ..availablePlaylists = [
          PlexPlaylist(
            id: 'playlist-1',
            title: 'Playlist 1',
            items: [_studioMovie],
          ),
          PlexPlaylist(
            id: 'playlist-2',
            title: 'Playlist 2',
            items: [_studioEpisode],
          ),
        ];
      addTearDown(controller.dispose);

      await _openChannelEditor(tester, controller, original);

      expect(
        find.text('Programming is read-only and will be preserved exactly.'),
        findsOneWidget,
      );
      expect(find.text('Entire library'), findsNothing);
      expect(find.text('Hand-picked'), findsNothing);
      expect(find.textContaining('Convert'), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, 'Renamed');
      await tester.enterText(find.byType(TextFormField).at(1), '42');
      await tester.pump(channelAirCheckDebounce + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save identity'));
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save identity'),
          )
          .onPressed!();
      await tester.pumpAndSettle();

      final saved = controller.channels.single;
      expect(saved.name, 'Renamed');
      expect(saved.number, 42);
      expect(saved.source.toJson(), original.source.toJson());
      expect(saved.builderKey, original.builderKey);
      expect(saved.anchor, original.anchor);
      expect(saved.shuffleSeed, original.shuffleSeed);
      expect(saved.playbackMode, testCase.initialMode);
      expect(saved.blockSize, testCase.initialBlockSize);
    });
  }

  testWidgets('custom sources expose authoring or lossless replacement', (
    tester,
  ) async {
    const item = ChannelItem(
      id: 'item',
      title: 'Program',
      duration: Duration(minutes: 30),
    );
    final cases = <ContentSource>[
      const LibrarySource(
        libraryId: 'movies',
        libraryType: PlexLibraryType.movie,
        filters: {'genre': 'Comedy'},
      ),
      const PlaylistSource('playlist-1'),
      const MixedSource(sources: [PlaylistSource('playlist-1')]),
      const LibrarySource(
        libraryId: 'movies',
        libraryType: PlexLibraryType.movie,
      ),
      const ManualSource([item]),
    ];
    final controller = FixtureController()
      ..stage = SetupStage.ready
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..selectedLibraryIds = const {'movies'};
    addTearDown(controller.dispose);

    for (var index = 0; index < cases.length; index++) {
      final source = cases[index];
      final channel = Channel(
        id: 'channel-$index',
        number: index + 1,
        name: 'Channel $index',
        source: source,
        playbackMode: PlaybackMode.shuffle,
        anchor: DateTime.utc(2026),
        shuffleSeed: index,
      );
      await _openChannelEditor(tester, controller, channel);
      expect(
        find.text('Programming is read-only and will be preserved exactly.'),
        findsNothing,
      );
      final sourceChoices = find.byWidgetPredicate(
        (widget) =>
            widget.runtimeType.toString().startsWith('SegmentedButton<'),
      );
      expect(
        find.descendant(of: sourceChoices, matching: find.text('Library')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sourceChoices, matching: find.text('Playlist')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sourceChoices,
          matching: find.text('Collection or filter'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sourceChoices, matching: find.text('Hand-picked')),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('read-only channel cancel and failed save keep the original', (
    tester,
  ) async {
    final original = Channel(
      id: 'playlist',
      number: 12,
      name: 'Playlist channel',
      source: const PlaylistSource('playlist-1'),
      playbackMode: PlaybackMode.shuffle,
      anchor: DateTime.utc(2026),
      shuffleSeed: 12,
      builderKey: 'playlist:playlist-1',
    );
    final controller = FixtureController(store: _FailNextSaveStore())
      ..stage = SetupStage.ready
      ..connection = _studioConnection
      ..channels = [original]
      ..availablePlaylists = [
        PlexPlaylist(
          id: 'playlist-1',
          title: 'Playlist 1',
          items: [_studioMovie],
        ),
      ];
    addTearDown(controller.dispose);

    await _openChannelEditor(tester, controller, original);
    await tester.enterText(find.byType(TextFormField).first, 'Cancelled');
    await tester.tap(find.text('Back to Channels'));
    await tester.pumpAndSettle();
    expect(controller.channels.single.toJson(), original.toJson());

    await _openChannelEditor(tester, controller, original);
    await tester.enterText(find.byType(TextFormField).first, 'Failed');
    await tester.ensureVisible(find.text('Save identity'));
    await tester.tap(find.text('Save identity'));
    await tester.pumpAndSettle();

    expect(controller.channels.single.toJson(), original.toJson());
  });

  testWidgets('settings dropdowns stay disabled until persistence completes', (
    tester,
  ) async {
    final controller = _SettingsFixtureController()..stage = SetupStage.ready;
    final fixture = UiFixture(controller: controller);
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Settings');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Guide'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desktop extended (6 hours)').last);
    await tester.pump();

    expect(
      tester
          .widgetList<DropdownButton<dynamic>>(find.byType(DropdownButton))
          .every((dropdown) => dropdown.onChanged == null),
      isTrue,
    );

    controller.failUpdate();
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This setting could not be saved. Your previous value remains.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<DropdownButton<dynamic>>(find.byType(DropdownButton))
          .every((dropdown) => dropdown.onChanged != null),
      isTrue,
    );
  });

  testWidgets('PIN dialog leaves autofocus with its keyboard owner', (
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

    final keyboardOwner = tester.widget<Focus>(
      find.byKey(const Key('profile-pin-keyboard-owner')),
    );
    expect(keyboardOwner.focusNode, isNotNull);
    expect(keyboardOwner.focusNode!.hasFocus, isTrue);
  });

  testWidgets('Channel Setup footer uses its available width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = FixtureController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: UpstreamChannelSetupView(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Configure channels')).dy,
      tester.getTopLeft(find.text('Select All')).dy,
    );
    expect(
      tester.getTopLeft(find.text('Configure channels')).dx,
      greaterThan(tester.getTopRight(find.text('Clear All')).dx),
    );
  });

  testWidgets('Channel Setup append review stays exact after apply failure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _FailingChannelSetupController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..channels = [_channel];
    final originalChannels = controller.channels;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: UpstreamChannelSetupView(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configure channels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add generated channels'));
    await tester.pump();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Create: 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Update: 0'), findsOneWidget);
    expect(find.bySemanticsLabel('Unchanged: 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Generated removed: 0'), findsOneWidget);
    expect(find.bySemanticsLabel('Final: 3'), findsOneWidget);

    await tester.tap(find.text('Confirm & Build'));
    await tester.pumpAndSettle();
    expect(find.text('The channel plan could not be applied.'), findsOneWidget);
    expect(controller.channels, same(originalChannels));
    expect(find.text('Lineup update failed'), findsOneWidget);
    expect(find.text('Review expected changes'), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );

    await tester.tap(find.text('Back to Review'));
    await tester.pumpAndSettle();
    expect(find.text('Review expected changes'), findsOneWidget);
    expect(find.bySemanticsLabel('Final: 3'), findsOneWidget);
    expect(Focus.of(tester.element(find.text('Back'))).hasFocus, isTrue);
  });

  testWidgets('Channel Setup apply is non-cancellable and waits on Complete', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _PendingChannelSetupController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: UpstreamChannelSetupView(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configure channels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build Channels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove 0 generated channels'));
    await tester.pump();
    await tester.tap(find.text('Confirm & Replace'));
    await tester.pump();

    expect(find.bySemanticsLabel('Applying channels'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('View lineup'), findsNothing);
    expect(controller.stage, SetupStage.channelSetup);

    controller.finishApply();
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Channel update complete'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
    expect(controller.stage, SetupStage.channelSetup);
    expect(Focus.of(tester.element(find.text('View lineup'))).hasFocus, isTrue);
    await tester.tap(find.text('View lineup'));
    await tester.pumpAndSettle();
    expect(controller.stage, SetupStage.ready);
  });

  testWidgets(
    'Channel Setup autofocus does not reclaim focus after scrolling',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = FixtureController()
        ..stage = SetupStage.channelSetup
        ..libraries = List.generate(
          30,
          (index) => PlexLibrary(
            id: 'library-$index',
            title: 'Library $index',
            type: PlexLibraryType.movie,
          ),
        );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: UpstreamChannelSetupView(controller: controller)),
      );
      await tester.pumpAndSettle();
      Focus.of(tester.element(find.text('Select All'))).requestFocus();
      await tester.pump();
      final intendedFocus = FocusManager.instance.primaryFocus;
      expect(intendedFocus, isNotNull);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2400));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 2400));
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, same(intendedFocus));
    },
  );

  testWidgets('Settings does not reclaim focus after a layout remount', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = FixtureController()..stage = SetupStage.ready;
    final outsideFocus = FocusNode(debugLabel: 'Outside Settings');
    addTearDown(controller.dispose);
    addTearDown(outsideFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            TextButton(
              focusNode: outsideFocus,
              onPressed: () {},
              child: const Text('Outside'),
            ),
            Expanded(child: SettingsView(controller: controller)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    outsideFocus.requestFocus();
    await tester.pump();

    await tester.binding.setSurfaceSize(const Size(1200, 700));
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus, same(outsideFocus));
  });
}

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Delete Newsroom'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete channel'));
  await tester.pumpAndSettle();
}

Future<void> _openChannelEditor(
  WidgetTester tester,
  FixtureController controller,
  Channel channel,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _studio(controller, channel),
          ),
          child: const Text('Open editor'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

Widget _studio(FixtureController controller, Channel channel) => Scaffold(
  body: Builder(
    builder: (context) => ChannelStudioView(
      controller: controller,
      mode: channel.builderKey == null
          ? ChannelStudioMode.editCustom
          : ChannelStudioMode.inspectGenerated,
      channel: channel,
      onBack: (_) async => Navigator.of(context).maybePop(),
      onSaved: (_) {},
      onDuplicate: (_) {},
      onOpenGenerateLineup: () async {},
      onTune: (_) async => false,
    ),
  ),
);

final _studioMovie = PlexMediaItem(
  id: 'studio-movie',
  title: 'Studio movie',
  type: 'movie',
  duration: const Duration(minutes: 90),
  libraryId: 'movies',
  parts: [PlexMediaPart(path: '/studio-movie')],
  genres: const ['Comedy'],
  year: 2026,
);

final _studioConnection = PlexConnection(
  uri: Uri.parse('https://studio.example:32400'),
  local: true,
  relay: false,
);

final _studioEpisode = PlexMediaItem(
  id: 'studio-episode',
  title: 'Studio episode',
  type: 'episode',
  duration: const Duration(minutes: 30),
  libraryId: 'shows',
  parts: [PlexMediaPart(path: '/studio-episode')],
  year: 2026,
);

class _CountingSetupController extends FixtureController {
  var setupEntries = 0;

  @override
  Future<void> enterChannelSetup() async {
    setupEntries++;
    await super.enterChannelSetup();
  }
}

class _ReviewStudioController extends FixtureController {
  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async => buildSchedule(
    resolveContent(channel.source, availableMedia, availablePlaylists),
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
    blockSize: channel.blockSize ?? 3,
  );
}

class _FailNextSaveStore extends FixtureStore {
  bool _failNextSave = true;

  @override
  Future<void> save(PersistedState value) async {
    if (_failNextSave) {
      _failNextSave = false;
      throw StateError('synthetic save failure');
    }
    await super.save(value);
  }
}

class _SettingsFixtureController extends FixtureController {
  final _update = Completer<void>();

  @override
  Future<void> updateSettings(LineupSettings value) => _update.future;

  void failUpdate() =>
      _update.completeError(StateError('synthetic save failure'));
}

class _ProfileFixtureController extends FixtureController {
  @override
  Future<bool> selectProfile(PlexHomeUser selected, {String? pin}) async =>
      true;
}

class _FailingChannelSetupController extends FixtureController {
  @override
  Future<bool> setLibraries(Set<String> ids) async {
    selectedLibraryIds = Set.unmodifiable(ids);
    availableMedia = [
      for (var index = 0; index < 6; index++)
        PlexMediaItem(
          id: 'movie-$index',
          title: 'Movie $index',
          type: 'movie',
          duration: const Duration(minutes: 90),
          libraryId: 'movies',
          genres: const ['Drama'],
        ),
    ];
    libraryScanStatus = LibraryScanStatus.complete;
    return true;
  }

  @override
  Future<void> applyChannelPlan(
    List<Channel> planned, {
    required ChannelBuildMode mode,
  }) async => throw StateError('synthetic apply failure');
}

class _PendingChannelSetupController extends _FailingChannelSetupController {
  final _apply = Completer<void>();

  @override
  Future<void> applyChannelPlan(
    List<Channel> planned, {
    required ChannelBuildMode mode,
  }) => _apply.future;

  void finishApply() => _apply.complete();
}

final _channel = Channel(
  id: 'newsroom',
  number: 7,
  name: 'Newsroom',
  source: const LibrarySource(
    libraryId: 'movies',
    libraryType: PlexLibraryType.movie,
  ),
  playbackMode: PlaybackMode.sequential,
  anchor: DateTime.utc(2026),
  shuffleSeed: 7,
);
