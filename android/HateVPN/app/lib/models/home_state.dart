import 'package:flutter/material.dart';

import '../vpn/cc_channel.dart';
import 'config_node.dart';
import 'debug_entry.dart';
import 'dependency_graph.dart';
import 'stop_reason.dart';
import 'traffic_snapshot.dart';
import 'tunnel_status.dart';
import 'ui_msg.dart';
import '../services/l10n/locale_controller.dart';
import '../services/networks_direction.dart';

export 'config_node.dart';
export 'dependency_graph.dart';
export 'stop_reason.dart';
export 'traffic_snapshot.dart';
export 'ui_msg.dart';

export 'debug_entry.dart';
export 'tunnel_status.dart';

enum NodeSortMode {
  defaultOrder(Icons.swap_vert),
  latencyAsc(Icons.signal_cellular_alt),
  nameAsc(Icons.sort_by_alpha),


  manual(Icons.drag_indicator);

  const NodeSortMode(this.icon);
  final IconData icon;



  String label() => switch (this) {
        defaultOrder => getLocalText.s("Default"),
        latencyAsc => getLocalText.s("Ping"),
        nameAsc => getLocalText.s("A–Z"),
        manual => getLocalText.s("Custom"),
      };



  NodeSortMode get next => switch (this) {
        NodeSortMode.defaultOrder => NodeSortMode.latencyAsc,
        NodeSortMode.latencyAsc => NodeSortMode.nameAsc,
        NodeSortMode.nameAsc => NodeSortMode.manual,
        NodeSortMode.manual => NodeSortMode.defaultOrder,
      };
}

class HomeState {
  HomeState({
    this.configRaw = '',
    this.runningConfigRaw,
    ParsedConfig? configModel,
    ParsedConfig? runningModel,
    this.tunnel = TunnelStatus.disconnected,
    this.lastError,
    this.stopReason,
    this.busy = false,
    this.ccGroups = const <CcGroup>[],
    this.groups = const <String>[],
    this.groupLabels = const <String, String>{},
    this.directionAutoTags = const <String>{},
    this.selectedGroup,
    this.nodes = const <String>[],
    this.activeInGroup,
    this.highlightedNode,
    this.delayByDirection = const <String, Map<String, int>>{},
    this.pingBusy = const <String, String>{},
    this.endpointStates = const <String, String>{},
    this.endpointIdleSince = const <String, int>{},
    this.sickRoots = const <String, List<DependentRef>>{},
    this.debugEvents = const <DebugEntry>[],
    this.sortMode = NodeSortMode.latencyAsc,

    this.pinDirect = true,
    this.pinAuto = true,
    this.resortOnManualPing = true,



    this.pingBatchGen = 0,

    this.manualOrder = const <String>[],
    this.traffic = TrafficSnapshot.zero,
    this.connectedSince,
    this.configChangedNeedRestart = false,
    this.configLoadError = false,
    this.lastStartError = '',
    this.lastStartErrorAt,
    this.networksOpen = false,
    this.tailscaleStatus = const <String, CcTailscaleStatus>{},
  })  : configModel = configModel ?? ParsedConfig.parse(configRaw),
        runningModel = runningModel ??
            (runningConfigRaw != null
                ? ParsedConfig.parse(runningConfigRaw)
                : null);





  final String configRaw;







  final String? runningConfigRaw;




  final ParsedConfig configModel;


  final ParsedConfig? runningModel;






  ParsedConfig get activeModel =>
      (tunnelUp ? runningModel : null) ?? configModel;



  String get activeConfigRaw =>
      (tunnelUp ? runningConfigRaw : null) ?? configRaw;

  final TunnelStatus tunnel;



  final UiMsg? lastError;






  final StopReason? stopReason;
  final bool busy;



  final List<CcGroup> ccGroups;
  final List<String> groups;



  final Map<String, String> groupLabels;




  final Set<String> directionAutoTags;


  String groupLabelOf(String tag) => groupLabels[tag] ?? tag;

  final String? selectedGroup;
  final List<String> nodes;
  final String? activeInGroup;
  final String? highlightedNode;















  final Map<String, Map<String, int>> delayByDirection;
  final Map<String, String> pingBusy;








  final Map<String, String> endpointStates;




  final Map<String, int> endpointIdleSince;





  final Map<String, List<DependentRef>> sickRoots;




  static const String scratchDirection = '\u0000scratch';


  String get delayDirectionKey => selectedGroup ?? scratchDirection;



  Map<String, int> get _ownDelays =>
      delayByDirection[delayDirectionKey] ?? const <String, int>{};







