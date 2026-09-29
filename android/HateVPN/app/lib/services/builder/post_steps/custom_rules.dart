part of '../post_steps.dart';












PresetApplyResult applyPresetBundles(
  RuleSetRegistry registry,
  List<CustomRule> rules,
  List<SelectableRule> presets, {
  Map<String, String> presetSrsPaths = const {},
}) {




  final state = _PresetSharedState();
  final warnings = <String>[];
  for (final cr in rules) {
    if (cr is! CustomRulePreset) continue;
    warnings.addAll(_applyPresetSingle(
      cr,
      registry,
      presets,
      state,
      presetSrsPaths: presetSrsPaths,
    ));
  }
  return PresetApplyResult(
    extraDnsServers: state.dnsServers,
    dnsServerPresetIdByTag: state.dnsServerPresetIdByTag,
    extraDnsRules: state.dnsRules,
    dnsRulesByPresetId: state.dnsRulesByPresetId,
    labelByPresetId: state.labelByPresetId,
    warnings: warnings,
  );
}





class _PresetSharedState {
  final List<Map<String, dynamic>> dnsServers = [];
  final Map<String, Map<String, dynamic>> dnsServerByTag = {};


  final Map<String, String> dnsServerPresetIdByTag = {};
  final List<Map<String, dynamic>> dnsRules = [];

  final Map<String, List<Map<String, dynamic>>> dnsRulesByPresetId = {};
  final Map<String, String> labelByPresetId = {};





  final List<DnsMirrorEntry> dnsMirrors = [];
}











class DnsMirrorEntry {
  const DnsMirrorEntry({
    this.presetId,
    this.ruleId,
    this.ruleName = '',
    this.serverTag = '',
    this.serverless = false,
    required this.body,
  });

  final String? presetId;
  final String? ruleId;
  final String ruleName;
  final String serverTag;





  final bool serverless;
  final Map<String, dynamic> body;
}









bool presetDnsEnableVar(CustomRulePreset cr, SelectableRule preset) {
  WizardVar? declared;
  for (final v in preset.vars) {
    if (v.name == 'dns_enable') {
      declared = v;
      break;
    }
  }
  if (declared == null) return true;




  if (declared.isRef) return true;
  final explicit = cr.varsValues['dns_enable'];
  if (explicit != null && explicit.isNotEmpty) return explicit == 'true';
  final def = declared.defaultValue;
  return def.isEmpty || def == 'true';
}






List<String> _applyPresetSingle(
  CustomRulePreset cr,
  RuleSetRegistry registry,
  List<SelectableRule> presets,
  _PresetSharedState state, {
  Map<String, String> presetSrsPaths = const {},
  Map<String, String> globalVars = const {},
  List<PresetNode> presetNodes = const [],
}) {
  final warnings = <String>[];
  if (cr.presetId.isEmpty) return warnings;

  final routeEnabled = cr.enabled;



  if (!routeEnabled) return warnings;

  SelectableRule? match;
  for (final p in presets) {
    if (p.presetId == cr.presetId) {
      match = p;
      break;
    }
  }
  if (match == null) {
    warnings.add('preset "${cr.presetId}" not found in template (rule skipped)');
    return warnings;
  }





  final dnsEnabled = presetDnsEnableVar(cr, match);



  final srsSubset = <String, String>{};
  final prefix = '${cr.presetId}|';
  for (final entry in presetSrsPaths.entries) {
    if (entry.key.startsWith(prefix)) {
      srsSubset[entry.key.substring(prefix.length)] = entry.value;
    }
  }

  final raw = expandPreset(cr, match,
      srsPaths: srsSubset, globalVars: globalVars, nodes: presetNodes);
  warnings.addAll(raw.warnings);




  for (final rs in raw.ruleSets) {
    final conflict = registry.tryRegisterRuleSet(rs);
    if (conflict) {
      final tag = rs['tag'];
      warnings.add(
          'rule_set "$tag" skipped: conflicts with earlier registered rule_set');
    }
  }




  if (routeEnabled) {
    for (final r in raw.routingRules) {
      registry.addRule(r);
    }
  }


  if (dnsEnabled) {
    if (raw.dnsRules.isNotEmpty) {
      state.dnsRules.addAll(raw.dnsRules);
      state.dnsRulesByPresetId[cr.presetId] = raw.dnsRules;



      for (final r in raw.dnsRules) {
        state.dnsMirrors.add(DnsMirrorEntry(
          presetId: cr.presetId,
          ruleName: match.label,
          body: r,
        ));
      }
    }
    for (final s in raw.dnsServers) {
      final tag = s['tag'];
      if (tag is! String) {
        state.dnsServers.add(s);
        continue;
      }
      final existing = state.dnsServerByTag[tag];
      if (existing == null) {
        state.dnsServerByTag[tag] = s;




        if (tag.startsWith('${cr.presetId}:')) {
          state.dnsServerPresetIdByTag[tag] = cr.presetId;
        }
        state.dnsServers.add(s);
      } else if (!const DeepCollectionEquality().equals(existing, s)) {
        warnings
            .add('dns server "$tag" skipped: conflicts with earlier preset');
      }
    }
  }

  state.labelByPresetId[cr.presetId] = match.label;
  return warnings;
}









