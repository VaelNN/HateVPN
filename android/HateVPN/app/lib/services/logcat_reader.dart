import 'package:flutter/services.dart';

import 'platform_channels.dart';











class LogcatReader {
  static const _channel = MethodChannel(PlatformChannels.methods);




  static Future<String?> tail({int count = 1000, String level = 'E'}) async {
    try {
      final raw = await _channel.invokeMethod<String>(
        'getLogcatTail',
        {'count': count, 'level': level},
      );
      if (raw == null || raw.isEmpty) return null;
      return raw;
    } catch (_) {
      return null;
    }
  }
}
