part of 'guide_view.dart';

class _HandheldProgramPoster extends StatefulWidget {
  const _HandheldProgramPoster({
    required this.controller,
    required this.program,
  });
  final GuideController controller;
  final GuideProgram program;

  @override
  State<_HandheldProgramPoster> createState() => _HandheldProgramPosterState();
}

class _HandheldProgramPosterState extends State<_HandheldProgramPoster> {
  Object? _identity;
  Future<Uint8List?>? _poster;

  @override
  Widget build(BuildContext context) {
    final item = widget.program.scheduled.item;
    final identity = (
      widget.controller,
      widget.controller.lineup.contentGeneration,
      item.id,
      posterPath(item),
    );
    if (_identity != identity) {
      _identity = identity;
      _poster = widget.controller.artworkFor(widget.program);
    }
    return _GuidePoster(key: ValueKey(identity), poster: _poster!);
  }
}

class _GuidePoster extends StatelessWidget {
  const _GuidePoster({required this.poster, super.key});
  final Future<Uint8List?> poster;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: FutureBuilder<Uint8List?>(
      future: poster,
      builder: (context, snapshot) => switch (snapshot.data) {
        final bytes? => Image.memory(
          bytes,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (context, _, _) => _fallback(context),
        ),
        null => _fallback(context),
      },
    ),
  );

  Widget _fallback(BuildContext context) =>
      ColoredBox(color: LineupTheme.of(context).elevatedSurface);
}

class _HandheldNowStrip extends StatefulWidget {
  const _HandheldNowStrip({
    required this.controller,
    required this.channel,
    required this.program,
    required this.onOpenPlayer,
  });

  final GuideController controller;
  final Channel? channel;
  final VoidCallback onOpenPlayer;
  final GuideProgram? program;

  @override
  State<_HandheldNowStrip> createState() => _HandheldNowStripState();
}

