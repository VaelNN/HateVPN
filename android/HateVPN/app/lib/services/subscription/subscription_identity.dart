import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';

import '../../models/server_list.dart';
import '../settings_storage.dart';








class SubscriptionIdentity {
  SubscriptionIdentity._();


  static const varUserAgent = 'subscription_user_agent';
  static const varSendHwid = 'subscription_send_hwid';
  static const varHwid = 'subscription_hwid';
  static const varDeviceOs = 'subscription_device_os';
  static const varVerOs = 'subscription_ver_os';
  static const varDeviceModel = 'subscription_device_model';


  static String userAgentOverride = '';


  static bool sendHwid = false;


  static String hwid = '';



  static String deviceOsOverride = '';
  static String verOsOverride = '';
  static String deviceModelOverride = '';


  static const deviceOsDefault = 'android';
  static String osVersion = '';
  static String deviceModel = '';


  static String get effectiveDeviceOs =>
      deviceOsOverride.isNotEmpty ? deviceOsOverride : deviceOsDefault;
  static String get effectiveVerOs =>
      verOsOverride.isNotEmpty ? verOsOverride : osVersion;
  static String get effectiveDeviceModel =>
      deviceModelOverride.isNotEmpty ? deviceModelOverride : deviceModel;


  static Future<void> init() async {
    userAgentOverride =
        (await SettingsStorage.getVar(varUserAgent, '')).trim();
    sendHwid = (await SettingsStorage.getVar(varSendHwid, 'false')) == 'true';
    hwid = (await SettingsStorage.getVar(varHwid, '')).trim();
    deviceOsOverride =
        (await SettingsStorage.getVar(varDeviceOs, '')).trim();
    verOsOverride = (await SettingsStorage.getVar(varVerOs, '')).trim();
    deviceModelOverride =
        (await SettingsStorage.getVar(varDeviceModel, '')).trim();
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      osVersion = info.version.release;
      deviceModel = info.model;
    } catch (_) {


    }
  }


  static void apply({
    String? userAgentOverride,
    bool? sendHwid,
    String? hwid,
    String? deviceOsOverride,
    String? verOsOverride,
    String? deviceModelOverride,
  }) {
    if (userAgentOverride != null) {
      SubscriptionIdentity.userAgentOverride = userAgentOverride.trim();
    }
    if (sendHwid != null) SubscriptionIdentity.sendHwid = sendHwid;
    if (hwid != null) SubscriptionIdentity.hwid = hwid.trim();
    if (deviceOsOverride != null) {
      SubscriptionIdentity.deviceOsOverride = deviceOsOverride.trim();
    }
    if (verOsOverride != null) {
      SubscriptionIdentity.verOsOverride = verOsOverride.trim();
    }
    if (deviceModelOverride != null) {
      SubscriptionIdentity.deviceModelOverride = deviceModelOverride.trim();
    }
  }




  static Map<String, String> fetchHeaders() => headersFrom(
        sendHwid: sendHwid,
        hwid: hwid,
        deviceOs: effectiveDeviceOs,
        verOs: effectiveVerOs,
        deviceModel: effectiveDeviceModel,
      );






  static SubscriptionIdentityOverride snapshotGlobal() =>
      SubscriptionIdentityOverride(
        userAgent: userAgentOverride,
        sendHwid: sendHwid,
        hwid: hwid,
        deviceOs: effectiveDeviceOs,
        verOs: effectiveVerOs,
        deviceModel: effectiveDeviceModel,
      );





  static Map<String, String> headersFrom({
    required bool sendHwid,
    required String hwid,
    required String deviceOs,
    required String verOs,
    required String deviceModel,
  }) {
    if (!sendHwid || hwid.isEmpty) return const {};
    return {
      'x-hwid': hwid,
      if (deviceOs.isNotEmpty) 'x-device-os': deviceOs,
      if (verOs.isNotEmpty) 'x-ver-os': verOs,
      if (deviceModel.isNotEmpty) 'x-device-model': deviceModel,
    };
  }
}



String generateUuidV4() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [
    for (final b in bytes) b.toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}



String generateProxyPassword() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
