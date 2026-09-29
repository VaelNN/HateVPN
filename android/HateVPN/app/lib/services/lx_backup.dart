

library;

import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';

import '../config/consts.dart';
import '../models/auto_select.dart';
import '../models/codec/auto_group_record.dart';
import '../models/codec/chain_record.dart';
import '../models/codec/node_link_record.dart';
import '../models/codec/source_record.dart';
import '../models/codec/source_replace_record.dart';
import '../models/core_reject_verdict.dart';
import '../models/custom_rule.dart';
import '../models/direction.dart';
import '../models/dns_ref.dart';
import '../models/import_rule.dart';
import '../models/node_link.dart';
import '../models/node_spec.dart' show AutoSelectSpec, NodeSpec;
import '../models/parser_config.dart' show kUserRuleNumStart;
import '../models/record_codec.dart';
import '../models/server_list.dart';
import '../models/source_chain.dart';
import '../models/source_replace.dart';
import 'core_reject/core_reject_backup.dart';
import 'lx_backup_slice.dart';
import 'node_link_address.dart';
import 'node_hash.dart' show deepSortKeys;
import 'parser/body_decoder.dart';
import 'parser/parse_all.dart';
import 'parser/uri_utils.dart' show newUuidV4;
import 'record_vars.dart';
import 'storage_migration/legacy_autogroup.dart';
import 'tag_resolver.dart';



































const int kLxBackupFormat0x = 1;


const int kLxBackupFormat10 = 2;




const int kLxBackupVersion = kLxBackupFormat10;



const String kLxAppLxBox = 'lxbox';
const String kLxAppLauncher = 'launcher';



const String kWarnUnknownOutbound = 'backup_unknown_outbound';
const String kWarnFinalDropped = 'backup_final_dropped';
const String kWarnUnknownPreset = 'backup_unknown_preset';
const String kWarnVarSkipped = 'backup_var_skipped';









const String kVarSkippedNotPortable = 'not_portable';
const String kVarSkippedUndeclared = 'undeclared';
const String kVarSkippedSuperseded = 'superseded';
const String kVarSkippedNoRecord = 'no_record';




const String kWarnUnknownField = 'backup_unknown_field';







const String kWarnExtensionsDropped = 'backup_extensions_dropped';









const String kWarnFieldTypeMismatch = 'backup_field_type_mismatch';







const String kWarnSourceFlagDropped = 'backup_source_flag_dropped';








const String kWarnLabelDropped = 'backup_label_dropped';







const String kWarnSourceIdentityDropped = 'backup_source_identity_dropped';








const String kWarnLocalOnlyDropped = 'backup_local_only_dropped';







const String kWarnDirectionExists = 'backup_direction_exists';











const String kWarnChainExists = 'backup_chain_exists';






const String kWarnDnsEntrySkipped = 'backup_dns_entry_skipped';




const String kWarnWarpSkipped = 'backup_warp_skipped';




const String kWarnSectionRecordDropped = 'backup_section_record_dropped';



const String kSectionDropReasonNotAllowed = 'not_allowed';






const String kWarnSourceKindUnsupported = 'backup_source_kind_unsupported';






const String kWarnGroupDegraded = 'backup_group_degraded';






const Set<String> kLxPortableVars = {
  'auto_detect_interface',
  'dns_cache_capacity',
  'dns_default_domain_resolver',
  'dns_final',
  'dns_optimistic',
  'dns_store_cache',
  'dns_strategy',
  'ipv6_enabled',
  'log_level',
  'resolve_strategy',
  'tls_fragment',
  'tls_fragment_fallback_delay',
  'tls_mixed_case_sni',
  'tls_record_fragment',


  'tun_address',
  'tun_address6',
  'tun_mtu',
  'tun_stack',
  'urltest_interval',
  'urltest_tolerance',
  'urltest_url',
};





const Set<String> _reservedOutbounds = {
  'direct',
  'block',
  'reject',
  'drop',
  'dns-out',
};




const Set<String> kLxImportDefaultSystemTags = {
  kDirectOutboundTag,
  kBlockOutboundTag,
};


class LxBackupWarning {
  const LxBackupWarning(this.code, this.detail, {this.kind = '', this.reason = ''});

  final String code;
  final String detail;



  final String kind;



  final String reason;

  @override
  String toString() => '$code: $detail';
}










class LxSubscription {
  const LxSubscription({
    required this.url,
    this.label = '',
    this.enabled = true,
    this.tagPrefix = '',
    this.updateIntervalHours,
    this.disabled = const {},
    this.nodeWarnings = const {},
    this.identity,
    this.id = '',
    this.fullSettings = false,
    this.position = 0,
    this.detour,
    this.detourPolicy,
    this.importRules,
    this.importRulesEnabled,
    this.onUpdateAction,
    this.replace,
  });




  final SourceReplace? replace;




  final NodeLink? detour;






  final DetourPolicy? detourPolicy;
  final List<ImportRule>? importRules;
  final bool? importRulesEnabled;
  final SubscriptionOnUpdateAction? onUpdateAction;



  final int position;



  final String id;




  final bool fullSettings;

  final String url;
  final String label;
  final bool enabled;
  final String tagPrefix;
  final int? updateIntervalHours;





  final Map<String, int> disabled;




  final Map<String, List<StoredWarning>> nodeWarnings;



  final SubscriptionIdentityOverride? identity;
}







class LxServer {
  const LxServer({
    this.uri = '',
    this.configJson,
    this.name = '',
    this.enabled = true,
    this.warnings = const [],
    this.folder = '',
    this.folderRef = '',
    this.id = '',
    this.skipPresets = false,
    this.detour,
    this.position = 0,
    this.autoGroup,
    this.detourPolicy,
    this.tagPrefix,
  });




  final AutoSelectSpec? autoGroup;




  final DetourPolicy? detourPolicy;
  final String? tagPrefix;



  final int position;




  final NodeLink? detour;


  final String uri;
  final Map<String, dynamic>? configJson;



  final String folderRef;


  final String id;



  final bool skipPresets;




  final String name;

  final bool enabled;



  final List<StoredWarning> warnings;





  final String folder;
}








class LxFolder {
  const LxFolder({
    required this.key,
    this.id = '',
    required this.name,
    this.enabled = true,
    this.tagPrefix = '',
    this.position = 0,
    this.detour,
    this.detourPolicy,
    this.pingUrl,
    this.pingTimeoutMs,
    this.replace,
  });



  final SourceReplace? replace;


  final NodeLink? detour;




  final DetourPolicy? detourPolicy;
  final String? pingUrl;
  final int? pingTimeoutMs;


  final int position;



  final String key;


  final String id;
  final String name;
  final bool enabled;
  final String tagPrefix;
}



class LxDns {
  const LxDns({
    this.servers = const [],
    this.rules = const [],
    this.finalServer = '',
    this.strategy = '',
    this.defaultDomainResolver = '',
  });




  final String defaultDomainResolver;

  final List<DnsServerRef> servers;
  final List<DnsRuleRef> rules;


  final String finalServer;


  final String strategy;

  bool get isEmpty =>
      servers.isEmpty &&
      rules.isEmpty &&
      finalServer.isEmpty &&
      strategy.isEmpty &&
      defaultDomainResolver.isEmpty;
}




















class LxDirectionPing {
  LxDirectionPing({String? url, int? timeoutMs})
    : url = (url != null && url.trim().isNotEmpty) ? url.trim() : null,
      timeoutMs = (timeoutMs != null && timeoutMs > 0) ? timeoutMs : null;

  final String? url;
  final int? timeoutMs;

  bool get isEmpty => url == null && timeoutMs == null;



  Map<String, dynamic> toStorage() => <String, dynamic>{
    if (url != null) 'url': url,
    if (timeoutMs != null) 'timeout_ms': timeoutMs,
  };
}













Map<String, LxDirectionPing> lxDirectionPingFromStorage(
  Map<String, dynamic> pingOptions,
) {
  final groups = pingOptions['groups'];
  if (groups is! Map) return const {};
  final out = <String, LxDirectionPing>{};
  for (final entry in groups.entries) {
    final tag = entry.key;
    final value = entry.value;
    if (tag is! String || tag.isEmpty || value is! Map) continue;
    final rawUrl = value['url'];
    final rawTimeout = value['timeout_ms'];


    final ping = LxDirectionPing(
      url: rawUrl is String ? rawUrl : null,
      timeoutMs: rawTimeout is num ? rawTimeout.toInt() : null,
    );
    if (ping.isEmpty) continue;
    out[tag] = ping;
  }
  return out;
}


class LxBackupFile {
  const LxBackupFile({
    required this.version,
    required this.exportedByApp,
    required this.exportedByVersion,
    required this.exportedAt,
    required this.directions,
    required this.rules,
    this.directionPing = const {},
    this.chains = const [],
    required this.subscriptions,
    required this.vars,
    required this.routeFinal,
    required this.warnings,
    this.servers = const [],
    this.folders = const [],
    this.chainHops = const {},
    this.chainPositions = const {},
    this.dns,
    this.warp = const [],
  });

  final int version;
  final String exportedByApp;
  final String exportedByVersion;
  final String exportedAt;







  final List<Direction> directions;










  final Map<String, LxDirectionPing> directionPing;


  final List<CustomRule> rules;









  final List<SourceChain> chains;



  final List<LxSubscription> subscriptions;





  final List<LxServer> servers;



  final List<LxFolder> folders;





  final Map<String, List<NodeLink>> chainHops;




  final Map<String, int> chainPositions;


  final LxDns? dns;




  final List<Map<String, dynamic>> warp;

  final Map<String, String> vars;



  final String? routeFinal;

  final List<LxBackupWarning> warnings;



  LxBackupFile copyWith({
    List<CustomRule>? rules,
    List<LxBackupWarning>? warnings,
  }) =>
      LxBackupFile(
        version: version,
        exportedByApp: exportedByApp,
        exportedByVersion: exportedByVersion,
        exportedAt: exportedAt,
        directions: directions,
        directionPing: directionPing,
        rules: rules ?? this.rules,
        chains: chains,
        chainHops: chainHops,
        chainPositions: chainPositions,
        subscriptions: subscriptions,
        servers: servers,
        folders: folders,
        dns: dns,
        warp: warp,
        vars: vars,
        routeFinal: routeFinal,
        warnings: warnings ?? this.warnings,
      );
}






class LxBackupExport {
  const LxBackupExport(this.json, this.warnings);

  final String json;
  final List<LxBackupWarning> warnings;
}





























Future<LxBackupExport> buildLxBackup({
  required List<ServerList> lists,
  required List<CustomRule> rules,
  required Map<String, String> vars,
  List<Direction> directions = const [],
  Map<String, LxDirectionPing> directionPing = const {},
  List<SourceChain> chains = const [],


  List<String>? sourceKeys,
  String? routeFinal,
  Map<String, dynamic>? dns,
  List<Map<String, dynamic>> warp = const [],
  RecordVarDecls recordVars = RecordVarDecls.none,
}) async {
  var appVersion = '';
  try {
    final info = await PackageInfo.fromPlatform();
    appVersion = '${info.version}+${info.buildNumber}';
  } catch (_) {

  }

  final warnings = <LxBackupWarning>[];
  final sources = _exportSources(
    lists: lists,
    chains: chains,
    sourceKeys: sourceKeys,
    warnings: warnings,
  );

  final portableVars = <String, String>{
    for (final e in vars.entries)
      if (kLxPortableVars.contains(e.key)) e.key: e.value,
  };

  final ruleRecords = <Map<String, dynamic>>[];
  for (final r in normalizePresetRulesVars(rules, recordVars)) {
    final stored = ruleToRecord(r);


    if (r is CustomRuleJson && stored['body'] == null) {
      _noteLocalOnly(warnings, r.name, const ['json']);
      continue;
    }
    final record =
        exportBackupRecord(BackupRecord.rule, stored, r.name, warnings);
    if (record != null) ruleRecords.add(record);
  }



  final out = <String, dynamic>{
    'lx_backup': kLxBackupVersion,
    'exported_by': {
      'app': kLxAppLxBox,
      'version': appVersion,
      'platform': 'android',
    },
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    if (sources.isNotEmpty) 'sources': sources,


    if (directions.isNotEmpty)
      'directions': [
        for (final d in directions) _directionToJson(d, directionPing[d.tag]),
      ],
    if (ruleRecords.isNotEmpty) 'rules': ruleRecords,
    if (dns != null && dns.isNotEmpty) 'dns': dns,
    if (portableVars.isNotEmpty) 'vars': portableVars,
    if (routeFinal != null && routeFinal.isNotEmpty)
      'route': {'final': routeFinal},


    if (warp.isNotEmpty) 'warp': warp,
  };

  return LxBackupExport(
    const JsonEncoder.withIndent('  ').convert(out),
    warnings,
  );
}




