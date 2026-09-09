import 'package:flutter/foundation.dart';

import '../playback/native_player.dart';

class DiagnosticEntry {
  const DiagnosticEntry(this.time, this.area, this.message, this.context);

  final DateTime time;
  final String area;
  final String message;
  final Map<String, Object> context;
}

enum DiagnosticPlaybackMethod { unknown, directPlay, directStream, transcode }

@immutable
class PlaybackDiagnosticSnapshot {
  const PlaybackDiagnosticSnapshot({
    required this.state,
    this.method = DiagnosticPlaybackMethod.unknown,
    this.receivedTelemetry,
  });

  final PlayerState state;
  final DiagnosticPlaybackMethod method;
  final PlayerTelemetry? receivedTelemetry;
}

@immutable
class DiagnosticSupportSnapshot {
  DiagnosticSupportSnapshot({
    required this.reportTime,
    required this.timeZone,
    required this.appVersion,
    required this.appBuild,
    required this.platform,
    required this.recordingEnabled,
    required this.plexServerSelected,
    required this.plexConnectionVerified,
    required this.playback,
    required List<DiagnosticEntry> events,
  }) : events = List.unmodifiable(events);

  final DateTime reportTime;
  final String timeZone;
  final String appVersion;
  final String appBuild;
  final String platform;
  final bool recordingEnabled;
  final bool plexServerSelected;
  final bool plexConnectionVerified;
  final PlaybackDiagnosticSnapshot playback;
  final List<DiagnosticEntry> events;
}

class Diagnostics extends ChangeNotifier {
  final List<DiagnosticEntry> _entries = [];
  bool _enabled = false;
  bool _disposed = false;

