import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/subtitle_cues.dart';
import 'package:lineup_desktop/playback/subtitle_layer.dart';
import 'package:lineup_desktop/settings/subtitle_style.dart';

import '../support/golden_test_support.dart';

SubtitleCues fixture({int align = 2, String text = 'Fixture caption'}) =>
    SubtitleCues([
      SubtitleCue(
        align: align,
        lines: [
          [SubtitleSegment(text: text)],
        ],
      ),
    ]);
SubtitlePainter painter(SubtitleStyle style, {SubtitleCues? cues}) =>
    SubtitlePainter(
      cues: cues ?? fixture(),
      appearance: style.resolve(),
      fontFamily: 'Inter',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPinnedTestFonts);
  test('every size uses presentation height and wraps at 90 percent', () {
    const size = Size(600, 300);
    for (final scale in SubtitleSize.values) {
      final p = painter(SubtitleStyle(size: scale));
      final text = p.layout(fixture().cues.single, size);
      expect(
        (text.text! as TextSpan).style!.fontSize,
        closeTo(.0533 * scale.scale * 300, .00001),
      );
      expect((text.text! as TextSpan).style!.height, 1.2);
      expect(text.textScaler, TextScaler.noScaling);
      text.dispose();
    }
    final p = painter(const SubtitleStyle());
    final text = p.layout(
      fixture(text: 'Long fixture caption ' * 20).cues.single,
      size,
    );
    expect(text.width, lessThanOrEqualTo(540));
    expect(text.computeLineMetrics().length, greaterThan(1));
    text.dispose();
  });
  test(
    'nine keypad alignments, line alignment and raise use rectangle geometry',
    () {
      const size = Size(600, 300);
      for (var align = 1; align <= 9; align++) {
        final cue = fixture(align: align).cues.single;
        final p = painter(const SubtitleStyle());
        final text = p.layout(cue, size);
        final offset = p.origin(cue, size, text.size);
        final column = (align - 1) % 3;
        final row = (align - 1) ~/ 3;
        expect(
          offset.dx,
          [30, (600 - text.width) / 2, 570 - text.width][column],
        );
        expect(
          offset.dy,
          [282 - text.height, (300 - text.height) / 2, 18][row],
        );
        expect(
          text.textAlign,
          [TextAlign.left, TextAlign.center, TextAlign.right][column],
        );
        for (final position in SubtitlePosition.values) {
          final raised = painter(SubtitleStyle(position: position));
          expect(
            raised.origin(cue, size, text.size).dy,
            closeTo(offset.dy - (row == 0 ? position.raise * 300 : 0), .00001),
          );
        }
        text.dispose();
      }
    },
  );
  test('approved final metrics and per-cue clearance use painted bounds', () {
    expect(SubtitlePainter.outlineStrokeEm, .10);
    expect(SubtitlePainter.shadowOffsetEm, .06);
    expect(SubtitlePainter.shadowBlurEm, .06);
    expect(SubtitlePainter.backgroundInsetEm, .2);

    const size = Size(600, 300);
    final p = painter(
      const SubtitleStyle(
        edge: SubtitleEdge.outline,
        windowOpacity: SubtitleBoxOpacity.full,
        backgroundOpacity: SubtitleBoxOpacity.full,
      ),
    );
    final bottom = fixture(align: 1).cues.single;
    final bounds = p.renderedBlockBounds(bottom, size);
    expect(
      p.clearanceLift(bottom, size, panelTop: bounds.bottom - 10),
      closeTo(10 + .02 * size.height, .00001),
    );
    final noRoomLift = p.clearanceLift(bottom, size, panelTop: 0);
    expect(bounds.top - noRoomLift, lessThan(0));
    expect(bounds.bottom - noRoomLift, closeTo(-.02 * size.height, .00001));
    expect(
      p.clearanceLift(fixture(align: 5).cues.single, size, panelTop: 0),
      0,
    );
    expect(
      p.clearanceLift(fixture(align: 7).cues.single, size, panelTop: 0),
      0,
    );
  });

  testWidgets('panel reporter maps the material feather into the layer', (
    tester,
  ) async {
    final avoidance = SubtitlePanelAvoidance();
    final presentationKey = GlobalKey();
    addTearDown(avoidance.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SubtitleLayer(
              cues: ValueNotifier(fixture()),
              appearance: ValueNotifier(const SubtitleStyle().resolve()),
              avoidance: avoidance,
              presentationKey: presentationKey,
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SubtitlePanelReporter(
                avoidance: avoidance,
                presentationKey: presentationKey,
                feather: 55,
                child: const SizedBox(height: 50, width: double.infinity),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    final layer = tester.renderObject<RenderBox>(find.byType(SubtitleLayer));
    expect(
      avoidance.value.highestPanelTop,
      closeTo(layer.size.height - 50 - 55, .00001),
    );
  });

  test('cue emphasis and viewer bold both survive styled spans', () {
    final cue = SubtitleCue(
      align: 2,
      lines: [
        [
          const SubtitleSegment(text: 'plain'),
          const SubtitleSegment(
            text: 'emphasis',
            italic: true,
            bold: true,
            underline: true,
          ),
        ],
        [const SubtitleSegment(text: 'second line')],
      ],
    );
    for (final bold in [false, true]) {
      final text = painter(SubtitleStyle(bold: bold))
          .layout(cue, const Size(600, 300));
      final spans = (text.text! as TextSpan).children!.cast<TextSpan>();
      expect(
        spans[0].style!.fontWeight,
        bold ? FontWeight.bold : FontWeight.normal,
      );
      expect(spans[1].style!.fontStyle, FontStyle.italic);
      expect(spans[1].style!.fontWeight, FontWeight.bold);
      expect(spans[1].style!.decoration, TextDecoration.underline);
      expect(spans[2].text, '\n');
      text.dispose();
    }
  });
  testWidgets(
    'app scaling ignored; empty cues are transparent and semantics absent',
    (tester) async {
      final cues = ValueNotifier(const SubtitleCues.empty());
      final appearance = ValueNotifier(const SubtitleStyle().resolve());
      addTearDown(cues.dispose);
      addTearDown(appearance.dispose);
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 600,
              height: 300,
              child: SubtitleLayer(cues: cues, appearance: appearance),
            ),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsNothing);
      cues.value = fixture();
      await tester.pump();
      final p =
          tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
              as SubtitlePainter;
      final text = p.layout(cues.value.cues.single, const Size(600, 300));
      expect((text.text! as TextSpan).style!.fontSize, 15.99);
      text.dispose();
      expect(find.bySemanticsLabel('Fixture caption'), findsNothing);
      expect(
        tester.widget<IgnorePointer>(find.byType(IgnorePointer)).ignoring,
        isTrue,
      );
      cues.value = const SubtitleCues.empty();
      await tester.pump();
      expect(find.byType(CustomPaint), findsNothing);
      semantics.dispose();
    },
  );
  test('edges paint distinct proportional output; line and window boxes coexist with opacity', () async {
    Future<Uint8List> raster(
      SubtitleStyle style,
      Size size, {
      SubtitleCues? cues,
    }) async {
      final recorder = ui.PictureRecorder();
      painter(style, cues: cues).paint(Canvas(recorder), size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      picture.dispose();
      return data!.buffer.asUint8List();
    }

    final hashes = <int>{};
    for (final edge in SubtitleEdge.values) {
      final data = await raster(
        SubtitleStyle(edge: edge, edgeColor: SubtitleColor.red),
        const Size(600, 300),
      );
      hashes.add(Object.hashAll(data));
    }
    expect(hashes, hasLength(SubtitleEdge.values.length));
    final style = const SubtitleStyle(
      edge: SubtitleEdge.none,
      backgroundColor: SubtitleColor.red,
      backgroundOpacity: SubtitleBoxOpacity.half,
      windowColor: SubtitleColor.blue,
      windowOpacity: SubtitleBoxOpacity.quarter,
    );
    final data = await raster(style, const Size(600, 300));
    final pixels = <String>{};
    for (var i = 0; i < data.length; i += 4) {
      pixels.add('${data[i]},${data[i + 1]},${data[i + 2]},${data[i + 3]}');
    }
    expect(pixels, contains('0,0,64,64')); // window only
    expect(
      pixels.any((p) => p.startsWith('128,0,32,160')),
      isTrue,
    ); // line over window
    expect(pixels, contains('0,0,0,0'));
    final empty = await raster(
      style,
      const Size(600, 300),
      cues: SubtitleCues([
        SubtitleCue(align: 2, lines: const [[]]),
      ]),
    );
    expect(empty.every((byte) => byte == 0), isTrue);
  });
  testWidgets(
    'font loads once on demand; fallback switches only after successful load',
    (tester) async {
      final fonts = _DelayedFonts();
      final cues = ValueNotifier(const SubtitleCues.empty());
      final appearance = ValueNotifier(
        const SubtitleStyle(font: SubtitleFont.casual).resolve(),
      );
      addTearDown(cues.dispose);
      addTearDown(appearance.dispose);
      await tester.pumpWidget(
        SubtitleLayer(cues: cues, appearance: appearance, fonts: fonts),
      );
      expect(fonts.paths, isEmpty);
      cues.value = fixture();
      await tester.pump();
      expect(fonts.paths, [
        'assets/fonts/subtitles/casual/Regular.ttf',
        'assets/fonts/subtitles/casual/Bold.ttf',
      ]);
      SubtitlePainter current() =>
          tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
              as SubtitlePainter;
      expect(current().fontFamily, 'Inter');
      fonts.release.complete();
      await tester.pump();
      await tester.pump();
      expect(current().fontFamily, 'Comic Neue');
      appearance.value = const SubtitleStyle(
        font: SubtitleFont.casual,
        bold: true,
      ).resolve();
      await tester.pump();
      expect(fonts.paths, hasLength(2));
    },
  );
  test('every bundled static font loads through FontLoader', () async {
    final fonts = SubtitleFonts();
    for (final font in SubtitleFont.values) {
      expect(await fonts.load(font), isTrue);
      expect(fonts.isReady(font), isTrue);
    }
  });
  test('real font asset requests are cached across consumers', () async {
    final assets = _CountingFonts();
    final fonts = SubtitleFonts(assets: assets);
    expect(assets.paths, isEmpty);
    final first = fonts.load(SubtitleFont.monoSans);
    final second = fonts.load(SubtitleFont.monoSans);
    expect(identical(first, second), isTrue);
    expect(await first, isTrue);
    expect(assets.paths, [
      'assets/fonts/subtitles/monoSans/Regular.ttf',
      'assets/fonts/subtitles/monoSans/Bold.ttf',
    ]);
  });
  test('missing font remains Standard and failure is cached', () async {
    final fonts = SubtitleFonts(assets: _MissingFonts());
    expect(await fonts.load(SubtitleFont.serif), isFalse);
    expect(fonts.isReady(SubtitleFont.serif), isFalse);
    expect(await fonts.load(SubtitleFont.serif), isFalse);
  });
}

class _DelayedFonts extends SubtitleFonts {
  final release = Completer<void>();
  final paths = <String>[];
  bool ready = false;
  @override
  bool isReady(SubtitleFont font) => ready;
  @override
  Future<bool> load(SubtitleFont font) async {
    paths.addAll([
      'assets/fonts/subtitles/${font.storageKey}/Regular.ttf',
      'assets/fonts/subtitles/${font.storageKey}/Bold.ttf',
    ]);
    await release.future;
    ready = true;
    return true;
  }
}

class _MissingFonts extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw StateError('fixture missing');
}

class _CountingFonts extends CachingAssetBundle {
  final paths = <String>[];
  @override
  Future<ByteData> load(String key) {
    paths.add(key);
    return rootBundle.load(key);
  }
}
