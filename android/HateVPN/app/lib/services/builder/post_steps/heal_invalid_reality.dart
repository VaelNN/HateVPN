part of '../post_steps.dart';























List<({String owner, String field, String original})> healInvalidReality(
  Map<String, dynamic> config, {
  Set<Map<String, dynamic>> authored = const {},
}) {
  final healed = <({String owner, String field, String original})>[];
  final outbounds = (config['outbounds'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>();
  for (final o in outbounds) {
    final tls = o['tls'];
    if (tls is! Map<String, dynamic>) continue;
    final reality = tls['reality'];
    if (reality is! Map<String, dynamic>) continue;

    if (reality['enabled'] != true) continue;
    final tag = o['tag'] as String? ?? '';
    final own = authored.contains(o);

    final pbk = reality['public_key'];
    if (pbk is! String || !isValidRealityPublicKey(pbk)) {
      if (editBodyPath(o,
          authored: own,
          code: 'reality_pbk_invalid',
          path: 'tls.reality',
          remove: true)) {
        healed.add((owner: tag, field: 'public_key', original: '$pbk'));
      }
      continue;
    }

    final sid = reality['short_id'];
    if (sid != null && sid is! String) {


      if (_clearShortId(o, own)) {
        healed.add((owner: tag, field: 'short_id', original: '$sid'));
      }
    } else if (sid is String && sid.isNotEmpty && !_isValidRealityShortId(sid)) {
      if (_clearShortId(o, own)) {
        healed.add((owner: tag, field: 'short_id', original: sid));
      }
    }
  }
  return healed;
}

bool _clearShortId(Map<String, dynamic> o, bool authored) => editBodyPath(o,
    authored: authored,
    code: 'reality_short_id_invalid',
    path: 'tls.reality.short_id',
    value: '');



bool _isValidRealityShortId(String s) {
  if (s.length > 16 || s.length.isOdd) return false;
  for (final r in s.runes) {
    final hex = (r >= 0x30 && r <= 0x39) ||
        (r >= 0x61 && r <= 0x66) ||
        (r >= 0x41 && r <= 0x46);
    if (!hex) return false;
  }
  return true;
}
