



















library;

import '../models/custom_rule.dart';
import '../models/direction.dart';
import '../models/parser_config.dart';
import '../models/server_list.dart';
import '../models/source_chain.dart';
import 'builder/rule_order.dart' show pinRequiredRuleNums;
import 'direction_mutations.dart';
import 'dns/dns_backup.dart';
import 'lx_backup.dart';
import 'record_vars.dart';
import 'settings_storage.dart';
import 'template_loader.dart';
import 'warp/warp_backup.dart';


class LxImportReceiver {
  const LxImportReceiver({
    this.lists = const [],
    this.directions = const [],
    this.chains = const [],
    this.systemTags = const {},
    this.selectableRules = const [],
    this.receiverTargets = const {},
    this.dns = const LxDns(),
    this.recordVars = RecordVarDecls.none,
  });


  final List<ServerList> lists;


  final List<Direction> directions;


  final List<SourceChain> chains;



  final Set<String> systemTags;




  final List<SelectableRule> selectableRules;




  final Set<String> receiverTargets;



  final LxDns dns;



  final RecordVarDecls recordVars;
}


class LxImportPlan {
  const LxImportPlan({
    required this.raw,
    required this.file,
    required this.knownTargets,
    required this.directions,
    required this.appliedDirections,
    required this.directionPing,
    required this.listsBefore,
    required this.lists,
    required this.appliedSources,
    required this.touched,
    required this.chains,
    required this.appliedChains,
    required this.rules,
    this.dns,
    this.sourceOrder = const [],
  });


  final String raw;



  final LxBackupFile file;


  final Set<String>? knownTargets;


  final List<Direction> directions;


  final int appliedDirections;


  final Map<String, LxDirectionPing> directionPing;


  final List<ServerList> listsBefore;


  final List<ServerList> lists;


  final int appliedSources;


  final List<BackupNodeRef> touched;


  final List<SourceChain> chains;


  final int appliedChains;


  final List<CustomRule> rules;


  final DnsBackupApply? dns;





  final List<String> sourceOrder;
}


typedef LxImportResult = ({
  LxBackupFile file,
  int appliedDirections,
  int appliedChains,
  int appliedSettings,
});



Set<String> templateSystemTags(WizardTemplate template) {
  final tags = <String>{};
  void addTags(Object? list) {
    if (list is! List) return;
    for (final o in list) {
      final tag = o is Map ? o['tag'] : null;
      if (tag is String && tag.trim().isNotEmpty) tags.add(tag.trim());
    }
  }

  addTags(template.config['outbounds']);
  addTags(template.config['endpoints']);
  for (final node in template.groupTemplates.magicNodes.values) {
    final tag = node.tag;
    if (tag != null && tag.trim().isNotEmpty) tags.add(tag.trim());
  }
  return tags;
}









