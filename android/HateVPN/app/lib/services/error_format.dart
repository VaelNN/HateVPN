import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;

import '../models/ui_msg.dart';























UiMsg formatUserError(Object e) {
  if (e is TimeoutException) {
    return TimeoutError(e.duration?.inMilliseconds ?? 0);
  }
  if (e is FileSystemException) {
    final osMsg = e.osError?.message;
    if (osMsg != null && osMsg.isNotEmpty) return RawMsg(osMsg);
    return RawMsg(e.message);
  }
  if (e is SocketException) {
    final osMsg = e.osError?.message;
    if (osMsg != null && osMsg.isNotEmpty) return RawMsg(osMsg);
    return RawMsg(e.message);
  }
  if (e is HttpException) return RawMsg(e.message);
  if (e is FormatException) return RawMsg(e.message);
  if (e is PlatformException) {
    final m = e.message;
    if (m != null && m.isNotEmpty) return RawMsg(m);
    return PrefixedMsg(ErrPrefix.platformError, RawMsg(e.code));
  }

  var s = e.toString();
  if (s.startsWith('Exception: ')) s = s.substring('Exception: '.length);
  return RawMsg(s.length > 120 ? '${s.substring(0, 117)}…' : s);
}
