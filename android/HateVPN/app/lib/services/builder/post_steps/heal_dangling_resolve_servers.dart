part of '../post_steps.dart';




















List<({int ruleIndex, String target})> healDanglingResolveServers(
    Map<String, dynamic> config) {
  final dns = config['dns'];
  final serverTags = <String>{
    if (dns is Map<String, dynamic>)
      for (final s in (dns['servers'] as List<dynamic>? ?? const []))
        if (s is Map<String, dynamic>) s['tag'] as String? ?? '',
  }..remove('');

  final route = config['route'];
  if (route is! Map<String, dynamic>) return const [];
  final rules = route['rules'];
  if (rules is! List) return const [];

  final removed = <({int ruleIndex, String target})>[];
  for (var i = 0; i < rules.length; i++) {
    final r = rules[i];
    if (r is! Map<String, dynamic>) continue;
    if (r['action'] != 'resolve') continue;
    final server = r['server'];
    if (server is! String || server.isEmpty) continue;
    if (serverTags.contains(server)) continue;
    r.remove('server');
    removed.add((ruleIndex: i, target: server));
  }
  return removed;
}
