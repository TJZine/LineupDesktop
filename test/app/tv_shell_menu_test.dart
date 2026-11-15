import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/diagnostics_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/settings_view.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/licenses/licenses_view.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets('TV Menu toggles the Lineup menu from each ready surface', (
    tester,
  ) async {
    final fixture = UiFixture(
      profile: tvProfile,
      player: FixturePlayer()
        ..emit(const PlayerStatus(state: PlayerState.ready, message: 'Ready')),
      scenario: LineupScenario(
        stage: SetupStage.ready,
        settings: const LineupSettings(reduceMotion: true),
        channels: [
          Channel(
            id: 'custom',
            number: 7,
            name: 'Synthetic channel',
            source: const ManualSource([]),
            playbackMode: PlaybackMode.sequential,
            anchor: DateTime.utc(2026, 1, 15),
            shuffleSeed: 0,
          ),
        ],
      ),
    );
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      const key = LogicalKeyboardKey.contextMenu;
      final menu = find.byKey(const Key('immersive-app-menu'));
      Future<void> toggle(Finder surface, {bool restoreFocus = true}) async {
        expect(surface, findsOneWidget);
        final previous = FocusManager.instance.primaryFocus;
        await tester.sendKeyDownEvent(key);
        await tester.pumpAndSettle();
        expect(menu, findsOneWidget);
        await tester.sendKeyRepeatEvent(key);
        await tester.pumpAndSettle();
        expect(menu, findsOneWidget);
        await tester.sendKeyUpEvent(key);
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(menu, findsNothing);
        expect(surface, findsOneWidget);
        if (restoreFocus) {
          expect(FocusManager.instance.primaryFocus, same(previous));
        }
      }

      await toggle(find.byKey(const Key('classic-guide')), restoreFocus: false);
      await openDestination(tester, 'Player');
      await toggle(find.byType(PlayerView), restoreFocus: false);
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await toggle(find.byType(SettingsView));

      await tester.tap(find.widgetWithText(TextButton, 'Support'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Diagnostics'));
      await tester.pumpAndSettle();
      await toggle(find.byType(DiagnosticsView));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Licenses'));
      await tester.pumpAndSettle();
      await toggle(find.byType(LicensesView));

      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage channels').last);
      await tester.pumpAndSettle();
      final channel = find.text('Synthetic channel');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await toggle(find.byKey(const Key('channels-app-menu')));
      await tester.tap(channel);
      await tester.pumpAndSettle();
      await toggle(find.text('Edit custom channel'));
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDefaultTargetPlatformOverride = null;
      fixture.controller.dispose();
    }
  });
}
