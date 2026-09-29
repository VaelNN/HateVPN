import 'dart:async';
import 'dart:io';

import '../models/ui_msg.dart';
import '../models/validation.dart';






















UiMsg humanizeError(Object e) {
  if (e is FatalValidationException) {
    return ValidationFatalMsg(e.issues);
  }
  if (e is SocketException) {
    final host = _extractSocketHost(e);
    return host.isNotEmpty
        ? NoConnectionToHost(host)
        : const ErrMsg(ErrKey.noConnection);
  }
  if (e is TimeoutException) {
    final secs = e.duration?.inSeconds ?? 0;
    if (secs > 0) return TimedOutAfter(secs);
    return const ErrMsg(ErrKey.requestTimedOut);
  }
  if (e is HttpException) {
    final msg = e.message;
    final m = RegExp(r'HTTP (\d{3})').firstMatch(msg);
    if (m != null) {
      return HttpStatusMsg(int.parse(m.group(1)!));
    }
    return RawMsg(msg);
  }
  if (e is FormatException) {
    return const ErrMsg(ErrKey.cantParseResponse);
  }
  if (e is FileSystemException) {
    return PrefixedMsg(ErrPrefix.fileError, RawMsg(e.message));
  }
  final raw = e.toString();

  final trimmed = raw.replaceFirst(RegExp(r'^[A-Za-z_]*(Exception|Error): '), '');
  return RawMsg(
      trimmed.length > 140 ? '${trimmed.substring(0, 137)}...' : trimmed);
}






String _extractSocketHost(SocketException e) {
  final addrHost = e.address?.host ?? '';
  if (addrHost.isNotEmpty) return addrHost;


  final m = RegExp(r"host lookup:\s*'([^']+)'", caseSensitive: false)
      .firstMatch(e.message);
  if (m != null) {
    final host = m.group(1)?.trim() ?? '';
    if (host.isNotEmpty) return host;
  }
  return '';
}
