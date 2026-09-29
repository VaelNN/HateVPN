









library;

import '../../models/codec/auto_group_record.dart';
import '../../models/codec/chain_record.dart';
import '../../models/codec/dns_record.dart';
import '../../models/codec/rule_record.dart';
import '../../models/codec/source_record.dart';
import '../../models/custom_rule.dart';
import '../../models/dns_ref.dart';
import '../../models/node_link.dart';
import '../../models/node_spec.dart';
import '../../models/parser_config.dart' show SelectableRule;
import '../../models/server_list.dart';
import '../json_clone.dart' show deepCloneJson;
import '../record_vars.dart';
import '../parser/body_decoder.dart';
import '../parser/parse_all.dart';
import '../settings_storage_keys.dart';
import 'legacy_autogroup.dart';
import 'legacy_form_v0.dart';
import 'migrate_node_links.dart';


const Set<String> kLegacyStorageKeys = {
  _kServerLists,
  _kChains,
  _kCustomRules,
  _kDnsOptions,
};

const _kServerLists = 'server_lists';
const _kChains = 'chains';
const _kCustomRules = 'custom_rules';
const _kDnsOptions = 'dns_options';


const _kLegacyDirections = 'channels';
const _kLegacyDirectionsMigrated = 'channels_migrated';


const Set<String> _kDeadTopLevelKeys = {
  'excluded_nodes',
  'preset_ids_remapped',
  'proxy_sources',
  'app_rules',
  'enabled_rules',
  'rule_outbounds',
  'node_overrides',
  'show_detour_servers',
};


const Set<String> _kDeadVarKeys = {'auto_rebuild'};


final class StorageMigrationResult {
  const StorageMigrationResult({
    required this.doc,
    required this.migrated,
    this.foundVersion,
    this.info = const [],
    this.warnings = const [],
  });



  final Map<String, dynamic> doc;


  final bool migrated;


  final int? foundVersion;


  final List<String> info;


  final List<String> warnings;


  String get summary => info.join('; ');


  Map<String, dynamic> toReportJson() => {
        'migrated': migrated,
        if (foundVersion != null) 'found_version': foundVersion,
        if (info.isNotEmpty) 'info': info,
        if (warnings.isNotEmpty) 'warnings': warnings,
      };
}









Map<String, String> presetIdsByDnsServerTag(Iterable<SelectableRule> presets) {
  final out = <String, String>{};
  final local = <String, String>{};
  for (final p in presets) {
    if (p.presetId.isEmpty) continue;
    for (final s in p.dnsServers) {
      final tag = s['tag'];
      if (tag is String && tag.isNotEmpty) {
        out.putIfAbsent('${p.presetId}:$tag', () => p.presetId);
        local.putIfAbsent(tag, () => p.presetId);
      }
    }
  }
  local.forEach((tag, id) => out.putIfAbsent(tag, () => id));
  return out;
}



int? storageDocVersion(Map<String, dynamic> doc) {
  final v = doc[kStorageVersionKey];
  return v is int && v >= 1 ? v : null;
}



bool storageDocNeedsMigration(Map<String, dynamic> doc) =>
    storageDocVersion(doc) == null ||
    kLegacyStorageKeys.any(doc.containsKey) ||
    _hasLegacyAutogroups(doc[kSourcesKey]);


























