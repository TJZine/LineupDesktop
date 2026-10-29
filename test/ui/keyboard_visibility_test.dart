import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/keyboard_visibility.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lineup/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Future<void> publish(
    Object? value, {
    String method = 'keyboardVisibilityChanged',
  }) async {
    final completed = Completer<void>();
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, value)),
      (_) => completed.complete(),
    );
    await completed.future;
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'callback precedes watch ack; only bool facts change visibility',
    () async {
      final ack = Completer<bool>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        expect(call.arguments, isNull);
        if (call.method == 'watchKeyboardVisibility') return ack.future;
        return null;
      });
      final source = PlatformKeyboardVisibility();
      var notifications = 0;
      source.addListener(() => notifications++);
      expect(source.value, isNull);
      await publish(true);
      expect(source.value, isTrue);
      ack.complete(
        false,
      ); // Support ack cannot overwrite the newer observation.
      await Future<void>.delayed(Duration.zero);
      expect(source.value, isTrue);
      for (final malformed in [
        null,
        1,
        'false',
        {'visible': false},
      ]) {
        await publish(malformed);
      }
      await publish(false, method: 'unrelated');
      expect(source.value, isTrue);
      expect(notifications, 1);
      await publish(false);
      expect(source.value, isFalse);
      source.dispose();
      source.dispose();
      await publish(true); // Retired handler cannot publish late facts.
      expect(notifications, 2);
      expect(calls, ['watchKeyboardVisibility', 'unwatchKeyboardVisibility']);
    },
  );

  for (final result in ['unsupported', 'missing', 'platform-error']) {
    test(
      '$result keeps unknown and cleanup retires an unfinished watch',
      () async {
        final calls = <String>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (result == 'missing') throw MissingPluginException();
          if (result == 'platform-error') {
            throw PlatformException(code: 'unavailable');
          }
          return false;
        });
        final source = PlatformKeyboardVisibility();
        await Future<void>.delayed(Duration.zero);
        expect(source.value, isNull);
        source.dispose();
        await Future<void>.delayed(Duration.zero);
        expect(calls, ['watchKeyboardVisibility', 'unwatchKeyboardVisibility']);
      },
    );
  }

  test('late acknowledgement after disposal cannot notify', () async {
    final ack = Completer<bool>();
    messenger.setMockMethodCallHandler(
      channel,
      (call) async =>
          call.method == 'watchKeyboardVisibility' ? ack.future : null,
    );
    final source = PlatformKeyboardVisibility();
    var notifications = 0;
    source.addListener(() => notifications++);
    source.dispose();
    ack.complete(true);
    await publish(true);
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 0);
  });
}
