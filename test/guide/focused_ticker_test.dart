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
}

class _Harness extends StatelessWidget {
  const _Harness({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Center(child: SizedBox(width: 140, child: child)),
  );
}
