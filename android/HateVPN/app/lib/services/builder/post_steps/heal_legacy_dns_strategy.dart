part of '../post_steps.dart';


























List<int> healLegacyDnsStrategy(Map<String, dynamic> config) {
  final dns = config['dns'];
  if (dns is! Map<String, dynamic>) return const [];
  final rules = dns['rules'];
  if (rules is! List) return const [];

  final hasIncompatible = rules.any((r) =>
      r is Map<String, dynamic> &&
      (r.containsKey('query_type') || r.containsKey('ip_version')));
  if (!hasIncompatible) return const [];

  final healed = <int>[];
  for (var i = 0; i < rules.length; i++) {
    final r = rules[i];
    if (r is Map<String, dynamic> && r.containsKey('strategy')) {
      r.remove('strategy');
      healed.add(i);
    }
  }
  return healed;
}
