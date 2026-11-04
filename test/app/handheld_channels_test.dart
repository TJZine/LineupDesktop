import 'dart:ui' show CheckedState, SemanticsAction;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channels_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/lineup_controls.dart';
import 'package:lineup_desktop/ui/handheld_management.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/golden_test_support.dart';
import '../support/handheld_probe.dart';
import '../support/ui_fixture.dart';

const _handheld = DeviceProfile(
  host: TargetPlatform.android,
  formFactor: FormFactor.handheld,
);
const _windows = [
  (Size(412, 915), 2.625),
  (Size(360, 800), 3.0),
  (Size(800, 1280), 2.0),
  (Size(600, 960), 2.0),
  (Size(690, 840), 2.6),
  (Size(960, 600), 2.0),
  (Size(1280, 800), 2.0),
];

Finder _key(String name) => find.byKey(ValueKey(name));
final _directory = find.byKey(const PageStorageKey('channels-directory'));
final _search = _key('channels-search');
final _reorder = _key('channels-reorder-list');
final _moveSearch = _key('channels-move-search');
final _more = find.byTooltip('More channel actions');
final _move = find.byTooltip('Move Documentaries');
final _drag = _key('reorder-drag-channel-1');

void main() {
  for (final (size, dpr) in _windows) {
    for (final scale in [1.0, 1.3, 2.0]) {
      _handheldTest('Channels ${size.width}×${size.height} @$dpr text $scale', (
        tester,
      ) async {
        _window(tester, size, dpr);
        await tester.runAsync(loadPinnedTestFonts);
        final fixture = _DirectoryFixture();
        await fixture.pump(tester, scale);
        final stacked = size.width != 1280 || scale == 2;
        expect(
          find.byType(HandheldPageBar),
          stacked ? findsOneWidget : findsNothing,
        );
        await _imeTap(tester, _search);
        await _dismissIme(tester);
        if (stacked) {
          await tester.enterText(_search, 'Late Night');
          await tester.pumpAndSettle();
          expect(_key('channel-row-channel-1'), findsNothing);
          await _tap(tester, find.byTooltip('Clear search'), touch: true);
          await _dismissIme(tester);
        }
        if (!stacked) {
          await expectHandheldReachable(
            tester,
            find.text('Add a custom channel'),
          );
          await _tap(
            tester,
            find.byTooltip('Actions for Documentaries'),
            touch: true,
          );
          for (final label in ['Duplicate as custom', 'Delete…']) {
            final item = find.ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            );
            await expectHandheldReachable(tester, item, touch: true);
          }
          await _tap(tester, find.text('Delete…'));
          for (final label in ['Cancel', 'Delete channel']) {
            await expectHandheldReachable(
              tester,
              find
                  .ancestor(
                    of: find.text(label).last,
                    matching: find.byType(LineupTouchTarget),
                  )
                  .last,
              touch: true,
            );
          }
          await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
          await _tap(tester, find.text('Reorder channels'));
          await _tap(
            tester,
            find.widgetWithText(TextButton, 'Move to…').first,
            touch: true,
          );
          await expectHandheldReachable(
            tester,
            find.widgetWithText(TextField, 'Search channels'),
          );
          Finder moveAction(String label) => find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(TextButton, label),
          );
          for (final label in ['Before', 'After', 'Cancel']) {
            await expectHandheldReachable(
              tester,
              moveAction(label).first,
              touch: true,
            );
          }
          await _tap(tester, moveAction('Cancel'));
          await expectHandheldReachable(tester, find.text('Cancel'));
          expect(tester.takeException(), isNull);
          return;
        }
        _checkWords(tester);
        await expectHandheldReachable(
          tester,
          find.byTooltip('Add a custom channel'),
          touch: true,
        );
        final first = _key('channel-row-channel-1');
        await _tap(
          tester,
          find.byTooltip('Actions for Documentaries'),
          touch: true,
        );
        expect(find.text('Duplicate as custom'), findsOneWidget);
        await _back(tester);
        await expectHandheldReachable(tester, first);
        await tester.longPress(first);
        await tester.pumpAndSettle();
        expect(find.text('1 selected'), findsOneWidget);
        _checkWords(tester);
        await _tap(
          tester,
          find.text('Select all'),
          touch: true,
          target: find.widgetWithText(TextButton, 'Select all'),
        );
        expect(find.text('3 selected'), findsOneWidget);
        await _tap(tester, find.byTooltip('Delete selected'), touch: true);
        await expectHandheldReachable(
          tester,
          find.ancestor(
            of: find.widgetWithText(FilledButton, 'Delete 3 channels'),
            matching: find.byType(LineupTouchTarget),
          ),
          touch: true,
        );
        await _back(tester);
        await _tap(
          tester,
          find.byTooltip('Cancel selection').last,
          touch: true,
        );
        await _startReorder(tester);
        _checkWords(tester);
        await expectHandheldReachable(tester, _drag, touch: true);
        await _tap(tester, _move, touch: true);
        await _tap(tester, find.text('Move down'));
        final semantics = tester.ensureSemantics();
        expect(
          find.bySemanticsLabel('Channel 1, will become 2'),
          findsOneWidget,
        );
        semantics.dispose();
        await expectHandheldReachable(
          tester,
          find.widgetWithText(FilledButton, 'Save'),
          touch: true,
        );
        await _tap(tester, _move, touch: true);
        await _tap(tester, find.text('Move to…'));
        _checkWords(tester);
        await _imeTap(tester, _moveSearch);
        await _tap(
          tester,
          find.widgetWithText(TextButton, 'Cancel'),
          touch: true,
        );
        await _dismissIme(tester);
        expect(_moveSearch, findsNothing);
        expect(_reorder, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  _handheldTest('selection row exposes one labeled checked action', (
    tester,
  ) async {
    _window(tester, const Size(412, 915), 2.625);
    final semantics = tester.ensureSemantics();
    try {
      await _DirectoryFixture().pump(tester, 1);
      final row = _key('channel-row-channel-1');
      await tester.longPress(row);
      await tester.pumpAndSettle();
      final node = tester.getSemantics(row);
      expect(node.label, contains('Documentaries'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      final childActions = <SemanticsNode>[];
      void inspect(SemanticsNode parent) {
        parent.visitChildren((child) {
          if (child.getSemanticsData().hasAction(SemanticsAction.tap)) {
            childActions.add(child);
          }
          inspect(child);
          return true;
        });
      }

      inspect(node);
      expect(childActions, isEmpty);
      expect(
        node.getSemanticsData().flagsCollection.isChecked,
        CheckedState.isTrue,
      );
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(row).getSemanticsData().flagsCollection.isChecked,
        CheckedState.isFalse,
      );
    } finally {
      semantics.dispose();
    }
  });

  for (final scale in [1.0, 1.3]) {
    for (final keyboard in [200.0, 300.0]) {
      _handheldTest('short Move sheet at text $scale with $keyboard dp IME', (
        tester,
      ) async {
        _window(tester, const Size(915, 412), 2.625);
        await tester.runAsync(loadPinnedTestFonts);
        await _DirectoryFixture().pump(tester, scale);
        await _startReorder(tester);
        await _tap(tester, _move);
        await _tap(tester, find.text('Move to…'));
        tester.view.viewInsets = FakeViewPadding(
          bottom: keyboard * tester.view.devicePixelRatio,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expectHandheldTarget(tester, _moveSearch);
        final cancel = find.widgetWithText(TextButton, 'Cancel');
        expectHandheldTarget(tester, cancel, touch: true);
        expect(
          tester.getCenter(cancel).dy,
          closeTo(tester.getCenter(_moveSearch).dy, 1),
        );
        expect(
          find.text('Late Night News', findRichText: true).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(_moveSearch);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: _moveSearch,
                  matching: find.byType(EditableText),
                ),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(_moveSearch, findsNothing);
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
      });
    }
  }

  _handheldTest(
    'touch drag, Move up/down/to and confirmed delete reach the controller',
    (tester) async {
      _window(tester, const Size(412, 915), 2.625);
      await tester.runAsync(loadPinnedTestFonts);
      final fixture = _DirectoryFixture();
      await fixture.pump(tester, 1);
      await _startReorder(tester);
      await expectHandheldReachable(tester, _drag);
      final third = _key('reorder-channel-3');
      final gesture = await tester.startGesture(
        tester.getCenter(_drag),
        kind: PointerDeviceKind.touch,
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(
        Offset(tester.getCenter(_drag).dx, tester.getBottomLeft(third).dy + 65),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(_key('reorder-channel-1')).dy,
        greaterThan(tester.getTopLeft(third).dy),
      );
      await _tap(tester, _move);
      await _tap(tester, find.text('Move up'));
      expect(
        tester.getTopLeft(_key('reorder-channel-1')).dy,
        lessThan(tester.getTopLeft(third).dy),
      );
      await _tap(tester, _move);
      await _tap(tester, find.text('Move down'));
      expect(
        tester.getTopLeft(_key('reorder-channel-1')).dy,
        greaterThan(tester.getTopLeft(third).dy),
      );
      await _tap(tester, _move);
      await _tap(tester, find.text('Move to…'));
      await _imeTap(tester, _moveSearch);
      await tester.enterText(_moveSearch, 'Late Night');
      await _dismissIme(tester);
      await _tap(tester, find.text('Move after'));
      await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(fixture.controller.channels.map((channel) => channel.id), [
        'channel-2',
        'channel-1',
        'channel-3',
      ]);
      expect(fixture.controller.channels.map((channel) => channel.number), [
        1,
        2,
        3,
      ]);

      await _startReorder(tester);
      await _tap(tester, _move);
      await _tap(tester, find.text('Move to…'));
      await tester.enterText(_moveSearch, 'Late Night');
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Move before'));
      await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(fixture.controller.channels.map((channel) => channel.id), [
        'channel-1',
        'channel-2',
        'channel-3',
      ]);

      await tester.longPress(_key('channel-row-channel-1'));
      await tester.pumpAndSettle();
      await _tap(tester, find.widgetWithText(TextButton, 'Select all'));
      await _tap(tester, find.byTooltip('Delete selected'));
      expect(fixture.controller.channels, hasLength(3));
      await _tap(
        tester,
        find.widgetWithText(FilledButton, 'Delete 3 channels'),
      );
      expect(fixture.controller.channels, isEmpty);
      expect(find.text('Build your first channel'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _handheldTest('Back closes Channels sheets, then mode, then tab', (
    tester,
  ) async {
    _window(tester, const Size(412, 915), 2.625);
    await tester.runAsync(loadPinnedTestFonts);
    final fixture = UiFixture(profile: _handheld, scenario: _scenario(3));
    addTearDown(fixture.controller.dispose);
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Channels'));
    await _imeTap(tester, _search);
    await _dismissIme(tester);
    await _tap(tester, _more);
    await _back(tester);
    expect(find.text('Select channels'), findsNothing);
    await tester.longPress(_key('channel-row-channel-1'));
    await tester.pumpAndSettle();
    final selectedChip = find.byWidgetPredicate(
      (widget) => widget is HandheldFilterChip && widget.label == 'Selected 1',
    );
    await _tap(tester, selectedChip);
    expect(_key('channel-row-channel-2'), findsNothing);
    await _back(tester);
    expect(find.text('1 selected'), findsNothing);
    await _startReorder(tester);
    await _tap(tester, _move);
    await _tap(tester, find.text('Move to…'));
    await _imeTap(tester, _moveSearch);
    await _dismissIme(tester);
    await _back(tester);
    expect(_moveSearch, findsNothing);
    expect(_reorder, findsOneWidget);
    await _back(tester);
    expect(_reorder, findsNothing);
    expect(_search, findsOneWidget);
    await _back(tester);
    expect(_search, findsNothing);
    expect(tester.takeException(), isNull);
  });

  _handheldTest('directory restores its anchor after a resize in Studio', (
    tester,
  ) async {
    _window(tester, const Size(360, 800), 2);
    await tester.runAsync(loadPinnedTestFonts);
    await _DirectoryFixture(count: 70).pump(tester, 1);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: _directory, matching: find.byType(Scrollable)),
        )
        .position;
    position.jumpTo(2400);
    await tester.pumpAndSettle();
    final anchor = _topRow(tester, _directory, 'channel-row-');
    final next = _key(
      'channel-row-channel-${int.parse(anchor.split('-').last) + 1}',
    );
    await tester.tap(next);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(800, 360) * 2;
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Back to Channels').last);
    expect(_topRow(tester, _directory, 'channel-row-'), anchor);
  });

  _handheldTest('Wide directory separator anchors the next row', (
    tester,
  ) async {
    _window(tester, const Size(1280, 800), 2);
    await tester.runAsync(loadPinnedTestFonts);
    final fixture = _DirectoryFixture(count: 70);
    await fixture.pump(tester, 1);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: _directory, matching: find.byType(Scrollable)),
        )
        .position;
    final row = tester.renderObject<RenderBox>(_key('channel-row-channel-4'));
    final start = RenderAbstractViewport.of(row)
        .getOffsetToReveal(row, 0)
        .offset;
    position.jumpTo(start + row.size.height + .5);
    await tester.pumpAndSettle();
    expect(
      _topRow(tester, _directory, 'channel-row-'),
      'channel-row-channel-5',
    );
    await fixture.pump(tester, 2);
    expect(
      _topRow(tester, _directory, 'channel-row-'),
      'channel-row-channel-5',
    );
  });

  _handheldTest('selection, filter, search, reorder and anchor survive B0', (
    tester,
  ) async {
    _window(tester, const Size(1280, 800), 2);
    await tester.runAsync(loadPinnedTestFonts);
    final fixture = _DirectoryFixture(count: 70);
    await fixture.pump(tester, 1);
    await tester.enterText(_search, 'Channel');
    await _dismissIme(tester);
    await _tap(
      tester,
      find.descendant(
        of: find.byWidgetPredicate((w) => w is LineupSegmentedControl),
        matching: find.text('Custom'),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.drag(_directory, const Offset(0, -270));
      await tester.pumpAndSettle();
    }
    final anchor = _topRow(tester, _directory, 'channel-row-');
    expect(anchor, isNot('channel-row-channel-4'));
    await fixture.pump(tester, 2);
    expect(_topRow(tester, _directory, 'channel-row-'), anchor);
    expect(tester.widget<TextField>(_search).controller!.text, 'Channel');
    expect(
      tester
          .widget<HandheldFilterChip>(
            find.byWidgetPredicate(
              (w) => w is HandheldFilterChip && w.label == 'Custom',
            ),
          )
          .selected,
      isTrue,
    );
    await tester.longPress(_key(anchor).hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    tester.view.physicalSize = const Size(800, 1280) * 2;
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(_topRow(tester, _directory, 'channel-row-'), anchor);
    tester.view.physicalSize = const Size(1280, 800) * 2;
    await fixture.pump(tester, 1);
    expect(find.text('Delete selected'), findsOneWidget);
    expect(_topRow(tester, _directory, 'channel-row-'), anchor);
    await _tap(tester, find.text('Cancel'));
    await fixture.pump(tester, 2);
    await _startReorder(tester);
    final firstMove = find.byTooltip('Move Documentaries');
    await tester.scrollUntilVisible(
      firstMove,
      -200,
      scrollable: find.descendant(
        of: _reorder,
        matching: find.byType(Scrollable),
      ),
    );
    await _tap(tester, firstMove);
    await _tap(tester, find.text('Move down'));
    for (var i = 0; i < 4; i++) {
      await tester.dragFrom(
        tester.getCenter(_reorder) - const Offset(100, 0),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
    }
    final reorderAnchor = _topRow(tester, _reorder, 'reorder-channel-');
    expect(reorderAnchor, isNot('reorder-channel-1'));
    await fixture.pump(tester, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save order'))
          .onPressed,
      isNotNull,
    );
    expect(_topRow(tester, _reorder, 'reorder-channel-'), reorderAnchor);
    await fixture.pump(tester, 2);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNotNull,
    );
    expect(_topRow(tester, _reorder, 'reorder-channel-'), reorderAnchor);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _startReorder(WidgetTester tester) async {
  await _tap(tester, _more, touch: true);
  await _tap(tester, find.text('Reorder channels'));
  expect(_reorder, findsOneWidget);
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> _dismissIme(WidgetTester tester) async {
  tester.view.resetViewInsets();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void _handheldTest(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void _window(WidgetTester tester, Size size, double dpr) {
  tester.view
    ..devicePixelRatio = dpr
    ..physicalSize = size * dpr;
  addTearDown(tester.view.reset);
}

Widget _host(double scale, Widget child) => MaterialApp(
  theme: LineupTheme.forName(
    LineupThemeName.emberSteel,
    formFactor: _handheld.formFactor,
  ),
  builder: (context, navigator) => DeviceProfileScope(
    profile: _handheld,
    child: MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: LineupCanvas(child: navigator!),
    ),
  ),
  home: child,
);

Future<void> _tap(
  WidgetTester tester,
  Finder control, {
  bool touch = false,
  Finder? target,
}) async {
  await expectHandheldReachable(tester, target ?? control, touch: touch);
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _imeTap(WidgetTester tester, Finder field) async {
  tester.view.viewInsets = FakeViewPadding(
    bottom: 300 * tester.view.devicePixelRatio,
  );
  await tester.pumpAndSettle();
  await expectHandheldReachable(tester, field);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.tapAt(tester.getCenter(field));
  await tester.pumpAndSettle();
  final editable = tester.widget<EditableText>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  expect(editable.focusNode.hasFocus, isTrue);
}

void _checkWords(WidgetTester tester) {
  final controls = [
    _key('handheld-page-bar-title'),
    for (final prefix in ['channel-row-', 'reorder-'])
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith(prefix);
      }),
  ];
  expectHandheldWords([
    for (final control in controls)
      ...tester.renderObjectList<RenderParagraph>(
        find.descendant(of: control, matching: find.byType(RichText)),
      ),
  ]);
}

String _topRow(WidgetTester tester, Finder list, String prefix) {
  final viewport = tester.getRect(list);
  final rows = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith(prefix);
  });
  final visible =
      [
        for (final element in rows.evaluate())
          if (tester.getRect(find.byWidget(element.widget)).bottom >
              viewport.top + 1)
            element,
      ]..sort(
        (a, b) => tester
            .getTopLeft(find.byWidget(a.widget))
            .dy
            .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
      );
  return (visible.first.widget.key! as ValueKey<String>).value;
}

LineupScenario _scenario(int count) => LineupScenario(
  stage: SetupStage.ready,
  settings: const LineupSettings(reduceMotion: true),
  channels: [
    for (var number = 1; number <= count; number++)
      Channel(
        id: 'channel-$number',
        number: number,
        name: switch (number) {
          1 => 'Documentaries',
          2 => 'Late Night News',
          3 => 'Weihnachtsfilmklassiker',
          _ => 'Channel $number',
        },
        source: ManualSource([
          ChannelItem(
            id: 'program-$number',
            title: 'Test program $number',
            duration: const Duration(minutes: 30),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.utc(2026),
        shuffleSeed: number,
        builderKey: number == 1 || number == 3 ? 'generated-$number' : null,
      ),
  ],
);

class _DirectoryFixture {
  _DirectoryFixture({int count = 3})
    : controller = FixtureController(scenario: _scenario(count)) {
    DateTime clock() => DateTime.utc(2026, 11, 3, 12);
    final guide = GuideController(lineup: controller, clock: clock);
    player = PlayerCoordinator(
      player: FixturePlayer(),
      lineup: controller,
      guide: guide,
      clock: clock,
    );
    addTearDown(guide.dispose);
    addTearDown(controller.dispose);
    addTearDown(player.dispose);
    addTearDown(menuFocus.dispose);
  }

  final FixtureController controller;
  final menuFocus = FocusNode();
  late final PlayerCoordinator player;

  Future<void> pump(WidgetTester tester, double scale) async {
    await tester.pumpWidget(
      _host(
        scale,
        Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => ChannelsView(
              controller: controller,
              player: player,
              onOpenPlayer: () {},
              onOpenMenu: (_, _) {},
              menuFocusNode: menuFocus,
              showNavigationMenu: !LineupCanvas.usesPortraitCompositionOf(
                context,
              ),
              onBack: LineupCanvas.usesPortraitCompositionOf(context)
                  ? null
                  : () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}
