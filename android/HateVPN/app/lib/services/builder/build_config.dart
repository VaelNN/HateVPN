import 'dart:convert';

import '../../models/direction.dart';
import '../../models/custom_rule.dart';
import '../../models/dns_ref.dart';
import '../../models/emit_context.dart';
import '../../models/node_spec.dart' show NodeSpec;
import '../../models/node_warning.dart';
import '../../models/parser_config.dart';
import '../../models/server_list.dart';
import '../../models/source_chain.dart';
import '../contract/group_genus.dart';
import '../../models/singbox_entry.dart';
import '../../models/template_vars.dart';
import '../../config/consts.dart';
import '../../models/validation.dart';
import '../app_log.dart';
import '../json_clone.dart';
import '../node_hash.dart';
import '../safe_regex.dart';
import '../rule_set_downloader.dart';
import '../tailscale_state/state_keys.dart';
import '../settings_storage.dart';
import '../template_loader.dart';
import 'chain_nodes.dart';
import 'core_chain_capability.dart';
import 'if_engine.dart';
import 'node_link_resolve.dart';
import 'rule_order.dart';
import 'post_steps.dart';
import 'preset_expand.dart' show PresetNode;
import 'registry_gate.dart';
import 'rule_set_registry.dart';
import 'server_list_build.dart';
import 'source_replace_build.dart';
import 'validator.dart';




class BuildResult {
  final String configJson;
  final Map<String, dynamic> config;
  final ValidationResult validation;
  final List<String> emitWarnings;
  final Map<String, String> generatedVars;





  final List<String> directionsWithoutNodes;










  final Map<String, NodeSpec> nodeByEmittedTag;


  final Map<String, List<NodeWarning>> nodeBuildWarningsByEmittedTag;





  final List<TemplateWarning> templateWarnings;




  final List<RegistryWarning> buildCodes;

  const BuildResult({
    required this.configJson,
    required this.config,
    required this.validation,
    required this.emitWarnings,
    required this.generatedVars,
    this.directionsWithoutNodes = const [],
    this.nodeByEmittedTag = const {},
    this.nodeBuildWarningsByEmittedTag = const {},
    this.templateWarnings = const [],
    this.buildCodes = const [],
  });
}


class BuildSettings {
  final Map<String, String> userVars;
  final Set<String> enabledGroups;
  final List<CustomRule> customRules;
  final String routeFinal;



  final List<Direction> directions;




  final List<SourceChain> chains;









  final String coreVersion;





  final Set<String>? coreBuildTags;



  final TunAppsConfig? tunApps;



  final VpnModeConfig? vpnMode;






  final String idleSuspend;





  final String idleSuspendReachable;






  final int wgBuildMax;






  final bool wgLazyBuild;





  final bool passiveCheck;






  final String tailscaleStateRoot;




  final Map<NodeSpec, String>? tailscaleStateDirs;

  const BuildSettings({
    this.userVars = const {},
    this.enabledGroups = const {},
    this.customRules = const [],
    this.routeFinal = '',
    this.directions = const [],
    this.chains = const [],
    this.coreVersion = '',
    this.coreBuildTags = kCoreBuildTags,
    this.tunApps,
    this.vpnMode,
    this.idleSuspend = '',
    this.idleSuspendReachable = '',
    this.wgBuildMax = 5,
    this.wgLazyBuild = true,
    this.passiveCheck = false,
    this.tailscaleStateRoot = '',
    this.tailscaleStateDirs,
  });
}





















Future<BuildResult> buildConfig({
  required List<ServerList> lists,
  BuildSettings settings = const BuildSettings(),
  WizardTemplate? template,
}) {
  final templateWarnings = TemplateWarnings();
  return collectTemplateWarnings(
    templateWarnings,
    () => _buildConfig(
      lists: lists,
      settings: settings,
      template: template,
      templateWarnings: templateWarnings,
    ),
  );
}



String _renderTemplateWarning(TemplateWarning w) =>
    'Template: ${RegistryWarning(code: w.code, params: w.params).renderEn()}';




const Map<String, (int, int)> kVarIntBounds = {
  'dns_cache_capacity': (1024, 65535),
};



bool varIntInBounds(String name, String raw) {
  final b = kVarIntBounds[name];
  if (b == null) return true;
  final n = int.tryParse(raw.trim());
  return n != null && n >= b.$1 && n <= b.$2;
}

