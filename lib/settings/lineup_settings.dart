enum GuideDensity { comfortable, compact }

enum VideoQuality { original, high, medium, low }

enum ToneMapPolicy { automatic, always, never }

enum SubtitleMode { off, forced, full }

class LineupSettings {
  const LineupSettings({
    this.guideHours = 4,
    this.pastMinutes = 30,
    this.guideDensity = GuideDensity.comfortable,
    this.videoQuality = VideoQuality.original,
    this.toneMapPolicy = ToneMapPolicy.automatic,
    this.audioOutput = 'system',
    this.audioPassthrough = false,
    this.directPlayAudioFallback = false,
    this.subtitleMode = SubtitleMode.full,
    this.subtitleLanguage = '',
    this.preferForcedSubtitles = false,
    this.reduceMotion = false,
    this.largeFocusIndicators = false,
    this.profilePickerOnStartup = false,
    this.diagnosticsEnabled = false,
  });

  final int guideHours;
  final int pastMinutes;
  final GuideDensity guideDensity;
  final VideoQuality videoQuality;
  final ToneMapPolicy toneMapPolicy;
  final String audioOutput;
  final bool audioPassthrough;
  final bool directPlayAudioFallback;
  final SubtitleMode subtitleMode;
  final String subtitleLanguage;
  final bool preferForcedSubtitles;
  final bool reduceMotion;
  final bool largeFocusIndicators;
  final bool profilePickerOnStartup;
  final bool diagnosticsEnabled;

  LineupSettings copyWith({
    int? guideHours,
    int? pastMinutes,
    GuideDensity? guideDensity,
    VideoQuality? videoQuality,
    ToneMapPolicy? toneMapPolicy,
    String? audioOutput,
    bool? audioPassthrough,
    bool? directPlayAudioFallback,
    SubtitleMode? subtitleMode,
    String? subtitleLanguage,
    bool? preferForcedSubtitles,
    bool? reduceMotion,
    bool? largeFocusIndicators,
    bool? profilePickerOnStartup,
    bool? diagnosticsEnabled,
  }) => LineupSettings(
    guideHours: guideHours ?? this.guideHours,
    pastMinutes: pastMinutes ?? this.pastMinutes,
    guideDensity: guideDensity ?? this.guideDensity,
    videoQuality: videoQuality ?? this.videoQuality,
    toneMapPolicy: toneMapPolicy ?? this.toneMapPolicy,
    audioOutput: audioOutput ?? this.audioOutput,
    audioPassthrough: audioPassthrough ?? this.audioPassthrough,
    directPlayAudioFallback:
        directPlayAudioFallback ?? this.directPlayAudioFallback,
    subtitleMode: subtitleMode ?? this.subtitleMode,
    subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
    preferForcedSubtitles: preferForcedSubtitles ?? this.preferForcedSubtitles,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    largeFocusIndicators: largeFocusIndicators ?? this.largeFocusIndicators,
    profilePickerOnStartup:
        profilePickerOnStartup ?? this.profilePickerOnStartup,
    diagnosticsEnabled: diagnosticsEnabled ?? this.diagnosticsEnabled,
  );

  Map<String, Object?> toJson() => {
    'guideHours': guideHours,
    'pastMinutes': pastMinutes,
    'guideDensity': guideDensity.name,
    'videoQuality': videoQuality.name,
    'toneMapPolicy': toneMapPolicy.name,
    'audioOutput': audioOutput,
    'audioPassthrough': audioPassthrough,
    'directPlayAudioFallback': directPlayAudioFallback,
    'subtitleMode': subtitleMode.name,
    'subtitleLanguage': subtitleLanguage,
    'preferForcedSubtitles': preferForcedSubtitles,
    'reduceMotion': reduceMotion,
    'largeFocusIndicators': largeFocusIndicators,
    'profilePickerOnStartup': profilePickerOnStartup,
    'diagnosticsEnabled': diagnosticsEnabled,
  };

  factory LineupSettings.fromJson(Object? value) {
    if (value is! Map) return const LineupSettings();
    final json = Map<String, Object?>.from(value);
    T enumValue<T extends Enum>(List<T> values, String key, T fallback) =>
        values.where((value) => value.name == json[key]).firstOrNull ??
        fallback;
    final guideHours = (json['guideHours'] as num?)?.toInt() ?? 4;
    final pastMinutes = (json['pastMinutes'] as num?)?.toInt() ?? 30;
    return LineupSettings(
      guideHours: guideHours.clamp(2, 12),
      pastMinutes: pastMinutes.clamp(0, 180),
      guideDensity: enumValue(
        GuideDensity.values,
        'guideDensity',
        GuideDensity.comfortable,
      ),
      videoQuality: enumValue(
        VideoQuality.values,
        'videoQuality',
        VideoQuality.original,
      ),
      toneMapPolicy: enumValue(
        ToneMapPolicy.values,
        'toneMapPolicy',
        ToneMapPolicy.automatic,
      ),
      audioOutput: json['audioOutput'] is String
          ? json['audioOutput']! as String
          : 'system',
      audioPassthrough: json['audioPassthrough'] == true,
      directPlayAudioFallback: json['directPlayAudioFallback'] == true,
      subtitleMode: enumValue(
        SubtitleMode.values,
        'subtitleMode',
        SubtitleMode.full,
      ),
      subtitleLanguage: json['subtitleLanguage'] is String
          ? json['subtitleLanguage']! as String
          : '',
      preferForcedSubtitles: json['preferForcedSubtitles'] == true,
      reduceMotion: json['reduceMotion'] == true,
      largeFocusIndicators: json['largeFocusIndicators'] == true,
      profilePickerOnStartup: json['profilePickerOnStartup'] == true,
      diagnosticsEnabled: json['diagnosticsEnabled'] == true,
    );
  }
}
