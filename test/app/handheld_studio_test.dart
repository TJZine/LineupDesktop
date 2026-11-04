import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_studio_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/channels_view.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/content_resolver.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/handheld_management.dart';
import 'package:lineup_desktop/ui/lineup_controls.dart';
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

void main() {
  for (final (size, dpr) in _windows) {
    for (final textScale in [1.0, 1.3, 2.0]) {
      testWidgets(
        'Studio handheld layout ${size.width}×${size.height} @$dpr text $textScale',
        (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          try {
            _window(tester, size, dpr);
            await tester.runAsync(loadPinnedTestFonts);
            final controller = _StudioController(scenario: _studioScenario());
            addTearDown(controller.dispose);
            await tester.pumpWidget(_studio(controller, textScale));
            await tester.pumpAndSettle();

            final stacked = size.width != 1280 || textScale == 2;
            expect(
              find.byType(HandheldPageBar),
              stacked ? findsOneWidget : findsNothing,
            );
            expect(find.textContaining('Alt+Up/Down reorders'), findsNothing);
            expect(tester.takeException(), isNull);

            await _reachable(
              tester,
              find
                  .ancestor(
                    of: find.byKey(const Key('studio-tune')),
                    matching: find.byType(LineupTouchTarget),
                  )
                  .last,
              touch: true,
            );
            await _reachable(
              tester,
              find
                  .ancestor(
                    of: find.widgetWithText(FilledButton, 'Save changes'),
                    matching: find.byType(LineupTouchTarget),
                  )
                  .last,
              touch: true,
            );

            if (stacked) {
              expect(find.text('Back to Channels'), findsNothing);
              final back = find.byTooltip('Back to Channels').last;
              expect(back, findsOneWidget);
              expect(find.text('Edit custom channel · Saved'), findsOneWidget);
              _checkWords(tester);

              final identity = find.byKey(const Key('studio-identity'));
              expect(identity, findsOneWidget);
              final identityStacks =
                  tester.getSize(identity).width / textScale < 420;
              final nameLabel = find.text('Channel name');
              final numberLabel = find.text('Number');
              expect(nameLabel, findsOneWidget);
              expect(numberLabel, findsOneWidget);
              final numberTop = tester.getTopLeft(numberLabel).dy;
              final nameBottom = tester.getBottomLeft(nameLabel).dy;
              expect(
                numberTop,
                identityStacks
                    ? greaterThan(nameBottom)
                    : lessThanOrEqualTo(nameBottom),
              );

              expect(tester.takeException(), isNull);
            }

            await tester.ensureVisible(find.textContaining('Channel programs'));
            expect(find.text('Move to…'), findsWidgets);
            await _reachable(
              tester,
              find
                  .ancestor(
                    of: find.text('Move to…').last,
                    matching: find.byType(LineupTouchTarget),
                  )
                  .last,
              touch: true,
              scrollStudio: true,
            );
            await _reachable(
              tester,
              find
                  .ancestor(
                    of: find.byTooltip('Remove from channel').last,
                    matching: find.byType(LineupTouchTarget),
                  )
                  .last,
              touch: true,
              scrollStudio: true,
            );
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  }

  for (final useArrow in [true, false]) {
    for (final draft in ['clean', 'pending choice', 'dirty']) {
      testWidgets('Studio ${useArrow ? 'arrow' : 'system'} Back with $draft', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          _window(tester, const Size(412, 915), 2.625);
          await tester.runAsync(loadPinnedTestFonts);
          final controller = _StudioController(scenario: _studioScenario());
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            UiFixture(controller: controller, profile: _handheld).build(),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Channels'));
          await tester.pumpAndSettle();
          expect(find.byType(ChannelsView), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('channel-row-studio-channel')),
          );
          await tester.pumpAndSettle();
          if (draft != 'clean') {
            await tester.enterText(
              find.byKey(const Key('studio-name')),
              'Edited',
            );
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
          }
          if (draft == 'pending choice') {
            final browse = find.byKey(const Key('studio-manual-browse-stage'));
            await _reachable(tester, browse, scrollStudio: true);
            await tester.tap(browse);
            await tester.pumpAndSettle();
            final select = find.text('Select');
            await _reachable(tester, select, scrollStudio: true);
            await tester.tap(select);
            await tester.pumpAndSettle();
            expect(find.text('Show selected'), findsOneWidget);
          }

          if (useArrow) {
            final back = find.byTooltip('Back to Channels').last;
            await _reachable(tester, back, touch: true);
            await tester.tap(back);
          } else {
            await tester.binding.handlePopRoute();
          }
          await tester.pumpAndSettle();
          if (draft == 'clean') {
            expect(find.byType(ChannelStudioView), findsNothing);
            expect(
              find.byKey(const ValueKey('channel-row-studio-channel')),
              findsOneWidget,
            );
          } else {
            expect(find.byType(ChannelStudioView), findsOneWidget);
            expect(find.text('Show selected'), findsNothing);
            expect(
              find.text('Discard changes?'),
              draft == 'dirty' ? findsOneWidget : findsNothing,
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}

Widget _studio(_StudioController controller, double textScale) => MaterialApp(
  theme: LineupTheme.forName(
    LineupThemeName.emberSteel,
    formFactor: FormFactor.handheld,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: true,
    ),
    child: DeviceProfileScope(
      profile: _handheld,
      child: LineupCanvas(child: child!),
    ),
  ),
  home: Scaffold(
    body: ChannelStudioView(
      controller: controller,
      mode: ChannelStudioMode.editCustom,
      channel: controller.channels.single,
      onBack: (_) async {},
      onSaved: (_) {},
      onDuplicate: (_) {},
      onOpenGenerateLineup: () async {},
      onTune: (_) async => false,
      clock: () => DateTime.utc(2026),
    ),
  ),
);

LineupScenario _studioScenario() {
  const first = ChannelItem(
    id: 'program-1',
    title: 'First program',
    duration: Duration(minutes: 30),
  );
  const second = ChannelItem(
    id: 'program-2',
    title: 'Second program',
    duration: Duration(minutes: 45),
  );
  final channel = Channel(
    id: 'studio-channel',
    number: 7,
    name: 'Documentaries',
    source: ManualSource([first, second]),
    playbackMode: PlaybackMode.sequential,
    anchor: DateTime.utc(2026),
    shuffleSeed: 7,
  );
  return LineupScenario(
    stage: SetupStage.ready,
    channels: [channel],
    availableMedia: [
      PlexMediaItem(
        id: 'program-1',
        title: 'First program',
        type: 'movie',
        duration: Duration(minutes: 30),
        parts: [PlexMediaPart(path: '/program-1')],
      ),
      PlexMediaItem(
        id: 'program-2',
        title: 'Second program',
        type: 'movie',
        duration: Duration(minutes: 45),
        parts: [PlexMediaPart(path: '/program-2')],
      ),
    ],
  );
}

class _StudioController extends FixtureController {
  _StudioController({super.scenario});

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async => buildSchedule(
    resolveContent(channel.source, availableMedia, availablePlaylists),
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
    scheduleVersion: channel.scheduleVersion,
  );
}

Future<void> _reachable(
  WidgetTester tester,
  Finder control, {
  bool touch = false,
  bool scrollStudio = false,
}) async {
  expect(control, findsOneWidget);
  final studioScroll = find.descendant(
    of: find.byKey(const Key('studio-scroll')),
    matching: find.byType(Scrollable),
  );
  if (scrollStudio && studioScroll.evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(
      control,
      -80,
      scrollable: studioScroll.first,
    );
  }
  await tester.ensureVisible(control);
  if (scrollStudio && studioScroll.evaluate().isNotEmpty) {
    final position = tester.state<ScrollableState>(studioScroll.first).position;
    if (position.pixels > 0) {
      position.jumpTo(
        (position.pixels - 80).clamp(0.0, position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
  }
  await tester.pumpAndSettle();
  expectHandheldTarget(tester, control, touch: touch);
}

void _window(WidgetTester tester, Size size, double dpr) {
  tester.view
    ..devicePixelRatio = dpr
    ..physicalSize = size * dpr;
  addTearDown(tester.view.reset);
}

void _checkWords(WidgetTester tester) {
  final paragraphs = [
    ...tester.renderObjectList<RenderParagraph>(
      find.descendant(
        of: find.byKey(const ValueKey('handheld-page-bar-title')),
        matching: find.byType(RichText),
      ),
    ),
    for (final finder in [
      find.text('First program'),
      find.text('Second program'),
      find.text('Programming'),
      find.textContaining('Channel programs'),
      find.text('Channel name'),
    ])
      ...tester.renderObjectList<RenderParagraph>(finder),
  ];

  expectHandheldWords(paragraphs);
}