Future<BuildResult> _buildConfig({
  required List<ServerList> lists,
  required BuildSettings settings,
  required WizardTemplate? template,
  required TemplateWarnings templateWarnings,
}) async {
  template ??= await TemplateLoader.load();


  final vars = <String, String>{};



  final byName = <String, WizardVar>{};
  for (final v in template.vars) {
    final raw = settings.userVars[v.name] ?? v.defaultValue;





    vars[v.name] =
        (raw.isEmpty && v.required && v.defaultValue.isNotEmpty && v.type != 'secret')
            ? v.defaultValue
            : raw;
    byName[v.name] = v;
  }


  for (final e in kVarIntBounds.entries) {
    final v = byName[e.key];
    final raw = vars[e.key];
    if (v == null || raw == null) continue;
    if (!varIntInBounds(e.key, raw)) vars[e.key] = v.defaultValue;
  }


  for (final e in settings.userVars.entries) {
    vars.putIfAbsent(e.key, () => e.value);
  }





  final generatedVars = <String, String>{};






  final vpnMode = settings.vpnMode;
  if (vpnMode != null) {
    vars['vpn_mode'] = vpnMode.mode;
    vars['proxy_type'] = vpnMode.proxyProtocol;
    vars['proxy_listen'] = vpnMode.proxyListen;
    vars['proxy_port'] = '${vpnMode.proxyPort}';
    vars['proxy_user'] = vpnMode.proxyUsername;
    vars['proxy_pass'] = vpnMode.proxyPassword;


    vars['proxy_auth'] =
        (vpnMode.effectiveAuth && vpnMode.proxyPassword.isNotEmpty)
            ? 'true'
            : 'false';
  } else {
    vars['vpn_mode'] = 'vpn';
  }

  final resolve = makeResolver(vars, byName);

  final config = deepCopyJson(template.config);
  _substituteVars(config, resolve);




  final tvars = TemplateVars(
    tlsFragment: vars['tls_fragment'] == 'true',
    tlsRecordFragment: vars['tls_record_fragment'] == 'true',
  );





  final route = config['route'] as Map<String, dynamic>? ?? {};
  final ruleSets = RuleSetRegistry(
    initialRuleSets: route['rule_set'] as List<dynamic>? ?? const [],
    initialRules: route['rules'] as List<dynamic>? ?? const [],
  );







  final directions = settings.directions.isNotEmpty
      ? settings.directions
      : _directionsFromTemplate(
          template.groupTemplates, settings.enabledGroups, resolve);

























  final linkTargets = NodeLinkTargets()
    ..addRootNames([
      for (final raw in (config['outbounds'] as List<dynamic>? ?? const []))
        if (raw is Map && raw['tag'] is String) raw['tag'] as String,
      for (final c in directions) ...[c.tag, c.autoTag],
    ]);
  for (final list in lists) {
    if (list is! UserServer) linkTargets.noteContainer(list.id, list.name);
  }


  final replaceNames = sourceReplaceNames(lists);



  final replaceConflicts = findReplaceTagConflicts(
    lists,
    directionNames: {for (final c in directions) ...[c.tag, c.autoTag]},
    systemNames: {
      ...kReservedDirectionTags,
      for (final raw in (config['outbounds'] as List<dynamic>? ?? const []))
        if (raw is Map && raw['tag'] is String) raw['tag'] as String,
    },
  );
  final ctx = _BuildCtx(
    tvars,
    ruleSets,
    passiveCheck: settings.passiveCheck,
    reservedTags: [
      for (final c in directions) ...[c.tag, c.autoTag],
      ...replaceNames,
    ],
    coreVersion: settings.coreVersion,
    linkTargets: linkTargets,
    blockedReplaces: {for (final c in replaceConflicts) c.listId},
  );
  for (final list in lists) {
    list.build(ctx);
  }



  linkTargets.addRootNames([
    for (final p in ctx.replacePlans)
      if (p.selectorMembers.isNotEmpty || p.autoMembers.isNotEmpty)
        ...p.replace.names,
  ]);



  final detourReport = resolveDeferredDetours(ctx.deferredDetours, linkTargets);
  ctx.dropEntries(detourReport);







  final registryReport = applyRegistryGate(
    [...ctx.outbounds, ...ctx.endpoints],
    coreVersion: settings.coreVersion,
    coreBuildTags: settings.coreBuildTags,
  );
  ctx.dropRegistryEntries(registryReport.dropped);



  final buildCodes = <RegistryWarning>[
    for (final c in replaceConflicts) c.warning,
  ];
  final replaceBuild = materializeReplaceGroups(
    ctx.replacePlans,
    alive: {
      for (final e in ctx.outbounds) e.tag,
      for (final e in ctx.endpoints) e.tag,
    },
    passiveCheck: settings.passiveCheck,
    warn: ctx.warn,
    code: buildCodes.add,

    resolveVar: resolve,
  );


  final conflictNames = {
    for (final c in replaceConflicts) c.warning.params['tag'],
  };
  replaceBuild.dropped.addAll(replaceNames.where((n) =>
      !replaceBuild.emitted.contains(n) && !conflictNames.contains(n)));




  final foldDetourLines = _dropCarriersOfDroppedReplaces(
      ctx, replaceBuild.dropped, linkTargets);





  final emitWarnings = <String>[
    ...ctx.warnings,
    ...detourReport.warnings,
    ...registryReport.warnings,



    for (final w in buildCodes) w.renderEn(),
    ...foldDetourLines,
  ];
  for (final list in lists) {
    if (!list.enabled) continue;


    final disabledHashes = switch (list) {
      final SubscriptionServers s when s.disabledHashes.isNotEmpty =>
        s.disabledHashes,
      _ => null,
    };


    final identities =
        disabledHashes == null ? null : sourceNodeIdentities(list.nodes);
    for (final node in list.nodes) {
      final identity = identities?[node];
      if (identity != null && disabledHashes!.containsKey(identity)) {
        continue;
      }
      for (final w in node.warnings) {
        final line = '${node.tag}: ${w.renderEn()}';
        if (!emitWarnings.contains(line)) emitWarnings.add(line);
      }
    }
  }














  final knownChainTargets = <String>{
    for (final e in ctx.outbounds) e.tag,
    for (final e in ctx.endpoints) e.tag,
    for (final raw in (config['outbounds'] as List<dynamic>? ?? const []))
      if (raw is Map && raw['tag'] is String) raw['tag'] as String,
    for (final c in directions) c.tag,
  };
  final chainResolution = resolveChains(
    settings.chains,
    knownTags: knownChainTargets,
    targets: linkTargets,
    hopBodies: {
      for (final e in ctx.outbounds) e.tag: e.map,
      for (final e in ctx.endpoints) e.tag: e.map,
    },
    coreVersion: settings.coreVersion,
  );
  for (final d in chainResolution.degraded) {
    emitWarnings.add(d.reason);
  }
  for (final n in chainResolution.notes) {
    emitWarnings.add(n.line);
  }







  final selectorTags = <String>[
    ...ctx.selectorEntries.map((e) => e.tag),
    ...replaceBuild.candidates,
    ...chainResolution.tags,
  ];





  final nodeEntries = <Map<String, dynamic>>[
    for (final e in ctx.outbounds) e.map,
    for (final e in ctx.endpoints) e.map,

    ...replaceBuild.groups,
  ];

  final directionsWithoutNodes = <String>[];
  final presetOutbounds = _buildDirectionGroups(
    directions: directions,
    selectorTags: selectorTags,
    nodeEntries: nodeEntries,
    emitWarnings: emitWarnings,
    directionsWithoutNodes: directionsWithoutNodes,
    passiveCheck: settings.passiveCheck,


    chainHops: chainHopsByTag(chainResolution.nodes),

    includeTargets: replaceBuild.emitted,
  );

  final baseOutbounds = config['outbounds'] as List<dynamic>? ?? const [];
  config['outbounds'] = [
    ...baseOutbounds,
    ...ctx.outbounds.map((e) => e.map),


    ...chainResolution.nodes,

    ...replaceBuild.groups,
    ...presetOutbounds,
  ];







  final stateRoot = settings.tailscaleStateRoot.trim();
  if (stateRoot.isNotEmpty) {
    final stateDirs = settings.tailscaleStateDirs;
    final dirByTag = <String, String>{
      if (stateDirs != null)
        for (final e in ctx.emittedTagByNode.entries)
          if (stateDirs[e.key] case final String name) e.value: name,
    };
    for (final ep in ctx.endpoints) {
      if (ep.map['type'] != 'tailscale') continue;
      final cur = ep.map['state_directory'];
      if (cur is String && cur.isNotEmpty) continue;
      final name = dirByTag[ep.tag];
      if (name == null && stateDirs != null) {
        AppLog.I.warning('Tailscale node "${ep.tag}" has no state record, '
            'directory named by its final tag');
      }
      ep.map['state_directory'] =
          '$stateRoot/tailscale/${name ?? tailscaleStateDirName(ep.tag)}';
    }
  }

  if (ctx.endpoints.isNotEmpty) {
    final baseEndpoints = config['endpoints'] as List<dynamic>? ?? const [];
    config['endpoints'] = [
      ...baseEndpoints,
      ...ctx.endpoints.map((e) => e.map),
    ];
  }



  final presetNodes = _collectPresetNodes(lists, ctx);







  final customRules = normalizeRuleOrder(
    [...settings.customRules],
    template.selectableRules,
    template,
  );



  final srsPaths = <String, String>{};
  for (final cr in customRules) {
    if (cr is! CustomRuleSrs) continue;

    for (final cacheId in cr.cacheIds) {
      final p = await RuleSetDownloader.cachedPath(cacheId);
      if (p != null) srsPaths[cacheId] = p;
    }
  }










  final presetSrsPaths = <String, String>{};
  for (final cr in customRules) {
    if (cr is! CustomRulePreset) continue;
    if (cr.presetId.isEmpty) continue;
    SelectableRule? preset;
    for (final p in template.selectableRules) {
      if (p.presetId == cr.presetId) {
        preset = p;
        break;
      }
    }
    if (preset == null) continue;
    for (final rs in preset.ruleSets) {
      if (rs['type'] != 'remote') continue;
      final tag = rs['tag'];
      if (tag is! String || tag.isEmpty) continue;
      final path = await RuleSetDownloader.cachedPathForPreset(cr.presetId, tag);
      if (path != null) {
        presetSrsPaths['${cr.presetId}|$tag'] = path;
      }
    }
  }







  final dnsRulesStorage = await SettingsStorage.getDnsRulesList();






  final activePresetIdsWithDnsRule = <String>{
    for (final cr in customRules)
      if (cr is CustomRulePreset && cr.enabled && cr.presetId.isNotEmpty)
        if (template.selectableRules
            .any((p) => p.presetId == cr.presetId && p.dnsRules.isNotEmpty))
          cr.presetId,
  };



  final dnsSrsCachedPaths = <String, String>{};
  for (final entry in dnsRulesStorage.whereType<DnsRuleSrs>()) {
    final p = await RuleSetDownloader.cachedPath(entry.id);
    if (p != null) dnsSrsCachedPaths[entry.id] = p;
  }




  final unifiedApply = applyAllCustomRules(
    ruleSets,
    customRules,
    template.selectableRules,
    srsPaths: srsPaths,
    presetSrsPaths: presetSrsPaths,
    globalVars: vars,
    presetNodes: presetNodes,
  );
  emitWarnings.addAll(unifiedApply.warnings);



  route['rule_set'] = ruleSets.getRuleSets();
  route['rules'] = ruleSets.getRules();
  config['route'] = route;











  final idle = settings.idleSuspend.trim();
  if (idle.isNotEmpty) {
    final wg = <String, dynamic>{'idle_suspend': idle};


    final reachable = settings.idleSuspendReachable.trim();
    if (reachable.isNotEmpty) {
      wg['idle_suspend_reachable'] = reachable;
    }










    if (settings.wgLazyBuild) {
      wg['lazy_build'] = true;
      wg['build_max'] = settings.wgBuildMax < 0 ? 0 : settings.wgBuildMax;
    }
    config['lx'] = <String, dynamic>{'wg': wg};
  }











  if (settings.routeFinal.isNotEmpty) {
    final validFinals = <String>{
      kDirectOutboundTag,
      kBlockOutboundTag,
      for (final o in presetOutbounds)
        if (o['tag'] is String) o['tag'] as String,
      ...replaceBuild.emitted,
    };
    var finalTag = settings.routeFinal;
    if (!validFinals.contains(finalTag)) {
      emitWarnings.add(
          'Route final "$finalTag" no longer exists — switched to vpn-1.');
      finalTag = 'vpn-1';
    }
    route['final'] = finalTag;
  }




  if (replaceBuild.dropped.isNotEmpty) {
    emitWarnings.addAll(retargetRulesOffDroppedReplaces(
      route,
      replaceBuild.dropped,
      liveFinals: {
        kDirectOutboundTag,
        kBlockOutboundTag,
        for (final o in presetOutbounds)
          if (o['tag'] is String) o['tag'] as String,
        ...replaceBuild.emitted,
      },
    ));
  }







  final authoredBodies = Set<Map<String, dynamic>>.identity()
    ..addAll([
      for (final e in <SingboxEntry>[...ctx.outbounds, ...ctx.endpoints])
        if (e.authored) e.map,
    ]);
  for (final w in applyDetourYields(config, authored: authoredBodies)) {
    emitWarnings
        .add(w.applied ? w.renderEn() : '${w.renderEn()} (not applied)');
    if (w.ownerTag.isNotEmpty) {
      registryReport.warningsByEmittedTag
          .putIfAbsent(w.ownerTag, () => [])
          .add(w);
    }
  }
  applyTlsFragment(config, vars);
  applyMixedCaseSni(config, vars);




  final resolverDefaults = <String, String>{
    for (final name in const ['dns_final', 'dns_default_domain_resolver'])
      name: byName[name]?.defaultValue ?? '',
  };

  await applyCustomDns(
    config,
    template.dnsOptions,
    extraServers: unifiedApply.extraDnsServers,
    extraServerPresetIds: unifiedApply.dnsServerPresetIdByTag,
    extraDnsRulesByPresetId: unifiedApply.dnsRulesByPresetId,
    activePresetIdsWithDnsRule: activePresetIdsWithDnsRule,
    dnsSrsCachedPaths: dnsSrsCachedPaths,
    dnsMirrors: unifiedApply.dnsMirrors,
    warningsOut: emitWarnings,
    resolverDefaults: resolverDefaults,
    globalVars: vars,
  );








  if (settings.tunApps != null) {
    applyTunPackages(config, settings.tunApps!);
  }




  final healedPrefixes = healPresetTagPrefix(config);
  if (healedPrefixes.isNotEmpty) {
    final shown = healedPrefixes.take(5).map((h) => '${h.from} → ${h.to}');
    emitWarnings.add(
        'Preset tags migrated to namespaced form (${healedPrefixes.length}): '
        '${shown.join(', ')}${healedPrefixes.length > 5 ? ', …' : ''}');
  }





  final healedResolve = healDanglingResolveServers(config);
  for (final h in healedResolve) {
    emitWarnings.add(
        'Resolve server removed: route rule #${h.ruleIndex} referenced '
        'missing DNS server "${h.target}" — falling back to DNS routing.');
  }






  final healedResolvers = healDanglingDnsResolvers(
    config,
    defaults: resolverDefaults,
  );
  for (final h in healedResolvers) {
    generatedVars[h.varName] = h.to;
    emitWarnings.add(
        '${h.field} reset to "${h.to}": DNS server "${h.from}" is gone '
        '(its preset was disabled or removed).');
  }





  final healedDnsStrategy = healLegacyDnsStrategy(config);
  if (healedDnsStrategy.isNotEmpty) {
    emitWarnings.add(
        'DNS rule strategy removed on rules ${healedDnsStrategy.join(", ")}: '
        'incompatible with query_type/ip_version DNS rules (e.g. FakeIP or '
        'Force IPv4) — kernel would reject the config. Resolution falls back '
        'to the global DNS strategy.');
  }





  final healedFingerprints = healUnknownUtlsFingerprints(config,
      authored: authoredBodies);
  for (final h in healedFingerprints) {
    emitWarnings.add(
        'Fingerprint replaced: outbound "${h.owner}" had unknown uTLS '
        'fingerprint "${h.original}" — using "chrome" instead.');
  }






  final healedReality = healInvalidReality(config, authored: authoredBodies);
  for (final h in healedReality) {
    emitWarnings.add(h.field == 'short_id'
        ? 'REALITY short_id cleared: outbound "${h.owner}" had invalid '
            'hex "${h.original}" — kernel would reject the whole config.'
        : 'REALITY removed: outbound "${h.owner}" had invalid public_key '
            '"${h.original}" — node degraded to plain TLS.');
  }










  emitWarnings.addAll(sanitizeOutboundGraph(
    config,
    directionTags: {for (final c in directions) c.tag},
  ));

  final validation = validateConfig(config);

  final templateItems = templateWarnings.items;
  return BuildResult(
    configJson: jsonEncode(config),
    config: config,
    validation: validation,
    emitWarnings: [
      for (final w in templateItems) _renderTemplateWarning(w),
      ...emitWarnings,
    ],
    templateWarnings: templateItems,
    buildCodes: buildCodes,
    generatedVars: generatedVars,
    directionsWithoutNodes: directionsWithoutNodes,
    nodeByEmittedTag: {
      for (final e in ctx.emittedTagAliases.entries) e.key: e.value,
      for (final e in ctx.emittedTagByNode.entries) e.value: e.key,
    },
    nodeBuildWarningsByEmittedTag: registryReport.warningsByEmittedTag,
  );
}






