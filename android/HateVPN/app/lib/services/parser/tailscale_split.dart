import 'dart:convert';

import '../../models/node_spec.dart';
import 'body_decoder.dart';












String? textWithoutTailscale(JsonConfig decoded) {
  final copy = deepCopyJson(decoded.value);
  var removed = false;

  bool isTailscale(Object? e) =>
      e is Map && e['type']?.toString() == 'tailscale';

  void stripConfig(Map<String, dynamic> cfg) {
    for (final key in const ['outbounds', 'endpoints']) {
      final list = cfg[key];
      if (list is! List) continue;
      final kept = [for (final e in list) if (!isTailscale(e)) e];
      if (kept.length == list.length) continue;
      removed = true;


      if (kept.isEmpty && key == 'endpoints') {
        cfg.remove(key);
      } else {
        cfg[key] = kept;
      }
    }
  }

  Object? out;



  switch (decoded.source.kind) {
    case SourceKind.singboxConfig:
      if (copy is! Map<String, dynamic>) return null;
      stripConfig(copy);
      out = copy;
    case SourceKind.singboxConfigArray:
      if (copy is! List) return null;
      for (final c in copy.whereType<Map<String, dynamic>>()) {
        stripConfig(c);
      }
      out = copy;
    case SourceKind.singboxOutboundArray:
      if (copy is! List) return null;
      final kept = [for (final e in copy) if (!isTailscale(e)) e];
      removed = kept.length != copy.length;
      out = kept;


    default:
      return null;
  }
  if (!removed) return null;
  return const JsonEncoder.withIndent('  ').convert(out);
}
