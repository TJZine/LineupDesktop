import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_filter.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/guide/guide_playback_placeholder.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/golden_test_support.dart';
import '../support/ui_fixture.dart';

void main() {
  setUpAll(loadPinnedTestFonts);
  for (final tv in [false, true]) {
    testWidgets('merged Guide bar order and search lifecycle TV=$tv', (
      tester,
    ) async {
      final guide = await _mount(tester, tv: tv);
      final top = find.byKey(const ValueKey('lineup-top-bar'));
      expect(tester.getSize(top).height, 72);
      final controls = [
        'guide-channel-filter',
        'guide-earlier',
        'guide-now',
        'guide-later',
        'guide-hours',
        'guide-search-button',
      ];
      double previous = 0;
      for (final key in controls) {
        final rect = tester.getRect(find.byKey(Key(key)));
        expect(rect.top, greaterThanOrEqualTo(tester.getTopLeft(top).dy));
        expect(rect.bottom, lessThanOrEqualTo(tester.getBottomLeft(top).dy));
        expect(rect.left, greaterThan(previous));
        previous = rect.left;
      }
      expect(find.byKey(const Key('guide-channel-search')), findsNothing);
      await tester.tap(find.byKey(const Key('guide-search-button')));
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('guide-channel-search'));
      expect(search, findsOneWidget);
      expect(find.byKey(const Key('guide-hours')), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        tv ? 'Guide channel search' : isNotNull,
      );
      await tester.enterText(search, 'Signal');
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(search, findsOneWidget);
      expect(guide.searchQuery, 'signal');
      await tester.tap(search);
      await tester.pumpAndSettle();
      if (tv) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(guide.searchQuery, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(search, findsNothing);
      expect(find.byKey(const Key('guide-search-button')), findsOneWidget);
      guide.setChannelFilter((
        group: ChannelFilterGroup.sourceType,
        value: 'custom',
      ));
      await tester.pumpAndSettle();
      final label = find.byKey(const Key('guide-active-channel-filter-label'));
      expect(label, findsOneWidget);
      expect(
        tester.getTopLeft(label).dx,
        lessThan(tester.getTopLeft(find.byKey(const Key('guide-earlier'))).dx),
      );
    });
  }
  for (final tv in [false, true]) {
    testWidgets('merged bar horizontal focus and grid return TV=$tv', (
      tester,
    ) async {
      final guide = await _mount(tester, tv: tv);
      tester
          .widget<TextButton>(find.byKey(const Key('guide-app-menu')))
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Guide channel filter',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide now');
      final channel = guide.focusedChannelId;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide grid');
      expect(guide.focusedChannelId, channel);
      if (tv) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          isNot('Guide grid'),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(guide.focusedChannelId, channel);
      }
    });
  }
  testWidgets('merged TV recovery wrap reaches actions and restores grid', (
    tester,
  ) async {
    var retries = 0;
    var next = 0;
    final guide = await _mount(
      tester,
      tv: true,
      picture: GuidePlaybackPlaceholder(
        unavailable: true,
        reduceMotion: true,
        onRetry: () => retries++,
        onNextChannel: () => next++,
      ),
    );
    guide.moveVertical(2);
    await tester.pumpAndSettle();
    final remembered = guide.focusedProgramId;
    Focus.of(
      tester.element(
        find
            .descendant(
              of: find.byKey(const Key('guide-channel-filter')),
              matching: find.text('All channels'),
            )
            .first,
      ),
    ).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_focusedButtonText(), 'Retry');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_focusedButtonText(), 'Next channel');
    expect((retries, next), (0, 0));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(next, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_focusedButtonText(), 'Retry');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Guide channel filter',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(retries, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide grid');
    expect(guide.focusedProgramId, remembered);
    expect(guide.focusedChannelId, 'c2');
  });
  for (final retry in [false, true]) {
    testWidgets(
      'TV recovery entry only targets visible enabled actions retry=$retry',
      (tester) async {
        await _mount(
          tester,
          tv: true,
          picture: GuidePlaybackPlaceholder(
            unavailable: true,
            reduceMotion: true,
            onNextChannel: retry ? () {} : null,
          ),
        );
        Focus.of(
          tester.element(
            find
                .descendant(
                  of: find.byKey(const Key('guide-channel-filter')),
                  matching: find.text('All channels'),
                )
                .first,
          ),
        ).requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        if (retry) {
          expect(_focusedButtonText(), 'Next channel');
        } else {
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Guide channel filter',
          );
        }
      },
    );
  }
  testWidgets('recovery shortcut leaves an open TV filter popup in charge', (
    tester,
  ) async {
    await _mount(
      tester,
      tv: true,
      picture: GuidePlaybackPlaceholder(
        unavailable: true,
        reduceMotion: true,
        onRetry: () {},
      ),
    );
    await tester.tap(find.byKey(const Key('guide-channel-filter')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_focusedButtonText(), isNot('Retry'));
    expect(find.byType(LineupDropdownMenuRow), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });
  for (final scale in [1.0, 1.3, 1.69]) {
    testWidgets('TV Guide row count follows measured floor scale=$scale', (
      tester,
    ) async {
      await _mount(tester, tv: true, scale: scale);
      final list = find.byKey(const Key('guide-schedule-list'));
      final extent = tester.widget<ListView>(list).itemExtent!;
      final count = tester.getSize(list).height / extent;
      expect(count, closeTo(scale <= 1.3 ? 6 : 5, .00001));
      expect(tester.takeException(), isNull);
    });
  }
  for (final scale in [1.5, 2.0]) {
    testWidgets('narrow enlarged Guide retains wrapping layout scale=$scale', (
      tester,
    ) async {
      await _mount(tester, size: const Size(1280, 720), scale: scale);
      expect(
        tester.getSize(find.byKey(const ValueKey('lineup-top-bar'))).height,
        80,
      );
      expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
      expect(find.byKey(const Key('guide-search-button')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<GuideController> _mount(
  WidgetTester tester, {
  bool tv = false,
  double scale = 1,
  Size size = const Size(1920, 1080),
  DateTime? now,
  List<ChannelItem>? items,
  Widget picture = const ColoredBox(color: Color(0xff17292f)),
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  now ??= DateTime(2026, 11, 16, 12, 18);
  final channels = List.generate(
    20,
    (i) => Channel(
      id: 'c$i',
      number: i + 1,
      name: 'Signal House $i',
      source: ManualSource(
        items ??
            List.generate(
              8,
              (j) => ChannelItem(
                id: 'p$i-$j',
                title: 'The Last Frequency',
                showTitle: 'Signal House',
                seasonNumber: 2,
                episodeNumber: j + 1,
                duration: const Duration(minutes: 48),
              ),
            ),
      ),
      playbackMode: PlaybackMode.sequential,
      anchor: now!.subtract(const Duration(minutes: 18)),
      shuffleSeed: i,
    ),
  );
  final lineup = FixtureController(
    scenario: LineupScenario(
      stage: SetupStage.ready,
      channels: channels,
      settings: const LineupSettings(reduceMotion: true),
    ),
  );
  final guide = GuideController(
    lineup: lineup,
    clock: () => now!,
    loadSchedule: (c) async =>
        buildChannelSchedule(c, (c.source as ManualSource).items),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });
  await tester.pumpWidget(
    DeviceProfileScope(
      profile: profileFor(tv),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: LineupTheme.forName(
          LineupThemeName.emberSteel,
          formFactor: profileFor(tv).formFactor,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: LineupCanvas(child: child!),
        ),
        home: GuideView(
          controller: guide,
          pictureInPicture: picture,
          watchingChannelId: 'c0',
          onOpenMenu: (_, _) {},
          onClose: (_, _) {},
          onTune: (_) async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return guide;
}

String? _focusedButtonText() {
  final widget = FocusManager.instance.primaryFocus?.context
      ?.findAncestorWidgetOfExactType<TextButton>();
  return widget?.child is Text ? (widget!.child as Text).data : null;
}
