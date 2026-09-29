import 'dart:convert';

import '../config/consts.dart'
    show kBlockOutboundTag, kDirectOutboundTag;
import '../models/custom_rule.dart';
import '../models/dns_ref.dart';
import '../models/parser_config.dart';
import '../models/record_codec.dart';
import 'builder/rule_order.dart' show nextUserRuleNum;
import 'parser/uri_utils.dart' show newUuidV4;
import 'storage_migration/legacy_form_v0.dart'
    show readLegacyCustomRule, readLegacyDnsRule, readLegacyDnsServer;































const int kRulesExportFormatVersion = 2;


const int kRulesFormatLegacy = 1;



const String kImportOutboundFallback = 'vpn-1';



String buildRulesExport(
  List<CustomRule> rules, {
  String? appVersion,
  List<DnsServerRef> dnsServers = const [],
  List<DnsRuleRef> dnsRules = const [],
}) {
  final out = <String, dynamic>{
    'app': 'lxbox',
    'kind': 'rules',
    'format': kRulesExportFormatVersion,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    if (appVersion != null && appVersion.isNotEmpty)
      'source_app_version': appVersion,
    'rules': [for (final r in rules) ruleToRecord(r)],
    if (dnsServers.isNotEmpty)
      'dns_servers': [for (final s in dnsServers) dnsServerToRecord(s)],
    if (dnsRules.isNotEmpty)
      'dns_rules': [for (final r in dnsRules) dnsRuleToRecord(r)],
  };
  return const JsonEncoder.withIndent('  ').convert(out);
}



String suggestedRulesFilename() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final date = '${now.year}${two(now.month)}${two(now.day)}'
      '-${two(now.hour)}${two(now.minute)}';
  return 'lxbox-rules-$date.json';
}




class RulesImportContents {
  const RulesImportContents({
    this.format = kRulesExportFormatVersion,
    this.createdAt,
    this.sourceAppVersion,
    required this.rawRules,
    this.rawDnsServers = const [],
    this.rawDnsRules = const [],
  });


  final int format;

  final DateTime? createdAt;
  final String? sourceAppVersion;
  final List<dynamic> rawRules;


  final List<dynamic> rawDnsServers;
  final List<dynamic> rawDnsRules;
}




RulesImportContents parseRulesImport(String raw) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    throw const FormatException(
        'Not a valid JSON file. Make sure you picked a LxBox rules file.');
  }

  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Rules file root must be a JSON object.');
  }

  final app = decoded['app']?.toString();
  final kind = decoded['kind']?.toString();
  if (app != 'lxbox' || kind != 'rules') {

    if (app == 'lxbox' && kind == 'backup') {
      throw const FormatException(
          'This is a LxBox backup file — restore it via Settings → Backup.');
    }
    throw const FormatException(
        'Not a LxBox rules file (missing or invalid app/kind markers).');
  }

  final format = decoded['format'];
  if (format is! int || format < 1) {
    throw const FormatException('Rules file has no valid format version.');
  }
  if (format > kRulesExportFormatVersion) {
    throw const FormatException(
        'Rules file is from a newer app version. Update LxBox and retry.');
  }

  final rules = decoded['rules'];
  if (rules is! List || rules.isEmpty) {
    throw const FormatException('Rules file contains no rules.');
  }

  DateTime? createdAt;
  final createdRaw = decoded['created_at']?.toString();
  if (createdRaw != null) {
    createdAt = DateTime.tryParse(createdRaw);
  }

  final dnsServers = decoded['dns_servers'];
  final dnsRules = decoded['dns_rules'];

  return RulesImportContents(
    format: format,
    createdAt: createdAt,
    sourceAppVersion: decoded['source_app_version']?.toString(),
    rawRules: rules,
    rawDnsServers: dnsServers is List ? dnsServers : const [],
    rawDnsRules: dnsRules is List ? dnsRules : const [],
  );
}



Set<String> referencedDnsServerTags(Iterable<CustomRule> rules) {
  final tags = <String>{};
  for (final r in rules) {
    final dnsTag = r.dns?.serverTag;
    if (dnsTag != null && dnsTag.isNotEmpty) tags.add(dnsTag);
    final resolveTag = r.resolve?.serverTag;
    if (resolveTag != null && resolveTag.isNotEmpty) tags.add(resolveTag);
  }
  return tags;
}



enum ImportRuleWarningKind {


  outboundMissing,




  dnsServerMissing,



  resolveServerMissing,
}

class ImportRuleWarning {
  const ImportRuleWarning(this.kind, this.missingTag);

  final ImportRuleWarningKind kind;


  final String missingTag;
}


enum ImportRuleRejectReason {


  unsupportedEntry,




  presetNotTransferable,



