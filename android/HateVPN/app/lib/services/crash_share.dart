import 'dart:io';

import 'package:share_plus/share_plus.dart';

import 'stderr_reader.dart';









Future<bool> shareCrashReport(CrashReportFile report) async {
  try {
    final files = <XFile>[];
    final dir = report.dirPath;
    if (dir != null) {


      await for (final e in Directory(dir).list(followLinks: false)) {
        if (e is! File) continue;
        final base = e.uri.pathSegments.last;
        files.add(XFile(e.path,
            name: '${report.name}-$base', mimeType: _mimeOf(base)));
      }
      files.sort((a, b) => (a.name).compareTo(b.name));
    }
    if (files.isEmpty) {
      files.add(XFile(report.path,
          name: report.name, mimeType: 'text/plain'));
    }
    await SharePlus.instance.share(ShareParams(
      files: files,
      subject: 'L×Box core crash — ${report.mtime.toIso8601String()}',
    ));
    return true;
  } catch (_) {
    return false;
  }
}

String _mimeOf(String name) =>
    name.endsWith('.json') ? 'application/json' : 'text/plain';
