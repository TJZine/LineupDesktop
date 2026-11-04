import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/platform/device_profile.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/handheld_management.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../../test/support/golden_test_support.dart';

const _handheld = DeviceProfile(
  host: TargetPlatform.android,
  formFactor: FormFactor.handheld,
);
const _desktop = DeviceProfile(
  host: TargetPlatform.macOS,
  formFactor: FormFactor.desktop,
);
const _tv = DeviceProfile(
  host: TargetPlatform.android,
  formFactor: FormFactor.tv,
);

void main() {
  setUpAll(loadPinnedTestFonts);

  androidWidgetTest('B0 keeps profile and canvas composition boundaries', (
    tester,
  ) async {
    Future<bool> stacked(
      Size size,
      DeviceProfile profile, {
      double textScale = 1,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      await tester.pumpWidget(
        _app(
          profile: profile,
          textScale: textScale,
          child: Builder(
            builder: (context) => Text(
              handheldStacked(context) ? 'stacked' : 'wide',
              key: const Key('composition'),
            ),
          ),
        ),
      );
      return tester.widget<Text>(find.byKey(const Key('composition'))).data ==
          'stacked';
    }

    addTearDown(tester.view.reset);
    expect(await stacked(const Size(412, 915), _handheld), isTrue);
    expect(await stacked(const Size(960, 600), _handheld), isTrue);
    expect(await stacked(const Size(1280, 800), _handheld), isFalse);
    expect(
      await stacked(const Size(1280, 800), _handheld, textScale: 1.3),
      isFalse,
    );
    expect(
      await stacked(const Size(1280, 800), _handheld, textScale: 1.5),
      isTrue,
    );
    expect(await stacked(const Size(412, 915), _desktop), isFalse);
    expect(await stacked(const Size(412, 915), _tv), isFalse);
  });

  androidWidgetTest(
    'app-ui geometry keeps the old default and opts into B1 width',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                LineupContentWidth(
                  child: ColoredBox(
                    key: const Key('default-content'),
                    color: Colors.red,
                  ),
                ),
                LineupContentWidth(
                  handheldContent: true,
                  child: ColoredBox(
                    key: const Key('handheld-content'),
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        tester.getRect(find.byKey(const Key('default-content'))).width,
        1104,
      );
      expect(
        tester.getRect(find.byKey(const Key('handheld-content'))).width,
        840,
      );
    },
  );

  androidWidgetTest(
    'action row stacks below 420 cu and stays beside at 420 cu',
    (tester) async {
      Future<void> pumpRow(Size size, double textScale) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        await tester.pumpWidget(
          _app(
            profile: _handheld,
            textScale: textScale,
            child: Scaffold(
              body: HandheldActionRow(
                primary: SizedBox(
                  key: const Key('primary'),
                  child: FilledButton(
                    onPressed: () {},
                    child: const Text('Continue'),
                  ),
                ),
                secondary: SizedBox(
                  key: const Key('secondary'),
                  child: OutlinedButton(
                    onPressed: () {},
                    child: const Text('Back'),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      addTearDown(tester.view.reset);
      await pumpRow(const Size(360, 800), 1);
      final narrowPrimary = tester.getRect(find.byKey(const Key('primary')));
      final narrowSecondary = tester.getRect(
        find.byKey(const Key('secondary')),
      );
      expect(narrowPrimary.top, greaterThan(narrowSecondary.bottom - .01));

      await pumpRow(const Size(800, 1280), 1);
      final widePrimary = tester.getRect(find.byKey(const Key('primary')));
      final wideSecondary = tester.getRect(find.byKey(const Key('secondary')));
      expect(widePrimary.top, closeTo(wideSecondary.top, .01));

      // The corrected fixture exposes the canvas width (888.9 cu), so 2x text
      // still has 444.4 cu and remains beside. The 360px case above is the
      // real <420 cu stacked boundary after canvas conversion.
      await pumpRow(const Size(800, 1280), 2);
      final scaledPrimary = tester.getRect(find.byKey(const Key('primary')));
      final scaledSecondary = tester.getRect(
        find.byKey(const Key('secondary')),
      );
      expect(scaledPrimary.top, closeTo(scaledSecondary.top, .01));
    },
  );

  androidWidgetTest('Setup action bar reads raw View insets and returns', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1
      ..viewInsets = FakeViewPadding.zero;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        profile: _handheld,
        child: Scaffold(
          bottomNavigationBar: HandheldSetupActionBar(
            primary: FilledButton(
              onPressed: () {},
              child: const Text('Continue'),
            ),
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('handheld-setup-action-bar')),
      findsOneWidget,
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('handheld-setup-action-bar')),
      findsNothing,
    );

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(
      find.byKey(const ValueKey('handheld-setup-action-bar')),
      findsOneWidget,
    );
  });

  androidWidgetTest(
    'touch-expanded buttons each expose one tappable semantics node',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final backFocus = FocusNode();
      addTearDown(backFocus.dispose);
      await tester.pumpWidget(
        _app(
          profile: _handheld,
          child: Scaffold(
            body: Column(
              children: [
                HandheldPageBar(
                  title: 'Review',
                  backFocusNode: backFocus,
                  backTooltip: 'Back to configure',
                  onBack: () {},
                ),
                LineupTouchTarget(
                  onPressed: () {},
                  child: IconButton(
                    tooltip: 'Remove item',
                    onPressed: () {},
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      backFocus.requestFocus();
      await tester.pump();
      expect(backFocus.hasPrimaryFocus, isTrue);

      for (final label in ['Back to configure', 'Remove item']) {
        final nodes = find.semantics
            .byPredicate(
              (node) =>
                  !node.isInvisible &&
                  !node.isMergedIntoParent &&
                  (node.label == label ||
                      node.getSemanticsData().tooltip == label),
            )
            .evaluate();
        expect(nodes, hasLength(1), reason: label);
        final node = nodes.single;
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
          reason: label,
        );
        var rect = node.rect;
        for (
          SemanticsNode? current = node;
          current != null;
          current = current.parent
        ) {
          if (current.transform case final transform?) {
            rect = MatrixUtils.transformRect(transform, rect);
          }
        }
        expect(rect.width, greaterThanOrEqualTo(48 - 1e-6), reason: label);
        expect(rect.height, greaterThanOrEqualTo(48 - 1e-6), reason: label);
      }
      semantics.dispose();
    },
  );

  androidWidgetTest(
    'choice sheet and select field activate with selection semantics',
    (tester) async {
      tester.view
        ..physicalSize = const Size(412, 915)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      tester.view.padding = const FakeViewPadding(bottom: 48);
      const longLabel = 'MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM';
      String? picked;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          profile: _handheld,
          child: Scaffold(
            body: Center(
              child: HandheldSelectField<String>(
                key: const Key('select'),
                label: 'Playback mode',
                value: 'auto',
                choices: [
                  HandheldChoice(value: 'auto', label: 'Automatic'),
                  HandheldChoice(
                    value: 'manual',
                    label: 'Manual',
                    detail: 'Choose a fixed mode',
                  ),
                  HandheldChoice(
                    value: 'delete',
                    label: 'Delete channel',
                    destructive: true,
                  ),
                  for (var i = 0; i < 12; i++)
                    HandheldChoice(value: 'extra-$i', label: 'Extra choice $i'),
                  HandheldChoice(value: 'last', label: longLabel),
                ],
                onChanged: (value) => picked = value,
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('select'))).label,
        'Playback mode, Automatic',
      );

      await tester.tap(find.byKey(const Key('select')));
      await tester.pumpAndSettle();
      expect(find.text('Playback mode'), findsOneWidget);
      expect(find.text('Automatic').last, findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Manual').last).label,
        contains('Choose a fixed mode'),
      );

      final sheet = find.byType(HandheldChoiceSheet<String>);
      final list = find.descendant(of: sheet, matching: find.byType(ListView));
      tester.view.physicalSize = const Size(412, 480);
      await tester.pumpAndSettle();
      final sheetBox = tester.renderObject<RenderBox>(sheet);
      final sheetRect = MatrixUtils.transformRect(
        sheetBox.getTransformTo(null),
        Offset.zero & sheetBox.size,
      );
      final height = 480 - sheetRect.top;
      await tester.drag(list, const Offset(0, -2000));
      await tester.pumpAndSettle();
      final target = find.descendant(
        of: sheet,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == longLabel &&
              widget.properties.onTap != null,
        ),
      );
      final targetRect = tester.getRect(target);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: target, matching: find.byType(RichText)),
      );
      final visible = paragraph.text.toPlainText();
      expect(targetRect.bottom, lessThanOrEqualTo(480 - 48));
      expect(targetRect.center.dy, lessThan(480 - 48));

      expect(height, lessThanOrEqualTo(480 * .9));
      expect(visible, endsWith('…'));
      await tester.tapAt(targetRect.center);
      await tester.pumpAndSettle();
      expect(picked, 'last');

      await tester.tap(find.byKey(const Key('select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manual').last);
      await tester.pumpAndSettle();
      expect(picked, 'manual');
      expect(find.text('Playback mode'), findsNothing);
      semantics.dispose();
    },
  );

  androidWidgetTest(
    'page bar, filters, rows and choices keep 48dp targets at scale .8',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1280, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          profile: _handheld,
          canvas: true,
          child: Scaffold(
            body: Column(
              children: [
                HandheldPageBar(
                  title: 'Channels',
                  onBack: () {},
                  backTooltip: 'Back to configure',
                ),
                HandheldFilterChip(
                  key: const Key('filter'),
                  label: 'All',
                  selected: true,
                  onSelected: () {},
                  section: 1,
                ),
                HandheldStackedRow(
                  number: 42,
                  next: 43,
                  name: 'Channel Name',
                  facts: 'Source · Playback · Generated',
                  trailing: IconButton(
                    onPressed: () {},
                    tooltip: 'More',
                    icon: const Icon(Icons.more_vert),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final back = tester.getRect(
        find.ancestor(
          of: find.byTooltip('Back to configure'),
          matching: find.byType(LineupTouchTarget),
        ),
      );
      expect(back.width, greaterThanOrEqualTo(48));
      expect(back.height, greaterThanOrEqualTo(48));
      final filter = tester.getRect(find.byKey(const Key('filter')));
      expect(filter.width, greaterThanOrEqualTo(48));
      expect(filter.height, greaterThanOrEqualTo(48));
      final row = tester.getRect(find.byType(HandheldStackedRow));
      expect(row.height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(find.byType(HandheldNumberBlock)).label,
        'Channel 42, will become 43',
      );
    },
  );

  androidWidgetTest(
    'page bar and number block clamp only their named text roles',
    (tester) async {
      tester.view
        ..physicalSize = const Size(360, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          profile: _handheld,
          textScaler: const TextScaler.linear(2),
          child: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  key: const Key('bar'),
                  child: const HandheldPageBar(
                    title: 'Midsummer Television Guide',
                    subtitle: 'Three sections',
                  ),
                ),
                const HandheldNumberBlock(1000, next: 43),
                const Text('body text reflows at two'),
              ],
            ),
          ),
        ),
      );
      final titleParagraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(const ValueKey('handheld-page-bar-title')),
          matching: find.byType(RichText),
        ),
      );
      final title = titleParagraph.text.toPlainText();
      final titleBoxes = titleParagraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: title.length),
      );
      expect(titleBoxes, isNotEmpty);
      expect(
        titleBoxes.map((box) => box.top).toSet(),
        hasLength(greaterThanOrEqualTo(2)),
      );
      for (final match in RegExp(r'\S+').allMatches(title)) {
        final wordBoxes = titleParagraph.getBoxesForSelection(
          TextSelection(baseOffset: match.start, extentOffset: match.end),
        );
        // A two-line page-bar title may ellipsize words after the visible
        // range. Geometry assertions apply to the rendered words only.
        if (wordBoxes.isEmpty) continue;
        expect(
          wordBoxes.map((box) => box.top).toSet(),
          hasLength(1),
          reason: 'word split across lines: ${match.group(0)}',
        );
      }
      expect(
        titleParagraph.textScaler.scale(titleParagraph.text.style!.fontSize!),
        lessThanOrEqualTo(1.3 * titleParagraph.text.style!.fontSize! + .01),
      );
      final number = tester.renderObject<RenderParagraph>(find.text('1000'));
      final digits = [
        for (var index = 0; index < 4; index++)
          ...number.getBoxesForSelection(
            TextSelection(baseOffset: index, extentOffset: index + 1),
          ),
      ];
      expect(digits, hasLength(4));
      expect(digits.map((box) => box.top).toSet(), hasLength(1));
      expect(digits.last.right, lessThanOrEqualTo(62.01));
      expect(
        number.textScaler.scale(number.text.style!.fontSize!),
        lessThanOrEqualTo(1.3 * number.text.style!.fontSize! + .01),
      );

      expect(tester.takeException(), isNull);
    },
  );

  androidWidgetTest(
    'B3 row words stay on one glyph line across large text modes',
    (tester) async {
      addTearDown(tester.view.reset);
      const names = [
        'Documentaries',
        'Late Night News',
        'Weihnachtsfilmklassiker',
      ];
      const modes = ['normal', 'selection', 'reorder'];
      const scales = [1.0, 1.3, 2.0];
      const sizes = [Size(360, 800), Size(412, 915)];

      for (final size in sizes) {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        for (final scale in scales) {
          final keys = <String, Key>{};
          await tester.pumpWidget(
            _app(
              profile: _handheld,
              textScale: scale,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final mode in modes)
                        for (final name in names)
                          Builder(
                            builder: (context) {
                              final id = '$mode-$name';
                              final key = ValueKey('b3-probe-$id');
                              keys[id] = key;
                              return HandheldStackedRow(
                                key: key,
                                number: 42,
                                next: mode == 'reorder' ? 43 : null,
                                name: name,
                                facts: mode == 'reorder'
                                    ? ''
                                    : 'Source · Playback · Generated',
                                leading: mode == 'selection'
                                    ? Checkbox(value: false, onChanged: (_) {})
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: () {},
                                      icon: const Icon(Icons.more_vert),
                                    ),
                                    if (mode == 'reorder')
                                      const SizedBox.square(
                                        dimension: 56,
                                        child: Icon(Icons.drag_handle),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          for (final entry in keys.entries) {
            final paragraphs = find
                .descendant(
                  of: find.byKey(entry.value),
                  matching: find.byType(RichText),
                )
                .evaluate()
                .map((element) => element.renderObject)
                .whereType<RenderParagraph>();
            for (final paragraph in paragraphs) {
              final paragraphText = paragraph.text.toPlainText();
              for (final match in RegExp(r'\S+').allMatches(paragraphText)) {
                final word = match.group(0)!;
                if (word.length < 2) continue;
                final boxes = paragraph.getBoxesForSelection(
                  TextSelection(
                    baseOffset: match.start,
                    extentOffset: match.end,
                  ),
                );
                expect(boxes, isNotEmpty, reason: '${entry.key}: $word');
                expect(
                  boxes.map((box) => box.top.round()).toSet(),
                  hasLength(1),
                  reason: '${entry.key}: $word split across lines',
                );
              }
            }
          }

          final representativeKey = keys['normal-Documentaries']!;
          final nameParagraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.byKey(representativeKey),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is RichText &&
                    widget.text.toPlainText() == 'Documentaries',
              ),
            ),
          );
          final numberRect = tester.getRect(
            find.descendant(
              of: find.byKey(representativeKey),
              matching: find.byType(HandheldNumberBlock),
            ),
          );
          final nameRect = tester.getRect(
            find.descendant(
              of: find.byKey(representativeKey),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is RichText &&
                    widget.text.toPlainText() == 'Documentaries',
              ),
            ),
          );
          expect(nameParagraph.text.toPlainText(), 'Documentaries');
          if (scale == 1.3) {
            expect(nameRect.top, lessThan(numberRect.bottom));
            expect(nameRect.left, greaterThan(numberRect.right - .01));
          }
          if (scale == 2.0) {
            expect(nameRect.top, greaterThanOrEqualTo(numberRect.bottom - .01));
            expect(nameRect.left, closeTo(numberRect.left, .01));
          }
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}

void androidWidgetTest(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Widget _app({
  required DeviceProfile profile,
  required Widget child,
  double textScale = 1,
  TextScaler? textScaler,
  bool canvas = true,
}) => DeviceProfileScope(
  profile: profile,
  child: MaterialApp(
    theme: LineupTheme.forName(
      LineupThemeName.emberSteel,
      formFactor: profile.formFactor,
    ),
    builder: (context, route) {
      final media = MediaQuery.of(context)
          .copyWith(textScaler: textScaler ?? TextScaler.linear(textScale));
      final contents = canvas ? LineupCanvas(child: route!) : route!;
      return MediaQuery(data: media, child: contents);
    },
    home: child,
  ),
);
