import 'method_channel_native_player.dart';
import 'native_player.dart';
import 'unsupported_native_player.dart';

/// Windows and macOS implement the `lineup/native_player` protocol on the
/// shared libmpv core; every other platform reports unsupported playback.
NativePlayer createPlatformNativePlayer({
  required bool isWindows,
  required bool isMacOS,
}) {
  if (isWindows || isMacOS) return MethodChannelNativePlayer();
  return UnsupportedNativePlayer(
    message: UnsupportedNativePlayer.platformMessage,
  );
}
