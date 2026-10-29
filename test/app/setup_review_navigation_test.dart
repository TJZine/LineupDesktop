import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_setup/review_step.dart';
import 'package:lineup_desktop/app/setup_review.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

void main() {
  testWidgets('184 virtualized rows: first, middle, last region key counts', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester);
    for (final number in [1, 92, 184]) {
      final row = _row(number);
      await _reveal(tester, row);
      _readNode(tester, row).requestFocus();
      await tester.pumpAndSettle();
      expect(
        find.text('Press right on any channel to jump here'),
        findsOneWidget,
      );
      final builtRows = find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith(
                  'review-channel-',
                ),
          )
          .evaluate()
          .length;
      expect(
        builtRows,
        lessThan(184),
        reason: 'Must exercise the real lazy roster',
      );
      var right = 0;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      right++;
      await tester.pumpAndSettle();

      expect(
        find.text('Press right on any channel to jump here'),
        findsNothing,
      );
      expect(_primary(tester).hasPrimaryFocus, isTrue);
      // Move the viewport while in the footer: the remembered row can be
      // disposed by the real sliver, so Up must also rebuild and reveal it.
      _scroll(tester)
          .jumpTo(number == 184 ? 0 : _scroll(tester).maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_readNode(tester, row).hasPrimaryFocus, isTrue);
      final viewport = tester.getRect(
        find.byKey(const ValueKey('channel-setup-review-roster')),
      );
      final rect = tester.getRect(row);
      expect(rect.top, greaterThanOrEqualTo(viewport.top - 1));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 1));
      debugPrint(
        'R1 row=$number right=$right up=1 builtRows=$builtRows rowRect=$rect viewport=$viewport',
      );

      if (number == 184) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(_back(tester).hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(_readNode(tester, row).hasPrimaryFocus, isTrue);
      }
      expect(fixture.actions, 0);
    }
  });
  testWidgets(
    'disclosure, disabled primary, consent, recalculation and both footer returns',
    (tester) async {
      final fixture = _Fixture()
        ..review = _review(updated: 92, removed: true)
        ..search = 'Test';
      await fixture.pump(tester);
      final row = _row(92);
      await _reveal(tester, row);
      final tile = find.descendant(
        of: row,
        matching: find.byType(ExpansionTile),
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(
        find.text('Name: Test channel 92 → Test updated channel 92'),
        findsOneWidget,
      );
      final node = _readNode(tester, row);
      node.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_back(tester).hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(node.hasPrimaryFocus, isTrue);
      expect(
        find.text('Name: Test channel 92 → Test updated channel 92'),
        findsOneWidget,
      );
      expect(fixture.confirmed, isFalse);
      expect(fixture.search, 'Test');
      expect(fixture.actions, 0);

      fixture.confirmed = true;
      await fixture.pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_primary(tester).hasPrimaryFocus, isTrue);
      // Footer horizontal navigation stays ordinary button traversal.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_back(tester).hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_primary(tester).hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(node.hasPrimaryFocus, isTrue);
      fixture.notice = 'Updating review…';
      await fixture.pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_back(tester).hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(node.hasPrimaryFocus, isTrue);
      expect(fixture.confirmed, isTrue);
      expect(fixture.search, 'Test');
      expect(fixture.filter, SetupReviewFilter.all);
      expect(fixture.actions, 0);
    },
  );

  testWidgets(
    'filtered fallback uses original order, preceding tie, then Search',
    (tester) async {
      final fixture = _Fixture()..review = _review(updated: 92);
      await fixture.pump(tester);
      await _reveal(tester, _row(92));
      _readNode(tester, _row(92)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      fixture.filter = SetupReviewFilter.unchanged;
      await fixture.pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_readNode(tester, _row(91)).hasPrimaryFocus, isTrue);
      expect(fixture.filter, SetupReviewFilter.unchanged);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      fixture.search = 'no matches';
      await fixture.pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Setup review search',
      );
      expect(fixture.search, 'no matches');
      expect(fixture.actions, 0);
    },
  );

  testWidgets('no-memory Up traverses to last row; return memory is consumed', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester);
    await _reveal(tester, _row(184));
    // Direct footer entry has no remembered row. Normal Up traversal must
    // select the last row, even when no row has ever owned focus.
    _back(tester).requestFocus();
    await tester.pumpAndSettle();
    expect(_back(tester).hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_readNode(tester, _row(184)).hasPrimaryFocus, isTrue);

    await _reveal(tester, _row(92));
    _readNode(tester, _row(92)).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_readNode(tester, _row(92)).hasPrimaryFocus, isTrue);
    await _reveal(tester, _row(184));
    _back(tester).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_readNode(tester, _row(184)).hasPrimaryFocus, isTrue);
    expect(fixture.actions, 0);
  });

  testWidgets('held Right and Up do not remember, reveal or refocus', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester);
    await _reveal(tester, _row(92));
    final node = _readNode(tester, _row(92));
    node.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_primary(tester).hasPrimaryFocus, isTrue);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(node.hasPrimaryFocus, isTrue);
    // Keep Up held, enter the footer again, and move the viewport. A repeat
    // must not start another return or run ordinary traversal.
    _back(tester).requestFocus();
    await tester.pumpAndSettle();
    _scroll(tester).jumpTo(_scroll(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    final offset = _scroll(tester).pixels;
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_back(tester).hasPrimaryFocus, isTrue);
    expect(_scroll(tester).pixels, offset);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);

    await _reveal(tester, _row(92));
    final freshNode = _readNode(tester, _row(92));
    freshNode.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    freshNode
        .requestFocus(); // another path out of the footer clears the memory
    await tester.pumpAndSettle();
    final rowOffset = _scroll(tester).pixels;
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(freshNode.hasPrimaryFocus, isTrue);
    expect(_scroll(tester).pixels, rowOffset);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(fixture.actions, 0);
  });

  testWidgets(
    'leaving footer and new review clear memory; recalculation prunes scopes',
    (tester) async {
      final fixture = _Fixture();
      await fixture.pump(tester);
      await _reveal(tester, _row(92));
      final removedScope = _rowScope(tester, _row(92));
      _readNode(tester, _row(92)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('channel-setup-review-search'));
      await _reveal(tester, search);
      tester.widget<TextField>(search).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await _reveal(tester, _row(184));
      final retainedScope = _rowScope(tester, _row(184));
      _back(tester).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_readNode(tester, _row(184)).hasPrimaryFocus, isTrue);

      await _reveal(tester, _row(92));
      _readNode(tester, _row(92)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      fixture.review = _review(omit: 92);
      await fixture.pump(tester);
      expect(removedScope.context?.mounted, isNot(true));
      expect(() => removedScope.addListener(() {}), throwsFlutterError);
      await _reveal(tester, _row(184));
      expect(_rowScope(tester, _row(184)), same(retainedScope));
      _back(tester).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_readNode(tester, _row(184)).hasPrimaryFocus, isTrue);
      expect(fixture.actions, 0);
    },
  );

  testWidgets(
    'region moves skip ineligible targets and cancel obsolete reveals',
    (tester) async {
      final fixture = _Fixture();
      await fixture.pump(tester);
      await _reveal(tester, _row(92));
      _readNode(tester, _row(92)).requestFocus();
      await tester.pumpAndSettle();
      _primary(tester).canRequestFocus = false;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_back(tester).hasPrimaryFocus, isTrue);
      _scroll(tester).jumpTo(_scroll(tester).maxScrollExtent);
      await tester.pumpAndSettle();
      // A return starts asynchronously; leaving the footer before its next frame
      // must prevent it from stealing focus or continuing to scroll.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      _back(tester).unfocus(disposition: UnfocusDisposition.scope);
      FocusManager.instance.applyFocusChangesIfNeeded();
      await tester.pumpAndSettle();
      expect(_footerFocused(tester), isFalse);
      expect(find.byKey(const ValueKey('review-footer-hint')), findsNothing);
      expect(fixture.actions, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Search editing and method/removal leaves keep Right; region movement does not activate',
    (tester) async {
      final fixture = _Fixture()..review = _review(updated: 92, removed: true);
      await fixture.pump(tester);
      final search = find.byKey(const ValueKey('channel-setup-review-search'));
      await tester.ensureVisible(search);
      await tester.tap(search);
      await tester.enterText(search, 'Test');
      await tester.pumpAndSettle();
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      editor.controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(editor.controller.selection.baseOffset, 2);
      expect(_footerFocused(tester), isFalse);
      final method = find.byKey(const ValueKey('review-build-method'));
      await _reveal(tester, method);
      await tester.tap(
        find.descendant(of: method, matching: find.text('Update and add')),
      );
      await tester.pumpAndSettle();
      final before = fixture.actions;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_footerFocused(tester), isFalse);
      expect(fixture.actions, before);
      final consent = find.byType(CheckboxListTile);
      await _reveal(tester, consent);
      await tester.tap(consent);
      await tester.pumpAndSettle();
      final afterConsent = fixture.actions;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_footerFocused(tester), isFalse);
      expect(fixture.actions, afterConsent);
    },
  );

  testWidgets(
    'filter fallback is nearest in original order and missing-source segments keep Right',
    (tester) async {
      final fixture = _Fixture()..review = _review(updated: 92, missing: true);
      await fixture.pump(tester);
      await _reveal(tester, _row(92));
      _readNode(tester, _row(92)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      fixture.filter = SetupReviewFilter.unchanged;
      await fixture.pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_readNode(tester, _row(91)).hasPrimaryFocus, isTrue);
      expect(fixture.filter, SetupReviewFilter.unchanged);
      final choice = find.byKey(
        const ValueKey('missing-source-choice-channel-1'),
      );
      await _reveal(tester, choice);
      await tester.tap(
        find.descendant(of: choice, matching: find.text('Keep')),
      );
      await tester.pumpAndSettle();
      final before = fixture.actions;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_footerFocused(tester), isFalse);
      expect(fixture.actions, before);
      expect(fixture.filter, SetupReviewFilter.unchanged);
    },
  );

  for (final tv in [true, false]) {
    testWidgets('no-change Review copy and existing callback: tv=$tv', (
      tester,
    ) async {
      final fixture = _Fixture()..review = _review(unchanged: true);
      await fixture.pump(tester, tv: tv);
      expect(find.text(tv ? 'Open guide' : 'View lineup'), findsOneWidget);
      if (!tv) {
        expect(find.byKey(const ValueKey('review-footer-hint')), findsNothing);
      }
      await tester.tap(
        find.widgetWithText(FilledButton, tv ? 'Open guide' : 'View lineup'),
      );
      expect(fixture.actions, 1);
    });
  }
}

