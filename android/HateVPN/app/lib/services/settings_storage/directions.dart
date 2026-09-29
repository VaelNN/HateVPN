part of '../settings_storage.dart';


























typedef DirectionHealResult = ({
  int rules,
  int detours,
  int includes,
  int chainPositions,
  int dnsServers,
});

Future<List<Direction>> _getDirections() async {
  final data = await _load();
  final raw = data['directions'] as List<dynamic>? ?? const [];
  return raw.whereType<Map<String, dynamic>>().map(Direction.fromJson).toList();
}

Future<void> _setDirections(List<Direction> directions, {bool flush = true}) async {
  final data = await _load();
  data['directions'] = directions.map((c) => c.toJson()).toList();
  SettingsStorage._cache = data;
  SettingsStorage.markConfigDirty();
  if (flush) await _save();
}












Future<Direction> _addDirection({String? label, String? tag}) async {
  final directions = (await _getDirections()).toList();
  final used = directions.map((c) => c.tag).toList();
  final wanted = (tag ?? nextDirectionTag(used)).trim();
  final conflict = directionTagConflict(wanted, used);
  if (conflict != null) {
    throw StateError('direction tag "$wanted" rejected: $conflict');
  }


  final ch = Direction(
      tag: wanted, label: label ?? defaultLabelForTag(wanted), enabled: true);
  directions.add(ch);
  await _setDirections(directions);
  return ch;
}

Future<DirectionHealResult> _updateDirection(Direction direction) async {
  final directions = (await _getDirections()).toList();
  final i = directions.indexWhere((c) => c.tag == direction.tag);
  if (i < 0) throw StateError('direction not found: ${direction.tag}');












  final was = directions[i];
  directions[i] = direction;
  final disabling = was.enabled && !direction.enabled;
  final flagUnset = was.isDetour && !direction.isDetour;
  var rules = 0;
  var detours = 0;
  var dnsServers = 0;
  if (disabling || flagUnset) {
    await _setDirections(directions, flush: false);
    if (disabling) {
      final healed = await _healDirectionRefs(direction.tag);
      rules = healed.rules;
      dnsServers = healed.dnsServers;
    }
    detours = await _healDetourDirectionRefs(direction.tag);
    await _save();
  } else {
    await _setDirections(directions);
  }








  return (
    rules: rules,
    detours: detours,
    includes: 0,
    chainPositions: 0,
    dnsServers: dnsServers,
  );
}







Future<DirectionHealResult> _deleteDirection(String tag) async {
  if (tag == 'vpn-1') throw StateError('vpn-1 is not deletable');
  var directions = (await _getDirections()).toList()
    ..removeWhere((c) => c.tag == tag);



  final (:healed, :count) = clearIncludeDirectionRefs(directions, tag);
  directions = healed;
  await _setDirections(directions, flush: false);
  final (:rules, :dnsServers) = await _healDirectionRefs(tag);
  final detours = await _healDetourDirectionRefs(tag);
  await _healPingOptionsGroupRefs(tag);
  await _save();
  return (
    rules: rules,
    detours: detours,
    includes: count,
    chainPositions: 0,
    dnsServers: dnsServers,
  );
}




























Future<void> _healPingOptionsGroupRefs(String deletedTag) async {
  final autoTag = '$deletedTag-auto';
  final data = await _load();
  final opts = data['ping_options'];
  if (opts is! Map<String, dynamic>) return;
  if (!_dropPingGroupKeys(opts, (t) => t == deletedTag || t == autoTag)) return;
  data['ping_options'] = opts;
  SettingsStorage._cache = data;
}



















Future<({int rules, int dnsServers})> _healDirectionRefs(
    String deletedTag) async {
  final autoTag = '$deletedTag-auto';
  final retarget = directionRefRetarget(deletedTag, 'vpn-1');
  final decls = await loadRecordVarDecls();
  var count = 0;

  final routeFinal = await SettingsStorage.getRouteFinal();
  if (routeFinal == deletedTag || routeFinal == autoTag) {
    await SettingsStorage.saveRouteFinal('vpn-1', flush: false);
    count++;
  }








  final rules = await SettingsStorage.getCustomRules();
  var changed = false;
  final healed = rules.map((r) {
    final next = r is CustomRulePreset
        ? retargetPresetOutboundVars(r, decls, retarget)
        : (r.outbound == deletedTag || r.outbound == autoTag)
            ? r.withOutbound('vpn-1')
            : r;
    if (!identical(next, r)) {
      changed = true;
      count++;
    }
    return next;
  }).toList();
  if (changed) {
    await SettingsStorage.saveCustomRules(healed, flush: false);
  }
  return (
    rules: count,
    dnsServers: await _healDnsServerDirectionRefs(retarget, decls),
  );
}






