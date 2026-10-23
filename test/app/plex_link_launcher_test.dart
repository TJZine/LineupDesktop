import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/plex_link_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lineup/platform');
  late List<MethodCall> calls;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls = [];
  });

  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }

  // Flutter verifies the platform override before tearDown callbacks run.
  Future<void> run(Future<void> Function() body) async {
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    test(
      '$platform asks native code to open the fixed link with no arguments',
      () {
        debugDefaultTargetPlatformOverride = platform;
        return run(() async {
          mock((_) async => true);
          await openPlexLink();
          expect(calls.single.method, 'openPlexLink');
          expect(calls.single.arguments, isNull);
        });
      },
    );

    for (final (name, handler)
        in <(String, Future<Object?> Function(MethodCall))>[
          ('false', (_) async => false),
          ('null', (_) async => null),
          ('a platform error', (_) async => throw PlatformException(code: 'x')),
          ('a missing handler', (_) async => throw MissingPluginException()),
        ]) {
      test(
        '$platform surfaces the browser error when native returns $name',
        () {
          debugDefaultTargetPlatformOverride = platform;
          return run(() async {
            mock(handler);
            await expectLater(
              openPlexLink(),
              throwsA(
                isA<ProcessException>().having(
                  (e) => e.message,
                  'message',
                  'Could not open browser.',
                ),
              ),
            );
          });
        },
      );
    }
  }
}
