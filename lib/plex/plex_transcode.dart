import 'dart:convert';

import 'package:xml/xml.dart';

import 'plex_models.dart';
import 'plex_xml.dart';

class VideoDecoderCapabilities {
  const VideoDecoderCapabilities({
    required this.codec,
    this.profiles = const [],
    this.maxLevel,
    this.maxWidth,
    this.maxHeight,
    this.maxBitrateKbps,
    this.hdr = const [],
    this.dolbyVisionProfiles = const [],
  });

  final String codec;
  final List<String> profiles;
  final String? maxLevel;
  final int? maxWidth;
  final int? maxHeight;
  final int? maxBitrateKbps;
  final List<String> hdr;
  final List<int> dolbyVisionProfiles;
}

class MediaCapabilities {
  const MediaCapabilities({
    this.videoDecoders = const [],
    this.audioDecoders = const [],
    this.audioPassthrough = const [],
    this.containers = const [],
    this.known = true,
  });

  static const unknown = MediaCapabilities(known: false);
  static const desktop = MediaCapabilities(
    videoDecoders: [VideoDecoderCapabilities(codec: '*')],
    audioDecoders: ['*'],
    containers: ['*'],
  );

  final List<VideoDecoderCapabilities> videoDecoders;
  final List<String> audioDecoders;
  final List<String> audioPassthrough;
  final List<String> containers;
  final bool known;

  factory MediaCapabilities.fromWire(Object? raw) {
    try {
      if (raw is! Map) return unknown;
      final videos = raw['videoDecoders'];
      if (videos is! List || videos.length > 64) return unknown;
      return MediaCapabilities(
        videoDecoders: List.unmodifiable(
          videos.map((entry) {
            if (entry is! Map) throw const FormatException();
            final codec = _capabilityName(entry['codec']);
            return VideoDecoderCapabilities(
              codec: codec,
              profiles: _names(entry['profiles'] ?? const [], 64),
              maxLevel: entry['maxLevel'] == null
                  ? null
                  : _capabilityName(entry['maxLevel']),
              maxWidth: _positiveBound(entry['maxWidth'], 65536),
              maxHeight: _positiveBound(entry['maxHeight'], 65536),
              maxBitrateKbps: _positiveBound(
                entry['maxBitrateKbps'],
                100000000,
              ),
              hdr: _names(
                entry['hdr'] ?? const [],
                3,
                allowed: const {'hdr10', 'hdr10plus', 'hlg'},
              ),
              dolbyVisionProfiles: _dvProfiles(entry['dolbyVisionProfiles']),
            );
          }),
        ),
        audioDecoders: _names(raw['audioDecoders'], 64),
        audioPassthrough: _names(raw['audioPassthrough'], 16),
        containers: _names(raw['containers'], 32),
      );
    } on FormatException {
      return unknown;
    }
  }
}

String _capabilityName(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 64 ||
      !RegExp(r'^[a-zA-Z0-9_. :-]+$').hasMatch(value)) {
    throw const FormatException();
  }
  return value;
}

List<String> _names(Object? raw, int maximum, {Set<String>? allowed}) {
  if (raw is! List || raw.length > maximum) throw const FormatException();
  final names = raw.map(_capabilityName).toList(growable: false);
  if (allowed != null && names.any((name) => !allowed.contains(name))) {
    throw const FormatException();
  }
  return List.unmodifiable(names);
}

int? _positiveBound(Object? raw, int maximum) {
  if (raw == null) return null;
  if (raw is! int || raw <= 0 || raw > maximum) throw const FormatException();
  return raw;
}

List<int> _dvProfiles(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List ||
      raw.length > 32 ||
      raw.any((value) => value is! int || value < 0 || value > 31)) {
    throw const FormatException();
  }
  return List<int>.unmodifiable(raw);
}

enum PlexTranscodeLocation { lan, wan, cellular }

enum PlexSessionSubtitles { none, burn }

enum PlexPlaybackMethod { directPlay, directStream, transcode }