List<PresetNode> _collectPresetNodes(List<ServerList> lists, _BuildCtx ctx) {
  final skip = <NodeSpec>{};
  for (final list in lists) {
    switch (list) {
      case UserServer u:
        if (u.skipPresets) skip.addAll(u.nodes);
      case FolderServers f:
        for (final m in f.members) {
          final node = m.node;
          if (m.skipPresets && node != null) skip.add(node);
        }
      case SubscriptionServers():
        break;
    }
  }
  final nodeByTag = <String, NodeSpec>{
    for (final e in ctx.emittedTagByNode.entries) e.value: e.key,
  };
  return [
    for (final e in <SingboxEntry>[...ctx.outbounds, ...ctx.endpoints])
      if (nodeByTag[e.tag] case final NodeSpec node)
        PresetNode(tag: e.tag, body: e.map, skipPresets: skip.contains(node)),
  ];
}



class _BuildCtx implements EmitContext {
  _BuildCtx(
    this._vars,
    this._ruleSets, {
    bool passiveCheck = false,
    Iterable<String> reservedTags = const [],
    String coreVersion = '',
    this.linkTargets,
    Set<String> blockedReplaces = const {},
  })  : _passiveCheck = passiveCheck,
        _coreVersion = coreVersion,
        _blockedReplaces = blockedReplaces {
    _taken.addAll(reservedTags);
  }

