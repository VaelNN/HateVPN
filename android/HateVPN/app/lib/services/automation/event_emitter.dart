import '../../vpn/box_vpn_client.dart';
import '../app_log.dart';
import '../settings_storage.dart';




















class AutomationEventEmitter {
  AutomationEventEmitter._();
  static final AutomationEventEmitter I = AutomationEventEmitter._();


  bool _lifecycleEnabled = false;
  bool _stateEnabled = false;
  bool _subsEnabled = false;
  bool _healthEnabled = false;


  void Function(String action, Map<String, Object?> extras)? _sendOverride;


  final Map<String, DateTime> _lastEmitAt = {};


  static const Map<String, Duration> _throttleWindows = {
    'SUB_REFRESH_FAILED': Duration(minutes: 1),
  };



  Future<void> reload() async {
    _lifecycleEnabled = await SettingsStorage.getAutomationEmitLifecycle();
    _stateEnabled = await SettingsStorage.getAutomationEmitState();
    _subsEnabled = await SettingsStorage.getAutomationEmitSubs();
    _healthEnabled = await SettingsStorage.getAutomationEmitHealth();
  }


  void debugConfigureForTest({
    bool lifecycle = false,
    bool state = false,
    bool subs = false,
    bool health = false,
    void Function(String action, Map<String, Object?> extras)? onSend,
  }) {
    _lifecycleEnabled = lifecycle;
    _stateEnabled = state;
    _subsEnabled = subs;
    _healthEnabled = health;
    _sendOverride = onSend;
    _lastEmitAt.clear();
  }



  void emitVpnConnected() => _emit('VPN_CONNECTED', const {}, _lifecycleEnabled);

  void emitVpnDisconnected(String reason) =>
      _emit('VPN_DISCONNECTED', {'reason': reason}, _lifecycleEnabled);

  void emitVpnError(String code, String message) =>
      _emit('VPN_ERROR', {'code': code, 'message': message}, _lifecycleEnabled);

  void emitVpnRevoked() => _emit('VPN_REVOKED', const {}, _lifecycleEnabled);

  void emitUpdateAvailable(String version, String url) => _emit(
      'UPDATE_AVAILABLE', {'version': version, 'url': url}, _lifecycleEnabled);

  void emitPermissionNeeded(String permission) =>
      _emit('PERMISSION_NEEDED', {'permission': permission}, _lifecycleEnabled);



  void emitNodeChanged(
          String? oldTag, String newTag, String group, String reason) =>
      _emit(
          'ACTIVE_NODE_CHANGED',
          {
            'old_tag': oldTag,
            'new_tag': newTag,
            'group': group,
            'reason': reason,
          },
          _stateEnabled);

  void emitGroupChanged(String? oldGroup, String newGroup, String reason) =>
      _emit(
          'ACTIVE_GROUP_CHANGED',
          {'old_group': oldGroup, 'new_group': newGroup, 'reason': reason},
          _stateEnabled);





  void emitNodeAlreadyActive(String tag, String group) =>
      _emit('NODE_ALREADY_ACTIVE', {'tag': tag, 'group': group}, _stateEnabled);



  void emitSubRefreshed(String subId, int nodesCount, int deltaCount) => _emit(
      'SUB_REFRESHED',
      {
        'sub_id': subId,
        'nodes_count': nodesCount,
        'delta_count': deltaCount,
      },
      _subsEnabled);

  void emitSubRefreshFailed(String subId, String error) => _emit(
        'SUB_REFRESH_FAILED',
        {'sub_id': subId, 'error': error},
        _subsEnabled,
        throttleKey: 'SUB_REFRESH_FAILED:$subId',
      );







  void emitHeartbeatFailed(int consecutiveFails) =>
      _emit('HEARTBEAT_FAILED', {'fails': consecutiveFails}, _healthEnabled);

  void emitLatencyDegraded(String tag, int latencyMs) => _emit(
      'LATENCY_DEGRADED', {'tag': tag, 'latency_ms': latencyMs}, _healthEnabled);



  void _emit(
    String action,
    Map<String, Object?> extras,
    bool gateEnabled, {
    String? throttleKey,
  }) {
    if (!gateEnabled) return;



    final window = _throttleWindows[action];
    if (window != null) {
      final key = throttleKey ?? action;
      final last = _lastEmitAt[key];
      final now = DateTime.now();
      if (last != null && now.difference(last) < window) {
        final agoSec = now.difference(last).inSeconds;
        AppLog.I.info('[automation] emit $action → throttled (last ${agoSec}s ago)');
        return;
      }
      _lastEmitAt[key] = now;
    }

    final send = _sendOverride;
    if (send != null) {
      send(action, extras);
    } else {
      BoxVpnClient.I.sendAutomationBroadcast(action, extras);
    }
    AppLog.I.info('[automation] emit $action${_fmtExtras(extras)} → ok');
  }

  String _fmtExtras(Map<String, Object?> extras) {
    if (extras.isEmpty) return '';
    final parts = extras.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}=${e.value}');
    return parts.isEmpty ? '' : ' ${parts.join(' ')}';
  }
}
