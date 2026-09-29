part of '../settings_storage.dart';







Future<Map<String, dynamic>> _dumpCache() async {
  final data = await _load();
  return jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
}






















Future<List<String>> _replaceRaw(
  Map<String, dynamic> snapshot, {
  bool merge = false,
}) async {


  final template = await TemplateLoader.load();




  final doc = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  final migration = migrateStorageDoc(
    doc,
    presetIdByDnsServerTag: presetIdsByDnsServerTag(template.selectableRules),
    subscriptionBodies: storageDocNeedsMigration(doc)
        ? await _subscriptionBodiesForMigration(doc)
        : const {},
    recordVars: RecordVarDecls.fromTemplate(template),
  );
  if (migration.info.isNotEmpty) {
    AppLog.I.info('replaceRaw: snapshot migrated to storage_version '
        '${storageDocVersion(migration.doc)} — ${migration.summary}');
  }
  if (migration.warnings.isNotEmpty) {
    AppLog.I.warning('replaceRaw: snapshot migration losses: '
        '${migration.warnings.join('; ')}');
  }
  final clean = migration.doc;

  final allowedVars =
      SettingsStorage.allowedVarKeys(template.vars.map((v) => v.name));

  final dropped = <String>[];
  final filtered = <String, dynamic>{};
  for (final entry in clean.entries) {
    final key = entry.key;
    final value = entry.value;
    if (!SettingsStorage.allowedTopLevelKeys.contains(key)) {
      dropped.add(key);
      continue;
    }
    if (key == 'vars' && value is Map) {
      final outVars = <String, dynamic>{};
      for (final v in value.entries) {
        final vk = v.key.toString();
        if (allowedVars.contains(vk)) {
          outVars[vk] = v.value;
        } else {
          dropped.add('vars.$vk');
        }
      }
      filtered[key] = outVars;
    } else {
      filtered[key] = value;
    }
  }

  if (!merge) {


    final current = await _load();
    final currentVars = current['vars'];
    if (currentVars is Map) {
      final outVars = (filtered['vars'] as Map<String, dynamic>?) ??
          <String, dynamic>{};
      for (final k in const {
        ...SettingsStorage.debugApiVarKeys,
        ...SettingsStorage.startupPromptVarKeys,
      }) {
        if (!outVars.containsKey(k) && currentVars.containsKey(k)) {
          outVars[k] = currentVars[k];
        }
      }
      if (outVars.isNotEmpty) filtered['vars'] = outVars;
    }
    SettingsStorage._cache = filtered;
    await _save();
    return dropped;
  }

  final current = await _load();
  for (final entry in filtered.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key == 'vars' && value is Map<String, dynamic>) {
      final existing = (current['vars'] as Map<String, dynamic>?) ?? {};
      for (final v in value.entries) {
        existing[v.key] = v.value;
      }
      current['vars'] = existing;
    } else {
      current[key] = value;
    }
  }
  SettingsStorage._cache = current;
  await _save();
  return dropped;
}

Future<TunAppsConfig> _getTunApps() async {
  final data = await _load();
  final raw = data['tun_apps'];
  if (raw is Map<String, dynamic>) {
    final mode = raw['mode'];
    final packages = (raw['packages'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];
    if (mode == SettingsStorage._tunAppsModeAllow ||
        mode == SettingsStorage._tunAppsModeDeny ||
        mode == SettingsStorage._tunAppsModeOff) {
      return TunAppsConfig(mode: mode as String, packages: packages);
    }
  }
  return const TunAppsConfig(
    mode: SettingsStorage._tunAppsModeOff,
    packages: <String>[],
  );
}

Future<void> _setTunApps(TunAppsConfig cfg, {bool flush = true}) async {
  if (!TunAppsConfig.isValidMode(cfg.mode)) {
    throw ArgumentError('tun_apps.mode must be off|allow|deny: ${cfg.mode}');
  }
  final dedup = <String>{};
  for (final p in cfg.packages) {
    final t = p.trim();
    if (t.isEmpty) continue;
    dedup.add(t);
  }
  final data = await _load();
  data['tun_apps'] = {
    'mode': cfg.mode,
    'packages': dedup.toList()..sort(),
  };
  SettingsStorage._cache = data;
  SettingsStorage.markConfigDirty();
  if (flush) await _save();
}


class TunAppsConfig {
  const TunAppsConfig({required this.mode, required this.packages});


  final String mode;
  final List<String> packages;



  static bool isValidMode(String mode) =>
      mode == 'off' || mode == 'allow' || mode == 'deny';

  bool get isOff => mode == 'off';
  bool get isAllow => mode == 'allow';
  bool get isDeny => mode == 'deny';

  TunAppsConfig copyWith({String? mode, List<String>? packages}) =>
      TunAppsConfig(
        mode: mode ?? this.mode,
        packages: packages ?? this.packages,
      );

  Map<String, Object?> toJson() => {'mode': mode, 'packages': packages};
}
