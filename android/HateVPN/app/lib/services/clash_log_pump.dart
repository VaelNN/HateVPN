import 'dart:async';

import 'package:flutter/services.dart';

import '../models/debug_entry.dart';
import 'app_log.dart';
import 'platform_channels.dart';




















class ClashLogPump {
  ClashLogPump._();
  static final ClashLogPump I = ClashLogPump._();

  static const _channel = EventChannel(PlatformChannels.coreLog);
  StreamSubscription? _sub;






  void attach() {
    if (_sub != null) return;
    _sub = _channel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (_) {



      },
      cancelOnError: false,
    );
  }

  void _onEvent(dynamic event) {
    if (event is String) {
      if (event.isEmpty) return;
      AppLog.I.log(parseLevel(event), event, source: DebugSource.core);
      return;
    }
    if (event is List) {


      final lines = <String>[];
      for (final item in event) {
        if (item is String && item.isNotEmpty) lines.add(item);
      }
      if (lines.isEmpty) return;
      AppLog.I.logBatch(lines, parseLevel, source: DebugSource.core);
    }
  }


  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }






















  static DebugLevel parseLevel(String line) {
    if (_errorRe.hasMatch(line)) return DebugLevel.error;
    if (_warnRe.hasMatch(line)) return DebugLevel.warning;
    if (_infoRe.hasMatch(line)) return DebugLevel.info;
    if (_debugRe.hasMatch(line)) return DebugLevel.debug;
    return DebugLevel.info;
  }

  static final _errorRe = RegExp(r'\b(ERROR|FATAL|PANIC)\b');
  static final _warnRe = RegExp(r'\bWARN\b');
  static final _infoRe = RegExp(r'\bINFO\b');
  static final _debugRe = RegExp(r'\b(TRACE|DEBUG)\b');
}
