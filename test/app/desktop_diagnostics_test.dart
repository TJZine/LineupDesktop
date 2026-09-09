import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/diagnostics_view.dart';
import 'package:lineup_desktop/diagnostics/diagnostics.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';

import '../support/ui_fixture.dart';

void main() {
  Future<void> show(WidgetTester tester, FixtureController controller) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(
          LineupThemeName.emberSteel,
          largeFocusIndicators: false,
        ),
        home: RepaintBoundary(
          key: const Key('diagnostic-render'),
          child: Scaffold(
            body: DiagnosticsView(
              controller: controller,
              playback: const PlaybackDiagnosticSnapshot(
                state: PlayerState.stopped,
              ),
              onRecordingSettings: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('diagnostics exposes its report and technical details', (
    tester,
  ) async {
    final controller = FixtureController();
    addTearDown(controller.dispose);
    await show(tester, controller);
    await tester.pumpAndSettle();
    expect(find.text('Copy redacted report'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Technical details'), 200);
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'copy failure retains context and retry produces an allowlisted snapshot',
    (tester) async {
      final controller = FixtureController()
        ..server = const PlexServer(
          id: 'synthetic',
          name: 'Private Server Sentinel',
          connections: [],
        );
      addTearDown(controller.dispose);
      var failures = true;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            if (failures) throw PlatformException(code: 'unavailable');
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await show(tester, controller);
      await tester.tap(find.text('Copy redacted report'));
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t copy the report. Try again.'), findsOneWidget);
      expect(find.text('Diagnostics'), findsOneWidget);
      failures = false;
      await tester.tap(find.text('Copy redacted report'));
      await tester.pumpAndSettle();
      expect(find.text('Report copied'), findsOneWidget);
      expect(copied, contains('Playback state: stopped'));
      expect(copied, contains('Playback method: Unknown'));
      expect(copied, isNot(contains(controller.server!.name)));
    },
  );

  testWidgets(
    'arriving events preserve an expanded event until explicitly refreshed',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = FixtureController();
      addTearDown(controller.dispose);
      controller.diagnostics.enabled = true;
      controller.diagnostics.add('application', 'Operation failed', {
        'code': 'unexpected',
      });
      await show(tester, controller);
      await tester.tap(find.text('application: Operation failed'));
      await tester.pumpAndSettle();
      expect(find.text('code: unexpected'), findsOneWidget);
      final oldPosition = tester.getTopLeft(
        find.text('application: Operation failed'),
      );
      controller.diagnostics.add('plex-auth', 'PIN cancellation failed');
      await tester.pumpAndSettle();
      expect(find.text('1 new event'), findsOneWidget);
      expect(find.text('code: unexpected'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('application: Operation failed')),
        oldPosition,
      );
      expect(find.text('plex-auth: PIN cancellation failed'), findsNothing);
      await tester.tap(find.text('1 new event'));
      await tester.pumpAndSettle();
      expect(find.text('plex-auth: PIN cancellation failed'), findsOneWidget);
      controller.diagnostics.enabled = false;
      await tester.pumpAndSettle();
      expect(find.text('application: Operation failed'), findsNothing);
      expect(find.textContaining('Recording is off.'), findsOneWidget);
    },
  );
}
