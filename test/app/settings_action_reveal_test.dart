import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

import '../support/golden_test_support.dart';
import '../support/ui_fixture.dart';

const _viewer = PlexHomeUser(
  id: 'viewer',
  name: 'Synthetic long viewer name for multiline values',
  protected: false,
);
const _server = PlexServer(
  id: 'server',
  name: 'Synthetic long server name for multiline Settings values',
  connections: [],
);

UiFixture _fixture({
  required bool tv,
  bool large = false,
  bool reduce = false,
}) => UiFixture(
  profile: profileFor(tv),
  guideClock: () => DateTime(2026, 1, 15, 12),
  scenario: LineupScenario(
    stage: SetupStage.ready,
    profile: _viewer,
    profiles: const [_viewer],
    server: _server,
    servers: const [_server],
    account: const PlexAccount(
      id: 'account',
      name: 'Synthetic account',
      email: 'fixture@example.invalid',
    ),
    settings: LineupSettings(largeFocusIndicators: large, reduceMotion: reduce),
  ),
);

Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Container)).first;

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool instant = false,
}) async {
  await tester.sendKeyEvent(key);
  if (instant) {
    // Focus settles and the post-layout reveal executes without an animation.
    await tester.pump();
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final scale in [1.0, 1.15, 1.3]) {
    for (final large in [false, true]) {
      for (final reduce in [false, true]) {
        testWidgets(
          'C3 Settings actions reveal context in both directions scale=$scale large=$large reduce=$reduce',
          (tester) async {
            await tester.runAsync(loadPinnedTestFonts);
            tester.view
              ..physicalSize = const Size(960, 540)
              ..devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            final fixture = _fixture(tv: true, large: large, reduce: reduce);
            final capture = GlobalKey();
            final violations = <String>[];
            final observations = <Map<String, Object?>>[];
            final tag = 'tv-scale$scale-large$large-reduce$reduce';
            try {
              await tester.pumpWidget(
                RepaintBoundary(key: capture, child: fixture.build()),
              );
              await tester.pumpAndSettle();
              // Faithful native recipe: Guide Menu -> Settings -> Account.
              await _key(tester, LogicalKeyboardKey.contextMenu);
              await _key(tester, LogicalKeyboardKey.arrowDown);
              await _key(tester, LogicalKeyboardKey.arrowDown);
              await _key(tester, LogicalKeyboardKey.select);
              for (var i = 0; i < 4; i++) {
                await _key(tester, LogicalKeyboardKey.arrowDown);
              }
              await _key(tester, LogicalKeyboardKey.select);
              await _key(
                tester,
                LogicalKeyboardKey.arrowRight,
                instant: reduce,
              );

              // Right enters the spatially nearest Account control. Canvas and
              // text density can place that on a later row; walk the real remote
              // path to the first row before checking the complete down/up tour.
              for (
                var i = 0;
                i < 3 &&
                    !Focus.of(tester.element(_row('Plex Home profile')))
                        .hasFocus;
                i++
              ) {
                await _key(tester, LogicalKeyboardKey.arrowUp, instant: reduce);
              }

              Future<void> inspect(
                String title,
                String? action,
                String stop,
              ) async {
                final row = _row(title);
                final viewport = find
                    .ancestor(
                      of: find.text(title),
                      matching: find.byType(ListView),
                    )
                    .first;
                final rect = tester.getRect(row);
                final view = tester.getRect(viewport);
                final owner = FocusManager.instance.primaryFocus!;
                final rowElement = tester.element(row);
                expect(owner.context, isNotNull);
                expect(Focus.of(rowElement).hasFocus, isTrue);
                final scale =
                    rect.width / tester.renderObject<RenderBox>(row).size.width;
                // Existing filled toggle rows also reveal the Large frame clearance.
                final clearance = large && action == null
                    ? LineupFocusFrame.contentClearance * scale
                    : 0.0;
                if (rect.top - clearance < view.top - .1 ||
                    rect.bottom + clearance > view.bottom + .1) {
                  violations.add(
                    '$stop $title: whole row $rect + clearance $clearance outside $view',
                  );
                }
                expect(rect.left, greaterThanOrEqualTo(view.left - .1));
                expect(rect.right, lessThanOrEqualTo(view.right + .1));
                if (action != null) {
                  final button = find.widgetWithText(OutlinedButton, action);
                  final widget = tester.widget<OutlinedButton>(button);
                  expect(
                    owner.context!
                        .findAncestorWidgetOfExactType<OutlinedButton>(),
                    same(widget),
                  );
                  final control = tester.getRect(button);
                  if (control.top < view.top - .1 ||
                      control.bottom > view.bottom + .1) {
                    violations.add(
                      '$stop $action: focused button/frame $control outside $view',
                    );
                  }
                  // Plain action rows retain their quiet body; only the button fills.
                  expect(
                    find.ancestor(
                      of: find.text(title),
                      matching: find.byType(LineupRowSurface),
                    ),
                    findsNothing,
                  );
                  expect(
                    (tester.widget<Container>(row).decoration! as BoxDecoration)
                        .color,
                    isNull,
                  );
                } else {
                  expect(
                    owner.context!.findAncestorWidgetOfExactType<Switch>(),
                    isNotNull,
                  );
                }
                if (title == 'Plex Home profile') {
                  final avatar = find.descendant(
                    of: row,
                    matching: find.byType(LineupProfileAvatar),
                  );
                  expect(avatar, findsOneWidget);
                  final avatarRect = tester.getRect(avatar);
                  if (avatarRect.top < view.top - .1 ||
                      avatarRect.bottom > view.bottom + .1) {
                    violations.add('$stop avatar $avatarRect outside $view');
                  }
                }
                observations.add({
                  'stop': stop,
                  'title': title,
                  'row': _rect(rect),
                  'viewport': _rect(view),
                  'clearance': clearance,
                  'owner': owner.debugLabel,
                });
                await _capture(tester, capture, '$tag-$stop');
              }

              await inspect(
                'Plex Home profile',
                'Switch profile',
                'account-down-0',
              );
              await _key(tester, LogicalKeyboardKey.arrowDown, instant: reduce);
              await inspect(
                'Show profile picker on startup',
                null,
                'account-down-1',
              );
              await _key(tester, LogicalKeyboardKey.arrowDown, instant: reduce);
              await inspect(
                'Plex Media Server',
                'Switch server',
                'account-down-2',
              );
              await _key(tester, LogicalKeyboardKey.arrowDown, instant: reduce);
              await inspect(
                'Signed-in Plex account',
                'Sign out of Plex',
                'account-down-3',
              );
              await _key(tester, LogicalKeyboardKey.arrowUp, instant: reduce);
              await inspect(
                'Plex Media Server',
                'Switch server',
                'account-up-0',
              );
              await _key(tester, LogicalKeyboardKey.arrowUp, instant: reduce);
              await inspect(
                'Show profile picker on startup',
                null,
                'account-up-1',
              );
              await _key(tester, LogicalKeyboardKey.arrowUp, instant: reduce);
              await inspect(
                'Plex Home profile',
                'Switch profile',
                'account-up-2',
              );

              await _key(tester, LogicalKeyboardKey.arrowLeft);
              for (
                var i = 0;
                i < 6 &&
                    !Focus.of(tester.element(find.text('Support').last))
                        .hasPrimaryFocus;
                i++
              ) {
                await _key(tester, LogicalKeyboardKey.arrowDown);
              }
              expect(
                Focus.of(tester.element(find.text('Support').last))
                    .hasPrimaryFocus,
                isTrue,
              );
              await _key(tester, LogicalKeyboardKey.select);
              await _key(
                tester,
                LogicalKeyboardKey.arrowRight,
                instant: reduce,
              );
              for (
                var i = 0;
                i < 3 &&
                    !Focus.of(
                      tester.element(_row('Record redacted diagnostics')),
                    ).hasFocus;
                i++
              ) {
                await _key(tester, LogicalKeyboardKey.arrowUp, instant: reduce);
              }
              await inspect(
                'Record redacted diagnostics',
                null,
                'support-down-0',
              );
              await _key(tester, LogicalKeyboardKey.arrowDown, instant: reduce);
              await inspect(
                'Diagnostics',
                'Open Diagnostics',
                'support-down-1',
              );
              await _key(tester, LogicalKeyboardKey.arrowDown, instant: reduce);
              await inspect('Licenses', 'Open Licenses', 'support-down-2');
              await _key(tester, LogicalKeyboardKey.arrowUp, instant: reduce);
              await inspect('Diagnostics', 'Open Diagnostics', 'support-up-0');
              await _key(tester, LogicalKeyboardKey.arrowUp, instant: reduce);
              await inspect(
                'Record redacted diagnostics',
                null,
                'support-up-1',
              );
              await _writeObservations(tester, tag, observations, violations);
              expect(
                violations,
                isEmpty,
                reason: 'Complete identifying context and focus paint at every stop',
              );
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              fixture.controller.dispose();
              tester.platformDispatcher.clearTextScaleFactorTestValue();
              tester.view.reset();
            }
          },
        );
      }
    }
  }

  for (final size in [const Size(1280, 720), const Size(1920, 1080)]) {
    testWidgets('Settings action desktop render $size', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.runAsync(loadPinnedTestFonts);
      await tester.binding.setSurfaceSize(size);
      final fixture = _fixture(tv: false);
      final capture = GlobalKey();
      try {
        await tester.pumpWidget(
          RepaintBoundary(key: capture, child: fixture.build()),
        );
        await tester.pumpAndSettle();
        await openDestination(tester, 'Settings');
        for (final category in ['Account', 'Support']) {
          await tester.tap(find.text(category).last);
          await tester.pumpAndSettle();
          for (final action
              in category == 'Account'
                  ? ['Switch profile', 'Switch server', 'Sign out of Plex']
                  : ['Open Diagnostics', 'Open Licenses']) {
            Focus.of(tester.element(find.text(action))).requestFocus();
            await tester.pumpAndSettle();
            await _capture(
              tester,
              capture,
              'desktop-${size.width.toInt()}-$action',
            );
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.controller.dispose();
        await tester.binding.setSurfaceSize(null);
        debugDefaultTargetPlatformOverride = null;
      }
    }, skip: Platform.environment['ACCOUNT_REVEAL_CAPTURE'] == null);
  }
}

List<double> _rect(Rect rect) => [rect.left, rect.top, rect.right, rect.bottom];
Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final dir = Platform.environment['ACCOUNT_REVEAL_CAPTURE'];
  if (dir == null) return;
  await tester.runAsync(() async {
    await Directory(dir).create(recursive: true);
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _writeObservations(
  WidgetTester tester,
  String name,
  List<Map<String, Object?>> stops,
  List<String> violations,
) async {
  final dir = Platform.environment['ACCOUNT_REVEAL_CAPTURE'];
  if (dir == null) return;
  await tester.runAsync(() async {
    await File('$dir/$name.json')
        .writeAsString(jsonEncode({'stops': stops, 'violations': violations}));
  });
}
