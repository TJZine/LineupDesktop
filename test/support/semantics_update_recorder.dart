import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Install before testWidgets creates the default binding. Records the actual
/// outgoing engine API, forwarding every argument in the pinned Flutter API.
class SemanticsRecordingBinding extends AutomatedTestWidgetsFlutterBinding {
  void Function(List<SemanticsUpdateRecord>)? onBatch;

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() => _RecordingBuilder(
    super.createSemanticsUpdateBuilder(),
    (nodes) => onBatch?.call(nodes),
  );
}

class SemanticsUpdateRecord {
  const SemanticsUpdateRecord(
    this.id, {
    this.children = const [],
    this.hitChildren = const [],
    this.rect = Rect.zero,
    this.label = '',
    this.value = '',
    this.actions = 0,
    this.traversalParent = -1,
    this.isSlider = false,
  });

  final int id;
  final List<int> children;
  final List<int> hitChildren;
  final Rect rect;
  final String label;
  final String value;
  final int actions;
  final int traversalParent;
  final bool isSlider;

  @override
  String toString() =>
      '#$id children=$children hit=$hitChildren '
      'size=${rect.size} labelLength=${label.length} value=$value '
      'actions=$actions traversalParent=$traversalParent';
}

class _RecordingBuilder implements ui.SemanticsUpdateBuilder {
  _RecordingBuilder(this.delegate, this.onBatch);
  final void Function(List<SemanticsUpdateRecord>) onBatch;
  final ui.SemanticsUpdateBuilder delegate;
  final nodes = <SemanticsUpdateRecord>[];

  @override
  void updateNode({
    required int id,
    required ui.SemanticsFlags flags,
    required int actions,
    required int maxValueLength,
    required int currentValueLength,
    required int textSelectionBase,
    required int textSelectionExtent,
    required int platformViewId,
    required int scrollChildren,
    required int scrollIndex,
    required int traversalParent,
    required double scrollPosition,
    required double scrollExtentMax,
    required double scrollExtentMin,
    required Rect rect,
    required String identifier,
    required String label,
    required List<ui.StringAttribute> labelAttributes,
    required String value,
    required List<ui.StringAttribute> valueAttributes,
    required String increasedValue,
    required List<ui.StringAttribute> increasedValueAttributes,
    required String decreasedValue,
    required List<ui.StringAttribute> decreasedValueAttributes,
    required String hint,
    required List<ui.StringAttribute> hintAttributes,
    required String tooltip,
    required TextDirection? textDirection,
    required Float64List transform,
    required Float64List hitTestTransform,
    required Int32List childrenInTraversalOrder,
    required Int32List childrenInHitTestOrder,
    required Int32List additionalActions,
    int headingLevel = 0,
    String linkUrl = '',
    ui.SemanticsRole role = ui.SemanticsRole.none,
    required List<String>? controlsNodes,
    ui.SemanticsValidationResult validationResult =
        ui.SemanticsValidationResult.none,
    ui.SemanticsHitTestBehavior hitTestBehavior =
        ui.SemanticsHitTestBehavior.defer,
    required ui.SemanticsInputType inputType,
    required Locale? locale,
    required String minValue,
    required String maxValue,
  }) {
    nodes.add(
      SemanticsUpdateRecord(
        id,
        children: childrenInTraversalOrder.toList(),
        hitChildren: childrenInHitTestOrder.toList(),
        rect: rect,
        label: label,
        value: value,
        actions: actions,
        traversalParent: traversalParent,
        isSlider: flags.isSlider,
      ),
    );
    delegate.updateNode(
      id: id,
      flags: flags,
      actions: actions,
      maxValueLength: maxValueLength,
      currentValueLength: currentValueLength,
      textSelectionBase: textSelectionBase,
      textSelectionExtent: textSelectionExtent,
      platformViewId: platformViewId,
      scrollChildren: scrollChildren,
      scrollIndex: scrollIndex,
      traversalParent: traversalParent,
      scrollPosition: scrollPosition,
      scrollExtentMax: scrollExtentMax,
      scrollExtentMin: scrollExtentMin,
      rect: rect,
      identifier: identifier,
      label: label,
      labelAttributes: labelAttributes,
      value: value,
      valueAttributes: valueAttributes,
      increasedValue: increasedValue,
      increasedValueAttributes: increasedValueAttributes,
      decreasedValue: decreasedValue,
      decreasedValueAttributes: decreasedValueAttributes,
      hint: hint,
      hintAttributes: hintAttributes,
      tooltip: tooltip,
      textDirection: textDirection,
      transform: transform,
      hitTestTransform: hitTestTransform,
      childrenInTraversalOrder: childrenInTraversalOrder,
      childrenInHitTestOrder: childrenInHitTestOrder,
      additionalActions: additionalActions,
      headingLevel: headingLevel,
      linkUrl: linkUrl,
      role: role,
      controlsNodes: controlsNodes,
      validationResult: validationResult,
      hitTestBehavior: hitTestBehavior,
      inputType: inputType,
      locale: locale,
      minValue: minValue,
      maxValue: maxValue,
    );
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => delegate.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );

  @override
  ui.SemanticsUpdate build() {
    onBatch(List.unmodifiable(nodes));
    return delegate.build();
  }
}

/// Structural regression oracle for the pinned common desktop bridge. This is
/// not a native AX implementation: it checks creation/destruction/reparenting,
/// not events, caches, roles, notifications or recovery after a native failure.
///
/// Mirrors accessibility_bridge.cc CommitUpdates/CreateRemoveReparentedNodesUpdate/
/// GetSubTreeList and ax_tree.cc ComputePendingChangesToNode. The C++ maps are
/// unordered. Replay opposing seed orders and reject disagreement explicitly;
/// these samples do not exhaust every possible std::unordered_map iteration.
/// Never continue replay after a rejection (the prepass may already have run).
class DesktopSemanticsReplay {
  final _forward = _StructuralTree();
  final _reverse = _StructuralTree();
  final batches = <List<SemanticsUpdateRecord>>[];
  String step = 'mount';
  String? firstError;

  Map<int, SemanticsUpdateRecord> get data => _forward.data;
  Map<int, List<int>> get children => _forward.children;
  Map<int, int> get parents => _forward.parents;
  int? get root => _forward.root;

  void apply(List<SemanticsUpdateRecord> records) {
    batches.add(records);
    if (firstError != null) return;
    final a = _forward.apply(records, reverse: false);
    final b = _reverse.apply(records, reverse: true);
    if ((a == null) != (b == null) ||
        (a == null && _forward.signature != _reverse.signature)) {
      firstError = 'Unsupported order-sensitive batch during $step: $a / $b';
    } else if (a != null) {
      firstError =
          'batch ${batches.length} during $step: $a\n'
          '${records.join('\n')}\nreverse-seed result: $b';
    }
  }

  List<SemanticsUpdateRecord> get traversal {
    final visited = <int>{};
    final result = <SemanticsUpdateRecord>[];
    void walk(int id) {
      if (!visited.add(id)) throw StateError('Cycle at $id');
      final node = data[id];
      if (node == null) throw StateError('Reachable node $id lacks data');
      result.add(node);
      for (final child in children[id] ?? const <int>[]) {
        walk(child);
      }
    }

    if (root != null) walk(root!);
    return result;
  }
}

class _StructuralTree {
  final children = <int, List<int>>{};
  final parents = <int, int>{};
  final data = <int, SemanticsUpdateRecord>{};
  int? root;

  String get signature {
    final ids = children.keys.toList()..sort();
    return '$root:${[for (final id in ids) '$id:${children[id]}']}';
  }