LxImportPlan planLxBackupImport(String raw, LxImportReceiver receiver) {
  final chainTagsBefore = {for (final c in receiver.chains) c.tag};
  final decoded = decodeLxBackup(
    raw,
    takenTags: {
      ...receiver.receiverTargets,
      for (final d in receiver.directions) d.tag,
      ...chainTagsBefore,
    }..removeWhere((t) => t.isEmpty),
    knownPresets: {for (final p in receiver.selectableRules) p.presetId},
    recordVars: receiver.recordVars,



    knownChains: chainTagsBefore,
  );








  final directions = receiver.directions.toList();
  final usedDirectionTags = [
    for (final d in directions) d.tag,


    ...sourceReplaceNames(receiver.lists),
    for (final s in decoded.subscriptions) ...?s.replace?.names,
    for (final f in decoded.folders) ...?f.replace?.names,
  ];
  final directionPing = <String, LxDirectionPing>{};
  var appliedDirections = 0;
  for (final d in decoded.directions) {
    if (directionTagConflict(d.tag, usedDirectionTags) != null) continue;
    directions.add(d);
    usedDirectionTags.add(d.tag);
    appliedDirections++;

    final ping = decoded.directionPing[d.tag];
    if (ping != null) directionPing[d.tag] = ping;
  }





  final usedChainTags = <String>[
    ...chainTagsBefore,
    ...usedDirectionTags,
  ];
  final acceptedChainTags = <String>{};
  for (final c in decoded.chains) {
    if (directionTagConflict(c.tag, usedChainTags) != null) continue;
    usedChainTags.add(c.tag);
    acceptedChainTags.add(c.tag);
  }
  final chainTags = {...chainTagsBefore, ...acceptedChainTags};



  final subMerge = mergeBackupSubscriptions(receiver.lists, decoded.subscriptions);
  final srvMerge = mergeBackupServers(
    subMerge.lists,
    decoded.servers,
    folders: decoded.folders,
    sourceIds: subMerge.ids,
    addedSources: subMerge.added,
    sourceDetours: subMerge.detours,
    rootNames: lxImportRootNames(
      directions: directions,
      chainTags: chainTags,
      systemTags: receiver.systemTags,

      replaceTags: [
        ...sourceReplaceNames(subMerge.lists),
        for (final f in decoded.folders) ...?f.replace?.names,
      ],
    ),
  );


  final known = lxImportKnownTargets(
    directions: directions,
    chainTags: chainTags,
    lists: srvMerge.lists,
    systemTags: receiver.systemTags,
    receiverTargets: receiver.receiverTargets,
  );
  var file = gateLxBackupTargets(decoded, known);

  final incomingChains = resolveBackupChainHops(
    file,
    srvMerge.lists,
    srvMerge.folderIds,
    linkOf: srvMerge.linkOf,
  );
  final chains = [
    ...receiver.chains,
    for (final c in incomingChains)
      if (acceptedChainTags.contains(c.tag)) c,
  ];



  var rules = renumberBackupAxis(file.rules);


  if (pinRequiredRuleNums(rules, receiver.selectableRules)) {
    rules = sortRulesByAxis(rules);
  }





  final extraWarnings = <LxBackupWarning>[];
  rules = normalizePresetRulesVars(
    rules,
    receiver.recordVars,
    onUndeclared: (presetId, name) => extraWarnings.add(LxBackupWarning(
        kWarnVarSkipped, 'preset:$presetId.vars.$name',
        reason: kVarSkippedUndeclared)),
  );










  final incomingDns = file.dns;
  final dns = incomingDns == null || incomingDns.isEmpty
      ? null
      : applyDnsBackup(
          incoming: incomingDns,
          servers: normalizeDnsServersVars(
              receiver.dns.servers, receiver.recordVars),
          rules: receiver.dns.rules,
          dnsFinal: receiver.dns.finalServer,
          strategy: receiver.dns.strategy,
          defaultDomainResolver: receiver.dns.defaultDomainResolver,
          recordVars: receiver.recordVars,
          knownTargets: known,
          warnings: extraWarnings,
        );
  if (extraWarnings.isNotEmpty) {
    file = file.copyWith(warnings: [...file.warnings, ...extraWarnings]);
  }

  return LxImportPlan(
    raw: raw,
    file: file,
    knownTargets: known,
    directions: directions,
    appliedDirections: appliedDirections,
    directionPing: directionPing,
    listsBefore: receiver.lists,
    lists: srvMerge.lists,
    appliedSources: subMerge.applied + srvMerge.applied,
    touched: srvMerge.touched,
    chains: chains,
    appliedChains: incomingChains
        .where((c) => acceptedChainTags.contains(c.tag))
        .length,
    rules: rules,
    dns: dns,
    sourceOrder: _importedSourceOrder(
      srvMerge.added,
      decoded.chainPositions,
      acceptedChainTags,
    ),
  );
}


List<String> _importedSourceOrder(
  Map<String, int> addedLists,
  Map<String, int> chainPositions,
  Set<String> acceptedChains,
) {
  final placed = <(int, String)>[
    for (final e in addedLists.entries)
      (e.value, SettingsStorage.sourceKeyForId(e.key)),
    for (final e in chainPositions.entries)
      if (acceptedChains.contains(e.key))
        (e.value, SettingsStorage.sourceKeyForChain(e.key)),
  ]..sort((a, b) {
      final byPos = a.$1.compareTo(b.$1);
      return byPos != 0 ? byPos : a.$2.compareTo(b.$2);
    });
  return [for (final (_, key) in placed) key];
}






class LxBackupImportService {
  const LxBackupImportService();


