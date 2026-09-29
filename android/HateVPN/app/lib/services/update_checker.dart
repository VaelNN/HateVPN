import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'project_links.dart';
import 'automation/event_emitter.dart';
import 'settings_storage.dart';







class UpdateChecker {
  UpdateChecker._();
  static final UpdateChecker I = UpdateChecker._();



  static const bool _upstreamUpdatesEnabled = false;

  static const _repoApi =
      'https://api.github.com/repos/Leadaxe/LxBox/releases/latest';




  static const _repoFallback =
      'https://raw.githubusercontent.com/Leadaxe/LxBox/main/docs/latest.json';
  static const _userAgent = 'LxBox';
  static const _httpTimeout = Duration(seconds: 10);
  static const _minCheckInterval = Duration(hours: 24);




  final ValueNotifier<UpdateInfo?> latest = ValueNotifier<UpdateInfo?>(null);

  bool _inFlight = false;









  bool _isDevBuild(String version) =>
      version.contains('-dev') || version.startsWith('0.0.0');

  Future<void> hydrate({required String localVersion}) async {
    if (!_upstreamUpdatesEnabled) return;
    if (_isDevBuild(localVersion)) return;
    final tag = await SettingsStorage.getLastKnownVersion();
    if (tag.isEmpty) return;
    final dismissed = await SettingsStorage.getDismissedUpdateVersion();
    if (tag == dismissed) return;
    if (!isNewer(tag, localVersion)) return;
    latest.value = UpdateInfo(
      tag: tag,
      name: tag,
      htmlUrl: ProjectLinks.releaseTag(tag),
      publishedAt: null,
    );
  }






  Future<void> maybeCheck({required String localVersion}) async {
    if (!_upstreamUpdatesEnabled) return;
    if (_inFlight) return;
    if (_isDevBuild(localVersion)) return;
    final enabled = await SettingsStorage.getAutoCheckUpdates();
    if (!enabled) return;
    final last = await SettingsStorage.getLastUpdateCheck();
    if (last != null && DateTime.now().toUtc().difference(last) < _minCheckInterval) {
      return;
    }
    await _check(localVersion: localVersion, source: 'auto');
  }





  Future<UpdateCheckResult> forceCheck({required String localVersion}) async {
    if (!_upstreamUpdatesEnabled) {
      return UpdateCheckResult.skipped('Private HateVPN build');
    }
    if (_inFlight) return UpdateCheckResult.skipped('check already in flight');
    return _check(localVersion: localVersion, source: 'manual');
  }

  Future<UpdateCheckResult> _check({
    required String localVersion,
    required String source,
  }) async {
    _inFlight = true;
    try {

      var info = await _fetchPrimary(source);

      info ??= await _fetchFallback(source);
      if (info == null) {


        return UpdateCheckResult.failed(
            "Couldn't reach GitHub — check network or try later");
      }


      await SettingsStorage.setLastUpdateCheck(DateTime.now().toUtc());
      if (info.tag.isNotEmpty) {
        await SettingsStorage.setLastKnownVersion(info.tag);
      }

      AppLog.I.info(
          'UpdateChecker[$source]: latest=${info.tag} local=$localVersion');

      if (!isNewer(info.tag, localVersion)) {
        latest.value = null;
        return UpdateCheckResult.upToDate(localVersion);
      }

      final dismissed = await SettingsStorage.getDismissedUpdateVersion();
      latest.value = info;

      AutomationEventEmitter.I.emitUpdateAvailable(info.tag, info.htmlUrl);
      return UpdateCheckResult.newer(info, dismissed: dismissed == info.tag);
    } finally {
      _inFlight = false;
    }
  }



  Future<UpdateInfo?> _fetchPrimary(String source) async {
    try {
      final resp = await http
          .get(Uri.parse(_repoApi), headers: {
            'User-Agent': '$_userAgent/${_userAgentSafeVersion()}',
            'Accept': 'application/vnd.github+json',
          })
          .timeout(_httpTimeout);
      if (resp.statusCode != 200) {
        AppLog.I.warning(
            'UpdateChecker[$source]: api.github.com HTTP ${resp.statusCode} — '
            'will try fallback');
        return null;
      }
      final json = jsonDecode(resp.body);
      if (json is! Map<String, dynamic>) {
        AppLog.I.warning('UpdateChecker[$source]: malformed primary JSON');
        return null;
      }
      final tag = (json['tag_name'] as String?) ?? '';
      if (tag.isEmpty) return null;
      final name = (json['name'] as String?) ?? tag;
      final htmlUrl = (json['html_url'] as String?) ??
          ProjectLinks.releaseTag(tag);
      final publishedRaw = json['published_at'] as String?;
      final publishedAt =
          publishedRaw != null ? DateTime.tryParse(publishedRaw) : null;
      return UpdateInfo(
        tag: tag,
        name: name,
        htmlUrl: htmlUrl,
        publishedAt: publishedAt,
      );
    } catch (e) {
      AppLog.I.warning('UpdateChecker[$source]: api.github.com $e');
      return null;
    }
  }




