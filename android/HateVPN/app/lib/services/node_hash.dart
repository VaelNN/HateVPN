import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/node_spec.dart';
import '../models/template_vars.dart';






























const int kDisabledHashTtlIntervals = 3;
const int kDisabledHashTtlFloorHours = 24;
const int kDisabledHashTtlCeilHours = 24 * 30;






Duration disabledHashTtl(int updateIntervalHours) {
  final hours = kDisabledHashTtlIntervals *
      (updateIntervalHours > 0 ? updateIntervalHours : 0);
  return Duration(
      hours:
          hours.clamp(kDisabledHashTtlFloorHours, kDisabledHashTtlCeilHours));
}













Map<NodeSpec, String> sourceNodeIdentities(List<NodeSpec> nodes) =>
    _sourceRawTags(nodes, withGroups: false);









Map<NodeSpec, String> sourceNodeRawTags(List<NodeSpec> nodes) =>
    _sourceRawTags(nodes, withGroups: true);

Map<NodeSpec, String> _sourceRawTags(
  List<NodeSpec> nodes, {
  required bool withGroups,
}) {
  final out = Map<NodeSpec, String>.identity();
  if (nodes.isEmpty) return out;
  final counts = <String, int>{};
  for (final node in nodes) {
    final id = _stampIdentity(node, counts);
    if (id != null) out[node] = id;
  }
  if (!withGroups) return out;
  for (final node in nodes) {
    if (!node.isGroup) continue;
    final raw = node.tag.trim();
    if (raw.isNotEmpty) out[node] = _uniquifyAgainstCounts(raw, counts);
  }
  return out;
}



String? _stampIdentity(NodeSpec node, Map<String, int> counts) {
  if (node.isGroup) return null;
  final raw = node.tag.trim();
  if (raw.isEmpty) return null;
  return _uniquifyAgainstCounts(raw, counts);
}







String _uniquifyAgainstCounts(String name, Map<String, int> counts) {
  if ((counts[name] ?? 0) == 0) {
    counts[name] = 1;
    return name;
  }
  while (true) {
    counts[name] = (counts[name] ?? 0) + 1;
    final candidate = '$name-${counts[name]}';
    if ((counts[candidate] ?? 0) == 0) {
      counts[candidate] = 1;
      return candidate;
    }
  }
}





dynamic deepSortKeys(dynamic value) {
  if (value is Map) {
    final entries = [
      for (final e in value.entries)
        MapEntry(e.key.toString(), deepSortKeys(e.value)),
    ]..sort((a, b) => a.key.compareTo(b.key));
    return <String, dynamic>{for (final e in entries) e.key: e.value};
  }
  if (value is List) return [for (final e in value) deepSortKeys(e)];
  return value;
}
















String legacyNodeIdentityHash(NodeSpec node) {
  final map = Map<String, dynamic>.from(node.emit(TemplateVars.empty).map)
    ..remove('tag')
    ..remove('detour');
  return sha256.convert(utf8.encode(jsonEncode(deepSortKeys(map)))).toString();
}






















String nodeDedupSignature(NodeSpec node) {
  final chained = node.chained;
  final self = legacyNodeIdentityHash(node);
  return chained == null ? self : '$self|${nodeDedupSignature(chained)}';
}





bool isLegacyIdentityKey(String key) {
  if (key.length != 64) return false;
  for (var i = 0; i < 64; i++) {
    final c = key.codeUnitAt(i);
    final isDigit = c >= 0x30 && c <= 0x39;
    final isLowerHex = c >= 0x61 && c <= 0x66;
    if (!isDigit && !isLowerHex) return false;
  }
  return true;
}


















Map<String, DateTime> migrateLegacyDisabledKeys(
  Map<String, DateTime> current,
  List<NodeSpec> nodes,
) {
  if (current.isEmpty) return current;
  final legacyKeys = [
    for (final k in current.keys)
      if (isLegacyIdentityKey(k)) k,
  ];
  if (legacyKeys.isEmpty) return current;



  final identities = sourceNodeIdentities(nodes);
  final byLegacyHash = <String, String>{};
  for (final node in nodes) {
    final identity = identities[node];
    if (identity == null) continue;


    byLegacyHash.putIfAbsent(legacyNodeIdentityHash(node), () => identity);
  }

  final next = <String, DateTime>{};
  for (final e in current.entries) {
    if (!isLegacyIdentityKey(e.key)) {
      next[e.key] = e.value;
      continue;
    }
    final identity = byLegacyHash[e.key];
    if (identity == null) continue;
    final existing = next[identity];
    if (existing == null || existing.isBefore(e.value)) {
      next[identity] = e.value;
    }
  }
  return next;
}





Map<String, DateTime> gcDisabledHashes(
  Map<String, DateTime> current,
  Set<String> freshHashes, {
  required int updateIntervalHours,
  required DateTime now,
}) {
  if (current.isEmpty) return current;
  final ttl = disabledHashTtl(updateIntervalHours);
  final next = <String, DateTime>{};
  current.forEach((hash, lastSeen) {
    if (freshHashes.contains(hash)) {
      next[hash] = now;
    } else if (now.difference(lastSeen) <= ttl) {
      next[hash] = lastSeen;
    }

  });
  return next;
}






Map<String, DateTime> applyRuleMarks(
  Map<String, DateTime> base, {
  required Set<String> enable,
  required Set<String> disable,
  required DateTime now,
}) {
  if (enable.isEmpty && disable.isEmpty) return base;
  return {
    for (final e in base.entries)
      if (!enable.contains(e.key)) e.key: e.value,
    for (final h in disable) h: now,
  };
}
