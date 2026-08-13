import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets('Settings applies and persists a theme immediately', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.text('Guide').first)).colorScheme.primary,
      const Color(0xFFE0782A),
    );

    await tester.tap(find.byKey(const Key('guide-app-menu')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<LineupThemeName>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slate & Pine').last);
    await tester.pumpAndSettle();

    expect(fixture.controller.settings.theme, LineupThemeName.slatePine);
    expect(
      Theme.of(tester.element(find.text('Theme'))).colorScheme.primary,
      const Color(0xFF809A79),
    );
  });

  testWidgets('Guide and player use the immersive shell policy', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('classic-guide')), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await tester.tap(find.byKey(const Key('guide-app-menu')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Player').last);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(const Key('player-app-menu')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const Key('player-app-menu')), findsOneWidget);
  });

  testWidgets('overlay Guide is secondary and keeps playback behind it', (
    tester,
  ) async {
    final player = FixturePlayer()
      ..emit(const PlayerStatus(state: PlayerState.ready, message: 'Ready'));
    final fixture = UiFixture(player: player)
      ..controller.stage = SetupStage.ready
      ..controller.settings = const LineupSettings(
        guideLayoutMode: GuideLayoutMode.overlay,
      );
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('overlay-guide')), findsOneWidget);
    expect(find.byType(PlayerSurface), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });
}
