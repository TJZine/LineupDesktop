import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'lineup_focus.dart';

export 'lineup_controls.dart';
export 'lineup_focus.dart';
export 'lineup_text_field_activation.dart';

typedef LineupMenuCallback = void Function(
  BuildContext invokerContext,
  FocusNode invokerFocus,
);

abstract final class LineupLayout {
  static const compact = 900.0;
  static const expandedNavigation = 1100.0;

  static bool isCompactWidth(double width) => width < compact;

  static EdgeInsets pageInsets(Size size) =>
      EdgeInsets.all((isCompactWidth(size.width) ? 20.0 : 32.0));
}

/// Shared shell geometry is expressed in canvas pixels; LineupCanvas scales it.
class LineupTopBar extends StatelessWidget {
  const LineupTopBar({
    this.onOpenMenu,
    this.menuFocusNode,
    this.menuKey,
    this.trailing,
    this.inset = 48,
    this.divider = true,
    super.key,
  });

  final LineupMenuCallback? onOpenMenu;
  final FocusNode? menuFocusNode;
  final Key? menuKey;
  final Widget? trailing;
  final double inset;
  final bool divider;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final roles = LineupTheme.of(context);
      final menu = onOpenMenu != null && menuFocusNode != null;
      final condensed = constraints.maxWidth < 900;
      final lockup = Builder(
        builder: (context) {
          final ink = LineupTheme.of(context);
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/branding/lineup-logo-mark.png',
                  width: 30,
                  height: 30,
                  excludeFromSemantics: true,
                ),
                if (!condensed) ...[
                  const SizedBox(width: 14),
                  Text(
                    'LINEUP',
                    style: TextStyle(
                      fontFamily: 'Arial',
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 3,
                      color: ink.primaryText,
                    ),
                  ),
                ],
                if (menu) ...[
                  const SizedBox(width: 14),
                  Icon(Icons.menu, size: 22, color: ink.primaryText),
                ],
              ],
            ),
          );
        },
      );
      return Container(
        key: const ValueKey('lineup-top-bar'),
        height: 80,
        padding: EdgeInsets.symmetric(horizontal: inset),
        decoration: BoxDecoration(
          border: divider
              ? Border(bottom: BorderSide(color: roles.subtleBorder))
              : null,
        ),
        child: Row(
          children: [
            if (menu)
              Builder(
                builder: (invokerContext) => Tooltip(
                  message: 'Open Lineup menu',
                  child: TextButton(
                    key: menuKey,
                    focusNode: menuFocusNode,
                    onPressed: () =>
                        onOpenMenu!(invokerContext, menuFocusNode!),
                    style: TextButton.styleFrom(
                      padding: roles.androidTv
                          ? const EdgeInsets.symmetric(horizontal: 20)
                          : EdgeInsets.zero,
                    ),
                    child: lockup,
                  ),
                ),
              )
            else
              Semantics(label: 'Lineup', child: lockup),
            const SizedBox(width: 20),
            Expanded(child: trailing ?? const SizedBox.shrink()),
          ],
        ),
      );
    },
  );
}

/// The cap applies to content, with the bar retaining the full window width.
class LineupContentWidth extends StatelessWidget {
  const LineupContentWidth({
    required this.child,
    this.maxWidth = 1824,
    this.vertical = 0,
    super.key,
  });
  final Widget child;
  final double maxWidth;
  final double vertical;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 48, vertical: vertical),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}

class LineupNotice extends StatelessWidget {
  const LineupNotice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    final radius = LineupTheme.of(context).panelRadius;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: color, size: 24),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class LineupPage extends StatelessWidget {
  const LineupPage({
    required this.title,
    required this.child,
    this.actions,
    this.titleWidget,
    this.traversalPolicy,
    this.topBar,
    this.showTitle = true,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? actions;
  final Widget? titleWidget;
  final FocusTraversalPolicy? traversalPolicy;
  final Widget? topBar;
  final bool showTitle;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: traversalPolicy,
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = LineupLayout.isCompactWidth(constraints.maxWidth);

          return DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!,
            child: Column(
              children: [
                ?topBar,
                Expanded(
                  child: LineupContentWidth(
                    vertical: 24,
                    child: Column(
                      key: const ValueKey('lineup-page-content'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showTitle && compact)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (titleWidget != null && actions != null) ...[
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: actions,
                                ),
                                const SizedBox(height: 16),
                                titleWidget!,
                              ] else ...[
                                titleWidget ?? _PageTitle(title),
                                if (actions != null) ...[
                                  const SizedBox(height: 16),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: actions,
                                  ),
                                ],
                              ],
                            ],
                          )
                        else if (showTitle)
                          Row(
                            children: [
                              Expanded(child: titleWidget ?? _PageTitle(title)),
                              ?actions,
                            ],
                          ),
                        if (showTitle) SizedBox(height: 24),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _PageTitle extends StatelessWidget {
  const _PageTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
  );
}

class LineupSection extends StatelessWidget {
  const LineupSection({required this.title, required this.children, super.key});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 16),
          const Divider(),
          ...children,
        ],
      ),
    ),
  );
}

