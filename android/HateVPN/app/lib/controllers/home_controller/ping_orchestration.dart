part of '../home_controller.dart';






mixin _PingMixin on ChangeNotifier {

  HomeState get _state;
  CcChannel get _cc;
  Timer? get _autoPingTimer;
  set _autoPingTimer(Timer? value);
  void _emit(HomeState next);
  void _addDebug(DebugSource source, String message);
  Future<void> reloadProxies();



  void _recomputeDependencyHealth();





  Future<void> runNodeUrltest(String nodeTag) async {
    if (!_state.tunnelUp) return;

    if (_state.activeModel[nodeTag]?.type == 'block') return;
    final pingBusy = Map<String, String>.from(_state.pingBusy)..[nodeTag] = '…';
    _emit(_state.copyWith(pingBusy: pingBusy));
    final group = _state.selectedGroup;
    final url = pingUrlFor(group);
    final timeoutMs = pingTimeoutFor(group);



    final directionKey = _state.delayDirectionKey;
    try {
      final r = await _cc.urlTestOutbound(nodeTag, link: url, timeoutMs: timeoutMs);
      final ms = r.lastDelayValue;
      final nextDelay = _delaysWith({nodeTag: ms}, direction: directionKey);
      final nextBusy = Map<String, String>.from(_state.pingBusy)..[nodeTag] = '';
      if (r.ok) {
        _emit(_state.copyWith(delayByDirection: nextDelay, pingBusy: nextBusy));
        _addDebug(DebugSource.app, 'URLTest $nodeTag → $url: ${ms}ms');
      } else {
        final msg = ProbeErrorMsg(nodeTag, _probeHost(url), RawMsg(r.error));
        _emit(_state.copyWith(
            delayByDirection: nextDelay, pingBusy: nextBusy, lastError: msg));
        _addDebug(DebugSource.app, msg.renderEn());
        _rescueGroupsSelecting(nodeTag);
      }
    } catch (e) {
      final nextDelay = _delaysWith({nodeTag: -1}, direction: directionKey);
      final nextBusy = Map<String, String>.from(_state.pingBusy)..[nodeTag] = '';
      final msg = _formatProbeError(nodeTag, url, e);
      _emit(_state.copyWith(
          delayByDirection: nextDelay, pingBusy: nextBusy, lastError: msg));
      _addDebug(DebugSource.app, msg.renderEn());
      _rescueGroupsSelecting(nodeTag);
    }

    _recomputeDependencyHealth();
  }







  Map<String, Map<String, int>> _delaysWith(
    Map<String, int?> updates, {
    String? direction,
  }) {
    final key = direction ?? _state.delayDirectionKey;
    final next = Map<String, Map<String, int>>.from(_state.delayByDirection);
    final delays = Map<String, int>.from(next[key] ?? const <String, int>{});
    updates.forEach((tag, ms) {
      if (ms == null) {
        delays.remove(tag);
      } else {
        delays[tag] = ms;
      }
    });
    next[key] = delays;
    return next;
  }











  void _rescueGroupsSelecting(String nodeTag) {
    if (!_state.tunnelUp) return;
    for (final g in _state.urltestGroups) {
      if (g.selected == nodeTag) {
        _addDebug(DebugSource.app,
            'Ping failed for "$nodeTag" — selected by ${g.tag} → group URLTest');
        unawaited(runGroupUrltest(g.tag));
      }
    }
  }








  static ProbeErrorMsg _formatProbeError(String target, String url, Object e) {
    return ProbeErrorMsg(target, _probeHost(url), formatUserError(e));
  }


  static String _probeHost(String url) {
    if (url.isEmpty) return '';
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return '';
    }
  }

  bool _massPingRunning = false;
  bool get massPingRunning => _massPingRunning;
  int _massPingEpoch = 0;




  Map<String, dynamic> _pingOptions = const {};
  String _templatePingUrl = '';
  int _templatePingTimeoutMs = 10000;




  String get pingUrl {
    final saved = _pingOptions['url'];
    if (saved is String && saved.isNotEmpty) return saved;
    return _templatePingUrl;
  }


  int get pingTimeout {
    final saved = _pingOptions['timeout_ms'];
    if (saved is num && saved > 0) return saved.toInt();
    return _templatePingTimeoutMs;
  }



  String pingUrlFor(String? groupTag) {
    if (groupTag != null && groupTag.isNotEmpty) {
      final groups = _pingOptions['groups'];
      if (groups is Map<String, dynamic>) {
        final override = groups[groupTag];
        if (override is Map<String, dynamic>) {
          final url = override['url'];
          if (url is String && url.isNotEmpty) return url;
        }
      }
    }
    return pingUrl;
  }


  int pingTimeoutFor(String? groupTag) {
    if (groupTag != null && groupTag.isNotEmpty) {
      final groups = _pingOptions['groups'];
      if (groups is Map<String, dynamic>) {
        final override = groups[groupTag];
        if (override is Map<String, dynamic>) {
          final t = override['timeout_ms'];
          if (t is num && t > 0) return t.toInt();
        }
      }
    }
    return pingTimeout;
  }




  Future<void> reloadPingOptions() async {
    try {

      final opts = (await TemplateLoader.load()).pingOptionsModel;
      _templatePingUrl = opts.defaultUrl;
      _templatePingTimeoutMs =
          opts.defaultTimeoutMs > 0 ? opts.defaultTimeoutMs : 10000;
    } catch (e) {
      _addDebug(DebugSource.app, 'Template load (ping options): $e');
    }
    _pingOptions = await SettingsStorage.getPingOptions();
  }

  static const _pingConcurrency = 10;




  static const _massPingFlushMs = 120;





  static const _autoPingDelay = Duration(seconds: 5);
  Future<void> _scheduleAutoPing() async {
    _autoPingTimer?.cancel();
    final enabled =
        await SettingsStorage.getVar('auto_ping_on_start', 'true');
    if (enabled != 'true') return;





    if (!_state.tunnelUp) return;
    _autoPingTimer = Timer(_autoPingDelay, () {
      if (!_state.tunnelUp || _state.nodes.isEmpty) return;
      unawaited(runMassUrltest());
    });
  }




  @visibleForTesting
  bool get autoPingScheduledForTesting => _autoPingTimer?.isActive ?? false;













  Future<void> runGroupUrltest(String groupTag) async {
    if (!_state.tunnelUp) return;
    final ok = await _cc.urlTestGroup(groupTag);
    if (ok) {
      _addDebug(DebugSource.app,
          'Group URLTest started: $groupTag (core tests all members + reselect)');
    } else {
      final msg =
          ProbeErrorMsg(groupTag, '', RawMsg('group URLTest RPC failed'));
      _addDebug(DebugSource.app, msg.renderEn());
      _emit(_state.copyWith(lastError: msg));
    }
  }












  Future<void> runMassUrltest({List<String>? order}) async {
    if (!_state.tunnelUp) return;

    if (_massPingRunning) {
      cancelMassPing();
      return;
    }



    final nodes = List<String>.from(order ?? _state.nodes)
        .where((t) => _state.activeModel[t]?.type != 'block')
        .toList();
    if (nodes.isEmpty) return;

    _massPingRunning = true;
    _massPingEpoch++;
    final epoch = _massPingEpoch;




    final massPingGroup = _state.selectedGroup;
    final massPingUrl = pingUrlFor(massPingGroup);
    final massPingTimeout = pingTimeoutFor(massPingGroup);



    final massPingDirection = massPingGroup ?? HomeState.scratchDirection;








    final busyMap = {for (final tag in nodes) tag: '…'};
    final clearedDelay = _delaysWith(
      {for (final tag in nodes) tag: null},
      direction: massPingDirection,
    );
    _emit(_state.copyWith(delayByDirection: clearedDelay, pingBusy: busyMap));
    _addDebug(DebugSource.app, 'Mass ping started (${nodes.length} nodes, concurrency=$_pingConcurrency)');


    var index = 0;





    final pendingDelay = <String, int>{};
    final pendingBusy = <String, String>{};
    void flush() {
      if (_massPingEpoch != epoch) return;
      if (pendingDelay.isEmpty && pendingBusy.isEmpty) return;
      final nextDelay = _delaysWith(pendingDelay, direction: massPingDirection);
      final nextBusy = Map<String, String>.from(_state.pingBusy)
        ..addAll(pendingBusy);
      pendingDelay.clear();
      pendingBusy.clear();
      _emit(_state.copyWith(delayByDirection: nextDelay, pingBusy: nextBusy));


      _recomputeDependencyHealth();
    }

    final flushTimer =
        Timer.periodic(const Duration(milliseconds: _massPingFlushMs), (_) {
      if (_massPingEpoch != epoch) return;
      flush();
    });

    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= nodes.length) break;
        if (!_massPingRunning || _massPingEpoch != epoch || !_state.tunnelUp) break;
        final tag = nodes[i];
        try {
          final r = await _cc.urlTestOutbound(tag,
              link: massPingUrl, timeoutMs: massPingTimeout);
          if (_massPingEpoch != epoch) break;

          pendingDelay[tag] = r.lastDelayValue;
          pendingBusy[tag] = '';
        } catch (_) {
          if (_massPingEpoch != epoch) break;
          pendingDelay[tag] = -1;
          pendingBusy[tag] = '';
        }
      }
    }

    final workers = List.generate(
      _pingConcurrency.clamp(1, nodes.length),
      (_) => worker(),
    );
    try {
      await Future.wait(workers);
    } finally {
      flushTimer.cancel();
      flush();
    }

    if (_massPingEpoch == epoch) {
      _massPingRunning = false;
      _addDebug(DebugSource.app, 'Mass ping finished');


      _emit(_state.copyWith(pingBatchGen: _state.pingBatchGen + 1));






      unawaited(_runAllUrltestGroups(epoch));
    }
  }

  Future<void> _runAllUrltestGroups(int epoch) async {


    final tags = _state.urltestGroups.map((g) => g.tag).toList();
    for (final tag in tags) {



      if (_massPingEpoch != epoch) return;
      await runGroupUrltest(tag);
    }






    if (_massPingEpoch == epoch) unawaited(_cc.cancelPing());
  }










  void haltAllProbing() {
    cancelMassPing();
    _autoPingTimer?.cancel();
    _autoPingTimer = null;
    ProbeLifecycle.I.haltAll();
  }









  void haltBackgroundProbing() {
    _autoPingTimer?.cancel();
    _autoPingTimer = null;
    ProbeLifecycle.I.haltAll();
  }

  void cancelMassPing() {
    if (!_massPingRunning) return;
    _massPingRunning = false;
    _massPingEpoch++;






    unawaited(_cc.cancelPing());


    _emit(_state.copyWith(pingBusy: const {}));
    _addDebug(DebugSource.app, 'Mass ping cancelled');
  }
}
