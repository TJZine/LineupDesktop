import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/diagnostics_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/settings_view.dart';
import 'package:lineup_desktop/licenses/licenses_view.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/ui/handheld_management.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import 'package:lineup_desktop/ui/lineup_controls.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../support/golden_test_support.dart';
import '../support/ui_fixture.dart';

const _handheld = DeviceProfile(
  host: TargetPlatform.android,
  formFactor: FormFactor.handheld,
);
const _settingsTab = ValueKey('handheld-tab-settings');
const _profileAvatar = ValueKey('profile-card-taylor');
const _overwideProfileName =
    'Multiplatformregistrationmultiplatformregistrationmultiplatformregistration';

void main() {
  setUpAll(loadPinnedTestFonts);
  for (final (size, dpr) in const [
    (Size(412, 915), 2.625),
    (Size(360, 800), 3.0),
    (Size(800, 1280), 2.0),
    (Size(600, 960), 2.0),
    (Size(690, 840), 2.6),
    (Size(960, 600), 2.0),
    (Size(1280, 800), 2.0),
  ]) {
    for (final textScale in [1.0, 1.3, 2.0]) {
      _h4Test('handheld H4 controls at $size @$dpr text $textScale', (
        tester,
      ) async {
        // The initial Guide has its own separately audited text matrix.
        final startSize = size.width < 412 ? Size(412, size.height) : size;
        _window(tester, startSize, dpr, 1);
        final fixture = UiFixture(
          profile: _handheld,
          scenario: const LineupScenario(stage: SetupStage.ready),
        );
        await _pump(tester, fixture);
        await _openSettings(tester);
        tester.view.physicalSize = size * dpr;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        await tester.pumpAndSettle();
        final settings = find.byType(SettingsView);
        final settingsContext = tester.element(settings);
        final list = MediaQuery.sizeOf(settingsContext).width < 900;
        final playback = find
            .descendant(of: settings, matching: find.text('Playback'))
            .first;
        if (list) {
          await tester.ensureVisible(playback);
          await tester.pumpAndSettle();
          _oneTappableNode(tester, RegExp(r'Playback'));
          final row = find
              .ancestor(of: playback, matching: find.byType(TextButton))
              .first;
          expect(tester.getSize(row).height, greaterThanOrEqualTo(84));
          _wordsStayOnOneLine(tester, 'Playback');
          expect(find.text('‹ Back to Guide'), findsNothing);
        }
        await _tap(tester, playback);
        expect(find.text('DVR playback controls'), findsOneWidget);
        expect(find.text('Match display HDR in fullscreen'), findsNothing);
        if (list) {
          final back = find.byTooltip('Back to Settings');
          _oneTappableNode(tester, RegExp(r'^Back to Settings$'));
          await _tap(tester, back);
        }
        await _tap(tester, find.text('Subtitles').first);
        expect(find.byKey(const ValueKey('subtitle-rows')), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (list) {
          await _tap(tester, find.byTooltip('Back to Settings'));
        }
        await _tap(tester, find.text('Support').first);
        final openDiagnostics = find.text('Open Diagnostics');
        if (list) {
          tester.view.viewInsets = FakeViewPadding(bottom: 300 * dpr);
          await tester.pumpAndSettle();
          await tester.ensureVisible(openDiagnostics);
          await tester.pumpAndSettle();
          expect(openDiagnostics.hitTestable(), findsOneWidget);
          expect(
            tester.getCenter(openDiagnostics).dy,
            lessThan(size.height - 300),
          );
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pumpAndSettle();
        }
        await _tap(tester, openDiagnostics);
        final diagnostics = find.byType(DiagnosticsView);
        if (handheldStacked(tester.element(diagnostics))) {
          _oneTappableNode(tester, RegExp(r'^Back to Support$'));
          _oneTappableNode(tester, RegExp(r'^Copy redacted report$'));
        }
        await _tap(tester, find.text('Copy redacted report'));
        expect(find.text('Report copied'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await _tap(tester, find.text('Open Licenses'));
        expect(find.byType(LicensesView), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(LicensesView), findsNothing);
        expect(find.text('Open Licenses'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      _h4Test('profile grid and link display facts at $size text $textScale', (
        tester,
      ) async {
        _window(tester, size, dpr, textScale);
        final linking = UiFixture(
          profile: _handheld,
          scenario: LineupScenario(
            stage: SetupStage.linking,
            activePin: PlexPin(
              id: 7,
              code: 'ABCD',
              expiresAt: DateTime.now().add(const Duration(minutes: 4)),
            ),
          ),
        );
        await _pump(tester, linking);
        expect(
          find.byType(QrImageView),
          size.shortestSide < 600 ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('Or scan with your phone'),
          size.shortestSide < 600 ? findsNothing : findsOneWidget,
        );
        final browser = find.text('Open browser');
        await tester.ensureVisible(browser);
        await tester.pumpAndSettle();
        expect(browser.hitTestable(), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        final controller = _PinController();
        final profiles = UiFixture(profile: _handheld, controller: controller);
        await _pump(tester, profiles);
        final first = tester.getRect(find.byKey(_profileAvatar));
        final second = tester.getRect(
          find.byKey(const ValueKey('profile-card-guest')),
        );
        final third = tester.getRect(
          find.byKey(const ValueKey('profile-card-family')),
        );
        expect(first.top, second.top);
        if (size.width < 600) {
          expect(third.top, greaterThan(first.top));
        } else {
          expect(third.top, first.top);
        }
        expect(
          tester.getSize(find.byType(LineupProfileAvatar).first).width *
              LineupCanvas.scaleOf(tester.element(find.byKey(_profileAvatar))),
          closeTo(88, .001),
        );
        _wordsStayOnOneLine(
          tester,
          'A deliberately long synthetic profile name',
        );
        _wordsStayOnOneLine(tester, "Who's watching?");
        final card = find.byKey(_profileAvatar);
        final badges = find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                (widget.data == 'Restricted' || widget.data == 'Current'),
          ),
        );
        expect(badges, findsNWidgets(2));
        final cardRect = tester.getRect(card);
        for (final badge in badges.evaluate()) {
          final scale = MediaQuery.textScalerOf(badge);
          expect(scale.scale(14), closeTo(14 * math.min(textScale, 1.3), .01));
          expect(
            cardRect.contains(tester.getCenter(find.byWidget(badge.widget))),
            isTrue,
          );
        }
        _oneTappableNode(tester, RegExp(r'Taylor'));
        await _tap(tester, find.text('Taylor'));
        expect(tester.testTextInput.isVisible, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        expect(controller.pinAttempts, isEmpty);
        for (final digit in ['1', '2', '3', '4']) {
          await _tap(tester, find.text(digit).last);
          if (digit != '4') expect(controller.pinAttempts, isEmpty);
        }
        expect(controller.pinAttempts, ['1234']);
        expect(tester.takeException(), isNull);
      });
    }
  }

  _h4Test('a profile word wider than the unscaled line breaks in place', (
    tester,
  ) async {
    _window(tester, const Size(360, 800), 1, 2);
    await _pump(
      tester,
      UiFixture(profile: _handheld, controller: _PinController()),
    );
    final word = find.text(_overwideProfileName);
    await tester.ensureVisible(word);
    await tester.pumpAndSettle();
    final richText = find.descendant(of: word, matching: find.byType(RichText));
    final paragraph = tester.renderObject<RenderParagraph>(richText);
    final boxes = paragraph.getBoxesForSelection(
      const TextSelection(
        baseOffset: 0,
        extentOffset: _overwideProfileName.length,
      ),
    );
    expect(boxes.map((box) => box.top).toSet(), hasLength(greaterThan(1)));
    final card = find.byKey(const ValueKey('profile-card-overwide'));
    expect(tester.getRect(word).width, lessThan(tester.getRect(card).width));
    expect(tester.takeException(), isNull);
  });

  _h4Test('Settings tab restores the last list or category page', (
    tester,
  ) async {
    _window(tester, const Size(412, 915), 1, 1);
    await _pump(
      tester,
      UiFixture(
        profile: _handheld,
        scenario: const LineupScenario(stage: SetupStage.ready),
      ),
    );
    await _openSettings(tester);
    Future<void> roundTrip() async {
      await _tap(tester, find.byKey(const ValueKey('handheld-tab-guide')));
      expect(find.byType(SettingsView), findsNothing);
      await _openSettings(tester);
    }

    await _tap(tester, find.text('Playback'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await roundTrip();
    expect(find.text('Playback'), findsOneWidget);
    expect(find.text('DVR playback controls'), findsNothing);

    await _tap(tester, find.text('Appearance'));
    await roundTrip();
    expect(find.byTooltip('Back to Settings'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    await _tap(tester, find.byTooltip('Back to Settings'));
    await roundTrip();
    expect(find.text('Playback'), findsOneWidget);
    expect(find.text('Theme'), findsNothing);

    await _tap(tester, find.text('Support').first);
    await _tap(tester, find.text('Open Diagnostics'));
    await _tap(tester, find.byTooltip('Back to Support'));
    expect(find.byTooltip('Back to Settings'), findsOneWidget);
    expect(find.text('Open Diagnostics'), findsOneWidget);
  });

  _h4Test(
    'category and list top survive the width flip, then Back returns to Guide',
    (tester) async {
      _window(tester, const Size(412, 915), 1, 1);
      await _pump(
        tester,
        UiFixture(
          profile: _handheld,
          scenario: const LineupScenario(stage: SetupStage.ready),
        ),
      );
      await _openSettings(tester);
      final view = find.byType(SettingsView);
      final appearance = find
          .descendant(of: view, matching: find.text('Appearance'))
          .first;
      final top = tester.getTopLeft(appearance);
      for (final open in [false, true]) {
        if (open) await _tap(tester, find.text('Playback'));
        tester.view.physicalSize = const Size(1280, 800);
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(412, 915);
        await tester.pumpAndSettle();
        if (open) {
          expect(find.text('DVR playback controls'), findsOneWidget);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        }
        expect(tester.getTopLeft(appearance), top);
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(view, findsNothing);
    },
  );

  _h4Test('phone QR gate uses display dimensions in a short tablet pane', (
    tester,
  ) async {
    _window(tester, const Size(412, 915), 2, 1);
    tester.view.display.size = const Size(1600, 2560);
    await _pump(
      tester,
      UiFixture(
        profile: _handheld,
        scenario: LineupScenario(
          stage: SetupStage.linking,
          activePin: PlexPin(
            id: 7,
            code: 'ABCD',
            expiresAt: DateTime.now().add(const Duration(minutes: 4)),
          ),
        ),
      ),
    );
    expect(find.byType(QrImageView), findsOneWidget);
  });

  for (final (host, form, displayMatching, hasLicenses, hasSettings) in const [
    (TargetPlatform.windows, FormFactor.desktop, true, false, false),
    (TargetPlatform.macOS, FormFactor.desktop, false, true, true),
    (TargetPlatform.android, FormFactor.tv, false, true, true),
    (TargetPlatform.android, FormFactor.handheld, false, true, true),
  ]) {
    _h4Test('H4 shell row gates for $host $form', (tester) async {
      _window(tester, const Size(1280, 800), 1, 1, host: host);
      final profile = DeviceProfile(host: host, formFactor: form);
      final player = FixturePlayer()
        ..capabilities = displayMatching
            ? PlayerCapabilities.forHost(TargetPlatform.windows)
            : const PlayerCapabilities.unavailable();
      await _pump(
        tester,
        UiFixture(
          profile: profile,
          player: player,
          scenario: const LineupScenario(stage: SetupStage.welcome),
        ),
      );
      expect(
        find.text('Settings'),
        hasSettings ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(
        tester,
        UiFixture(
          profile: profile,
          player: FixturePlayer()..capabilities = player.capabilities,
          scenario: const LineupScenario(stage: SetupStage.ready),
        ),
      );
      await _openSettings(tester);
      await _tap(tester, find.text('Playback').first);
      expect(
        find.text('Match display HDR in fullscreen'),
        displayMatching ? findsOneWidget : findsNothing,
      );
      await _tap(tester, find.text('Support').first);
      expect(
        find.text('Open Licenses'),
        hasLicenses ? findsOneWidget : findsNothing,
      );
    });
  }
}

class _PinController extends FixtureController {
  _PinController()
    : super(
        scenario: const LineupScenario(
          stage: SetupStage.profiles,
          profile: PlexHomeUser(
            id: 'taylor',
            name: 'Taylor',
            protected: true,
            restricted: true,
          ),
          profiles: [
            PlexHomeUser(
              id: 'taylor',
              name: 'Taylor',
              protected: true,
              restricted: true,
            ),
            PlexHomeUser(id: 'guest', name: 'Guest', protected: false),
            PlexHomeUser(id: 'family', name: 'Family', protected: false),
            PlexHomeUser(
              id: 'overwide',
              name: _overwideProfileName,
              protected: false,
            ),
            PlexHomeUser(
              id: 'long',
              name: 'A deliberately long synthetic profile name',
              protected: false,
            ),
          ],
        ),
      );

  final pinAttempts = <String?>[];

  @override
  Future<bool> selectProfile(PlexHomeUser selected, {String? pin}) async {
    pinAttempts.add(pin);
    return false;
  }
}

void _window(
  WidgetTester tester,
  Size size,
  double dpr,
  double scale, {
  TargetPlatform host = TargetPlatform.android,
}) {
  debugDefaultTargetPlatformOverride = host;
  tester.view
    ..devicePixelRatio = dpr
    ..physicalSize = size * dpr;
  tester.view.display
    ..devicePixelRatio = dpr
    ..size = size * dpr;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (_) async => null,
  );
  addTearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    tester.view.reset();
    tester.view.display.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

void _h4Test(String name, WidgetTesterCallback body) {
  testWidgets(name, semanticsEnabled: true, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _pump(WidgetTester tester, UiFixture fixture) async {
  addTearDown(fixture.controller.dispose);
  await tester.pumpWidget(fixture.build());
  await tester.pumpAndSettle();
}

Future<void> _openSettings(WidgetTester tester) async {
  final tab = find.byKey(_settingsTab);
  if (tab.evaluate().isNotEmpty) {
    await _tap(tester, tab);
    return;
  }
  await _tap(tester, find.byTooltip('Open Lineup menu').first);
  await _tap(tester, find.text('Settings').last);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void _oneTappableNode(WidgetTester tester, RegExp label) {
  final nodes = find.semantics
      .byAction(SemanticsAction.tap)
      .evaluate()
      .where(
        (node) =>
            !node.isInvisible &&
            !node.isMergedIntoParent &&
            (label.hasMatch(node.getSemanticsData().label) ||
                label.hasMatch(node.getSemanticsData().tooltip)),
      );
  expect(
    nodes,
    hasLength(1),
    reason:
        '$label among ${find.semantics.byAction(SemanticsAction.tap).evaluate().map((node) => (node.label, node.getSemanticsData().tooltip, node.isInvisible, node.isMergedIntoParent)).toList()}',
  );
  final node = nodes.single;
  var rect = node.rect;
  for (
    SemanticsNode? current = node;
    current != null;
    current = current.parent
  ) {
    if (current.transform case final transform?) {
      rect = MatrixUtils.transformRect(transform, rect);
    }
  }
  final shortest =
      math.min(rect.width, rect.height) / tester.view.devicePixelRatio;
  expect(shortest, greaterThanOrEqualTo(48 - .001), reason: '$label');
}

void _wordsStayOnOneLine(WidgetTester tester, String text) {
  final plain = find.text(text);
  if (plain.evaluate().isNotEmpty) {
    _checkParagraphWords(tester, plain.first);
    return;
  }
  final wrapped = find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == text,
  );
  expect(wrapped, findsOneWidget);
  final words = text.split(RegExp(r'\s+'));
  for (final word in words) {
    final child = find.descendant(of: wrapped, matching: find.text(word));
    expect(child, findsOneWidget);
    _checkParagraphWords(tester, child);
  }
}

void _checkParagraphWords(WidgetTester tester, Finder text) {
  final richText = find
      .descendant(of: text, matching: find.byType(RichText))
      .first;
  final paragraph = tester.renderObject<RenderParagraph>(richText);
  final plainText = paragraph.text.toPlainText(includeSemanticsLabels: false);
  for (final word in RegExp(r'\S+').allMatches(plainText)) {
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: word.start, extentOffset: word.end),
    );
    expect(
      boxes.map((box) => box.top).toSet(),
      hasLength(1),
      reason: word.group(0),
    );
    expect(
      boxes.every(
        (box) => box.left >= -1 && box.right <= paragraph.size.width + 1,
      ),
      isTrue,
      reason: word.group(0),
    );
  }
}
