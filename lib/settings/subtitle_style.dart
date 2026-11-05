import 'package:flutter/foundation.dart';

enum SubtitleSize {
  p50('p50', '50%', 0.5),
  p75('p75', '75%', 0.75),
  p100('p100', '100%', 1.0),
  p125('p125', '125%', 1.25),
  p150('p150', '150%', 1.5),
  p200('p200', '200%', 2.0),
  p300('p300', '300%', 3.0);

  const SubtitleSize(this.storageKey, this.label, this.scale);
  final String storageKey;
  final String label;
  final double scale;
}

enum SubtitlePosition {
  bottom('bottom', 'Bottom', 0.0),
  raised('raised', 'Raised', 0.05),
  higher('higher', 'Higher', 0.1),
  highest('highest', 'Highest', 0.15);

  const SubtitlePosition(this.storageKey, this.label, this.raise);
  final String storageKey;
  final String label;
  final double raise;
}

enum SubtitleColor {
  white('white', 'White', 0xffffff),
  yellow('yellow', 'Yellow', 0xffff00),
  cyan('cyan', 'Cyan', 0x00ffff),
  green('green', 'Green', 0x00ff00),
  magenta('magenta', 'Magenta', 0xff00ff),
  red('red', 'Red', 0xff0000),
  blue('blue', 'Blue', 0x0000ff),
  black('black', 'Black', 0x000000);

  const SubtitleColor(this.storageKey, this.label, this.rgb);
  final String storageKey;
  final String label;
  final int rgb;
}

enum SubtitleTextOpacity {
  full('full', '100%', 1.0),
  threeQuarters('threeQuarters', '75%', 0.75),
  half('half', '50%', 0.5),
  quarter('quarter', '25%', 0.25);

  const SubtitleTextOpacity(this.storageKey, this.label, this.opacity);
  final String storageKey;
  final String label;
  final double opacity;
}

enum SubtitleBoxOpacity {
  off('off', 'Off', 0.0),
  quarter('quarter', '25%', 0.25),
  half('half', '50%', 0.5),
  threeQuarters('threeQuarters', '75%', 0.75),
  full('full', '100%', 1.0);

  const SubtitleBoxOpacity(this.storageKey, this.label, this.opacity);
  final String storageKey;
  final String label;
  final double opacity;
}

enum SubtitleFont {
  standard('standard', 'Standard', 'Inter'),
  monoSans('monoSans', 'Monospaced sans', 'JetBrains Mono'),
  serif('serif', 'Proportional serif', 'Source Serif 4'),
  monoSerif('monoSerif', 'Monospaced serif', 'Courier Prime'),
  casual('casual', 'Casual', 'Comic Neue'),
  cursive('cursive', 'Cursive', 'Dancing Script'),
  smallCaps('smallCaps', 'Small capitals', 'Alegreya Sans SC');

  const SubtitleFont(this.storageKey, this.label, this.fontFamily);
  final String storageKey;
  final String label;
  final String fontFamily;
}

enum SubtitleEdge {
  none('none', 'None'),
  outline('outline', 'Outline'),
  dropShadow('dropShadow', 'Drop shadow'),
  raised('raised', 'Raised'),
  depressed('depressed', 'Depressed');

  const SubtitleEdge(this.storageKey, this.label);
  final String storageKey;
  final String label;
}

enum SubtitlePreset {
  standard('standard', 'Standard'),
  dropShadow('dropShadow', 'Drop shadow'),
  classicBox('classicBox', 'Classic box'),
  highContrast('highContrast', 'High contrast'),
  light('light', 'Light');

  const SubtitlePreset(this.storageKey, this.label);
  final String storageKey;
  final String label;
}

/// Global persisted preferences; device-derived values never enter this model.
@immutable
final class SubtitleStyle {
  const SubtitleStyle({
    this.size = SubtitleSize.p100,
    this.position = SubtitlePosition.bottom,
    this.textColor = SubtitleColor.white,
    this.textOpacity = SubtitleTextOpacity.full,
    this.font = SubtitleFont.standard,
    this.bold = false,
    this.edge = SubtitleEdge.outline,
    this.edgeColor = SubtitleColor.black,
    this.backgroundColor = SubtitleColor.black,
    this.backgroundOpacity = SubtitleBoxOpacity.off,
    this.windowColor = SubtitleColor.black,
    this.windowOpacity = SubtitleBoxOpacity.off,
    this.styleStyledSubtitles = false,
    this.useDeviceStyle = false,
  });

