


















library;

import 'package:flutter/foundation.dart' show visibleForTesting;


enum BackupRecord {
  subscription,
  server,
  folder,


  folderNode,
  chain,


  rule,
  dnsServer,
  dnsRule,
}


enum BackupFieldFate {

  contract,



  setting,


  runtime,
}






final class BackupField {
  const BackupField(this.record, this.key, this.fate, {this.declared = false});

  final BackupRecord record;
  final String key;
  final BackupFieldFate fate;


  final bool declared;


  bool get travels => fate == BackupFieldFate.contract || declared;
}

const _c = BackupFieldFate.contract;
const _s = BackupFieldFate.setting;
const _r = BackupFieldFate.runtime;


const List<BackupField> kBackupFields = [

  BackupField(BackupRecord.subscription, 'kind', _c),
  BackupField(BackupRecord.subscription, 'id', _c),
  BackupField(BackupRecord.subscription, 'name', _c),
  BackupField(BackupRecord.subscription, 'enabled', _c),
  BackupField(BackupRecord.subscription, 'url', _c),
  BackupField(BackupRecord.subscription, 'tag_policy', _c),
  BackupField(BackupRecord.subscription, 'identity', _c),
  BackupField(BackupRecord.subscription, 'update', _c),
  BackupField(BackupRecord.subscription, 'disabled', _c),


  BackupField(BackupRecord.subscription, 'warnings', _c),
  BackupField(BackupRecord.subscription, 'detour', _c),
  BackupField(BackupRecord.subscription, 'replace', _c),
  BackupField(BackupRecord.subscription, 'detour_policy', _s, declared: true),
  BackupField(BackupRecord.subscription, 'import_rules', _s, declared: true),
  BackupField(BackupRecord.subscription, 'import_rules_enabled', _s,
      declared: true),
  BackupField(BackupRecord.subscription, 'on_update_action', _s,
      declared: true),

  BackupField(BackupRecord.subscription, 'meta', _r),
  BackupField(BackupRecord.subscription, 'last_updated', _r),
  BackupField(BackupRecord.subscription, 'last_update_attempt', _r),
  BackupField(BackupRecord.subscription, 'last_update_status', _r),
  BackupField(BackupRecord.subscription, 'last_node_count', _r),
  BackupField(BackupRecord.subscription, 'consecutive_fails', _r),



  BackupField(BackupRecord.subscription, 'group_defaults', _r),


  BackupField(BackupRecord.server, 'kind', _c),
  BackupField(BackupRecord.server, 'id', _c),
  BackupField(BackupRecord.server, 'tag', _c),
  BackupField(BackupRecord.server, 'enabled', _c),

  BackupField(BackupRecord.server, 'warnings', _c),
  BackupField(BackupRecord.server, 'origin', _c),

  BackupField(BackupRecord.server, 'body', _c),
  BackupField(BackupRecord.server, 'detour', _c),


  BackupField(BackupRecord.server, 'sections', _r),

  BackupField(BackupRecord.server, 'skip_presets', _c),
  BackupField(BackupRecord.server, 'detour_policy', _s, declared: true),
  BackupField(BackupRecord.server, 'tag_policy', _s, declared: true),


  BackupField(BackupRecord.folder, 'kind', _c),
  BackupField(BackupRecord.folder, 'id', _c),
  BackupField(BackupRecord.folder, 'name', _c),
  BackupField(BackupRecord.folder, 'enabled', _c),
  BackupField(BackupRecord.folder, 'tag_policy', _c),
  BackupField(BackupRecord.folder, 'detour', _c),
  BackupField(BackupRecord.folder, 'replace', _c),
  BackupField(BackupRecord.folder, 'detour_policy', _s, declared: true),
  BackupField(BackupRecord.folder, 'ping_url', _s, declared: true),
  BackupField(BackupRecord.folder, 'ping_timeout_ms', _s, declared: true),
  BackupField(BackupRecord.folder, 'created_at', _r),
  BackupField(BackupRecord.folder, 'nodes', _c),


  BackupField(BackupRecord.folderNode, 'kind', _c),
  BackupField(BackupRecord.folderNode, 'tag', _c),
  BackupField(BackupRecord.folderNode, 'enabled', _c),

  BackupField(BackupRecord.folderNode, 'warnings', _c),
  BackupField(BackupRecord.folderNode, 'origin', _c),
  BackupField(BackupRecord.folderNode, 'body', _c),
  BackupField(BackupRecord.folderNode, 'detour', _c),
  BackupField(BackupRecord.folderNode, 'reason', _c),
  BackupField(BackupRecord.folderNode, 'sections', _r),
  BackupField(BackupRecord.folderNode, 'skip_presets', _c),



  BackupField(BackupRecord.folderNode, 'group', _c),


  BackupField(BackupRecord.chain, 'kind', _c),
  BackupField(BackupRecord.chain, 'tag', _c),
  BackupField(BackupRecord.chain, 'enabled', _c),
  BackupField(BackupRecord.chain, 'label', _s, declared: true),
  BackupField(BackupRecord.chain, 'body', _c),
  BackupField(BackupRecord.chain, 'hops', _c),


  BackupField(BackupRecord.rule, 'kind', _c),
  BackupField(BackupRecord.rule, 'id', _c),
  BackupField(BackupRecord.rule, 'name', _c),
  BackupField(BackupRecord.rule, 'enabled', _c),
  BackupField(BackupRecord.rule, 'num', _c),
  BackupField(BackupRecord.rule, 'refs', _c),
  BackupField(BackupRecord.rule, 'update_interval_hours', _s, declared: true),
  BackupField(BackupRecord.rule, 'ref', _c),
  BackupField(BackupRecord.rule, 'vars', _c),


  BackupField(BackupRecord.rule, 'verbatim', _r, declared: true),
  BackupField(BackupRecord.rule, 'body', _c),
  BackupField(BackupRecord.rule, 'dns', _c),
  BackupField(BackupRecord.rule, 'resolve', _c),


  BackupField(BackupRecord.dnsServer, 'kind', _c),
  BackupField(BackupRecord.dnsServer, 'tag', _c),
  BackupField(BackupRecord.dnsServer, 'ref', _c),
  BackupField(BackupRecord.dnsServer, 'enabled', _c),
  BackupField(BackupRecord.dnsServer, 'body', _c),


  BackupField(BackupRecord.dnsServer, 'vars', _s, declared: true),
  BackupField(BackupRecord.dnsServer, 'description', _s, declared: true),


  BackupField(BackupRecord.dnsRule, 'kind', _c),
  BackupField(BackupRecord.dnsRule, 'id', _c),
  BackupField(BackupRecord.dnsRule, 'name', _c),
  BackupField(BackupRecord.dnsRule, 'ref', _c),
  BackupField(BackupRecord.dnsRule, 'enabled', _c),
  BackupField(BackupRecord.dnsRule, 'body', _c),
  BackupField(BackupRecord.dnsRule, 'kind:srs', _s),

  BackupField(BackupRecord.dnsRule, 'kind:template', _r),
];

