@TestOn('mac-os')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';

import '../support/golden_test_support.dart';
import '../support/ui_fixture.dart';

const _goldenKey = Key('guide-sparse-visual-boundary');
const _viewport = Size(1920, 1080);
final _fixedNow = DateTime.utc(2026, 1, 15, 3, 17);
final Uint8List _posterBytes = File(
  'test/support/now_playing/signal-after-midnight-poster.png',
).readAsBytesSync();

void main() {
  setUpAll(loadPinnedTestFonts);

  testWidgets('matched rich Guide information', (tester) async {
    final context = await _pumpGuide(tester, rich: true);
    await tester.runAsync(
      () => precacheImage(
        ResizeImage.resizeIfNeeded(360, null, MemoryImage(_posterBytes)),
        context,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide-focused-artwork')), findsOneWidget);
    expect(find.byKey(const Key('guide-program-badges')), findsOneWidget);
    await _match(tester, 'guide-overlay-rich-1920x1080.png');
  });

  testWidgets('matched reference-free Guide information', (tester) async {
    await _pumpGuide(tester, rich: false);

    expect(find.byKey(const Key('guide-focused-artwork')), findsNothing);
    expect(find.byKey(const Key('guide-program-badges')), findsNothing);
    await _match(tester, 'guide-overlay-sparse-1920x1080.png');
  });
}

Future<BuildContext> _pumpGuide(
  WidgetTester tester, {
  required bool rich,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _viewport;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final lineup = _ComparisonController(_channels(rich));
  addTearDown(lineup.dispose);
  final guide = GuideController(
    lineup: lineup,
    clock: () => _fixedNow,
    loadSchedule: lineup.loadScheduleFor,
  );
  addTearDown(guide.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _goldenKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: LineupTheme.forName(LineupThemeName.emberSteel),
        home: GuideView(
          controller: guide,
          overlayMode: true,
          playbackMessage: 'Synthetic player surface',
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  return tester.element(find.byKey(_goldenKey));
}

Future<void> _match(WidgetTester tester, String name) async {
  final boundary = find.byKey(_goldenKey);
  markSubtreeNeedsPaint(tester.renderObject(boundary));
  await tester.pump();
  await expectLater(boundary, matchesGoldenFile('goldens/$name'));
}

List<Channel> _channels(bool rich) => [
  for (var channelIndex = 0; channelIndex < 5; channelIndex++)
    Channel(
      id: 'channel-$channelIndex',
      number: channelIndex + 1,
      name: const [
        'CineVault',
        'WNEX Weather',
        'Nature Field',
        'Retro Detectives',
        'City Life',
      ][channelIndex],
      source: ManualSource([
        for (var programIndex = 0; programIndex < 8; programIndex++)
          ChannelItem(
            id: 'program-$channelIndex-$programIndex',
            title: const [
              'Northbound',
              'Regional Weather',
              'Coasts at Dusk',
              'The Great Detectives',
              'City Stories',
            ][(channelIndex + programIndex) % 5],
            duration: const Duration(minutes: 30),
            showTitle: rich ? 'Lineup Stories' : null,
            poster: rich ? Uri.parse('test://guide/poster') : null,
            backdrop: rich ? Uri.parse('test://guide/poster') : null,
            summary: rich
                ? 'A privacy-safe synthetic listing with enough detail to exercise the approved rich Guide composition.'
                : null,
            contentRating: rich ? 'TV-14' : null,
            genres: rich ? const ['Drama', 'Mystery'] : const [],
            year: rich ? 2026 : null,
            seasonNumber: rich ? 1 : null,
            episodeNumber: rich ? programIndex + 1 : null,
            resolution: rich ? '4K' : null,
            videoCodec: rich ? 'hevc' : null,
            audioCodec: rich ? 'eac3' : null,
            audioChannels: rich ? 6 : null,
            dynamicRange: rich ? 'HDR10' : null,
          ),
      ]),
      playbackMode: PlaybackMode.sequential,
      anchor: DateTime.utc(2026, 1, 15, 3),
      shuffleSeed: channelIndex + 1,
    ),
];

class _ComparisonController extends FixtureController {
  _ComparisonController(List<Channel> fixtureChannels) {
    stage = SetupStage.ready;
    settings = const LineupSettings(
      guideLayoutMode: GuideLayoutMode.overlay,
      reduceMotion: true,
    );
    channels = fixtureChannels;
    currentChannelId = fixtureChannels[1].id;
  }

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async => buildSchedule(
    (channel.source as ManualSource).items,
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
  );

  @override
  Future<Uint8List?> artworkForPath(Uri path) async => _posterBytes;
}