class LineupEmptyState extends StatelessWidget {
  const LineupEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 0,
          ),
          child: Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    if (action != null) ...[SizedBox(height: 24), action!],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: LineupTheme.buttonStyle(
              LineupTheme.of(context),
              LineupButtonTier.destructive,
              focusVisible: LineupFocusScope.visible(context),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;

bool clearLogoIsUsable(Size intrinsicSize, BoxConstraints constraints) {
  if (!intrinsicSize.width.isFinite ||
      !intrinsicSize.height.isFinite ||
      intrinsicSize.width <= 0 ||
      intrinsicSize.height <= 0 ||
      !constraints.hasBoundedWidth ||
      !constraints.hasBoundedHeight) {
    return false;
  }
  final fitted = applyBoxFit(
    BoxFit.contain,
    intrinsicSize,
    constraints.biggest,
  ).destination;
  return fitted.height >= constraints.maxHeight * 0.35 &&
      fitted.width >= constraints.maxWidth * 0.2;
}

class ClearLogoImage extends StatefulWidget {
  const ClearLogoImage(
    this.bytes, {
    required this.fallback,
    this.imageKey,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.maximumSize,
    this.minimumVisibleSize,
    this.maximumVisibleHeight,
    super.key,
  });

  final Uint8List bytes;
  final Widget fallback;
  final Key? imageKey;
  final String? semanticLabel;
  final bool excludeFromSemantics;
  final Size? maximumSize;
  final Size? minimumVisibleSize;

  /// Optional cap on the actual alpha-bearing artwork after padding is cropped.
  /// Existing consumers retain their original contain scale when omitted.
  final double? maximumVisibleHeight;

  @override
  State<ClearLogoImage> createState() => _ClearLogoImageState();
}

typedef _ClearLogoRequest = ({
  Uint8List bytes,
  int width,
  int height,
  double pixelRatio,
});

class _ClearLogoImageState extends State<ClearLogoImage> {
  _ClearLogoRequest? _request;
  _ClearLogoRaster? _raster;
  int _generation = 0;

  void _reset() {
    _generation++;
    _request = null;
    _raster?.image.dispose();
    _raster = null;
  }

  @override
  void didUpdateWidget(covariant ClearLogoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) _reset();
  }

  @override
  void dispose() {
    _reset();
    super.dispose();
  }

  void _load(_ClearLogoRequest request) {
    _reset();
    _request = request;
    final entry = _clearLogoCacheEntry(request);
    if (entry.completed) {
      // Called from build before `_raster` is read, so no setState is needed.
      _raster = entry.cloneRaster();
      return;
    }
    final generation = _generation;
    unawaited(
      entry.done.then((_) {
        if (!mounted || generation != _generation) return;
        final raster = entry.cloneRaster();
        if (raster != null) setState(() => _raster = raster);
      }),
    );
  }

  // Round down so every bucket still fits the current slot. Changes within a
  // bucket only relayout the existing raster, avoiding repeated decodes.
  static int _pixelBucket(double pixels) =>
      math.max(1, (pixels / 8).floor() * 8);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, available) {
      final constraints = widget.maximumSize == null
          ? available
          : BoxConstraints(
              maxWidth: math.min(available.maxWidth, widget.maximumSize!.width),
              maxHeight: math.min(
                available.maxHeight,
                widget.maximumSize!.height,
              ),
            );
      if (!constraints.hasBoundedWidth ||
          !constraints.hasBoundedHeight ||
          constraints.biggest.isEmpty) {
        if (_request != null) _reset();
        return widget.fallback;
      }
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final request = (
        bytes: widget.bytes,
        width: _pixelBucket(constraints.maxWidth * dpr),
        height: _pixelBucket(constraints.maxHeight * dpr),
        pixelRatio: dpr,
      );
      if (request != _request) _load(request);
      final raster = _raster;
      if (raster == null ||
          !clearLogoIsUsable(raster.intrinsicSize, constraints)) {
        return widget.fallback;
      }
      final fraction = raster.visibleFraction;
      var fitted = applyBoxFit(
        BoxFit.contain,
        raster.intrinsicSize,
        constraints.biggest,
      ).destination;
      final crop =
          widget.minimumVisibleSize != null ||
          widget.maximumVisibleHeight != null;
      if (crop) {
        final cap = widget.maximumVisibleHeight;
        if (cap != null && fitted.height * fraction.height > cap) {
          fitted *= cap / (fitted.height * fraction.height);
        }
        final minimum = widget.minimumVisibleSize;
        if (minimum != null &&
            (fitted.width * fraction.width < minimum.width ||
                fitted.height * fraction.height < minimum.height)) {
          return widget.fallback;
        }
      }
      Widget image = ConstrainedBox(
        constraints: constraints,
        child: RawImage(
          key: widget.imageKey,
          image: raster.image,
          // Preserve the original contain geometry independently of decode size.
          width: fitted.width,
          height: fitted.height,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
        ),
      );
      if (!widget.excludeFromSemantics) {
        image = Semantics(
          container: widget.semanticLabel != null,
          image: true,
          label: widget.semanticLabel ?? '',
          child: image,
        );
      }
      if (!crop) return image;
      return SizedBox(
        width: fitted.width * fraction.width,
        height: fitted.height * fraction.height,
        child: Stack(
          children: [
            Positioned(
              left: -fitted.width * fraction.left,
              top: -fitted.height * fraction.top,
              width: fitted.width,
              height: fitted.height,
              child: image,
            ),
          ],
        ),
      );
    },
  );
}

