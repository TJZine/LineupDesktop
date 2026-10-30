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
                    child: LineupHeading('One Appearance\nTwo', style: style),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('One'), findsOneWidget);
        expect(find.text('Appearance'), findsOneWidget);
        expect(find.text('Two'), findsOneWidget);
        final one = tester.getRect(find.text('One'));
        final appearance = tester.getRect(find.text('Appearance'));
        final two = tester.getRect(find.text('Two'));
        expect(appearance.top, greaterThanOrEqualTo(one.bottom));
        expect(two.top, greaterThanOrEqualTo(appearance.bottom));
        for (final text in find.byType(RichText).evaluate()) {
          final paragraph = text.renderObject! as RenderParagraph;
          if (paragraph.text.toPlainText() == 'Appearance') {
            expect(paragraph.textScaler.scale(48), greaterThanOrEqualTo(48));
            expect(
              paragraph.textScaler.scale(48),
              lessThanOrEqualTo(scaler.scale(48)),
            );
          }
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'body and desktop headings keep ordinary Text and inherited scaler',
    (tester) async {
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
    },
  );
}

/// Contract probe only: this is not the Android 14+ font converter curve.
class _SyntheticNonlinearScaler extends TextScaler {
  const _SyntheticNonlinearScaler();
  @override
  double scale(double fontSize) => fontSize * (fontSize >= 28 ? 1.5 : 2);
  @override
  double get textScaleFactor => 2;
}
