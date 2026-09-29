import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'app_log.dart';
import 'platform_channels.dart';
import 'settings_storage.dart';











class UsageRegion {
  UsageRegion._();

  static const _channel = MethodChannel(PlatformChannels.utils);


  static String? _detected;


  static Future<String?> Function()? detectorOverride;


  static Future<String> effective() async {
    final setting = await SettingsStorage.getRegion();
    if (setting == SettingsStorage.regionNone) return '';
    if (setting != SettingsStorage.regionAuto) return setting;
    return detected();
  }


  static Future<String> detected() async {
    final cached = _detected;
    if (cached != null) return cached;
    String? cc;
    try {
      cc = detectorOverride != null
          ? await detectorOverride!()
          : await _channel.invokeMethod<String>('networkCountry');
    } catch (e) {

      AppLog.I.debug('UsageRegion: native lookup failed ($e)');
    }
    cc ??= _localeCountry();
    final norm = cc.trim().toLowerCase();
    return _detected = RegExp(r'^[a-z]{2}$').hasMatch(norm) ? norm : '';
  }


  static String _localeCountry() {
    try {
      final m = RegExp(r'^[A-Za-z]{2,3}[_-]([A-Za-z]{2})\b')
          .firstMatch(Platform.localeName);
      return m?.group(1) ?? '';
    } catch (_) {
      return '';
    }
  }


  static void resetForTest() => _detected = null;
}
