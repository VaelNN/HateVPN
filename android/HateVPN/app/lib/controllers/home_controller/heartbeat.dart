part of '../home_controller.dart';






mixin _HeartbeatMixin on ChangeNotifier {

  HomeState get _state;
  BoxVpnClient get _vpn;
  void _emit(HomeState next);
  void _addDebug(DebugSource source, String message);

  void haltAllProbing();

  String? _invalidateRunningConfig();



  DateTime? get lastCcStatusAt;
  void _stopCcStreams();

  Future<void> _refreshEndpointStates();

  Timer? _heartbeat;
  int _heartbeatFailures = 0;



  static const _heartbeatInterval = Duration(seconds: 5);
  static const _heartbeatTimeout = Duration(seconds: 8);
  static const _maxHeartbeatFailures = 2;




  bool _heartbeatFailNotified = false;








  bool _skipNextHeartbeatFail = false;

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatFailures = 0;
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) => _checkHeartbeat());
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _heartbeatFailures = 0;
  }






  Future<void> _checkHeartbeat() async {
    if (!_state.tunnelUp) {
      _stopHeartbeat();
      return;
    }
    final last = lastCcStatusAt;


    if (last == null) return;

    final silence = DateTime.now().difference(last);
    if (silence <= _heartbeatTimeout) {
      _heartbeatFailures = 0;
      _skipNextHeartbeatFail = false;




      unawaited(_refreshEndpointStates());
      return;
    }




    if (_skipNextHeartbeatFail) {
      _skipNextHeartbeatFail = false;
      return;
    }

    _heartbeatFailures++;
    _addDebug(
      DebugSource.app,
      'Heartbeat: cc status silent ${silence.inSeconds}s '
      '($_heartbeatFailures/$_maxHeartbeatFailures)',
    );
    if (_heartbeatFailures >= _maxHeartbeatFailures) {
      _stopHeartbeat();
      if (!_heartbeatFailNotified) {
        HapticService.I.onHeartbeatFail();
        _heartbeatFailNotified = true;
      }
      _onTunnelDead();
    }
  }

  void _onTunnelDead() {
    _addDebug(DebugSource.app, 'Tunnel appears dead (heartbeat lost)');


    haltAllProbing();





    _stopCcStreams();



    SelectorInfo.I.clearSelected();
    _emit(
      _state.copyWith(
        tunnel: TunnelStatus.revoked,





        lastError: const ErrMsg(ErrKey.tunnelNotResponding),
        ccGroups: const <CcGroup>[],
        groups: <String>[],
        nodes: <String>[],
        highlightedNode: null,
        traffic: TrafficSnapshot.zero,
        connectedSince: null,
        configChangedNeedRestart: false,
        runningConfigRaw:
            _invalidateRunningConfig(),
      ),
    );
    unawaited(_tryCleanStop());
  }

  Future<void> _tryCleanStop() async {
    try {
      await _vpn.stopVPN();
    } catch (_) {

    }
  }
}
