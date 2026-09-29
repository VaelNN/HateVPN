




























library;

import '../models/custom_rule.dart';
import '../models/dns_ref.dart';
import '../models/parser_config.dart';
import 'app_log.dart';
import 'template_loader.dart';


const String kPresetOutboundVar = 'outbound';


class RecordVarDecl {
  const RecordVarDecl({
    required this.name,
    this.defaultValue = '',
    this.type = '',
    this.isRef = false,
  });

  final String name;


  final String defaultValue;


  final String type;


  final bool isRef;
}


class RecordVarDecls {
  const RecordVarDecls({this.dnsServers = const {}, this.presets = const {}});


  static const none = RecordVarDecls();



  final Map<String, List<RecordVarDecl>> dnsServers;


  final Map<String, List<RecordVarDecl>> presets;

  bool get isEmpty => dnsServers.isEmpty && presets.isEmpty;


  factory RecordVarDecls.fromTemplate(WizardTemplate template) =>
      RecordVarDecls(
        dnsServers: dnsServerVarDecls(template.dnsOptions),
        presets: {
          for (final p in template.selectableRules)
            if (p.presetId.isNotEmpty)
              p.presetId: [
                for (final v in p.vars)
                  if (v.name.isNotEmpty)
                    RecordVarDecl(
                      name: v.name,
                      defaultValue: v.defaultValue,
                      type: v.type,
                      isRef: v.isRef,
                    ),
              ],
        },
      );





  factory RecordVarDecls.fromJson(Map<String, dynamic> j) {
    final dnsOptions = j['dns_options'];
    final presets = <String, List<RecordVarDecl>>{};
    for (final key in const ['presets', 'selectable_rules']) {
      final list = j[key];
      if (list is! List) continue;
      for (final p in list) {
        if (p is! Map) continue;
        final id = p['id'] ?? p['preset_id'];
        if (id is! String || id.isEmpty) continue;
        presets[id] = _declsOf(p['vars']);
      }
    }
    return RecordVarDecls(
      dnsServers: dnsOptions is Map
          ? dnsServerVarDecls(dnsOptions.cast<String, dynamic>())
          : const {},
      presets: presets,
    );
  }
}



Map<String, List<RecordVarDecl>> dnsServerVarDecls(
    Map<String, dynamic> dnsOptions) {
  final out = <String, List<RecordVarDecl>>{};
  final servers = dnsOptions['servers'];
  if (servers is! List) return out;
  for (final s in servers) {
    if (s is! Map) continue;
    final server = s['server'];
    final tag = server is Map ? server['tag'] : s['tag'];
    if (tag is! String || tag.isEmpty || out.containsKey(tag)) continue;
    out[tag] = _declsOf(s['vars']);
  }
  return out;
}

List<RecordVarDecl> _declsOf(Object? raw) => [
      if (raw is List)
        for (final d in raw)
          if (d is Map) ?_declOf(d),
    ];

RecordVarDecl? _declOf(Map d) {
  final ref = d['ref'];
  if (ref is String && ref.isNotEmpty) {
    return RecordVarDecl(name: ref, isRef: true);
  }
  final name = d['name'];
  if (name is! String || name.isEmpty) return null;

  final def = d.containsKey('default_value') ? d['default_value'] : d['default'];
  final type = d['type'];
  return RecordVarDecl(
    name: name,
    defaultValue: def?.toString() ?? '',
    type: type is String ? type : '',
  );
}



Future<RecordVarDecls> loadRecordVarDecls() async {
  try {
    return RecordVarDecls.fromTemplate(await TemplateLoader.load());
  } catch (e) {
    AppLog.I.warning('record vars: template not loaded ($e); '
        'record variables are written as is');
    return RecordVarDecls.none;
  }
}



typedef RecordVarsNormalized = ({
  Map<String, String> vars,
  List<String> undeclared,
});





RecordVarsNormalized normalizeRecordVarValues(
  Map<String, String> values,
  List<RecordVarDecl> decls, {
  Set<String> implicit = const {},
}) {
  final byName = {for (final d in decls) d.name: d};
  final vars = <String, String>{};
  final undeclared = <String>[];
  for (final e in values.entries) {
    final decl = byName[e.key];
    if (decl == null) {
      if (implicit.contains(e.key)) {
        final v = e.value.trim();
        if (v.isNotEmpty) vars[e.key] = v;
      } else {
        undeclared.add(e.key);
      }
      continue;
    }
    if (decl.isRef) {
      vars[e.key] = e.value;
      continue;
    }
    final v = e.value.trim();
    if (v.isEmpty || v == decl.defaultValue.trim()) continue;
    vars[e.key] = v;
  }
  return (vars: vars, undeclared: undeclared);
}





String? recordVarValueToStore(String value, RecordVarDecl? decl) {
  if (decl != null && decl.isRef) return value;
  final v = value.trim();
  if (v.isEmpty) return null;
  if (decl != null && v == decl.defaultValue.trim()) return null;
  return v;
}

bool _sameVars(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}