  final Set<String> _blockedReplaces;

  @override
  bool isReplaceBlocked(String listId) => _blockedReplaces.contains(listId);

  @override
  final NodeLinkTargets? linkTargets;


  final deferredDetours = <DeferredDetour>[];

  @override
  void deferDetour(DeferredDetour detour) => deferredDetours.add(detour);



  void dropEntries(DeferredDetourReport report) {
    if (report.droppedEntries.isEmpty) return;
    bool gone(SingboxEntry e) => report.droppedEntries.contains(e);
    outbounds.removeWhere(gone);
    endpoints.removeWhere(gone);
    selectorEntries.removeWhere(gone);
    autoEntries.removeWhere(gone);
    emittedTagByNode
        .removeWhere((node, _) => report.droppedNodes.contains(node));
  }








  void dropRegistryEntries(List<SingboxEntry> dropped) {
    if (dropped.isEmpty) return;
    bool gone(SingboxEntry e) => dropped.contains(e);
    outbounds.removeWhere(gone);
    endpoints.removeWhere(gone);
    selectorEntries.removeWhere(gone);
    autoEntries.removeWhere(gone);
    final tags = {for (final e in dropped) e.tag};
    emittedTagByNode.removeWhere((_, tag) => tags.contains(tag));
    emittedTagAliases.removeWhere((tag, _) => tags.contains(tag));
  }
  final TemplateVars _vars;
  final RuleSetRegistry _ruleSets;
  final bool _passiveCheck;
  final String _coreVersion;
  final _taken = <String>{kDirectOutboundTag, 'dns-out', 'block-out'};

