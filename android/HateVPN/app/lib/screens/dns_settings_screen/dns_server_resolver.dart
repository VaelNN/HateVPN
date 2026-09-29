import '../../models/custom_rule.dart';
import '../../models/dns_ref.dart';
import '../../models/parser_config.dart' show WizardVar;
import '../../services/builder/post_steps.dart'
    show resolveTemplateDnsServerBody;
import '../../services/builder/preset_expand.dart' show normalizeDnsDetour;
import 'resolved_server.dart';
















List<ResolvedServer> resolveDisplayedServers(
  List<DnsServerRef> servers,
  Map<String, Map<String, dynamic>> templateByTag,
  Map<String, Map<String, dynamic>> presetServersByTag, {


  Map<String, String> ruleRefsByTag = const {},
}) {
  final out = <ResolvedServer>[];
  for (final ref in servers) {
    final tag = ref.tag;
    if (tag.isEmpty) continue;

    final ServerKind kind;
    final Map<String, dynamic> body;
    ServerKind? overrides;
    String? presetLabel;
    var presetId = '';
    String? canonicalDescription;
    var vars = const <WizardVar>[];
    var varValues = const <String, String>{};

    switch (ref) {
      case DnsServerInline():
        kind = ServerKind.inline;
        body = Map<String, dynamic>.from(ref.body);

        if (presetServersByTag.containsKey(tag)) {
          overrides = ServerKind.preset;
          final p = presetServersByTag[tag]!;
          presetLabel = p['_preset_label']?.toString();
          presetId = p['_preset_id']?.toString() ?? '';
          canonicalDescription = p['description']?.toString();
        } else if (templateByTag.containsKey(tag)) {
          overrides = ServerKind.template;
          canonicalDescription = templateByTag[tag]?['description']?.toString();
        }
      case DnsServerPreset():
        kind = ServerKind.preset;
        final p = presetServersByTag[tag];
        if (p == null) continue;
        body = Map<String, dynamic>.from(p)
          ..remove('_preset_label')
          ..remove('_preset_id');
        presetLabel = p['_preset_label']?.toString();
        presetId = ref.presetId.isNotEmpty
            ? ref.presetId
            : p['_preset_id']?.toString() ?? '';
        canonicalDescription = p['description']?.toString();
      case DnsServerTemplate():
        kind = ServerKind.template;
        final t = templateByTag[tag];
        if (t == null) continue;



        varValues = ref.varValues;
        final resolvedBody =
            resolveTemplateDnsServerBody(t, varValues: varValues);
        if (resolvedBody == null) continue;
        normalizeDnsDetour(resolvedBody);
        body = resolvedBody;
        vars = (t['vars'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(WizardVar.fromJson)
            .toList();
        canonicalDescription = t['description']?.toString();
    }



    body
      ..['tag'] = tag
      ..remove('description')
      ..remove('enabled');


    final refDesc = ref.description;
    final description = (refDesc != null && refDesc.isNotEmpty)
        ? refDesc
        : (canonicalDescription ?? '');

    out.add(ResolvedServer(
      kind: kind,
      tag: tag,
      description: description,
      enabled: ref.enabled,
      body: body,
      overrides: overrides,
      presetLabel: presetLabel,
      presetId: presetId,
      vars: vars,
      varValues: varValues,
      usedByRule: ruleRefsByTag[tag],
    ));
  }


  out.sort((a, b) => a.kind.index.compareTo(b.kind.index));
  return out;
}







List<String> enabledServerTags(List<ResolvedServer> displayedServers) {
  final out = <String>[];
  for (final s in displayedServers) {
    if (!s.enabled && !s.locked) continue;
    if (s.tag.isEmpty) continue;
    out.add(s.tag);
  }
  return out;
}











({String dnsFinal, String defaultResolver}) renameDnsServerTagRefs({
  required List<DnsServerRef> servers,
  required List<DnsRuleRef> rules,
  required Map<String, Map<String, dynamic>> templateByTag,
  required String oldTag,
  required String newTag,
  required String dnsFinal,
  required String defaultResolver,
}) {
  for (var i = 0; i < servers.length; i++) {
    final entry = servers[i];
    switch (entry) {
      case DnsServerInline(:final body):
        if (body['domain_resolver'] == oldTag) {
          servers[i] = entry.copyWith(
              body: {...body, 'domain_resolver': newTag});
        }
      case DnsServerTemplate(:final varValues) when varValues.isNotEmpty:


        final wrapper = templateByTag[entry.tag];
        final dnsVarNames = <String>{
          for (final d in (wrapper?['vars'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>())
            if (d['type'] == 'dns_servers' && d['name'] is String)
              d['name'] as String,
        };
        if (dnsVarNames.any((name) => varValues[name] == oldTag)) {
          servers[i] = entry.copyWith(varValues: {
            for (final e in varValues.entries)
              e.key: dnsVarNames.contains(e.key) && e.value == oldTag
                  ? newTag
                  : e.value,
          });
        }
      case DnsServerTemplate() || DnsServerPreset():
        break;
    }
  }

  for (var i = 0; i < rules.length; i++) {
    final entry = rules[i];
    switch (entry) {
      case DnsRuleInline(:final rule) when rule['server'] == oldTag:
        rules[i] = entry.copyWith(rule: {...rule, 'server': newTag});
      case DnsRuleSrs(:final server) when server == oldTag:
        rules[i] = entry.copyWith(server: newTag);

      case DnsRuleSrs(:final body?) when body['server'] == oldTag:
        rules[i] = entry.copyWith(body: {...body, 'server': newTag});
      default:
        break;
    }
  }

  return (
    dnsFinal: dnsFinal == oldTag ? newTag : dnsFinal,
    defaultResolver: defaultResolver == oldTag ? newTag : defaultResolver,
  );
}




List<CustomRule> renameRuleDnsServerTag(
  List<CustomRule> rules,
  String oldTag,
  String newTag,
) {
  var changed = false;
  final out = rules.map((cr) {
    final dns = cr.dns;
    if (dns == null || dns.serverTag != oldTag) return cr;
    changed = true;
    return switch (cr) {
      CustomRuleInline() => cr.copyWith(dns: dns.copyWith(serverTag: newTag)),
      CustomRuleSrs() => cr.copyWith(dns: dns.copyWith(serverTag: newTag)),
      CustomRulePreset() => cr,

      CustomRuleJson() => cr,
    };
  }).toList(growable: false);
  return changed ? out : rules;
}






List<DnsRuleRef> cleanDnsRulesForPersist(
  List<DnsRuleRef> rules,
  Map<String, Map<String, dynamic>> templateRulesByName,
  Map<String, List<Map<String, dynamic>>> presetRulesByPresetId,
) {
  return rules
      .where((e) => switch (e) {
            DnsRuleInline() || DnsRuleSrs() => true,
            DnsRuleTemplate(:final name) =>
              templateRulesByName.containsKey(name),
            DnsRulePreset(:final presetId) =>
              presetRulesByPresetId.containsKey(presetId),
          })
      .toList();
}
