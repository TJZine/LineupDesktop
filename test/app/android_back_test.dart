import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

import '../support/ui_fixture.dart';

void main() {
  const platform = MethodChannel('lineup/platform');
  var backgrounded = 0;
  setUp(() {
    backgrounded = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          expect(call.method, 'moveTaskToBack');
          backgrounded++;
          return true;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);
  });

  void androidTest(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  androidTest('welcome backgrounds and Support returns before backgrounding', (
    tester,
  ) async {
    final fixture = UiFixture(
      androidTv: true,
      scenario: const LineupScenario(stage: SetupStage.welcome),
    );
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(backgrounded, 1);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.text('Your Plex library, scheduled like television'),
      findsOneWidget,
    );
    expect(backgrounded, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  androidTest(
    'Android onboarding recovers a real control after stranded focus and resume',
    (tester) async {
      final fixture = UiFixture(
        androidTv: true,
        scenario: const LineupScenario(stage: SetupStage.welcome),
      );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      final initial = FocusManager.instance.primaryFocus!;
      final navigation = initial.ancestors.firstWhere(
        (node) => node.debugLabel == 'Onboarding navigation',
      );
      navigation.requestFocus();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(initial));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      initial.unfocus();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(initial));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  androidTest(
    'one predictive Back leaves PIN without also cancelling Profiles',
    (tester) async {
      final fixture = UiFixture(
        androidTv: true,
        scenario: const LineupScenario(
          stage: SetupStage.profiles,
          profileSelectionOrigin: SetupStage.servers,
          profiles: [
            PlexHomeUser(
              id: 'protected',
              name: 'Fixture viewer',
              protected: true,
            ),
          ],
        ),
      );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-card-protected')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-pin-sheet')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
      expect(fixture.controller.stage, SetupStage.profiles);
      expect(fixture.controller.profileSelectionCanCancel, isTrue);
      expect(backgrounded, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(fixture.controller.stage, SetupStage.servers);
      expect(backgrounded, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
