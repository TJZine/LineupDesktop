import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart'
    show LineupScenario, SetupStage;
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/golden_test_support.dart';
import '../support/handheld_probe.dart';
import '../support/ui_fixture.dart';

const _handheld = DeviceProfile(
  host: TargetPlatform.android,
  formFactor: FormFactor.handheld,
);
const _scheduleKey = Key('guide-schedule-list');
const _nowLineKey = Key('guide-now-line');
const _sheetKey = Key('handheld-program-sheet');
const _watchKey = Key('handheld-program-watch');
const _searchKey = Key('guide-channel-search');
const _activePillKey = Key('handheld-guide-active-pill');
final _origin = DateTime(2026, 1, 15, 9);

const _configs = [
  (Size(412, 915), 2.625),
  (Size(360, 800), 3.0),
  (Size(800, 1280), 2.0),
  (Size(600, 960), 2.0),
  (Size(690, 840), 2.6),
  (Size(960, 600), 2.0),
  (Size(1280, 800), 2.0),
];

const _programs = [
  ChannelItem(
    id: 'first',
    title: 'First episode',
    showTitle: 'Morning Cinema',
    duration: Duration(minutes: 30),
  ),
  ChannelItem(
    id: 'second',
    title: 'Documentary and Discovery',
    duration: Duration(minutes: 30),
    summary: 'A synthetic story for exercising the Guide details sheet.',
  ),
  ChannelItem(
    id: 'third',
    title: 'Midday Cinema',
    duration: Duration(minutes: 30),
  ),
];

