import 'package:flutter/foundation.dart';

import '../../controllers/home_controller.dart';
import '../../services/contract/group_genus.dart';
import '../../controllers/subscription_controller.dart';
import '../../models/home_state.dart';
import '../../models/node_spec.dart';
import '../../models/node_warning.dart';
import '../../models/server_list.dart';
import '../../services/safe_regex.dart';
import '../subscriptions_screen/entry_warnings.dart';
import 'node_filter.dart';
import 'node_filter_view_model.dart';
import 'source_lookup.dart';



String protoLabel(String type) => type == GroupGenus.manual

    ? 'Manual'
    : switch (type) {
      'vless' => 'VLESS',
      'vmess' => 'VMess',
      'trojan' => 'Trojan',
      'shadowsocks' => 'SS',
      'hysteria2' => 'Hy2',
      'tuic' => 'TUIC',
      'wireguard' => 'WG',
      'masque' => 'MASQUE',
      'anytls' => 'AnyTLS',
      'ssh' => 'SSH',
      'socks' => 'SOCKS',
      'http' => 'HTTP',
      'tailscale' => 'Tailscale',


      'urltest' => 'Auto',
      _ => type.toUpperCase(),
    };



String autoModeLabel(String mode) => switch (mode) {
      'least_test' => 'Fastest',
      'round_robin' => 'Pool',
      _ => mode,
    };
























final Map<String, RegExp?> _badgeRegexCache = {};

RegExp? _cachedBadgeRegex(String badge) => _badgeRegexCache.putIfAbsent(
      badge,
      () => tryCompileRegex(badge, unicode: true),
    );

String poolBadges(List<String> memberLabels, String badge) {
  if (badge.isEmpty || memberLabels.isEmpty) return '';

  final re = _cachedBadgeRegex(badge);
  if (re == null) return '';
  final counts = <String, int>{};
  for (final l in memberLabels) {
    final m = re.firstMatch(l);
    if (m == null) continue;
    final hit = m.group(0) ?? '';
    if (hit.isEmpty) continue;
    counts[hit] = (counts[hit] ?? 0) + 1;
  }
  return counts.entries
      .map((e) => e.value > 1 ? '${e.key}[${e.value}]' : e.key)
      .join(', ');
}

String? autoGroupLabel(Map<String, dynamic>? raw) {
  if (raw == null || raw['type'] != 'urltest') return null;
  final members = (raw['outbounds'] as List?)?.length ?? 0;

  final balancer = raw['balancer'];
  if (balancer is! Map) return '🎯 [$members]';

  final pool = (balancer['pool'] as num?)?.toInt() ?? members;
  return '🔀 [$members/$pool]';
}















class NodeListPresenter {
  NodeListPresenter({
    required this.controller,
    required this.subController,
    required this.filter,
  });

  final HomeController controller;
  final SubscriptionController subController;
  final NodeFilterViewModel filter;




  List<String>? _cachedSorted;
  ({NodeSortMode mode, int gen, int nodesLen, bool pinD, bool pinA})?
      _cachedSortKey;




  bool _isUserAutoGroup(String tag, HomeState state) =>
      !state.isSystemControlTag(tag) &&
      (state.groupOf(tag)?.type == 'urltest' ||
          state.activeModel[tag]?.type == 'urltest');








  String? protocolOfTag(String tag, HomeState state) {

    final model = state.activeModel;
    if (_isUserAutoGroup(tag, state)) return 'urltest';
    final urltestNow = state.urltestNowOf(tag);
    return model.protocolOf(tag) ??
        (urltestNow != null ? model.protocolOf(urltestNow) : null);
  }




  String autoModeOf(String tag, HomeState state) {
    final raw = state.activeModel[tag]?.raw;
    return (raw?['balancer'] is Map) ? 'round_robin' : 'least_test';
  }




