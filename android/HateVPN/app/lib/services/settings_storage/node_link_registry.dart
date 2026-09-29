

















library;

import '../../models/auto_select.dart';
import '../../models/node_link.dart';
import '../../models/node_spec.dart';
import '../../models/server_list.dart';
import '../../models/source_chain.dart';
import '../node_link_address.dart';


final class NodeLinkChange {
  const NodeLinkChange({
    required this.lists,
    required this.chains,
    this.detourCarriers = const [],
    this.touchedGroups = const [],
    this.groupMembers = 0,
    this.touchedChains = const [],
    this.positions = 0,
  });


  final List<ServerList> lists;


  final List<SourceChain> chains;





  final List<String> detourCarriers;


  final List<String> touchedGroups;


  final int groupMembers;


  final List<String> touchedChains;


  final int positions;

  bool get isEmpty =>
      detourCarriers.isEmpty && groupMembers == 0 && positions == 0;

  bool get chainsChanged => positions > 0;
}








({Map<NodeLink, NodeLink> moves, Set<NodeLink> gone}) diffNodeAddresses(
  List<ServerList> before,
  List<ServerList> after, {
  Map<NodeSpec, NodeSpec> renamed = const {},
}) {
  final was = _addresses(before);
  final now = _addresses(after);
  final moves = <NodeLink, NodeLink>{};
  final gone = <NodeLink>{};
  final kept = <NodeLink>{};
  was.forEach((node, address) {
    final successor = renamed[node] ?? node;
    final next = now[successor];
    if (next == null) {
      gone.add(address);
    } else if (next != address) {
      moves[address] = next;
    } else {
      kept.add(address);
    }
  });


  gone.removeAll(kept);
  return (moves: moves, gone: gone);
}


typedef NodeLinkRelink = ({
  List<ServerList> lists,
  List<SourceChain> chains,
  NodeLinkChange cleared,
  NodeLinkChange rewritten,
});






NodeLinkRelink relinkNodeLinks(
  List<ServerList> lists,
  List<SourceChain> chains, {
  Map<NodeLink, NodeLink> moves = const {},
  Set<NodeLink> gone = const {},
  Set<String> goneContainers = const {},
}) {
  final cleared = (gone.isEmpty && goneContainers.isEmpty)
      ? NodeLinkChange(lists: lists, chains: chains)
      : clearNodeLinks(
          lists,
          chains,
          (l) =>
              gone.contains(l) ||
              (!l.isRoot && goneContainers.contains(l.folderId)),
        );
  final rewritten = rewriteNodeLinks(cleared.lists, cleared.chains, moves);
  return (
    lists: rewritten.lists,
    chains: rewritten.chains,
    cleared: cleared,
    rewritten: rewritten,
  );
}

Map<NodeSpec, NodeLink> _addresses(List<ServerList> lists) {
  final out = Map<NodeSpec, NodeLink>.identity();
  for (final l in lists) {
    final raw = l is UserServer ? null : containerRawTags(l);
    for (final n in containerNodes(l)) {
      final a = nodeAddressIn(l, n, raw: raw);
      if (a != null) out[n] = a;
    }
  }
  return out;
}




NodeLinkChange rewriteNodeLinks(
  List<ServerList> lists,
  List<SourceChain> chains,
  Map<NodeLink, NodeLink> moves,
) {
  if (moves.isEmpty) return NodeLinkChange(lists: lists, chains: chains);
  return _mapLinks(lists, chains, (l) => moves[l], dropHop: false);
}



NodeLinkChange clearNodeLinks(
  List<ServerList> lists,
  List<SourceChain> chains,
  bool Function(NodeLink link) isGone,
) =>
    _mapLinks(lists, chains, (l) => isGone(l) ? NodeLink.none : null,
        dropHop: true);



NodeLinkChange _mapLinks(
  List<ServerList> lists,
  List<SourceChain> chains,
  NodeLink? Function(NodeLink link) replace, {
  required bool dropHop,
}) {
  final carriers = <String>[];
  final groups = <String>[];
  var groupMembers = 0;
  NodeLink? swap(NodeLink l) {
    if (l.isEmpty) return null;
    final next = replace(l);
    return next == null || next == l ? null : next;
  }

  final outLists = <ServerList>[];
  for (final l in lists) {
    var next = l;
    final override = swap(l.detourPolicy.overrideDetour);
    if (override != null) {
      final p = l.detourPolicy.copyWith(overrideDetour: override);
      next = switch (l) {
        SubscriptionServers s => s.copyWith(detourPolicy: p),
        UserServer u => u.copyWith(detourPolicy: p),
        FolderServers f => f.copyWith(detourPolicy: p),
      };
      carriers.add(_sourceName(l));
    }
    if (next is FolderServers) {
      final folderId = next.id;
      var changed = false;
      final members = <FolderMember>[];
      for (final m in next.members) {
        var member = m;
        final d = swap(m.detour);
        if (d != null) {
          member = member.copyWith(detour: d);
          carriers.add(m.node?.tag ?? '');
        }
        final group = _mapGroupMembers(member, folderId, swap, dropHop);
        if (group != null) {
          member = group.member;
          groups.add(m.node?.tag ?? '');
          groupMembers += group.hits;
        }
        if (!identical(member, m)) changed = true;
        members.add(member);
      }
      if (changed) next = next.copyWith(members: members);
    }
    outLists.add(next);
  }

  var positions = 0;
  final touched = <String>[];
  final outChains = <SourceChain>[];
  for (final c in chains) {
    var hit = false;
    final hops = <NodeLink>[];
    for (final h in c.hops) {
      final next = swap(h);
      if (next == null) {
        hops.add(h);
        continue;
      }
      hit = true;
      positions++;
      if (!(dropHop && next.isEmpty)) hops.add(next);
    }
    if (!hit) {
      outChains.add(c);
      continue;
    }
    touched.add(c.displayLabel);
    outChains.add(c.copyWith(hops: hops));
  }

  return NodeLinkChange(
    lists: outLists,
    chains: outChains,
    detourCarriers: carriers,
    touchedGroups: groups,
    groupMembers: groupMembers,
    touchedChains: touched,
    positions: positions,
  );
}





({FolderMember member, int hits})? _mapGroupMembers(
  FolderMember m,
  String folderId,
  NodeLink? Function(NodeLink link) swap,
  bool drop,
) {
  final g = m.node;
  if (g is! AutoSelectSpec) return null;
  final membership = g.membership;
  if (membership is! ExplicitMembers) return null;
  var hits = 0;
  final links = <NodeLink>[];
  for (final l in membership.members) {
    final address = l.isRoot ? NodeLink(folderId: folderId, tag: l.tag) : l;
    final next = swap(address);
    if (next == null) {
      links.add(l);
      continue;
    }
    hits++;
    if (!(drop && next.isEmpty)) links.add(next);
  }
  if (hits == 0) return null;
  return (
    member: FolderMember.auto(
      g.copyWith(membership: ExplicitMembers(links)),
      enabled: m.enabled,
    ),
    hits: hits,
  );
}

String _sourceName(ServerList l) => switch (l) {
      UserServer u => u.nodes.isNotEmpty
          ? containerFinalForm(u, u.nodes.first.tag)
          : u.name,
      SubscriptionServers s when s.name.isEmpty =>
        Uri.tryParse(s.url)?.host ?? s.url,
      _ => l.name,
    };
