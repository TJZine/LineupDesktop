// Stock-widget keyboard probe. No query contents are logged.
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProbeApp());
}

class ProbeApp extends StatefulWidget {
  const ProbeApp({super.key});

  @override
  State<ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<ProbeApp> {
  static const seed = 'zzaxverification';
  final controller = TextEditingController.fromValue(
    const TextEditingValue(
      text: seed,
      selection: TextSelection.collapsed(offset: seed.length),
    ),
  );
  final focus = FocusNode();
  final clock = Stopwatch()..start();
  int sequence = 0;
  static final knownKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.backspace,
  };

  void log(String kind, [Map<String, Object?> extra = const {}]) {
    print(
      '[stock-keyboard-trace] ${jsonEncode({'sequence': ++sequence, 'kind': kind, 'utc': DateTime.now().toUtc().toIso8601String(), 'elapsedUs': clock.elapsedMicroseconds, 'searchHasFocus': focus.hasFocus, 'searchPrimary': identical(FocusManager.instance.primaryFocus, focus), 'length': controller.text.length, 'selectionBase': controller.selection.baseOffset, 'selectionExtent': controller.selection.extentOffset, ...extra})}',
    );
  }

  void changed() => log('query-change');
  void focusChanged() => log('focus-change');

  bool key(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final known = knownKeys.contains(event.logicalKey);
    log('hardware-key', {
      'phase': event is KeyDownEvent
          ? 'down'
          : event is KeyUpEvent
          ? 'up'
          : 'repeat',
      'category': known ? 'known-key' : 'redacted-key',
      'logical': known ? event.logicalKey.keyId : null,
      'physical': known ? event.physicalKey.usbHidUsage : null,
      'synthesized': event.synthesized,
      'eventUs': event.timeStamp.inMicroseconds,
      'meta': keyboard.isMetaPressed,
      'control': keyboard.isControlPressed,
      'alt': keyboard.isAltPressed,
      'shift': keyboard.isShiftPressed,
    });
    return false;
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(changed);
    focus.addListener(focusChanged);
    HardwareKeyboard.instance.addHandler(key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) log('probe-ready');
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(key);
    focus.removeListener(focusChanged);
    controller.removeListener(changed);
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Keyboard stock probe',
    home: Scaffold(
      body: TextField(
        controller: controller,
        focusNode: focus,
        decoration: const InputDecoration(labelText: 'Probe search'),
      ),
    ),
  );
}
