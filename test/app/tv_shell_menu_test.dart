import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/diagnostics_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/channel_studio_view.dart';
import 'package:lineup_desktop/app/settings_view.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/licenses/licenses_view.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
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
      final studio = find.byType(ChannelStudioView);
      expect(studio, findsOneWidget);
      final view = tester.widget<ChannelStudioView>(studio);
      expect(view.mode, ChannelStudioMode.editCustom);
      expect(view.channel?.id, 'custom');
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.byKey(const Key('studio-status-tag')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.header == true,
            ),
          ),
          matching: find.byWidgetPredicate(
            (widget) => widget is Text && widget.data == 'Synthetic channel',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('studio-status-tag')),
          matching: find.text('Saved'),
        ),
        findsOneWidget,
      );
      await toggle(studio);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDefaultTargetPlatformOverride = null;
      fixture.controller.dispose();
    }
  });

  testWidgets('TV Menu follows the active Settings and onboarding surface', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.reset);
    const profile = PlexHomeUser(
      id: 'synthetic-profile',
      name: 'Synthetic profile',
      protected: false,
    );
    final fixture = UiFixture(
      profile: tvProfile,
      scenario: const LineupScenario(
        stage: SetupStage.ready,
        profile: profile,
        profiles: [profile],
        settings: LineupSettings(reduceMotion: true),
      ),
    );
    addTearDown(fixture.controller.dispose);
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    final menu = find.byKey(const Key('immersive-app-menu'));
    Future<void> pressMenu() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await pressMenu();
    await tap(find.byKey(const Key('app-menu-account')));
    await tap(find.text('Sign out of Plex'));
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final confirmationFocus = FocusManager.instance.primaryFocus;
    await pressMenu();
    expect(dialog, findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(confirmationFocus));
    await tap(find.widgetWithText(TextButton, 'Cancel'));
    expect(menu, findsNothing);
    expect(fixture.controller.stage, SetupStage.ready);

    await tap(find.text('Switch profile'));
    expect(fixture.controller.stage, SetupStage.profiles);
    expect(find.byKey(const ValueKey('onboarding-app-menu')), findsOneWidget);
    await pressMenu();
    expect(menu, findsOneWidget);
    await pressMenu();
    expect(menu, findsNothing);
    await tap(find.widgetWithText(TextButton, 'Settings'));
    expect(find.text('Open Licenses'), findsOneWidget);
    expect(find.byTooltip('Open Lineup menu'), findsNothing);
    await pressMenu();
    expect(menu, findsNothing);
    expect(find.text('Open Licenses'), findsOneWidget);
    expect(fixture.controller.stage, SetupStage.profiles);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open Licenses'), findsNothing);
    expect(menu, findsNothing);
    await pressMenu();
    expect(menu, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
