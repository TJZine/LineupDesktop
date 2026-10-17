import 'method_channel_native_player.dart';
import 'native_player.dart';
import 'unsupported_native_player.dart';

NativePlayer createPlatformNativePlayer({
  required bool isWindows,
  required bool isMacOS,
}) {
  if (isWindows) return MethodChannelNativePlayer();
  return UnsupportedNativePlayer(
    message: isMacOS
        ? UnsupportedNativePlayer.macOSMessage
        : UnsupportedNativePlayer.platformMessage,
  );
}
