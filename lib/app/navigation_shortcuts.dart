import 'package:flutter/foundation.dart';
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
