import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../playback/subtitle_appearance_source.dart';
import '../playback/subtitle_cues.dart';
import '../playback/subtitle_layer.dart';
import '../settings/subtitle_style.dart';

import '../platform/device_profile.dart';
import '../settings/lineup_settings.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'lineup_controller.dart';

part 'settings_subtitles.dart';

enum SettingsCategory {
  appearance,
  guide,
  playback,
  subtitles,
  accessibility,
  account,
  support,
}

class SettingsView extends StatefulWidget {
  const SettingsView({
    required this.controller,
    this.subtitleAppearance,
    this.category = SettingsCategory.appearance,
    this.onCategoryChanged,
    this.authorizationTransitionPending = false,
    this.onSwitchProfile,
    this.onSwitchServer,
    this.onSignOut,
    this.onOpenDiagnostics,
    this.onOpenLicenses,
    this.openLicensesFocus,
    this.supportOnly = false,
    this.focusNode,
    this.menuFocusNode,
    this.onOpenMenu,
    this.onBack,
    this.backLabel = '‹ Back to Guide',
    super.key,
  });
  final LineupController controller;
  final SubtitleAppearanceSource? subtitleAppearance;
  final SettingsCategory category;
  final ValueChanged<SettingsCategory>? onCategoryChanged;
  final bool authorizationTransitionPending;
  final VoidCallback? onSwitchProfile;
  final VoidCallback? onSwitchServer;
  final Future<void> Function()? onSignOut;
  final VoidCallback? onOpenDiagnostics;
  final VoidCallback? onOpenLicenses;
  final FocusNode? openLicensesFocus;
  final bool supportOnly;
  final FocusNode? focusNode;
  final FocusNode? menuFocusNode;
  final LineupMenuCallback? onOpenMenu;
  final VoidCallback? onBack;
  final String backLabel;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late SettingsCategory _localCategory;
  late LineupSettings _displaySettings;
  late LineupSettings _lastControllerSettings;
  bool _categoryFocusPlaced = false;
  final List<_PendingSave> _pendingSaves = [];
  final _tvRailFocus = {
    for (final category in SettingsCategory.values)
      category: FocusNode(debugLabel: 'Settings ${category.name}'),
  };
  final _detailFocus = FocusNode(debugLabel: 'Settings detail');
  final _themeSwatchesKey = GlobalKey<_ThemeSwatchesState>();
  final _desktopSubtitleRailFocus = FocusNode(debugLabel: 'Subtitles category');
  Timer? _railDwell;
  final _subtitleFocus = <_SettingKey, FocusNode>{};
  bool _subtitleCustomising = false;

  _SettingKey get _firstSubtitleCustomiseSetting =>
      defaultTargetPlatform == TargetPlatform.android &&
          _displaySettings.subtitleStyle.useDeviceStyle
      ? _SettingKey.subtitleBold
      : _SettingKey.subtitleTextColor;