  nameExists,


  unknownPreset,
}


class SanitizedImportRule {
  const SanitizedImportRule({
    this.rule,
    required this.displayLabel,
    this.warnings = const [],
    this.rejectReason,
    this.needsSrsDownload = false,
  });



  final CustomRule? rule;



  final String displayLabel;

  final List<ImportRuleWarning> warnings;
  final ImportRuleRejectReason? rejectReason;




  final bool needsSrsDownload;

  bool get importable => rule != null;
}















SanitizedImportRule sanitizeImportedRule(
  dynamic rawEntry, {
  required Set<String> directionTags,
  required Set<String> dnsServerTags,
  required WizardTemplate template,
  Set<String> existingNames = const {},
  int format = kRulesExportFormatVersion,
}) {
  if (rawEntry is! Map<String, dynamic>) {
    return const SanitizedImportRule(
      displayLabel: '',
      rejectReason: ImportRuleRejectReason.unsupportedEntry,
    );
  }

  final label = rawEntry['name']?.toString() ?? '';
  final parsed = _ruleOfEntry(rawEntry, format);
  if (parsed == null) {
    return SanitizedImportRule(
      displayLabel: label,
      rejectReason: ImportRuleRejectReason.unsupportedEntry,
    );
  }





  if (parsed.kind == CustomRuleKind.preset) {
    return SanitizedImportRule(
      displayLabel: label.isNotEmpty ? label : parsed.presetId,
      rejectReason: ImportRuleRejectReason.presetNotTransferable,
    );
  }


  if (existingNames.contains(parsed.name)) {
    return SanitizedImportRule(
      displayLabel: parsed.name,
      rejectReason: ImportRuleRejectReason.nameExists,
    );
  }

  final warnings = <ImportRuleWarning>[];
  var rule = parsed;
  var forceDisable = false;


  final validOutbounds = <String>{
    '',
    kOutboundReject,
    kBlockOutboundTag,
    kDirectOutboundTag,
    ...directionTags,
  };
  final outbound = rule.outbound;
  if (!validOutbounds.contains(outbound)) {
    warnings.add(
        ImportRuleWarning(ImportRuleWarningKind.outboundMissing, outbound));
    rule = rule.withOutbound(kImportOutboundFallback);


    forceDisable = true;
  }



  final dns = rule.dns;
  if (dns != null &&
      dns.serverTag.isNotEmpty &&
      !dnsServerTags.contains(dns.serverTag)) {
    warnings.add(ImportRuleWarning(
        ImportRuleWarningKind.dnsServerMissing, dns.serverTag));
    rule = _withDns(
        rule, dns.copyWith(enabled: false, serverTag: ''));
  }
  final resolve = rule.resolve;
  if (resolve != null &&
      resolve.serverTag.isNotEmpty &&
      !dnsServerTags.contains(resolve.serverTag)) {
    warnings.add(ImportRuleWarning(
        ImportRuleWarningKind.resolveServerMissing, resolve.serverTag));
    rule = _withResolve(rule, resolve.copyWith(serverTag: ''));
  }




  final needsSrs = rule is CustomRuleSrs;
  if (needsSrs || forceDisable) {
    rule = rule.withEnabled(false);
  }

  return SanitizedImportRule(
    rule: rule,
    displayLabel: rule.name,
    warnings: warnings,
    needsSrsDownload: needsSrs,
  );
}









CustomRule? _ruleOfEntry(Map<String, dynamic> entry, int format) {
  final withoutId = {...entry}..remove('id');
  if (format == kRulesFormatLegacy) {
    final kind = entry['kind']?.toString();
    if (!CustomRuleKind.values.any((k) => k.name == kind)) return null;
    try {
      return readLegacyCustomRule(withoutId);
    } catch (_) {
      return null;
    }
  }
  return ruleFromRecord(withoutId, unknownAsVerbatim: true).value;
}









CustomRule insertImportedRule(
  List<CustomRule> target,
  CustomRule rule, {
  required WizardTemplate template,
}) {
  rule.orderNum = nextUserRuleNum(target);
  target.add(rule);
  return rule;
}




enum ImportDnsSkipReason {


  unsupportedEntry,



  alreadyExists,


  notAvailable,



  managedByPresets,
}



class SanitizedImportDnsItem<T extends Object> {
  const SanitizedImportDnsItem({
    this.item,
    required this.label,
    this.skipReason,
  });

  final T? item;
  final String label;
  final ImportDnsSkipReason? skipReason;

  bool get importable => item != null;
}





