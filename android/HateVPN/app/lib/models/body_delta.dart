













library;


typedef BodyPath = List<String>;

final class BodyDelta {
  const BodyDelta({this.add = const [], this.drop = const []});


  final List<(BodyPath, Object?)> add;


  final List<BodyPath> drop;

  bool get isEmpty => add.isEmpty && drop.isEmpty;


  BodyDelta? withoutAdds(Set<String> paths) {
    final kept = [
      for (final a in add)
        if (!paths.contains(a.$1.join('.'))) a,
    ];
    final out = BodyDelta(add: kept, drop: drop);
    return out.isEmpty ? null : out;
  }


  void applyTo(Map<String, dynamic> map, Object? Function(Object?) copy) {
    for (final p in drop) {
      final parent = _parentOf(map, p);
      parent?.remove(p.last);
    }
    for (final (p, v) in add) {
      final parent = _parentOf(map, p);
      if (parent == null || parent.containsKey(p.last)) continue;
      parent[p.last] = copy(v);
    }
  }

  static Map<String, dynamic>? _parentOf(Map<String, dynamic> map, BodyPath p) {
    Map<String, dynamic> cur = map;
    for (var i = 0; i < p.length - 1; i++) {
      final next = cur[p[i]];
      if (next is! Map) return null;


      if (next is! Map<String, dynamic>) {
        final widened = Map<String, dynamic>.from(next);
        cur[p[i]] = widened;
        cur = widened;
      } else {
        cur = next;
      }
    }
    return cur;
  }
}
