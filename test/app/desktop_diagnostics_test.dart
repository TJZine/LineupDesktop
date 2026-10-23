import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
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
  Future<void> show(
    WidgetTester tester,
    FixtureController controller, {
    bool androidTv = false,
    VoidCallback? onRecordingSettings,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        theme: LineupTheme.forName(
          LineupThemeName.emberSteel,
          largeFocusIndicators: false,
          androidTv: androidTv,
        ),
        home: RepaintBoundary(
          key: const Key('diagnostic-render'),
          child: Scaffold(
            body: DiagnosticsView(
              controller: controller,
              playback: const PlaybackDiagnosticSnapshot(
                state: PlayerState.stopped,
              ),
              onRecordingSettings: onRecordingSettings ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'TV arrows read the full technical panel and reach recording settings',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 2;
      try {
        final controller = FixtureController();
        addTearDown(controller.dispose);
        var recordingCalls = 0;
        await show(
          tester,
          controller,
          androidTv: true,
          onRecordingSettings: () => recordingCalls++,
        );
        await tester.pumpAndSettle();
        Future<void> key(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }

        bool focusedIn(Finder finder) {
          final target = tester.element(finder);
          final primary =
              FocusManager.instance.primaryFocus?.context as Element?;
          var inside = identical(target, primary);
          primary?.visitAncestorElements((e) {
            inside |= identical(e, target);
            return !inside;
          });
          return inside;
        }

        final copy = find.widgetWithText(FilledButton, 'Copy redacted report');
        final technical = find.byKey(
          const PageStorageKey('diagnostic-technical-details'),
        );
        final recording = find.widgetWithText(TextButton, 'Recording settings');
        // Enter through normal remote traversal, with no pointer or requestFocus.
        await key(LogicalKeyboardKey.arrowDown);
        expect(focusedIn(copy), isTrue);
        await key(LogicalKeyboardKey.arrowDown);
        expect(focusedIn(technical), isTrue);
        await key(LogicalKeyboardKey.select);
        final list = tester.widget<ListView>(find.byType(ListView));
        final scroll = list.controller!;
        final start = scroll.offset;
        await key(LogicalKeyboardKey.arrowDown);
        expect(scroll.offset, greaterThan(start));
        final viewport = tester.getRect(find.byType(ListView));
        var sawLowerDetails = false;
        var sawEvents = false;
        for (var i = 0; i < 60; i++) {
          for (final pair in [
            (
              find.byKey(
                const ValueKey('diagnostics-technical-fact-Renderer output'),
              ),
              true,
            ),
            (find.text('Recent events'), false),
          ]) {
            if (pair.$1.evaluate().isNotEmpty) {
              final rect = tester.getRect(pair.$1);
              final visible =
                  rect.top >= viewport.top && rect.bottom <= viewport.bottom;
              if (pair.$2) {
                sawLowerDetails |= visible;
              } else {
                sawEvents |= visible;
              }
            }
          }
          if (scroll.offset >= scroll.position.maxScrollExtent) break;
          await key(LogicalKeyboardKey.arrowDown);
        }
        expect(sawLowerDetails, isTrue);
        expect(sawEvents, isTrue);
        expect(focusedIn(technical), isTrue);
        await key(LogicalKeyboardKey.arrowDown);
        expect(focusedIn(recording), isTrue);
        await key(LogicalKeyboardKey.select);
        expect(recordingCalls, 1);
        await key(LogicalKeyboardKey.arrowUp);
        expect(focusedIn(technical), isTrue);
        // Reverse reading while the existing expanded toggle retains ownership.
        for (var i = 0; i < 60 && scroll.offset > 0; i++) {
          await key(LogicalKeyboardKey.arrowUp);
        }
        expect(scroll.offset, 0);
        await key(LogicalKeyboardKey.arrowUp);
        expect(focusedIn(copy), isTrue);
        // Select still collapses the panel; ordinary traversal then reaches the
        // interactive control below it without swallowing its activation.
        await key(LogicalKeyboardKey.arrowDown);
        await key(LogicalKeyboardKey.select);
        await key(LogicalKeyboardKey.arrowDown);
        expect(focusedIn(recording), isTrue);
        await key(LogicalKeyboardKey.select);
        expect(recordingCalls, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

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
    for (final row in ['Windows display', 'HDR matching', 'Renderer output']) {
      expect(find.text(row), findsOneWidget);
    }
    expect(
      find.text(
        "Display state is reported by Windows; it does not verify the TV's picture.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('macOS technical details report HDR output as OS-managed', (
    tester,
  ) async {
    final controller = FixtureController();
    addTearDown(controller.dispose);
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await show(tester, controller);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Technical details'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('HDR output'), findsOneWidget);
      expect(find.text('Managed by macOS'), findsOneWidget);
      expect(find.text('Renderer output'), findsOneWidget);
      expect(find.text('Windows display'), findsNothing);
      expect(find.text('HDR matching'), findsNothing);
      expect(
        find.text(
          'macOS manages HDR output; Lineup does not change display modes.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('reported by Windows'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'copy failure retains context and retry produces an allowlisted snapshot',
    (tester) async {
      final controller = FixtureController(
        scenario: LineupScenario(
          server: const PlexServer(
            id: 'synthetic',
            name: 'Private Server Sentinel',
            connections: [],
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.diagnostics.enabled = true;
      controller.diagnostics.add(DiagnosticEvent.pinCancellationFailed, {
        'code': 'auth-denied',
      });
      controller.diagnostics.add(DiagnosticEvent.playbackRequestFailed, {
        'operation': 'audio_track',
        'code': 'command_error',
      });
      controller.diagnostics.add(DiagnosticEvent.nativePlaybackFailed, {
        'failureCode': 'safe-looking-private-sentinel',
      });
      controller.diagnostics.add(
        DiagnosticEvent.someCollectionsCouldNotBeLoaded,
        {'count': 2},
      );
      controller.diagnostics.add(DiagnosticEvent.castPortraitUnavailable, {
        'code': 'portrait_https',
        'failureCode': 'unavailable',
        'count': 1,
      });
      controller.diagnostics.add(DiagnosticEvent.castPortraitUnavailable, {
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
      expect(
        copied,
        contains('plex-auth: PIN cancellation failed (code=auth-denied)'),
      );
      expect(copied, contains('operation=audio_track, code=command_error'));
      expect(copied, isNot(contains('safe-looking-private-sentinel')));
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
      controller.diagnostics.add(DiagnosticEvent.operationFailed, {
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
      controller.diagnostics.add(DiagnosticEvent.pinCancellationFailed);
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
        controller.diagnostics.add(DiagnosticEvent.operationFailed, {
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
          controller.diagnostics.add(DiagnosticEvent.pinCancellationFailed);
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
    controller.diagnostics.add(DiagnosticEvent.guideScheduleLoadTimedOut);
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
