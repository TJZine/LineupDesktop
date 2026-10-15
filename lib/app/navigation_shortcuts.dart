import 'package:flutter/services.dart';

enum ShellDestination { guide, channels, settings, diagnostics, player }

/// Command chords use Ctrl on every platform today. Keep the platform policy
/// here; deciding whether macOS should use Command is a separate product choice.
bool commandModifier(HardwareKeyboard keyboard) => keyboard.isControlPressed;

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
