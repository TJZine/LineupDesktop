import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/lineup_controls.dart';

import '../support/ui_fixture.dart';

void main() {
  for (final tv in [false, true]) {
    testWidgets(
      'Settings rail selects ${tv ? 'on TV dwell' : 'on desktop activation'}',
      (tester) async {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = const Size(1920, 1080);
        addTearDown(tester.view.reset);
        final fixture = UiFixture(
          profile: profileFor(tv),
          scenario: const LineupScenario(
            stage: SetupStage.ready,
            settings: LineupSettings(reduceMotion: true),
          ),
        );
        addTearDown(fixture.controller.dispose);
        await tester.pumpWidget(fixture.build());
        await tester.pumpAndSettle();
        if (tv) {
          await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Settings').last);
          await tester.pumpAndSettle();
        } else {
          await openDestination(tester, 'Settings');
        }
        final settings = find.text('Settings');
        expect(tester.widget<Text>(settings).style!.fontSize, 16);
        final pane = find.byKey(const Key('settings-detail-pane'));
        final heading = find.descendant(
          of: pane,
          matching: find.text('Appearance'),
        );
        expect(tester.widget<Text>(heading).style!.fontSize, greaterThan(16));
        expect(find.text('Theme'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 80));
        expect(find.text('Theme'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 149));
        expect(find.text('Theme'), findsOneWidget);
        expect(find.text('Visible hours'), findsNothing);
        await tester.pump(const Duration(milliseconds: 1));
        final pause = find.text('Pause and seek controls');
        if (tv) {
          expect(pause, findsOneWidget);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Settings playback',
          );
          // Right also commits the newly focused category without waiting for
          // dwell. Its first available control receives focus in the same move.
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(find.text('Visible hours'), findsOneWidget);
          final focus = FocusManager.instance.primaryFocus;
          final hours = tester.element(
            find.byKey(const ValueKey('settings-field-Visible hours')),
          );
          expect(focus?.context, isNotNull);
          bool isInHours = false;
          focus?.context?.visitAncestorElements((element) {
            if (element != hours) return true;
            isInHours = true;
            return false;
          });
          expect(isInHours, isTrue);
          final subtitleButton = find.widgetWithText(TextButton, 'Subtitles');
          tester.widget<TextButton>(subtitleButton).focusNode!.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pump();
          expect(find.byKey(const ValueKey('subtitle-rows')), findsOneWidget);
        } else {
          expect(find.text('Theme'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(pause, findsOneWidget);
        }

        await tester.tap(find.widgetWithText(TextButton, 'Account'));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('Plex Home profile')).dx,
          closeTo(
            tester.getTopLeft(find.text('Show profile picker on startup')).dx,
            .01,
          ),
        );
        expect(
          tester.getTopLeft(find.text('Plex Media Server')).dx,
          closeTo(
            tester.getTopLeft(find.text('Show profile picker on startup')).dx,
            .01,
          ),
        );
        if (tv) {
          final label = find.text('Show profile picker on startup');
          final surface = find.ancestor(
            of: label,
            matching: find.byType(LineupRowSurface),
          );
          final toggle = find.descendant(
            of: surface,
            matching: find.byType(Switch),
          );
          expect(tester.getRect(label).left - tester.getRect(surface).left, 16);
          expect(
            tester.getRect(surface).right - tester.getRect(toggle).right,
            16,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
