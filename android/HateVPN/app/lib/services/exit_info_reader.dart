import 'package:flutter/services.dart';

import 'platform_channels.dart';







class ExitInfoReader {
  static const _channel = MethodChannel(PlatformChannels.methods);














  static Future<List<Map<String, Object?>>> read() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'getApplicationExitInfo',
      );
      if (raw == null) return const [];
      return raw
          .cast<Map<Object?, Object?>>()
          .map((m) => m.map((k, v) => MapEntry(k as String, v)))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
