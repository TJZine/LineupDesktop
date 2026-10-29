import 'subtitle_style.dart';

enum OverlayTransparency {
  moreTransparent('more-transparent', 'More transparent'),
  standard('standard', 'Standard'),
  reduced('reduced', 'Reduce transparency');

  const OverlayTransparency(this.storageKey, this.label);
  final String storageKey;
  final String label;
}

enum GuideInfoBackgroundMode { bleed, themeDefault, artwork }

enum LineupThemeName {
  emberSteel('ember-steel', 'Ember & Steel'),
  slatePine('slate-pine', 'Slate & Pine'),
  swiss('swiss', 'Mint Noir'),
  directv('directv', 'Satellite Blue');

  const LineupThemeName(this.storageKey, this.label);

  final String storageKey;
  final String label;
}

class LineupSettings {
  static const guideHoursOptions = [2, 3, 4];
  static const osdAutoHideSecondsOptions = [2, 4, 6, 8, 10, 15];

  const LineupSettings({
    this.overlayTransparency = OverlayTransparency.standard,
    this.theme = LineupThemeName.emberSteel,
    this.guideHours = 2,
    this.guideShowChannelSources = false,
    this.guideInfoBackgroundMode = GuideInfoBackgroundMode.bleed,
    this.preferClearLogos = true,
    this.dvrControlsEnabled = false,
    this.matchDisplayHdr = true,
    this.nowWatchingBanner = true,
    this.osdAutoHideSeconds = 4,
    this.reduceMotion = false,
    this.largeFocusIndicators = false,
    this.profilePickerOnStartup = false,
    this.diagnosticsEnabled = false,
    this.subtitleStyle = const SubtitleStyle(),
  });

  final OverlayTransparency overlayTransparency;
  final LineupThemeName theme;
  final int guideHours;
  final bool guideShowChannelSources;
  final GuideInfoBackgroundMode guideInfoBackgroundMode;
  final bool preferClearLogos;
  final bool dvrControlsEnabled;
  final bool matchDisplayHdr;
  final bool nowWatchingBanner;
  final int osdAutoHideSeconds;
  final bool reduceMotion;
  final bool largeFocusIndicators;
  final bool profilePickerOnStartup;
  final bool diagnosticsEnabled;
  final SubtitleStyle subtitleStyle;

  LineupSettings copyWith({
    OverlayTransparency? overlayTransparency,
    LineupThemeName? theme,
    int? guideHours,
    bool? guideShowChannelSources,
    GuideInfoBackgroundMode? guideInfoBackgroundMode,
    bool? preferClearLogos,
    bool? dvrControlsEnabled,
    bool? matchDisplayHdr,
    bool? nowWatchingBanner,
    int? osdAutoHideSeconds,
    bool? reduceMotion,
    bool? largeFocusIndicators,
    bool? profilePickerOnStartup,
    bool? diagnosticsEnabled,
    SubtitleStyle? subtitleStyle,
  }) => LineupSettings(
    overlayTransparency: overlayTransparency ?? this.overlayTransparency,
    theme: theme ?? this.theme,
    guideHours: guideHours ?? this.guideHours,
    guideShowChannelSources:
        guideShowChannelSources ?? this.guideShowChannelSources,
    guideInfoBackgroundMode:
        guideInfoBackgroundMode ?? this.guideInfoBackgroundMode,
    preferClearLogos: preferClearLogos ?? this.preferClearLogos,
    dvrControlsEnabled: dvrControlsEnabled ?? this.dvrControlsEnabled,
    matchDisplayHdr: matchDisplayHdr ?? this.matchDisplayHdr,
    nowWatchingBanner: nowWatchingBanner ?? this.nowWatchingBanner,
    osdAutoHideSeconds: osdAutoHideSeconds ?? this.osdAutoHideSeconds,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    largeFocusIndicators: largeFocusIndicators ?? this.largeFocusIndicators,
    profilePickerOnStartup:
        profilePickerOnStartup ?? this.profilePickerOnStartup,
    diagnosticsEnabled: diagnosticsEnabled ?? this.diagnosticsEnabled,
    subtitleStyle: subtitleStyle ?? this.subtitleStyle,
  );

