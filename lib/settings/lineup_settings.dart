enum GuideDensity { comfortable, compact }

enum GuideLayoutMode { pictureInPicture, overlay }

enum LineupThemeName {
  emberSteel('ember-steel', 'Ember & Steel'),
  slatePine('slate-pine', 'Slate & Pine'),
  swiss('swiss', 'Swiss Minimal'),
  directv('directv', 'DirecTV Classic'),
  glass('glass', 'Glassmorphism');

  const LineupThemeName(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static LineupThemeName fromStorage(Object? value) => values.firstWhere(
    (theme) => theme.storageKey == value,
    orElse: () => emberSteel,
  );
}

enum VideoQuality { original, high, medium, low }

enum ToneMapPolicy { automatic, always, never }

enum SubtitleMode { off, forced, full }

class LineupSettings {
  const LineupSettings({
    this.theme = LineupThemeName.emberSteel,
    this.guideHours = 4,
    this.pastMinutes = 30,
    this.guideDensity = GuideDensity.comfortable,
    this.guideLayoutMode = GuideLayoutMode.pictureInPicture,
    this.videoQuality = VideoQuality.original,
    this.toneMapPolicy = ToneMapPolicy.automatic,
    this.audioOutput = 'system',
    this.audioPassthrough = false,
    this.directPlayAudioFallback = false,
    this.audioSetupComplete = false,
    this.subtitleMode = SubtitleMode.full,
    this.subtitleLanguage = '',
    this.preferForcedSubtitles = false,
    this.reduceMotion = false,
    this.largeFocusIndicators = false,
    this.profilePickerOnStartup = false,
    this.diagnosticsEnabled = false,
  });

  final LineupThemeName theme;
  final int guideHours;
  final int pastMinutes;
  final GuideDensity guideDensity;
  final GuideLayoutMode guideLayoutMode;
  final VideoQuality videoQuality;
  final ToneMapPolicy toneMapPolicy;
  final String audioOutput;
  final bool audioPassthrough;
  final bool directPlayAudioFallback;
  final bool audioSetupComplete;
  final SubtitleMode subtitleMode;
  final String subtitleLanguage;
  final bool preferForcedSubtitles;
  final bool reduceMotion;
  final bool largeFocusIndicators;
  final bool profilePickerOnStartup;
  final bool diagnosticsEnabled;

  LineupSettings copyWith({
    LineupThemeName? theme,
    int? guideHours,
    int? pastMinutes,
    GuideDensity? guideDensity,
    GuideLayoutMode? guideLayoutMode,
    VideoQuality? videoQuality,
    ToneMapPolicy? toneMapPolicy,
    String? audioOutput,
    bool? audioPassthrough,
    bool? directPlayAudioFallback,
    bool? audioSetupComplete,
    SubtitleMode? subtitleMode,
    String? subtitleLanguage,
    bool? preferForcedSubtitles,
    bool? reduceMotion,
    bool? largeFocusIndicators,
    bool? profilePickerOnStartup,
    bool? diagnosticsEnabled,
  }) => LineupSettings(
    theme: theme ?? this.theme,
    guideHours: guideHours ?? this.guideHours,
    pastMinutes: pastMinutes ?? this.pastMinutes,
    guideDensity: guideDensity ?? this.guideDensity,
    guideLayoutMode: guideLayoutMode ?? this.guideLayoutMode,
    videoQuality: videoQuality ?? this.videoQuality,
    toneMapPolicy: toneMapPolicy ?? this.toneMapPolicy,
    audioOutput: audioOutput ?? this.audioOutput,
    audioPassthrough: audioPassthrough ?? this.audioPassthrough,
    directPlayAudioFallback:
        directPlayAudioFallback ?? this.directPlayAudioFallback,
    audioSetupComplete: audioSetupComplete ?? this.audioSetupComplete,
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
    'theme': theme.storageKey,
    'guideHours': guideHours,
    'pastMinutes': pastMinutes,
    'guideDensity': guideDensity.name,
    'guideLayoutMode': guideLayoutMode.name,
    'videoQuality': videoQuality.name,
    'toneMapPolicy': toneMapPolicy.name,
    'audioOutput': audioOutput,
    'audioPassthrough': audioPassthrough,
    'directPlayAudioFallback': directPlayAudioFallback,
    'audioSetupComplete': audioSetupComplete,
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
      theme: LineupThemeName.fromStorage(json['theme']),
      guideHours: guideHours.clamp(2, 12),
      pastMinutes: pastMinutes.clamp(0, 180),
      guideDensity: enumValue(
        GuideDensity.values,
        'guideDensity',
        GuideDensity.comfortable,
      ),
      guideLayoutMode: enumValue(
        GuideLayoutMode.values,
        'guideLayoutMode',
        GuideLayoutMode.pictureInPicture,
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
      audioSetupComplete: json['audioSetupComplete'] == true,
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
