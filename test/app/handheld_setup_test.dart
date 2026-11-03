import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_setup/review_step.dart';
import 'package:lineup_desktop/app/channel_setup_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/setup_review.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/handheld_management.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/golden_test_support.dart';
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
final _roster = _key('channel-setup-review-roster');
final _search = _key('channel-setup-review-search');
final _apply = _key('apply-reviewed-lineup');
final _consent = _key('channel-setup-replace-confirmation');

void main() {
  for (final (size, dpr) in _windows) {
    for (final scale in [1.0, 1.3, 2.0]) {
      _handheldTest('Setup ${size.width}×${size.height} @$dpr text $scale', (
        tester,
      ) async {
        _window(tester, size, dpr);
        await tester.runAsync(loadPinnedTestFonts);
        final controller = _SetupController();
        addTearDown(controller.dispose);
        await _pumpSetup(tester, controller, scale: scale);

        _checkTitleWords(tester);
        final scan = _key('scan-selected-libraries');
        await _tap(tester, scan);
        await _tap(tester, _key('continue-ready-libraries'));
        _checkTitleWords(tester);
        final review = _key('review-channels');
        await _tap(tester, review);

        _checkTitleWords(tester);
        final stacked = find.byType(HandheldPageBar).evaluate().isNotEmpty;
        expect(stacked, size.width != 1280 || scale == 2);
        expect(find.ancestor(of: _search, matching: _roster), findsNothing);
        final replaceMode = find.text('Replace generated channels');
        if (replaceMode.evaluate().isEmpty ||
            replaceMode.hitTestable().evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            replaceMode,
            140,
            scrollable: find
                .descendant(of: _roster, matching: find.byType(Scrollable))
                .first,
          );
        }
        await _tap(tester, replaceMode);
        expect(tester.widget<FilledButton>(_apply).onPressed, isNull);
        await _reachable(tester, _consent);
        await _reachable(tester, _apply);
        await _imeTap(tester, _search);
        expect(_apply, findsNothing);
        if (stacked) expect(_consent, findsNothing);
        tester.view.resetViewInsets();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await _tap(tester, _consent);
        await _tap(tester, _apply);
        expect(controller.applied, 1);
        await _reachable(
          tester,
          find.widgetWithText(FilledButton, 'View lineup'),
        );
        for (final status in [
          LibraryScanStatus.scanning,
          LibraryScanStatus.transientFailure,
          LibraryScanStatus.empty,
        ]) {
          await tester.pumpWidget(const SizedBox.shrink());
          final recovery = _SetupController(scanStatus: status);
          addTearDown(recovery.dispose);
          await _pumpSetup(tester, recovery, scale: scale);
          await _checkRecovery(tester, recovery);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  _handheldTest(
    'Review touch scroll keeps its row and search across B0 flips',
    (tester) async {
      _window(tester, const Size(1280, 800), 2);
      await tester.runAsync(loadPinnedTestFonts);
      await tester.pumpWidget(_host(1, _ReviewFixture()));
      await tester.pumpAndSettle();
      await tester.enterText(_search, 'Test');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      for (var drag = 0; drag < 10; drag++) {
        await tester.drag(_roster, const Offset(0, -280));
        await tester.pumpAndSettle();
      }
      final anchor = _topRow(tester);
      expect(anchor, isNot('review-channel-channel-1'));
      expect(
        find
            .byWidgetPredicate((widget) {
              final key = widget.key;
              return key is ValueKey<String> &&
                  key.value.startsWith('review-channel-');
            })
            .evaluate()
            .length,
        lessThan(184),
      );
      await _imeTap(tester, _search);
      tester.view.resetViewInsets();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final before = _topRow(tester);
      await tester.pumpWidget(_host(2, _ReviewFixture()));
      await tester.pumpAndSettle();
      expect(_topRow(tester), before);
      expect(tester.widget<TextField>(_search).controller!.text, 'Test');
      await _imeTap(tester, _search);
      tester.view.resetViewInsets();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final stackedAnchor = _topRow(tester);
      await tester.pumpWidget(_host(1, _ReviewFixture()));
      await tester.pumpAndSettle();
      expect(_topRow(tester), stackedAnchor);
      await _tap(tester, find.byTooltip('Clear search'));
      expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  _handheldTest('production Setup retains its active step across B0', (
    tester,
  ) async {
    _window(tester, const Size(1280, 800), 2);
    final controller = _SetupController();
    addTearDown(controller.dispose);
    await _pumpSetup(tester, controller, scale: 1.3);
    await _tap(tester, _key('scan-selected-libraries'));
    await _tap(tester, _key('continue-ready-libraries'));
    await _tap(tester, _key('configure-section-2'));
    await _pumpSetup(tester, controller, scale: 2);
    expect(
      tester.widget<HandheldFilterChip>(_key('configure-section-2')).selected,
      isTrue,
    );
    await _tap(tester, _key('review-channels'));
    await tester.enterText(_search, 'Drama');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _pumpSetup(tester, controller, scale: 1.3);
    expect(tester.widget<TextField>(_search).controller!.text, 'Drama');
    expect(_apply, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _handheldTest('updated fields render on their own lines below facts', (
    tester,
  ) async {
    _window(tester, const Size(360, 800), 3);
    await tester.runAsync(loadPinnedTestFonts);
    await tester.pumpWidget(_host(2, _ReviewFixture(search: 'updated')));
    await tester.pumpAndSettle();
    final row = _key('review-channel-channel-1');
    await tester.scrollUntilVisible(
      row,
      180,
      scrollable: find
          .descendant(of: _roster, matching: find.byType(Scrollable))
          .first,
    );
    Finder line(String text) => find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().startsWith(text),
      ),
    );
    expect(
      tester.getTopLeft(line('Name:')).dy,
      greaterThan(tester.getTopLeft(line('Library')).dy),
    );
    expect(
      tester.getTopLeft(line('Playback:')).dy,
      greaterThan(tester.getTopLeft(line('Name:')).dy),
    );
    expect(tester.takeException(), isNull);
  });
  _handheldTest('Configure choice sheet, touch expansion and Setup Back', (
    tester,
  ) async {
    _window(tester, const Size(360, 800), 3);
    await tester.runAsync(loadPinnedTestFonts);
    final controller = _SetupController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      UiFixture(controller: controller, profile: _handheld).build(),
    );
    await tester.pumpAndSettle();
    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    await _tap(tester, _key('scan-selected-libraries'));
    await _reachable(tester, _key('scan-again-libraries'));
    await _tap(tester, _key('continue-ready-libraries'));
    await _tap(tester, _key('configure-section-2'));
    final limit = _key('rules-maximum');
    await _scrollConfig(tester, limit);
    await _tap(tester, limit);
    final sheet = find.byType(HandheldChoiceSheet<int>);
    final option = tester.widget<HandheldChoiceSheet<int>>(sheet).choices.first;
    await _tap(
      tester,
      find.descendant(of: sheet, matching: find.text(option.label)),
    );
    expect(tester.widget<HandheldSelectField<int>>(limit).value, option.value);

    final arrow = find.byTooltip('Move later').first;
    await _scrollConfig(tester, arrow);
    await _checkTouchRegion(tester, arrow);
    await _tap(tester, arrow);
    await _tap(tester, _key('configure-section-1'));
    final block = _key('setup-playback-block');
    await _scrollConfig(tester, block);
    await _tap(tester, block);
    final specials = find.widgetWithText(
      CheckboxMenuButton,
      'Include specials',
    );
    await _scrollConfig(tester, specials);
    await _checkTouchRegion(tester, specials);
    await _tap(tester, specials);
    expect(tester.widget<CheckboxMenuButton>(specials).value, isTrue);

    await _tap(tester, _key('review-channels'));
    await back();
    expect(_key('review-channels'), findsOneWidget);
    await _tap(tester, find.byTooltip('Back to libraries').last);
    expect(_key('continue-ready-libraries'), findsOneWidget);
    await _tap(tester, _key('continue-ready-libraries'));
    await back();
    expect(_key('continue-ready-libraries'), findsOneWidget);
    await _tap(tester, _key('continue-ready-libraries'));
    await _tap(tester, _key('review-channels'));
    await _tap(tester, find.byTooltip('Back to configure').last);
    expect(_key('review-channels'), findsOneWidget);
    await _tap(tester, _key('review-channels'));
    controller.failApply = true;
    await _tap(tester, _apply);
    await _reachable(
      tester,
      find.widgetWithText(FilledButton, 'Back to review'),
    );
    await back();
    expect(_apply, findsOneWidget);
    await back();
    await back();
    await _tap(tester, find.byTooltip('Cancel setup').last);
    expect(controller.cancelled, 1);
    await back();
    expect(controller.cancelled, 2);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _checkRecovery(
  WidgetTester tester,
  _SetupController controller,
) async {
  switch (controller.scanStatus) {
    case LibraryScanStatus.scanning:
      await _tap(tester, find.widgetWithText(TextButton, 'Cancel scan'));
      expect(controller.libraryScanStatus, LibraryScanStatus.cancelled);
    case LibraryScanStatus.transientFailure:
      await _tap(tester, _key('retry-failed-libraries'));
      expect(controller.retried, isTrue);
    case LibraryScanStatus.empty:
      await _tap(tester, _key('setup-switch-server'));
      expect(controller.switched, 1);
    default:
      throw StateError('Unexpected fixture status');
  }
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

Future<void> _reachable(WidgetTester tester, Finder control) async {
  expect(control, findsOneWidget);
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  final box = tester.renderObject<RenderBox>(control);
  final bounds = MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
  final dpr = tester.view.devicePixelRatio;
  final window = tester.view.physicalSize / dpr;
  final keyboard = tester.view.viewInsets.bottom / dpr;
  expect(
    bounds.left,
    greaterThanOrEqualTo(-.5),
    reason: '$control bounds $bounds',
  );
  expect(
    bounds.top,
    greaterThanOrEqualTo(-.5),
    reason: '$control bounds $bounds',
  );
  expect(
    bounds.right,
    lessThanOrEqualTo(window.width + .5),
    reason: '$control bounds $bounds',
  );
  expect(
    bounds.bottom,
    lessThanOrEqualTo(window.height - keyboard + .5),
    reason: '$control bounds $bounds',
  );
  final hits = HitTestResult();
  tester.binding.hitTestInView(hits, bounds.center, tester.view.viewId);
  expect(
    hits.path.any((hit) {
      for (var node = hit.target; node is RenderObject; node = node.parent!) {
        if (identical(node, box)) return true;
        if (node.parent == null) break;
      }
      return false;
    }),
    isTrue,
    reason: '$control center is covered',
  );
}

Future<void> _tap(WidgetTester tester, Finder control) async {
  await _reachable(tester, control);
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _imeTap(WidgetTester tester, Finder field) async {
  tester.view.viewInsets = FakeViewPadding(
    bottom: 300 * tester.view.devicePixelRatio,
  );
  await tester.pumpAndSettle();
  await _reachable(tester, field);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.tapAt(tester.getCenter(field));
  await tester.pumpAndSettle();
  final editable = tester.widget<EditableText>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  expect(editable.focusNode.hasFocus, isTrue);
}

void _checkTitleWords(WidgetTester tester) {
  final title = _key('handheld-page-bar-title');
  if (title.evaluate().isEmpty) return;
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: title, matching: find.byType(RichText)),
  );
  for (final word in RegExp(
    r'[^\s-]+',
  ).allMatches(paragraph.text.toPlainText())) {
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: word.start, extentOffset: word.end),
    );
    expect(
      boxes.map((box) => box.bottom).toSet(),
      hasLength(1),
      reason: word.group(0),
    );
  }
}

Future<void> _scrollConfig(WidgetTester tester, Finder control) async {
  final scrollable = find
      .descendant(
        of: _key('channel-configuration'),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(control, 160, scrollable: scrollable);
}

Future<void> _checkTouchRegion(WidgetTester tester, Finder control) async {
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  final region = find
      .ancestor(of: control, matching: find.byType(LineupTouchTarget))
      .first;
  expect(tester.getRect(region).height, greaterThanOrEqualTo(48 - .01));
}

Future<void> _pumpSetup(
  WidgetTester tester,
  _SetupController controller, {
  required double scale,
}) async {
  await tester.pumpWidget(
    _host(
      scale,
      ListenableBuilder(
        listenable: controller,
        builder: (_, _) => UpstreamChannelSetupView(controller: controller),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _topRow(WidgetTester tester) {
  final viewport = tester.getRect(_roster);
  return find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('review-channel-');
      })
      .evaluate()
      .map((element) {
        final box = element.renderObject! as RenderBox;
        return (
          (element.widget.key! as ValueKey<String>).value,
          MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          ),
        );
      })
      .firstWhere(
        (row) =>
            row.$2.top < viewport.top + 3 && row.$2.bottom > viewport.top + 3,
      )
      .$1;
}

Channel _channel(int number, {bool updated = false}) => Channel(
  id: 'channel-$number',
  number: number,
  name: updated ? 'Test updated channel $number' : 'Test channel $number',
  builderKey: 'synthetic-$number',
  source: const ManualSource([]),
  playbackMode: updated ? PlaybackMode.sequential : PlaybackMode.shuffle,
  anchor: DateTime.utc(2026),
  shuffleSeed: number,
);

class _ReviewFixture extends StatelessWidget {
  const _ReviewFixture({this.search = ''});
  final String search;

  @override
  Widget build(BuildContext context) {
    final base = [for (var i = 1; i <= 184; i++) _channel(i)];
    final review = SetupReview(
      base: base,
      plan: (
        channels: [_channel(1, updated: true), ...base.sublist(1, 183)],
        allocatedOriginals: 183,
        excludedOriginals: 0,
        allocatedExtras: 0,
        excludedExtras: 0,
        numberLimitExcluded: 0,
        existingSkipped: 0,
        unmatchedGenerated: const [],
        eligibleOriginalsByStrategy: const {},
        allocatedOriginalsByStrategy: const {},
        allocatedChannelsByStrategy: const {},
        truncated: false,
      ),
      mode: ChannelBuildMode.replace,
      strategyBySource: const {},
    );
    return Scaffold(
      body: SetupReviewStep(
        review: review,
        notice: null,
        removalConfirmed: false,
        sourceOrder: const [],
        sourceLabel: (_) => 'Library',
        initialFilter: SetupReviewFilter.all,
        initialSearch: search,
        onFilterChanged: (_) {},
        onSearchChanged: (_) {},
        isGeneratedSourceConfirmedGone: (_) => false,
        onBack: () {},
        onModeChanged: (_) {},
        onRemovalChanged: (_, _) {},
        onRemovalConfirmationChanged: (_) {},
        onApply: () {},
        onViewLineup: () {},
      ),
    );
  }
}

class _SetupController extends FixtureController {
  _SetupController({this.scanStatus = LibraryScanStatus.idle})
    : super(
        scenario: LineupScenario(
          stage: SetupStage.channelSetup,
          channelSetupCanCancel: true,
          channels: [_channel(100)],
          libraryScanStatus: scanStatus,
          libraries: scanStatus == LibraryScanStatus.empty
              ? const []
              : const [
                  PlexLibrary(
                    id: 'movies',
                    title: 'Movies',
                    type: PlexLibraryType.movie,
                  ),
                ],
          availableMedia: [
            for (var i = 0; i < 8; i++)
              PlexMediaItem(
                id: 'movie-$i',
                title: 'Film $i',
                type: 'movie',
                duration: const Duration(minutes: 30),
                libraryId: 'movies',
                parts: [PlexMediaPart(path: '/parts/$i')],
                genres: const ['Drama'],
              ),
          ],
        ),
      );

  final LibraryScanStatus scanStatus;
  bool failApply = false;
  int applied = 0;
  int switched = 0;
  int cancelled = 0;
  bool retried = false;

  @override
  Set<String> get libraryScanRetryIds =>
      scanStatus == LibraryScanStatus.transientFailure && !retried
      ? const {'movies'}
      : const {};

  @override
  void cancelLibraryScan() {
    fixtureActor.reportScan(status: LibraryScanStatus.cancelled);
  }

  @override
  void cancelChannelSetup() => cancelled++;

  @override
  void showServers() => switched++;

  Set<String> ready = {};

  @override
  Set<String> get libraryScanReadyIds => ready;

  @override
  Future<bool> scanLibraries(
    Set<String> ids, {
    bool retryFailedOnly = false,
  }) async {
    retried = retryFailedOnly;
    ready = ids;
    fixtureActor.reportScan(status: LibraryScanStatus.complete);
    return false; // Keep Libraries open to exercise Continue.
  }

  @override
  Future<bool> commitLibraryScan(Set<String> readyIds) async {
    fixtureActor.publishInventory(selectedLibraryIds: readyIds);
    return true;
  }

  @override
  Future<ChannelPlanApplyResult> applyReviewedChannelPlan(
    List<Channel> planned, {
    required ChannelBuildMode mode,
    required List<Channel> expectedBase,
    Set<String> removeChannelIds = const {},
  }) async {
    applied++;
    if (failApply) throw StateError('Synthetic failure');
    return ChannelPlanApplyResult.applied;
  }
}
