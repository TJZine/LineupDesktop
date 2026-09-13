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
      expect(find.text('Diagnostics'), findsWidgets);
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
      final semantics = tester.ensureSemantics();

      await show(tester, controller);
      final time = controller.diagnostics.entries.single.time.toLocal();
      final timestamp = [
        time.hour,
        time.minute,
        time.second,
      ].map((part) => part.toString().padLeft(2, '0')).join(':');
      expect(find.text(timestamp), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp('${RegExp.escape(timestamp)}.*application: Operation failed'),
        ),
        findsOneWidget,
      );
      semantics.dispose();
      await tester.tap(find.text('Operation failed'));
      await tester.pumpAndSettle();
      expect(find.text('Code: unexpected', findRichText: true), findsOneWidget);
      final oldPosition = tester.getTopLeft(find.text('Operation failed'));
      controller.diagnostics.add('plex-auth', 'PIN cancellation failed');
      await tester.pumpAndSettle();
      expect(find.text('1 new event'), findsOneWidget);
      expect(find.text('Code: unexpected', findRichText: true), findsOneWidget);
      expect(tester.getTopLeft(find.text('Operation failed')), oldPosition);
      expect(find.text('PIN cancellation failed'), findsNothing);
      await tester.tap(find.text('1 new event'));
      await tester.pumpAndSettle();
      expect(find.text('PIN cancellation failed'), findsOneWidget);
      controller.diagnostics.enabled = false;
      await tester.pumpAndSettle();
      expect(find.text('Operation failed'), findsNothing);
      expect(find.text('Diagnostic recording is off'), findsOneWidget);
    },
  );
}