class PresetApplyResult {
  final List<Map<String, dynamic>> extraDnsServers;


  final Map<String, String> dnsServerPresetIdByTag;
  final List<Map<String, dynamic>> extraDnsRules;
  final Map<String, List<Map<String, dynamic>>> dnsRulesByPresetId;
  final Map<String, String> labelByPresetId;
  final List<String> warnings;

  const PresetApplyResult({
    this.extraDnsServers = const [],
    this.dnsServerPresetIdByTag = const {},
    this.extraDnsRules = const [],
    this.dnsRulesByPresetId = const {},
    this.labelByPresetId = const {},
    this.warnings = const [],
  });
}
























List<String> applyCustomRules(
  RuleSetRegistry registry,
  List<CustomRule> rules, {
  Map<String, String> srsPaths = const {},
  bool skipDisabled = true,
}) {




  final warnings = <String>[];
  for (final cr in rules) {
    if (skipDisabled && !cr.enabled) continue;
    switch (cr) {
      case CustomRulePreset():

        continue;
      case CustomRuleSrs():
        warnings.addAll(_applySrsSingle(cr, registry, srsPaths));
      case CustomRuleInline():
        warnings.addAll(_applyInlineSingle(cr, registry));
      case CustomRuleJson():
        warnings.addAll(_applyJsonSingle(cr, registry));
    }
  }
  return warnings;
}







List<String> _applySrsSingle(
  CustomRuleSrs cr,
  RuleSetRegistry registry,
  Map<String, String> srsPaths, {
  List<DnsMirrorEntry>? dnsMirrors,
}) {
  final warnings = <String>[];
  if (cr.outbound.isEmpty) return warnings;
  final requestedTag = cr.name.trim().isEmpty ? 'unnamed' : cr.name.trim();




  final cacheIds = cr.cacheIds;
  if (cacheIds.isEmpty || cacheIds.any((c) => srsPaths[c] == null)) {
    warnings.add(
        'SRS rule "${cr.name}" skipped: no cached file (Download first).');
    return warnings;
  }
  final tags = <String>[];
  for (var i = 0; i < cacheIds.length; i++) {
    tags.add(registry.addRuleSet({
      'type': 'local',
      'tag': i == 0 ? requestedTag : '$requestedTag-${i + 1}',
      'format': 'binary',
      'path': srsPaths[cacheIds[i]]!,
    }));
  }

  final Object tag = tags.length == 1 ? tags.first : tags;



  if (cr.resolveActive) {
    registry.addRule(_resolveToRoute(
      tag,
      cr.resolve!,
      ports: cr.intPorts,
      portRanges: cr.portRanges,
      packages: cr.packages,
      protocols: cr.protocols,
      network: cr.network,
      ipIsPrivate: cr.ipIsPrivate,
      sourceIpCidrs: cr.sourceIpCidrs,
      sourceIpIsPrivate: cr.sourceIpIsPrivate,
      inbounds: cr.inbounds,
      wifiSsids: cr.wifiSsids,
      wifiBssids: cr.wifiBssids,
    ));
  }

  if (!(cr.resolveActive && cr.resolve!.only)) {
    registry.addRule(_outboundToRoute(
      tag,
      cr.outbound,
      ports: cr.intPorts,
      portRanges: cr.portRanges,
      packages: cr.packages,
      protocols: cr.protocols,
      network: cr.network,
      ipIsPrivate: cr.ipIsPrivate,


      sourceIpCidrs: cr.sourceIpCidrs,
      sourceIpIsPrivate: cr.sourceIpIsPrivate,
      inbounds: cr.inbounds,
      wifiSsids: cr.wifiSsids,
      wifiBssids: cr.wifiBssids,
    ));
  }
  if (dnsMirrors != null && (cr.dnsMirrorActive || cr.forceIpv4Active)) {


    Map<String, dynamic> srsMatch() {
      final m = <String, dynamic>{'rule_set': tag};
      if (cr.packages.isNotEmpty) m['package_name'] = cr.packages;
      if (cr.wifiSsids.isNotEmpty) m['wifi_ssid'] = cr.wifiSsids;
      if (cr.wifiBssids.isNotEmpty) m['wifi_bssid'] = cr.wifiBssids;

      if (cr.sourceIpCidrs.isNotEmpty) m['source_ip_cidr'] = cr.sourceIpCidrs;
      if (cr.inbounds.isNotEmpty) m['inbound'] = cr.inbounds;
      return m;
    }


    if (cr.forceIpv4Active) {
      final mirror = srsMatch()
        ..['ip_version'] = 6
        ..['action'] = 'predefined'
        ..['rcode'] = 'NOERROR';
      dnsMirrors.add(DnsMirrorEntry(
        ruleId: cr.id,
        ruleName: cr.name,
        serverless: true,
        body: mirror,
      ));
    }
    if (cr.dnsMirrorActive) {
      dnsMirrors.add(DnsMirrorEntry(
        ruleId: cr.id,
        ruleName: cr.name,
        serverTag: cr.dns!.serverTag,
        body: srsMatch(),
      ));
    }
  }
  return warnings;
}








