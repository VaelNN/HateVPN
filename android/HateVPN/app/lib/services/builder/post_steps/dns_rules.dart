part of '../post_steps.dart';




































Future<void> applyCustomDns(
  Map<String, dynamic> config,
  Map<String, dynamic> templateDnsOptions, {
  List<Map<String, dynamic>> extraServers = const [],

  Map<String, String> extraServerPresetIds = const {},
  Map<String, List<Map<String, dynamic>>> extraDnsRulesByPresetId = const {},
  Set<String> activePresetIdsWithDnsRule = const {},
  Map<String, String> dnsSrsCachedPaths = const {},
  List<DnsMirrorEntry> dnsMirrors = const [],
  List<String>? warningsOut,




  Map<String, String> resolverDefaults = const {},

  Map<String, String> globalVars = const {},
}) async {
  final dns = (config['dns'] as Map<String, dynamic>?) ?? <String, dynamic>{};




  final templateServers =
      (templateDnsOptions['servers'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((s) => Map<String, dynamic>.from(s))
          .toList();

  final templateByTag = templateDnsServersByTag(templateServers);
  final presetServersByTag = <String, Map<String, dynamic>>{
    for (final s in extraServers)
      if (s['tag'] is String && (s['tag'] as String).isNotEmpty)
        s['tag'] as String: Map<String, dynamic>.from(s),
  };


  final resolvedServers = await resolveDnsServersList(
    templateServers: templateServers,
    presetServersByTag: presetServersByTag,
    presetIdByTag: extraServerPresetIds,
  );



  final knownOutboundTags = <String>{
    for (final o in (config['outbounds'] as List<dynamic>? ?? const []))
      if (o is Map && o['tag'] is String) o['tag'] as String,
    for (final e in (config['endpoints'] as List<dynamic>? ?? const []))
      if (e is Map && e['tag'] is String) e['tag'] as String,
  };


  final tailscaleEndpointTags = <String>{
    for (final e in (config['endpoints'] as List<dynamic>? ?? const []))
      if (e is Map && e['type'] == 'tailscale' && e['tag'] is String)
        e['tag'] as String,
  };



  final ruleReferencedTags = <String>{
    for (final m in dnsMirrors)
      if (m.ruleId != null && m.serverTag.isNotEmpty) m.serverTag,
  };



  final detourDropped = <String>{};
  final serverBodies = resolveDnsServersBodies(
    resolved: resolvedServers,
    templateByTag: templateByTag,
    presetServersByTag: presetServersByTag,
    knownOutboundTags: knownOutboundTags,
    ruleReferencedTags: ruleReferencedTags,
    warningsOut: warningsOut,
    tailscaleEndpointTags: tailscaleEndpointTags,
    detourDroppedOut: detourDropped,
    globalVars: globalVars,
  );
  dns['servers'] = serverBodies;







  final emittedServerTags = <String>{
    for (final s in serverBodies)
      if (s['tag'] is String) s['tag'] as String,
    ...detourDropped,
  };


  final templateRules = (templateDnsOptions['rules'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();
  final resolved = await resolveDnsRulesList(
    templateRules: templateRules,
    activePresetIdsWithDnsRule: activePresetIdsWithDnsRule,
  );
  final templateRulesByName = <String, Map<String, dynamic>>{
    for (final r in templateRules)
      if (r['name'] is String && (r['name'] as String).isNotEmpty)
        r['name'] as String: r,
  };

  final outRules = <Map<String, dynamic>>[];


  final extraDnsSrsRuleSets = <Map<String, dynamic>>[];




  var mirrorGroupEmitted = false;
  void emitMirrorGroup() {
    if (mirrorGroupEmitted) return;
    mirrorGroupEmitted = true;
    for (final m in dnsMirrors) {
      if (m.presetId != null) {




        final srv = m.body['server'];
        if (srv is String && !emittedServerTags.contains(srv)) continue;
        outRules.add(m.body);
      } else if (m.serverless) {


        outRules.add(m.body);
      } else {


        if (!emittedServerTags.contains(m.serverTag)) continue;
        outRules.add({...m.body, 'server': m.serverTag});
      }
    }
  }

  for (final entry in resolved) {
    if (entry is DnsRulePreset) {
      if (dnsMirrors.isNotEmpty) {




        emitMirrorGroup();
        continue;
      }



      if (!entry.enabled) continue;
      final bodies = extraDnsRulesByPresetId[entry.presetId];
      if (bodies != null) outRules.addAll(bodies);
      continue;
    }
    if (entry is DnsRuleTemplate &&
        dnsMirrors.isNotEmpty &&
        !mirrorGroupEmitted) {
      emitMirrorGroup();
    }
    if (!entry.enabled) continue;
    switch (entry) {
      case DnsRuleInline(:final rule):
        outRules.add(rule);
      case DnsRuleTemplate(:final name):
        final t = templateRulesByName[name];
        if (t != null) {
          final clean = Map<String, dynamic>.from(t)
            ..remove('name')
            ..remove('enabled_default');
          outRules.add(clean);
        }
      case DnsRuleSrs(
          :final id,
          :final name,
          :final body,
          server: final legacyServer,
          rule: final legacyRule,
        ):



        final bodyServer = body?['server'];
        final server =
            legacyServer ?? (bodyServer is String ? bodyServer : null);
        final rule = legacyRule ?? body;
        if (server == null || server.isEmpty) continue;
        final path = dnsSrsCachedPaths[id];
        if (path == null) continue;
        final tag = name.isNotEmpty ? name : 'dns_srs_$id';
        extraDnsSrsRuleSets.add({
          'type': 'local',
          'tag': tag,
          'format': 'binary',
          'path': path,
        });
        final dnsRule = <String, dynamic>{
          'rule_set': tag,
          'server': server,
        };

        if (rule != null) {
          for (final e in rule.entries) {
            if (e.key == 'rule_set' || e.key == 'server') continue;
            dnsRule[e.key] = e.value;
          }
        }
        outRules.add(dnsRule);
      case DnsRulePreset():
        break;
    }
  }

  if (dnsMirrors.isNotEmpty) emitMirrorGroup();
  if (outRules.isNotEmpty) dns['rules'] = outRules;
  config['dns'] = dns;


  warningsOut?.addAll(healDetourDroppedDnsRefs(
    config,
    detourDropped: detourDropped,
    defaults: resolverDefaults,
  ));
  if (extraDnsSrsRuleSets.isNotEmpty) {


    final route = (config['route'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final existing = (route['rule_set'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        <Map<String, dynamic>>[];
    final knownTags = <String>{
      for (final rs in existing)
        if (rs['tag'] is String) rs['tag'] as String,
    };
    for (final rs in extraDnsSrsRuleSets) {
      final tag = rs['tag'];
      if (tag is String && knownTags.add(tag)) {
        existing.add(rs);
      }
    }
    route['rule_set'] = existing;
    config['route'] = route;
  }

  config['dns'] = dns;
}


















Future<List<DnsRuleRef>> resolveDnsRulesList({
  required List<Map<String, dynamic>> templateRules,
  required Set<String> activePresetIdsWithDnsRule,
}) async {
  final stored = await SettingsStorage.getDnsRulesList();

  final templateNames = <String>{
    for (final r in templateRules)
      if (r['name'] is String && (r['name'] as String).isNotEmpty)
        r['name'] as String,
  };

  final result = <DnsRuleRef>[];
  final seenTemplateNames = <String>{};
  final seenPresetIds = <String>{};

  for (final entry in stored) {
    switch (entry) {


      case DnsRuleInline() || DnsRuleSrs():
        result.add(entry);
      case DnsRuleTemplate(:final name):
        if (templateNames.contains(name)) {
          result.add(entry);
          seenTemplateNames.add(name);
        }
      case DnsRulePreset(:final presetId):



        if (activePresetIdsWithDnsRule.contains(presetId)) {
          result.add(entry);
          seenPresetIds.add(presetId);
        }
    }
  }









  var templateBlockStart = result.indexWhere((e) => e is DnsRuleTemplate);
  if (templateBlockStart < 0) templateBlockStart = result.length;





  for (final pid in activePresetIdsWithDnsRule) {
    if (seenPresetIds.contains(pid)) continue;
    result.insert(
        templateBlockStart, DnsRulePreset(presetId: pid, enabled: true));
    templateBlockStart++;
  }


  for (final r in templateRules) {
    final name = r['name'];
    if (name is! String || name.isEmpty) continue;
    if (seenTemplateNames.contains(name)) continue;
    final enabledDefault = r['enabled_default'] != false;
    result.add(DnsRuleTemplate(name: name, enabled: enabledDefault));
  }




  final firstPresetIdx = result.indexWhere((e) => e is DnsRulePreset);
  if (firstPresetIdx >= 0) {
    final presetBlock =
        result.whereType<DnsRulePreset>().toList(growable: false);
    if (presetBlock.length > 1) {
      result.removeWhere((e) => e is DnsRulePreset);
      result.insertAll(firstPresetIdx, presetBlock);
    }
  }


  if (!const ListEquality<DnsRuleRef>().equals(stored, result)) {
    await SettingsStorage.saveDnsRulesList(result);
  }
  return result;
}
