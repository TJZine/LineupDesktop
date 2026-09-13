import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
    final themeDropdown = find.byType(DropdownButton<LineupThemeName>);
    await tester.tap(themeDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(LineupThemeName.slatePine.label).last);
    await tester.pumpAndSettle();

    expect(fixture.controller.settings.theme, LineupThemeName.slatePine);
    expect(
      Theme.of(tester.element(themeDropdown)).colorScheme.primary,
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

  testWidgets('theme dropdown exposes selection and keyboard traversal', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Settings');

    final dropdown = find.byType(DropdownButton<LineupThemeName>);
    final widget = tester.widget<DropdownButton<LineupThemeName>>(dropdown);
    expect(widget.value, LineupThemeName.emberSteel);
    expect(widget.onChanged, isNotNull);
    expect(
      tester
          .getSemantics(dropdown)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(fixture.controller.settings.theme, LineupThemeName.slatePine);
    expect(
      tester.widget<DropdownButton<LineupThemeName>>(dropdown).value,
      LineupThemeName.slatePine,
    );
  }, semanticsEnabled: true);

  testWidgets('theme dropdown applies every approved palette', (tester) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Settings');

    for (final theme in LineupThemeName.values.skip(1)) {
      final dropdown = find.byType(DropdownButton<LineupThemeName>);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(theme.label).last);
      await tester.pumpAndSettle();

      expect(fixture.controller.settings.theme, theme);
      expect(
        tester.widget<DropdownButton<LineupThemeName>>(dropdown).value,
        theme,
      );
    }
  });

  testWidgets('theme dropdown remains reachable at accessible text scale', (
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

    expect(find.byType(DropdownButton<LineupThemeName>), findsOneWidget);
    final menu = find.byKey(const Key('settings-app-menu'));
    expect(menu, findsOneWidget);
    final menuButton = tester.widget<TextButton>(menu);
    expect(menuButton.focusNode, isNotNull);
    menuButton.focusNode!.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(menuButton.focusNode));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings refreshes from controller setting changes', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Settings');
    await tester.tap(find.widgetWithText(TextButton, 'Guide'));
    await tester.pumpAndSettle();

    final guideHours = find.byType(DropdownButton<int>);
    expect(tester.widget<DropdownButton<int>>(guideHours).value, 2);

    await fixture.controller.updateSettings(
      fixture.controller.settings.copyWith(guideHours: 4),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<DropdownButton<int>>(guideHours).value, 4);
  });

  testWidgets('failed setting save restores value without moving focus', (
    tester,
  ) async {
    final controller = _DelayedSettingsController()..stage = SetupStage.ready;
    await tester.pumpWidget(UiFixture(controller: controller).build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Settings');

    final dropdown = find.byType(DropdownButton<LineupThemeName>);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(LineupThemeName.slatePine.label).last);
    await tester.pump(const Duration(milliseconds: 350));

    final focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull);
    expect(find.text('Saving…'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Playback'))
          .onPressed,
      isNotNull,
    );

    controller.fail();
    await tester.pumpAndSettle();
    expect(controller.settings.theme, LineupThemeName.emberSteel);
    expect(find.byKey(const Key('setting-error-theme')), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(focused));
    expect(
      tester.widget<DropdownButton<LineupThemeName>>(dropdown).value,
      LineupThemeName.emberSteel,
    );
  });

  testWidgets('Guide and player use the immersive shell policy', (
    tester,
  ) async {
    final player = FixturePlayer()
      ..emit(const PlayerStatus(state: PlayerState.ready, message: 'Ready'));
    final fixture = UiFixture(player: player)
      ..controller.stage = SetupStage.ready;
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

  testWidgets('Settings retains one mounted player surface', (tester) async {
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
  });

  testWidgets(
    'unavailable Guide picture preserves a truthful non-tunable state',
    (tester) async {
      final player = FixturePlayer()
        ..emit(
          const PlayerStatus(
            state: PlayerState.unsupported,
            message: 'Playback is not supported on this device.',
          ),
        );
      final fixture = UiFixture(player: player)
        ..controller.stage = SetupStage.ready
        ..controller.settings = const LineupSettings(reduceMotion: true);
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      expect(find.text('Playback unavailable'), findsOneWidget);
      expect(
        find.text('Playback is not supported on this device.'),
        findsOneWidget,
      );
      expect(find.byType(PlayerSurface), findsNothing);
      expect(find.text('Retry'), findsNothing);
      await openDestination(tester, 'Channels');
      expect(find.text('Playback unavailable'), findsNothing);
    },
  );

  testWidgets('legacy overlay preference still presents the PiP Guide', (
    tester,
  ) async {
    final player = FixturePlayer()
      ..emit(const PlayerStatus(state: PlayerState.ready, message: 'Ready'));
    final fixture = UiFixture(player: player)
      ..controller.stage = SetupStage.ready
      ..controller.settings = LineupSettings.fromJson({
        ...const LineupSettings().toJson(),
        'guideLayoutMode': 'overlay',
      });
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('classic-guide')), findsOneWidget);
    expect(find.byKey(const Key('overlay-guide')), findsNothing);
    expect(find.byKey(const Key('guide-picture-in-picture')), findsOneWidget);
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

class _DelayedSettingsController extends FixtureController {
  final _update = Completer<void>();

  @override
  Future<void> updateSettings(LineupSettings value) async {
    await _update.future;
  }

  void fail() => _update.completeError(StateError('synthetic save failure'));
}
