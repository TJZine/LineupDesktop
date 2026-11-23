import 'package:flutter/painting.dart';

final class TextMeasure<T> {
  const TextMeasure._(this._read);

  static final size = TextMeasure<Size>._((painter) => painter.size);
  static final exceedsMaxLines = TextMeasure<bool>._(
    (painter) => painter.didExceedMaxLines,
  );
  static final lineCount = TextMeasure<int>._(
    (painter) => painter.computeLineMetrics().length,
  );
  static final preferredLineHeight = TextMeasure<double>._(
    (painter) => painter.preferredLineHeight,
  );

  final T Function(TextPainter) _read;

  T call({
    required String text,
    required TextStyle? style,
    required TextDirection textDirection,
    required TextScaler textScaler,
    double maxWidth = double.infinity,
    int? maxLines,
    String? ellipsis,
    Locale? locale,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: maxLines,
      ellipsis: ellipsis,
      locale: locale,
    );
    try {
      painter.layout(maxWidth: maxWidth);
      return _read(painter);
    } finally {
      painter.dispose();
    }
  }
}
