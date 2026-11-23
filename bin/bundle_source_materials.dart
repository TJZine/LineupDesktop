import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  File argument(String name) => File(
    arguments
        .singleWhere((value) => value.startsWith('--$name='))
        .substring('--$name='.length),
  );

  final input = argument('input');
  final output = argument('output');
  final sources = (jsonDecode(input.readAsStringSync()) as Map<String, dynamic>)
      .cast<String, String>();
  final root = Directory.current.resolveSymbolicLinksSync();
  final documents = <String, String>{};
  for (final entry in sources.entries) {
    final path = entry.value;
    if (!RegExp(r'^[a-zA-Z0-9_./ -]+$').hasMatch(path) ||
        path
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw FormatException('Invalid source material path', path);
    }
    final file = File('$root/$path');
    if (!file.resolveSymbolicLinksSync().startsWith(
      '$root${Platform.pathSeparator}',
    )) {
      throw FormatException(
        'Source material resolves outside the repository',
        path,
      );
    }
    final bytes = file.readAsBytesSync();
    final text = utf8.decode(bytes);
    // Dart consumes a leading UTF-8 BOM. Keep it in the delivered source.
    final hasBom =
        bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf;
    documents[entry.key] = hasBom ? '\ufeff$text' : text;
  }
  output.writeAsStringSync(jsonEncode(documents));
  String depfilePath(String path) =>
      path.replaceAll(r'\', r'\\').replaceAll(' ', r'\ ');
  final dependencies = sources.values.toSet().map(depfilePath).join(' ');
  File('${output.path}.d')
      .writeAsStringSync('${depfilePath(output.path)}: $dependencies\n');
}
