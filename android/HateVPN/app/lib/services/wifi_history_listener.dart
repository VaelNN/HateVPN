import 'package:flutter/services.dart';

import 'platform_channels.dart';
import 'settings_storage.dart';




















class WifiHistoryListener {
  WifiHistoryListener._();

  static final WifiHistoryListener I = WifiHistoryListener._();

  static const _channel = MethodChannel(PlatformChannels.wifiHistory);
  static const _utilsChannel = MethodChannel(PlatformChannels.utils);

  bool _initialized = false;



  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_onCall);




    final enabled = await SettingsStorage.getAutoRecordWifi();
    if (enabled) {
      await setEnabled(true);
    }
  }



  Future<void> dispose() async {
    if (!_initialized) return;
    _initialized = false;
    _channel.setMethodCallHandler(null);
    await setEnabled(false);
  }

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method != 'onWifiSeen') return null;
    final args = (call.arguments as Map?)?.cast<String, dynamic>();
    if (args == null) return null;
    final ssid = (args['ssid'] as String?) ?? '';
    final bssid = (args['bssid'] as String?) ?? '';
    if (ssid.isEmpty) return null;
    await SettingsStorage.addToWifiHistory(ssid, bssid);
    return null;
  }



  Future<void> setEnabled(bool enabled) async {
    try {
      await _utilsChannel.invokeMethod(
        'setAutoRecordWifi',
        {'enable': enabled},
      );
    } catch (_) {


    }
  }
}
