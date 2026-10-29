import 'package:flutter/foundation.dart';

import '../playback/native_player.dart';

/// Fixed producer events. Export also checks these definitions for snapshots
/// constructed directly, without passing through [Diagnostics.add].
enum DiagnosticEvent {
  credentialCleanupFailed('application', 'Credential cleanup failed'),
  stateSaveFailed('application', 'State save failed'),
  operationFailed('application', 'Operation failed'),
  pinCancellationFailed('plex-auth', 'PIN cancellation failed'),
  credentialWriteFailed('plex-auth', 'Credential write failed'),
  pinPollFailed('plex-auth', 'PIN poll failed'),
  playlistDiscoveryUnavailable(
    'plex-library',
    'Playlist discovery unavailable',
  ),
  somePlaylistsCouldNotBeLoaded(
    'plex-library',
    'Some playlists could not be loaded',
  ),
  someCollectionsCouldNotBeLoaded(
    'plex-library',
    'Some collections could not be loaded',
  ),
  collectionDiscoveryUnavailable(
    'plex-library',
    'Collection discovery unavailable',
  ),
  libraryScanTiming('plex-library', 'Library scan timing'),
  castEnrichment('plex', 'Cast enrichment'),
  castPortraitUnavailable('plex', 'Cast portrait unavailable'),
  guideCurrentProgramWaitTimedOut(
    'guide',
    'Guide current program wait timed out',
  ),
  guideScheduleLoadTimedOut('guide', 'Guide schedule load timed out'),
  nativePlaybackFailed('playback', 'Native playback failed'),
  playbackRequestFailed('playback', 'Playback request failed'),
  plexPlaybackSelected('playback', 'Plex playback selected');

  const DiagnosticEvent(this.area, this.message);