List<String> _applyInlineSingle(
  CustomRuleInline cr,
  RuleSetRegistry registry, {
  List<DnsMirrorEntry>? dnsMirrors,
}) {
  final warnings = <String>[];
  if (cr.outbound.isEmpty) return warnings;




  Map<String, dynamic> mirrorBody(String ruleSetTag) {
    final m = <String, dynamic>{};
    if (ruleSetTag.isNotEmpty) m['rule_set'] = ruleSetTag;
    if (cr.inbounds.isNotEmpty) m['inbound'] = cr.inbounds;
    return m;
  }





  void addForceIpv4Mirror(String ruleSetTag) {
    if (dnsMirrors == null || !cr.forceIpv4Active) return;
    final matchFields = mirrorBody(ruleSetTag);



    if (matchFields.isEmpty) return;
    final mirror = matchFields
      ..['ip_version'] = 6
      ..['action'] = 'predefined'
      ..['rcode'] = 'NOERROR';
    dnsMirrors.add(DnsMirrorEntry(
      ruleId: cr.id,
      ruleName: cr.name,
      serverless: true,
      body: mirror,
    ));
  }

  void addDnsMirror(String ruleSetTag) {
    if (dnsMirrors == null || !cr.dnsMirrorActive) return;
    final mirror = mirrorBody(ruleSetTag);


    if (mirror.isEmpty) return;
    dnsMirrors.add(DnsMirrorEntry(
      ruleId: cr.id,
      ruleName: cr.name,
      serverTag: cr.dns!.serverTag,
      body: mirror,
    ));
  }
  final requestedTag = cr.name.trim().isEmpty ? 'unnamed' : cr.name.trim();

  final match = <String, dynamic>{};
  if (cr.domains.isNotEmpty) match['domain'] = cr.domains;
  if (cr.domainSuffixes.isNotEmpty) {
    match['domain_suffix'] = cr.domainSuffixes;
  }
  if (cr.domainKeywords.isNotEmpty) {
    match['domain_keyword'] = cr.domainKeywords;
  }
  if (cr.ipCidrs.isNotEmpty) match['ip_cidr'] = cr.ipCidrs;
  final intPorts = cr.intPorts;
  if (intPorts.isNotEmpty) match['port'] = intPorts;
  if (cr.portRanges.isNotEmpty) match['port_range'] = cr.portRanges;
  if (cr.packages.isNotEmpty) match['package_name'] = cr.packages;




  if (cr.sourceIpCidrs.isNotEmpty) match['source_ip_cidr'] = cr.sourceIpCidrs;
  if (cr.wifiSsids.isNotEmpty) match['wifi_ssid'] = cr.wifiSsids;
  if (cr.wifiBssids.isNotEmpty) match['wifi_bssid'] = cr.wifiBssids;





  if (match.isEmpty) {



    if (cr.protocols.isEmpty &&
        cr.network.isEmpty &&
        !cr.ipIsPrivate &&
        !cr.sourceIpIsPrivate &&
        cr.inbounds.isEmpty) {
      return warnings;
    }
    registry.addRule(_outboundToRoute(
      '',
      cr.outbound,
      protocols: cr.protocols,
      network: cr.network,
      ipIsPrivate: cr.ipIsPrivate,
      sourceIpIsPrivate: cr.sourceIpIsPrivate,
      inbounds: cr.inbounds,
    ));
    addForceIpv4Mirror('');
    addDnsMirror('');
    return warnings;
  }

  final tag = registry.addRuleSet({
    'type': 'inline',
    'tag': requestedTag,
    'rules': [match],
  });



  if (cr.resolveActive) {
    registry.addRule(_resolveToRoute(
      tag,
      cr.resolve!,
      protocols: cr.protocols,
      network: cr.network,
      ipIsPrivate: cr.ipIsPrivate,
      sourceIpIsPrivate: cr.sourceIpIsPrivate,
      inbounds: cr.inbounds,
    ));
  }








  if (!(cr.resolveActive && cr.resolve!.only)) {
    registry.addRule(_outboundToRoute(
      tag,
      cr.outbound,
      protocols: cr.protocols,
      network: cr.network,
      ipIsPrivate: cr.ipIsPrivate,
      sourceIpIsPrivate: cr.sourceIpIsPrivate,
      inbounds: cr.inbounds,
    ));
  }
  addForceIpv4Mirror(tag);
  addDnsMirror(tag);
  return warnings;
}













