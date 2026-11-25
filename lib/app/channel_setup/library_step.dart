import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:lineup_desktop/platform/device_profile.dart';

import '../../channels/channel.dart';
import '../../plex/plex_models.dart';
import '../../ui/app_theme.dart';
import '../../ui/app_ui.dart';
import '../lineup_controller.dart' show LibraryScanFact, LibraryScanStatus;
import '../lineup_restore_view.dart';
import 'step_scaffold.dart';

typedef SetupScanIntent = Future<void> Function({
  bool retryFailedOnly,
  Set<String>? retryLibraryIds,
  bool advanceWhenReady,
});

/// One render's library/scan facts. Commands remain in the setup flow.
class SetupLibraryData {
  SetupLibraryData({
    required List<PlexLibrary> libraries,
    required Map<String, LibraryScanFact> libraryScanFacts,
    required Set<String> libraryScanReadyIds,
    required Set<String> libraryScanRetryIds,
    required Set<String> libraryScanCommittableIds,
    required Set<String> unavailableCollectionLibraryIds,
    required Set<String> failedPlaylistIds,
    required this.libraryScanStatus,
    required this.playlistCatalogUnavailable,
    required this.busy,
    required this.canSwitchServer,
    required this.channelSetupCanCancel,
    required this.error,
    required this.profileCredentialRecoveryNotice,
    required Map<String, String> collectionRecoveryByLibrary,
    required this.selectionCollectionRecovery,
    required this.progress,
  }) : libraries = List.unmodifiable(libraries),
       libraryScanFacts = Map.unmodifiable(libraryScanFacts),
       libraryScanReadyIds = Set.unmodifiable(libraryScanReadyIds),
       libraryScanRetryIds = Set.unmodifiable(libraryScanRetryIds),
       libraryScanCommittableIds = Set.unmodifiable(libraryScanCommittableIds),
       unavailableCollectionLibraryIds = Set.unmodifiable(
         unavailableCollectionLibraryIds,
       ),
       failedPlaylistIds = Set.unmodifiable(failedPlaylistIds),
       collectionRecoveryByLibrary = Map.unmodifiable(
         collectionRecoveryByLibrary,
       );

  final List<PlexLibrary> libraries;
  final Map<String, LibraryScanFact> libraryScanFacts;
  final Set<String> libraryScanReadyIds;
  final Set<String> libraryScanRetryIds;
  final Set<String> libraryScanCommittableIds;
  final Set<String> unavailableCollectionLibraryIds;
  final Set<String> failedPlaylistIds;
  final LibraryScanStatus libraryScanStatus;
  final bool playlistCatalogUnavailable;
  final bool busy;
  final bool canSwitchServer;
  final bool channelSetupCanCancel;
  final String? error;
  final String? profileCredentialRecoveryNotice;
  final Map<String, String> collectionRecoveryByLibrary;
  final String? selectionCollectionRecovery;
  final LibraryScanProgress progress;
}

class SetupLibraryStep extends StatelessWidget {
  const SetupLibraryStep({
    required this.data,
    required this.onSwitchServer,
    required this.onCancelSetup,
    required this.onCancelScan,
    required this.selectedLibraryIds,
    required this.error,
    required this.onScan,
    required this.onCommit,
    required this.onToggleLibrary,
    required this.onToggleAll,
    this.entryFocusNode,
    this.onRequestLogout,
    super.key,
  });

  final SetupLibraryData data;
  final VoidCallback onSwitchServer;
  final VoidCallback onCancelSetup;
  final VoidCallback onCancelScan;
  final Set<String> selectedLibraryIds;
  final String? error;
  final SetupScanIntent onScan;
  final Future<void> Function(Set<String> ready) onCommit;
  final ValueChanged<String> onToggleLibrary;
  final ValueChanged<Set<String>> onToggleAll;
  final FocusNode? entryFocusNode;
  final Future<void> Function()? onRequestLogout;

