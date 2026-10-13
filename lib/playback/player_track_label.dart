import 'package:language_code/language_code.dart';

import 'native_player.dart';

/// The complete display contract for one audio or subtitle track.
class PlayerTrackDisplay {
  PlayerTrackDisplay({
    required this.primaryText,
    required List<String> secondaryFacts,
    required this.compactText,
    required this.tooltipText,
    required this.semanticsText,
  }) : secondaryFacts = List.unmodifiable(secondaryFacts);

  final String primaryText;
  final List<String> secondaryFacts;
  final String? compactText;
  final String tooltipText;
  final String semanticsText;
}

/// A view-owned cache shared by compact controls and the track drawer.
class PlayerTrackDisplayCache {
  PlayerTrackDisplayProjection? _projection;

  PlayerTrackDisplayProjection forTracks(Iterable<PlayerTrack> tracks) {
    if (_projection?.matches(tracks) != true) {
      _projection = PlayerTrackDisplayProjection(tracks);
    }
    return _projection!;
  }
}

/// Prepared display policy for a complete immutable track snapshot.
/// Selection is deliberately excluded: callers read confirmed selection live.
class PlayerTrackDisplayProjection {
  PlayerTrackDisplayProjection(Iterable<PlayerTrack> tracks)
    : _tracks = List.unmodifiable(tracks) {
    _regional = [
      for (final track in _tracks) _regionalLanguage(track.language),
    ];
    final facts = [for (final track in _tracks) _factsFor(track)];
    _bases = [
      for (var i = 0; i < _tracks.length; i++)
        _baseDisplay(_tracks[i], facts[i]),
    ];
    _compactKeys = [for (final fact in facts) _compactKey(fact)];
    _titleKeys = [for (final base in _bases) _equivalenceKey(base.titleText)];
    _displays = List.unmodifiable([
      for (var i = 0; i < _tracks.length; i++)
        _displayFor(_tracks[i], facts[i], _bases[i]),
    ]);
  }

  final List<PlayerTrack> _tracks;
  late final List<({String? language, String? region})> _regional;
  late final List<_BaseDisplay> _bases;
  late final List<String> _compactKeys;
  late final List<String?> _titleKeys;
  late final List<PlayerTrackDisplay> _displays;

  _TrackFacts _factsFor(PlayerTrack track) {
    final index = _tracks.indexOf(track);
    final regional = index < 0
        ? _regionalLanguage(track.language)
        : _regional[index];
    final disambiguateRegion =
        regional.region != null &&
        _tracks.indexed.any(
          (entry) =>
              entry.$2.type == track.type &&
              entry.$2.id != track.id &&
              _regional[entry.$1].language == regional.language &&
              _regional[entry.$1].region != null &&
              _regional[entry.$1].region != regional.region,
        );
    return _TrackFacts.from(
      track,
      language: disambiguateRegion
          ? _language(track.language)
          : regional.language,
      region: disambiguateRegion ? null : regional.region,
    );
  }

  PlayerTrackDisplay _displayFor(
    PlayerTrack track,
    _TrackFacts facts,
    _BaseDisplay base,
  ) {
    final compactKey = _compactKey(facts);
    final titleKey = _equivalenceKey(base.titleText);
    return _display(
      track,
      facts,
      base,
      needsTrackDiscriminator: _tracks.indexed.any(
        (entry) =>
            entry.$2.type == track.type &&
            entry.$2.id != track.id &&
            _bases[entry.$1].visibleKey == base.visibleKey,
      ),
      sameCompact: _tracks.indexed.any(
        (entry) =>
            entry.$2.type == track.type &&
            entry.$2.id != track.id &&
            _compactKeys[entry.$1] == compactKey,
      ),
      titleDiffers: _tracks.indexed.any(
        (entry) =>
            entry.$2.type == track.type &&
            entry.$2.id != track.id &&
            _titleKeys[entry.$1] != titleKey,
      ),
    );
  }

