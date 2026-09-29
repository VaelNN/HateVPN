import '../../config/consts.dart' show kDirectOutboundTag;
import '../../models/custom_rule.dart';
import '../../models/parser_config.dart';
import '../contract/registry.dart';
import '../json_clone.dart';
import 'if_engine.dart';







class PresetFragments {
  final List<Map<String, dynamic>> dnsServers;



  final List<Map<String, dynamic>> dnsRules;
  final List<Map<String, dynamic>> ruleSets;



  final List<Map<String, dynamic>> routingRules;
  final List<String> warnings;

  const PresetFragments({
    this.dnsServers = const [],
    this.dnsRules = const [],
    this.ruleSets = const [],
    this.routingRules = const [],
    this.warnings = const [],
  });

  bool get isEmpty =>
      dnsServers.isEmpty &&
      dnsRules.isEmpty &&
      ruleSets.isEmpty &&
      routingRules.isEmpty;
}




const _kIntermediateActions = {'resolve', 'sniff', 'route-options'};




const _kServerlessDnsActions = {'predefined', 'reject', 'route-options'};



const _kAddressDnsServerTypes = {'udp', 'tcp', 'tls', 'https', 'quic', 'h3'};




bool dnsServerMissingAddress(Map<String, dynamic> server) {
  final type = server['type'];
  if (type is! String || !_kAddressDnsServerTypes.contains(type)) return false;
  final address = server['server'];
  return address is! String || address.trim().isEmpty;
}




String? ruleSetMissingSource(Map<String, dynamic> rs) {
  bool has(String k) {
    final v = rs[k];
    if (v is String) return v.trim().isNotEmpty;
    if (v is List) return v.isNotEmpty;
    return v != null;
  }

  return switch (rs['type']) {
    'remote' => has('url') ? null : 'url',
    'local' => has('path') ? null : 'path',


    'inline' => rs['rules'] is List ? null : 'rules',
    _ => 'url/path',
  };
}




void reportFragmentDropped(String owner, String kind, String reason) =>
    reportTemplateWarning(templateWarnFragmentDropped,
        {'owner': owner, 'kind': kind, 'reason': reason});



const _kRouteRuleConditions = 'route_rule_conditions';
const _kDnsRuleConditions = 'dns_rule_conditions';











bool hasRuleCondition(Map<String, dynamic> rule, String list) {
  final conds = ContractRegistry.I.allowlistValues(list);
  if (conds == null || conds.isEmpty) return true;
  return _hasCondition(rule, conds);
}

bool _hasCondition(Map<dynamic, dynamic> rule, Set<String> conds) {
  for (final e in rule.entries) {
    if (!conds.contains(e.key)) continue;
    final v = e.value;
    if (v == null) continue;
    if (v is List) {
      if (v.isEmpty) continue;
      final subRules = v.whereType<Map>().toList();
      if (subRules.isEmpty) return true;
      if (subRules.any((m) => _hasCondition(m, conds))) return true;
      continue;
    }
    return true;
  }
  return false;
}


class BundleMerge {
  final List<Map<String, dynamic>> dnsServers;
  final List<Map<String, dynamic>> dnsRules;
  final List<Map<String, dynamic>> ruleSets;
  final List<Map<String, dynamic>> routingRules;
  final List<String> warnings;

  const BundleMerge({
    this.dnsServers = const [],
    this.dnsRules = const [],
    this.ruleSets = const [],
    this.routingRules = const [],
    this.warnings = const [],
  });
}






































PresetFragments expandPreset(
  CustomRulePreset rule,
  SelectableRule preset, {
  Map<String, String> srsPaths = const {},
  Map<String, String> globalVars = const {},
  List<PresetNode> nodes = const [],
}) {
  final forEach = preset.forEach;
  if (forEach == null) {
    return _expandPresetBody(rule, preset,
        srsPaths: srsPaths, globalVars: globalVars);
  }
  final resolvedVars = presetVarsMap(rule, preset, globalVars: globalVars);
  if (resolvedVars.error != null) {
    return PresetFragments(warnings: [resolvedVars.error!]);
  }
  final parts = <PresetFragments>[
    for (final node in _forEachMatches(forEach, nodes, resolvedVars.vars))
      _expandPresetBody(rule, preset,
          srsPaths: srsPaths,
          globalVars: globalVars,
          nodeVars: presetNodeResolver(forEach.as, node),
          namespace: false),
  ];
  return PresetFragments(
    dnsServers: [for (final p in parts) ...p.dnsServers],
    dnsRules: [for (final p in parts) ...p.dnsRules],
    ruleSets: [for (final p in parts) ...p.ruleSets],
    routingRules: [for (final p in parts) ...p.routingRules],

    warnings: {for (final p in parts) ...p.warnings}.toList(),
  );
}






