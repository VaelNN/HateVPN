part of '../subscription_controller.dart';








class SubscriptionEntry extends ChangeNotifier {
  ServerList _list;
  int nodeCount;



  UiMsg? status;

  SubscriptionEntry({
    required ServerList list,
    int? nodeCount,
    this.status,
  })  : _list = list,
        nodeCount = nodeCount ??
            (list is SubscriptionServers ? list.lastNodeCount : list.nodes.length);

  ServerList get list => _list;

  String get id => _list.id;
  String get name => _list.name;
  bool get enabled => _list.enabled;
  String get tagPrefix => _list.tagPrefix;
  DetourPolicy get detourPolicy => _list.detourPolicy;
  String get type => _list.type;


  String get url => _list is SubscriptionServers ? (_list as SubscriptionServers).url : '';


  List<String> get connections {
    if (_list is UserServer) {
      final raw = (_list as UserServer).rawBody;
      if (raw.isEmpty) return const [];
      return raw
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  DateTime? get lastUpdated =>
      _list is SubscriptionServers ? (_list as SubscriptionServers).lastUpdated : null;

  SubscriptionMeta? get meta =>
      _list is SubscriptionServers ? (_list as SubscriptionServers).meta : null;

  int get uploadBytes => meta?.uploadBytes ?? 0;
  int get downloadBytes => meta?.downloadBytes ?? 0;
  int get totalBytes => meta?.totalBytes ?? 0;
  int get expireTimestamp => meta?.expireTimestamp ?? 0;
  String get supportUrl => meta?.supportUrl ?? '';
  String get webPageUrl => meta?.webPageUrl ?? '';
  int get updateIntervalHours => _list is SubscriptionServers
      ? (_list as SubscriptionServers).updateIntervalHours
      : 0;

  int get consecutiveFails => _list is SubscriptionServers
      ? (_list as SubscriptionServers).consecutiveFails
      : 0;

  UpdateStatus get lastUpdateStatus => _list is SubscriptionServers
      ? (_list as SubscriptionServers).lastUpdateStatus
      : UpdateStatus.never;



  SubscriptionOnUpdateAction get onUpdateAction => _list is SubscriptionServers
      ? (_list as SubscriptionServers).onUpdateAction
      : SubscriptionOnUpdateAction.rebuild;



  List<NodeWarning> get dropped => _list is SubscriptionServers
      ? (_list as SubscriptionServers).dropped
      : const [];



  SubscriptionIdentityOverride? get identity => _list is SubscriptionServers
      ? (_list as SubscriptionServers).identity
      : null;


  bool get hasCustomIdentity => identity != null;







  int get detourCount {
    var n = 0;
    for (final node in _list.nodes) {
      for (var hop = node.chained; hop != null; hop = hop.chained) {
        n++;
      }
    }
    return n;
  }

  bool get registerDetourServers => detourPolicy.registerDetourServers;
  bool get registerDetourInAuto => detourPolicy.registerDetourInAuto;
  bool get useDetourServers => detourPolicy.useDetourServers;
  NodeLink get overrideDetour => detourPolicy.overrideDetour;
  bool get replaceDetourChain => detourPolicy.replaceDetourChain;

  static String formatAgo(DateTime dt) => _formatAgo(dt);

  String get displayName {





    if (_list is! UserServer && name.isNotEmpty) return name;
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.host.isNotEmpty) return uri.host;
      return url.length > 40 ? '${url.substring(0, 40)}…' : url;
    }
    if (_list.nodes.isNotEmpty) {
      return _list.nodes.first.label.isNotEmpty
          ? _list.nodes.first.label
          : _list.nodes.first.tag;
    }
    final conns = connections;
    if (conns.isNotEmpty) {
      final c = conns.first;
      if (c.startsWith('{')) {
        final tagMatch = RegExp(r'"tag"\s*:\s*"([^"]+)"').firstMatch(c);
        if (tagMatch != null) return tagMatch.group(1)!;
      }
      return c.length > 40 ? '${c.substring(0, 40)}...' : c;
    }



    return '(empty)';
  }