  Map<String, Object?> toJson() => {
    'overlayTransparency': overlayTransparency.storageKey,
    'theme': theme.storageKey,
    'guideHours': guideHours,
    'guideShowChannelSources': guideShowChannelSources,
    'guideInfoBackgroundMode': guideInfoBackgroundMode.name,
    'preferClearLogos': preferClearLogos,
    'dvrControlsEnabled': dvrControlsEnabled,
    'matchDisplayHdr': matchDisplayHdr,
    'nowWatchingBanner': nowWatchingBanner,
    'osdAutoHideSeconds': osdAutoHideSeconds,
    'audioSetupComplete': true,
    'reduceMotion': reduceMotion,
    'largeFocusIndicators': largeFocusIndicators,
    'profilePickerOnStartup': profilePickerOnStartup,
    'diagnosticsEnabled': diagnosticsEnabled,
    'subtitleStyle': subtitleStyle.toJson(),
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
      'overlayTransparency',
      'theme',
      'guideHours',
      'guideShowChannelSources',
      'pastMinutes',
      'guideDensity',
      'guideLayoutMode',
      'guideInfoBackgroundMode',
      'preferClearLogos',
      'dvrControlsEnabled',
      'matchDisplayHdr',
      'libraryTabsEnabled',
      'nowWatchingBanner',
      'osdAutoHideSeconds',
      'audioSetupComplete',
      'reduceMotion',
      'largeFocusIndicators',
      'profilePickerOnStartup',
      'diagnosticsEnabled',
      'subtitleStyle',
    };
    final keys = json.keys.toSet();
    const retiredFields = {
      'pastMinutes',
      'guideDensity',
      'guideLayoutMode',
      'libraryTabsEnabled',
    };
    final requiredFields = fields.difference({
      'overlayTransparency',
      'dvrControlsEnabled',
      'matchDisplayHdr',
      'guideShowChannelSources',
      'subtitleStyle',
      ...retiredFields,
    });
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

    void retiredString(String key, Set<String> values) {
      final persisted = json[key];
      if (persisted is! String || !values.contains(persisted)) {
        throw FormatException('Invalid $key');
      }
    }

    if (json.containsKey('pastMinutes')) {
      option('pastMinutes', [0, 15, 30, 60, 120, 180]);
    }
    if (json.containsKey('guideDensity')) {
      retiredString('guideDensity', {'comfortable', 'compact'});
    }
    if (json.containsKey('guideLayoutMode')) {
      retiredString('guideLayoutMode', {'pictureInPicture', 'overlay'});
    }
    if (json.containsKey('libraryTabsEnabled')) {
      boolean('libraryTabsEnabled');
    }
    boolean('audioSetupComplete');
    final persistedGuideHours = option('guideHours', [
      ...guideHoursOptions,
      6,
      8,
      12,
    ]);
    return LineupSettings(
      overlayTransparency: json.containsKey('overlayTransparency')
          ? enumValue(
              OverlayTransparency.values,
              'overlayTransparency',
              (level) => level.storageKey,
            )
          : OverlayTransparency.standard,
      theme: json['theme'] == 'glass'
          ? LineupThemeName.emberSteel
          : enumValue(
              LineupThemeName.values,
              'theme',
              (theme) => theme.storageKey,
            ),
      guideHours: persistedGuideHours > 4 ? 4 : persistedGuideHours,
      guideShowChannelSources: optionalBoolean(
        'guideShowChannelSources',
        fallback: false,
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
      matchDisplayHdr: optionalBoolean('matchDisplayHdr', fallback: true),
      nowWatchingBanner: boolean('nowWatchingBanner'),
      osdAutoHideSeconds: option(
        'osdAutoHideSeconds',
        osdAutoHideSecondsOptions,
      ),
      reduceMotion: boolean('reduceMotion'),
      largeFocusIndicators: boolean('largeFocusIndicators'),
      profilePickerOnStartup: boolean('profilePickerOnStartup'),
      diagnosticsEnabled: boolean('diagnosticsEnabled'),
      subtitleStyle: json.containsKey('subtitleStyle')
          ? SubtitleStyle.fromJson(json['subtitleStyle'])
          : const SubtitleStyle(),
    );
  }
}
