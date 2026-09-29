import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../vpn/box_vpn_client.dart';







const kCrashReportBaseName = 'CrashReport-lxbox.log';



const kCrashArchiveDir = 'crash_reports';




const kCrashTraceName = 'go.log';



const kCrashMetaName = 'metadata.json';


const kCrashKeep = 10;








class CrashReportFile {
  const CrashReportFile({
    required this.path,
    required this.name,
    required this.mtime,
    required this.size,
    required this.isCurrent,
    this.dirPath,
    this.coreVersion,
  });


  final String path;


  final String name;
  final DateTime mtime;
  final int size;


  final bool isCurrent;



  final String? dirPath;


  final String? coreVersion;
}














class StderrReader {

  static Future<String?> read() async {
    final file = await _file();
    if (file == null) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }


  static Future<String?> path() async => (await _file())?.path;




  static Future<File?> _file() async {
    try {
      final base = await CrashReports.baseDir();
      final f = File('$base/$kCrashReportBaseName');
      if (await f.exists() && await f.length() > 0) return f;
      return null;
    } catch (_) {
      return null;
    }
  }
}


class CrashReports {







  static Future<String> baseDir() async {
    final native = await BoxVpnClient().getFilesDir();
    if (native != null && native.isNotEmpty) return native;
    return (await getApplicationDocumentsDirectory()).path;
  }



  static Future<List<CrashReportFile>> list() async {
    final out = <CrashReportFile>[];
    try {
      final base = await baseDir();
      final current = File('$base/$kCrashReportBaseName');
      if (await current.exists()) {
        final stat = await current.stat();
        if (stat.size > 0) {
          out.add(CrashReportFile(
            path: current.path,
            name: kCrashReportBaseName,
            mtime: stat.modified,
            size: stat.size,
            isCurrent: true,
          ));
        }
      }
      out.addAll(await _archive(base));
    } catch (_) {
      return out;
    }
    out.sort((a, b) => b.mtime.compareTo(a.mtime));
    return out;
  }







  static Future<List<CrashReportFile>> _archive(String base) async {
    final dir = Directory('$base/$kCrashArchiveDir');
    if (!await dir.exists()) return const [];
    final out = <CrashReportFile>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name = entity.uri.pathSegments
          .lastWhere((s) => s.isNotEmpty, orElse: () => '');
      if (entity is Directory) {
        final log = File('${entity.path}/$kCrashTraceName');
        if (!await log.exists()) continue;
        final stat = await log.stat();
        out.add(CrashReportFile(
          path: log.path,
          name: name,
          mtime: stat.modified,
          size: stat.size,
          isCurrent: false,
          dirPath: entity.path,
          coreVersion: await _coreVersionOf(entity.path),
        ));
      } else if (entity is File) {
        final stat = await entity.stat();
        out.add(CrashReportFile(
          path: entity.path,
          name: name,
          mtime: stat.modified,
          size: stat.size,
          isCurrent: false,
        ));
      }
    }
    return out;
  }



  static Future<String?> _coreVersionOf(String dirPath) async {
    try {
      final f = File('$dirPath/$kCrashMetaName');
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is Map && j['coreVersion'] is String) return j['coreVersion'];
    } catch (_) {

    }
    return null;
  }









  static Future<int> prune({int keep = kCrashKeep}) async {
    try {
      final base = await baseDir();
      final archive = await _archive(base);
      if (archive.length <= keep) return 0;
      archive.sort((a, b) => b.mtime.compareTo(a.mtime));
      var removed = 0;
      for (final r in archive.skip(keep)) {
        try {


          final dir = r.dirPath;
          if (dir != null) {
            await Directory(dir).delete(recursive: true);
          } else {
            await File(r.path).delete();
          }
          removed++;
        } catch (_) {

        }
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }




  static String stamp(CrashReportFile f) =>
      '${f.name}@${f.mtime.toUtc().toIso8601String()}';
}
