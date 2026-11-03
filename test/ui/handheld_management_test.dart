import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/platform/device_profile.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/handheld_management.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

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
  testWidgets('B0 keeps profile and canvas composition boundaries', (
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
      await stacked(const Size(1280, 800), _handheld, textScale: 1.5),
      isTrue,
    );
    expect(await stacked(const Size(412, 915), _desktop), isFalse);
    expect(await stacked(const Size(412, 915), _tv), isFalse);
  });

  testWidgets('app-ui geometry keeps the old default and opts into B1 width', (
    tester,
  ) async {
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
  });

  testWidgets('action row stacks below 420 cu and stays beside at 420 cu', (
    tester,
  ) async {
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
    final narrowSecondary = tester.getRect(find.byKey(const Key('secondary')));
    expect(narrowPrimary.top, greaterThan(narrowSecondary.bottom - .01));

    await pumpRow(const Size(800, 1280), 1);
    final widePrimary = tester.getRect(find.byKey(const Key('primary')));
    final wideSecondary = tester.getRect(find.byKey(const Key('secondary')));
    expect(widePrimary.top, closeTo(wideSecondary.top, .01));

    await pumpRow(const Size(800, 1280), 2);
    final scaledPrimary = tester.getRect(find.byKey(const Key('primary')));
    final scaledSecondary = tester.getRect(find.byKey(const Key('secondary')));
    expect(scaledPrimary.top, greaterThan(scaledSecondary.bottom - .01));
  });

  testWidgets('Setup action bar reads raw View insets and returns', (
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

  testWidgets(
    'choice sheet and select field activate with selection semantics',
    (tester) async {
      tester.view
        ..physicalSize = const Size(412, 915)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
                choices: const [
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

      await tester.tap(find.text('Manual').last);
      await tester.pumpAndSettle();
      expect(picked, 'manual');
      expect(find.text('Playback mode'), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
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

  testWidgets('page bar and number block clamp only their named text roles', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        profile: _handheld,
        textScale: 2,
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
              const HandheldNumberBlock(42, next: 43),
              const Text('body text reflows at two'),
            ],
          ),
        ),
      ),
    );
    final titleParagraphs = <RenderParagraph>[];
    for (final element
        in find
            .descendant(
              of: find.byKey(const Key('bar')),
              matching: find.byType(Text),
            )
            .evaluate()) {
      final renderObject = element.renderObject;
      if (renderObject is RenderParagraph) titleParagraphs.add(renderObject);
    }
    expect(titleParagraphs, isNotEmpty);
    for (final paragraph in titleParagraphs) {
      expect(
        paragraph.textScaler.scale(paragraph.text.style!.fontSize!),
        lessThanOrEqualTo(1.3 * paragraph.text.style!.fontSize! + .01),
      );
    }
    final number = tester.renderObject<RenderParagraph>(find.text('42'));
    expect(
      number.textScaler.scale(number.text.style!.fontSize!),
      lessThanOrEqualTo(1.3 * number.text.style!.fontSize! + .01),
    );

    final titleLines = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('bar')),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    final titleOnly = titleLines.sublist(0, titleLines.length - 1);
    expect(titleLines, isNotEmpty);
    const words = {'Midsummer', 'Television', 'Guide'};
    expect(
      titleOnly.every(
        (line) => line
            .replaceAll('…', '')
            .split(RegExp(r'\s+'))
            .every(words.contains),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _app({
  required DeviceProfile profile,
  required Widget child,
  double textScale = 1,
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
          .copyWith(textScaler: TextScaler.linear(textScale));
      final contents = MediaQuery(data: media, child: route!);
      return canvas ? LineupCanvas(child: contents) : contents;
    },
    home: child,
  ),
);
