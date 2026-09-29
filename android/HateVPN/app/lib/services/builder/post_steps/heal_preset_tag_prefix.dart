part of '../post_steps.dart';

























List<({String from, String to})> healPresetTagPrefix(
    Map<String, dynamic> config) {
  final healed = <({String from, String to})>[];

  final dns = config['dns'];
  final dnsServers = (dns is Map<String, dynamic>)
      ? (dns['servers'] as List<dynamic>? ?? const [])
      : const [];



  final byLocal = <String, String?>{};
  void index(Iterable<dynamic> items) {
    for (final it in items) {
      if (it is! Map<String, dynamic>) continue;
      final tag = it['tag'];
      if (tag is! String) continue;
      final sep = tag.indexOf(':');
      if (sep <= 0) continue;
      final local = tag.substring(sep + 1);
      if (local.isEmpty) continue;
      byLocal[local] = byLocal.containsKey(local) ? null : tag;
    }
  }

  index(dnsServers);
  final route = config['route'];
  if (route is Map<String, dynamic>) {
    index(route['rule_set'] as List<dynamic>? ?? const []);
  }
  if (byLocal.isEmpty) return healed;



  final existing = <String>{
    for (final s in dnsServers)
      if (s is Map<String, dynamic> && s['tag'] is String) s['tag'] as String,
    if (route is Map<String, dynamic>)
      for (final rs in (route['rule_set'] as List<dynamic>? ?? const []))
        if (rs is Map<String, dynamic> && rs['tag'] is String)
          rs['tag'] as String,
  };

  Object? healRef(Object? value) {
    if (value is String) {
      if (existing.contains(value)) return value;
      final target = byLocal[value];
      if (target == null) return value;
      healed.add((from: value, to: target));
      return target;
    }
    if (value is List) {
      return [for (final v in value) healRef(v)];
    }
    return value;
  }


  if (dns is Map<String, dynamic>) {
    for (final r in (dns['rules'] as List<dynamic>? ?? const [])) {
      if (r is! Map<String, dynamic>) continue;
      if (r['server'] != null) r['server'] = healRef(r['server']);
      if (r['rule_set'] != null) r['rule_set'] = healRef(r['rule_set']);
    }
    if (dns['final'] != null) dns['final'] = healRef(dns['final']);
  }


  if (route is Map<String, dynamic>) {
    for (final r in (route['rules'] as List<dynamic>? ?? const [])) {
      if (r is! Map<String, dynamic>) continue;
      if (r['rule_set'] != null) r['rule_set'] = healRef(r['rule_set']);
      if (r['server'] != null) r['server'] = healRef(r['server']);
    }
  }

  return healed;
}