class _HandheldNowStripState extends State<_HandheldNowStrip> {
  Object? _posterIdentity;
  Object? _backdropIdentity;
  Future<Color?>? _color;
  Future<Uint8List?>? _backdrop;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final program = widget.program;
    final item = program?.scheduled.item;
    final settings = controller.lineup.settings;
    final mode = settings.guideInfoBackgroundMode;
    final roles = LineupTheme.of(context);
    final generation = controller.lineup.contentGeneration;
    final posterIdentity = (
      mode,
      controller,
      generation,
      item?.id,
      item == null ? null : posterPath(item),
    );
    if (_posterIdentity != posterIdentity) {
      _posterIdentity = posterIdentity;
      _color = program == null || mode != GuideInfoBackgroundMode.bleed
          ? null
          : controller
                .artworkFor(program)
                .then((bytes) => bytes == null ? null : _artworkColor(bytes));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final physicalRatio = LineupCanvas.physicalPixelRatioOf(context);
        final bucket = CoverResizeImage.bucket;
        final width =
            (constraints.maxWidth * physicalRatio / bucket).ceil() * bucket;
        final height = (180 * physicalRatio / bucket).ceil() * bucket;
        final identity = (
          controller,
          generation,
          mode,
          item?.id,
          item?.backdrop,
          width,
          height,
        );
        if (_backdropIdentity != identity) {
          _backdropIdentity = identity;
          _backdrop = program == null || mode != GuideInfoBackgroundMode.artwork
              ? null
              : controller.backdropFor(program, width: width, height: height);
        }
        final channel = widget.channel;
        final channelLabel = channel == null
            ? ''
            : '${channel.number} · ${channel.name}';
        final title = item?.showTitle ?? item?.title ?? 'Nothing playing';
        final compact = constraints.hasTightHeight;
        final strip = FutureBuilder<Color?>(
          future: _color,
          builder: (context, tint) {
            final fill = mode == GuideInfoBackgroundMode.bleed
                ? Color.alphaBlend(
                    (tint.data ?? roles.progressFill).withValues(alpha: .45),
                    roles.primarySurface,
                  )
                : roles.primarySurface;
            return AnimatedContainer(
              key: const Key('handheld-guide-now-strip'),
              color: fill,
              duration: settings.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 400),
              child: Stack(
                children: [
                  if (_backdrop != null)
                    Positioned.fill(
                      child: FutureBuilder<Uint8List?>(
                        future: _backdrop,
                        builder: (context, artwork) =>
                            artwork.connectionState != ConnectionState.done ||
                                artwork.data == null
                            ? const SizedBox.shrink()
                            : Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.memory(
                                    artwork.data!,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    excludeFromSemantics: true,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  ),
                                  ColoredBox(
                                    color: roles.deepBackground.withValues(
                                      alpha: .68,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  SingleChildScrollView(
                    physics: compact
                        ? null
                        : const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _GuideWordText(
                          channelLabel,
                          style: LineupTypography.small.copyWith(
                            color: roles.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _GuideWordText(
                          title,
                          style: LineupTypography.title(
                            24,
                            90,
                          ).copyWith(color: roles.primaryText),
                        ),
                        if (program != null) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            key: const Key('guide-program-progress'),
                            minHeight: 4,
                            value: _elapsedFraction(program, controller.now),
                            color: roles.progressFill,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
        return compact
            ? _HandheldGuideAction(
                label: '$channelLabel, $title. Open full player.',
                onTap: widget.onOpenPlayer,
                child: strip,
              )
            : strip;
      },
    );
  }
}

double _elapsedFraction(GuideProgram program, DateTime now) {
  final scheduled = program.scheduled;
  final elapsed = now.difference(scheduled.start).inMicroseconds;
  final duration = scheduled.end.difference(scheduled.start).inMicroseconds;
  return duration <= 0 ? 0 : (elapsed / duration).clamp(0.0, 1.0);
}

String _minutesLeft(Duration remaining) =>
    '${math.max(1, _guideMinutes(remaining).ceil())}m';

class _HandheldProgramSheet extends StatelessWidget {
  const _HandheldProgramSheet({
    required this.channel,
    required this.program,
    required this.now,
    required this.poster,
    required this.color,
    required this.onWatch,
  });

  final Channel channel;
  final GuideProgram program;
  final DateTime now;
  final Future<Uint8List?> poster;
  final Future<Color?> color;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final item = program.scheduled.item;
    final current = program.isCurrentAt(now);
    final start = _time(context, program.scheduled.start);
    final end = _time(context, program.scheduled.end);
    final duration = program.scheduled.end.difference(program.scheduled.start);
    final episode = [
      ?_episodeCode(item),
      if (item.showTitle != null) item.title,
    ].join(' · ');
    final badges = mediaBadges(item, surface: MediaBadgeSurface.guide);
    final secondary = LineupTypography.body.copyWith(
      color: roles.secondaryText,
    );
    void close() => Navigator.of(context).pop();
    final minimum = LineupCanvas.minimumTouchExtentOf(context);
    final buttonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size.square(math.max(56, minimum))),
      visualDensity: VisualDensity.standard,
    );
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: FutureBuilder<Color?>(
        future: color,
        builder: (context, tint) => DecoratedBox(
          key: const Key('handheld-program-sheet'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(
                  (tint.data ?? roles.elevatedSurface).withValues(alpha: .5),
                  roles.primarySurface,
                ),
                roles.primarySurface,
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: roles.defaultBorder,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 104,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: _GuidePoster(poster: poster),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _GuideWordText(
                              '${channel.number} · ${channel.name}',
                              style: LineupTypography.small.copyWith(
                                color: roles.secondaryText,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Semantics(
                              header: true,
                              child: _GuideWordText(
                                item.showTitle ?? item.title,
                                style: LineupTypography.title(
                                  30,
                                  90,
                                ).copyWith(color: roles.primaryText),
                              ),
                            ),
                            if (episode.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              _GuideWordText(episode, style: secondary),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              current
                                  ? '$start–$end · ${_minutesLeft(program.scheduled.end.difference(now))} left'
                                  : '$start–$end · ${duration.inMinutes} min',
                              style: secondary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final badge in badges)
                          _GuideMediaBadge(label: badge),
                      ],
                    ),
                  ],
                  if (item.summary?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 14),
                    _GuideWordText(
                      item.summary!,
                      maxLines: 6,
                      style: LineupTypography.body.copyWith(
                        height: 1.4,
                        color: roles.primaryText,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (program.scheduled.start.isAfter(now))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _GuideWordText(
                        'Airs at $start. Watching tunes channel ${channel.number} now.',
                        style: LineupTypography.body.copyWith(
                          fontSize: 15,
                          color: roles.mutedText,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('handheld-program-watch'),
                          style: buttonStyle,
                          onPressed: onWatch,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text('Watch channel ${channel.number}'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        style: buttonStyle,
                        onPressed: close,
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps line breaks between words. The requested scaler still determines
/// every normal word, including when Android supplies a nonlinear scaler.
class _GuideWordText extends StatelessWidget {
  const _GuideWordText(this.text, {required this.style, this.maxLines});

  final String text;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final requested = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      final words = text.trim().split(RegExp(r'\s+'));
      final size = style.fontSize!;
      final merged = DefaultTextStyle.of(context).style.merge(style);

      InlineSpan fit(String word) {
        double width(double candidate) {
          final painter = TextPainter(
            text: TextSpan(
              text: word,
              style: merged.copyWith(fontSize: candidate),
            ),
            textDirection: direction,
            textScaler: TextScaler.noScaling,
          )..layout();
          final measured = painter.width;
          painter.dispose();
          return measured;
        }

        final available = constraints.maxWidth;
        final scaled = requested.scale(size);
        if (width(scaled) <= available) return TextSpan(text: word);
        if (width(size) > available) {
          return WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Text(
              word,
              style: style,
              textScaler: TextScaler.noScaling,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }

        var low = size;
        var high = scaled;
        for (var step = 0; step < 12; step++) {
          final middle = (low + high) / 2;
          if (width(middle) <= available - 1) {
            low = middle;
          } else {
            high = middle;
          }
        }
        // Text.rich applies the original (possibly nonlinear) scaler after
        // layout. Convert the measured effective size back to its input.
        var lowerInput = 0.0;
        var upperInput = size;
        for (var step = 0; step < 14; step++) {
          final middle = (lowerInput + upperInput) / 2;
          if (requested.scale(middle) <= low) {
            lowerInput = middle;
          } else {
            upperInput = middle;
          }
        }
        return TextSpan(
          text: word,
          style: TextStyle(fontSize: upperInput),
        );
      }

      return Text.rich(
        TextSpan(
          children: [
            for (var index = 0; index < words.length; index++) ...[
              if (index > 0) const TextSpan(text: ' '),
              fit(words[index]),
            ],
          ],
        ),
        style: style,
        semanticsLabel: text,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      );
    },
  );
}
