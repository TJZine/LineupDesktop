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
  late GoldenFileComparator previousGoldenFileComparator;
  setUpAll(() async {
    await loadPinnedTestFonts();
    previousGoldenFileComparator = installCrossMacOsGoldenComparator();
  });
  tearDownAll(() => restoreGoldenFileComparator(previousGoldenFileComparator));

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('Guide without playback remains opaque outside its aperture', (
    tester,
  ) async {
    final fixture = _readyFixture()
      ..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, fixture.build());
    await _expectClassicOpacity(tester);
  });

  testWidgets('Guide with PiP remains opaque outside its native aperture', (
    tester,
  ) async {
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
  });

  testWidgets('player OSD at 1920x1080', (tester) async {
    final fixture = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.paused,
        message: 'Paused',
      ),
    );
    await _pump(tester, fixture.build(), viewport: const Size(1920, 1080));
    await openDestination(tester, 'Player');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(find.byKey(const Key('player-osd-surface')), findsOneWidget);
    await _match(tester, 'player-osd-1920x1080.png', additionalPumps: 2);
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
    await openDestination(tester, 'Player');
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

  testWidgets('Appearance chooser at large desktop size', (tester) async {
    final fixture = _readyFixture();
    await _pump(tester, fixture.build(), viewport: const Size(1920, 1080));
    await openDestination(tester, 'Settings');

    expect(find.byType(DropdownButton<LineupThemeName>), findsOneWidget);
    await _match(tester, 'settings-appearance-ember-steel-1920x1080.png');
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

UiFixture _readyFixture({
  PlayerStatus? playerState,
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
    );
  }
  final controller = _VisualController()
    ..stage = SetupStage.ready
    ..channels = _channels
    ..currentChannelId = _channels[1].id
    ..useWordmarkArtwork = useWordmarkArtwork;
  return UiFixture(
    controller: controller,
    player: player,
    guideClock: () => _fixedNow,
  );
}

class _VisualController extends FixtureController {
  bool useWordmarkArtwork = false;

  @override
  Future<Uint8List?> artworkForPath(Uri path) async =>
      useWordmarkArtwork ? _nowPlayingArtwork[path] : _syntheticArtwork;

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async =>
      buildChannelSchedule(channel, (channel.source as ManualSource).items);
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
