import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';






enum DownloadOutcome {

  downloaded,


  notModified,


  failed,
}



class DownloadResult {
  const DownloadResult(this.outcome, this.path);
  final DownloadOutcome outcome;
  final String? path;

  bool get ok => outcome != DownloadOutcome.failed;


  bool get changed => outcome == DownloadOutcome.downloaded;
}









class RuleSetMeta {
  const RuleSetMeta({
    this.lastUpdated,
    this.lastAttempt,
    this.etag,
    this.lastError,
  });


  final DateTime? lastUpdated;


  final DateTime? lastAttempt;


  final String? etag;



  final String? lastError;


  bool get failing => lastError != null;

  Map<String, dynamic> toJson() => {
        if (lastUpdated != null)
          'lastUpdated': lastUpdated!.toUtc().toIso8601String(),
        if (lastAttempt != null)
          'lastAttempt': lastAttempt!.toUtc().toIso8601String(),
        if (etag != null) 'etag': etag,
        if (lastError != null) 'lastError': lastError,
      };

  factory RuleSetMeta.fromJson(Map<String, dynamic> j) => RuleSetMeta(
        lastUpdated: _parseDate(j['lastUpdated']),
        lastAttempt: _parseDate(j['lastAttempt']),
        etag: j['etag'] as String?,
        lastError: j['lastError'] as String?,
      );

  static DateTime? _parseDate(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
}









class RuleSetDownloader {
  RuleSetDownloader._();

  static const _timeout = Duration(seconds: 30);
  static const _dirName = 'rule_sets';

  static Directory? _cacheDir;





  static void resetCacheForTesting() => _cacheDir = null;

  static Future<Directory> _dir() async {


    final cached = _cacheDir;
    if (cached != null) {
      if (!await cached.exists()) await cached.create(recursive: true);
      return cached;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  static Future<File> _file(String id) async =>
      File('${(await _dir()).path}/$id.srs');



  static Future<File> _metaFile(String id) async =>
      File('${(await _dir()).path}/$id$_metaSuffix');

  static const _metaSuffix = '.meta.json';



  static Future<RuleSetMeta> readMeta(String id) async {
    try {
      final f = await _metaFile(id);
      if (!await f.exists()) return const RuleSetMeta();
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map<String, dynamic>) return const RuleSetMeta();
      return RuleSetMeta.fromJson(raw);
    } catch (_) {
      return const RuleSetMeta();
    }
  }



  static Future<void> _writeMeta(String id, RuleSetMeta meta) async {
    try {
      await (await _metaFile(id)).writeAsString(jsonEncode(meta.toJson()),
          flush: true);
    } catch (_) {}
  }


  static Future<bool> isCached(String id) async {
    try {
      return await (await _file(id)).exists();
    } catch (_) {
      return false;
    }
  }


  static Future<String?> cachedPath(String id) async {
    final f = await _file(id);
    return await f.exists() ? f.path : null;
  }


  static Future<DateTime?> lastUpdated(String id) async {
    final f = await _file(id);
    if (!await f.exists()) return null;
    return (await f.stat()).modified;
  }












  static const _prodBackoffs = [Duration(seconds: 1), Duration(seconds: 3)];



  static Future<String?> download(
    String id,
    String url, {
    http.Client? client,
    List<Duration>? backoffs,
  }) async {
    final r = await fetch(id, url, client: client, backoffs: backoffs);
    return r.ok ? r.path : null;
  }











  static Future<DownloadResult> fetch(
    String id,
    String url, {
    bool conditional = false,
    http.Client? client,
    List<Duration>? backoffs,
  }) async {
    backoffs ??= _prodBackoffs;
    final now = DateTime.now();
    final prev = await readMeta(id);


    Future<DownloadResult> finish(
      DownloadOutcome outcome, {
      String? etag,
      String? error,
    }) async {
      await _writeMeta(
        id,
        RuleSetMeta(

          lastUpdated: error == null ? now : prev.lastUpdated,
          lastAttempt: now,


          etag: etag ?? prev.etag,
          lastError: error,
        ),
      );
      return DownloadResult(outcome, await cachedPath(id));
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final f = await _file(id);
        final tmp = File('${f.path}.tmp');

        final headers = <String, String>{'User-Agent': 'LxBox'};


        final etag = prev.etag;
        if (conditional && etag != null && etag.isNotEmpty && await f.exists()) {
          headers['If-None-Match'] = etag;
        }

        final resp = await (client != null
                ? client.get(Uri.parse(url), headers: headers)
                : http.get(Uri.parse(url), headers: headers))
            .timeout(_timeout);

        if (resp.statusCode == 304) {
          return await finish(DownloadOutcome.notModified);
        }
        if (resp.statusCode >= 400 && resp.statusCode < 500) {
          return await finish(DownloadOutcome.failed,
              error: 'HTTP ${resp.statusCode}');
        }
        if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
          if (attempt < backoffs.length) {
            await Future<void>.delayed(backoffs[attempt]);
            continue;
          }
          return await finish(DownloadOutcome.failed,
              error: resp.bodyBytes.isEmpty && resp.statusCode == 200
                  ? 'empty body'
                  : 'HTTP ${resp.statusCode}');
        }
        await tmp.writeAsBytes(resp.bodyBytes, flush: true);
        if (await f.exists()) await f.delete();
        await tmp.rename(f.path);
        return await finish(DownloadOutcome.downloaded,
            etag: resp.headers['etag']);
      } catch (e) {
        if (attempt < backoffs.length) {
          await Future<void>.delayed(backoffs[attempt]);
          continue;
        }
        return await finish(DownloadOutcome.failed, error: _shortError(e));
      }
    }
    return await finish(DownloadOutcome.failed, error: 'retries exhausted');
  }


