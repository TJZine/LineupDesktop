import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/method_channel_native_player.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/native_player_factory.dart';
import 'package:lineup_desktop/playback/unsupported_native_player.dart';

void main() {
  test('macOS backend never masquerades as successful playback', () async {
    final player = UnsupportedNativePlayer.macos();

    await player.initialize();
    expect(player.status.state, PlayerState.unsupported);
    expect(player.status.message, contains('not implemented'));
    await expectLater(player.play(), throwsA(isA<PlayerUnavailable>()));
    await expectLater(
      player.load(Uri.parse('https://example.invalid/media')),
      throwsA(
        isA<PlayerUnavailable>().having(
          (error) => error.message,
          'message',
          'Native playback is not implemented on macOS.',
        ),
      ),
    );
    await player.dispose();
  });

  test(
    'factory selects the method-channel or truthful unsupported backend',
    () {
      expect(
        createPlatformNativePlayer(isWindows: true, isMacOS: false),
        isA<MethodChannelNativePlayer>(),
      );
      final macOS = createPlatformNativePlayer(isWindows: false, isMacOS: true);
      expect(macOS, isA<UnsupportedNativePlayer>());
      expect(macOS.status.message, 'Playback is not implemented on macOS');

      final other = createPlatformNativePlayer(
        isWindows: false,
        isMacOS: false,
      );
      expect(other, isA<UnsupportedNativePlayer>());
      expect(
        other.status.message,
        'Playback is not implemented on this platform',
      );
    },
  );

  test('PlayerTelemetry equality covers every reported fact', () {
    const baseline = PlayerTelemetry(
      videoOutput: 'gpu',
      hardwareDecoder: 'd3d11',
      videoCodec: 'h264',
      videoFormat: 'yuv420p',
      width: 1920,
      height: 1080,
      pixelFormat: 'nv12',
      hardwarePixelFormat: 'd3d11',
      primaries: 'bt.709',
      gamma: 'pq',
      targetGamma: 'pq',
      targetPrimaries: 'bt.2020',
      targetPixelFormat: 'rgba16f',
      colorMatrix: 'bt.709',
      signalPeak: 10,
    );
    const same = PlayerTelemetry(
      videoOutput: 'gpu',
      hardwareDecoder: 'd3d11',
      videoCodec: 'h264',
      videoFormat: 'yuv420p',
      width: 1920,
      height: 1080,
      pixelFormat: 'nv12',
      hardwarePixelFormat: 'd3d11',
      primaries: 'bt.709',
      gamma: 'pq',
      targetGamma: 'pq',
      targetPrimaries: 'bt.2020',
      targetPixelFormat: 'rgba16f',
      colorMatrix: 'bt.709',
      signalPeak: 10,
    );
    expect(baseline, same);
    expect(baseline.hashCode, same.hashCode);
    for (final variant in [
      const PlayerTelemetry(videoOutput: 'other'),
      const PlayerTelemetry(hardwareDecoder: 'other'),
      const PlayerTelemetry(videoCodec: 'other'),
      const PlayerTelemetry(videoFormat: 'other'),
      const PlayerTelemetry(width: 1),
      const PlayerTelemetry(height: 1),
      const PlayerTelemetry(pixelFormat: 'other'),
      const PlayerTelemetry(hardwarePixelFormat: 'other'),
      const PlayerTelemetry(primaries: 'other'),
      const PlayerTelemetry(gamma: 'other'),
      const PlayerTelemetry(targetGamma: 'other'),
      const PlayerTelemetry(targetPrimaries: 'other'),
      const PlayerTelemetry(targetPixelFormat: 'other'),
      const PlayerTelemetry(colorMatrix: 'other'),
      const PlayerTelemetry(signalPeak: 1),
    ]) {
      expect(baseline, isNot(variant));
    }
  });
}