void main() {
  setUpAll(loadPinnedTestFonts);

  for (final (size, dpr) in _configs) {
    for (final text in [1.0, 1.3, 2.0]) {
      _testGuideWidgets(
        'Handheld Guide reaches controls at $size @$dpr text $text',
        (tester) async {
          _configure(tester, size, dpr, text);
          final fixture = _GuideFixture();
          await fixture.mount(tester, picture: true);
          expect(tester.takeException(), isNull);

          if (!LineupCanvas.usesPortraitCompositionFor(
            size,
            formFactor: FormFactor.handheld,
          )) {
            expect(find.byTooltip('Filter by library'), findsNothing);
            final now = find.byKey(const Key('guide-now'));
            expect(now.hitTestable(), findsOneWidget);
            await tester.tap(now);
            await tester.pumpAndSettle();
            expect(fixture.guide.windowStart, _origin);
            await fixture.unmount(tester);
            return;
          }

          final filter = find.byTooltip('Filter by library');
          final search = find.byTooltip('Search channels');
          final tile = _tile(0);
          final onNow = _card('Morning Cinema, channel 1.');
          final later = _card('Documentary and Discovery, channel 1.');
          final picture = find.byKey(const Key('guide-picture-in-picture'));
          for (final (control, label) in [
            (filter, 'Filter by library'),
            (search, 'Search channels'),
            (tile, 'Channel 1, Documentary Stories. Watch.'),
            (onNow, 'Morning Cinema, channel 1. On now, 17m left. Watch.'),
            (
              later,
              'Documentary and Discovery, channel 1. Starts 9:30 AM. Details.',
            ),
            (picture, 'Now playing picture in picture. Open full player.'),
          ]) {
            _expectTapTarget(tester, control, size, expectedLabel: label);
          }
          final expectedScale = LineupCanvas.scaleFor(
            size,
            formFactor: FormFactor.handheld,
          );
          expect(
            tester.getSize(picture).width * expectedScale,
            closeTo(size.width, .01),
          );
          expect(tester.getSize(picture).aspectRatio, closeTo(16 / 9, .001));
          expect(
            tester.getSize(tile).width,
            size.shortestSide < 600 ? 100 : 120,
          );

          final tileText = find.descendant(
            of: tile,
            matching: find.text('Documentary Stories', findRichText: true),
          );
          expectHandheldWords([tester.renderObject<RenderParagraph>(tileText)]);

          await tester.tap(later);
          await tester.pumpAndSettle();
          expect(find.byKey(_sheetKey), findsOneWidget);
          if (size == const Size(800, 1280)) {
            final sheet = _windowRect(tester, find.byKey(_sheetKey));
            expect(sheet.width, lessThanOrEqualTo(640));
            expect(sheet.center.dx, closeTo(size.width / 2, .01));
          }
          expectHandheldWords([
            tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.byKey(_sheetKey),
                matching: find.text(
                  'Documentary and Discovery',
                  findRichText: true,
                ),
              ),
            ),
          ]);
          await tester.ensureVisible(find.byKey(_watchKey));
          await tester.pumpAndSettle();
          _expectTapTarget(
            tester,
            find.byKey(_watchKey),
            size,
            expectedLabel: 'Watch channel 1',
          );

          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byKey(_sheetKey), findsNothing);

          await tester.tap(search);
          await tester.pumpAndSettle();
          tester.view.viewInsets = FakeViewPadding(bottom: 300 * dpr);
          await tester.pumpAndSettle();
          final field = find.byKey(_searchKey);
          final fieldRect = _windowRect(tester, field);
          expect(fieldRect.bottom, lessThanOrEqualTo(size.height - 300 + .1));
          expect(field.hitTestable(), findsOneWidget);
          await tester.enterText(field, 'Documentary');
          await tester.pumpAndSettle();
          final clear = find.byTooltip('Clear search');
          _expectTapTarget(
            tester,
            clear,
            size,
            bottomInset: 300,
            expectedLabel: 'Clear search',
          );
          tester.view.resetViewInsets();
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          expect(field, findsNothing);
          final activeSearch = find.byTooltip('Search channels: Documentary');
          _expectActivePill(
            tester,
            activeSearch,
            size,
            'Search channels: Documentary',
          );
          final fullRoundTrip =
              size == const Size(360, 800) && dpr == 3.0 && text == 2.0;
          if (fullRoundTrip) {
            await tester.tap(activeSearch);
            await tester.pumpAndSettle();
            await tester.tap(clear);
            await tester.pumpAndSettle();
            expect(fixture.guide.searchQuery, isEmpty);
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            expect(field, findsNothing);
            expect(search, findsOneWidget);

            await tester.tap(filter);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Cinema library'));
            await tester.pumpAndSettle();
            expect(fixture.guide.libraryFilterId, 'cinema');
            final activeFilter = find.byTooltip(
              'Filter by library: Cinema library',
            );
            _expectActivePill(
              tester,
              activeFilter,
              size,
              'Filter by library: Cinema library',
            );
            await tester.tap(activeFilter);
            await tester.pumpAndSettle();
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            expect(fixture.guide.libraryFilterId, 'cinema');
            await tester.tap(activeFilter);
            await tester.pumpAndSettle();
            await tester.tap(find.text('All libraries'));
            await tester.pumpAndSettle();
            expect(fixture.guide.libraryFilterId, isNull);
          }
          expect(tester.takeException(), isNull);
          await fixture.unmount(tester);
        },
      );
    }
  }

  _testGuideWidgets('Guide program sheet follows a live height cap', (
    tester,
  ) async {
    _configure(tester, const Size(800, 1280), 2, 1);
    final fixture = _GuideFixture();
    await fixture.mount(tester);

    await tester.tap(_card('Documentary and Discovery, channel 1.'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(_sheetKey);
    expect(sheet, findsOneWidget);
    expect(
      _windowRect(tester, sheet).height,
      lessThanOrEqualTo(1280 * .9 + .1),
    );

    tester.view.physicalSize = const Size(800, 360) * 2;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_windowRect(tester, sheet).height, lessThanOrEqualTo(360 * .9 + .1));

    await fixture.unmount(tester);
  });

  _testGuideWidgets('Shell exposes only the pinned picture as its tap target', (
    tester,
  ) async {
    const size = Size(412, 915);
    _configure(tester, size, 2.625, 1);
    final fixture = _GuideFixture(channelCount: 4);
    final player = FixturePlayer.preloaded()
      ..emit(
        const PlayerStatus(state: PlayerState.ready, message: 'Synthetic'),
      );
    final app = UiFixture(
      profile: _handheld,
      controller: fixture.lineup,
      guideClock: () => fixture.now,
      player: player,
    );
    await tester.pumpWidget(app.build());
    await tester.pumpAndSettle();
    final picture = find.byKey(const Key('guide-picture-in-picture'));
    const label = 'Now playing picture in picture. Open full player.';
    _expectTapTarget(tester, picture, size, expectedLabel: label);
    final node = find.semantics
        .byPredicate((node) => node.label == label)
        .evaluate()
        .single;
    expect(node.rect.size, tester.getSize(picture));
    await fixture.unmount(tester);
  });

  _testGuideWidgets('Guide uses measured threshold for pinned thumbnail', (
    tester,
  ) async {
    const dpr = 3.0;
    _configure(tester, const Size(800, 1280), dpr, 1);
    final fixture = _GuideFixture();
    await fixture.mount(tester, picture: true);
    final picture = find.byKey(const Key('guide-picture-in-picture'));
    final strip = find.byKey(const Key('handheld-guide-now-strip'));
    final schedule = find.byKey(_scheduleKey);
    final originalPicture = tester.element(picture);
    final threshold = _windowRect(tester, schedule).top + 2 * 80 * .9;
    void resize(double height) {
      tester.view.physicalSize = Size(800 * dpr, (height * dpr).ceilToDouble());
    }

    resize(threshold + 1);
    await tester.pumpAndSettle();
    expect(_windowRect(tester, picture).width, closeTo(800, .01));
    expect(
      _windowRect(tester, schedule).height,
      greaterThanOrEqualTo(2 * 80 * .9),
    );
    resize(threshold - 1);
    await tester.pumpAndSettle();
    expect(_windowRect(tester, picture).width, lessThan(800));
    expect(tester.element(picture), same(originalPicture));

    resize(360);
    await tester.pumpAndSettle();
    final thumb = _windowRect(tester, picture);
    final details = _windowRect(tester, strip);
    expect(thumb.size.aspectRatio, closeTo(16 / 9, .001));
    expect(thumb.height, closeTo(details.height, .01));
    expect(thumb.top, closeTo(details.top, .01));
    expect(thumb.right, closeTo(details.left, .01));
    expect(
      _windowRect(tester, schedule).height,
      greaterThanOrEqualTo(2 * 84 * .9),
    );
    expect(tester.element(picture), same(originalPicture));
    await tester.tap(picture);
    await tester.tap(strip);
    expect(fixture.openPlayerCalls, 2);
    expect(fixture.tunes, isEmpty);
    expect(tester.takeException(), isNull);
    await fixture.unmount(tester);
  });

  _testGuideWidgets(
    'Short Guide keeps the natural strip height beside the picture',
    (tester) async {
      _configure(tester, const Size(800, 1280), 3, 1.3);
      final fixture = _GuideFixture();
      await fixture.mount(tester, picture: true, tabBarHeight: 78);
      final strip = find.byKey(const Key('handheld-guide-now-strip'));
      final picture = find.byKey(const Key('guide-picture-in-picture'));
      final naturalHeight = _windowRect(tester, strip).height;
      tester.view.physicalSize = const Size(800, 360) * 3;
      await tester.pumpAndSettle();
      expect(_windowRect(tester, picture).height, closeTo(naturalHeight, .01));
      expect(_windowRect(tester, strip).height, closeTo(naturalHeight, .01));
      expect(
        find.byKey(const Key('guide-program-progress')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await fixture.unmount(tester);
    },
  );

  _testGuideWidgets('Narrow Guide cards own their interval and long press', (
    tester,
  ) async {
    _configure(tester, const Size(360, 800), 3, 1);
    final fixture = _GuideFixture(
      programs: const [
        ChannelItem(
          id: 'first',
          title: 'First short',
          duration: Duration(minutes: 5),
        ),
        ChannelItem(
          id: 'second',
          title: 'Second short',
          duration: Duration(minutes: 5),
        ),
        ..._programs,
      ],
    )..now = _origin;
    await fixture.mount(tester);
    final first = _card('First short, channel 1.');
    final second = _card('Second short, channel 1.');
    final firstRect = _windowRect(tester, first);
    final secondRect = _windowRect(tester, second);
    expect(firstRect.width, closeTo((360 - 108 * .9) * .55 * 5 / 30, .01));
    expect(firstRect.width, lessThan(48));
    expect(firstRect.right, closeTo(secondRect.left, .01));
    for (final card in [first, second]) {
      final node = tester.getSemantics(card);
      final data = node.getSemanticsData();
      expect(node.isMergedIntoParent, isFalse);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
    }
    await tester.tapAt(Offset(firstRect.right - .1, firstRect.center.dy));
    expect(fixture.tunes, ['ch-0']);
    await tester.longPressAt(
      Offset(secondRect.left + .1, secondRect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_sheetKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_sheetKey),
        matching: find.text('Second short', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(fixture.tunes, ['ch-0']);
    await fixture.unmount(tester);
  });

  _testGuideWidgets(
    'Guide activates live or tile, inspects later or held card',
    (tester) async {
      _configure(tester, const Size(412, 915), 2.625, 1);
      final fixture = _GuideFixture();
      await fixture.mount(tester);

      await tester.tap(_tile(1));
      await tester.tap(_card('Morning Cinema, channel 1.'));
      expect(fixture.tunes, ['ch-1', 'ch-0']);

      await tester.tap(_card('Documentary and Discovery, channel 1.'));
      await tester.pumpAndSettle();
      expect(fixture.tunes, hasLength(2));
      expect(find.byKey(_sheetKey), findsOneWidget);
      await tester.ensureVisible(find.byKey(_watchKey));
      await tester.tap(find.byKey(_watchKey));
      await tester.pumpAndSettle();
      expect(fixture.tunes, ['ch-1', 'ch-0', 'ch-0']);
      expect(fixture.guide.selectedProgram?.scheduled.item.id, 'first');

      await tester.longPress(_card('Morning Cinema, channel 1.'));
      await tester.pumpAndSettle();
      expect(find.byKey(_sheetKey), findsOneWidget);
      expect(fixture.tunes, hasLength(3));
      // This button was built while the program aired. Simulate rollover before
      // the next widget tick and confirm the press rechecks the schedule.
      fixture.now = _origin.add(const Duration(minutes: 30));
      await tester.ensureVisible(find.byKey(_watchKey));
      await tester.tap(find.byKey(_watchKey));
      expect(fixture.tunes, hasLength(3));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(_card('Morning Cinema, channel 1.'));
      await tester.pumpAndSettle();
      expect(fixture.tunes, hasLength(3));
      expect(find.byKey(_sheetKey), findsOneWidget);
      await fixture.unmount(tester);
    },
  );

  for (final atTop in [true, false]) {
    _testGuideWidgets(
      'Guide retains horizontal time and row anchor, top=$atTop',
      (tester) async {
        _configure(tester, const Size(800, 1280), 2, 1.3);
        final fixture = _GuideFixture(channelCount: 32);
        await fixture.mount(tester);

        ScrollController scroll() =>
            tester.widget<ListView>(find.byKey(_scheduleKey)).controller!;
        double labelLeft() => _windowRect(
          tester,
          find.descendant(
            of: find.byKey(const Key('handheld-guide-ruler')),
            matching: find.text('9:30 AM'),
          ),
        ).left;
        final initialLeft = labelLeft();
        if (!atTop) {
          await tester.dragFrom(
            _windowRect(tester, find.byKey(_scheduleKey)).center,
            const Offset(-100, 0),
          );
          scroll().jumpTo(5 * 80 * 1.3);
          await tester.pumpAndSettle();
        }
        final leftBefore = labelLeft();
        final originBefore = fixture.guide.windowStart;
        expect(leftBefore, atTop ? initialLeft : lessThan(initialLeft));

        tester.view.physicalSize = const Size(1280, 800) * 2;
        await tester.pumpAndSettle();
        expect(fixture.guide.windowStart, originBefore);
        expect(fixture.guide.verticalOffsetFor(1), closeTo(atTop ? 0 : 5, .01));

        tester.view.physicalSize = const Size(800, 1280) * 2;
        await tester.pumpAndSettle();
        expect(fixture.guide.windowStart, originBefore);
        expect(fixture.guide.verticalOffsetFor(1), closeTo(atTop ? 0 : 5, .01));
        expect(labelLeft(), closeTo(leftBefore, .01));
        expect(fixture.tunes, isEmpty);
        await tester.tap(find.byKey(const Key('handheld-guide-now')));
        await tester.pumpAndSettle();
        expect(labelLeft(), closeTo(initialLeft, .01));
        expect(fixture.guide.verticalOffsetFor(1), closeTo(atTop ? 0 : 5, .01));
        expect(tester.takeException(), isNull);
        await fixture.unmount(tester);
      },
    );
  }

  _testGuideWidgets('Guide owns one global Retry when every row failed', (
    tester,
  ) async {
    _configure(tester, const Size(360, 800), 3, 2);
    final fixture = _GuideFixture(channelCount: 3)..failAll = true;
    await fixture.mount(tester);
    expect(find.text("Schedules couldn't load"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Schedule unavailable'), findsNothing);
    fixture.failAll = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text("Schedules couldn't load"), findsNothing);
    expect(find.text('Morning Cinema'), findsWidgets);
    await fixture.unmount(tester);
  });

  _testGuideWidgets('Guide shows a row Retry and independent loading state', (
    tester,
  ) async {
    _configure(tester, const Size(360, 800), 3, 2);
    final fixture = _GuideFixture(channelCount: 3)
      ..failed.add('ch-0')
      ..pending['ch-2'] = Completer<ScheduleIndex>();
    await fixture.mount(tester);
    expect(find.text('Schedule unavailable'), findsOneWidget);
    expect(find.text('Loading schedule…'), findsOneWidget);
    expect(find.text("Schedules couldn't load"), findsNothing);
    fixture.failed.clear();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule unavailable'), findsNothing);
    expect(find.text('Loading schedule…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.unmount(tester);
  });

  _testGuideWidgets('Guide marker keeps its exact time coordinate', (
    tester,
  ) async {
    _configure(tester, const Size(412, 915), 2.625, 1);
    final fixture = _GuideFixture()..now = _origin;
    await fixture.mount(tester);
    final first = _windowRect(tester, find.byKey(_nowLineKey)).left;
    final schedule = _windowRect(tester, find.byKey(_scheduleKey));
    expect(first, closeTo((100 + 8) * .9, .01));
    fixture.now = _origin.add(const Duration(minutes: 15));
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(
      _windowRect(tester, find.byKey(_nowLineKey)).left,
      closeTo(first + (schedule.right - first) * .55 / 2, .01),
    );
    await fixture.unmount(tester);
  });
}

void _testGuideWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final semantics = tester.ensureSemantics();
    try {
      await callback(tester);
    } finally {
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Finder _tile(int index) =>
    find.byKey(ValueKey('handheld-guide-channel-ch-$index'));
Finder _card(String title) =>
    find.bySemanticsLabel(RegExp('^${RegExp.escape(title)}'));

void _configure(WidgetTester tester, Size size, double dpr, double text) {
  tester.view
    ..devicePixelRatio = dpr
    ..physicalSize = size * dpr;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Rect _windowRect(WidgetTester tester, Finder finder) {
  final render = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    render.getTransformTo(null),
    Offset.zero & render.size,
  );
}

void _expectTapTarget(
  WidgetTester tester,
  Finder finder,
  Size window, {
  double bottomInset = 0,
  String? expectedLabel,
}) {
  expect(finder.hitTestable(), findsOneWidget);
  // A semantics finder also finds widgets with non-tappable text labels.
  // Confirm that precisely one visible unmerged node carries the action.
  final label = expectedLabel ?? tester.getSemantics(finder).label;
  expect(label, isNotEmpty, reason: finder.toString());
  final matching = find.semantics
      .byPredicate(
        (candidate) =>
            candidate.label == label &&
            !candidate.isInvisible &&
            !candidate.isMergedIntoParent,
      )
      .evaluate();
  expect(matching, hasLength(1), reason: label);
  final node = matching.single;
  expect(
    node.getSemanticsData().hasAction(SemanticsAction.tap),
    isTrue,
    reason: label,
  );
  var transform = Matrix4.identity();
  for (
    SemanticsNode? ancestor = node;
    ancestor != null;
    ancestor = ancestor.parent
  ) {
    final local = ancestor.transform;
    if (local != null) transform = local.multiplied(transform);
  }
  final dpr = tester.view.devicePixelRatio;
  final bounds = MatrixUtils.transformRect(transform, node.rect);
  expect(bounds.width / dpr, greaterThanOrEqualTo(48 - .1), reason: label);
  expect(bounds.height / dpr, greaterThanOrEqualTo(48 - .1), reason: label);
  final visible = Rect.fromLTWH(
    0,
    0,
    window.width,
    window.height - bottomInset,
  );
  expect(
    visible.inflate(.1).contains(bounds.center / dpr),
    isTrue,
    reason: label,
  );
}

void _expectActivePill(
  WidgetTester tester,
  Finder finder,
  Size window,
  String label,
) {
  _expectTapTarget(tester, finder, window, expectedLabel: label);
  final pill = find.descendant(
    of: finder,
    matching: find.byKey(_activePillKey),
  );
  expect(pill, findsOneWidget);
  expect(tester.getSize(pill), const Size(64, 32));
}

class _GuideFixture {
  _GuideFixture({
    int channelCount = 14,
    List<ChannelItem> programs = _programs,
  }) {
    lineup = FixtureController(
      scenario: LineupScenario(
        stage: SetupStage.ready,
        libraries: const [
          PlexLibrary(
            id: 'cinema',
            title: 'Cinema library',
            type: PlexLibraryType.movie,
          ),
        ],
        channels: [
          for (var index = 0; index < channelCount; index++)
            Channel(
              id: 'ch-$index',
              number: index + 1,
              name: index.isEven ? 'Documentary Stories' : 'Family Movies',
              source: index.isEven
                  ? const LibrarySource(
                      libraryId: 'cinema',
                      libraryType: PlexLibraryType.movie,
                    )
                  : ManualSource(programs),
              playbackMode: PlaybackMode.sequential,
              anchor: _origin,
              shuffleSeed: index,
            ),
        ],
        settings: const LineupSettings(reduceMotion: true),
      ),
    );
    guide = GuideController(
      lineup: lineup,
      clock: () => now,
      loadSchedule: (channel) async {
        if (failAll || failed.contains(channel.id)) {
          throw StateError('synthetic schedule failure');
        }
        if (pending[channel.id] case final result?) return result.future;
        return buildChannelSchedule(channel, programs);
      },
    );
  }

  late final FixtureController lineup;
  late final GuideController guide;
  DateTime now = _origin.add(const Duration(minutes: 13));
  final tunes = <String>[];
  int openPlayerCalls = 0;
  bool failAll = false;
  final failed = <String>{};
  final pending = <String, Completer<ScheduleIndex>>{};

  Future<void> mount(
    WidgetTester tester, {
    bool picture = false,
    double tabBarHeight = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(LineupThemeName.emberSteel),
        builder: (_, child) => DeviceProfileScope(
          profile: _handheld,
          child: LineupCanvas(child: child!),
        ),
        home: Column(
          children: [
            Expanded(
              child: GuideView(
                controller: guide,
                watchingChannelId: picture ? 'ch-0' : null,
                pictureInPicture: picture
                    ? const ColoredBox(color: Colors.blue)
                    : null,
                onOpenPlayer: picture ? () => openPlayerCalls++ : null,
                onClose: (_, _) {},
                onTune: (id) async => tunes.add(id),
              ),
            ),
            SizedBox(height: tabBarHeight),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    guide.dispose();
    lineup.dispose();
  }
}
