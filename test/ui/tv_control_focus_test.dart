import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

Color? _ink(WidgetTester tester, String label) => tester
    .widget<RichText>(
      find.descendant(
        of: find.text(label).first,
        matching: find.byType(RichText),
      ),
    )
    .text
    .style
    ?.color;

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  required bool tv,
  required TargetPlatform platform,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: LineupTheme.forName(
        LineupThemeName.emberSteel,
        androidTv: tv,
      ).copyWith(platform: platform),
      builder: LineupCanvas.builder,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  autofocus: true,
                  onPressed: () {},
                  child: const Text('Start'),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    final tv = platform == TargetPlatform.android;
    testWidgets('$platform toggle focus follows D-pad, not touch highlight', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final node = FocusNode();
      addTearDown(node.dispose);
      final value = ValueNotifier(true);
      addTearDown(value.dispose);
      await _mount(
        tester,
        LineupToggleSurface(
          child: ValueListenableBuilder<bool>(
            valueListenable: value,
            builder: (_, checked, _) => SwitchListTile(
              focusNode: node,
              value: checked,
              title: const Text('Artwork'),
              subtitle: const Text('Show title artwork'),
              onChanged: (checked) => value.value = checked,
            ),
          ),
        ),
        tv: tv,
        platform: platform,
      );
      final before = tester.element(find.byType(SwitchListTile));
      final base = _ink(tester, 'Artwork');
      final baseSupport = _ink(tester, 'Show title artwork');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(node.hasFocus, isTrue);
      expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
      expect(_ink(tester, 'Artwork'), tv ? const Color(0xFF090806) : base);
      expect(
        _ink(tester, 'Show title artwork'),
        tv ? const Color(0xFF090806) : baseSupport,
      );
      expect(tester.element(find.byType(SwitchListTile)), same(before));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(value.value, isFalse);
      expect(node.hasFocus, isTrue);
      expect(_ink(tester, 'Artwork'), tv ? const Color(0xFF090806) : base);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(node.hasFocus, isFalse);
      expect(_ink(tester, 'Artwork'), base);
      if (!tv) expect(find.byType(LineupRowSurface), findsNothing);
    });

    testWidgets('$platform form dropdown focus and popup ink are independent', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final node = FocusNode();
      addTearDown(node.dispose);
      await _mount(
        tester,
        Builder(
          builder: (context) => lineupDropdownField<int>(
            context: context,
            focusNode: node,
            initialValue: 1,
            items: const [
              DropdownMenuItem(value: 1, child: Text('First')),
              DropdownMenuItem(value: 2, child: Text('Second')),
            ],
            onChanged: (_) {},
          ),
        ),
        tv: tv,
        platform: platform,
      );
      final field = tester.element(find.byType(DropdownButtonFormField<int>));
      final baseSurface = LineupTheme.of(field).elevatedSurface;
      final base = _ink(tester, 'First');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(node.hasFocus, isTrue);
      expect(_ink(tester, 'First'), tv ? const Color(0xFF090806) : base);
      expect(
        tester
            .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
            .dropdownColor,
        baseSurface,
      );
      expect(
        tester.element(find.byType(DropdownButtonFormField<int>)),
        same(field),
      );
      if (tv) {
        final decorator = tester.widget<InputDecorator>(
          find.byType(InputDecorator),
        );
        expect(decorator.isFocused, isTrue);
        expect(decorator.decoration.fillColor, const Color(0xFFE9DCC3));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final second = find.text('Second').hitTestable();
      expect(second, findsOneWidget);
      if (tv) {
        expect(_inkAt(tester, second), const Color(0xFF090806));
        final first = find.text('First').hitTestable();
        expect(_inkAt(tester, first), const Color(0xFFF3E8D2));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(node.hasFocus, isTrue);
    });
  }

  testWidgets(
    'TV Material and ListTile defaults carry focus ink without losing selection',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      const marker = Icon(Icons.check, color: Color(0xFFE1AD52));
      await _mount(
        tester,
        LineupRowSurface(
          selected: true,
          child: ListTile(
            focusNode: node,
            title: const Text('Preset'),
            subtitle: const Text('Details'),
            trailing: marker,
            onTap: () {},
          ),
        ),
        tv: true,
        platform: TargetPlatform.android,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(node.hasFocus, isTrue);
      expect(_ink(tester, 'Preset'), const Color(0xFF090806));
      expect(_ink(tester, 'Details'), const Color(0xFF090806));
      expect(tester.widget<Icon>(find.byIcon(Icons.check)).color, marker.color);
      expect(
        tester.widget<LineupRowSurface>(find.byType(LineupRowSurface)).selected,
        isTrue,
      );
    },
  );

  for (final checkbox in [false, true]) {
    testWidgets(
      'TV ${checkbox ? 'checkbox' : 'switch'} disabled control is skipped',
      (tester) async {
        final node = FocusNode();
        addTearDown(node.dispose);
        await _mount(
          tester,
          LineupToggleSurface(
            child: checkbox
                ? CheckboxListTile(
                    focusNode: node,
                    value: true,
                    onChanged: null,
                    title: const Text('Disabled'),
                  )
                : SwitchListTile(
                    focusNode: node,
                    value: true,
                    onChanged: null,
                    title: const Text('Disabled'),
                  ),
          ),
          tv: true,
          platform: TargetPlatform.android,
        );
        final base = _ink(tester, 'Disabled');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(node.hasFocus, isFalse);
        expect(_ink(tester, 'Disabled'), base);
      },
    );
  }

  testWidgets('TV checkbox checked state is independent of actual focus', (
    tester,
  ) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    final node = FocusNode();
    addTearDown(node.dispose);
    await _mount(
      tester,
      LineupToggleSurface(
        child: CheckboxListTile(
          focusNode: node,
          value: false,
          onChanged: (_) {},
          title: const Text('Consent'),
        ),
      ),
      tv: true,
      platform: TargetPlatform.android,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
    expect(_ink(tester, 'Consent'), const Color(0xFF090806));
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
  });
}

Color? _inkAt(WidgetTester tester, Finder finder) => tester
    .widget<RichText>(
      find.descendant(of: finder, matching: find.byType(RichText)),
    )
    .text
    .style
    ?.color;
