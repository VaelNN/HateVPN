import 'package:collection/collection.dart';

import '../services/parser/body_decoder.dart';
import '../services/parser/parse_all.dart';
import 'core_reject_verdict.dart';
import 'import_rule.dart';
import 'node_link.dart';
import 'node_spec.dart';
import 'node_warning.dart';
import 'source_replace.dart';
import 'subscription_meta.dart';





sealed class ServerList {
  final String id;
  final String name;
  final bool enabled;
  final String tagPrefix;
  final DetourPolicy detourPolicy;
  final List<NodeSpec> nodes;

  ServerList({
    required this.id,
    required this.name,
    required this.enabled,
    required this.tagPrefix,
    required this.detourPolicy,
    List<NodeSpec>? nodes,
  }) : nodes = nodes ?? <NodeSpec>[];

  String get type;



  SourceReplace? get replace => null;
}






List<String> sourceReplaceNames(Iterable<ServerList> lists) => [
      for (final l in lists)
        if (l.replace case final r?) ...r.names,
    ];


enum UpdateStatus { never, ok, failed, inProgress }









enum SubscriptionOnUpdateAction {



  rebuild,




  reload,



  none;

  static SubscriptionOnUpdateAction fromJson(dynamic raw) =>
      SubscriptionOnUpdateAction.values.firstWhere(
        (a) => a.name == raw,
        orElse: () => SubscriptionOnUpdateAction.rebuild,
      );
}









class SubscriptionIdentityOverride {


  final String userAgent;


  final bool sendHwid;


  final String hwid;


  final String deviceOs;
  final String verOs;
  final String deviceModel;

  const SubscriptionIdentityOverride({
    this.userAgent = '',
    this.sendHwid = false,
    this.hwid = '',
    this.deviceOs = '',
    this.verOs = '',
    this.deviceModel = '',
  });

  Map<String, dynamic> toJson() => {
        if (userAgent.isNotEmpty) 'user_agent': userAgent,
        'send_hwid': sendHwid,
        if (hwid.isNotEmpty) 'hwid': hwid,
        if (deviceOs.isNotEmpty) 'device_os': deviceOs,
        if (verOs.isNotEmpty) 'ver_os': verOs,
        if (deviceModel.isNotEmpty) 'device_model': deviceModel,
      };

  SubscriptionIdentityOverride copyWith({
    String? userAgent,
    bool? sendHwid,
    String? hwid,
    String? deviceOs,
    String? verOs,
    String? deviceModel,
  }) =>
      SubscriptionIdentityOverride(
        userAgent: userAgent ?? this.userAgent,
        sendHwid: sendHwid ?? this.sendHwid,
        hwid: hwid ?? this.hwid,
        deviceOs: deviceOs ?? this.deviceOs,
        verOs: verOs ?? this.verOs,
        deviceModel: deviceModel ?? this.deviceModel,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SubscriptionIdentityOverride &&
          userAgent == other.userAgent &&
          sendHwid == other.sendHwid &&
          hwid == other.hwid &&
          deviceOs == other.deviceOs &&
          verOs == other.verOs &&
          deviceModel == other.deviceModel);

  @override
  int get hashCode =>
      Object.hash(userAgent, sendHwid, hwid, deviceOs, verOs, deviceModel);
}

const _eq = DeepCollectionEquality();




Map<String, int> _disabledSeconds(Map<String, DateTime> marks) => {
      for (final e in marks.entries)
        e.key: e.value.millisecondsSinceEpoch ~/ 1000,
    };

final class SubscriptionServers extends ServerList {
  final String url;
  final SubscriptionMeta? meta;
  final DateTime? lastUpdated;
  final DateTime? lastUpdateAttempt;
  final UpdateStatus lastUpdateStatus;
  final int updateIntervalHours;
  final int lastNodeCount;




  final int consecutiveFails;








  final Map<String, DateTime> disabledHashes;









  final Map<String, List<StoredWarning>> nodeWarnings;





  final SubscriptionIdentityOverride? identity;





  final List<ImportRule> importRules;



  final bool importRulesEnabled;




  final SubscriptionOnUpdateAction onUpdateAction;







  final List<NodeWarning> dropped;


  @override
  final SourceReplace? replace;










  final Map<String, String> groupDefaults;

  SubscriptionServers({
    required super.id,
    required super.name,
    required super.enabled,
    required super.tagPrefix,
    required super.detourPolicy,
    required this.url,
    this.meta,
    this.lastUpdated,
    this.lastUpdateAttempt,
    this.lastUpdateStatus = UpdateStatus.never,
    this.updateIntervalHours = 24,
    this.lastNodeCount = 0,
    this.consecutiveFails = 0,
    this.disabledHashes = const {},
    this.nodeWarnings = const {},
    this.identity,
    this.importRules = const [],
    this.importRulesEnabled = true,
    this.onUpdateAction = SubscriptionOnUpdateAction.rebuild,
    this.dropped = const [],
    this.replace,
    this.groupDefaults = const {},
    super.nodes,
  });




