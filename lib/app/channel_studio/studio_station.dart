part of '../channel_studio_view.dart';

class _StudioStation extends StatefulWidget {
  const _StudioStation({
    required this.draft,
    required this.name,
    required this.number,
    required this.saving,
    required this.busy,
    required this.hasShowGrouping,
    required this.confirmedMovieOnly,
    required this.hasNumberConflict,
    required this.hasFreeNumber,
    required this.sourceSummary,
    required this.validateNumber,
    required this.onChanged,
    required this.onUseNext,
    super.key,
  });
  final ChannelStudioDraft draft;
  final TextEditingController name;
  final TextEditingController number;
  final bool saving;
  final bool busy;
  final bool hasShowGrouping;
  final bool confirmedMovieOnly;
  final bool hasNumberConflict;
  final bool hasFreeNumber;
  final String sourceSummary;
  final String? Function(String?) validateNumber;
  final VoidCallback onChanged;
  final VoidCallback onUseNext;
  @override
  State<_StudioStation> createState() => _StudioStationState();
}

class _StudioStationState extends State<_StudioStation> {
  final _nameFocus = FocusNode(debugLabel: 'Channel name');
  final _numberFocus = FocusNode(debugLabel: 'Channel number');
  ChannelStudioDraft get _session => widget.draft;
  TextEditingController get _name => widget.name;
  TextEditingController get _number => widget.number;
  bool get _saving => widget.saving;
  bool get _busy => widget.busy;
  void _changed([VoidCallback? change]) {
    change?.call();
    widget.onChanged();
  }

  String? _validateNumber(String? value) => widget.validateNumber(value);
  void focusIdentity({required bool name}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusStudioNode(context, name ? _nameFocus : _numberFocus);
    });
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _numberFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasShowGrouping = widget.hasShowGrouping;
    final confirmedMovieOnly = widget.confirmedMovieOnly;
    final roles = LineupTheme.of(context);
    return Container(
      key: const Key('studio-station'),
      padding: EdgeInsets.only(top: 8, bottom: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: roles.subtleBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final double numberWidth = 120 * (textScale > 1 ? textScale : 1);
              final identity = Row(
                children: [
                  Expanded(
                    child: LineupField(
                      label: 'Channel name',
                      child: TextFormField(
                        key: const Key('studio-name'),
                        controller: _name,
                        focusNode: _nameFocus,
                        enabled: !_saving,
                        style: _studioBodyStyle(context),
                        decoration: const InputDecoration(hintText: 'Required'),
                        onChanged: (_) => _changed(),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a channel name.'
                            : null,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  SizedBox(
                    width: numberWidth,
                    child: LineupField(
                      label: 'Number',
                      child: TextFormField(
                        key: const Key('studio-number'),
                        controller: _number,
                        focusNode: _numberFocus,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        style: _studioBodyStyle(context),
                        decoration: const InputDecoration(),
                        onChanged: (_) => _changed(),
                        validator: _validateNumber,
                      ),
                    ),
                  ),
                ],
              );
              final playback = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_session.generated) ...[
                    Text(
                      'Playback order · Read-only',
                      style: _studioSupportStyle(context),
                    ),
                    SizedBox(height: 12),
                    Text(
                      _rhythmLabel(_session.playbackMode, _session.blockSize),
                      style: _studioBodyStyle(context),
                    ),
                  ] else
                    _playbackEditor(confirmedMovieOnly),
                ],
              );
              if (constraints.maxWidth < 760) {
                return Column(
                  children: [identity, SizedBox(height: 12), playback],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 9, child: identity),
                  SizedBox(width: 24),
                  Expanded(flex: 11, child: playback),
                ],
              );
            },
          ),
          if (widget.hasNumberConflict)
            Align(
              alignment: Alignment.centerLeft,
              child: LineupInlineLink(
                onPressed: _saving || !widget.hasFreeNumber
                    ? null
                    : widget.onUseNext,
                child: const Text('Use next available'),
              ),
            ),
          if (!_session.generated &&
              confirmedMovieOnly &&
              _session.playbackMode != PlaybackMode.block)
            Focus(
              child: Semantics(
                key: const Key('studio-mini-marathon-explanation'),
                focusable: true,
                child: const Text(
                  'Mini-marathons is available when this source includes episodes with series information.',
                ),
              ),
            ),
          if (_session.generated) ...[
            SizedBox(height: 12),
            Text(
              'Generator recipe: ${widget.sourceSummary}. Schedule timing stays the same.',
            ),
          ] else if (_session.playbackMode == PlaybackMode.block) ...[
            if (!hasShowGrouping) SizedBox(height: 12),
            if (!hasShowGrouping)
              Focus(
                child: Semantics(
                  key: const Key('studio-mini-marathon-explanation'),
                  focusable: true,
                  child: const Text(
                    'Mini-marathons needs episodes grouped by show title or show artwork. Choose another rhythm or add grouped episodes.',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _playbackEditor(bool confirmedMovieOnly) => LayoutBuilder(
    builder: (context, constraints) {
      final block = _session.playbackMode == PlaybackMode.block;
      final inline =
          block &&
          constraints.maxWidth >= 740 &&
          MediaQuery.textScalerOf(context).scale(14) <= 21;
      return Wrap(
        spacing: 12,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: inline ? constraints.maxWidth - 474 : constraints.maxWidth,
            child: LineupField(
              label: 'Playback order',
              child: lineupDropdownField<PlaybackMode>(
                context: context,
                key: const Key('studio-playback-order'),
                initialValue: _session.playbackMode,
                isExpanded: true,
                iconSize: 24,
                itemHeight: null,
                decoration: const InputDecoration(),
                items: [
                  const DropdownMenuItem(
                    value: PlaybackMode.shuffle,
                    child: Text('Shuffle'),
                  ),
                  const DropdownMenuItem(
                    value: PlaybackMode.sequential,
                    child: Text('In order'),
                  ),
                  DropdownMenuItem(
                    value: PlaybackMode.block,
                    enabled:
                        !confirmedMovieOnly ||
                        _session.playbackMode == PlaybackMode.block,
                    child: const Text('Mini-marathons'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value == null) return;
                        _changed(() {
                          _session.playbackMode = value;
                          _session.blockSize ??= 3;
                        });
                      },
              ),
            ),
          ),
          if (block) ...[
            SizedBox(
              width: inline ? 220 : constraints.maxWidth,
              child: LineupField(
                label: 'Episodes per block',
                child: lineupDropdownField<int>(
                  context: context,
                  key: const Key('studio-block-size'),
                  isExpanded: true,
                  iconSize: 24,
                  itemHeight: null,
                  initialValue:
                      (_session.blockSize ?? 3) >= 2 &&
                          (_session.blockSize ?? 3) <= 5
                      ? _session.blockSize ?? 3
                      : null,
                  decoration: const InputDecoration(),
                  items: [
                    for (var size = 2; size <= 5; size++)
                      DropdownMenuItem(value: size, child: Text('$size')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => _changed(() => _session.blockSize = value),
                ),
              ),
            ),
            SizedBox(
              width: inline ? 230 : constraints.maxWidth,
              child: SwitchListTile(
                key: const Key('studio-include-specials'),
                contentPadding: EdgeInsets.zero,
                value: _session.includeSpecials,
                title: const Text('Include specials'),
                onChanged: _saving
                    ? null
                    : (value) =>
                          _changed(() => _session.includeSpecials = value),
              ),
            ),
            if (_session.includeSpecials)
              const Text('Season 0 specials play after regular seasons.'),
          ],
        ],
      );
    },
  );
}
