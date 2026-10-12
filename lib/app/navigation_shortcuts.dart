import 'package:flutter/services.dart';

/// Recognizes Shell route chords without deciding when a caller handles them.
/// Shell accepts initial presses; Player also lets matching repeats propagate.
int? navigationShortcutIndex(LogicalKeyboardKey key) {
  if (!HardwareKeyboard.instance.isControlPressed) return null;
  return switch (key) {
    LogicalKeyboardKey.digit1 || LogicalKeyboardKey.keyG => 0,
    LogicalKeyboardKey.digit2 => 1,
    LogicalKeyboardKey.digit3 || LogicalKeyboardKey.comma => 2,
    LogicalKeyboardKey.digit4 => 3,
    LogicalKeyboardKey.digit5 || LogicalKeyboardKey.keyP => 4,
    _ => null,
  };
}
