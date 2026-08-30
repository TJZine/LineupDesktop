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
      Theme.of(tester.element(find.byKey(const Key('classic-guide'))))
          .colorScheme
          .primary,
      emberSteel.colorScheme.primary,
    );

    await openDestination(tester, 'Settings');
    await tester.tap(find.byKey(const Key('theme-option-slate-pine')));
    await tester.pumpAndSettle();

    expect(fixture.controller.settings.theme, LineupThemeName.slatePine);
    expect(
      Theme.of(tester.element(find.byKey(const Key('theme-option-slate-pine'))))
          .colorScheme
          .primary,
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

  testWidgets('theme chooser exposes selection and remote-style traversal', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Settings');

    final emberSemantics = tester.widget<Semantics>(
      find.byKey(const Key('theme-option-semantics-ember-steel')),
    );
    final slateSemantics = tester.widget<Semantics>(
      find.byKey(const Key('theme-option-semantics-slate-pine')),
    );
    expect(emberSemantics.properties.button, isTrue);
    expect(emberSemantics.properties.selected, isTrue);
    expect(slateSemantics.properties.selected, isFalse);

    await tester.tap(find.byKey(const Key('theme-option-ember-steel')));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(fixture.controller.settings.theme, LineupThemeName.slatePine);
    expect(
      Focus.of(tester.element(find.byKey(const Key('theme-option-slate-pine'))))
          .hasFocus,
      isTrue,
    );
  });

  testWidgets('theme chooser applies every approved palette', (tester) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Settings');

    for (final theme in LineupThemeName.values.skip(1)) {
      final option = find.byKey(Key('theme-option-${theme.storageKey}'));
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();

      expect(fixture.controller.settings.theme, theme);
      final semantics = tester.widget<Semantics>(
        find.byKey(Key('theme-option-semantics-${theme.storageKey}')),
      );
      expect(semantics.properties.selected, isTrue);
    }
  });

  testWidgets('theme chooser remains reachable at accessible text scale', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 600);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Settings');

    final lastTheme = find.byKey(const Key('theme-option-glass'));
    await tester.ensureVisible(lastTheme);
    await tester.pumpAndSettle();

    expect(lastTheme, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Guide and player use the immersive shell policy', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('classic-guide')), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await openDestination(tester, 'Player');
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(const Key('player-app-menu')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const Key('player-app-menu')), findsOneWidget);
  });

  testWidgets('Settings uses one immersive rail without playback', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    await openDestination(tester, 'Settings');

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(PlayerSurface), findsNothing);
    expect(find.byType(PlayerView), findsNothing);
    expect(find.byKey(const Key('settings-category-rail')), findsOneWidget);
    expect(find.byKey(const Key('settings-detail-pane')), findsOneWidget);
  });

  testWidgets('Settings mounts one player surface behind its immersive rail', (
    tester,
  ) async {
    final player = FixturePlayer()
      ..emit(const PlayerStatus(state: PlayerState.ready, message: 'Ready'));
    final fixture = UiFixture(player: player)
      ..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    await openDestination(tester, 'Settings');

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(PlayerSurface), findsOneWidget);
    expect(find.byType(PlayerView), findsNothing);
    expect(find.byKey(const Key('settings-immersive-scrim')), findsOneWidget);
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const Key('settings-immersive-scrim')),
                )
                .decoration
            as BoxDecoration;
    expect(
      (decoration.gradient! as LinearGradient).colors,
      everyElement(predicate<Color>((color) => color.a < 1)),
    );
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