  Future<UpdateInfo?> _fetchFallback(String source) async {
    try {
      final resp = await http
          .get(Uri.parse(_repoFallback), headers: {
            'User-Agent': '$_userAgent/${_userAgentSafeVersion()}',
          })
          .timeout(_httpTimeout);
      if (resp.statusCode != 200) {
        AppLog.I.warning(
            'UpdateChecker[$source]: fallback HTTP ${resp.statusCode}');
        return null;
      }
      final json = jsonDecode(resp.body);
      if (json is! Map<String, dynamic>) {
        AppLog.I.warning('UpdateChecker[$source]: malformed fallback JSON');
        return null;
      }
      final tag = (json['tag'] as String?) ?? '';
      if (tag.isEmpty) return null;
      final name = (json['name'] as String?) ?? tag;
      final htmlUrl = (json['html_url'] as String?) ??
          ProjectLinks.releaseTag(tag);
      final publishedRaw = json['published_at'] as String?;
      final publishedAt =
          publishedRaw != null ? DateTime.tryParse(publishedRaw) : null;
      AppLog.I.info('UpdateChecker[$source]: fallback hit tag=$tag');
      return UpdateInfo(
        tag: tag,
        name: name,
        htmlUrl: htmlUrl,
        publishedAt: publishedAt,
      );
    } catch (e) {
      AppLog.I.warning('UpdateChecker[$source]: fallback $e');
      return null;
    }
  }



  String _userAgentSafeVersion() {
    return '1.x';
  }




  Future<void> dismissCurrent() async {
    final cur = latest.value;
    if (cur == null) return;
    await SettingsStorage.setDismissedUpdateVersion(cur.tag);
    latest.value = null;
  }
}



@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.tag,
    required this.name,
    required this.htmlUrl,
    this.publishedAt,
  });

  final String tag;
  final String name;
  final String htmlUrl;
  final DateTime? publishedAt;
}


@immutable
class UpdateCheckResult {
  const UpdateCheckResult._({
    required this.kind,
    this.info,
    this.localVersion,
    this.message,
    this.dismissed = false,
  });

  factory UpdateCheckResult.newer(UpdateInfo info, {required bool dismissed}) =>
      UpdateCheckResult._(
        kind: UpdateCheckKind.newer,
        info: info,
        dismissed: dismissed,
      );

  factory UpdateCheckResult.upToDate(String local) => UpdateCheckResult._(
        kind: UpdateCheckKind.upToDate,
        localVersion: local,
      );

  factory UpdateCheckResult.failed(String msg) => UpdateCheckResult._(
        kind: UpdateCheckKind.failed,
        message: msg,
      );

  factory UpdateCheckResult.skipped(String msg) => UpdateCheckResult._(
        kind: UpdateCheckKind.skipped,
        message: msg,
      );

  final UpdateCheckKind kind;
  final UpdateInfo? info;
  final String? localVersion;
  final String? message;
  final bool dismissed;
}

enum UpdateCheckKind { newer, upToDate, failed, skipped }








bool isNewer(String remote, String local) {
  final r = _parseSemver(remote);
  final l = _parseSemver(local);
  if (r == null || l == null) return false;
  for (var i = 0; i < 3; i++) {
    final ri = i < r.length ? r[i] : 0;
    final li = i < l.length ? l[i] : 0;
    if (ri > li) return true;
    if (ri < li) return false;
  }
  return false;
}




List<int>? _parseSemver(String raw) {
  if (raw.isEmpty) return null;
  var s = raw.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);

  final cutAt = s.indexOf(RegExp(r'[^0-9.]'));
  if (cutAt >= 0) s = s.substring(0, cutAt);
  if (s.isEmpty) return null;
  final parts = s.split('.');
  if (parts.length < 2 || parts.length > 3) return null;
  final out = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0) return null;
    out.add(n);
  }
  return out;
}
