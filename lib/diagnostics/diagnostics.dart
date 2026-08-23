class DiagnosticEntry {
  const DiagnosticEntry(this.time, this.area, this.message, this.context);

  final DateTime time;
  final String area;
  final String message;
  final Map<String, Object> context;
}

class Diagnostics {
  final List<DiagnosticEntry> _entries = [];
  bool _enabled = false;

  List<DiagnosticEntry> get entries => List.unmodifiable(_entries);

  bool get enabled => _enabled;

  set enabled(bool value) {
    _enabled = value;
    if (!value) _entries.clear();
  }

  void add(
    String area,
    String message, [
    Map<String, Object?> context = const {},
  ]) {
    if (!enabled) return;
    final safe = <String, Object>{};
    for (final entry in context.entries) {
      final value = entry.value;
      if (_stringKeys.contains(entry.key) && value is String) {
        safe[entry.key] = _safeToken.hasMatch(value) ? value : 'unexpected';
      } else if (entry.key == 'httpStatus' &&
          value is int &&
          value >= 100 &&
          value <= 599) {
        safe[entry.key] = value;
      } else if (entry.key == 'count' &&
          value is int &&
          value >= 0 &&
          value <= 1000000) {
        safe[entry.key] = value;
      }
    }
    _entries.add(
      DiagnosticEntry(DateTime.now().toUtc(), area, redact(message), safe),
    );
    if (_entries.length > 250) _entries.removeAt(0);
  }

  static String redact(String input) => input
      .replaceAllMapped(
        RegExp(
          r'("?\bAuthorization"?\s*[:=]\s*)((?:Bearer|Basic)\s+)?("[^"]*"|[^\s,&}]+)',
          caseSensitive: false,
        ),
        (match) => '${match[1]}${match[2] ?? ''}[REDACTED]',
      )
      .replaceAllMapped(
        RegExp(r'\b(Bearer|Basic)\s+\S+', caseSensitive: false),
        (match) => '${match[1]} [REDACTED]',
      )
      .replaceAllMapped(
        RegExp(
          r'("?(?:X-Plex-Token|authToken|token|password|pin)"?\s*[:=]\s*)("[^"]*"|[^\s,&}]+)',
          caseSensitive: false,
        ),
        (match) => '${match[1]}[REDACTED]',
      )
      .replaceAll(RegExp(r'https?://[^\s]+', caseSensitive: false), '[URL]')
      .replaceAll(RegExp(r'(?:/[\w .-]+){2,}'), '[PATH]')
      .replaceAll(
        RegExp(r'\b[A-Z]:\\[^\r\n]+', caseSensitive: false),
        '[PATH]',
      );

  static const _stringKeys = {
    'code',
    'failureCode',
    'mode',
    'container',
    'videoCodec',
    'audioCodec',
    'dynamicRange',
    'videoOutput',
    'hardwareDecoder',
  };
  static final _safeToken = RegExp(r'^[A-Za-z0-9._+-]{1,64}$');
}
