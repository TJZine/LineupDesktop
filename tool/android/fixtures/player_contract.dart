// Disposable emulator runtime check: real Dart transport + production Android adapter.
// This entrypoint never reads app state, credentials, Plex, or private media.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lineup_desktop/playback/method_channel_native_player.dart';
import 'package:lineup_desktop/playback/native_player.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _FixtureOverlay()));
  WidgetsBinding.instance.addPostFrameCallback((_) => _run(args));
}

class _FixtureOverlay extends StatelessWidget {
  const _FixtureOverlay();
  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.transparent,
    body: Align(
      alignment: Alignment.topRight,
      child: ColoredBox(
        color: Color(0x80552D04),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Synthetic player contract',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
    ),
  );
}

void _fact(String phase, [Map<String, Object?> facts = const {}]) {
  // Never serialize PlayerUnavailable, URI, token, tracks/title or raw native output.
  // ignore: avoid_print
  print('U3_CONTRACT ${jsonEncode({'phase': phase, ...facts})}');
}

Future<void> _wait(bool Function() condition, {int seconds = 12}) async {
  final until = DateTime.now().add(Duration(seconds: seconds));
  while (!condition()) {
    if (DateTime.now().isAfter(until)) throw StateError('observation_timeout');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> _run(List<String> args) async {
  final player = MethodChannelNativePlayer();
  final mode =
      args.where((a) => a.startsWith('--case=')).firstOrNull?.substring(7) ??
      'contract';
  var phase = 'initialize';
  player.events.listen((event) {
    if (event.status.state == PlayerState.error ||
        event.status.state == PlayerState.ended) {
      _fact('event', {
        'state': event.status.state.name,
        'code': event.status.failureCode,
        'generation': event.generation,
      });
    }
  });
  Future<void> load(
    String fixture, {
    bool paused = false,
    double? start,
    int generation = 1,
    bool token = true,
  }) async {
    await player.load(
      Uri.parse('https://localhost:18443/${token ? 'auth/' : ''}$fixture'),
      plexToken: token ? 'lineup-synthetic-fixture-only' : null,
      startPaused: paused,
      startPosition: start == null
          ? null
          : Duration(microseconds: (start * 1000000).round()),
      generation: generation,
    );
  }

  try {
    await player.initialize();
    if (!player.fullscreen) throw StateError('initial_fullscreen');
    await player.setFullscreen(false);
    if (!player.fullscreen) throw StateError('observed_fullscreen');
    await player.setDisplayMatching(
      const DisplayMatchingRequest(
        revision: 1,
        session: true,
        desired: DisplayMatchingState.hdr,
      ),
    );
    await _wait(
      () =>
          player.displayReport.session ==
          DisplayMatchingSessionState.unavailable,
    );
    await player.setVideoRect(
      const PlayerVideoRect(left: 0, top: 0, width: 960, height: 540, scale: 2),
    );
    _fact('initialized');
    if (mode == 'release-isolation') {
      phase = 'release-isolation';
      try {
        await load('h264.mp4');
        throw StateError('untrusted_ca_accepted');
      } on PlayerUnavailable catch (e) {
        if (e.failureCode != 'network_error') rethrow;
        _fact('PASS', {'case': mode, 'code': e.failureCode});
      }
      return;
    }
    if (mode == 'background') {
      phase = 'background-load';
      await load('h264.mp4');
      await _wait(() => player.position > const Duration(seconds: 1));
      _fact('background-ready');
      await _wait(
        () => player.status.state == PlayerState.stopped,
        seconds: 45,
      );
      _fact('background-stopped');
      await _wait(
        () =>
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
        seconds: 45,
      );
      phase = 'foreground-successor';
      await load('h264.mp4', generation: 2, start: 23.25);
      await _wait(() => player.position > const Duration(seconds: 24));
      _fact('PASS', {'case': mode});
      return;
    }
    if (mode == 'negative') {
      for (final (fixture, expected) in [
        ('cross-host', 'network_error'),
        ('cross-port', 'network_error'),
        ('downgrade', 'network_error'),
        ('loop', 'network_error'),
        ('nested.m3u8', 'container_error'),
        ('bad-parent.mp4', 'container_error'),
        ('unknown-jp2.mp4', 'video_decode_error'),
        ('unknown-audio.mp4', 'audio_decode_error'),
        ('unsupported-video.mkv', 'video_decode_error'),
        ('unsupported-audio.mkv', 'audio_decode_error'),
      ]) {
        phase = fixture;
        try {
          await load(fixture);
          throw StateError('negative_control_played');
        } on PlayerUnavailable catch (e) {
          if (e.failureCode != expected) rethrow;
          _fact('negative', {'case': fixture, 'code': e.failureCode});
        }
        await player.stop();
      }
      for (final (uri, status) in [
        ('https://localhost:18443/auth/h264.mp4', 401),
        ('https://localhost:18443/missing.mp4', 404),
      ]) {
        phase = 'http-$status';
        try {
          await player.load(Uri.parse(uri));
          throw StateError('http_control_played');
        } on PlayerUnavailable catch (e) {
          if (e.failureCode != 'http_error' ||
              player.status.httpStatus != status) {
            rethrow;
          }
          _fact('negative-http', {'status': status, 'code': e.failureCode});
        }
        await player.stop();
      }
      phase = 'same-origin';
      await load('same');
      await _wait(() => player.position > const Duration(seconds: 1));
      _fact('PASS', {'case': mode});
      return;
    }
    if (mode == 'formats') {
      for (final fixture in [
        'audio-only.mp4',
        'video-only.mp4',
        'mixed-audio.mp4',
        'mixed-video.mp4',
        'late-moov.mp4',
        'fragmented.mp4',
        'chapters.mp4',
        'tracks.mp4',
        'audio-only.mkv',
        'video-only.mkv',
        'mixed-audio.mkv',
        'mixed-video.mkv',
      ]) {
        phase = fixture;
        await load(fixture);
        await _wait(
          () =>
              player.position > const Duration(seconds: 1) ||
              player.status.state == PlayerState.error,
        );
        if (player.status.state == PlayerState.error) {
          throw StateError('format_failed');
        }
        await player.seek(const Duration(milliseconds: 2250));
        await _wait(
          () =>
              player.position >= const Duration(milliseconds: 2250) ||
              player.status.state == PlayerState.error,
        );
        if (player.status.state == PlayerState.error) {
          throw StateError('format_seek_failed');
        }
        _fact('format', {
          'case': fixture,
          'positionMs': player.position.inMilliseconds,
        });
        await player.stop();
      }
      _fact('PASS', {'case': mode});
      return;
    }
    if (mode == 'seek-lifetime') {
      phase = 'indexed-valid-load';
      await load('indexed-repeat-valid.mp4', paused: true);
      await player.seek(const Duration(seconds: 45));
      await player.play();
      await _wait(
        () =>
            player.position >= const Duration(seconds: 64) ||
            player.status.state == PlayerState.error,
        seconds: 25,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      if (player.status.state != PlayerState.playing) {
        throw StateError('valid_indexed_initialization');
      }
      _fact('indexed-valid', {'positionMs': player.position.inMilliseconds});
      await player.stop();
      phase = 'indexed-omitted-load';
      await load('indexed-repeat-unknown.mp4', paused: true);
      await player.seek(const Duration(seconds: 45));
      await player.play();
      await _wait(() => player.status.state == PlayerState.error, seconds: 30);
      if (player.status.failureCode != 'video_decode_error') {
        throw StateError('indexed_omission_not_typed');
      }
      _fact('PASS', {'case': mode, 'code': player.status.failureCode});
      return;
    }
    if (mode == 'lifetime') {
      for (final fixture in [
        'repeat-continuous-fragmented.mp4',
        'repeat-unknown-fragmented.mp4',
      ]) {
        phase = fixture;
        await load(fixture);
        if (fixture == 'repeat-continuous-fragmented.mp4') {
          final until = DateTime.now().add(const Duration(seconds: 16));
          while (DateTime.now().isBefore(until)) {
            await Future<void>.delayed(const Duration(seconds: 1));
            _fact('lifetime-position', {
              'positionMs': player.position.inMilliseconds,
              'state': player.status.state.name,
            });
            if (player.status.state == PlayerState.error ||
                player.status.state == PlayerState.ended) {
              throw StateError('valid_second_segment_failed');
            }
          }
        } else {
          await _wait(
            () => player.status.state == PlayerState.error,
            seconds: 25,
          );
        }
        if (fixture == 'repeat-continuous-fragmented.mp4') {
          if (player.status.state == PlayerState.error) {
            throw StateError('valid_second_moov');
          }
          _fact('lifetime-valid', {
            'positionMs': player.position.inMilliseconds,
          });
        } else {
          if (player.status.failureCode != 'video_decode_error') {
            throw StateError('omitted_second_moov');
          }
          _fact('lifetime-omitted', {'code': player.status.failureCode});
        }
        await player.stop();
      }
      _fact('PASS', {'case': mode});
      return;
    }
    phase = 'paused-initial-join';
    await load('h264.mp4', paused: true, start: 13.25);
    await _wait(() => player.position >= const Duration(seconds: 13));
    if (player.status.state != PlayerState.paused) {
      throw StateError('paused_ready');
    }
    _fact(phase, {'positionMs': player.position.inMilliseconds});
    phase = 'play-pause';
    await player.play();
    await _wait(() => player.position > const Duration(seconds: 14));
    await player.pause();
    await _wait(() => player.status.state == PlayerState.paused);
    phase = 'exact';
    await player.seek(const Duration(milliseconds: 31250));
    await _wait(() => (player.position.inMilliseconds - 31250).abs() < 150);
    _fact(phase, {'positionMs': player.position.inMilliseconds});
    phase = 'keyframes';
    await player.seek(
      const Duration(milliseconds: 45250),
      mode: SeekMode.keyframes,
    );
    await _wait(
      () =>
          player.position.inMilliseconds >= 43000 &&
          player.position.inMilliseconds < 45250,
    );
    _fact(phase, {'positionMs': player.position.inMilliseconds});
    phase = 'rectangle';
    await player.setVideoRect(
      const PlayerVideoRect(
        left: 20,
        top: 30,
        width: 600,
        height: 338,
        scale: 2,
      ),
    );
    await player.setVideoRect(
      const PlayerVideoRect(left: 0, top: 0, width: 0, height: 0, scale: 2),
    );
    await player.play();
    final before = player.position;
    await _wait(
      () => player.position > before + const Duration(milliseconds: 500),
    );
    await player.setVideoRect(
      const PlayerVideoRect(left: 0, top: 0, width: 960, height: 540, scale: 2),
    );
    _fact(phase);
    phase = 'stop-successor';
    await player.stop();
    await load('tracks-aac.mkv', generation: 2);
    await _wait(
      () =>
          player.tracks.where((t) => t.type == PlayerTrackType.audio).length ==
              2 &&
          player.tracks
                  .where((t) => t.type == PlayerTrackType.subtitle)
                  .length ==
              2,
    );
    for (final type in [PlayerTrackType.audio, PlayerTrackType.subtitle]) {
      for (final track in player.tracks.where((t) => t.type == type).toList()) {
        phase = 'track-${type.name}';
        await player.selectTrack(type, track.id);
        await _wait(
          () => player.tracks.any((t) => t.id == track.id && t.selected),
        );
        _fact(phase, {'id': track.id, 'codec': track.codec});
        if (type == PlayerTrackType.subtitle) {
          await Future<void>.delayed(const Duration(seconds: 5));
        }
      }
    }
    phase = 'subtitles-off';
    await player.selectTrack(PlayerTrackType.subtitle, null);
    await _wait(
      () => player.tracks
          .where((t) => t.type == PlayerTrackType.subtitle)
          .every((t) => !t.selected),
    );
    phase = 'subtitles-on';
    final text = player.tracks.firstWhere(
      (t) => t.type == PlayerTrackType.subtitle,
    );
    await player.selectTrack(PlayerTrackType.subtitle, text.id);
    await _wait(() => player.tracks.any((t) => t.id == text.id && t.selected));
    _fact('tracks-observed');
    phase = 'eof';
    await player.stop();
    await load('eof.mp4', generation: 3);
    await _wait(() => player.status.state == PlayerState.ended, seconds: 15);
    await load('h264.mp4', generation: 4);
    await _wait(() => player.position > const Duration(seconds: 1));
    _fact('PASS', {'case': mode});
  } catch (e) {
    _fact('FAIL', {
      'at': phase,
      'code': e is PlayerUnavailable ? e.failureCode : 'assertion_or_timeout',
    });
  } finally {
    try {
      await player.dispose();
      _fact('disposed');
    } catch (_) {
      _fact('FAIL', {'at': 'dispose', 'code': 'dispose_failed'});
    }
  }
}
