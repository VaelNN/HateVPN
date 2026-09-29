














import '../../models/custom_rule.dart';
import '../../models/dns_ref.dart';
import '../../models/parser_config.dart';



import '../../screens/dns_settings_screen/dns_server_resolver.dart';
import '../../widgets/outbound_picker.dart' show OutboundOption;
import '../builder/build_config.dart' show varIntInBounds;
import '../builder/post_steps.dart';
import '../builder/preset_expand.dart';
import '../builder/rule_set_registry.dart';
import '../settings_storage.dart';
import '../template_loader.dart';




class DnsSettingsSnapshot {
  const DnsSettingsSnapshot({
    required this.servers,
    required this.templateByTag,
    required this.presetServersByTag,
    required this.rules,
    required this.templateRulesByName,
    required this.presetRulesByPresetId,
    required this.presetLabelByPresetId,
    required this.presetDnsEnable,
    required this.outboundOptions,
    required this.customRules,
    required this.dnsMirrorsByRuleId,
    required this.strategy,
    required this.dnsFinal,
    required this.defaultResolver,
    required this.resolverReset,
    this.presetServedTagsByPresetId = const {},
    this.cacheCapacity = '',
    this.optimistic = true,
    this.storeCache = true,
  });

  final List<DnsServerRef> servers;
  final Map<String, Map<String, dynamic>> templateByTag;
  final Map<String, Map<String, dynamic>> presetServersByTag;
  final List<DnsRuleRef> rules;
  final Map<String, Map<String, dynamic>> templateRulesByName;
  final Map<String, List<Map<String, dynamic>>> presetRulesByPresetId;
  final Map<String, String> presetLabelByPresetId;
  final Map<String, bool> presetDnsEnable;
  final List<OutboundOption> outboundOptions;
  final List<CustomRule> customRules;
  final Map<String, List<DnsMirrorEntry>> dnsMirrorsByRuleId;
  final String strategy;
  final String dnsFinal;
  final String defaultResolver;



  final bool resolverReset;



  final Map<String, List<String>> presetServedTagsByPresetId;




  final String cacheCapacity;
  final bool optimistic;
  final bool storeCache;
}

class DnsController {
  const DnsController._();









