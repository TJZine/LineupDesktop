import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

import '../support/ui_fixture.dart';

const _down = LogicalKeyboardKey.arrowDown;
const _left = LogicalKeyboardKey.arrowLeft;
const _right = LogicalKeyboardKey.arrowRight;
const _select = LogicalKeyboardKey.select;
const _back = LogicalKeyboardKey.goBack;

Future<void> _keys(WidgetTester tester, List<LogicalKeyboardKey> keys) async {
  for (final key in keys) {
    await tester.sendKeyEvent(
      key,
      physicalKey: key == _back ? PhysicalKeyboardKey.escape : null,
    );
    await tester.pumpAndSettle();
  }
}

void _tvTest(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 2;
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void _focusedVisible(WidgetTester tester, Finder control) {
  final primary = FocusManager.instance.primaryFocus!;
  expect(
    primary.context!.findAncestorWidgetOfExactType<OutlinedButton>(),
    same(tester.widget<OutlinedButton>(control)),
  );
  final rect = tester.getRect(control);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(540));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(960));
}

var _backgroundRequests = 0;
void main() {
  const platform = MethodChannel('lineup/platform');
  setUp(() {
    _backgroundRequests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          expect(call.method, 'moveTaskToBack');
          _backgroundRequests++;
          return true;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null),
  );
  _tvTest(
    'protected PIN remote walk reaches every bottom key, error, Cancel and Back',
    (tester) async {
      final fixture = UiFixture(controller: _RejectedPinController());
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await _keys(tester, [_select]);
      Finder digit(String value) => find.widgetWithText(OutlinedButton, value);
      _focusedVisible(tester, digit('1'));
      await _keys(tester, [_select, _select, _select, _select]);
      expect(find.text('Incorrect PIN. Try again.'), findsOneWidget);
      _focusedVisible(tester, digit('1'));
      await _keys(tester, [_select, _right]);
      _focusedVisible(tester, digit('2'));
      await _keys(tester, [_right]);
      _focusedVisible(tester, digit('3'));
      await _keys(tester, [_down]);
      _focusedVisible(tester, digit('6'));
      await _keys(tester, [_left]);
      _focusedVisible(tester, digit('5'));
      await _keys(tester, [_left]);
      _focusedVisible(tester, digit('4'));
      await _keys(tester, [_down]);
      _focusedVisible(tester, digit('7'));
      await _keys(tester, [_right]);
      _focusedVisible(tester, digit('8'));
      await _keys(tester, [_right]);
      _focusedVisible(tester, digit('9'));
      await _keys(tester, [_down]);
      final delete = find.descendant(
        of: find.byTooltip('Backspace'),
        matching: find.byType(OutlinedButton),
      );
      _focusedVisible(tester, delete);
      await _keys(tester, [_left]);
      _focusedVisible(tester, digit('0'));
      await _keys(tester, [_right, _select]);
      expect(
        tester
            .widget<Semantics>(find.byKey(const Key('profile-pin-progress')))
            .properties
            .label,
        '0 of 4 digits entered',
      );
      await _keys(tester, [_left, _down]);
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<TextButton>(),
        same(tester.widget<TextButton>(cancel)),
      );
      expect(tester.getRect(cancel).bottom, lessThanOrEqualTo(540));
      await _keys(tester, [_select]);
      expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
      await _keys(tester, [_select]);
      _focusedVisible(tester, digit('1'));
      await _keys(tester, [_back]);
      expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
      expect(fixture.controller.stage, SetupStage.profiles);
      expect(_backgroundRequests, 0);
    },
  );

  _tvTest(
    'current protected profile PIN Back owns both native paths without backgrounding',
    (tester) async {
      final fixture = UiFixture(
        controller: _RejectedPinController(current: true),
      );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await _keys(tester, [_select]);
      _focusedVisible(tester, find.widgetWithText(OutlinedButton, '1'));
      await tester.sendKeyDownEvent(
        _back,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await tester.binding.handlePopRoute();
      await tester.sendKeyUpEvent(
        _back,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
      expect(fixture.controller.stage, SetupStage.profiles);
      expect(fixture.controller.profileSelectionCanCancel, isTrue);
      expect(_backgroundRequests, 0);
      await _keys(tester, [_select]);
      _focusedVisible(tester, find.widgetWithText(OutlinedButton, '1'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
      expect(fixture.controller.stage, SetupStage.profiles);
      expect(fixture.controller.profileSelectionCanCancel, isTrue);
      expect(_backgroundRequests, 0);
    },
  );
}

class _RejectedPinController extends FixtureController {
  _RejectedPinController({bool current = false})
    : super(
        scenario: LineupScenario(
          stage: SetupStage.profiles,
          profile: current
              ? const PlexHomeUser(
                  id: 'protected',
                  name: 'Fixture viewer',
                  protected: true,
                )
              : null,
          profileSelectionOrigin: current ? SetupStage.ready : null,
          profiles: const [
            PlexHomeUser(
              id: 'protected',
              name: 'Fixture viewer',
              protected: true,
            ),
          ],
        ),
      );
  @override
  Future<bool> selectProfile(PlexHomeUser user, {String? pin}) async {
    fixtureActor.present(
      LineupPresentation(error: ('That Plex Home PIN was not accepted.',)),
    );
    notifyListeners();
    return false;
  }
}