  /// Reuses labels across position, pending-command and selection updates.
  /// Order, type, identity and every display input must still match.
  bool matches(Iterable<PlayerTrack> tracks) {
    final current = tracks.iterator;
    for (final previous in _tracks) {
      if (!current.moveNext() ||
          _displayInputs(previous) != _displayInputs(current.current)) {
        return false;
      }
    }
    return !current.moveNext();
  }

  PlayerTrackDisplay displayFor(PlayerTrack track) {
    final index = _tracks.indexWhere(
      (entry) => entry.type == track.type && entry.id == track.id,
    );
    if (index < 0) {
      throw ArgumentError.value(track.id, 'track', 'Not in this snapshot');
    }
    return _displays[index];
  }
}

Object _displayInputs(PlayerTrack track) => (
  track.id,
  track.type,
  track.title,
  track.language,
  track.codec,
  track.channelCount,
  track.channelLayout,
  track.forced,
  track.external,
  track.hearingImpaired,
  track.visualImpaired,
  track.commentary,
);

/// Pure, shared presentation policy for an individual track choice.
PlayerTrackDisplay formatPlayerTrackDisplay(
  PlayerTrack track, {
  Iterable<PlayerTrack> peers = const <PlayerTrack>[],
}) {
  final projection = PlayerTrackDisplayProjection(peers);
  final facts = projection._factsFor(track);
  return projection._displayFor(track, facts, _baseDisplay(track, facts));
}

PlayerTrackDisplay _display(
  PlayerTrack track,
  _TrackFacts facts,
  _BaseDisplay base, {
  required bool needsTrackDiscriminator,
  required bool sameCompact,
  required bool titleDiffers,
}) {
  final secondaryFacts = [
    if (needsTrackDiscriminator) 'Track ${track.id}',
    ...base.secondaryFacts,
  ];
  final compactText = _compactText(
    facts,
    base,
    sameCompact: sameCompact,
    titleDiffers: titleDiffers,
  );
  final description = _description(base.primaryText, secondaryFacts);
  final semanticsDescription = _semanticsDescription(base, secondaryFacts);
  final typeName = _typeName(track.type);
  return PlayerTrackDisplay(
    primaryText: base.primaryText,
    secondaryFacts: secondaryFacts,
    compactText: compactText,
    tooltipText: '$typeName track: $description',
    semanticsText: 'Select $typeName track: $semanticsDescription.',
  );
}

class _TrackFacts {
  const _TrackFacts({
    required this.language,
    required this.title,
    required this.region,
    required this.purposes,
    required this.channels,
    required this.codec,
  });

  factory _TrackFacts.from(
    PlayerTrack track, {
    required String? language,
    required String? region,
  }) {
    final title = _clean(track.title);
    final purposes = <String>[
      if (track.type == PlayerTrackType.audio && track.visualImpaired == true)
        'Audio description',
      if (track.type == PlayerTrackType.audio && track.commentary == true)
        'Commentary',
      if (track.type == PlayerTrackType.subtitle &&
          track.hearingImpaired == true)
        'SDH',
      if (track.type == PlayerTrackType.subtitle && track.forced == true)
        'Forced',
    ];
    final channels = track.type == PlayerTrackType.audio
        ? _channels(track.channelCount, track.channelLayout)
        : null;
    return _TrackFacts(
      language: language,
      region: region,
      title: title,
      purposes: purposes,
      channels: channels,
      codec: _codec(track.codec),
    );
  }

  final String? language;
  final String? region;
  final String? title;
  final List<String> purposes;
  final String? channels;
  final String? codec;
}

class _BaseDisplay {
  const _BaseDisplay({
    required this.primaryText,
    required this.secondaryFacts,
    required this.visibleKey,
    required this.primaryPurpose,
    required this.titleText,
  });

  final String primaryText;
  final List<String> secondaryFacts;
  final String visibleKey;
  final String? primaryPurpose;
  final String? titleText;
}