  bool get _settled => switch (data.libraryScanStatus) {
    LibraryScanStatus.complete ||
    LibraryScanStatus.empty ||
    LibraryScanStatus.unsupported ||
    LibraryScanStatus.transientFailure => true,
    _ => false,
  };

  bool _unusable(String id) => switch (data.libraryScanFacts[id]?.status) {
    LibraryScanStatus.empty ||
    LibraryScanStatus.unsupported ||
    LibraryScanStatus.transientFailure => true,
    LibraryScanStatus.complete => !data.libraryScanCommittableIds.contains(id),
    _ => false,
  };

  String _summary(Set<String> usableIds) {
    final statuses = [
      for (final id in selectedLibraryIds)
        data.libraryScanFacts[id]?.status ?? LibraryScanStatus.idle,
    ];
    int count(LibraryScanStatus status) =>
        statuses.where((value) => value == status).length;
    if (data.libraryScanStatus == LibraryScanStatus.scanning) {
      final checked = statuses
          .where(
            (status) => const {
              LibraryScanStatus.complete,
              LibraryScanStatus.empty,
              LibraryScanStatus.unsupported,
              LibraryScanStatus.transientFailure,
            }.contains(status),
          )
          .length;
      return '$checked of ${statuses.length} libraries checked';
    }
    if (data.libraryScanStatus == LibraryScanStatus.cancelled) {
      return 'Your selections are preserved. Scan again when you’re ready.';
    }
    if (!_settled ||
        statuses.isEmpty ||
        (usableIds.isNotEmpty && !selectedLibraryIds.any(usableIds.contains))) {
      return 'Choose the libraries to build channels from.';
    }
    final ready = data.libraryScanCommittableIds
        .intersection(selectedLibraryIds)
        .length;
    if (ready == 0) {
      if (data.selectionCollectionRecovery != null) {
        return 'No libraries are ready. Change the collection inventory in Plex before rescanning, or change your selection.';
      }
      return data.libraryScanRetryIds
              .intersection(selectedLibraryIds)
              .isNotEmpty
          ? 'No libraries are ready. Retry failed scans or change your selection.'
          : 'No libraries are ready. Change your selection or scan again.';
    }
    return [
      '$ready ${ready == 1 ? 'library' : 'libraries'} ready',
      if (count(LibraryScanStatus.empty) > 0)
        '${count(LibraryScanStatus.empty)} empty',
      if (count(LibraryScanStatus.unsupported) > 0)
        '${count(LibraryScanStatus.unsupported)} with no playable media',
      if (count(LibraryScanStatus.transientFailure) > 0)
        '${count(LibraryScanStatus.transientFailure)} failed',
      if (count(LibraryScanStatus.idle) > 0)
        '${count(LibraryScanStatus.idle)} not scanned',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final ready = data.libraryScanCommittableIds.intersection(
      selectedLibraryIds,
    );
    final retry = data.libraryScanRetryIds.intersection(selectedLibraryIds);
    final hasLibraries = data.libraries.isNotEmpty;
    final scanning = data.libraryScanStatus == LibraryScanStatus.scanning;
    final canContinue = hasLibraries && !scanning && ready.isNotEmpty;
    final canRetry =
        !scanning &&
        data.libraryScanStatus != LibraryScanStatus.cancelled &&
        (retry.isNotEmpty ||
            data.error != null ||
            (_settled &&
                (data.playlistCatalogUnavailable ||
                    data.failedPlaylistIds.isNotEmpty)));
    final roles = LineupTheme.of(context);
    final bodyStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: roles.secondaryText, fontSize: 18, height: 1.4);
    final actionStyle = Theme.of(context).textTheme.labelLarge!.copyWith(
      fontSize: DeviceProfile.of(context).isTv
          ? LineupTypography.tvTextFloor
          : 18,
    );
    Widget actionLabel(String label) => Builder(
      builder: (context) => Text(
        label,
        style: DeviceProfile.of(context).isTv
            ? actionStyle.copyWith(color: LineupTheme.of(context).primaryText)
            : actionStyle,
      ),
    );
    final retryLabel = data.selectionCollectionRecovery != null
        ? 'Rescan after Plex changes'
        : retry.isEmpty
        ? 'Retry scan'
        : 'Retry failed scans';
    final scanError = error ?? data.error;
    final excluded = selectedLibraryIds.length - ready.length;
    final footer = SetupFooter(
      configuration: true,
      leading: const [],
      summary: Wrap(
        spacing: 8,
        children: [
          if (hasLibraries)
            TextButton(
              key: const ValueKey('setup-switch-server'),
              style: TextButton.styleFrom(
                padding: DeviceProfile.of(context).isTv
                    ? const EdgeInsets.symmetric(horizontal: 20)
                    : EdgeInsets.zero,
                minimumSize: const Size(0, 48),
                alignment: Alignment.centerLeft,
              ),
              onPressed: data.canSwitchServer ? onSwitchServer : null,
              child: actionLabel('Switch server'),
            ),
          if (!scanning && data.channelSetupCanCancel)
            TextButton(
              style: DeviceProfile.of(context).isTv
                  ? TextButton.styleFrom(minimumSize: const Size(0, 48))
                  : null,
              onPressed: onCancelSetup,
              child: actionLabel('Cancel'),
            ),
          if (hasLibraries &&
              !scanning &&
              data.libraryScanReadyIds
                  .intersection(selectedLibraryIds)
                  .isNotEmpty)
            TextButton(
              key: const ValueKey('scan-again-libraries'),
              onPressed: data.busy
                  ? null
                  : () => onScan(advanceWhenReady: false),
              child: actionLabel('Scan again'),
            ),
        ],
      ),
      trailing: !hasLibraries
          ? Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (onRequestLogout != null)
                  TextButton(
                    onPressed: data.busy ? null : onRequestLogout,
                    child: Text(
                      'Sign out',
                      style: LineupTypography.tvLabelStyle(context),
                    ),
                  ),
                FilledButton(
                  key: const ValueKey('setup-switch-server'),
                  focusNode:
                      DeviceProfile.of(context).isTv &&
                          !data.busy &&
                          data.canSwitchServer
                      ? entryFocusNode
                      : null,
                  autofocus:
                      DeviceProfile.of(context).isTv &&
                      !data.busy &&
                      data.canSwitchServer,
                  onPressed: data.canSwitchServer ? onSwitchServer : null,
                  child: Text(
                    'Switch server',
                    style: LineupTypography.tvLabelStyle(context),
                  ),
                ),
              ],
            )
          : scanning
          ? TextButton(
              autofocus: DeviceProfile.of(context).isTv,
              onPressed: onCancelScan,
              child: actionLabel('Cancel scan'),
            )
          : canContinue
          ? FilledButton(
              key: const ValueKey('continue-ready-libraries'),
              focusNode: DeviceProfile.of(context).isTv ? entryFocusNode : null,
              autofocus: DeviceProfile.of(context).isTv,
              onPressed: data.busy ? null : () => onCommit(ready),
              child: Text(
                'Continue with ${ready.length} ${ready.length == 1 ? 'library' : 'libraries'}',
                style: LineupTypography.tvLabelStyle(context),
              ),
            )
          : canRetry
          ? FilledButton(
              key: const ValueKey('retry-failed-libraries'),
              focusNode: DeviceProfile.of(context).isTv ? entryFocusNode : null,
              autofocus: DeviceProfile.of(context).isTv,
              onPressed: selectedLibraryIds.isEmpty || data.busy
                  ? null
                  : () => onScan(retryFailedOnly: true),
              child: Text(
                retryLabel,
                style: LineupTypography.tvLabelStyle(context),
              ),
            )
          : FilledButton(
              key: const ValueKey('scan-selected-libraries'),
              focusNode:
                  DeviceProfile.of(context).isTv &&
                      (_settled ||
                          data.libraryScanStatus == LibraryScanStatus.cancelled)
                  ? entryFocusNode
                  : null,
              autofocus:
                  DeviceProfile.of(context).isTv &&
                  (_settled ||
                      data.libraryScanStatus == LibraryScanStatus.cancelled),
              onPressed: selectedLibraryIds.isEmpty || data.busy
                  ? null
                  : onScan,
              child: Text(
                _settled ? 'Scan again' : 'Scan selected libraries',
                style: LineupTypography.tvLabelStyle(context),
              ),
            ),
    );
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final singleScroll =
            DeviceProfile.of(context).isTv ||
            constraints.maxHeight < 800 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.5;
        final list = ListView.separated(
          key: const ValueKey('library-selection-list'),
          shrinkWrap: true,
          physics: singleScroll ? const NeverScrollableScrollPhysics() : null,
          itemCount: data.libraries.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) =>
              _libraryRow(context, data.libraries[index], index),
        );
        final usableIds = {
          for (final library in data.libraries)
            if (!_unusable(library.id)) library.id,
        };
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(
              context,
              'Choose libraries',
              usableIds.length < data.libraries.length &&
                      !scanning &&
                      data.libraryScanStatus != LibraryScanStatus.cancelled
                  ? '${data.libraryScanCommittableIds.length} of ${data.libraries.length} libraries can be used. The others are left out; you can scan again at any time.'
                  : data.libraries.isEmpty || _settled || scanning
                  ? ''
                  : _summary(usableIds),
            ),
            if (scanning) ...[
              const SizedBox(height: 10),
              LibraryScanPhaseStatus(progress: data.progress, centered: false),
            ],
            const SizedBox(height: 32),
            if (data.libraries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: LineupEmptyState(
                  icon: Icons.video_library_outlined,
                  title: 'No movie or show libraries found',
                  message:
                      'Choose another Plex server with accessible libraries.',
                ),
              )
            else ...[
              _selectionSummary(context, usableIds),
              if (singleScroll)
                list
              else
                Flexible(fit: FlexFit.loose, child: list),
            ],
            if (!scanning && ((_settled && hasLibraries) || scanError != null))
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    scanError != null && (retry.isEmpty || error != null)
                        ? [
                            scanError,
                            ?data.profileCredentialRecoveryNotice,
                          ].join('\n')
                        : ready.isEmpty
                        ? _summary(usableIds)
                        : '${ready.length} of ${selectedLibraryIds.length} ${selectedLibraryIds.length == 1 ? 'library' : 'libraries'} ${ready.length == 1 ? 'is' : 'are'} ready. Continuing builds from ${data.libraries.where((library) => ready.contains(library.id)).map((library) => library.title).join(', ')}${excluded > 0 ? ' only' : ''}.',
                    style: bodyStyle,
                  ),
                ),
              ),
            if (!DeviceProfile.of(context).isTv) ...[
              const SizedBox(height: 24),
              footer,
            ],
          ],
        );
        if (DeviceProfile.of(context).isTv) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: SetupStage(
                footer: footer,
                child: SingleChildScrollView(
                  key: const ValueKey('channel-setup-single-scroll'),
                  child: content,
                ),
              ),
            ),
          );
        }
        return Align(
          alignment: singleScroll ? Alignment.topCenter : Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(constraints.maxWidth, 1040),
            ),
            child: singleScroll
                ? SingleChildScrollView(
                    key: const ValueKey('channel-setup-single-scroll'),
                    child: content,
                  )
                : content,
          ),
        );
      },
    );
    return DeviceProfile.of(context).isTv
        ? FocusTraversalGroup(
            policy: SetupVerticalTraversalPolicy(),
            child: body,
          )
        : body;
  }

  Widget _header(BuildContext context, String title, String subtitle) => Column(
    key: const ValueKey('channel-setup-header'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(
          title,
          style: LineupTypography.pageTitle.copyWith(
            color: LineupTheme.of(context).primaryText,
          ),
        ),
      ),
      if (subtitle != '') ...[
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: LineupTypography.body.copyWith(
            height: 1.4,
            color: LineupTheme.of(context).secondaryText,
          ),
        ),
      ],
    ],
  );

  Widget _selectionSummary(BuildContext context, Set<String> usableIds) {
    final roles = LineupTheme.of(context);
    final summaryStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: roles.secondaryText, fontSize: 16, height: 1.4);
    final editable =
        !data.busy && data.libraryScanStatus != LibraryScanStatus.scanning;
    final selected = usableIds.intersection(selectedLibraryIds).length;
    final all = usableIds.isNotEmpty && selected == usableIds.length;
    void toggleAll() => onToggleAll(usableIds);
    final value = all
        ? true
        : selected == 0
        ? false
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 8, 16),
      child: Row(
        children: [
          if (usableIds.length > 1)
            FocusTraversalOrder(
              order: const NumericFocusOrder(0),
              // One focus target covers the checkbox and its label, matching
              // the library rows. The button carries the tri-state semantics.
              child: MergeSemantics(
                child: Semantics(
                  checked: value ?? false,
                  mixed: value == null,
                  child: TextButton(
                    style: const ButtonStyle(
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                    onPressed: editable ? toggleAll : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _checkbox(
                          key: const ValueKey('select-all-libraries'),
                          skipTraversal: true,
                          tristate: true,
                          value: value,
                          onChanged: editable ? (_) => toggleAll() : null,
                        ),
                        const SizedBox(width: 8),
                        Builder(
                          builder: (context) {
                            final ink = LineupTheme.of(context);
                            return Text(
                              'Select all',
                              style: summaryStyle.copyWith(
                                fontSize: 16,
                                color: editable
                                    ? ink.secondaryText
                                    : ink.mutedText,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          Text(
            '$selected of ${usableIds.length} selected',
            style: summaryStyle,
          ),
        ],
      ),
    );
  }

  Widget _checkbox({
    Key? key,
    required bool? value,
    required ValueChanged<bool?>? onChanged,
    bool tristate = false,
    double width = 48,
    bool skipTraversal = false,
    String? semanticLabel,
  }) {
    final checkbox = Checkbox(
      key: key,
      tristate: tristate,
      value: value,
      onChanged: onChanged,
    );
    return SizedBox(
      width: width,
      height: 48,
      child: skipTraversal
          ? ExcludeFocus(child: ExcludeSemantics(child: checkbox))
          : semanticLabel == null
          ? checkbox
          : Semantics(label: semanticLabel, child: checkbox),
    );
  }

  Widget _libraryRow(BuildContext context, PlexLibrary library, int index) {
    final tv = DeviceProfile.of(context).isTv;
    final unavailable = _unusable(library.id);
    final selected = selectedLibraryIds.contains(library.id) && !unavailable;
    final row = LayoutBuilder(
      builder: (context, constraints) {
        final roles = LineupTheme.of(context);
        final textTheme = Theme.of(context).textTheme;
        final fact = data.libraryScanFacts[library.id];
        final collectionRecovery = data.collectionRecoveryByLibrary[library.id];
        final titleStyle = textTheme.bodyMedium!.copyWith(
          color: unavailable ? roles.mutedText : roles.primaryText,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.3,
        );
        final statusStyle = textTheme.bodyMedium!.copyWith(
          fontSize: 18,
          height: 1.4,
        );
        final typeStyle = textTheme.bodyMedium!.copyWith(
          color: roles.mutedText,
          fontSize: 16,
          height: 1.4,
        );
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final narrow =
            constraints.maxWidth / textScale < 620 || textScale >= 1.6;
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(library.title, style: titleStyle),
            if (fact != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _scanDetail(fact, blocked: _settled && unavailable),
                    style: statusStyle.copyWith(
                      color: _scanColor(context, fact.status),
                    ),
                  ),
                  if (fact.status == LibraryScanStatus.transientFailure ||
                      data.libraryScanRetryIds.contains(library.id) ||
                      data.unavailableCollectionLibraryIds.contains(library.id))
                    FocusTraversalOrder(
                      order: NumericFocusOrder(index * 2 + 2),
                      child: LineupInlineLink(
                        key: ValueKey('retry-library-${library.id}'),
                        onPressed: data.busy
                            ? null
                            : () => onScan(retryLibraryIds: {library.id}),
                        child: Text(
                          collectionRecovery == null
                              ? 'Retry'
                              : 'Rescan after Plex changes',
                        ),
                      ),
                    ),
                ],
              ),
              if (collectionRecovery != null) ...[
                const SizedBox(height: 8),
                Text(collectionRecovery, style: statusStyle),
              ],
            ],
          ],
        );
        final type = Text(
          library.type == PlexLibraryType.show ? 'TV Shows' : 'Movies',
          textAlign: TextAlign.end,
          style: typeStyle,
        );
        final content = narrow
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _checkbox(
                    value: selected,
                    skipTraversal: tv,
                    semanticLabel: library.title,
                    onChanged: data.busy || unavailable
                        ? null
                        : (_) => onToggleLibrary(library.id),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        details,
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerRight, child: type),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _checkbox(
                    value: selected,
                    skipTraversal: tv,
                    semanticLabel: library.title,
                    onChanged: data.busy || unavailable
                        ? null
                        : (_) => onToggleLibrary(library.id),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: details),
                  const SizedBox(width: 16),
                  type,
                ],
              );
        final firstTvRow =
            tv &&
            index == 0 &&
            !unavailable &&
            !_settled &&
            data.libraryScanStatus != LibraryScanStatus.cancelled &&
            data.libraryScanCommittableIds
                .intersection(selectedLibraryIds)
                .isEmpty &&
            !data.busy &&
            data.libraryScanStatus != LibraryScanStatus.scanning;
        return InkWell(
          key: ValueKey('library-row-${library.id}'),
          focusNode: firstTvRow ? entryFocusNode : null,
          autofocus: firstTvRow,
          canRequestFocus: tv && !unavailable,
          excludeFromSemantics: !tv,
          onTap: data.busy || unavailable
              ? null
              : () => onToggleLibrary(library.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            child: content,
          ),
        );
      },
    );
    return tv
        ? FocusTraversalOrder(
            order: NumericFocusOrder(index * 2 + 1),
            child: Semantics(
              checked: selected,
              enabled: !unavailable,
              // The checkbox alone shows checked state; the surface carries
              // focus and hover only.
              child: LineupRowSurface(selected: false, child: row),
            ),
          )
        : row;
  }

  Color _scanColor(BuildContext context, LibraryScanStatus status) {
    final roles = LineupTheme.of(context);
    if (status != LibraryScanStatus.transientFailure) {
      return roles.secondaryText;
    }
    final focusedTv =
        DeviceProfile.of(context).isTv &&
        LineupFocusScope.visible(context, Focus.of(context).hasFocus);
    return focusedTv ? roles.primaryText : Theme.of(context).colorScheme.error;
  }

  String _scanDetail(
    LibraryScanFact fact, {
    required bool blocked,
  }) => switch (fact.status) {
    LibraryScanStatus.idle => 'Waiting to scan',
    LibraryScanStatus.scanning => switch (fact.phase) {
      PlexLibraryScanPhase.items =>
        'Scanning · ${fact.completedItems} items checked',
      PlexLibraryScanPhase.collections => 'Loading collections',
      PlexLibraryScanPhase.showGenres => 'Loading show details',
    },
    LibraryScanStatus.complete =>
      '${blocked ? '' : 'Ready · '}${fact.completedItems} ${fact.completedItems == 1 ? 'item' : 'items'} checked',
    LibraryScanStatus.empty => 'No media found',
    LibraryScanStatus.unsupported => 'No playable media found',
    LibraryScanStatus.transientFailure => 'Couldn’t scan · Try again.',
    LibraryScanStatus.cancelled => 'Cancelled · Scan again when you’re ready.',
  };
}
