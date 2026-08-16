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
      if (_forbiddenKey.hasMatch(entry.key)) continue;
      final value = entry.value;
      if (value is String || value is num || value is bool) {
        final redacted = redact(value.toString());
        safe[entry.key.substring(0, entry.key.length.clamp(0, 64))] = redacted
            .substring(0, redacted.length.clamp(0, 500));
      }
    }
    _entries.add(
      DiagnosticEntry(DateTime.now().toUtc(), area, redact(message), safe),
    );
    if (_entries.length > 250) _entries.removeAt(0);
  }

  static String redact(String input) => input
      .replaceAll(
        RegExp(
          r'("?\bAuthorization"?\s*[:=]\s*)(?:Bearer|Basic)\s+\S+',
          caseSensitive: false,
        ),
        r'$1[REDACTED]',
      )
      .replaceAll(
        RegExp(r'\b(Bearer|Basic)\s+\S+', caseSensitive: false),
        r'$1 [REDACTED]',
      )
      .replaceAll(
        RegExp(
          r'("?(?:X-Plex-Token|Authorization|authToken|token|password|pin)"?\s*[:=]\s*)("[^"]*"|[^\s,&}]+)',
          caseSensitive: false,
        ),
        r'$1[REDACTED]',
      )
      .replaceAll(RegExp(r'https?://[^\s]+', caseSensitive: false), '[URL]')
      .replaceAll(RegExp(r'(?:/[\w .-]+){2,}'), '[PATH]')
      .replaceAll(
        RegExp(r'\b[A-Z]:\\[^\r\n]+', caseSensitive: false),
        '[PATH]',
      );

  static final _forbiddenKey = RegExp(
    r'(token|auth|header|credential|secret|pin|password|url|uri|path|stack|handle)',
    caseSensitive: false,
  );
}
