part of '../post_steps.dart';




























List<({String owner, String original})> healUnknownUtlsFingerprints(
  Map<String, dynamic> config, {
  Set<Map<String, dynamic>> authored = const {},
}) {
  final healed = <({String owner, String original})>[];
  final outbounds = (config['outbounds'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>();
  for (final o in outbounds) {
    final tls = o['tls'];
    if (tls is! Map<String, dynamic>) continue;




    final own = authored.contains(o);
    if (o['type'] == 'hysteria2' || o['type'] == 'tuic') {
      for (final k in const ['utls', 'reality']) {
        if (!tls.containsKey(k)) continue;
        editBodyPath(o,
            authored: own,
            code: 'tls_not_applicable_quic',
            path: 'tls.$k',
            remove: true);
      }
      continue;
    }
    final utls = tls['utls'];
    if (utls is! Map<String, dynamic>) continue;
    final fp = utls['fingerprint'];
    if (fp is String && fp.isNotEmpty) {
      final n = normalizeUtlsFingerprintValue(fp);
      if (n.value != fp) {
        final done = editBodyPath(o,
            authored: own,
            code: 'utls_fp_unknown',
            path: 'tls.utls.fingerprint',
            value: n.value,
            remove: n.value.isEmpty);
        if (done && n.value.isNotEmpty && n.junk) {
          healed.add((owner: o['tag'] as String? ?? '', original: fp));
        }
      }
    }
  }
  return healed;
}
