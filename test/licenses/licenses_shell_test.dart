import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/licenses/licenses_view.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

import '../support/ui_fixture.dart';
import '../support/golden_test_support.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lineup/platform');
  var backgrounds = 0;
  setUpAll(() async {
    await loadPinnedTestFonts();
    await rootBundle.loadString('assets/licenses/index.txt');
    LicenseRegistry.addLicense(
      () => Stream.value(
        LicenseEntryWithLineBreaks([
          'Fixture package',
        ], 'Copyright fixture\n\nComplete fixture package license.'),
      ),
    );
  });
  void macTest(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  setUp(() {
    backgrounds = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'moveTaskToBack') {
        backgrounds++;
        return true;
      }
      if (call.method == 'listLicenseDocuments') {
        return [
          {'id': 'info', 'path': 'BUILD-INFO.txt', 'bytes': 10},
          {
            'id': 'summary',
            'path': 'licenses/NOTICES-SUMMARY.txt',
            'bytes': 10,
          },
          {'id': 'license', 'path': 'licenses/mpv/LICENSE.LGPL', 'bytes': 100},
        ];
      }
      return 'Full offline license\n\nCopyright test';
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> escape(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  macTest(
    'ready shell pops each level, restores Support and preserves store/player',
    (tester) async {
      final fixture = UiFixture(
        scenario: const LineupScenario(stage: SetupStage.ready),
      );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await openDestination(tester, 'Settings');
      await tap(tester, 'Support');
      final saved = fixture.controller.fixtureStore.savedStates.length;
      final stops = fixture.player.stops;
      final loads = fixture.player.loads.length;
      await tap(tester, 'Open Licenses');
      await tap(tester, 'mpv');
      await tap(tester, 'LICENSE.LGPL');
      expect(find.text('Full offline license'), findsOneWidget);
      await escape(tester);
      expect(find.text('LICENSE.LGPL'), findsOneWidget);
      await escape(tester);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'mpv');
      expect(find.byType(LicensesView), findsOneWidget);
      await escape(tester);
      expect(find.byType(LicensesView), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Open Licenses');
      expect(fixture.controller.fixtureStore.savedStates.length, saved);
      expect(fixture.player.stops, stops);
      expect(fixture.player.loads.length, loads);
      await escape(tester);
      expect(find.byKey(const Key('classic-guide')), findsOneWidget);
    },
  );

  macTest(
    'first-run Settings Support requires no Plex session; late load can close',
    (tester) async {
      final fixture = UiFixture(
        scenario: const LineupScenario(stage: SetupStage.welcome),
      );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await tap(tester, 'Settings');
      expect(find.text('Open Licenses'), findsOneWidget);
      await tap(tester, 'Open Licenses');
      expect(find.text('Native runtime'), findsOneWidget);
      await escape(tester);
      await escape(tester);
      expect(
        find.text('Your Plex library, scheduled like television'),
        findsOneWidget,
      );
      expect(fixture.controller.stage, SetupStage.welcome);
      expect(fixture.controller.fixtureStore.savedStates, isEmpty);
    },
  );

  testWidgets('Android onboarding opens Support and offline licenses', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final fixture = UiFixture(
        profile: profileFor(true),
        scenario: const LineupScenario(stage: SetupStage.welcome),
      );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await tap(tester, 'Settings');
      expect(find.text('Open Licenses'), findsOneWidget);
      await tap(tester, 'Open Licenses');
      expect(find.text('Native runtime'), findsOneWidget);
      expect(find.text('Sources and rebuilding'), findsNothing);
      expect(find.text('Flutter and packages'), findsOneWidget);
      expect(find.text('Fonts and engine notices'), findsOneWidget);
      await tap(tester, 'Fonts and engine notices');
      expect(find.text('Instrument Sans'), findsOneWidget);
      expect(find.text('Inter'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await escape(tester);
      expect(find.byType(LicensesView), findsNothing);
      expect(find.text('Open Licenses'), findsOneWidget);
      expect(backgrounds, 0);
      await escape(tester);
      expect(
        find.text('Your Plex library, scheduled like television'),
        findsOneWidget,
      );
      expect(fixture.controller.stage, SetupStage.welcome);
      expect(backgrounds, 0);
      await escape(tester);
      expect(backgrounds, 1);
      expect(fixture.controller.stage, SetupStage.welcome);
      expect(fixture.controller.fixtureStore.savedStates, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  macTest('menu Esc precedes reader Back; Settings command dismisses reader', (
    tester,
  ) async {
    final fixture = UiFixture(
      scenario: const LineupScenario(stage: SetupStage.ready),
    );
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Settings');
    await tap(tester, 'Support');
    await tap(tester, 'Open Licenses');
    await tester.tap(find.byTooltip('Open Lineup menu'));
    await tester.pumpAndSettle();
    await escape(tester);
    expect(find.byType(LicensesView), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(LicensesView), findsNothing);
    expect(find.text('Open Licenses'), findsOneWidget);
  });
  for (final picker in ['profile', 'server']) {
    macTest(
      'R03 Support cancellation preserves Player return from $picker picker',
      (tester) async {
        const profile = PlexHomeUser(
          id: 'profile',
          name: 'Fixture profile',
          protected: false,
        );
        const server = PlexServer(
          id: 'server',
          name: 'Fixture server',
          connections: [],
        );
        final fixture = UiFixture(
          player: FixturePlayer()
            ..emit(
              const PlayerStatus(state: PlayerState.ready, message: 'Ready'),
            ),
          scenario: const LineupScenario(
            stage: SetupStage.ready,
            profile: profile,
            profiles: [profile],
            server: server,
            servers: [server],
          ),
        );
        await tester.pumpWidget(fixture.build());
        await tester.pumpAndSettle();
        await openDestination(tester, 'Player');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.comma);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(find.text('‹ Back to Player'), findsOneWidget);
        await tap(tester, 'Account');
        final stops = fixture.player.stops;
        final loads = fixture.player.loads.length;
        final saves = fixture.controller.fixtureStore.savedStates.length;
        await tap(tester, 'Switch $picker');
        expect(
          fixture.controller.stage,
          picker == 'profile' ? SetupStage.profiles : SetupStage.servers,
        );
        await tap(tester, 'Settings');
        expect(find.text('Open Licenses'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.f3);
        await tester.pumpAndSettle();
        expect(fixture.controller.stage, SetupStage.ready);
        expect(find.text('‹ Back to Player'), findsOneWidget);
        await escape(tester);
        expect(find.byType(PlayerView), findsOneWidget);
        expect(fixture.player.stops, stops);
        expect(fixture.player.loads.length, loads);
        expect(fixture.controller.fixtureStore.savedStates.length, saves);
        expect(fixture.controller.profile, profile);
        expect(fixture.controller.server?.id, server.id);
      },
    );
  }

  for (final hadPlayerRoute in [false, true]) {
    macTest(
      'R03 Support restoration keeps ${hadPlayerRoute ? 'Player origin' : 'first-run Guide fallback'}',
      (tester) async {
        final fixture = UiFixture(
          player: FixturePlayer()
            ..emit(
              const PlayerStatus(state: PlayerState.ready, message: 'Ready'),
            ),
          scenario: LineupScenario(
            stage: hadPlayerRoute ? SetupStage.ready : SetupStage.servers,
            restoringSavedLineup: !hadPlayerRoute,
            busy: !hadPlayerRoute,
          ),
        );
        await tester.pumpWidget(fixture.build());
        await tester.pump();
        if (hadPlayerRoute) {
          await openDestination(tester, 'Player');
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.comma);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pumpAndSettle();
          fixture.controller.fixtureActor.present(
            const LineupPresentation(
              stage: SetupStage.servers,
              restoring: true,
              busy: true,
            ),
          );
          await tester.pump();
        }
        final stops = fixture.player.stops;
        final loads = fixture.player.loads.length;
        final saves = fixture.controller.fixtureStore.savedStates.length;
        const codec = StandardMethodCodec();
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'lineup/app_menu',
          codec.encodeMethodCall(const MethodCall('openSettings')),
          (_) {},
        );
        await tester.pumpAndSettle();
        expect(find.text('Open Licenses'), findsOneWidget);
        fixture.controller.fixtureActor.present(
          const LineupPresentation(
            stage: SetupStage.ready,
            restoring: false,
            busy: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(hadPlayerRoute ? '‹ Back to Player' : '‹ Back to Guide'),
          findsOneWidget,
        );
        await escape(tester);
        expect(
          hadPlayerRoute
              ? find.byType(PlayerView)
              : find.byKey(const Key('classic-guide')),
          findsOneWidget,
        );
        expect(fixture.player.stops, stops);
        expect(fixture.player.loads.length, loads);
        expect(fixture.controller.fixtureStore.savedStates.length, saves);
      },
    );
  }

  macTest('Support and Licenses index fixture renders', (tester) async {
    final directory = Platform.environment['LINEUP_LICENSE_RENDER_DIR'];
    for (final size in [const Size(1280, 720), const Size(1920, 1080)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final fixture = UiFixture(
        scenario: const LineupScenario(stage: SetupStage.ready),
      );
      await tester.pumpWidget(
        RepaintBoundary(key: const Key('shell-render'), child: fixture.build()),
      );
      await tester.pumpAndSettle();
      await openDestination(tester, 'Settings');
      await tap(tester, 'Support');
      await tester.ensureVisible(find.text('Open Licenses'));
      await tester.pumpAndSettle();
      Future<void> capture(String name) => tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('shell-render')),
            )
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory!).create(recursive: true);
        await File(
          '$directory/$name-${size.width.toInt()}x${size.height.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      if (directory != null) await capture('support');
      await tap(tester, 'Open Licenses');
      for (
        var attempt = 0;
        attempt < 20 && find.text('Loading licenses…').evaluate().isNotEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (directory != null) await capture('index');
      await tester.pumpWidget(const SizedBox());
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