Map<String, dynamic>? exportBackupRecord(
  BackupRecord kind,
  Map<String, dynamic> stored,
  String entity,
  List<LxBackupWarning> warnings,
) {
  final slice = sliceBackupRecord(kind, stored);
  _noteLocalOnly(warnings, entity, slice.dropped);
  return slice.record;
}



List<Map<String, dynamic>> _exportSources({
  required List<ServerList> lists,
  required List<SourceChain> chains,
  required List<String>? sourceKeys,
  required List<LxBackupWarning> warnings,
}) {
  Map<String, dynamic>? ofList(ServerList list) =>
      _exportSource(list, warnings);
  Map<String, dynamic>? ofChain(SourceChain c) => exportBackupRecord(
        BackupRecord.chain,
        chainToRecord(c),
        c.tag,
        warnings,
      );
  if (sourceKeys == null) {
    return [
      for (final list in lists) ?ofList(list),
      for (final c in chains) ?ofChain(c),
    ];
  }
  final listByKey = {for (final l in lists) 'id:${l.id}': l};
  final chainByKey = {for (final c in chains) 'chain:${c.tag}': c};
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  void takeList(String k, ServerList l) {
    final rec = ofList(l);
    if (rec != null) out.add(rec);
    seen.add(k);
  }

  void takeChain(String k, SourceChain c) {
    final rec = ofChain(c);
    if (rec != null) out.add(rec);
    seen.add(k);
  }

  for (final k in sourceKeys) {
    final l = listByKey[k];
    if (l != null) {
      takeList(k, l);
      continue;
    }
    final c = chainByKey[k];
    if (c != null) takeChain(k, c);
  }
  for (final e in listByKey.entries) {
    if (!seen.contains(e.key)) takeList(e.key, e.value);
  }
  for (final e in chainByKey.entries) {
    if (!seen.contains(e.key)) takeChain(e.key, e.value);
  }
  return out;
}

Map<String, dynamic>? _exportSource(
  ServerList list,
  List<LxBackupWarning> warnings,
) {
  final kind = switch (list) {
    SubscriptionServers() => BackupRecord.subscription,
    UserServer() => BackupRecord.server,
    FolderServers() => BackupRecord.folder,
  };
  final stored = sanitizeCoreRejectInBackupRecord(sourceToRecord(list), kind,
      forExport: true);
  final entity = switch (list) {
    SubscriptionServers s => s.name.isEmpty ? s.url : s.name,
    UserServer u =>
      _str(stored['tag']).isEmpty ? u.id : _str(stored['tag']),
    FolderServers f => f.name,
  };
  final record = exportBackupRecord(kind, stored, entity, warnings);
  if (record == null) return null;
  return switch (kind) {
    BackupRecord.server => _withJsonBody(record),
    BackupRecord.folder => {
        for (final e in record.entries)
          e.key: e.key == 'nodes' && e.value is List
              ? [
                  for (final n in e.value as List)



                    if (n is Map &&
                        (n['kind'] == kNodeKindAuto || _hasSourceText(n)))
                      _withJsonBody(n.cast<String, dynamic>()),
                ]
              : e.value,
      },
    _ => record,
  };
}

bool _hasSourceText(Map<dynamic, dynamic> node) {
  final origin = node['origin'];
  return origin is Map && _str(origin['raw']).trim().isNotEmpty;
}






Map<String, dynamic> _withJsonBody(Map<String, dynamic> node) {
  final origin = node['origin'];
  if (origin is! Map || origin['kind'] != 'json') return node;
  final obj = _tryDecodeObject(_str(origin['raw']).trim());
  if (obj == null ||
      obj['type'] is! String ||
      obj.containsKey('outbounds') ||
      obj.containsKey('endpoints')) {
    return node;
  }
  return {
    for (final e in node.entries) ...{
      e.key: e.value,
      if (e.key == 'origin')
        'body': {
          for (final b in obj.entries)
            if (b.key != 'tag' && b.key != 'detour') b.key: b.value,
        },
    },
  };
}




void _noteLocalOnly(
  List<LxBackupWarning> warnings,
  String entity,
  List<String> fields,
) {
  if (fields.isEmpty) return;
  warnings.add(
    LxBackupWarning(kWarnLocalOnlyDropped, '$entity: ${fields.join(', ')}'),
  );
}


Map<String, dynamic>? _tryDecodeObject(String body) {
  if (!body.startsWith('{')) return null;
  try {
    final decoded = jsonDecode(body);
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  } catch (_) {
    return null;
  }
}





















LxBackupFile parseLxBackup(
  String raw, {
  Set<String> knownOutbounds = const {},
  Set<String> knownPresets = const {},
  Set<String> knownChains = const {},
  RecordVarDecls recordVars = RecordVarDecls.none,
}) {
  final file = decodeLxBackup(
    raw,
    takenTags: knownOutbounds,
    knownPresets: knownPresets,
    knownChains: knownChains,
    recordVars: recordVars,
  );
  return gateLxBackupTargets(
    file,
    lxImportKnownTargets(
      directions: file.directions,
      chainTags: {for (final c in file.chains) c.tag},
      receiverTargets: {...knownOutbounds, ...knownChains},
    ),
  );
}














LxBackupFile decodeLxBackup(
  String raw, {
  Set<String> takenTags = const {},
  Set<String> knownPresets = const {},
  Set<String> knownChains = const {},
  RecordVarDecls recordVars = RecordVarDecls.none,
}) {
  final dynamic decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Это не файл LX Backup');
  }
  final version = decoded['lx_backup'];
  if (version is! int) {
    throw const FormatException('Это не файл LX Backup: нет поля lx_backup');
  }
  if (version > kLxBackupVersion) {
    throw FormatException(
      'Формат бэкапа v$version новее поддерживаемого v$kLxBackupVersion — обновите приложение',
    );
  }
  if (version < kLxBackupFormat0x) {
    throw const FormatException('Это не файл LX Backup: нет поля lx_backup');
  }
  if (version == kLxBackupFormat10) {
    return _parse10(
      decoded,
      takenTags: takenTags,
      knownPresets: knownPresets,
      knownChains: knownChains,
      recordVars: recordVars,
    );
  }
  return _parse0x(
    decoded,
    version,
    takenTags: takenTags,
    knownPresets: knownPresets,
    knownChains: knownChains,
    recordVars: recordVars,
  );
}


LxBackupFile _parse0x(
  Map<String, dynamic> decoded,
  int version, {
  required Set<String> takenTags,
  required Set<String> knownPresets,
  required Set<String> knownChains,
  required RecordVarDecls recordVars,
}) {





  final warnings = _scanUnknown(decoded);

  final directions = _parseDirections(decoded, takenTags, warnings);









  final chains = <SourceChain>[];
  final takenChainTags = <String>{
    for (final t in knownChains) t.trim(),
  };
  for (final item in (decoded['chains'] as List? ?? const [])) {
    if (item is! Map) continue;
    final j = item.cast<String, dynamic>();
    final tag = (j['tag'] as String?)?.trim() ?? '';



    if (tag.isEmpty || j['chain'] is! Map) continue;
    if (!takenChainTags.add(tag)) {
      warnings.add(LxBackupWarning(kWarnChainExists, tag));
      continue;
    }
    chains.add(_chainFromCanon(j, tag));
  }

  final rules = <CustomRule>[
    for (final item in (decoded['rules'] as List? ?? const []))
      if (item is Map)
        ..._ruleFromJson(
          item.cast<String, dynamic>(),
          knownPresets,
          warnings,
        ),
  ];








  final dnsWarnings = <LxBackupWarning>[];
  final dnsRaw = _dnsFromJson(
    (decoded['dns'] as Map?)?.cast<String, dynamic>(),
    dnsWarnings,
    recordVars,
  );
  final parsedVars =
      _parseVars(decoded, warnings, dns: dnsRaw, recordVars: recordVars);
  final routeFinal = _parseRouteFinal(decoded);
  final warp = _parseWarp(decoded, warnings);
  final subscriptions = [
    for (final s in (decoded['subscriptions'] as List? ?? const []))
      if (s is Map) _subscriptionFromJson(s.cast<String, dynamic>(), warnings),
  ];
  final servers = _legacyAutogroups0x([
    for (final s in (decoded['servers'] as List? ?? const []))
      if (s is Map) _serverFromJson(s.cast<String, dynamic>(), warnings),
  ], warnings);
  warnings.addAll(dnsWarnings);

  final by = (decoded['exported_by'] as Map?)?.cast<String, dynamic>() ?? {};
  return LxBackupFile(
    version: version,
    exportedByApp: (by['app'] as String?) ?? '',
    exportedByVersion: (by['version'] as String?) ?? '',
    exportedAt: (decoded['exported_at'] as String?) ?? '',
    directions: directions.directions,
    directionPing: directions.ping,
    rules: sortRulesByAxis(rules),
    chains: chains,
    subscriptions: subscriptions,
    servers: servers,
    dns: parsedVars.dns,
    warp: warp,
    vars: parsedVars.vars,
    routeFinal: routeFinal,
    warnings: warnings,
  );
}


typedef _ParsedDirections = ({
  List<Direction> directions,
  Map<String, LxDirectionPing> ping,
});








_ParsedDirections _parseDirections(
  Map<String, dynamic> decoded,
  Set<String> takenTags,
  List<LxBackupWarning> warnings,
) {
  final directions = <Direction>[];

  final directionPing = <String, LxDirectionPing>{};





  final taken = <String>{
    for (final t in takenTags) t.trim(),
  };
  final items = decoded['directions'];
  for (final item in (items is List ? items : const [])) {
    if (item is! Map) continue;
    final j = item.cast<String, dynamic>();
    final rawTag = j['tag'];
    final tag = rawTag is String ? rawTag.trim() : '';
    if (tag.isEmpty) continue;
    if (!taken.add(tag)) {
      warnings.add(LxBackupWarning(kWarnDirectionExists, tag));
      continue;
    }
    directions.add(_directionFromCanon(j, tag));




    final ping = _directionPingFromCanon(j, tag, warnings);
    if (!ping.isEmpty) directionPing[tag] = ping;
  }
  return (
    directions: directions,
    ping: directionPing,
  );
}


















({Map<String, String> vars, LxDns? dns}) _parseVars(
  Map<String, dynamic> decoded,
  List<LxBackupWarning> warnings, {
  LxDns? dns,
  RecordVarDecls recordVars = RecordVarDecls.none,
}) {
  final vars = <String, String>{};
  final raw = decoded['vars'];
  final rawVars = raw is Map ? raw.cast<String, dynamic>() : const {};
  final servers = dns?.servers.toList();

  final ownVars = <String>{
    for (final s in servers ?? const <DnsServerRef>[])
      if (s is DnsServerTemplate && s.varValues.isNotEmpty) s.tag,
  };
  var lifted = false;
  for (final key in rawVars.keys.toList()..sort()) {
    if (kLxPortableVars.contains(key)) {
      vars[key] = '${rawVars[key]}';
      continue;
    }
    final target = rootDnsVarTarget(key, recordVars);
    if (target == null) {
      warnings.add(LxBackupWarning(kWarnVarSkipped, key,
          reason: kVarSkippedNotPortable));
      continue;
    }
    final at = servers == null
        ? -1
        : servers.indexWhere(
            (s) => s is DnsServerTemplate && s.tag == target.tag);
    if (at < 0) {
      warnings.add(LxBackupWarning(kWarnVarSkipped, key,
          reason: kVarSkippedNoRecord));
      continue;
    }
    if (ownVars.contains(target.tag)) {
      warnings.add(LxBackupWarning(kWarnVarSkipped, key,
          reason: kVarSkippedSuperseded));
      continue;
    }
    final value = rawVars[key];
    final text = value == null ? '' : '$value'.trim();
    if (text.isEmpty) continue;
    final record = servers![at] as DnsServerTemplate;
    servers[at] = record.copyWith(
        varValues: {...record.varValues, target.varName: text});
    lifted = true;
  }
  return (
    vars: vars,
    dns: !lifted || dns == null
        ? dns
        : LxDns(
            servers: servers!,
            rules: dns.rules,
            finalServer: dns.finalServer,
            strategy: dns.strategy,
            defaultDomainResolver: dns.defaultDomainResolver,
          ),
  );
}



String? _parseRouteFinal(Map<String, dynamic> decoded) {
  final route = decoded['route'];
  final finalTag = route is Map ? route['final'] : null;
  if (finalTag is! String || finalTag.isEmpty) return null;
  return finalTag;
}



List<Map<String, dynamic>> _parseWarp(
  Map<String, dynamic> decoded,
  List<LxBackupWarning> warnings,
) {
  final warp = <Map<String, dynamic>>[];
  final items = decoded['warp'];
  for (final item in (items is List ? items : const [])) {
    if (item is! Map) continue;
    final j = item.cast<String, dynamic>();
    final rawType = j['type'];
    final type = rawType is String ? rawType : '';
    if (type != 'wg' && type != 'masque') {
      warnings.add(
        LxBackupWarning(
          kWarnWarpSkipped,
          type.isEmpty ? 'warp[]: нет type' : 'warp[]: $type',
        ),
      );
      continue;
    }
    warp.add(j);
  }
  return warp;
}




