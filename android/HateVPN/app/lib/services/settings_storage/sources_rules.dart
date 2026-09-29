part of '../settings_storage.dart';































List<SourceEntry> _sourceEntriesOf(
  Map<String, dynamic> doc, {
  void Function(Object error)? onCorrupt,
  void Function(String note)? onNote,
}) {
  final records = _recordsAt(doc[kSourcesKey]);
  final out = <SourceEntry>[];
  for (var i = 0; i < records.length; i++) {
    final r = records[i];
    final notes = <String>[];
    if (_isChainRecord(r)) {
      final read = chainFromRecord(r, notes: notes);
      final chain = read.value;
      if (chain == null) {
        onCorrupt?.call(read.dropped!);
        out.add(OpaqueEntry(r, i));
        continue;
      }
      if (onNote != null) {
        notes.forEach(onNote);
        if (read.unknownKeys.isNotEmpty) {
          onNote('chain "${chain.tag}": keys not kept by the model: '
              '${read.unknownKeys.join(', ')}');
        }
      }
      out.add(ChainEntry(chain));
      continue;
    }
    final read = sourceFromRecord(r, notes: notes);
    final list = read.value;
    if (list == null) {
      onCorrupt?.call(read.dropped!);
      out.add(OpaqueEntry(r, i));
      continue;
    }
    if (onNote != null) {
      notes.forEach(onNote);
      if (read.unknownKeys.isNotEmpty) {
        onNote('${r['kind']} "${list.id}": keys not kept by the model: '
            '${read.unknownKeys.join(', ')}');
      }
    }
    out.add(ContainerEntry(list));
  }
  return out;
}

Future<List<SourceEntry>> _getSourceEntries() async => _sourceEntriesOf(
      await _load(),
      onCorrupt: (e) => AppLog.I.warning('Skipping unreadable source record: $e'),
      onNote: _logStorageNoteOnce,
    );






Future<void> _writeEntries(List<SourceEntry> entries,
    {bool flush = true}) async {
  final data = await _load();
  data[kSourcesKey] = [
    for (final e in entries)
      switch (e) {
        ContainerEntry(:final list) => sourceToRecord(list),
        ChainEntry(:final chain) => chainToRecord(chain),
        OpaqueEntry(:final record) => record,
      },
  ];
  SettingsStorage._cache = data;
  if (flush) await _save();
}



Future<void> _saveSourceEntries(List<SourceEntry> entries,
    {bool flush = true}) async {
  await _writeEntries(entries, flush: flush);
  SettingsStorage.markConfigDirty();
}

Future<List<ServerList>> _getServerLists() async => _serverListsOf(
      await _load(),
      onCorrupt: (e) => AppLog.I.warning('Skipping unreadable source record: $e'),
      onNote: _logStorageNoteOnce,
    );



List<ServerList> _serverListsOf(
  Map<String, dynamic> doc, {
  void Function(Object error)? onCorrupt,
  void Function(String note)? onNote,
}) =>
    [
      for (final e
          in _sourceEntriesOf(doc, onCorrupt: onCorrupt, onNote: onNote))
        if (e is ContainerEntry) e.list,
    ];





Future<void> _saveServerLists(List<ServerList> lists,
        {bool flush = true}) async =>
    _writeEntries(
      _replaceKind<ContainerEntry>(
        await _getSourceEntries(),
        [for (final l in lists) ContainerEntry(l)],
      ),
      flush: flush,
    );















List<SourceEntry> _replaceKind<T extends SourceEntry>(
  List<SourceEntry> all,
  List<SourceEntry> ours,
) {
  final slotKeys = {
    for (final e in all)
      if (e is T) e.sourceKey,
  };
  final survivors = <SourceEntry>[];
  final fresh = <SourceEntry>[];
  for (final e in ours) {
    (slotKeys.contains(e.sourceKey) ? survivors : fresh).add(e);
  }
  final survivorKeys = {for (final e in survivors) e.sourceKey};
  final out = <SourceEntry>[];
  var next = 0;
  for (final e in all) {
    if (e is! T) {
      out.add(e);
    } else if (survivorKeys.contains(e.sourceKey) && next < survivors.length) {
      out.add(survivors[next++]);
    }
  }
  out
    ..addAll(survivors.skip(next))
    ..addAll(fresh);
  return out;
}

