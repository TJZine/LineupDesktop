// MethodCall.arguments is intentionally dynamic in these protocol fixtures.
// ignore_for_file: avoid_dynamic_calls

// Dart-side protocol conformance suite for `lineup/native_player`.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/method_channel_native_player.dart';
import 'package:lineup_desktop/playback/native_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lineup/native_player');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('observed fullscreen', () {
    late MethodChannelNativePlayer player;
    setUp(() {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
    });

    test(
      'strict player-scoped bool, broadcast snapshots without a load',
      () async {
        await player.initialize();
        final first = <bool>[];
        final second = <bool>[];
        final a = player.fullscreenChanges.listen(first.add);
        final b = player.fullscreenChanges.listen(second.add);
        addTearDown(a.cancel);
        addTearDown(b.cancel);
        for (final invalid in [null, 0, 1, 'true', <Object>[]]) {
          await _sendNativeEvent(messenger, {
            'type': 'fullscreen',
            'fullscreen': invalid,
          });
        }
        await _sendNativeEvent(messenger, {'type': 'fullscreen'});
        expect(first, isEmpty);
        expect(player.fullscreen, isFalse);
        await _sendNativeEvent(messenger, {
          'type': 'fullscreen',
          'fullscreen': true,
          'loadId': -99,
        });
        expect(first, [true]);
        expect(second, [true]);
        expect(player.fullscreen, isTrue);
        final late = <bool>[];
        final c = player.fullscreenChanges.listen(late.add);
        addTearDown(c.cancel);
        expect(late, isEmpty);
        await _sendNativeEvent(messenger, {
          'type': 'fullscreen',
          'fullscreen': false,
        });
        expect(first, [true, false]);
        expect(second, [true, false]);
        expect(late, [false]);
      },
    );

    test('initializing accepts native snapshot; disposed lifetime rejects late events', () async {
      final initialized = Completer<void>();
      final disposed = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') await initialized.future;
        if (call.method == 'dispose') await disposed.future;
        return null;
      });
      final observations = <bool>[];
      final subscription = player.fullscreenChanges.listen(observations.add);
      addTearDown(subscription.cancel);
      final initialize = player.initialize();
      await pumpEventQueue(times: 2);
      await _sendNativeEvent(messenger, {
        'type': 'fullscreen',
        'fullscreen': true,
      });
      expect(player.fullscreen, isTrue);
      initialized.complete();
      await initialize;
      final dispose = player.dispose();
      await pumpEventQueue(times: 2);
      await _sendNativeEvent(messenger, {
        'type': 'fullscreen',
        'fullscreen': true,
      });
      expect(player.fullscreen, isFalse);
      expect(observations, [true]);
      disposed.complete();
      await dispose;
      await player.initialize();
      expect(player.fullscreen, isFalse);
      await _sendNativeEvent(messenger, {
        'type': 'fullscreen',
        'fullscreen': true,
      });
      expect(observations, [true, true]);
    });

    test(
      'late command success cannot change a fresher observed state',
      () async {
        final reply = Completer<void>();
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setFullscreen') await reply.future;
          return null;
        });
        await player.initialize();
        final request = player.setFullscreen(true);
        await pumpEventQueue(times: 2);
        await _sendNativeEvent(messenger, {
          'type': 'fullscreen',
          'fullscreen': false,
        });
        reply.complete();
        await request;
        expect(player.fullscreen, isFalse);
      },
    );
  });

  group('typed track snapshots', () {
    late MethodChannelNativePlayer player;
    late int loadId;
    const identity = <String, Object?>{
      'id': 7,
      'type': 'audio',
      'selected': true,
    };
    const facts = <String, Object?>{
      'title': 'Synthetic mix',
      'lang': 'eng',
      'codec': 'aac',
      'demux-channel-count': 6,
      'demux-channels': '5.1(side)',
      'forced': true,
      'external': false,
      'hearing-impaired': true,
      'visual-impaired': false,
      'commentary': true,
    };

    Map<String, Object?> readFacts(PlayerTrack track) => {
      'title': track.title,
      'lang': track.language,
      'codec': track.codec,
      'demux-channel-count': track.channelCount,
      'demux-channels': track.channelLayout,
      'forced': track.forced,
      'external': track.external,
      'hearing-impaired': track.hearingImpaired,
      'visual-impaired': track.visualImpaired,
      'commentary': track.commentary,
    };

    Future<void> snapshot(List<Object?> tracks) => _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'track-list',
      'value': tracks,
    });

    setUp(() async {
      final dispatched = Completer<int>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'load') {
          dispatched.complete(
            (call.arguments as Map<Object?, Object?>)['loadId'] as int,
          );
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final load = player.load(Uri(scheme: 'lineup-test'));
      loadId = await dispatched.future;
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'playing',
      });
      await load;
    });

    test('only active valid track-list arrivals mark tracks updated', () async {
      final events = <PlayerEvent>[];
      final subscription = player.events.listen(events.add);
      addTearDown(subscription.cancel);
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'time-pos',
        'value': 0,
      });
      expect(events.last.tracksUpdated, isFalse);
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId - 1,
        'name': 'track-list',
        'value': [],
      });
      expect(events, hasLength(1));
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'track-list',
        'value': null,
      });
      expect(events.last.tracksUpdated, isFalse);
      await snapshot([]);
      expect(events.last.tracksUpdated, isTrue);
      expect(events.last.tracks, isEmpty);
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'time-pos',
        'value': 1,
      });
      expect(events.last.tracksUpdated, isFalse);
    });

    test('position events reuse the immutable track snapshot', () async {
      final events = <PlayerEvent>[];
      final subscription = player.events.listen(events.add);
      addTearDown(subscription.cancel);
      await snapshot([identity]);
      final tracks = player.tracks;
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'time-pos',
        'value': 1.25,
      });
      expect(events, hasLength(2));
      expect(identical(events.first.tracks, tracks), isTrue);
      expect(identical(events.last.tracks, tracks), isTrue);
      expect(tracks.clear, throwsUnsupportedError);
    });

    test('old fields do not fabricate new facts', () async {
      const oldFacts = {
        'title': 'Synthetic mix',
        'lang': 'eng',
        'codec': 'aac',
      };
      await snapshot([
        {...identity, ...oldFacts},
      ]);
      final track = player.tracks.single;
      expect(track.id, 7);
      expect(track.type, PlayerTrackType.audio);
      expect(track.selected, isTrue);
      expect(readFacts(track), {
        for (final key in facts.keys) key: oldFacts[key],
      });
    });

    test('all accepted facts preserve values and descriptive false', () async {
      await snapshot([
        {...identity, ...facts},
      ]);
      expect(readFacts(player.tracks.single), facts);
      final inverted = {
        for (final entry in facts.entries)
          entry.key: entry.value is bool ? !(entry.value as bool) : entry.value,
      };
      await snapshot([
        {...identity, ...inverted},
      ]);
      expect(readFacts(player.tracks.single), inverted);
    });

    test('absent and null optional facts stay unknown', () async {
      for (final optional in [
        <String, Object?>{},
        {for (final key in facts.keys) key: null},
      ]) {
        await snapshot([
          {...identity, ...optional},
        ]);
        expect(readFacts(player.tracks.single).values, everyElement(isNull));
        expect(player.tracks.single.selected, isTrue);
      }
    });

    test('wrong optional types lose only that fact', () async {
      for (final entry in facts.entries) {
        for (final wrong in <Object?>[
          null,
          'wrong',
          1,
          1.5,
          false,
          <Object?>[],
          <String, Object?>{},
        ]) {
          if ((entry.value is String && wrong is String) ||
              (entry.value is bool && wrong is bool) ||
              (entry.value is int && wrong is int)) {
            continue;
          }
          await snapshot([
            {...identity, ...facts, entry.key: wrong},
          ]);
          expect(readFacts(player.tracks.single), {
            ...facts,
            entry.key: null,
          }, reason: 'Malformed ${entry.key} must be absent');
        }
      }
    });

    test('channel counts accept only positive integers', () async {
      for (final count in <Object?>[0, -1, '6', 6.0, 1.5, null, true]) {
        await snapshot([
          {...identity, ...facts, 'demux-channel-count': count},
        ]);
        expect(player.tracks.single.channelCount, isNull);
        expect(player.tracks.single.channelLayout, '5.1(side)');
      }
      for (final count in [1, 2, 6, 8, 123]) {
        await snapshot([
          {...identity, 'demux-channel-count': count},
        ]);
        expect(player.tracks.single.channelCount, count);
        expect(player.tracks.single.channelLayout, isNull);
      }
    });

    test('rejects malformed identity before a valid selected track', () async {
      await snapshot([
        null,
        'invalid',
        <Object?>[],
        <String, Object?>{},
        for (final id in <Object?>[0, -1, '7', 7.0, 1.5, null, true])
          {...identity, 'id': id},
        {'type': 'audio', 'selected': true},
        for (final type in <Object?>[
          'Audio',
          'subtitle',
          'audio ',
          '',
          null,
          1,
        ])
          {...identity, 'type': type},
        {'id': 7, 'selected': true},
        for (final selected in <Object?>[null, 'true', 0, 1, 1.0])
          {...identity, 'selected': selected},
        {'id': 7, 'type': 'audio'},
        identity,
      ]);
      expect(player.tracks, hasLength(1));
      expect(player.tracks.single.id, 7);
      expect(player.tracks.single.selected, isTrue);
      await snapshot([
        {...identity, 'type': 'video', 'selected': false},
        {...identity, 'type': 'sub'},
      ]);
      expect(player.tracks.map((track) => track.type), [
        PlayerTrackType.video,
        PlayerTrackType.subtitle,
      ]);
      expect(player.tracks.first.selected, isFalse);
    });

    test(
      'successive snapshots remove facts and preserve immutable old state',
      () async {
        final events = <PlayerEvent>[];
        final subscription = player.events.listen(events.add);
        addTearDown(subscription.cancel);
        await snapshot([
          {...identity, ...facts},
        ]);
        final previous = player.tracks;
        expect(previous.clear, throwsUnsupportedError);
        expect(events.last.tracks.clear, throwsUnsupportedError);
        await snapshot([identity]);
        expect(readFacts(player.tracks.single).values, everyElement(isNull));
        expect(
          readFacts(events.last.tracks.single).values,
          everyElement(isNull),
        );
        expect(readFacts(previous.single), facts);
        expect(
          () => player.tracks.add(previous.single),
          throwsUnsupportedError,
        );
      },
    );

    test('non-whitelisted sentinels do not supply fallback facts', () async {
      await snapshot([
        {
          ...identity,
          for (final key in [
            'codec-desc',
            'codec-profile',
            'default',
            'external-filename',
            'ff-index',
            'src-id',
            'program-id',
            'demux-bitrate',
            'demux-samplerate',
            'decoder',
            'unlisted-sentinel',
          ])
            key: 'excluded-sentinel',
        },
      ]);
      expect(readFacts(player.tracks.single).values, everyElement(isNull));
      expect(player.tracks.single.id, 7);
      expect(player.tracks.single.type, PlayerTrackType.audio);
      expect(player.tracks.single.selected, isTrue);
    });
  });

  test(
    'projects bounded native playback facts and completes a loaded file',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'initialize'
            ? <String, Object?>{'clientApiVersion': 131072}
            : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final load = player.load(
        Uri.parse('https://plex.example/media/sample.mp4'),
        plexToken: 'test-token',
        startPosition: const Duration(microseconds: 18250001),
      );
      await Future<void>.delayed(Duration.zero);
      final loadId = calls.last.arguments!['loadId']! as int;
      expect(calls.last.arguments!['plexToken'], 'test-token');
      expect(calls.last.arguments!['startSeconds'], 18.250001);
      expect(
        calls.last.arguments!['uri'],
        'https://plex.example/media/sample.mp4',
      );

      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'current-vo',
        'value': 'gpu-next',
      });
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'hwdec-current',
        'value': 'd3d11va',
      });
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'video-params',
        'value': {
          'w': 1920,
          'h': 1080,
          'pixelformat': 'nv12',
          'hw-pixelformat': 'd3d11',
          'primaries': 'bt.2020',
          'gamma': 'pq',
          'colormatrix': 'bt.2020-ncl',
          'sig-peak': 10.0,
        },
      });
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'video-target-params',
        'value': {
          'gamma': '  PQ ',
          'primaries': 'BT.2020',
          'pixelformat': 'RGBA16F',
          'unlisted': 'ignored',
        },
      });
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'track-list',
        'value': [
          {
            'id': 1,
            'type': 'video',
            'title': null,
            'lang': null,
            'codec': 'h264',
            'selected': true,
          },
        ],
      });
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'playing',
        'message': 'Playing',
      });
      await load;

      expect(
        calls.map((call) => call.method),
        containsAll(['initialize', 'load']),
      );
      expect(player.status.state, PlayerState.playing);
      expect(player.telemetry.videoOutput, 'gpu-next');
      expect(player.telemetry.hardwareDecoder, 'd3d11va');
      expect(player.telemetry.isHdr, isTrue);
      expect(player.telemetry.targetGamma, 'pq');
      expect(player.telemetry.targetPrimaries, 'bt.2020');
      expect(player.telemetry.targetPixelFormat, 'rgba16f');
      expect(player.tracks.single.codec, 'h264');
      expect(player.tracks.single.selected, isTrue);

      await player.dispose();
      await player.initialize();
      expect(calls.where((call) => call.method == 'initialize'), hasLength(2));
    },
  );

  test('drops a property event with a malformed name', () async {
    var loadId = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'load') {
        loadId = (call.arguments as Map<Object?, Object?>)['loadId'] as int;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    final events = <PlayerEvent>[];
    final subscription = player.events.listen(events.add);
    addTearDown(subscription.cancel);
    final load = player.load(Uri.parse('file:///malformed-property.mp4'));
    await Future<void>.delayed(Duration.zero);
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
    });
    await load;
    final eventCount = events.length;

    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 42,
      'value': 'ignored',
    });

    expect(events, hasLength(eventCount));
    expect(player.telemetry, const PlayerTelemetry());
  });

  test('uses a safe fallback for a malformed state message', () async {
    var loadId = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'load') {
        loadId = (call.arguments as Map<Object?, Object?>)['loadId'] as int;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    final load = player.load(Uri.parse('file:///malformed-state.mp4'));
    await Future<void>.delayed(Duration.zero);
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
      'message': 42,
    });

    expect(player.status.state, PlayerState.playing);
    expect(player.status.message, 'playing');
    await load;
  });

  test(
    'drops malformed direct telemetry values without clearing valid facts',
    () async {
      var loadId = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'load') {
          loadId = (call.arguments as Map<Object?, Object?>)['loadId'] as int;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final load = player.load(Uri.parse('file:///malformed-telemetry.mp4'));
      await Future<void>.delayed(Duration.zero);
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'playing',
      });
      await load;
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'video-codec',
        'value': 'h264',
      });
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'video-codec',
        'value': 42,
      });

      expect(player.telemetry.videoCodec, 'h264');
    },
  );

  test(
    'encodes startPaused and keeps raw playing readiness separate',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final load = player.load(
        Uri.parse('file:///paused.mp4'),
        generation: 8,
        startPaused: true,
      );
      await Future<void>.delayed(Duration.zero);
      final loadCall = calls.singleWhere((call) => call.method == 'load');
      final loadId = loadCall.arguments!['loadId']! as int;
      expect(loadCall.arguments!['startPaused'], isTrue);

      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'playing',
      });
      await load;

      expect(player.status.state, PlayerState.paused);
      expect(player.status.message, 'Paused');
    },
  );

  test(
    'routes valid player-scoped display reports and rejects stale data',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      final reports = <DisplayMatchingReport>[];
      final subscription = player.displayReports.listen(reports.add);
      addTearDown(subscription.cancel);
      await player.initialize();
      await player.setDisplayMatching(
        const DisplayMatchingRequest(
          revision: 4,
          session: true,
          desired: DisplayMatchingState.hdr,
        ),
      );

      expect(
        calls
            .singleWhere((call) => call.method == 'setDisplayMatching')
            .arguments,
        {'revision': 4, 'session': true, 'desired': 'hdr'},
      );
      await _sendNativeEvent(messenger, {
        'type': 'display',
        'loadId': -1,
        'revision': 4,
        'session': 'active',
        'observed': 'hdr',
        'outcome': 'matched',
        'wrote': true,
        'owned': true,
        'reason': null,
        'route': 'hdr_state',
        'activeColorMode': 'hdr',
      });
      expect(reports, hasLength(1));
      expect(player.displayReport.session, DisplayMatchingSessionState.active);
      expect(player.displayReport.observed, DisplayMatchingState.hdr);
      expect(player.displayReport.activeColorMode, DisplayActiveColorMode.hdr);

      await _sendNativeEvent(messenger, {
        'type': 'display',
        'revision': 3,
        'session': 'active',
        'observed': 'sdr',
        'outcome': 'matched',
        'wrote': false,
        'owned': false,
        'reason': null,
        'route': 'hdr_state',
      });
      await _sendNativeEvent(messenger, {
        'type': 'display',
        'revision': 4,
        'session': 'not-a-session',
        'observed': 'sdr',
        'outcome': 'matched',
        'wrote': false,
        'owned': false,
        'reason': null,
        'route': 'hdr_state',
      });
      expect(reports, hasLength(1));
    },
  );

  test('admission fallback is typed, current and player scoped', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    final reports = <DisplayMatchingReport>[];
    final subscription = player.displayReports.listen(reports.add);
    addTearDown(subscription.cancel);
    await player.initialize();
    await player.setDisplayMatching(
      const DisplayMatchingRequest(
        revision: 5,
        session: true,
        desired: DisplayMatchingState.hdr,
      ),
    );
    const fallback = <String, Object?>{
      'type': 'display',
      'loadId': -1,
      'revision': 5,
      'session': 'unavailable',
      'observed': 'unknown',
      'outcome': 'failed',
      'wrote': false,
      'owned': false,
      'reason': 'guardian_unavailable',
      'route': 'none',
      'activeColorMode': 'unknown',
    };
    await _sendNativeEvent(messenger, {...fallback, 'revision': 4});
    await _sendNativeEvent(messenger, {...fallback, 'revision': 6});
    await _sendNativeEvent(messenger, {
      ...fallback,
      'reason': 'unknown_recovery_reason',
    });
    expect(reports, isEmpty);
    await _sendNativeEvent(messenger, fallback);
    expect(reports, hasLength(1));
    expect(
      player.displayReport.session,
      DisplayMatchingSessionState.unavailable,
    );
    expect(player.displayReport.outcome, DisplayMatchingOutcome.failed);
    expect(
      player.displayReport.reason,
      DisplayMatchingReason.guardianUnavailable,
    );
    expect(player.displayReport.wrote, isFalse);
    expect(player.displayReport.owned, isFalse);
    expect(player.displayReport.route, DisplayMatchingRoute.none);
    expect(player.status.state, isNot(PlayerState.error));
  });

  test('resets the display revision across initialize', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    await player.setDisplayMatching(
      const DisplayMatchingRequest(
        revision: 8,
        session: true,
        desired: DisplayMatchingState.sdr,
      ),
    );
    await player.dispose();
    await player.initialize();
    await player.setDisplayMatching(
      const DisplayMatchingRequest(
        revision: 1,
        session: false,
        desired: DisplayMatchingState.unknown,
      ),
    );

    expect(
      calls.where((call) => call.method == 'setDisplayMatching'),
      hasLength(2),
    );
    expect(calls.last.arguments, {
      'revision': 1,
      'session': false,
      'desired': 'unknown',
    });
  });

  test('maps a correlated native ended state to PlayerState.ended', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    final events = <PlayerEvent>[];
    final subscription = player.events.listen(events.add);
    addTearDown(subscription.cancel);
    await player.initialize();
    final load = player.load(Uri.parse('file:///ended.mp4'), generation: 42);
    await Future<void>.delayed(Duration.zero);
    final loadId = calls.last.arguments!['loadId']! as int;
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
    });
    await load;

    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'ended',
      'message': 'Playback ended',
    });

    expect(player.status.state, PlayerState.ended);
    expect(player.status.message, 'Playback ended');
    expect(events.last.status.state, PlayerState.ended);
    expect(events.last.generation, 42);
  });

  test(
    'leaves stopped state unchanged for a correlated terminal event',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final load = player.load(Uri.parse('file:///stopped.mp4'));
      await Future<void>.delayed(Duration.zero);
      final loadId = calls.last.arguments!['loadId']! as int;
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'playing',
      });
      await load;

      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'stopped',
        'message': 'Playback stopped',
      });

      expect(player.status.state, PlayerState.stopped);
      expect(player.status.message, 'Playback stopped');
    },
  );

  test('seek mode is explicit on the wire and defaults to exact', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    calls.clear();
    await player.seek(
      const Duration(microseconds: 1250123),
      mode: SeekMode.keyframes,
    );
    await player.seek(Duration.zero);
    expect(calls.map((call) => call.arguments), [
      {'seconds': 1.250123, 'mode': 'keyframes'},
      {'seconds': 0.0, 'mode': 'exact'},
    ]);
  });

  test('dispatches the complete bounded outgoing command contract', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'selectTrack') {
        final arguments = call.arguments as Map<Object?, Object?>;
        scheduleMicrotask(() {
          unawaited(
            _sendNativeEvent(messenger, {
              'type': 'trackResult',
              'loadId': arguments['loadId'],
              'requestId': arguments['requestId'],
              'success': true,
            }),
          );
        });
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    final load = player.load(
      Uri.parse('https://plex.example/media/sample.mp4'),
    );
    await Future<void>.delayed(Duration.zero);
    final loadId = calls.last.arguments['loadId'] as int;
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
      'message': 'Playing',
    });
    await load;
    calls.clear();

    await player.play();
    await player.pause();
    await player.seek(const Duration(milliseconds: 1250));
    await player.setVideoRect(
      const PlayerVideoRect(
        left: 12,
        top: 34,
        width: 640,
        height: 360,
        scale: 2,
      ),
    );
    await player.setFullscreen(true);
    await player.selectTrack(PlayerTrackType.audio, 7);
    await player.selectTrack(PlayerTrackType.subtitle, null);
    await player.setVolume(42.5);
    final stop = player.stop();
    await Future<void>.delayed(Duration.zero);
    await _sendNativeEvent(messenger, {
      'type': 'stopResult',
      'stopId': calls.last.arguments['stopId'],
      'success': true,
    });
    await stop;

    expect(calls.map((call) => call.method), [
      'play',
      'pause',
      'seek',
      'setVideoRect',
      'setFullscreen',
      'selectTrack',
      'selectTrack',
      'setVolume',
      'stop',
    ]);
    expect(calls[2].arguments, {'seconds': 1.25, 'mode': 'exact'});
    expect(calls[3].arguments, {
      'left': 12.0,
      'top': 34.0,
      'width': 640.0,
      'height': 360.0,
      'scale': 2.0,
    });
    expect(calls[4].arguments, {'fullscreen': true});
    expect(calls[5].arguments, {
      'type': 'audio',
      'id': 7,
      'loadId': loadId,
      'requestId': 1,
    });
    expect(calls[6].arguments, {
      'type': 'subtitle',
      'id': null,
      'loadId': loadId,
      'requestId': 2,
    });
    expect(calls[7].arguments, {'volume': 42.5});
  });

  test(
    'reports native track execution failure without failing playback',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'selectTrack') {
          final arguments = call.arguments as Map<Object?, Object?>;
          scheduleMicrotask(() {
            unawaited(
              _sendNativeEvent(messenger, {
                'type': 'trackResult',
                'loadId': arguments['loadId'],
                'requestId': arguments['requestId'],
                'success': false,
              }),
            );
          });
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final load = player.load(
        Uri.parse('https://plex.example/media/sample.mp4'),
      );
      await Future<void>.delayed(Duration.zero);
      final loadId = calls.last.arguments['loadId'] as int;
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'playing',
        'message': 'Playing',
      });
      await load;

      await expectLater(
        player.selectTrack(PlayerTrackType.audio, 7),
        throwsA(
          isA<PlayerUnavailable>().having(
            (error) => error.failureCode,
            'failureCode',
            'command_error',
          ),
        ),
      );
      expect(player.status.state, PlayerState.playing);
    },
  );

  test('correlates overlapping native track execution results', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    final load = player.load(
      Uri.parse('https://plex.example/media/sample.mp4'),
    );
    await Future<void>.delayed(Duration.zero);
    final loadId = calls.last.arguments['loadId'] as int;
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
      'message': 'Playing',
    });
    await load;

    final first = player.selectTrack(PlayerTrackType.audio, 7);
    final firstFailure = expectLater(
      first,
      throwsA(
        isA<PlayerUnavailable>().having(
          (error) => error.failureCode,
          'failureCode',
          'command_error',
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final second = player.selectTrack(PlayerTrackType.audio, 8);
    var secondCompleted = false;
    unawaited(
      second.then<void>((_) {
        secondCompleted = true;
      }),
    );
    await Future<void>.delayed(Duration.zero);
    final trackCalls = calls
        .where((call) => call.method == 'selectTrack')
        .toList(growable: false);

    await _sendNativeEvent(messenger, {
      'type': 'trackResult',
      'loadId': loadId,
      'requestId': trackCalls.first.arguments['requestId'],
      'success': false,
    });
    await firstFailure;
    await Future<void>.delayed(Duration.zero);
    expect(secondCompleted, isFalse);

    await _sendNativeEvent(messenger, {
      'type': 'trackResult',
      'loadId': loadId,
      'requestId': trackCalls.last.arguments['requestId'],
      'success': true,
    });
    await second;
    expect(secondCompleted, isTrue);
    expect(player.status.state, PlayerState.playing);
  });

  test('bounds missing native track execution results', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer(
      trackTimeout: const Duration(milliseconds: 1),
    );
    addTearDown(player.dispose);
    await player.initialize();
    final load = player.load(
      Uri.parse('https://plex.example/media/sample.mp4'),
    );
    await Future<void>.delayed(Duration.zero);
    final loadId = calls.last.arguments['loadId'] as int;
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
      'message': 'Playing',
    });
    await load;

    await expectLater(
      player.selectTrack(PlayerTrackType.audio, 7),
      throwsA(
        isA<PlayerUnavailable>().having(
          (error) => error.failureCode,
          'failureCode',
          'wait_timeout',
        ),
      ),
    );
    expect(player.status.state, PlayerState.playing);
  });

  test(
    'normalizes allowlisted native command failures without raw prose',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'play') {
          throw PlatformException(
            code: 'command_queue_full',
            message: 'opaque native queue detail',
          );
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();

      await expectLater(
        player.play(),
        throwsA(
          isA<PlayerUnavailable>()
              .having(
                (error) => error.failureCode,
                'failureCode',
                'command_queue_full',
              )
              .having(
                (error) => error.message,
                'message',
                'The native player is busy. Try again.',
              ),
        ),
      );
    },
  );

  test('missing required engine uses platform-neutral wording', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'play') {
        throw PlatformException(code: 'required_engine_unavailable');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();

    await expectLater(
      player.play(),
      throwsA(
        isA<PlayerUnavailable>().having(
          (error) => error.message,
          'message',
          'The required video engine is unavailable.',
        ),
      ),
    );
  });

  test(
    'initial start validates before dispatch and preserves zero as an option',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final media = Uri.parse('https://media.example/a%20b?quality=original');
      await expectLater(
        player.load(media, startPosition: const Duration(microseconds: -1)),
        throwsA(
          isA<PlayerUnavailable>().having(
            (e) => e.failureCode,
            'failureCode',
            'invalid_argument',
          ),
        ),
      );
      expect(calls.where((c) => c.method == 'load'), isEmpty);
      final loaded = player.load(media, startPosition: Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final call = calls.last;
      expect(call.arguments['startSeconds'], 0.0);
      expect(call.arguments['uri'], media.toString());
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'state': 'playing',
        'loadId': call.arguments['loadId'],
      });
      await loaded;
    },
  );

  test('authenticated loads require an HTTPS authority in Dart', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();

    for (final insecure in [
      Uri.parse('http://dev-media.test/video.mp4'),
      Uri.parse('https:opaque-media-path'),
    ]) {
      await expectLater(
        player.load(insecure, plexToken: 'secret-token'),
        throwsA(
          isA<PlayerUnavailable>().having(
            (error) => error.failureCode,
            'failureCode',
            'insecure_media_uri',
          ),
        ),
      );
    }
    expect(calls.where((call) => call.method == 'load'), isEmpty);

    final load = player.load(Uri.parse('http://dev-media.test/video.mp4'));
    await Future<void>.delayed(Duration.zero);
    final loadCall = calls.singleWhere((call) => call.method == 'load');
    final loadId = loadCall.arguments!['loadId']! as int;
    expect(loadCall.arguments!['plexToken'], isNull);
    expect(loadCall.arguments.containsKey('startSeconds'), isFalse);
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
    });
    await load;
  });

  test('projects bounded native failure codes behaviorally', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    const messages = {
      'correlation_error': 'Media load tracking failed',
      'command_error': 'Media player command failed',
      'event_queue_overflow': 'Media player event queue overflowed',
    };

    for (final entry in messages.entries) {
      final load = player.load(Uri.parse('file:///${entry.key}.mp4'));
      await Future<void>.delayed(Duration.zero);
      final loadCall = calls.lastWhere((call) => call.method == 'load');
      final loadId = loadCall.arguments!['loadId']! as int;
      final expectation = expectLater(
        load,
        throwsA(
          isA<PlayerUnavailable>()
              .having((error) => error.failureCode, 'failureCode', entry.key)
              .having((error) => error.message, 'message', entry.value),
        ),
      );

      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'error',
        'message': 'raw native detail',
        'failureCode': entry.key,
      });

      await expectation;
      expect(player.status.failureCode, entry.key);
      expect(player.status.message, entry.value);
    }
  });

  test(
    'native load errors preserve retry and coordinator generation',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      final events = <PlayerEvent>[];
      final subscription = player.events.listen(events.add);
      addTearDown(subscription.cancel);
      await player.initialize();
      final load = player.load(
        Uri.parse('file:///retryable.mp4'),
        generation: 42,
      );
      await Future<void>.delayed(Duration.zero);
      final loadId = calls.last.arguments!['loadId']! as int;
      final loadExpectation = expectLater(
        load,
        throwsA(isA<PlayerUnavailable>()),
      );
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'error',
        'message': 'Temporary media failure',
      });

      await loadExpectation;
      expect(player.status.recoverable, isTrue);
      expect(
        events.where((event) => event.status.state == PlayerState.error),
        isNotEmpty,
      );
      expect(
        events
            .where((event) => event.status.state == PlayerState.error)
            .every(
              (event) => event.status.recoverable && event.generation == 42,
            ),
        isTrue,
      );
    },
  );

  test(
    'maps structured native failures without exposing native prose',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final load = player.load(Uri.parse('https://plex.example/media'));
      await Future<void>.delayed(Duration.zero);
      final loadId = calls.last.arguments!['loadId']! as int;
      final expectation = expectLater(
        load,
        throwsA(
          isA<PlayerUnavailable>().having(
            (error) => error.message,
            'message',
            'Media server returned HTTP 503',
          ),
        ),
      );

      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'error',
        'message': 'raw native detail that must not reach Dart UI',
        'failureCode': 'http_error',
        'httpStatus': 503,
      });

      await expectation;
      expect(player.status.message, 'Media server returned HTTP 503');
      expect(player.status.failureCode, 'http_error');
      expect(player.status.httpStatus, 503);
    },
  );

  test('preserves the bounded libmpv fallback description', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    final load = player.load(Uri.parse('file:///broken.mp4'));
    await Future<void>.delayed(Duration.zero);
    final loadId = calls.last.arguments!['loadId']! as int;
    final expectation = expectLater(load, throwsA(isA<PlayerUnavailable>()));

    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'error',
      'message': 'loading failed',
      'failureCode': 'mpv_error',
    });

    await expectation;
    expect(player.status.message, 'loading failed');
    expect(player.status.failureCode, 'mpv_error');
    expect(player.status.httpStatus, isNull);
  });

  test('normalizes unknown native failure codes before projection', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    final load = player.load(Uri.parse('file:///broken.mp4'));
    await Future<void>.delayed(Duration.zero);
    final loadId = calls.last.arguments!['loadId']! as int;
    final expectation = expectLater(
      load,
      throwsA(
        isA<PlayerUnavailable>()
            .having((error) => error.failureCode, 'failureCode', 'native_error')
            .having(
              (error) => error.message,
              'message',
              'Media playback failed',
            ),
      ),
    );

    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'error',
      'message': 'opaque native detail',
      'failureCode': 'unbounded_native_extension',
    });

    await expectation;
    expect(player.status.failureCode, 'native_error');
    expect(player.status.message, 'Media playback failed');
  });

  test(
    'ignores stale or unscoped events and clears facts for replacement',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final first = player.load(Uri.parse('file:///one.mp4'));
      await Future<void>.delayed(Duration.zero);
      final firstId = calls.last.arguments!['loadId']! as int;
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': firstId,
        'name': 'video-codec',
        'value': 'h264',
      });
      final second = player.load(Uri.parse('file:///two.mp4'));
      await expectLater(first, throwsA(isA<PlayerUnavailable>()));
      await Future<void>.delayed(Duration.zero);
      final secondId = calls.last.arguments!['loadId']! as int;

      expect(player.telemetry.videoCodec, isNull);
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': firstId,
        'state': 'playing',
      });
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': firstId,
        'state': 'ended',
        'message': 'Playback ended',
      });
      await _sendNativeEvent(messenger, {'type': 'state', 'state': 'playing'});
      expect(player.status.state, PlayerState.loading);

      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': secondId,
        'state': 'playing',
      });
      await second;
    },
  );

  test(
    'ignores duplicate terminal events and clears nullable telemetry',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final video = player.load(Uri.parse('file:///video.mp4'));
      await Future<void>.delayed(Duration.zero);
      final videoId = calls.last.arguments!['loadId']! as int;
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': videoId,
        'name': 'video-codec',
        'value': 'h264',
      });
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': videoId,
        'state': 'playing',
      });
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': videoId,
        'state': 'playing',
      });
      await video;

      final audio = player.load(Uri.parse('file:///audio.mp3'));
      final audioFailure = expectLater(
        audio,
        throwsA(isA<PlayerUnavailable>()),
      );
      await Future<void>.delayed(Duration.zero);
      final audioId = calls.last.arguments!['loadId']! as int;
      expect(player.telemetry.videoCodec, isNull);
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': audioId,
        'name': 'video-codec',
        'value': null,
      });
      expect(player.telemetry.videoCodec, isNull);
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': audioId,
        'state': 'error',
      });
      await audioFailure;
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': audioId,
        'state': 'error',
      });
    },
  );

  test(
    'serializes initialize and dispose while initialization is pending',
    () async {
      final initializeResponse = Completer<void>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return call.method == 'initialize' ? initializeResponse.future : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      final initialize = player.initialize();
      final dispose = player.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((call) => call.method), ['initialize']);
      initializeResponse.complete();
      await initialize;
      await dispose;
      expect(calls.map((call) => call.method), ['initialize', 'dispose']);
    },
  );

  test(
    'dispose rejects a pending load and late events cannot mutate it',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final load = player.load(Uri.parse('file:///pending.mp4'));
      final loadFailure = expectLater(load, throwsA(isA<PlayerUnavailable>()));
      await Future<void>.delayed(Duration.zero);
      final loadId = calls.last.arguments!['loadId']! as int;
      await player.dispose();
      await loadFailure;
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'video-codec',
        'value': 'late',
      });
      expect(player.telemetry.videoCodec, isNull);
    },
  );

  test(
    'stop queue acknowledgment is not completion and failure is retryable',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      var settled = false;
      final stop = player.stop().whenComplete(() => settled = true);
      final failure = expectLater(
        stop,
        throwsA(
          isA<PlayerUnavailable>().having(
            (error) => error.failureCode,
            'failureCode',
            'stop_failed',
          ),
        ),
      );
      await pumpEventQueue(times: 2);
      expect(settled, isFalse);
      final firstId = calls.last.arguments['stopId'];
      await _sendNativeEvent(messenger, {
        'type': 'stopResult',
        'stopId': firstId,
        'success': false,
      });
      await failure;
      final retry = player.stop();
      await pumpEventQueue(times: 2);
      final nextId = calls.last.arguments['stopId'];
      expect(nextId, isNot(firstId));
      await _sendNativeEvent(messenger, {
        'type': 'stopResult',
        'stopId': nextId,
        'success': true,
      });
      await retry;
      expect(player.status.state, PlayerState.stopped);
    },
  );

  testWidgets(
    'late stop result after timeout cannot complete a retry or replacement',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final player = MethodChannelNativePlayer(
        stopTimeout: const Duration(milliseconds: 20),
      );
      final initialization = player.initialize();
      await tester.pump();
      await initialization;
      final firstStop = expectLater(
        player.stop(),
        throwsA(
          isA<PlayerUnavailable>().having(
            (error) => error.failureCode,
            'failureCode',
            'stop_timeout',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await firstStop;
      final firstId = calls.last.arguments['stopId'];
      final retry = player.stop();
      final replacement = player.load(Uri.parse('file:///replacement.mp4'));
      await tester.pump();
      final nextId = calls.last.arguments['stopId'];
      await _sendNativeEvent(messenger, {
        'type': 'stopResult',
        'stopId': firstId,
        'success': true,
      });
      expect(calls.where((call) => call.method == 'load'), isEmpty);
      await _sendNativeEvent(messenger, {
        'type': 'stopResult',
        'stopId': nextId,
        'success': true,
      });
      await retry;
      await tester.pump();
      final loadId = calls.last.arguments['loadId'];
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'playing',
      });
      await replacement;
      await _sendNativeEvent(messenger, {
        'type': 'stopResult',
        'stopId': firstId,
        'success': true,
      });
      expect(player.status.state, PlayerState.playing);
      final disposal = player.dispose();
      await tester.pump();
      await disposal;
    },
  );

  test(
    'dispose settles pending stop and rejects its late result after recreation',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final player = MethodChannelNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final stop = player.stop();
      final failure = expectLater(stop, throwsA(isA<PlayerUnavailable>()));
      await pumpEventQueue(times: 2);
      final stopId = calls.last.arguments['stopId'];
      await player.dispose();
      await failure;
      await player.initialize();
      await _sendNativeEvent(messenger, {
        'type': 'stopResult',
        'stopId': stopId,
        'success': true,
      });
      expect(player.status.state, PlayerState.idle);
    },
  );

  test('stop retires a pending load before its native reply and ignores late events', () async {
    final calls = <MethodCall>[];
    final stopReply = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return call.method == 'stop' ? stopReply.future : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    var loadSettled = false;
    final load = player
        .load(Uri.parse('file:///pending.mp4'), generation: 7)
        .whenComplete(() => loadSettled = true);
    final loadFailure = expectLater(load, throwsA(isA<PlayerUnavailable>()));
    await Future<void>.delayed(Duration.zero);
    final loadId = calls.last.arguments!['loadId']! as int;
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'video-codec',
      'value': 'h264',
    });
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'time-pos',
      'value': 12,
    });
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'duration',
      'value': 30,
    });
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'track-list',
      'value': [
        {'id': 1, 'type': 'video', 'selected': true},
      ],
    });

    var stopSettled = false;
    final stop = player.stop().whenComplete(() => stopSettled = true);
    await Future<void>.delayed(Duration.zero);

    expect(loadSettled, isTrue);
    expect(stopSettled, isFalse);
    expect(player.status.state, PlayerState.loading);
    expect(player.telemetry.videoCodec, 'h264');
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'video-codec',
      'value': 'late',
    });
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
    });
    expect(player.telemetry.videoCodec, 'h264');

    stopReply.complete();
    await _sendNativeEvent(messenger, {
      'type': 'stopResult',
      'stopId': calls
          .where((call) => call.method == 'stop')
          .last
          .arguments['stopId'],
      'success': true,
    });
    await stop;
    await loadFailure;
    expect(player.status.state, PlayerState.stopped);
    expect(player.status.message, 'Stopped');
    expect(player.position, Duration.zero);
    expect(player.duration, Duration.zero);
    expect(player.telemetry.videoCodec, isNull);
    expect(player.tracks, isEmpty);
  });

  test('replacement load waits for native stop completion', () async {
    final calls = <MethodCall>[];
    final stopReply = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return call.method == 'stop' ? stopReply.future : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    final first = player.load(Uri.parse('file:///first.mp4'), generation: 1);
    await Future<void>.delayed(Duration.zero);
    final firstId = calls.last.arguments!['loadId']! as int;
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': firstId,
      'state': 'playing',
    });
    await first;

    final stop = player.stop();
    await Future<void>.delayed(Duration.zero);
    final replacement = player.load(
      Uri.parse('file:///replacement.mp4'),
      generation: 2,
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((call) => call.method == 'load'), hasLength(1));
    stopReply.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((call) => call.method == 'load'), hasLength(1));
    await _sendNativeEvent(messenger, {
      'type': 'stopResult',
      'stopId': calls.last.arguments['stopId'],
      'success': true,
    });
    await stop;
    await Future<void>.delayed(Duration.zero);
    final replacementId = calls.last.arguments!['loadId']! as int;
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': replacementId,
      'name': 'video-codec',
      'value': 'hevc',
    });
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': replacementId,
      'state': 'playing',
    });
    await replacement;

    expect(player.status.state, PlayerState.playing);
    expect(player.telemetry.videoCodec, 'hevc');
  });

  test('load invocation failure retires its load id', () async {
    var loadId = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'load') {
        loadId = call.arguments!['loadId']! as int;
        throw PlatformException(code: 'load_failed');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    await expectLater(
      player.load(Uri.parse('file:///broken.mp4')),
      throwsA(
        isA<PlayerUnavailable>()
            .having(
              (error) => error.failureCode,
              'failureCode',
              'native_command_error',
            )
            .having(
              (error) => error.message,
              'message',
              'The native player command failed.',
            ),
      ),
    );
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
    });
    expect(player.status.state, PlayerState.error);
  });

  test('load timeout retires its load id', () async {
    var loadId = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'load') loadId = call.arguments!['loadId']! as int;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer(loadTimeout: Duration.zero);
    addTearDown(player.dispose);
    await player.initialize();
    await expectLater(
      player.load(Uri.parse('file:///timeout.mp4')),
      throwsA(isA<TimeoutException>()),
    );
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'video-codec',
      'value': 'late',
    });
    expect(player.telemetry.videoCodec, isNull);
    expect(player.status.state, PlayerState.error);
  });

  test(
    'replacement observes pending failure before delayed load reply',
    () async {
      final calls = <MethodCall>[];
      final firstReply = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        if (call.method == 'load' &&
            calls.where((item) => item.method == 'load').length == 1) {
          return firstReply.future;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        final player = MethodChannelNativePlayer();
        addTearDown(player.dispose);
        await player.initialize();
        final first = player.load(Uri.parse('file:///first.mp4'));
        final firstFailure = expectLater(
          first,
          throwsA(isA<PlayerUnavailable>()),
        );
        await Future<void>.delayed(Duration.zero);

        final second = player.load(Uri.parse('file:///second.mp4'));
        await Future<void>.delayed(Duration.zero);
        final secondCall = calls.where((call) => call.method == 'load').last;
        await _sendNativeEvent(messenger, {
          'type': 'state',
          'loadId': secondCall.arguments!['loadId']! as int,
          'state': 'playing',
        });
        await second;
        firstReply.complete();
        await firstFailure;
      }, (error, _) => uncaught.add(error));

      expect(uncaught, isEmpty);
    },
  );

  test('null video parameters clear grouped telemetry and HDR', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    final load = player.load(Uri.parse('file:///hdr.mp4'));
    await Future<void>.delayed(Duration.zero);
    final loadId = calls.last.arguments!['loadId']! as int;
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'video-params',
      'value': {
        'w': 3840,
        'h': 2160,
        'pixelformat': 'p010',
        'hw-pixelformat': 'd3d11',
        'primaries': 'bt.2020',
        'gamma': 'pq',
        'colormatrix': 'bt.2020-ncl',
        'sig-peak': 10.0,
      },
    });
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'video-params',
      'value': {'w': 'invalid'},
    });
    expect(player.telemetry.width, 3840);
    expect(player.telemetry.isHdr, isTrue);

    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'video-params',
      'value': null,
    });
    expect(player.telemetry.width, isNull);
    expect(player.telemetry.height, isNull);
    expect(player.telemetry.pixelFormat, isNull);
    expect(player.telemetry.hardwarePixelFormat, isNull);
    expect(player.telemetry.primaries, isNull);
    expect(player.telemetry.gamma, isNull);
    expect(player.telemetry.colorMatrix, isNull);
    expect(player.telemetry.signalPeak, isNull);
    expect(player.telemetry.isHdr, isFalse);

    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
    });
    await load;
  });

  test('pause events remain scoped across replacement autoplay', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = MethodChannelNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    final first = player.load(Uri.parse('file:///first.mp4'));
    await Future<void>.delayed(Duration.zero);
    final firstId = calls.last.arguments!['loadId']! as int;
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': firstId,
      'state': 'playing',
    });
    await first;
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': firstId,
      'name': 'pause',
      'value': true,
    });
    expect(player.status.state, PlayerState.paused);

    final second = player.load(Uri.parse('file:///second.mp4'));
    await Future<void>.delayed(Duration.zero);
    final secondId = calls.last.arguments!['loadId']! as int;
    expect(player.status.state, PlayerState.loading);
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': firstId,
      'name': 'pause',
      'value': false,
    });
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': secondId,
      'name': 'pause',
      'value': true,
    });
    expect(player.status.state, PlayerState.loading);
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': secondId,
      'state': 'playing',
    });
    await second;
    // mpv does not repeat pause=true after FILE_LOADED.
    expect(player.status.state, PlayerState.paused);

    final third = player.load(Uri.parse('file:///third.mp4'));
    await Future<void>.delayed(Duration.zero);
    final thirdId = calls.last.arguments!['loadId']! as int;
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': thirdId,
      'state': 'playing',
    });
    await third;
    expect(player.status.state, PlayerState.playing);
  });

  test('rejects a second platform-channel owner', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final first = MethodChannelNativePlayer();
    addTearDown(first.dispose);
    final second = MethodChannelNativePlayer();
    addTearDown(second.dispose);
    await first.initialize();
    await expectLater(second.initialize(), throwsA(isA<PlayerUnavailable>()));
    await first.dispose();
    await second.initialize();
  });
}

Future<void> _sendNativeEvent(
  TestDefaultBinaryMessenger messenger,
  Map<String, Object?> event,
) {
  return messenger.handlePlatformMessage(
    'lineup/native_player',
    const StandardMethodCodec().encodeMethodCall(MethodCall('event', event)),
    null,
  );
}
