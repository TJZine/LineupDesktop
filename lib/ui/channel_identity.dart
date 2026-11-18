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
    this.tickerBuilder,
    this.showNameTooltip = false,
    this.maxLines = 1,
    this.allowTagBelow = false,
    this.secondary,
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
  final Widget Function(TextStyle style)? tickerBuilder;
  final bool showNameTooltip;
  final int? maxLines;
  final bool allowTagBelow;
  final Widget? secondary;

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

  static double _textWidth(
    BuildContext context,
    String text,
    TextStyle style,
  ) => TextPainter.computeWidth(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  );

  double nameIndent(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final name = base.merge(nameStyle);
    final scaledSize = MediaQuery.textScalerOf(context)
        .scale(name.fontSize ?? 14);
    final hasIcon = channel.kind != ChannelKind.unknown;
    final number =
        numberWidth ??
        _textWidth(
          context,
          numberText ?? '${channel.number}',
          name.merge(numberStyle),
        );
    return number + scaledSize * (hasIcon ? .5 + .9 : .25);
  }

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
    final scaledSize = MediaQuery.textScalerOf(context)
        .scale(name.fontSize ?? 14);
    final gap = scaledSize * .25;
    final number = Text(
      numberText ?? '${channel.number}',
      textAlign: numberAlignment,
      style: name.merge(numberStyle),
      maxLines: 1,
      softWrap: false,
    );
    final tag = libraryTag == null ? null : '· $libraryTag';
    final identity = LayoutBuilder(
      builder: (context, constraints) {
        final prefix = nameIndent(context);
        final bounded = constraints.hasBoundedWidth;
        final labelRoom = math.max(0.0, constraints.maxWidth - prefix);
        final nameWidth = tickerBuilder != null || tag != null
            ? _textWidth(context, channel.name, name)
            : null;
        final tagWidth = tag == null ? 0.0 : _textWidth(context, tag, support);
        final besideTagRoom = labelRoom - tagWidth - gap;
        // Flutter can wrap an overwide word between letters, and a ticker can
        // scroll it offscreen. Keep the same static ellipsis in either case.
        final longestWord = bounded && (maxLines != 1 || tickerBuilder != null)
            ? channel.name.split(RegExp(r'\s+')).fold(0.0, (width, word) {
                return math.max(width, _textWidth(context, word, name));
              })
            : 0.0;
        final tagBelow =
            tag != null &&
            allowTagBelow &&
            nameWidth! > besideTagRoom &&
            (maxLines == 1 ||
                longestWord > labelRoom ||
                nameWidth <= labelRoom);
        final tagBeside =
            tag != null &&
            !tagBelow &&
            (nameWidth! <= besideTagRoom ||
                (!allowTagBelow &&
                    maxLines == 1 &&
                    besideTagRoom >= math.min(nameWidth, scaledSize * 2.5)));
        final overwide = longestWord > (tagBeside ? besideTagRoom : labelRoom);
        final lines = overwide ? 1 : maxLines;
        final ticker = overwide ? null : tickerBuilder;
        Widget title =
            ticker?.call(name) ??
            Text(
              channel.name,
              style: name,
              maxLines: lines,
              overflow: lines == null
                  ? TextOverflow.clip
                  : TextOverflow.ellipsis,
            );
        if (showNameTooltip) {
          title = Tooltip(
            message: channel.name,
            excludeFromSemantics: true,
            child: title,
          );
        }
        final label = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (numberWidth case final width?)
              SizedBox(width: width, child: number)
            else
              number,
            if (icon != null) ...[
              SizedBox(width: gap),
              Icon(icon, size: scaledSize * .9, color: support.color),
            ],
            SizedBox(width: gap),
            if (bounded)
              Flexible(
                child: ticker != null && nameWidth != null
                    ? ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: nameWidth),
                        child: title,
                      )
                    : title,
              )
            else
              title,
            if (tagBeside) ...[
              SizedBox(width: gap),
              Text(tag, style: support, maxLines: 1, softWrap: false),
            ],
          ],
        );
        final secondaryLine = secondary;
        final belowTag = tagBelow
            ? Text(
                secondaryLine == null ? libraryTag! : tag,
                style: support,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null;
        if (belowTag == null && secondaryLine == null) return label;
        // Let the library use the space beyond half the line when possible.
        // Leave room for a supporting icon and truncation mark.
        final sharedTagWidth = secondaryLine != null && belowTag != null
            ? math.min(
                tagWidth,
                math.max(
                  math.max(0.0, labelRoom - gap) / 2,
                  labelRoom -
                      2 * gap -
                      scaledSize -
                      _textWidth(context, '…', support),
                ),
              )
            : 0.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label,
            Padding(
              padding: EdgeInsetsDirectional.only(start: prefix),
              child: secondaryLine != null && belowTag != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: secondaryLine),
                        SizedBox(width: gap),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: sharedTagWidth),
                          child: belowTag,
                        ),
                      ],
                    )
                  : secondaryLine ?? belowTag!,
            ),
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
