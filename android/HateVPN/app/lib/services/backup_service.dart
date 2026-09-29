import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:package_info_plus/package_info_plus.dart';

import '../models/custom_rule.dart';
import '../models/server_list.dart';
import '../models/source_chain.dart';
import 'app_log.dart';
import 'json_clone.dart';
import 'record_vars.dart';
import 'settings_storage.dart';
import 'settings_storage_keys.dart';
import 'storage_migration/migrate_storage.dart';
import 'template_loader.dart';



enum BackupCategory {
  serverLists,
  routing,
  appSettings,
  debugConfig,
  vpnSettings,
}






const _topLevelRoutingKeys = {
  kRulesKey,
  'route_final',




  'directions',
  'directions_migrated',
  'route_idle_suspend',
  'route_idle_suspend_reachable',
  'wg_build_max',
  'wg_lazy_build',
  'urltest_passive_check',
  'enabled_groups',
  'tun_apps',
  'vpn_mode',
  kDnsKey,
};

















const _topLevelAppKeys = {
  'ping_options',
  'last_global_update',
  'presets_migrated',
  'late_presets_seeded',
  'warp_account',
  'masque_account',
  'interrupt_connections_on_switch',
  'node_sort_mode',
  'node_manual_order',
  'profiler_retention_sec',
};



const _varDebugKeys = SettingsStorage.debugApiVarKeys;













class BackupContents {




  BackupContents({
    this.createdAt,
    this.sourceAppVersion,
    Map<String, dynamic>? storage,
    this.vpnSettings,
    Map<String, String> presetIdByDnsServerTag = const {},
    Map<String, String> subscriptionBodies = const {},
    RecordVarDecls recordVars = RecordVarDecls.none,
  }) : storageMigration = storage == null
            ? null
            : migrateStorageDoc(storage,
                presetIdByDnsServerTag: presetIdByDnsServerTag,
                subscriptionBodies: subscriptionBodies,
                recordVars: recordVars);

  final DateTime? createdAt;
  final String? sourceAppVersion;


  final StorageMigrationResult? storageMigration;




  Map<String, dynamic>? get storage => storageMigration?.doc;



  final Map<String, dynamic>? vpnSettings;



  late final _EntitiesRead<ServerList> _serverLists =
      _readEntities(storage, SettingsStorage.serverListsOf);


  late final _EntitiesRead<CustomRule> _rules =
      _readEntities(storage, SettingsStorage.customRulesOf);



  late final _EntitiesRead<SourceChain> _chains =
      _readEntities(storage, SettingsStorage.chainsOf);


  Set<BackupCategory> availableCategories() {
    final s = storage;
    return {

      if (_serverLists.count + _chains.count > 0) BackupCategory.serverLists,
      if (s != null && _hasAnyRouting(s)) BackupCategory.routing,
      if (s != null && _hasAnyApp(s)) BackupCategory.appSettings,
      if (s != null && _hasAnyDebug(s)) BackupCategory.debugConfig,
      if (vpnSettings != null && vpnSettings!.isNotEmpty)
        BackupCategory.vpnSettings,
    };
  }


  int countFor(BackupCategory cat) {
    final s = storage ?? const <String, dynamic>{};
    return switch (cat) {
      BackupCategory.serverLists => _serverLists.count + _chains.count,
      BackupCategory.routing => _rules.count,
      BackupCategory.appSettings => () {
          final vars = s['vars'];
          if (vars is! Map) return 0;
          return vars.keys
              .where((k) => !_varDebugKeys.contains(k.toString()))
              .length;
        }(),
      BackupCategory.debugConfig => () {
          final vars = s['vars'];
          if (vars is! Map) return 0;
          return vars.keys
              .where((k) => _varDebugKeys.contains(k.toString()))
              .length;
        }(),
      BackupCategory.vpnSettings => vpnSettings?.length ?? 0,
    };
  }


  String? get routingFinalOutbound => storage?['route_final'] as String?;



  ({int subs, int custom}) splitServerLists() {
    final subs =
        _serverLists.items.whereType<SubscriptionServers>().length;
    return (subs: subs, custom: _serverLists.count - subs);
  }

  static bool _hasAnyRouting(Map<String, dynamic> s) {

    for (final k in _topLevelRoutingKeys) {
      final v = s[k];
      if (v is List && v.isNotEmpty) return true;
      if (v is Map && v.isNotEmpty) return true;
      if (v is String && v.isNotEmpty) return true;
    }
    return false;
  }

  static bool _hasAnyApp(Map<String, dynamic> s) {
    final vars = s['vars'];
    if (vars is Map) {
      for (final k in vars.keys) {
        if (!_varDebugKeys.contains(k.toString())) return true;
      }
    }
    for (final k in _topLevelAppKeys) {
      if (s[k] != null) return true;
    }
    return false;
  }

