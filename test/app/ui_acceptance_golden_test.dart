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

import '../support/ui_fixture.dart';

const _viewport = Size(1280, 720);
const _goldenKey = Key('visual-acceptance-boundary');
final _fixedNow = DateTime.utc(2026, 1, 15, 3, 17);
final _syntheticArtwork = File('assets/branding/lineup-logo-mark.png')
    .readAsBytesSync();

void main() {
  setUpAll(_loadPinnedTestFont);

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

  testWidgets('Audio Setup', (tester) async {
    final fixture = UiFixture()..controller.stage = SetupStage.audio;

    await _pump(tester, fixture.build());
    await _match(
      tester,
      'audio-setup-1280x720.png',
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
    final regions = [
      shell,
      tester.getRect(find.byKey(const ValueKey('channel-setup-header'))),
      tester.getRect(find.widgetWithText(Chip, 'Step 2 of 3')),
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
      tester.getBottomRight(find.text('Done')).dy,
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
            playerState: const PlayerStatus(
              state: PlayerState.playing,
              message: 'Playing',
            ),
          )
          ..controller.channels = _richPlayerChannels
          ..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, fixture.build());
    await _openDestination(tester, 'Player');
    final context = tester.element(find.byKey(_goldenKey));
    await tester.runAsync(
      () => precacheImage(MemoryImage(_syntheticArtwork), context),
    );
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
            playerState: const PlayerStatus(
              state: PlayerState.playing,
              message: 'Playing',
            ),
          )
          ..controller.channels = _richPlayerChannels
          ..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, fixture.build(), viewport: const Size(1920, 1080));
    await _openDestination(tester, 'Player');
    final context = tester.element(find.byKey(_goldenKey));
    await tester.runAsync(
      () => precacheImage(MemoryImage(_syntheticArtwork), context),
    );
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
}

Future<void> _loadPinnedTestFont() async {
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  while (flutterRoot.parent.path != flutterRoot.path &&
      !File(
        '${flutterRoot.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ).existsSync()) {
    flutterRoot = flutterRoot.parent;
  }
  final fontDirectory =
      '${flutterRoot.path}/bin/cache/artifacts/material_fonts';
  if (!Directory(fontDirectory).existsSync()) {
    throw StateError(
      'Pinned Flutter material-fonts directory is missing: $fontDirectory',
    );
  }
  final requiredFonts = [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'MaterialIcons-Regular.otf',
  ];
  for (final filename in requiredFonts) {
    if (!File('$fontDirectory/$filename').existsSync()) {
      throw StateError('Pinned Flutter test font is missing: $filename');
    }
  }
  for (final family in ['Roboto', '.AppleSystemUIFont']) {
    final loader = FontLoader(family);
    for (final file in [
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
    ]) {
      loader.addFont(
        File('$fontDirectory/$file').readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  }
  final icons = ByteData.sublistView(
    await File('$fontDirectory/MaterialIcons-Regular.otf').readAsBytes(),
  );
  await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
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
  await expectLater(find.byKey(_goldenKey), matchesGoldenFile('goldens/$name'));
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
}) {
  final player = FixturePlayer();
  if (playerState != null) {
    player.emit(
      playerState,
      position: const Duration(minutes: 18),
      duration: const Duration(minutes: 48),
      telemetry: const PlayerTelemetry(
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
    ..stage = SetupStage.ready
    ..channels = _channels
    ..currentChannelId = _channels[1].id;
  return UiFixture(
    controller: controller,
    player: player,
    guideClock: () => _fixedNow,
  );
}

class _VisualController extends FixtureController {
  Map<String, LibraryScanFact> scanFacts = const {};

  @override
  Map<String, LibraryScanFact> get libraryScanFacts => scanFacts;

  @override
  Future<Uint8List?> artworkForPath(Uri path) async => _syntheticArtwork;

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
  await tester.tap(find.text('This will replace your current lineup'));
  await tester.pump();
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
        name: channel.name,
        source: ManualSource([
          for (var program = 0; program < 8; program++)
            ChannelItem(
              id: 'program-1-$program',
              title: const [
                'City Stories',
                'After Midnight',
                'World in Focus',
                'The Long Way Home',
              ][program % 4],
              showTitle: program.isEven ? 'Lineup Originals' : null,
              duration: Duration(minutes: 24 + program * 4),
              poster: Uri.parse('test://poster-$program'),
              backdrop: Uri.parse('test://backdrop-$program'),
              clearLogo: Uri.parse('test://logo-$program'),
              summary: 'A small-town radio host follows a mysterious signal across the night.',
              contentRating: 'TV-14',
              genres: const ['Drama', 'Mystery'],
              year: 2026,
              seasonNumber: program.isEven ? 1 : null,
              episodeNumber: program.isEven ? program + 1 : null,
              resolution: '1080p',
              videoCodec: 'h264',
              audioCodec: 'aac',
              audioChannels: 6,
              dynamicRange: 'SDR',
            ),
        ]),
        playbackMode: channel.playbackMode,
        anchor: channel.anchor,
        shuffleSeed: channel.shuffleSeed,
      ),
];
