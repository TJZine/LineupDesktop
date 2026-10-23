import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'lineup_focus.dart';

/// Android TV fields have separate navigation and editing focus. Arrow arrival
/// never grants EditableText a keyboard token; Select explicitly starts editing.
/// Desktop builders receive their original focus node and editing behavior.
class LineupTextFieldActivation extends StatefulWidget {
  const LineupTextFieldActivation({
    required this.builder,
    this.focusNode,
    this.enabled = true,
    super.key,
  });

  final Widget Function(
    BuildContext context,
    FocusNode? focusNode,
    VoidCallback? onEditingComplete,
  )
  builder;
  final FocusNode? focusNode;
  final bool enabled;

  @override
  State<LineupTextFieldActivation> createState() =>
      _LineupTextFieldActivationState();
}

class _LineupTextFieldActivationState extends State<LineupTextFieldActivation>
    with WidgetsBindingObserver {
  final _navigationFocus = FocusNode(debugLabel: 'TV text field');
  final _editingFocus = FocusNode(debugLabel: 'TV text field editor');
  FocusNode get _focus => widget.focusNode ?? _navigationFocus;
  bool _editing = false;
  bool _keyboardWasVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _editingFocus.addListener(_editingFocusChanged);
  }

  @override
  void didUpdateWidget(LineupTextFieldActivation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _editing) {
      _editing = false;
      _editingFocus.unfocus();
    }
  }

  void _editingFocusChanged() {
    if (!_editing && _editingFocus.hasFocus) {
      setState(() => _editing = true);
    } else if (_editing && !_editingFocus.hasFocus) {
      // A pointer or another route may take focus. End editing without stealing
      // that control's focus; Back/Done explicitly restore navigation focus.
      setState(() => _editing = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _editing ||
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed ||
            ModalRoute.of(context)?.isCurrent == false) {
          return;
        }
        // EditableText closes its connection by unfocusing to the route scope.
        // Restore this field only in that stranded state, never over another
        // control or a newly opened route.
        final primary = FocusManager.instance.primaryFocus;
        if (primary == null || primary is FocusScopeNode) _focus.requestFocus();
      });
    }
  }

  void _activate() {
    if (!widget.enabled || _editing) return;
    setState(() {
      _editing = true;
      _keyboardWasVisible = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _editingFocus.requestFocus();
    });
  }

  void _finishEditing() {
    if (!_editing) return;
    setState(() => _editing = false);
    _focus.requestFocus();
  }

  @override
  void didChangeMetrics() {
    if (!mounted || !_editing) return;
    final keyboardVisible = View.of(context).viewInsets.bottom > 0;
    if (keyboardVisible) {
      _keyboardWasVisible = true;
    } else if (_keyboardWasVisible) {
      // Android's IME can consume Back without sending Flutter a key or pop.
      // Its inset transition is the observation that editing has ended.
      _finishEditing();
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_editing &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      // A shown TV IME owns its arrows. Once an arrow reaches this single-line
      // field, leave editing rather than trapping navigation in EditableText.
      _finishEditing();
      _focus.focusInDirection(
        key == LogicalKeyboardKey.arrowUp
            ? TraversalDirection.up
            : TraversalDirection.down,
      );
      return KeyEventResult.handled;
    }
    if (_editing &&
        (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      _finishEditing();
      return KeyEventResult.handled;
    }
    if (!_editing &&
        (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _editingFocus.removeListener(_editingFocusChanged);
    _editingFocus.dispose();
    _navigationFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    if (!roles.androidTv) {
      return widget.builder(context, widget.focusNode, null);
    }
    final focused =
        !_editing && LineupFocusScope.visible(context, _focus.hasFocus);
    final data = Theme.of(context);
    final decoration = data.inputDecorationTheme;
    final fill = focused && roles.focusTreatment == LineupFocusTreatment.fill;
    return Focus(
      focusNode: _focus,
      canRequestFocus: widget.enabled,
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: _key,
      child: Listener(
        onPointerDown: (_) => _activate(),
        child: LineupFocusInk(
          focused: fill,
          child: LineupFocusFrame(
            focused: fill,
            child: Builder(
              builder: (context) => Theme(
                data: Theme.of(context).copyWith(
                  inputDecorationTheme: decoration.copyWith(
                    hintStyle: decoration.hintStyle?.copyWith(
                      color: LineupTheme.of(context).mutedText,
                    ),
                    labelStyle: decoration.labelStyle?.copyWith(
                      color: LineupTheme.of(context).secondaryText,
                    ),
                    fillColor: fill
                        ? roles.focusedSurface
                        : decoration.fillColor,
                    enabledBorder: focused
                        ? decoration.focusedBorder
                        : decoration.enabledBorder,
                  ),
                ),
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  descendantsAreTraversable: _editing,
                  child: Builder(
                    builder: (context) =>
                        widget.builder(context, _editingFocus, _finishEditing),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
