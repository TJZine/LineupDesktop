import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:lineup_desktop/platform/device_profile.dart';

import 'app_theme.dart';
import 'keyboard_visibility.dart';
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
  ValueListenable<bool?>? _visibility;
  bool _observedVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _editingFocus.addListener(_editingFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visibility = KeyboardVisibilityScope.maybeOf(context);
    if (identical(visibility, _visibility)) {
      if (!_currentEditor) _clearVisibilityHistory();
      return;
    }
    _visibility?.removeListener(_visibilityChanged);
    _visibility = visibility;
    _observedVisible = false;
    visibility?.addListener(_visibilityChanged);
    _visibilityChanged();
  }

  bool get _currentEditor =>
      mounted &&
      widget.enabled &&
      _editing &&
      _editingFocus.hasPrimaryFocus &&
      ModalRoute.of(context)?.isCurrent != false;

  void _clearVisibilityHistory() {
    _observedVisible = false;
    _keyboardWasVisible = false;
  }

  void _visibilityChanged() =>
      _observeVisibility(_visibility?.value, fromInsets: false);

  void _insetsChanged() => _observeVisibility(
    // A shown floating IME can have zero insets. Native visibility wins and
    // retires inset-only hide credit while it explicitly reports shown.
    _visibility?.value == true ? null : View.of(context).viewInsets.bottom > 0,
    fromInsets: true,
  );

  void _observeVisibility(bool? visible, {required bool fromInsets}) {
    if (!_currentEditor) {
      _clearVisibilityHistory();
      return;
    }
    final resumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final wasVisible = fromInsets ? _keyboardWasVisible : _observedVisible;
    if (visible == null || (visible && resumed)) {
      if (fromInsets) {
        _keyboardWasVisible = visible == true;
      } else {
        _observedVisible = visible == true;
      }
    } else if (visible == false && wasVisible && resumed) {
      _finishEditing();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep shown history only while this editor remains live/current. A hide
    // observed while paused is reconciled on return, without taking focus in
    // the background or carrying history across an actual editor retirement.
    if (state == AppLifecycleState.resumed) {
      _visibilityChanged();
      _insetsChanged();
    } else if (!_currentEditor) {
      _clearVisibilityHistory();
    }
  }

  @override
  void didUpdateWidget(LineupTextFieldActivation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _editing) {
      _clearVisibilityHistory();
      _editing = false;
      _editingFocus.unfocus();
    }
  }

  void _editingFocusChanged() {
    if (!_editing && _editingFocus.hasFocus) {
      _clearVisibilityHistory();
      setState(() => _editing = true);
    } else if (_editing && !_editingFocus.hasFocus) {
      // A pointer or another route may take focus. End editing without stealing
      // that control's focus; Back/Done explicitly restore navigation focus.
      _clearVisibilityHistory();
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
    if (_editingFocus.hasPrimaryFocus) _visibilityChanged();
  }

  void _activate() {
    if (!widget.enabled || _editing) return;
    setState(() {
      _editing = true;
      _clearVisibilityHistory();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _editingFocus.requestFocus();
    });
  }

  void _finishEditing() {
    if (!_editing) return;
    _clearVisibilityHistory();
    setState(() => _editing = false);
    _focus.requestFocus();
  }

  @override
  void didChangeMetrics() {
    if (mounted) _insetsChanged();
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
    _visibility?.removeListener(_visibilityChanged);
    WidgetsBinding.instance.removeObserver(this);
    _editingFocus.removeListener(_editingFocusChanged);
    _editingFocus.dispose();
    _navigationFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    if (!DeviceProfile.of(context).isTv) {
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