StorageMigrationResult migrateStorageDoc(
  Map<String, dynamic> doc, {
  Map<String, String> presetIdByDnsServerTag = const {},
  Map<String, String> subscriptionBodies = const {},
  RecordVarDecls recordVars = RecordVarDecls.none,
}) {
  final version = storageDocVersion(doc);
  final legacyPresent = [
    for (final k in kLegacyStorageKeys)
      if (doc.containsKey(k)) k,
  ];
  if (version != null && legacyPresent.isEmpty) {
    final sources = doc[kSourcesKey];
    if (sources is! List || !_hasLegacyAutogroups(sources)) {
      return StorageMigrationResult(
          doc: doc, migrated: false, foundVersion: version);
    }
    final info = <String>[];
    final warnings = <String>[];
    final out = deepCloneJson(doc) as Map<String, dynamic>;
    out[kSourcesKey] = migrateAutogroupMembers(
      [
        for (final e in out[kSourcesKey] as List)
          if (e is Map) e.cast<String, dynamic>(),
      ],
      info,
      warnings,
    );
    return StorageMigrationResult(
      doc: out,
      migrated: true,
      foundVersion: version,
      info: info,
      warnings: warnings,
    );
  }

  final info = <String>[];
  final warnings = <String>[];
  final convert = version == null;

  final rawVersion = doc[kStorageVersionKey];
  if (rawVersion != null && version == null) {
    warnings.add('storage_version "$rawVersion" is not a version, '
        'the document is read as the legacy form');
  }

  List<Map<String, dynamic>>? sources;
  List<Map<String, dynamic>>? rules;
  Map<String, dynamic>? dns;
  if (convert) {
    if (doc.containsKey(_kServerLists) || doc.containsKey(_kChains)) {


      sources = migrateNodeLinks(
        migrateAutogroupMembers(
            _convertSources(doc, info, warnings), info, warnings),
        directions: doc['directions'] ?? doc[_kLegacyDirections],
        subscriptionBodies: subscriptionBodies,
        info: info,
        warnings: warnings,
      );
    }
    if (doc.containsKey(_kCustomRules)) {
      rules = _convertRules(doc[_kCustomRules], recordVars, info, warnings);
    }
    if (doc.containsKey(_kDnsOptions)) {
      dns = _convertDns(doc[_kDnsOptions], presetIdByDnsServerTag, recordVars,
          info, warnings);
    }
  } else {
    warnings.add('storage_version $version with legacy keys '
        '${legacyPresent.join(', ')}: legacy keys dropped, '
        'records in $kSourcesKey/$kRulesKey/$kDnsKey kept');
  }

  final dropped = <String>[];
  final renamed = <String>[];





  final legacyDirectionsGuard = (doc.containsKey(_kLegacyDirections) ||
          doc.containsKey(_kLegacyDirectionsMigrated)) &&
      !doc.containsKey('directions_migrated') &&
      (doc['directions'] is List ||
          (doc[_kLegacyDirections] is List && !doc.containsKey('directions')));
  final out = <String, dynamic>{
    kStorageVersionKey: version ?? kStorageVersion,
  };
  for (final e in doc.entries) {
    final key = e.key;
    switch (key) {
      case kStorageVersionKey:
        break;
      case _kServerLists || _kChains:


        if (sources != null && !out.containsKey(kSourcesKey)) {
          out[kSourcesKey] = sources;
        }
      case _kCustomRules:
        if (rules != null) out[kRulesKey] = rules;
      case _kDnsOptions:
        if (dns != null) out[kDnsKey] = dns;
      case kSourcesKey when sources != null:
      case kRulesKey when rules != null:
      case kDnsKey when dns != null:
        warnings.add('"$key" without storage_version is replaced by '
            'the legacy keys of the same document');
      case _kLegacyDirections:

        if (e.value != null && !doc.containsKey('directions')) {
          out['directions'] = deepCloneJson(e.value);
          renamed.add('$key → directions');
        } else {
          dropped.add(key);
        }
      case _kLegacyDirectionsMigrated:
        if (e.value != null && !doc.containsKey('directions_migrated')) {
          out['directions_migrated'] =
              legacyDirectionsGuard ? true : deepCloneJson(e.value);
          renamed.add('$key → directions_migrated');
        } else {
          dropped.add(key);
        }
      case 'vars':
        final vars = e.value;
        if (vars is! Map) {
          out[key] = deepCloneJson(vars);
          break;
        }
        final outVars = <String, dynamic>{};
        for (final v in vars.entries) {
          if (_kDeadVarKeys.contains(v.key)) {
            dropped.add('vars.${v.key}');
          } else {
            outVars['${v.key}'] = deepCloneJson(v.value);
          }
        }
        out[key] = outVars;
      default:
        if (_kDeadTopLevelKeys.contains(key)) {
          dropped.add(key);
        } else {
          out[key] = deepCloneJson(e.value);
        }
    }
  }

  if (legacyDirectionsGuard && !out.containsKey('directions_migrated')) {
    out['directions_migrated'] = true;
  }

  if (renamed.isNotEmpty) info.add('renamed: ${renamed.join(', ')}');
  if (dropped.isNotEmpty) info.add('dropped keys: ${dropped.join(', ')}');

  return StorageMigrationResult(
    doc: out,
    migrated: true,
    foundVersion: version,
    info: info,
    warnings: warnings,
  );
}