_BaseDisplay _baseDisplay(PlayerTrack track, _TrackFacts facts) {
  final languageKey = _equivalenceKey(facts.language);
  final rawLanguageKey = _equivalenceKey(_clean(track.language));
  final titleKey = _equivalenceKey(facts.title);
  final codecKey = _equivalenceKey(facts.codec);
  final rawCodecKey = _equivalenceKey(_clean(track.codec));
  final titleIsDuplicate =
      facts.title != null &&
      (titleKey == languageKey ||
          titleKey == rawLanguageKey ||
          titleKey == codecKey ||
          titleKey == rawCodecKey ||
          facts.purposes.any(
            (purpose) => titleKey == _equivalenceKey(purpose),
          ));
  final title = titleIsDuplicate ? null : facts.title;
  final primaryPurpose = title == null && facts.language != null
      ? facts.purposes.firstOrNull
      : null;
  final qualifier = title ?? primaryPurpose;
  final primary = facts.language == null
      ? qualifier ?? _fallbackTrackLabel(track.type, track.id)
      : qualifier == null
      ? facts.language!
      : '${facts.language} — $qualifier';
  final secondary = <String>[];
  final seen = <String>{};
  for (final value in [facts.language, title]) {
    final key = _equivalenceKey(value);
    if (key != null) seen.add(key);
  }
  void addFact(String? fact) {
    if (fact == null) return;
    final key = _equivalenceKey(fact);
    if (key != null && seen.add(key)) secondary.add(fact);
  }

  for (final purpose in facts.purposes) {
    if (purpose != primaryPurpose) addFact(purpose);
  }
  addFact(facts.region);
  addFact(facts.channels);
  addFact(facts.codec);
  if (track.external == true) addFact('External');
  return _BaseDisplay(
    primaryText: primary,
    secondaryFacts: secondary,
    visibleKey: _visibleKey(primary, secondary),
    primaryPurpose: primaryPurpose,
    titleText: title,
  );
}

String? _compactText(
  _TrackFacts facts,
  _BaseDisplay base, {
  required bool sameCompact,
  required bool titleDiffers,
}) {
  final language = facts.language;
  final purposes = facts.purposes;
  final title = base.titleText;
  if (language == null) return title ?? purposes.firstOrNull;
  final purposeText = purposes.join(' • ');
  if (title == null || !sameCompact || !titleDiffers) {
    return purposeText.isEmpty ? language : '$language — $purposeText';
  }
  final detail = purposeText.isEmpty ? title : '$purposeText · $title';
  return '$language — $detail';
}

String _compactKey(_TrackFacts facts) =>
    _visibleKey(facts.language ?? '', facts.purposes);

String _description(String primary, List<String> secondaryFacts) {
  if (secondaryFacts.isEmpty) return primary;
  return '$primary; ${secondaryFacts.join('; ')}';
}

String _semanticsDescription(_BaseDisplay base, List<String> secondaryFacts) {
  final primary = switch (base.primaryPurpose) {
    'SDH' => base.primaryText.replaceFirst(
      'SDH',
      'subtitles for deaf and hard-of-hearing viewers',
    ),
    'Forced' => base.primaryText.replaceFirst('Forced', 'marked as forced'),
    _ => base.primaryText,
  };
  final secondary = secondaryFacts
      .map(
        (fact) => switch (fact) {
          'SDH' => 'subtitles for deaf and hard-of-hearing viewers',
          'Forced' => 'marked as forced',
          _ => fact,
        },
      )
      .join('; ');
  return secondary.isEmpty ? primary : '$primary; $secondary';
}

({String? language, String? region}) _regionalLanguage(String? value) {
  final full = _language(value);
  final parts = _clean(value)?.split(RegExp(r'[-_]'));
  if (parts == null || parts.length < 2) return (language: full, region: null);
  final last = parts.last;
  if (!RegExp(r'^(?:[A-Za-z]{2}|[0-9]{3})$').hasMatch(last)) {
    return (language: full, region: null);
  }
  final base = _language(parts.take(parts.length - 1).join('-'));
  // Unknown tags retain the original label instead of inventing a region.
  if (full == _clean(value) || base == null || full == base) {
    return (language: full, region: null);
  }
  final qualifier =
      full!.toLowerCase().startsWith('${base.toLowerCase()} (') &&
          full.endsWith(')')
      ? full.substring(base.length + 2, full.length - 1)
      : full;
  return (language: base, region: qualifier);
}

