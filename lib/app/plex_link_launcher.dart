import 'dart:io';

/// Opens only the public linking page; the viewer enters the displayed code.
Future<void> openPlexLink() async {
  final (executable, arguments) = switch (Platform.operatingSystem) {
    'macos' => ('open', const ['https://plex.tv/link']),
    'windows' => (
      'rundll32.exe',
      const ['url.dll,FileProtocolHandler', 'https://plex.tv/link'],
    ),
    _ => throw UnsupportedError('Browser linking is unavailable.'),
  };
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw const ProcessException('browser', [], 'Could not open browser.');
  }
}