List<Map<String, dynamic>> _convertSources(
  Map<String, dynamic> doc,
  List<String> info,
  List<String> warnings,
) {
  final out = <Map<String, dynamic>>[];
  var subscriptions = 0, servers = 0, folders = 0;
  final multiNode = <String>[];

  final rawLists = doc[_kServerLists];
  if (rawLists != null && rawLists is! List) {
    warnings.add('$_kServerLists is not a list, dropped');
  }
  if (rawLists is List) {
    for (var i = 0; i < rawLists.length; i++) {
      final raw = rawLists[i];
      if (raw is! Map) {
        warnings.add('$_kServerLists[$i]: not an object, dropped');
        continue;
      }
      final j = raw.cast<String, dynamic>();
      try {
        final list = readLegacyServerList(j);
        out.add(sourceToRecord(list));
        switch (list) {
          case SubscriptionServers():
            subscriptions++;
          case UserServer():
            servers++;
            if (list.nodes.length > 1) multiNode.add(list.id);
          case FolderServers():
            folders++;
        }
      } catch (e) {
        warnings.add('$_kServerLists[$i] ${_sourceName(j)}: '
            'does not read ($e), dropped');
      }
    }
  }

  final rawChains = doc[_kChains];
  if (rawChains != null && rawChains is! List) {
    warnings.add('$_kChains is not a list, dropped');
  }
  final chains = <LegacyChain>[];
  if (rawChains is List) {
    for (var i = 0; i < rawChains.length; i++) {
      final raw = rawChains[i];
      if (raw is! Map) {
        warnings.add('$_kChains[$i]: not an object, dropped');
        continue;
      }
      try {
        final c = readLegacyChain(raw.cast<String, dynamic>());
        if (c.chain.tag.isEmpty) {
          warnings.add('$_kChains[$i]: chain without tag, dropped');
          continue;
        }
        chains.add(c);
      } catch (e) {
        warnings.add('$_kChains[$i] "${raw['tag']}": does not read ($e), '
            'dropped');
      }
    }
  }
  for (final c in sortLegacyChains(chains)) {
    out.add(chainToRecord(c));
  }

  info.add('$kSourcesKey: $subscriptions subscriptions, '
      '$servers servers, $folders folders, ${chains.length} chains');
  if (multiNode.isNotEmpty) {
    info.add('servers with several nodes kept as one record: '
        '${multiNode.length} (${multiNode.join(', ')})');
  }
  return out;
}

String _sourceName(Map<String, dynamic> j) {
  final id = j['id'];
  final name = j['name'];
  return '(${j['type']} id "$id"${name is String && name.isNotEmpty ? ' "$name"' : ''})';
}




bool _isLegacyAutogroup(Object? node) {
  if (node is! Map) return false;
  final origin = node['origin'];
  return isLegacyAutogroupText(origin is Map ? origin['raw'] : null);
}

bool _hasLegacyAutogroups(Object? sources) =>
    sources is List &&
    sources.any((s) =>
        s is Map &&
        s['kind'] == kSourceKindFolder &&
        s['nodes'] is List &&
        (s['nodes'] as List).any(_isLegacyAutogroup));

