  Set<String> variantsOfTag(String tag, HomeState state) {
    final model = state.activeModel;



    if (_isUserAutoGroup(tag, state)) return {autoModeOf(tag, state)};

    var n = model[tag];
    if (n == null || n.isControl || n.type.isEmpty) {
      final urltestNow = state.urltestNowOf(tag);
      n = urltestNow != null ? model[urltestNow] : null;


      if (n != null && (n.isControl || n.type.isEmpty)) n = null;
    }
    if (n == null) return const <String>{};
    return {
      ?n.transportLabel,
      ?n.securityLabel,
    };
  }



  static const _variantOrder = <String>[
    'tcp', 'ws', 'grpc', 'h2', 'h3', 'httpupgrade', 'quic', 'xhttp',
    'TLS', 'TLS+Vision', 'Reality', 'Reality+Vision',
    'awg', 'awg1.5', 'awg2', 'awg3', 'awg3.1',

    'least_test', 'round_robin',
  ];

  static int _variantRank(String v) {


    final base = v.endsWith('+') ? v.substring(0, v.length - 1) : v;
    final i = _variantOrder.indexOf(base);
    return i >= 0 ? i : _variantOrder.length;
  }








  List<(String, String)>? _prefixIndex;

  Set<String> _sourcesOfTag(String tag) {
    final index = _prefixIndex ??= sourcePrefixIndex(subController.entries);
    final result = <String>{};
    for (final (prefix, id) in index) {
      if (tag.startsWith(prefix)) result.add(id);
    }
    return result;
  }



  NodeFilter buildNodeFilter(HomeState state) => NodeFilter(
        regex: filter.activeRegex,
        regexInvert: filter.regexInvert,
        protocols: filter.enabledProtocols,
        protocolsInvert: filter.protocolsInvert,
        variants: filter.enabledVariants,
        variantsInvert: filter.variantsInvert,
        subscriptions: filter.enabledSubscriptions,
        subscriptionsInvert: filter.subscriptionsInvert,
        maxPingMs: filter.activeMaxPingMs,
        protocolOf: (t) => protocolOfTag(t, state),
        variantsOf: (t) => variantsOfTag(t, state),
        subscriptionsOf: _sourcesOfTag,


        pingOf: state.delayOf,
      );



  List<String> poolOf(List<String> sortedNodes, HomeState state) => sortedNodes
      .where((t) =>
          state.isSystemControlTag(t) ||
          filter.detourPoolPasses(state.activeModel[t]?.isDetour ?? false))
      .toList();








  (List<String>, List<String>) splitNodes(
      List<String> sortedNodes, HomeState state,
      {List<String>? pool}) {


    pool ??= poolOf(sortedNodes, state);
    final f = buildNodeFilter(state);
    final matching = <String>[];
    final nonMatching = <String>[];
    for (final tag in pool) {
      if (state.isSystemControlTag(tag) || f.passes(tag)) {
        matching.add(tag);
      } else {
        nonMatching.add(tag);
      }
    }
    return (matching, nonMatching);
  }



  List<String> computeDisplayList(HomeState state) {
    _prefixIndex = null;
    final (matching, nonMatching) = splitNodes(viewSortedNodes(state), state);
    return filter.showNonMatching
        ? [...matching, ...nonMatching]
        : matching;
  }





  List<String> viewSortedNodes(HomeState s) {
    if (s.resortOnManualPing) {
      _cachedSortKey = null;
      _cachedSorted = null;
      return s.sortedNodes;
    }
    final key = (
      mode: s.sortMode,
      gen: s.pingBatchGen,
      nodesLen: s.nodes.length,
      pinD: s.pinDirect,
      pinA: s.pinAuto,
    );
    if (key == _cachedSortKey && _cachedSorted != null) {




      if (_cachedSorted!.every(s.nodeSet.contains)) return _cachedSorted!;
    }
    _cachedSortKey = key;
    _cachedSorted = List<String>.unmodifiable(s.sortedNodes);
    return _cachedSorted!;
  }