  static bool _hasAnyDebug(Map<String, dynamic> s) {
    final vars = s['vars'];
    if (vars is! Map) return false;
    for (final k in vars.keys) {
      if (_varDebugKeys.contains(k.toString())) return true;
    }
    return false;
  }
}




typedef _EntitiesRead<T> = ({List<T> items, List<Object> corrupt});

extension<T> on _EntitiesRead<T> {
  int get count => items.length + corrupt.length;
}

_EntitiesRead<T> _readEntities<T>(
  Map<String, dynamic>? doc,
  List<T> Function(
    Map<String, dynamic> doc, {
    void Function(Object error)? onCorrupt,
  }) read,
) {
  final corrupt = <Object>[];
  final items = doc == null ? <T>[] : read(doc, onCorrupt: corrupt.add);
  return (items: items, corrupt: corrupt);
}


class BackupApplyResult {
  const BackupApplyResult({
    this.serverListsApplied = 0,
    this.routingApplied = 0,
    this.appSettingsApplied = 0,
    this.debugConfigApplied = 0,
    this.vpnSettingsApplied = 0,
    this.droppedKeys = const [],
    this.errors = const [],
  });

  final int serverListsApplied;
  final int routingApplied;
  final int appSettingsApplied;
  final int debugConfigApplied;
  final int vpnSettingsApplied;




  final List<String> droppedKeys;

  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;
}




















class BackupService {
  const BackupService();


  Future<String> buildExport({required Set<BackupCategory> include}) async {
    final out = <String, dynamic>{
      'app': 'lxbox',
      'kind': 'backup',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      final info = await PackageInfo.fromPlatform();
      out['source_app_version'] = '${info.version}+${info.buildNumber}';
    } catch (_) {

    }

    final raw = await SettingsStorage.exportRaw();
    final filtered = filterStorageForExport(raw, include: include);
    if (filtered.isNotEmpty) {
      out['storage'] = filtered;
    }

    if (include.contains(BackupCategory.vpnSettings)) {
      out['vpn_settings'] = await _readVpnSettings();
    }

    return const JsonEncoder.withIndent('  ').convert(out);
  }