List<Map<String, dynamic>> migrateAutogroupMembers(
  List<Map<String, dynamic>> sources,
  List<String> info,
  List<String> warnings,
) {
  var converted = 0;
  final out = <Map<String, dynamic>>[];
  for (final source in sources) {
    final nodes = source['nodes'];
    if (source['kind'] != kSourceKindFolder ||
        nodes is! List ||
        !nodes.any(_isLegacyAutogroup)) {
      out.add(source);
      continue;
    }
    final folderId = source['id'] is String ? source['id'] as String : '';
    final name = source['name'];
    final where = 'folder "${name is String && name.isNotEmpty ? name : folderId}"';
    final parsed = [
      for (final n in nodes) _isLegacyAutogroup(n) ? null : _recordNode(n),
    ];
    final next = <Object?>[];
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      if (!_isLegacyAutogroup(n)) {
        next.add(n);
        continue;
      }
      final record = _autogroupRecord(
        (n as Map).cast<String, dynamic>(),
        nodes,
        parsed,
        folderId,
        '$where: nodes[$i]',
        warnings,
      );
      if (record != null) {
        next.add(record);
        converted++;
      }
    }
    out.add({...source, 'nodes': next});
  }
  if (converted > 0) {
    info.add('auto nodes: $converted autogroup members → kind auto');
  }
  return out;
}