  SubscriptionServers withGroupDefaultsApplied() {
    if (groupDefaults.isEmpty) return this;
    var changed = false;
    final next = <NodeSpec>[];
    for (final n in nodes) {
      final want = n is AutoSelectSpec && n.isManual ? groupDefaults[n.tag] : null;
      if (n is AutoSelectSpec && want != null && want != n.manualDefault) {
        next.add(n.copyWith(manualDefault: want));
        changed = true;
      } else {
        next.add(n);
      }
    }
    return changed ? copyWith(nodes: next) : this;
  }



  List<ImportRule> get activeImportRules =>
      importRulesEnabled ? importRules.where((r) => r.isUsable).toList() : const [];

  @override
  String get type => 'subscription';

  SubscriptionServers copyWith({
    String? name,
    bool? enabled,
    String? tagPrefix,
    DetourPolicy? detourPolicy,
    String? url,
    SubscriptionMeta? meta,
    DateTime? lastUpdated,
    DateTime? lastUpdateAttempt,
    UpdateStatus? lastUpdateStatus,
    int? updateIntervalHours,
    int? lastNodeCount,
    int? consecutiveFails,
    Map<String, DateTime>? disabledHashes,
    Map<String, List<StoredWarning>>? nodeWarnings,
    SubscriptionIdentityOverride? identity,
    bool clearIdentity = false,
    List<ImportRule>? importRules,
    bool? importRulesEnabled,
    SubscriptionOnUpdateAction? onUpdateAction,
    List<NodeSpec>? nodes,
    List<NodeWarning>? dropped,
    SourceReplace? replace,
    bool clearReplace = false,
    Map<String, String>? groupDefaults,
  }) =>
      SubscriptionServers(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        tagPrefix: tagPrefix ?? this.tagPrefix,
        detourPolicy: detourPolicy ?? this.detourPolicy,
        url: url ?? this.url,
        meta: meta ?? this.meta,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        lastUpdateAttempt: lastUpdateAttempt ?? this.lastUpdateAttempt,
        lastUpdateStatus: lastUpdateStatus ?? this.lastUpdateStatus,
        updateIntervalHours: updateIntervalHours ?? this.updateIntervalHours,
        lastNodeCount: lastNodeCount ?? this.lastNodeCount,
        consecutiveFails: consecutiveFails ?? this.consecutiveFails,
        disabledHashes: disabledHashes ?? this.disabledHashes,
        nodeWarnings: nodeWarnings ?? this.nodeWarnings,


        identity: clearIdentity ? null : (identity ?? this.identity),
        importRules: importRules ?? this.importRules,
        importRulesEnabled: importRulesEnabled ?? this.importRulesEnabled,
        onUpdateAction: onUpdateAction ?? this.onUpdateAction,
        dropped: dropped ?? this.dropped,
        replace: clearReplace ? null : (replace ?? this.replace),
        groupDefaults: groupDefaults ?? this.groupDefaults,
        nodes: nodes ?? this.nodes,
      );



  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SubscriptionServers &&
          id == other.id &&
          name == other.name &&
          enabled == other.enabled &&
          tagPrefix == other.tagPrefix &&
          detourPolicy == other.detourPolicy &&
          url == other.url &&
          meta == other.meta &&
          lastUpdated == other.lastUpdated &&
          lastUpdateAttempt == other.lastUpdateAttempt &&
          lastUpdateStatus == other.lastUpdateStatus &&
          updateIntervalHours == other.updateIntervalHours &&
          lastNodeCount == other.lastNodeCount &&
          consecutiveFails == other.consecutiveFails &&
          _eq.equals(_disabledSeconds(disabledHashes),
              _disabledSeconds(other.disabledHashes)) &&
          _eq.equals(nodeWarnings, other.nodeWarnings) &&
          identity == other.identity &&
          _eq.equals(importRules, other.importRules) &&
          importRulesEnabled == other.importRulesEnabled &&
          onUpdateAction == other.onUpdateAction &&
          replace == other.replace &&
          _eq.equals(groupDefaults, other.groupDefaults));

  @override
  int get hashCode => Object.hashAll([
        id,
        name,
        enabled,
        tagPrefix,
        detourPolicy,
        url,
        meta,
        lastUpdated,
        lastUpdateAttempt,
        lastUpdateStatus,
        updateIntervalHours,
        lastNodeCount,
        consecutiveFails,
        _eq.hash(_disabledSeconds(disabledHashes)),
        _eq.hash(nodeWarnings),
        identity,
        _eq.hash(importRules),
        importRulesEnabled,
        onUpdateAction,
        replace,
        _eq.hash(groupDefaults),
      ]);
}