  final SubtitleSize size;
  final SubtitlePosition position;
  final SubtitleColor textColor;
  final SubtitleTextOpacity textOpacity;
  final SubtitleFont font;
  final bool bold;
  final SubtitleEdge edge;
  final SubtitleColor edgeColor;
  final SubtitleColor backgroundColor;
  final SubtitleBoxOpacity backgroundOpacity;
  final SubtitleColor windowColor;
  final SubtitleBoxOpacity windowOpacity;
  final bool styleStyledSubtitles;
  final bool useDeviceStyle;

  SubtitleStyle copyWith({
    SubtitleSize? size,
    SubtitlePosition? position,
    SubtitleColor? textColor,
    SubtitleTextOpacity? textOpacity,
    SubtitleFont? font,
    bool? bold,
    SubtitleEdge? edge,
    SubtitleColor? edgeColor,
    SubtitleColor? backgroundColor,
    SubtitleBoxOpacity? backgroundOpacity,
    SubtitleColor? windowColor,
    SubtitleBoxOpacity? windowOpacity,
    bool? styleStyledSubtitles,
    bool? useDeviceStyle,
  }) => SubtitleStyle(
    size: size ?? this.size,
    position: position ?? this.position,
    textColor: textColor ?? this.textColor,
    textOpacity: textOpacity ?? this.textOpacity,
    font: font ?? this.font,
    bold: bold ?? this.bold,
    edge: edge ?? this.edge,
    edgeColor: edgeColor ?? this.edgeColor,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    windowColor: windowColor ?? this.windowColor,
    windowOpacity: windowOpacity ?? this.windowOpacity,
    styleStyledSubtitles: styleStyledSubtitles ?? this.styleStyledSubtitles,
    useDeviceStyle: useDeviceStyle ?? this.useDeviceStyle,
  );

  Map<String, Object?> toJson() => {
    'size': size.storageKey,
    'position': position.storageKey,
    'textColor': textColor.storageKey,
    'textOpacity': textOpacity.storageKey,
    'font': font.storageKey,
    'bold': bold,
    'edge': edge.storageKey,
    'edgeColor': edgeColor.storageKey,
    'backgroundColor': backgroundColor.storageKey,
    'backgroundOpacity': backgroundOpacity.storageKey,
    'windowColor': windowColor.storageKey,
    'windowOpacity': windowOpacity.storageKey,
    'styleStyledSubtitles': styleStyledSubtitles,
    'useDeviceStyle': useDeviceStyle,
  };

  factory SubtitleStyle.fromJson(Object? value) {
    const fields = {
      'size',
      'position',
      'textColor',
      'textOpacity',
      'font',
      'bold',
      'edge',
      'edgeColor',
      'backgroundColor',
      'backgroundOpacity',
      'windowColor',
      'windowOpacity',
      'styleStyledSubtitles',
      'useDeviceStyle',
    };
    if (value is! Map ||
        value.length != fields.length ||
        !value.keys.toSet().containsAll(fields)) {
      throw const FormatException('Invalid subtitle style fields');
    }
    T choice<T>(String key, List<T> values, String Function(T) storage) {
      return values.where((v) => storage(v) == value[key]).firstOrNull ??
          (throw FormatException('Invalid subtitle style $key'));
    }

    bool boolean(String key) {
      final v = value[key];
      if (v is! bool) throw FormatException('Invalid subtitle style $key');
      return v;
    }

    return SubtitleStyle(
      size: choice('size', SubtitleSize.values, (v) => v.storageKey),
      position: choice(
        'position',
        SubtitlePosition.values,
        (v) => v.storageKey,
      ),
      textColor: choice('textColor', SubtitleColor.values, (v) => v.storageKey),
      textOpacity: choice(
        'textOpacity',
        SubtitleTextOpacity.values,
        (v) => v.storageKey,
      ),
      font: choice('font', SubtitleFont.values, (v) => v.storageKey),
      bold: boolean('bold'),
      edge: choice('edge', SubtitleEdge.values, (v) => v.storageKey),
      edgeColor: choice('edgeColor', SubtitleColor.values, (v) => v.storageKey),
      backgroundColor: choice(
        'backgroundColor',
        SubtitleColor.values,
        (v) => v.storageKey,
      ),
      backgroundOpacity: choice(
        'backgroundOpacity',
        SubtitleBoxOpacity.values,
        (v) => v.storageKey,
      ),
      windowColor: choice(
        'windowColor',
        SubtitleColor.values,
        (v) => v.storageKey,
      ),
      windowOpacity: choice(
        'windowOpacity',
        SubtitleBoxOpacity.values,
        (v) => v.storageKey,
      ),
      styleStyledSubtitles: boolean('styleStyledSubtitles'),
      useDeviceStyle: boolean('useDeviceStyle'),
    );
  }

