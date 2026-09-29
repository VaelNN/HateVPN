

















library;

import 'node_warning.dart';



const kCoreRejectedCode = 'core_rejected';


const kCoreRejectedReasonParam = 'reason';


const kCoreRejectedSourceParam = 'source_id';



const kCoreRejectedNodeKeyParam = 'node_key';


final class CoreRejectNodeRef {
  const CoreRejectNodeRef({required this.sourceId, required this.nodeKey});

  final String sourceId;
  final String nodeKey;

  static CoreRejectNodeRef? fromParams(Map<String, String> params) {
    final sourceId = params[kCoreRejectedSourceParam];
    final nodeKey = params[kCoreRejectedNodeKeyParam];
    if (sourceId == null ||
        sourceId.isEmpty ||
        nodeKey == null ||
        nodeKey.isEmpty) {
      return null;
    }
    return CoreRejectNodeRef(sourceId: sourceId, nodeKey: nodeKey);
  }

  Map<String, String> toParams() => {
        kCoreRejectedSourceParam: sourceId,
        kCoreRejectedNodeKeyParam: nodeKey,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoreRejectNodeRef &&
          sourceId == other.sourceId &&
          nodeKey == other.nodeKey);

  @override
  int get hashCode => Object.hash(sourceId, nodeKey);

  @override
  String toString() => 'CoreRejectNodeRef($sourceId, $nodeKey)';
}



final class StoredWarning {
  const StoredWarning({required this.code, this.params = const {}});

  final String code;
  final Map<String, String> params;


  String get reason => params[kCoreRejectedReasonParam] ?? '';

  bool get isCoreRejected => code == kCoreRejectedCode;





  factory StoredWarning.coreRejected(
    String reason, {
    CoreRejectNodeRef? ref,
  }) =>
      StoredWarning(
        code: kCoreRejectedCode,
        params: {
          kCoreRejectedReasonParam: reason,
          if (ref != null) ...ref.toParams(),
        },
      );


  CoreRejectNodeRef? get coreRejectRef => CoreRejectNodeRef.fromParams(params);


  RegistryWarning toWarning() =>
      RegistryWarning(code: code, params: params);

  Map<String, dynamic> toJson() => {
        'code': code,
        if (params.isNotEmpty) 'params': {...params},
      };



  static StoredWarning? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final code = raw['code'];
    if (code is! String || code.isEmpty) return null;
    final p = raw['params'];
    final params = <String, String>{};
    if (p is Map) {
      for (final e in p.entries) {
        final k = e.key;
        final v = e.value;
        if (k is String && k.isNotEmpty && v != null) params[k] = '$v';
      }
    }
    return StoredWarning(code: code, params: params);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredWarning &&
          code == other.code &&
          _mapEq(params, other.params));

  @override
  int get hashCode => Object.hash(
        code,
        Object.hashAllUnordered(
            params.entries.map((e) => '${e.key}=${e.value}')),
      );

  @override
  String toString() => 'StoredWarning($code, $params)';
}

bool _mapEq(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}



RegistryWarning coreRejectedWarningOf(String reason) =>
    StoredWarning.coreRejected(reason).toWarning();



List<Map<String, dynamic>> storedWarningsToJson(List<StoredWarning> ws) =>
    [for (final w in ws) w.toJson()];


List<StoredWarning> storedWarningsFromJson(Object? raw) {
  if (raw is! List) return const [];
  final out = <StoredWarning>[];
  for (final e in raw) {
    final w = StoredWarning.fromJson(e);
    if (w != null) out.add(w);
  }
  return out;
}


Map<String, List<StoredWarning>> storedWarningsMapFromJson(Object? raw) {
  if (raw is! Map || raw.isEmpty) return const {};
  final out = <String, List<StoredWarning>>{};
  for (final e in raw.entries) {
    final k = e.key;
    if (k is! String || k.isEmpty) continue;
    final ws = storedWarningsFromJson(e.value);
    if (ws.isNotEmpty) out[k] = ws;
  }
  return out;
}

Map<String, dynamic> storedWarningsMapToJson(
        Map<String, List<StoredWarning>> m) =>
    {
      for (final e in m.entries)
        if (e.value.isNotEmpty) e.key: storedWarningsToJson(e.value),
    };



List<StoredWarning> upsertVerdict(
  List<StoredWarning> existing,
  StoredWarning verdict,
) =>
    [verdict, ...existing.where((w) => w.code != verdict.code)];


List<StoredWarning> dropVerdict(List<StoredWarning> existing) =>
    existing.where((w) => !w.isCoreRejected).toList();
