

















library;

import '../../models/node_link.dart';
import '../../models/node_spec.dart';
import '../../models/singbox_entry.dart';



final class NodeLinkResolution {
  const NodeLinkResolution.ok(String this.tag) : reason = '';
  const NodeLinkResolution.fail(this.reason) : tag = null;

  final String? tag;
  final String reason;

  bool get ok => tag != null;
}


class NodeLinkTargets {
  final _byFolder = <String, Map<String, String>>{};



  final _groupForms = <String, Map<String, List<String>>>{};



  final _containers = <String, String>{};

  final _rootNodes = <String>{};
  final _rootNames = <String>{};
  final _dropped = <String>{};
  final _linkByFinal = <String, NodeLink>{};


  void noteContainer(String id, String name) => _containers[id] = name;




  void noteMember(String containerId, String rawTag, String finalTag) {
    if (rawTag.isEmpty || finalTag.isEmpty) return;
    final byRaw = _byFolder.putIfAbsent(containerId, () => {});
    if (byRaw.containsKey(rawTag)) return;
    byRaw[rawTag] = finalTag;
    _linkByFinal.putIfAbsent(
        finalTag, () => NodeLink(folderId: containerId, tag: rawTag));
  }



  void noteGroup(
    String containerId,
    String rawTag,
    String finalForm,
    String finalTag,
  ) {
    noteMember(containerId, rawTag, finalTag);
    if (finalTag.isEmpty) return;
    (_groupForms.putIfAbsent(containerId, () => {})[finalForm] ??= [])
        .add(finalTag);
  }


  void noteRootNode(String finalTag) {
    if (finalTag.isEmpty) return;
    _rootNodes.add(finalTag);
    _linkByFinal.putIfAbsent(finalTag, () => NodeLink(tag: finalTag));
  }


  void addRootNames(Iterable<String> tags) {
    for (final t in tags) {
      if (t.isNotEmpty) _rootNames.add(t);
    }
  }



  void markDropped(Iterable<String> finalTags) => _dropped.addAll(finalTags);


  String containerName(String id) {
    final name = _containers[id] ?? '';
    return name.isNotEmpty ? name : id;
  }



  NodeLink linkOfFinal(String finalTag) =>
      _linkByFinal[finalTag] ?? NodeLink(tag: finalTag);



  String? finalOf(NodeLink link) {
    if (link.isRoot) return _rootNodes.contains(link.tag) ? link.tag : null;
    return _byFolder[link.folderId]?[link.tag];
  }


  NodeLinkResolution resolve(NodeLink link) {
    if (link.tag.trim().isEmpty) {
      return const NodeLinkResolution.fail('the reference is empty');
    }
    if (!link.isRoot) {
      if (!_containers.containsKey(link.folderId)) {
        return const NodeLinkResolution.fail('the referenced source is gone');
      }
      var tag = _byFolder[link.folderId]?[link.tag];
      if (tag == null) {


        final forms = _groupForms[link.folderId]?[link.tag];
        if (forms != null && forms.length == 1) tag = forms.single;
      }
      if (tag == null) {
        return NodeLinkResolution.fail('it has no node "${link.tag}"');
      }
      if (_dropped.contains(tag)) {
        return NodeLinkResolution.fail('node "$tag" was skipped by this build');
      }
      return NodeLinkResolution.ok(tag);
    }
    if (_rootNodes.contains(link.tag)) {
      if (_dropped.contains(link.tag)) {
        return NodeLinkResolution.fail(
            'node "${link.tag}" was skipped by this build');
      }
      return NodeLinkResolution.ok(link.tag);
    }
    if (_rootNames.contains(link.tag)) return NodeLinkResolution.ok(link.tag);
    return NodeLinkResolution.fail('target "${link.tag}" is not among nodes, '
        'Directions and folder replacements');
  }


  String describe(NodeLink link) => link.isRoot
      ? '"${link.tag}"'
      : '"${link.tag}" in "${containerName(link.folderId)}"';
}


