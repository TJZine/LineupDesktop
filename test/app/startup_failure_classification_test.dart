import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_app.dart';
import 'package:lineup_desktop/playback/native_player.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets('non-engine native startup failures keep generic recovery', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });

    await tester.pumpWidget(
      LineupBootstrap(
        player: _FailingPlayer(),
        controller: FixtureController(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The required Lineup DirectComposition Flutter engine is not active.',
      ),
      findsNothing,
    );
    expect(
      find.text(
        'Restart the app, and check diagnostics if the problem continues.',
      ),
      findsOneWidget,
    );
  });
}

class _FailingPlayer extends FixturePlayer {
  @override
  Future<void> initialize() => Future.error(
    PlatformException(
      code: 'initialize_failed',
      message: 'libmpv could not create a client.',
    ),
  );

  @override
  PlayerStatus get status => const PlayerStatus(
    state: PlayerState.idle,
    message: 'Native player not initialized',
  );
}