List<CustomRule> sortRulesByAxis(List<CustomRule> rules) {
  final indexed = [
    for (var i = 0; i < rules.length; i++) (i, rules[i]),
  ];
  indexed.sort((a, b) {
    final an = a.$2.orderNum;
    final bn = b.$2.orderNum;
    if (an != null && bn != null && an != bn) return an.compareTo(bn);
    if (an == null && bn != null) return 1;
    if (an != null && bn == null) return -1;
    return a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}











const String _extensionsKey = 'extensions';

const Set<String> _rootKeys = {
  'lx_backup',
  'exported_by',
  'exported_at',
  'subscriptions',
  'servers',
  'directions',
  'chains',
  'rules',
  'dns',
  'vars',
  'route',
  'warp',
};

const Set<String> _exportedByKeys = {'app', 'version', 'platform'};
const Set<String> _routeKeys = {'final'};




const Set<String> _sourceRefKeys = {
  'detour_tag',
  'detour_node_source_id',
  'detour_node_tag',
  'detour_node_label',
};

const Set<String> _subscriptionKeys = {
  ..._sourceRefKeys,
  'id',
  'url',
  'label',
  'enabled',
  'max_nodes',
  'tag',
  'update',
  'disabled',
  'warnings',
  'skip',
  'outbounds',

  'identity',
  'exclude_from_global',
  'expose_group_tags_to_global',
};

const Set<String> _serverKeys = {
  ..._sourceRefKeys,
  'id',
  'uri',
  'config_json',
  'label',
  'node_tag',
  'enabled',
  'folder',
  'exclude_from_global',





  'sections',
};

const Set<String> _chainKeys = {
  ..._sourceRefKeys,
  'id',
  'tag',






  'label',
  'enabled',
  'chain',
  'exclude_from_global',
};

const Set<String> _directionKeys = {
  'tag',



  'label',
  'enabled',
  'filter',
  'invert',
  'default',
  'include_direct',
  'include_block',
  'include',
  'interrupt_exist_connections',





  'ping_url',
  'ping_timeout_ms',
  'auto',
};

const Set<String> _directionAutoKeys = {
  'mode',
  'url',
  'interval',
  'tolerance',
  'idle_timeout',
  'interrupt_exist_connections',
  'pool',
  'pool_tolerance',
  'sticky_hash',
};

const Set<String> _ruleKeys = {
  'kind',
  'name',
  'enabled',
  'num',
  'outbound',
  'ref',
  'refs',
  'vars',
  'match',
  'dns',
  'resolve',
};




const Set<String> _chainBodyKeys = {
  'hops',
  'idle_timeout',
  'rewrite',
  'strip',
  'strip_evasion',
};




const Set<String> _warpKeys = {
  'type',
  'private_key',
  'peer_public',
  'client_v4',
  'client_v6',
  'client_id',
  'device_id',
  'token',
  'account_id',
  'license',
  'warp_plus',
  'created_at',
  'private_key_der',
  'server_pub_der',
  'server',
  'port',




  'sni',
  'idle_timeout',
  'keep_alive',
  'awg',
  'endpoint',
};

const Set<String> _dnsKeys = {'servers', 'rules', 'final', 'strategy'};
const Set<String> _dnsRefKeys = {
  'kind',
  'tag',
  'name',
  'enabled',
  'num',
  'ref',
  'vars',
  'value',
};



const Map<String, String> _arrayLabelKeys = {
  'subscriptions': 'url',
  'servers': 'node_tag',
  'chains': 'tag',
  'directions': 'tag',
  'rules': 'name',
  'outbounds': 'tag',
  'warp': 'type',
};














List<LxBackupWarning> _scanUnknown(Map<String, dynamic> root) {
  final sc = _UnknownScan();

  sc.object('', root, _rootKeys);
  sc.nested(root, 'exported_by', _exportedByKeys);
  sc.nested(root, 'route', _routeKeys);

  final dns = (root['dns'] as Map?)?.cast<String, dynamic>();
  if (dns != null) {
    sc.object('dns', dns, _dnsKeys);
    sc.array(dns, 'dns.servers', 'servers', _dnsRefKeys, 'name', null);
    sc.array(dns, 'dns.rules', 'rules', _dnsRefKeys, 'name', null);
  }

  sc.array(root, 'subscriptions', 'subscriptions', _subscriptionKeys, null, (
    where,
    item,
  ) {


    sc.array(
      item,
      '$where.outbounds',
      'outbounds',
      _directionKeys,
      null,
      sc.directionBody,
    );
  });
  sc.array(root, 'servers', 'servers', _serverKeys, null, null);
  sc.array(root, 'chains', 'chains', _chainKeys, null, (where, item) {
    sc.nestedAt(item, where, 'chain', _chainBodyKeys);
  });
  sc.array(
    root,
    'directions',
    'directions',
    _directionKeys,
    null,
    sc.directionBody,
  );
  sc.array(root, 'rules', 'rules', _ruleKeys, null, null);
  sc.array(root, 'warp', 'warp', _warpKeys, null, null);

  return sc.warnings();
}



class _UnknownScan {
  final _fields = <String>[];
  final _seenField = <String>{};
  final _extensionsAt = <String>[];
  final _seenExtension = <String>{};

  void _note(String where, String key) {
    if (key == _extensionsKey) {
      final place = where.isEmpty ? '<file root>' : where;
      if (_seenExtension.add(place)) _extensionsAt.add(place);
      return;
    }
    final name = where.isEmpty ? key : '$where.$key';
    if (_seenField.add(name)) _fields.add(name);
  }

  void object(String where, Map<String, dynamic> obj, Set<String> known) {
    for (final key in obj.keys) {
      if (!known.contains(key)) _note(where, key);
    }
  }

  void nested(Map<String, dynamic> parent, String key, Set<String> known) {
    final obj = (parent[key] as Map?)?.cast<String, dynamic>();
    if (obj == null) return;
    object(key, obj, known);
  }



  void nestedAt(
    Map<String, dynamic> parent,
    String where,
    String key,
    Set<String> known,
  ) {
    final obj = (parent[key] as Map?)?.cast<String, dynamic>();
    if (obj == null) return;
    object('$where.$key', obj, known);
  }





  void dnsServer10Body(String where, Map<String, dynamic> item) {
    final kind = item['kind'];
    if ((kind == 'user' || kind == 'preset') && item.containsKey('vars')) {
      _note(where, 'vars');
    }
  }



  void directionBody(String where, Map<String, dynamic> item) {
    nestedAt(item, where, 'auto', _directionAutoKeys);
  }



  void array(
    Map<String, dynamic> parent,
    String where,
    String key,
    Set<String> known,
    String? labelKey,
    void Function(String, Map<String, dynamic>)? deeper,
  ) {
    final items = parent[key];
    if (items is! List) return;
    final label = labelKey ?? _arrayLabelKeys[key] ?? '';
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! Map) continue;
      final j = item.cast<String, dynamic>();
      final entry = '$where[${_entryLabel(j, label, i)}]';
      object(entry, j, known);
      if (deeper != null) deeper(entry, j);
    }
  }

  static String _entryLabel(
    Map<String, dynamic> item,
    String labelKey,
    int index,
  ) {
    final v = item[labelKey];
    if (v is String && v.isNotEmpty) return v;
    return '#${index + 1}';
  }

  List<LxBackupWarning> warnings() {
    final out = <LxBackupWarning>[];
    if (_extensionsAt.isNotEmpty) {
      final places = _extensionsAt.toList()..sort();
      out.add(LxBackupWarning(kWarnExtensionsDropped, places.join(', ')));
    }
    for (final name in _fields.toList()..sort()) {
      out.add(LxBackupWarning(kWarnUnknownField, name));
    }
    return out;
  }
}






LxSubscription _subscriptionFromJson(
  Map<String, dynamic> j,
  List<LxBackupWarning> warnings,
) {
  j = sanitizeCoreRejectInBackupRecord(j, BackupRecord.subscription);
  final label = (j['label'] as String?) ?? '';
  final where = label.isEmpty ? ((j['url'] as String?) ?? '') : label;




  for (final key in const [
    'exclude_from_global',
    'expose_group_tags_to_global',
  ]) {
    if (j.containsKey(key)) {
      warnings.add(LxBackupWarning(kWarnSourceFlagDropped, '$where.$key'));
    }
  }




  if (j['skip'] is List || j['skip'] is bool) {
    warnings.add(LxBackupWarning(kWarnFieldTypeMismatch, '$where.skip'));
  }






  final tag = (j['tag'] as Map?)?.cast<String, dynamic>() ?? const {};
  final update = (j['update'] as Map?)?.cast<String, dynamic>() ?? const {};

  return LxSubscription(
    id: (j['id'] is String) ? (j['id'] as String).trim() : '',
    url: (j['url'] as String?) ?? '',
    label: label,
    enabled: j['enabled'] as bool? ?? true,
    tagPrefix: (tag['prefix'] as String?) ?? '',
    updateIntervalHours: (update['interval_hours'] as num?)?.toInt(),
    disabled: _disabledFromJson(j['disabled']),
    nodeWarnings: storedWarningsMapFromJson(j['warnings']),
    identity: _identityFromJson(j['identity'], where, warnings),
  );
}








SubscriptionIdentityOverride? _identityFromJson(
  Object? raw,
  String where,
  List<LxBackupWarning> warnings,
) {
  if (raw is! Map) return null;
  final j = raw.cast<String, dynamic>();

  _noteIdentityDropped(
    [
      for (final k in j.keys)
        if (!_identityAppliedKeys.contains(k)) k,
    ],
    where,
    warnings,
  );

  return SubscriptionIdentityOverride(
    userAgent: (j['user_agent'] as String?) ?? '',
    sendHwid: (j['send_hwid'] as bool?) ?? false,
    hwid: (j['hwid'] as String?) ?? '',
    deviceOs: (j['device_os'] as String?) ?? '',
    verOs: (j['ver_os'] as String?) ?? '',
    deviceModel: (j['device_model'] as String?) ?? '',
  );
}





void _noteIdentityDropped(
  Iterable<String> keys,
  String where,
  List<LxBackupWarning> warnings,
) {
  final set = keys.toSet();
  final ordered = [
    for (final k in _identityKeyOrder)
      if (set.contains(k)) k,
    ...(set.where((k) => !_identityKeyOrder.contains(k)).toList()..sort()),
  ];
  if (ordered.isEmpty) return;
  warnings.add(LxBackupWarning(
    kWarnSourceIdentityDropped,
    '$where: ${ordered.join(', ')}',
  ));
}



const List<String> _identityKeyOrder = [
  'user_agent',
  'send_hwid',
  'hwid',
  'device_os',
  'ver_os',
  'device_model',
  'hash_device_model',
];



const Set<String> _identityAppliedKeys = {
  'user_agent',
  'send_hwid',
  'hwid',
  'device_os',
  'ver_os',
  'device_model',
};









Map<String, int> _disabledFromJson(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, int>{};
  raw.forEach((k, v) {
    final key = '$k';
    if (key.isEmpty) return;
    final ts = v is num ? v.toInt() : null;
    if (ts == null) return;
    out[key] = ts;
  });
  return out;
}







LxServer _serverFromJson(
  Map<String, dynamic> j,
  List<LxBackupWarning> warnings,
) {
  final nodeTag = (j['node_tag'] as String?)?.trim() ?? '';
  final label = (j['label'] as String?)?.trim() ?? '';
  var name = nodeTag;
  if (nodeTag.isEmpty) {
    name = label;
  } else if (label.isNotEmpty && label != nodeTag) {
    warnings.add(LxBackupWarning(kWarnLabelDropped, nodeTag));
  }

  if (j.containsKey('exclude_from_global')) {
    warnings.add(
      LxBackupWarning(
        kWarnSourceFlagDropped,
        '${name.isEmpty ? 'servers[]' : name}.exclude_from_global',
      ),
    );
  }



  return LxServer(
    uri: (j['uri'] as String?) ?? '',
    configJson: (j['config_json'] as Map?)?.cast<String, dynamic>(),
    name: name,
    enabled: j['enabled'] as bool? ?? true,

    folder: (j['folder'] as String?)?.trim() ?? '',
  );
}