  final outbounds = <Outbound>[];
  final endpoints = <Endpoint>[];
  final selectorEntries = <SingboxEntry>[];
  final autoEntries = <SingboxEntry>[];


  final replacePlans = <ReplacePlan>[];

  @override
  void addReplacePlan(ReplacePlan plan) => replacePlans.add(plan);


  final emittedTagByNode = <NodeSpec, String>{};


  final emittedTagAliases = <String, NodeSpec>{};


  final warnings = <String>[];

  @override
  TemplateVars get vars => _vars;

  @override
  RuleSetRegistry get ruleSets => _ruleSets;

  @override
  bool get passiveCheck => _passiveCheck;

  @override
  String get coreVersion => _coreVersion;

  @override
  void noteEmitted(NodeSpec node, String finalTag) {
    emittedTagByNode[node] = finalTag;
  }

  @override
  void noteEmittedAlias(String finalTag, NodeSpec owner) {
    emittedTagAliases[finalTag] = owner;
  }

  @override
  void warn(String line) {
    if (!warnings.contains(line)) warnings.add(line);
  }

  @override
  String allocateTag(String baseTag) {
    if (!_taken.contains(baseTag)) {
      _taken.add(baseTag);
      return baseTag;
    }
    for (var i = 1; i < 100000; i++) {
      final c = '$baseTag-$i';
      if (!_taken.contains(c)) {
        _taken.add(c);
        return c;
      }
    }
    return baseTag;
  }