  List<ServerList>? _warningsLists;
  Map<String, NodeSpec>? _warningsTagMap;
  Map<String, List<NodeWarning>>? _warningsBuild;
  List<String>? _warningsNodes;
  Map<String, List<NodeWarning>>? _warningsByTag;


  @visibleForTesting
  int debugWarningsPasses = 0;

  Map<String, List<NodeWarning>> _warningsByTagFor(
      List<String> tags, HomeState state) {
    final entries = subController.entries;
    final emittedTagMap = subController.lastEmittedTagMap;
    final buildWarnings = subController.lastBuildWarningsByTag;
    final cached = _warningsByTag;
    final lists = _warningsLists;
    if (cached != null &&
        lists != null &&
        identical(_warningsTagMap, emittedTagMap) &&
        identical(_warningsBuild, buildWarnings) &&
        identical(_warningsNodes, state.nodes) &&
        lists.length == entries.length &&
        tags.every(cached.containsKey)) {
      var same = true;
      for (var i = 0; i < lists.length; i++) {
        if (!identical(lists[i], entries[i].list)) {
          same = false;
          break;
        }
      }
      if (same) return cached;
    }
    debugWarningsPasses++;
    _warningsLists = [for (final e in entries) e.list];
    _warningsTagMap = emittedTagMap;
    _warningsBuild = buildWarnings;
    _warningsNodes = state.nodes;
    return _warningsByTag = <String, List<NodeWarning>>{
      for (final tag in tags)
        tag: warningsForConfigTag(
          tag,
          entries,
          emittedTagMap: emittedTagMap,
          buildWarningsByTag: buildWarnings,
        ),
    };
  }



  NodeListData computeListData(HomeState state) {



    _prefixIndex = null;









    final allTags = viewSortedNodes(state);
    final pool = poolOf(allTags, state);





    final cache = state.activeModel;



    final (matching, nonMatching) = splitNodes(allTags, state, pool: pool);
    final matchingSet = matching.toSet();


    final displayList = filter.showNonMatching
        ? <String>[...matching, ...nonMatching]
        : matching;



    final emojis = NodeFilter.extractEmojis(allTags);
    final availableProtocols = <String>{};
    final availableVariants = <String>{};
    for (final t in pool) {
      final p = protocolOfTag(t, state);
      if (p != null) availableProtocols.add(p);
      availableVariants.addAll(variantsOfTag(t, state));
    }
    final sourceOptions = <(String, String)>[];
    for (final e in subController.entries) {
      final list = e.list;




      if ((list is SubscriptionServers || list is FolderServers) &&
          e.enabled &&
          list.tagPrefix.isNotEmpty &&
          list.nodes.isNotEmpty) {
        sourceOptions.add((e.id, e.displayName));
      }
    }






    final warningsByTag = _warningsByTagFor(allTags, state);

    return NodeListData(
      cache: cache,
      matchingSet: matchingSet,
      displayList: displayList,
      emojis: emojis,
      availableProtocols: availableProtocols.toList()..sort(),
      availableVariants: availableVariants.toList()
        ..sort((a, b) {
          final byRank = _variantRank(a).compareTo(_variantRank(b));
          return byRank != 0 ? byRank : a.compareTo(b);
        }),
      sourceOptions: sourceOptions,
      warningsByTag: warningsByTag,
    );
  }
}


class NodeListData {
  const NodeListData({
    required this.cache,
    required this.matchingSet,
    required this.displayList,
    required this.emojis,
    required this.availableProtocols,
    required this.availableVariants,
    required this.sourceOptions,
    required this.warningsByTag,
  });

  final ParsedConfig cache;
  final Set<String> matchingSet;
  final List<String> displayList;
  final List<String> emojis;
  final List<String> availableProtocols;



  final List<String> availableVariants;


  final List<(String, String)> sourceOptions;


  final Map<String, List<NodeWarning>> warningsByTag;


  WarningSeverity? topWarningSeverityOf(String tag) =>
      topWarningSeverity(warningsByTag[tag] ?? const []);
}