class PlexSessionRequest {
  PlexSessionRequest({
    required this.ratingKey,
    required this.sessionId,
    required this.profile,
    this.partIndex = 0,
    this.offset = Duration.zero,
    this.location = PlexTranscodeLocation.lan,
    this.subtitles = PlexSessionSubtitles.none,
    this.maxVideoBitrateKbps,
    this.videoWidth,
    this.videoHeight,
  }) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(ratingKey) ||
        !isPlexSessionId(sessionId) ||
        partIndex < 0 ||
        offset.isNegative ||
        (maxVideoBitrateKbps != null && maxVideoBitrateKbps! <= 0) ||
        ((videoWidth == null) != (videoHeight == null)) ||
        (videoWidth != null && videoWidth! <= 0) ||
        (videoHeight != null && videoHeight! <= 0) ||
        ((maxVideoBitrateKbps == null) != (videoWidth == null))) {
      throw ArgumentError('Invalid Plex session request.');
    }
  }

  final String ratingKey;
  final String sessionId;
  final PlexProfile profile;
  final int partIndex;
  final Duration offset;
  final PlexTranscodeLocation location;
  final PlexSessionSubtitles subtitles;
  final int? maxVideoBitrateKbps;
  final int? videoWidth;
  final int? videoHeight;

  Map<String, String> query({required bool directPlay}) => {
    'path': '/library/metadata/$ratingKey',
    'mediaIndex': '0',
    'partIndex': '$partIndex',
    'offset': '${offset.inSeconds}',
    'session': sessionId,
    'protocol': 'hls',
    'fastSeek': '1',
    'directPlay': directPlay ? '1' : '0',
    'directStream': '1',
    'directStreamAudio': '1',
    'videoQuality': '100',
    if (maxVideoBitrateKbps != null) ...{
      'maxVideoBitrate': '$maxVideoBitrateKbps',
      'videoBitrate': '$maxVideoBitrateKbps',
      'videoResolution': '${videoWidth}x$videoHeight',
    },
    'location': location.name,
    'autoAdjustQuality': '0',
    'subtitles': subtitles.name,
    'subtitleSize': '100',
    'audioBoost': '100',
    'audioChannelCount': '8',
  };
}

bool isPlexSessionId(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value);

class PlexSessionStart {
  const PlexSessionStart({required this.variant, required this.sessionId});
  final Uri variant;
  final String sessionId;

  @override
  String toString() => 'PlexSessionStart(<redacted>)';
}

class PlexDecisionStream {
  const PlexDecisionStream({
    this.streamType,
    this.id,
    this.decision,
    this.location,
    this.codec,
    this.width,
    this.height,
    this.bitrate,
    this.colorTrc,
  });
  final int? streamType;
  final String? id;
  final String? decision;
  final String? location;
  final String? codec;
  final int? width;
  final int? height;
  final int? bitrate;
  final String? colorTrc;
}

class PlexDecision {
  const PlexDecision({
    this.generalDecisionCode,
    this.generalDecisionText,
    this.directPlayDecisionCode,
    this.directPlayDecisionText,
    this.transcodeDecisionCode,
    this.transcodeDecisionText,
    this.mediaDecision,
    this.partDecision,
    this.streams = const [],
  });
  final int? generalDecisionCode;
  final String? generalDecisionText;
  final int? directPlayDecisionCode;
  final String? directPlayDecisionText;
  final int? transcodeDecisionCode;
  final String? transcodeDecisionText;
  final String? mediaDecision;
  final String? partDecision;
  final List<PlexDecisionStream> streams;

  PlexPlaybackMethod get method {
    if (directPlayDecisionCode == 1000) return PlexPlaybackMethod.directPlay;
    if (streams.any(
      (stream) =>
          stream.streamType == 1 &&
          (stream.decision == 'transcode' || stream.decision == 'burn'),
    )) {
      return PlexPlaybackMethod.transcode;
    }
    return PlexPlaybackMethod.directStream;
  }
}

