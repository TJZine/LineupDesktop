import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

const _expected = [
  (Size(1920, 1080), 768, 5, 93),
  (Size(2560, 1440), 1024, 5, 93),
  (Size(3840, 2160), 1536, 5, 93),
  (Size(1280, 720), 358, 5, 93),
  (Size(1366, 768), 444, 5, 93),
  (Size(1280, 800), 501, 5, 93),
  (Size(1024, 768), 410, 5, 98),
  (Size(2560, 1080), 768, 5, 93),
  (Size(3440, 1440), 1024, 5, 93),
  (Size(1470, 923), 588, 5, 111),
  (Size(1512, 949), 605, 6, 96),
  (Size(1728, 1084), 691, 6, 98),
  (Size(1280, 600), 233, 5, 80),
];

void main() {
  test('L40 matches the approved window presets', () {
    for (final (window, pictureWidth, count, rowHeight) in _expected) {
      final scale = LineupCanvas.scaleFor(window);
      final policy = GuideLayoutPolicy.forSize(
        window / scale,
        hasPicture: true,
      );
      expect(
        policy.pictureWidth * scale,
        closeTo(pictureWidth, 1),
        reason: '$window',
      );
      expect(
        policy.showcaseHeight * scale,
        closeTo(pictureWidth * 9 / 16, 1),
        reason: '$window',
      );
      expect(policy.rowCount, count, reason: '$window');
      expect(policy.rowHeight, closeTo(rowHeight, 1), reason: '$window');
    }
  });

  test('L40 keeps the picture and row floors across the study sweep', () {
    const widths = [
      1024,
      1152,
      1280,
      1366,
      1440,
      1512,
      1600,
      1728,
      1920,
      2560,
      3440,
    ];
    final windows = {
      for (final w in widths)
        for (var h = 600; h <= 1600; h += 40)
          if (w / h >= 4 / 3 && w / h <= 21 / 9)
            Size(w.toDouble(), h.toDouble()),
      for (final (window, _, _, _) in _expected) window,
      const Size(1440, 900),
      const Size(1680, 1050),
      const Size(1920, 1200),
      const Size(2560, 1600),
      const Size(1470, 956),
      const Size(1512, 982),
      const Size(1710, 1112),
      const Size(1710, 1079),
      const Size(1728, 1117),
      const Size(1536, 864),
      const Size(1600, 900),
      const Size(1920, 1280),
      const Size(3024, 1964),
    };
    for (final window in windows) {
      final canvas = window / LineupCanvas.scaleFor(window);
      for (final scale in [1.0, 1.15, 1.3, 1.5, 2.0]) {
        for (final midnight in [false, true]) {
          final header = (midnight ? 46 : 38) * scale;
          final reason = '$window, text $scale, midnight $midnight';
          final baseline = _legacyDesktop(canvas, scale, header);
          final policy = GuideLayoutPolicy.forSize(
            canvas,
            hasPicture: true,
            textScale: scale,
            timeHeaderHeight: header,
          );
          final rowFloor = math.max(92.8, 52.7 * scale + 16.8);
          final extraRowFloor = math.max(96, rowFloor);
          final space = baseline.available - policy.showcaseHeight;
          const epsilon = 0.000001;
          // The legacy picture could be clipped by the band (0.01 cu rounding).
          final legacyPicture = math.min(
            baseline.band * 16 / 9,
            math.min(baseline.pictureWidth, canvas.width - 412),
          );
          expect(
            policy.pictureWidth + epsilon,
            greaterThanOrEqualTo(legacyPicture),
            reason: reason,
          );
          expect(
            policy.pictureWidth,
            lessThanOrEqualTo(canvas.width * .40 + epsilon),
            reason: reason,
          );
          expect(
            policy.rowHeight + epsilon,
            greaterThanOrEqualTo(math.min(rowFloor, baseline.rowHeight)),
            reason: reason,
          );
          expect(
            policy.rowCount,
            math.max(5, (space / extraRowFloor).floor()),
            reason: reason,
          );
          if (policy.rowCount >= 6) {
            expect(
              policy.rowHeight,
              greaterThanOrEqualTo(extraRowFloor),
              reason: reason,
            );
          }

          final noPicture = GuideLayoutPolicy.forSize(
            canvas,
            hasPicture: false,
            textScale: scale,
            timeHeaderHeight: header,
          );
          expect(
            noPicture.showcaseHeight,
            closeTo(baseline.band, epsilon),
            reason: reason,
          );
          expect(
            noPicture.pictureWidth,
            closeTo(baseline.pictureWidth, epsilon),
            reason: reason,
          );
          expect(
            noPicture.rowHeight,
            closeTo(baseline.rowHeight, epsilon),
            reason: reason,
          );
          expect(noPicture.rowCount, 5, reason: reason);

          _expectLegacyTv(canvas, scale, header, reason);
        }
      }
    }
  });
}

// Frozen pre-L40 desktop allocation, including its distinct chrome budgets.
({double available, double band, double pictureWidth, double rowHeight})
_legacyDesktop(Size size, double scale, double header) {
  final control = math.max(48.0, 18 * scale * 1.4 + 16);
  double controls(double inset) =>
      size.width - inset < 1000 * scale ? control * 2 : math.max(56.0, control);
  final available = math.max(0.0, size.height - 90 - header - controls(24));
  final pictureSpace = math.max(0.0, size.height - 110 - header - controls(40));
  final minimumRow = 58 * scale;
  final allocation = math.max(
    0.0,
    math.min(
      math.max(pictureSpace * .3, size.height - 1080 + 324) + .005,
      pictureSpace - minimumRow * 5,
    ),
  );
  final band = math.max(0.0, allocation - .01);
  return (
    available: available.toDouble(),
    band: band,
    pictureWidth: math.min(324, allocation) * 16 / 9,
    rowHeight: math.max(minimumRow, (available - band) / 5),
  );
}

void _expectLegacyTv(Size size, double scale, double header, String reason) {
  const controls = 56.0;
  const pictureMinimum = Size(244, 144);
  final identity = 568 + 430 * (scale - 1);
  final rowFloor = math.max(58 * scale, 44 * scale + 18);
  final information = 299 * scale;
  final available = math.max(0.0, size.height - 90 - controls - header);
  final band = math.min(
    math.max(
      size.height - 1080 + 324,
      math.max(information, pictureMinimum.height),
    ),
    math.max(0.0, available - rowFloor * 5),
  );
  final picture = math.max(
    pictureMinimum.width,
    math.min(
      band * 16 / 9,
      math.min(size.width * .32, size.width - 84 - identity - 400 * scale),
    ),
  );
  final tv = GuideLayoutPolicy.forSize(
    size,
    hasPicture: true,
    textScale: scale,
    timeHeaderHeight: header,
    tvControlsHeight: controls,
    tvRowFloor: rowFloor,
    tvInformationHeight: information,
    tvIdentityWidth: identity,
    tvPictureMinimum: pictureMinimum,
  );
  expect(tv.showcaseHeight, closeTo(band, .000001), reason: reason);
  expect(tv.pictureWidth, closeTo(picture, .000001), reason: reason);
  expect(
    tv.rowHeight,
    closeTo(math.max(rowFloor, (available - band) / 5), .000001),
    reason: reason,
  );
  expect(tv.rowCount, 5, reason: reason);
}