List<PresetNode> presetForEachNodes(
  CustomRulePreset rule,
  SelectableRule preset,
  List<PresetNode> nodes, {
  Map<String, String> globalVars = const {},
}) {
  final forEach = preset.forEach;
  if (forEach == null) return const [];
  final resolvedVars = presetVarsMap(rule, preset, globalVars: globalVars);
  if (resolvedVars.error != null) return const [];
  return _forEachMatches(forEach, nodes, resolvedVars.vars).toList();
}

Iterable<PresetNode> _forEachMatches(
  PresetForEach forEach,
  List<PresetNode> nodes,
  Map<String, dynamic> varsMap,
) sync* {
  for (final node in nodes) {
    if (node.body['type'] != forEach.nodeType) continue;
    final filter = forEach.filter;
    if (filter != null) {
      final nodeVars = presetNodeResolver(forEach.as, node);
      final ok = evalCond(deepCloneJson(filter), (name) {
        final v = nodeVars(name);
        if (v != null) return v;
        if (!varsMap.containsKey(name)) return null;
        return varsMap[name] ?? Dropped.instance;
      });
      if (!ok) continue;
    }
    yield node;
  }
}



class PresetNode {
  const PresetNode({
    required this.tag,
    required this.body,
    this.skipPresets = false,
  });

  final String tag;
  final Map<String, dynamic> body;
  final bool skipPresets;
}



const Set<String> kPresetNodeRecordFields = {'skip_presets'};









VarResolver presetNodeResolver(String as, PresetNode node) {
  final prefix = '$as.';
  return (String name) {
    if (name == as) return node.tag;
    if (!name.startsWith(prefix)) return null;
    final field = name.substring(prefix.length);
    if (field == 'skip_presets') return node.skipPresets;
    if (!field.startsWith('body.')) return Dropped.instance;
    Object? cur = node.body;
    for (final part in field.substring('body.'.length).split('.')) {
      if (cur is! Map || !cur.containsKey(part)) return Dropped.instance;
      cur = cur[part];
    }
    if (cur == null) return Dropped.instance;
    if (cur is String && cur.isEmpty) return Dropped.instance;
    return deepCloneJson(cur);
  };
}