Future<int> _healDnsServerDirectionRefs(
  Map<String, String> retarget,
  RecordVarDecls decls,
) async {
  var count = 0;
  final servers = await SettingsStorage.getDnsServers();
  var rootCount = 0;
  final healedServers = <DnsServerRef>[];
  for (final s in servers) {
    final next = retargetDnsServerDirectionRefs(s, decls, retarget);
    if (!identical(next, s)) rootCount++;
    healedServers.add(next);
  }
  if (rootCount > 0) {
    await SettingsStorage.saveDnsServers(healedServers, flush: false);
  }
  count += rootCount;
  return count;
}









Future<int> _healDetourDirectionRefs(String tag) async {
  final lists = await _getServerLists();
  var count = 0;
  var changed = false;
  final healed = <ServerList>[];
  for (final l in lists) {

    final r = clearDetourDirectionRefs(l, tag);
    if (r.healed != null) {
      changed = true;
      count += r.count;
      healed.add(r.healed!);
    } else {
      healed.add(l);
    }
  }
  if (changed) await _saveServerLists(healed, flush: false);
  return count;
}






















































bool _ensureRequiredDirection(Map<String, dynamic> data) {
  final raw = data['directions'];
  if (raw is! List) return false;
  for (final e in raw) {
    if (e is Map && e['tag'] == 'vpn-1') return false;
  }
  data['directions'] = [
    Direction(
      tag: 'vpn-1',
      label: defaultLabelForTag('vpn-1'),
      enabled: true,
    ).toJson(),
    ...raw,
  ];
  return true;
}






























bool _pruneOrphanPingGroups(Map<String, dynamic> data) {
  final opts = data['ping_options'];
  if (opts is! Map<String, dynamic>) return false;
  if (opts['groups'] is! Map<String, dynamic>) return false;
  final alive = <String>{};
  final raw = data['directions'];
  if (raw is List) {
    for (final e in raw) {
      if (e is Map) {
        final tag = e['tag'];
        if (tag is String && tag.isNotEmpty) {
          alive.add(tag);
          alive.add('$tag-auto');
        }
      }
    }
  }
  if (!_dropPingGroupKeys(opts, (t) => !alive.contains(t))) return false;
  data['ping_options'] = opts;
  return true;
}

Future<void> _migrateDirectionsIfNeeded(
  GroupTemplates gt, {
  Map<String, String> varDefaults = const {},
}) async {
  final data = await _load();


  if (data['directions'] is List) {
    var dirty = false;
    if (_ensureRequiredDirection(data)) dirty = true;
    if (_pruneOrphanPingGroups(data)) dirty = true;
    if (dirty) {
      SettingsStorage._cache = data;
      await _save();
    }
    return;
  }



  if (data['directions_migrated'] == true) {
    data['directions_migrated'] = true;


    _pruneOrphanPingGroups(data);
    SettingsStorage._cache = data;
    await _save();
    return;
  }



  final enabled = await SettingsStorage.getEnabledGroups();
  final hasAuto = gt.direction.include.contains('auto');
  final directions = <Direction>[];
  for (final dc in gt.defaultDirections) {
    final isEnabled = dc.tag == 'vpn-1'
        ? true
        : (enabled.isEmpty ? dc.defaultEnabled : enabled.contains(dc.tag));
    final auto = hasAuto
        ? _seedAutoFromTemplate(gt.auto, varDefaults: varDefaults)
        : null;
    directions.add(
        Direction.seedFromDefault(dc, gt.direction, enabled: isEnabled, auto: auto));
  }

  data['directions'] = directions.map((c) => c.toJson()).toList();
  data['directions_migrated'] = true;
  _pruneOrphanPingGroups(data);
  SettingsStorage._cache = data;
  await _save();
}












DirectionAuto _seedAutoFromTemplate(
  AutoTemplate at, {
  Map<String, String> varDefaults = const {},
}) {
  final opts = at.options;


  String? fromVar(Object? v) {
    if (v is! String || !v.startsWith('@')) return null;
    final d = varDefaults[v.substring(1)];
    return (d != null && d.isNotEmpty) ? d : null;
  }


  String? str(Object? v) {
    if (v is! String || v.isEmpty || v.startsWith('@')) return null;
    return v;
  }


  int? toInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String && !v.startsWith('@')) return int.tryParse(v.trim());
    return null;
  }



  const fallback = DirectionAuto();
  return DirectionAuto(
    url: str(opts['url']) ?? fromVar(opts['url']) ?? fallback.url,
    interval: str(opts['interval']) ?? fromVar(opts['interval']) ?? fallback.interval,
    tolerance: toInt(opts['tolerance']) ??
        int.tryParse(fromVar(opts['tolerance']) ?? '') ??
        fallback.tolerance,
    idleTimeout: fallback.idleTimeout,
    interruptExistConnections: fallback.interruptExistConnections,
  );
}