  void _openSubtitleCustomise() {
    setState(() => _subtitleCustomising = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _subtitleFocus[_firstSubtitleCustomiseSetting]?.requestFocus();
      }
    });
  }

  void _closeSubtitleCustomise() {
    setState(() => _subtitleCustomising = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _subtitleFocus[_SettingKey.subtitleCustomise]?.requestFocus();
      }
    });
  }

  bool _saving(_SettingKey key) => _pendingSaves.any((p) => p.key == key);
  final Map<_SettingKey, String> _errors = {};

  SettingsCategory get _category =>
      widget.onCategoryChanged == null ? _localCategory : widget.category;

  @override
  void initState() {
    super.initState();
    _localCategory = widget.category;
    _lastControllerSettings = widget.controller.settings;
    _displaySettings = _lastControllerSettings;
    widget.controller.addListener(_controllerChanged);
    widget.subtitleAppearance?.addListener(_appearanceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _categoryFocusPlaced = true;
    });
  }

  @override
  void didUpdateWidget(covariant SettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subtitleAppearance != widget.subtitleAppearance) {
      oldWidget.subtitleAppearance?.removeListener(_appearanceChanged);
      widget.subtitleAppearance?.addListener(_appearanceChanged);
    }
    if (oldWidget.category != widget.category &&
        widget.category != SettingsCategory.subtitles) {
      _subtitleCustomising = false;
    }
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_controllerChanged);
    widget.controller.addListener(_controllerChanged);
    _lastControllerSettings = widget.controller.settings;
    _displaySettings = _lastControllerSettings;
  }

  void _appearanceChanged() {
    if (mounted) setState(() {});
  }

  void _controllerChanged() {
    final settings = widget.controller.settings;
    if (identical(settings, _lastControllerSettings)) return;
    _lastControllerSettings = settings;
    var refreshed = settings;
    for (final pending in _pendingSaves) {
      refreshed = pending.change(refreshed);
    }
    if (!mounted) return;
    setState(() => _displaySettings = refreshed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    widget.subtitleAppearance?.removeListener(_appearanceChanged);
    _railDwell?.cancel();
    for (final node in _tvRailFocus.values) {
      node.dispose();
    }
    _detailFocus.dispose();
    _desktopSubtitleRailFocus.dispose();
    for (final node in _subtitleFocus.values) {
      node.dispose();
    }
    for (final pending in _pendingSaves) {
      pending.timer?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsTheme = LineupTheme.forName(
      _displaySettings.theme,
      largeFocusIndicators: _displaySettings.largeFocusIndicators,
      formFactor: DeviceProfile.of(context).formFactor,
    );
    final roles = settingsTheme.extension<LineupThemeRoles>()!;
    return LineupFocusTheme(
      data: settingsTheme,
      child: Material(
        type: MaterialType.transparency,
        child: FocusTraversalGroup(
          child: ColoredBox(
            key: const Key('settings-immersive-scrim'),
            color: roles.deepBackground.withValues(alpha: 0.94),
            child: SafeArea(
              left: DeviceProfile.of(context).isTv,
              top: DeviceProfile.of(context).isTv,
              right: DeviceProfile.of(context).isTv,
              bottom: DeviceProfile.of(context).isTv,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      LineupLayout.isCompactWidth(constraints.maxWidth) ||
                      MediaQuery.textScalerOf(context).scale(1) >= 2;
                  final theme = Theme.of(context);
                  return DefaultTextStyle(
                    style: theme.textTheme.bodyMedium!,
                    child: Builder(
                      builder: (context) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LineupTopBar(
                            menuKey: const Key('settings-app-menu'),
                            onOpenMenu: widget.onOpenMenu,
                            menuFocusNode: widget.menuFocusNode,
                          ),
                          Expanded(
                            child: LineupContentWidth(
                              vertical: 24,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _settingsHeader(context),
                                  const SizedBox(height: 24),
                                  Expanded(
                                    child: compact
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              _categoryRail(context, true),
                                              Expanded(
                                                child: _detailPane(
                                                  context,
                                                  true,
                                                ),
                                              ),
                                            ],
                                          )
                                        : Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              _categoryRail(context, false),
                                              Expanded(
                                                child: _detailPane(
                                                  context,
                                                  false,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsHeader(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.onBack != null)
        LineupInlineLink(
          onPressed: widget.onBack,
          child: Text(
            widget.backLabel,
            style: LineupTypography.tvLabelStyle(context),
          ),
        ),
      Text(
        'Settings',
        style: TextStyle(
          color: LineupTheme.of(context).secondaryText,
          fontSize: 16,
        ),
      ),
    ],
  );

  Widget _categoryRail(BuildContext context, bool compact) {
    final roles = LineupTheme.of(context);
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 20 : 0,
        compact ? 14 : 8,
        compact ? 20 : 32,
        compact ? 12 : 0,
      ),
      child: compact
          ? _categorySelector(context, true)
          : _categorySelector(context, false),
    );
    return Focus(
      focusNode: DeviceProfile.of(context).isTv ? widget.focusNode : null,
      canRequestFocus:
          DeviceProfile.of(context).isTv && widget.focusNode != null,
      skipTraversal: true,
      onFocusChange: (_) {
        // Shell returns focus here after a route or overlay closes. The rail
        // rows keep their own nodes so a dwell never moves the focused row.
        if (DeviceProfile.of(context).isTv &&
            widget.focusNode?.hasPrimaryFocus == true) {
          _tvRailFocus[_category]!.requestFocus();
        }
      },
      child: DecoratedBox(
        key: const Key('settings-category-rail'),
        decoration: BoxDecoration(
          border: Border(
            right: compact
                ? BorderSide.none
                : BorderSide(color: roles.subtleBorder),
            bottom: compact
                ? BorderSide(color: roles.subtleBorder)
                : BorderSide.none,
          ),
        ),
        child: compact ? content : SizedBox(width: 312, child: content),
      ),
    );
  }

  static const _rowInset = 16.0;

  Widget _detailPane(BuildContext context, bool compact) => Padding(
    key: const Key('settings-detail-pane'),
    padding: EdgeInsets.fromLTRB(
      (compact ? 20 : 48) - (DeviceProfile.of(context).isTv ? _rowInset : 0),
      (compact ? 20 : 8),
      (compact ? 20 : 24),
      (compact ? 20 : 24),
    ),
    child: Focus(
      focusNode: _detailFocus,
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (DeviceProfile.of(context).isTv &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _tvRailFocus[_category]!.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          key: const Key('settings-content-column'),
          constraints: BoxConstraints(
            maxWidth: _category == SettingsCategory.subtitles
                ? double.infinity
                : 1040,
          ),
          child: _categoryDetail(context),
        ),
      ),
    ),
  );

  void _selectCategory(SettingsCategory category) {
    _railDwell?.cancel();
    if (_category == category) return;
    setState(() {
      _localCategory = category;
      if (category != SettingsCategory.subtitles) {
        _subtitleCustomising = false;
      }
    });
    widget.onCategoryChanged?.call(category);
  }

  void _followRailFocus(SettingsCategory category, bool focused) {
    if (!focused) return;
    _railDwell?.cancel();
    if (category == _category) return;
    _railDwell = Timer(const Duration(milliseconds: 150), () {
      if (mounted && _tvRailFocus[category]!.hasPrimaryFocus) {
        _selectCategory(category);
      }
    });
  }

  void _enterDetail(SettingsCategory category) {
    if (category == _category) {
      _focusFirstSetting();
      return;
    }
    _selectCategory(category);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          category == _category &&
          _tvRailFocus[category]!.hasPrimaryFocus) {
        _focusFirstSetting();
      }
    });
  }

  void _focusFirstSetting() {
    if (_category == SettingsCategory.appearance) {
      _themeSwatchesKey.currentState?.focusFirst();
    } else if (_category == SettingsCategory.subtitles) {
      _subtitleFocus[_subtitleCustomising
              ? _firstSubtitleCustomiseSetting
              : defaultTargetPlatform == TargetPlatform.android
              ? _SettingKey.subtitleDevice
              : _SettingKey.subtitlePreset]
          ?.requestFocus();
    } else {
      _detailFocus.traversalDescendants.firstOrNull?.requestFocus();
    }
  }

  Widget _categorySelector(BuildContext context, bool compact) {
    final tv = DeviceProfile.of(context).isTv;
    final controls = [
      for (final category
          in widget.supportOnly
              ? [SettingsCategory.support]
              : SettingsCategory.values)
        Padding(
          padding: EdgeInsets.only(right: 10, bottom: 10),
          child: Focus(
            canRequestFocus: false,
            onFocusChange: tv
                ? (focused) => _followRailFocus(category, focused)
                : null,
            onKeyEvent: (_, event) {
              if (tv &&
                  !compact &&
                  event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _enterDetail(category);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: LineupNavigationRow(
              selected: category == _category,
              focusNode: tv
                  ? _tvRailFocus[category]
                  : (category == _category ? widget.focusNode : null) ??
                        (category == SettingsCategory.subtitles
                            ? _desktopSubtitleRailFocus
                            : null),
              autofocus: category == _category && !_categoryFocusPlaced,
              onPressed: () {
                _selectCategory(category);
                if (!tv) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && category == _category) {
                      widget.focusNode?.requestFocus();
                    }
                  });
                }
              },
              child: Text(
                _categoryLabel(category),
                style: LineupTypography.tvLabelStyle(context),
              ),
            ),
          ),
        ),
    ];
    return compact
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: controls),
          )
        : ListView(children: controls);
  }

  Widget _categoryDetail(BuildContext context) {
    if (_category == SettingsCategory.subtitles) {
      return _subtitleDetail(context);
    }
    final value = _displaySettings;
    final isTv = DeviceProfile.of(context).isTv;

    return ListView(
      key: ValueKey(_category),
      children: [
        _SettingsSection(
          title: _categoryLabel(_category),
          description: _categoryDescription(_category),
          children: switch (_category) {
            SettingsCategory.appearance => [
              ..._settingControl<LineupThemeName>(
                _SettingKey.theme,
                (current, item) => current.copyWith(theme: item),
                (onChanged) => _ThemeSwatches(
                  key: _themeSwatchesKey,
                  value: value.theme,
                  onChanged: onChanged,
                ),
              ),
              ..._settingControl<GuideInfoBackgroundMode>(
                _SettingKey.guideInfoBackgroundMode,
                (current, item) =>
                    current.copyWith(guideInfoBackgroundMode: item),
                (onChanged) => _Dropdown<GuideInfoBackgroundMode>(
                  'Guide information background',
                  'Choose artwork colors, the theme, or an artwork backdrop.',
                  value.guideInfoBackgroundMode,
                  GuideInfoBackgroundMode.values,
                  (item) => switch (item) {
                    GuideInfoBackgroundMode.bleed => 'Artwork colors',
                    GuideInfoBackgroundMode.themeDefault => 'Theme background',
                    GuideInfoBackgroundMode.artwork => 'Artwork backdrop',
                  },
                  onChanged,
                ),
              ),
              ..._settingControl<bool>(
                _SettingKey.preferClearLogos,
                (current, item) => current.copyWith(preferClearLogos: item),
                (onChanged) => _SettingsSwitchTile(
                  title: const Text('Use title artwork'),
                  subtitle: const Text(
                    'Use available Plex title artwork with a readable text fallback.',
                  ),
                  value: value.preferClearLogos,
                  onChanged: onChanged,
                ),
              ),
              ..._settingControl<OverlayTransparency>(
                _SettingKey.overlayTransparency,
                (current, item) => current.copyWith(overlayTransparency: item),
                (onChanged) => _Dropdown<OverlayTransparency>(
                  'Player overlays',
                  'How much of the picture shows through Player controls and panels. More transparent can be harder to read on bright scenes.',
                  value.overlayTransparency,
                  OverlayTransparency.values,
                  (item) => item.label,
                  onChanged,
                  choiceDescription: (item) => switch (item) {
                    OverlayTransparency.moreTransparent => 'Lightest',
                    OverlayTransparency.standard => 'Default',
                    OverlayTransparency.reduced =>
                      'Most solid, easiest to read',
                  },
                ),
              ),
            ],
            SettingsCategory.guide => [
              ..._settingControl<int>(
                _SettingKey.guideHours,
                (current, item) => current.copyWith(guideHours: item),
                (onChanged) => _Dropdown<int>(
                  'Visible hours',
                  'Choose how much of the schedule appears at once.',
                  value.guideHours,
                  LineupSettings.guideHoursOptions,
                  (item) => switch (item) {
                    2 => 'Detailed (2 hours)',
                    3 => 'Wide (3 hours)',
                    _ => 'Extended ($item hours)',
                  },
                  choiceDescription: (item) => switch (item) {
                    2 => 'Less schedule at once',
                    3 => 'Balanced schedule at once',
                    _ => 'More schedule at once',
                  },
                  onChanged,
                  first: true,
                ),
              ),
              ..._settingControl<bool>(
                _SettingKey.guideShowChannelSources,
                (current, item) =>
                    current.copyWith(guideShowChannelSources: item),
                (onChanged) => _SettingsSwitchTile(
                  title: const Text('Show channel sources'),
                  subtitle: const Text(
                    "Show where each channel's programs come from under its name in the Guide.",
                  ),
                  value: value.guideShowChannelSources,
                  onChanged: onChanged,
                ),
              ),
              ..._settingControl<bool>(
                _SettingKey.nowWatchingBanner,
                (current, item) => current.copyWith(nowWatchingBanner: item),
                (onChanged) => _SettingsSwitchTile(
                  title: const Text('Show now playing in Guide'),
                  subtitle: const Text(
                    'Identify the playing channel and program while browsing other listings.',
                  ),
                  value: value.nowWatchingBanner,
                  onChanged: onChanged,
                ),
              ),
            ],
            SettingsCategory.playback => [
              ..._settingControl<int>(
                _SettingKey.osdAutoHideSeconds,
                (current, item) => current.copyWith(osdAutoHideSeconds: item),
                (onChanged) => _Dropdown<int>(
                  'Player controls auto-hide',
                  'Set how long controls remain visible while playing.',
                  value.osdAutoHideSeconds,
                  LineupSettings.osdAutoHideSecondsOptions,
                  (item) => '$item seconds',
                  onChanged,
                  first: true,
                ),
              ),
              ..._settingControl<bool>(
                _SettingKey.dvrControlsEnabled,
                (current, item) => current.copyWith(dvrControlsEnabled: item),
                (onChanged) => _SettingsSwitchTile(
                  title: const Text('Pause and seek controls'),
                  subtitle: const Text(
                    'Show transport controls in the Player and enable pause, seek, stop, and media-key shortcuts.',
                  ),
                  value: value.dvrControlsEnabled,
                  onChanged: onChanged,
                ),
              ),
              if (defaultTargetPlatform != TargetPlatform.macOS && !isTv)
                ..._settingControl<bool>(
                  _SettingKey.matchDisplayHdr,
                  (current, item) => current.copyWith(matchDisplayHdr: item),
                  (onChanged) => _SettingsSwitchTile(
                    title: const Text('Match display HDR in fullscreen'),
                    subtitle: const Text(
                      'Switch Windows HDR on for HDR programs and off for SDR programs while fullscreen, then restore your display setting.',
                    ),
                    value: value.matchDisplayHdr,
                    onChanged: onChanged,
                  ),
                ),
            ],
            SettingsCategory.subtitles => const [],
            SettingsCategory.accessibility => [
              ..._settingControl<LineupTextSize>(
                _SettingKey.textSize,
                (current, item) => current.copyWith(textSize: item),
                (onChanged) => _Dropdown<LineupTextSize>(
                  'Text size',
                  'Larger text can show fewer Guide rows.',
                  value.textSize,
                  LineupTextSize.values,
                  (item) => item.label,
                  onChanged,
                  first: true,
                ),
              ),
              ..._settingControl<bool>(
                _SettingKey.reduceMotion,
                (current, item) => current.copyWith(reduceMotion: item),
                (onChanged) => _SettingsSwitchTile(
                  title: const Text('Reduce motion'),
                  subtitle: const Text(
                    'Disable nonessential application transitions.',
                  ),
                  value: value.reduceMotion,
                  onChanged: onChanged,
                ),
              ),
              ..._settingControl<bool>(
                _SettingKey.largeFocusIndicators,
                (current, item) => current.copyWith(largeFocusIndicators: item),
                (onChanged) => _SettingsSwitchTile(
                  title: const Text('Large focus indicators'),
                  subtitle: const Text(
                    'Use thicker outlines when navigating with a keyboard or remote.',
                  ),
                  value: value.largeFocusIndicators,
                  onChanged: onChanged,
                ),
              ),
            ],
            SettingsCategory.account => [
              _SettingsRow(
                revealOnFocus: true,
                label: const Text('Plex Home profile'),
                helper: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    LineupProfileAvatar(
                      name:
                          widget.controller.profile?.name ??
                          widget.controller.account?.name ??
                          'Plex account',
                      identity:
                          widget.controller.profile?.id ??
                          widget.controller.account?.id ??
                          'account',
                      photo:
                          widget.controller.profile?.thumb?.isAbsolute == true
                          ? NetworkImage(
                              widget.controller.profile!.thumb.toString(),
                            )
                          : null,
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.controller.profile?.name ??
                            widget.controller.account?.name ??
                            'Plex account',
                      ),
                    ),
                  ],
                ),
                control: OutlinedButton(
                  onPressed:
                      widget.authorizationTransitionPending ||
                          widget.controller.profiles.isEmpty
                      ? null
                      : widget.onSwitchProfile ??
                            widget.controller.showProfiles,
                  child: Text(
                    'Switch profile',
                    style: LineupTypography.tvLabelStyle(context),
                  ),
                ),
                first: true,
              ),
              ..._settingControl<bool>(
                _SettingKey.profilePickerOnStartup,
                (current, item) =>
                    current.copyWith(profilePickerOnStartup: item),
                (onChanged) => _SettingsSwitchTile(
                  title: const Text('Show profile picker on startup'),
                  subtitle: const Text(
                    'Ask who is watching when this Plex Home has multiple profiles.',
                  ),
                  value: value.profilePickerOnStartup,
                  onChanged: onChanged,
                ),
              ),
              _SettingsRow(
                revealOnFocus: true,
                label: const Text('Plex Media Server'),
                helper: widget.controller.server == null
                    ? const Text('No server selected')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.controller.server!.name),
                          LineupConnectionStatus(
                            connection: widget.controller.connection,
                          ),
                        ],
                      ),
                control: OutlinedButton(
                  onPressed: widget.authorizationTransitionPending
                      ? null
                      : widget.onSwitchServer ?? widget.controller.showServers,
                  child: Text(
                    'Switch server',
                    style: LineupTypography.tvLabelStyle(context),
                  ),
                ),
              ),
              SizedBox(height: 24),
              _SettingsRow(
                revealOnFocus: true,
                label: const Text('Signed-in Plex account'),
                helper: Text(
                  '${widget.controller.account?.name ?? 'Plex account'}\n'
                  'Sign-out keeps saved lineup and media metadata on this device.',
                ),
                control: OutlinedButton(
                  onPressed:
                      widget.authorizationTransitionPending ||
                          widget.onSignOut == null
                      ? null
                      : () => unawaited(widget.onSignOut!()),
                  child: Text(
                    'Sign out of Plex',
                    style: LineupTypography.tvLabelStyle(context),
                  ),
                ),
              ),
            ],
            SettingsCategory.support => [
              ..._settingControl<bool>(
                _SettingKey.diagnosticsEnabled,
                (current, item) => current.copyWith(diagnosticsEnabled: item),
                (onChanged) => _SettingsSwitchTile(
                  title: const Text('Record redacted diagnostics'),
                  subtitle: const Text(
                    'Tokens, URLs, paths, headers and credentials are excluded. Turning this off clears recorded events.',
                  ),
                  value: value.diagnosticsEnabled,
                  onChanged: onChanged,
                  first: true,
                ),
              ),
              _SettingsRow(
                revealOnFocus: true,
                label: const Text('Diagnostics'),
                helper: const Text(
                  'Review redacted support events from this session.',
                ),
                control: OutlinedButton(
                  onPressed: widget.onOpenDiagnostics,
                  child: Text(
                    'Open Diagnostics',
                    style: LineupTypography.tvLabelStyle(context),
                  ),
                ),
              ),
              if (defaultTargetPlatform == TargetPlatform.macOS || isTv)
                _SettingsRow(
                  revealOnFocus: true,
                  label: const Text('Licenses'),
                  helper: const Text(
                    'Read third-party licenses, notices, and source information.',
                  ),
                  control: OutlinedButton(
                    focusNode: widget.openLicensesFocus,
                    onPressed: widget.onOpenLicenses,
                    child: Text(
                      'Open Licenses',
                      style: LineupTypography.tvLabelStyle(context),
                    ),
                  ),
                ),
            ],
          },
        ),
      ],
    );
  }

  void _changeSubtitle(
    _SettingKey key,
    SubtitleStyle Function(SubtitleStyle) change,
  ) {
    if (change(_displaySettings.subtitleStyle) ==
        _displaySettings.subtitleStyle) {
      return;
    }
    unawaited(
      _update(
        key,
        (current) =>
            current.copyWith(subtitleStyle: change(current.subtitleStyle)),
        keepEnabled: true,
      ),
    );
  }

  List<Widget> _settingControl<T>(
    _SettingKey key,
    LineupSettings Function(LineupSettings, T) change,
    Widget Function(ValueChanged<T>?) build,
  ) => [
    build(
      _saving(key)
          ? null
          : (value) =>
                unawaited(_update(key, (current) => change(current, value))),
    ),
    _settingFeedback(key),
  ];

  Widget _settingFeedback(_SettingKey key) {
    final error = _errors[key];
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          error,
          key: ValueKey('setting-error-${key.name}'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    if (_pendingSaves.any((p) => p.key == key && p.showSaving)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text('Saving…'),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _update(
    _SettingKey key,
    LineupSettings Function(LineupSettings) change, {
    bool keepEnabled = false,
  }) async {
    if (!keepEnabled && _saving(key)) return;
    final pending = _PendingSave(key, change);
    setState(() {
      _pendingSaves.add(pending);
      _errors.remove(key);
      _displaySettings = change(_displaySettings);
    });
    pending.timer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _pendingSaves.contains(pending)) {
        setState(() => pending.showSaving = true);
      }
    });
    String? error;
    try {
      await widget.controller.updateSettings(change);
    } catch (_) {
      error = 'Could not save. The previous value was restored.';
    } finally {
      pending.timer?.cancel();
      if (mounted) {
        setState(() {
          _pendingSaves.remove(pending);
          var refreshed = widget.controller.settings;
          for (final pending in _pendingSaves) {
            refreshed = pending.change(refreshed);
          }
          _displaySettings = refreshed;
          if (error != null) {
            _errors[key] = error;
          } else {
            _errors.remove(key);
          }
        });
      }
    }
  }

  static String _categoryLabel(SettingsCategory category) => switch (category) {
    SettingsCategory.appearance => 'Appearance',
    SettingsCategory.guide => 'Guide',
    SettingsCategory.playback => 'Playback',
    SettingsCategory.subtitles => 'Subtitles',
    SettingsCategory.accessibility => 'Accessibility',
    SettingsCategory.account => 'Account',
    SettingsCategory.support => 'Support',
  };

  static String _categoryDescription(SettingsCategory category) =>
      switch (category) {
        SettingsCategory.appearance => 'Choose the atmosphere of your lineup.',
        SettingsCategory.guide => 'Browse the schedule your way.',
        SettingsCategory.playback => 'Control how playback controls behave.',
        SettingsCategory.subtitles => 'Applies to text subtitles. Image subtitles follow Size and Position only.',
        SettingsCategory.accessibility =>
          'Make navigation easier to see and follow.',
        SettingsCategory.account =>
          'Manage who is watching and where your media comes from.',
        SettingsCategory.support =>
          'Collect useful information when something goes wrong.',
      };
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.description,
    required this.children,
    this.trailingGap = 32,
  });

  final double trailingGap;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: DeviceProfile.of(context).isTv
                ? _SettingsViewState._rowInset
                : 0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: roles.primaryText,
                    fontSize: 44,
                    fontWeight: FontWeight.w600,
                    height: 1.08,
                  ),
                ),
              ),
              SizedBox(height: 6),
              Text(
                description,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: roles.secondaryText,
                  fontSize: 18,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: trailingGap),
        ...children,
      ],
    );
  }
}