PresetFragments _expandPresetBody(
  CustomRulePreset rule,
  SelectableRule preset, {
  Map<String, String> srsPaths = const {},
  Map<String, String> globalVars = const {},
  VarResolver? nodeVars,
  bool namespace = true,
}) {
  final warnings = <String>[];



  final resolvedVars = presetVarsMap(rule, preset, globalVars: globalVars);
  final varsError = resolvedVars.error;
  if (varsError != null) {
    warnings.add(varsError);
    return PresetFragments(warnings: warnings);
  }
  final varsMap = resolvedVars.vars;

  final expandedRuleSets = <Map<String, dynamic>>[];
  for (final rs in preset.ruleSets) {


    if (!fragmentGateSatisfied(rs, varsMap, extra: nodeVars)) continue;

    final copy = deepCopyJson(rs);
    final result = substituteVars(copy, varsMap, extra: nodeVars);
    if (result is! Map<String, dynamic>) continue;
    if (result['tag'] is! String) continue;

    final missingSource = ruleSetMissingSource(result);
    if (missingSource != null) {
      reportFragmentDropped(preset.presetId, 'route.rule_set', missingSource);
      continue;
    }




    stripFragmentGateKeys(result);




    if (result['type'] == 'remote') {
      final tag = result['tag'] as String;
      final localPath = srsPaths[tag];
      if (localPath == null) {
        warnings.add(
          'preset "${preset.presetId}": remote rule_set "$tag" skipped — '
          'no cached file (download first)',
        );
        continue;
      }

      result
        ..['type'] = 'local'
        ..remove('url')
        ..remove('download_detour')
        ..remove('update_interval')
        ..['path'] = localPath;
      if (result['format'] is! String) {
        result['format'] = 'binary';
      }
    }
    expandedRuleSets.add(result);
  }

  final expandedTags = {
    for (final rs in expandedRuleSets) rs['tag'] as String,
  };




  final dnsRules = <Map<String, dynamic>>[];
  {
    final copy = <dynamic>[for (final r in preset.dnsRules) deepCopyJson(r)];
    final substituted = substituteVars(copy, varsMap, extra: nodeVars);
    final items = substituted is List ? substituted : const [];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final result = item;




      final action = result['action'];
      final serverless =
          action is String && _kServerlessDnsActions.contains(action);
      if (result['server'] is! String && !serverless) {
        reportFragmentDropped(preset.presetId, 'dns.rules', 'server/action');
        continue;
      }





      final refTag = result['rule_set'];
      if (refTag is String && refTag.isNotEmpty) {
        if (!expandedTags.contains(refTag)) {


          reportFragmentDropped(preset.presetId, 'dns.rules', 'rule_set');
          continue;
        }
      } else if (refTag is List) {
        final present = refTag
            .whereType<String>()
            .where(expandedTags.contains)
            .toList();
        if (present.isEmpty) {


          reportFragmentDropped(preset.presetId, 'dns.rules', 'rule_set');
          continue;
        }
        result['rule_set'] = present.length == 1 ? present.first : present;
      } else if (refTag != null) {



        result.remove('rule_set');
        warnings.add(
          'preset "${preset.presetId}": DNS rule rule_set has invalid '
          'value (${refTag.runtimeType}) — reference dropped',
        );
      }


      if (!hasRuleCondition(result, _kDnsRuleConditions)) {
        reportFragmentDropped(preset.presetId, 'dns.rules', 'rule_set');
        continue;
      }
      dnsRules.add(result);
    }
  }

  final routingRules = <Map<String, dynamic>>[];
  {







    final copy = <dynamic>[for (final r in preset.rules) deepCopyJson(r)];
    final substituted = substituteVars(copy, varsMap, extra: nodeVars);
    final items = substituted is List ? substituted : const [];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final result = item;
      if (result['outbound'] is! String && result['action'] is! String) {


        reportFragmentDropped(preset.presetId, 'route.rules', 'outbound/action');
        continue;
      }






      final isIntermediate = _kIntermediateActions.contains(result['action']);
      if (!isIntermediate) {

















        final override = rule.varsValues['outbound'];
        if (override != null && override.isNotEmpty) {
          result.remove('action');
          result.remove('outbound');
          if (override == 'reject') {
            result['action'] = 'reject';
          } else {
            result['outbound'] = override;
          }
        }




















        if (result['outbound'] == 'reject') {
          result.remove('outbound');
          result['action'] = 'reject';
        }
      }









      final refTag = result['rule_set'];
      if (refTag is String && refTag.isNotEmpty) {
        if (!expandedTags.contains(refTag)) {


          reportFragmentDropped(preset.presetId, 'route.rules', 'rule_set');
          continue;
        }
      } else if (refTag is List) {
        final present = refTag
            .whereType<String>()
            .where(expandedTags.contains)
            .toList();
        if (present.isEmpty) {


          reportFragmentDropped(preset.presetId, 'route.rules', 'rule_set');
          continue;
        }

        result['rule_set'] = present.length == 1 ? present.first : present;
      } else if (refTag != null) {




        result.remove('rule_set');
        warnings.add(
          'preset "${preset.presetId}": routing rule rule_set has invalid '
          'value (${refTag.runtimeType}) — reference dropped',
        );
      }




      if (!hasRuleCondition(result, _kRouteRuleConditions)) {
        reportFragmentDropped(preset.presetId, 'route.rules', 'rule_set');
        continue;
      }
      routingRules.add(result);
    }
  }












  final hasDnsServerVar = preset.vars.any((v) => v.name == 'dns_server');
  final selectedDns = varsMap['dns_server'] as String?;
  Set<String>? wanted;
  if (hasDnsServerVar) {
    wanted = {};
    if (selectedDns != null && selectedDns.isNotEmpty) {
      wanted.add(selectedDns);
      for (final s in preset.dnsServers) {
        if (s['tag'] != selectedDns) continue;
        if (s['type'] != 'group') break;
        for (final m in (s['servers'] as List<dynamic>? ?? const [])) {
          if (m is String && m.isNotEmpty) wanted.add(m);
        }
        break;
      }
    }
  }



  final dnsServers = <Map<String, dynamic>>[];
  for (final s in preset.dnsServers) {
    if (wanted != null && !wanted.contains(s['tag'])) continue;
    final copy = deepCopyJson(s);
    final result = substituteVars(copy, varsMap, extra: nodeVars);
    if (result is! Map<String, dynamic>) continue;
    if (result['tag'] is! String) continue;


    if (dnsServerMissingAddress(result)) {
      reportFragmentDropped(preset.presetId, 'dns.servers', 'server');
      continue;
    }
    normalizeDnsDetour(result);
    dnsServers.add(result);
  }

  final fragments = PresetFragments(
    dnsServers: dnsServers,
    dnsRules: dnsRules,
    ruleSets: expandedRuleSets,
    routingRules: routingRules,
    warnings: warnings,
  );
  return namespace
      ? namespacePresetTags(preset.presetId, fragments)
      : fragments;
}











