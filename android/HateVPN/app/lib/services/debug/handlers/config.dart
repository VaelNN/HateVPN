import 'dart:convert';

import 'package:path_provider/path_provider.dart';

import '../context.dart';
import '../contract/errors.dart';
import '../transport/request.dart';
import '../transport/response.dart';














Future<DebugResponse> configHandler(DebugRequest req, DebugContext ctx) async {
  if (req.path == '/config' && req.method == 'PUT') {
    return _put(req, ctx);
  }
  if (req.method != 'GET') {
    throw BadRequest('method ${req.method} not allowed on ${req.path}');
  }
  return switch (req.path) {
    '/config' => _body(ctx, pretty: false),
    '/config/pretty' => _body(ctx, pretty: true),
    '/config/path' => _path(),
    '/config/running' => _running(ctx),
    _ => throw NotFound('config path: ${req.path}'),
  };
}







Future<DebugResponse> _running(DebugContext ctx) async {
  final home = ctx.requireHome();
  final raw = home.state.runningConfigRaw;
  if (raw == null || raw.isEmpty) {
    throw const Conflict(
        'running config unavailable (tunnel down, kernel without '
        'GetRunningConfig, or snapshot not fetched yet)');
  }
  return RawJsonResponse(raw);
}








Future<DebugResponse> _put(DebugRequest req, DebugContext ctx) async {
  if (req.body.isEmpty) {
    throw const BadRequest('body required (raw sing-box JSON)');
  }
  final String text;
  try {
    text = utf8.decode(req.body, allowMalformed: false);
  } on FormatException catch (e) {
    throw BadRequest('body is not valid UTF-8: ${e.message}');
  }

  try {
    final parsed = jsonDecode(text);
    if (parsed is! Map) {
      throw const BadRequest('config body must be JSON object');
    }
  } on FormatException catch (e) {
    throw BadRequest('invalid JSON config: ${e.message}');
  }
  final home = ctx.requireHome();
  final saved = await home.saveParsedConfig(text);
  if (!saved) {
    throw const UpstreamError('saveParsedConfig returned false');
  }
  return JsonResponse({
    'ok': true,
    'action': 'config-put',
    'bytes': text.length,
    'tunnel_up_when_saved': home.state.tunnelUp,
    'note': 'override is temporary — POST /action/rebuild-config (or any '
        'UI action that triggers a rebuild) wipes it, regenerating the config '
        'from settings. To pin it permanently — PUT /settings/config_locked '
        '{"locked": true} (see §037).',
  });
}

Future<DebugResponse> _body(DebugContext ctx, {required bool pretty}) async {
  final home = ctx.requireHome();
  final raw = home.state.configRaw;
  if (raw.isEmpty) throw const NotFound('no saved config');
  if (!pretty) return RawJsonResponse(raw);
  try {
    final parsed = jsonDecode(raw);
    return JsonResponse(parsed, pretty: true);
  } on FormatException {

    return RawJsonResponse(raw);
  }
}

Future<DebugResponse> _path() async {
  final dir = await getApplicationDocumentsDirectory();
  return JsonResponse({
    'app_documents_dir': dir.path,
    'note':
        'sing-box core saves the config in the internal files dir '
        '(/data/data/<pkg>/files/) via the native side; the path above is for reference.',
  });
}
