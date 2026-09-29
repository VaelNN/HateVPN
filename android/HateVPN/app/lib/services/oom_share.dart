import 'dart:io';

import 'package:share_plus/share_plus.dart';

import 'oom_reports.dart';











Future<bool> shareOomReport(OomReportFile report) async {
  try {
    final files = <XFile>[];
    await for (final e
        in Directory(report.dirPath).list(followLinks: false)) {
      if (e is! File) continue;
      final base = e.uri.pathSegments.last;


      files.add(XFile(e.path,
          name: '${report.name}-$base', mimeType: _mimeOf(base)));
    }
    if (files.isEmpty) return false;
    files.sort((a, b) => (a.name).compareTo(b.name));

    await Share.shareXFiles(
      files,
      subject: 'L×Box core OOM report — ${report.mtime.toIso8601String()}',
    );
    return true;
  } catch (_) {
    return false;
  }
}



String _mimeOf(String name) {
  if (name.endsWith('.pb')) return 'application/octet-stream';
  if (name.endsWith('.json')) return 'application/json';
  return 'text/plain';
}
