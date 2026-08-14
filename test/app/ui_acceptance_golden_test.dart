@TestOn('mac-os')
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

import '../support/ui_fixture.dart';

const _viewport = Size(1280, 720);
const _goldenKey = Key('visual-acceptance-boundary');
final _fixedNow = DateTime.utc(2026, 1, 15, 3, 17);

void main() {
  setUpAll(_loadPinnedTestFont);

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('profile selection', (tester) async {
    final fixture = UiFixture()
      ..controller.stage = SetupStage.profiles
      ..controller.profiles = const [
        PlexHomeUser(id: 'adult', name: 'Alex', protected: false),
        PlexHomeUser(id: 'child', name: 'Family', protected: true),
      ];

    await _pump(tester, fixture.build());
    await _match(tester, 'profiles-1280x720.png');
  });

  testWidgets('Channel Setup review', (tester) async {
    final controller = _VisualController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ];
    addTearDown(controller.dispose);

    await _pump(
      tester,
      UiFixture(controller: controller, guideClock: () => _fixedNow).build(),
    );
    await tester.tap(find.text('Configure channels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build Channels'));
    await tester.pumpAndSettle();

    expect(find.text('Review expected changes'), findsOneWidget);
    await _match(tester, 'channel-setup-review-1280x720.png');
  });

  testWidgets('Guide without playback', (tester) async {
    final fixture = _readyFixture();
    await _pump(tester, fixture.build());
    await _expectClassicOpacity(tester);
    await _match(tester, 'guide-no-playback-1280x720.png');
  });

  testWidgets('Guide with PiP allocation', (tester) async {
    final fixture = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.ready,
        message: 'Synthetic player surface',
      ),
    );
    await _pump(tester, fixture.build());
    await _expectClassicOpacity(
      tester,
      aperture: find.byKey(const Key('guide-picture-in-picture')),
    );
    await _match(tester, 'guide-pip-1280x720.png');
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
          );
    await _pump(tester, fixture.build());
    await _match(tester, 'guide-overlay-1280x720.png');
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
    await _match(tester, 'player-osd-1280x720.png');
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
    await _match(tester, 'mini-guide-1280x720.png');
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
  final roboto = File('$fontDirectory/Roboto-Regular.ttf');
  if (!roboto.existsSync()) {
    throw StateError('Pinned Flutter test fonts were not found.');
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

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _viewport;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(RepaintBoundary(key: _goldenKey, child: child));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _match(WidgetTester tester, String name) async {
  final guide = name.startsWith('guide-');
  if (guide) {
    final context = tester.element(find.byKey(_goldenKey));
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/branding/lineup-logo-mark.png'),
        context,
      ),
    );
  }
  if (guide || name == 'player-osd-1280x720.png') {
    await tester.pump(const Duration(milliseconds: 400));
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

UiFixture _readyFixture({PlayerStatus? playerState}) {
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
      tracks: const [
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
          key: '/library/metadata/$index',
          title: 'Synthetic Movie ${index + 1}',
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