  String subtitle() {
    final parts = <String>[];
    final s = status;
    if (s != null) parts.add(s.render());
    if (lastUpdated != null) parts.add(_formatAgo(lastUpdated!));
    return parts.join(' · ');
  }

  static String _formatAgo(DateTime dt) => relativeTime(DateTime.now(), dt);

  void _replaceList(ServerList next) {
    _list = next;
    notifyListeners();
  }







  set name(String v) => _replaceList(_copy(name: v));
  set enabled(bool v) => _replaceList(_copy(enabled: v));
  set tagPrefix(String v) => _replaceList(_copy(tagPrefix: v));











  set updateIntervalHours(int v) {
    final list = _list;
    if (list is! SubscriptionServers) return;
    final clamped = v < -1 ? -1 : v;
    _replaceList(list.copyWith(updateIntervalHours: clamped));
  }




  set onUpdateAction(SubscriptionOnUpdateAction v) {
    final list = _list;
    if (list is! SubscriptionServers) return;
    _replaceList(list.copyWith(onUpdateAction: v));
  }



  void enableCustomIdentity() {
    final list = _list;
    if (list is! SubscriptionServers || list.identity != null) return;
    _replaceList(
        list.copyWith(identity: SubscriptionIdentity.snapshotGlobal()));
  }



  void disableCustomIdentity() {
    final list = _list;
    if (list is! SubscriptionServers) return;
    _replaceList(list.copyWith(clearIdentity: true));
  }



  void updateIdentity(SubscriptionIdentityOverride next) {
    final list = _list;
    if (list is! SubscriptionServers || list.identity == null) return;
    _replaceList(list.copyWith(identity: next));
  }





  void updateImportRules(List<ImportRule> rules) {
    final list = _list;
    if (list is! SubscriptionServers) return;
    _replaceList(list.copyWith(importRules: rules));
  }


  set importRulesEnabled(bool v) {
    final list = _list;
    if (list is! SubscriptionServers) return;
    _replaceList(list.copyWith(importRulesEnabled: v));
  }

  set registerDetourServers(bool v) =>
      _replaceList(_copy(detourPolicy: detourPolicy.copyWith(registerDetourServers: v)));
  set registerDetourInAuto(bool v) =>
      _replaceList(_copy(detourPolicy: detourPolicy.copyWith(registerDetourInAuto: v)));
  set useDetourServers(bool v) =>
      _replaceList(_copy(detourPolicy: detourPolicy.copyWith(useDetourServers: v)));
  set overrideDetour(NodeLink v) =>
      _replaceList(_copy(detourPolicy: detourPolicy.copyWith(overrideDetour: v)));
  set replaceDetourChain(bool v) =>
      _replaceList(_copy(detourPolicy: detourPolicy.copyWith(replaceDetourChain: v)));



  SourceReplace? get replace => _list.replace;
  set replace(SourceReplace? v) => switch (_list) {
        final SubscriptionServers s =>
          _replaceList(s.copyWith(replace: v, clearReplace: v == null)),
        final FolderServers f =>
          _replaceList(f.copyWith(replace: v, clearReplace: v == null)),
        UserServer() => null,
      };

  ServerList _copy({
    String? name,
    bool? enabled,
    String? tagPrefix,
    DetourPolicy? detourPolicy,
  }) =>
      switch (_list) {
        final SubscriptionServers s => s.copyWith(
            name: name,
            enabled: enabled,
            tagPrefix: tagPrefix,
            detourPolicy: detourPolicy,
          ),
        final UserServer u => u.copyWith(
            name: name,
            enabled: enabled,
            tagPrefix: tagPrefix,
            detourPolicy: detourPolicy,
          ),
        final FolderServers f => f.copyWith(
            name: name,
            enabled: enabled,
            tagPrefix: tagPrefix,
            detourPolicy: detourPolicy,
          ),
      };
}
