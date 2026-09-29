part of '../post_steps.dart';





















































































List<String> sanitizeOutboundGraph(
  Map<String, dynamic> config, {
  Set<String> directionTags = const {},
  String blockTag = kBlockOutboundTag,
  String directTag = kDirectOutboundTag,
}) {
  final outbounds = (config['outbounds'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();
  final endpoints = (config['endpoints'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();
  final entries = [...outbounds, ...endpoints];
  if (entries.isEmpty) return const [];

  final warnings = <String>[];



  final danglingDetourOwners = <String, List<String>>{};



  final sanitizedDetourOwners = <String, List<String>>{};


  final droppedTags = <String>{};




  final cyclicMemberGroups = <String, List<String>>{};


  final blockedDirections = <String>[];

  final byTag = <String, Map<String, dynamic>>{};
  for (final e in entries) {
    final tag = e['tag'];
    if (tag is String && tag.isNotEmpty) byTag[tag] = e;
  }
  final dropped = <Map<String, dynamic>>{};














  bool alive(String tag) {
    final e = byTag[tag];
    return e != null && !dropped.contains(e);
  }

  void dropEntry(Map<String, dynamic> e, String why) {
    if (!dropped.add(e)) return;
    droppedTags.add(_tagOf(e));
    warnings.add('Outbound "${_tagOf(e)}" removed from the config: $why');
  }

  final limit = entries.length * 4 + 8;
  for (var iter = 0; iter < limit; iter++) {
    var changed = false;
    for (final e in entries) {
      if (dropped.contains(e)) continue;
      if (_sanitizeEntryRefs(
        e,
        alive: alive,
        byTag: byTag,
        dropped: dropped,
        drop: dropEntry,
        warnings: warnings,
        danglingDetourOwners: danglingDetourOwners,
        sanitizedDetourOwners: sanitizedDetourOwners,
        droppedTags: droppedTags,
        cyclicMemberGroups: cyclicMemberGroups,
        blockedDirections: blockedDirections,
        directionTags: directionTags,
        blockTag: blockTag,
        directTag: directTag,
      )) {
        changed = true;
      }
    }
    if (_pruneChainLeavesUnderGroups(
      entries,
      alive: alive,
      byTag: byTag,
      dropped: dropped,
      warnings: warnings,
    )) {
      changed = true;
    }
    if (_breakDependencyCycle(
      entries,
      alive: alive,
      byTag: byTag,
      dropped: dropped,
      warnings: warnings,
    )) {
      changed = true;
    }
    if (!changed) break;
  }













  for (final dirTag in blockedDirections) {
    final riders = <String>[];
    for (final e in entries) {
      if (dropped.contains(e)) continue;
      if (e['detour'] == dirTag) {
        final owner = _tagOf(e);
        if (owner.isNotEmpty && !riders.contains(owner)) riders.add(owner);
      }
    }
    if (riders.isEmpty) continue;
    warnings.add(_blockedDetourRidersLine(dirTag, riders));
  }

  for (final e in cyclicMemberGroups.entries) {
    warnings.add(_detourGroupCycleLine(e.key, e.value));
  }
  for (final e in danglingDetourOwners.entries) {
    warnings.add(_detourRemovedLine(e.key, e.value));
  }
  for (final e in sanitizedDetourOwners.entries) {
    warnings.add(_detourRemovedLine(e.key, e.value, targetSanitized: true));
  }



  for (final e in entries) {
    if (!dropped.contains(e)) _sanitizeUrltestTimings(e, warnings);
  }




  if (dropped.isNotEmpty) {
    for (final key in const ['outbounds', 'endpoints']) {
      final list = config[key];
      if (list is List) {
        list.removeWhere((o) => o is Map<String, dynamic> && dropped.contains(o));
      }
    }
  }
  return warnings;
}

String _tagOf(Map<String, dynamic> e) => e['tag'] as String? ?? '';





bool _isGroup(Map<String, dynamic> e) {
  final t = e['type'];
  return t == 'selector' || t == 'urltest';
}



bool _isChain(Map<String, dynamic> e) => e['type'] == kChainOutboundType;





enum _EdgeKind { detour, member, chainHop }

List<String> _membersOf(Map<String, dynamic> e) =>
    (e['outbounds'] as List<dynamic>? ?? const []).whereType<String>().toList();

void _setMembers(Map<String, dynamic> e, List<String> members) {
  e['outbounds'] = members;
}


bool _sanitizeEntryRefs(
  Map<String, dynamic> e, {
  required bool Function(String) alive,
  required Map<String, Map<String, dynamic>> byTag,
  required Set<Map<String, dynamic>> dropped,
  required void Function(Map<String, dynamic>, String) drop,
  required List<String> warnings,
  required Map<String, List<String>> danglingDetourOwners,
  required Map<String, List<String>> sanitizedDetourOwners,
  required Set<String> droppedTags,
  required Map<String, List<String>> cyclicMemberGroups,
  required List<String> blockedDirections,
  required Set<String> directionTags,
  required String blockTag,
  required String directTag,
}) {
  var changed = false;
  final tag = _tagOf(e);


  final detour = e['detour'];
  if (detour is String && detour.isNotEmpty && !alive(detour)) {
    e.remove('detour');




    final bucket =
        droppedTags.contains(detour) ? sanitizedDetourOwners : danglingDetourOwners;
    (bucket[detour] ??= []).add(tag);
    changed = true;
  }

















  if (_isChain(e)) {
    final hops = _membersOf(e);
    for (var i = 0; i < hops.length; i++) {
      final ref = hops[i];
      if (!alive(ref)) {
        drop(
            e,
            'hop "$ref" (position ${i + 1}) does not exist in the final '
                'config — a route without a hop would be a different route');
        return true;
      }
      if (i >= 1) {
        final t = byTag[ref];
        if (t != null && !dropped.contains(t) && _isChain(t)) {
          drop(
              e,
              'nested chain "$ref" is at position ${i + 1} — the core allows '
                  'a nested chain only as the first hop');
          return true;
        }
      }
    }
    return changed;
  }

  if (!_isGroup(e)) return changed;

  final members = _membersOf(e);
  final kept = <String>[];
  final lost = <String>[];



















  final cyclic = <String>[];
  for (final ref in members) {
    if (!alive(ref)) {
      if (!lost.contains(ref)) lost.add(ref);
      continue;
    }


    final m = byTag[ref];
    if (m != null && _detourReaches(m, tag, byTag, alive)) {
      if (!cyclic.contains(ref)) cyclic.add(ref);
      continue;
    }
    if (!kept.contains(ref)) kept.add(ref);
  }

  if (lost.isNotEmpty) {
    warnings.add(
        'Group "$tag": members ${_quotedList(lost)} do not exist in the final '
        'config — excluded from the group.');
    changed = true;
  }
  if (cyclic.isNotEmpty) {

    for (final ref in cyclic) {
      final groups = cyclicMemberGroups[ref] ??= [];
      if (!groups.contains(tag)) groups.add(tag);
    }
    changed = true;
  }
  if (lost.isNotEmpty || cyclic.isNotEmpty || kept.length != members.length) {
    _setMembers(e, kept);
    changed = true;
  }


  if (kept.isEmpty) {
    if (directionTags.contains(tag) && e['type'] == 'selector') {





      _setMembers(e, [blockTag, directTag]);
      e['default'] = blockTag;
      if (!blockedDirections.contains(tag)) blockedDirections.add(tag);
      warnings.add(
          'Direction "$tag": no members left after graph sanitation — traffic '
          'is blocked (default).');
      return true;
    }
    drop(e, 'no members left');
    return true;
  }




  final def = e['default'];
  if (def is String && def.isNotEmpty && !kept.contains(def)) {
    warnings.add(
        'Group "$tag": default "$def" is not among its members — replaced '
        'with "${kept.first}".');
    e['default'] = kept.first;
    changed = true;
  }
  return changed;
}









bool _detourReaches(
  Map<String, dynamic> node,
  String target,
  Map<String, Map<String, dynamic>> byTag,
  bool Function(String) alive,
) {
  final d = node['detour'];
  if (d is! String || d.isEmpty) return false;
  final seen = <String>{};
  final queue = <String>[d];
  while (queue.isNotEmpty) {
    final tag = queue.removeLast();
    if (tag == target) return true;
    if (!seen.add(tag) || !alive(tag)) continue;
    final e = byTag[tag];
    if (e == null || !_isGroup(e)) continue;
    queue.addAll(_membersOf(e));
  }
  return false;
}




















bool _pruneChainLeavesUnderGroups(
  List<Map<String, dynamic>> entries, {
  required bool Function(String) alive,
  required Map<String, Map<String, dynamic>> byTag,
  required Set<Map<String, dynamic>> dropped,
  required List<String> warnings,
}) {

  final queue = <String>[];
  final seen = <String>{};
  for (final e in entries) {
    if (dropped.contains(e) || !_isChain(e)) continue;
    final hops = _membersOf(e);
    for (var i = 1; i < hops.length; i++) {
      final ref = hops[i];
      final t = byTag[ref];
      if (t != null && !dropped.contains(t) && _isGroup(t) && seen.add(ref)) {
        queue.add(ref);
      }
    }
  }
  var changed = false;
  while (queue.isNotEmpty) {
    final tag = queue.removeAt(0);
    final g = byTag[tag];
    if (g == null || dropped.contains(g)) continue;
    final kept = <String>[];
    final lost = <String>[];
    for (final ref in _membersOf(g)) {
      final t = byTag[ref];
      if (t != null && !dropped.contains(t) && _isChain(t)) {
        if (!lost.contains(ref)) lost.add(ref);
        continue;
      }
      if (t != null && !dropped.contains(t) && _isGroup(t) && seen.add(ref)) {
        queue.add(ref);
      }
      kept.add(ref);
    }
    if (lost.isNotEmpty) {
      warnings.add(
          'Group "$tag" is used as a hop (position 2 or later) of a chain, so '
          'chains ${_quotedList(lost)} were excluded from it — the core allows '
          'a nested chain only as the first hop and would fail to start.');
      _setMembers(g, kept);
      changed = true;
    }
  }
  return changed;
}























bool _breakDependencyCycle(
  List<Map<String, dynamic>> entries, {
  required bool Function(String) alive,
  required Map<String, Map<String, dynamic>> byTag,
  required Set<Map<String, dynamic>> dropped,
  required List<String> warnings,
}) {


  final nodes = <String>[];
  final detourEdge = <String, String>{};
  final memberEdges = <String, List<String>>{};
  final chainOwners = <String>{};
  for (final e in entries) {
    if (dropped.contains(e)) continue;
    final tag = _tagOf(e);
    if (tag.isEmpty) continue;
    nodes.add(tag);
    final d = e['detour'];
    if (d is String && d.isNotEmpty && byTag[d] != null && !dropped.contains(byTag[d]!)) {
      detourEdge[tag] = d;
    }



    if (_isGroup(e) || _isChain(e)) {
      final live = [
        for (final m in _membersOf(e))
          if (byTag[m] != null && !dropped.contains(byTag[m]!)) m,
      ];
      if (live.isNotEmpty) memberEdges[tag] = live;
      if (_isChain(e)) chainOwners.add(tag);
    }
  }

  Set<String> cyclicWithout(({String from, String ref, _EdgeKind kind})? cut) =>
      _cyclicGraphNodes(nodes, detourEdge, memberEdges, cut);

  final cyclic = cyclicWithout(null);
  if (cyclic.isEmpty) return false;



  final candidates = <({String from, String ref, _EdgeKind kind})>[];
  for (final tag in nodes) {
    if (!cyclic.contains(tag)) continue;
    final d = detourEdge[tag];
    if (d != null && cyclic.contains(d)) {
      candidates.add((from: tag, ref: d, kind: _EdgeKind.detour));
    }
    final kind =
        chainOwners.contains(tag) ? _EdgeKind.chainHop : _EdgeKind.member;
    for (final m in memberEdges[tag] ?? const <String>[]) {
      if (cyclic.contains(m)) {
        candidates.add((from: tag, ref: m, kind: kind));
      }
    }
  }
  candidates.sort((a, b) {
    final c = a.from.compareTo(b.from);
    return c != 0 ? c : a.ref.compareTo(b.ref);
  });
  if (candidates.isEmpty) return false;

  var best = candidates.first;
  var bestScore = -1;
  for (final c in candidates) {
    final score = cyclic.length - cyclicWithout(c).length;
    if (score > bestScore) {
      bestScore = score;
      best = c;
    }
  }
  if (bestScore <= 0) return false;

  final from = byTag[best.from]!;
  switch (best.kind) {
    case _EdgeKind.detour:
      warnings.add(
          'Dependency cycle through detour "${best.from}" → "${best.ref}" — '
          'detour removed (the node dials directly).');
      from.remove('detour');
    case _EdgeKind.member:
      warnings.add(
          'Dependency cycle: "${best.ref}" excluded from group "${best.from}".');
      _setMembers(
          from, [for (final m in _membersOf(from)) if (m != best.ref) m]);
    case _EdgeKind.chainHop:



      dropped.add(from);
      warnings.add(
          'Outbound "${best.from}" removed from the config: dependency cycle '
          'through hop "${best.ref}" — a route without that hop would be a '
          'different route.');
  }
  return true;
}






Set<String> _cyclicGraphNodes(
  List<String> nodes,
  Map<String, String> detourEdge,
  Map<String, List<String>> memberEdges,
  ({String from, String ref, _EdgeKind kind})? cut,
) {
  List<String> adjOf(String u) => [
        for (final m in memberEdges[u] ?? const <String>[])
          if (!(cut != null &&
              cut.kind != _EdgeKind.detour &&
              cut.from == u &&
              cut.ref == m))
            m,
        if (detourEdge[u] != null &&
            !(cut != null && cut.kind == _EdgeKind.detour && cut.from == u))
          detourEdge[u]!,
      ];

  final index = <String, int>{};
  final low = <String, int>{};
  final onStack = <String>{};
  final stack = <String>[];
  final cyclic = <String>{};
  var counter = 0;

  for (final root in nodes) {
    if (index.containsKey(root)) continue;
    final work = <(String, int)>[(root, 0)];
    while (work.isNotEmpty) {
      final (v, pi) = work.last;
      if (pi == 0) {
        index[v] = low[v] = counter++;
        stack.add(v);
        onStack.add(v);
      }
      var recursed = false;
      final adj = adjOf(v);
      for (var i = pi; i < adj.length; i++) {
        final w = adj[i];
        if (!index.containsKey(w)) {
          work.last = (v, i + 1);
          work.add((w, 0));
          recursed = true;
          break;
        } else if (onStack.contains(w)) {
          low[v] = low[v]!.compareTo(index[w]!) < 0 ? low[v]! : index[w]!;
        }
      }
      if (recursed) continue;
      if (low[v] == index[v]) {
        final comp = <String>[];
        while (true) {
          final w = stack.removeLast();
          onStack.remove(w);
          comp.add(w);
          if (w == v) break;
        }
        if (comp.length > 1) {
          cyclic.addAll(comp);
        } else if (adjOf(comp.single).contains(comp.single)) {
          cyclic.add(comp.single);
        }
      }
      work.removeLast();
      if (work.isNotEmpty) {
        final (u, upi) = work.last;
        low[u] = low[u]!.compareTo(low[v]!) < 0 ? low[u]! : low[v]!;
        work.last = (u, upi);
      }
    }
  }
  return cyclic;
}

String _quotedList(List<String> tags) => tags.map((t) => '"$t"').join(', ');














String _blockedDetourRidersLine(String dirTag, List<String> riders) {
  const shown = 5;
  final head = riders.take(shown).map((r) => '"$r"').join(', ');
  final rest = riders.length - shown;
  final subject = riders.length == 1
      ? 'Outbound $head still detours'
      : '${riders.length} outbounds ($head${rest > 0 ? ', and $rest more' : ''}) '
          'still detour';
  return '$subject through direction "$dirTag", which is now blocked — '
      '${riders.length == 1 ? 'its' : 'their'} traffic is blocked too. The '
      'detour is kept on purpose: dropping it would send that traffic outside '
      'the VPN.';
}





String _detourGroupCycleLine(String node, List<String> groups) {
  final subject = groups.length == 1
      ? 'group ${_quotedList(groups)}'
      : 'groups ${_quotedList(groups)}';
  return 'Outbound "$node" detours through $subject it belongs to — excluded '
      'from ${groups.length == 1 ? 'it' : 'them'} (its detour is kept; '
      'otherwise the kernel would not start: dependency cycle).';
}

String _detourRemovedLine(String target, List<String> owners,
    {bool targetSanitized = false}) {
  const shown = 5;
  final head = owners.take(shown).map((o) => '"$o"').join(', ');
  final rest = owners.length - shown;
  final subject = owners.length == 1
      ? 'outbound $head'
      : '${owners.length} outbounds ($head${rest > 0 ? ', and $rest more' : ''})';
  final works = owners.length == 1 ? 'node works' : 'nodes work';


  if (targetSanitized) {
    return 'Detour removed: $subject pointed at "$target", which was left '
        'with no members and removed during sanitation — $works directly.';
  }
  return 'Detour removed: $subject referenced missing "$target" — '
      '$works directly.';
}
