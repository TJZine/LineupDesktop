import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/guide/focused_ticker.dart';

void main() {
  testWidgets('fits without overflow and keeps ellipsis presentation static', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _Harness(
        child: FocusedTicker(text: 'Short program', focused: true),
      ),
    );

    final textFinder = find.text('Short program');
    final text = tester.widget<Text>(textFinder);
    final initialPosition = tester.getTopLeft(textFinder);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.getTopLeft(textFinder), initialPosition);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focused overflow moves after the initial pause', (tester) async {
    await tester.pumpWidget(
      const _Harness(
        child: FocusedTicker(
          text: 'A very long focused program title that must move',
          focused: true,
        ),
      ),
    );
    await tester.pump();
    final textFinder = find.text(
      'A very long focused program title that must move',
    );
    final initialX = tester.getTopLeft(textFinder).dx;

    // Cross the 900 ms start delay without advancing the scroll first.
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.getTopLeft(textFinder).dx, initialX);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getTopLeft(textFinder).dx, lessThan(initialX));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion keeps overflowing text static', (tester) async {
    await tester.pumpWidget(
      const _Harness(
        child: FocusedTicker(
          text: 'A very long focused program title that must stay still',
          focused: true,
          reduceMotion: true,
        ),
      ),
    );
    final textFinder = find.text(
      'A very long focused program title that must stay still',
    );
    final initialX = tester.getTopLeft(textFinder).dx;
    await tester.pump(const Duration(seconds: 3));

    final text = tester.widget<Text>(textFinder);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.getTopLeft(textFinder).dx, initialX);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchanged rebuild does not restart an active reveal', (
    tester,
  ) async {
    const ticker = FocusedTicker(
      key: ValueKey('ticker'),
      text: 'A very long title whose reveal survives ordinary rebuilds',
      focused: true,
    );
    await tester.pumpWidget(const _Harness(child: ticker));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));
    final finder = find.text(ticker.text);
    final before = tester.getTopLeft(finder).dx;

    await tester.pumpWidget(const _Harness(child: ticker));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.getTopLeft(finder).dx, lessThan(before));
  });

  testWidgets('RTL overflow travels toward the exposed leading text', (
    tester,
  ) async {
    const text = 'عنوان طويل جدًا يجب أن يتحرك ليكشف النص بالكامل';
    await tester.pumpWidget(
      const _Harness(
        direction: TextDirection.rtl,
        child: FocusedTicker(text: text, focused: true),
      ),
    );
    await tester.pump();
    final initialX = tester.getTopLeft(find.text(text)).dx;
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getTopLeft(find.text(text)).dx, greaterThan(initialX));
  });

  testWidgets('deactivation resets and stops obsolete motion', (tester) async {
    const text = 'A very long title that stops when its surface is inactive';
    await tester.pumpWidget(
      const _Harness(child: FocusedTicker(text: text, focused: true)),
    );
    await tester.pump();
    final initialX = tester.getTopLeft(find.text(text)).dx;
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getTopLeft(find.text(text)).dx, lessThan(initialX));

    await tester.pumpWidget(
      const _Harness(
        child: FocusedTicker(text: text, focused: true, active: false),
      ),
    );
    final resetX = tester.getTopLeft(find.text(text)).dx;
    await tester.pump(const Duration(seconds: 3));
    expect(tester.getTopLeft(find.text(text)).dx, resetX);
  });
}

class _Harness extends StatelessWidget {
  const _Harness({required this.child, this.direction = TextDirection.ltr});

  final Widget child;
  final TextDirection direction;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Directionality(
      textDirection: direction,
      child: Center(child: SizedBox(width: 140, child: child)),
    ),
  );
}
