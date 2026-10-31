import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channels_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/handheld_navigation.dart';
import 'package:lineup_desktop/app/navigation_shortcuts.dart';
import 'package:lineup_desktop/app/settings_view.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/native_video_surface.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/playback/subtitle_cues.dart';
import 'package:lineup_desktop/playback/subtitle_layer.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import 'package:lineup_desktop/ui/lineup_controls.dart';

import '../support/ui_fixture.dart';

const _handheld = DeviceProfile(
  host: TargetPlatform.android,
  formFactor: FormFactor.handheld,
);
final _now = DateTime.utc(2026, 1, 15, 3, 17);

void main() {
  const platform = MethodChannel('lineup/platform');
  var backgrounded = 0;
  setUp(() {
    backgrounded = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'moveTaskToBack') backgrounded++;
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);
  });

  void navigationTest(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(tester);
      } finally {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> tab(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(ValueKey('handheld-tab-$name')));
    await tester.pumpAndSettle();
  }

  // 800x1280 exercises the approved tablet bar without attributing existing
  // phone Channels/UI-B overflows to the new navigation foundation.
  navigationTest(
    'portrait tablet tabs, mini player and surface transfer add no history or reload',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(800, 1280);
      addTearDown(tester.view.reset);
      final fixture = _ready();
      final elsewhere = FocusNode(debugLabel: 'Unrelated Back focus');
      addTearDown(elsewhere.dispose);
      await tester.pumpWidget(
        Focus(focusNode: elsewhere, child: fixture.build()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HandheldTabBar), findsOneWidget);
      expect(find.byTooltip('Open Lineup menu'), findsNothing);
      expect(find.byType(HandheldMiniPlayer), findsNothing);
      expect(find.byType(NativeVideoSurface), findsOneWidget);
      final loads = fixture.player.loads.length;
      final selection = fixture.controller.currentChannelId;
      final rectStart = fixture.player.videoRects.length;

      await tab(tester, 'channels');
      expect(find.byType(ChannelsView), findsOneWidget);
      expect(find.byType(HandheldMiniPlayer), findsOneWidget);
      expect(find.byType(NativeVideoSurface), findsOneWidget);
      expect(find.byTooltip('Open Lineup menu'), findsNothing);
      final thumbnail = tester.getRect(
        find.descendant(
          of: find.byType(HandheldMiniPlayer),
          matching: find.byType(NativeVideoSurface),
        ),
      );
      expect(thumbnail.width / thumbnail.height, closeTo(16 / 9, .001));
      final cues = SubtitleCues([
        SubtitleCue(
          align: 2,
          lines: [
            [const SubtitleSegment(text: 'Live cue')],
          ],
        ),
      ]);
      fixture.player.emitSubtitleCues(cues);
      await tester.pumpAndSettle();
      final liveCaptions = find.descendant(
        of: find.byType(HandheldMiniPlayer),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is SubtitlePainter,
        ),
      );
      expect(liveCaptions, findsOneWidget);
      await tab(tester, 'settings');
      expect(find.byType(SettingsView), findsOneWidget);
      expect(find.byType(HandheldMiniPlayer), findsOneWidget);
      expect(find.byType(NativeVideoSurface), findsOneWidget);
      expect(liveCaptions, findsNothing);
      expect(fixture.player.subtitleCues.value, same(cues));
      expect(find.text('‹ Back to Channels'), findsNothing);
      await tester.tap(find.byKey(const Key('handheld-mini-playback')));
      await tester.pumpAndSettle();
      expect(fixture.player.pauseCalls, 1);
      await tester.tap(find.byKey(const Key('handheld-mini-open')));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerView), findsOneWidget);
      expect(find.byType(HandheldTabBar), findsNothing);
      expect(find.byType(HandheldMiniPlayer), findsNothing);
      expect(find.byType(NativeVideoSurface), findsOneWidget);
      elsewhere.requestFocus();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(HandheldTabBar), findsOneWidget);
      expect(find.byType(HandheldMiniPlayer), findsNothing);
      await tab(tester, 'channels');
      await tab(tester, 'settings');
      elsewhere.requestFocus();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsView), findsNothing);
      expect(find.byType(ChannelsView), findsNothing);
      expect(backgrounded, 0);
      expect(fixture.controller.currentChannelId, selection);
      expect(fixture.player.loads.length, loads);
      expect(fixture.player.stops, 0);
      final transfers = fixture.player.videoRects.skip(rectStart).toList();
      expect(transfers, isNotEmpty);
      expect(
        transfers.every((rect) => rect.width > 0 && rect.height > 0),
        isTrue,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(backgrounded, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  navigationTest(
    'resize keeps the Settings element and selection while transferring its output',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(800, 1280);
      addTearDown(tester.view.reset);
      final fixture = _ready();
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await tab(tester, 'settings');
      final state = tester.state(find.byType(SettingsView));
      final loads = fixture.player.loads.length;
      final rectStart = fixture.player.videoRects.length;
      for (final size in [
        const Size(1280, 800),
        const Size(960, 600),
        const Size(800, 1280),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(SettingsView)), same(state));
        expect(find.byType(NativeVideoSurface), findsOneWidget);
        final aperture = tester.getRect(find.byType(NativeVideoSurface));
        final published = fixture.player.videoRects.last;
        expect(published.left, closeTo(aperture.left, .001));
        expect(published.top, closeTo(aperture.top, .001));
        expect(published.width, closeTo(aperture.width, .001));
        expect(published.height, closeTo(aperture.height, .001));
        expect(
          find.byType(HandheldTabBar),
          size.height > size.width ? findsOneWidget : findsNothing,
        );
        expect(fixture.player.loads.length, loads);
        expect(fixture.player.stops, 0);
      }
      final transfers = fixture.player.videoRects.skip(rectStart).toList();
      expect(transfers, isNotEmpty);
      expect(
        transfers.every((rect) => rect.width > 0 && rect.height > 0),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final scale in [1.0, 1.3, 2.0]) {
    navigationTest(
      'phone mini player keeps one 16:9 output and accessible separate actions at text $scale',
      (tester) async {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = const Size(360, 800);
        addTearDown(tester.view.reset);
        final fixture = _ready();
        final guide = GuideController(
          lineup: fixture.controller,
          clock: () => _now,
        );
        final player = PlayerCoordinator(
          player: fixture.player,
          lineup: fixture.controller,
          guide: guide,
          clock: () => _now,
        );
        var opened = 0;
        await tester.pumpWidget(
          DeviceProfileScope(
            profile: _handheld,
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: LineupCanvas(child: child!),
              ),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: HandheldMiniPlayer(
                    controller: player,
                    onOpenPlayer: () => opened++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final mini = tester.getRect(
          find.byKey(const Key('handheld-mini-player')),
        );
        expect(mini.height, closeTo(76 * scale.clamp(1, 1.3) * .9, .001));
        final output = tester.getRect(find.byType(NativeVideoSurface));
        expect(output.width / output.height, closeTo(16 / 9, .001));
        final open = find.byKey(const Key('handheld-mini-open'));
        final pause = find.byKey(const Key('handheld-mini-playback'));
        for (final target in [
          open,
          find
              .ancestor(of: pause, matching: find.byType(LineupTouchTarget))
              .first,
        ]) {
          final rect = tester.getRect(target);
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
        }
        await tester.tap(pause);
        await tester.pumpAndSettle();
        expect(fixture.player.pauseCalls, 1);
        expect(opened, 0);
        await tester.tap(open);
        expect(opened, 1);
        expect(find.byType(NativeVideoSurface), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        player.dispose();
        guide.dispose();
        await fixture.player.dispose();
        fixture.controller.dispose();
      },
    );
  }

  for (final size in [const Size(360, 800), const Size(800, 1280)]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      navigationTest(
        'tabs grow locally with safe bottom and 48dp targets at $size text $scale',
        (tester) async {
          tester.view
            ..devicePixelRatio = 1
            ..physicalSize = size;
          addTearDown(tester.view.reset);
          ShellDestination? selected;
          await tester.pumpWidget(
            DeviceProfileScope(
              profile: _handheld,
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(bottom: 24),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: LineupCanvas(child: child!),
                ),
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: HandheldTabBar(
                      destination: ShellDestination.guide,
                      onSelect: (value) => selected = value,
                    ),
                  ),
                ),
              ),
            ),
          );
          final bar = tester.getRect(find.byKey(const Key('handheld-tab-bar')));
          expect(bar.height, closeTo(78 * scale.clamp(1, 1.3) * .9, .001));
          expect(bar.bottom, closeTo(size.height - 24, .001));
          for (final name in ['guide', 'channels', 'settings']) {
            final target = find.byKey(ValueKey('handheld-tab-$name'));
            final rect = tester.getRect(target);
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
            await tester.tap(target);
          }
          expect(selected, ShellDestination.settings);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

UiFixture _ready() => UiFixture(
  profile: _handheld,
  player: FixturePlayer.preloaded()
    ..emit(const PlayerStatus(state: PlayerState.playing, message: 'Ready')),
  guideClock: () => _now,
  scenario: LineupScenario(
    stage: SetupStage.ready,
    settings: const LineupSettings(reduceMotion: true),
    currentChannelId: 'channel',
    channels: [
      Channel(
        id: 'channel',
        number: 7,
        name: 'Channel',
        source: const ManualSource([
          ChannelItem(
            id: 'program',
            title: 'Program',
            duration: Duration(hours: 24),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: _now.subtract(const Duration(hours: 1)),
        shuffleSeed: 1,
      ),
    ],
  ),
);
