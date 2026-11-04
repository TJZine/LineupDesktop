import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/platform/device_profile.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

void main() {
  for (final scaler in [
    const TextScaler.linear(1.3),
    const _SyntheticNonlinearScaler(),
  ]) {
    testWidgets(
      'headlines wrap whole words and fit only over-wide words with $scaler',
      (tester) async {
        const style = TextStyle(fontSize: 48, fontFamily: 'Ahem');
        await tester.pumpWidget(
          DeviceProfileScope(
            profile: const DeviceProfile(
              host: TargetPlatform.android,
              formFactor: FormFactor.handheld,
            ),
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: scaler),
                child: const Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 520,
                    child: LineupHeading(
                      'One Appearance\nTwo MMMMMMMMMMMMMMMMMMMMMM',
                      style: style,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        Rect wordBounds(String word) {
          final paragraphs = find
              .descendant(
                of: find.byType(LineupHeading),
                matching: find.byType(RichText),
              )
              .evaluate()
              .map((element) => element.renderObject! as RenderParagraph);
          for (final paragraph in paragraphs) {
            final start = paragraph.text.toPlainText().indexOf(word);
            if (start < 0) continue;
            final glyphs = [
              for (var index = start; index < start + word.length; index++)
                ...paragraph.getBoxesForSelection(
                  TextSelection(baseOffset: index, extentOffset: index + 1),
                ),
            ];
            expect(glyphs, hasLength(word.length));
            expect(glyphs.map((box) => box.top).toSet(), hasLength(1));
            return glyphs.first
                .toRect()
                .expandToInclude(glyphs.last.toRect())
                .shift(paragraph.localToGlobal(Offset.zero));
          }
          throw StateError('Missing word: $word');
        }

        final one = wordBounds('One');
        final appearance = wordBounds('Appearance');
        final two = wordBounds('Two');
        expect(one.width, closeTo(3 * scaler.scale(48), .1));
        expect(two.width, closeTo(one.width, .1));
        expect(appearance.top, greaterThanOrEqualTo(one.bottom - .1));
        expect(two.top, greaterThanOrEqualTo(appearance.bottom - 1));
        expect(appearance.width, inInclusiveRange(480, 520.01));
        final last = wordBounds('MMMMMMMM');
        expect(last.width, closeTo(8 * 48, .1));
        expect(wordBounds('…').right, lessThanOrEqualTo(520.01));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('desktop headings keep ordinary Text and inherited scaler', (
    tester,
  ) async {
    const scaler = _SyntheticNonlinearScaler();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: scaler),
          child: const LineupHeading(
            'Desktop heading stays intact',
            style: TextStyle(fontSize: 48),
          ),
        ),
      ),
    );
    expect(find.text('Desktop heading stays intact'), findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    expect(paragraph.textScaler, same(scaler));
  });
}

/// Contract probe only: this is not the Android 14+ font converter curve.
class _SyntheticNonlinearScaler extends TextScaler {
  const _SyntheticNonlinearScaler();
  @override
  double scale(double fontSize) => fontSize * (fontSize >= 28 ? 1.5 : 2);
  @override
  double get textScaleFactor => 2;
}