  static String _shortError(Object e) {
    if (e is TimeoutException) return 'timeout';
    if (e is SocketException) return 'network unreachable';
    return e.runtimeType.toString();
  }







  static Future<void> delete(String id) async {
    try {
      final f = await _file(id);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    try {
      final m = await _metaFile(id);
      if (await m.exists()) await m.delete();
    } catch (_) {}
  }












  static String presetCacheId(String presetId, String ruleSetTag) =>
      'preset__${presetId}__$ruleSetTag';

  static Future<String?> cachedPathForPreset(
    String presetId,
    String ruleSetTag,
  ) =>
      cachedPath(presetCacheId(presetId, ruleSetTag));

  static Future<String?> downloadForPreset(
    String presetId,
    String ruleSetTag,
    String url,
  ) =>
      download(presetCacheId(presetId, ruleSetTag), url);


  static Future<DownloadResult> fetchForPreset(
    String presetId,
    String ruleSetTag,
    String url, {
    bool conditional = false,
    http.Client? client,
    List<Duration>? backoffs,
  }) =>
      fetch(presetCacheId(presetId, ruleSetTag), url,
          conditional: conditional, client: client, backoffs: backoffs);


  static Future<RuleSetMeta> readMetaForPreset(
          String presetId, String ruleSetTag) =>
      readMeta(presetCacheId(presetId, ruleSetTag));

  static Future<void> deleteForPreset(String presetId, String ruleSetTag) =>
      delete(presetCacheId(presetId, ruleSetTag));
















  static Future<int> pruneOrphans(Set<String> activeCacheIds) async {
    try {
      final dir = await _dir();
      var pruned = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final String id;
        if (name.endsWith(_metaSuffix)) {
          id = name.substring(0, name.length - _metaSuffix.length);
        } else if (name.endsWith('.srs')) {
          id = name.substring(0, name.length - '.srs'.length);
        } else {
          continue;
        }
        if (activeCacheIds.contains(id)) continue;
        try {
          await entity.delete();
          pruned++;
        } catch (_) {}
      }
      return pruned;
    } catch (_) {
      return 0;
    }
  }
}
