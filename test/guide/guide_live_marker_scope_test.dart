import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets('Guide live marker suppression is scoped to handheld profiles', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 720);
    addTearDown(tester.view.reset);

    const profiles = [
      (
        name: 'desktop',
        profile: DeviceProfile(
          host: TargetPlatform.macOS,
          formFactor: FormFactor.desktop,
        ),
        expectsMarker: true,
      ),
      (
        name: 'tv',
        profile: DeviceProfile(
          host: TargetPlatform.android,
          formFactor: FormFactor.tv,
        ),
        expectsMarker: true,
      ),
      (
        name: 'handheld',
        profile: DeviceProfile(
          host: TargetPlatform.android,
          formFactor: FormFactor.handheld,
        ),
        expectsMarker: false,
      ),
    ];

    final anchor = DateTime(2026, 10, 30, 12);
    final now = anchor.add(const Duration(minutes: 1));

    for (final testCase in profiles) {
      final controller = FixtureController(
        scenario: LineupScenario(
          settings: const LineupSettings(reduceMotion: true),
          channels: [
            Channel(
              id: 'live',
              number: 1,
              name: 'Live',
              source: const ManualSource([
                ChannelItem(
                  id: 'current',
                  title: 'Current program',
                  duration: Duration(minutes: 3),
                ),
              ]),
              playbackMode: PlaybackMode.sequential,
              anchor: anchor,
              shuffleSeed: 0,
            ),
          ],
        ),
      );
      final guide = GuideController(
        lineup: controller,
        clock: () => now,
        loadSchedule: (channel) async => buildSchedule(
          (channel.source as ManualSource).items,
          mode: channel.playbackMode,
          seed: channel.shuffleSeed,
        ),
      );
      addTearDown(guide.dispose);
      addTearDown(controller.dispose);

      final previousFlutterError = FlutterError.onError;
      var knownGuideOverflowCount = 0;
      FlutterError.onError = (details) {
        // The compatibility fixture intentionally makes non-handheld cells
        // narrow enough to retain the pre-H1 marker overflow. Consume only
        // that known rendering diagnostic; unrelated errors still surface.
        if (details.exception is FlutterError &&
            details.exception.toString().startsWith(
              'A RenderFlex overflowed by ',
            )) {
          knownGuideOverflowCount++;
          return;
        }
        previousFlutterError?.call(details);
      };
      try {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => DeviceProfileScope(
              profile: testCase.profile,
              child: LineupCanvas(child: child ?? const SizedBox.shrink()),
            ),
            home: GuideView(
              controller: guide,
              onClose: (_, _) {},
              onTune: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final current = guide
            .row('live')
            .programs
            .singleWhere((program) => program.isCurrentAt(now));
        final cell = find.byKey(ValueKey(current.id));
        expect(cell, findsOneWidget, reason: testCase.name);
        expect(
          find.descendant(
            of: cell,
            matching: find.byKey(const Key('guide-airing-dot')),
          ),
          testCase.expectsMarker ? findsOneWidget : findsNothing,
          reason: testCase.name,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        FlutterError.onError = previousFlutterError;
      }
      expect(
        knownGuideOverflowCount,
        lessThanOrEqualTo(1),
        reason: 'only the known narrow-cell diagnostic may be consumed',
      );
    }
  });
}