final class DeferredDetour {
  const DeferredDetour({
    required this.holder,
    required this.link,
    required this.carrier,
    required this.entries,
    required this.node,
  });



  final SingboxEntry holder;

  final NodeLink link;


  final SingboxEntry carrier;


  final List<SingboxEntry> entries;

  final NodeSpec node;
}


final class DeferredDetourReport {
  const DeferredDetourReport({
    required this.droppedEntries,
    required this.droppedNodes,
    required this.warnings,
  });


  final Set<SingboxEntry> droppedEntries;

  final Set<NodeSpec> droppedNodes;


  final List<String> warnings;
}










DeferredDetourReport resolveDeferredDetours(
  List<DeferredDetour> pending,
  NodeLinkTargets targets,
) {
  if (pending.isEmpty) {
    return const DeferredDetourReport(
        droppedEntries: {}, droppedNodes: {}, warnings: []);
  }
  final target = <DeferredDetour, String>{};
  final reason = <DeferredDetour, String>{};

  final ownerOf = <String, DeferredDetour>{};
  for (final p in pending) {
    for (final e in p.entries) {
      ownerOf.putIfAbsent(e.tag, () => p);
    }
  }

  for (final p in pending) {
    final r = targets.resolve(p.link);
    if (!r.ok) {
      reason[p] = r.reason;
    } else if (ownerOf[r.tag] == p) {
      reason[p] = 'the detour points at the node itself';
    } else {
      target[p] = r.tag!;
    }
  }


  for (final p in pending) {
    if (reason.containsKey(p)) continue;
    final seen = <DeferredDetour>{p};
    var cur = p;
    while (true) {
      final t = target[cur];
      final next = t == null ? null : ownerOf[t];
      if (next == null) break;
      if (next == p) {
        reason[p] = 'the detour loops back to this node';
        break;
      }
      if (!seen.add(next)) break;
      cur = next;
    }
  }


  final droppedTags = <String>{
    for (final p in reason.keys)
      for (final e in p.entries) e.tag,
  };
  var changed = true;
  while (changed) {
    changed = false;
    for (final p in pending) {
      if (reason.containsKey(p)) continue;
      final t = target[p];
      if (t != null && droppedTags.contains(t)) {
        reason[p] = 'node "$t" it goes through was skipped';
        for (final e in p.entries) {
          droppedTags.add(e.tag);
        }
        changed = true;
      }
    }
  }



  final carriersByCause = <(String, String), List<String>>{};
  final droppedEntries = Set<SingboxEntry>.identity();
  final droppedNodes = Set<NodeSpec>.identity();
  for (final p in pending) {
    final why = reason[p];
    if (why == null) {
      p.holder.map['detour'] = target[p];
      continue;
    }
    droppedEntries.addAll(p.entries);
    droppedNodes.add(p.node);
    final carriers =
        carriersByCause.putIfAbsent((targets.describe(p.link), why), () => []);
    if (!carriers.contains(p.carrier.tag)) carriers.add(p.carrier.tag);
  }
  targets.markDropped(droppedTags);
  return DeferredDetourReport(
    droppedEntries: droppedEntries,
    droppedNodes: droppedNodes,
    warnings: [
      for (final e in carriersByCause.entries)
        _unresolvedDetourLine(e.value, e.key.$1, e.key.$2),
    ],
  );
}



String _unresolvedDetourLine(List<String> carriers, String link, String why) {
  const tail = 'is not emitted, so its traffic never goes direct.';
  if (carriers.length == 1) {
    return 'Node "${carriers.single}" was skipped: its detour $link did not '
        'resolve — $why. A node whose detour does not resolve $tail';
  }
  const shown = 5;
  final head = carriers.take(shown).map((c) => '"$c"').join(', ');
  final rest = carriers.length - shown;
  return '${carriers.length} nodes ($head${rest > 0 ? ', and $rest more' : ''}) '
      'were skipped: their detour $link did not resolve — $why. A node whose '
      'detour does not resolve $tail';
}