SanitizedImportDnsItem<DnsServerRef> sanitizeImportedDnsServer(
  dynamic raw, {
  required Set<String> existingTags,
  required Set<String> templateServerTags,
  int format = kRulesExportFormatVersion,
}) {
  if (raw is! Map) {
    return const SanitizedImportDnsItem(
        label: '', skipReason: ImportDnsSkipReason.unsupportedEntry);
  }
  final map = raw.cast<String, dynamic>();
  final ref = format == kRulesFormatLegacy
      ? readLegacyDnsServer(map)
      : dnsServerFromRecord(map).value;
  if (ref == null) {
    return SanitizedImportDnsItem(
      label: (map['tag'] ?? map['ref'])?.toString() ?? '',
      skipReason: ImportDnsSkipReason.unsupportedEntry,
    );
  }
  final label = (ref.description?.isNotEmpty ?? false)
      ? '${ref.description} (${ref.tag})'
      : ref.tag;
  if (ref is DnsServerPreset) {
    return SanitizedImportDnsItem(
        label: label, skipReason: ImportDnsSkipReason.managedByPresets);
  }
  if (existingTags.contains(ref.tag)) {
    return SanitizedImportDnsItem(
        label: label, skipReason: ImportDnsSkipReason.alreadyExists);
  }
  if (ref is DnsServerTemplate && !templateServerTags.contains(ref.tag)) {
    return SanitizedImportDnsItem(
        label: label, skipReason: ImportDnsSkipReason.notAvailable);
  }
  return SanitizedImportDnsItem(item: ref, label: label);
}





SanitizedImportDnsItem<DnsRuleRef> sanitizeImportedDnsRule(
  dynamic raw, {
  required List<DnsRuleRef> existingRules,
  required WizardTemplate template,
  int format = kRulesExportFormatVersion,
}) {
  if (raw is! Map) {
    return const SanitizedImportDnsItem(
        label: '', skipReason: ImportDnsSkipReason.unsupportedEntry);
  }
  final map = raw.cast<String, dynamic>();
  final ref = format == kRulesFormatLegacy
      ? readLegacyDnsRule(map)
      : dnsRuleFromRecord(map).value;
  if (ref == null) {
    return SanitizedImportDnsItem(
      label: (map['name'] ?? map['presetId'] ?? map['ref'])?.toString() ?? '',
      skipReason: ImportDnsSkipReason.unsupportedEntry,
    );
  }

  switch (ref) {
    case DnsRulePreset():
      final exists = existingRules
          .any((r) => r is DnsRulePreset && r.presetId == ref.presetId);
      if (exists) {
        return SanitizedImportDnsItem(
            label: ref.presetId,
            skipReason: ImportDnsSkipReason.alreadyExists);
      }
      final known =
          template.selectableRules.any((sr) => sr.presetId == ref.presetId);
      if (!known) {
        return SanitizedImportDnsItem(
            label: ref.presetId,
            skipReason: ImportDnsSkipReason.notAvailable);
      }
      return SanitizedImportDnsItem(item: ref, label: ref.presetId);

    case DnsRuleTemplate():
      final exists = existingRules
          .any((r) => r is DnsRuleTemplate && r.name == ref.name);
      if (exists) {
        return SanitizedImportDnsItem(
            label: ref.name, skipReason: ImportDnsSkipReason.alreadyExists);
      }
      final known = (template.dnsOptions['rules'] as List<dynamic>? ??
              const [])
          .any((r) => r is Map && r['name'] == ref.name);
      if (!known) {
        return SanitizedImportDnsItem(
            label: ref.name, skipReason: ImportDnsSkipReason.notAvailable);
      }
      return SanitizedImportDnsItem(item: ref, label: ref.name);

    case DnsRuleInline():

      if (existingRules.contains(ref)) {
        return SanitizedImportDnsItem(
            label: ref.name, skipReason: ImportDnsSkipReason.alreadyExists);
      }
      return SanitizedImportDnsItem(item: ref, label: ref.name);

    case DnsRuleSrs():
      final dup =
          existingRules.any((r) => r is DnsRuleSrs && r.name == ref.name);
      if (dup) {
        return SanitizedImportDnsItem(
            label: ref.name, skipReason: ImportDnsSkipReason.alreadyExists);
      }

      return SanitizedImportDnsItem(
          item: ref.copyWith(id: newUuidV4()), label: ref.name);
  }
}





CustomRule _withDns(CustomRule rule, RuleDns dns) => switch (rule) {
      CustomRuleInline() => rule.copyWith(dns: dns),
      CustomRuleSrs() => rule.copyWith(dns: dns),
      _ => rule,
    };

CustomRule _withResolve(CustomRule rule, RuleResolve resolve) =>
    switch (rule) {
      CustomRuleInline() => rule.copyWith(resolve: resolve),
      CustomRuleSrs() => rule.copyWith(resolve: resolve),
      _ => rule,
    };
