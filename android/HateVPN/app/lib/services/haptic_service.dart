import 'dart:async';

import 'package:flutter/services.dart';

import 'settings_storage.dart';















class HapticService {
  HapticService({this.enabled = true, this.throttle = const Duration(milliseconds: 100)});

  static final HapticService I = HapticService();



  bool enabled;
  final Duration throttle;
  DateTime _lastFired = DateTime.fromMillisecondsSinceEpoch(0);



  Future<void> loadFromPrefs() async {
    final v = await SettingsStorage.getVar(prefsKey, 'true');
    enabled = v != 'false';
  }

  static const String prefsKey = 'haptic_enabled';



  void onConnectTap() => _fire(HapticFeedback.selectionClick);
  void onNodeSelect() => _fire(HapticFeedback.selectionClick);


  void onVpnConnected() => _fire(HapticFeedback.mediumImpact);
  void onVpnDisconnected() => _fire(HapticFeedback.lightImpact);
  void onFetchSuccess() => _fire(HapticFeedback.lightImpact);
  void onPresetApply() => _fire(HapticFeedback.mediumImpact);


  void onVpnCrashed() => _fire(HapticFeedback.heavyImpact);
  void onHeartbeatFail() => _fire(HapticFeedback.heavyImpact);
  void onFetchError() => _fire(HapticFeedback.mediumImpact);

  void _fire(Future<void> Function() impact) {
    if (!enabled) return;
    final now = DateTime.now();
    if (now.difference(_lastFired) < throttle) return;
    _lastFired = now;
    unawaited(impact());
  }
}
