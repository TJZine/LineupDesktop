import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/main.dart';

void main() {
  // Deliberately no binding initialization: startup suppression must work first.
  test(
    'release startup suppresses raw output and categorizes global errors',
    () {
      final oldBuilder = ErrorWidget.builder;
      final oldPrint = debugPrint;
      final oldError = FlutterError.onError;
      final oldPlatformError = PlatformDispatcher.instance.onError;
      final output = <String>[];
      try {
        runZoned(
          () {
            configureRuntimeErrors(release: true);
            debugPrint('CANARY token=private before binding');
            FlutterError.onError!(
              FlutterErrorDetails(
                exception: Exception('CANARY framework secret'),
              ),
            );
            expect(
              PlatformDispatcher.instance.onError!(
                Exception('CANARY platform secret'),
                StackTrace.fromString('CANARY stack'),
              ),
              isTrue,
            );
          },
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, message) => output.add(message),
          ),
        );
        expect(output, ['Lineup: framework_error', 'Lineup: unhandled_error']);
      } finally {
        ErrorWidget.builder = oldBuilder;
        debugPrint = oldPrint;
        FlutterError.onError = oldError;
        PlatformDispatcher.instance.onError = oldPlatformError;
      }
    },
  );

  test('development preserves the existing debug output callback', () {
    final oldBuilder = ErrorWidget.builder;
    final oldPrint = debugPrint;
    final oldError = FlutterError.onError;
    final oldPlatformError = PlatformDispatcher.instance.onError;
    final output = <String?>[];
    try {
      debugPrint = (message, {wrapWidth}) => output.add(message);
      configureRuntimeErrors(release: false);
      debugPrint('developer detail');
      expect(output, ['developer detail']);
    } finally {
      ErrorWidget.builder = oldBuilder;
      debugPrint = oldPrint;
      FlutterError.onError = oldError;
      PlatformDispatcher.instance.onError = oldPlatformError;
    }
  });
}
