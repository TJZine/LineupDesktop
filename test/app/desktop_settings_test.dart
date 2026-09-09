import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_shell.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';

import '../support/ui_fixture.dart';

const _longProfileName =
    'A deliberately long Plex Home profile name for the desktop settings acceptance fixture';
const _longAccountName =
    'A deliberately long signed-in Plex account name for the desktop settings acceptance fixture';
const _longServerName =
    'A deliberately long Plex Media Server name for the desktop settings acceptance fixture';

void main() {
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
    final semantics = tester.ensureSemantics();
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

    for (final category in SettingsCategory.values.skip(1)) {
      final categoryButton = find.widgetWithText(
        OutlinedButton,
        _categoryLabel(category),
      );
      await tester.ensureVisible(categoryButton);
      await tester.tap(categoryButton);
      await tester.pumpAndSettle();
      final contentFinder = find.text(_categoryContent(category));
      await tester.ensureVisible(contentFinder);
      expect(contentFinder, findsOneWidget);
      if (category == SettingsCategory.account) {
        expect(find.text(_longProfileName), findsOneWidget);
        expect(find.text(_longAccountName), findsOneWidget);
        expect(find.textContaining(_longServerName), findsOneWidget);
      }
    }
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

Future<void> _showSettings(
  WidgetTester tester,
  FixtureController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
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
