import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/golden_test_support.dart';
import '../support/ui_fixture.dart';

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets(
      'TV library menu keeps complete identifying names at scale=$scale',
      (tester) async {
        await tester.runAsync(loadPinnedTestFonts);
        tester.view
          ..physicalSize = const Size(1920, 1080)
          ..devicePixelRatio = 2;
        final now = DateTime.utc(2026, 10, 23, 12);
        final channels = [
          for (var i = 1; i <= 2; i++)
            Channel(
              id: 'library-$i',
              number: i,
              name: 'Channel $i',
              source: LibrarySource(
                libraryId: 'movies-$i',
                libraryType: PlexLibraryType.movie,
              ),
              playbackMode: PlaybackMode.sequential,
              anchor: now,
              shuffleSeed: i,
            ),
        ];
        final lineup = FixtureController(
          scenario: LineupScenario(
            stage: SetupStage.ready,
            channels: channels,
            libraries: [
              for (var i = 1; i <= 2; i++)
                PlexLibrary(
                  id: 'movies-$i',
                  title: 'Synthetic movies $i',
                  type: PlexLibraryType.movie,
                ),
            ],
          ),
        );
        final guide = GuideController(
          lineup: lineup,
          clock: () => now,
          loadSchedule: (channel) async => buildSchedule(
            const [
              ChannelItem(
                id: 'program',
                title: 'Synthetic program',
                duration: Duration(hours: 2),
              ),
            ],
            mode: channel.playbackMode,
            seed: channel.shuffleSeed,
          ),
        );
        try {
          await tester.pumpWidget(
            DeviceProfileScope(
              profile: profileFor(true),
              child: MaterialApp(
                theme: LineupTheme.forName(
                  LineupThemeName.emberSteel,
                  formFactor: profileFor(true).formFactor,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: Builder(
                    builder: (context) => LineupCanvas.builder(context, child),
                  ),
                ),
                home: SafeArea(
                  child: GuideView(
                    controller: guide,
                    pictureInPicture: const SizedBox.shrink(),
                    onClose: (_, _) {},
                    onTune: (_) async {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final picker = find.byKey(const Key('guide-library-picker'));
          final node = tester
              .widget<DropdownButton<String?>>(picker)
              .focusNode!;
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          node.requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          for (var i = 1; i <= 2; i++) {
            final text = find.text('Synthetic movies $i');
            expect(text, findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(text);
            final painter = TextPainter(
              text: paragraph.text,
              textDirection: paragraph.textDirection,
              textScaler: paragraph.textScaler,
            )..layout(maxWidth: paragraph.size.width);
            expect(
              paragraph.size.height + .01,
              greaterThanOrEqualTo(painter.height),
              reason: 'Final identifying digit must be painted',
            );
            painter.dispose();
            final item = find
                .ancestor(
                  of: text,
                  matching: find.byType(DropdownMenuItem<String?>),
                )
                .first;
            expect(
              tester.getRect(text).bottom,
              lessThanOrEqualTo(tester.getRect(item).bottom + .01),
            );
            expect(paragraph.textScaler.scale(18), closeTo(18 * scale, .01));
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          guide.dispose();
          lineup.dispose();
          tester.view.reset();
        }
      },
    );
  }
  for (final scale in [1.0, 1.3]) {
    for (final longName in [false, true]) {
      testWidgets(
        'TV placeholder keeps complete state text in its existing budget: scale=$scale long=$longName',
        (tester) async {
          await tester.runAsync(loadPinnedTestFonts);
          tester.view
            ..physicalSize = const Size(1920, 1080)
            ..devicePixelRatio = 2;
          final now = DateTime.utc(2026, 10, 23, 12);
          final channels = [
            for (var i = 0; i < 6; i++)
              Channel(
                id: 'channel-$i',
                number: i + 1,
                name: i == 0 && longName
                    ? 'A very long synthetic channel name that describes a complete collection of documentaries and historical programs'
                    : 'Synthetic channel ${i + 1}',
                source: const ManualSource([
                  ChannelItem(
                    id: 'program',
                    title: 'Synthetic program',
                    duration: Duration(hours: 2),
                  ),
                ]),
                playbackMode: PlaybackMode.sequential,
                anchor: now,
                shuffleSeed: i,
              ),
          ];
          final lineup = FixtureController(
            scenario: LineupScenario(
              stage: SetupStage.ready,
              settings: const LineupSettings(guideHours: 2, reduceMotion: true),
              channels: channels,
            ),
          );
          final first = Completer<ScheduleIndex>();
          final retry = Completer<ScheduleIndex>();
          var attempts = 0;
          final guide = GuideController(
            lineup: lineup,
            clock: () => now,
            loadSchedule: (channel) {
              if (channel.id == channels.first.id) {
                return ++attempts == 1 ? first.future : retry.future;
              }
              return Future.value(
                buildSchedule(
                  (channel.source as ManualSource).items,
                  mode: channel.playbackMode,
                  seed: channel.shuffleSeed,
                ),
              );
            },
          );
          try {
            await tester.pumpWidget(
              DeviceProfileScope(
                profile: profileFor(true),
                child: MaterialApp(
                  theme: LineupTheme.forName(
                    LineupThemeName.emberSteel,
                    formFactor: profileFor(true).formFactor,
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: Builder(
                      builder: (context) =>
                          LineupCanvas.builder(context, child),
                    ),
                  ),
                  home: SafeArea(
                    child: GuideView(
                      controller: guide,
                      pictureInPicture: const SizedBox.shrink(),
                      onClose: (_, _) {},
                      onTune: (_) async {},
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final details = find.byKey(const Key('guide-information-details'));
            var originalArea = tester.getRect(
              find.byKey(const Key('guide-information-area')),
            );
            void completeStatus(String status) {
              expect(tester.takeException(), isNull);
              final text = find.descendant(
                of: details,
                matching: find.text(status),
              );
              expect(text, findsOneWidget);
              final paragraph = tester.renderObject<RenderParagraph>(text);
              expect(paragraph.textScaler.scale(18), closeTo(18 * scale, .01));
              final painter = TextPainter(
                text: paragraph.text,
                textDirection: paragraph.textDirection,
                textScaler: paragraph.textScaler,
              )..layout(maxWidth: paragraph.size.width);
              expect(
                paragraph.size.height + .01,
                greaterThanOrEqualTo(painter.height),
                reason: 'Full status, not a clipped/ellipsized fit',
              );
              painter.dispose();
              final area = tester.getRect(details);
              final rect = tester.getRect(text);
              expect(rect.top, greaterThanOrEqualTo(area.top - .01));
              expect(rect.bottom, lessThanOrEqualTo(area.bottom + .01));
              expect(rect.left, greaterThanOrEqualTo(area.left - .01));
              expect(rect.right, lessThanOrEqualTo(area.right + .01));
              expect(
                tester.getRect(find.byKey(const Key('guide-information-area'))),
                originalArea,
              );
              final identity = find.descendant(
                of: details,
                matching: find.text('1 • ${channels.first.name}'),
              );
              expect(identity, findsOneWidget);
              expect(
                tester.getSemantics(identity).getSemanticsData().label,
                contains(channels.first.name),
              );
            }

            completeStatus('Loading schedule…');
            first.completeError(StateError('Synthetic unavailable schedule'));
            await tester.pumpAndSettle();
            completeStatus('Schedule unavailable');
            await guide.retry(channels.first.id);
            await tester.pumpAndSettle();
            completeStatus('Retrying…');
            retry.complete(
              buildSchedule(
                (channels.first.source as ManualSource).items,
                mode: channels.first.playbackMode,
                seed: 0,
              ),
            );
            await tester.pumpAndSettle();
            await lineup.updateSettings(
              (settings) => settings.copyWith(guideHours: 0),
            );
            await tester.pumpAndSettle();
            originalArea = tester.getRect(
              find.byKey(const Key('guide-information-area')),
            );
            completeStatus('No programs scheduled in this time range');
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            guide.dispose();
            lineup.dispose();
            tester.view.reset();
          }
        },
        semanticsEnabled: true,
      );
    }
  }
}
