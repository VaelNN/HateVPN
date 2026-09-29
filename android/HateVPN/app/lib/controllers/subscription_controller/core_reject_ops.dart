










library;

import 'dart:convert';

import '../../models/core_reject_verdict.dart';
import '../../models/node_warning.dart';
import '../../models/node_spec.dart';
import '../../models/server_list.dart';
import '../../models/template_vars.dart';
import '../../services/core_reject/core_reject_guard.dart';
import '../../services/node_hash.dart';
import '../../services/tag_resolver.dart';







String canonicalNodeBody(NodeSpec node) {
  try {

    return jsonEncode(_sortKeys(node.emit(const TemplateVars()).map));
  } catch (_) {


    return '';
  }
}

Object? _sortKeys(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _sortKeys(v[k])};
  }
  if (v is List) return [for (final e in v) _sortKeys(e)];
  return v;
}


typedef VerdictApply = ({ServerList list, bool changed});


typedef CoreRejectNavigationTarget = ({
  int entryIndex,
  int? memberIndex,
  NodeSpec node,
  NodeSpec source,
  ServerList list,
});


CoreRejectNodeRef? nodeRefFor(ServerList list, NodeSpec node) {
  final key = nodeKeyFor(list, node);
  if (key == null) return null;
  return CoreRejectNodeRef(sourceId: list.id, nodeKey: key);
}










String? nodeKeyFor(ServerList list, NodeSpec node) {
  switch (list) {
    case SubscriptionServers():
      return sourceNodeIdentities(list.nodes)[node];
    case FolderServers():
      for (final m in list.members) {
        if (identical(m.node, node)) {
          return folderMemberKeys(list)[node] ?? m.nameHint;
        }
      }
      return null;
    case UserServer():
      if (list.nodes.any((n) => identical(n, node))) return node.tag;
      return null;
  }
}


Map<NodeSpec, String> folderMemberKeys(FolderServers list) => sourceNodeRawTags([
      for (final m in list.members)
        if (m.node != null) m.node!,
    ]);

bool _nodeOrHop(NodeSpec owner, NodeSpec node) {
  if (identical(owner, node)) return true;
  for (var hop = owner.chained; hop != null; hop = hop.chained) {
    if (identical(hop, node)) return true;
  }
  return false;
}

NodeSpec? _sourceNodeOf(NodeSpec node, ServerList list) {
  switch (list) {
    case FolderServers():
      for (final m in list.members) {
        final n = m.node;
        if (n != null && _nodeOrHop(n, node)) return n;
      }
    case SubscriptionServers():
    case UserServer():
      for (final n in list.nodes) {
        if (_nodeOrHop(n, node)) return n;
      }
  }
  return null;
}



CoreRejectNavigationTarget? resolveCoreRejectNode(
  List<(int index, String id, ServerList list)> entries,
  DisabledNode disabled, {
  Map<String, NodeSpec>? emittedTagMap,
}) {
  var ref = disabled.ref ?? _refFromStoredVerdict(entries, disabled);
  if (ref != null) {
    final byRef = _resolveByRef(entries, ref);
    if (byRef != null) return byRef;
  }

  final mapped = emittedTagMap?[disabled.tag];
  if (mapped != null) {
    final fromMap = _resolveByNode(entries, mapped);
    if (fromMap != null) return fromMap;
  }

  return _resolveByTagAmongDisabled(entries, disabled.tag);
}








CoreRejectNodeRef? _refFromStoredVerdict(
  List<(int index, String id, ServerList list)> entries,
  DisabledNode disabled,
) {
  final found = <CoreRejectNodeRef>{};
  void take(Iterable<StoredWarning> ws) {
    for (final w in ws) {
      if (!w.isCoreRejected || w.reason != disabled.reason) continue;
      final ref = w.coreRejectRef;
      if (ref != null) found.add(ref);
    }
  }

  for (final (_, _, list) in entries) {
    switch (list) {
      case SubscriptionServers():
        for (final e in list.nodeWarnings.entries) {
          take(e.value);
        }
      case FolderServers():
        for (final m in list.members) {
          take(m.warnings);
        }
      case UserServer():
        take(list.warnings);
    }
  }
  return found.length == 1 ? found.single : null;
}

