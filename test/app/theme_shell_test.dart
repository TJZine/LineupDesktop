import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets('Settings applies and persists a theme immediately', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    final emberSteel = LineupTheme.forName(LineupThemeName.emberSteel);
    final slatePine = LineupTheme.forName(LineupThemeName.slatePine);
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.text('Guide').first)).colorScheme.primary,
      emberSteel.colorScheme.primary,
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
      slatePine.colorScheme.primary,
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(
      fixture.controller.fixtureStore.state.settings.theme,
      LineupThemeName.slatePine,
    );

    final restored = FixtureController(
      store: fixture.controller.fixtureStore,
      restoreOnInitialize: true,
    );
    addTearDown(restored.dispose);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      UiFixture(controller: restored, player: FixturePlayer()).build(),
    );
    await tester.pumpAndSettle();
    expect(restored.settings.theme, LineupThemeName.slatePine);
    expect(
      Theme.of(
        tester.element(
          find.text('Your Plex library, scheduled like television'),
        ),
      ).colorScheme.primary,
      slatePine.colorScheme.primary,
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

  testWidgets('accessibility settings propagate through the application root', (
    tester,
  ) async {
    final fixture = UiFixture()
      ..controller.stage = SetupStage.ready
      ..controller.settings = const LineupSettings(
        reduceMotion: true,
        largeFocusIndicators: true,
      );
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    final context = tester.element(find.byKey(const Key('classic-guide')));
    final expectedTheme = LineupTheme.forName(
      LineupThemeName.emberSteel,
      largeFocusIndicators: true,
    );
    expect(MediaQuery.disableAnimationsOf(context), isTrue);
    expect(
      Theme.of(context).extension<LineupThemeRoles>()!.focusBorderWidth,
      expectedTheme.extension<LineupThemeRoles>()!.focusBorderWidth,
    );
  });
}
