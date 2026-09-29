import 'dart:convert';
import 'dart:io';

import 'stderr_reader.dart' show CrashReports;








const kOomArchiveDir = 'oom_reports';






const kOomMetaName = 'metadata.json';


const kOomLogName = 'go.log';





const kOomKeep = 5;






class OomReportFile {
  const OomReportFile({
    required this.path,
    required this.name,
    required this.mtime,
    required this.size,
    required this.dirPath,
    this.coreVersion,
    this.memoryUsage,
    this.heapInuse,
    this.numGoroutine,
  });


  final String path;


  final String name;
  final DateTime mtime;


  final int size;


  final String dirPath;


  final String? coreVersion;



  final String? memoryUsage;



  final String? heapInuse;


  final int? numGoroutine;
}








class OomReports {

  static Future<List<OomReportFile>> list() async {
    try {
      final base = await CrashReports.baseDir();
      final reports = await _scan(base);
      reports.sort((a, b) => b.mtime.compareTo(a.mtime));
      return reports;
    } catch (_) {
      return const [];
    }
  }





  static Future<int> totalSize() async {
    final reports = await list();
    var total = 0;
    for (final r in reports) {
      total += r.size;
    }
    return total;
  }




  static Future<List<OomReportFile>> _scan(String base) async {
    final dir = Directory('$base/$kOomArchiveDir');
    if (!await dir.exists()) return const [];
    final out = <OomReportFile>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final meta = File('${entity.path}/$kOomMetaName');
      if (!await meta.exists()) continue;
      final name = entity.uri.pathSegments
          .lastWhere((s) => s.isNotEmpty, orElse: () => '');
      final stat = await meta.stat();
      final fields = await _metaOf(meta);
      out.add(OomReportFile(
        path: meta.path,
        name: name,
        mtime: stat.modified,
        size: await _dirSize(entity),
        dirPath: entity.path,
        coreVersion: fields['coreVersion'] as String?,
        memoryUsage: fields['memoryUsage'] as String?,
        heapInuse: fields['heapInuse'] as String?,
        numGoroutine: _asInt(fields['numGoroutine']),
      ));
    }
    return out;
  }



  static Future<int> _dirSize(Directory dir) async {
    var total = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        try {
          total += await e.length();
        } catch (_) {

        }
      }
    } catch (_) {
      return total;
    }
    return total;
  }



  static Future<Map<String, Object?>> _metaOf(File meta) async {
    try {
      final j = jsonDecode(await meta.readAsString());
      if (j is Map) return j.cast<String, Object?>();
    } catch (_) {

    }
    return const {};
  }



  static int? _asInt(Object? v) => switch (v) {
        int i => i,
        String s => int.tryParse(s),
        _ => null,
      };








  static Future<int> prune({int keep = kOomKeep}) async {
    try {
      final reports = await list();
      if (reports.length <= keep) return 0;
      var removed = 0;
      for (final r in reports.skip(keep)) {
        if (await _delete(r)) removed++;
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }




  static Future<int> clear() async {
    try {
      var removed = 0;
      for (final r in await list()) {
        if (await _delete(r)) removed++;
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }



  static Future<bool> _delete(OomReportFile r) async {
    try {
      await Directory(r.dirPath).delete(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