CoreRejectNavigationTarget? _resolveByRef(
  List<(int index, String id, ServerList list)> entries,
  CoreRejectNodeRef ref,
) {
  for (final (index, id, list) in entries) {
    if (id != ref.sourceId) continue;
    switch (list) {
      case SubscriptionServers():
        for (final n in list.nodes) {
          if (sourceNodeIdentities(list.nodes)[n] == ref.nodeKey) {
            return (
              entryIndex: index,
              memberIndex: null,
              node: n,
              source: n,
              list: list,
            );
          }
        }
      case FolderServers():


        final keys = folderMemberKeys(list);
        for (final byKey in [true, false]) {
          for (var mi = 0; mi < list.members.length; mi++) {
            final m = list.members[mi];
            final n = m.node;
            if (n == null) continue;
            final key = byKey ? keys[n] : n.tag;
            if (key == ref.nodeKey) {
              return (
                entryIndex: index,
                memberIndex: mi,
                node: n,
                source: n,
                list: list,
              );
            }
          }
        }
      case UserServer():
        for (final n in list.nodes) {
          if (n.tag == ref.nodeKey) {
            return (
              entryIndex: index,
              memberIndex: null,
              node: n,
              source: n,
              list: list,
            );
          }
        }
    }
  }
  return null;
}

CoreRejectNavigationTarget? _resolveByNode(
  List<(int index, String id, ServerList list)> entries,
  NodeSpec node,
) {
  for (final (index, _, list) in entries) {
    switch (list) {
      case FolderServers():
        for (var mi = 0; mi < list.members.length; mi++) {
          final n = list.members[mi].node;
          if (n != null && _nodeOrHop(n, node)) {
            return (
              entryIndex: index,
              memberIndex: mi,
              node: node,
              source: n,
              list: list,
            );
          }
        }
      case SubscriptionServers():
      case UserServer():
        if (list.nodes.any((n) => _nodeOrHop(n, node))) {
          final source = _sourceNodeOf(node, list) ?? node;
          return (
            entryIndex: index,
            memberIndex: null,
            node: node,
            source: source,
            list: list,
          );
        }
    }
  }
  return null;
}

CoreRejectNavigationTarget? _resolveByTagAmongDisabled(
  List<(int index, String id, ServerList list)> entries,
  String tag,
) {
  final candidates = <String>[tag];
  final m = RegExp(r'^(.*)-\d+$').firstMatch(tag);
  if (m != null) candidates.add(m.group(1)!);

  for (final cand in candidates) {
    for (final (index, _, list) in entries) {
      switch (list) {
        case SubscriptionServers():
          for (final n in list.nodes) {
            final identity = sourceNodeIdentities(list.nodes)[n];
            if (identity == null) continue;
            final hasVerdict = list.nodeWarnings[identity]
                    ?.any((w) => w.isCoreRejected) ==
                true;
            if (!hasVerdict && !list.disabledHashes.containsKey(identity)) {
              continue;
            }
            final bare = n.tag;
            final display =
                list.tagPrefix.isEmpty ? bare : TagResolver.displayTag(list.tagPrefix, bare);
            if (bare == cand || display == cand || identity == cand) {
              return (
                entryIndex: index,
                memberIndex: null,
                node: n,
                source: n,
                list: list,
              );
            }
            for (var hop = n.chained; hop != null; hop = hop.chained) {
              final hopDisplay = list.tagPrefix.isEmpty
                  ? hop.tag
                  : TagResolver.displayTag(list.tagPrefix, hop.tag);
              if (hop.tag == cand || hopDisplay == cand) {
                return (
                  entryIndex: index,
                  memberIndex: null,
                  node: n,
                  source: n,
                  list: list,
                );
              }
            }
          }
        case FolderServers():
          for (var mi = 0; mi < list.members.length; mi++) {
            final m = list.members[mi];
            if (!m.warnings.any((w) => w.isCoreRejected) && m.enabled) {
              continue;
            }
            final key = m.node?.tag ?? m.nameHint;
            if (key == cand && m.node != null) {
              return (
                entryIndex: index,
                memberIndex: mi,
                node: m.node!,
                source: m.node!,
                list: list,
              );
            }
          }
        case UserServer():
          if (!list.warnings.any((w) => w.isCoreRejected) && list.enabled) {
            continue;
          }
          for (final n in list.nodes) {
            if (n.tag == cand) {
              return (
                entryIndex: index,
                memberIndex: null,
                node: n,
                source: n,
                list: list,
              );
            }
          }
      }
    }
  }
  return null;
}




