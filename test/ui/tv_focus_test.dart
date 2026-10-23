import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

void main() {
  testWidgets('TV row focus fills the row and preserves the child element', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(LineupThemeName.emberSteel, androidTv: true),
        builder: LineupCanvas.builder,
        home: Scaffold(
          body: LineupRowSurface(
            selected: true,
            child: Focus(
              focusNode: focusNode,
              child: const _RoleProbe(key: ValueKey('role-probe')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final probe = find.byKey(const ValueKey('role-probe'));
    final before = tester.element(probe);
    expect(LineupTheme.of(before).primaryText, const Color(0xFFF3E8D2));

    focusNode.requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 160));

    final after = tester.element(probe);
    expect(identical(before, after), isTrue);
    expect(LineupTheme.of(after).primaryText, const Color(0xFF090806));
    expect(LineupTheme.of(after).secondaryText, const Color(0xFF3B3226));
    final focusedRoles = LineupTheme.of(after);
    expect(focusedRoles.deepBackground, const Color(0xFFD7C7A8));
    expect(focusedRoles.primarySurface, const Color(0xFFD7C7A8));
    expect(focusedRoles.elevatedSurface, const Color(0xFFD7C7A8));
    expect(focusedRoles.selectedSurface, const Color(0xFFD7C7A8));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color ==
                const Color(0xFFE9DCC3),
      ),
      findsOneWidget,
    );
  });

  testWidgets('large TV focus paints the exception and honors reduce motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(
          LineupThemeName.emberSteel,
          androidTv: true,
          largeFocusIndicators: true,
        ),
        builder: (context, child) => LineupCanvas.builder(
          context,
          MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: LineupSelectionCard(
            autofocus: true,
            selected: false,
            onPressed: () {},
            child: const Text('Card'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1.06);
    expect(scale.duration, Duration.zero);
    expect(
      tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .every((container) => container.duration == Duration.zero),
      isTrue,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.foregroundPainter != null,
      ),
      findsWidgets,
    );
  });
}

class _RoleProbe extends StatelessWidget {
  const _RoleProbe({super.key});

  @override
  Widget build(BuildContext context) => Text(
    'Focused row',
    style: TextStyle(color: LineupTheme.of(context).primaryText),
  );
}
