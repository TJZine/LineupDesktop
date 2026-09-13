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

void main() {
  setUpAll(loadPinnedTestFonts);

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
    );
  }
  final controller = _OpacityController()
    ..stage = SetupStage.ready
    ..channels = _channels
    ..currentChannelId = _channels[1].id;
  return UiFixture(
    controller: controller,
    player: player,
    guideClock: () => _fixedNow,
  );
}

class _OpacityController extends FixtureController {
  @override
  Future<Uint8List?> artworkForPath(Uri path) async => _syntheticArtwork;

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