PlexDecision parsePlexDecision(String body) {
  try {
    Map<Object?, Object?> root;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const FormatException();
      root = decoded;
    } on FormatException {
      root = plexXmlRecord(XmlDocument.parse(body).rootElement);
    }
    final container = root['MediaContainer'] is Map
        ? root['MediaContainer'] as Map<Object?, Object?>
        : root;
    if (_int(container['generalDecisionCode']) == null) {
      throw const FormatException();
    }
    final metadata = _firstRecord(container['Metadata'] ?? container['Video']);
    final media = _firstRecord(metadata?['Media'] ?? container['Media']);
    final part = _firstRecord(media?['Part']);
    return PlexDecision(
      generalDecisionCode: _int(container['generalDecisionCode']),
      generalDecisionText: sanitizePlexDecisionText(
        container['generalDecisionText'],
      ),
      directPlayDecisionCode: _int(container['directPlayDecisionCode']),
      directPlayDecisionText: sanitizePlexDecisionText(
        container['directPlayDecisionText'],
      ),
      transcodeDecisionCode: _int(container['transcodeDecisionCode']),
      transcodeDecisionText: sanitizePlexDecisionText(
        container['transcodeDecisionText'],
      ),
      mediaDecision: _string(media?['decision']),
      partDecision: _string(part?['decision']),
      streams: List.unmodifiable([
        for (final stream in _records(part?['Stream']))
          PlexDecisionStream(
            streamType: _int(stream['streamType']),
            id: _stringId(stream['id']),
            decision: _string(stream['decision']),
            location: _string(stream['location']),
            codec: _string(stream['codec']),
            width: _int(stream['width']),
            height: _int(stream['height']),
            bitrate: _int(stream['bitrate']),
            colorTrc: _string(stream['colorTrc']),
          ),
      ]),
    );
  } catch (_) {
    throw const PlexException(
      'parse-error',
      'Plex returned an invalid decision.',
    );
  }
}

Map<String, Object?> _xmlRecord(XmlElement element) => {
  for (final attribute in element.attributes)
    attribute.name.local: attribute.value,
  for (final name
      in element.childElements.map((child) => child.name.local).toSet())
    name: [
      for (final child in element.childElements.where(
        (child) => child.name.local == name,
      ))
        _xmlRecord(child),
    ],
};

Iterable<Map<Object?, Object?>> _records(Object? raw) =>
    raw is List ? raw.whereType<Map<Object?, Object?>>() : const [];
Map<Object?, Object?>? _firstRecord(Object? raw) => _records(raw).firstOrNull;
int? _int(Object? value) =>
    value is int ? value : int.tryParse(value is String ? value : '');
String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
String? _stringId(Object? value) => value is int ? '$value' : _string(value);

String? sanitizePlexDecisionText(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  var text = raw.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ');
  text = text.replaceAll(
    RegExp(
      r'''(["'])(?:https?://|[a-z]:[\\/]|\\\\|/).*?\1''',
      caseSensitive: false,
    ),
    '<redacted>',
  );
  // Unquoted paths and URLs can contain spaces. Their end is ambiguous, so
  // discard the remaining server text rather than retain a private title.
  final unsafe = RegExp(
    r'https?://|[a-z]:[\\/]|\\\\|/',
    caseSensitive: false,
  ).firstMatch(text);
  if (unsafe != null) text = '${text.substring(0, unsafe.start)}<redacted>';
  text = text.replaceAll(
    RegExp(r'X-Plex-Token\s*[:=]\s*[^\s,;]+', caseSensitive: false),
    '<redacted>',
  );
  text = text.replaceAll(
    RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
      caseSensitive: false,
    ),
    '<redacted>',
  );
  return text.length > 200 ? text.substring(0, 200) : text;
}

const maximumPlexMasterBytes = 64 * 1024;
const _invalidMaster = PlexException(
  'session-invalid',
  'Plex returned an unsupported session playlist.',
);

Uri validatePlexSessionMaster(
  String body, {
  required Uri server,
  required Uri start,
}) {
  if (utf8.encode(body).length > maximumPlexMasterBytes) throw _invalidMaster;
  final lines = const LineSplitter()
      .convert(body)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty || lines.first != '#EXTM3U') throw _invalidMaster;
  var count = 0;
  String? variant;
  var expectingVariant = false;
  for (final line in lines.skip(1)) {
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      if (expectingVariant) throw _invalidMaster;
      count++;
      expectingVariant = true;
    } else if (line.startsWith('#EXT-X-MEDIA:') ||
        line.startsWith('#EXT-X-I-FRAME-STREAM-INF:') ||
        line.startsWith('#EXT-X-SESSION-KEY:') ||
        (line.startsWith('#') &&
            RegExp(r'\bURI\s*=', caseSensitive: false).hasMatch(line))) {
      throw _invalidMaster;
    } else if (!line.startsWith('#')) {
      if (!expectingVariant || variant != null) throw _invalidMaster;
      variant = line;
      expectingVariant = false;
    }
  }
  if (count != 1 || expectingVariant || variant == null) throw _invalidMaster;
  try {
    final uri = start.resolve(variant);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.authority.contains('@') ||
        uri.scheme != server.scheme ||
        uri.host != server.host ||
        uri.port != server.port ||
        uri.fragment.isNotEmpty ||
        uri.queryParametersAll.keys.any(
          (key) => key.toLowerCase() == 'x-plex-token',
        ) ||
        !RegExp(
          r'^/video/:/transcode/universal/session/[^/]+/base/index\.m3u8$',
        ).hasMatch(uri.path)) {
      throw _invalidMaster;
    }
    return uri;
  } on FormatException {
    throw _invalidMaster;
  } on ArgumentError {
    throw _invalidMaster;
  }
}

