import 'dart:convert';











Map<String, dynamic> deepCopyJson(Map<String, dynamic> src) =>
    jsonDecode(jsonEncode(src)) as Map<String, dynamic>;


Object? deepCloneJson(Object? v) =>
    v == null ? null : jsonDecode(jsonEncode(v));



bool deepEqualsJson(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
      if (!deepEqualsJson(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEqualsJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