  List<DiagnosticEntry> get entries => List.unmodifiable(_entries);

  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_disposed) return;
    if (_enabled == value) return;
    _enabled = value;
    if (!value) _entries.clear();
    notifyListeners();
  }

  void add(
    String area,
    String message, [
    Map<String, Object?> context = const {},
  ]) {
    if (_disposed || !enabled) return;
    final safe = <String, Object>{};
    for (final entry in context.entries) {
      final value = entry.value;
      if (_stringKeys.contains(entry.key) && value is String) {
        safe[entry.key] = _safeToken.hasMatch(value) ? value : 'unexpected';
      } else if (entry.key == 'httpStatus' &&
          value is int &&
          value >= 100 &&
          value <= 599) {
        safe[entry.key] = value;
      } else if (entry.key == 'count' &&
          value is int &&
          value >= 0 &&
          value <= 1000000) {
        safe[entry.key] = value;
      }
    }
    _entries.add(
      DiagnosticEntry(
        DateTime.now().toUtc(),
        area,
        redact(message),
        Map.unmodifiable(safe),
      ),
    );
    if (_entries.length > 250) _entries.removeAt(0);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _entries.clear();
    super.dispose();
  }

  DiagnosticSupportSnapshot snapshot({
    required DateTime reportTime,
    required String timeZone,
    required String appVersion,
    required String appBuild,
    required String platform,
    required bool plexServerSelected,
    required bool plexConnectionVerified,
    required PlaybackDiagnosticSnapshot playback,
  }) => DiagnosticSupportSnapshot(
    reportTime: reportTime,
    timeZone: timeZone,
    appVersion: appVersion,
    appBuild: appBuild,
    platform: platform,
    recordingEnabled: enabled,
    plexServerSelected: plexServerSelected,
    plexConnectionVerified: plexConnectionVerified,
    playback: playback,
    events: _entries,
  );

  String buildSupportReport(DiagnosticSupportSnapshot snapshot) {
    final telemetry = snapshot.playback.receivedTelemetry;
    final lines = <String>[
      'Lineup Desktop support report',
      'Report time: ${snapshot.reportTime.toIso8601String()}',
      'Time zone: ${_safeTimeZone(snapshot.timeZone)}',
      'App: ${_safeFact(snapshot.appVersion)} (${_safeFact(snapshot.appBuild)})',
      'Platform: ${_safeFact(snapshot.platform)}',
      'Diagnostic recording: ${snapshot.recordingEnabled ? 'On' : 'Off'}',
      'Playback state: ${snapshot.playback.state.name}',
      'Playback method: ${_methodLabel(snapshot.playback.method)}',
      'Plex server selected: ${snapshot.plexServerSelected ? 'Yes' : 'No'}',
      'Plex connection verified: ${snapshot.plexConnectionVerified ? 'Yes' : 'No'}',
      if (telemetry?.width case final width? when width > 0)
        if (telemetry?.height case final height? when height > 0)
          'Received video: ${width}x$height',
      if (_recognized(_videoCodecs, telemetry?.videoCodec) case final codec?)
        'Received video codec: $codec',
      if (_recognized(_dynamicRanges, telemetry?.gamma) case final signal?)
        'Reported media transfer: $signal',
      if (_recognized(_videoOutputs, telemetry?.videoOutput) case final output?)
        'Video output: $output',
      if (_recognized(_hardwareDecoders, telemetry?.hardwareDecoder)
          case final decoder?)
        'Hardware decoder: $decoder',
      '',
      'Recent events:',
    ];
    for (final entry in snapshot.events) {
      if (!_allowedEvents.contains((entry.area, entry.message))) continue;
      final facts = <String>[];
      for (final fact in entry.context.entries) {
        if (_reportContextValue(fact.key, fact.value) case final value?) {
          facts.add('${fact.key}=$value');
        }
      }
      lines.add(
        '${entry.time.toIso8601String()} ${entry.area}: ${entry.message}'
        '${facts.isEmpty ? '' : ' (${facts.join(', ')})'}',
      );
    }
    return '${lines.join('\n')}\n';
  }

  static String redact(String input) => input
      .replaceAllMapped(
        RegExp(
          r'("?\bAuthorization"?\s*[:=]\s*)((?:Bearer|Basic)\s+)?("[^"]*"|[^\s,&}]+)',
          caseSensitive: false,
        ),
        (match) => '${match[1]}${match[2] ?? ''}[REDACTED]',
      )
      .replaceAllMapped(
        RegExp(r'\b(Bearer|Basic)\s+\S+', caseSensitive: false),
        (match) => '${match[1]} [REDACTED]',
      )
      .replaceAllMapped(
        RegExp(
          r'("?(?:X-Plex-Token|authToken|token|password|pin)"?\s*[:=]\s*)("[^"]*"|[^\s,&}]+)',
          caseSensitive: false,
        ),
        (match) => '${match[1]}[REDACTED]',
      )
      .replaceAll(RegExp(r'https?://[^\s]+', caseSensitive: false), '[URL]')
      .replaceAll(RegExp(r'(?:/[\w .-]+){2,}'), '[PATH]')
      .replaceAll(
        RegExp(r'\b[A-Z]:\\[^\r\n]+', caseSensitive: false),
        '[PATH]',
      );

  static const _stringKeys = {
    'code',
    'failureCode',
    'operation',
    'container',
    'videoCodec',
    'audioCodec',
    'dynamicRange',
    'videoOutput',
    'hardwareDecoder',
  };
  static final _safeToken = RegExp(r'^[A-Za-z0-9._+-]{1,64}$');

  static String _safeFact(String value) =>
      _safeToken.hasMatch(value) ? value : 'Unavailable';
  static String _safeTimeZone(String value) =>
      RegExp(r'^[A-Za-z0-9 _+:/.-]{1,64}$').hasMatch(value)
      ? value
      : 'Unavailable';

  static String _methodLabel(DiagnosticPlaybackMethod method) =>
      switch (method) {
        DiagnosticPlaybackMethod.unknown => 'Unknown',
        DiagnosticPlaybackMethod.directPlay => 'Direct Play',
        DiagnosticPlaybackMethod.directStream => 'Direct Stream',
        DiagnosticPlaybackMethod.transcode => 'Transcode',
      };

  static String? _recognized(Set<String> allowed, String? value) {
    final normalized = value?.toLowerCase();
    return normalized != null && allowed.contains(normalized)
        ? normalized
        : null;
  }

  static String? _reportContextValue(String key, Object value) => switch (key) {
    'httpStatus' when value is int && value >= 100 && value <= 599 => '$value',
    'count' when value is int && value >= 0 && value <= 1000000 => '$value',
    'operation' when value is String => _recognized(_operations, value),
    'code' ||
    'failureCode' when value is String => _recognized(_failureCodes, value),
    'container' when value is String => _recognized(_containers, value),
    'videoCodec' when value is String => _recognized(_videoCodecs, value),
    'audioCodec' when value is String => _recognized(_audioCodecs, value),
    'dynamicRange' when value is String => _recognized(_dynamicRanges, value),
    'videoOutput' when value is String => _recognized(_videoOutputs, value),
    'hardwareDecoder' when value is String => _recognized(
      _hardwareDecoders,
      value,
    ),
    _ => null,
  };

  static const _allowedEvents = <(String, String)>{
    ('application', 'Credential cleanup failed'),
    ('application', 'State save failed'),
    ('application', 'Operation failed'),
    ('plex-auth', 'PIN cancellation failed'),
    ('plex-auth', 'Credential write failed'),
    ('plex-auth', 'PIN poll failed'),
    ('plex-library', 'Playlist discovery unavailable'),
    ('plex-library', 'Some playlists could not be loaded'),
    ('guide', 'Guide current program wait timed out'),
    ('guide', 'Guide schedule load timed out'),
    ('playback', 'Native playback failed'),
    ('playback', 'Playback request failed'),
    ('playback', 'Plex playback selected'),
  };
  static const _operations = {
    'play',
    'pause',
    'seek',
    'stop',
    'audio_track',
    'subtitle_track',
    'fullscreen',
    'scope_cleanup',
    'request',
  };
  static const _failureCodes = {
    'unexpected',
    'offline',
    'http_error',
    'player_unavailable',
    'command_queue_full',
    'wait_timeout',
    'write-failed',
    'credential-cleanup-failed',
    'credential-write-failed',
    'server-unreachable',
    'resource-not-found',
    'parse-error',
  };
  static const _containers = {'mpeg-ts', 'mpegts', 'mp4', 'mkv'};
  static const _videoCodecs = {'h264', 'hevc', 'av1', 'mpeg2video', 'vp9'};
  static const _audioCodecs = {'aac', 'ac3', 'eac3', 'dts', 'truehd', 'opus'};
  static const _dynamicRanges = {'pq', 'hlg', 'smpte-st-2084', 'hdr10', 'sdr'};
  static const _videoOutputs = {'gpu-next', 'gpu'};
  static const _hardwareDecoders = {'d3d11va', 'nvdec', 'videotoolbox'};
}