  final String area;
  final String message;
}

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
    this.displayReport = const DisplayMatchingReport.initial(),
  });

  final PlayerState state;
  final DiagnosticPlaybackMethod method;
  final PlayerTelemetry? receivedTelemetry;
  final DisplayMatchingReport displayReport;
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

  void add(DiagnosticEvent event, [Map<String, Object?> context = const {}]) {
    if (_disposed || !enabled) return;
    final safe = <String, Object>{};
    for (final entry in context.entries) {
      if (_contextPolicies[entry.key]?.sanitizeForStorage(entry.value)
          case final value?) {
        safe[entry.key] = value;
      }
    }
    _entries.add(
      DiagnosticEntry(
        DateTime.now().toUtc(),
        event.area,
        redact(event.message),
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
    final isMacOS = isMacOSPlatform(snapshot.platform);
    final lines = <String>[
      'Lineup Desktop support report',
      'Report time: ${snapshot.reportTime.toIso8601String()}',
      'Time zone: ${_safeTimeZone(snapshot.timeZone)}',
      'App: ${_safeFact(snapshot.appVersion)} (${_safeBuild(snapshot.appBuild)})',
      'Platform: ${_safeFact(snapshot.platform)}',
      'Diagnostic recording: ${snapshot.recordingEnabled ? 'On' : 'Off'}',
      'Playback state: ${snapshot.playback.state.name}',
      'Playback method: ${_methodLabel(snapshot.playback.method)}',
      if (isMacOS) ...[
        'HDR output: $macOSHdrOutputFact',
        'Renderer output: ${rendererOutputFact(telemetry)}',
        macOSDisplayStateNote,
      ] else ...[
        'Windows display: ${windowsDisplayFact(snapshot.playback.displayReport)}',
        'HDR matching: ${hdrMatchingFact(snapshot.playback.displayReport)}',
        'Renderer output: ${rendererOutputFact(telemetry)}',
        windowsDisplayStateNote,
      ],
      'Plex server selected: ${snapshot.plexServerSelected ? 'Yes' : 'No'}',
      'Plex connection verified: ${snapshot.plexConnectionVerified ? 'Yes' : 'No'}',
      if (telemetry?.width case final width? when width > 0)
        if (telemetry?.height case final height? when height > 0)
          'Received video: ${width}x$height',
      if (_recognized(_videoCodecs, telemetry?.videoCodec) case final codec?)
        'Received video codec: $codec',
      if (_recognized(_dynamicRanges, telemetry?.gamma) case final signal?)
        'Reported media transfer: $signal',
      if (_recognized(_pixelFormats, telemetry?.pixelFormat) case final format?)
        'Reported pixel format: $format',
      if (_recognized(_primaries, telemetry?.primaries) case final primaries?)
        'Reported color primaries: $primaries',
      if (_recognized(_colorMatrices, telemetry?.colorMatrix)
          case final matrix?)
        'Reported color matrix: $matrix',
      if (telemetry?.signalPeak case final peak?
          when peak.isFinite && peak >= 0 && peak <= 10000)
        'Reported signal peak: $peak',
      if (_recognized(_videoOutputs, telemetry?.videoOutput) case final output?)
        'Video output: $output',
      if (_recognized(_hardwareDecoders, telemetry?.hardwareDecoder)
          case final decoder?)
        'Hardware decoder: $decoder',
      '',
      'Recent events:',
    ];
    for (final entry in snapshot.events) {
      if (!DiagnosticEvent.values.any(
        (event) => event.area == entry.area && event.message == entry.message,
      )) {
        continue;
      }
      final facts = <String>[];
      for (final fact in entry.context.entries) {
        if (_contextPolicies[fact.key]?.admitForExport(fact.value)
            case final value?) {
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

  /// [platform] is `TargetPlatform.name` as carried by the snapshot.
  static bool isMacOSPlatform(String platform) => platform == 'macOS';
  static const macOSHdrOutputFact = 'Managed by macOS';
  static const macOSDisplayStateNote =
      'macOS manages HDR output; Lineup does not change display modes.';
  static const windowsDisplayStateNote =
      "Display state is reported by Windows; it does not verify the TV's picture.";

  static String windowsDisplayFact(DisplayMatchingReport report) =>
      '${report.observed.name} · ${report.route.name}'
      '${report.activeColorMode == null ? '' : ' · ${report.activeColorMode!.name}'}';

  static String hdrMatchingFact(DisplayMatchingReport report) =>
      '${report.session.name} · ${report.outcome.name} · revision=${report.revision} · '
      'wrote=${report.wrote} · owned=${report.owned}'
      '${report.reason == null ? '' : ' · ${report.reason!.name}'}';

  static String rendererOutputFact(PlayerTelemetry? telemetry) => [
    _recognized(_rendererTransfers, telemetry?.targetGamma) ?? 'Unavailable',
    _recognized(_primaries, telemetry?.targetPrimaries) ?? 'Unavailable',
    _recognized(_rendererFormats, telemetry?.targetPixelFormat) ??
        'Unavailable',
  ].join(' · ');

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

  // One definition per key, with intentionally distinct storage/export rules.
  static const _contextPolicies = <String, _ContextPolicy>{
    'castOutcome': _FixedEnumContextPolicy({
      'requested',
      'enriched',
      'noRicherData',
      'failed',
    }),
    'castFailure': _FixedEnumContextPolicy({
      'auth',
      'timeout',
      'transport',
      'shape',
    }),
    'code': _CategoricalContextPolicy(_failureCategories),
    'failureCode': _CategoricalContextPolicy(_failureCategories),
    'operation': _CategoricalContextPolicy(_operations),
    'container': _CategoricalContextPolicy(_containers),
    'videoCodec': _CategoricalContextPolicy(_videoCodecs),
    'audioCodec': _CategoricalContextPolicy(_audioCodecs),
    'dynamicRange': _CategoricalContextPolicy(_dynamicRanges),
    'videoOutput': _CategoricalContextPolicy(_videoOutputs),
    'hardwareDecoder': _CategoricalContextPolicy(_hardwareDecoders),
    'scanPath': _CategoricalContextPolicy(_scanPaths),
    'libraryType': _CategoricalContextPolicy(_libraryTypes),
    'httpStatus': _IntegerContextPolicy(100, 599),
    'count': _IntegerContextPolicy(0, 1000000),
    'itemsMs': _IntegerContextPolicy(0, 86400000),
    'collectionsMs': _IntegerContextPolicy(0, 86400000),
    'showGenresMs': _IntegerContextPolicy(0, 86400000),
    'items': _IntegerContextPolicy(0, 1000000),
    'collections': _IntegerContextPolicy(0, 1000000),
    'members': _IntegerContextPolicy(0, 1000000),
    'shows': _IntegerContextPolicy(0, 1000000),
  };
  static const _scanPaths = {'launch', 'setup'};
  static const _libraryTypes = {'movie', 'show'};
  static final _safeToken = RegExp(r'^[A-Za-z0-9._+-]{1,64}$');

  static String _safeFact(String value) =>
      _safeToken.hasMatch(value) ? value : 'Unavailable';
  static final _releaseBuild = RegExp(r'^[0-9]{1,20}@[a-fA-F0-9]{40}$');

  static String _safeBuild(String value) =>
      _safeToken.hasMatch(value) || _releaseBuild.hasMatch(value)
      ? value
      : 'Unavailable';

  /// Exportable categories are fixed producer outcomes, never upstream text.
  /// Producers retain domain normalization; unknown failures use unexpected.
  static String? failureCategory(String value) =>
      _recognized(_failureCategories, value);

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
  static const _failureCategories = {
    'unexpected',
    'offline',
    'http_error',
    'network-timeout',
    'network-unavailable',
    'rate-limited',
    'auth-denied',
    'response-unavailable',
    'auth-required',
    'auth-invalid',
    'access-denied',
    'incorrect-pin',
    'unsupported',
    'playback-unavailable',
    'authorization-unavailable',
    'invalid-library',
    'playlist-unavailable',
    'collection-unavailable',
    'collection-scale-exceeded',
    'response-too-large',
    'library-page-invalid',
    'library-page-too-large',
    'library-page-not-progressing',
    'library-scale-exceeded',
    'playlist-page-invalid',
    'playlist-page-too-large',
    'playlist-page-not-progressing',
    'playlist-scale-exceeded',
    'network_error',
    'audio_decode_error',
    'video_decode_error',
    'audio_output_error',
    'video_output_error',
    'source_open_error',
    'container_error',
    'correlation_error',
    'command_error',
    'event_queue_overflow',
    'mpv_error',
    'required_engine_unavailable',
    'initialize_failed',
    'dispose_in_progress',
    'not_initialized',
    'invalid_argument',
    'insecure_media_uri',
    'window_error',
    'native_command_error',
    'native_playback_error',
    'native_error',
    'premature_end',
    'stop_timeout',
    'stop_failed',
    'player_unavailable',
    'command_queue_full',
    'wait_timeout',
    'write-failed',
    'credential-cleanup-failed',
    'credential-write-failed',
    'server-unreachable',
    'resource-not-found',
    'parse-error',
    'portrait_invalid',
    'portrait_https',
    'portrait_http',
    'portrait_pms',
    'authorization',
    'timeout',
    'size',
    'unavailable',
    'transport',
  };
  static const _containers = {'mpeg-ts', 'mpegts', 'mp4', 'mkv'};
  static const _videoCodecs = {'h264', 'hevc', 'av1', 'mpeg2video', 'vp9'};
  static const _audioCodecs = {'aac', 'ac3', 'eac3', 'dts', 'truehd', 'opus'};
  static const _dynamicRanges = {'pq', 'hlg', 'smpte-st-2084', 'hdr10', 'sdr'};
  static const _pixelFormats = {
    'yuv420p',
    'yuv420p10le',
    'yuv422p',
    'yuv422p10le',
    'yuv444p',
    'yuv444p10le',
    'nv12',
    'p010',
    'p010le',
    'rgb24',
    'rgba',
    'bgra',
  };
  static const _rendererTransfers = {
    ..._dynamicRanges,
    'bt.1886',
    'bt.709',
    'srgb',
    'linear',
    'gamma1.8',
    'gamma2.0',
    'gamma2.2',
    'gamma2.4',
    'gamma2.6',
    'gamma2.8',
  };
  static const _rendererFormats = {
    ..._pixelFormats,
    'rgb10a2',
    'rgba16hf',
    'rgba16f',
    'rgb0',
    'bgr0',
  };
  static const _primaries = {
    'bt.601-525',
    'bt.601-625',
    'bt.709',
    'bt.2020',
    'bt709',
    'bt2020',
    'dci-p3',
    'display-p3',
  };
  static const _colorMatrices = {
    'bt.601',
    'bt.709',
    'bt.2020-ncl',
    'bt.2020-cl',
    'bt709',
    'bt2020nc',
    'bt2020c',
    'rgb',
  };
  static const _videoOutputs = {'gpu-next', 'gpu'};
  static const _hardwareDecoders = {'d3d11va', 'nvdec', 'videotoolbox'};
}

sealed class _ContextPolicy {
  const _ContextPolicy();

  Object? sanitizeForStorage(Object? value);
  String? admitForExport(Object value);
}

/// Cast enrichment records only closed outcome/failure enums, even in memory.
final class _FixedEnumContextPolicy extends _ContextPolicy {
  const _FixedEnumContextPolicy(this.values);
  final Set<String> values;

  @override
  String? sanitizeForStorage(Object? value) =>
      value is String && values.contains(value) ? value : null;

  @override
  String? admitForExport(Object value) => sanitizeForStorage(value);
}

final class _CategoricalContextPolicy extends _ContextPolicy {
  const _CategoricalContextPolicy(this.categories);

  final Set<String> categories;

  // The UI reads stored values. Safe unknown tokens and casing must survive.
  @override
  String? sanitizeForStorage(Object? value) => value is String
      ? (Diagnostics._safeToken.hasMatch(value) ? value : 'unexpected')
      : null;

  // Snapshots can be forged, so never trust prior storage sanitation here.
  @override
  String? admitForExport(Object value) =>
      value is String ? Diagnostics._recognized(categories, value) : null;
}

final class _IntegerContextPolicy extends _ContextPolicy {
  const _IntegerContextPolicy(this.minimum, this.maximum);

  final int minimum;
  final int maximum;

  @override
  int? sanitizeForStorage(Object? value) =>
      value is int && value >= minimum && value <= maximum ? value : null;

  @override
  String? admitForExport(Object value) => sanitizeForStorage(value)?.toString();
}
