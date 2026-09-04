@TestOn('mac-os')
library;

import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

import '../support/golden_test_support.dart';
import '../support/ui_fixture.dart';

const _viewport = Size(1280, 720);
const _goldenKey = Key('visual-acceptance-boundary');
final _fixedNow = DateTime.utc(2026, 1, 15, 3, 17);
final _syntheticArtwork = File('assets/branding/lineup-logo-mark.png')
    .readAsBytesSync();
final _nowPlayingArtwork = <Uri, Uint8List>{
  Uri.parse('test://now-playing/poster'): File(
    'test/support/now_playing/signal-after-midnight-poster.png',
  ).readAsBytesSync(),
  Uri.parse('test://now-playing/title'): File(
    'test/support/now_playing/signal-after-midnight-title.png',
  ).readAsBytesSync(),
  Uri.parse('/library/metadata/test/now-playing/cast-elias'): File(
    'test/support/now_playing/cast-elias-vale.png',
  ).readAsBytesSync(),
  Uri.parse('/library/metadata/test/now-playing/cast-mina'): File(
    'test/support/now_playing/cast-mina-park.png',
  ).readAsBytesSync(),
  Uri.parse('/library/metadata/test/now-playing/cast-solomon'): File(
    'test/support/now_playing/cast-solomon-reed.png',
  ).readAsBytesSync(),
  Uri.parse('/library/metadata/test/now-playing/cast-clara'): File(
    'test/support/now_playing/cast-clara-wynn.png',
  ).readAsBytesSync(),
};