Future<List<String>> _getSourceKeys() async =>
    [for (final e in await _getSourceEntries()) e.sourceKey];










Future<bool> _reorderSources(List<String> keys) async {
  final entries = await _getSourceEntries();
  bool reject(String why) {
    AppLog.I.warning('reorderSources rejected: $why '
        '(keys=${keys.length}, records=${entries.length})');
    return false;
  }

  final want = keys.toSet();
  if (want.length != keys.length) return reject('duplicate key');
  final byKey = <String, SourceEntry>{};
  for (final e in entries) {
    final k = e.sourceKey;
    if (!want.contains(k)) continue;
    if (byKey.containsKey(k)) return reject('ambiguous record $k');
    byKey[k] = e;
  }
  if (byKey.length != keys.length) {
    return reject('unknown key ${want.difference(byKey.keys.toSet()).first}');
  }
  var next = 0;
  await _saveSourceEntries([
    for (final e in entries)
      want.contains(e.sourceKey) ? byKey[keys[next++]]! : e,
  ]);
  return true;
}


List<Map<String, dynamic>> _recordsAt(Object? raw) => raw is List
    ? [
        for (final e in raw)
          if (e is Map<String, dynamic>)
            e
          else if (e is Map)
            e.cast<String, dynamic>(),
      ]
    : const [];

bool _isChainRecord(Map<String, dynamic> r) => r['kind'] == kSourceKindChain;




final Set<String> _loggedStorageNotes = {};

void _logStorageNoteOnce(String note) {
  if (_loggedStorageNotes.add(note)) {
    AppLog.I.warning('SettingsStorage: $note');
  }
}







Future<Set<String>> _getEnabledGroups() async {
  final data = await _load();
  final list = data['enabled_groups'] as List<dynamic>? ?? [];
  return list.map((e) => e.toString()).toSet();
}

Future<void> _saveEnabledGroups(Set<String> groups,
    {bool flush = true}) async {
  final data = await _load();
  data['enabled_groups'] = groups.toList();
  SettingsStorage._cache = data;
  SettingsStorage.markConfigDirty();
  if (flush) await _save();
}





Future<DateTime?> _getLastGlobalUpdate() async {
  final data = await _load();
  final raw = data['last_global_update'] as String?;
  if (raw == null) return null;
  return DateTime.tryParse(raw);
}

Future<void> _setLastGlobalUpdate(DateTime dt) async {
  final data = await _load();
  data['last_global_update'] = dt.toIso8601String();
  SettingsStorage._cache = data;
  await _save();
}

Duration? _parseReloadInterval(String reload) {
  final trimmed = reload.trim().toLowerCase();
  if (trimmed.isEmpty) return null;
  final match = RegExp(r'^(\d+)\s*(h|m|s)$').firstMatch(trimmed);
  if (match == null) return null;
  final value = int.parse(match.group(1)!);
  return switch (match.group(2)) {
    'h' => Duration(hours: value),
    'm' => Duration(minutes: value),
    's' => Duration(seconds: value),
    _ => null,
  };
}

Future<bool> _shouldRefreshSubscriptions(String reloadInterval) async {
  final interval = SettingsStorage.parseReloadInterval(reloadInterval);
  if (interval == null) return false;
  final lastUpdate = await SettingsStorage.getLastGlobalUpdate();
  if (lastUpdate == null) return true;
  return DateTime.now().difference(lastUpdate) >= interval;
}









