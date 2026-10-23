import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'licenses_repository.dart';

class LicensesView extends StatefulWidget {
  const LicensesView({
    required this.onBack,
    this.repository,
    this.onOpenMenu,
    this.menuFocusNode,
    super.key,
  });
  final VoidCallback onBack;
  final LicensesRepository? repository;
  final LineupMenuCallback? onOpenMenu;
  final FocusNode? menuFocusNode;
  @override
  State<LicensesView> createState() => LicensesViewState();
}

class _SourceState {
  _SourceState(this.source);
  final LicenseSource source;
  List<LicenseItem>? items;
  bool failed = false;
  int revision = 0;
}

class _ReadingPage {
  _ReadingPage(this.item);
  final LicenseItem? item;
  final scroll = ScrollController();
  final back = FocusNode(debugLabel: 'Licenses back');
  final copy = FocusNode(debugLabel: 'Copy license document');
  final content = FocusNode(debugLabel: 'License document');
  final selection = FocusNode(
    debugLabel: 'License text selection',
    skipTraversal: defaultTargetPlatform == TargetPlatform.android,
  );
  final rows = <String, FocusNode>{};
  Future<({String? text, bool failed})>? text;
  String? returnId;
  String? copyFeedback;
  void dispose() {
    scroll.dispose();
    back.dispose();
    copy.dispose();
    content.dispose();
    selection.dispose();
    for (final node in rows.values) {
      node.dispose();
    }
  }
}

class LicensesViewState extends State<LicensesView> {
  final _pages = [_ReadingPage(null)];
  late final _sources = (widget.repository ?? LicensesRepository()).sources
      .map(_SourceState.new)
      .toList();
  _ReadingPage get _page => _pages.last;

  @override
  void initState() {
    super.initState();
    for (final source in _sources) {
      unawaited(_load(source));
    }
    _focusBack();
  }

