











library;

import 'dart:convert' show jsonDecode, jsonEncode;

import '../../models/node_warning.dart';
import '../../models/singbox_entry.dart';
import '../contract/body_edit.dart';
import '../contract/body_sanitizer.dart';
import '../contract/node_core_gate.dart';
import '../contract/registry.dart';
import 'core_chain_capability.dart' show kCoreBuildTags;


final class RegistryGateReport {
  const RegistryGateReport(
    this.warnings,
    this.dropped, {
    this.warningsByEmittedTag = const {},
  });


  final List<String> warnings;


  final List<SingboxEntry> dropped;


  final Map<String, List<NodeWarning>> warningsByEmittedTag;
}






















RegistryGateReport applyRegistryGate(
  List<SingboxEntry> entries, {
  required String coreVersion,
  Set<String>? coreBuildTags = kCoreBuildTags,
}) {
  final warnings = <String>[];
  final dropped = <SingboxEntry>[];
  final warningsByEmittedTag = <String, List<NodeWarning>>{};















  for (final entry in entries) {
    final type = entry.map['type'];
    if (type is String && type.isNotEmpty) continue;
    dropped.add(entry);
    const w = RegistryWarning(
      code: 'field_missing',
      path: 'type',
      params: {'field': 'type'},
    );
    final line = '${entry.tag}: ${w.message()} [type]';
    if (!warnings.contains(line)) warnings.add(line);
  }

  if (!ContractRegistry.I.isLoaded) {
    return RegistryGateReport(
      warnings,
      dropped,
      warningsByEmittedTag: warningsByEmittedTag,
    );
  }

  final core = CoreInfo(version: coreVersion, tags: coreBuildTags);
  for (final entry in entries) {
    final type = entry.map['type'];
    if (type is! String || type.isEmpty) continue;
    final tag = entry.tag;




    final refusal = nodeCoreRefusal(type, entry.map, core);
    if (refusal != null) {
      final w = RegistryWarning(
        code: refusal.code,
        path: refusal.path,
        params: {'reason': refusal.reason},
        ownerTag: tag,
      );
      final where = refusal.path == null ? '' : ' [${refusal.path}]';
      final line = '$tag: ${w.message()}$where';
      if (!warnings.contains(line)) warnings.add(line);
      warningsByEmittedTag.putIfAbsent(tag, () => []).add(w);
      dropped.add(entry);
      continue;
    }



    final original = entry.authored
        ? (jsonDecode(jsonEncode(entry.map)) as Map).cast<String, dynamic>()
        : entry.map;
    final raw = Map<String, dynamic>.from(entry.authored
        ? (jsonDecode(jsonEncode(entry.map)) as Map).cast<String, dynamic>()
        : entry.map);
    final res = settleSanitized(
      type,
      original,
      RegistrySanitizer.sanitize(
        raw,
        scheme: type,
        coreVersion: coreVersion,
        source: entry.authored ? BodySource.singbox : BodySource.other,
      ),
      authored: entry.authored,
    );
    if (res.warnings.isEmpty && res.body == null) continue;

    for (final w in res.warnings) {


      final line = '$tag: ${reportLineOf(w)}';
      if (!warnings.contains(line)) warnings.add(line);
      warningsByEmittedTag.putIfAbsent(tag, () => []).add(w);
    }

    if (res.body == null) {
      dropped.add(entry);
      continue;
    }



    applyRegistryEdits(
      entry.map,
      scheme: type,
      authored: false,
      edited: res.body!,
      warnings: const [],
    );
  }

  return RegistryGateReport(
    warnings,
    dropped,
    warningsByEmittedTag: warningsByEmittedTag,
  );
}



String reportLineOf(RegistryWarning w) {
  final where = w.path == null
      ? ''
      : ' [${w.path}${w.value == null ? '' : '=${w.value}'}]';
  final mark = w.applied ? '' : ' (not applied)';
  return '${w.message()}$where$mark';
}
