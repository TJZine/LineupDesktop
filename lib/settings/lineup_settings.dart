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
    this.dvrControlsEnabled = false,
    this.libraryTabsEnabled = true,
    this.nowWatchingBanner = true,
    this.osdAutoHideSeconds = 4,
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
  final bool dvrControlsEnabled;
  final bool libraryTabsEnabled;
  final bool nowWatchingBanner;
  final int osdAutoHideSeconds;
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
    bool? dvrControlsEnabled,
    bool? libraryTabsEnabled,
    bool? nowWatchingBanner,
    int? osdAutoHideSeconds,
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
    dvrControlsEnabled: dvrControlsEnabled ?? this.dvrControlsEnabled,
    libraryTabsEnabled: libraryTabsEnabled ?? this.libraryTabsEnabled,
    nowWatchingBanner: nowWatchingBanner ?? this.nowWatchingBanner,
    osdAutoHideSeconds: osdAutoHideSeconds ?? this.osdAutoHideSeconds,
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
    'dvrControlsEnabled': dvrControlsEnabled,
    'libraryTabsEnabled': libraryTabsEnabled,
    'nowWatchingBanner': nowWatchingBanner,
    'osdAutoHideSeconds': osdAutoHideSeconds,
    // Retain the legacy canonical key so existing settings continue to load.
    // It no longer gates onboarding and must not seed future passthrough state.
    'audioSetupComplete': true,
    'reduceMotion': reduceMotion,
    'largeFocusIndicators': largeFocusIndicators,
    'profilePickerOnStartup': profilePickerOnStartup,
    'diagnosticsEnabled': diagnosticsEnabled,
  };

  factory LineupSettings.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid settings');
    late final Map<String, Object?> json;
    try {
      json = Map<String, Object?>.from(value);
    } catch (error) {
      throw FormatException('Invalid settings', error);
    }
    const fields = {
      'theme',
      'guideHours',
      'pastMinutes',
      'guideDensity',
      'guideLayoutMode',
      'guideInfoBackgroundMode',
      'preferClearLogos',
      'dvrControlsEnabled',
      'libraryTabsEnabled',
      'nowWatchingBanner',
      'osdAutoHideSeconds',
      'audioSetupComplete',
      'reduceMotion',
      'largeFocusIndicators',
      'profilePickerOnStartup',
      'diagnosticsEnabled',
    };
    final keys = json.keys.toSet();
    final requiredFields = fields.difference({'dvrControlsEnabled'});
    if (!keys.containsAll(requiredFields) ||
        keys.difference(fields).isNotEmpty) {
      throw const FormatException('Settings fields are not canonical');
    }

    T enumValue<T>(List<T> values, String key, String Function(T) storage) {
      final persisted = json[key];
      if (persisted is! String) throw FormatException('Invalid $key');
      return values.where((value) => storage(value) == persisted).firstOrNull ??
          (throw FormatException('Invalid $key'));
    }

    int option(String key, List<int> options) {
      final persisted = json[key];
      if (persisted is! int || !options.contains(persisted)) {
        throw FormatException('Invalid $key');
      }
      return persisted;
    }

    bool boolean(String key) {
      final persisted = json[key];
      if (persisted is! bool) throw FormatException('Invalid $key');
      return persisted;
    }

    bool optionalBoolean(String key, {required bool fallback}) {
      if (!json.containsKey(key)) return fallback;
      return boolean(key);
    }

    // Validate and discard the retired onboarding flag.
    boolean('audioSetupComplete');
    return LineupSettings(
      theme: enumValue(
        LineupThemeName.values,
        'theme',
        (theme) => theme.storageKey,
      ),
      guideHours: option('guideHours', guideHoursOptions),
      pastMinutes: option('pastMinutes', pastMinutesOptions),
      guideDensity: enumValue(
        GuideDensity.values,
        'guideDensity',
        (density) => density.name,
      ),
      guideLayoutMode: enumValue(
        GuideLayoutMode.values,
        'guideLayoutMode',
        (mode) => mode.name,
      ),
      guideInfoBackgroundMode: enumValue(
        GuideInfoBackgroundMode.values,
        'guideInfoBackgroundMode',
        (mode) => mode.name,
      ),
      preferClearLogos: boolean('preferClearLogos'),
      dvrControlsEnabled: optionalBoolean(
        'dvrControlsEnabled',
        fallback: false,
      ),
      libraryTabsEnabled: boolean('libraryTabsEnabled'),
      nowWatchingBanner: boolean('nowWatchingBanner'),
      osdAutoHideSeconds: option(
        'osdAutoHideSeconds',
        osdAutoHideSecondsOptions,
      ),
      reduceMotion: boolean('reduceMotion'),
      largeFocusIndicators: boolean('largeFocusIndicators'),
      profilePickerOnStartup: boolean('profilePickerOnStartup'),
      diagnosticsEnabled: boolean('diagnosticsEnabled'),
    );
  }
}