  Future<LxImportReceiver> loadReceiver() async {
    final template = await TemplateLoader.load();
    final vars = await SettingsStorage.getAllVars();
    return LxImportReceiver(
      lists: await SettingsStorage.getServerLists(),
      directions: await SettingsStorage.getDirections(),
      chains: await SettingsStorage.getChains(),
      systemTags: templateSystemTags(template),
      selectableRules: template.selectableRules,
      dns: LxDns(
        servers: await SettingsStorage.getDnsServers(),
        rules: await SettingsStorage.getDnsRulesList(),
        finalServer: vars['dns_final'] ?? '',
        strategy: vars['dns_strategy'] ?? '',
        defaultDomainResolver: vars['dns_default_domain_resolver'] ?? '',
      ),
      recordVars: RecordVarDecls.fromTemplate(template),
    );
  }


  Future<LxImportPlan> prepare(String raw) async =>
      planLxBackupImport(raw, await loadReceiver());




  Future<LxImportResult> apply(LxImportPlan preview) async {
    final plan = planLxBackupImport(preview.raw, await loadReceiver());
    final file = plan.file;

    if (plan.appliedDirections > 0) {
      await DirectionMutations.bulkReplace(plan.directions);
    }


    for (final entry in plan.directionPing.entries) {
      await SettingsStorage.setGroupPing(
        entry.key,
        url: entry.value.url,
        timeoutMs: entry.value.timeoutMs,
      );
    }
    if (plan.appliedChains > 0) await SettingsStorage.setChains(plan.chains);
    await SettingsStorage.saveCustomRules(plan.rules);

    final settings = await _applySections(plan);
    await _placeImportedSources(plan.sourceOrder);
    return (
      file: file,
      appliedDirections: plan.appliedDirections,
      appliedChains: plan.appliedChains,
      appliedSettings: settings,
    );
  }





  Future<void> _placeImportedSources(List<String> order) async {
    if (order.length < 2) return;
    final present = (await SettingsStorage.getSourceKeys()).toSet();
    final keys = [
      for (final k in order)
        if (present.contains(k)) k,
    ];
    if (keys.length < 2) return;
    await SettingsStorage.reorderSources(keys);
  }





  Future<int> _applySections(LxImportPlan plan) async {
    final file = plan.file;
    var applied = 0;


    for (final e in file.vars.entries) {
      await SettingsStorage.setVar(e.key, e.value, flush: false);
      applied++;
    }


    final routeFinal = file.routeFinal;
    if (routeFinal != null && routeFinal.isNotEmpty) {
      await SettingsStorage.saveRouteFinal(routeFinal, flush: false);
      applied++;
    }




    final before = plan.listsBefore;
    final merged = plan.lists;
    applied += plan.appliedSources;
    final listsChanged = merged.length != before.length ||
        plan.touched.isNotEmpty ||
        [
          for (var i = 0; i < before.length; i++)
            if (!identical(merged[i], before[i])) i,
        ].isNotEmpty;
    if (listsChanged) await SettingsStorage.saveServerLists(merged);




    final result = plan.dns;
    if (result != null) {
      await SettingsStorage.saveDnsServers(result.servers, flush: false);
      await SettingsStorage.saveDnsRulesList(result.rules, flush: false);
      await SettingsStorage.setVar('dns_final', result.dnsFinal, flush: false);
      await SettingsStorage.setVar('dns_strategy', result.strategy,
          flush: false);

      if (result.defaultDomainResolver.isNotEmpty) {
        await SettingsStorage.setVar(
            'dns_default_domain_resolver', result.defaultDomainResolver,
            flush: false);
      }
      applied += result.applied;
    }


    for (final entry in file.warp) {
      if (entry['type'] == 'wg') {
        if (await SettingsStorage.getWarpAccount() != null) continue;
        final acc = warpAccountFromBackup(entry);
        if (acc == null) continue;
        await SettingsStorage.setWarpAccount(acc, flush: false);
        applied++;
      } else if (entry['type'] == 'masque') {
        if (await SettingsStorage.getMasqueAccount() != null) continue;
        final acc = masqueAccountFromBackup(entry);
        if (acc == null) continue;
        await SettingsStorage.setMasqueAccount(acc, flush: false);
        applied++;
      }
    }

    await SettingsStorage.flushToDisk();
    return applied;
  }
}
