import '../../../controllers/subscription_controller.dart';
import '../../../models/codec/node_link_record.dart';
import '../../../models/codec/source_record.dart';
import '../../../models/import_rule.dart';
import '../../../models/node_warning.dart';
import '../../../models/server_list.dart';
import '../../../models/source_chain.dart';
import '../../../models/source_entry.dart';
import '../../contract/registry_warning.dart';
import '../../node_link_address.dart';
import '../../url_mask.dart';

export '../../url_mask.dart' show maskSubscriptionUrl;













Map<String, Object?> serializeSourceEntry(
  SourceEntry entry, {
  required bool reveal,
  SubscriptionEntry? liveEntry,
}) =>
    switch (entry) {
      ContainerEntry() => {
          'source_key': entry.sourceKey,
          ...serializeSubEntry(liveEntry!, reveal: reveal),
        },
      ChainEntry(:final chain) => _serializeChainAsSource(entry, chain),
      OpaqueEntry() => {
          'source_key': entry.sourceKey,
          'kind': 'Unreadable',


          'record_kind': entry.kind,
          'enabled': false,
        },
    };




Map<String, Object?> _serializeChainAsSource(
        ChainEntry entry, SourceChain chain) =>
    {
      'source_key': entry.sourceKey,
      'id': chain.tag,
      'kind': 'SourceChain',
      'title': chain.displayLabel,
      'enabled': chain.enabled,

      'nodes_count': chain.hops.length,
      'hops_count': chain.hops.length,
    };


Map<String, Object?> serializeSubEntry(
  SubscriptionEntry e, {
  required bool reveal,
}) {
  final list = e.list;
  final rawUrl = e.url;
  return {
    'id': e.id,
    'kind': switch (list) {
      SubscriptionServers() => 'SubscriptionServers',
      UserServer() => 'UserServer',
      FolderServers() => 'FolderServers',
    },
    'url': reveal ? rawUrl : maskSubscriptionUrl(rawUrl),
    'title': e.name,
    'enabled': e.enabled,
    'tag_prefix': e.tagPrefix,
    'nodes_count': e.nodeCount,
    'last_update_at': e.lastUpdated?.toUtc().toIso8601String(),
    'last_update_status': e.lastUpdateStatus.name,
    'consecutive_fails': e.consecutiveFails,
    'update_interval_hours': e.updateIntervalHours,




    'override_detour': nodeLinkToRecordOrNull(e.overrideDetour),
    'detour_policy': {
      'register_detour_servers': e.registerDetourServers,
      'register_detour_in_auto': e.registerDetourInAuto,
      'use_detour_servers': e.useDetourServers,
      'override_detour': nodeLinkToRecordOrNull(e.overrideDetour),
    },




    if (list is UserServer) 'skip_presets': list.skipPresets,





    if (list is UserServer && reveal) 'raw': list.rawBody,
    if (list is SubscriptionServers) ...{
      'on_update_action': list.onUpdateAction.name,



      'identity': list.identity?.toJson(),
      'import_rules_enabled': list.importRulesEnabled,


      'import_rules_count': list.importRules.length,
    },
  };
}















Map<String, Object?> serializeParseDrop(RegistryWarning w) {
  final code = w.code;
  final value = maskRegistrySecretValue(w.path, w.value);
  return {
    'code': code,
    'path': w.path,
    'value': value,
    'title_en': registryTitle(code, RegistryLang.en,
        path: w.path, value: value, params: w.params),
  };
}

Map<String, Object?> serializeNodeWarning(NodeWarning w) {
  final reg = w is RegistryWarning ? w : null;
  final code = reg?.code;
  return {
    'code': code,
    'severity': w.severity.name,
    'path': reg?.path,
    'value': reg?.value,
    if (reg != null && reg.params.isNotEmpty) 'params': {...reg.params},


    'applied': w.applied,







    'title_en': code == null
        ? null
        : registryTitle(code, RegistryLang.en,
            path: reg!.path, value: reg.value, params: reg.params),


    'text_en': w.renderEn(),
  };
}


Map<String, String> entrySourceKinds(SubscriptionEntry e) {
  final raw = entryRawText(e);
  if (raw.isEmpty) {
    return const {'origin_kind': '', 'source_kind': ''};
  }
  return {
    'origin_kind': originKindOf(raw),
    'source_kind': sourceKindOf(raw),
  };
}


String entryRawText(SubscriptionEntry e) {
  final list = e.list;
  return switch (list) {
    UserServer() => list.rawBody,
    SubscriptionServers() => list.url.isNotEmpty
        ? list.url
        : (list.nodes.isNotEmpty ? list.nodes.first.rawSource : ''),
    FolderServers() =>
        list.memberRaws.isNotEmpty ? list.memberRaws.first : '',
  };
}





































Map<String, Object?> serializeEntryWarnings(SubscriptionEntry e) {
  final rawTags = containerRawTags(e.list);
  final byTag = <String, Object?>{};
  final nodes = e.list.nodes;
  for (var i = 0; i < nodes.length; i++) {
    final n = nodes[i];









    final key = rawTags[n] ?? '#$i';
    byTag[byTag.containsKey(key) ? '$key#$i' : key] = [
      for (final w in n.warnings) serializeNodeWarning(w),
    ];
  }
  return byTag;
}









Map<String, Object?> serializeImportRule(ImportRule r, int index) => {
      'index': index,
      'usable': r.isUsable,
      ...r.toJson(),
    };




Map<String, Object?> serializeFolderEntry(
  SubscriptionEntry e, {
  required bool reveal,
}) {
  final folder = e.list as FolderServers;
  return {
    ...serializeSubEntry(e, reveal: reveal),
    'created_at': folder.createdAt.toUtc().toIso8601String(),
    'members_count': folder.members.length,
    'disabled_count': folder.disabledCount,
    'members': [
      for (var i = 0; i < folder.members.length; i++)
        serializeFolderMember(folder.members[i], i, reveal: reveal),
    ],
  };
}



Map<String, Object?> serializeFolderMember(
  FolderMember m,
  int index, {
  required bool reveal,
}) =>
    {
      'index': index,
      'enabled': m.enabled,

      'detour': nodeLinkToRecordOrNull(m.detour),
      'tag': m.node?.tag,
      'protocol': m.node?.protocol,
      'broken': m.node == null,
      if (reveal) 'raw': m.raw,
      'skip_presets': m.skipPresets,
    };
