import '../../settings_storage.dart';
import '../context.dart';
import '../contract/errors.dart';
import '../transport/request.dart';
import '../transport/response.dart';
import '_shared.dart';














Future<DebugResponse> wifiHistoryHandler(
    DebugRequest req, DebugContext ctx) async {
  final path = req.path;

  if (path == '/wifi_history') {
    return switch (req.method) {
      'GET' => _list(),
      'POST' => _add(req),
      'DELETE' => _remove(req),
      _ => throw BadRequest(
          'method ${req.method} not allowed on /wifi_history'),
    };
  }

  if (path == '/wifi_history/all') {
    if (req.method != 'DELETE') {
      throw BadRequest(
        'method ${req.method} not allowed on /wifi_history/all (DELETE only)',
      );
    }
    return _clear();
  }

  throw NotFound('wifi_history path: $path');
}

Future<DebugResponse> _list() async {
  final history = await SettingsStorage.getWifiHistory();
  return JsonResponse(history);
}

Future<DebugResponse> _add(DebugRequest req) async {
  final body = req.jsonBodyAsMap();
  final ssid = fieldString(body, 'ssid') ?? '';
  if (ssid.trim().isEmpty) {
    throw const BadRequest('field "ssid" required');
  }
  final bssid = (fieldString(body, 'bssid') ?? '').trim().toLowerCase();
  await SettingsStorage.addToWifiHistory(ssid, bssid);
  return JsonResponse({
    'ok': true,
    'action': 'wifi_history-add',
    'ssid': ssid,
    'bssid': bssid,
  }, status: 201);
}

Future<DebugResponse> _remove(DebugRequest req) async {
  final body = req.jsonBodyAsMap();
  final ssid = fieldString(body, 'ssid') ?? '';
  if (ssid.trim().isEmpty) {
    throw const BadRequest(
      'field "ssid" required (use DELETE /wifi_history/all to clear all)',
    );
  }
  final bssid = (fieldString(body, 'bssid') ?? '').trim().toLowerCase();
  await SettingsStorage.removeFromWifiHistory(ssid, bssid);
  return JsonResponse({
    'ok': true,
    'action': 'wifi_history-remove',
    'ssid': ssid,
    'bssid': bssid,
  });
}

Future<DebugResponse> _clear() async {
  await SettingsStorage.clearWifiHistory();
  return JsonResponse({
    'ok': true,
    'action': 'wifi_history-clear',
  });
}