  @override
  void addEntry(SingboxEntry entry) {
    switch (entry) {
      case Outbound():
        outbounds.add(entry);
      case Endpoint():
        endpoints.add(entry);
    }
  }

  @override
  void addToSelectorTagList(SingboxEntry entry) => selectorEntries.add(entry);

  @override
  void addToAutoList(SingboxEntry entry) => autoEntries.add(entry);
}












List<Map<String, dynamic>> _buildDirectionGroups({
  required List<Direction> directions,
  required List<String> selectorTags,
  required List<Map<String, dynamic>> nodeEntries,
  required List<String> emitWarnings,
  required List<String> directionsWithoutNodes,
  bool passiveCheck = false,


  Map<String, List<String>> chainHops = const {},


  Set<String> includeTargets = const {},
}) {


  final baseNodes = selectorTags;

  final active = directions.where((c) => c.enabled || c.isRequired).toList();



  List<String> nodesFor(Direction c) {
    if (c.nodeFilter.isEmpty) return baseNodes;
    final re = tryCompileRegex(c.nodeFilter, caseSensitive: false);
    if (re == null) return baseNodes;
    return baseNodes
        .where((t) => re.hasMatch(t) != c.nodeFilterInvert)
        .toList();
  }









  final memberSets = <List<String>>[];






  final filteredCounts = <int>[];
  for (final c in active) {
    final filtered = nodesFor(c);
    filteredCounts.add(filtered.length);
    final (:kept, :dropped) =
        dropChainsThroughDirection(filtered, c.tag, chainHops);
    memberSets.add(kept);
    if (dropped.isNotEmpty) {
      emitWarnings.add(chainCycleThroughDirectionLine(c.displayLabel, dropped));
    }
  }




  final groupTags = {
    for (final e in nodeEntries)
      if (GroupGenus.isKnown('${e['type']}')) e['tag'] as String,
  };
  final autoSets = [
    for (final ms in memberSets)
      [
        for (final t in ms)
          if (!groupTags.contains(t)) t,
      ],
  ];





  final emittedAbove = <String>{};

  final result = <Map<String, dynamic>>[];
  for (var i = 0; i < active.length; i++) {
    final c = active[i];
    final nodes = memberSets[i];
    final autoNodes = autoSets[i];
    final emitAuto = c.auto != null && autoNodes.isNotEmpty;












    final includeTags = <String>[];
    for (final t in c.include) {
      if (emittedAbove.contains(t) || includeTargets.contains(t)) {
        if (!includeTags.contains(t)) includeTags.add(t);
        continue;
      }
      emitWarnings.add(
          'Direction "${c.displayLabel}" (${c.tag}): option "$t" dropped — '
          'it must be another direction listed above this one (and enabled).');
    }
























    final selectorOutbounds = <String>[
      if (emitAuto) c.autoTag,
      if (c.includeDirect) kDirectOutboundTag,
      if (c.includeBlock) kBlockOutboundTag,
      ...includeTags,

      for (final t in nodes)
        if (!includeTags.contains(t)) t,
    ];







    final emptyFallback = selectorOutbounds.isEmpty;
    if (emptyFallback) {
      selectorOutbounds.addAll([kBlockOutboundTag, kDirectOutboundTag]);
    }








    if (nodes.isEmpty &&
        filteredCounts[i] == 0 &&
        c.nodeFilter.isNotEmpty &&
        selectorTags.isNotEmpty) {
      final effective =
          emptyFallback ? kBlockOutboundTag : selectorOutbounds.first;




      final outcome = switch (effective) {
        kDirectOutboundTag => 'traffic goes direct (no VPN hop)',
        kBlockOutboundTag => 'traffic is blocked (default)',
        _ => 'traffic falls back to "$effective"',
      };
      emitWarnings.add(
          'Direction "${c.displayLabel}" (${c.tag}): node filter matched no '
          'nodes — $outcome. '
          'Check its node filter.');








      final onlyMagic = selectorOutbounds
          .every((t) => t == kDirectOutboundTag || t == kBlockOutboundTag);
      if (emptyFallback || onlyMagic) {
        directionsWithoutNodes.add(c.displayLabel);
      }
    }

    final selector = <String, dynamic>{
      'tag': c.tag,
      'type': 'selector',
      'outbounds': selectorOutbounds,
      'interrupt_exist_connections': c.interruptExistConnections,
    };

    if (emptyFallback) {
      selector['default'] = kBlockOutboundTag;
    }


    if (c.defaultFilter.isNotEmpty) {
      final re = tryCompileRegex(c.defaultFilter, caseSensitive: false);
      final def = re == null ? null : _firstMatch(nodes, re);








      if (def != null && selectorOutbounds.contains(def)) {
        selector['default'] = def;
      }
    }












    if (emitAuto && !selector.containsKey('default')) {
      selector['default'] = c.autoTag;
    }






    if (emitAuto) {
      result.add(buildAutoGroup(
        tag: c.autoTag,
        outbounds: autoNodes,
        a: c.auto!,
        passiveCheck: passiveCheck,
      ));
    }








    result.add(selector);







    emittedAbove.add(c.tag);
  }
  return result;
}