enum UserSource { paste, file, qr, manual }

final class UserServer extends ServerList {


  final UserSource origin;

  final String rawBody;




  final List<StoredWarning> warnings;



  final bool skipPresets;

  UserServer({
    required super.id,
    required super.name,
    required super.enabled,
    required super.tagPrefix,
    required super.detourPolicy,
    this.origin = UserSource.manual,
    this.rawBody = '',
    this.warnings = const [],
    this.skipPresets = false,
    super.nodes,
  });

  @override
  String get type => 'user';

  UserServer copyWith({
    String? name,
    bool? enabled,
    String? tagPrefix,
    DetourPolicy? detourPolicy,
    UserSource? origin,
    String? rawBody,
    List<StoredWarning>? warnings,
    List<NodeSpec>? nodes,
    bool? skipPresets,
  }) =>
      UserServer(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        tagPrefix: tagPrefix ?? this.tagPrefix,
        detourPolicy: detourPolicy ?? this.detourPolicy,
        origin: origin ?? this.origin,
        rawBody: rawBody ?? this.rawBody,
        warnings: warnings ?? this.warnings,
        skipPresets: skipPresets ?? this.skipPresets,
        nodes: nodes ?? this.nodes,
      );



  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserServer &&
          id == other.id &&
          enabled == other.enabled &&
          tagPrefix == other.tagPrefix &&
          detourPolicy == other.detourPolicy &&
          rawBody == other.rawBody &&
          _eq.equals(warnings, other.warnings) &&
          skipPresets == other.skipPresets);

  @override
  int get hashCode => Object.hash(id, enabled, tagPrefix, detourPolicy,
      rawBody, _eq.hash(warnings), skipPresets);
}





final class FolderMember {
  final String raw;
  final bool enabled;




  final List<StoredWarning> warnings;



  final String nameHint;





  final NodeLink detour;


  final bool skipPresets;



  final NodeSpec? node;

  FolderMember({
    required this.raw,
    this.enabled = true,
    this.warnings = const [],
    this.detour = NodeLink.none,
    this.nameHint = '',
    this.skipPresets = false,
    NodeSpec? node,
  }) : node = node ?? _parseFirst(raw, nameHint);






  FolderMember.auto(AutoSelectSpec group,
      {bool enabled = true, List<StoredWarning> warnings = const []})
      : this(raw: '', enabled: enabled, node: group, warnings: warnings);

  static NodeSpec? _parseFirst(String raw, String nameHint) {
    if (raw.trim().isEmpty) return null;
    try {
      final nodes =
          parseAll(decode(raw),
          nameHint: nameHint.isEmpty ? null : nameHint, own: true);
      return nodes.isEmpty ? null : nodes.first;
    } catch (_) {
      return null;
    }
  }

  FolderMember copyWith({
    String? raw,
    bool? enabled,
    List<StoredWarning>? warnings,
    NodeLink? detour,
    String? nameHint,
    bool? skipPresets,
  }) =>
      FolderMember(
        raw: raw ?? this.raw,
        enabled: enabled ?? this.enabled,
        warnings: warnings ?? this.warnings,
        detour: detour ?? this.detour,
        nameHint: nameHint ?? this.nameHint,
        skipPresets: skipPresets ?? this.skipPresets,

        node: raw == null && nameHint == null ? node : null,
      );



  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FolderMember &&
          raw == other.raw &&
          enabled == other.enabled &&
          _eq.equals(warnings, other.warnings) &&
          detour == other.detour &&
          nameHint == other.nameHint &&
          skipPresets == other.skipPresets &&
          _sameGroup(node, other.node));

  static bool _sameGroup(NodeSpec? a, NodeSpec? b) => a is AutoSelectSpec
      ? b is AutoSelectSpec && a.sameGroupAs(b)
      : b is! AutoSelectSpec;

  @override
  int get hashCode => Object.hash(
      raw, enabled, _eq.hash(warnings), detour, nameHint, skipPresets);
}





final class FolderServers extends ServerList {
  final List<FolderMember> members;


  final DateTime createdAt;




  final String? pingUrl;
  final int? pingTimeoutMs;


  @override
  final SourceReplace? replace;

  FolderServers({
    required super.id,
    required super.name,
    required super.enabled,
    required super.tagPrefix,
    required super.detourPolicy,
    List<FolderMember>? members,
    DateTime? createdAt,
    this.pingUrl,
    this.pingTimeoutMs,
    this.replace,
  })  : members = members ?? <FolderMember>[],
        createdAt = createdAt ?? DateTime.now(),
        super(nodes: [
          for (final m in members ?? const <FolderMember>[])
            if (m.enabled && m.node != null) m.node!,
        ]);