class _ClearLogoRaster {
  const _ClearLogoRaster(this.image, this.intrinsicSize, this.visibleFraction);

  final ui.Image image;
  final Size intrinsicSize;
  final Rect visibleFraction;
}

const _clearLogoCacheCapacity = 8;

/// One decoded (or failed) logo for a bytes object and pixel bucket. The cache
/// owns [raster]'s master image; mounted states only ever hold clones of it.
class _ClearLogoCacheEntry {
  _ClearLogoCacheEntry(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
  late final Future<void> done;
  _ClearLogoRaster? raster;
  bool completed = false;

  /// Set when the cache was reset while this decode was in flight.
  bool dropped = false;

  _ClearLogoRaster? cloneRaster() {
    final master = raster;
    if (master == null) return null;
    return _ClearLogoRaster(
      master.image.clone(),
      master.intrinsicSize,
      master.visibleFraction,
    );
  }
}

// Least recently used first. Bytes are matched by identity, never by content.
final List<_ClearLogoCacheEntry> _clearLogoCache = [];

_ClearLogoCacheEntry _clearLogoCacheEntry(_ClearLogoRequest request) {
  final index = _clearLogoCache.indexWhere(
    (entry) =>
        identical(entry.bytes, request.bytes) &&
        entry.width == request.width &&
        entry.height == request.height,
  );
  if (index >= 0) {
    final entry = _clearLogoCache.removeAt(index);
    _clearLogoCache.add(entry);
    return entry;
  }
  final entry = _ClearLogoCacheEntry(
    request.bytes,
    request.width,
    request.height,
  );
  entry.done = _decodeClearLogo(request).then((raster) {
    entry.completed = true;
    if (entry.dropped) {
      raster?.image.dispose();
      return;
    }
    entry.raster = raster;
  });
  _clearLogoCache.add(entry);
  _evictClearLogos();
  return entry;
}

// Runs only on insertion, which happens during build. Waiters clone in the
// microtasks that follow a decode, so every completed entry has been cloned
// before it can be evicted here.
void _evictClearLogos() {
  while (_clearLogoCache.length > _clearLogoCacheCapacity) {
    final index = _clearLogoCache.indexWhere((entry) => entry.completed);
    if (index < 0) return; // Never evict an in-flight decode.
    _clearLogoCache.removeAt(index).raster?.image.dispose();
  }
}

@visibleForTesting
void debugResetClearLogoCache() {
  for (final entry in _clearLogoCache) {
    if (entry.completed) {
      entry.raster?.image.dispose();
      entry.raster = null;
    } else {
      entry.dropped = true;
    }
  }
  _clearLogoCache.clear();
}

Future<_ClearLogoRaster?> _decodeClearLogo(_ClearLogoRequest request) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(request.bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final intrinsicSize = Size(
      descriptor.width.toDouble(),
      descriptor.height.toDouble(),
    );
    final scale = math.min(
      1.0,
      math.min(
        request.width / descriptor.width,
        request.height / descriptor.height,
      ),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).floor()),
      targetHeight: math.max(1, (descriptor.height * scale).floor()),
    );
    image = (await codec.getNextFrame()).image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixels == null) return null;
    var left = image.width, right = -1, top = image.height, bottom = -1;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (pixels.getUint8((y * image.width + x) * 4 + 3) >= 32) {
          left = math.min(left, x);
          right = math.max(right, x);
          top = math.min(top, y);
          bottom = math.max(bottom, y);
        }
      }
    }
    if (right < left || bottom < top) return null;
    final fraction = Rect.fromLTRB(
      math.max(0, left - 1) / image.width,
      math.max(0, top - 1) / image.height,
      math.min(image.width, right + 2) / image.width,
      math.min(image.height, bottom + 2) / image.height,
    );
    final result = _ClearLogoRaster(image, intrinsicSize, fraction);
    image = null; // The caller now owns this validated image handle.
    return result;
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
