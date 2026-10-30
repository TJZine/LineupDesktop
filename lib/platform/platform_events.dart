import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show VoidCallback;

/// One callback owner per platform channel, with independently watched facts.
/// Consumers share subscriptions rather than replacing each other's handler.
final class PlatformEvents {
  PlatformEvents._(this.channel);

  factory PlatformEvents({MethodChannel? channel}) {
    final resolved = channel ?? const MethodChannel('lineup/platform');
    final key = (resolved.binaryMessenger, resolved.name);
    return _owners.putIfAbsent(key, () => PlatformEvents._(resolved));
  }

  static final _owners = <(BinaryMessenger, String), PlatformEvents>{};
  final MethodChannel channel;
  final _observations = <String, _Observation>{};

  VoidCallback subscribe({
    required String event,
    required String watch,
    required String unwatch,
    required void Function(Object?) onEvent,
    required bool Function(Object?) accepts,
  }) {
    if (_observations.isEmpty) channel.setMethodCallHandler(_dispatch);
    final first = !_observations.containsKey(event);
    final observation = _observations.putIfAbsent(
      event,
      () => _Observation(unwatch, accepts),
    );
    final listener = _Listener(onEvent);
    observation.listeners.add(listener);
    if (observation.hasValue) onEvent(observation.value);
    if (first) unawaited(_invokeOptional(watch));
    var active = true;
    return () {
      if (!active) return;
      active = false;
      observation.listeners.remove(listener);
      if (observation.listeners.isNotEmpty) return;
      _observations.remove(event);
      unawaited(_invokeOptional(observation.unwatch));
      if (_observations.isEmpty) {
        channel.setMethodCallHandler(null);
      }
    };
  }

  Future<void> _dispatch(MethodCall call) async {
    final observation = _observations[call.method];
    if (observation == null || !observation.accepts(call.arguments)) return;
    observation
      ..hasValue = true
      ..value = call.arguments;
    for (final listener in List.of(observation.listeners)) {
      if (observation.listeners.contains(listener))
        listener.onEvent(call.arguments);
    }
  }

  Future<void> _invokeOptional(String method) async {
    try {
      await channel.invokeMethod<Object?>(method);
      // A watch acknowledgement is support, never a newer observed fact.
    } on MissingPluginException {
      // Optional observations stay unknown on hosts without a mechanism.
    } on PlatformException {
      // An unavailable observation must not fail application startup/teardown.
    }
  }
}

final class _Observation {
  _Observation(this.unwatch, this.accepts);
  final bool Function(Object?) accepts;
  final String unwatch;
  final listeners = <_Listener>{};
  bool hasValue = false;
  Object? value;
}

final class _Listener {
  _Listener(this.onEvent);
  final void Function(Object?) onEvent;
}
