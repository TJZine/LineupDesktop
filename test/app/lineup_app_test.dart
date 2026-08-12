import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_app.dart';
import 'package:lineup_desktop/playback/native_player.dart';

void main() {
  testWidgets('shows honest empty states and supports shell navigation', (
    tester,
  ) async {
    final player = _FakePlayer();

    await tester.pumpWidget(LineupBootstrap(player: player));
    await tester.pumpAndSettle();

    expect(find.text('Your guide is ready for setup'), findsOneWidget);
    expect(find.text('Playback test backend ready'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Settings are not available yet'), findsOneWidget);
    expect(find.text('No channels yet'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(player.disposed, isTrue);
  });

  testWidgets('presents initialization failures without entering the shell', (
    tester,
  ) async {
    await tester.pumpWidget(LineupBootstrap(player: _FailingPlayer()));
    await tester.pumpAndSettle();

    expect(find.text('Lineup Desktop could not start'), findsOneWidget);
    expect(
      find.textContaining('No settings or media were changed'),
      findsOneWidget,
    );
    expect(find.textContaining('player initialization failed'), findsNothing);
    expect(find.text('Guide'), findsNothing);
  });
}

class _FakePlayer implements NativePlayer {
  bool disposed = false;

  @override
  PlayerStatus get status => const PlayerStatus(
    state: PlayerState.idle,
    message: 'Playback test backend ready',
  );

  @override
  Stream<PlayerEvent> get events => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> load(Uri media) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FailingPlayer extends _FakePlayer {
  @override
  Future<void> initialize() async {
    throw StateError('player initialization failed');
  }
}
