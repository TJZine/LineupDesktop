import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// Some controls supply their own accessible labels and exclude the tooltip
// from semantics. The framework's byTooltip finder cannot read those messages
// on the standalone Material package's Tooltip widget.
Finder materialTooltip(String message) => find.byWidgetPredicate(
  (widget) => widget is Tooltip && widget.message == message,
);
