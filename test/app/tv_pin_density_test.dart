import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

import '../support/golden_test_support.dart';
import '../support/ui_fixture.dart';

void main() {
  for (final scale in [1.0, 1.15, 1.3]) {
    for (final large in [false, true]) {
      for (final long in [false, true]) {
        testWidgets('TV complete PIN scale=$scale large=$large long=$long', (
          tester,
        ) async {
          await tester.runAsync(loadPinnedTestFonts);
          tester.view
            ..physicalSize = const Size(1920, 1080)
            ..devicePixelRatio = 2;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final user = PlexHomeUser(
            id: 'protected',
            name: long
                ? 'A deliberately long profile name with a second line and an ellipsis'
                : 'Viewer',
            protected: true,
          );
          final controller = _PinController(
            scenario: LineupScenario(
              stage: SetupStage.profiles,
              profiles: [user],
              settings: LineupSettings(
                largeFocusIndicators: large,
                reduceMotion: large,
              ),
            ),
          );
          final fixture = UiFixture(
            controller: controller,
            profile: profileFor(true),
          );
          final capture = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(key: capture, child: fixture.build()),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(
            () => precacheImage(
              const AssetImage('assets/branding/lineup-logo-mark.png'),
              tester.element(
                find.byKey(const ValueKey('profile-card-protected')),
              ),
            ),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('profile-pin-sheet')), findsOneWidget);
          for (final error in [false, true]) {
            if (error) {
              for (var digit = 0; digit < 4; digit++) {
                await tester.sendKeyEvent(LogicalKeyboardKey.select);
                await tester.pumpAndSettle();
              }
              expect(controller.submitted, ['1111']);
              expect(
                find.byKey(const Key('profile-pin-error')),
                findsOneWidget,
              );
            }
            final dir = Platform.environment['R7_CAPTURE'];
            if (dir != null) {
              await tester.runAsync(() async {
                await Directory(dir).create(recursive: true);
                final image =
                    await (capture.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage(pixelRatio: 2);
                expect(image.width, 1920);
                expect(image.height, 1080);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '$dir/pin-$scale-large$large-long$long-error$error.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            expect(
              tester.getRect(find.byKey(const Key('profile-pin-status'))).top -
                  tester
                      .getRect(find.byKey(const Key('profile-pin-progress')))
                      .bottom,
              closeTo(8, .001),
              reason: 'PIN retains the desktop 16cu gap at canvas scale .5',
            );
            final scrolls = find.descendant(
              of: find.byKey(const Key('profile-pin-sheet')),
              matching: find.byType(Scrollable),
            );
            for (final element in scrolls.evaluate()) {
              final state = tester.state<ScrollableState>(
                find.byElementPredicate((e) => e == element),
              );
              expect(
                state.position.maxScrollExtent,
                0,
                reason: 'The full PIN task must fit before focus can reveal a clipped control',
              );
              expect(state.position.pixels, 0);
            }
            for (final field in [
              find.text(user.name).last,
              find.byKey(const Key('profile-pin-progress')),
              find.byKey(const Key('profile-pin-status')),
              find.widgetWithText(TextButton, 'Cancel'),
              find.widgetWithText(OutlinedButton, '1'),
              find.widgetWithText(OutlinedButton, '0'),
            ]) {
              final rect = tester.getRect(field).inflate(large ? 1.5 : 0);
              expect(rect.top, greaterThanOrEqualTo(0));
              expect(rect.bottom, lessThanOrEqualTo(540));
            }
            if (error) {
              final text = find.descendant(
                of: find.byKey(const Key('profile-pin-error')),
                matching: find.byType(RichText),
              );
              final paragraph = tester.renderObject<RenderParagraph>(text);
              final painter = TextPainter(
                text: paragraph.text,
                textScaler: paragraph.textScaler,
                textDirection: paragraph.textDirection,
              )..layout(maxWidth: paragraph.size.width);
              expect(
                paragraph.size.height,
                greaterThanOrEqualTo(painter.height),
                reason: 'The complete error glyphs must fit',
              );
              painter.dispose();
            }
          }
          // Traverse the actual control grid to Cancel, then activate it.
          for (var move = 0; move < 4; move++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pumpAndSettle();
          }
          expect(
            Focus.of(tester.element(find.text('Cancel'))).hasFocus,
            isTrue,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
          expect(
            Focus.of(tester.element(find.text(user.name).last)).hasFocus,
            isTrue,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        });
      }
    }
  }
}

class _PinController extends FixtureController {
  _PinController({super.scenario});
  final submitted = <String>[];
  @override
  Future<bool> selectProfile(PlexHomeUser user, {String? pin}) async {
    submitted.add(pin ?? '');
    fixtureActor.present(
      LineupPresentation(
        error: (
          'The profile could not be selected. Check your connection and try again.',
        ),
      ),
    );
    return false;
  }
}