  String? apply(List<SemanticsUpdateRecord> records, {required bool reverse}) {
    final pending = {for (final node in records) node.id: node};
    if (pending.length != records.length) {
      return 'Unsupported duplicate records';
    }
    final prepass = <int, List<int>>{};
    for (final node in records) {
      for (final child in node.children) {
        if (!children.containsKey(child)) continue;
        final parent = parents[child];
        if (parent == null) return 'Unsupported root reparent';
        if (parent == node.id) continue;
        if (!pending.containsKey(child)) {
          return 'Reparented child $child lacks required pending record';
        }
        prepass
            .putIfAbsent(parent, () => List.of(children[parent]!))
            .remove(child);
      }
    }
    if (prepass.isNotEmpty) {
      final ids = prepass.keys.toList()..sort();
      final error = _update(
        [
          for (final id in reverse ? ids.reversed : ids)
            SemanticsUpdateRecord(id, children: prepass[id]!),
        ],
        null,
        const {},
      );
      if (error != null) return 'prepass: $error';
    }
    final remaining = Map.of(pending);
    final lists = <List<SemanticsUpdateRecord>>[];
    while (remaining.isNotEmpty) {
      final ids = remaining.keys.toList()..sort();
      final target = remaining.remove(reverse ? ids.last : ids.first)!;
      final list = <SemanticsUpdateRecord>[];
      final visiting = <int>{};
      void collect(SemanticsUpdateRecord node) {
        if (!visiting.add(node.id)) {
          throw StateError('Cyclic pending traversal');
        }
        list.add(node);
        for (final child in node.children) {
          final update = remaining.remove(child);
          if (update != null) collect(update);
        }
        visiting.remove(node.id);
      }

      collect(target);
      lists.add(list);
    }
    return _update(
      [for (final list in lists.reversed) ...list],
      root == null && lists.isNotEmpty ? lists.last.first.id : null,
      pending,
    );
  }

  String? _update(
    List<SemanticsUpdateRecord> nodes,
    int? newRoot,
    Map<int, SemanticsUpdateRecord> records,
  ) {
    // The pending state uses last-known data, including changes earlier in this
    // update. A destroyed node can be created again and must be initialized.
    final alive = children.keys.toSet();
    final last = {for (final e in children.entries) e.key: List.of(e.value)};
    final requiresInit = <int>{};
    final destroyed = <int>{};
    final provided = <int>{};
    bool create(int id) {
      if (!alive.add(id)) return false;
      requiresInit.add(id);
      return true;
    }

    void destroy(int id) {
      if (!alive.remove(id)) return;
      destroyed.add(id);
      for (final child in last[id] ?? const <int>[]) {
        destroy(child);
      }
      last.remove(id);
      requiresInit.remove(id);
    }

    for (final node in nodes) {
      final id = node.id;
      if (!alive.contains(id)) {
        if (id != newRoot) {
          return '$id will not be in the tree and is not the new root';
        }
        create(id);
      }
      final now = node.children.toSet();
      if (now.length != node.children.length) {
        return 'Node $id has duplicate child';
      }
      if (requiresInit.contains(id)) {
        for (final child in now) {
          // IncrementPendingCreateNodeCount rejects ANY child already alive,
          // including an existing child of a newly created node (no APPROX rule).
          if (!create(child)) {
            return 'Node $child already exists during creation';
          }
        }
      } else {
        final old = (last[id] ?? const <int>[]).toSet();
        // AXTree iterates std::set_symmetric_difference in numeric ID order.
        final changed = {
          ...old.difference(now),
          ...now.difference(old),
        }.toList()..sort();
        for (final child in changed) {
          if (now.contains(child)) {
            if (!create(child)) {
              return 'Node $child is not marked for destruction, would be reparented to $id';
            }
          } else {
            destroy(child);
          }
        }
      }
      last[id] = node.children;
      requiresInit.remove(id);
      provided.add(id);
    }
    if (requiresInit.isNotEmpty) return 'Nodes left pending: $requiresInit';
    // Commit only the supported structural result. This makes no assertion that
    // arbitrary native Unserialize failures are atomic or recoverable.
    for (final id in destroyed) {
      children.remove(id);
      data.remove(id);
    }
    for (final id in provided.where(alive.contains)) {
      children[id] = last[id]!;
      if (records[id] case final record?) data[id] = record;
    }
    parents.clear();
    for (final entry in children.entries) {
      for (final child in entry.value) {
        parents[child] = entry.key;
      }
    }
    root ??= newRoot;
    return null;
  }
}