Future<List<CustomRule>> _getCustomRules() async {
  final data = await _load();
  final rules = _customRulesOf(data);



  if (data['hatevpn_full_tunnel_v1'] == true) return rules;
  const directPresets = {'ru-direct', 'bittorrent', 'vowifi'};
  final updated = <CustomRule>[
    for (final rule in rules)
      if (rule is CustomRulePreset && directPresets.contains(rule.presetId))
        rule.copyWith(enabled: false)
      else
        rule,
  ];
  data['hatevpn_full_tunnel_v1'] = true;
  SettingsStorage._cache = data;
  if (updated.any((rule) => rule is CustomRulePreset &&
      directPresets.contains(rule.presetId))) {
    await _saveCustomRules(updated);
  } else {
    await _save();
  }
  return updated;
}










List<CustomRule> _customRulesOf(
  Map<String, dynamic> doc, {
  void Function(Object error)? onCorrupt,
}) {
  final out = <CustomRule>[];
  for (final r in _recordsAt(doc[kRulesKey])) {
    final read = ruleFromRecord(r, unknownAsVerbatim: true);
    final rule = read.value;
    if (rule != null) {
      out.add(rule);
    } else if (onCorrupt != null) {
      onCorrupt(read.dropped!);
    } else {
      throw FormatException('unreadable rule record: ${read.dropped}');
    }
  }
  return out;
}







Future<void> _saveCustomRules(List<CustomRule> rules,
    {bool flush = true}) async {
  final decls = await loadRecordVarDecls();
  final data = await _load();
  data[kRulesKey] = [
    for (final r in splitJsonRuleArrays(normalizePresetRulesVars(rules, decls)))
      ruleToRecord(r),
  ];
  SettingsStorage._cache = data;
  SettingsStorage.markConfigDirty();
  if (flush) await _save();
}












Future<bool> _hasDefaultsSeeded() async {
  final data = await _load();
  return data['presets_migrated'] == true;
}

Future<void> _markDefaultsSeeded() async {
  final data = await _load();
  data['presets_migrated'] = true;

  data[_kLatePresetsSeededKey] = kLateDefaultPresetIds.toList()..sort();
  SettingsStorage._cache = data;
  await _save();
}





const Set<String> kLateDefaultPresetIds = {'tailscale'};



const String _kLatePresetsSeededKey = 'late_presets_seeded';









Future<bool> _seedLateDefaultPresets(WizardTemplate? template) async {
  final data = await _load();
  if (data['presets_migrated'] != true) return false;
  final done = <String>{
    ...(data[_kLatePresetsSeededKey] as List? ?? const []).whereType<String>(),
  };
  final pending = kLateDefaultPresetIds.difference(done);
  if (pending.isEmpty) return false;

  final WizardTemplate tpl;
  try {
    tpl = template ?? await TemplateLoader.load();
  } catch (e) {
    AppLog.I.warning('SettingsStorage: late presets not seeded, '
        'template unavailable: $e');
    return false;
  }
  final rules = _customRulesOf(data);
  final present = {
    for (final cr in rules)
      if (cr is CustomRulePreset) cr.presetId,
  };
  var added = false;
  for (final id in pending.toList()..sort()) {
    if (present.contains(id)) continue;
    SelectableRule? spec;
    for (final p in tpl.selectableRules) {
      if (p.presetId == id) {
        spec = p;
        break;
      }
    }
    if (spec == null || !spec.defaultEnabled) continue;
    final seeded = selectableRuleToCustom(spec, tpl);
    rules.add(CustomRulePreset(
      name: seeded.name,
      presetId: seeded.presetId,
      varsValues: seeded.varsValues,
      orderNum: spec.num,
    ));
    added = true;
    AppLog.I.info('SettingsStorage: default preset "$id" added once');
  }
  data[_kLatePresetsSeededKey] = ({...done, ...pending}.toList()..sort());
  SettingsStorage._cache = data;
  if (added) {
    await _saveCustomRules(rules);
  } else {
    await _save();
  }
  return added;
}
