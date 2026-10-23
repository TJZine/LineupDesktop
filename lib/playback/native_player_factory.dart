import 'method_channel_native_player.dart';
import 'native_player.dart';
import 'unsupported_native_player.dart';

/// Windows and macOS implement the `lineup/native_player` protocol on the
/// shared libmpv core. Android implements the same wire with Media3.
NativePlayer createPlatformNativePlayer({
  required bool isWindows,
  required bool isMacOS,
  bool isAndroid = false,
}) {
  if (isWindows || isMacOS || isAndroid) return MethodChannelNativePlayer();
  return UnsupportedNativePlayer(
    message: UnsupportedNativePlayer.platformMessage,
  );
}
