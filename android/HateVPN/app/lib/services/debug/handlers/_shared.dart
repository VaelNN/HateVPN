import '../../../models/codec/node_link_record.dart';
import '../../../models/node_link.dart';
import '../context.dart';
import '../contract/errors.dart';
import '../transport/request.dart';










Future<Map<String, Object?>> maybeRebuild(DebugRequest req, DebugContext ctx) async {
  if (!req.qBool('rebuild')) return const {};
  final sub = ctx.requireSub();
  final home = ctx.requireHome();
  try {
    final json = await sub.generateConfig();
    if (json == null) {
      return {
        'rebuilt': false,
        'rebuild_error': 'generate failed: ${sub.lastError?.renderEn() ?? ''}',
      };
    }
    final saved = await home.saveParsedConfig(json);
    if (!saved) {
      return {
        'rebuilt': false,
        'rebuild_error': 'saveParsedConfig returned false',
      };
    }
    return {'rebuilt': true, 'config_bytes': json.length};
  } catch (e) {
    return {'rebuilt': false, 'rebuild_error': e.toString()};
  }
}



bool? fieldBool(Map<String, dynamic> m, String key) {
  if (!m.containsKey(key)) return null;
  final v = m[key];
  if (v is bool) return v;
  throw BadRequest('field "$key" must be bool, got ${v.runtimeType}');
}

String? fieldString(Map<String, dynamic> m, String key) {
  if (!m.containsKey(key)) return null;
  final v = m[key];
  if (v is String) return v;
  throw BadRequest('field "$key" must be string, got ${v.runtimeType}');
}

int? fieldInt(Map<String, dynamic> m, String key) {
  if (!m.containsKey(key)) return null;
  final v = m[key];
  if (v is int) return v;
  throw BadRequest('field "$key" must be int, got ${v.runtimeType}');
}

List<String>? fieldStringList(Map<String, dynamic> m, String key) {
  if (!m.containsKey(key)) return null;
  final v = m[key];
  if (v is List) {
    return v.map((e) {
      if (e is String) return e;
      throw BadRequest('field "$key" must be list of strings');
    }).toList();
  }
  throw BadRequest('field "$key" must be array, got ${v.runtimeType}');
}




NodeLink? fieldNodeLink(Map<String, dynamic> m, String key) {
  if (!m.containsKey(key)) return null;
  final v = m[key];
  if (v == null) return NodeLink.none;
  final link = nodeLinkFromRecord(v);
  if (link == null) {
    throw BadRequest('field "$key" must be {"folder_id"?: string, "tag": '
        'string}, a string or null, got ${v.runtimeType}');
  }
  return link.tag.isEmpty ? NodeLink.none : link;
}



List<NodeLink>? fieldNodeLinkList(Map<String, dynamic> m, String key) {
  if (!m.containsKey(key)) return null;
  final v = m[key];
  if (v is! List) {
    throw BadRequest('field "$key" must be array, got ${v.runtimeType}');
  }
  return [
    for (final e in v)
      nodeLinkFromRecord(e) ??
          (throw BadRequest('field "$key" must be a list of '
              '{"folder_id"?: string, "tag": string} or strings')),
  ];
}

List<int>? fieldIntList(Map<String, dynamic> m, String key) {
  if (!m.containsKey(key)) return null;
  final v = m[key];
  if (v is List) {
    return v.map((e) {
      if (e is int) return e;
      throw BadRequest('field "$key" must be list of ints');
    }).toList();
  }
  throw BadRequest('field "$key" must be array, got ${v.runtimeType}');
}




Map<String, String>? fieldStringMap(Map<String, dynamic> m, String key) {
  if (!m.containsKey(key)) return null;
  final v = m[key];
  if (v is Map) {
    return {
      for (final e in v.entries)
        if (e.key is String) e.key as String: e.value?.toString() ?? '',
    };
  }
  throw BadRequest('field "$key" must be object, got ${v.runtimeType}');
}
