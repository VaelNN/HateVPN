import '../../controllers/subscription_controller.dart';
import '../../models/core_reject_verdict.dart';
import '../../models/node_spec.dart';
import '../../models/server_list.dart';
import '../../services/node_hash.dart';
import '../../services/tag_resolver.dart';





























Set<String> sourcesOfTag(
  String tag,
  List<SubscriptionEntry> entries,
) {
  final result = <String>{};
  for (final (prefix, id) in sourcePrefixIndex(entries)) {
    if (tag.startsWith(prefix)) result.add(id);
  }
  return result;
}







List<(String, String)> sourcePrefixIndex(List<SubscriptionEntry> entries) {
  final out = <(String, String)>[];
  for (final e in entries) {
    final list = e.list;

    if (list is! SubscriptionServers && list is! FolderServers) continue;
    if (!e.enabled) continue;
    final prefix = list.tagPrefix;
    if (prefix.isEmpty) continue;
    out.add(('$prefix ', e.id));
  }
  return out;
}



class TagOwner {

  final int entryIndex;


  final int? memberIndex;

  const TagOwner(this.entryIndex, {this.memberIndex});
}
















TagOwner? ownerOfTag(String culpritTag, List<SubscriptionEntry> entries) {
  final candidates = <String>[culpritTag];
  final m = RegExp(r'^(.*)-\d+$').firstMatch(culpritTag);
  if (m != null) candidates.add(m.group(1)!);

  for (final cand in candidates) {
    for (var ei = 0; ei < entries.length; ei++) {
      final list = entries[ei].list;
      final bare = TagResolver.stripPrefix(cand, list.tagPrefix);
      if (list is FolderServers) {
        for (var mi = 0; mi < list.members.length; mi++) {
          if (list.members[mi].node?.tag == bare) {
            return TagOwner(ei, memberIndex: mi);
          }
        }
      } else {
        for (final n in list.nodes) {
          if (n.tag == bare) return TagOwner(ei);


          for (var hop = n.chained; hop != null; hop = hop.chained) {
            if (hop.tag == bare) return TagOwner(ei);
          }
        }
      }
    }
  }
  return null;
}




bool _nodeOrHop(NodeSpec owner, NodeSpec node) {
  if (identical(owner, node)) return true;
  for (var hop = owner.chained; hop != null; hop = hop.chained) {
    if (identical(hop, node)) return true;
  }
  return false;
}


({NodeSpec node, List<StoredWarning> stored})? storedNodeOfEmittedTag(
  String emittedTag,
  List<SubscriptionEntry> entries,
) {
  final owner = ownerOfTag(emittedTag, entries);
  if (owner == null) return null;
  final list = entries[owner.entryIndex].list;
  switch (list) {
    case FolderServers f:
      final mi = owner.memberIndex;
      if (mi == null) return null;
      final m = f.members[mi];
      final n = m.node;
      if (n == null) return null;
      return (node: n, stored: m.warnings);
    case SubscriptionServers sub:
      final candidates = <String>[emittedTag];
      final dedup = RegExp(r'^(.*)-\d+$').firstMatch(emittedTag);
      if (dedup != null) candidates.add(dedup.group(1)!);
      for (final cand in candidates) {
        final bare = TagResolver.stripPrefix(cand, sub.tagPrefix);
        for (final n in sub.nodes) {
          if (n.tag == bare) {
            final id = sourceNodeIdentities(sub.nodes)[n];
            return (
              node: n,
              stored: id == null
                  ? const <StoredWarning>[]
                  : sub.nodeWarnings[id] ?? const <StoredWarning>[],
            );
          }
          for (var hop = n.chained; hop != null; hop = hop.chained) {
            if (hop.tag == bare) {
              final id = sourceNodeIdentities(sub.nodes)[n];
              return (
                node: n,
                stored: id == null
                    ? const <StoredWarning>[]
                    : sub.nodeWarnings[id] ?? const <StoredWarning>[],
              );
            }
          }
        }
      }
      return null;
    case UserServer us:
      if (us.nodes.isEmpty) return null;
      return (node: us.nodes.first, stored: us.warnings);
  }
}

TagOwner? ownerOfNode(NodeSpec node, List<SubscriptionEntry> entries) {
  for (var ei = 0; ei < entries.length; ei++) {
    final list = entries[ei].list;
    switch (list) {
      case FolderServers():
        for (var mi = 0; mi < list.members.length; mi++) {
          final n = list.members[mi].node;
          if (n != null && _nodeOrHop(n, node)) {
            return TagOwner(ei, memberIndex: mi);
          }
        }
      case SubscriptionServers():
      case UserServer():
        if (list.nodes.any((n) => _nodeOrHop(n, node))) {
          return TagOwner(ei);
        }
    }
  }
  return null;
}


NodeSpec? sourceNodeOf(NodeSpec node, ServerList list) {
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
