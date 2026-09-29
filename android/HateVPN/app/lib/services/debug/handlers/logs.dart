import '../../../models/debug_entry.dart';
import '../../app_log.dart';
import '../context.dart';
import '../contract/errors.dart';
import '../transport/request.dart';
import '../transport/response.dart';


















Future<DebugResponse> logsHandler(DebugRequest req, DebugContext ctx) async {
  if (req.method == 'GET') {
    if (req.path == '/logs') return _list(req, ctx, sourceOverride: null);
    if (req.path == '/logs/app') {
      return _list(req, ctx, sourceOverride: DebugSource.app);
    }
    if (req.path == '/logs/core') {
      return _list(req, ctx, sourceOverride: DebugSource.core);
    }
  }
  if (req.path == '/logs/clear' && req.method == 'POST') {
    return _clear(req, ctx);
  }
  throw NotFound('logs path: ${req.method} ${req.path}');
}

Future<DebugResponse> _list(
  DebugRequest req,
  DebugContext ctx, {
  required DebugSource? sourceOverride,
}) async {
  final limit = (req.qInt('limit') ?? 200).clamp(1, 1000);


  DebugSource? source = sourceOverride;
  if (source == null) {
    final raw = req.q('source');
    if (raw == 'app') {
      source = DebugSource.app;
    } else if (raw == 'core') {
      source = DebugSource.core;
    } else if (raw != null && raw.isNotEmpty) {
      throw BadRequest('source must be "app" or "core", got "$raw"');
    }
  }


  var entries = source != null
      ? AppLog.I.entriesForSource(source)
      : AppLog.I.entries;



  final levelRaw = req.q('level');
  if (levelRaw != null && levelRaw.isNotEmpty) {
    final wanted = <DebugLevel>{};
    for (final part in levelRaw.split(',')) {
      final name = part.trim();
      if (name.isEmpty) continue;
      final matched = DebugLevel.values.where((l) => l.name == name);
      if (matched.isEmpty) {
        throw BadRequest(
            'level must be one of debug|info|warning|error, got "$name"');
      }
      wanted.add(matched.first);
    }
    if (wanted.isNotEmpty) {
      entries = entries.where((e) => wanted.contains(e.level)).toList();
    }
  }



  final q = req.q('q')?.trim();
  if (q != null && q.isNotEmpty) {
    final needle = q.toLowerCase();
    entries = entries.where((e) => e.message.toLowerCase().contains(needle))
        .toList();
  }

  final slice = entries.take(limit).toList();
  return JsonResponse(slice.map(_entryToJson).toList());
}

Map<String, Object?> _entryToJson(DebugEntry e) => {
      'ts': e.time.toUtc().toIso8601String(),
      'level': e.level.name,
      'source': e.source.name,
      'message': e.message,
    };

Future<DebugResponse> _clear(DebugRequest req, DebugContext ctx) async {

  final raw = req.q('source');
  if (raw == null || raw.isEmpty) {
    AppLog.I.clear();
    return const JsonResponse({'ok': true, 'action': 'clear', 'source': 'all'});
  }
  if (raw == 'app') {
    AppLog.I.clearSource(DebugSource.app);
    return const JsonResponse({'ok': true, 'action': 'clear', 'source': 'app'});
  }
  if (raw == 'core') {
    AppLog.I.clearSource(DebugSource.core);
    return const JsonResponse({'ok': true, 'action': 'clear', 'source': 'core'});
  }
  throw BadRequest('source must be "app" or "core" (or omit), got "$raw"');
}