List<Direction> _directionsFromTemplate(
  GroupTemplates gt,
  Set<String> enabledGroupTags,
  VarResolver resolve,
) {





  const fallback = DirectionAuto();
  String? s(String name) => resolve(name)?.toString();

  DirectionAuto seedAuto() => DirectionAuto(
        url: s('urltest_url') ?? fallback.url,
        interval: s('urltest_interval') ?? fallback.interval,
        tolerance: int.tryParse(s('urltest_tolerance') ?? '') ?? fallback.tolerance,
        idleTimeout: fallback.idleTimeout,
        interruptExistConnections: fallback.interruptExistConnections,
      );

  final hasAuto = gt.direction.include.contains('auto');
  final out = <Direction>[];
  for (final dc in gt.defaultDirections) {
    final enabled = dc.tag == 'vpn-1'
        ? true
        : (enabledGroupTags.isEmpty
            ? dc.defaultEnabled
            : enabledGroupTags.contains(dc.tag));
    final auto = hasAuto ? seedAuto() : null;
    out.add(
        Direction.seedFromDefault(dc, gt.direction, enabled: enabled, auto: auto));
  }
  return out;
}






String? _firstMatch(List<String> tags, RegExp re) {
  for (final t in tags) {
    if (re.hasMatch(t)) return t;
  }
  return null;
}











