import 'package:flutter/material.dart';

enum HandheldUnfitWord { ellipsis, lastResortBreak }

/// Fits individual words within the available line using the inherited scaler.
class HandheldWordText extends StatelessWidget {
  const HandheldWordText(
    this.text, {
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.maxWidth,
    this.breakAfter,
    this.unfitWord = HandheldUnfitWord.ellipsis,
    this.semanticsLabel,
    super.key,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final double? maxWidth;
  final Pattern? breakAfter;
  final HandheldUnfitWord unfitWord;
  final String? semanticsLabel;

  static final _words = RegExp(r'\S+');
  @override
  Widget build(BuildContext context) {
    final width = maxWidth;
    return width == null
        ? LayoutBuilder(
            builder: (context, constraints) =>
                _buildText(context, constraints.maxWidth),
          )
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: _buildText(context, width),
          );
  }

  Widget _buildText(BuildContext context, double width) {
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final floor = effectiveStyle.fontSize ?? 14;
    final requested = MediaQuery.textScalerOf(context).scale(floor);
    final scaledStyle = effectiveStyle.copyWith(fontSize: requested);
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      locale: Localizations.maybeLocaleOf(context),
    );

    double measure(String value, double size) {
      painter.text = TextSpan(
        text: value,
        style: effectiveStyle.copyWith(fontSize: size),
      );
      painter.layout();
      return painter.width;
    }

    TextSpan fit(String word) {
      var size = requested;
      var display = word;
      var measured = measure(word, requested);
      // Use the paragraph's own line breaker to detect words with a natural
      // break at punctuation or between ideographs.
      final hasInternalBreak =
          painter.minIntrinsicWidth + .01 < painter.maxIntrinsicWidth;
      String keepTogether(String value) =>
          hasInternalBreak ? value.characters.join('\u2060') : value;

      if (hasInternalBreak) {
        display = keepTogether(word);
        measured = measure(display, requested);
      }
      if (measured > width) {
        size = floor;
        if (requested <= floor || measure(display, floor) > width) {
          size = requested < floor ? requested : floor;
          if (unfitWord == HandheldUnfitWord.lastResortBreak) {
            display = word;
          } else {
            final characters = word.characters.toList();
            var low = 0;
            var high = characters.length;
            while (low < high) {
              final middle = (low + high + 1) ~/ 2;
              final candidate = keepTogether(
                '${characters.take(middle).join()}…',
              );
              if (measure(candidate, size) <= width) {
                low = middle;
              } else {
                high = middle - 1;
              }
            }
            display = measure('…', size) <= width
                ? keepTogether('${characters.take(low).join()}…')
                : '';
          }
        } else {
          var high = requested;
          for (var step = 0; step < 16; step++) {
            final middle = (size + high) / 2;
            if (measure(display, middle) <= width) {
              size = middle;
            } else {
              high = middle;
            }
          }
        }
      }
      return TextSpan(
        text: display,
        style: TextStyle(fontSize: size),
      );
    }

    final spans = <TextSpan>[];
    var end = 0;
    try {
      for (final match in _words.allMatches(text)) {
        if (match.start > end) {
          spans.add(TextSpan(text: text.substring(end, match.start)));
        }
        final word = match.group(0)!;
        var start = 0;
        for (final separator
            in breakAfter?.allMatches(word) ?? const <Match>[]) {
          if (separator.end <= start || separator.end == word.length) continue;
          spans
            ..add(fit(word.substring(start, separator.end)))
            ..add(const TextSpan(text: '\u200b'));
          start = separator.end;
        }
        spans.add(fit(word.substring(start)));
        end = match.end;
      }
      if (end < text.length) spans.add(TextSpan(text: text.substring(end)));
    } finally {
      painter.dispose();
    }
    return Semantics(
      label: semanticsLabel ?? text,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(children: spans),
        style: scaledStyle,
        textAlign: textAlign,
        textScaler: TextScaler.noScaling,
        softWrap: true,
        maxLines: maxLines,
        overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
      ),
    );
  }
}
