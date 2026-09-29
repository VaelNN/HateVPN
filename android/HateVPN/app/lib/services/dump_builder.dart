import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/codec/source_record.dart';
import '../models/debug_entry.dart';
import '../models/server_list.dart';
import 'app_log.dart';
import 'debug/debug_registry.dart';
import 'exit_info_reader.dart';
import 'logcat_reader.dart';
import 'oom_reports.dart';
import 'settings_storage.dart';
import 'stderr_reader.dart';
import 'version_info.dart';
import '../vpn/box_vpn_client.dart';




class DumpBuilder {
  DumpBuilder._();

  static Future<String> build() async {
    final now = DateTime.now();

    String? config;
    try {
      final raw = await BoxVpnClient().getConfig();
      if (raw.isNotEmpty && raw != '{}') config = raw;
    } catch (_) {}





    String? coreVersion;
    try {
      final v = await BoxVpnClient().getCoreVersion();
      if (v.isNotEmpty) coreVersion = v;
    } catch (_) {}




    String? goroutinesStack;
    try {
      if ((await BoxVpnClient().getVpnStatus()).isUp) {
        final s = await BoxVpnClient().dumpGoroutines();
        if (s.isNotEmpty) goroutinesStack = s;
      }
    } catch (_) {}

    final vars = await SettingsStorage.getAllVars();











    final liveSub = DebugRegistry.I.sub;
    final List<ServerList> lists = liveSub != null
        ? liveSub.entries.map((e) => e.list).toList()
        : await SettingsStorage.getServerLists();








    final stderr = await StderrReader.read();
    final exitInfo = await ExitInfoReader.read();
    final logcatTail = await LogcatReader.tail();



    final crashArchive = await _crashArchive();


    final oomReports = await oomReportsSection();

    final dump = <String, dynamic>{
      'generated_at': now.toIso8601String(),
      'app': 'lxbox',




      'app_version': VersionInfo.I.version,
      'app_build': VersionInfo.I.buildNumber,
      'core_version': coreVersion,
      'vars': vars,
      'server_lists': lists.map(_sanitizeList).toList(),
      'config': config == null ? null : _tryDecode(config),
      'debug_log': AppLog.I.entries.map(_entryJson).toList(),
      'stderr_log': stderr,
      'crash_archive': crashArchive,
      'oom_reports': oomReports,
      'exit_info': exitInfo,
      'logcat_tail': logcatTail,
      'goroutines_stack': goroutinesStack,
    };

    final dir = await getTemporaryDirectory();
    final stamp =
        now.toIso8601String().replaceAll(':', '-').substring(0, 19);
    final file = File('${dir.path}/lxbox-dump-$stamp.json');
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(dump));
    return file.path;
  }








  static const _crashBodyLimit = 64 * 1024;

  static Future<List<Map<String, Object?>>> _crashArchive() async {
    try {
      final reports =
          (await CrashReports.list()).where((r) => !r.isCurrent).toList();
      final out = <Map<String, Object?>>[];
      for (final r in reports) {
        String? content;
        try {
          content = await File(r.path).readAsString();
        } catch (_) {


        }
        final truncated =
            content != null && content.length > _crashBodyLimit;
        out.add({
          'name': r.name,
          'mtime': r.mtime.toUtc().toIso8601String(),
          'size': r.size,
          if (r.coreVersion != null) 'core_version': r.coreVersion,
          if (truncated) 'truncated': true,
          'content':
              truncated ? content.substring(0, _crashBodyLimit) : content,
        });
      }
      return out;
    } catch (_) {
      return const [];
    }
  }












  static Future<List<Map<String, Object?>>> oomReportsSection() async {
    try {
      final reports = await OomReports.list();
      return [
        for (final (i, r) in reports.indexed)
          {
            'name': r.name,
            'mtime': r.mtime.toUtc().toIso8601String(),
            'size': r.size,
            if (r.coreVersion != null) 'core_version': r.coreVersion,
            if (r.memoryUsage != null) 'memory_usage': r.memoryUsage,
            if (r.heapInuse != null) 'heap_inuse': r.heapInuse,
            if (r.numGoroutine != null) 'num_goroutine': r.numGoroutine,
            if (i < kOomKeep) ...await _oomReportBody(r.dirPath),
          },
      ];
    } catch (_) {
      return const [];
    }
  }










  static Future<Map<String, Object?>> _oomReportBody(String dirPath) async {
    final body = <String, Object?>{};
    final files = <String, Object?>{};
    try {
      await for (final e
          in Directory(dirPath).list(followLinks: false)) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        try {
          switch (name) {
            case 'metadata.json':
              body['metadata'] = _tryDecode(await e.readAsString());
            case 'connections.json':
              body['connections'] = _tryDecode(await e.readAsString());
            case 'configuration.json':
              body['configuration'] = _tryDecode(await e.readAsString());
            case 'go.log':


              final log = await e.readAsString();
              final cut = log.length > _crashBodyLimit;
              if (cut) body['go_log_truncated'] = true;
              body['go_log'] =
                  cut ? log.substring(log.length - _crashBodyLimit) : log;
            case 'cmdline':
              body['cmdline'] =
                  (await e.readAsString()).replaceAll('\x00', ' ');
            default:
              final raw = await e.readAsBytes();
              files[name] = {
                'encoding': 'gzip+base64',
                'raw_size': raw.length,
                'data': base64Encode(gzip.encode(raw)),
              };
          }
        } catch (_) {


        }
      }
    } catch (_) {

    }
    if (files.isNotEmpty) body['files'] = files;
    return body;
  }




  static Map<String, dynamic> _sanitizeList(ServerList l) {
    final j = sourceToRecord(l);
    j['_node_tags'] = l.nodes.map((n) => n.tag).toList();
    j['_node_count'] = l.nodes.length;
    return j;
  }

  static dynamic _tryDecode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return s;
    }
  }

  static Map<String, dynamic> _entryJson(DebugEntry e) => {
        'time': e.time.toIso8601String(),
        'level': e.level.name,
        'source': e.source == DebugSource.core ? 'core' : 'app',
        'message': e.message,
        if (e.fromPreviousSession) 'prev_session': true,
      };
}
