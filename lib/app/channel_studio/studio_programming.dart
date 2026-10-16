part of '../channel_studio_view.dart';

class _StudioProgramming extends StatefulWidget {
  const _StudioProgramming({
    required this.draft,
    required this.inventory,
    required this.readInventory,
    required this.selectedLibraries,
    required this.libraries,
    required this.channels,
    required this.name,
    required this.sourceLabel,
    required this.sourceExplanation,
    required this.programmingError,
    required this.inventoryStatus,
    required this.saving,
    required this.sourceRevision,
    required this.onChanged,
    required this.onPendingChanged,
    required this.onOpenChannel,
    super.key,
  });
  final ChannelStudioDraft draft;
  final _StudioInventory inventory;
  final _StudioInventory Function() readInventory;
  final List<PlexLibrary> selectedLibraries;
  final List<PlexLibrary> libraries;
  final List<Channel> channels;
  final String name;
  final String sourceLabel;
  final String? sourceExplanation;
  final String? programmingError;
  final Widget inventoryStatus;
  final bool saving;
  final int sourceRevision;
  final VoidCallback onChanged;
  final ValueChanged<_StudioPendingChoice?> onPendingChanged;
  final Future<void> Function(Channel)? onOpenChannel;
  @override
  State<_StudioProgramming> createState() => _StudioProgrammingState();
}

class _StudioProgrammingState extends State<_StudioProgramming> {
  late final _FilterPickerController _picker;
  BuildContext? _programmingContext;
  double _pickerMinimumHeight = 0;
  bool _selectionPending = false;
  ChannelStudioDraft get _session => widget.draft;
  bool get _saving => widget.saving;

  @override
  void initState() {
    super.initState();
    _picker = _FilterPickerController(onOpening: _retainProgrammingHeight);
    _picker.addListener(_pickerChanged);
  }

  @override
  void didUpdateWidget(_StudioProgramming oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceRevision != widget.sourceRevision) {
      _picker.close(notify: false);
      _selectionPending = false;
    }
  }

  void _retainProgrammingHeight() {
    final box = _programmingContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) _pickerMinimumHeight = box.size.height;
  }

  void _pickerChanged() {
    setState(() {});
    _publishPending();
  }

  void _selectionChanged(bool value) {
    _selectionPending = value;
    _publishPending();
  }

  void _publishPending() => widget.onPendingChanged(
    _picker.activeKey != null
        ? _StudioPendingChoice.filter
        : _selectionPending
        ? _StudioPendingChoice.selection
        : null,
  );
  void _selectSource(StudioSourceChoice? choice) {
    if (choice == _session.sourceChoice) return;
    _picker.close(notify: false);
    _selectionPending = false;
    _session.sourceChoice = choice;
    _publishPending();
    widget.onChanged();
  }

  @override
  void dispose() {
    _picker.removeListener(_pickerChanged);
    _picker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) {
      _programmingContext = context;
      return ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: _picker.activeKey == null ? 0 : _pickerMinimumHeight,
        ),
        child: _programmingCard(),
      );
    },
  );
  Widget _programmingCard() {
    final roles = LineupTheme.of(context);
    final libraryActive =
        _session.sourceChoice == StudioSourceChoice.library ||
        _session.sourceChoice == StudioSourceChoice.filter;
    final manualActive = _session.sourceChoice == StudioSourceChoice.handPicked;
    return DefaultTextStyle.merge(
      style: _studioBodyStyle(context),
      child: Column(
        key: const Key('studio-programming'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 16,
            runSpacing: 4,
            children: [
              Text('Programming', style: _studioSectionHeadingStyle(context)),
              Text(
                widget.sourceLabel,
                style: _studioSupportStyle(context, color: roles.secondaryText),
              ),
            ],
          ),
          SizedBox(height: 16),
          if (_session.sourceReadOnly) ...[
            const Text(
              'Programming is read-only and will be preserved exactly.',
            ),
            _studioSourceExplanation(context, widget.sourceExplanation),
          ] else ...[
            if (_session.source is MixedSource &&
                _session.sourceChoice == null) ...[
              widget.inventoryStatus,
              const Text(
                'This mixed source is preserved exactly. Choose a source below only if you want to replace it.',
              ),
              SizedBox(height: 8),
            ],
            LayoutBuilder(
              builder: (context, constraints) =>
                  LineupSegmentedControl<StudioSourceChoice>(
                    key: const Key('studio-source-choices'),
                    expanded: true,
                    direction:
                        MediaQuery.textScalerOf(context).scale(14) > 21 ||
                            constraints.maxWidth < 480
                        ? Axis.vertical
                        : Axis.horizontal,
                    multiSelectionEnabled: false,
                    emptySelectionAllowed: _session.source is MixedSource,
                    segments: const [
                      ButtonSegment(
                        value: StudioSourceChoice.library,
                        label: Text('Library'),
                      ),
                      ButtonSegment(
                        value: StudioSourceChoice.playlist,
                        label: Text('Plex playlist'),
                      ),
                      ButtonSegment(
                        value: StudioSourceChoice.handPicked,
                        label: Text('Hand-picked'),
                      ),
                    ],
                    selected: {?_session.sourceChoice},
                    showSelectedIcon: false,
                    onSelectionChanged: _saving
                        ? null
                        : (value) => _selectSource(value.singleOrNull),
                  ),
            ),
            SizedBox(height: 8),
            // Retain completed searches and browser filters across source switches.
            // Inactive editors retain State without building inventory-derived controls.
            Offstage(
              offstage: !libraryActive,
              child: ExcludeFocus(
                excluding: !libraryActive,
                child: _StudioFilterEditor(
                  draft: _session,
                  active: libraryActive,
                  inventory: widget.inventory,
                  selectedLibraries: widget.selectedLibraries,
                  libraries: widget.libraries,
                  picker: _picker,
                  saving: _saving,
                  inventoryStatus: widget.inventoryStatus,
                  sourceExplanation: widget.sourceExplanation,
                  programmingError: widget.programmingError,
                  onChanged: widget.onChanged,
                ),
              ),
            ),
            if (_session.sourceChoice == StudioSourceChoice.playlist)
              _StudioPlaylist(
                playlists: widget.inventory.playlists,
                selectedId: _session.playlistId,
                otherUses: widget.channels.where(
                  (channel) =>
                      channel.id != _session.id &&
                      channel.source is PlaylistSource &&
                      (channel.source as PlaylistSource).playlistId ==
                          _session.playlistId,
                ),
                saving: _saving,
                inventoryStatus: widget.inventoryStatus,
                sourceExplanation: widget.sourceExplanation,
                onChanged: (value) {
                  _session.playlistId = value;
                  widget.onChanged();
                },
                onOpenChannel: widget.onOpenChannel,
              ),
            Offstage(
              offstage: !manualActive,
              child: ExcludeFocus(
                excluding: !manualActive,
                child: _StudioManualEditor(
                  rundown: _session.rundown,
                  inventory: widget.inventory,
                  readInventory: widget.readInventory,
                  selectedLibraries: widget.selectedLibraries,
                  libraries: widget.libraries,
                  picker: _picker,
                  saving: _saving,
                  active: manualActive,
                  sourceRevision: widget.sourceRevision,
                  name: widget.name,
                  inventoryStatus: widget.inventoryStatus,
                  sourceExplanation: widget.sourceExplanation,
                  onChanged: widget.onChanged,
                  onSelectionPendingChanged: _selectionChanged,
                ),
              ),
            ),
            if (_session.sourceChoice == null)
              _studioSourceExplanation(context, widget.sourceExplanation),
          ],
        ],
      ),
    );
  }
}
