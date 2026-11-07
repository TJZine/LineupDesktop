import 'dart:async';

import '../plex/plex_transcode.dart';
import 'native_player.dart';

enum PlexPartMode { automatic, reactiveFallback, restartSession }

class PlaybackCancellation {
  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get cancelled => _cancelled.future;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

typedef OpenPlexPart = Future<PartLoad> Function(
  int partIndex,
  Duration? position,
  PlaybackCancellation cancellation, {
  required bool desktop,
  required Future<MediaCapabilities> Function() mediaCapabilities,
  required PlexPartMode mode,
  required int restarts,
});

sealed class PartLoad {
  const PartLoad(this.uri, this.method);

  final Uri uri;
  final PlexPlaybackMethod method;
}

final class DirectPartLoad extends PartLoad {
  const DirectPartLoad(Uri uri, this.token)
    : super(uri, PlexPlaybackMethod.directPlay);

  final String? token;
}

final class SessionPartLoad extends PartLoad {
  const SessionPartLoad({
    required Uri uri,
    required PlexPlaybackMethod method,
    required this.handle,
    required this.offset,
    this.playlist,
  }) : super(uri, method);

  final PlexSessionHandle handle;
  final Duration offset;
  final NativeSessionPlaylist? playlist;
}

abstract interface class PlexSessionHandle {
  /// Retires the issued session. If loaded, [nativeStop] has already been
  /// dispatched and must settle or reach its deadline before PMS receives stop.
  Future<void> stop({Future<void>? nativeStop});

  Future<PartLoad> restartAt(
    Duration position,
    PlaybackCancellation cancellation, {
    required int restarts,
  });
}