NodeSpec? _recordNode(Object? node) {
  if (node is! Map) return null;
  final origin = node['origin'];
  final raw = origin is Map ? origin['raw'] : null;
  if (raw is! String || raw.trim().isEmpty) return null;
  try {
    final nodes = parseAll(decode(raw));
    return nodes.isEmpty ? null : nodes.first;
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _autogroupRecord(
  Map<String, dynamic> node,
  List<dynamic> nodes,
  List<NodeSpec?> parsed,
  String folderId,
  String where,
  List<String> warnings,
) {
  final raw = (node['origin'] as Map)['raw'] as String;
  final read = legacyAutogroupSpec(
    raw,
    nodes: parsed,
    enabledAt: (i) {
      final n = nodes[i];
      return !(n is Map && n['enabled'] == false);
    },
    linkOf: (_, tag) => NodeLink(folderId: folderId, tag: tag),
  );
  if (read == null) {
    warnings.add('$where: autogroup text does not read, dropped '
        '(the text stays in .v0.bak)');
    return null;
  }
  final group = read.group;
  for (final problem in read.dropped) {
    warnings.add('$where "${group.tag}": member $problem, dropped');
  }
  if (node['detour'] != null || node['sections'] != null) {
    warnings.add('$where "${group.tag}": detour and sections of an auto node '
        'are dropped');
  }
  final enabled = node['enabled'];
  return autoGroupMemberToRecord(
    FolderMember.auto(group, enabled: enabled is bool ? enabled : true),
    group,
    folderId,
  );
}



List<Map<String, dynamic>> _convertRules(
  Object? raw,
  RecordVarDecls recordVars,
  List<String> info,
  List<String> warnings,
) {
  if (raw is! List) {
    warnings.add('$_kCustomRules is not a list, dropped');
    return [];
  }
  final out = <Map<String, dynamic>>[];
  var read = 0;
  final split = <String>[];
  for (var i = 0; i < raw.length; i++) {
    final e = raw[i];
    if (e is! Map) {
      warnings.add('$_kCustomRules[$i]: not an object, dropped');
      continue;
    }
    final CustomRule rule;
    try {
      rule = readLegacyCustomRule(e.cast<String, dynamic>());
    } catch (err) {
      warnings.add('$_kCustomRules[$i] "${e['name']}": does not read ($err), '
          'dropped');
      continue;
    }
    read++;
    try {
      if (rule is CustomRuleJson) {
        final records = _jsonRuleRecords(rule, warnings);
        if (records.length > 1) split.add('"${rule.name}" → ${records.length}');
        out.addAll(records);
        continue;
      }
      final badPorts = [
        for (final p in rule.ports)
          if (!_isPort(p)) p,
      ];
      if (badPorts.isNotEmpty) {
        warnings.add('rule "${rule.name}": non-numeric ports dropped: '
            '${badPorts.join(', ')}');
      }
      out.add(ruleToRecord(normalizePresetRuleVars(rule, recordVars)));
    } catch (err) {
      warnings.add('rule "${rule.name}": does not convert ($err), dropped');
    }
  }
  info.add('$kRulesKey: $read rules → ${out.length} records');
  if (split.isNotEmpty) info.add('json rules split: ${split.join(', ')}');
  return out;
}

bool _isPort(String p) {
  final n = int.tryParse(p);
  return n != null && n >= 0 && n <= 65535;
}




List<Map<String, dynamic>> _jsonRuleRecords(
  CustomRuleJson rule,
  List<String> warnings,
) {
  final records = [
    for (final r in splitJsonRuleArrays([rule], notes: warnings))
      ruleToRecord(r),
  ];
  if (records.length == 1 &&
      !records.single.containsKey('body') &&
      rule.json.trim().isNotEmpty) {
    warnings.add('rule "${rule.name}": raw JSON is not an object or an array '
        'of objects, kept without body (the text stays in .v0.bak)');
  }
  return records;
}



Map<String, dynamic> _convertDns(
  Object? raw,
  Map<String, String> presetIdByTag,
  RecordVarDecls recordVars,
  List<String> info,
  List<String> warnings,
) {
  if (raw is! Map) {
    warnings.add('$_kDnsOptions is not an object, dropped');
    return {};
  }
  final out = <String, dynamic>{};
  var servers = 0, rules = 0;
  final noPreset = <String>[];

  final rawServers = raw['servers'];
  if (rawServers is List) {
    final list = <Map<String, dynamic>>[];
    for (var i = 0; i < rawServers.length; i++) {
      final e = rawServers[i];
      if (e is! Map) {
        warnings.add('dns server [$i]: not an object, dropped');
        continue;
      }
      final j = e.cast<String, dynamic>();
      try {
        var ref = readLegacyDnsServer(j);
        if (ref == null) {
          warnings.add('dns server [$i] "${j['tag']}": '
              '${j['kind'] == null ? 'record without kind (old form)' : 'kind "${j['kind']}" or required fields missing'}, '
              'dropped');
          continue;
        }
        if (ref is DnsServerPreset) {
          final presetId = presetIdByTag[ref.tag] ?? '';
          if (presetId.isEmpty) noPreset.add(ref.tag);
          ref = ref.copyWith(presetId: presetId);
        }
        list.add(dnsServerToRecord(normalizeDnsServerVars(ref, recordVars)));
        servers++;
      } catch (err) {
        warnings.add('dns server [$i] "${j['tag']}": does not read ($err), '
            'dropped');
      }
    }
    out[kDnsServersKey] = list;
  } else if (rawServers != null) {
    warnings.add('$_kDnsOptions.servers is not a list, dropped');
  }

  final rawRules = raw['rules'];
  if (rawRules is List) {
    final list = <Map<String, dynamic>>[];
    for (var i = 0; i < rawRules.length; i++) {
      final e = rawRules[i];
      if (e is! Map) {
        warnings.add('dns rule [$i]: not an object, dropped');
        continue;
      }
      final j = e.cast<String, dynamic>();
      final name = j['name'] ?? j['presetId'];
      try {
        final ref = readLegacyDnsRule(j);
        if (ref == null) {
          warnings.add('dns rule [$i] "$name": kind "${j['kind']}" '
              'is an old form or required fields are missing, dropped');
          continue;
        }
        list.add(dnsRuleToRecord(ref));
        rules++;
      } catch (err) {
        warnings.add('dns rule [$i] "$name": does not read ($err), dropped');
      }
    }
    out[kDnsRulesKey] = list;
  } else if (rawRules != null) {
    warnings.add('$_kDnsOptions.rules is not a list, dropped');
  }

  for (final k in raw.keys) {

    if (k == 'servers' || k == 'rules' || k == 'rules_json') continue;
    warnings.add('$_kDnsOptions.$k: unknown key, dropped');
  }

  info.add('$kDnsKey: $servers servers, $rules rules');
  if (noPreset.isNotEmpty) {
    info.add('dns preset servers without a known preset (ref = tag): '
        '${noPreset.join(', ')}');
  }
  return out;
}
