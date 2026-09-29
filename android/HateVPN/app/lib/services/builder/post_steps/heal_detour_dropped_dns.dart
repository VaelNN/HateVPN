part of '../post_steps.dart';






































List<String> healDetourDroppedDnsRefs(
  Map<String, dynamic> config, {
  required Set<String> detourDropped,
  Map<String, String> defaults = const {},
}) {
  if (detourDropped.isEmpty) return const [];
  final dns = config['dns'];
  if (dns is! Map<String, dynamic>) return const [];
  final warnings = <String>[];

  final rules = dns['rules'];

  final out = <dynamic>[];
  var rulesChanged = false;
  if (rules is List) {
    for (var i = 0; i < rules.length; i++) {
      final r = rules[i];
      if (r is! Map<String, dynamic>) {
        out.add(r);
        continue;
      }
      final server = r['server'];
      final action = r['action'];
      if (server is! String ||
          !detourDropped.contains(server) ||
          (action != null && action != 'route' && action != 'evaluate')) {
        out.add(r);
        continue;
      }
      out.add(dnsRuleAsReject(r));
      rulesChanged = true;
      warnings.add('DNS rule #$i now rejects: its server "$server" was dropped '
          '(detour is not in the config).');
    }
  }

  final dnsFinal = dns['final'];
  if (dnsFinal is String && detourDropped.contains(dnsFinal)) {
    dns.remove('final');
    out.add(<String, dynamic>{'action': 'reject'});
    rulesChanged = true;
    warnings.add('dns.final removed: DNS server "$dnsFinal" was dropped '
        '(detour is not in the config), remaining queries are rejected.');
  }
  if (rulesChanged) dns['rules'] = out;

  final pool = _DnsResolverPool.of(config);
  final preferred = defaults['dns_default_domain_resolver'] ?? '';




  void heal(Map<String, dynamic> owner, String key, String where,
      {String except = '', bool dropOnly = false}) {
    final value = owner[key];
    final target = switch (value) {
      String s => s,
      Map m when m['server'] is String => m['server'] as String,
      _ => null,
    };
    if (target == null || !detourDropped.contains(target)) return;
    final to =
        dropOnly ? null : pool?.replacement(preferred, except: except);
    if (to == null) {
      owner.remove(key);
      warnings.add(dropOnly
          ? '$where: $key removed, DNS server "$target" was dropped (detour '
              'is not in the config).'
          : '$where: $key removed, DNS server "$target" was dropped (detour '
              'is not in the config) and no DNS server can replace it.');
      return;
    }
    if (value is Map) {
      owner[key] = <String, dynamic>{...value.cast<String, dynamic>(), 'server': to};
    } else {
      owner[key] = to;
    }
    warnings.add('$where: $key switched to "$to", DNS server "$target" was '
        'dropped (detour is not in the config).');
  }

  final route = config['route'];
  if (route is Map<String, dynamic>) {
    heal(route, 'default_domain_resolver', 'route');
  }
  for (final section in const ['outbounds', 'endpoints']) {
    for (final o in (config[section] as List<dynamic>? ?? const [])) {
      if (o is! Map<String, dynamic>) continue;
      heal(o, 'domain_resolver', '$section "${o['tag'] ?? ''}"');
    }
  }
  for (final s in (dns['servers'] as List<dynamic>? ?? const [])) {
    if (s is! Map<String, dynamic>) continue;
    final tag = s['tag'] as String? ?? '';
    heal(s, 'domain_resolver', 'DNS server "$tag"',
        except: tag, dropOnly: !_dnsAddressIsDomain(s['server']));
  }
  return warnings;
}



bool _dnsAddressIsDomain(Object? address) {
  if (address is! String) return false;
  var a = address.trim();
  if (a.isEmpty) return false;
  if (a.startsWith('[') && a.endsWith(']')) a = a.substring(1, a.length - 1);
  try {
    Uri.parseIPv4Address(a);
    return false;
  } on FormatException {

  }
  try {
    Uri.parseIPv6Address(a);
    return false;
  } on FormatException {
    return true;
  }
}



Map<String, dynamic> dnsRuleAsReject(Map<String, dynamic> rule) {
  const routeKeys = {
    'server',
    'action',
    'tag',
    'strategy',
    'disable_cache',
    'disable_optimistic_cache',
    'rewrite_ttl',
    'client_subnet',
    'remove_client_subnet',
    'timeout',
    'speculative',
    'race',
  };
  return <String, dynamic>{
    for (final e in rule.entries)
      if (!routeKeys.contains(e.key)) e.key: e.value,
    'action': 'reject',
  };
}