  @override
  String get type => 'folder';





  List<String> get memberRaws => [
        for (final m in members)
          if (m.enabled && m.node != null) m.raw,
      ];

  int get disabledCount => members.where((m) => !m.enabled).length;



  List<NodeLink> get nodeDetours => [
        for (final m in members)
          if (m.enabled && m.node != null) m.detour,
      ];

  FolderServers copyWith({
    String? name,
    bool? enabled,
    String? tagPrefix,
    DetourPolicy? detourPolicy,
    List<FolderMember>? members,
    String? pingUrl,
    int? pingTimeoutMs,
    bool clearPing = false,
    SourceReplace? replace,
    bool clearReplace = false,
  }) =>
      FolderServers(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        tagPrefix: tagPrefix ?? this.tagPrefix,
        detourPolicy: detourPolicy ?? this.detourPolicy,
        createdAt: createdAt,
        members: members ?? this.members,
        pingUrl: clearPing ? null : (pingUrl ?? this.pingUrl),
        pingTimeoutMs: clearPing ? null : (pingTimeoutMs ?? this.pingTimeoutMs),
        replace: clearReplace ? null : (replace ?? this.replace),
      );


  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FolderServers &&
          id == other.id &&
          name == other.name &&
          enabled == other.enabled &&
          tagPrefix == other.tagPrefix &&
          detourPolicy == other.detourPolicy &&
          _eq.equals(members, other.members) &&
          createdAt == other.createdAt &&
          pingUrl == other.pingUrl &&
          pingTimeoutMs == other.pingTimeoutMs &&
          replace == other.replace);

  @override
  int get hashCode => Object.hash(id, name, enabled, tagPrefix, detourPolicy,
      _eq.hash(members), createdAt, pingUrl, pingTimeoutMs, replace);
}










({ServerList? healed, int count}) clearDetourDirectionRefs(
    ServerList l, String tag) {
  final autoTag = '$tag-auto';
  bool matches(NodeLink v) => v.isRoot && (v.tag == tag || v.tag == autoTag);

  var count = 0;
  ServerList next = l;
  if (matches(l.detourPolicy.overrideDetour)) {
    final p = l.detourPolicy.copyWith(overrideDetour: NodeLink.none);
    next = switch (l) {
      SubscriptionServers s => s.copyWith(detourPolicy: p),
      UserServer u => u.copyWith(detourPolicy: p),
      FolderServers f => f.copyWith(detourPolicy: p),
    };
    count++;
  }
  if (next is FolderServers) {
    var membersChanged = false;
    final ms = next.members.map((m) {
      if (matches(m.detour)) {
        membersChanged = true;
        count++;
        return m.copyWith(detour: NodeLink.none);
      }
      return m;
    }).toList();
    if (membersChanged) next = next.copyWith(members: ms);
  }
  return (healed: count > 0 ? next : null, count: count);
}



class DetourPolicy {
  final bool registerDetourServers;
  final bool registerDetourInAuto;
  final bool useDetourServers;


  final NodeLink overrideDetour;



  final bool replaceDetourChain;

  const DetourPolicy({
    this.registerDetourServers = false,
    this.registerDetourInAuto = false,
    this.useDetourServers = true,
    this.overrideDetour = NodeLink.none,
    this.replaceDetourChain = false,
  });

  static const defaults = DetourPolicy();



  Map<String, dynamic> toJson() => {
        'register_detour_servers': registerDetourServers,
        'register_detour_in_auto': registerDetourInAuto,
        'use_detour_servers': useDetourServers,
        'replace_detour_chain': replaceDetourChain,
      };

  DetourPolicy copyWith({
    bool? registerDetourServers,
    bool? registerDetourInAuto,
    bool? useDetourServers,
    NodeLink? overrideDetour,
    bool? replaceDetourChain,
  }) =>
      DetourPolicy(
        registerDetourServers:
            registerDetourServers ?? this.registerDetourServers,
        registerDetourInAuto:
            registerDetourInAuto ?? this.registerDetourInAuto,
        useDetourServers: useDetourServers ?? this.useDetourServers,
        overrideDetour: overrideDetour ?? this.overrideDetour,
        replaceDetourChain:
            replaceDetourChain ?? this.replaceDetourChain,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DetourPolicy &&
          registerDetourServers == other.registerDetourServers &&
          registerDetourInAuto == other.registerDetourInAuto &&
          useDetourServers == other.useDetourServers &&
          overrideDetour == other.overrideDetour &&
          replaceDetourChain == other.replaceDetourChain);

  @override
  int get hashCode => Object.hash(registerDetourServers, registerDetourInAuto,
      useDetourServers, overrideDetour, replaceDetourChain);
}