List<LxServer> _legacyAutogroups0x(
  List<LxServer> servers,
  List<LxBackupWarning> warnings,
) {
  if (!servers.any((s) => s.folder.isNotEmpty && isLegacyAutogroupText(s.uri))) {
    return servers;
  }
  final byFolder = <String, List<int>>{};
  for (var i = 0; i < servers.length; i++) {
    final folder = servers[i].folder;
    if (folder.isNotEmpty) (byFolder[folder] ??= []).add(i);
  }
  final out = servers.toList();
  byFolder.forEach((folder, indexes) {
    final members = [for (final i in indexes) servers[i]];
    final nodes = <NodeSpec?>[
      for (final m in members)
        isLegacyAutogroupText(m.uri) ? null : FolderMember(raw: _body0x(m)).node,
    ];
    for (var k = 0; k < members.length; k++) {
      final m = members[k];
      if (!isLegacyAutogroupText(m.uri)) continue;
      final read = legacyAutogroupSpec(
        m.uri,
        nodes: nodes,
        enabledAt: (i) => members[i].enabled,
        linkOf: (i, tag) =>
            NodeLink(tag: members[i].name.isNotEmpty ? members[i].name : tag),
      );
      if (read == null) continue;
      for (final problem in read.dropped) {
        warnings.add(LxBackupWarning(
          kWarnGroupDegraded,
          read.group.tag,
          reason: 'member $problem, dropped',
        ));
      }
      out[indexes[k]] = LxServer(
        autoGroup: read.group,
        name: read.group.tag,
        enabled: m.enabled,
        folder: folder,
        position: m.position,
      );
    }
  });
  return out;
}


String _body0x(LxServer s) => s.uri.isNotEmpty
    ? s.uri
    : (s.configJson == null ? '' : jsonEncode(s.configJson));












LxDns? _dnsFromJson(
  Map<String, dynamic>? j,
  List<LxBackupWarning> warnings,
  RecordVarDecls recordVars,
) {
  if (j == null) return null;

  final servers = <DnsServerRef>[];
  for (final item in (j['servers'] as List? ?? const [])) {
    if (item is! Map) continue;
    final e = item.cast<String, dynamic>();
    final kind = (e['kind'] as String?) ?? '';
    if (!_dns0xKinds.contains(kind)) {
      warnings.add(
        LxBackupWarning(kWarnDnsEntrySkipped, 'dns.servers: kind=${e['kind']}'),
      );
      continue;
    }
    final server = _dnsServer0x(e, kind);
    if (server == null) continue;
    if (!_templateServerDeclared(server, recordVars)) {
      warnings.add(LxBackupWarning(
          kWarnDnsEntrySkipped, 'dns.servers: template:${server.tag}'));
      continue;
    }
    servers.add(server);
  }

  final rules = <DnsRuleRef>[];
  for (final item in (j['rules'] as List? ?? const [])) {
    if (item is! Map) continue;
    final e = item.cast<String, dynamic>();
    final kind = (e['kind'] as String?) ?? '';
    if (!_dns0xKinds.contains(kind)) {
      warnings.add(
        LxBackupWarning(kWarnDnsEntrySkipped, 'dns.rules: kind=${e['kind']}'),
      );
      continue;
    }
    if (_dnsRule0x(e, kind) case final rule?) rules.add(rule);
  }

  return LxDns(
    servers: servers,
    rules: rules,
    finalServer: (j['final'] as String?) ?? '',
    strategy: (j['strategy'] as String?) ?? '',
  );
}


const Set<String> _dns0xKinds = {'template', 'preset', 'user'};




DnsServerRef? _dnsServer0x(Map<String, dynamic> e, String kind) {
  final name = _str(e['name']);
  final enabled = e['enabled'] is bool ? e['enabled'] as bool : true;
  switch (kind) {
    case 'user':
      final value = e['value'];
      if (name.isEmpty || value is! Map) return null;
      return DnsServerInline(
        enabled: enabled,
        tag: name,
        body: {...value.cast<String, dynamic>()}..remove('tag'),
      );
    case 'preset':
      final ref = _str(e['ref']).isNotEmpty ? _str(e['ref']) : name;
      final at = ref.indexOf(':');
      final tag = at < 0 ? ref : ref.substring(at + 1);
      if (tag.isEmpty) return null;
      return DnsServerPreset(
        enabled: enabled,
        tag: tag,
        presetId: at < 0 ? '' : ref.substring(0, at),
      );
    default:
      if (name.isEmpty) return null;


      final vars = e['vars'];
      return DnsServerTemplate(
        enabled: enabled,
        tag: name,
        varValues: vars is Map
            ? {
                for (final v in vars.entries)
                  if (v.value != null) v.key.toString(): v.value.toString(),
              }
            : const {},
      );
  }
}




bool _templateServerDeclared(DnsServerRef server, RecordVarDecls recordVars) =>
    server is! DnsServerTemplate ||
    recordVars.dnsServers.isEmpty ||
    recordVars.dnsServers.containsKey(server.tag);



DnsRuleRef? _dnsRule0x(Map<String, dynamic> e, String kind) {
  final name = _str(e['name']);
  final enabled = e['enabled'] is bool ? e['enabled'] as bool : true;
  switch (kind) {
    case 'user':
      final value = e['value'];
      if (value is! Map) return null;
      return DnsRuleInline(
        name: name,
        rule: value.cast<String, dynamic>(),
        enabled: enabled,
      );
    case 'preset':
      final ref = _str(e['ref']);
      return ref.isEmpty ? null : DnsRulePreset(presetId: ref, enabled: enabled);
    default:
      return name.isEmpty
          ? null
          : DnsRuleTemplate(name: name, enabled: enabled);
  }
}














Direction _directionFromCanon(Map<String, dynamic> j, String tag) {
  final rawAuto = j['auto'];
  return Direction(
    tag: tag,

    label: (j['label'] as String?) ?? '',

    enabled: j['enabled'] as bool? ?? true,
    nodeFilter: (j['filter'] as String?) ?? '',
    nodeFilterInvert: j['invert'] as bool? ?? false,
    defaultFilter: (j['default'] as String?) ?? '',


    includeDirect: j['include_direct'] as bool? ?? false,
    includeBlock: j['include_block'] as bool? ?? false,
    include: _strList(j['include']),


    interruptExistConnections:
        j['interrupt_exist_connections'] as bool? ?? true,
    auto: rawAuto is Map
        ? directionAutoFromRecord(rawAuto.cast<String, dynamic>())
        : null,
  );
}


















LxDirectionPing _directionPingFromCanon(
  Map<String, dynamic> j,
  String tag,
  List<LxBackupWarning> warnings,
) {
  final rawUrl = j['ping_url'];
  if (rawUrl != null && rawUrl is! String) {
    warnings.add(
      LxBackupWarning(kWarnFieldTypeMismatch, 'directions[$tag].ping_url'),
    );
  }

  final rawTimeout = j['ping_timeout_ms'];

  if (rawTimeout != null && rawTimeout is! num) {
    warnings.add(
      LxBackupWarning(
        kWarnFieldTypeMismatch,
        'directions[$tag].ping_timeout_ms',
      ),
    );
  }



  return LxDirectionPing(
    url: rawUrl is String ? rawUrl : null,
    timeoutMs: rawTimeout is num ? rawTimeout.toInt() : null,
  );
}

















Map<String, dynamic> _directionToJson(Direction d, LxDirectionPing? ping) => {
  'tag': d.tag,
  if (d.label.isNotEmpty && d.label != d.tag) 'label': d.label,


  if (!d.enabled) 'enabled': false,
  if (d.nodeFilter.isNotEmpty) 'filter': d.nodeFilter,
  if (d.nodeFilterInvert) 'invert': true,
  if (d.defaultFilter.isNotEmpty) 'default': d.defaultFilter,
  if (d.includeDirect) 'include_direct': true,
  if (d.includeBlock) 'include_block': true,
  if (d.include.isNotEmpty) 'include': d.include,
  'interrupt_exist_connections': d.interruptExistConnections,
  if (ping?.url != null) 'ping_url': ping!.url,
  if (ping?.timeoutMs != null) 'ping_timeout_ms': ping!.timeoutMs,
  if (d.auto != null) 'auto': directionAutoToRecord(d.auto!),
};