void _substituteVars(dynamic obj, VarResolver resolve) {
  walk(obj, resolve);
}







List<String> _dropCarriersOfDroppedReplaces(
  _BuildCtx ctx,
  Set<String> dropped,
  NodeLinkTargets targets,
) {
  if (dropped.isEmpty) return const [];
  targets.markDropped(dropped);
  final entries = <SingboxEntry>[...ctx.outbounds, ...ctx.endpoints];
  final gone = <String>{...dropped};
  final carriersBy = <String, List<String>>{};
  final removed = <SingboxEntry>[];
  var changed = true;
  while (changed) {
    changed = false;
    for (final e in entries) {
      if (removed.contains(e)) continue;
      final d = e.map['detour'];
      if (d is! String || !gone.contains(d)) continue;
      removed.add(e);
      gone.add(e.tag);

      final root = dropped.contains(d)
          ? d
          : carriersBy.entries
                  .firstWhere((c) => c.value.contains(d),
                      orElse: () => MapEntry(d, const []))
                  .key;
      carriersBy.putIfAbsent(root, () => []).add(e.tag);
      changed = true;
    }
  }
  if (removed.isEmpty) return const [];
  ctx.dropRegistryEntries(removed);
  targets.markDropped(removed.map((e) => e.tag));
  return [
    for (final c in carriersBy.entries)
      '${c.value.length == 1 ? 'Node "${c.value.single}" was' : '${c.value.length} nodes (${c.value.take(5).map((t) => '"$t"').join(', ')}${c.value.length > 5 ? ', and ${c.value.length - 5} more' : ''}) were'} '
          'skipped: the detour goes through replace group "${c.key}", which '
          'was not built. A node whose detour does not resolve is not '
          'emitted, so its traffic never goes direct.',
  ];
}