VerdictApply applyVerdict(ServerList list, NodeSpec node, String reason) {
  final verdict =
      StoredWarning.coreRejected(reason, ref: nodeRefFor(list, node));
  switch (list) {
    case SubscriptionServers():
      final hash = sourceNodeIdentities(list.nodes)[node];
      if (hash == null) return (list: list, changed: false);
      final disabled = Map<String, DateTime>.from(list.disabledHashes);
      disabled[hash] = DateTime.now();
      final ws = Map<String, List<StoredWarning>>.from(list.nodeWarnings);
      ws[hash] = upsertVerdict(ws[hash] ?? const [], verdict);
      return (
        list: list.copyWith(disabledHashes: disabled, nodeWarnings: ws),
        changed: true
      );

    case FolderServers():
      final at = list.members.indexWhere((m) => identical(m.node, node));
      if (at < 0) return (list: list, changed: false);
      final members = [...list.members];
      members[at] = members[at].copyWith(
        enabled: false,
        warnings: upsertVerdict(members[at].warnings, verdict),
      );
      return (list: list.copyWith(members: members), changed: true);

    case UserServer():
      if (!list.nodes.any((n) => identical(n, node))) {
        return (list: list, changed: false);
      }
      return (
        list: list.copyWith(
          enabled: false,
          warnings: upsertVerdict(list.warnings, verdict),
        ),
        changed: true
      );
  }
}


VerdictApply revertVerdict(ServerList list, NodeSpec node) {
  switch (list) {
    case SubscriptionServers():
      final hash = sourceNodeIdentities(list.nodes)[node];
      if (hash == null) return (list: list, changed: false);
      if (!list.disabledHashes.containsKey(hash) &&
          !list.nodeWarnings.containsKey(hash)) {
        return (list: list, changed: false);
      }
      final disabled = Map<String, DateTime>.from(list.disabledHashes)
        ..remove(hash);
      return (
        list: clearSubscriptionVerdict(
          list.copyWith(disabledHashes: disabled),
          hash,
        ),
        changed: true,
      );

    case FolderServers():
      final at = list.members.indexWhere((m) => identical(m.node, node));
      if (at < 0) return (list: list, changed: false);
      final m = list.members[at];
      if (m.enabled && !m.warnings.any((w) => w.isCoreRejected)) {
        return (list: list, changed: false);
      }
      final members = [...list.members];
      members[at] = m.copyWith(
        enabled: true,
        warnings: dropVerdict(m.warnings),
      );
      return (list: list.copyWith(members: members), changed: true);

    case UserServer():
      if (!list.nodes.any((n) => identical(n, node))) {
        return (list: list, changed: false);
      }
      if (list.enabled && !list.warnings.any((w) => w.isCoreRejected)) {
        return (list: list, changed: false);
      }
      return (
        list: list.copyWith(
          enabled: true,
          warnings: dropVerdict(list.warnings),
        ),
        changed: true,
      );
  }
}


