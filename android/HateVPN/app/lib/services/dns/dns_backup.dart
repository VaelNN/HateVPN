

































library;

import 'dart:convert';

import '../../models/dns_ref.dart';
import '../../models/record_codec.dart';
import '../lx_backup.dart';
import '../lx_backup_slice.dart';
import '../node_hash.dart' show deepSortKeys;
import '../record_vars.dart';









Map<String, dynamic>? dnsToBackup({
  required List<DnsServerRef> servers,
  required List<DnsRuleRef> rules,
  required String dnsFinal,
  required String strategy,
  String defaultDomainResolver = '',
  List<LxBackupWarning>? warnings,
  RecordVarDecls recordVars = RecordVarDecls.none,
}) {
  final sink = warnings ?? <LxBackupWarning>[];
  final outServers = [
    for (final s in normalizeDnsServersVars(servers, recordVars))
      ?exportBackupRecord(BackupRecord.dnsServer, dnsServerToRecord(s),
          'dns: ${_serverLabel(s)}', sink),
  ];
  final outRules = [
    for (final r in rules)
      ?exportBackupRecord(BackupRecord.dnsRule, dnsRuleToRecord(r),
          'dns: ${_ruleLabel(r)}', sink),
  ];
  final out = <String, dynamic>{
    if (strategy.isNotEmpty) 'strategy': strategy,
    if (dnsFinal.isNotEmpty) 'final': dnsFinal,
    if (defaultDomainResolver.isNotEmpty)
      'default_domain_resolver': defaultDomainResolver,
    if (outServers.isNotEmpty) 'servers': outServers,
    if (outRules.isNotEmpty) 'rules': outRules,
  };
  return out.isEmpty ? null : out;
}

String _serverLabel(DnsServerRef s) =>
    s is DnsServerPreset ? dnsServerPresetRef(s) : s.tag;

String _ruleLabel(DnsRuleRef r) => switch (r) {
      DnsRuleInline(:final name) ||
      DnsRuleSrs(:final name) ||
      DnsRuleTemplate(:final name) =>
        name.isEmpty ? 'dns rule' : name,
      DnsRulePreset(:final presetId) => presetId,
    };


typedef DnsBackupApply = ({
  List<DnsServerRef> servers,
  List<DnsRuleRef> rules,
  String dnsFinal,
  String strategy,


  String defaultDomainResolver,
  int applied,
});














































DnsBackupApply applyDnsBackup({
  required LxDns incoming,
  required List<DnsServerRef> servers,
  required List<DnsRuleRef> rules,
  required String dnsFinal,
  required String strategy,
  String defaultDomainResolver = '',
  RecordVarDecls recordVars = RecordVarDecls.none,
  Set<String>? knownTargets,
  List<LxBackupWarning>? warnings,
}) {
  var applied = 0;
  final sink = warnings ?? <LxBackupWarning>[];
  final outServers = servers.toList();
  final localIndex = <String, int>{
    for (var i = outServers.length - 1; i >= 0; i--)
      _serverKey(outServers[i]): i,
  };
  final haveServers = <String>{for (final s in outServers) _serverKey(s)};


  final presetTags = <String>{
    for (final s in outServers)
      if (s is DnsServerPreset) s.tag,
  };

  final touched = <int>{};
  for (final s in incoming.servers) {
    final key = _serverKey(s);
    final incomingVars = s is DnsServerTemplate
        ? _declaredFileVars(s, recordVars, sink)
        : const <String, String>{};
    if (!haveServers.add(key)) {

      final at = localIndex[key];
      final local = at == null ? null : outServers[at];
      if (local is DnsServerTemplate && incomingVars.isNotEmpty) {
        final merged = {...local.varValues, ...incomingVars};
        outServers[at!] = normalizeDnsServerVars(
            local.copyWith(varValues: merged), recordVars);
        touched.add(at);
        applied++;
      }
      continue;
    }
    if (s is DnsServerPreset && !presetTags.add(s.tag)) continue;
    outServers.add(s is DnsServerTemplate
        ? normalizeDnsServerVars(
            s.copyWith(varValues: incomingVars), recordVars)
        : s);
    touched.add(outServers.length - 1);
    applied++;
  }
  if (knownTargets != null) {
    for (final i in touched.toList()..sort()) {
      final gated = _gateServerTarget(outServers[i], recordVars, knownTargets, sink);
      if (gated != null) outServers[i] = gated;
    }
  }

  final outRules = rules.toList();
  final localRules = <String>{for (final r in outRules) _ruleKey(r)};
  final addedRefs = <String>{};
  final usedNames = <String>{
    for (final r in outRules)
      if (_nameOf(r) case final name? when name.isNotEmpty) name,
  };
  for (final r in incoming.rules) {
    final key = _ruleKey(r);
    if (localRules.contains(key)) continue;
    if (r is! DnsRuleInline && !addedRefs.add(key)) continue;
    final rule = r is DnsRuleInline && r.name.isEmpty
        ? r.copyWith(name: _uniqueName(_ruleNameFromBody(r.rule), usedNames))
        : r;
    if (_nameOf(rule) case final name? when name.isNotEmpty) {
      usedNames.add(name);
    }
    outRules.add(rule);
    applied++;
  }





  return (
    servers: outServers,
    rules: outRules,
    dnsFinal: incoming.finalServer.isNotEmpty ? incoming.finalServer : dnsFinal,
    strategy: incoming.strategy.isNotEmpty ? incoming.strategy : strategy,
    defaultDomainResolver: incoming.defaultDomainResolver.isNotEmpty
        ? incoming.defaultDomainResolver
        : defaultDomainResolver,
    applied: applied,
  );
}