/// Canonical short video codec policy shared by runtime and Plex facts.
String? formatPlayerVideoCodec(String? value) {
  final cleaned = _clean(value)?.toLowerCase();
  if (cleaned == null) return null;
  final token = RegExp(r'^[a-z0-9][a-z0-9_.-]{0,31}')
      .firstMatch(cleaned)
      ?.group(0);
  return switch (token) {
    'hevc' || 'h265' || 'h.265' => 'HEVC',
    'h264' || 'h.264' || 'avc' || 'avc1' => 'H.264',
    'av1' => 'AV1',
    'vp9' => 'VP9',
    'vp8' => 'VP8',
    'mpeg2video' || 'mpeg2' || 'mpeg-2' => 'MPEG-2',
    'mpeg1video' || 'mpeg1' || 'mpeg-1' => 'MPEG-1',
    'vc1' || 'vc-1' || 'wmv3' => 'VC-1',
    'mpeg4' => 'MPEG-4',
    _ => token?.toUpperCase(),
  };
}

String? _language(String? value) {
  final cleaned = _clean(value);
  if (cleaned == null) return null;
  final lower = cleaned.toLowerCase();
  if (lower == 'und') return null;
  if (lower == 'mul') return 'Multiple languages';
  if (lower == 'zxx') return 'No linguistic content';

  final parts = cleaned.split(RegExp(r'[-_]'));
  if (parts.any((part) => part.isEmpty)) return cleaned;
  final normalized = parts.indexed
      .map((entry) {
        final index = entry.$1;
        final part = entry.$2;
        if (index == 0) return part.toLowerCase();
        if (part.length == 4 && RegExp(r'^[A-Za-z]{4}$').hasMatch(part)) {
          return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
        }
        if ((part.length == 2 && RegExp(r'^[A-Za-z]{2}$').hasMatch(part)) ||
            (part.length == 3 && RegExp(r'^\d{3}$').hasMatch(part))) {
          return part.toUpperCase();
        }
        return part.toLowerCase();
      })
      .join('_');
  for (final code in LanguageCodes.values) {
    if (code.code == normalized) return code.nativeName;
  }
  return cleaned;
}

String? _channels(int? count, String? layout) {
  final cleanedLayout = _clean(layout);
  switch (cleanedLayout) {
    case 'stereo':
      return 'Stereo';
    case '5.1':
    case '5.1(side)':
      return '5.1 surround';
  }
  if (count == null || count <= 0) return null;
  return count == 1 ? '1 channel' : '$count channels';
}

String? _codec(String? value) {
  final cleaned = _clean(value);
  return switch (cleaned) {
    'aac' => 'AAC',
    'ac3' => 'Dolby Digital',
    'eac3' => 'Dolby Digital Plus',
    'truehd' => 'Dolby TrueHD',
    'dts' => 'DTS',
    'flac' => 'FLAC',
    'opus' => 'Opus',
    'subrip' => 'SRT (text)',
    'ass' => 'ASS (styled text)',
    'ssa' => 'SSA (styled text)',
    'hdmv_pgs_subtitle' => 'PGS (image)',
    'dvd_subtitle' => 'VobSub (image)',
    _ => cleaned,
  };
}

String? _clean(String? value) {
  final cleaned = value?.trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}

String? _equivalenceKey(String? value) {
  final cleaned = _clean(value);
  return cleaned?.replaceAll(RegExp(r'[\s_-]+'), ' ').trim().toLowerCase();
}

String _visibleKey(String primary, Iterable<String> secondary) => <String>[
  primary,
  ...secondary,
].map((value) => _equivalenceKey(value)).join('|');

String _fallbackTrackLabel(PlayerTrackType type, int id) {
  final kind = _typeName(type);
  return '$kind track $id';
}

String _typeName(PlayerTrackType type) => switch (type) {
  PlayerTrackType.audio => 'Audio',
  PlayerTrackType.subtitle => 'Subtitle',
  PlayerTrackType.video => 'Video',
};