void main() {
  setUpAll(loadPinnedTestFonts);

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('profile selection', (tester) async {
    final fixture = _profileSelectionFixture();

    await _pump(tester, fixture.build());
    await _match(
      tester,
      'profiles-1280x720.png',
      precacheLogo: true,
      additionalPumps: 1,
    );
  });

  testWidgets('profile selection at 1920x1080', (tester) async {
    final fixture = _profileSelectionFixture();

    await _pump(tester, fixture.build(), viewport: const Size(1920, 1080));
    await _match(
      tester,
      'profiles-1920x1080.png',
      precacheLogo: true,
      additionalPumps: 1,
    );
  });

  testWidgets('protected profile PIN', (tester) async {
    const profile = PlexHomeUser(
      id: 'protected',
      name: 'Taylor',
      protected: true,
    );
    final fixture = UiFixture()
      ..controller.stage = SetupStage.profiles
      ..controller.profiles = const [profile];

    await _pump(tester, fixture.build());
    await tester.tap(find.text('Taylor'));
    await tester.pumpAndSettle();
    await _match(
      tester,
      'profile-pin-1280x720.png',
      precacheLogo: true,
      additionalPumps: 1,
    );
  });

  testWidgets('terminal Plex linking failure', (tester) async {
    final fixture = UiFixture()
      ..controller.stage = SetupStage.linking
      ..controller.error =
          'Lineup could not connect to Plex. Check your connection and request a new code.';

    await _pump(tester, fixture.build());
    expect(find.text('Waiting for sign-in…'), findsNothing);
    await _match(tester, 'auth-link-failure-1280x720.png');
  });

  testWidgets('server selection', (tester) async {
    final selected = PlexServer(
      id: 'studio',
      name: 'Studio Server',
      owned: true,
      connections: [
        PlexConnection(
          uri: Uri.parse('https://local.synthetic.invalid'),
          local: true,
          relay: false,
        ),
        PlexConnection(
          uri: Uri.parse('https://remote.synthetic.invalid'),
          local: false,
          relay: false,
        ),
        PlexConnection(
          uri: Uri.parse('https://relay.synthetic.invalid'),
          local: false,
          relay: true,
        ),
      ],
    );
    final fixture = UiFixture()
      ..controller.stage = SetupStage.servers
      ..controller.server = selected
      ..controller.connection = PlexConnection(
        uri: Uri.parse('https://selected.synthetic.invalid'),
        local: true,
        relay: false,
        latency: const Duration(milliseconds: 126),
      )
      ..controller.servers = [
        selected,
        PlexServer(
          id: 'shared',
          name: 'Family Server',
          connections: [
            PlexConnection(
              uri: Uri.parse('https://shared.synthetic.invalid'),
              local: false,
              relay: false,
            ),
          ],
        ),
      ];

    await _pump(tester, fixture.build());
    await _match(
      tester,
      'server-selection-1280x720.png',
      precacheLogo: true,
      additionalPumps: 1,
    );
  });

  testWidgets('Channel Setup strategies', (tester) async {
    final controller = _VisualController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ];
    await _pump(
      tester,
      UiFixture(controller: controller, guideClock: () => _fixedNow).build(),
    );
    await tester.tap(find.text('Configure channels'));
    await tester.pumpAndSettle();

    expect(find.text('Configure the lineup'), findsOneWidget);
    final viewport = Offset.zero & _viewport;
    final shell = tester.getRect(
      find.byKey(const ValueKey('channel-setup-shell')),
    );
    final header = tester.getRect(
      find.byKey(const ValueKey('channel-setup-header')),
    );
    expect(header.bottom, lessThan(shell.top));
    expect(
      tester.getRect(find.widgetWithText(Chip, 'Step 2 of 3')).bottom,
      lessThan(shell.top),
    );
    final regions = [
      tester.getRect(find.byKey(const ValueKey('channel-setup-strategy-rail'))),
      tester.getRect(
        find.byKey(const ValueKey('channel-setup-strategy-details')),
      ),
      tester.getRect(find.widgetWithText(FilledButton, 'Build Channels')),
    ];
    for (final region in regions) {
      expect(viewport.intersect(region), region);
      expect(shell.intersect(region), region);
    }
    await _match(
      tester,
      'channel-setup-strategies-1280x720.png',
      precacheLogo: true,
      additionalPumps: 2,
    );
  });

  testWidgets('Channel Setup review', (tester) async {
    final controller = _VisualController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ];
    await _pump(
      tester,
      TickerMode(
        enabled: false,
        child: UiFixture(
          controller: controller,
          guideClock: () => _fixedNow,
        ).build(),
      ),
    );
    await tester.tap(find.text('Configure channels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build Channels'));
    await tester.pumpAndSettle();

    expect(find.text('Review expected changes'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Channel Setup')).dy,
      lessThan(tester.getTopLeft(find.text('Review expected changes')).dy),
    );
    expect(
      tester.getBottomRight(find.text('Confirm & Replace')).dy,
      lessThanOrEqualTo(_viewport.height),
    );
    await _match(
      tester,
      'channel-setup-review-1280x720.png',
      precacheLogo: true,
      additionalPumps: 2,
    );
  });

  testWidgets('Channel Setup review at 1920x1080', (tester) async {
    final controller = _VisualController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ];
    await _pump(
      tester,
      TickerMode(
        enabled: false,
        child: UiFixture(
          controller: controller,
          guideClock: () => _fixedNow,
        ).build(),
      ),
      viewport: const Size(1920, 1080),
    );
    await tester.tap(find.text('Configure channels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build Channels'));
    await tester.pumpAndSettle();

    expect(find.text('Review expected changes'), findsOneWidget);
    expect(find.bySemanticsLabel('Final: 2'), findsOneWidget);
    expect(
      tester.getBottomRight(find.text('Confirm & Replace')).dy,
      lessThanOrEqualTo(1080),
    );
    await _match(
      tester,
      'channel-setup-review-1920x1080.png',
      precacheLogo: true,
      additionalPumps: 2,
    );
  });

  testWidgets('Channel Setup review with generated removals', (tester) async {
    final controller = _VisualController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..channels = [
        Channel(
          id: 'retro-detectives',
          number: 42,
          name: 'Retro Detectives',
          source: const LibrarySource(
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
          ),
          playbackMode: PlaybackMode.shuffle,
          anchor: DateTime.utc(2026, 1, 15),
          shuffleSeed: 42,
          builderKey: 'synthetic:retro-detectives',
        ),
      ];
    await _pump(
      tester,
      TickerMode(
        enabled: false,
        child: UiFixture(
          controller: controller,
          guideClock: () => _fixedNow,
        ).build(),
      ),
    );
    await tester.tap(find.text('Configure channels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Remove 1 generated channel'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm & Replace'),
          )
          .onPressed,
      isNull,
    );
    await _match(
      tester,
      'channel-setup-review-removals-1280x720.png',
      precacheLogo: true,
      additionalPumps: 2,
    );
  });

  testWidgets('Channel Setup progress', (tester) async {
    final controller = _PendingVisualController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ];
    await _pump(
      tester,
      TickerMode(
        enabled: false,
        child: UiFixture(
          controller: controller,
          guideClock: () => _fixedNow,
        ).build(),
      ),
    );
    await _openChannelSetupApply(tester);

    expect(find.bySemanticsLabel('Applying channels'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Channel Setup')).dy,
      lessThan(tester.getTopLeft(find.text('Applying your lineup')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Channel Setup')).dy,
      greaterThanOrEqualTo(0),
    );
    expect(find.text('Step 3 of 3'), findsOneWidget);
    for (final element in tester.allElements) {
      element.renderObject?.markNeedsPaint();
    }
    await tester.pump();
    await _match(
      tester,
      'channel-setup-progress-1280x720.png',
      precacheLogo: true,
      additionalPumps: 2,
    );
  });

  testWidgets('Channel Setup complete', (tester) async {
    final controller = _PendingVisualController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ];
    await _pump(
      tester,
      TickerMode(
        enabled: false,
        child: UiFixture(
          controller: controller,
          guideClock: () => _fixedNow,
        ).build(),
      ),
    );
    await _openChannelSetupApply(tester);
    controller.finishApply();
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Channel update complete'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Channel Setup')).dy,
      lessThan(tester.getTopLeft(find.text('Your lineup is ready')).dy),
    );
    expect(
      tester.getBottomRight(find.text('View lineup')).dy,
      lessThanOrEqualTo(_viewport.height),
    );
    await _match(
      tester,
      'channel-setup-complete-1280x720.png',
      precacheLogo: true,
      additionalPumps: 2,
    );
  });

  testWidgets('Channel Setup library outcomes', (tester) async {
    final controller = _VisualController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(
          id: 'movies',
          title: 'Feature Films',
          type: PlexLibraryType.movie,
        ),
        PlexLibrary(id: 'shows', title: 'Series', type: PlexLibraryType.show),
        PlexLibrary(
          id: 'archive',
          title: 'Archive',
          type: PlexLibraryType.movie,
        ),
        PlexLibrary(
          id: 'imports',
          title: 'Recent Imports',
          type: PlexLibraryType.movie,
        ),
      ]
      ..selectedLibraryIds = const {'movies', 'shows', 'archive', 'imports'}
      ..libraryScanStatus = LibraryScanStatus.transientFailure
      ..libraryScanCompletedPages = 8
      ..libraryScanCompletedItems = 83
      ..libraryScanTotalItems = 112
      ..error = 'Plex could not complete the library scan.'
      ..scanFacts = const {
        'movies': LibraryScanFact(
          status: LibraryScanStatus.complete,
          completedPages: 4,
          completedItems: 72,
          totalItems: 72,
        ),
        'shows': LibraryScanFact(
          status: LibraryScanStatus.unsupported,
          completedPages: 2,
          completedItems: 8,
          totalItems: 8,
        ),
        'archive': LibraryScanFact(
          status: LibraryScanStatus.empty,
          completedPages: 1,
          totalItems: 0,
        ),
        'imports': LibraryScanFact(
          status: LibraryScanStatus.transientFailure,
          completedPages: 1,
          completedItems: 3,
          totalItems: 32,
        ),
      };

    await _pump(
      tester,
      TickerMode(
        enabled: false,
        child: UiFixture(
          controller: controller,
          guideClock: () => _fixedNow,
        ).build(),
      ),
    );
    expect(find.text('Retry scan'), findsOneWidget);
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('72/72 items · 4 pages'), findsOneWidget);
    expect(find.text('Unsupported'), findsOneWidget);
    expect(find.text('8/8 items · 2 pages'), findsOneWidget);
    expect(find.text('Empty'), findsOneWidget);
    expect(find.text('0/0 items · 1 page'), findsOneWidget);
    expect(find.text('Scan failed'), findsOneWidget);
    expect(find.text('3/32 items · 1 page'), findsOneWidget);
    await _match(
      tester,
      'channel-setup-libraries-1280x720.png',
      precacheLogo: true,
      additionalPumps: 2,
    );
  });

  testWidgets('Guide without playback', (tester) async {
    final fixture = _readyFixture()
      ..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, fixture.build());
    await _expectClassicOpacity(tester);
    await _match(
      tester,
      'guide-no-playback-1280x720.png',
      precacheLogo: true,
      additionalPumps: 2,
    );
  });

  testWidgets('Guide with PiP allocation', (tester) async {
    final fixture = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.ready,
        message: 'Synthetic player surface',
      ),
    )..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, fixture.build());
    await _expectClassicOpacity(
      tester,
      aperture: find.byKey(const Key('guide-picture-in-picture')),
    );
    await _match(
      tester,
      'guide-pip-1280x720.png',
      precacheLogo: true,
      additionalPumps: 2,
    );
  });

  testWidgets('overlay Guide', (tester) async {
    final fixture =
        _readyFixture(
            playerState: const PlayerStatus(
              state: PlayerState.ready,
              message: 'Synthetic player surface',
            ),
          )
          ..controller.settings = const LineupSettings(
            guideLayoutMode: GuideLayoutMode.overlay,
            reduceMotion: true,
          );
    await _pump(tester, fixture.build());
    await _match(
      tester,
      'guide-overlay-1280x720.png',
      precacheLogo: true,
      additionalPumps: 2,
    );
  });

  testWidgets('player OSD', (tester) async {
    final fixture = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.paused,
        message: 'Paused',
      ),
    );
    await _pump(tester, fixture.build());
    await _openDestination(tester, 'Player');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(find.byKey(const Key('player-osd-surface')), findsOneWidget);
    await _match(tester, 'player-osd-1280x720.png', additionalPumps: 2);
  });

  testWidgets('player OSD at 1920x1080', (tester) async {
    final fixture = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.paused,
        message: 'Paused',
      ),
    );
    await _pump(tester, fixture.build(), viewport: const Size(1920, 1080));
    await _openDestination(tester, 'Player');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(find.byKey(const Key('player-osd-surface')), findsOneWidget);
    await _match(tester, 'player-osd-1920x1080.png', additionalPumps: 2);
  });

  testWidgets('player Now Playing', (tester) async {
    final fixture =
        _readyFixture(
            useWordmarkArtwork: true,
            playerState: const PlayerStatus(
              state: PlayerState.playing,
              message: 'Playing',
            ),
          )
          ..controller.channels = _richPlayerChannels
          ..controller.settings = const LineupSettings(
            guideHours: 4,
            reduceMotion: true,
          );
    await _pump(tester, fixture.build());
    await _openDestination(tester, 'Player');
    final context = tester.element(find.byKey(_goldenKey));
    await tester.runAsync(() async {
      for (final bytes in _nowPlayingArtwork.values) {
        await precacheImage(MemoryImage(bytes), context);
      }
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pump();

    expect(find.byKey(const Key('player-now-playing-surface')), findsOneWidget);
    await _match(
      tester,
      'player-now-playing-1280x720.png',
      precacheLogo: true,
      additionalPumps: 2,
    );
  });

  testWidgets('player Now Playing at 1920x1080', (tester) async {
    final fixture =
        _readyFixture(
            useWordmarkArtwork: true,
            playerState: const PlayerStatus(
              state: PlayerState.playing,
              message: 'Playing',
            ),
          )
          ..controller.channels = _richPlayerChannels
          ..controller.settings = const LineupSettings(
            guideHours: 4,
            reduceMotion: true,
          );
    await _pump(tester, fixture.build(), viewport: const Size(1920, 1080));
    await _openDestination(tester, 'Player');
    final context = tester.element(find.byKey(_goldenKey));
    await tester.runAsync(() async {
      for (final bytes in _nowPlayingArtwork.values) {
        await precacheImage(MemoryImage(bytes), context);
      }
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pump();

    expect(find.byKey(const Key('player-now-playing-surface')), findsOneWidget);
    await _match(
      tester,
      'player-now-playing-1920x1080.png',
      precacheLogo: true,
      additionalPumps: 2,
    );
  });

  testWidgets('player audio track rail', (tester) async {
    final fixture = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.playing,
        message: 'Playing',
      ),
      tracks: const [
        PlayerTrack(
          id: 1,
          type: PlayerTrackType.audio,
          selected: true,
          title: 'English',
          language: 'eng',
          codec: 'aac',
        ),
        PlayerTrack(
          id: 2,
          type: PlayerTrackType.audio,
          selected: false,
          title: 'Spanish',
          language: 'spa',
          codec: 'ac3',
        ),
      ],
    )..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, fixture.build());
    await _openDestination(tester, 'Player');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();

    expect(find.byKey(const Key('playback-options-rail')), findsOneWidget);
    await _match(tester, 'player-audio-tracks-1280x720.png');
  });

  testWidgets('player long subtitle track rail', (tester) async {
    final fixture = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.playing,
        message: 'Playing',
      ),
      tracks: [
        for (var index = 1; index <= 14; index++)
          PlayerTrack(
            id: index,
            type: PlayerTrackType.subtitle,
            selected: index == 10,
            title: 'Subtitle track $index',
            language: index.isEven ? 'eng' : 'spa',
            codec: index.isEven ? 'ass' : 'srt',
          ),
      ],
    )..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, fixture.build());
    await _openDestination(tester, 'Player');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();

    expect(
      Focus.of(tester.element(find.text('Subtitle track 10'))).hasFocus,
      isTrue,
    );
    await _match(tester, 'player-subtitles-long-1280x720.png');
  });

  testWidgets('Mini Guide', (tester) async {
    final fixture = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.playing,
        message: 'Playing',
      ),
    );
    await _pump(tester, fixture.build());
    await _openDestination(tester, 'Player');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(find.byKey(const Key('mini-guide-shelf')), findsOneWidget);
    await _match(tester, 'mini-guide-1280x720.png', additionalPumps: 2);
  });

  testWidgets('Mini Guide at 1920x1080', (tester) async {
    final fixture = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.playing,
        message: 'Playing',
      ),
    );
    await _pump(tester, fixture.build(), viewport: const Size(1920, 1080));
    await _openDestination(tester, 'Player');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(find.byKey(const Key('mini-guide-shelf')), findsOneWidget);
    await _match(tester, 'mini-guide-1920x1080.png', additionalPumps: 2);
  });

  testWidgets('Settings in alternate theme', (tester) async {
    final fixture = _readyFixture()
      ..controller.settings = const LineupSettings(
        theme: LineupThemeName.slatePine,
      );
    await _pump(tester, fixture.build());
    await _openDestination(tester, 'Settings');
    await _match(tester, 'settings-slate-pine-1280x720.png');
  });

  testWidgets('Appearance chooser at compact desktop size', (tester) async {
    final fixture = _readyFixture();
    await _pump(tester, fixture.build(), viewport: const Size(800, 600));
    await _openDestination(tester, 'Settings');

    expect(find.byKey(const Key('theme-option-ember-steel')), findsOneWidget);
    await _match(tester, 'settings-appearance-ember-steel-800x600.png');
  });

  testWidgets('Appearance chooser at large desktop size', (tester) async {
    final fixture = _readyFixture();
    await _pump(tester, fixture.build(), viewport: const Size(1920, 1080));
    await _openDestination(tester, 'Settings');

    expect(find.byKey(const Key('theme-option-ember-steel')), findsOneWidget);
    await _match(tester, 'settings-appearance-ember-steel-1920x1080.png');
  });

  testWidgets('Settings over playback in Ember & Steel', (tester) async {
    final fixture = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.playing,
        message: 'Playing',
      ),
    )..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, fixture.build());
    await _openDestination(tester, 'Settings');

    expect(find.byType(PlayerSurface), findsOneWidget);
    expect(find.byType(PlayerView), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    await _match(tester, 'settings-playback-ember-steel-1280x720.png');
  });

  testWidgets('Channel Studio expanded custom authoring with Air Check', (
    tester,
  ) async {
    final fixture = _studioFixture();
    await _pump(tester, fixture.build());
    await _openDestination(tester, 'Channels');
    await tester.tap(find.byTooltip('Open Saturday Cartoons'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await _match(tester, 'channel-studio-expanded-1280x720.png');
  });

  testWidgets('Channel Studio compact custom authoring with Air Check', (
    tester,
  ) async {
    final fixture = _studioFixture();
    await _pump(tester, fixture.build(), viewport: const Size(800, 600));
    await _openDestination(tester, 'Channels');
    await tester.tap(find.byTooltip('Open Saturday Cartoons'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const Key('studio-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .pixels,
      0,
    );
    for (final finder in [
      find.text('Saved'),
      find.byKey(const Key('channel-air-check')),
      find.text('Programming'),
      find.text('Save changes'),
    ]) {
      expect(
        (Offset.zero & const Size(800, 600)).overlaps(tester.getRect(finder)),
        isTrue,
      );
    }
    await _match(tester, 'channel-studio-compact-800x600.png');
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size viewport = _viewport,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = viewport;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(RepaintBoundary(key: _goldenKey, child: child));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

UiFixture _profileSelectionFixture() => UiFixture()
  ..controller.stage = SetupStage.profiles
  ..controller.profile = const PlexHomeUser(
    id: 'adult',
    name: 'Alex',
    protected: false,
    admin: true,
  )
  ..controller.profiles = const [
    PlexHomeUser(id: 'adult', name: 'Alex', protected: false, admin: true),
    PlexHomeUser(
      id: 'child',
      name: 'Family',
      protected: true,
      restricted: true,
    ),
    PlexHomeUser(id: 'guest', name: 'Guest', protected: false),
    PlexHomeUser(
      id: 'movies',
      name: 'A deliberately long synthetic profile name',
      protected: false,
      restricted: true,
    ),
    PlexHomeUser(id: 'kids', name: 'Kids', protected: false, restricted: true),
    PlexHomeUser(id: 'sports', name: 'Sports', protected: false),
    PlexHomeUser(id: 'parents', name: 'Parents', protected: true),
    PlexHomeUser(id: 'weekend', name: 'Weekend', protected: false),
    PlexHomeUser(
      id: 'visitor',
      name: 'Visitor',
      protected: false,
      restricted: true,
    ),
  ];

Future<void> _match(
  WidgetTester tester,
  String name, {
  bool precacheLogo = false,
  int additionalPumps = 0,
}) async {
  if (precacheLogo) {
    final context = tester.element(find.byKey(_goldenKey));
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/branding/lineup-logo-mark.png'),
        context,
      ),
    );
  }
  for (var index = 0; index < additionalPumps; index++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
  final boundary = find.byKey(_goldenKey);
  markSubtreeNeedsPaint(tester.renderObject(boundary));
  await tester.pump();
  await expectLater(boundary, matchesGoldenFile('goldens/$name'));
}

Future<void> _expectClassicOpacity(
  WidgetTester tester, {
  Finder? aperture,
}) async {
  final boundaryFinder = find.byKey(_goldenKey);
  final boundary = tester.renderObject<RenderRepaintBoundary>(boundaryFinder);
  final capture = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = (width: image.width, height: image.height, pixels: pixels);
    image.dispose();
    return result;
  });
  if (capture == null || capture.pixels == null) {
    fail('Classic Guide pixels could not be read.');
  }
  final width = capture.width;
  final height = capture.height;
  final pixels = capture.pixels!;

  final boundaryOrigin = tester.getTopLeft(boundaryFinder);
  final allowed = aperture == null
      ? null
      : (tester.getTopLeft(aperture) - boundaryOrigin) &
            tester.getSize(aperture);
  Offset? firstUnexpectedTransparency;
  var transparentPixels = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (pixels.getUint8((y * width + x) * 4 + 3) == 255) continue;
      transparentPixels++;
      final point = Offset(x + 0.5, y + 0.5);
      if (allowed == null || !allowed.inflate(1).contains(point)) {
        firstUnexpectedTransparency ??= point;
      }
    }
  }

  expect(
    firstUnexpectedTransparency,
    isNull,
    reason:
        'Classic Guide transparency escaped the PlayerSurface aperture at '
        '$firstUnexpectedTransparency.',
  );
  expect(transparentPixels, allowed == null ? 0 : greaterThan(0));
}

Future<void> _openDestination(WidgetTester tester, String destination) async {
  await tester.tap(find.byKey(const Key('guide-app-menu')));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.tap(find.text(destination).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

UiFixture _readyFixture({
  PlayerStatus? playerState,
  List<PlayerTrack>? tracks,
  bool useWordmarkArtwork = false,
}) {
  final player = FixturePlayer();
  if (playerState != null) {
    player.emit(
      playerState,
      position: const Duration(minutes: 18),
      duration: const Duration(minutes: 48),
      telemetry: useWordmarkArtwork
          ? const PlayerTelemetry(
              width: 3840,
              height: 2160,
              videoCodec: 'hevc',
              gamma: 'pq',
            )
          : const PlayerTelemetry(
              width: 1920,
              height: 1080,
              videoCodec: 'h264',
            ),
      tracks:
          tracks ??
          const [
            PlayerTrack(
              id: 1,
              type: PlayerTrackType.audio,
              selected: true,
              title: 'English',
            ),
            PlayerTrack(
              id: 2,
              type: PlayerTrackType.subtitle,
              selected: false,
              title: 'English captions',
            ),
          ],
    );
  }
  final controller = _VisualController()
    ..useWordmarkArtwork = useWordmarkArtwork
    ..stage = SetupStage.ready
    ..channels = _channels
    ..currentChannelId = _channels[1].id;
  return UiFixture(
    controller: controller,
    player: player,
    guideClock: () => _fixedNow,
  );
}

UiFixture _studioFixture() {
  const programs = [
    ChannelItem(
      id: 'cartoon-one',
      title: 'Moonbase Mystery',
      showTitle: 'Saturday Signals',
      duration: Duration(minutes: 30),
    ),
    ChannelItem(
      id: 'cartoon-two',
      title: 'The Clockwork Cove',
      showTitle: 'Saturday Signals',
      duration: Duration(minutes: 30),
    ),
    ChannelItem(
      id: 'cartoon-three',
      title: 'Rocket Club Rescue',
      showTitle: 'Junior Orbit',
      duration: Duration(minutes: 30),
    ),
    ChannelItem(
      id: 'cartoon-four',
      title: 'Cloud City Picnic',
      showTitle: 'Junior Orbit',
      duration: Duration(minutes: 30),
    ),
  ];
  final channel = Channel(
    id: 'studio-custom',
    number: 42,
    name: 'Saturday Cartoons',
    source: const ManualSource(programs),
    playbackMode: PlaybackMode.sequential,
    anchor: DateTime.utc(2026, 1, 15, 3),
    shuffleSeed: 42,
  );
  final controller = _VisualController()
    ..stage = SetupStage.ready
    ..channels = [channel]
    ..availableMedia = [
      for (final program in programs)
        PlexMediaItem(
          id: program.id,
          title: program.title,
          type: 'episode',
          duration: program.duration,
          grandparentTitle: program.showTitle,
          parts: [PlexMediaPart(path: '/synthetic/${program.id}')],
        ),
    ];
  return UiFixture(controller: controller, guideClock: () => _fixedNow);
}

class _VisualController extends FixtureController {
  Map<String, LibraryScanFact> scanFacts = const {};
  bool useWordmarkArtwork = false;

  @override
  Map<String, LibraryScanFact> get libraryScanFacts => scanFacts;

  @override
  Future<Uint8List?> artworkForPath(Uri path) async =>
      useWordmarkArtwork ? _nowPlayingArtwork[path] : _syntheticArtwork;

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async => buildSchedule(
    (channel.source as ManualSource).items,
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
  );

  @override
  Future<bool> setLibraries(Set<String> ids) async {
    selectedLibraryIds = Set.unmodifiable(ids);
    availableMedia = [
      for (var index = 0; index < 12; index++)
        PlexMediaItem(
          id: 'movie-$index',
          title: 'Synthetic Movie ${index + 1}',
          type: 'movie',
          duration: const Duration(minutes: 90),
          libraryId: 'movies',
          parts: [PlexMediaPart(path: '/parts/movie-$index')],
          genres: const ['Drama'],
          addedAt: DateTime.utc(2026, 1, index + 1),
        ),
    ];
    libraryScanStatus = LibraryScanStatus.complete;
    return true;
  }
}

class _PendingVisualController extends _VisualController {
  final _apply = Completer<void>();

  @override
  Future<void> applyChannelPlan(
    List<Channel> planned, {
    required ChannelBuildMode mode,
  }) async {
    await _apply.future;
    await super.applyChannelPlan(planned, mode: mode);
  }

  void finishApply() => _apply.complete();
}

Future<void> _openChannelSetupApply(WidgetTester tester) async {
  await tester.tap(find.text('Configure channels'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Build Channels'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirm & Replace'));
  await tester.pump();
}

final _channels = List.generate(
  12,
  (index) => Channel(
    id: 'channel-$index',
    number: index + 1,
    name: const [
      'Action Cinema',
      'Comedy Club',
      'Documentary',
      'Family Favorites',
    ][index % 4],
    source: ManualSource([
      for (var program = 0; program < 8; program++)
        ChannelItem(
          id: 'program-$index-$program',
          title: const [
            'The Long Way Home',
            'City Stories',
            'After Midnight',
            'World in Focus',
          ][(index + program) % 4],
          showTitle: program.isEven ? 'Lineup Originals' : null,
          duration: Duration(minutes: 24 + program * 4),
        ),
    ]),
    playbackMode: PlaybackMode.sequential,
    anchor: DateTime.utc(2026, 8, 13),
    shuffleSeed: index,
  ),
  growable: false,
);

final _richPlayerChannels = [
  for (final channel in _channels)
    if (channel.id != 'channel-1')
      channel
    else
      Channel(
        id: channel.id,
        number: channel.number,
        name: 'Midnight Mysteries',
        source: ManualSource([
          for (var program = 0; program < 8; program++)
            ChannelItem(
              id: 'program-1-$program',
              title: const [
                'The Last Frequency',
                'Voices in the Static',
                'A Light Below',
                'The Silent Relay',
              ][program % 4],
              showTitle: 'Signal After Midnight',
              duration: const Duration(minutes: 48),
              poster: Uri.parse('test://now-playing/poster'),
              backdrop: Uri.parse('test://now-playing/poster'),
              clearLogo: Uri.parse('test://now-playing/title'),
              summary: 'When a vanished emergency broadcast returns after twenty years, a night-shift radio engineer and a skeptical detective trace its coded warnings through a city that insists the original case never happened.',
              contentRating: 'TV-14',
              genres: const ['Mystery', 'Drama', 'Thriller'],
              year: 2026,
              seasonNumber: 1,
              episodeNumber: program + 1,
              resolution: '4K',
              videoCodec: 'hevc',
              audioCodec: 'eac3',
              audioChannels: 6,
              dynamicRange: 'HDR10',
              cast: [
                ChannelCastMember(
                  name: 'Elias Vale',
                  role: 'Jonah Mercer',
                  portrait: Uri.parse(
                    '/library/metadata/test/now-playing/cast-elias',
                  ),
                ),
                ChannelCastMember(
                  name: 'Mina Park',
                  role: 'Detective Hana Voss',
                  portrait: Uri.parse(
                    '/library/metadata/test/now-playing/cast-mina',
                  ),
                ),
                ChannelCastMember(
                  name: 'Solomon Reed',
                  role: 'Arthur Bell',
                  portrait: Uri.parse(
                    '/library/metadata/test/now-playing/cast-solomon',
                  ),
                ),
                ChannelCastMember(
                  name: 'Clara Wynn',
                  role: 'June Mercer',
                  portrait: Uri.parse(
                    '/library/metadata/test/now-playing/cast-clara',
                  ),
                ),
                ChannelCastMember(name: 'Noa Bell', role: 'Evelyn Shaw'),
              ],
            ),
        ]),
        playbackMode: channel.playbackMode,
        anchor: channel.anchor,
        shuffleSeed: channel.shuffleSeed,
      ),
];
