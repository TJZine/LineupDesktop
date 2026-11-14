import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../channels/channel.dart';
import 'app_theme.dart';

class ChannelIdentity extends StatelessWidget {
  const ChannelIdentity({
    required this.channel,
    this.libraryTag,
    this.nameStyle,
    this.numberStyle,
    this.supportStyle,
    this.numberWidth,
    this.numberText,
    this.numberAlignment = TextAlign.start,
    this.nameBuilder,
    this.maxLines = 1,
    this.showSemantics = true,
    this.semanticsContainer = true,
    super.key,
  });

  final Channel channel;
  final String? libraryTag;
  final TextStyle? nameStyle;
  final TextStyle? numberStyle;
  final TextStyle? supportStyle;
  final double? numberWidth;
  final String? numberText;
  final TextAlign numberAlignment;
  final Widget Function(TextStyle style)? nameBuilder;
  final int maxLines;

  /// Rows which already own an interactive semantics node can include [label]
  /// on that node and exclude this widget's visuals.
  final bool showSemantics;
  final bool semanticsContainer;

  static String? libraryTagFor(Channel channel, Iterable<Channel> lineup) {
    final library = channel.libraryTitle;
    if (library == null) return null;
    return lineup.any(
          (other) =>
              other.id != channel.id &&
              other.name == channel.name &&
              other.libraryTitle != null &&
              other.libraryTitle != library,
        )
        ? library
        : null;
  }

  static String label(Channel channel, {String? libraryTag}) => [
    'Channel ${channel.number}',
    channel.name,
    switch (channel.kind) {
      ChannelKind.tv => 'TV',
      ChannelKind.film => 'Film',
      ChannelKind.both => 'TV and film',
      ChannelKind.unknown => null,
    },
    if (libraryTag != null) '$libraryTag library',
  ].nonNulls.join(', ');

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final name = base.merge(nameStyle);
    final support = base
        .merge(supportStyle)
        .copyWith(
          color: supportStyle?.color ?? LineupTheme.of(context).secondaryText,
        );
    final icon = switch (channel.kind) {
      ChannelKind.tv => Icons.tv_outlined,
      ChannelKind.film => Icons.movie_outlined,
      ChannelKind.both => Icons.video_library_outlined,
      ChannelKind.unknown => null,
    };
    final fontSize = name.fontSize ?? 14.0;
    final scaler = MediaQuery.textScalerOf(context);
    final gap = scaler.scale(fontSize) * .25;
    final number = Text(
      numberText ?? '${channel.number}',
      textAlign: numberAlignment,
      style: name.merge(numberStyle),
      maxLines: 1,
      softWrap: false,
    );
    final title =
        nameBuilder?.call(name) ??
        Text(
          channel.name,
          style: name,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        );
    final tag = libraryTag;
    final identity = LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedWidth;
        final supportSpan = TextSpan(
          text: tag == null ? null : '· $tag',
          style: support,
        );
        double textWidth(String value, TextStyle style) =>
            TextPainter.computeWidth(
              text: TextSpan(text: value, style: style),
              textDirection: Directionality.of(context),
              textScaler: scaler,
            );
        final iconWidth = icon == null ? 0.0 : scaler.scale(fontSize) * .9;
        final availableForLabel =
            constraints.maxWidth -
            (numberWidth ?? textWidth(number.data!, number.style!)) -
            textWidth('•', support) -
            (icon == null ? 2 : 3) * gap -
            iconWidth;
        final nameWidth = nameBuilder != null || tag != null
            ? textWidth(channel.name, name)
            : null;
        final tagWidth = tag == null
            ? 0.0
            : textWidth(supportSpan.text!, support);
        final labelRoom = math.max(0.0, availableForLabel);
        // Keep room for the name and put the overflow on the name alone.
        final showTag =
            tag != null &&
            (!bounded ||
                labelRoom - tagWidth - gap >=
                    math.min(nameWidth!, scaler.scale(fontSize) * 2.5));
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (numberWidth case final width?)
              SizedBox(width: width, child: number)
            else
              number,
            SizedBox(width: gap),
            Text('•', style: support, maxLines: 1),
            if (icon != null) ...[
              SizedBox(width: gap),
              Icon(icon, size: iconWidth, color: support.color),
            ],
            SizedBox(width: gap),
            if (bounded)
              Flexible(
                child: nameBuilder != null && nameWidth != null
                    ? ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: nameWidth),
                        child: title,
                      )
                    : title,
              )
            else
              title,
            if (showTag) ...[
              SizedBox(width: gap),
              Text(
                supportSpan.text!,
                style: support,
                maxLines: 1,
                softWrap: false,
              ),
            ],
          ],
        );
      },
    );
    return showSemantics
        ? Semantics(
            container: semanticsContainer,
            label: label(channel, libraryTag: libraryTag),
            excludeSemantics: true,
            child: identity,
          )
        : ExcludeSemantics(child: identity);
  }
}
