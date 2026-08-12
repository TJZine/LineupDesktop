import 'dart:async';

abstract interface class NativePlayer {
  PlayerStatus get status;
  Stream<PlayerEvent> get events;

  Future<void> initialize();
  Future<void> load(Uri media);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
}

enum PlayerState { idle, loading, playing, paused, stopped, error, unsupported }

class PlayerStatus {
  const PlayerStatus({required this.state, required this.message});

  final PlayerState state;
  final String message;
}

class PlayerEvent {
  const PlayerEvent({required this.status, this.position = Duration.zero});

  final PlayerStatus status;
  final Duration position;
}

class PlayerUnavailable implements Exception {
  const PlayerUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}
