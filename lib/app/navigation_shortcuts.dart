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

/// Android predictive Back uses route pops instead of key events. Keep a single
/// route claim, then run the focused controls' ordinary Back handlers in their
/// normal leaf-to-root order. This never injects a hardware event or changes the
/// pressed-key state. A handled API 30 key therefore cannot also request a pop.
class AndroidBackScope extends StatefulWidget {
  const AndroidBackScope({required this.child, super.key});
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

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.goBack) {
      return KeyEventResult.ignored;
    }
    _background();
    return KeyEventResult.handled;
  }

  void _systemBack(bool didPop, Object? result) {
    if (didPop || ModalRoute.of(context)?.isCurrent != true) return;
    // Android may send a route pop during a hardware Back dispatch, even when
    // its key handler already consumed the press. That pressed key owns Back;
    // only the key-free predictive path needs the route-to-focus translation.
    if (HardwareKeyboard.instance.logicalKeysPressed.contains(
      LogicalKeyboardKey.goBack,
    )) {
      return;
    }
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
    } else {
      _background();
    }
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