  SubtitleStyle applying(SubtitlePreset preset) {
    final base = copyWith(
      textColor: SubtitleColor.white,
      textOpacity: SubtitleTextOpacity.full,
      edge: SubtitleEdge.none,
      edgeColor: SubtitleColor.black,
      backgroundColor: SubtitleColor.black,
      backgroundOpacity: SubtitleBoxOpacity.off,
      windowColor: SubtitleColor.black,
      windowOpacity: SubtitleBoxOpacity.off,
    );
    return switch (preset) {
      SubtitlePreset.standard => base.copyWith(edge: SubtitleEdge.outline),
      SubtitlePreset.dropShadow => base.copyWith(edge: SubtitleEdge.dropShadow),
      SubtitlePreset.classicBox => base.copyWith(
        backgroundOpacity: SubtitleBoxOpacity.threeQuarters,
      ),
      SubtitlePreset.highContrast => base.copyWith(
        textColor: SubtitleColor.yellow,
        backgroundOpacity: SubtitleBoxOpacity.full,
      ),
      SubtitlePreset.light => base.copyWith(
        textColor: SubtitleColor.black,
        backgroundColor: SubtitleColor.white,
        backgroundOpacity: SubtitleBoxOpacity.full,
      ),
    };
  }

  SubtitlePreset? get preset =>
      SubtitlePreset.values.where((p) => applying(p) == this).firstOrNull;

  SubtitleAppearance resolve() => SubtitleAppearance(
    textColor: _argb(textColor.rgb, textOpacity.opacity),
    edgeColor: _argb(edgeColor.rgb, textOpacity.opacity),
    backgroundColor: _argb(backgroundColor.rgb, backgroundOpacity.opacity),
    windowColor: _argb(windowColor.rgb, windowOpacity.opacity),
    edge: edge,
    font: font,
    bold: bold,
    scale: size.scale,
    raise: position.raise,
  );

  @override
  bool operator ==(Object other) =>
      other is SubtitleStyle &&
      size == other.size &&
      position == other.position &&
      textColor == other.textColor &&
      textOpacity == other.textOpacity &&
      font == other.font &&
      bold == other.bold &&
      edge == other.edge &&
      edgeColor == other.edgeColor &&
      backgroundColor == other.backgroundColor &&
      backgroundOpacity == other.backgroundOpacity &&
      windowColor == other.windowColor &&
      windowOpacity == other.windowOpacity &&
      styleStyledSubtitles == other.styleStyledSubtitles &&
      useDeviceStyle == other.useDeviceStyle;

  @override
  int get hashCode => Object.hash(
    size,
    position,
    textColor,
    textOpacity,
    font,
    bold,
    edge,
    edgeColor,
    backgroundColor,
    backgroundOpacity,
    windowColor,
    windowOpacity,
    styleStyledSubtitles,
    useDeviceStyle,
  );
}

int _argb(int rgb, double opacity) => ((opacity * 255).round() << 24) | rgb;

/// Concrete paint inputs. Colors are unsigned ARGB; fontFamily is a FontLoader key.
@immutable
final class SubtitleAppearance {
  const SubtitleAppearance({
    required this.textColor,
    required this.edgeColor,
    required this.backgroundColor,
    required this.windowColor,
    required this.edge,
    required this.font,
    required this.bold,
    required this.scale,
    required this.raise,
  });

  final int textColor;
  final int edgeColor;
  final int backgroundColor;
  final int windowColor;
  final SubtitleEdge edge;
  final SubtitleFont font;
  final bool bold;
  final double scale;
  final double raise;

  String get fontFamily => font.fontFamily;
}
