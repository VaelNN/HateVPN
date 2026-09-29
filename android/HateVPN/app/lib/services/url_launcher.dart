import 'package:flutter/services.dart';

import 'platform_channels.dart';



class UrlLauncher {
  UrlLauncher._();

  static const _channel = MethodChannel(PlatformChannels.utils);







  static Future<bool> open(String url, {String? fallbackUrl}) async {
    try {
      await _channel.invokeMethod('openUrl', {
        'url': url,
        'fallbackUrl': ?fallbackUrl,
      });
      return true;
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: fallbackUrl ?? url));
      return false;
    }
  }




  static Future<bool> openAppSettings() async {
    try {
      final ok = await _channel.invokeMethod<bool>('openAppSettings');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }



  static Future<bool> openLocationSettings() async {
    try {
      final ok = await _channel.invokeMethod<bool>('openLocationSettings');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }









  static Future<bool> hasRealFilePicker() async {
    try {
      final ok = await _channel.invokeMethod<bool>('hasRealFilePicker');
      return ok ?? true;
    } catch (_) {
      return true;
    }
  }











  static Future<String?> filePickerAction() async {
    try {
      return await _channel.invokeMethod<String>('filePickerAction') ??
          actionOpenDocument;
    } catch (_) {
      return actionOpenDocument;
    }
  }


  static const actionOpenDocument = 'android.intent.action.OPEN_DOCUMENT';
  static const actionGetContent = 'android.intent.action.GET_CONTENT';











  static Future<List<Map<String, Object?>>?> pickFilesViaGetContent({
    bool allowMultiple = false,
  }) async {
    final picked = await _channel.invokeListMethod<Object?>(
      'pickFileViaGetContent',
      {'allowMultiple': allowMultiple},
    );
    return picked
        ?.whereType<Map<Object?, Object?>>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }









  static Future<bool> canSaveToDownloads() async {
    try {
      final ok = await _channel.invokeMethod<bool>('canSaveToDownloads');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }






  static Future<String?> saveToDownloads({
    required String fileName,
    required String content,
  }) async {
    try {
      return await _channel.invokeMethod<String>(
        'saveToDownloads',
        {'fileName': fileName, 'content': content},
      );
    } catch (_) {
      return null;
    }
  }









  static Future<bool> hasCamera() async {
    try {
      final ok = await _channel.invokeMethod<bool>('hasCamera');
      return ok ?? true;
    } catch (_) {
      return true;
    }
  }


  static Future<bool> checkNotificationPermission() async {
    try {
      final granted =
          await _channel.invokeMethod<bool>('checkNotificationPermission');
      return granted ?? true;
    } catch (_) {
      return true;
    }
  }



  static Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (_) {

    }
  }




  static Future<bool> checkNearbyWifiPermission() async {
    try {
      final granted =
          await _channel.invokeMethod<bool>('checkNearbyWifiPermission');
      return granted ?? true;
    } catch (_) {
      return true;
    }
  }



  static Future<void> requestNearbyWifiPermission() async {
    try {
      await _channel.invokeMethod('requestNearbyWifiPermission');
    } catch (_) {

    }
  }





  static Future<bool> checkBackgroundLocationPermission() async {
    try {
      final granted = await _channel
          .invokeMethod<bool>('checkBackgroundLocationPermission');
      return granted ?? true;
    } catch (_) {
      return true;
    }
  }









  static Future<WifiInfoResult> getCurrentWifiInfo() async {
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('getCurrentWifiInfo');
      if (raw == null) {
        return const WifiInfoResult.error('runtime_error');
      }
      final error = raw['error'] as String?;
      if (error != null) {
        final missingRaw = raw['missing'] as String?;
        final missing = missingRaw == null
            ? const <String>[]
            : missingRaw
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(growable: false);
        return WifiInfoResult.error(error, missing: missing);
      }
      final ssid = raw['ssid'] as String?;
      final bssid = raw['bssid'] as String?;
      if (ssid == null || ssid.isEmpty) {
        return const WifiInfoResult.error('unknown_ssid');
      }
      return WifiInfoResult.success(ssid: ssid, bssid: bssid ?? '');
    } catch (_) {
      return const WifiInfoResult.error('runtime_error');
    }
  }
}


sealed class WifiInfoResult {
  const WifiInfoResult();

  const factory WifiInfoResult.success({
    required String ssid,
    required String bssid,
  }) = WifiInfoSuccess;

  const factory WifiInfoResult.error(
    String reason, {
    List<String> missing,
  }) = WifiInfoError;
}

class WifiInfoSuccess extends WifiInfoResult {
  const WifiInfoSuccess({required this.ssid, required this.bssid});
  final String ssid;
  final String bssid;
}

class WifiInfoError extends WifiInfoResult {
  const WifiInfoError(this.reason, {this.missing = const []});


  final String reason;




  final List<String> missing;
}