class _ThemeSwatches extends StatefulWidget {
  const _ThemeSwatches({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final LineupThemeName value;
  final ValueChanged<LineupThemeName>? onChanged;

  @override
  State<_ThemeSwatches> createState() => _ThemeSwatchesState();
}

class _ThemeSwatchesState extends State<_ThemeSwatches> {
  final _focus = {
    for (final theme in LineupThemeName.values)
      theme: FocusNode(debugLabel: 'Theme ${theme.label}'),
  };

  void focusFirst() => _focus[LineupThemeName.values.first]!.requestFocus();

  @override
  void dispose() {
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final inset = DeviceProfile.of(context).isTv
        ? _SettingsViewState._rowInset
        : 0.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 16, inset, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Theme',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            'Color and surface treatment throughout Lineup.',
            style: TextStyle(
              color: roles.secondaryText,
              fontSize: 18,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 16.0;
              final columns = constraints.maxWidth >= 232 * 4 + gap * 3 ? 4 : 2;
              final width = math.min(
                232.0,
                (constraints.maxWidth - gap * (columns - 1)) / columns,
              );
              return Wrap(
                key: const ValueKey('settings-field-Theme'),
                spacing: gap,
                runSpacing: 20,
                children: [
                  for (final theme in LineupThemeName.values)
                    SizedBox(
                      width: width,
                      child: Builder(
                        builder: (context) {
                          final swatch = LineupTheme.forName(theme)
                              .extension<LineupThemeRoles>()!;
                          final selected = theme == widget.value;
                          return Focus(
                            canRequestFocus: false,
                            onKeyEvent: (_, event) {
                              if (!DeviceProfile.of(context).isTv ||
                                  event is! KeyDownEvent) {
                                return KeyEventResult.ignored;
                              }
                              final delta =
                                  event.logicalKey ==
                                      LogicalKeyboardKey.arrowRight
                                  ? 1
                                  : event.logicalKey ==
                                        LogicalKeyboardKey.arrowLeft
                                  ? -1
                                  : 0;
                              final index = theme.index + delta;
                              if (delta == 0 ||
                                  index < 0 ||
                                  index >= LineupThemeName.values.length) {
                                return KeyEventResult.ignored;
                              }
                              _focus[LineupThemeName.values[index]]!
                                  .requestFocus();
                              return KeyEventResult.handled;
                            },
                            child: Semantics(
                              button: true,
                              label: theme.label,
                              selected: selected,
                              enabled: widget.onChanged != null,
                              onTap: widget.onChanged == null
                                  ? null
                                  : () => widget.onChanged!(theme),
                              child: ExcludeSemantics(
                                child: OutlinedButton(
                                  focusNode: _focus[theme],
                                  key: ValueKey('settings-theme-${theme.name}'),
                                  onPressed: () {
                                    if (widget.onChanged != null) {
                                      _focus[theme]!.requestFocus();
                                      widget.onChanged!(theme);
                                    }
                                  },
                                  style:
                                      OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.all(4),
                                        foregroundColor:
                                            widget.onChanged == null
                                            ? roles.mutedText
                                            : null,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            roles.panelRadius,
                                          ),
                                        ),
                                      ).copyWith(
                                        side: WidgetStateProperty.resolveWith(
                                          (states) =>
                                              states.contains(
                                                WidgetState.focused,
                                              )
                                              ? null
                                              : BorderSide.none,
                                        ),
                                      ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        key: ValueKey(
                                          'settings-theme-preview-${theme.name}',
                                        ),
                                        height: 132,
                                        padding: const EdgeInsets.all(24),
                                        decoration: BoxDecoration(
                                          color: swatch.deepBackground,
                                          borderRadius: BorderRadius.circular(
                                            roles.panelRadius,
                                          ),
                                          border: Border.all(
                                            color: selected
                                                ? roles.progressFill
                                                : roles.subtleBorder,
                                            width: selected ? 3 : 1,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 100,
                                              height: 8,
                                              color: swatch.primaryText,
                                            ),
                                            const SizedBox(height: 12),
                                            Container(
                                              width: 72,
                                              height: 6,
                                              color: swatch.primaryText
                                                  .withValues(alpha: .55),
                                            ),
                                            const Spacer(),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Container(
                                                    height: 24,
                                                    color:
                                                        swatch.elevatedSurface,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  width: 48,
                                                  height: 24,
                                                  color: swatch.progressFill,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        theme.label,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    required this.helper,
    required this.control,
    this.first = false,
    this.revealOnFocus = false,
    this.filledOnFocus = false,
  });

  final Widget label;
  final Widget helper;
  final Widget control;
  final bool first;
  final bool revealOnFocus;
  final bool filledOnFocus;

  @override
  Widget build(BuildContext context) {
    final row = LayoutBuilder(
      builder: (context, constraints) {
        final reflow =
            constraints.maxWidth < 900 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.5;
        final controlWidth = math.min(280.0, constraints.maxWidth);
        final theme = Theme.of(context);
        final roles = LineupTheme.of(context);
        final description = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefaultTextStyle.merge(
              style: theme.textTheme.titleMedium?.copyWith(
                color: roles.primaryText,
                fontSize: 18,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
              child: label,
            ),
            SizedBox(height: 6),
            DefaultTextStyle.merge(
              style: theme.textTheme.bodyLarge?.copyWith(
                color: roles.secondaryText,
                fontSize: 18,
                height: 1.5,
              ),
              child: helper,
            ),
          ],
        );
        final inset = DeviceProfile.of(context).isTv
            ? _SettingsViewState._rowInset
            : 0.0;
        return Container(
          constraints: BoxConstraints(minHeight: 132),
          padding: EdgeInsets.fromLTRB(
            // LineupToggleSurface already reserves 3px for its leading edge.
            inset - (inset > 0 && filledOnFocus ? 3 : 0),
            (first ? 16 : 28),
            inset,
            28,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: roles.subtleBorder)),
          ),
          child: reflow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    description,
                    SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(width: controlWidth, child: control),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: description),
                    SizedBox(width: 32),
                    SizedBox(width: controlWidth, child: control),
                  ],
                ),
        );
      },
    );
    return revealOnFocus && DeviceProfile.of(context).isTv
        ? LineupFocusReveal(child: row)
        : row;
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.first = false,
  });

  final Widget title;
  final Widget subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return LineupToggleSurface(
      child: MergeSemantics(
        child: _SettingsRow(
          filledOnFocus: true,
          label: title,
          helper: subtitle,
          control: Builder(
            builder: (context) {
              return SizedBox(
                height: 48,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 56,
                    child: Switch(
                      value: value,
                      onChanged: onChanged,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              );
            },
          ),
          first: first,
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown(
    this.label,
    this.description,
    this.value,
    this.values,
    this.display,
    this.changed, {
    this.choiceDescription,
    this.first = false,
  });
  final String label;
  final String description;
  final T value;
  final List<T> values;
  final String Function(T) display;
  final ValueChanged<T>? changed;
  final String Function(T)? choiceDescription;
  final bool first;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <DropdownMenuItem<T>>[];
    final selectedItems = <Widget>[];
    for (final item in values) {
      final label = display(item);
      items.add(
        DropdownMenuItem(
          value: item,
          child: choiceDescription == null
              ? Text(label)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    Builder(
                      builder: (context) => Text(
                        choiceDescription!(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: LineupTheme.of(context).secondaryText,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      );
      selectedItems.add(Text(label));
    }
    return LineupToggleSurface(
      child: MergeSemantics(
        child: _SettingsRow(
          filledOnFocus: true,
          label: Text(label),
          helper: Text(description),
          control: SizedBox(
            width: double.infinity,
            child: lineupDropdownField<T>(
              context: context,
              key: ValueKey('settings-field-$label'),
              initialValue: value,
              isExpanded: true,
              itemHeight: null,
              icon: const Icon(Icons.arrow_drop_down, size: 20),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: DeviceProfile.of(context).isTv
                    ? LineupTypography.tvTextFloor
                    : 18,
              ),
              decoration: InputDecoration(),
              items: items,
              selectedItemChildren: choiceDescription == null
                  ? null
                  : selectedItems,
              onChanged: changed == null
                  ? null
                  : (item) {
                      if (item != null) changed!(item);
                    },
            ),
          ),
          first: first,
        ),
      ),
    );
  }
}

enum _SettingKey {
  theme,
  guideInfoBackgroundMode,
  preferClearLogos,
  overlayTransparency,
  guideHours,
  guideShowChannelSources,
  nowWatchingBanner,
  osdAutoHideSeconds,
  dvrControlsEnabled,
  matchDisplayHdr,
  textSize,
  reduceMotion,
  largeFocusIndicators,
  profilePickerOnStartup,
  diagnosticsEnabled,
  subtitleCustomise,
  subtitlePreset,
  subtitleSize,
  subtitlePosition,
  subtitleTextColor,
  subtitleTextOpacity,
  subtitleFont,
  subtitleBold,
  subtitleEdge,
  subtitleEdgeColor,
  subtitleBackgroundOpacity,
  subtitleBackgroundColor,
  subtitleWindowOpacity,
  subtitleWindowColor,
  subtitleStyled,
  subtitleDevice,
  subtitleReset,
}

class _PendingSave {
  _PendingSave(this.key, this.change);

  final _SettingKey key;

  final LineupSettings Function(LineupSettings) change;
  Timer? timer;
  bool showSaving = false;
}
