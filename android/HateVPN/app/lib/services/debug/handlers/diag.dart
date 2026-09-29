import 'dart:convert';
import 'dart:io';

import '../../../models/debug_entry.dart';
import '../../../vpn/box_vpn_client.dart';
import '../../app_log.dart';
import '../../dump_builder.dart';
import '../../exit_info_reader.dart';
import '../../logcat_reader.dart';
import '../../stderr_reader.dart';
import '../context.dart';
import '../contract/errors.dart';
import '../transport/request.dart';
import '../transport/response.dart';



Future<DebugResponse> diagHandler(DebugRequest req, DebugContext ctx) async {
  return switch (req.path) {
    '/diag/dump' => _dump(),
    '/diag/exit-info' => _exitInfo(),
    '/diag/logcat' => _logcat(req),
    '/diag/stderr' => _stderr(),
    '/diag/applog' => _applog(req),
    '/diag/pprof' => _pprof(req),
    _ => throw NotFound('diag path: ${req.path}'),
  };
}


Future<DebugResponse> _dump() async {
  final path = await DumpBuilder.build();
  final bytes = await File(path).readAsBytes();
  return BytesResponse(bytes,
      filename: path.split('/').last, contentType: 'application/json');
}



Future<DebugResponse> _exitInfo() async =>
    JsonResponse(await ExitInfoReader.read());


Future<DebugResponse> _logcat(DebugRequest req) async {
  final count = int.tryParse(req.query['count'] ?? '1000') ?? 1000;
  final level = (req.query['level'] ?? 'E').trim();
  final text = await LogcatReader.tail(count: count, level: level) ?? '';
  return BytesResponse(utf8.encode(text), contentType: 'text/plain; charset=utf-8');
}


Future<DebugResponse> _stderr() async {
  final text = await StderrReader.read() ?? '';
  return BytesResponse(utf8.encode(text), contentType: 'text/plain; charset=utf-8');
}














Future<DebugResponse> _pprof(DebugRequest req) async {
  final profile = (req.query['profile'] ?? 'goroutine').trim();
  if (!_pprofProfiles.contains(profile)) {
    throw BadRequest(
        'unknown pprof profile: $profile (allowed: ${_pprofProfiles.join('|')})');
  }

  final query = (req.query['query'] ?? _defaultQuery(profile)).trim();
  final pathAndQuery = query.isEmpty ? profile : '$profile?$query';


  final blockingSeconds = profile == 'profile'
      ? (int.tryParse(RegExp(r'seconds=(\d+)').firstMatch(query)?.group(1) ?? '10') ??
              10)
          .clamp(1, 60)
      : 0;
  final bytes = await BoxVpnClient()
      .pprofRaw(pathAndQuery, blockingSeconds: blockingSeconds);


  final isText = profile == 'goroutine' && query.startsWith('debug=');
  return isText
      ? BytesResponse(bytes, contentType: 'text/plain; charset=utf-8')
      : BytesResponse(bytes,
          filename: '$profile.pb', contentType: 'application/octet-stream');
}

String _defaultQuery(String profile) => switch (profile) {
      'goroutine' => 'debug=2',
      'profile' => 'seconds=10',
      'heap' => 'gc=1',
      _ => '',
    };


const _pprofProfiles = <String>{
  'goroutine',
  'profile',
  'heap',
  'allocs',
  'block',
  'mutex',
  'threadcreate',
};



Future<DebugResponse> _applog(DebugRequest req) async {
  final filter = (req.query['prev'] ?? 'all').toLowerCase();
  final entries = AppLog.I.entries.where((e) => switch (filter) {
        'true' => e.fromPreviousSession,
        'false' => !e.fromPreviousSession,
        _ => true,
      });
  return JsonResponse(entries
      .map((e) => {
            'time': e.time.toIso8601String(),
            'source': e.source == DebugSource.core ? 'core' : 'app',
            'level': e.level.name,
            'message': e.message,
            if (e.fromPreviousSession) 'prev_session': true,
          })
      .toList());
}
