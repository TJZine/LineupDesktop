import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

import '../support/golden_test_support.dart';
import '../support/ui_fixture.dart';

final _origin = DateTime(2026, 1, 15, 9);
const _handheld = DeviceProfile(
  host: TargetPlatform.android,
  formFactor: FormFactor.handheld,
);

class _RuntimeFixture extends FixtureController {
  _RuntimeFixture()
    : super(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          currentChannelId: 'ch-1',
          settings: const LineupSettings(reduceMotion: true),
          channels: [
            for (var i = 1; i <= 8; i++)
              Channel(
                id: 'ch-$i',
                number: i,
                name: 'Fixture Channel $i',
                source: ManualSource([
                  ChannelItem(
                    id: '$i-now',
                    title: 'Synthetic Now $i',
                    duration: const Duration(minutes: 30),
                  ),
                  ChannelItem(
                    id: '$i-later',
                    title: 'Synthetic Later $i',
                    duration: const Duration(minutes: 30),
                  ),
                ]),
                playbackMode: PlaybackMode.sequential,
                anchor: _origin,
                shuffleSeed: i,
              ),
          ],
        ),
      );

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async =>
      buildChannelSchedule(channel, (channel.source as ManualSource).items);

  @override
  LineupPlaybackRequest playbackFor(String itemId) =>
      LineupPlaybackRequest.parts([
        LineupPlaybackPart(uri: Uri.parse('https://synthetic.invalid/$itemId')),
      ]);
}

class _RuntimeFixturePlayer extends FixturePlayer {
  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
    Duration? startPosition,
  }) async {
    await super.load(
      media,
      plexToken: plexToken,
      generation: generation,
      startPaused: startPaused,
      startPosition: startPosition,
    );
    emit(
      const PlayerStatus(state: PlayerState.playing, message: 'Synthetic'),
      position: startPosition,
      duration: const Duration(minutes: 2),
      eventGeneration: generation,
    );
  }
}

void main() {
  setUpAll(loadPinnedTestFonts);
  for (final expiresWhileClosing in [false, true]) {
    testWidgets(
      'Watch waits through metrics while closing, expired=$expiresWhileClosing',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final semantics = tester.ensureSemantics();
        final controller = _RuntimeFixture();
        final player = _RuntimeFixturePlayer();
        var now = _origin.add(const Duration(seconds: 35));
        tester.view
          ..devicePixelRatio = 2.625
          ..physicalSize = const Size(1080, 2400)
          ..padding = const FakeViewPadding(top: 126, bottom: 63)
          ..viewPadding = const FakeViewPadding(top: 126, bottom: 63);
        addTearDown(tester.view.reset);
        try {
          final app = UiFixture(
            controller: controller,
            profile: _handheld,
            player: player,
            guideClock: () => now,
          );
          await tester.pumpWidget(app.build());
          await tester.pumpAndSettle();
          expect(find.byType(GuideView), findsOneWidget);
          await tester.tap(
            find.bySemanticsLabel(
              RegExp(r'^Channel 3, Fixture Channel 3\. Watch\.$'),
            ),
          );
          await tester.pumpAndSettle();
          expect(player.loads, hasLength(1));
          expect(find.byType(PlayerView), findsOneWidget);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(GuideView), findsOneWidget);
          expect(
            find.byKey(const Key('guide-picture-in-picture')),
            findsOneWidget,
          );
          await tester.tap(
            find.bySemanticsLabel(
              RegExp(r'Synthetic Later 1, channel 1\. Starts'),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('handheld-program-sheet')),
            findsOneWidget,
          );
          final watch = find.byKey(const Key('handheld-program-watch'));
          expect(watch.hitTestable(), findsOneWidget);
          await tester.tap(watch);
          await tester.pump();
          expect(find.byType(GuideView), findsOneWidget);
          expect(find.byType(PlayerView), findsNothing);
          expect(player.loads, hasLength(1));
          expect(
            find.byKey(const Key('handheld-program-sheet')),
            findsOneWidget,
            reason: 'Watch must exercise the actual reverse transition',
          );
          await tester.pump(const Duration(milliseconds: 48));
          tester.view
            ..padding = const FakeViewPadding()
            ..viewPadding = const FakeViewPadding(top: 126, bottom: 63);
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull);
          if (expiresWhileClosing) {
            now = _origin.add(const Duration(hours: 1));
          }
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('handheld-program-sheet')), findsNothing);
          expect(
            find.byType(GuideView),
            expiresWhileClosing ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(PlayerView),
            expiresWhileClosing ? findsNothing : findsOneWidget,
          );
          expect(player.loads, hasLength(expiresWhileClosing ? 1 : 2));
          expect(
            controller.currentChannelId,
            expiresWhileClosing ? 'ch-3' : 'ch-1',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        } finally {
          semantics.dispose();
          controller.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