Finder _row(int number) =>
    find.byKey(ValueKey('review-channel-channel-$number'));
Finder get _roster => find.byKey(const ValueKey('channel-setup-review-roster'));
ScrollPosition _scroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _roster, matching: find.byType(Scrollable)).first,
    )
    .position;
Future<void> _reveal(WidgetTester tester, Finder row) async {
  _scroll(tester).jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    row,
    500,
    maxScrolls: 80,
    scrollable: find
        .descendant(of: _roster, matching: find.byType(Scrollable))
        .first,
  );
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
}

FocusNode _readNode(WidgetTester tester, Finder row) => Focus.of(
  tester.element(find.descendant(of: row, matching: find.byType(Text)).first),
);
FocusNode _rowScope(WidgetTester tester, Finder row) => _readNode(tester, row)
    .ancestors
    .firstWhere((node) => node.debugLabel?.startsWith('Review row ') == true);
FocusNode _back(WidgetTester tester) => tester
    .widget<TextButton>(find.byKey(const ValueKey('back-to-configure')))
    .focusNode!;
FocusNode _primary(WidgetTester tester) => Focus.of(
  tester.element(
    find
        .descendant(of: find.byType(FilledButton), matching: find.byType(Text))
        .last,
  ),
);
bool _footerFocused(WidgetTester tester) =>
    _primary(tester).hasFocus ||
    Focus.of(tester.element(find.text('Back to configure'))).hasFocus;

