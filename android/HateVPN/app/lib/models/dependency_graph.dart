import 'dart:convert';

import 'config_node.dart';



class DependentRef {
  const DependentRef({
    required this.kind,
    required this.tag,
    this.via,
  });


  final String kind;


  final String tag;




  final String? via;

  bool get isDns => kind == 'dns';

  @override
  bool operator ==(Object other) =>
      other is DependentRef &&
      other.kind == kind &&
      other.tag == tag &&
      other.via == via;

  @override
  int get hashCode => Object.hash(kind, tag, via);

  @override
  String toString() => 'DependentRef($kind $tag via=$via)';
}











class DependencyGraph {
  const DependencyGraph._({
    required Map<String, List<DependentRef>> dependentsOf,
    required Map<String, List<String>> selectorMembers,
    required Map<String, List<String>> urltestMembers,
    required Set<String> payloadTags,
  })  : _dependentsOf = dependentsOf,
        _selectorMembers = selectorMembers,
        _urltestMembers = urltestMembers,
        _payloadTags = payloadTags;

  const DependencyGraph.empty()
      : _dependentsOf = const {},
        _selectorMembers = const {},
        _urltestMembers = const {},
        _payloadTags = const {};


  final Map<String, List<DependentRef>> _dependentsOf;


  final Map<String, List<String>> _selectorMembers;


  final Map<String, List<String>> _urltestMembers;


  final Set<String> _payloadTags;

  bool get isEmpty =>
      _dependentsOf.isEmpty && _selectorMembers.isEmpty && _payloadTags.isEmpty;



  List<DependentRef> directDependents(String tag) =>
      _dependentsOf[tag] ?? const [];



  factory DependencyGraph.fromConfig(String configRaw) {
    if (configRaw.isEmpty) return const DependencyGraph.empty();
    final dependents = <String, List<DependentRef>>{};
    final selectorMembers = <String, List<String>>{};
    final urltestMembers = <String, List<String>>{};
    final payload = <String>{};
    try {
      final cfg = jsonDecode(configRaw) as Map<String, dynamic>;
      final raws = [
        ...(cfg['outbounds'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>(),
        ...(cfg['endpoints'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>(),
      ];
      for (final o in raws) {
        final tag = o['tag'];
        if (tag is! String || tag.isEmpty) continue;
        final type = o['type'] as String? ?? '';
        if (!ConfigNode.kControlTypes.contains(type)) payload.add(tag);
        final detour = o['detour'];
        if (detour is String && detour.isNotEmpty) {
          (dependents[detour] ??= [])
              .add(DependentRef(kind: 'node', tag: tag));
        }
        if (type == 'selector' || type == 'urltest') {
          final members = (o['outbounds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList();
          (type == 'selector' ? selectorMembers : urltestMembers)[tag] =
              members;
        }
      }
      final servers = (cfg['dns']?['servers'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      for (final s in servers) {
        final tag = s['tag'];
        final detour = s['detour'];
        if (tag is! String || tag.isEmpty) continue;
        if (detour is String && detour.isNotEmpty) {
          (dependents[detour] ??= [])
              .add(DependentRef(kind: 'dns', tag: tag));
        }
      }
    } catch (_) {
      return const DependencyGraph.empty();
    }
    return DependencyGraph._(
      dependentsOf: dependents,
      selectorMembers: selectorMembers,
      urltestMembers: urltestMembers,
      payloadTags: payload,
    );
  }





  static bool _isDead(String tag, Map<String, Map<String, int>> delays) {
    var seen = false;
    for (final direction in delays.values) {
      final v = direction[tag];
      if (v == null) continue;
      if (v >= 0) return false;
      seen = true;
    }
    return seen;
  }









  Map<String, List<DependentRef>> computeSick({
    required Map<String, String> selections,
    required Map<String, Map<String, int>> delays,
  }) {
    if (isEmpty) return const {};

    final dead = <String>{
      for (final tag in _payloadTags)
        if (_isDead(tag, delays)) tag,
    };
    if (dead.isEmpty) return const {};


    final selectedIn = <String, List<String>>{};
    selections.forEach((group, selected) {
      if (_selectorMembers.containsKey(group)) {
        (selectedIn[selected] ??= []).add(group);
      }
    });

    final result = <String, List<DependentRef>>{};
    for (final root in dead) {
      final visited = <String>{root};
      final queue = <String>[root];
      final affected = <DependentRef>[];
      while (queue.isNotEmpty) {
        final cur = queue.removeLast();


        for (final dep in _dependentsOf[cur] ?? const <DependentRef>[]) {
          if (!visited.add(dep.tag)) continue;
          affected.add(DependentRef(
            kind: dep.kind,
            tag: dep.tag,
            via: cur == root ? null : cur,
          ));
          if (!dep.isDns) queue.add(dep.tag);
        }


        for (final group in selectedIn[cur] ?? const <String>[]) {
          if (visited.add(group)) queue.add(group);
        }

        _urltestMembers.forEach((group, members) {
          if (visited.contains(group) || !members.contains(cur)) return;
          if (members.every(dead.contains)) {
            visited.add(group);
            queue.add(group);
          }
        });
      }
      if (affected.isNotEmpty) result[root] = affected;
    }
    return result;
  }
}