  static Future<DnsSettingsSnapshot> load({
    List<PresetNode> presetNodes = const [],
  }) async {
    final template = await TemplateLoader.load();
    final vars = await SettingsStorage.getAllVars();



    final templateServersRaw = [
      for (final s in template.dnsOptionsModel.servers) s.wrapper,
    ];
    final templateRulesRaw =
        (template.dnsOptions['rules'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();



    final templateByTag = template.dnsOptionsModel.wrappersByTag;


    final directions = await SettingsStorage.getDirections();
    final outboundOptions = <OutboundOption>[
      const OutboundOption(value: 'direct-out', label: 'direct'),
      for (final c in directions)
        if (c.enabled || c.isRequired)
          OutboundOption(value: c.tag, label: c.displayLabel),
    ];


    final templateRulesByName = <String, Map<String, dynamic>>{
      for (final r in templateRulesRaw)
        if (r['name'] is String && (r['name'] as String).isNotEmpty)
          r['name'] as String: r,
    };



    final presetRulesByPresetId = <String, List<Map<String, dynamic>>>{};
    final presetLabelByPresetId = <String, String>{};
    final presetDnsEnable = <String, bool>{};
    final presetServersWithLabel = <Map<String, dynamic>>[];


    final presetIdByServerTag = <String, String>{};






    final storedPresetIdByTag = <String, String>{};
    final presetServedTagsByPresetId = <String, List<String>>{};
    final activeRules = await SettingsStorage.getCustomRules();
    final allPresets = template.selectableRules;
    final activePresetIdsWithDnsRule = <String>{};
    for (final cr in activeRules) {
      if (cr is! CustomRulePreset) continue;
      if (cr.presetId.isEmpty) continue;
      if (!cr.enabled) continue;
      SelectableRule? match;
      for (final p in allPresets) {
        if (p.presetId == cr.presetId) {
          match = p;
          break;
        }
      }
      if (match == null) continue;
      if (match.dnsRules.isNotEmpty) {
        activePresetIdsWithDnsRule.add(cr.presetId);
      }

      if (match.vars.any((v) => v.name == 'dns_enable')) {
        presetDnsEnable[cr.presetId] = presetDnsEnableVar(cr, match);
      }
      final fragments = expandPreset(cr, match, nodes: presetNodes);
      if (match.forEach != null) {
        presetServedTagsByPresetId[cr.presetId] = [
          for (final n in presetForEachNodes(cr, match, presetNodes)) n.tag,
        ];
      }
      if (match.dnsRules.isNotEmpty) {
        presetRulesByPresetId[cr.presetId] = fragments.dnsRules;
      }
      presetLabelByPresetId[cr.presetId] = match.label;
      for (final s in fragments.dnsServers) {
        final tag = s['tag'];
        if (tag is String && tag.isNotEmpty) {
          presetIdByServerTag.putIfAbsent(tag, () => cr.presetId);
          if (tag.startsWith('${cr.presetId}:')) {
            storedPresetIdByTag.putIfAbsent(tag, () => cr.presetId);
          }
        }
        final annotated = Map<String, dynamic>.from(s)
          ..['_preset_label'] = match.label;
        presetServersWithLabel.add(annotated);
      }
    }



    final resolvedRules = await resolveDnsRulesList(
      templateRules: templateRulesRaw,
      activePresetIdsWithDnsRule: activePresetIdsWithDnsRule,
    );


    final presetServersByTag = <String, Map<String, dynamic>>{
      for (final s in presetServersWithLabel)
        if (s['tag'] is String && (s['tag'] as String).isNotEmpty)
          s['tag'] as String: s,
    };


    presetServersByTag.forEach(
        (tag, s) => s['_preset_id'] = presetIdByServerTag[tag]);
    final resolvedServers = await resolveDnsServersList(
      templateServers: templateServersRaw,
      presetServersByTag: presetServersByTag,
      presetIdByTag: storedPresetIdByTag,
    );


    final previewRules = [
      for (final cr in activeRules)
        if (cr.dnsMirrorEligible && !(cr.dns?.enabled ?? false))
          switch (cr) {
            CustomRuleInline() =>
              cr.copyWith(dns: cr.dns!.copyWith(enabled: true)),
            CustomRuleSrs() =>
              cr.copyWith(dns: cr.dns!.copyWith(enabled: true)),
            _ => cr,
          }
        else
          cr,
    ];
    final mirrorSrsPaths = <String, String>{
      for (final cr in previewRules)
        if (cr is CustomRuleSrs) cr.id: '<srs>',
    };
    final unifiedMirrors = applyAllCustomRules(
      RuleSetRegistry(),
      previewRules,
      allPresets,
      srsPaths: mirrorSrsPaths,
    );

    final dnsMirrorsByRuleId = <String, List<DnsMirrorEntry>>{};
    for (final m in unifiedMirrors.dnsMirrors) {
      final id = m.ruleId;
      if (id == null || id.isEmpty) continue;
      (dnsMirrorsByRuleId[id] ??= []).add(m);
    }



    final ruleRefsByTag = <String, String>{
      for (final cr in activeRules)
        if (cr.dnsMirrorActive)
          cr.dns!.serverTag: cr.name.isNotEmpty ? cr.name : 'rule',
    };
    final availableTags = enabledServerTags(resolveDisplayedServers(
        resolvedServers, templateByTag, presetServersByTag,
        ruleRefsByTag: ruleRefsByTag));





    final templateDefaults = <String, String>{
      for (final v in template.vars) v.name: v.defaultValue,
    };
    String defaultOf(String name) => templateDefaults[name] ?? '';



    final storedFinal = vars['dns_final'] ?? '';
    final storedResolver = vars['dns_default_domain_resolver'] ?? '';
    var dnsFinal =
        storedFinal.isNotEmpty ? storedFinal : defaultOf('dns_final');
    var defaultResolver = storedResolver.isNotEmpty
        ? storedResolver
        : defaultOf('dns_default_domain_resolver');
    var resolverReset = false;
    if (dnsFinal.isNotEmpty && !availableTags.contains(dnsFinal)) {
      dnsFinal = defaultOf('dns_final');
      resolverReset = true;
    }
    if (defaultResolver.isNotEmpty &&
        !availableTags.contains(defaultResolver)) {
      defaultResolver = defaultOf('dns_default_domain_resolver');
      resolverReset = true;
    }



    String varOrDefault(String name) {
      final v = vars[name] ?? '';
      return v.trim().isNotEmpty ? v.trim() : defaultOf(name);
    }

    bool boolVar(String name) =>
        varOrDefault(name).toLowerCase() == 'true';
    var cacheCapacity = varOrDefault('dns_cache_capacity');
    if (!varIntInBounds('dns_cache_capacity', cacheCapacity)) {
      cacheCapacity = defaultOf('dns_cache_capacity');
    }

    return DnsSettingsSnapshot(
      servers: resolvedServers,
      templateByTag: templateByTag,
      presetServersByTag: presetServersByTag,
      rules: resolvedRules,
      templateRulesByName: templateRulesByName,
      presetRulesByPresetId: presetRulesByPresetId,
      presetLabelByPresetId: presetLabelByPresetId,
      presetDnsEnable: presetDnsEnable,
      outboundOptions: outboundOptions,
      customRules: activeRules,
      dnsMirrorsByRuleId: dnsMirrorsByRuleId,

      strategy: (vars['dns_strategy']?.isNotEmpty ?? false)
          ? vars['dns_strategy']!
          : defaultOf('dns_strategy'),
      dnsFinal: dnsFinal,
      defaultResolver: defaultResolver,
      resolverReset: resolverReset,
      presetServedTagsByPresetId: presetServedTagsByPresetId,
      cacheCapacity: cacheCapacity,
      optimistic: boolVar('dns_optimistic'),
      storeCache: boolVar('dns_store_cache'),
    );
  }




  static Future<void> stage({
    required List<DnsServerRef> servers,
    required List<DnsRuleRef> rules,
    required Map<String, Map<String, dynamic>> templateRulesByName,
    required Map<String, List<Map<String, dynamic>>> presetRulesByPresetId,
    required String strategy,
    required String dnsFinal,
    required String defaultResolver,
    String? cacheCapacity,
    bool? optimistic,
    bool? storeCache,
  }) async {
    await SettingsStorage.saveDnsServers(servers, flush: false);
    final cleaned = cleanDnsRulesForPersist(
      rules,
      templateRulesByName,
      presetRulesByPresetId,
    );
    await SettingsStorage.saveDnsRulesList(cleaned, flush: false);
    await SettingsStorage.setVar('dns_strategy', strategy, flush: false);
    await SettingsStorage.setVar('dns_final', dnsFinal, flush: false);
    await SettingsStorage.setVar(
        'dns_default_domain_resolver', defaultResolver,
        flush: false);

    if (cacheCapacity != null &&
        varIntInBounds('dns_cache_capacity', cacheCapacity)) {
      await SettingsStorage.setVar('dns_cache_capacity', cacheCapacity,
          flush: false);
    }
    if (optimistic != null) {
      await SettingsStorage.setVar('dns_optimistic', '$optimistic',
          flush: false);
    }
    if (storeCache != null) {
      await SettingsStorage.setVar('dns_store_cache', '$storeCache',
          flush: false);
    }
  }
}