  void _focusBack() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _page.back.requestFocus();
  });

  Future<void> _load(_SourceState source) async {
    final revision = ++source.revision;
    source.failed = false;
    source.items = null;
    try {
      final items = await source.source.load();
      if (!mounted || source.revision != revision) return;
      setState(() => source.items = items);
    } catch (_) {
      if (!mounted || source.revision != revision) return;
      setState(() => source.failed = true);
    }
  }

  void back() {
    if (_pages.length == 1) {
      widget.onBack();
      return;
    }
    final removed = _pages.removeLast();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      removed.dispose();
      if (!mounted) return;
      final node = _page.rows[_page.returnId];
      (node ?? _page.back).requestFocus();
    });
  }

  void _open(LicenseItem item) {
    _page.returnId = item.id;
    setState(() {
      final page = _ReadingPage(item);
      if (item.read != null) page.text = _read(item);
      _pages.add(page);
    });
    _focusBack();
  }

  @override
  void dispose() {
    for (final page in _pages) {
      page.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final page = _page;
    final item = page.item;
    final parent = _pages.length == 1
        ? 'Support'
        : _pages[_pages.length - 2].item?.title ?? 'Licenses';
    return ColoredBox(
      color: roles.deepBackground,
      child: Column(
        children: [
          LineupTopBar(
            onOpenMenu: widget.onOpenMenu,
            menuFocusNode: widget.menuFocusNode,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: FocusTraversalGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The header scrolls with the document in very short or scaled windows.
                        Expanded(
                          child: _readingSurface(page, (context) {
                            final roles = LineupTheme.of(context);
                            return Scrollbar(
                              controller: page.scroll,
                              thumbVisibility: true,
                              child: Focus(
                                focusNode: page.content,
                                skipTraversal:
                                    defaultTargetPlatform ==
                                    TargetPlatform.android,
                                canRequestFocus:
                                    defaultTargetPlatform !=
                                        TargetPlatform.android ||
                                    item?.read != null,
                                onKeyEvent: (_, event) =>
                                    _scrollKey(page, event),
                                child: SelectionArea(
                                  focusNode: page.selection,
                                  child: CustomScrollView(
                                    key: PageStorageKey(
                                      'licenses-${item?.id ?? 'index'}',
                                    ),
                                    controller: page.scroll,
                                    slivers: [
                                      SliverToBoxAdapter(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            LineupInlineLink(
                                              focusNode: page.back,
                                              onPressed: back,
                                              child: Text('‹ Back to $parent'),
                                            ),
                                            Semantics(
                                              header: true,
                                              child: Text(
                                                item?.title ?? 'Licenses',
                                                style: LineupTypography
                                                    .pageTitle
                                                    .copyWith(
                                                      color: roles.primaryText,
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              item == null
                                                  ? 'Third-party software used by this build.'
                                                  : item.subtitle.isNotEmpty
                                                  ? item.subtitle
                                                  : 'License and notice documents bundled with this build.',
                                              style: TextStyle(
                                                color: roles.secondaryText,
                                              ),
                                            ),
                                            const SizedBox(height: 24),
                                          ],
                                        ),
                                      ),
                                      if (item == null)
                                        ..._index()
                                      else if (item.children != null)
                                        _rows(item.children!)
                                      else
                                        SliverToBoxAdapter(
                                          child: _document(page),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readingSurface(_ReadingPage page, WidgetBuilder builder) =>
      AnimatedBuilder(
        animation: page.content,
        builder: (context, _) {
          final tvDocument =
              defaultTargetPlatform == TargetPlatform.android &&
              page.item?.read != null;
          final focused = LineupFocusScope.visible(
            context,
            tvDocument && page.content.hasPrimaryFocus,
          );
          final roles = LineupTheme.of(context);
          return Semantics(
            container: tvDocument,
            label: tvDocument ? 'License document' : null,
            focusable: tvDocument,
            focused: tvDocument ? page.content.hasPrimaryFocus : null,
            child: LineupFocusFrame(
              focused: focused,
              child: ColoredBox(
                key: const Key('licenses-reading-surface'),
                color: focused ? roles.focusedSurface : roles.deepBackground,
                child: LineupFocusInk(
                  focused: focused,
                  child: Builder(builder: builder),
                ),
              ),
            ),
          );
        },
      );

  KeyEventResult _scrollKey(_ReadingPage page, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!page.scroll.hasClients) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final position = page.scroll.position;
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Back and Copy are actions; only the explicit reading owner consumes
      // document arrows. Loading/failure pages retain ordinary Retry traversal.
      final readable = page.item?.read != null && page.copy.context != null;
      if (readable) {
        if (key == LogicalKeyboardKey.arrowDown && page.back.hasFocus) {
          return _focusAction(page.copy, towardsEnd: true);
        }
        if (key == LogicalKeyboardKey.arrowDown && page.copy.hasFocus) {
          page.content.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp && page.copy.hasFocus) {
          return _focusAction(page.back);
        }
        if (page.content.hasPrimaryFocus &&
            (key == LogicalKeyboardKey.arrowLeft ||
                (key == LogicalKeyboardKey.arrowUp &&
                    position.pixels <= position.minScrollExtent))) {
          return _focusAction(page.copy);
        }
      }
      if (!page.content.hasPrimaryFocus &&
          (key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.arrowUp)) {
        FocusManager.instance.primaryFocus?.focusInDirection(
          key == LogicalKeyboardKey.arrowDown
              ? TraversalDirection.down
              : TraversalDirection.up,
        );
        return KeyEventResult.handled;
      }
    }
    final amount = switch (key) {
      LogicalKeyboardKey.arrowDown => 48.0,
      LogicalKeyboardKey.arrowUp => -48.0,
      LogicalKeyboardKey.pageDown => position.viewportDimension * .85,
      LogicalKeyboardKey.pageUp => -position.viewportDimension * .85,
      _ => null,
    };
    final target = key == LogicalKeyboardKey.home
        ? 0.0
        : key == LogicalKeyboardKey.end
        ? position.maxScrollExtent
        : amount == null
        ? null
        : position.pixels + amount;
    if (target == null) {
      return KeyEventResult.ignored;
    }
    page.scroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    return KeyEventResult.handled;
  }

  KeyEventResult _focusAction(FocusNode node, {bool towardsEnd = false}) {
    node.requestFocus();
    final context = node.context;
    if (context != null) {
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: towardsEnd
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ),
      );
    }
    return KeyEventResult.handled;
  }

  List<Widget> _index() => [
    for (final source in _sources) ...[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Semantics(
            header: true,
            child: Text(
              source.source.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
      ),
      if (source.failed)
        SliverToBoxAdapter(
          child: _failure(
            'These licenses could not be loaded.',
            () => setState(() {
              unawaited(_load(source));
            }),
          ),
        )
      else if (source.items == null)
        SliverToBoxAdapter(
          child: Semantics(
            liveRegion: true,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Loading licenses…'),
            ),
          ),
        )
      else
        _rows(source.items!),
    ],
  ];

  Widget _rows(List<LicenseItem> items) => SliverList.builder(
    itemCount: items.length,
    itemBuilder: (context, index) {
      final item = items[index];
      final focus = _page.rows.putIfAbsent(
        item.id,
        () => FocusNode(debugLabel: item.title),
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: LineupNavigationRow(
          key: ValueKey('license-row-${item.id}'),
          selected: false,
          focusNode: focus,
          onPressed: () => _open(item),
          child: Row(
            children: [
              Expanded(child: Text(item.title)),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      );
    },
  );

  Future<({String? text, bool failed})> _read(LicenseItem item) async {
    try {
      return (text: await item.read!(), failed: false);
    } catch (_) {
      return (text: null, failed: true);
    }
  }

  Widget _document(_ReadingPage page) =>
      FutureBuilder<({String? text, bool failed})>(
        future: page.text,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Semantics(
              liveRegion: true,
              child: const Text('Loading license document…'),
            );
          }
          if (snapshot.data?.failed == true) {
            return _failure('This license document could not be loaded.', () {
              setState(() {
                page.text = _read(page.item!);
              });
            });
          }
          if (!snapshot.hasData) {
            return Semantics(
              liveRegion: true,
              child: Text('Loading license document…'),
            );
          }
          // Separate paragraphs stay readable to assistive technology and selectable
          // together. Raw source text is never interpreted as markup or links.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  focusNode: page.copy,
                  style: defaultTargetPlatform == TargetPlatform.android
                      ? LineupTheme.buttonStyle(
                          LineupTheme.of(context),
                          LineupButtonTier.text,
                          focusVisible: LineupFocusScope.visible(context),
                        )
                      : null,
                  onPressed: () => _copy(page, snapshot.requireData.text!),
                  child: const Text('Copy document'),
                ),
              ),
              if (page.copyFeedback != null)
                Semantics(liveRegion: true, child: Text(page.copyFeedback!)),
              for (final paragraph in snapshot.requireData.text!.split('\n\n'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    paragraph,
                    softWrap: true,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.5,
                      color: LineupTheme.of(context).primaryText,
                    ),
                  ),
                ),
            ],
          );
        },
      );

  Future<void> _copy(_ReadingPage page, String text) async {
    String feedback;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      feedback = 'Document copied';
    } catch (_) {
      feedback = 'Could not copy the document. Try again.';
    }
    if (mounted && _page == page) setState(() => page.copyFeedback = feedback);
  }

  Widget _failure(String message, VoidCallback retry) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LineupNotice(message: message),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: retry, child: const Text('Retry')),
      const SizedBox(height: 16),
    ],
  );
}
