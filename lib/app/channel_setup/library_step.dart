import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  final VoidCallback onToggleAll;
  final Future<void> Function()? onRequestLogout;

  bool get _settled => switch (data.libraryScanStatus) {
    LibraryScanStatus.complete ||
    LibraryScanStatus.empty ||
    LibraryScanStatus.unsupported ||
    LibraryScanStatus.transientFailure => true,
    _ => false,
  };

  String _summary() {
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
    if (!_settled || statuses.isEmpty) {
      return 'Select the Plex libraries to scan for channel ideas.';
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
    final actionStyle = Theme.of(context).textTheme.labelLarge!
        .copyWith(fontSize: 18);
    Widget actionLabel(String label) => Builder(
      builder: (context) => Text(
        label,
        style: roles.androidTv
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
      summary: Wrap(
        spacing: 8,
        children: [
          if (hasLibraries)
            TextButton(
              key: const ValueKey('setup-switch-server'),
              style: TextButton.styleFrom(
                padding: LineupTheme.of(context).androidTv
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
              style: roles.androidTv
                  ? TextButton.styleFrom(minimumSize: const Size(0, 48))
                  : null,
              onPressed: onCancelSetup,
              child: actionLabel('Cancel'),
            ),
        ],
      ),
      leading: [
        if (hasLibraries &&
            !scanning &&
            data.libraryScanReadyIds
                .intersection(selectedLibraryIds)
                .isNotEmpty)
          OutlinedButton(
            key: const ValueKey('scan-again-libraries'),
            onPressed: data.busy ? null : () => onScan(advanceWhenReady: false),
            child: const Text('Scan again'),
          ),
        if (canRetry && canContinue)
          OutlinedButton(
            key: const ValueKey('retry-failed-libraries'),
            onPressed: data.busy ? null : () => onScan(retryFailedOnly: true),
            child: Text(retryLabel),
          ),
      ],
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
                    child: const Text('Sign out'),
                  ),
                FilledButton(
                  key: const ValueKey('setup-switch-server'),
                  onPressed: data.canSwitchServer ? onSwitchServer : null,
                  child: const Text('Switch server'),
                ),
              ],
            )
          : scanning
          ? TextButton(
              onPressed: onCancelScan,
              child: actionLabel('Cancel scan'),
            )
          : canContinue
          ? FilledButton(
              key: const ValueKey('continue-ready-libraries'),
              onPressed: data.busy ? null : () => onCommit(ready),
              child: Text(
                'Continue with ${ready.length} ${ready.length == 1 ? 'library' : 'libraries'}',
              ),
            )
          : canRetry
          ? FilledButton(
              key: const ValueKey('retry-failed-libraries'),
              onPressed: selectedLibraryIds.isEmpty || data.busy
                  ? null
                  : () => onScan(retryFailedOnly: true),
              child: Text(retryLabel),
            )
          : FilledButton(
              key: const ValueKey('scan-selected-libraries'),
              onPressed: selectedLibraryIds.isEmpty || data.busy
                  ? null
                  : onScan,
              child: Text(_settled ? 'Scan again' : 'Scan selected libraries'),
            ),
    );
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final singleScroll =
            roles.androidTv ||
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
        final title = data.libraryScanStatus == LibraryScanStatus.scanning
            ? 'Scanning your libraries'
            : _settled
            ? 'Review your libraries'
            : 'Choose libraries';
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(
              context,
              title,
              data.libraries.isEmpty || _settled || scanning ? '' : _summary(),
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
              _selectionSummary(context),
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
                        ? scanError
                        : ready.isEmpty
                        ? _summary()
                        : '${ready.length} of ${selectedLibraryIds.length} ${selectedLibraryIds.length == 1 ? 'library' : 'libraries'} ${ready.length == 1 ? 'is' : 'are'} ready. Continuing builds from ${data.libraries.where((library) => ready.contains(library.id)).map((library) => library.title).join(', ')}${excluded > 0 ? ' only' : ''}.',
                    style: bodyStyle,
                  ),
                ),
              ),
            if (!roles.androidTv) ...[const SizedBox(height: 24), footer],
          ],
        );
        if (roles.androidTv) {
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
    return roles.androidTv
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

  Widget _selectionSummary(BuildContext context) {
    final roles = LineupTheme.of(context);
    final summaryStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: roles.metadataTextSize(desktop: 16),
      height: 1.4,
    );
    final editable =
        !data.busy && data.libraryScanStatus != LibraryScanStatus.scanning;
    final libraries = data.libraries;
    final selected = selectedLibraryIds.length;
    final all = selected == libraries.length;
    final value = all
        ? true
        : selected == 0
        ? false
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      child: Row(
        children: [
          if (libraries.length > 1) ...[
            _checkbox(
              key: const ValueKey('select-all-libraries'),
              skipTraversal: roles.androidTv,
              tristate: true,
              value: value,
              onChanged: editable ? (_) => onToggleAll() : null,
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(0),
              child: TextButton(
                style: const ButtonStyle(
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                onPressed: editable ? onToggleAll : null,
                child: Builder(
                  builder: (context) {
                    final ink = LineupTheme.of(context);
                    return Text(
                      'Select all',
                      style: summaryStyle.copyWith(
                        fontSize: ink.compactActionTextSize,
                        color: editable ? ink.secondaryText : ink.mutedText,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          const Spacer(),
          Text(
            '$selected of ${libraries.length} selected',
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
    final tv = LineupTheme.of(context).androidTv;
    final selected = selectedLibraryIds.contains(library.id);
    final row = LayoutBuilder(
      builder: (context, constraints) {
        final roles = LineupTheme.of(context);
        final textTheme = Theme.of(context).textTheme;
        final fact = data.libraryScanFacts[library.id];
        final collectionRecovery = data.collectionRecoveryByLibrary[library.id];
        final titleStyle = textTheme.bodyMedium!.copyWith(
          color: roles.primaryText,
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
          fontSize: roles.metadataTextSize(desktop: 16),
          height: 1.4,
        );
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final narrow =
            constraints.maxWidth / textScale < 620 || textScale >= 1.6;
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(library.title, style: titleStyle),
                if (selected &&
                    _settled &&
                    !data.libraryScanCommittableIds.contains(library.id))
                  Text("Won't be used", style: typeStyle),
              ],
            ),
            if (fact != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _scanDetail(fact),
                    style: statusStyle.copyWith(
                      color: _scanColor(context, fact.status),
                    ),
                  ),
                  if (fact.status == LibraryScanStatus.transientFailure ||
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _checkbox(
                    value: selected,
                    skipTraversal: tv,
                    semanticLabel: library.title,
                    onChanged: data.busy
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _checkbox(
                    value: selected,
                    skipTraversal: tv,
                    semanticLabel: library.title,
                    onChanged: data.busy
                        ? null
                        : (_) => onToggleLibrary(library.id),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: details),
                  const SizedBox(width: 16),
                  type,
                ],
              );
        return InkWell(
          key: ValueKey('library-row-${library.id}'),
          canRequestFocus: tv,
          excludeFromSemantics: !tv,
          onTap: data.busy ? null : () => onToggleLibrary(library.id),
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
              child: LineupRowSurface(selected: selected, child: row),
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
        roles.androidTv &&
        LineupFocusScope.visible(context, Focus.of(context).hasFocus);
    return focusedTv ? roles.primaryText : Theme.of(context).colorScheme.error;
  }

  String _scanDetail(LibraryScanFact fact) => switch (fact.status) {
    LibraryScanStatus.idle => 'Waiting to scan',
    LibraryScanStatus.scanning => switch (fact.phase) {
      PlexLibraryScanPhase.items =>
        'Scanning · ${fact.completedItems} items checked',
      PlexLibraryScanPhase.collections => 'Loading collections',
      PlexLibraryScanPhase.showGenres => 'Loading show details',
    },
    LibraryScanStatus.complete =>
      'Ready · ${fact.completedItems} ${fact.completedItems == 1 ? 'item' : 'items'} checked',
    LibraryScanStatus.empty => 'No media found',
    LibraryScanStatus.unsupported => 'No playable media found',
    LibraryScanStatus.transientFailure => 'Couldn’t scan · Try again.',
    LibraryScanStatus.cancelled => 'Cancelled · Scan again when you’re ready.',
  };
}
