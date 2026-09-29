import '../../models/validation.dart';




const kMaxDetourCulprits = 3;













ValidationResult validateConfig(Map<String, dynamic> config) {
  final issues = <ValidationIssue>[];

  final outbounds = (config['outbounds'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();
  final endpoints = (config['endpoints'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();

  final allTags = <String>{
    for (final o in outbounds) o['tag'] as String? ?? '',
    for (final e in endpoints) e['tag'] as String? ?? '',
  }..remove('');


  final rules = (config['route']?['rules'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>();
  var ruleIdx = 0;
  for (final r in rules) {
    final outRef = r['outbound'];
    if (outRef is String && outRef.isNotEmpty && !allTags.contains(outRef)) {
      issues.add(DanglingOutboundRef('rules[$ruleIdx]', outRef));
    }
    ruleIdx++;
  }






  final routeFinal = config['route']?['final'];
  if (routeFinal is String &&
      routeFinal.isNotEmpty &&
      !allTags.contains(routeFinal)) {
    issues.add(DanglingOutboundRef('route.final', routeFinal));
  }






  final detourEdge = <String, String>{};
  for (final o in [...outbounds, ...endpoints]) {
    final detour = o['detour'];
    if (detour is! String || detour.isEmpty) continue;
    final owner = o['tag'] as String? ?? '';
    if (!allTags.contains(detour)) {
      issues.add(DanglingDetourRef(owner, detour));
    } else if (owner.isNotEmpty) {
      detourEdge[owner] = detour;
    }
  }














  final groupMembers = <String, List<String>>{};
  for (final o in outbounds) {
    final type = o['type'] as String? ?? '';
    if (type != 'selector' && type != 'urltest') continue;
    final tag = o['tag'] as String? ?? '';
    if (tag.isEmpty) continue;
    final members = (o['outbounds'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .where(allTags.contains)
        .toList();
    if (members.isNotEmpty) groupMembers[tag] = members;
  }
  issues.addAll(
    _detectDetourCycles(detourEdge: detourEdge, groupMembers: groupMembers),
  );


  final dns = config['dns'];
  final dnsServerTags = <String>{
    for (final s
        in (dns?['servers'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>())
      s['tag'] as String? ?? '',
  }..remove('');
  final dnsFinal = dns?['final'];
  if (dnsFinal is String &&
      dnsFinal.isNotEmpty &&
      !dnsServerTags.contains(dnsFinal)) {
    issues.add(DanglingDnsServerRef('dns.final', dnsFinal));
  }
  final domainResolver = config['route']?['default_domain_resolver'];
  if (domainResolver is String &&
      domainResolver.isNotEmpty &&
      !dnsServerTags.contains(domainResolver)) {
    issues.add(
      DanglingDnsServerRef('route.default_domain_resolver', domainResolver),
    );
  }





  final dnsServerList = (dns?['servers'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();
  final dnsTypeByTag = <String, String>{
    for (final s in dnsServerList)
      if (s['tag'] is String && (s['tag'] as String).isNotEmpty)
        s['tag'] as String: s['type'] as String? ?? '',
  };




  for (final ref in <(String, Object?)>[
    ('dns.final', dnsFinal),
    ('route.default_domain_resolver', domainResolver),
  ]) {
    final (field, value) = ref;
    if (value is! String || value.isEmpty) continue;
    final type = dnsTypeByTag[value];
    if (type == 'fakeip' || type == 'hosts') {
      issues.add(BadResolverServerType(field, value, type!));
    }
  }

  final dnsGroupEdges = <String, List<String>>{};
  for (final s in dnsServerList) {
    if (s['type'] != 'group') continue;
    final tag = s['tag'] as String? ?? '';
    if (tag.isEmpty) continue;
    final members = (s['servers'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    if (members.isEmpty) {
      issues.add(EmptyDnsGroup(tag));
      continue;
    }
    for (final m in members) {
      final mt = dnsTypeByTag[m];
      if (mt == 'fakeip' || mt == 'hosts') {
        issues.add(BadDnsGroupMember(tag, m, mt!));
      }
    }

    dnsGroupEdges[tag] = [
      for (final m in members)
        if (dnsTypeByTag[m] == 'group') m,
    ];
  }
  issues.addAll(_findDnsGroupCycles(dnsGroupEdges));


  for (final o in outbounds) {
    final type = o['type'] as String? ?? '';
    final tag = o['tag'] as String? ?? '';
    final opts = (o['outbounds'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    if (type == 'urltest' && opts.isEmpty) {
      issues.add(EmptyUrltestGroup(tag));
    }
    if (type == 'selector') {
      final def = o['default'];


      if (def != null && (def is! String || !opts.contains(def))) {
        issues.add(InvalidDefault(tag, def.toString()));
      }
    }
  }

  return ValidationResult(issues);
}



























List<DetourCycle> _detectDetourCycles({
  required Map<String, String> detourEdge,
  required Map<String, List<String>> groupMembers,
}) {
  final nodes = <String>{
    ...detourEdge.keys,
    ...detourEdge.values,
    ...groupMembers.keys,
    for (final ms in groupMembers.values) ...ms,
  };
  if (nodes.isEmpty) return const [];

  final initialCyclic = _cyclicNodes(nodes, detourEdge, groupMembers, const {});
  if (initialCyclic.isEmpty) return const [];






  final removed = <String>{};
  final culprits = <String>[];
  final structuralCycles = <List<String>>[];
  while (culprits.length < kMaxDetourCulprits) {
    final cyclic = _cyclicNodes(nodes, detourEdge, groupMembers, removed);
    if (cyclic.isEmpty) break;
    final candidates =
        detourEdge.keys
            .where(
              (u) =>
                  !removed.contains(u) &&
                  cyclic.contains(u) &&
                  cyclic.contains(detourEdge[u]),
            )
            .toList()
          ..sort();
    var best = candidates.isEmpty ? null : candidates.first;
    var bestScore = 0;
    for (final u in candidates) {
      final after = _cyclicNodes(nodes, detourEdge, groupMembers, {
        ...removed,
        u,
      });
      final score = cyclic.length - after.length;
      if (score > bestScore) {
        bestScore = score;
        best = u;
      }
    }
    if (best == null || bestScore <= 0) {





      structuralCycles.add(cyclic.toList()..sort());
      break;
    }
    removed.add(best);
    culprits.add(best);
  }






  final undirected = <String, Set<String>>{};
  void link(String a, String b) {
    if (!initialCyclic.contains(a) || !initialCyclic.contains(b)) return;
    (undirected[a] ??= {}).add(b);
    (undirected[b] ??= {}).add(a);
  }

  for (final e in detourEdge.entries) {
    link(e.key, e.value);
  }
  for (final g in groupMembers.entries) {
    for (final m in g.value) {
      link(g.key, m);
    }
  }

  final componentOf = <String, int>{};
  var compId = 0;
  for (final start in initialCyclic) {
    if (componentOf.containsKey(start)) continue;
    final queue = [start];
    componentOf[start] = compId;
    while (queue.isNotEmpty) {
      final u = queue.removeLast();
      for (final v in undirected[u] ?? const <String>{}) {
        if (componentOf.containsKey(v)) continue;
        componentOf[v] = compId;
        queue.add(v);
      }
    }
    compId++;
  }

  final byComponent = <int, List<String>>{};
  for (final c in culprits) {
    (byComponent[componentOf[c] ?? -1] ??= []).add(c);
  }

  return [
    for (final group in byComponent.values)
      DetourCycle(
        _representativeCycle(group.first, detourEdge, groupMembers),
        culprits: [
          for (final tag in group) (tag: tag, detour: detourEdge[tag]!),
        ],
      ),


    for (final cycle in structuralCycles) DetourCycle(cycle),
  ];
}



Set<String> _cyclicNodes(
  Set<String> nodes,
  Map<String, String> detourEdge,
  Map<String, List<String>> groupMembers,
  Set<String> removed,
) {
  List<String> adjOf(String u) => [
    ...?groupMembers[u],
    if (!removed.contains(u) && detourEdge.containsKey(u)) detourEdge[u]!,
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




List<String> _representativeCycle(
  String culprit,
  Map<String, String> detourEdge,
  Map<String, List<String>> groupMembers,
) {
  final target = detourEdge[culprit]!;
  if (target == culprit) return [culprit];
  final prev = <String, String>{};
  final queue = [target];
  final seen = <String>{target};
  while (queue.isNotEmpty) {
    final u = queue.removeAt(0);
    if (u == culprit) break;
    final adj = [
      ...?groupMembers[u],
      if (detourEdge.containsKey(u)) detourEdge[u]!,
    ];
    for (final v in adj) {
      if (!seen.add(v)) continue;
      prev[v] = u;
      queue.add(v);
    }
  }

  final path = <String>[];
  String? cur = culprit;
  while (cur != null && cur != target) {
    path.add(cur);
    cur = prev[cur];
  }
  path.add(target);


  return [culprit, ...path.reversed.where((t) => t != culprit)];
}






List<DnsGroupCycle> _findDnsGroupCycles(Map<String, List<String>> edges) {
  final issues = <DnsGroupCycle>[];
  final done = <String>{};
  for (final start in edges.keys) {
    if (done.contains(start)) continue;
    final onPath = <String>[];
    final visitedLocal = <String>{};
    void dfs(String u) {
      if (done.contains(u)) return;
      final idx = onPath.indexOf(u);
      if (idx != -1) {

        final cycle = onPath.sublist(idx);
        issues.add(DnsGroupCycle(List<String>.unmodifiable(cycle)));
        done.addAll(cycle);
        return;
      }
      if (!visitedLocal.add(u)) return;
      onPath.add(u);
      for (final v in (edges[u] ?? const [])) {
        dfs(v);
      }
      onPath.removeLast();
    }

    dfs(start);
    done.add(start);
  }
  return issues;
}
