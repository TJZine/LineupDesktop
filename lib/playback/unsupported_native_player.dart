import 'dart:async';

import 'native_player.dart';

class UnsupportedNativePlayer implements NativePlayer {
  UnsupportedNativePlayer.macos();

  static const _unsupported = PlayerStatus(
    state: PlayerState.unsupported,
    message: 'Playback is not implemented on macOS',
  );

  @override
  PlayerStatus get status => _unsupported;

  @override
  Stream<PlayerEvent> get events => const Stream.empty();

  @override
  Future<void> initialize() async {}

  Never _unavailable() => throw const PlayerUnavailable(
    'Native playback is not implemented on macOS.',
  );

  @override
  Future<void> load(Uri media) async => _unavailable();

  @override
  Future<void> play() async => _unavailable();

  @override
  Future<void> pause() async => _unavailable();

  @override
  Future<void> seek(Duration position) async => _unavailable();

  @override
  Future<void> stop() async => _unavailable();

  @override
  Future<void> dispose() async {}
}
