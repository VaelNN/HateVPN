import '../../../models/codec/chain_record.dart';
import '../../../models/codec/source_record.dart';
import '../../../models/server_list.dart';
import '../../settings_storage.dart';
import '../../settings_storage_keys.dart';
import '../../url_mask.dart';





























Map<String, Object?> serializeStorageCache(Map<String, dynamic> cache) {
  final out = <String, Object?>{};
  for (final e in cache.entries) {
    out[e.key] = switch (e.key) {
      'vars' => _scrubVars(e.value),
      kSourcesKey => [
          for (final list in SettingsStorage.serverListsOf(cache))
            serializeStorageSource(list),
          for (final chain in SettingsStorage.chainsOf(cache))
            chainToRecord(chain),
        ],
      _ => e.value,
    };
  }
  return out;
}

Object? _scrubVars(dynamic vars) {
  if (vars is! Map) return vars;
  final out = <String, Object?>{};
  for (final e in vars.entries) {
    final k = e.key.toString();
    if (k == 'debug_token') {
      final v = e.value?.toString() ?? '';
      out[k] = v.isEmpty ? '' : '***';
    } else {
      out[k] = e.value;
    }
  }
  return out;
}





Map<String, Object?> serializeStorageSource(ServerList list) => {
      for (final e in sourceToRecord(list).entries)
        ...switch ((list, e.key)) {
          (SubscriptionServers s, 'url') => {'url': maskSubscriptionUrl(s.url)},
          (UserServer u, 'origin') => {
              'origin': {
                'kind': (e.value as Map)['kind'],
                'raw_bytes': u.rawBody.length,
              },
            },
          (FolderServers f, 'nodes') => {'nodes_count': f.members.length},
          _ => {e.key: e.value},
        },
    };
