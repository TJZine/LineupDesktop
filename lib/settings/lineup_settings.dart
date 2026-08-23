enum GuideDensity { comfortable, compact }

enum GuideLayoutMode { pictureInPicture, overlay }

enum GuideInfoBackgroundMode { bleed, themeDefault, artwork }

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
  static const guideHoursOptions = [2, 3, 4, 6, 8, 12];
  static const pastMinutesOptions = [0, 15, 30, 60, 120, 180];
  static const osdAutoHideSecondsOptions = [2, 4, 6, 8, 10, 15];

  const LineupSettings({
    this.theme = LineupThemeName.emberSteel,
    this.guideHours = 2,
    this.pastMinutes = 30,
    this.guideDensity = GuideDensity.comfortable,
    this.guideLayoutMode = GuideLayoutMode.pictureInPicture,
    this.guideInfoBackgroundMode = GuideInfoBackgroundMode.bleed,
    this.preferClearLogos = true,
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
  final GuideInfoBackgroundMode guideInfoBackgroundMode;
  final bool preferClearLogos;
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
    GuideInfoBackgroundMode? guideInfoBackgroundMode,
    bool? preferClearLogos,
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
    guideInfoBackgroundMode:
        guideInfoBackgroundMode ?? this.guideInfoBackgroundMode,
    preferClearLogos: preferClearLogos ?? this.preferClearLogos,
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
    'guideInfoBackgroundMode': guideInfoBackgroundMode.name,
    'preferClearLogos': preferClearLogos,
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
    int number(String key, int fallback) {
      final value = json[key];
      return value is num && value.isFinite ? value.toInt() : fallback;
    }

    int option(String key, int fallback, List<int> options) {
      final value = number(key, fallback);
      return options.reduce((best, candidate) {
        final bestDistance = (best - value).abs();
        final candidateDistance = (candidate - value).abs();
        return candidateDistance <= bestDistance ? candidate : best;
      });
    }

    return LineupSettings(
      theme: LineupThemeName.fromStorage(json['theme']),
      guideHours: option('guideHours', 2, guideHoursOptions),
      pastMinutes: option('pastMinutes', 30, pastMinutesOptions),
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
      guideInfoBackgroundMode: enumValue(
        GuideInfoBackgroundMode.values,
        'guideInfoBackgroundMode',
        GuideInfoBackgroundMode.bleed,
      ),
      preferClearLogos: json['preferClearLogos'] != false,
      libraryTabsEnabled: json['libraryTabsEnabled'] != false,
      nowWatchingBanner: json['nowWatchingBanner'] != false,
      osdAutoHideSeconds: option(
        'osdAutoHideSeconds',
        4,
        osdAutoHideSecondsOptions,
      ),
      audioSetupComplete: json['audioSetupComplete'] == true,
      reduceMotion: json['reduceMotion'] == true,
      largeFocusIndicators: json['largeFocusIndicators'] == true,
      profilePickerOnStartup: json['profilePickerOnStartup'] == true,
      diagnosticsEnabled: json['diagnosticsEnabled'] == true,
    );
  }
}
