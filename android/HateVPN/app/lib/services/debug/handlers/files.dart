import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../oom_reports.dart'
    show kOomArchiveDir, kOomMetaName, OomReports;
import '../../rule_set_downloader.dart';
import '../../stderr_reader.dart'
    show kCrashArchiveDir, kCrashReportBaseName, kCrashTraceName, CrashReports;
import '../context.dart';
import '../contract/errors.dart';
import '../transport/request.dart';
import '../transport/response.dart';









Future<DebugResponse> filesHandler(DebugRequest req, DebugContext ctx) async {
  return switch (req.path) {
    '/files/srs/list' => _srsList(ctx),
    '/files/srs' => _srsFile(req, ctx),
    '/files/local' || '/files/external' => _localFile(req, ctx),

    '/files/crash/list' => _crashList(),
    '/files/crash' => _crashFile(req),

    '/files/oom/list' => _oomList(),
    '/files/oom' => _oomFile(req),
    _ => throw NotFound('files path: ${req.path}'),
  };
}


Future<DebugResponse> _srsList(DebugContext ctx) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/rule_sets');
  if (!await dir.exists()) return const JsonResponse([]);
  final entries = <Map<String, Object?>>[];
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (!name.endsWith('.srs')) continue;
    final stat = await entity.stat();
    entries.add({
      'rule_id': name.substring(0, name.length - 4),
      'size': stat.size,
      'mtime': stat.modified.toUtc().toIso8601String(),
    });
  }
  return JsonResponse(entries);
}

Future<DebugResponse> _srsFile(DebugRequest req, DebugContext ctx) async {
  final id = req.requiredQuery('ruleId');
  _assertSafeName(id);
  final path = await RuleSetDownloader.cachedPath(id);
  if (path == null) throw NotFound('srs for ruleId=$id');
  final f = File(path);
  if (!await f.exists()) throw NotFound('srs file: $path');
  final bytes = await f.readAsBytes();
  return BytesResponse(bytes, filename: '$id.srs');
}





const _localWhitelist = {



  'stderr.log',
  'cache.db',


  kCrashReportBaseName,
  '$kCrashReportBaseName.old',
};

Future<DebugResponse> _localFile(DebugRequest req, DebugContext ctx) async {
  final name = req.requiredQuery('name');
  _assertSafeName(name);
  if (!_localWhitelist.contains(name)) {
    throw NotFound('not whitelisted: $name');
  }

  final base = await _nativeFilesDir();
  final f = File('$base/$name');
  if (!await f.exists()) throw NotFound('file: $name');
  final bytes = await f.readAsBytes();
  return BytesResponse(bytes, filename: name);
}









Future<DebugResponse> _crashList() async {
  final reports =
      (await CrashReports.list()).where((r) => !r.isCurrent).toList();
  return JsonResponse([
    for (final r in reports)
      {
        'name': r.name,
        'size': r.size,
        'mtime': r.mtime.toUtc().toIso8601String(),
        if (r.coreVersion != null) 'core_version': r.coreVersion,

        if (r.dirPath != null) 'kind': 'dir',
      },
  ]);
}





Future<DebugResponse> _crashFile(DebugRequest req) async {
  final name = req.requiredQuery('name');
  _assertSafeName(name);
  final inner = req.uri.queryParameters['file'];
  if (inner != null) _assertSafeName(inner);
  final base = await _nativeFilesDir();
  final root = '$base/$kCrashArchiveDir/$name';

  final f = await Directory(root).exists()
      ? File('$root/${inner ?? kCrashTraceName}')
      : File(root);
  if (!await f.exists()) throw NotFound('crash report: $name');
  final bytes = await f.readAsBytes();
  return BytesResponse(bytes, filename: '$name-${f.uri.pathSegments.last}');
}






Future<DebugResponse> _oomList() async {
  final reports = await OomReports.list();
  return JsonResponse([
    for (final r in reports)
      {
        'name': r.name,
        'size': r.size,
        'mtime': r.mtime.toUtc().toIso8601String(),
        if (r.coreVersion != null) 'core_version': r.coreVersion,
        if (r.memoryUsage != null) 'memory_usage': r.memoryUsage,
        if (r.heapInuse != null) 'heap_inuse': r.heapInuse,
        if (r.numGoroutine != null) 'num_goroutine': r.numGoroutine,
      },
  ]);
}





Future<DebugResponse> _oomFile(DebugRequest req) async {
  final name = req.requiredQuery('name');
  _assertSafeName(name);
  final inner = req.uri.queryParameters['file'];
  if (inner != null) _assertSafeName(inner);
  final base = await _nativeFilesDir();
  final f = File('$base/$kOomArchiveDir/$name/${inner ?? kOomMetaName}');
  if (!await f.exists()) throw NotFound('oom report: $name');
  final bytes = await f.readAsBytes();
  return BytesResponse(bytes, filename: '$name-${f.uri.pathSegments.last}');
}



Future<String> _nativeFilesDir() => CrashReports.baseDir();



void _assertSafeName(String name) {
  if (name.isEmpty ||
      name.contains('/') ||
      name.contains('\\') ||
      name.contains('..') ||
      name.startsWith('.')) {
    throw BadRequest('invalid name: only basename allowed');
  }
}