  Future<BackupContents> parseImport(String raw) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      throw const FormatException(
          'Not a valid JSON file. Make sure you picked a LxBox backup file.');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup root must be a JSON object.');
    }

    final app = decoded['app']?.toString();
    final kind = decoded['kind']?.toString();
    if (app != 'lxbox' || kind != 'backup') {
      throw const FormatException(
          'Not a LxBox backup file (missing or invalid app/kind markers).');
    }

    final storage = decoded['storage'];
    if (storage is! Map<String, dynamic>) {
      throw const FormatException(
          'Unsupported backup format. Re-export from a recent app version.');
    }

    DateTime? createdAt;
    final createdRaw = decoded['created_at']?.toString();
    if (createdRaw != null) {
      createdAt = DateTime.tryParse(createdRaw);
    }

    Map<String, dynamic>? vpn;
    final rawVpn = decoded['vpn_settings'];
    if (rawVpn is Map<String, dynamic>) {
      vpn = Map<String, dynamic>.from(rawVpn);
    }

    final legacy = storageDocNeedsMigration(storage);
    return BackupContents(
      createdAt: createdAt,
      sourceAppVersion: decoded['source_app_version']?.toString(),
      storage: storage,
      vpnSettings: vpn,
      presetIdByDnsServerTag: legacy
          ? await SettingsStorage.presetIdsForMigration()
          : const {},


      subscriptionBodies: legacy
          ? await SettingsStorage.subscriptionBodiesForMigration(storage)
          : const {},

      recordVars: legacy ? await loadRecordVarDecls() : RecordVarDecls.none,
    );
  }




  Future<BackupApplyResult> applyImport(
    BackupContents contents, {
    required bool merge,
    required Set<BackupCategory> include,
  }) async {
    final errors = <String>[];
    final droppedKeys = <String>[];
    var serverLists = 0;
    var routing = 0;
    var appS = 0;
    var debug = 0;
    var vpn = 0;

    final raw = contents.storage;
    if (raw != null) {
      final migration = contents.storageMigration;
      if (migration != null && migration.migrated) {
        AppLog.I.info('Backup import: storage block migrated to '
            'storage_version ${storageDocVersion(migration.doc)}'
            '${migration.summary.isEmpty ? '' : ' — ${migration.summary}'}');
      }
      if (migration != null && migration.warnings.isNotEmpty) {
        AppLog.I.warning('Backup import: storage migration losses: '
            '${migration.warnings.join('; ')}');
      }





      final mergeServerLists =
          merge && include.contains(BackupCategory.serverLists);

      final mergeChains = mergeServerLists;
      final filtered = _filterStorage(raw, include: include);
      if (merge) filtered.remove(kSourcesKey);

      if (mergeServerLists) {
        for (final e in contents._serverLists.corrupt) {
          errors.add('Server list parse: $e');
        }
        try {
          final existing = await SettingsStorage.getServerLists();
          final ids = existing.map((e) => e.id).toSet();
          for (final list in contents._serverLists.items) {
            if (ids.add(list.id)) {
              existing.add(list);
              serverLists++;
            }
          }
          if (serverLists > 0) await SettingsStorage.saveServerLists(existing);
        } catch (e) {
          errors.add('Server lists: $e');
        }
      } else if (include.contains(BackupCategory.serverLists)) {
        serverLists = contents.countFor(BackupCategory.serverLists);
      }

      if (mergeChains) {
        for (final e in contents._chains.corrupt) {
          errors.add('Chain parse: $e');
        }


        if (contents._chains.items.isNotEmpty) {
          try {
            await SettingsStorage.setChains(contents._chains.items);
          } catch (e) {
            errors.add('Chains: $e');
          }
        }
      }

      try {



        final dropped = await SettingsStorage.replaceRaw(filtered, merge: merge);
        droppedKeys.addAll(dropped);
        if (dropped.isNotEmpty) {
          AppLog.I.warning(
              'Backup import dropped ${dropped.length} unknown key(s): '
              '${dropped.join(', ')}');
        }
      } catch (e) {
        errors.add('Storage: $e');
      }




      try {
        final template = await TemplateLoader.load();
        await SettingsStorage.migrateDirectionsIfNeeded(
          template.groupTemplates,
          varDefaults: {
            for (final v in template.vars) v.name: v.defaultValue,
          },
        );
      } catch (e) {
        errors.add('Directions migration: $e');
      }

      routing = contents.countFor(BackupCategory.routing);
      appS = contents.countFor(BackupCategory.appSettings);
      debug = contents.countFor(BackupCategory.debugConfig);
      if (!include.contains(BackupCategory.routing)) routing = 0;
      if (!include.contains(BackupCategory.appSettings)) appS = 0;
      if (!include.contains(BackupCategory.debugConfig)) debug = 0;
    }

    if (include.contains(BackupCategory.vpnSettings) &&
        contents.vpnSettings != null) {
      vpn = await _applyVpnSettings(contents.vpnSettings!, errors);
    }

    return BackupApplyResult(
      serverListsApplied: serverLists,
      routingApplied: routing,
      appSettingsApplied: appS,
      debugConfigApplied: debug,
      vpnSettingsApplied: vpn,
      droppedKeys: droppedKeys,
      errors: errors,
    );
  }




  Future<Map<String, dynamic>> _readVpnSettings() =>
      SettingsStorage.exportNativePrefsBackup();

  Future<int> _applyVpnSettings(
          Map<String, dynamic> data, List<String> errors) =>
      SettingsStorage.applyNativePrefsBackup(data,
          onError: (key, e) => errors.add('vpn_settings.$key: $e'));





  static Future<String> suggestedFilename() async {
    String appVersion = '0';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
    } catch (_) {}
    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    final date =
        '${now.year}${pad(now.month)}${pad(now.day)}-${pad(now.hour)}${pad(now.minute)}';
    return 'lxbox-backup-v$appVersion-$date.json';
  }


  @visibleForTesting
  static Map<String, dynamic> filterStorageForExport(
    Map<String, dynamic> raw, {
    required Set<BackupCategory> include,
  }) {
    return _filterStorage(raw, include: include);
  }













  static Map<String, dynamic> _filterStorage(
    Map<String, dynamic> raw, {
    required Set<BackupCategory> include,
  }) {
    final wantServers = include.contains(BackupCategory.serverLists);
    final wantRouting = include.contains(BackupCategory.routing);
    final wantApp = include.contains(BackupCategory.appSettings);
    final wantDebug = include.contains(BackupCategory.debugConfig);

    final out = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key == kStorageVersionKey) {


        out[key] = value;
      } else if (key == kSourcesKey) {


        if (value is List && wantServers) {
          out[key] = [for (final r in value) deepCloneJson(r)];
        }
      } else if (key == 'vars') {
        if (value is Map) {
          final filteredVars = <String, dynamic>{};
          for (final v in value.entries) {
            final vk = v.key.toString();
            final isDebug = _varDebugKeys.contains(vk);
            if (isDebug && wantDebug) {
              filteredVars[vk] = deepCloneJson(v.value);
            } else if (!isDebug && wantApp) {
              filteredVars[vk] = deepCloneJson(v.value);
            }
          }
          if (filteredVars.isNotEmpty) out[key] = filteredVars;
        }
      } else if (_topLevelRoutingKeys.contains(key)) {
        if (wantRouting) out[key] = deepCloneJson(value);
      } else if (_topLevelAppKeys.contains(key)) {
        if (wantApp) out[key] = deepCloneJson(value);
      }






    }
    return out;
  }
}