  int? delayOf(String tag) {
    final own = _ownDelays[tag];
    if (own != null) return own;
    for (final entry in delayByDirection.entries) {
      if (entry.key == delayDirectionKey) continue;
      final v = entry.value[tag];
      if (v != null) return v;
    }
    return null;
  }



  bool delayIsForeign(String tag) =>
      !_ownDelays.containsKey(tag) && delayOf(tag) != null;
  final List<DebugEntry> debugEvents;
  final NodeSortMode sortMode;


  final bool pinDirect;
  final bool pinAuto;


  final bool resortOnManualPing;



  final int pingBatchGen;



  final List<String> manualOrder;
  final TrafficSnapshot traffic;
  final DateTime? connectedSince;




  final bool configChangedNeedRestart;






  final bool configLoadError;







  final String lastStartError;


  final DateTime? lastStartErrorAt;

  bool get tunnelUp => tunnel.isUp;




  final bool networksOpen;



  final Map<String, CcTailscaleStatus> tailscaleStatus;



  List<String> get networksNodes => networksNodeTags(activeModel);





  bool get showingNetworks =>
      tunnelUp &&
      (networksOpen || groups.isEmpty) &&
      networksNodes.isNotEmpty;










  late final Map<String, CcGroup> _groupByTag = () {
    final m = <String, CcGroup>{};
    for (final g in ccGroups) {
      m.putIfAbsent(g.tag, () => g);
    }
    return m;
  }();


  CcGroup? groupOf(String tag) => _groupByTag[tag];

  bool _isUrltest(String type) => type.toLowerCase().contains('urltest');
  bool _isSelector(String type) => type.toLowerCase().contains('selector');



  List<String> get selectorGroupTags => [
        for (final g in ccGroups)
          if (g.selectable && _isSelector(g.type)) g.tag,
      ];



  String? urltestNowOf(String tag) {
    final g = groupOf(tag);
    if (g == null || !_isUrltest(g.type)) return null;
    return g.selected.isEmpty ? null : g.selected;
  }






  bool isControlTag(String tag) {
    final g = groupOf(tag);
    if (g != null && (_isSelector(g.type) || _isUrltest(g.type))) return true;
    return activeModel[tag]?.isControl ?? false;
  }











  bool isSystemControlTag(String tag) {
    if (groupLabels.containsKey(tag) || directionAutoTags.contains(tag)) {
      return true;
    }
    final t = activeModel[tag]?.type;
    return t == 'direct' || t == 'block' || t == 'dns';
  }


  Iterable<CcGroup> get urltestGroups =>
      ccGroups.where((g) => _isUrltest(g.type));








  late final List<String> sortedNodes = _computeSortedNodes();




  late final List<String> _pinnedTags = _computePinned();




  late final Set<String> nodeSet = nodes.toSet();




  int get pinnedNodeCount => _pinnedTags.length;




  late final Set<String> pinnedTagSet = _pinnedTags.toSet();





  List<String> _computePinned() {


    final model = activeModel;
    final pinnedSet = <String>{
      for (final n in nodes)
        if ((pinDirect && model[n]?.type == 'direct') ||


            (pinAuto &&
                model[n]?.type == 'urltest' &&
                directionAutoTags.contains(n)) ||
            model[n]?.type == 'block')
          n,
    };
    final pinned = [
      ...nodes.where((n) => pinnedSet.contains(n) && model[n]?.type == 'direct'),
      ...nodes.where((n) =>
          pinnedSet.contains(n) &&
          model[n]?.type == 'urltest' &&
          directionAutoTags.contains(n)),
      ...nodes.where((n) => pinnedSet.contains(n) && model[n]?.type == 'block'),
    ];



    final active = activeInGroup;
    if (active != null &&
        active.isNotEmpty &&
        nodeSet.contains(active) &&
        !pinnedSet.contains(active)) {
      pinned.add(active);
    }
    return pinned;
  }

  List<String> _computeSortedNodes() {
    final pinned = _pinnedTags;
    final pinnedSet = pinned.toSet();
    final rest = nodes.where((n) => !pinnedSet.contains(n)).toList();
    switch (sortMode) {
      case NodeSortMode.defaultOrder:

        break;
      case NodeSortMode.latencyAsc:
        rest.sort(_compareLatency);
      case NodeSortMode.nameAsc:
        rest.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      case NodeSortMode.manual:


        final restSet = rest.toSet();



        final orderSet = manualOrder.toSet();
        final ordered = <String>[
          ...manualOrder.where(restSet.contains),
          ...rest.where((n) => !orderSet.contains(n)),
        ];
        return [...pinned, ...ordered];
    }
    return [...pinned, ...rest];
  }

