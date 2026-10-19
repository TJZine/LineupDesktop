import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/content_resolver.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

import '../support/ui_fixture.dart';

void main() {
  for (final accountPicker in [false, true]) {
    testWidgets(
      'app menu removes route tooltips and restores them on return (account picker: $accountPicker)',
      (tester) async {
        final fixture = UiFixture(
          scenario: LineupScenario(
            stage: SetupStage.ready,
            profiles: const [
              PlexHomeUser(id: 'one', name: 'One', protected: false),
              PlexHomeUser(id: 'two', name: 'Two', protected: false),
            ],
          ),
        );
        await tester.pumpWidget(fixture.build());
        await tester.pumpAndSettle();

        if (accountPicker) {
          await openDestination(tester, 'Settings');
          await tester.tap(find.text('Account'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Switch profile'));
          await tester.pumpAndSettle();
          expect(fixture.controller.stage, SetupStage.profiles);
        }

        final menuTooltip = find.byWidgetPredicate(
          (widget) => widget is Tooltip && widget.message == 'Open Lineup menu',
        );
        expect(
          tester.state<TooltipState>(menuTooltip).ensureTooltipVisible(),
          isTrue,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Open Lineup menu'), findsOneWidget);

        await tester.tap(
          find.byKey(
            Key(accountPicker ? 'onboarding-app-menu' : 'guide-app-menu'),
          ),
        );
        await tester.pump();
        expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
        expect(find.text('Open Lineup menu'), findsNothing);
        expect(
          tester.state<TooltipState>(menuTooltip).ensureTooltipVisible(),
          isFalse,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          tester.state<TooltipState>(menuTooltip).ensureTooltipVisible(),
          isTrue,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Open Lineup menu'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('shell preserves an outer tooltip visibility restriction', (
    tester,
  ) async {
    final fixture = UiFixture(
      scenario: LineupScenario(stage: SetupStage.ready),
    );
    await tester.pumpWidget(
      TooltipVisibility(visible: false, child: fixture.build()),
    );
    await tester.pumpAndSettle();

    final menuTooltip = find.byWidgetPredicate(
      (widget) => widget is Tooltip && widget.message == 'Open Lineup menu',
    );
    expect(
      tester.state<TooltipState>(menuTooltip).ensureTooltipVisible(),
      isFalse,
    );
    await tester.tap(find.byKey(const Key('guide-app-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guide').last);
    await tester.pumpAndSettle();
    expect(
      tester.state<TooltipState>(menuTooltip).ensureTooltipVisible(),
      isFalse,
    );
    expect(find.text('Open Lineup menu'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final returnToLive in [false, true]) {
    testWidgets(
      'Guide Now tooltip stays reachable with its button (return to live: $returnToLive)',
      (tester) async {
        final fixture = _guideFocusFixture();
        await tester.pumpWidget(fixture.build());
        await tester.pumpAndSettle();
        final guide = tester
            .widget<GuideView>(find.byType(GuideView))
            .controller;
        if (returnToLive) guide.moveWindow(4);
        await tester.pumpAndSettle();
        final label = returnToLive ? 'Return to live' : 'Now';
        final button = find.byKey(const Key('guide-now'));
        final tooltip = find.ancestor(
          of: button,
          matching: find.byType(Tooltip),
        );
        expect(tester.widget<Tooltip>(tooltip).message, label);
        expect(
          tester.state<TooltipState>(tooltip).ensureTooltipVisible(),
          isTrue,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text && widget.textSpan?.toPlainText() == label,
          ),
          findsOneWidget,
        );
        // A local overlay node can exist without being grafted into the view's
        // accessibility tree. Traverse from the root to establish reachability.
        final reachable = tester.semantics.simulatedAccessibilityTraversal();
        expect(
          reachable.where(
            (node) =>
                node.label == label &&
                node.getSemanticsData().flagsCollection.isButton &&
                node.getSemanticsData().hasAction(SemanticsAction.tap),
          ),
          hasLength(1),
        );
        expect(
          reachable.where(
            (node) =>
                node.label == label &&
                !node.getSemanticsData().hasAction(SemanticsAction.tap),
          ),
          hasLength(1),
        );
        expect(fixture.player.loads, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      semanticsEnabled: true,
    );
  }

  for (final showTooltip in [false, true]) {
    testWidgets(
      'Guide Later survives keyboard menu return and still browses (tooltip: $showTooltip)',
      (tester) async {
        final fixture = _guideFocusFixture();
        await tester.pumpWidget(fixture.build());
        await tester.pumpAndSettle();
        final guide = tester
            .widget<GuideView>(find.byType(GuideView))
            .controller;
        expect(guide.currentProgram('newsroom'), isNotNull);
        final later = find.byKey(const Key('guide-later'));
        final invoker = _controlFocus(tester, later);
        invoker.requestFocus();
        await tester.pump();
        expect(invoker.hasPrimaryFocus, isTrue);
        final tooltip = find.descendant(
          of: later,
          matching: find.byType(Tooltip),
        );
        if (showTooltip) {
          expect(
            tester.state<TooltipState>(tooltip).ensureTooltipVisible(),
            isTrue,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text('Later by 30 minutes'), findsOneWidget);
        }

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
        expect(find.text('Later by 30 minutes'), findsNothing);
        expect(
          tester.state<TooltipState>(tooltip).ensureTooltipVisible(),
          isFalse,
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('immersive-app-menu')), findsNothing);
        final liveInvoker = _controlFocus(tester, later);
        expect(liveInvoker, same(invoker));
        expect(liveInvoker.context?.mounted, isTrue);
        expect(liveInvoker.hasPrimaryFocus, isTrue);
        final previousStart = guide.windowStart;
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          guide.windowStart.difference(previousStart),
          const Duration(minutes: 30),
        );
        expect(find.byType(GuideView), findsOneWidget);
        expect(fixture.player.loads, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final control in [
    'Earlier by 30 minutes',
    'Now',
    'Close Guide',
    'Remove library filter',
  ]) {
    testWidgets('Guide $control restores its live keyboard invoker', (
      tester,
    ) async {
      final fixture = _guideFocusFixture();
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      final guide = tester.widget<GuideView>(find.byType(GuideView)).controller;
      final liveStart = guide.windowStart;
      if (control == 'Earlier by 30 minutes' || control == 'Now') {
        guide.moveWindow(1);
      } else if (control == 'Remove library filter') {
        guide.setLibraryFilter('movies');
      }
      await tester.pumpAndSettle();
      final button = control == 'Now'
          ? find.byKey(const Key('guide-now'))
          : find.byTooltip(control);
      final invoker = _controlFocus(tester, button);
      invoker.requestFocus();
      await tester.pump();
      expect(invoker.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('immersive-app-menu')), findsNothing);
      expect(_controlFocus(tester, button), same(invoker));
      expect(invoker.context?.mounted, isTrue);
      expect(invoker.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      switch (control) {
        case 'Earlier by 30 minutes':
        case 'Now':
          expect(guide.windowStart, liveStart);
        case 'Close Guide':
          expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
        case 'Remove library filter':
          expect(guide.libraryFilterId, isNull);
      }
      expect(fixture.player.loads, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final key in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  ]) {
    testWidgets('Guide Clear search activates with ${key.keyLabel}', (
      tester,
    ) async {
      final fixture = _guideFocusFixture();
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      final guide = tester.widget<GuideView>(find.byType(GuideView)).controller;
      final search = find.byKey(const Key('guide-channel-search'));
      final searchFocus = tester.widget<TextField>(search).focusNode!;
      final liveStart = guide.windowStart;
      await tester.enterText(search, 'News');
      await tester.pumpAndSettle();

      for (final throughMenu in [false, true]) {
        final button = find.byTooltip('Clear search');
        final invoker = _controlFocus(tester, button);
        invoker.requestFocus();
        await tester.pump();
        expect(invoker.hasPrimaryFocus, isTrue);
        if (throughMenu) {
          await tester.sendKeyEvent(LogicalKeyboardKey.f2);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('immersive-app-menu')), findsNothing);
          expect(_controlFocus(tester, button), same(invoker));
          expect(invoker.context?.mounted, isTrue);
          expect(invoker.hasPrimaryFocus, isTrue);
        }

        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(guide.searchQuery, isEmpty);
        expect(button, findsNothing);
        expect(searchFocus.hasPrimaryFocus, isTrue);
        // Use the live input connection without asking the test harness to
        // focus the field again: clearing must leave search ready to edit.
        tester.testTextInput.enterText('News');
        await tester.pumpAndSettle();
        expect(guide.searchQuery, 'news');
        expect(guide.windowStart, liveStart);
        expect(find.byType(GuideView), findsOneWidget);
        expect(fixture.player.loads, isEmpty);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('menu return falls back when the Guide invoker is removed', (
    tester,
  ) async {
    final fixture = _guideFocusFixture();
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    final guide = tester.widget<GuideView>(find.byType(GuideView)).controller;
    guide.setLibraryFilter('movies');
    await tester.pumpAndSettle();
    _controlFocus(
      tester,
      find.byTooltip('Remove library filter'),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
    guide.setLibraryFilter(null);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove library filter'), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shell keeps the deliberate destination inventory and focus', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fixture = UiFixture(
      scenario: LineupScenario(stage: SetupStage.ready),
    );
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(
      tester
          .widget<ExcludeSemantics>(
            find.byKey(const Key('immersive-route-semantics')),
          )
          .excluding,
      isFalse,
    );
    await tester.tap(find.byKey(const Key('guide-app-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
    expect(
      tester
          .widget<ExcludeSemantics>(
            find.byKey(const Key('immersive-route-semantics')),
          )
          .excluding,
      isTrue,
    );
    await tester.tap(find.text('Guide').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('immersive-app-menu')), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide Lineup menu');

    await tester.tap(find.byKey(const Key('guide-app-menu')));
    await tester.pumpAndSettle();
    for (var index = 0; index < 12; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<Card>()
            ?.key,
        const Key('immersive-app-menu'),
      );
    }
    for (final label in ['Guide', 'Player', 'Channels', 'Settings']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.byKey(const Key('app-menu-account')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Account')), findsOneWidget);
    await tester.tap(find.text('Channels').last);
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Channels');
    expect(find.byType(NavigationRail), findsNothing);

    await openDestination(tester, 'Settings');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Settings');
    await tester.tap(find.widgetWithText(TextButton, 'Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Diagnostics'));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Diagnostics');
  });

  testWidgets('Settings preserves logical desktop layout at DPR2', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(3840, 2160);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fixture = UiFixture(
      scenario: LineupScenario(stage: SetupStage.ready),
    );
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    await openDestination(tester, 'Settings');

    final rail = find.byKey(const Key('settings-category-rail'));
    expect(MediaQuery.sizeOf(tester.element(rail)), const Size(1920, 1080));
    expect(tester.getSize(rail).width, 312);
    expect(tester.takeException(), isNull);
  });

  testWidgets('channel deletion requires explicit destructive confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = UiFixture(
      scenario: LineupScenario(stage: SetupStage.ready, channels: [_channel()]),
    );
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await tester.pump();
    await openDestination(tester, 'Channels');

    await tester.tap(find.byTooltip('Actions for Newsroom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 1 channel?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fixture.controller.channels, hasLength(1));
    expect(find.byTooltip('Actions for Newsroom'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Open Newsroom');

    await tester.tap(find.byTooltip('Actions for Newsroom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete channel'));
    await tester.pumpAndSettle();
    expect(fixture.controller.channels, isEmpty);
  });

  testWidgets('channel deletion cancellation tolerates a removed opener', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = UiFixture(
      scenario: LineupScenario(stage: SetupStage.ready, channels: [_channel()]),
    );
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await tester.pump();
    await openDestination(tester, 'Channels');

    await tester.tap(find.byTooltip('Actions for Newsroom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    fixture.controller
      ..fixtureActor.replaceChannels(const [])
      ..notifyListeners();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

Channel _channel() => Channel(
  id: 'newsroom',
  number: 7,
  name: 'Newsroom',
  source: const LibrarySource(
    libraryId: 'movies',
    libraryType: PlexLibraryType.movie,
  ),
  playbackMode: PlaybackMode.shuffle,
  anchor: DateTime.utc(2026),
  shuffleSeed: 7,
);

FocusNode _controlFocus(WidgetTester tester, Finder control) => Focus.of(
  tester.element(
    find
        .descendant(
          of: control,
          matching: find.byWidgetPredicate(
            (widget) => widget is Icon || widget is Text,
          ),
        )
        .first,
  ),
);

UiFixture _guideFocusFixture() => UiFixture(
  guideClock: () => DateTime.utc(2026, 10, 18, 16),
  controller: _GuideFocusController(),
);

class _GuideFocusController extends FixtureController {
  _GuideFocusController()
    : super(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          channels: [_channel()],
          availableMedia: [
            PlexMediaItem(
              id: 'news',
              title: 'News',
              type: 'movie',
              libraryId: 'movies',
              duration: const Duration(minutes: 30),
              parts: [PlexMediaPart(path: '/synthetic-news')],
            ),
          ],
        ),
      );

  // Exercise shell interaction with real schedule policy and deterministic IO.
  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async => buildSchedule(
    resolveContent(channel.source, availableMedia),
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
  );
}