class _Fixture {
  SetupReview review = _review();
  String search = '';
  SetupReviewFilter filter = SetupReviewFilter.all;
  String? notice;
  bool confirmed = false;
  int actions = 0;
  Future<void> pump(
    WidgetTester tester, {
    bool tv = true,
    double scale = 1,
  }) async {
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(LineupThemeName.emberSteel, androidTv: tv),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: LineupCanvas(child: child!),
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(40),
            child: SetupReviewStep(
              review: review,
              notice: notice,
              removalConfirmed: confirmed,
              sourceOrder: const [],
              sourceLabel: (_) => 'Library',
              initialFilter: filter,
              initialSearch: search,
              onFilterChanged: (value) => filter = value,
              onSearchChanged: (value) => search = value,
              isGeneratedSourceConfirmedGone: (channel) =>
                  channel.id == 'channel-1',
              onBack: () => actions++,
              onModeChanged: (_) => actions++,
              onRemovalChanged: (_, _) => actions++,
              onRemovalConfirmationChanged: (_) => actions++,
              onApply: () => actions++,
              onViewLineup: () => actions++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

SetupReview _review({
  int count = 184,
  int? updated,
  int? omit,
  int? moved,
  bool removed = false,
  bool unchanged = false,
  bool missing = false,
}) {
  Channel channel(int i, {bool before = false}) => Channel(
    id: 'channel-$i',
    number: moved == i && !before ? 999 : i,
    name: updated == i && !before
        ? 'Test updated channel $i'
        : 'Test channel $i',
    source: const ManualSource([]),
    builderKey: 'generated-$i',
    playbackMode: PlaybackMode.shuffle,
    anchor: DateTime.utc(2026),
    shuffleSeed: i,
  );
  final channels = [
    for (var i = 1; i <= count; i++)
      if (i != omit) channel(i),
  ];
  return SetupReview(
    base: updated != null || removed || unchanged
        ? [
            for (var i = 1; i <= count; i++)
              if (i != omit) channel(i, before: true),
            if (removed) channel(count + 1),
          ]
        : const [],
    plan: (
      channels: unchanged ? const [] : channels,
      allocatedOriginals: count,
      excludedOriginals: 0,
      allocatedExtras: 0,
      excludedExtras: 0,
      numberLimitExcluded: 0,
      existingSkipped: 0,
      unmatchedGenerated: missing ? [channel(1)] : const [],
      eligibleOriginalsByStrategy: const {},
      allocatedOriginalsByStrategy: const {},
      allocatedChannelsByStrategy: const {},
      truncated: false,
    ),
    mode: unchanged || missing
        ? ChannelBuildMode.merge
        : ChannelBuildMode.replace,
    strategyBySource: const {},
  );
}