  int _compareLatency(String a, String b) {



    final da = delayOf(a);
    final db = delayOf(b);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    if (da < 0 && db < 0) return 0;
    if (da < 0) return 1;
    if (db < 0) return -1;
    return da.compareTo(db);
  }

  HomeState copyWith({
    String? configRaw,


    Object? runningConfigRaw = _unset,
    TunnelStatus? tunnel,
    Object? lastError = _unset,
    Object? stopReason = _unset,
    bool? busy,
    List<CcGroup>? ccGroups,
    List<String>? groups,
    Map<String, String>? groupLabels,
    Set<String>? directionAutoTags,
    Object? selectedGroup = _unset,
    List<String>? nodes,
    Object? activeInGroup = _unset,
    Object? highlightedNode = _unset,
    Map<String, Map<String, int>>? delayByDirection,
    Map<String, String>? pingBusy,
    Map<String, String>? endpointStates,
    Map<String, int>? endpointIdleSince,
    Map<String, List<DependentRef>>? sickRoots,
    List<DebugEntry>? debugEvents,
    NodeSortMode? sortMode,
    bool? pinDirect,
    bool? pinAuto,
    bool? resortOnManualPing,
    int? pingBatchGen,
    List<String>? manualOrder,
    TrafficSnapshot? traffic,
    Object? connectedSince = _unset,
    bool? configChangedNeedRestart,
    bool? configLoadError,
    String? lastStartError,
    Object? lastStartErrorAt = _unset,
    bool? networksOpen,
    Map<String, CcTailscaleStatus>? tailscaleStatus,
  }) {
    return HomeState(
      configRaw: configRaw ?? this.configRaw,
      runningConfigRaw: identical(runningConfigRaw, _unset)
          ? this.runningConfigRaw
          : runningConfigRaw as String?,



      configModel:
          configRaw != null ? ParsedConfig.parse(configRaw) : configModel,


      runningModel: identical(runningConfigRaw, _unset)
          ? runningModel
          : (runningConfigRaw is String
              ? ParsedConfig.parse(runningConfigRaw)
              : null),
      tunnel: tunnel ?? this.tunnel,
      lastError: identical(lastError, _unset)
          ? this.lastError
          : lastError as UiMsg?,


      stopReason: identical(stopReason, _unset)
          ? (identical(lastError, _unset) ? this.stopReason : null)
          : stopReason as StopReason?,
      busy: busy ?? this.busy,
      ccGroups: ccGroups ?? this.ccGroups,
      groups: groups ?? this.groups,
      groupLabels: groupLabels ?? this.groupLabels,
      directionAutoTags: directionAutoTags ?? this.directionAutoTags,
      selectedGroup: identical(selectedGroup, _unset)
          ? this.selectedGroup
          : selectedGroup as String?,
      nodes: nodes ?? this.nodes,
      activeInGroup: identical(activeInGroup, _unset)
          ? this.activeInGroup
          : activeInGroup as String?,
      highlightedNode: identical(highlightedNode, _unset)
          ? this.highlightedNode
          : highlightedNode as String?,
      delayByDirection: delayByDirection ?? this.delayByDirection,
      pingBusy: pingBusy ?? this.pingBusy,
      endpointStates: endpointStates ?? this.endpointStates,
      endpointIdleSince: endpointIdleSince ?? this.endpointIdleSince,
      sickRoots: sickRoots ?? this.sickRoots,
      debugEvents: debugEvents ?? this.debugEvents,
      sortMode: sortMode ?? this.sortMode,
      pinDirect: pinDirect ?? this.pinDirect,
      pinAuto: pinAuto ?? this.pinAuto,
      resortOnManualPing: resortOnManualPing ?? this.resortOnManualPing,
      pingBatchGen: pingBatchGen ?? this.pingBatchGen,
      manualOrder: manualOrder ?? this.manualOrder,
      traffic: traffic ?? this.traffic,
      connectedSince: identical(connectedSince, _unset)
          ? this.connectedSince
          : connectedSince as DateTime?,
      configChangedNeedRestart: configChangedNeedRestart ?? this.configChangedNeedRestart,
      configLoadError: configLoadError ?? this.configLoadError,
      lastStartError: lastStartError ?? this.lastStartError,
      lastStartErrorAt: identical(lastStartErrorAt, _unset)
          ? this.lastStartErrorAt
          : lastStartErrorAt as DateTime?,
      networksOpen: networksOpen ?? this.networksOpen,
      tailscaleStatus: tailscaleStatus ?? this.tailscaleStatus,
    );
  }
}

const _unset = Object();
