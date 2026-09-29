













library;

import '../../models/core_reject_verdict.dart';
import '../lx_backup_slice.dart';





Map<String, dynamic> sanitizeCoreRejectInBackupRecord(
  Map<String, dynamic> record,
  BackupRecord kind, {
  bool forExport = false,
}) {
  switch (kind) {
    case BackupRecord.folder:
      if (forExport) return record;
      final nodes = record['nodes'];
      if (nodes is! List) return record;
      return {
        ...record,
        'nodes': [
          for (final n in nodes)
            if (n is Map)
              sanitizeCoreRejectInBackupRecord(
                n.cast<String, dynamic>(),
                BackupRecord.folderNode,
              )
            else
              n,
        ],
      };
    case BackupRecord.subscription:
      return _sanitizeSubscriptionRecord(record);
    case BackupRecord.server:
    case BackupRecord.folderNode:
      if (forExport) return record;
      return _sanitizeServerLikeRecord(record);
    default:
      return record;
  }
}

Map<String, dynamic> _sanitizeSubscriptionRecord(Map<String, dynamic> record) {
  final warnings = _stringKeyMap(record['warnings']);
  final strippedWarnings = <String, dynamic>{};
  for (final e in warnings.entries) {
    final kept = _withoutCoreRejected(storedWarningsFromJson(e.value));
    if (kept.isNotEmpty) strippedWarnings[e.key] = storedWarningsToJson(kept);
  }
  final out = Map<String, dynamic>.from(record);
  _setOrRemove(out, 'warnings', strippedWarnings);
  return out;
}

Map<String, dynamic> _sanitizeServerLikeRecord(Map<String, dynamic> record) {
  final kept = _withoutCoreRejected(storedWarningsFromJson(record['warnings']));
  final out = Map<String, dynamic>.from(record);
  _setOrRemove(out, 'warnings', kept.isEmpty ? null : storedWarningsToJson(kept));
  return out;
}

List<StoredWarning> _withoutCoreRejected(List<StoredWarning> ws) =>
    [for (final w in ws) if (!w.isCoreRejected) w];

Map<String, dynamic> _stringKeyMap(Object? raw) {
  if (raw is! Map) return {};
  return {for (final e in raw.entries) e.key.toString(): e.value};
}

void _setOrRemove(Map<String, dynamic> out, String key, Object? value) {
  if (value == null || (value is Map && value.isEmpty)) {
    out.remove(key);
  } else {
    out[key] = value;
  }
}
