part of '../post_steps.dart';





































void _sanitizeUrltestTimings(
  Map<String, dynamic> e,
  List<String> warnings,
) {
  if (e['type'] != 'urltest') return;

  final interval = _urltestDuration(e, 'interval', _kCoreUrltestIntervalNs);
  final idle = _urltestDuration(e, 'idle_timeout', _kCoreUrltestIdleTimeoutNs);
  if (interval == null || idle == null) return;
  if (interval.ns <= idle.ns) return;



  final target = interval.raw ?? _kCoreUrltestInterval;
  e['idle_timeout'] = target;

  String describe(({int ns, String? raw}) d, String coreDefault) =>
      d.raw == null ? '$coreDefault (core default)' : '"${d.raw}"';
  final tag = _tagOf(e);
  warnings.add(
      'Group "$tag": interval ${describe(interval, _kCoreUrltestInterval)} is '
      'greater than idle_timeout '
      '${describe(idle, _kCoreUrltestIdleTimeout)} — idle_timeout '
      '${idle.raw == null ? 'set' : 'raised'} to "$target", otherwise the core '
      'would not start. The interval is kept: shortening it would probe the '
      'servers more often than configured.');
}



const _kCoreUrltestInterval = '3m';
const _kCoreUrltestIdleTimeout = '30m';
const _kCoreUrltestIntervalNs = 3 * 60 * 1000000000;
const _kCoreUrltestIdleTimeoutNs = 30 * 60 * 1000000000;




({int ns, String? raw})? _urltestDuration(
  Map<String, dynamic> e,
  String key,
  int defaultNs,
) {
  if (!e.containsKey(key)) return (ns: defaultNs, raw: null);
  final raw = e[key];
  if (raw is! String) return null;
  final ns = parseCoreDurationNanos(raw);
  if (ns == null || ns < 0) return null;
  if (ns == 0) return (ns: defaultNs, raw: null);
  return (ns: ns, raw: raw);
}
