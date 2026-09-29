import 'dart:convert';

import '../../models/codec/source_record.dart';
import '../../models/node_spec.dart';

































Map<String, dynamic>? verbatimBodyOf(String containerRaw, NodeSpec node) {
  if (node is AutoSelectSpec) return null;


  if (!isAuthoredNodeSource(containerRaw)) return null;
  final src = node.rawSource.trim();
  if (!src.startsWith('{')) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(src);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final body = Map<String, dynamic>.from(decoded);
  body.remove('detour');
  final tag = body['tag'];
  if (tag is! String || tag.isEmpty) body['tag'] = node.tag;
  return body;
}
