import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/platform/platform_events.dart';
import 'package:lineup_desktop/ui/keyboard_visibility.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lineup/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> publish(String method, Object? value) async {
    final done = Completer<void>();
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, value)),
      (_) => done.complete(),
    );
    await done.future;
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('keyboard and window subscriptions coexist, replay facts and refcount watches', () async {
    final calls = <String>[];
    final ack = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'watchKeyboardVisibility' ? ack.future : true;
    });
    final first = PlatformKeyboardVisibility();
    await publish('keyboardVisibilityChanged', true);
    await publish('keyboardVisibilityChanged', 'malformed');
    final second = PlatformKeyboardVisibility();
    expect(second.value, isTrue);
    final windows = <Object?>[];
    final stop = PlatformEvents().subscribe(
      event: 'multiWindowChanged',
      watch: 'watchWindowFacts',
      unwatch: 'unwatchWindowFacts',
      accepts: (fact) => fact is bool,
      onEvent: windows.add,
    );
    await publish('multiWindowChanged', false);
    expect(windows, [false]);
    first.dispose();
    await publish('keyboardVisibilityChanged', false);
    expect(second.value, isFalse);
    expect(calls.where((call) => call == 'watchKeyboardVisibility').length, 1);
    expect(calls, isNot(contains('unwatchKeyboardVisibility')));
    second.dispose();
    await publish('multiWindowChanged', true);
    expect(windows, [false, true]);
    ack.complete(false);
    await Future<void>.delayed(Duration.zero);
    stop();
    stop();
    await publish('multiWindowChanged', false);
    expect(windows, [false, true]);
    expect(
      calls.where((call) => call == 'unwatchKeyboardVisibility').length,
      1,
    );
    expect(calls.where((call) => call == 'unwatchWindowFacts').length, 1);
  });

  test(
    'a callback can retire another listener without delivering a late fact',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async => true);
      var delivered = 0;
      late void Function() stopSecond;
      final dispatcher = PlatformEvents();
      final stopFirst = dispatcher.subscribe(
        event: 'multiWindowChanged',
        watch: 'watchWindowFacts',
        unwatch: 'unwatchWindowFacts',
        accepts: (fact) => fact is bool,
        onEvent: (_) => stopSecond(),
      );
      stopSecond = dispatcher.subscribe(
        event: 'multiWindowChanged',
        watch: 'watchWindowFacts',
        unwatch: 'unwatchWindowFacts',
        accepts: (fact) => fact is bool,
        onEvent: (_) => delivered++,
      );
      await publish('multiWindowChanged', true);
      expect(delivered, 0);
      stopFirst();
    },
  );
  test(
    'retire and rewatch clears old facts while old acknowledgements stay inert',
    () async {
      final oldAck = Completer<bool>();
      var watches = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'watchKeyboardVisibility') {
          watches++;
          if (watches == 1) return oldAck.future;
        }
        return true;
      });
      final retired = PlatformKeyboardVisibility();
      await publish('keyboardVisibilityChanged', true);
      expect(retired.value, isTrue);
      retired.dispose();
      final current = PlatformKeyboardVisibility();
      expect(current.value, isNull);
      await publish('keyboardVisibilityChanged', false);
      oldAck.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(current.value, isFalse);
      expect(watches, 2);
      current.dispose();
    },
  );
}
