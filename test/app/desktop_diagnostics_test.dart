import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
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
        builder: LineupCanvas.builder,
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
    expect(find.text('Recording off'), findsOneWidget);
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
      controller.diagnostics.enabled = true;
      controller.diagnostics.add('plex-auth', 'PIN cancellation failed');
      controller.diagnostics.add(
        'plex-library',
        'Some collections could not be loaded',
        {'count': 2},
      );
      controller.diagnostics.add('plex', 'Cast portrait unavailable', {
        'code': 'portrait_https',
        'failureCode': 'unavailable',
        'count': 1,
      });
      controller.diagnostics.add('plex', 'Cast portrait unavailable', {
        'code': 'portrait_unknown_secret',
        'failureCode': 'private-failure',
        'count': 1,
        'server': 'https://private.example/secret?X-Plex-Token=token-secret',
        'path': '/Users/private/title.mkv',
        'title': 'Private Title Sentinel',
      });
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
      expect(copied, contains('plex-auth: PIN cancellation failed'));
      expect(
        copied,
        contains(
          'plex-library: Some collections could not be loaded (count=2)',
        ),
      );
      expect(
        copied,
        contains(
          'plex: Cast portrait unavailable (code=portrait_https, '
          'failureCode=unavailable, count=1)',
        ),
      );
      expect(copied, isNot(contains('portrait_unknown_secret')));
      expect(copied, isNot(contains('private-failure')));
      expect(copied, isNot(contains('private.example')));
      expect(copied, isNot(contains('Private Title Sentinel')));
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
          RegExp('${RegExp.escape(timestamp)}.*Application: Operation failed'),
        ),
        findsOneWidget,
      );
      expect(find.text('Application'), findsOneWidget);
      expect(find.text('Recording on'), findsOneWidget);
      semantics.dispose();
      await tester.tap(find.text('Operation failed'));
      await tester.pumpAndSettle();
      expect(find.text('Code: unexpected', findRichText: true), findsOneWidget);
      final oldPosition = tester.getTopLeft(find.text('Operation failed'));
      final reservedSlot = tester.getRect(
        find.byKey(const ValueKey('diagnostics-new-events-slot')),
      );
      controller.diagnostics.add('plex-auth', 'PIN cancellation failed');
      await tester.pumpAndSettle();
      expect(find.text('1 new event'), findsOneWidget);
      expect(
        tester.getRect(
          find.byKey(const ValueKey('diagnostics-new-events-slot')),
        ),
        reservedSlot,
      );
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

  for (final size in [const Size(1280, 720), const Size(1920, 1080)]) {
    testWidgets(
      'new event count does not move the expanded reader at ${size.width}x${size.height} with enlarged text',
      (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final controller = FixtureController();
        addTearDown(controller.dispose);
        controller.diagnostics.enabled = true;
        controller.diagnostics.add('application', 'Operation failed', {
          'code': 'unexpected',
        });
        await show(tester, controller);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Operation failed'));
        await tester.tap(find.text('Operation failed'));
        await tester.pumpAndSettle();

        final readerPosition = tester.getTopLeft(
          find.text('Code: unexpected', findRichText: true),
        );
        final slotFinder = find.byKey(
          const ValueKey('diagnostics-new-events-slot'),
        );
        final initialSlot = tester.getRect(slotFinder);
        expect(initialSlot.height, greaterThan(0));

        for (var count = 1; count <= 10; count++) {
          controller.diagnostics.add('plex-auth', 'Synthetic event $count');
          await tester.pumpAndSettle();
          expect(
            find.text('$count new ${count == 1 ? 'event' : 'events'}'),
            findsOneWidget,
          );
          expect(tester.getRect(slotFinder), initialSlot);
          expect(
            tester.getTopLeft(
              find.text('Code: unexpected', findRichText: true),
            ),
            readerPosition,
          );
        }
      },
    );
  }

  testWidgets('technical details reuse the summary grid and media subcolumns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = FixtureController();
    addTearDown(controller.dispose);
    controller.diagnostics.enabled = true;
    controller.diagnostics.add('guide', 'Guide refreshed');
    await show(tester, controller);
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();

    final summaryPlayback = tester.getRect(
      find.byKey(const ValueKey('diagnostics-summary-Playback')),
    );
    final summaryVideo = tester.getRect(
      find.byKey(const ValueKey('diagnostics-summary-Video')),
    );
    final summarySignal = tester.getRect(
      find.byKey(const ValueKey('diagnostics-summary-Media signal')),
    );
    final application = tester.getRect(
      find.byKey(const ValueKey('diagnostics-technical-Application')),
    );
    final videoOutput = tester.getRect(
      find.byKey(const ValueKey('diagnostics-technical-Video output')),
    );
    final mediaSignal = tester.getRect(
      find.byKey(const ValueKey('diagnostics-technical-Media signal')),
    );

    expect(application.left, closeTo(summaryPlayback.left, 0.1));
    expect(videoOutput.left, closeTo(summaryVideo.left, 0.1));
    expect(mediaSignal.left, closeTo(summarySignal.left, 0.1));
    expect(
      tester
          .getRect(
            find.byKey(const ValueKey('diagnostics-technical-fact-Transfer')),
          )
          .width,
      closeTo(
        tester
            .getRect(
              find.byKey(
                const ValueKey('diagnostics-technical-fact-Pixel format'),
              ),
            )
            .width,
        0.1,
      ),
    );
    expect(
      tester
          .getRect(
            find.byKey(const ValueKey('diagnostics-technical-fact-Transfer')),
          )
          .left,
      lessThan(
        tester
            .getRect(
              find.byKey(
                const ValueKey('diagnostics-technical-fact-Pixel format'),
              ),
            )
            .left,
      ),
    );

    final technicalTile = tester.getRect(
      find.byKey(const PageStorageKey('diagnostic-technical-details')),
    );
    final event = controller.diagnostics.entries.single;
    await tester.ensureVisible(find.byKey(ObjectKey(event)));
    expect(
      tester.getRect(find.byKey(ObjectKey(event))).right,
      closeTo(technicalTile.right, 0.1),
    );
  });
}
