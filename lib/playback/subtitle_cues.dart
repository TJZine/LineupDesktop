import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Ephemeral media content. Never include these values in diagnostics or logs.
@immutable
final class SubtitleSegment {
  const SubtitleSegment({
    required this.text,
    this.italic = false,
    this.bold = false,
    this.underline = false,
  });
  final String text;
  final bool italic;
  final bool bold;
  final bool underline;
}

@immutable
final class SubtitleCue {
  SubtitleCue({required this.align, required List<List<SubtitleSegment>> lines})
    : lines = List.unmodifiable(lines.map(List<SubtitleSegment>.unmodifiable));
  final int align;
  final List<List<SubtitleSegment>> lines;
}

@immutable
final class SubtitleCues {
  SubtitleCues(List<SubtitleCue> cues) : cues = List.unmodifiable(cues);
  const SubtitleCues.empty() : cues = const [];
  final List<SubtitleCue> cues;
  bool get isEmpty => cues.isEmpty;

  /// Reject an entire malformed value; bounds apply to UTF-8 bytes, not UTF-16.
  static SubtitleCues? tryParse(Object? value) {
    if (value is! List || value.length > 8) return null;
    var bytes = 0;
    final cues = <SubtitleCue>[];
    for (final item in value) {
      if (item is! Map) return null;
      final align = item['align'];
      final rawLines = item['lines'];
      if (align is! int ||
          align < 1 ||
          align > 9 ||
          rawLines is! List ||
          rawLines.length > 8) {
        return null;
      }
      final lines = <List<SubtitleSegment>>[];
      for (final rawLine in rawLines) {
        if (rawLine is! List || rawLine.length > 32) return null;
        final line = <SubtitleSegment>[];
        for (final raw in rawLine) {
          if (raw is! Map || raw['text'] is! String) return null;
          final text = raw['text'] as String;
          // Bound allocation before encoding potentially hostile input.
          if (text.length > 4096) return null;
          bytes += utf8.encode(text).length;
          if (bytes > 4096) return null;
          for (final flag in ['italic', 'bold', 'underline']) {
            if (raw.containsKey(flag) && raw[flag] is! bool) return null;
          }
          line.add(
            SubtitleSegment(
              text: text,
              italic: raw['italic'] == true,
              bold: raw['bold'] == true,
              underline: raw['underline'] == true,
            ),
          );
        }
        lines.add(line);
      }
      cues.add(SubtitleCue(align: align, lines: lines));
    }
    return SubtitleCues(cues);
  }
}