Map<String, List<StoredWarning>> gcNodeWarnings(
  Map<String, List<StoredWarning>> warnings,
  Map<String, DateTime> disabled,
  Set<String> freshIdentities,
) {
  if (warnings.isEmpty) return warnings;
  return {
    for (final e in warnings.entries)
      if (disabled.containsKey(e.key) || freshIdentities.contains(e.key))
        e.key: e.value,
  };
}


SubscriptionServers clearSubscriptionVerdict(
    SubscriptionServers list, String identity) {
  final cur = list.nodeWarnings[identity];
  if (cur == null) return list;
  final next = Map<String, List<StoredWarning>>.from(list.nodeWarnings);
  final rest = dropVerdict(cur);
  if (rest.isEmpty) {
    next.remove(identity);
  } else {
    next[identity] = rest;
  }
  return list.copyWith(nodeWarnings: next);
}










({Map<String, DateTime> disabled, Map<String, List<StoredWarning>> warnings})
    refreshSubscriptionVerdicts({
  required Map<String, DateTime> disabled,
  required Map<String, List<StoredWarning>> warnings,
  required Map<String, String> oldBodies,
  required Map<String, String> newBodies,
}) {
  if (warnings.isEmpty) return (disabled: disabled, warnings: warnings);
  final nextDisabled = Map<String, DateTime>.from(disabled);
  final nextWarnings = <String, List<StoredWarning>>{};
  for (final e in warnings.entries) {
    final id = e.key;
    final hasVerdict = e.value.any((w) => w.isCoreRejected);
    if (!hasVerdict) {
      nextWarnings[id] = e.value;
      continue;
    }
    final oldBody = oldBodies[id];
    final newBody = newBodies[id];

    if (newBody == null) {
      nextWarnings[id] = e.value;
      continue;
    }


    if (oldBody != null && oldBody == newBody) {
      nextWarnings[id] = e.value;
      continue;
    }
    nextDisabled.remove(id);
    final rest = dropVerdict(e.value);
    if (rest.isNotEmpty) nextWarnings[id] = rest;
  }
  return (disabled: nextDisabled, warnings: nextWarnings);
}






















bool verdictDroppedByEdit({
  required List<StoredWarning> warnings,
  required NodeSpec? before,
  required NodeSpec? after,
}) {
  if (!warnings.any((w) => w.isCoreRejected)) return false;


  if (before == null || after == null) return true;
  return canonicalNodeBody(before) != canonicalNodeBody(after);
}


Map<String, String> bodiesByIdentity(List<NodeSpec> nodes) {
  final ids = sourceNodeIdentities(nodes);
  return {
    for (final e in ids.entries) e.value: canonicalNodeBody(e.key),
  };
}











void stampStoredVerdicts(
  List<NodeSpec> nodes,
  Map<String, List<StoredWarning>> stored,
) {
  if (stored.isEmpty) return;
  final ids = sourceNodeIdentities(nodes);
  for (final e in ids.entries) {
    final ws = stored[e.value];
    if (ws == null || ws.isEmpty) continue;
    stampNodeWarnings(e.key, ws);
  }
}


void stampNodeWarnings(NodeSpec node, List<StoredWarning> stored) {
  for (final w in stored) {
    final made = w.toWarning();
    node.warnings.removeWhere(
        (x) => x is RegistryWarning && x.code == made.code && x.path == null);
    node.warnings.insert(0, made);
  }
}




void unstampCoreRejected(NodeSpec node) {
  node.warnings.removeWhere((x) =>
      x is RegistryWarning && x.code == kCoreRejectedCode && x.path == null);
}





List<NodeWarning> mergedNodeWarnings(
  NodeSpec node,
  List<StoredWarning> stored,
) {
  final out = [...node.warnings];
  for (final w in stored) {
    final made = w.toWarning();
    out.removeWhere(
        (x) => x is RegistryWarning && x.code == made.code && x.path == null);
    out.insert(0, made);
  }
  return out;
}