Map<BackupRecord, Map<String, BackupField>> _index(List<BackupField> fields) => {
      for (final kind in BackupRecord.values)
        kind: {
          for (final f in fields)
            if (f.record == kind) f.key: f,
        },
    };

Map<BackupRecord, Map<String, BackupField>> _byRecord = _index(kBackupFields);




@visibleForTesting
void overrideBackupFieldsForTesting(List<BackupField>? fields) {
  _byRecord = _index(fields ?? kBackupFields);
}



Set<String> declaredBackupKeys(BackupRecord record) => {
      for (final f in _byRecord[record]!.values)
        if (f.declared && f.fate != BackupFieldFate.contract) f.key,
    };



bool backupKindTravels(BackupRecord record, String kind) =>
    _byRecord[record]!['kind:$kind']?.travels ?? true;



typedef BackupSlice = ({Map<String, dynamic>? record, List<String> dropped});





BackupSlice sliceBackupRecord(
  BackupRecord record,
  Map<String, dynamic> stored,
) {
  final fields = _byRecord[record]!;
  final kindRow = fields['kind:${stored['kind']}'];
  if (kindRow != null && !kindRow.travels) {
    return (
      record: null,
      dropped: [
        if (kindRow.fate == BackupFieldFate.setting) '${stored['kind']}',
      ],
    );
  }
  final out = <String, dynamic>{};
  final dropped = <String>[];
  for (final e in stored.entries) {
    final field = fields[e.key];
    if (field == null) {

      dropped.add(e.key);
      continue;
    }
    if (!field.travels) {
      if (field.fate == BackupFieldFate.setting &&
          !_isDefault(record, e.key, e.value, stored)) {
        dropped.add(e.key);
      }
      continue;
    }
    out[e.key] = switch (e.key) {
      'nodes' when e.value is List && record == BackupRecord.folder =>
        _sliceNodes(e.value as List, dropped),
      _ => e.value,
    };
  }
  return (record: out, dropped: dropped);
}



Map<String, dynamic> stripUndeclaredBackupFields(
  BackupRecord record,
  Map<String, dynamic> incoming,
) {
  final fields = _byRecord[record]!;
  final out = <String, dynamic>{};
  for (final e in incoming.entries) {
    final field = fields[e.key];
    if (field != null && !field.travels) continue;
    out[e.key] = switch (e.key) {
      'nodes' when e.value is List && record == BackupRecord.folder => [
          for (final n in e.value as List)
            n is Map
                ? stripUndeclaredBackupFields(
                    BackupRecord.folderNode, n.cast<String, dynamic>())
                : n,
        ],
      _ => e.value,
    };
  }
  return out;
}






bool _isDefault(
  BackupRecord record,
  String key,
  Object? v,
  Map<String, dynamic> stored,
) =>
    v == null ||
    (v is String && v.isEmpty) ||
    (v is Map && v.isEmpty) ||
    (v is List && v.isEmpty) ||
    (record == BackupRecord.chain && key == 'label' && v == stored['tag']);

List<dynamic> _sliceNodes(List<dynamic> nodes, List<String> dropped) => [
      for (var i = 0; i < nodes.length; i++)
        if (nodes[i] case final Map node)
          _sliceNested(BackupRecord.folderNode, node.cast<String, dynamic>(),
              'nodes[${_label(node, 'tag', i)}]', dropped)
        else
          nodes[i],
    ];



Map<String, dynamic> _sliceNested(
  BackupRecord kind,
  Map<String, dynamic> record,
  String path,
  List<String> dropped,
) {
  final slice = sliceBackupRecord(kind, record);
  dropped.addAll(slice.dropped.map((k) => '$path.$k'));
  return slice.record ?? record;
}

String _label(Map<dynamic, dynamic> record, String key, int index) {
  final v = record[key];
  return v is String && v.isNotEmpty ? v : '#${index + 1}';
}