class PlexMediaFacts {
  const PlexMediaFacts({
    this.container,
    this.videoCodec,
    this.videoProfile,
    this.bitDepth,
    this.width,
    this.height,
    this.bitrateKbps,
    this.maxLevel,
    this.dolbyVisionProfile,
    this.audioCodec,
  });
  final String? container;
  final String? videoCodec;
  final String? videoProfile;
  final int? bitDepth;
  final int? width;
  final int? height;
  final int? bitrateKbps;

  /// Plex metadata level encoding: H.264 level × 10, HEVC level × 30.
  /// Other codec levels are not currently used for local eligibility.
  final String? maxLevel;
  final int? dolbyVisionProfile;
  final String? audioCodec;
}

class PlexTranscodeTarget {
  PlexTranscodeTarget._(Iterable<String> video, Iterable<String> audio)
    : videoCodecs = List.unmodifiable(video),
      audioCodecs = List.unmodifiable(audio);

  final List<String> videoCodecs;
  final List<String> audioCodecs;

  String get _directive =>
      'add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mp4&videoCodec=${videoCodecs.join(',')}&audioCodec=${audioCodecs.join(',')}&replace=true)';
}

class PlexProfile {
  PlexProfile._({
    required String? directPlayProfile,
    required List<String> limitations,
    required this.transcodeTarget,
    required this.eligible,
  }) : profileExtra = [
         ?directPlayProfile,
         if (transcodeTarget != null) transcodeTarget._directive,
         ...limitations,
       ].join('+');

  final String profileExtra;
  final PlexTranscodeTarget? transcodeTarget;
  final bool Function(PlexMediaFacts facts) eligible;
}

