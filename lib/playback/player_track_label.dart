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

  String get secondaryText => secondaryFacts.join(' • ');
}

/// Pure, shared presentation policy for audio and subtitle track choices.
PlayerTrackDisplay formatPlayerTrackDisplay(
  PlayerTrack track, {
  Iterable<PlayerTrack> peers = const <PlayerTrack>[],
}) {
  final sameType = peers
      .where((peer) => peer.type == track.type)
      .toList(growable: false);
  final facts = _TrackFacts.from(track);
  final base = _baseDisplay(track, facts);
  final needsTrackDiscriminator = sameType.any((peer) {
    if (peer.id == track.id) return false;
    final peerFacts = _TrackFacts.from(peer);
    final peerBase = _baseDisplay(peer, peerFacts);
    return peerBase.visibleKey == base.visibleKey;
  });
  final secondaryFacts = [
    if (needsTrackDiscriminator) 'Track ${track.id}',
    ...base.secondaryFacts,
  ];
  final compactText = _compactText(track, facts, sameType, base);
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
    required this.purposes,
    required this.channels,
    required this.codec,
  });

  factory _TrackFacts.from(PlayerTrack track) {
    final title = _clean(track.title);
    final language = _language(track.language);
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
      title: title,
      purposes: purposes,
      channels: channels,
      codec: _codec(track.codec),
    );
  }

  final String? language;
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
  PlayerTrack track,
  _TrackFacts facts,
  List<PlayerTrack> peers,
  _BaseDisplay base,
) {
  final language = facts.language;
  final purposes = facts.purposes;
  final title = base.titleText;
  if (language == null) return title ?? purposes.firstOrNull;

  final sameCompact = peers.where((peer) => peer.id != track.id).any((peer) {
    final otherFacts = _TrackFacts.from(peer);
    return _compactKey(otherFacts) == _compactKey(facts);
  });
  final purposeText = purposes.join(' • ');
  final titleDiffers =
      title != null &&
      peers.any((peer) {
        if (peer.id == track.id || peer.type != track.type) return false;
        final otherTitle = _baseDisplay(peer, _TrackFacts.from(peer)).titleText;
        return _equivalenceKey(otherTitle) != _equivalenceKey(title);
      });
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
  return count != null && count > 0 ? '$count channels' : null;
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
