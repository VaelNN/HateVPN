












library;

import '../../models/node_spec.dart';
import '../../models/server_list.dart';
import '../node_link_address.dart';
import '../tag_resolver.dart';






String tailscaleStateDirName(String finalTag) {
  final cleaned =
      finalTag.replaceAll(RegExp(r'[^A-Za-z0-9._-]', unicode: true), '_');
  return cleaned.isEmpty ? 'tailscale' : cleaned;
}


final class TailscaleStateNode {
  const TailscaleStateNode({
    required this.node,
    required this.key,
    required this.baseName,
  });

  final TailscaleSpec node;


  final String key;




  final String baseName;
}


final class TailscaleStateScan {
  const TailscaleStateScan({
    required this.nodes,
    required this.unresolvedContainers,
    required this.explicitDirs,
  });


  final List<TailscaleStateNode> nodes;




  final Set<String> unresolvedContainers;



  final Set<String> explicitDirs;

  Set<String> get keys => {for (final n in nodes) n.key};
}


TailscaleStateScan scanTailscaleStateNodes(List<ServerList> lists) {
  final nodes = <TailscaleStateNode>[];
  final unresolved = <String>{};
  final explicit = <String>{};

  String? explicitDir(TailscaleSpec node) {
    final v = node.body['state_directory'];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  for (final l in lists) {
    switch (l) {
      case UserServer u:
        if (u.nodes.isEmpty) unresolved.add(u.id);
        var n = 0;
        for (final node in u.nodes) {
          if (node is! TailscaleSpec) continue;
          n++;
          final own = explicitDir(node);
          if (own != null) {
            explicit.add(own);
            continue;
          }
          nodes.add(TailscaleStateNode(
            node: node,
            key: n == 1 ? u.id : '${u.id}#$n',
            baseName: tailscaleStateDirName(
                TagResolver.displayTag(u.tagPrefix, node.tag)),
          ));
        }
      case FolderServers():
      case SubscriptionServers():
        if (l is SubscriptionServers && l.nodes.isEmpty) unresolved.add(l.id);
        if (l is FolderServers && l.members.any((m) => m.node == null)) {
          unresolved.add(l.id);
        }
        final raw = containerRawTags(l);
        final counts = <String, int>{};
        for (final node in containerNodes(l)) {
          if (node is! TailscaleSpec) continue;
          final tag = raw[node];
          if (tag == null || tag.isEmpty) {
            unresolved.add(l.id);
            continue;
          }
          final c = counts[tag] = (counts[tag] ?? 0) + 1;
          final own = explicitDir(node);
          if (own != null) {
            explicit.add(own);
            continue;
          }
          nodes.add(TailscaleStateNode(
            node: node,
            key: c == 1 ? '${l.id}/$tag' : '${l.id}/$tag#$c',
            baseName: tailscaleStateDirName(
                TagResolver.displayTag(l.tagPrefix, node.tag)),
          ));
        }
    }
  }
  return TailscaleStateScan(
    nodes: nodes,
    unresolvedContainers: unresolved,
    explicitDirs: explicit,
  );
}


bool hasTailscaleNodes(List<ServerList> lists) {
  for (final l in lists) {
    for (final n in containerNodes(l)) {
      if (n is TailscaleSpec) return true;
    }
  }
  return false;
}


bool tailscaleKeyInContainer(String key, String id) =>
    key == id || key.startsWith('$id/') || key.startsWith('$id#');








({
  Map<String, String> moves,
  Set<String> gone,
  Set<String> goneContainers,
}) diffTailscaleStateKeys(
  List<ServerList> before,
  List<ServerList> after, {
  Map<NodeSpec, NodeSpec> renamed = const {},
}) {
  Map<NodeSpec, String> keysOf(List<ServerList> lists) {
    final out = Map<NodeSpec, String>.identity();
    for (final n in scanTailscaleStateNodes(lists).nodes) {
      out[n.node] = n.key;
    }
    return out;
  }

  final was = keysOf(before);
  final now = keysOf(after);
  final moves = <String, String>{};
  final gone = <String>{};
  was.forEach((node, key) {
    final next = now[renamed[node] ?? node];
    if (next == null) {
      gone.add(key);
    } else if (next != key) {
      moves[key] = next;
    }
  });
  final afterIds = {for (final l in after) l.id};
  return (
    moves: moves,
    gone: gone,
    goneContainers: {
      for (final l in before)
        if (!afterIds.contains(l.id)) l.id,
    },
  );
}