Map<String, String> _declaredFileVars(
  DnsServerTemplate s,
  RecordVarDecls recordVars,
  List<LxBackupWarning> warnings,
) {
  final declared = recordVars.dnsServers[s.tag];
  final byName = {
    for (final d in declared ?? const <RecordVarDecl>[]) d.name: d,
  };
  final out = <String, String>{};
  for (final e in s.varValues.entries) {
    if (declared != null && !byName.containsKey(e.key)) {
      warnings.add(LxBackupWarning(
          kWarnVarSkipped, 'dns:${s.tag}.vars.${e.key}',
          reason: kVarSkippedUndeclared));
      continue;
    }
    final v = e.value.trim();
    if (v.isNotEmpty) out[e.key] = v;
  }
  return out;
}





DnsServerRef? _gateServerTarget(
  DnsServerRef server,
  RecordVarDecls recordVars,
  Set<String> known,
  List<LxBackupWarning> warnings,
) {
  final targets = <String>[
    if (server case DnsServerTemplate(:final tag, :final varValues))
      for (final d in recordVars.dnsServers[tag] ?? const <RecordVarDecl>[])
        if (d.type == 'outbound' && (varValues[d.name] ?? '').isNotEmpty)
          varValues[d.name]!,
    if (server case DnsServerInline(:final body))
      if (body['detour'] case final String detour when detour.trim().isNotEmpty)
        detour,
  ];
  final unknown = [
    for (final t in targets)
      if (!lxIsKnownImportTarget(t, known)) t,
  ];
  if (unknown.isEmpty) return null;
  for (final t in unknown) {
    warnings.add(LxBackupWarning(kWarnUnknownOutbound, 'dns:${server.tag} → $t'));
  }
  return server.enabled ? server.withEnabled(false) : null;
}

String _serverKey(DnsServerRef s) => switch (s) {


      DnsServerPreset() => 'preset\u0000${dnsServerPresetRef(s)}',
      _ => '${s.kind}\u0000${s.tag}',
    };



String _ruleKey(DnsRuleRef r) => switch (r) {
      DnsRuleInline(:final rule) => 'user\u0000${jsonEncode(deepSortKeys(rule))}',
      DnsRulePreset(:final presetId) => 'preset\u0000$presetId',
      DnsRuleTemplate(:final name) => 'template\u0000$name',
      DnsRuleSrs(:final id) => 'srs\u0000$id',
    };

String? _nameOf(DnsRuleRef r) => switch (r) {
      DnsRuleInline(:final name) ||
      DnsRuleSrs(:final name) ||
      DnsRuleTemplate(:final name) =>
        name,
      DnsRulePreset() => null,
    };




String _ruleNameFromBody(Map<String, dynamic> body) {
  for (final e in body.entries) {
    if (e.key == 'server' || e.key == 'action') continue;
    final v = e.value;
    if (v is List && v.isNotEmpty && v.first is String) return v.first as String;
    if (v is String && v.isNotEmpty) return v;
  }
  final server = body['server'];
  return server is String && server.isNotEmpty ? server : 'rule';
}

String _uniqueName(String base, Set<String> used) {
  if (!used.contains(base)) return base;
  for (var n = 2;; n++) {
    final candidate = '$base-$n';
    if (!used.contains(candidate)) return candidate;
  }
}
