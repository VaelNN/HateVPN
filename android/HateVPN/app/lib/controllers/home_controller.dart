import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/route_config.dart';
import '../vpn/box_vpn_client.dart';
import '../vpn/cc_channel.dart';
import '../config/config_parse.dart';
import '../models/direction.dart' show UrltestMode;
import '../models/home_state.dart';
import '../services/app_log.dart';
import '../services/automation/event_emitter.dart';
import '../services/config_staleness.dart';
import '../services/error_format.dart';
import '../services/file_import.dart';
import '../services/probe/probe_lifecycle.dart';
import '../services/rule_name_resolver.dart';
import '../services/selector_info.dart';
import '../services/settings_storage.dart';
import '../services/support/support_message.dart';
import '../services/template_loader.dart';
import '../services/haptic_service.dart';
import '../services/rule_set_auto_updater.dart';
import '../services/subscription/auto_updater.dart';
import '../services/core_reject/core_reject_state.dart';

part 'home_controller/config_io.dart';
part 'home_controller/heartbeat.dart';
part 'home_controller/ping_orchestration.dart';

class HomeController extends ChangeNotifier
    with _ConfigIoMixin, _HeartbeatMixin, _PingMixin {
  HomeController({
    AutoUpdater? autoUpdater,
    RuleSetAutoUpdater? ruleSetAutoUpdater,
  })  : _autoUpdater = autoUpdater,
        _ruleSetAutoUpdater = ruleSetAutoUpdater;

  @override
  final BoxVpnClient _vpn = BoxVpnClient();
  final AutoUpdater? _autoUpdater;



  final RuleSetAutoUpdater? _ruleSetAutoUpdater;
  StreamSubscription<TunnelStatusEvent>? _statusSub;



  @override
  final CcChannel _cc = CcChannel.instance;



  StreamSubscription<CcStatus>? _ccStatusSub;
  StreamSubscription<List<CcGroup>>? _ccGroupsSub;





  StreamSubscription<List<CcTailscaleStatus>>? _tailnetSub;
  String? _tailnetKey;




  bool _didColdStartResync = false;



  Map<String, String> _directionLabels = const {};




  Set<String> _roundRobinAutoTags = const {};






  Set<String> _directionAutoTags = const {};

  @override
  HomeState _state = HomeState();
  HomeState get state => _state;






  bool _disposed = false;






  bool _previewEmpty = false;
  bool get previewEmpty => _previewEmpty;
  void setPreviewEmpty(bool on) {
    if (_previewEmpty == on) return;
    _previewEmpty = on;
    notifyListeners();
  }





  SupportPreviewRequest? _supportPreview;
  void requestSupportPreview(SupportPreviewRequest req) {
    _supportPreview = req;
    notifyListeners();
  }

  SupportPreviewRequest? takeSupportPreview() {
    final r = _supportPreview;
    _supportPreview = null;
    return r;
  }



  DateTime? _lastReloadTap;
  DateTime? _lastResetNetworkTap;
  static const _recoveryCooldown = Duration(seconds: 3);



  @override
  Timer? _autoPingTimer;
















  Timer? _transientTimeoutTimer;



























  static const _defaultStoppingTimeout = Duration(seconds: 12);
  static const _defaultConnectingTimeout = Duration(seconds: 15);
  Duration _stoppingTimeout = _defaultStoppingTimeout;
  Duration _connectingTimeout = _defaultConnectingTimeout;




  ({int connectingMs, int stoppingMs}) debugSetTransientTimeouts({
    int? connectingMs,
    int? stoppingMs,
  }) {
    if (connectingMs != null) {
      _connectingTimeout = Duration(milliseconds: connectingMs);
    }
    if (stoppingMs != null) {
      _stoppingTimeout = Duration(milliseconds: stoppingMs);
    }
    _addDebug(DebugSource.app,
        '[vpn] transient timeouts set: connecting=${_connectingTimeout.inMilliseconds}ms stopping=${_stoppingTimeout.inMilliseconds}ms');
    return (
      connectingMs: _connectingTimeout.inMilliseconds,
      stoppingMs: _stoppingTimeout.inMilliseconds,
    );
  }


  ({int connectingMs, int stoppingMs}) get debugTransientTimeouts => (
        connectingMs: _connectingTimeout.inMilliseconds,
        stoppingMs: _stoppingTimeout.inMilliseconds,
      );



  Future<bool> debugForceStopVpn() => _vpn.forceStopVPN();





  Future<void> init() async {
    await _loadSavedConfig();
    await refreshDirectionLabels();
    await reloadPingOptions();
    _statusSub = _vpn.onStatusChanged.listen(_handleStatusEvent);





    final pulled = await _vpn.getVpnStatus();
    _handleStatusEvent(TunnelStatusEvent(status: pulled, raw: pulled.name));
  }




  Future<void> refreshDirectionLabels() async {
    final directions = await SettingsStorage.getDirections();
    if (_disposed) return;


    _directionLabels = {
      for (final c in directions) c.tag: c.displayLabel,
    };

    _directionAutoTags = {for (final c in directions) c.autoTag};

    _roundRobinAutoTags = {
      for (final c in directions)
        if (c.auto?.mode == UrltestMode.roundRobin) c.autoTag,
    };



    SelectorInfo.I.setFallbackTags([
      for (final c in directions) ...[c.tag, c.autoTag],
    ]);
    _emit(_state.copyWith(
      groupLabels: _directionLabels,
      directionAutoTags: _directionAutoTags,
    ));
  }



  bool isDirectionAutoTag(String tag) => _directionAutoTags.contains(tag);






  final _poolCache = <String, List<CcPoolSlot>>{};
  final _poolInFlight = <String>{};
  int _poolCacheGen = -1;



  List<CcPoolSlot>? poolSlots(String tag) {

    if (_poolCacheGen != _state.pingBatchGen) {
      _poolCacheGen = _state.pingBatchGen;
      _poolCache.clear();
      _poolInFlight.clear();
    }
    final cached = _poolCache[tag];
    if (cached != null) return cached;
    if (!_state.tunnelUp || !_poolInFlight.add(tag)) return null;
    unawaited(_fetchPool(tag));
    return null;
  }

  Future<void> _fetchPool(String tag) async {
    final slots = await _cc.getPool(tag);
    if (_disposed || slots == null) return;
    _poolCache[tag] = slots;
    notifyListeners();
  }






  bool isRoundRobinAuto(String autoTag) =>
      _roundRobinAutoTags.contains(autoTag) ||
      _state.configModel.rawOf(autoTag)?['balancer'] != null;





  Future<List<CcPoolSlot>?> getPool(String autoTag) => _cc.getPool(autoTag);

  @override
  void dispose() {
    _disposed = true;
    _stopHeartbeat();
    _autoPingTimer?.cancel();
    _transientTimeoutTimer?.cancel();
    _statusSub?.cancel();
    _ccStatusSub?.cancel();
    _ccGroupsSub?.cancel();
    _groupsPullTimer?.cancel();
    _tailnetSub?.cancel();
    if (_tailnetKey != null) unawaited(_cc.releaseTailscaleStatus());
    super.dispose();
  }





  @override
  void _emit(HomeState next) {





    if (_disposed) return;
    _state = next;
    notifyListeners();
    _syncTailnetStatus();
  }





  void _syncTailnetStatus() {
    final s = _state;
    final nodes = s.tunnelUp ? s.networksNodes : const <String>[];
    final key = nodes.isEmpty
        ? null
        : '${nodes.join('\n')}|${s.runningConfigRaw?.hashCode}';
    if (key == _tailnetKey) return;
    final wasActive = _tailnetKey != null;
    _tailnetKey = key;
    if (key == null) {

      unawaited(_cc.releaseTailscaleStatus());
      if (s.tailscaleStatus.isNotEmpty) {
        _emit(s.copyWith(tailscaleStatus: const <String, CcTailscaleStatus>{}));
      }
      return;
    }


    _tailnetSub ??= _cc.tailscaleStatus.listen((list) {
      if (_tailnetKey == null) return;


      final prev = _state.tailscaleStatus;
      final same = prev.length == list.length &&
          list.every((e) =>
              prev[e.tag]?.backendState == e.backendState &&
              prev[e.tag]?.stateText == e.stateText &&
              prev[e.tag]?.peers.length == e.peers.length);
      if (same) return;
      _emit(_state.copyWith(tailscaleStatus: {for (final e in list) e.tag: e}));
    }, onError: (Object e) {
      _addDebug(DebugSource.app, 'cc tailscale stream error: $e');
    });
    if (wasActive) {
      _addDebug(DebugSource.app, 'Tailscale status: resubscribe');
      unawaited(_cc.restartTailscaleStatus());
    } else {
      unawaited(_cc.acquireTailscaleStatus());
    }
  }



  void openNetworks() {
    if (_state.networksOpen) return;
    _emit(_state.copyWith(networksOpen: true));
  }

  @override
  void _addDebug(DebugSource source, String message) {
    AppLog.I.log(
      source == DebugSource.core ? DebugLevel.info : DebugLevel.debug,
      message,
      source: source,
    );
  }







  @visibleForTesting
  void debugHandleStatusEvent(TunnelStatusEvent event) =>
      _handleStatusEvent(event);





  @visibleForTesting
  void debugSeedNodeState({
    required String group,
    required String activeNode,
    bool tunnelUp = true,
    List<String>? groups,
    Map<String, Map<String, int>>? delayByDirection,
  }) =>
      _emit(_state.copyWith(
        tunnel: tunnelUp ? TunnelStatus.connected : TunnelStatus.disconnected,
        selectedGroup: group,
        activeInGroup: activeNode,
        highlightedNode: activeNode,
        groups: groups ?? <String>[group],
        delayByDirection: delayByDirection,
      ));

  void _handleStatusEvent(TunnelStatusEvent event) {
    final tunnel = event.status;
    final prevTunnel = _state.tunnel;
    _addDebug(DebugSource.core,
        'status=${event.raw}${event.errorReason != null ? " reason=${event.errorReason}" : ""}');
    _addDebug(DebugSource.app,
        '[vpn] _handleStatusEvent raw="${event.raw}" tunnel=${tunnel.name} prev=${prevTunnel.name} need_restart_before=${_state.configChangedNeedRestart}');






    if (tunnel == TunnelStatus.connected) {

      _settleStartOutcome(null);
      _emit(_state.copyWith(
        tunnel: tunnel,
        connectedSince: DateTime.now(),
        configChangedNeedRestart: false,



        runningConfigRaw: prevTunnel == TunnelStatus.connected
            ? _state.runningConfigRaw
            : _invalidateRunningConfig(),


        lastStartError: '',
        lastStartErrorAt: null,
      ));




      unawaited(_syncUptimeFromNative());



      if (prevTunnel != TunnelStatus.connected) {
        unawaited(_captureRunningConfig());
      }


      unawaited(_startCcStreams());





      unawaited(SettingsStorage.getCustomRules().then((r) =>
          RuleNameResolver.I
              .setRules(r, template: TemplateLoader.cachedOrNull())));
      _startHeartbeat();
      _heartbeatFailNotified = false;
      HapticService.I.onVpnConnected();

      _autoUpdater?.onVpnConnected();

      _ruleSetAutoUpdater?.onVpnConnected();
      unawaited(_scheduleAutoPing());

      AutomationEventEmitter.I.emitVpnConnected();
    } else if (tunnel == TunnelStatus.disconnected ||
        tunnel == TunnelStatus.revoked) {






      if (prevTunnel == TunnelStatus.disconnected ||
          prevTunnel == TunnelStatus.revoked) {
        _addDebug(DebugSource.app,
            '[vpn] stale terminal ignored (tunnel=${tunnel.name} prev=${prevTunnel.name})');


        if (tunnel != prevTunnel) _emit(_state.copyWith(tunnel: tunnel));
        _transientTimeoutTimer?.cancel();
        _transientTimeoutTimer = null;



        final rawError = event.coreError ?? event.errorReason;
        if (rawError != null && rawError.isNotEmpty) {
          _settleStartOutcome(rawError);
        }
        return;
      }
      _stopHeartbeat();


      CoreRejectState.I.dismissBanner();





      haltAllProbing();


      _stopCcStreams();

      RuleNameResolver.I.clear();


      SelectorInfo.I.clearSelected();




      final stopReason = StopReason.fromEvent(
          revoked: tunnel == TunnelStatus.revoked,
          errorReason: event.errorReason);
      final reasonEn = stopReason?.renderEn() ?? '';










      _settleStartOutcome(event.coreError ?? event.errorReason ?? '');

      _disabledEndpoints.clear();
      _emit(
        _state.copyWith(
          tunnel: tunnel,
          lastError: stopReason != null
              ? StopReasonMsg(stopReason)
              : _state.lastError,
          stopReason: stopReason ?? _state.stopReason,





          lastStartError:
              reasonEn.isNotEmpty ? reasonEn : _state.lastStartError,
          lastStartErrorAt:
              reasonEn.isNotEmpty ? DateTime.now() : _state.lastStartErrorAt,
          ccGroups: const <CcGroup>[],
          groups: <String>[],
          nodes: <String>[],
          highlightedNode: null,
          traffic: TrafficSnapshot.zero,
          connectedSince: null,
          configChangedNeedRestart: false,
          runningConfigRaw: _invalidateRunningConfig(),

          endpointStates: const <String, String>{},
          endpointIdleSince: const <String, int>{},
        ),
      );


      if (prevTunnel == TunnelStatus.connected) {
        if (tunnel == TunnelStatus.revoked) {
          HapticService.I.onVpnCrashed();
        } else {
          HapticService.I.onVpnDisconnected();
        }


        _autoUpdater?.onVpnStopped();
      }
      if (reasonEn.isNotEmpty) {
        _addDebug(DebugSource.core, reasonEn);
      }



      if (tunnel == TunnelStatus.revoked) {
        AutomationEventEmitter.I.emitVpnRevoked();
        AutomationEventEmitter.I.emitVpnDisconnected('revoked');
      } else if (event.errorReason != null) {
        AutomationEventEmitter.I.emitVpnError('tunnel_error', event.errorReason!);
        AutomationEventEmitter.I.emitVpnDisconnected('error');
      } else {
        AutomationEventEmitter.I.emitVpnDisconnected('user');
      }
    } else if (tunnel == TunnelStatus.stopping || tunnel == TunnelStatus.connecting) {
      _stopHeartbeat();
      _emit(_state.copyWith(tunnel: tunnel));
      _armTransientTimeout(tunnel);
      return;
    } else {
      _stopHeartbeat();
      _emit(_state.copyWith(tunnel: tunnel));
    }


    _transientTimeoutTimer?.cancel();
    _transientTimeoutTimer = null;
  }












  static const _connectingTimeoutPerEndpoint = Duration(seconds: 10);




  static const _connectingTimeoutCap = Duration(minutes: 4);





  int get _configEndpointCount =>
      _state.configModel.nodes.where((n) => n.kind == 'endpoint').length;





  Duration get _effectiveConnectingTimeout {
    if (_connectingTimeout != _defaultConnectingTimeout) {
      return _connectingTimeout;
    }
    final scaled = _connectingTimeout +
        _connectingTimeoutPerEndpoint * _configEndpointCount;
    return scaled > _connectingTimeoutCap ? _connectingTimeoutCap : scaled;
  }



  ({int connectingMs, int endpoints}) get debugEffectiveConnectingTimeout => (
        connectingMs: _effectiveConnectingTimeout.inMilliseconds,
        endpoints: _configEndpointCount,
      );





  @visibleForTesting
  void debugSetConfigRaw(String raw) =>
      _emit(_state.copyWith(configRaw: raw));






  void _armTransientTimeout(TunnelStatus expected) {
    _transientTimeoutTimer?.cancel();
    final timeout = expected == TunnelStatus.connecting
        ? _effectiveConnectingTimeout
        : _stoppingTimeout;



    final endpointsAtArm = _configEndpointCount;
    if (expected == TunnelStatus.connecting) {
      _addDebug(
          DebugSource.app,
          '[vpn] connecting timeout armed: ${timeout.inMilliseconds}ms '
          '(endpoints=$endpointsAtArm)');
    }
    _transientTimeoutTimer = Timer(timeout, () async {
      if (_state.tunnel != expected) return;
      _addDebug(
          DebugSource.app, 'Timeout in ${expected.name}, forcing disconnect');







      await _vpn.forceStopVPN();
      if (_disposed) return;
      _addDebug(DebugSource.app, '[vpn] forceStopVPN sent (timeout in ${expected.name})');
      if (_state.tunnel != expected) return;


      SelectorInfo.I.clearSelected();








      final timedOutStart = expected == TunnelStatus.connecting;
      final reason = timedOutStart
          ? StopStartTimeout(
              seconds: timeout.inSeconds, endpoints: endpointsAtArm)
          : null;
      if (reason != null) {
        _addDebug(DebugSource.app, reason.renderEn());
      }
      _disabledEndpoints.clear();
      _emit(_state.copyWith(
        tunnel: TunnelStatus.disconnected,
        lastError: reason != null
            ? StopReasonMsg(reason)
            : const ErrMsg(ErrKey.connectionTimedOut),
        stopReason: reason ?? _state.stopReason,

        lastStartError: reason?.renderEn() ?? _state.lastStartError,
        lastStartErrorAt: reason != null ? DateTime.now() : _state.lastStartErrorAt,
        ccGroups: const <CcGroup>[],
        groups: <String>[],
        nodes: <String>[],
        traffic: TrafficSnapshot.zero,
        connectedSince: null,
        configChangedNeedRestart: false,
        runningConfigRaw: _invalidateRunningConfig(),

        endpointStates: const <String, String>{},
        endpointIdleSince: const <String, int>{},
      ));


      if (timedOutStart) _settleStartOutcome(reason!.renderEn());
    });
  }










































  Future<bool> _stopInternal() async {
    final ok = await _vpn.stopVPN();
    _addDebug(DebugSource.app, '[vpn] stopVPN returned $ok');
    if (ok) {


      _emit(_state.copyWith(configChangedNeedRestart: false));
    }
    return ok;
  }


  Future<void> _pushNotificationLabels() async {
    await _vpn.setNotificationTitle('HateVPN');
    await _vpn.setNotificationText('');
  }







  Completer<String?>? _startOutcome;


  void _settleStartOutcome(String? error) {
    final c = _startOutcome;
    if (c == null || c.isCompleted) return;
    _startOutcome = null;
    c.complete(error);
  }




  Future<String?> startAndAwaitVerdict({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final existing = _startOutcome;
    if (existing != null && !existing.isCompleted) {
      return existing.future.timeout(timeout, onTimeout: () => '');
    }
    final c = Completer<String?>();
    _startOutcome = c;
    await start();
    if (_state.tunnel == TunnelStatus.connected) {
      _settleStartOutcome(null);
      return null;
    }

    if (!c.isCompleted &&
        _state.tunnel == TunnelStatus.disconnected &&
        _state.lastError != null) {
      _settleStartOutcome(_state.lastError!.renderEn());
      return c.future;
    }
    return c.future.timeout(timeout, onTimeout: () {


      if (!c.isCompleted) {
        if (_startOutcome == c) _startOutcome = null;
        c.complete('');
      }
      return '';
    });
  }




  Future<String?> startAndAwaitVerdictHeadless({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final existing = _startOutcome;
    if (existing != null && !existing.isCompleted) {
      return existing.future.timeout(timeout, onTimeout: () => '');
    }
    final c = Completer<String?>();
    _startOutcome = c;
    final r = await _vpn.startVpnHeadless();
    if (!r.started) {


      _settleStartOutcome('');
      return c.future;
    }
    if (_state.tunnel == TunnelStatus.connected) {
      _settleStartOutcome(null);
      return null;
    }
    return c.future.timeout(timeout, onTimeout: () {
      if (!c.isCompleted) {
        if (_startOutcome == c) _startOutcome = null;
        c.complete('');
      }
      return '';
    });
  }

  Future<bool> _startInternal() async {
    await _pushNotificationLabels();
    final ok = await _vpn.startVPN();
    _addDebug(DebugSource.app, '[vpn] startVPN returned $ok');
    if (ok) {


      _emit(_state.copyWith(configChangedNeedRestart: false));
    }
    return ok;
  }

  Future<void> start() async {
    _emit(_state.copyWith(busy: true, lastError: null));
    try {
      final ok = await _startInternal();
      if (!ok) {
        _emit(_state.copyWith(lastError: const ErrMsg(ErrKey.failedToStartVpn)));
      }
    } catch (e) {
      _emit(_state.copyWith(lastError: formatUserError(e)));
      _addDebug(DebugSource.app, 'startVPN exception: $e');
    } finally {
      _emit(_state.copyWith(busy: false));
    }
  }

  Future<void> stop() async {







    CoreRejectState.I.cancelRun();
    _emit(_state.copyWith(busy: true, lastError: null));
    try {
      final ok = await _stopInternal();
      if (!ok) {
        _emit(_state.copyWith(lastError: const ErrMsg(ErrKey.stopTimedOut)));
      }
    } catch (e) {
      _emit(_state.copyWith(lastError: formatUserError(e)));
      _addDebug(DebugSource.app, 'stopVPN exception: $e');
    } finally {
      _emit(_state.copyWith(busy: false));
    }
  }




  bool get canReload =>
      _state.tunnel == TunnelStatus.connected &&
      (_lastReloadTap == null ||
          DateTime.now().difference(_lastReloadTap!) > _recoveryCooldown);



  Future<void> reloadVpn() async {
    if (!canReload) return;
    final prevReloadTap = _lastReloadTap;
    _lastReloadTap = DateTime.now();
    notifyListeners();








    final staleSnapshot = _state.runningConfigRaw;
    _emit(_state.copyWith(runningConfigRaw: _invalidateRunningConfig()));
    try {
      final ok = await _vpn.reloadVPN();
      _addDebug(DebugSource.app, '[vpn] reload → ok=$ok');






      if (ok && !_disposed) {
        _emit(_state.copyWith(configChangedNeedRestart: false));
      }
    } catch (e) {
      _lastReloadTap = prevReloadTap;
      _addDebug(DebugSource.app, '[vpn] reload error: $e');
      if (!_disposed) {
        _emit(_state.copyWith(
            lastError: PrefixedMsg(ErrPrefix.reloadFailed, formatUserError(e))));
      }
      return;
    }











    unawaited(_captureRunningConfig(staleRaw: staleSnapshot));





















    unawaited(() async {
      await pullToRefresh();
      await _scheduleAutoPing();
    }());




    Future.delayed(_recoveryCooldown, () {
      if (!_disposed && _lastReloadTap != null) notifyListeners();
    });
  }



  Future<bool> resetNetwork() async {
    if (_state.tunnel != TunnelStatus.connected) return false;
    if (_lastResetNetworkTap != null &&
        DateTime.now().difference(_lastResetNetworkTap!) < _recoveryCooldown) {
      return false;
    }
    _lastResetNetworkTap = DateTime.now();
    final ok = await _vpn.resetNetwork();
    _addDebug(DebugSource.app, '[vpn] resetNetwork → ok=$ok');
    return ok;
  }







  Future<void> reconnect() async {
    final wasUp = _state.tunnel == TunnelStatus.connected ||
        _state.tunnel == TunnelStatus.connecting;
    if (!wasUp) {
      await start();
      return;
    }
    _emit(_state.copyWith(busy: true, lastError: null));
    try {
      final stopped = await _stopInternal();
      if (!stopped) {
        _emit(_state.copyWith(
            lastError: const ErrMsg(ErrKey.stopTimedOutReconnectAborted)));
        _addDebug(DebugSource.app, 'reconnect: stop timed out, aborting start');
        return;
      }
      final started = await _startInternal();
      if (!started) {
        _emit(_state.copyWith(lastError: const ErrMsg(ErrKey.failedToStartVpn)));
      }
    } catch (e) {
      _emit(_state.copyWith(lastError: formatUserError(e)));
      _addDebug(DebugSource.app, 'reconnect exception: $e');
    } finally {
      _emit(_state.copyWith(busy: false));
    }
  }







  DateTime? _lastCcStatusAt;
  @override
  DateTime? get lastCcStatusAt => _lastCcStatusAt;






  Future<void> _syncUptimeFromNative() async {
    final uptimeMs = await _vpn.getTunnelUptimeMs();
    if (_disposed || _state.tunnel != TunnelStatus.connected) return;
    if (uptimeMs < 2000) return;
    final realStart = DateTime.now().subtract(Duration(milliseconds: uptimeMs));
    _emit(_state.copyWith(connectedSince: realStart));
  }




  Future<void> _startCcStreams() async {
    _ccStatusSub?.cancel();
    _ccGroupsSub?.cancel();






    _ccStatusSub = _cc.status.listen(_onCcStatus, onError: (Object e) {
      _addDebug(DebugSource.app, 'cc status stream error: $e');
    });
    _ccGroupsSub = _cc.groups.listen(_onCcGroups, onError: (Object e) {
      _addDebug(DebugSource.app, 'cc groups stream error: $e');
    });












    if (!_didColdStartResync) {
      _didColdStartResync = true;
      await _cc.resyncForReopen();
      if (_disposed || !_state.tunnelUp) return;
    }

    unawaited(_cc.connectScreen());






    _startGroupsPull();
  }


  bool _fetchingRunningConfig = false;






  static const _reloadCapturePause = Duration(milliseconds: 1200);









  int _runningConfigEpoch = 0;





  @override
  String? _invalidateRunningConfig() {
    _runningConfigEpoch++;
    return null;
  }
















  Future<void> _captureRunningConfig({String? staleRaw}) async {
    if (_disposed || _fetchingRunningConfig) return;
    if (!_state.tunnelUp) return;
    _fetchingRunningConfig = true;
    final epoch = _runningConfigEpoch;
    try {






      if (staleRaw != null) await Future<void>.delayed(_reloadCapturePause);




      String? echoedRaw;
      for (var attempt = 0; attempt < _groupsPullMaxAttempts; attempt++) {
        final raw = await _cc.getRunningConfig();

        if (_disposed || !_state.tunnelUp) return;



        if (epoch != _runningConfigEpoch) {
          _addDebug(DebugSource.app,
              '[cc] running config dropped (epoch $epoch → $_runningConfigEpoch)');
          return;
        }
        if (raw != null && raw != staleRaw) {
          _emit(_state.copyWith(runningConfigRaw: raw));
          _addDebug(DebugSource.app,
              '[cc] running config captured (${raw.length} bytes)');
          _reapplyDisabledEndpoints();
          return;
        }

        if (raw != null) echoedRaw = raw;
        await Future<void>.delayed(_groupsPullStep);
      }






      if (echoedRaw != null && epoch == _runningConfigEpoch && !_disposed) {
        _emit(_state.copyWith(runningConfigRaw: echoedRaw));
        _addDebug(DebugSource.app,
            '[cc] running config unchanged after reload (${echoedRaw.length} bytes)');
        _reapplyDisabledEndpoints();
      } else if (!_disposed) {
        _addDebug(DebugSource.app,
            '[cc] running config unavailable after $_groupsPullMaxAttempts attempts');
      }
    } finally {
      _fetchingRunningConfig = false;
    }
  }

  Timer? _groupsPullTimer;



  static const _groupsPullStep = Duration(milliseconds: 400);
  static const _groupsPullMaxAttempts = 12;

  void _startGroupsPull([int attempt = 0]) {
    _groupsPullTimer?.cancel();
    _groupsPullTimer = Timer(_groupsPullStep, () async {
      if (!_state.tunnelUp) return;

      if (_state.ccGroups.isNotEmpty) return;
      final groups = await _cc.getGroups();
      if (_disposed || !_state.tunnelUp) return;
      if (groups == null) {

        if (attempt + 1 < _groupsPullMaxAttempts) {
          _startGroupsPull(attempt + 1);
        } else {
          _addDebug(DebugSource.app,
              '[cc] getGroups still unavailable after $_groupsPullMaxAttempts attempts');
        }
        return;
      }
      if (groups.isEmpty) {


        _addDebug(DebugSource.app, '[cc] getGroups → empty (no selector groups)');
        _applyGroups(groups);
        return;
      }
      _addDebug(DebugSource.app,
          '[cc] getGroups pull → ${groups.length} groups');
      _applyGroups(groups);
    });
  }










  @override
  Future<void> _refreshEndpointStates() async {
    final list = await _cc.getOutbounds();
    if (_disposed || !_state.tunnelUp) return;
    if (list == null) return;
    final next = <String, String>{};
    final idle = <String, int>{};
    for (final o in list) {
      if (o.endpointState.isEmpty) continue;
      next[o.tag] = o.endpointState;

      if (o.endpointState == CcEndpointState.asleep) {
        idle[o.tag] = o.idleSinceSeconds;
      }
    }



    final drifted = [
      for (final t in _disabledEndpoints)
        if (next[t] != null && next[t] != CcEndpointState.disabled) t,
    ];
    if (drifted.isNotEmpty) unawaited(_disableEndpoints(drifted));

    final prev = _state.endpointStates;
    final prevIdle = _state.endpointIdleSince;
    if (next.length == prev.length &&
        next.entries.every((e) => prev[e.key] == e.value) &&
        idle.length == prevIdle.length &&
        idle.entries.every((e) => prevIdle[e.key] == e.value)) {
      return;
    }
    _emit(_state.copyWith(endpointStates: next, endpointIdleSince: idle));
  }





  final Set<String> _disabledEndpoints = <String>{};






  Future<String?> setEndpointEnabled(String tag, bool enabled) async {
    if (!_state.tunnelUp) return 'failed_precondition';


    if (enabled) _disabledEndpoints.remove(tag);
    final String st;
    try {
      st = await _cc.setEndpointEnabled(tag, enabled);
    } on PlatformException catch (e) {
      if (enabled && e.code != 'not_found') _disabledEndpoints.add(tag);
      _addDebug(DebugSource.app,
          '[cc] setEndpointEnabled($tag, $enabled) → ${e.code}: ${e.message}');
      return e.code;
    } on MissingPluginException {
      if (enabled) _disabledEndpoints.add(tag);
      return 'error';
    }
    if (_disposed) return null;
    if (!enabled) _disabledEndpoints.add(tag);
    _addDebug(DebugSource.app, '[cc] setEndpointEnabled($tag, $enabled) → $st');
    _patchEndpointState(tag, st);
    return null;
  }


  void _patchEndpointState(String tag, String st) {
    if (st.isEmpty || !_state.tunnelUp) return;
    final next = Map<String, String>.of(_state.endpointStates)..[tag] = st;
    final idle = Map<String, int>.of(_state.endpointIdleSince);
    if (st != CcEndpointState.asleep) idle.remove(tag);
    _emit(_state.copyWith(endpointStates: next, endpointIdleSince: idle));
  }





  void _reapplyDisabledEndpoints() {
    if (_disabledEndpoints.isEmpty) return;
    unawaited(_disableEndpoints(_disabledEndpoints.toList()));
  }

  Future<void> _disableEndpoints(List<String> tags) async {
    final epoch = _runningConfigEpoch;
    for (final tag in tags) {
      if (_disposed || !_state.tunnelUp || epoch != _runningConfigEpoch) return;
      if (!_disabledEndpoints.contains(tag)) continue;
      try {
        final st = await _cc.setEndpointEnabled(tag, false);
        if (_disposed || !_disabledEndpoints.contains(tag)) continue;
        _patchEndpointState(tag, st);
      } on PlatformException catch (e) {
        if (e.code == 'not_found' || e.code == 'invalid_argument') {
          _disabledEndpoints.remove(tag);
        }
        _addDebug(DebugSource.app,
            '[cc] re-disable $tag → ${e.code}: ${e.message}');
      } on MissingPluginException {
        return;
      }
    }
  }


  @override
  void _stopCcStreams() {
    _ccStatusSub?.cancel();
    _ccStatusSub = null;
    _ccGroupsSub?.cancel();
    _ccGroupsSub = null;
    _groupsPullTimer?.cancel();
    _groupsPullTimer = null;
    _lastCcStatusAt = null;


    _cc.resetCaches();
    unawaited(_cc.disconnectScreen());
  }





  static const _trafficEmitThrottle = Duration(seconds: 1);
  DateTime? _lastTrafficEmitAt;



  void _onCcStatus(CcStatus s) {
    if (!_state.tunnelUp) return;
    final now = DateTime.now();

    _lastCcStatusAt = now;
    _heartbeatFailures = 0;

    if (_lastTrafficEmitAt != null &&
        now.difference(_lastTrafficEmitAt!) < _trafficEmitThrottle) {
      return;
    }
    _lastTrafficEmitAt = now;
    _emit(_state.copyWith(
      traffic: TrafficSnapshot(
        uploadTotal: s.uplinkTotal,
        downloadTotal: s.downlinkTotal,
        activeConnections: s.connectionsIn + s.connectionsOut,
        connectionsIn: s.connectionsIn,
        connectionsOut: s.connectionsOut,
        memory: s.memory,

        byRule: _state.traffic.byRule,
        byApp: _state.traffic.byApp,
      ),
    ));
  }




  void _onCcGroups(List<CcGroup> groups) {
    if (!_state.tunnelUp) return;











    if (groups.isEmpty && _state.ccGroups.isNotEmpty) {
      _addDebug(DebugSource.app,
          '[cc] empty groups push ignored (have ${_state.ccGroups.length} live)');
      return;
    }
    _applyGroups(groups);
  }




  void _applyGroups(List<CcGroup> ccGroups) {







    SelectorInfo.I.setGroups({
      for (final g in ccGroups)
        if (g.selected.isNotEmpty) g.tag: g.selected,
    });


    var next = _state.copyWith(ccGroups: ccGroups);

    final groups = next.selectorGroupTags
        .where((name) => name != 'GLOBAL')
        .toList();

    String? initial = next.selectedGroup;
    if (initial == null || !groups.contains(initial)) {




      final finalTag = RouteConfig.finalTag(next.configRaw);
      if (finalTag != null && groups.contains(finalTag)) {
        initial = finalTag;
      } else {
        initial = groups.isNotEmpty ? groups.first : null;
      }
    }

    _emit(next.copyWith(
        groups: groups, groupLabels: _directionLabels, selectedGroup: initial));
    unawaited(applyGroup(initial));


    _recomputeDependencyHealth();
  }



  @override
  Future<void> reloadProxies() async {
    if (!_state.tunnelUp) return;
    _applyGroups(_state.ccGroups);
  }




  DependencyGraph _depGraph = const DependencyGraph.empty();
  String _depGraphRaw = '';



  DependencyGraph _ensureDepGraph() {
    final raw = _state.activeConfigRaw;
    if (raw != _depGraphRaw) {
      _depGraphRaw = raw;
      _depGraph = DependencyGraph.fromConfig(raw);
    }
    return _depGraph;
  }



  List<DependentRef> directDependentsOf(String tag) =>
      _ensureDepGraph().directDependents(tag);








  @override
  void _recomputeDependencyHealth() {
    _ensureDepGraph();
    final selections = <String, String>{
      for (final g in _state.ccGroups)
        if (g.selectable && g.selected.isNotEmpty) g.tag: g.selected,
    };
    final sick = _depGraph.computeSick(
      selections: selections,
      delays: _state.delayByDirection,
    );
    if (_sickRootsEqual(sick, _state.sickRoots)) return;

    final prevDnsVictims = <String>{
      for (final list in _state.sickRoots.values)
        for (final d in list)
          if (d.isDns) d.tag,
    };
    DnsViaDeadNodeMsg? banner;
    for (final e in sick.entries) {
      for (final d in e.value) {
        if (d.isDns && !prevDnsVictims.contains(d.tag)) {
          banner = DnsViaDeadNodeMsg(d.tag, e.key, d.via ?? '');
          break;
        }
      }
      if (banner != null) break;
    }
    final hasDnsVictims =
        sick.values.any((list) => list.any((d) => d.isDns));
    if (banner != null) {
      _addDebug(DebugSource.app, banner.renderEn());
      _emit(_state.copyWith(sickRoots: sick, lastError: banner));
    } else if (!hasDnsVictims && _state.lastError is DnsViaDeadNodeMsg) {
      _emit(_state.copyWith(sickRoots: sick, lastError: null));
    } else {
      _emit(_state.copyWith(sickRoots: sick));
    }
  }

  static bool _sickRootsEqual(
    Map<String, List<DependentRef>> a,
    Map<String, List<DependentRef>> b,
  ) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final other = b[e.key];
      if (other == null || !listEquals(e.value, other)) return false;
    }
    return true;
  }





  Future<void> pullToRefresh() async {
    if (!_state.tunnelUp) {
      _applyGroups(_state.ccGroups);
      return;
    }
    final groups = await _cc.getGroups();
    if (!_state.tunnelUp) return;
    if (groups != null) {
      _applyGroups(groups);
    } else {
      _applyGroups(_state.ccGroups);
    }
  }

  Future<void> applyGroup(String? tag) async {
    if (tag == null) {
      _emit(
        _state.copyWith(
          nodes: <String>[],
          activeInGroup: null,
          highlightedNode: null,
        ),
      );
      return;
    }
    final group = _state.groupOf(tag);
    if (group == null) return;
    final nodes = group.items.map((e) => e.tag).toList();
    final now = group.selected.isEmpty ? null : group.selected;
    _emit(
      _state.copyWith(
        nodes: nodes,
        activeInGroup: now,
        highlightedNode: now,
      ),
    );



    BoxVpnClient.I.setAutomationActiveState(
      node: now,
      group: tag,
      nodes: nodes,
      groups: _state.groups,
    );

    await _pushNotificationLabels();
  }





  void Function(String group, String node)? onMemberSelected;




  Future<bool> selectInGroup(String group, String nodeTag) async {
    if (group == _state.selectedGroup) {
      await switchNode(nodeTag);
      return _state.activeInGroup == nodeTag;
    }
    if (!_state.tunnelUp) return false;
    try {
      final ok = await _cc.selectOutbound(group, nodeTag);
      if (!ok) return false;
      final fresh = await _cc.getGroups();
      if (fresh != null) _applyGroups(fresh);
      _addDebug(DebugSource.app, 'Node selected in $group: $nodeTag');
      onMemberSelected?.call(group, nodeTag);
      return true;
    } catch (e) {
      _addDebug(DebugSource.app, 'Node switch error: $e');
      return false;
    }
  }

  Future<void> switchNode(String nodeTag) async {
    final group = _state.selectedGroup;
    if (group == null || !_state.tunnelUp) return;
    final prevNode = _state.activeInGroup;





    if (prevNode == nodeTag) {
      AutomationEventEmitter.I.emitNodeAlreadyActive(nodeTag, group);
      return;
    }
    _emit(_state.copyWith(busy: true, highlightedNode: nodeTag));
    try {


      final ok = await _cc.selectOutbound(group, nodeTag);
      if (!ok) throw const FormatException('selectOutbound rejected');




      if (await SettingsStorage.getInterruptOnSwitch()) {
        try {
          final ids = await _connectionIdsInGroup(group);
          await Future(() async {
            for (final id in ids) {
              try {
                await _cc.closeConnection(id);
              } catch (_) { }
            }
          }).timeout(const Duration(seconds: 5), onTimeout: () {});
          _addDebug(
              DebugSource.app, 'Interrupted ${ids.length} conns in $group');
        } catch (e) {
          _addDebug(DebugSource.app, 'Interrupt-on-switch failed: $e');
        }
      }






      final fresh = await _cc.getGroups();
      if (fresh != null) {
        _applyGroups(fresh);
      } else {

        _applyGroups(_state.ccGroups);
        _emit(_state.copyWith(activeInGroup: nodeTag));
      }
      _addDebug(DebugSource.app, 'Node selected: $nodeTag');
      onMemberSelected?.call(group, nodeTag);


      AutomationEventEmitter.I
          .emitNodeChanged(prevNode, nodeTag, group, 'user');

      BoxVpnClient.I.setAutomationActiveState(node: nodeTag, group: group);
    } catch (e) {
      _emit(_state.copyWith(
          lastError: PrefixedMsg(ErrPrefix.switchFailed, formatUserError(e))));
      _addDebug(DebugSource.app, 'Node switch error: $e');
    } finally {
      _emit(_state.copyWith(busy: false));
    }
  }















  Future<List<String>> _connectionIdsInGroup(String group) async {
    final conns = await _cc.connections.first
        .timeout(const Duration(seconds: 1), onTimeout: () => const []);
    return conns
        .where((c) => !c.isClosed && c.chains.contains(group))
        .map((c) => c.id)
        .where((id) => id.isNotEmpty)
        .toList();
  }










  void setSelectedGroup(String? group) {
    final prevGroup = _state.selectedGroup;


    _emit(_state.copyWith(
      selectedGroup: group,
      pingBatchGen: _state.pingBatchGen + 1,
      networksOpen: false,
    ));


    if (group != null && group != prevGroup) {
      AutomationEventEmitter.I.emitGroupChanged(prevGroup, group, 'user');
    }
  }

  void setHighlightedNode(String nodeTag) {
    _emit(_state.copyWith(highlightedNode: nodeTag));
  }

  void cycleSortMode() {


    _emit(_state.copyWith(sortMode: _state.sortMode.next));
    _persistSort();
  }




  void setSortMode(NodeSortMode mode) {
    if (mode == _state.sortMode) return;
    _emit(_state.copyWith(sortMode: mode));
    _persistSort();
  }


  void _persistSort() {
    unawaited(
        SettingsStorage.setNodeSort(_state.sortMode.name, _state.manualOrder));
  }


  void setPinDirect(bool v) => _emit(_state.copyWith(pinDirect: v));
  void setPinAuto(bool v) => _emit(_state.copyWith(pinAuto: v));
  void setResortOnManualPing(bool v) =>
      _emit(_state.copyWith(resortOnManualPing: v));







  void markConfigChangedNeedRestart() {
    if (_state.tunnelUp) {
      _emit(_state.copyWith(configChangedNeedRestart: true));
    }
  }




  void commitManualReorder(List<String> newOrder) {
    _emit(_state.copyWith(
      sortMode: NodeSortMode.manual,
      manualOrder: List<String>.unmodifiable(newOrder),
    ));
    _persistSort();
  }

  void clearError() {
    if (_state.lastError != null) {
      _emit(_state.copyWith(lastError: null));
    }
  }











  void onAppResumed() {
    unawaited(_resyncOnResume());
  }











  void onAppPaused() {
    _stopHeartbeat();






    haltBackgroundProbing();



    if (_state.tunnelUp) unawaited(_cc.pauseClients());
  }

  Future<void> _resyncOnResume() async {
    try {
      final native = await _vpn.getVpnStatus();
      if (native != _state.tunnel) {
        _addDebug(DebugSource.app,
            '[vpn] onAppResumed: divergence native=${native.name} state=${_state.tunnel.name} — re-sync');
        _handleStatusEvent(TunnelStatusEvent(status: native, raw: native.name));
      }
    } catch (e) {
      _addDebug(DebugSource.app, '[vpn] onAppResumed pull error: $e');
    }



    if (_state.tunnelUp) unawaited(_cc.resumeClients());





    if (_state.tunnelUp) {




      _addDebug(DebugSource.app,
          'Resumed from background — re-syncing tunnel (heartbeat/streams were paused)');
      _skipNextHeartbeatFail = true;
      _startHeartbeat();
      unawaited(_checkHeartbeat());
    }
  }
}

