import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ShellDestination { guide, channels, settings, diagnostics, player }

/// Command chords use Command on macOS and Ctrl on every other platform. Keep
/// the platform policy here. Guards that reject any modifier for plain-key
/// shortcuts must stay modifier-agnostic and not use this.
bool commandModifier(HardwareKeyboard keyboard) =>
    defaultTargetPlatform == TargetPlatform.macOS
    ? keyboard.isMetaPressed
    : keyboard.isControlPressed;

ShellDestination? navigationShortcutDestination(LogicalKeyboardKey key) {
  if (!commandModifier(HardwareKeyboard.instance)) return null;
  return switch (key) {
    LogicalKeyboardKey.digit1 ||
    LogicalKeyboardKey.keyG => ShellDestination.guide,
    LogicalKeyboardKey.digit2 => ShellDestination.channels,
    LogicalKeyboardKey.digit3 ||
    LogicalKeyboardKey.comma => ShellDestination.settings,
    LogicalKeyboardKey.digit4 => ShellDestination.diagnostics,
    LogicalKeyboardKey.digit5 ||
    LogicalKeyboardKey.keyP => ShellDestination.player,
    _ => null,
  };
}

/// Native Android normalizes OS Back to one route request. This single root
/// claim runs the focused controls' ordinary Back handlers in leaf-to-root
/// order, without injecting a hardware event or tracking a prior press. Product
/// actions remain shared with the existing logical Back key path.
class AndroidBackScope extends StatefulWidget {
  const AndroidBackScope({
    required this.child,
    this.onUnhandledBack,
    super.key,
  });
  final bool Function()? onUnhandledBack;
  final Widget child;

  static bool claims(BuildContext context) =>
      context.findAncestorStateOfType<_AndroidBackScopeState>() != null;

  @override
  State<AndroidBackScope> createState() => _AndroidBackScopeState();
}

class _AndroidBackScopeState extends State<AndroidBackScope> {
  final _focus = FocusNode(debugLabel: 'Android root Back');
  static const _platform = MethodChannel('lineup/platform');

  void _background() =>
      unawaited(_platform.invokeMethod<bool>('moveTaskToBack'));

  void _dispatchUnhandledBack() {
    if (widget.onUnhandledBack?.call() != true) _background();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final contextual =
        key == LogicalKeyboardKey.goBack ||
        (widget.onUnhandledBack != null &&
            (key == LogicalKeyboardKey.escape ||
                key == LogicalKeyboardKey.backspace));
    if (!contextual || event is KeyUpEvent) return KeyEventResult.ignored;
    final context = FocusManager.instance.primaryFocus?.context;
    if (key == LogicalKeyboardKey.backspace &&
        (context?.widget is EditableText ||
            context?.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent && widget.onUnhandledBack != null) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    _dispatchUnhandledBack();
    return KeyEventResult.handled;
  }

  void _systemBack(bool didPop, Object? result) {
    if (didPop || ModalRoute.of(context)?.isCurrent != true) return;
    const event = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.browserBack,
      logicalKey: LogicalKeyboardKey.goBack,
      timeStamp: Duration.zero,
    );
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null &&
        (primary == _focus || primary.ancestors.contains(_focus))) {
      // Snapshot before callbacks: handling Back may remove a focused subtree.
      for (final node in [primary, ...primary.ancestors]) {
        if (node.onKeyEvent?.call(node, event) case final result?
            when result != KeyEventResult.ignored) {
          return;
        }
        if (node == _focus) break;
      }
    }
    _dispatchUnhandledBack();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: false,
    onPopInvokedWithResult: _systemBack,
    child: Focus(
      focusNode: _focus,
      canRequestFocus: false,
      onKeyEvent: _key,
      child: widget.child,
    ),
  );
}