SourceChain _chainFromCanon(Map<String, dynamic> j, String tag) {
  final canon =
      (j['chain'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};



  final label = j['label'];
  final enabled = j['enabled'];
  return chainFromRecord({
    'kind': kSourceKindChain,
    'tag': tag,
    if (label is String) 'label': label,



    if (enabled is bool) 'enabled': enabled,
    'body': {
      for (final e in canon.entries)
        if (e.key != 'hops') e.key: e.value,
    },
    'hops': [
      for (final h in (canon['hops'] is List ? canon['hops'] as List : const []))
        if (h is String) h,
    ],
  }).value!;
}













bool _isKnownOutbound(String tag, Set<String> known) {
  final t = tag.trim();
  return _reservedOutbounds.contains(t) || known.contains(t);
}




bool lxIsKnownImportTarget(String tag, Set<String> known) =>
    _isKnownOutbound(tag, known);
















Set<String> lxImportRootNames({
  Iterable<Direction> directions = const [],
  Iterable<String> chainTags = const [],
  Set<String> systemTags = const {},
  Iterable<String> replaceTags = const [],
}) {
  final names = <String>{};
  void add(String tag) {
    final t = tag.trim();
    if (t.isNotEmpty) names.add(t);
  }

  (systemTags.isEmpty ? kLxImportDefaultSystemTags : systemTags).forEach(add);
  for (final d in directions) {
    if (d.tag.trim().isEmpty) continue;
    add(d.tag);


    if (d.auto != null) add(d.autoTag);
  }
  chainTags.forEach(add);
  replaceTags.forEach(add);
  return names;
}



Set<String> lxImportRootNodeTags(List<ServerList> lists) => {
      for (final l in lists)
        if (l is UserServer)

          for (final n in l.nodes.isNotEmpty ? l.nodes : _nodesOf(l.rawBody))
            if (n.tag.isNotEmpty) containerFinalForm(l, n.tag),
    };



















Set<String>? lxImportKnownTargets({
  Iterable<Direction> directions = const [],
  Iterable<String> chainTags = const [],
  List<ServerList> lists = const [],
  Set<String> systemTags = const {},
  Set<String> receiverTargets = const {},
}) {
  final rootNodes = lxImportRootNodeTags(lists);
  final replaceTags = sourceReplaceNames(lists);
  final receiver = {
    for (final t in receiverTargets)
      if (t.trim().isNotEmpty) t.trim(),
  };
  if (systemTags.isEmpty &&
      directions.every((d) => d.tag.trim().isEmpty) &&
      chainTags.every((t) => t.trim().isEmpty) &&
      rootNodes.isEmpty &&
      replaceTags.isEmpty &&
      receiver.isEmpty) {
    return null;
  }
  return {
    ..._reservedOutbounds,
    ...lxImportRootNames(
      directions: directions,
      chainTags: chainTags,
      systemTags: systemTags,
      replaceTags: replaceTags,
    ),
    ...rootNodes,
    ...receiver,
  };
}




String _ruleTarget(CustomRule r) => switch (r) {
      CustomRuleInline(:final outbound) => outbound,
      CustomRuleSrs(:final outbound) => outbound,
      CustomRulePreset() => '',
      CustomRuleJson(:final json) => switch (_tryDecodeObject(json.trim())) {
          {'outbound': final String o} => o,
          _ => '',
        },
    };












LxBackupFile gateLxBackupTargets(LxBackupFile file, Set<String>? known) {
  if (known == null) return file;
  final warnings = [...file.warnings];
  final rules = <CustomRule>[];
  for (final r in file.rules) {
    final target = _ruleTarget(r);
    if (target.isEmpty || _isKnownOutbound(target, known)) {
      rules.add(r);
      continue;
    }
    warnings.add(LxBackupWarning(kWarnUnknownOutbound,
        '${r.name.isEmpty ? r.kind.name : r.name} → $target'));
    rules.add(r.withEnabled(false));
  }
  var routeFinal = file.routeFinal;
  if (routeFinal != null &&
      routeFinal.isNotEmpty &&
      !_isKnownOutbound(routeFinal, known)) {
    warnings.add(LxBackupWarning(kWarnFinalDropped, routeFinal));
    routeFinal = null;
  }
  return LxBackupFile(
    version: file.version,
    exportedByApp: file.exportedByApp,
    exportedByVersion: file.exportedByVersion,
    exportedAt: file.exportedAt,
    directions: file.directions,
    directionPing: file.directionPing,
    rules: rules,
    chains: file.chains,
    chainHops: file.chainHops,
    chainPositions: file.chainPositions,
    subscriptions: file.subscriptions,
    servers: file.servers,
    folders: file.folders,
    dns: file.dns,
    warp: file.warp,
    vars: file.vars,
    routeFinal: routeFinal,
    warnings: warnings,
  );
}





List<CustomRule> _ruleFromJson(
  Map<String, dynamic> j,
  Set<String> knownPresets,
  List<LxBackupWarning> warnings,
) {
  final kindName = (j['kind'] as String?) ?? '';
  final name = (j['name'] as String?) ?? '';
  if (kindName == 'json') {
    return _jsonRule0x(j, name, warnings);
  }
  final enabled = (j['enabled'] as bool?) ?? true;
  final rawNum = j['num'];
  final orderNum = rawNum is num ? rawNum.toInt() : null;
  final outbound = (j['outbound'] as String?) ?? '';

  final rule = _ruleBodyFromJson(
    j,
    kindName,
    name,
    enabled,
    orderNum,
    outbound,
    knownPresets,
    warnings,
  );
  return rule == null ? const [] : [rule];
}



CustomRule? _ruleBodyFromJson(
  Map<String, dynamic> j,
  String kindName,
  String name,
  bool enabled,
  int? orderNum,
  String outbound,
  Set<String> knownPresets,
  List<LxBackupWarning> warnings,
) {
  switch (kindName) {
    case 'inline':
      final match = (j['match'] as Map?)?.cast<String, dynamic>() ?? const {};
      return CustomRuleInline(
        name: name,
        enabled: enabled,
        orderNum: orderNum,
        domains: _strList(match['domain']),
        domainSuffixes: _strList(match['domain_suffix']),
        domainKeywords: _strList(match['domain_keyword']),
        ipCidrs: _strList(match['ip_cidr']),
        ports: _strList(match['port']),
        portRanges: _strList(match['port_range']),
        protocols: _strList(match['protocol']),
        network: _strList(match['network']),



        outbound: outbound.isEmpty ? kDirectOutboundTag : outbound,


        dns: RuleDns.fromJson(j['dns']),
        resolve: RuleResolve.fromJson(j['resolve']),
      );

    case 'preset':
      final ref = (j['ref'] as String?) ?? '';
      if (knownPresets.isNotEmpty && !knownPresets.contains(ref)) {
        enabled = false;
        warnings.add(LxBackupWarning(kWarnUnknownPreset, ref));
      }

      final vars = j['vars'];
      return CustomRulePreset(
        name: name,
        enabled: enabled,
        orderNum: orderNum,
        presetId: ref,
        varsValues: vars is Map
            ? {
                for (final e in vars.entries)
                  if (e.key is String)
                    e.key as String: e.value?.toString() ?? '',
              }
            : const {},
      );

    case 'srs':
      return CustomRuleSrs(
        name: name,
        enabled: enabled,
        orderNum: orderNum,

        srsUrl: _str(j['ref']),
        srsUrls: _strList(j['refs']),
        outbound: outbound,
        dns: RuleDns.fromJson(j['dns']),
        resolve: RuleResolve.fromJson(j['resolve']),
      );

    default:
      warnings.add(
        LxBackupWarning(kWarnUnknownField, 'rules[].kind=$kindName'),
      );
      return null;
  }
}






List<CustomRule> _jsonRule0x(
  Map<String, dynamic> j,
  String name,
  List<LxBackupWarning> warnings,
) {
  final match = j['match'];
  if (match is! Map && match is! List) {
    warnings.add(
      LxBackupWarning(kWarnUnknownField, 'rules[].kind=json: $name'),
    );
    return const [];
  }
  final record = <String, dynamic>{
    'kind': 'inline',
    'name': name,
    if (j['enabled'] is bool) 'enabled': j['enabled'],
    if (j['num'] is num) 'num': j['num'],
    'verbatim': true,
  };
  return [
    for (final part in _splitRuleBodies(
        record, match is Map ? [match] : match, 'rules[$name].match', warnings))
      ?ruleFromRecord(part).value,
  ];
}

List<String> _strList(Object? v) {
  if (v is List) return [for (final e in v) '$e'];
  return const [];
}
















String _str(Object? v) => v is String ? v : '';

String _trimmed(Object? v) => v is String ? v.trim() : '';

Map<String, dynamic>? _obj(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : null;

List<Object?> _list(Object? v) => v is List ? v : const [];



const String _kNoFileId = '\u0000';


NodeLink? _link10(Object? raw) {
  final link = nodeLinkFromRecord(raw);
  return link == null || link.tag.isEmpty ? null : link;
}



String _source10Label(Map<String, dynamic> j) {
  final url = _trimmed(j['url']);
  if (url.isNotEmpty) return url;
  final name = _trimmed(j['name']);
  if (name.isNotEmpty) return name;
  return _trimmed(j['tag']);
}



Map<String, dynamic> _sourceForCodec(
  BackupRecord kind,
  Map<String, dynamic> j,
  String fileId, {
  Map<String, dynamic> override = const {},
}) =>
    {
      ...stripUndeclaredBackupFields(kind, j),
      ...override,
      'id': fileId.isEmpty ? _kNoFileId : fileId,
    };




bool _carries(BackupRecord kind, Map<String, dynamic> j, String key) =>
    j.containsKey(key) && declaredBackupKeys(kind).contains(key);


DetourPolicy _flagsOf(DetourPolicy p) => p.copyWith(overrideDetour: NodeLink.none);

LxBackupFile _parse10(
  Map<String, dynamic> decoded, {
  required Set<String> takenTags,
  required Set<String> knownPresets,
  required Set<String> knownChains,
  required RecordVarDecls recordVars,
}) {
  final warnings = _scanUnknown10(decoded);

  final parsedDirections = _parseDirections(decoded, takenTags, warnings);

  final subscriptions = <LxSubscription>[];
  final servers = <LxServer>[];
  final folders = <LxFolder>[];
  final chains = <SourceChain>[];
  final chainHops = <String, List<NodeLink>>{};
  final chainPositions = <String, int>{};
  final takenChainTags = <String>{
    for (final t in knownChains) t.trim(),
  };

  final sources = _list(decoded['sources']);
  for (var i = 0; i < sources.length; i++) {
    final j = _obj(sources[i]);
    if (j == null) continue;
    final kind = _str(j['kind']);
    switch (kind) {
      case 'subscription':
        _dropForeignSections(j, kind, warnings);
        subscriptions.add(_subscription10(j, i, warnings));
      case 'server':
        final server = _server10(j, warnings, position: i);
        if (server != null) servers.add(server);
      case 'folder':
        _dropForeignSections(j, kind, warnings);
        final folder = _folder10(j, i);
        folders.add(folder);
        for (final rawNode in _list(j['nodes'])) {
          final node = _obj(rawNode);
          if (node == null) continue;
          final member = _folderMember10(node, folder, warnings);
          if (member != null) servers.add(member);
        }
      case 'chain':
        final tag = _trimmed(j['tag']);

        if (tag.isEmpty) continue;
        _dropForeignSections(j, kind, warnings);
        if (!takenChainTags.add(tag)) {
          warnings.add(LxBackupWarning(kWarnChainExists, tag));
          continue;
        }
        final chain = _chain10(j, tag, warnings);
        if (chain == null) continue;
        chains.add(chain.chain);
        chainHops[tag] = chain.hops;
        chainPositions[tag] = i;
      default:


        warnings.add(LxBackupWarning(
          kWarnSourceKindUnsupported,
          _source10Label(j),
          kind: kind,
        ));
    }
  }

  final rules = <CustomRule>[
    for (final item in _list(decoded['rules']))
      if (_obj(item) case final j?) ..._rule10(j, knownPresets, warnings),
  ];


  final dnsWarnings = <LxBackupWarning>[];
  final dnsRaw =
      _dns10(decoded['dns'], knownPresets, dnsWarnings, recordVars);
  final parsedVars =
      _parseVars(decoded, warnings, dns: dnsRaw, recordVars: recordVars);
  final vars = parsedVars.vars;
  final routeFinal = _parseRouteFinal(decoded);
  final warp = _parseWarp(decoded, warnings);
  warnings.addAll(dnsWarnings);
  final dns = parsedVars.dns;

  final by = _obj(decoded['exported_by']) ?? const <String, dynamic>{};
  return LxBackupFile(
    version: kLxBackupFormat10,
    exportedByApp: _str(by['app']),
    exportedByVersion: _str(by['version']),
    exportedAt: _str(decoded['exported_at']),
    directions: parsedDirections.directions,
    directionPing: parsedDirections.ping,
    rules: sortRulesByAxis(rules),
    chains: chains,
    chainHops: chainHops,
    chainPositions: chainPositions,
    subscriptions: subscriptions,
    servers: servers,
    folders: folders,
    dns: dns,
    warp: warp,
    vars: vars,
    routeFinal: routeFinal,
    warnings: warnings,
  );
}







void _dropForeignSections(
  Map<String, dynamic> j,
  String kind,
  List<LxBackupWarning> warnings,
) {
  final raw = _obj(j['sections']);
  if (raw == null) return;
  final dns = _obj(raw['dns']);
  final carriesRecords = _list(raw['rules']).isNotEmpty ||
      _list(dns?['servers']).isNotEmpty ||
      _list(dns?['rules']).isNotEmpty;
  if (!carriesRecords) return;
  warnings.add(LxBackupWarning(
    kWarnSectionRecordDropped,
    '${_source10Label(j)}: sections',
    kind: kind,
    reason: kSectionDropReasonNotAllowed,
  ));
}














LxServer? _server10(
  Map<String, dynamic> j,
  List<LxBackupWarning> warnings, {
  LxFolder? folder,
  int position = 0,
}) {
  j = sanitizeCoreRejectInBackupRecord(
    j,
    folder == null ? BackupRecord.server : BackupRecord.folderNode,
  );
  _dropForeignSections(j, _str(j['kind']), warnings);
  if (j.containsKey('sections')) j = {...j}..remove('sections');
  final tag = _trimmed(j['tag']);
  final origin = _obj(j['origin']);
  final hasOrigin = _str(origin?['raw']).trim().isNotEmpty;
  final fileId = folder == null ? _trimmed(j['id']) : '';
  final read = sourceFromRecord(
    _sourceForCodec(
      folder == null ? BackupRecord.server : BackupRecord.folderNode,

      hasOrigin ? j : ({...j}..remove('origin')),
      fileId,
      override: const {'kind': kSourceKindServer},
    ),
  );
  final node = read.value;
  if (node is! UserServer) return null;
  final raw = node.rawBody;
  if (raw.trim().isEmpty) return null;

  var uri = '';
  Map<String, dynamic>? configJson;
  final obj = hasOrigin && _str(origin?['kind']) != 'json'
      ? null
      : _tryDecodeObject(raw.trim());
  if (obj != null) {
    configJson = {...obj, if (tag.isNotEmpty) 'tag': tag};
  } else {

    uri = raw;
  }

  final root = folder == null;
  return LxServer(
    detour: _link10(j['detour']),
    detourPolicy: root && _carries(BackupRecord.server, j, 'detour_policy')
        ? _flagsOf(node.detourPolicy)
        : null,
    tagPrefix: root && _carries(BackupRecord.server, j, 'tag_policy')
        ? node.tagPrefix
        : null,
    uri: uri,
    configJson: configJson,
    name: tag,
    enabled: node.enabled,
    warnings: storedWarningsFromJson(j['warnings']),
    folder: folder?.name ?? '',
    folderRef: folder?.key ?? '',
    position: position,
    id: fileId,
    skipPresets: node.skipPresets,
  );
}






LxServer? _folderMember10(
  Map<String, dynamic> node,
  LxFolder folder,
  List<LxBackupWarning> warnings,
) {
  final kind = _str(node['kind']);
  final tag = _trimmed(node['tag']);
  switch (kind) {
    case 'server':
      return _server10(node, warnings, folder: folder);
    case kNodeKindAuto:
      _dropForeignSections(node, kind, warnings);
      final read = autoGroupMemberFromRecord(
        stripUndeclaredBackupFields(BackupRecord.folderNode, node),
        folderId: folder.key,
        where: '${folder.name}: $tag',
      );
      final group = read.member.node! as AutoSelectSpec;
      return LxServer(
        autoGroup: group,
        name: group.tag,
        enabled: read.member.enabled,

        warnings: read.member.warnings,
        folder: folder.name,
        folderRef: folder.key,
      );
    case 'unsupported':
      final raw = _str(_obj(node['origin'])?['raw']);
      if (raw.trim().isNotEmpty) {
        _dropForeignSections(node, kind, warnings);
        return LxServer(
          uri: raw,
          name: tag,
          enabled: node['enabled'] is bool ? node['enabled'] as bool : true,
          folder: folder.name,
          folderRef: folder.key,
        );
      }
  }
  warnings.add(LxBackupWarning(
    kWarnSourceKindUnsupported,
    '${folder.name}: ${tag.isEmpty ? kind : tag}',
    kind: kind,
  ));
  return null;
}






LxSubscription _subscription10(
  Map<String, dynamic> j,
  int position,
  List<LxBackupWarning> warnings,
) {
  j = sanitizeCoreRejectInBackupRecord(j, BackupRecord.subscription);
  final fileId = _trimmed(j['id']);
  final read = sourceFromRecord(
      _sourceForCodec(BackupRecord.subscription, j, fileId));
  final sub = read.value! as SubscriptionServers;
  bool carries(String key) => _carries(BackupRecord.subscription, j, key);
  _noteIdentityDropped(
    [
      for (final k in read.unknownKeys)
        if (k.startsWith('identity.')) k.substring('identity.'.length),
    ],
    _source10Label(j),
    warnings,
  );
  return LxSubscription(
    id: fileId,
    url: sub.url,
    label: sub.name,
    enabled: sub.enabled,
    tagPrefix: sub.tagPrefix,
    updateIntervalHours: sub.updateIntervalHours,
    disabled: {
      for (final e in sub.disabledHashes.entries)
        e.key: e.value.millisecondsSinceEpoch ~/ 1000,
    },
    nodeWarnings: sub.nodeWarnings,
    identity: sub.identity,
    detour: _link10(j['detour']),
    detourPolicy: carries('detour_policy') ? _flagsOf(sub.detourPolicy) : null,
    importRules: carries('import_rules') ? sub.importRules : null,
    importRulesEnabled:
        carries('import_rules_enabled') ? sub.importRulesEnabled : null,
    onUpdateAction: carries('on_update_action') ? sub.onUpdateAction : null,
    replace: sub.replace,
    fullSettings: true,
    position: position,
  );
}



LxFolder _folder10(Map<String, dynamic> j, int position) {
  final fileId = _trimmed(j['id']);
  final read = sourceFromRecord(_sourceForCodec(
    BackupRecord.folder,
    j,
    fileId,
    override: const {'nodes': <Object?>[]},
  ));
  final folder = read.value! as FolderServers;
  bool carries(String key) => _carries(BackupRecord.folder, j, key);
  return LxFolder(
    position: position,



    key: fileId.isNotEmpty ? fileId : '\u0000$position',
    id: fileId,

    name: folder.name,
    enabled: folder.enabled,
    tagPrefix: folder.tagPrefix,
    detour: _link10(j['detour']),
    detourPolicy: carries('detour_policy') ? _flagsOf(folder.detourPolicy) : null,
    pingUrl: carries('ping_url') ? folder.pingUrl : null,
    pingTimeoutMs: carries('ping_timeout_ms') ? folder.pingTimeoutMs : null,
    replace: folder.replace,
  );
}





({SourceChain chain, List<NodeLink> hops})? _chain10(
  Map<String, dynamic> j,
  String tag,
  List<LxBackupWarning> warnings,
) {
  final read = chainFromRecord(
    {...stripUndeclaredBackupFields(BackupRecord.chain, j), 'tag': tag},
  );
  final chain = read.value;
  if (chain == null) return null;
  for (final key in read.unknownKeys) {
    if (key.startsWith('body.')) {
      warnings.add(LxBackupWarning(kWarnUnknownField, 'sources[$tag].$key'));
    }
  }
  return (
    chain: chain,
    hops: [
      for (final h in _list(j['hops'])) ?nodeLinkFromRecord(h),
    ],
  );
}












List<Map<String, dynamic>> _splitRuleBodies(
  Map<String, dynamic> record,
  Object? body,
  String where,
  List<LxBackupWarning> warnings,
) {
  if (body is! List) return [record];
  final name = _str(record['name']);
  final parts = <Map<String, dynamic>>[];
  for (var i = 0; i < body.length; i++) {
    final item = body[i];
    if (item is! Map) {
      warnings.add(
          LxBackupWarning(kWarnUnknownField, '$where[$i]: not an object'));
      continue;
    }
    parts.add({
      for (final e in record.entries)
        if (e.key != 'id' || parts.isEmpty) e.key: e.value,
      'name': parts.isEmpty || name.isEmpty ? name : '$name #${parts.length + 1}',
      'body': item.cast<String, dynamic>(),
    });
  }
  if (body.isEmpty) {
    warnings.add(LxBackupWarning(kWarnUnknownField, '$where: empty array'));
  }
  return parts;
}









List<CustomRule> _rule10(
  Map<String, dynamic> j,
  Set<String> knownPresets,
  List<LxBackupWarning> warnings,
) {
  final kind = _str(j['kind']);
  final name = _str(j['name']);
  final ref = _str(j['ref']);
  final label = name.isNotEmpty ? name : (ref.isNotEmpty ? ref : kind);
  if (kind != 'inline' && kind != 'srs' && kind != 'preset') {

    warnings.add(LxBackupWarning(kWarnUnknownField, 'rules[].kind=$kind'));
    return const [];
  }
  final record = stripUndeclaredBackupFields(BackupRecord.rule, j);
  return [
    for (final part in _splitRuleBodies(
        record, record['body'], 'rules[$label].body', warnings))
      ?_ruleRecord10(part, kind, knownPresets, warnings),
  ];
}

CustomRule? _ruleRecord10(
  Map<String, dynamic> j,
  String kind,
  Set<String> knownPresets,
  List<LxBackupWarning> warnings,
) {
  final name = _str(j['name']);
  final ref = _str(j['ref']);
  final label = name.isNotEmpty ? name : (ref.isNotEmpty ? ref : kind);
  final read = ruleFromRecord(j, unknownAsVerbatim: true);
  final rule = read.value;
  if (rule == null) {
    warnings.add(
        LxBackupWarning(kWarnUnknownField, 'rules[$label]: ${read.dropped}'));
    return null;
  }

  if (rule is CustomRulePreset) {
    CustomRule out = rule;


    if (out.name.isEmpty) out = out.withName(rule.presetId);
    if (knownPresets.isNotEmpty && !knownPresets.contains(rule.presetId)) {
      warnings.add(LxBackupWarning(kWarnUnknownPreset, rule.presetId));
      out = out.withEnabled(false);
    }
    return out;
  }

  if (read.unknownKeys.isNotEmpty) {
    if (kind != 'inline' || read.unknownKeys.contains('rule_set')) {
      warnings.add(LxBackupWarning(
        kWarnUnknownField,
        'rules[$label].body: ${read.unknownKeys.join(', ')}',
      ));
      return null;
    }


    for (final key in const ['dns', 'resolve']) {
      if (j[key] is Map && (j[key] as Map).isNotEmpty) {
        warnings.add(LxBackupWarning(kWarnUnknownField, 'rules[$label].$key'));
      }
    }
  }
  return rule;
}









LxDns? _dns10(
  Object? raw,
  Set<String> knownPresets,
  List<LxBackupWarning> warnings,
  RecordVarDecls recordVars,
) {
  final j = _obj(raw);
  if (j == null) return null;

  final servers = <DnsServerRef>[];
  for (final item in _list(j['servers'])) {
    final e = _obj(item);
    if (e == null) continue;
    final kind = _str(e['kind']);
    final read = (kind == 'user' || kind == 'template' || kind == 'preset')
        ? dnsServerFromRecord(
            stripUndeclaredBackupFields(BackupRecord.dnsServer, e))
        : null;
    final server = read?.value;
    if (server == null) {
      warnings.add(LxBackupWarning(
        kWarnDnsEntrySkipped,
        'dns.servers: ${read?.dropped ?? 'kind=$kind'}',
      ));
      continue;
    }

    if (server is DnsServerPreset &&
        server.presetId.isNotEmpty &&
        knownPresets.isNotEmpty &&
        !knownPresets.contains(server.presetId)) {
      warnings.add(LxBackupWarning(
          kWarnDnsEntrySkipped, 'dns.servers: ${_trimmed(e['ref'])}'));
      continue;
    }
    if (!_templateServerDeclared(server, recordVars)) {
      warnings.add(LxBackupWarning(
          kWarnDnsEntrySkipped, 'dns.servers: template:${server.tag}'));
      continue;
    }
    servers.add(server);
  }

  final rules = <DnsRuleRef>[];
  for (final item in _list(j['rules'])) {
    final e = _obj(item);
    if (e == null) continue;
    final kind = _str(e['kind']);


    final readable = kind == 'user' ||
        kind == 'preset' ||
        ((kind == 'srs' || kind == 'template') &&
            backupKindTravels(BackupRecord.dnsRule, kind));
    final read = readable
        ? dnsRuleFromRecord(stripUndeclaredBackupFields(BackupRecord.dnsRule, e))
        : null;
    switch (read?.value) {
      case final DnsRulePreset rule
          when knownPresets.isNotEmpty && !knownPresets.contains(rule.presetId):
        warnings.add(LxBackupWarning(
          kWarnDnsEntrySkipped,
          'dns.rules: ${_str(e['ref'])}',
        ));
      case final DnsRuleRef rule:
        rules.add(rule);
      case null:
        warnings.add(LxBackupWarning(
          kWarnDnsEntrySkipped,
          'dns.rules: ${read?.dropped ?? 'kind=$kind'}',
        ));
    }
  }

  return LxDns(
    servers: servers,
    rules: rules,
    finalServer: _str(j['final']),
    strategy: _str(j['strategy']),
    defaultDomainResolver: _str(j['default_domain_resolver']),
  );
}










const Set<String> _root10Keys = {
  'lx_backup',
  'exported_by',
  'exported_at',
  'sources',
  'directions',
  'rules',
  'dns',
  'vars',
  'route',
  'warp',
};


const Set<String> _node10Keys = {
  'kind',
  'tag',
  'enabled',
  'origin',
  'body',
  'detour',
  'hops',
  'group',
  'service',
  'reason',
  'sections',

  'skip_presets',



  'warnings',
};



const Set<String> _source10Keys = {
  ..._node10Keys,
  'id',
  'name',
  'tag_policy',
  'nodes',
  'url',
  'identity',
  'relays_in_directions',
  'skip',
  'max_nodes',
  'update',
  'disabled',


  'replace',
};

const Set<String> _origin10Keys = {'kind', 'raw', 'sub_url'};
const Set<String> _link10Keys = {'folder_id', 'tag'};
const Set<String> _tagPolicy10Keys = {'prefix', 'postfix'};
const Set<String> _update10Keys = {'interval_hours', 'auto_refresh'};
const Set<String> _group10Keys = {
  'group_type',
  'default',
  'members',
  'strategy',

  'members_rule',
  'pool_badge',
};
const Set<String> _membersRule10Keys = {'include', 'exclude'};

const Set<String> _rule10Keys = {
  'kind',
  'name',
  'enabled',
  'num',
  'ref',
  'vars',
  'refs',
  'body',
  'id',
  'dns',
  'resolve',
};

const Set<String> _dns10Keys = {
  'strategy',
  'final',
  'default_domain_resolver',
  'servers',
  'rules',
};
const Set<String> _dnsServer10Keys = {'kind', 'tag', 'ref', 'enabled', 'body'};
const Set<String> _dnsRule10Keys = {
  'kind',
  'ref',
  'name',
  'id',
  'enabled',
  'body',
};






List<LxBackupWarning> _scanUnknown10(Map<String, dynamic> root) {
  final sc = _UnknownScan();

  final sourceKeys = {
    ..._source10Keys,
    ...declaredBackupKeys(BackupRecord.subscription),
    ...declaredBackupKeys(BackupRecord.server),
    ...declaredBackupKeys(BackupRecord.folder),
    ...declaredBackupKeys(BackupRecord.chain),
  };
  final nodeKeys = {
    ..._node10Keys,
    ...declaredBackupKeys(BackupRecord.folderNode),
  };
  final ruleKeys = {..._rule10Keys, ...declaredBackupKeys(BackupRecord.rule)};
  final dnsServerKeys = {
    ..._dnsServer10Keys,
    ...declaredBackupKeys(BackupRecord.dnsServer),
  };
  final dnsRuleKeys = {
    ..._dnsRule10Keys,
    ...declaredBackupKeys(BackupRecord.dnsRule),
  };

  sc.object('', root, _root10Keys);
  sc.nested(root, 'exported_by', _exportedByKeys);
  sc.nested(root, 'route', _routeKeys);

  final dns = _obj(root['dns']);
  if (dns != null) {
    sc.object('dns', dns, _dns10Keys);
    sc.array(dns, 'dns.servers', 'servers', dnsServerKeys, 'tag',
        sc.dnsServer10Body);
    sc.array(dns, 'dns.rules', 'rules', dnsRuleKeys, 'name', null);
  }

  void sourceBody(String where, Map<String, dynamic> item) {
    sc.nestedAt(item, where, 'origin', _origin10Keys);
    sc.nestedAt(item, where, 'detour', _link10Keys);
    sc.nestedAt(item, where, 'tag_policy', _tagPolicy10Keys);
    sc.nestedAt(item, where, 'update', _update10Keys);
    sc.array(item, '$where.hops', 'hops', _link10Keys, 'tag', null);
    final group = _obj(item['group']);
    if (group != null) {
      sc.object('$where.group', group, _group10Keys);
      sc.array(
          group, '$where.group.members', 'members', _link10Keys, 'tag', null);
      sc.nestedAt(group, '$where.group', 'strategy', _directionAutoKeys);
      sc.nestedAt(group, '$where.group', 'members_rule', _membersRule10Keys);
    }
    final replace = _obj(item['replace']);
    if (replace != null) {
      sc.object('$where.replace', replace, kReplaceRecordKeys);
      sc.nestedAt(replace, '$where.replace', 'auto', _directionAutoKeys);
    }
  }

  sc.array(root, 'sources', 'sources', sourceKeys, 'tag', (where, item) {
    sourceBody(where, item);
    sc.array(item, '$where.nodes', 'nodes', nodeKeys, 'tag', sourceBody);
  });
  sc.array(
    root,
    'directions',
    'directions',
    _directionKeys,
    null,
    sc.directionBody,
  );
  sc.array(root, 'rules', 'rules', ruleKeys, 'name', null);
  sc.array(root, 'warp', 'warp', _warpKeys, null, null);

  return sc.warnings();
}



typedef BackupSubscriptionMerge = ({


  List<ServerList> lists,


  Map<String, int> byUrl,


  int applied,



  Map<String, String> ids,



  Map<String, int> added,





  Map<String, NodeLink?> detours,
});





String _adoptSourceId(String fileId, Set<String> taken) {
  final id = fileId.isNotEmpty &&
          _sourceIdShape.hasMatch(fileId) &&
          !taken.contains(fileId)
      ? fileId
      : newUuidV4();
  taken.add(id);
  return id;
}

final RegExp _sourceIdShape = RegExp(r'^[A-Za-z0-9_-]{1,64}$');



























BackupSubscriptionMerge mergeBackupSubscriptions(
  List<ServerList> lists,
  List<LxSubscription> incoming,
) {
  final byUrl = <String, int>{
    for (var i = 0; i < lists.length; i++)
      if (lists[i] is SubscriptionServers)
        (lists[i] as SubscriptionServers).url: i,
  };
  final merged = lists.toList();
  final takenIds = <String>{for (final l in merged) l.id};
  final ids = <String, String>{};
  final added = <String, int>{};
  final detours = <String, NodeLink?>{};
  var applied = 0;

  DateTime at(int unixSeconds) =>
      DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);

  for (final sub in incoming) {
    if (sub.url.isEmpty) continue;
    final idx = byUrl[sub.url];
    if (idx != null) {
      final existing = merged[idx] as SubscriptionServers;

      final add = <String, DateTime>{
        for (final e in sub.disabled.entries)
          if (!existing.disabledHashes.containsKey(e.key)) e.key: at(e.value),
      };


      final addW = <String, List<StoredWarning>>{
        for (final e in sub.nodeWarnings.entries)
          if (!existing.nodeWarnings.containsKey(e.key)) e.key: e.value,
      };
      merged[idx] = existing.copyWith(
        disabledHashes: {...existing.disabledHashes, ...add},
        nodeWarnings: {...existing.nodeWarnings, ...addW},

        name: sub.label.isNotEmpty ? sub.label : null,
        tagPrefix: sub.tagPrefix,
        updateIntervalHours: sub.updateIntervalHours ??
            (sub.fullSettings ? _defaultUpdateIntervalHours : null),
        enabled: sub.enabled,



        identity: sub.identity,
        clearIdentity: sub.identity == null,



        detourPolicy: sub.detourPolicy?.copyWith(
            overrideDetour: existing.detourPolicy.overrideDetour),
        importRules: sub.importRules,
        importRulesEnabled: sub.importRulesEnabled,
        onUpdateAction: sub.onUpdateAction,


        replace: sub.replace,
        clearReplace: sub.fullSettings && sub.replace == null,
      );
      if (sub.id.isNotEmpty) ids[sub.id] = existing.id;
      if (sub.fullSettings) detours[existing.id] = sub.detour;
      applied++;
      continue;
    }

    merged.add(SubscriptionServers(
      id: _adoptSourceId(sub.id, takenIds),
      name: sub.label,
      enabled: sub.enabled,
      tagPrefix: sub.tagPrefix,
      detourPolicy: sub.detourPolicy ?? DetourPolicy.defaults,
      url: sub.url,
      updateIntervalHours:
          sub.updateIntervalHours ?? _defaultUpdateIntervalHours,



      identity: sub.identity,
      disabledHashes: {
        for (final e in sub.disabled.entries) e.key: at(e.value),
      },
      nodeWarnings: sub.nodeWarnings,
      importRules: sub.importRules ?? const [],
      importRulesEnabled: sub.importRulesEnabled ?? true,
      onUpdateAction: sub.onUpdateAction ?? SubscriptionOnUpdateAction.rebuild,
      replace: sub.replace,
    ));
    byUrl[sub.url] = merged.length - 1;
    if (sub.id.isNotEmpty) ids[sub.id] = merged.last.id;
    if (sub.detour != null) detours[merged.last.id] = sub.detour;
    added[merged.last.id] = sub.position;
    applied++;
  }

  return (
    lists: merged,
    byUrl: byUrl,
    applied: applied,
    ids: ids,
    added: added,
    detours: detours,
  );
}


const int _defaultUpdateIntervalHours = 24;



typedef BackupNodeRef = ({int list, int member});


typedef BackupServerMerge = ({


  List<ServerList> lists,



  Map<String, int> added,


  int applied,





  Map<String, String> folderIds,



  List<BackupNodeRef> touched,






  BackupLinkMapper linkOf,
});


typedef BackupLinkMapper = NodeLink Function(NodeLink link, {bool legacy});




























String canonicalNodeBody(String body) {
  final t = body.trim();
  if (t.startsWith('{')) {
    final map = _tryDecodeObject(t);
    if (map != null) {
      final stripped = Map<String, dynamic>.from(map)
        ..remove('tag')
        ..remove('detour');
      return jsonEncode(deepSortKeys(stripped));
    }
    return t;
  }
  if (t.contains('\n')) return t;
  final hash = t.indexOf('#');
  return hash < 0 ? t : t.substring(0, hash).trim();
}



























BackupServerMerge mergeBackupServers(
  List<ServerList> lists,
  List<LxServer> incoming, {
  List<LxFolder> folders = const [],
  Map<String, String> sourceIds = const {},
  Map<String, int> addedSources = const {},
  Map<String, NodeLink?> sourceDetours = const {},
  Set<String> rootNames = const {},
}) {
  final merged = lists.toList();
  final takenIds = <String>{for (final l in merged) l.id};
  var applied = 0;
  final touched = <BackupNodeRef>[];


  final added = <String, int>{...addedSources};



  final folderById = <String, int>{};
  final folderByName = <String, int>{};
  for (var i = 0; i < merged.length; i++) {
    final l = merged[i];
    if (l is! FolderServers) continue;
    folderById.putIfAbsent(l.id, () => i);
    folderByName.putIfAbsent(l.name, () => i);
  }




  final folderIds = <String, String>{};
  final matchedAt = <String, int>{};
  final plannedId = <String, String>{};
  final freshNames = <String>{};
  for (final f in folders) {
    int? at;
    if (f.id.isNotEmpty) at = folderById[f.id];
    if (at == null && !freshNames.contains(f.name)) at = folderByName[f.name];
    final String localId;
    if (at != null) {
      matchedAt[f.key] = at;
      localId = merged[at].id;
    } else {
      localId = _adoptSourceId(f.id, takenIds);
      plannedId[f.key] = localId;
      if (!folderByName.containsKey(f.name)) {
        folderByName[f.name] = -1;
        freshNames.add(f.name);
      }
    }
    if (f.id.isNotEmpty) folderIds[f.id] = localId;
  }


  final linkIds = {...sourceIds, ...folderIds};





  final pendingLinks =
      <({int at, int member, NodeLink? link, bool count})>[];
  for (var i = 0; i < merged.length; i++) {
    final l = merged[i];
    if (l is! SubscriptionServers || !sourceDetours.containsKey(l.id)) continue;
    pendingLinks
        .add((at: i, member: -1, link: sourceDetours[l.id], count: false));
  }

  final singleBodies = <String, int>{};
  for (var i = 0; i < merged.length; i++) {
    final l = merged[i];
    if (l is UserServer) {
      singleBodies.putIfAbsent(canonicalNodeBody(l.rawBody), () => i);
    }
  }


  final folderPosition = {for (final f in folders) f.key: f.position};
  final events = <(int, int, int, Object)>[
    for (var i = 0; i < folders.length; i++)
      (folders[i].position, 0, i, folders[i]),
    for (var i = 0; i < incoming.length; i++)
      (
        incoming[i].folderRef.isNotEmpty
            ? (folderPosition[incoming[i].folderRef] ?? incoming[i].position)
            : incoming[i].position,
        1,
        i,
        incoming[i],
      ),
  ]..sort((a, b) {
      if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
      if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
      return a.$3.compareTo(b.$3);
    });

  final folderAtKey = <String, int>{};


  final landings = <(int, String), String>{};
  final autoGroups = <_BackupAutoGroup>[];
  for (final (position, _, _, item) in events) {
    if (item is LxFolder) {
      final at = matchedAt[item.key];
      if (at != null) {
        final local = merged[at] as FolderServers;
        final policy = (item.detourPolicy ?? local.detourPolicy)
            .copyWith(overrideDetour: local.detourPolicy.overrideDetour);
        final pingUrl = item.pingUrl ?? local.pingUrl;
        final pingTimeoutMs = item.pingTimeoutMs ?? local.pingTimeoutMs;
        final changed = local.enabled != item.enabled ||
            local.tagPrefix != item.tagPrefix ||
            local.detourPolicy != policy ||
            local.pingUrl != pingUrl ||
            local.pingTimeoutMs != pingTimeoutMs ||
            local.replace != item.replace;
        if (changed) {
          merged[at] = local.copyWith(
            enabled: item.enabled,
            tagPrefix: item.tagPrefix,
            detourPolicy: policy,
            pingUrl: pingUrl,
            pingTimeoutMs: pingTimeoutMs,

            replace: item.replace,
            clearReplace: item.replace == null,
          );
          applied++;
        }
        pendingLinks
            .add((at: at, member: -1, link: item.detour, count: !changed));
        folderAtKey[item.key] = at;
      } else {
        merged.add(FolderServers(
          id: plannedId[item.key]!,
          name: item.name,
          enabled: item.enabled,
          tagPrefix: item.tagPrefix,
          detourPolicy: item.detourPolicy ?? DetourPolicy.defaults,
          pingUrl: item.pingUrl,
          pingTimeoutMs: item.pingTimeoutMs,
          replace: item.replace,
        ));
        pendingLinks.add((
          at: merged.length - 1,
          member: -1,
          link: item.detour,
          count: false,
        ));
        folderAtKey[item.key] = merged.length - 1;
        if (folderByName[item.name] == -1) {
          folderByName[item.name] = merged.length - 1;
        }
        added[merged.last.id] = position;
        applied++;
      }
      continue;
    }

    final srv = item as LxServer;
    if (srv.autoGroup != null) {
      final at = srv.folderRef.isNotEmpty
          ? folderAtKey[srv.folderRef]
          : _folder0xAt(merged, srv, folderByName, takenIds, added, position);
      if (at == null) continue;
      applied += _mergeFolderAutoGroup(merged, at, srv, autoGroups);
      continue;
    }
    final body = srv.uri.isNotEmpty
        ? srv.uri
        : (srv.configJson == null ? '' : jsonEncode(srv.configJson));
    if (body.isEmpty) continue;

    if (srv.folderRef.isNotEmpty) {

      final at = folderAtKey[srv.folderRef];
      if (at == null) continue;
      final count = (merged[at] as FolderServers).members.length;
      applied += _mergeFolderMember(
          merged, at, srv, body, NodeLink.none, touched,
          landings: landings);
      if ((merged[at] as FolderServers).members.length > count) {
        pendingLinks
            .add((at: at, member: count, link: srv.detour, count: false));
      }
      continue;
    }

    if (srv.folder.isEmpty) {
      final key = canonicalNodeBody(body);
      final hit = singleBodies[key];
      if (hit != null) {
        final local = merged[hit] as UserServer;


        final flags = srv.detourPolicy
            ?.copyWith(overrideDetour: local.detourPolicy.overrideDetour);
        final side = (flags != null && flags != local.detourPolicy) ||
            (srv.tagPrefix != null && srv.tagPrefix != local.tagPrefix);
        final skip = srv.skipPresets && !local.skipPresets;
        if (side || skip) {
          merged[hit] = local.copyWith(
            detourPolicy: flags,
            tagPrefix: srv.tagPrefix,
            skipPresets: skip ? true : null,
          );
          applied++;
        }
        touched.add((list: hit, member: -1));
        continue;
      }
      merged.add(UserServer(
        id: _adoptSourceId(srv.id, takenIds),
        name: srv.name,
        enabled: srv.enabled,
        tagPrefix: srv.tagPrefix ?? '',
        detourPolicy: srv.detourPolicy ?? DetourPolicy.defaults,
        origin: UserSource.manual,
        rawBody: body,

        warnings: srv.warnings,
        skipPresets: srv.skipPresets,
      ));
      pendingLinks.add((
        at: merged.length - 1,
        member: -1,
        link: srv.detour,
        count: false,
      ));
      singleBodies[key] = merged.length - 1;
      touched.add((list: merged.length - 1, member: -1));
      added[merged.last.id] = position;
      applied++;
      continue;
    }


    final at =
        _folder0xAt(merged, srv, folderByName, takenIds, added, position);
    applied += _mergeFolderMember(merged, at, srv, body, NodeLink.none, touched,
        landings: landings);
  }

  applied += _bindBackupAutoGroups(merged, autoGroups, linkIds, landings);

  final linkOf = _backupLinkMapper(
    merged: merged,
    incoming: incoming,
    folders: folders,
    folderAtKey: folderAtKey,
    folderByName: folderByName,
    ids: linkIds,
    landings: landings,
    rootNames: rootNames,
  );
  for (final p in pendingLinks) {
    final l = merged[p.at];
    final link = p.link == null ? NodeLink.none : linkOf(p.link!, at: p.at);
    if (p.member < 0) {
      if (l.detourPolicy.overrideDetour == link) continue;
      final policy = l.detourPolicy.copyWith(overrideDetour: link);
      merged[p.at] = switch (l) {
        SubscriptionServers s => s.copyWith(detourPolicy: policy),
        UserServer u => u.copyWith(detourPolicy: policy),
        FolderServers f => f.copyWith(detourPolicy: policy),
      };
      if (p.count) applied++;
    } else if (l is FolderServers && p.member < l.members.length) {
      if (l.members[p.member].detour == link) continue;
      merged[p.at] = l.copyWith(
        members: l.members.toList()
          ..[p.member] = l.members[p.member].copyWith(detour: link),
      );
    }
  }



  final firstNew = merged.indexWhere((l) => added.containsKey(l.id));
  if (firstNew >= 0) {
    final order = [for (var i = firstNew; i < merged.length; i++) i]
      ..sort((a, b) {
        final byPos = added[merged[a].id]!.compareTo(added[merged[b].id]!);
        return byPos != 0 ? byPos : a.compareTo(b);
      });
    final remap = <int, int>{
      for (var k = 0; k < order.length; k++) order[k]: firstNew + k,
    };
    final tail = [for (final i in order) merged[i]];
    merged.replaceRange(firstNew, merged.length, tail);
    for (var t = 0; t < touched.length; t++) {
      final moved = remap[touched[t].list];
      if (moved != null) touched[t] = (list: moved, member: touched[t].member);
    }
  }

  return (
    lists: merged,
    added: added,
    applied: applied,
    folderIds: linkIds,
    touched: touched,
    linkOf: (NodeLink link, {bool legacy = false}) =>
        linkOf(link, legacy: legacy),
  );
}
















NodeLink Function(NodeLink link, {int? at, bool legacy}) _backupLinkMapper({
  required List<ServerList> merged,
  required List<LxServer> incoming,
  required List<LxFolder> folders,
  required Map<String, int> folderAtKey,
  required Map<String, int> folderByName,
  required Map<String, String> ids,
  required Map<(int, String), String> landings,
  required Set<String> rootNames,
}) {
  final atByFileId = <String, int>{
    for (final f in folders)
      if (f.id.isNotEmpty && folderAtKey[f.key] != null)
        f.id: folderAtKey[f.key]!,
  };
  final folderByKey = {for (final f in folders) f.key: f};


  final rootTaken = <String>{...rootNames, ...lxImportRootNodeTags(merged)};


  final fileFinal = <String, Set<NodeLink>>{};
  final fileRaw = <String, Set<NodeLink>>{};
  final fileRawAt = <int, Set<String>>{};
  void addFile(int at, String prefix, String name) {
    if (name.isEmpty || at < 0 || at >= merged.length) return;
    final here =
        NodeLink(folderId: merged[at].id, tag: landings[(at, name)] ?? name);
    for (final form in _fileFinalForms(prefix, name)) {
      (fileFinal[form] ??= {}).add(here);
    }
    (fileRaw[name] ??= {}).add(here);
    (fileRawAt[at] ??= {}).add(name);
  }

  for (final srv in incoming) {
    final name = srv.autoGroup?.tag ?? srv.name;
    if (srv.folderRef.isNotEmpty) {
      final f = folderByKey[srv.folderRef];
      final at = folderAtKey[srv.folderRef];
      if (f != null && at != null) addFile(at, f.tagPrefix, name);
    } else if (srv.folder.isNotEmpty) {
      final at = folderByName[srv.folder];
      if (at != null) addFile(at, '', name);
    }
  }


  final hereFinal = <String, Set<NodeLink>>{};
  final hereRaw = <String, Set<NodeLink>>{};
  for (final l in merged) {
    if (l is UserServer) continue;
    containerRawTags(l).forEach((_, raw) {
      final here = NodeLink(folderId: l.id, tag: raw);
      (hereFinal[containerFinalForm(l, raw)] ??= {}).add(here);
      (hereRaw[raw] ??= {}).add(here);
    });
  }

  return (NodeLink link, {int? at, bool legacy = false}) {
    if (link.isEmpty) return link;
    if (!link.isRoot) {
      final fileAt = atByFileId[link.folderId];
      if (fileAt != null) {
        final folder = merged[fileAt];
        final landed = landings[(fileAt, link.tag)];
        if (landed != null) return NodeLink(folderId: folder.id, tag: landed);
        final raw = containerRawTags(folder);
        final groupForms = <String, List<String>>{};
        raw.forEach((node, tag) {
          if (node.isGroup) {
            for (final form in _fileFinalForms(folder.tagPrefix, tag)) {
              (groupForms[form] ??= []).add(tag);
            }
          }
        });
        return lowerGroupFinalLink(
          NodeLink(folderId: folder.id, tag: link.tag),
          folder.id,
          raw.values.toSet(),
          groupForms,
        );
      }
      final local = ids[link.folderId];
      return local == null ? link : NodeLink(folderId: local, tag: link.tag);
    }
    final t = link.tag;
    if (rootTaken.contains(t)) return link;

    if (at != null && at >= 0 && at < merged.length) {
      final carrier = merged[at];
      if (carrier is FolderServers) {
        if (fileRawAt[at]?.contains(t) ?? false) {
          return NodeLink(
              folderId: carrier.id, tag: landings[(at, t)] ?? t);
        }
        final lifted =
            liftSiblingLink(link, carrier.id, containerRawTagSet(carrier));
        if (!lifted.isRoot) return lifted;
      }
    }
    Set<NodeLink> hits(
      Map<String, Set<NodeLink>> byFinal,
      Map<String, Set<NodeLink>> byRaw,
    ) =>
        {...?byFinal[t], if (legacy) ...?byRaw[t]};
    final fromFile = hits(fileFinal, fileRaw);
    if (fromFile.isNotEmpty) {
      return fromFile.length == 1 ? fromFile.single : link;
    }
    final fromHere = hits(hereFinal, hereRaw);
    return fromHere.length == 1 ? fromHere.single : link;
  };
}


List<NodeSpec> _nodesOf(String raw) {
  if (raw.trim().isEmpty) return const [];
  try {
    return parseAll(decode(raw), own: true);
  } catch (_) {
    return const [];
  }
}






Set<String> _fileFinalForms(String prefix, String raw) => {
      TagResolver.displayTag(prefix, raw),
      if (prefix.isNotEmpty) '$prefix$raw',
    };



int _mergeFolderMember(
  List<ServerList> merged,
  int folderAt,
  LxServer srv,
  String body,
  NodeLink detour,
  List<BackupNodeRef> touched, {
  Map<(int, String), String>? landings,
}) {
  final folder = merged[folderAt] as FolderServers;
  final canon = canonicalNodeBody(body);
  final hit = folder.members.indexWhere((m) => canonicalNodeBody(m.raw) == canon);
  if (hit >= 0) {
    final here = folder.members[hit].node?.tag ?? '';
    if (srv.name.isNotEmpty && here.isNotEmpty) {
      landings?[(folderAt, srv.name)] = here;
    }
    touched.add((list: folderAt, member: hit));

    final skip = srv.skipPresets && !folder.members[hit].skipPresets;
    if (!skip) return 0;
    final members = folder.members.toList();
    members[hit] = members[hit].copyWith(skipPresets: true);
    merged[folderAt] = folder.copyWith(members: members);
    return 1;
  }
  final member = FolderMember(
    raw: body,
    enabled: srv.enabled,

    warnings: srv.warnings,
    detour: detour,
    skipPresets: srv.skipPresets,
  );
  final here = member.node?.tag ?? '';
  if (srv.name.isNotEmpty && here.isNotEmpty) {
    landings?[(folderAt, srv.name)] = here;
  }
  merged[folderAt] = folder.copyWith(members: [...folder.members, member]);
  touched.add((list: folderAt, member: folder.members.length));
  return 1;
}



int _folder0xAt(
  List<ServerList> merged,
  LxServer srv,
  Map<String, int> folderByName,
  Set<String> takenIds,
  Map<String, int> added,
  int position,
) {
  final at = folderByName[srv.folder];
  if (at != null && at >= 0) return at;
  merged.add(FolderServers(
    id: _adoptSourceId('', takenIds),
    name: srv.folder,
    enabled: true,
    tagPrefix: '',
    detourPolicy: DetourPolicy.defaults,
  ));
  folderByName[srv.folder] = merged.length - 1;
  added[merged.last.id] = position;
  return merged.length - 1;
}


typedef _BackupAutoGroup = ({
  int folderAt,
  int member,
  LxServer srv,
  bool fresh,
});





int _mergeFolderAutoGroup(
  List<ServerList> merged,
  int folderAt,
  LxServer srv,
  List<_BackupAutoGroup> pending,
) {
  final folder = merged[folderAt] as FolderServers;
  final group = srv.autoGroup!;
  final hit = folder.members.indexWhere(
      (m) => m.node is AutoSelectSpec && m.node!.tag == group.tag);
  if (hit >= 0) {
    pending.add((folderAt: folderAt, member: hit, srv: srv, fresh: false));
    return 0;
  }
  merged[folderAt] = folder.copyWith(members: [
    ...folder.members,
    FolderMember.auto(group, enabled: srv.enabled, warnings: srv.warnings),
  ]);
  pending.add((
    folderAt: folderAt,
    member: folder.members.length,
    srv: srv,
    fresh: true,
  ));
  return 1;
}






int _bindBackupAutoGroups(
  List<ServerList> merged,
  List<_BackupAutoGroup> pending,
  Map<String, String> ids,
  Map<(int, String), String> landings,
) {
  var applied = 0;
  for (final p in pending) {
    final folder = merged[p.folderAt] as FolderServers;
    var group = p.srv.autoGroup!;
    final membership = group.membership;
    if (membership is ExplicitMembers) {
      group = group.copyWith(
        membership: ExplicitMembers([
          for (final l in membership.members)
            if (l.isRoot || l.folderId == p.srv.folderRef)
              NodeLink(
                folderId: folder.id,
                tag: landings[(p.folderAt, l.tag)] ?? l.tag,
              )
            else
              NodeLink(folderId: ids[l.folderId] ?? l.folderId, tag: l.tag),
        ]),
      );
    }
    final member = FolderMember.auto(group,
        enabled: p.srv.enabled, warnings: p.srv.warnings);
    if (folder.members[p.member] == member) continue;
    merged[p.folderAt] = folder.copyWith(
      members: folder.members.toList()..[p.member] = member,
    );
    if (!p.fresh) applied++;
  }
  return applied;
}











List<SourceChain> resolveBackupChainHops(
  LxBackupFile file,
  List<ServerList> lists,
  Map<String, String> folderIds, {
  BackupLinkMapper? linkOf,
}) {
  NodeLink map(NodeLink link, {required bool legacy}) => linkOf != null
      ? linkOf(link, legacy: legacy)
      : _remapLink(link, folderIds);

  return [
    for (final c in file.chains)
      if (file.chainHops[c.tag] case final links?)
        c.copyWith(hops: [for (final l in links) map(l, legacy: false)])
      else if (linkOf != null)
        c.copyWith(hops: [for (final l in c.hops) map(l, legacy: true)])
      else
        c,
  ];
}


NodeLink _remapLink(NodeLink link, Map<String, String> ids) {
  if (link.isRoot) return link;
  final local = ids[link.folderId];
  return local == null ? link : NodeLink(folderId: local, tag: link.tag);
}































List<CustomRule> renumberBackupAxis(List<CustomRule> rules) {
  if (rules.every((r) => r.orderNum == null)) return rules;

  var last = -1;
  void see(int? n) {
    if (n != null && n > last) last = n;
  }

  for (final r in rules) {
    see(r.orderNum);
  }
  var next = last + 1 < kUserRuleNumStart ? kUserRuleNumStart : last + 1;
  for (final r in rules) {
    r.orderNum ??= next++;
  }
  return sortRulesByAxis(rules);
}
