import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/platform/handheld_system_ui.dart';
import 'package:lineup_desktop/playback/native_player.dart';

import '../support/test_doubles.dart';

void main() {
  test(
    'phone orientation uses display and real multiwindow, not viewport size',
    () {
      HandheldSystemUiPolicy policy({
        Size display = const Size(412, 915),
        Size window = const Size(412, 891),
        bool? multiWindow = false,
        bool player = false,
        bool osd = true,
        bool fullscreen = false,
      }) => HandheldSystemUiPolicy(
        displaySize: display,
        windowSize: window,
        multiWindow: multiWindow,
        playerVisible: player,
        osdVisible: osd,
        fullscreen: fullscreen,
      );
      expect(policy().orientations, [DeviceOrientation.portraitUp]);
      expect(policy(player: true).orientations, [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      expect(policy(player: true, fullscreen: true).orientations, [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      expect(policy(fullscreen: true).orientations, [
        DeviceOrientation.portraitUp,
      ]);
      expect(
        policy(
          player: true,
          fullscreen: true,
          display: const Size(800, 1280),
        ).orientations,
        isEmpty,
      );
      expect(
        policy(player: true, fullscreen: true, multiWindow: true).orientations,
        isEmpty,
      );
      expect(
        policy(
          display: const Size(1280, 800),
          window: const Size(400, 600),
        ).orientations,
        isEmpty,
      );
      expect(policy(display: const Size(600, 960)).orientations, isEmpty);
      expect(policy(display: const Size(599, 960)).orientations, [
        DeviceOrientation.portraitUp,
      ]);
      expect(policy(multiWindow: true).orientations, isEmpty);
      expect(policy(multiWindow: null).orientations, isEmpty);
      expect(policy(player: true, osd: true).hideBars, isFalse);
      expect(policy(player: true, osd: false).hideBars, isTrue);
      expect(
        policy(player: true, window: const Size(915, 412)).hideBars,
        isTrue,
      );
      expect(policy(window: const Size(915, 412)).hideBars, isFalse);
    },
  );

  testWidgets(
    'actual fact callbacks and destination changes drive platform calls and restore on exit',
    (tester) async {
      const platform = MethodChannel('lineup/platform');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      final native = FakeNativePlayer(
        capabilities: const PlayerCapabilities(
          displayMatching: false,
          fullscreen: PlayerFullscreenMode.systemBars,
        ),
      );
      addTearDown(native.dispose);
      messenger.setMockMethodCallHandler(platform, (_) async => true);
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(platform, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(412, 891);
      tester.view.display
        ..devicePixelRatio = 1
        ..size = const Size(412, 915);
      addTearDown(tester.view.reset);
      addTearDown(tester.view.display.reset);
      Future<void> pump({bool player = false, bool osd = true}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: HandheldSystemUi(
              playerVisible: player,
              osdVisible: osd,
              player: native,
              child: const SizedBox(),
            ),
          ),
        );
        await tester.pump();
      }

      Future<void> fact(bool multiWindow) async {
        final done = Completer<void>();
        await messenger.handlePlatformMessage(
          platform.name,
          platform.codec.encodeMethodCall(
            MethodCall('multiWindowChanged', multiWindow),
          ),
          (_) => done.complete(),
        );
        await done.future;
        await tester.pump();
        await tester.pump();
      }

      await pump();
      await fact(false);
      expect(
        calls
            .where(
              (call) => call.method == 'SystemChrome.setPreferredOrientations',
            )
            .last
            .arguments,
        ['DeviceOrientation.portraitUp'],
      );
      await pump(player: true);
      expect(
        calls
            .where(
              (call) => call.method == 'SystemChrome.setPreferredOrientations',
            )
            .last
            .arguments,
        [
          'DeviceOrientation.portraitUp',
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight',
        ],
      );
      await pump(player: true, osd: false);
      expect(native.fullscreenValues, [false, true]);
      native.emitFullscreen(false);
      await pump(player: true, osd: false);
      expect(native.fullscreenValues, [false, true]);
      await fact(true);
      expect(
        calls
            .where(
              (call) => call.method == 'SystemChrome.setPreferredOrientations',
            )
            .last
            .arguments,
        isEmpty,
      );
      await pump();
      expect(native.fullscreenValues, [false, true, false]);
      expect(
        calls.any(
          (call) => call.method == 'SystemChrome.setEnabledSystemUIMode',
        ),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        calls
            .where(
              (call) => call.method == 'SystemChrome.setPreferredOrientations',
            )
            .last
            .arguments,
        isEmpty,
      );
    },
  );
  testWidgets(
    'retiring startup policy cannot restore over a newly mounted shell',
    (tester) async {
      const platform = MethodChannel('lineup/platform');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      final native = FakeNativePlayer(
        capabilities: const PlayerCapabilities.unavailable(),
      );
      addTearDown(native.dispose);
      messenger.setMockMethodCallHandler(platform, (_) async => true);
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(platform, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(412, 915);
      tester.view.display
        ..devicePixelRatio = 1
        ..size = const Size(412, 915);
      addTearDown(tester.view.reset);
      addTearDown(tester.view.display.reset);
      Widget host(String key) => MaterialApp(
        home: HandheldSystemUi(
          key: ValueKey(key),
          playerVisible: false,
          player: native,
          osdVisible: true,
          child: const SizedBox(),
        ),
      );
      await tester.pumpWidget(host('startup'));
      final done = Completer<void>();
      await messenger.handlePlatformMessage(
        platform.name,
        platform.codec.encodeMethodCall(
          const MethodCall('multiWindowChanged', false),
        ),
        (_) => done.complete(),
      );
      await done.future;
      await tester.pump();
      await tester.pump();
      calls.clear();
      await tester.pumpWidget(host('shell'));
      await tester.pump();
      await tester.pump();
      final orientations = calls.where(
        (call) => call.method == 'SystemChrome.setPreferredOrientations',
      );
      expect(orientations, isNotEmpty);
      expect(orientations.last.arguments, ['DeviceOrientation.portraitUp']);
      expect(
        orientations.any((call) => (call.arguments as List).isEmpty),
        isFalse,
      );
      expect(native.fullscreenValues, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'returning to the previous policy while a new policy is in flight wins',
    (tester) async {
      const platform = MethodChannel('lineup/platform');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      final releaseBOrientation = Completer<void>();
      final native = FakeNativePlayer(
        capabilities: const PlayerCapabilities(
          displayMatching: false,
          fullscreen: PlayerFullscreenMode.systemBars,
        ),
      );
      addTearDown(native.dispose);
      var holdBOrientation = false;
      messenger.setMockMethodCallHandler(platform, (_) async => true);
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        if (call.method == 'SystemChrome.setPreferredOrientations' &&
            holdBOrientation &&
            (call.arguments as List).contains(
              'DeviceOrientation.landscapeLeft',
            )) {
          await releaseBOrientation.future;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(platform, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(412, 891);
      tester.view.display
        ..devicePixelRatio = 1
        ..size = const Size(412, 915);
      addTearDown(tester.view.reset);
      addTearDown(tester.view.display.reset);
      Widget host({bool player = false, bool osd = true}) => MaterialApp(
        home: HandheldSystemUi(
          playerVisible: player,
          osdVisible: osd,
          player: native,
          child: const SizedBox(),
        ),
      );

      await tester.pumpWidget(host());
      await tester.pump();
      final factDone = Completer<void>();
      await messenger.handlePlatformMessage(
        platform.name,
        platform.codec.encodeMethodCall(
          const MethodCall('multiWindowChanged', false),
        ),
        (_) => factDone.complete(),
      );
      await factDone.future;
      await tester.pump();
      await tester.pump();
      expect(
        calls
            .where(
              (call) => call.method == 'SystemChrome.setPreferredOrientations',
            )
            .last
            .arguments,
        ['DeviceOrientation.portraitUp'],
      );
      expect(native.fullscreenValues, [false]);

      holdBOrientation = true;
      await tester.pumpWidget(host(player: true, osd: false));
      await tester.pump();
      expect(
        calls
            .where(
              (call) => call.method == 'SystemChrome.setPreferredOrientations',
            )
            .last
            .arguments,
        [
          'DeviceOrientation.portraitUp',
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight',
        ],
      );

      await tester.pumpWidget(host());
      await tester.pump();
      releaseBOrientation.complete();
      await tester.pump();
      await tester.pump();
      expect(
        calls
            .where(
              (call) => call.method == 'SystemChrome.setPreferredOrientations',
            )
            .last
            .arguments,
        ['DeviceOrientation.portraitUp'],
      );
      expect(native.fullscreenValues, [false]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