DnsServerRef normalizeDnsServerVars(
  DnsServerRef server,
  RecordVarDecls decls, {
  void Function(String name)? onUndeclared,
}) {
  if (server is! DnsServerTemplate) return server;
  final declared = decls.dnsServers[server.tag];
  if (declared == null) return server;
  final n = normalizeRecordVarValues(server.varValues, declared);
  if (onUndeclared != null) n.undeclared.forEach(onUndeclared);
  if (_sameVars(n.vars, server.varValues)) return server;
  return server.copyWith(varValues: n.vars);
}


List<DnsServerRef> normalizeDnsServersVars(
  List<DnsServerRef> servers,
  RecordVarDecls decls, {
  void Function(String tag, String name)? onUndeclared,
}) {
  if (decls.dnsServers.isEmpty) return servers;
  return [
    for (final s in servers)
      normalizeDnsServerVars(
        s,
        decls,
        onUndeclared:
            onUndeclared == null ? null : (name) => onUndeclared(s.tag, name),
      ),
  ];
}



CustomRule normalizePresetRuleVars(
  CustomRule rule,
  RecordVarDecls decls, {
  void Function(String name)? onUndeclared,
}) {
  if (rule is! CustomRulePreset) return rule;
  final declared = decls.presets[rule.presetId];
  if (declared == null) return rule;
  final n = normalizeRecordVarValues(rule.varsValues, declared,
      implicit: const {kPresetOutboundVar});
  if (onUndeclared != null) n.undeclared.forEach(onUndeclared);
  if (_sameVars(n.vars, rule.varsValues)) return rule;
  return rule.copyWith(varsValues: n.vars);
}


List<CustomRule> normalizePresetRulesVars(
  List<CustomRule> rules,
  RecordVarDecls decls, {
  void Function(String presetId, String name)? onUndeclared,
}) {
  if (decls.presets.isEmpty) return rules;
  return [
    for (final r in rules)
      normalizePresetRuleVars(
        r,
        decls,
        onUndeclared: onUndeclared == null
            ? null
            : (name) => onUndeclared(r.presetId, name),
      ),
  ];
}





({String tag, String varName})? rootDnsVarTarget(
  String name,
  RecordVarDecls decls,
) {
  if (!name.startsWith('dns_')) return null;
  ({String tag, String varName})? best;
  for (final e in decls.dnsServers.entries) {
    final tag = e.key;
    for (final d in e.value) {
      if (d.isRef || 'dns_${tag}_${d.name}' != name) continue;
      if (best == null || tag.length > best.tag.length) {
        best = (tag: tag, varName: d.name);
      }
    }
  }
  return best;
}








Map<String, String> directionRefRetarget(
  String tag,
  String to, {
  bool rename = false,
}) =>
    {tag: to, '$tag-auto': rename ? '$to-auto' : to};



Set<String> dnsServerOutboundVarNames(String tag, RecordVarDecls decls) {
  final declared = decls.dnsServers[tag];
  if (declared == null) return const {kPresetOutboundVar};
  return {
    for (final d in declared)
      if (!d.isRef && d.type == 'outbound') d.name,
  };
}



Set<String> presetOutboundVarNames(String presetId, RecordVarDecls decls) => {
      kPresetOutboundVar,
      for (final d in decls.presets[presetId] ?? const <RecordVarDecl>[])
        if (!d.isRef && d.type == 'outbound') d.name,
    };




Map<String, String>? _retargetValues(
  Map<String, String> values,
  Set<String> names,
  List<RecordVarDecl> decls,
  Map<String, String> retarget,
) {
  Map<String, String>? out;
  for (final name in names) {
    final to = retarget[values[name]?.trim()];
    if (to == null) continue;
    out ??= Map<String, String>.of(values);
    final decl = decls.where((d) => d.name == name).firstOrNull;
    final stored = recordVarValueToStore(to, decl);
    if (stored == null) {
      out.remove(name);
    } else {
      out[name] = stored;
    }
  }
  return out;
}




DnsServerRef retargetDnsServerOutboundVars(
  DnsServerRef server,
  RecordVarDecls decls,
  Map<String, String> retarget,
) {
  if (server is! DnsServerTemplate || server.varValues.isEmpty) return server;
  final next = _retargetValues(
    server.varValues,
    dnsServerOutboundVarNames(server.tag, decls),
    decls.dnsServers[server.tag] ?? const [],
    retarget,
  );
  return next == null ? server : server.copyWith(varValues: next);
}





DnsServerRef retargetDnsServerDirectionRefs(
  DnsServerRef server,
  RecordVarDecls decls,
  Map<String, String> retarget,
) =>
    switch (server) {
      DnsServerTemplate() =>
        retargetDnsServerOutboundVars(server, decls, retarget),
      DnsServerInline() => retargetDnsServerDetour(server, retarget),
      DnsServerPreset() => server,
    };



CustomRule retargetPresetOutboundVars(
  CustomRule rule,
  RecordVarDecls decls,
  Map<String, String> retarget,
) {
  if (rule is! CustomRulePreset || rule.varsValues.isEmpty) return rule;
  final next = _retargetValues(
    rule.varsValues,
    presetOutboundVarNames(rule.presetId, decls),
    decls.presets[rule.presetId] ?? const [],
    retarget,
  );
  return next == null ? rule : rule.copyWith(varsValues: next);
}
