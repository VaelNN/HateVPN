import '../../../models/custom_rule.dart';
import '../../rule_set_downloader.dart';
import '../../template_loader.dart';












Future<Map<String, Object?>> serializeCustomRule(CustomRule r) async {
  final base = <String, Object?>{
    'id': r.id,
    'name': r.name,
    'enabled': r.enabled,
    'kind': r.kind.name,


    'num': r.orderNum,
  };
  switch (r) {
    case CustomRuleInline():
      return {
        ...base,
        if (r.domains.isNotEmpty) 'domains': r.domains,
        if (r.domainSuffixes.isNotEmpty) 'domain_suffixes': r.domainSuffixes,
        if (r.domainKeywords.isNotEmpty) 'domain_keywords': r.domainKeywords,
        if (r.ipCidrs.isNotEmpty) 'ip_cidrs': r.ipCidrs,
        if (r.ports.isNotEmpty) 'ports': r.ports,
        if (r.portRanges.isNotEmpty) 'port_ranges': r.portRanges,
        if (r.packages.isNotEmpty) 'packages': r.packages,
        if (r.protocols.isNotEmpty) 'protocols': r.protocols,

        if (r.network.isNotEmpty) 'network': r.network,
        if (r.ipIsPrivate) 'ip_is_private': true,

        if (r.sourceIpCidrs.isNotEmpty) 'source_ip_cidrs': r.sourceIpCidrs,
        if (r.sourceIpIsPrivate) 'source_ip_is_private': true,
        if (r.inbounds.isNotEmpty) 'inbounds': r.inbounds,


        if (r.wifiSsids.isNotEmpty) 'wifi_ssids': r.wifiSsids,
        if (r.wifiBssids.isNotEmpty) 'wifi_bssids': r.wifiBssids,
        'outbound': r.outbound,

        if (r.dns != null) 'dns': _serializeRuleDns(r.dns!),

        if (r.resolve != null) 'resolve': _serializeRuleResolve(r.resolve!),
      };
    case CustomRuleSrs():
      final cachedPath = await RuleSetDownloader.cachedPath(r.id);
      final mtime = await RuleSetDownloader.lastUpdated(r.id);
      return {
        ...base,
        'srs_url': r.srsUrl,

        'srs_urls': r.srsUrls,
        if (r.ports.isNotEmpty) 'ports': r.ports,
        if (r.portRanges.isNotEmpty) 'port_ranges': r.portRanges,
        if (r.packages.isNotEmpty) 'packages': r.packages,
        if (r.protocols.isNotEmpty) 'protocols': r.protocols,

        if (r.network.isNotEmpty) 'network': r.network,
        if (r.ipIsPrivate) 'ip_is_private': true,

        if (r.sourceIpCidrs.isNotEmpty) 'source_ip_cidrs': r.sourceIpCidrs,
        if (r.sourceIpIsPrivate) 'source_ip_is_private': true,
        if (r.inbounds.isNotEmpty) 'inbounds': r.inbounds,
        if (r.wifiSsids.isNotEmpty) 'wifi_ssids': r.wifiSsids,
        if (r.wifiBssids.isNotEmpty) 'wifi_bssids': r.wifiBssids,
        'outbound': r.outbound,
        if (r.dns != null) 'dns': _serializeRuleDns(r.dns!),
        if (r.resolve != null) 'resolve': _serializeRuleResolve(r.resolve!),
        'srs': {
          'cached': cachedPath != null,
          'path': cachedPath,
          'mtime': mtime?.toUtc().toIso8601String(),
        },
      };
    case CustomRulePreset():
      final preset = await _lookupPreset(r.presetId);
      final remoteRuleSets = <Map<String, Object?>>[];
      var inlineCount = 0;
      if (preset != null) {
        for (final rs in preset.ruleSets) {
          if (rs['type'] == 'remote') {
            final tag = rs['tag']?.toString() ?? '';
            final url = rs['url']?.toString() ?? '';
            if (tag.isEmpty) continue;
            final cacheId =
                RuleSetDownloader.presetCacheId(r.presetId, tag);
            final path = await RuleSetDownloader.cachedPathForPreset(
              r.presetId,
              tag,
            );
            final mtime = await RuleSetDownloader.lastUpdated(cacheId);
            remoteRuleSets.add({
              'tag': tag,
              'url': url,
              'cached': path != null,
              'path': path,
              'mtime': mtime?.toUtc().toIso8601String(),
            });
          } else {
            inlineCount++;
          }
        }
      }



      final refNames = preset == null
          ? const <String>{}
          : {for (final v in preset.vars) if (v.isRef) v.name};
      final cleanVarsValues = refNames.isEmpty
          ? r.varsValues
          : {
              for (final e in r.varsValues.entries)
                if (!refNames.contains(e.key)) e.key: e.value,
            };
      return {
        ...base,
        'preset_id': r.presetId,
        if (cleanVarsValues.isNotEmpty) 'vars_values': cleanVarsValues,
        'effective_outbound': r.outbound,
        if (preset != null)
          'preset': {
            'label': preset.label,
            'description': preset.description,
            'default_enabled': preset.defaultEnabled,

            'locked': preset.locked,
            'num': preset.num,
            'is_sortable': preset.isSortable,
            'inline_rule_sets': inlineCount,
            'remote_rule_sets': remoteRuleSets,
            'has_dns_rule': preset.dnsRules.isNotEmpty,


            'dns_rules_count': preset.dnsRules.length,
            'dns_servers_count': preset.dnsServers.length,
            'vars_count': preset.vars.length,
          },

        'ready': remoteRuleSets.every((rs) => rs['cached'] == true),
      };
    case CustomRuleJson():

      return {
        ...base,
        'json': r.json,
      };
  }
}


Map<String, Object?> _serializeRuleDns(RuleDns dns) => {
      'enabled': dns.enabled,
      'server_tag': dns.serverTag,

      if (dns.forceIpv4) 'force_ipv4': true,
    };



Map<String, Object?> _serializeRuleResolve(RuleResolve r) => {
      'only': r.only,
      if (r.strategy.isNotEmpty) 'strategy': r.strategy,
      if (r.serverTag.isNotEmpty) 'server_tag': r.serverTag,
      if (r.disableCache) 'disable_cache': true,
      if (r.disableOptimisticCache) 'disable_optimistic_cache': true,
      if (r.rewriteTtl != null) 'rewrite_ttl': r.rewriteTtl,
      if (r.timeout.isNotEmpty) 'timeout': r.timeout,
      if (r.clientSubnet.isNotEmpty) 'client_subnet': r.clientSubnet,
    };

Future<dynamic> _lookupPreset(String presetId) async {
  if (presetId.isEmpty) return null;
  final template = await TemplateLoader.load();
  for (final p in template.selectableRules) {
    if (p.presetId == presetId) return p;
  }
  return null;
}