PresetFragments namespacePresetTags(String presetId, PresetFragments f) {
  if (presetId.isEmpty) return f;

  final localDnsTags = <String>{
    for (final s in f.dnsServers)
      if (s['tag'] is String) s['tag'] as String,
  };
  final localRuleSetTags = <String>{
    for (final rs in f.ruleSets)
      if (rs['tag'] is String) rs['tag'] as String,
  };
  if (localDnsTags.isEmpty && localRuleSetTags.isEmpty) return f;

  String qualify(String tag) => '$presetId:$tag';

  Object? mapRef(Object? value, Set<String> local) {
    if (value is String) return local.contains(value) ? qualify(value) : value;
    if (value is List) {
      return [
        for (final v in value)
          (v is String && local.contains(v)) ? qualify(v) : v,
      ];
    }
    return value;
  }

  final dnsServers = [
    for (final s in f.dnsServers)
      {
        ...s,
        'tag': qualify(s['tag'] as String),


        if (s['servers'] != null) 'servers': mapRef(s['servers'], localDnsTags),
      },
  ];

  final ruleSets = [
    for (final rs in f.ruleSets) {...rs, 'tag': qualify(rs['tag'] as String)},
  ];

  final dnsRules = [
    for (final r in f.dnsRules)
      {
        ...r,
        if (r['server'] != null) 'server': mapRef(r['server'], localDnsTags),
        if (r['rule_set'] != null)
          'rule_set': mapRef(r['rule_set'], localRuleSetTags),
      },
  ];

  final routingRules = [
    for (final r in f.routingRules)
      {
        ...r,
        if (r['rule_set'] != null)
          'rule_set': mapRef(r['rule_set'], localRuleSetTags),




        if (r['server'] != null) 'server': mapRef(r['server'], localDnsTags),
      },
  ];

  return PresetFragments(
    dnsServers: dnsServers,
    dnsRules: dnsRules,
    ruleSets: ruleSets,
    routingRules: routingRules,
    warnings: f.warnings,
  );
}







BundleMerge mergeFragments(List<PresetFragments> all) {
  final dnsServers = <Map<String, dynamic>>[];
  final dnsServerByTag = <String, Map<String, dynamic>>{};
  final ruleSets = <Map<String, dynamic>>[];
  final ruleSetByTag = <String, Map<String, dynamic>>{};
  final dnsRules = <Map<String, dynamic>>[];
  final routingRules = <Map<String, dynamic>>[];
  final warnings = <String>[];

  for (final f in all) {
    warnings.addAll(f.warnings);

    for (final s in f.dnsServers) {
      final tag = s['tag'];
      if (tag is! String) {
        dnsServers.add(s);
        continue;
      }
      final existing = dnsServerByTag[tag];
      if (existing == null) {
        dnsServerByTag[tag] = s;
        dnsServers.add(s);
      } else if (!deepEqualsJson(existing, s)) {
        warnings.add('dns server "$tag" skipped: conflicts with earlier preset');
      }
    }

    for (final rs in f.ruleSets) {
      final tag = rs['tag'];
      if (tag is! String) {
        ruleSets.add(rs);
        continue;
      }
      final existing = ruleSetByTag[tag];
      if (existing == null) {
        ruleSetByTag[tag] = rs;
        ruleSets.add(rs);
      } else if (!deepEqualsJson(existing, rs)) {
        warnings.add('rule_set "$tag" skipped: conflicts with earlier preset');
      }
    }

    dnsRules.addAll(f.dnsRules);
    routingRules.addAll(f.routingRules);
  }

  return BundleMerge(
    dnsServers: dnsServers,
    dnsRules: dnsRules,
    ruleSets: ruleSets,
    routingRules: routingRules,
    warnings: warnings,
  );
}