UnifiedApplyResult applyAllCustomRules(
  RuleSetRegistry registry,
  List<CustomRule> rules,
  List<SelectableRule> presets, {
  Map<String, String> srsPaths = const {},
  Map<String, String> presetSrsPaths = const {},
  Map<String, String> globalVars = const {},

  List<PresetNode> presetNodes = const [],
}) {
  final state = _PresetSharedState();
  final warnings = <String>[];
  for (final cr in rules) {
    switch (cr) {
      case CustomRulePreset():




        warnings.addAll(_applyPresetSingle(
          cr,
          registry,
          presets,
          state,
          presetSrsPaths: presetSrsPaths,
          globalVars: globalVars,
          presetNodes: presetNodes,
        ));
      case CustomRuleInline():
        if (!cr.enabled) continue;
        warnings.addAll(
            _applyInlineSingle(cr, registry, dnsMirrors: state.dnsMirrors));
      case CustomRuleSrs():
        if (!cr.enabled) continue;
        warnings.addAll(_applySrsSingle(cr, registry, srsPaths,
            dnsMirrors: state.dnsMirrors));
      case CustomRuleJson():
        if (!cr.enabled) continue;
        warnings.addAll(_applyJsonSingle(cr, registry));
    }
  }
  return UnifiedApplyResult(
    extraDnsServers: state.dnsServers,
    dnsServerPresetIdByTag: state.dnsServerPresetIdByTag,
    extraDnsRules: state.dnsRules,
    dnsRulesByPresetId: state.dnsRulesByPresetId,
    labelByPresetId: state.labelByPresetId,
    dnsMirrors: state.dnsMirrors,
    warnings: warnings,
  );
}







class UnifiedApplyResult {
  final List<Map<String, dynamic>> extraDnsServers;


  final Map<String, String> dnsServerPresetIdByTag;
  final List<Map<String, dynamic>> extraDnsRules;
  final Map<String, List<Map<String, dynamic>>> dnsRulesByPresetId;
  final Map<String, String> labelByPresetId;
  final List<DnsMirrorEntry> dnsMirrors;
  final List<String> warnings;

  const UnifiedApplyResult({
    this.extraDnsServers = const [],
    this.dnsServerPresetIdByTag = const {},
    this.extraDnsRules = const [],
    this.dnsRulesByPresetId = const {},
    this.labelByPresetId = const {},
    this.dnsMirrors = const [],
    this.warnings = const [],
  });
}




Map<String, dynamic> _outboundToRoute(
  Object tag,
  String outbound, {
  List<int>? ports,
  List<String>? portRanges,
  List<String>? packages,
  List<String>? protocols,
  List<String>? network,
  bool ipIsPrivate = false,
  List<String>? sourceIpCidrs,
  bool sourceIpIsPrivate = false,
  List<String>? inbounds,
  List<String>? wifiSsids,
  List<String>? wifiBssids,
}) {
  final rule = <String, dynamic>{};


  final hasTag = tag is List ? tag.isNotEmpty : (tag as String).isNotEmpty;
  if (hasTag) rule['rule_set'] = tag;
  if (ports != null && ports.isNotEmpty) rule['port'] = ports;
  if (portRanges != null && portRanges.isNotEmpty) {
    rule['port_range'] = portRanges;
  }
  if (packages != null && packages.isNotEmpty) rule['package_name'] = packages;
  if (protocols != null && protocols.isNotEmpty) rule['protocol'] = protocols;

  if (network != null && network.isNotEmpty) rule['network'] = network;
  if (ipIsPrivate) rule['ip_is_private'] = true;



  if (sourceIpCidrs != null && sourceIpCidrs.isNotEmpty) {
    rule['source_ip_cidr'] = sourceIpCidrs;
  }



  if (sourceIpIsPrivate) rule['source_ip_is_private'] = true;
  if (inbounds != null && inbounds.isNotEmpty) rule['inbound'] = inbounds;












  if (wifiSsids != null && wifiSsids.isNotEmpty) rule['wifi_ssid'] = wifiSsids;
  if (wifiBssids != null && wifiBssids.isNotEmpty) {
    rule['wifi_bssid'] = wifiBssids;
  }
  if (outbound == kOutboundReject) {
    rule['action'] = 'reject';
  } else {
    rule['outbound'] = outbound;
  }
  return rule;
}