PlexProfile buildProfile(
  MediaCapabilities capabilities, {
  required bool desktop,
}) {
  final c = capabilities;
  final videos =
      c.videoDecoders.map((decoder) => decoder.codec).toSet().toList()..sort();
  final audio = {
    ...c.audioDecoders,
    ...c.audioPassthrough.map(_plexAudioCodec),
  }.toList()..sort();
  final containers = c.containers.toSet().toList()..sort();
  final videoTargets = desktop
      ? ['hevc', 'h264']
      : c.known
      ? ['hevc', 'h264'].where(videos.contains).toList()
      : <String>[];
  final audioTargets = desktop
      ? ['aac', 'ac3', 'eac3']
      : c.known
      ? ['aac', 'ac3', 'eac3'].where(audio.contains).toList()
      : <String>[];
  final target = videoTargets.isNotEmpty && audioTargets.isNotEmpty
      ? PlexTranscodeTarget._(videoTargets, audioTargets)
      : null;
  final directPlayProfile = desktop
      ? 'add-direct-play-profile(type=videoProfile&container=*&videoCodec=*&audioCodec=*&subtitleCodec=*&replace=true)'
      : c.known &&
            containers.isNotEmpty &&
            videos.isNotEmpty &&
            audio.isNotEmpty
      ? 'add-direct-play-profile(type=videoProfile&container=${containers.join(',')}&videoCodec=${videos.join(',')}&audioCodec=${audio.join(',')}&protocol=http&replace=true)'
      : null;
  final limitations = <String>[
    'add-limitation(scope=videoAudioCodec&scopeName=*&type=upperBound&name=audio.channels&value=8&replace=true)',
  ];
  if (!desktop && c.known) {
    for (final decoder in c.videoDecoders) {
      void limitation(
        String name,
        String value, {
        String type = 'upperBound',
        String field = 'value',
      }) {
        limitations.add(
          'add-limitation(scope=videoCodec&scopeName=${decoder.codec}&type=$type&name=$name&$field=$value&replace=true)',
        );
      }

      if (const {'hevc', 'h264', 'av1', 'vp9'}.contains(decoder.codec)) {
        // E2 confirms the bit-depth grammar against the current Generic profile.
        limitation('video.bitDepth', '${_maximumBitDepth(decoder)}');
      }
      if (decoder.maxWidth != null) {
        limitation('video.width', '${decoder.maxWidth}');
      }
      if (decoder.maxHeight != null) {
        limitation('video.height', '${decoder.maxHeight}');
      }
      final level = _plexLevel(decoder);
      if (level != null) {
        limitation('video.level', '$level');
      }
      if (decoder.profiles.isNotEmpty) {
        limitation(
          'video.profile',
          _plexVideoProfiles(decoder).join('|'),
          type: 'match',
          field: 'list',
        );
      }
      if (const {'h264', 'hevc', 'av1'}.contains(decoder.codec)) {
        // E2 confirms this DV match-list form; absent DV is optional for SDR/HDR10.
        limitations.add(
          'add-limitation(scope=videoCodec&scopeName=${decoder.codec}&type=match&name=video.DOVIProfile&list=${decoder.dolbyVisionProfiles.join('|')}&isRequired=false&replace=true)',
        );
      }
    }
  }
  return PlexProfile._(
    directPlayProfile: directPlayProfile,
    limitations: limitations,
    transcodeTarget: target,
    eligible: (facts) {
      if (desktop) return true;
      if (!c.known ||
          facts.container == null ||
          facts.videoCodec == null ||
          facts.videoProfile == null ||
          facts.bitDepth == null ||
          facts.width == null ||
          facts.height == null ||
          facts.audioCodec == null ||
          !containers.contains(facts.container) ||
          !audio.contains(facts.audioCodec)) {
        return false;
      }
      return c.videoDecoders.any(
        (decoder) =>
            decoder.codec == facts.videoCodec &&
            _plexVideoProfiles(decoder).contains(facts.videoProfile) &&
            facts.bitDepth! > 0 &&
            facts.bitDepth! <= _maximumBitDepth(decoder) &&
            decoder.maxWidth != null &&
            facts.width! > 0 &&
            facts.width! <= decoder.maxWidth! &&
            decoder.maxHeight != null &&
            facts.height! > 0 &&
            facts.height! <= decoder.maxHeight! &&
            _withinLevel(facts.maxLevel, decoder) &&
            (facts.dolbyVisionProfile == null ||
                decoder.dolbyVisionProfiles.contains(facts.dolbyVisionProfile)),
      );
    },
  );
}

String _plexAudioCodec(String codec) => switch (codec) {
  'dts' || 'dtshd' => 'dca',
  _ => codec,
};
int _maximumBitDepth(VideoDecoderCapabilities decoder) =>
    decoder.profiles.any(
      (profile) =>
          profile.toLowerCase().contains('10') ||
          profile.toLowerCase().contains('profile 2') ||
          profile.toLowerCase().contains('profile2') ||
          (decoder.codec == 'vp9' && (profile == '2' || profile == '3')),
    )
    ? 10
    : 8;
// Only H.264 and HEVC level policy is confirmed. Bitrate and other codec
// levels remain capability facts until their PMS decision policy is confirmed.
int? _levelScale(String codec) => switch (codec) {
  'h264' => 10,
  'hevc' => 30,
  _ => null,
};

int? _plexLevel(VideoDecoderCapabilities decoder) {
  final scale = _levelScale(decoder.codec);
  final value = double.tryParse(decoder.maxLevel ?? '');
  if (scale == null || value == null || !value.isFinite || value <= 0) {
    return null;
  }
  final encoded = value * scale;
  if (!encoded.isFinite) return null;
  final rounded = encoded.round();
  return (encoded - rounded).abs() < 0.000001 ? rounded : null;
}

bool _withinLevel(String? source, VideoDecoderCapabilities decoder) {
  if (_levelScale(decoder.codec) == null || decoder.maxLevel == null) {
    return true;
  }
  final limit = _plexLevel(decoder);
  final value = int.tryParse(source ?? '');
  return limit != null && value != null && value > 0 && value <= limit;
}

List<String> _plexVideoProfiles(VideoDecoderCapabilities decoder) => [
  // FFmpeg reports AV1 Main independently of bit depth, and names VP9 profiles.
  ...decoder.profiles
      .map(
        (profile) => switch ((decoder.codec, profile)) {
          ('av1', 'main 10') => 'main',
          ('vp9', '0' || '1' || '2' || '3') => 'profile $profile',
          _ => profile,
        },
      )
      .toSet(),
];
