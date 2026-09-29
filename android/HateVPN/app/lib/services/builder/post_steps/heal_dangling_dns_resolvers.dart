part of '../post_steps.dart';
























List<({String field, String varName, String from, String to})>
    healDanglingDnsResolvers(
  Map<String, dynamic> config, {
  required Map<String, String> defaults,
}) {
  final dns = config['dns'];
  if (dns is! Map<String, dynamic>) return const [];
  final pool = _DnsResolverPool.of(config);
  if (pool == null) return const [];

  String? replacementFor(String current, String varName) {
    if (current.isEmpty || pool.tags.contains(current)) return null;
    return pool.replacement(defaults[varName] ?? '');
  }

  final healed = <({String field, String varName, String from, String to})>[];

  final dnsFinal = dns['final'];
  if (dnsFinal is String) {
    final to = replacementFor(dnsFinal, 'dns_final');
    if (to != null) {
      dns['final'] = to;
      healed.add((
        field: 'dns.final',
        varName: 'dns_final',
        from: dnsFinal,
        to: to,
      ));
    }
  }

  final route = config['route'];
  if (route is Map<String, dynamic>) {
    final resolver = route['default_domain_resolver'];
    if (resolver is String) {
      final to = replacementFor(resolver, 'dns_default_domain_resolver');
      if (to != null) {
        route['default_domain_resolver'] = to;
        healed.add((
          field: 'route.default_domain_resolver',
          varName: 'dns_default_domain_resolver',
          from: resolver,
          to: to,
        ));
      }
    }
  }
  return healed;
}





class _DnsResolverPool {
  _DnsResolverPool(this.tags, this.usable);

  final Set<String> tags;
  final List<String> usable;


  static _DnsResolverPool? of(Map<String, dynamic> config) {
    final dns = config['dns'];
    if (dns is! Map<String, dynamic>) return null;
    final servers = (dns['servers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final tags = <String>{
      for (final s in servers) s['tag'] as String? ?? '',
    }..remove('');
    if (tags.isEmpty) return null;
    const forbidden = {'fakeip', 'hosts'};
    final usable = <String>[
      for (final s in servers)
        if ((s['tag'] as String? ?? '').isNotEmpty &&
            !forbidden.contains(s['type']))
          s['tag'] as String,
    ];
    if (usable.isEmpty) return null;
    return _DnsResolverPool(tags, usable);
  }



  String? replacement(String preferred, {String except = ''}) {
    if (preferred.isNotEmpty &&
        preferred != except &&
        usable.contains(preferred)) {
      return preferred;
    }
    for (final t in usable) {
      if (t != except) return t;
    }
    return null;
  }
}