Map<String, dynamic> _resolveToRoute(
  Object tag,
  RuleResolve r, {
  List<int>? ports,
  List<String>? portRanges,
  List<String>? packages,
  List<String>? protocols,
  List<String>? network,
  bool ipIsPrivate = false,
  List<String>? sourceIpCidrs,
  bool sourceIpIsPrivate = false,
  List<String>? inbounds,
  List<String>? wifiSsids,
  List<String>? wifiBssids,
}) {
  final rule = _outboundToRoute(
    tag,
    '',
    ports: ports,
    portRanges: portRanges,
    packages: packages,
    protocols: protocols,


    network: network,
    ipIsPrivate: ipIsPrivate,
    sourceIpCidrs: sourceIpCidrs,
    sourceIpIsPrivate: sourceIpIsPrivate,
    inbounds: inbounds,
    wifiSsids: wifiSsids,
    wifiBssids: wifiBssids,
  );
  rule.remove('outbound');
  rule['action'] = 'resolve';


  if (r.strategy.isNotEmpty) rule['strategy'] = r.strategy;
  if (r.serverTag.isNotEmpty) rule['server'] = r.serverTag;
  if (r.disableCache) rule['disable_cache'] = true;
  if (r.disableOptimisticCache) rule['disable_optimistic_cache'] = true;
  if (r.rewriteTtl != null) rule['rewrite_ttl'] = r.rewriteTtl;
  if (r.timeout.isNotEmpty) rule['timeout'] = r.timeout;
  if (r.clientSubnet.isNotEmpty) rule['client_subnet'] = r.clientSubnet;
  return rule;
}






List<String> _applyJsonSingle(CustomRuleJson cr, RuleSetRegistry registry) {
  final warnings = <String>[];
  final name = cr.name.trim().isEmpty ? 'unnamed' : cr.name.trim();
  final text = cr.json.trim();
  if (text.isEmpty) {
    warnings.add('Raw-JSON rule "$name" skipped: empty body.');
    return warnings;
  }
  final dynamic decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    warnings.add('Raw-JSON rule "$name" skipped: invalid JSON.');
    return warnings;
  }
  if (decoded is Map<String, dynamic>) {
    final dropped = _stripCommentKeys(decoded);
    if (dropped > 0) {
      warnings.add('Raw-JSON rule "$name": $dropped comment key(s) ("//...") '
          'dropped — the core rejects unknown fields.');
    }
    if (decoded.isEmpty) {
      warnings.add(
          'Raw-JSON rule "$name" skipped: empty after dropping comment keys.');
      return warnings;
    }
    registry.addRule(decoded);
  } else if (decoded is List) {
    var added = 0;
    var dropped = 0;
    for (final e in decoded) {
      if (e is Map<String, dynamic>) {
        dropped += _stripCommentKeys(e);


        if (e.isEmpty) continue;
        registry.addRule(e);
        added++;
      }
    }
    if (dropped > 0) {
      warnings.add('Raw-JSON rule "$name": $dropped comment key(s) ("//...") '
          'dropped — the core rejects unknown fields.');
    }
    if (added == 0) {
      warnings.add(
          'Raw-JSON rule "$name" skipped: array has no rule objects.');
    }
  } else {
    warnings.add(
        'Raw-JSON rule "$name" skipped: expected an object or array of objects.');
  }
  return warnings;
}









int _stripCommentKeys(Object? node) {
  var removed = 0;
  if (node is Map) {
    final bad =
        node.keys.where((k) => k is String && k.startsWith('//')).toList();
    for (final k in bad) {
      node.remove(k);
      removed++;
    }
    for (final v in node.values) {
      removed += _stripCommentKeys(v);
    }
  } else if (node is List) {
    for (final v in node) {
      removed += _stripCommentKeys(v);
    }
  }
  return removed;
}
