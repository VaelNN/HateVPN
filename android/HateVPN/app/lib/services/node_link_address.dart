












library;

import '../models/node_link.dart';
import '../models/node_spec.dart';
import '../models/server_list.dart';
import 'node_hash.dart';
import 'tag_resolver.dart';




List<NodeSpec> containerNodes(ServerList l) => switch (l) {
      FolderServers f => [
          for (final m in f.members)
            if (m.node != null) m.node!,
        ],
      _ => l.nodes,
    };



Map<NodeSpec, String> containerRawTags(ServerList l) {
  if (l is SubscriptionServers) return sourceNodeRawTags(l.nodes);
  final out = Map<NodeSpec, String>.identity();
  for (final n in containerNodes(l)) {
    if (n.tag.isNotEmpty) out[n] = n.tag;
  }
  return out;
}


Set<String> containerRawTagSet(ServerList l) =>
    containerRawTags(l).values.toSet();




NodeLink? nodeAddressIn(
  ServerList l,
  NodeSpec node, {
  Map<NodeSpec, String>? raw,
}) {
  if (l is UserServer) {
    if (node.tag.isEmpty) return null;
    return NodeLink(tag: TagResolver.displayTag(l.tagPrefix, node.tag));
  }
  final tag = (raw ?? containerRawTags(l))[node];
  if (tag == null || tag.isEmpty) return null;
  return NodeLink(folderId: l.id, tag: tag);
}


List<NodeLink> sourceNodeAddresses(ServerList l) {
  final raw = l is UserServer ? null : containerRawTags(l);
  return [
    for (final n in containerNodes(l)) ?nodeAddressIn(l, n, raw: raw),
  ];
}


NodeLink? folderMemberAddress(FolderServers f, int index) {
  if (index < 0 || index >= f.members.length) return null;
  final node = f.members[index].node;
  if (node == null) return null;
  return nodeAddressIn(f, node);
}




String containerFinalForm(ServerList l, String rawTag) =>
    TagResolver.displayTag(l.tagPrefix, rawTag);