String? normalizeDnsDetour(
  Map<String, dynamic> server, {
  Set<String>? knownOutbounds,
}) {







  if (server['type'] == 'group') {
    server.remove('detour');
    return null;
  }


  if (server['type'] == 'tailscale') {
    server.remove('detour');
    return null;
  }
  final detour = server['detour'];
  if (detour is! String) return null;
  if (detour.isEmpty || detour == kDirectOutboundTag) {
    server.remove('detour');
    return null;
  }
  if (knownOutbounds != null && !knownOutbounds.contains(detour)) {
    return detour;
  }
  return null;
}

















dynamic substituteVars(
  dynamic obj,
  Map<String, dynamic> vars, {
  VarResolver? extra,
}) {
  return walk(obj, (name) {
    final own = extra?.call(name);
    if (own != null) return own;
    if (!vars.containsKey(name)) return null;
    final v = vars[name];
    if (v == null) return Dropped.instance;
    return v;
  });
}

























({Map<String, dynamic> vars, String? error}) presetVarsMap(
  CustomRulePreset rule,
  SelectableRule preset, {
  Map<String, String> globalVars = const {},
}) {
  final varsMap = <String, dynamic>{};
  String? error;
  for (final v in preset.vars) {


    if (v.isRef) continue;








    final hasExplicit = rule.varsValues.containsKey(v.name);
    final explicit = rule.varsValues[v.name];
    if (hasExplicit) {
      if (explicit == null || explicit.isEmpty) {
        if (v.required) {
          error ??=
              'preset "${preset.presetId}": required var "${v.name}" set to empty';
        }
        varsMap[v.name] = null;
      } else {
        varsMap[v.name] = explicit;
      }
    } else if (v.defaultValue.isNotEmpty) {
      varsMap[v.name] = v.defaultValue;
    } else {
      if (v.required) {
        error ??= 'preset "${preset.presetId}": required var "${v.name}" unset';
      }
      varsMap[v.name] = null;
    }
  }






  for (final v in preset.vars) {
    if (!v.isRef) continue;
    final gv = globalVars[v.ref];
    varsMap[v.name] = (gv != null && gv.isNotEmpty) ? gv : null;
  }








  for (final e in globalVars.entries) {
    varsMap.putIfAbsent(e.key, () => e.value);
  }
  return (vars: varsMap, error: error);
}






bool fragmentGateSatisfied(
  Map<String, dynamic> fragment,
  Map<String, dynamic> varsMap, {
  VarResolver? extra,
}) {
  final legacy = fragment['enabled'];
  if (legacy is String) {
    final substituted = substituteVars(legacy, varsMap, extra: extra);
    if (substituted is! String || substituted.trim().toLowerCase() != 'true') {
      return false;
    }
  } else if (legacy is bool && !legacy) {


    return false;
  }

  final gate = fragment[enableKey];
  if (gate == null) return true;
  Object? resolve(String name) {
    final own = extra?.call(name);
    if (own != null) return own;
    final v = varsMap[name];
    if (v == null) return null;
    return v is String ? coerceVarValue(v, _gateVarType(v)) : v;
  }

  return evalCond(gate, resolve);
}




String _gateVarType(String raw) {
  final t = raw.trim().toLowerCase();
  return (t == 'true' || t == 'false') ? 'bool' : 'text';
}










void stripFragmentGateKeys(Map<String, dynamic> fragment) {
  fragment.remove(enableKey);
  fragment.remove('enabled');
}
