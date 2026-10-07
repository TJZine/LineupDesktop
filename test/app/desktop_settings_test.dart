import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import 'package:lineup_desktop/app/lineup_shell.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/lineup_controls.dart';

import '../support/ui_fixture.dart';

const _longProfileName =
    'A deliberately long Plex Home profile name for the desktop settings acceptance fixture';
const _longAccountName =
    'A deliberately long signed-in Plex account name for the desktop settings acceptance fixture';
const _longServerName =
    'A deliberately long Plex Media Server name for the desktop settings acceptance fixture';

void main() {
  testWidgets('Guide source switch uses optimistic save and failure rollback', (
    tester,
  ) async {
    final store = _DelayedSettingsStore();
    final controller = FixtureController(store: store);
    addTearDown(controller.dispose);
    await _showSettings(tester, controller);
    await _openCategory(tester, SettingsCategory.guide);
    final toggle = find.byType(Switch).first;
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(
      find.text(
        "Show where each channel's programs come from under its name in the Guide.",
      ),
      findsOneWidget,
    );
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(tester.widget<Switch>(toggle).onChanged, isNull);
    expect(controller.settings.guideShowChannelSources, isFalse);
    store.pending.completeError(StateError('synthetic save failure'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(tester.widget<Switch>(toggle).onChanged, isNotNull);
    store.pending = Completer<void>();
    await tester.tap(toggle);
    await tester.pump();
    store.pending.complete();
    await tester.pumpAndSettle();
    expect(controller.settings.guideShowChannelSources, isTrue);
    expect(store.state.settings.guideShowChannelSources, isTrue);
  });

  testWidgets('Settings categories and theme control remain accessible', (
    tester,
  ) async {
    final controller = FixtureController()
      ..account = const PlexAccount(
        id: 'account',
        name: _longAccountName,
        email: 'synthetic@example.invalid',
      )
      ..profile = const PlexHomeUser(
        id: 'profile',
        name: _longProfileName,
        protected: false,
      )
      ..server = PlexServer(
        id: 'server',
        name: _longServerName,
        owned: true,
        connections: [
          PlexConnection(
            uri: Uri.parse('https://synthetic.invalid:32400'),
            local: false,
            relay: false,
          ),
        ],
      )
      ..connection = PlexConnection(
        uri: Uri.parse('https://synthetic.invalid:32400'),
        local: false,
        relay: false,
      );
    addTearDown(controller.dispose);

    await _showSettings(tester, controller);
    final themeDropdown = find.byType(DropdownButton<LineupThemeName>);
    await tester.ensureVisible(themeDropdown);
    final theme = tester.widget<DropdownButton<LineupThemeName>>(themeDropdown);
    expect(theme.value, LineupThemeName.emberSteel);
    expect(theme.onChanged, isNotNull);
    expect(
      tester
          .getSemantics(themeDropdown)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(
      tester.getSemantics(themeDropdown).getSemanticsData().label,
      contains('Theme'),
    );

    for (final category in SettingsCategory.values.skip(1)) {
      final categoryButton = find.widgetWithText(
        TextButton,
        _categoryLabel(category),
      );
      await tester.ensureVisible(categoryButton);
      await tester.tap(categoryButton);
      await tester.pumpAndSettle();
      final contentFinder = find.text(_categoryContent(category));
      await tester.ensureVisible(contentFinder);
      expect(contentFinder, findsOneWidget);
      if (category == SettingsCategory.account) {
        expect(find.byType(LineupProfileAvatar), findsOneWidget);
        expect(find.text(_longProfileName), findsOneWidget);
        expect(find.text(_longAccountName), findsOneWidget);
        expect(find.textContaining(_longServerName), findsOneWidget);
      }
    }
    expect(tester.takeException(), isNull);
  }, semanticsEnabled: true);

  testWidgets('Settings switches expose names, state, and activation', (
    tester,
  ) async {
    final controller = FixtureController();
    addTearDown(controller.dispose);

    await _showSettings(tester, controller);
    await _openCategory(tester, SettingsCategory.accessibility);

    final reduceMotion = find.byType(Switch).first;
    var semantics = tester.getSemantics(reduceMotion).getSemanticsData();
    expect(semantics.label, contains('Reduce motion'));
    expect(semantics.flagsCollection.isToggled, Tristate.isFalse);
    expect(semantics.flagsCollection.isEnabled, Tristate.isTrue);
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(reduceMotion);
    await tester.pumpAndSettle();
    expect(controller.settings.reduceMotion, isTrue);
    semantics = tester.getSemantics(reduceMotion).getSemanticsData();
    expect(semantics.flagsCollection.isToggled, Tristate.isTrue);

    await _openCategory(tester, SettingsCategory.support);
    final diagnostics = find.byType(Switch).first;
    semantics = tester.getSemantics(diagnostics).getSemanticsData();
    expect(semantics.label, contains('Record redacted diagnostics'));
    expect(semantics.flagsCollection.isToggled, Tristate.isFalse);
    expect(semantics.flagsCollection.isEnabled, Tristate.isTrue);
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(diagnostics);
    await tester.pumpAndSettle();
    expect(controller.settings.diagnosticsEnabled, isTrue);
    semantics = tester.getSemantics(diagnostics).getSemanticsData();
    expect(semantics.flagsCollection.isToggled, Tristate.isTrue);
  }, semanticsEnabled: true);

  testWidgets('settings controls share one right edge across categories', (
    tester,
  ) async {
    final controller = FixtureController()
      ..account = const PlexAccount(
        id: 'account',
        name: _longAccountName,
        email: 'synthetic@example.invalid',
      )
      ..profile = const PlexHomeUser(
        id: 'profile',
        name: _longProfileName,
        protected: false,
      )
      ..server = const PlexServer(
        id: 'server',
        name: _longServerName,
        connections: [],
      );
    addTearDown(controller.dispose);

    await _showSettings(tester, controller);
    final dropdown = find.byKey(const ValueKey('settings-field-Theme'));
    await tester.ensureVisible(dropdown);
    final dropdownRight = tester.getRect(dropdown).right;

    final appearanceSwitch = find.byType(Switch).first;
    await tester.ensureVisible(appearanceSwitch);
    expect(tester.getRect(appearanceSwitch).right, closeTo(dropdownRight, 0.1));

    await _openCategory(tester, SettingsCategory.account);
    final profileButton = find.widgetWithText(OutlinedButton, 'Switch profile');
    await tester.ensureVisible(profileButton);
    expect(tester.getRect(profileButton).right, closeTo(dropdownRight, 0.1));
  });

  testWidgets(
    'visible hours menu keeps all choices and readable descriptions',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1280, 720)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = FixtureController();
      addTearDown(controller.dispose);

      await _showSettings(tester, controller);
      await _openCategory(tester, SettingsCategory.guide);
      final field = find.byKey(const ValueKey('settings-field-Visible hours'));
      await tester.ensureVisible(field);
      expect(find.text('Detailed (2 hours)'), findsOneWidget);
      await tester.tap(field);
      await tester.pumpAndSettle();

      expect(find.text('Detailed (2 hours)'), findsNWidgets(2));
      expect(find.text('Less schedule at once'), findsOneWidget);
      expect(find.text('Wide (3 hours)'), findsOneWidget);
      expect(find.text('Balanced schedule at once'), findsOneWidget);
      expect(find.text('Extended (4 hours)'), findsOneWidget);
      expect(find.text('More schedule at once'), findsOneWidget);
      expect(
        find.descendant(
          of: field,
          matching: find.text('Less schedule at once'),
        ),
        findsNothing,
      );
      expect(find.text('Saved setting'), findsNothing);
    },
  );
}

Future<void> _showSettings(
  WidgetTester tester,
  FixtureController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: LineupCanvas.builder,
      theme: LineupTheme.forName(
        LineupThemeName.emberSteel,
        largeFocusIndicators: false,
      ),
      home: RepaintBoundary(
        key: const Key('desktop-settings-render'),
        child: Scaffold(body: SettingsView(controller: controller)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCategory(
  WidgetTester tester,
  SettingsCategory category,
) async {
  final button = find.widgetWithText(TextButton, _categoryLabel(category));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

String _categoryLabel(SettingsCategory category) => switch (category) {
  SettingsCategory.appearance => 'Appearance',
  SettingsCategory.guide => 'Guide',
  SettingsCategory.playback => 'Playback',
  SettingsCategory.accessibility => 'Accessibility',
  SettingsCategory.account => 'Account',
  SettingsCategory.support => 'Support',
};

String _categoryContent(SettingsCategory category) => switch (category) {
  SettingsCategory.appearance => 'Use title artwork',
  SettingsCategory.guide => 'Show now playing in Guide',
  SettingsCategory.playback => 'DVR playback controls',
  SettingsCategory.accessibility => 'Large focus indicators',
  SettingsCategory.account => 'Signed-in Plex account',
  SettingsCategory.support => 'Diagnostics',
};

class _DelayedSettingsStore extends FixtureStore {
  Completer<void> pending = Completer<void>();
  @override
  Future<void> save(value) async {
    await pending.future;
    await super.save(value);
  }
}
