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

class LineupSettings {
  const LineupSettings({
    this.theme = LineupThemeName.emberSteel,
    this.guideHours = 4,
    this.pastMinutes = 30,
    this.guideDensity = GuideDensity.comfortable,
    this.guideLayoutMode = GuideLayoutMode.pictureInPicture,
    this.libraryTabsEnabled = true,
    this.nowWatchingBanner = true,
    this.osdAutoHideSeconds = 4,
    this.audioSetupComplete = false,
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
  final bool libraryTabsEnabled;
  final bool nowWatchingBanner;
  final int osdAutoHideSeconds;
  final bool audioSetupComplete;
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
    bool? libraryTabsEnabled,
    bool? nowWatchingBanner,
    int? osdAutoHideSeconds,
    bool? audioSetupComplete,
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
    libraryTabsEnabled: libraryTabsEnabled ?? this.libraryTabsEnabled,
    nowWatchingBanner: nowWatchingBanner ?? this.nowWatchingBanner,
    osdAutoHideSeconds: osdAutoHideSeconds ?? this.osdAutoHideSeconds,
    audioSetupComplete: audioSetupComplete ?? this.audioSetupComplete,
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
    'libraryTabsEnabled': libraryTabsEnabled,
    'nowWatchingBanner': nowWatchingBanner,
    'osdAutoHideSeconds': osdAutoHideSeconds,
    'audioSetupComplete': audioSetupComplete,
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
    final osdAutoHideSeconds =
        (json['osdAutoHideSeconds'] as num?)?.toInt() ?? 4;
    return LineupSettings(
      theme: LineupThemeName.fromStorage(json['theme']),
      guideHours: guideHours.clamp(2, 12).toInt(),
      pastMinutes: pastMinutes.clamp(0, 180).toInt(),
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
      libraryTabsEnabled: json['libraryTabsEnabled'] != false,
      nowWatchingBanner: json['nowWatchingBanner'] != false,
      osdAutoHideSeconds: osdAutoHideSeconds.clamp(2, 15).toInt(),
      audioSetupComplete: json['audioSetupComplete'] == true,
      reduceMotion: json['reduceMotion'] == true,
      largeFocusIndicators: json['largeFocusIndicators'] == true,
      profilePickerOnStartup: json['profilePickerOnStartup'] == true,
      diagnosticsEnabled: json['diagnosticsEnabled'] == true,
    );
  }
}
